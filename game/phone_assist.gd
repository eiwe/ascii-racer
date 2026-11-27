## Phone driving aids (Mobile.active(), touch and tilt steering only): the
## grip-limited lock, the steering assist and the brake assist. Runs every
## physics step after TouchControls and TiltInput and before the car, reads its
## values from the [phone] settings (the pause menu changes them mid-race) and
## hands them to the car (Car.phone_grip_margin, Car.phone_assist_angle) and to
## the automatic throttle (throttle).
##
## While a steering key or a gamepad stick is in use the aids are off: the car
## then steers with today's lock and no assist (the assist fades out).
class_name PhoneAssist
extends Node

## Steering assist: the road's curvature this far ahead (s x speed) feeds the
## wheel (the steering's own lag), plus a heading term that turns the car's
## direction of travel toward the road's at HEADING_RATE (1/s). No pull toward
## the centre line: the player chooses the offset.
const ASSIST_LOOK_TIME: float = 0.12
const CURVATURE_SPAN: float = 0.6 ## u: the curvature is averaged over this much road
const HEADING_RATE: float = 8.0
## The offset the player chose (the car's offset whenever they steer, or when
## the assist fades in) is held gently: the heading aimed for leans toward it
## by HOLD_GAIN rad per unit of offset, at most HOLD_MAX. Hands off, the car
## keeps its line instead of drifting wide through long and banked corners.
const HOLD_GAIN: float = 0.25
const HOLD_MAX: float = 0.12
const ASSIST_MAX_DEG: float = 20.0 ## largest wheel angle the assist adds
## The assist's wheel angle changes at most this fast (rad/s), and its fade
## (off the road, in the air, in a drift, in reverse) at most FADE_RATE per
## second: no snap in the wheel angle.
const ASSIST_RATE: float = 1.5
const FADE_RATE: float = 3.0
const REVERSE_BELOW: float = 1.0 ## u/s: fades out below this forward speed
## Facing the wrong way: the assist fades out as the car's heading error from
## the road grows from WRONG_WAY.x to WRONG_WAY.y degrees (it does not try to
## turn the car round on the road's width), and comes back below it.
const WRONG_WAY: Vector2 = Vector2(45.0, 90.0)
## Brake assist: Autopilot's speed plan, made for the deceleration a lift
## gives (coasting, measured on asphalt at 6..11 u/s) and the cornering it
## plans for (Autopilot's 9 u/s^2 at road grip 1.3). The CORNER SPEED value
## (corner_speed, 1 = this plan) scales the corner speeds it aims for.
const LIFT_DECEL: float = 3.5
const PLAN_LATERAL: float = 9.0
const PLAN_AHEAD: float = 12.0 ## u of road it looks ahead

var game: Node
var car: Car
## True while the aids apply (touch or tilt steering; no key, no stick).
var active: bool = false
## The automatic throttle's strength (1 = flat out; the brake assist lifts it).
var throttle: float = 1.0
## The steering assist's fade (0..1) and the speed plan here (u/s), for tests.
var fade: float = 0.0
var plan_speed: float = 99.0
var _hold: float = 0.0 ## the offset the player chose
## The car's own progress along the circuit (Track.progress, followed from
## step to step): the lap timer's only moves forward, and a car facing the
## wrong way needs the road where it really is.
var _s: float = -1.0
var _track: Track
## The heading gains (defaults HEADING_RATE, HOLD_GAIN); tests may override
## them with -- --assisttune=<rate>,<hold>.
var heading_rate: float = HEADING_RATE
var hold_gain: float = HOLD_GAIN


func _enter_tree() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--assisttune="):
			var v := arg.trim_prefix("--assisttune=").split(",")
			heading_rate = v[0].to_float()
			hold_gain = v[1].to_float()


func _ready() -> void:
	process_physics_priority = -90 # after TouchControls and TiltInput (-100), before the car


func _physics_process(delta: float) -> void:
	if car == null or game == null:
		return
	var au: AudioDirector = game.audio
	var tr: Track = game.track
	if tr != _track:
		_track = tr
		_s = -1.0
	if tr != null:
		_s = tr.progress(car.global_position, _s)
	active = car.player_input and not _keys_or_stick()
	var scheme: String = game.phone_controls()
	var margin := float(au.phone_get("grip_margin", Mobile.GRIP_MARGIN_DEFAULT))
	var on_keys := scheme == "buttons" or scheme == "split"
	if on_keys and not bool(au.phone_get("grip_on_keys", Mobile.GRIP_ON_KEYS_DEFAULT)):
		margin = 0.0
	car.phone_grip_margin = margin if active else 0.0
	# Sensitivity for the scheme in use (tilt and slider).
	if game.touch != null:
		game.touch.slider_sensitivity = float(au.phone_get("sens_slider", Mobile.SENSITIVITY_DEFAULT))
	if game.tilt != null:
		game.tilt.full_lock_deg = TiltInput.FULL_LOCK_DEG / maxf(float(au.phone_get("sens_tilt", Mobile.SENSITIVITY_DEFAULT)), 0.01)
	_update_assist(delta, float(au.phone_get("steer_assist", Mobile.STEER_ASSIST_DEFAULT)))
	_update_brake_assist(bool(au.phone_get("brake_assist", Mobile.BRAKE_ASSIST_DEFAULT)),
		float(au.phone_get("corner_speed", Mobile.CORNER_SPEED_DEFAULT)))


