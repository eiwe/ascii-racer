## Drives the car for the demo reel the way a person would: a racing line
## (out-in-out, using the road width and kerbs), steering that moves like a
## thumb on a stick, braking and lifting into corners and feeding the throttle
## out, the handbrake drift through the tight corners, flat out over the jump,
## and small lap-to-lap variation. Recovers from mistakes by itself (reversing
## out of a jam), with a quiet reset as the last resort.
##
## The racing line is the centre line relaxed like an elastic band inside the
## road (each point pulled toward the midpoint of its neighbours, clamped to
## the usable width), which gives the out-in-out shape. A speed profile from
## its curvature, with braking passes, sets the target speed.
class_name DemoDriver
extends Node

## Steering gain and pure-pursuit look-ahead (units + seconds of travel).
var steer_gain: float = 1.3
var look_base: float = 1.0
var look_time: float = 0.22

## Asks the owner for a quiet reset (the car is stuck, upside down or lost).
signal reset_requested

## Line points every LINE_STEP along the centre line.
const LINE_STEP: float = 0.5
const RELAX_ITERATIONS: int = 600
## Usable half width for the car's centre: flat road (wheels may touch the
## kerb), raised road (walls), and the jump (kept straight and central).
var width_flat: float = 1.0
var width_raised: float = 0.85
const WIDTH_JUMP: float = 0.25
## Planning: cornering and braking it trusts (u/s^2), scaled by the car's grip.
var lateral_accel: float = 9.5
var brake_accel: float = 7.0
## Thumb: how fast the stick moves (full lock per second) and its smoothing (s).
var stick_rate: float = 8.0
var stick_smooth: float = 0.03
## Pedals: rise and fall rates (per second).
var throttle_up: float = 2.5
var throttle_down: float = 7.0
var brake_up: float = 6.0
var brake_down: float = 5.0
## Corners tighter than this (1/radius) and long enough are taken with the
## handbrake drift; the hairpin always, others sometimes.
const DRIFT_CURVATURE: float = 0.18
var drift_chance_other: float = 0.4
## Whether the hairpin is taken with the handbrake drift.
var drift_hairpin: bool = true
## Hand steadiness: amplitude of the line's wobble (units), and the lap-to-lap
## spread of corner speed and braking (multipliers, min..max).
var wobble: float = 0.06
var lap_speed_range: Vector2 = Vector2(0.95, 1.03)
var lap_brake_range: Vector2 = Vector2(0.9, 1.05)
## Set every step by a subclass (OpponentDriver): a lateral shift of the line
## (units, + = right) and a cap on the target speed (u/s), e.g. to go round or
## follow another car.
var lateral_bias: float = 0.0
var speed_cap: float = INF
## In a drift: stick toward the inside, plus this much per radian of path error.
var drift_inside: float = 0.0
var drift_gain: float = 4.0
## Flat out from here to here (the jump), as s along the lap.
## Flat out over the jumps: from the track's jump data (Track.flat_out_ranges;
## track 1: 19 to 33.5).
var _flat_out: Array[Vector2] = []
## Body slip beyond which an unplanned slide is caught.
const SLIDE_CATCH_DEG: float = 8.0
## Steering is capped at the angle that asks the tyres for this share of their
## grip at the current speed (a driver does not crank full lock at speed).
var steer_grip_share: float = 0.95
## Wheelbase used for that cap (the kit car's axles are 0.5 apart).
const WHEELBASE: float = 0.5

var car: Car
var track: Track
## Fixed seed for the lap-to-lap variation (0 = random each run).
var rng_seed: int = 0
## Read-outs.
var resets: int = 0
var drifts: int = 0
var progress: float = -1.0

