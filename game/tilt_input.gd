## Tilt steering (phone only): the phone's roll in landscape steers the car.
## Gravity (Input.get_gravity(), screen axes: x right, y up, z toward the
## viewer; it points at the ground, (0, -9.8, 0) held upright) is low-passed,
## the roll is read from it and faded out as the phone lies flat, then shaped
## (dead zone, full lock at FULL_LOCK_DEG, a gentle curve). Positive roll =
## right side down = steer right; `flip` inverts it (the axis conventions are
## from Godot's source, not confirmed on a device).
##
## The value goes into the steer_left / steer_right actions as an analogue
## strength, so the car takes it through its stick path (stick_steer_speed, no
## key smoothing). The car's stick curve (stick_steer_exponent) is undone here
## so the wheel follows sign * amount^EXPONENT.
##
## On the desktop (`--mobile`) the pointer's x position, or the left stick
## when it is moved, stands in for the roll (+-SIM_RANGE_DEG) and goes through
## the same filter and shaping. On a phone a moved gamepad stick wins over tilt.
class_name TiltInput
extends Node

const DEAD_ZONE_DEG: float = 1.5
const FULL_LOCK_DEG: float = 30.0
const EXPONENT: float = 1.2
## Low-pass rate (1/s) of the gravity vector.
const FILTER_RATE: float = 18.0
## Roll fades out between these lengths of gravity in the screen plane (m/s^2):
## a phone lying flat has none there.
const UPRIGHT_FADE: Vector2 = Vector2(1.0, 3.5)
const SIM_RANGE_DEG: float = 40.0
## Low-pass rate (1/s) of the display roll's gravity vector. A hand trajectory
## (0 to 25 deg in 0.25 s, a 2 Hz +-10 deg slalom, 0.2 deg rms sensor noise at
## 100 Hz, 40 ms display latency) gave the lowest moving horizon error with
## stationary jitter under 0.15 deg rms at 75/s without a prediction lead.
const DISPLAY_RATE: float = 75.0
const PAD_DEADZONE: float = 0.15

var car: Car
## Steers only while true (Game sets it while the player drives).
var enabled: bool = false
## Inverts the roll (the pause menu's FLIP STEERING, saved).
var flip: bool = false
## The filtered roll, radians, positive = right side down (after `flip`). The
## level display (a later phase) turns the picture by this.
var roll: float = 0.0
## The shaped steering, -1..1 (what the wheel follows).
var steer: float = 0.0
## The roll for the level display (radians, positive = right side down, after
## `flip`): its own faster low-pass (DISPLAY_RATE, chosen by simulation; the
## accelerometer fallback keeps FILTER_RATE), no dead zone, the same flat-phone fade.
var display_roll: float = 0.0
## Where the roll came from: "sensor", "accelerometer", "none", "pad", "pointer", "test".
var source: String = ""
## Tests: a roll in degrees to feed instead of the sensor or pointer (NAN = off).
var test_roll_deg: float = NAN

var _g := Vector3(0.0, -9.8, 0.0)
var _gd := Vector3(0.0, -9.8, 0.0)
var _holding: bool = false


func _ready() -> void:
	process_physics_priority = -100 # before the car reads its inputs


func _physics_process(delta: float) -> void:
	var raw := _gravity()
	_g = _g.lerp(raw, 1.0 - exp(-FILTER_RATE * delta))
	var upright := Vector2(_g.x, _g.y).length()
	var r := atan2(_g.x, -_g.y) * smoothstep(UPRIGHT_FADE.x, UPRIGHT_FADE.y, upright)
	roll = -r if flip else r
	steer = shape(roll)
	var rate := FILTER_RATE if source == "accelerometer" else DISPLAY_RATE
	_gd = _gd.lerp(raw, 1.0 - exp(-rate * delta))
	var rd := atan2(_gd.x, -_gd.y) * smoothstep(UPRIGHT_FADE.x, UPRIGHT_FADE.y, Vector2(_gd.x, _gd.y).length())
	display_roll = -rd if flip else rd
	_apply()


## Steering for a roll (radians): zero inside the dead zone, full at FULL_LOCK_DEG.
static func shape(r: float) -> float:
	var a := clampf((absf(rad_to_deg(r)) - DEAD_ZONE_DEG) / (FULL_LOCK_DEG - DEAD_ZONE_DEG), 0.0, 1.0)
	return signf(r) * pow(a, EXPONENT)


## Gravity in screen axes, from the source in use.
func _gravity() -> Vector3:
	if not is_nan(test_roll_deg):
		source = "test"
		return _from_roll(deg_to_rad(test_roll_deg))
	if Mobile.device():
		var g := Input.get_gravity()
		source = "sensor"
		if g.length() < 1.0:
			g = Input.get_accelerometer()
			source = "accelerometer"
		if g.length() < 1.0:
			source = "none"
			return Vector3(0.0, -9.8, 0.0)
		return g
	var stick := _pad_x()
	if stick != 0.0:
		source = "pad"
		return _from_roll(deg_to_rad(stick * SIM_RANGE_DEG))
	source = "pointer"
	var vp := get_viewport()
	var w := vp.get_visible_rect().size.x
	var u := clampf(vp.get_mouse_position().x / maxf(w, 1.0), 0.0, 1.0)
	return _from_roll(deg_to_rad((u * 2.0 - 1.0) * SIM_RANGE_DEG))


static func _from_roll(r: float) -> Vector3:
	return Vector3(sin(r), -cos(r), 0.0) * 9.8


## The left stick's x on any connected pad, 0 inside its dead zone.
static func _pad_x() -> float:
	for d in Input.get_connected_joypads():
		var x := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		if absf(x) > PAD_DEADZONE:
			return x
	return 0.0


## Writes the steering into the actions (or lets go of them).
func _apply() -> void:
	var on := enabled and car != null and car.player_input
	# On a phone a moved stick takes over (its own events set the actions).
	if Mobile.device() and _pad_x() != 0.0:
		on = false
	if not on or steer == 0.0:
		_release()
		return
	var v := pow(absf(steer), 1.0 / maxf(car.stick_steer_exponent, 0.01))
	if steer > 0.0:
		Input.action_release(&"steer_left")
		Input.action_press(&"steer_right", v)
	else:
		Input.action_release(&"steer_right")
		Input.action_press(&"steer_left", v)
	_holding = true


func _release() -> void:
	if _holding:
		Input.action_release(&"steer_left")
		Input.action_release(&"steer_right")
		_holding = false
