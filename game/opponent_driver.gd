## The opponent's brain: the reel's human-style driver (DemoDriver) set up for
## a difficulty level, plus what racing needs: awareness of the other car (go
## round a slower or stopped car ahead or lift behind it; hold a line when side
## by side rather than swerving into it) and nitro on the straights. The car is
## the player's car with the same values: the levels differ only in how close
## to the limit it drives, never in what the car can do.
class_name OpponentDriver
extends DemoDriver

## The other car on track (the player's).
var other: Car
## Nitro on the long straights (levels 4 and 5), under the player's tank rules.
var use_nitro: bool = false
## Car-centre lateral limit when going round (units; the road is 1.35 wide each side).
const PASS_LIMIT: float = 1.05
## Wanted gap between the two cars' centres side by side (units; a car is about 0.5 wide).
const SIDE_GAP: float = 0.8
## How far ahead along the track the other car is watched (units + seconds of travel).
const WATCH_BASE: float = 2.5
const WATCH_TIME: float = 0.6
## Straight enough for nitro: max curvature over the next stretch, and its length (s of travel).
const NITRO_MAX_CURVATURE: float = 0.04
const NITRO_LOOK_TIME: float = 1.4

var _bias_target: float = 0.0
var _other_progress: float = -1.0
var _nitro_on: bool = false

## Level -> driving style. Planning numbers are what the driver trusts (u/s^2,
## scaled by the car's grip as for the reel); wobble and the lap spread are its
## mistakes.
const LEVELS: Dictionary = {
	1: {"lateral_accel": 5.4, "brake_accel": 4.0, "steer_grip_share": 0.8, "wobble": 0.12, "lap_speed_range": Vector2(0.9, 1.0), "lap_brake_range": Vector2(0.85, 1.0), "drift_hairpin": false, "use_nitro": false, "roll_jumps": true},
	2: {"lateral_accel": 6.15, "brake_accel": 4.7, "steer_grip_share": 0.85, "wobble": 0.1, "lap_speed_range": Vector2(0.92, 1.0), "lap_brake_range": Vector2(0.88, 1.0), "drift_hairpin": false, "use_nitro": false, "roll_jumps": true},
	3: {"lateral_accel": 7.1, "brake_accel": 5.6, "steer_grip_share": 0.9, "wobble": 0.08, "lap_speed_range": Vector2(0.94, 1.01), "lap_brake_range": Vector2(0.9, 1.03), "drift_hairpin": false, "use_nitro": false},
	4: {"lateral_accel": 9.0, "brake_accel": 7.0, "steer_grip_share": 0.95, "wobble": 0.05, "lap_speed_range": Vector2(0.96, 1.02), "lap_brake_range": Vector2(0.93, 1.03), "drift_hairpin": true, "use_nitro": true},
	5: {"lateral_accel": 12.0, "brake_accel": 10.0, "steer_grip_share": 1.0, "wobble": 0.03, "lap_speed_range": Vector2(0.99, 1.01), "lap_brake_range": Vector2(0.98, 1.01), "drift_hairpin": true, "use_nitro": true},
}


static func make(level: int) -> OpponentDriver:
	var d := OpponentDriver.new()
	d.apply_level(level)
	d.drift_chance_other = 0.0
	return d


## Sets the driving style (before _ready, or later: the speed plan is rebuilt).
func apply_level(level: int) -> void:
	var l: Dictionary = LEVELS[clampi(level, 1, 5)]
	for k: String in l:
		set(k, l[k])
	if is_node_ready():
		_new_lap()


func restart() -> void:
	super.restart()
	_bias_target = 0.0
	lateral_bias = 0.0
	speed_cap = INF
	_other_progress = -1.0
	_nitro_on = false
	car.nitro_input = false


## Released at the start: the pedal goes straight down (a driver floors it on
## reaction rather than easing it in).
func launch() -> void:
	restart()
	_throttle = 1.0
	car.throttle_input = 1.0


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_watch_other()
	lateral_bias = move_toward(lateral_bias, _bias_target, 1.6 * delta)
	super._physics_process(delta)
	_nitro()


## Lateral offset of the racing line itself at s (without the wobble or bias).
func _line_lateral(s: float) -> float:
	var n := _offset.size()
	if n == 0:
		return 0.0
	var f := fposmod(s, track.length) / track.length * n
	var i := int(f) % n
	return lerpf(_offset[i], _offset[(i + 1) % n], f - int(f)) * _lap_amp


func _watch_other() -> void:
	_bias_target = 0.0
	speed_cap = INF
	if other == null or progress < 0.0 or not is_instance_valid(other):
		return
	_other_progress = track.progress(other.global_position, _other_progress)
	var ds := wrapf(_other_progress - progress, -track.length * 0.5, track.length * 0.5)
	var v := maxf(car.forward_speed, 0.0)
	var my_lat := track.lateral_offset(car.global_position, progress)
	var o_lat := track.lateral_offset(other.global_position, _other_progress)
	var line := _line_lateral(progress + maxf(ds, 0.0))
	if absf(ds) < 1.0:
		# Side by side: keep to our side of the other car.
		var side := signf(my_lat - o_lat) if my_lat != o_lat else 1.0
		var keep := o_lat + side * SIDE_GAP
		if side > 0.0 and line < keep or side < 0.0 and line > keep:
			_bias_target = clampf(keep, -PASS_LIMIT, PASS_LIMIT) - line
	elif ds >= 1.0 and ds < WATCH_BASE + WATCH_TIME * v:
		# Ahead and in our way: go round on the side with more room, or lift.
		if absf(line - o_lat) < SIDE_GAP:
			var room_right := PASS_LIMIT - o_lat
			var room_left := o_lat + PASS_LIMIT
			var side := 1.0 if room_right >= room_left else -1.0
			var room := maxf(room_right, room_left)
			_bias_target = clampf(o_lat + side * SIDE_GAP, -PASS_LIMIT, PASS_LIMIT) - line
			var other_v := other.linear_velocity.dot(track.tangent_at(_other_progress))
			if room < SIDE_GAP or ds < 2.0 and v - other_v > 1.0:
				speed_cap = maxf(other_v, 2.0) + (1.5 if room >= SIDE_GAP else 0.0)


func _nitro() -> void:
	if not use_nitro or car.drift_state != Car.Drift.NONE:
		_nitro_on = false
		car.nitro_input = false
		return
	var v := car.forward_speed
	var straight := track.max_curvature(progress, maxf(v, 1.0) * NITRO_LOOK_TIME) < NITRO_MAX_CURVATURE
	var clear := speed_cap == INF and absf(car.slip_angle) < deg_to_rad(4.0) and car.wheels_grounded >= 3
	if _nitro_on:
		_nitro_on = straight and clear and car.nitro_tank > 0.0
	else:
		_nitro_on = straight and clear and v > car.top_speed * 0.55 and car.nitro_tank >= car.nitro_capacity * 0.5
	car.nitro_input = _nitro_on