var _offset: PackedFloat32Array = PackedFloat32Array() ## lateral offset of the line per point
var _speed: PackedFloat32Array = PackedFloat32Array() ## target speed per point
var _corners: Array = [] ## [entry s, exit s, direction, is hairpin]
var _lap_amp: float = 1.0
var _lap_speed: float = 1.0
var _lap_brake: float = 1.0
var _wobble_phase: float = 0.0
var _rng := RandomNumberGenerator.new()
var _stick: float = 0.0
var _stick_out: float = 0.0
var _throttle: float = 0.0
var _brake: float = 0.0
var _last_s: float = 0.0
var _time: float = 0.0
## Drift through a corner: index into _corners, or -1.
var _drift_corner: int = -1
var _drift_tap: float = 0.0
var _drift_plan: Array[bool] = []
## Recovery.
var _stuck: float = 0.0
var _reverse: float = 0.0
var _trouble: float = 0.0
var _check_s: float = 0.0 ## progress a few seconds ago (no progress = jammed)
var _check_t: float = 0.0


func _ready() -> void:
	process_physics_priority = -10 # before the car reads its inputs
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_flat_out = track.flat_out_ranges()
	_build_line()
	_find_corners()
	_new_lap()


func _points() -> int:
	return int(round(track.length / LINE_STEP))


func _in_flat_out(s: float, margin: float) -> bool:
	for r in _flat_out:
		if s >= r.x - margin and s <= r.y + margin:
			return true
	return false


func _width_at(s: float) -> float:
	if _in_flat_out(s, 1.0):
		return WIDTH_JUMP
	# Narrow a little before a raised stretch (walls) starts, not at it.
	for ahead: float in [0.0, 1.5, 3.0]:
		if track.structure_at(s + ahead) != 0:
			return width_raised
	return width_flat


func _build_line() -> void:
	var n := _points()
	var ds := track.length / n
	var base := PackedVector2Array()
	var right := PackedVector2Array()
	var width := PackedFloat32Array()
	for i in n:
		var p := track.point_at(i * ds)
		var t := track.tangent_at(i * ds)
		base.append(Vector2(p.x, p.z))
		right.append(Vector2(-t.z, t.x).normalized())
		width.append(_width_at(i * ds))
	_offset.resize(n)
	_offset.fill(0.0)
	for it in RELAX_ITERATIONS:
		for i in n:
			var a := base[(i - 1 + n) % n] + right[(i - 1 + n) % n] * _offset[(i - 1 + n) % n]
			var b := base[(i + 1) % n] + right[(i + 1) % n] * _offset[(i + 1) % n]
			var q := base[i] + right[i] * _offset[i]
			var o := _offset[i] + 0.5 * ((a + b) * 0.5 - q).dot(right[i])
			_offset[i] = clampf(o, -width[i], width[i])


## Corners worth naming: runs of curvature above DRIFT_CURVATURE.
func _find_corners() -> void:
	_corners.clear()
	var n := track.curvature.size()
	var ds := track.length / n
	var i := 0
	while i < n:
		var k := track.curvature[i]
		if absf(k) < DRIFT_CURVATURE:
			i += 1
			continue
		var j := i
		var turn := 0.0
		while j < n and signf(track.curvature[j]) == signf(k) and absf(track.curvature[j]) >= DRIFT_CURVATURE:
			turn += absf(track.curvature[j]) * ds
			j += 1
		_corners.append([i * ds, j * ds, signf(k), turn > deg_to_rad(150.0)])
		i = j


## Fresh variation for the coming lap, and the speed profile that goes with it.
func _new_lap() -> void:
	_lap_amp = _rng.randf_range(0.82, 1.0)
	_lap_speed = _rng.randf_range(lap_speed_range.x, lap_speed_range.y)
	_lap_brake = _rng.randf_range(lap_brake_range.x, lap_brake_range.y)
	_wobble_phase = _rng.randf() * TAU
	_drift_plan.clear()
	for c: Array in _corners:
		_drift_plan.append(c[3] and drift_hairpin or _rng.randf() < drift_chance_other)
	_build_speed()


