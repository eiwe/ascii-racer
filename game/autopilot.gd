## Simple centre-line follower for testing: pure-pursuit steering toward a point
## ahead on the centre line, and a speed target from the curvature ahead with a
## braking-distance check. Drives the car through its input fields.
class_name Autopilot
extends Node

@export var lateral_accel: float = 9.0 ## cornering limit it plans for (u/s^2), for road grip 1.3
@export var brake_accel: float = 7.0 ## braking it plans for (u/s^2)
@export var max_speed: float = 20.0
@export var line_offset: float = 0.0 ## drive this far right of the centre line
## Take corners tighter than drift_min_curvature with the handbrake drift.
@export var drift_corners: bool = false
@export var drift_min_curvature: float = 0.19
## How far before the corner (along the centre line) the drift starts.
@export var drift_entry_ahead: float = 1.0
## Steering in the drift: base inside amount and gain on the path error (1/rad).
@export var drift_steer_base: float = 0.7
@export var drift_steer_gain: float = 2.0

var car: Car
var track: Track
var progress: float = -1.0
var enabled: bool = true
var drifts_started: int = 0
var _drift_dir: float = 0.0


func _ready() -> void:
	process_physics_priority = -10 # before the car reads its inputs


func _physics_process(_delta: float) -> void:
	if not enabled or car == null:
		return
	car.player_input = false
	var pos := car.global_position
	progress = track.progress(pos, progress)
	var v := car.forward_speed

	var look := 0.9 + 0.22 * maxf(v, 0.0)
	var target := track.point_at(progress + look)
	var t := track.tangent_at(progress + look)
	target += t.cross(Vector3.UP) * line_offset
	var to := target - pos
	to.y = 0.0
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	var err := fwd.signed_angle_to(to, Vector3.DOWN) # + = target to the right
	var lock := deg_to_rad(lerpf(car.max_steer_low_deg, car.max_steer_high_deg, clampf(v / car.top_speed, 0.0, 1.0)))
	car.steer_input = clampf(err / lock * 1.3, -1.0, 1.0)

	var want := max_speed
	# Planned grip relative to the original car's (road grip 1.3), like DemoDriver.
	var grip := car.grip_road / 1.3 * minf(car.front_grip, car.rear_grip)
	var d := 0.0
	while d < 10.0:
		var k := track.max_curvature(progress + d, 0.5)
		if k > 0.0:
			var vc := sqrt(lateral_accel * grip / k)
			want = minf(want, sqrt(vc * vc + 2.0 * brake_accel * d))
		d += 0.5
	car.throttle_input = clampf((want - v) * 2.0, 0.0, 1.0)
	car.brake_input = clampf((v - want - 0.2) * 1.5, 0.0, 1.0)
	car.handbrake_input = false
	if drift_corners:
		_drift(pos, v)


## Handbrake drift through tight corners: start on the way in, steer the arc
## from the direction of travel (the body is angled), let go when it ends.
func _drift(pos: Vector3, v: float) -> void:
	var k_in := _mean_curvature(progress + drift_entry_ahead - 0.3, 0.6)
	var corner := absf(k_in) >= drift_min_curvature
	if car.drift_state == Car.Drift.NONE:
		_drift_dir = 0.0
		if corner and v > car.drift_min_speed + 0.5 and car.wheels_on_road >= 3:
			_drift_dir = signf(k_in)
			car.handbrake_input = true
			car.steer_input = _drift_dir
			drifts_started += 1
		return
	if car.drift_state != Car.Drift.DRIFT:
		return
	# Still in the same corner: keep the handbrake and steer the arc.
	var k_mid := _mean_curvature(progress, 0.6)
	if signf(k_mid) == _drift_dir and absf(k_mid) >= drift_min_curvature * 0.75:
		var look := 0.8 + 0.15 * v
		var to := track.point_at(progress + look) - pos
		to.y = 0.0
		var vel := car.linear_velocity
		vel.y = 0.0
		var err := vel.signed_angle_to(to, Vector3.DOWN) # + = target right of the path
		car.handbrake_input = true
		car.steer_input = _drift_dir * clampf(drift_steer_base + err * _drift_dir * drift_steer_gain, -0.4, 1.0)
		var want := sqrt(car.drift_grip * Car.G * 0.8 / maxf(absf(k_mid), 0.1))
		car.throttle_input = clampf((want - v) * 2.0, 0.0, 1.0)
		car.brake_input = clampf((v - want - 0.3) * 1.0, 0.0, 1.0)
	else:
		car.handbrake_input = false
		car.steer_input = 0.0 # let go: the drift ends and straightens


## Mean signed curvature over [s, s + span] (smooths the joints between arcs).
func _mean_curvature(s: float, span: float) -> float:
	var n := maxi(int(span / Track.SAMPLE_STEP), 1)
	var i0 := track.index_at(s)
	var sum := 0.0
	for k in n:
		sum += track.curvature[(i0 + k) % track.curvature.size()]
	return sum / n
