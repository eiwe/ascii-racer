## Gamepad vibration from the car: a light buzz for tyres sliding (scaled by how
## far past the grip limit they are), a rumble for running off the road, and a
## thump for impacts (scaled by the sudden change of velocity). Vibrates the pad
## that was used last. Always stopped when the car is (nearly) still, when
## disabled and when the node leaves the tree (quit).
class_name PadRumble
extends Node

## Overall strength, 0 = off.
@export_range(0.0, 1.0, 0.05) var strength: float = 0.5
## Weak (high-frequency) motor at full slide; grip usage this far past 1 counts as full.
@export_range(0.0, 1.0, 0.05) var slide_weak: float = 0.45
@export_range(0.1, 3.0, 0.05) var slide_full_excess: float = 1.0
## Off-road rumble, both motors, at full off-road running speed.
@export_range(0.0, 1.0, 0.05) var offroad_weak: float = 0.25
@export_range(0.0, 1.0, 0.05) var offroad_strong: float = 0.2
## Impact: velocity change in one step beyond what tyres and brakes can do
## (u/s) that gives a full-strength thump, and how fast the thump decays (1/s).
@export_range(0.1, 10.0, 0.1) var impact_full_dv: float = 3.0
@export_range(1.0, 30.0, 0.5) var impact_decay: float = 9.0

var car: Car
var enabled: bool = true
## Device being vibrated (last joypad that sent an event, or the first connected).
var device: int = -1
## Read-outs for the HUD and tests.
var weak: float = 0.0
var strong: float = 0.0
var start_calls: int = 0
var stop_calls: int = 0
var running: bool = false

var _impact: float = 0.0
var _prev_v: Vector3 = Vector3.ZERO
var _prev_p: Vector3 = Vector3.ZERO
var _sent: Vector2 = Vector2(-1.0, -1.0)
var _refresh: float = 0.0


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		device = pads[0]


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.device != device and event.device >= 0 and Input.get_connected_joypads().has(event.device):
			stop()
			device = event.device


## Hotplug: pick up a new pad when there is none; on losing ours, switch to
## another connected pad or none (-1, no vibration calls).
func _on_joy_connection_changed(dev: int, connected: bool, pads: Array[int] = Input.get_connected_joypads()) -> void:
	if connected and device < 0:
		device = dev
	elif not connected and dev == device:
		running = false
		_sent = Vector2(-1.0, -1.0)
		pads = pads.filter(func(d: int) -> bool: return d != dev)
		device = pads[0] if not pads.is_empty() else -1


func _physics_process(delta: float) -> void:
	if car == null:
		return
	var v := car.linear_velocity
	var p := car.global_position
	# Velocity change beyond what the tyres and brakes alone can produce (not
	# counting resets: a teleport jumps the position).
	var dv := (v - _prev_v).length() - 20.0 * delta
	if p.distance_to(_prev_p) > (v.length() + _prev_v.length()) * delta + 0.2:
		dv = 0.0
	_prev_v = v
	_prev_p = p
	_impact = maxf(_impact * exp(-impact_decay * delta), clampf(dv / impact_full_dv, 0.0, 1.0))
	var speed := v.length()
	var slide := 0.0
	var off := 0.0
	if speed > 0.5 and car.wheels_grounded > 0:
		var excess := 0.0
		for u in car.wheel_usage:
			excess = maxf(excess, u - 1.0)
		slide = clampf(excess / slide_full_excess, 0.0, 1.0) * clampf(speed / 2.0, 0.0, 1.0)
		off = float(car.wheels_grounded - car.wheels_on_road) / 4.0 * clampf(speed / 3.0, 0.0, 1.0)
	weak = clampf(slide * slide_weak + off * offroad_weak + _impact * 0.3, 0.0, 1.0) * strength
	strong = clampf(off * offroad_strong + _impact, 0.0, 1.0) * strength
	if not enabled or device < 0 or speed < 0.2 and _impact < 0.05 or weak + strong < 0.02:
		weak = 0.0
		strong = 0.0
		stop()
		return
	# Re-send when it changes noticeably, and at least every 0.1 s with a short
	# duration, so a missed stop can never leave the motors running.
	_refresh -= delta
	if absf(weak - _sent.x) > 0.03 or absf(strong - _sent.y) > 0.03 or _refresh <= 0.0:
		Input.start_joy_vibration(device, weak, strong, 0.25)
		start_calls += 1
		running = true
		_sent = Vector2(weak, strong)
		_refresh = 0.1


func stop() -> void:
	if running and device >= 0:
		Input.stop_joy_vibration(device)
		stop_calls += 1
	running = false
	_sent = Vector2(-1.0, -1.0)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		stop()


func _exit_tree() -> void:
	stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()