func _line_point(s: float) -> Vector3:
	var n := _offset.size()
	var f := fposmod(s, track.length) / track.length * n
	var i := int(f) % n
	var o := lerpf(_offset[i], _offset[(i + 1) % n], f - int(f)) * _lap_amp
	o += wobble * sin(s * 0.21 + _wobble_phase) # a hand is never perfectly steady
	o += lateral_bias
	var t := track.tangent_at(s)
	return track.point_at(s) + Vector3(-t.z, 0.0, t.x).normalized() * o


func _build_speed() -> void:
	var n := _offset.size()
	var ds := track.length / n
	var pts := PackedVector3Array()
	for i in n:
		pts.append(_line_point(i * ds))
	var grip := car.grip_road / 1.3 * minf(car.front_grip, car.rear_grip)
	var a_lat := lateral_accel * grip * _lap_speed
	_speed.resize(n)
	for i in n:
		var a := pts[(i - 1 + n) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		var k := _curvature(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
		_speed[i] = minf(20.0, sqrt(_corner_accel(a_lat, i * ds) / maxf(k, 1e-4)))
	var decel := brake_accel * _lap_brake * grip
	for pass_i in 2:
		for j in range(n - 1, -1, -1):
			var nxt := _speed[(j + 1) % n]
			_speed[j] = minf(_speed[j], sqrt(nxt * nxt + 2.0 * decel * ds))


## Cornering acceleration the plan allows at s (Track.corner_accel).
func _corner_accel(a_lat: float, s: float) -> float:
	return track.corner_accel(a_lat, s)


static func _curvature(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area2 := absf((b - a).cross(c - a))
	return 2.0 * area2 / maxf(ab * bc * ca, 1e-6)


func _speed_at(s: float) -> float:
	var n := _speed.size()
	return _speed[int(fposmod(s, track.length) / track.length * n) % n]


func _physics_process(delta: float) -> void:
	if car == null:
		return
	car.player_input = false
	_time += delta
	var pos := car.global_position
	progress = track.progress(pos, progress)
	if progress < _last_s - track.length * 0.5:
		_new_lap()
	_last_s = progress
	var v := car.forward_speed
	var fwd := -car.global_basis.z
	fwd.y = 0.0

	# Trouble: stuck, off the road far away, facing the wrong way, upside down.
	var tangent := track.tangent_at(progress)
	var wrong_way := fwd.normalized().dot(Vector3(tangent.x, 0.0, tangent.z).normalized()) < -0.2
	var lost := absf(track.lateral_offset(pos, progress)) > 5.0
	if not car.is_upright() or wrong_way or lost:
		_trouble += delta
	else:
		_trouble = maxf(_trouble - delta, 0.0)
	# No progress along the lap for a while (jammed against something, or
	# reversing out has not worked): a quiet reset.
	_check_t += delta
	if _check_t > 6.0:
		if fposmod(progress - _check_s, track.length) < 3.0:
			_trouble = 3.0
		_check_s = progress
		_check_t = 0.0
	if _trouble > 2.5:
		_trouble = 0.0
		_check_t = 0.0
		resets += 1
		reset_requested.emit()
	if _reverse > 0.0:
		_reverse -= delta
		_apply(-_stick_out, 0.0, 1.0, false, delta) # brake at a standstill = reverse
		return
	if absf(v) < 0.4 and _throttle > 0.6:
		_stuck += delta
		if _stuck > 1.2:
			_stuck = 0.0
			_reverse = 0.9
	else:
		_stuck = 0.0

	# Steering: pure pursuit on the racing line.
	var look := look_base + look_time * maxf(v, 0.0)
	var to := _line_point(progress + look) - pos
	to.y = 0.0
	var err := fwd.signed_angle_to(to, Vector3.DOWN)
	var lock := maxf(car.steer_lock, deg_to_rad(4.0))
	var steer := clampf(err / lock * steer_gain, -1.0, 1.0)
	if v > 1.0:
		var a_max := car.grip_road * Car.G * minf(car.front_grip, car.rear_grip) * steer_grip_share
		var cap := atan(WHEELBASE * a_max / (v * v)) / lock
		steer = clampf(steer, -cap, cap)

	# Speed: aim for the profile a little ahead (reaction time).
	var want := minf(_speed_at(progress + maxf(v, 0.0) * 0.3), speed_cap)
	var thr := clampf((want - v) * 1.6 + 0.15, 0.0, 1.0)
	var brk := clampf((v - want - 0.25) * 0.9, 0.0, 1.0)
	if lost:
		want = 3.0
		thr = clampf((want - v) * 1.5, 0.0, 0.7)
	var flat := _in_flat_out(progress, 0.0)
	if flat:
		thr = 1.0
		brk = 0.0

	# Handbrake drift through the chosen corners.
	var hb := false
	var c := _corner_ahead(progress)
	if _drift_corner >= 0:
		var cc: Array = _corners[_drift_corner]
		var into := wrapf(progress - cc[0], -track.length * 0.5, track.length * 0.5)
		if into > (cc[1] - cc[0]) - 2.5 or car.drift_state == Car.Drift.NONE and _drift_tap <= 0.0:
			_drift_corner = -1 # let go: the car straightens itself
		else:
			var dir: float = cc[2]
			_drift_tap -= delta
			hb = true # held through the corner; the stick shapes the arc
			# Inside amount from the path error, as a driver balances it.
			var vel := car.linear_velocity
			vel.y = 0.0
			var perr := vel.signed_angle_to(to, Vector3.DOWN)
			steer = dir * clampf(drift_inside + perr * dir * drift_gain, -0.4, 1.0)
			if car.drift_state == Car.Drift.NONE and _drift_tap > 0.0:
				# Kicking it in: enough lock for the car to start the drift.
				steer = dir * maxf(absf(steer), 0.5)
			thr = clampf(0.85 - car.drift_angle * 0.6, 0.4, 1.0)
			brk = 0.0
	elif absf(car.slip_angle) > deg_to_rad(SLIDE_CATCH_DEG) and v > 1.5:
		# An unplanned slide (power oversteer, a kerb): counter-steer and ease off.
		steer = clampf(steer + car.slip_angle / deg_to_rad(12.0), -1.0, 1.0)
		thr *= 0.2
	if _drift_corner < 0 and c >= 0 and _drift_plan[c] and v > car.drift_min_speed + 1.0:
		var cc: Array = _corners[c]
		var to_entry := fposmod(cc[0] - progress, track.length)
		if to_entry < 0.6 + v * 0.08:
			_drift_corner = c
			_drift_tap = 0.22
			drifts += 1
			steer = cc[2]
			hb = true
	_apply(steer, thr, brk, hb, delta)


## The corner whose entry is just ahead (within a few units), or -1.
func _corner_ahead(s: float) -> int:
	for i in _corners.size():
		var d := fposmod(_corners[i][0] - s, track.length)
		if d < 4.0:
			return i
	return -1


## Moves the stick and pedals toward what the driver wants, at human rates.
func _apply(steer: float, thr: float, brk: float, hb: bool, delta: float) -> void:
	_stick = move_toward(_stick, steer, stick_rate * delta)
	_stick_out = lerpf(_stick_out, _stick, 1.0 - exp(-delta / stick_smooth))
	_throttle = move_toward(_throttle, thr, (throttle_up if thr > _throttle else throttle_down) * delta)
	_brake = move_toward(_brake, brk, (brake_up if brk > _brake else brake_down) * delta)
	car.steer_input = _stick_out
	car.throttle_input = _throttle
	car.brake_input = _brake
	car.handbrake_input = hb


## After a reset or a start: forget the history.
func restart() -> void:
	progress = -1.0
	_stuck = 0.0
	_reverse = 0.0
	_trouble = 0.0
	_drift_corner = -1
	_check_t = 0.0
	_check_s = progress
	_stick = 0.0
	_stick_out = 0.0
	_throttle = 0.0
	_brake = 0.0