## A steering key or a moved gamepad stick: the player is not steering by touch or tilt.
func _keys_or_stick() -> bool:
	var left: Array[StringName] = [&"steer_left", &"arrow_left"]
	var right: Array[StringName] = [&"steer_right", &"arrow_right"]
	if Car._key_held(left) or Car._key_held(right):
		return true
	return TiltInput._pad_x() != 0.0


func _update_assist(delta: float, strength: float) -> void:
	var tr: Track = game.track
	var target := 0.0
	var on := 1.0
	if strength <= 0.0 or not active or tr == null:
		on = 0.0
	elif car.wheels_grounded == 0 or car.drift_state != Car.Drift.NONE or car.forward_speed < REVERSE_BELOW:
		on = 0.0
	else:
		on = car.wheels_on_road / 4.0
		on *= 1.0 - smoothstep(WRONG_WAY.x, WRONG_WAY.y, rad_to_deg(absf(_heading_error(tr, _s))))
	fade = move_toward(fade, on, FADE_RATE * delta)
	var lat := tr.lateral_offset(car.global_position, _s) if tr != null else 0.0
	if fade <= 0.0 or car.steer_input != 0.0 or car._steer_state != 0.0:
		_hold = lat # the player steers (or the assist is out): their offset is the one to keep
	if fade > 0.0 and tr != null and strength > 0.0:
		var s: float = _s
		var v := maxf(car.forward_speed, 0.0)
		var k := _curvature(tr, s + v * ASSIST_LOOK_TIME)
		var ff := atan(car._wheelbase * k)
		# Heading: the direction of travel against the road's, turned toward it.
		var err := _heading_error(tr, s)
		err += clampf((_hold - lat) * hold_gain, -HOLD_MAX, HOLD_MAX) # lean toward the chosen offset
		var head := err * heading_rate * car._wheelbase / maxf(v, 2.0)
		target = clampf(ff + head, -deg_to_rad(ASSIST_MAX_DEG), deg_to_rad(ASSIST_MAX_DEG)) * strength * fade
	car.phone_assist_angle = move_toward(car.phone_assist_angle, target, ASSIST_RATE * delta)


## The road's direction against the car's direction of travel (its nose when
## slow), radians, + = the road heads to the right.
func _heading_error(tr: Track, s: float) -> float:
	var vel := car.linear_velocity
	vel.y = 0.0
	var dir := vel if vel.length() > 1.0 else -car.global_basis.z
	dir.y = 0.0
	var road := tr.tangent_at(s)
	road.y = 0.0
	return dir.signed_angle_to(road, Vector3.DOWN)


## Mean signed curvature (+ = right) over CURVATURE_SPAN around s.
static func _curvature(tr: Track, s: float) -> float:
	var n := 5
	var k := 0.0
	for i in n:
		k += tr.curvature[tr.index_at(s - CURVATURE_SPAN * 0.5 + CURVATURE_SPAN * i / float(n - 1))]
	return k / n


## Autopilot's speed plan for lifting: the slowest of the corner speeds ahead
## reachable by coasting at LIFT_DECEL.
func speed_plan(tr: Track, s: float, corner_speed: float) -> float:
	var want := 99.0
	var grip := car.grip_road / 1.3 * minf(car.front_grip, car.rear_grip)
	var d := 0.0
	while d < PLAN_AHEAD:
		var k := tr.max_curvature(s + d, 0.5)
		if k > 0.0:
			var vc := sqrt(tr.corner_accel(PLAN_LATERAL * grip, s + d) / k) * corner_speed
			want = minf(want, sqrt(vc * vc + 2.0 * LIFT_DECEL * d))
		d += 0.5
	return want


func _update_brake_assist(on: bool, corner_speed: float) -> void:
	throttle = 1.0
	plan_speed = 99.0
	if not on or game.track == null or not car.player_input:
		return
	plan_speed = speed_plan(game.track, _s, corner_speed)
	var v := car.forward_speed
	throttle = clampf((plan_speed - v) * 2.0, 0.0, 1.0) # lift only: hands-off laps measured +4..6 % on Autopilot, never off the road
