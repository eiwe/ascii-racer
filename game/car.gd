## The Toy Racer: a RigidBody3D on four raycast wheels with custom forces.
##
## Per wheel and physics step: a ray from the top of the wheel's travel finds the
## ground; a spring + damper along the car's up axis holds the body up; the tyre
## gets a longitudinal force (drive on the rear pair, brakes, rolling drag) and
## a lateral force from its slip angle, and the two are clamped together to the
## grip limit (friction circle), so asking for more than the tyre has makes it
## slide. Forces act at the contact patch; the centre of mass sits almost on the
## ground so the car leans on its springs but does not roll over.
##
## Speed is in world units per second; the car is 0.875 long.
class_name Car
extends RigidBody3D

const WHEEL_NAMES: PackedStringArray = ["wheel-fl", "wheel-fr", "wheel-bl", "wheel-br"]
const G: float = 9.8
enum Drift { NONE, DRIFT, EXIT }
const DRIFT_BOOST_MIN_TIME: float = 0.4
## Share of handbrake_decel kept during a low-speed handbrake pivot.
const DRIFT_PIVOT_BRAKE: float = 0.25
## Yaw torque gain toward the wanted yaw rate (1/s) and its cap (rad/s^2).
const DRIFT_YAW_GAIN: float = 25.0
const DRIFT_YAW_ACCEL_MAX: float = 120.0
## Blend time from tyre forces to drift forces on entry (s).
const DRIFT_BLEND_TIME: float = 0.06
## Exit: the drift forces hand back to the tyres as the body angle falls below
## this, and the exit ends below DRIFT_EXIT_DONE_DEG (or after DRIFT_EXIT_MAX_TIME).
const DRIFT_EXIT_BLEND_DEG: float = 10.0
const DRIFT_EXIT_DONE_DEG: float = 2.0
const DRIFT_EXIT_MAX_TIME: float = 0.7
## Tank (seconds) needed to start a burn: holding the button on an empty tank
## does not stutter on the trickle.
const NITRO_MIN_START: float = 0.15

@export_group("Chassis")
## Centre of mass height above the ground contact plane. Low = cannot roll over.
@export_range(0.0, 0.3, 0.005) var com_height: float = 0.05
## Moments of inertia (pitch, yaw, roll) for mass 1; scaled by mass.
@export var inertia_per_mass: Vector3 = Vector3(0.07, 0.12, 0.035)

@export_group("Suspension")
@export_range(0.05, 0.3, 0.005) var wheel_radius: float = 0.125
## How far each wheel can move up from its resting position.
@export_range(0.0, 0.2, 0.005) var travel_up: float = 0.05
## How far each wheel can hang below its resting position.
@export_range(0.0, 0.2, 0.005) var travel_down: float = 0.07
## Natural frequency of each corner's spring.
@export_range(0.5, 10.0, 0.1) var spring_hz: float = 3.2
@export_range(0.0, 2.0, 0.05) var damping_ratio: float = 0.6
## Cap on one wheel's suspension force, in units of that corner's static load.
@export_range(1.0, 10.0, 0.1) var max_suspension_load: float = 5.0

@export_group("Air")
## With no wheel on the ground: damping of pitch and roll rate (1/s) and a
## gentle pull toward level (1/s^2), so jumps do not tumble the car. Yaw is free.
@export_range(0.0, 20.0, 0.5) var air_damping: float = 3.0
@export_range(0.0, 50.0, 0.5) var air_level: float = 6.0
## A drift survives this long in the air (crests, the jump).
@export_range(0.0, 2.0, 0.05) var drift_air_time: float = 0.6

@export_group("Engine and brakes")
## Speed at which the drive force reaches zero. Rolling drag makes the real top
## speed on the road a little lower (13.0 here gives about 11.6).
@export_range(1.0, 20.0, 0.1) var top_speed: float = 13.0
## Acceleration from standstill (falls off as (1 - (v / top_speed)^2)).
@export_range(0.5, 30.0, 0.1) var launch_accel: float = 10.0
@export_range(0.5, 10.0, 0.1) var reverse_speed: float = 3.0
@export_range(0.5, 30.0, 0.1) var reverse_accel: float = 5.0
## Deceleration asked of the brakes at full pedal (grip-limited).
@export_range(1.0, 40.0, 0.5) var brake_decel: float = 12.0
## Share of brake force on the front axle.
@export_range(0.0, 1.0, 0.05) var brake_front_bias: float = 0.6
## Rear-wheel deceleration with the throttle released (and no brake): shifts
## weight forward on lift-off, so lifting mid-corner tucks the nose in. 0 = coast.
@export_range(0.0, 10.0, 0.25) var engine_braking: float = 2.1
## Constant rolling drag while coasting.
@export_range(0.0, 5.0, 0.05) var rolling_decel: float = 0.8
## Extra speed-proportional drag per wheel off the road (1/s). Sets off-road top speed.
@export_range(0.0, 5.0, 0.05) var offroad_drag: float = 1.1

@export_group("Steering")
## Front wheel angle at full lock, standing still.
@export_range(5.0, 45.0, 0.5) var max_steer_low_deg: float = 25.0
## Front wheel angle at full lock, at top speed.
@export_range(1.0, 45.0, 0.5) var max_steer_high_deg: float = 7.0
## Keys: how fast the wheel turns toward the requested angle (full lock per second).
@export_range(0.5, 30.0, 0.5) var steer_speed: float = 6.0
## Keys: how fast it returns to centre when the input eases off.
@export_range(0.5, 30.0, 0.5) var steer_return_speed: float = 9.0
## Analogue stick: how fast the wheel follows the stick (full lock per second).
## Much faster than for keys; the thumb already does the smoothing.
@export_range(1.0, 120.0, 1.0) var stick_steer_speed: float = 40.0
## Analogue stick response curve: lock fraction = |stick|^exponent. 1 = linear,
## higher = finer control near centre, full lock still at full deflection.
@export_range(1.0, 3.0, 0.05) var stick_steer_exponent: float = 1.4
## Fraction of the car's slip angle added to the steering, pointing the front
## wheels along the direction of travel: makes counter-steering catch slides
## even though steering is reduced at speed. 0 = none. The player wins: when the
## input steers against the assist (into the slide), the assist fades out in
## proportion to the input, so full lock gives full lock.
@export_range(0.0, 1.5, 0.05) var counter_steer_assist: float = 0.35
## Steering with a slide (counter-steering) may use more lock than the speed
## allows otherwise: the lock opens toward max_steer_low_deg as the body slip
## grows, reaching it at this slip angle, so a person can catch a big slide at
## speed. 0 = off (the lock always follows the speed).
@export_range(0.0, 60.0, 1.0) var countersteer_open_deg: float = 18.0

@export_group("Tyres")
## Friction coefficient on the road.
@export_range(0.1, 3.0, 0.05) var grip_road: float = 1.3
## Friction coefficient off the road (on the ground).
@export_range(0.1, 3.0, 0.05) var grip_ground: float = 0.58
@export_range(0.1, 2.0, 0.05) var front_grip: float = 1.05
@export_range(0.1, 2.0, 0.05) var rear_grip: float = 1.1
## Longitudinal grip (drive, brakes) as a multiple of the lateral grip: the
## friction circle becomes an ellipse, so the car can brake and put power down
## harder than it can corner.
@export_range(0.5, 2.0, 0.05) var grip_long_ratio: float = 1.6
## Slip angle at which lateral grip peaks.
@export_range(1.0, 30.0, 0.5) var peak_slip_deg: float = 7.0
## Lateral grip left when sliding well past the peak (fraction of peak).
@export_range(0.1, 1.0, 0.05) var slide_grip: float = 0.87
## Fraction of the rear tyres' lateral grip lost at full throttle, scaled by the
## pedal and by the drive force left at this speed (like launch_accel): power
## oversteer that throttle can hold and lifting gives back. 0 = only the friction
## circle (drive force sharing the grip).
@export_range(0.0, 0.8, 0.05) var power_oversteer: float = 0.15
## Rear grip multiplier while the handbrake is held: always in the classic
## handbrake (drift_mode off); with drift_mode only for a low-speed pivot
## (handbrake + steering below drift_min_speed).
@export_range(0.0, 1.0, 0.05) var handbrake_rear_grip: float = 0.4
## Braking from the handbrake (rear wheels), as a deceleration.
@export_range(0.0, 20.0, 0.5) var handbrake_decel: float = 3.0
## Below this speed the slip angle uses this speed as its denominator, so the
## lateral force fades smoothly instead of flipping at standstill.
@export_range(0.1, 3.0, 0.05) var low_speed_slip: float = 0.8

@export_group("Drift (handbrake)")
## Handbrake + steering above drift_min_speed starts an arcade drift: the tyre
## forces hand over to a held body angle, an arc set by the stick and a slow
## speed loss, ending in a boost. Off = classic handbrake (rear grip cut).
@export var drift_mode: bool = true
## Slowest speed at which the handbrake starts (or keeps, x0.8) a drift.
@export_range(0.5, 6.0, 0.1) var drift_min_speed: float = 2.5
## Steering needed, either way, to start a drift with the handbrake.
@export_range(0.1, 1.0, 0.05) var drift_steer_threshold: float = 0.35
## Body angle to the direction of travel held in a drift, stick at neutral.
@export_range(5.0, 50.0, 0.5) var drift_angle_deg: float = 25.0
## Extra angle at full inside stick (less when steering outward).
@export_range(0.0, 20.0, 0.5) var drift_angle_steer_deg: float = 8.0
## Hard ceiling on the body angle in a drift.
@export_range(10.0, 80.0, 1.0) var drift_angle_max_deg: float = 45.0
## How fast the body swings to the drift angle and back on exit (1/s).
@export_range(1.0, 30.0, 0.5) var drift_rotate_rate: float = 8.0
## Arc curvature (1 / radius) with the stick fully to the inside of the drift.
@export_range(0.05, 2.0, 0.01) var drift_carve: float = 0.55
## Curvature with the stick at neutral, as a fraction of drift_carve; steering
## outward straightens the arc further.
@export_range(0.0, 1.0, 0.05) var drift_carve_neutral: float = 0.45
## Sideways acceleration available in a drift, in g on the road (scaled by the
## surface's grip): how tight the arc can be at speed.
@export_range(0.2, 3.0, 0.05) var drift_grip: float = 1.1
## Speed lost per second in a drift on full throttle (lifting adds rolling drag
## and engine braking, the brake pedal adds more).
@export_range(0.0, 10.0, 0.1) var drift_speed_loss: float = 0.4
## Exit boost: forward acceleration (u/s^2) for drift_boost_time after a drift
## of at least DRIFT_BOOST_MIN_TIME, scaled by the charge (full after
## drift_boost_charge_time of drifting). 0 = no boost.
@export_range(0.0, 20.0, 0.25) var drift_boost_accel: float = 3.75
@export_range(0.1, 3.0, 0.05) var drift_boost_time: float = 0.5
@export_range(0.2, 5.0, 0.1) var drift_boost_charge_time: float = 1.5

@export_group("Nitro")
## A full tank: seconds of burn (held; tap to feather).
@export_range(0.0, 5.0, 0.05) var nitro_capacity: float = 1.5
## Extra drive while burning (u/s^2 at standstill), through the rear tyres on the
## ground (so it can break them loose in a corner) and straight on the body in
## the air. Falls off toward the raised top speed like the engine's drive.
@export_range(0.0, 30.0, 0.5) var nitro_accel: float = 10.0
## Top speed raised by this fraction while burning.
@export_range(0.0, 1.0, 0.01) var nitro_top_gain: float = 0.25
## Time for the push to build up and to die away (s).
@export_range(0.01, 1.0, 0.01) var nitro_ramp_time: float = 0.2
## Refill while drifting (handbrake drift held), as tank fractions per second.
@export_range(0.0, 2.0, 0.05) var nitro_drift_refill: float = 0.35
## Slow refill: seconds to fill an empty tank (0 = none). Neither refill runs while burning.
@export_range(0.0, 120.0, 1.0) var nitro_trickle_time: float = 20.0
## Above the normal top speed after a burn, extra drag per u/s of excess (1/s),
## so the car settles back over a second or two.
@export_range(0.0, 5.0, 0.05) var nitro_overspeed_drag: float = 1.2

@export_group("Visual")
## Body roll per g of lateral acceleration (on top of the physical lean).
@export_range(0.0, 20.0, 0.5) var lean_deg_per_g: float = 6.0
## Body pitch per g of longitudinal acceleration (on top of the physical pitch).
@export_range(0.0, 20.0, 0.5) var pitch_deg_per_g: float = 3.0
@export_range(0.0, 20.0, 0.5) var max_lean_deg: float = 8.0

## Driving inputs. Read from the InputMap unless `player_input` is false, in
## which case whoever drives (autopilot, test script) writes them.
var player_input: bool = true
var steer_input: float = 0.0 ## -1 left .. 1 right
var throttle_input: float = 0.0 ## 0..1
var brake_input: float = 0.0 ## 0..1, reverses when (nearly) stopped
var handbrake_input: bool = false
var nitro_input: bool = false
## False ignores nitro_input (e.g. the demo reel).
var nitro_enabled: bool = true
## True when the steering comes from an analogue stick (no key smoothing): set
## by a deflected stick, cleared by a steering key.
var steer_analog: bool = false
## When false the arrow keys do not drive (the tuning panel uses them).
var arrow_keys_drive: bool = true

## Read-outs.
var forward_speed: float = 0.0 ## along the car's nose, + forward
var steer_angle: float = 0.0 ## front wheel angle, radians, + right
var steer_lock: float = 0.0 ## full-lock angle at the current speed, radians
var wheels_grounded: int = 0
var wheels_on_road: int = 0
## Surface under each wheel (fl, fr, rl, rr) last physics step (Surfaces id; &"" in the air).
var wheel_surface: Array[StringName] = [&"", &"", &"", &""]
## Sum of the grounded wheels' grip relative to asphalt, and whether any wheel
## is on a surface other than asphalt or the plain ground (dirt, snow...).
var _grip_ratio_sum: float = 0.0
var _special_surface: bool = false
var _drift_loss_sum: float = 0.0
## Per wheel: how hard it is sliding sideways (0 = gripping, 1 = well past the
## tyre's peak) and spinning under power (0..1), for the dust and tyre sounds.
var wheel_slide: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
var wheel_spin: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
## Per wheel, last step: grip relative to asphalt, and whether it was on a
## surface other than asphalt or the plain ground (for split-grip braking).
var _wheel_ratio: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0]
var _wheel_special: Array[bool] = [false, false, false, false]
var slip_angle: float = 0.0 ## car body slip (radians), + = moving to its right
var local_accel: Vector3 = Vector3.ZERO ## filtered, body frame: x right, z forward
## Per wheel (fl, fr, rl, rr): how much of the tyre's grip is asked for, 1 = at the
## limit (lateral slip at the curve's peak, or force on the friction circle);
## above 1 the tyre slides. 0 when the wheel is in the air.
var wheel_usage: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
var drift_state: Drift = Drift.NONE
var drift_dir: float = 0.0 ## +1 drifting right (clockwise), -1 left
var drift_time: float = 0.0 ## seconds in the current/last drift
var drift_angle: float = 0.0 ## body angle to the travel direction, radians, + = into the drift
var drift_target: float = 0.0 ## the angle the drift aims for, radians
var drift_radius: float = 0.0 ## arc radius the drift is carving
var boost_charge: float = 0.0 ## 0..1, builds while drifting
var boost_left: float = 0.0 ## seconds of exit boost still to come
var boost_power: float = 0.0 ## 0..1, charge being delivered by the current boost
var _drift_w: float = 0.0 ## 0 = tyres, 1 = drift forces
var _exit_time: float = 0.0
var _hb_armed: bool = true ## the handbrake was up since the last drift ended
var air_time: float = 0.0 ## seconds since a wheel last touched the ground
var nitro_tank: float = 1.5 ## seconds of burn left
var nitro_level: float = 0.0 ## 0..1 push being delivered (ramps in and out)
## Seconds since the current burn started (0 when not burning), and how many
## burns have started (for sound and effects: a change = ignition).
var nitro_time: float = 0.0
var nitro_ignitions: int = 0
var _nitro_held: bool = false

var _steer_state: float = 0.0
var _mounts: Array[Vector3] = [] ## wheel attach points (top of travel), body local
var _rest: Array[Vector3] = [] ## wheel hub rest positions, body local
var _wheel_nodes: Array[Node3D] = []
## Set before the car enters the tree to drive with these wheel rest
## positions (fl, fr, bl, br; body local) instead of the model's: a car with a
## different body keeps the same physics. The model's wheels are then drawn at
## their own positions, offset from the physics ones.
var physics_wheel_rest: Array[Vector3] = []
var _visual_offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _wheel_spin: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
var _wheel_drop: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0] ## hub distance below mount
var _prev_velocity: Vector3 = Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()

@onready var _lean: Node3D = $Lean


func _ready() -> void:
	add_to_group(Lighting.LIT_CARS) # headlights in the night lighting mode
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	can_sleep = false
	# Pull the wheels out of the body mesh so the visual lean does not tilt them.
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	add_child(wheels)
	for wn in WHEEL_NAMES:
		var w := find_child(wn, true, false) as Node3D
		var rest := wheels.to_local(w.global_position)
		w.reparent(wheels, false)
		w.position = rest
		w.basis = Basis.IDENTITY
		_wheel_nodes.append(w)
		if physics_wheel_rest.size() == 4:
			var i := _rest.size()
			_visual_offset[i] = rest - physics_wheel_rest[i]
			rest = physics_wheel_rest[i]
		_rest.append(rest)
	refresh_tuning()
	_ray.collision_mask = Track.LAYER_SURFACE
	_ray.exclude = [get_rid()]
	_ray.hit_back_faces = false


## Sets exported tunables by name (e.g. from a preset) and updates what is
## derived from them. Safe while driving.
func apply_tuning(values: Dictionary) -> void:
	for key: String in values:
		set(key, values[key])
	refresh_tuning()


## Re-derives the centre of mass, inertia and wheel mounts from the tunables.
## Call after changing com_height, inertia_per_mass or travel_up directly.
func refresh_tuning() -> void:
	center_of_mass = Vector3(0.0, com_height, 0.0)
	inertia = inertia_per_mass * mass
	_mounts.clear()
	for r in _rest:
		_mounts.append(Vector3(r.x, r.y + travel_up, r.z))


## Whether any key bound to these actions is held down.
static func _key_held(actions: Array[StringName]) -> bool:
	for action in actions:
		for e in InputMap.action_get_events(action):
			var k := e as InputEventKey
			if k != null and (Input.is_physical_key_pressed(k.physical_keycode) if k.physical_keycode != KEY_NONE else Input.is_key_pressed(k.keycode)):
				return true
	return false


func _read_player_input() -> void:
	# The source is decided every step from what is held: a steering key means
	# digital (smoothed) steering from the keys alone; otherwise the steering
	# comes from the analogue axis (rescaled past the action deadzone).
	var left: Array[StringName] = [&"steer_left"]
	var right: Array[StringName] = [&"steer_right"]
	if arrow_keys_drive:
		left.append(&"arrow_left")
		right.append(&"arrow_right")
	var keys := float(_key_held(right)) - float(_key_held(left))
	if keys != 0.0 or _key_held(left):
		steer_input = keys
		steer_analog = false
	else:
		steer_input = Input.get_axis(&"steer_left", &"steer_right")
		# A centred stick keeps the last source, so the wheels follow the stick
		# back to centre at stick speed and keys still return at key speed.
		if steer_input != 0.0:
			steer_analog = true
	throttle_input = Input.get_action_strength(&"throttle")
	brake_input = Input.get_action_strength(&"brake")
	if arrow_keys_drive:
		throttle_input = maxf(throttle_input, Input.get_action_strength(&"arrow_up"))
		brake_input = maxf(brake_input, Input.get_action_strength(&"arrow_down"))
	handbrake_input = Input.is_action_pressed(&"handbrake")
	nitro_input = Input.is_action_pressed(&"nitro")


func _physics_process(delta: float) -> void:
	if player_input:
		_read_player_input()
	else:
		steer_analog = false # scripted drivers write a target, smoothed like keys

	var xf := global_transform
	var up := xf.basis.y.normalized()
	var fwd := -xf.basis.z.normalized()
	var right := xf.basis.x.normalized()
	var v := linear_velocity
	forward_speed = v.dot(fwd)
	var lat_speed := v.dot(right)
	slip_angle = atan2(lat_speed, absf(forward_speed)) if v.length() > 0.5 else 0.0

	# Filtered acceleration in the body frame, for the visual lean.
	var acc := (v - _prev_velocity) / delta
	_prev_velocity = v
	var a_body := Vector3(acc.dot(right), acc.dot(up), acc.dot(fwd))
	local_accel = local_accel.lerp(a_body, 1.0 - exp(-delta / 0.12))

	_update_steering(delta)
	_update_drift_state(delta)
	_update_nitro(delta)
	var top_eff := boosted_top_speed()

	var corner_mass := mass * 0.25
	var k := corner_mass * pow(TAU * spring_hz, 2.0)
	var c := 2.0 * damping_ratio * sqrt(k * corner_mass)
	var free_len := travel_up + corner_mass * G / k # spring length with no load
	var ray_len := travel_up + travel_down + wheel_radius
	var max_load := corner_mass * G * max_suspension_load
	var com_global := xf * center_of_mass
	var space := get_world_3d().direct_space_state

	wheels_grounded = 0
	wheels_on_road = 0
	_grip_ratio_sum = 0.0
	_special_surface = false
	_drift_loss_sum = 0.0
	for i in 4:
		var front := i < 2
		var mount := xf * _mounts[i]
		_ray.from = mount
		_ray.to = mount - up * ray_len
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			_wheel_drop[i] = travel_up + travel_down
			wheel_usage[i] = 0.0
			wheel_surface[i] = &""
			wheel_slide[i] = 0.0
			wheel_spin[i] = 0.0
			_wheel_special[i] = false
			continue
		var dist := mount.distance_to(hit.position)
		var hub := clampf(dist - wheel_radius, 0.0, travel_up + travel_down)
		_wheel_drop[i] = hub
		wheels_grounded += 1
		var surf: StringName = hit.collider.get_meta(&"surface", &"road")
		wheel_surface[i] = surf
		var classic := Surfaces.is_classic(surf)
		var on_road: bool = surf == &"road" or not classic and bool(Surfaces.get_value(surf, "on_road", true))
		if on_road:
			wheels_on_road += 1
		if not classic:
			_special_surface = true

		var contact: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var pv := v + angular_velocity.cross(contact - com_global)

		# Suspension: spring on hub travel, damper on the body's motion at the mount
		# (not on travel rate, so a step in the ground does not spike it).
		var spring := k * (free_len - (dist - wheel_radius))
		var damper := -c * pv.dot(up)
		var load := clampf(spring + damper, 0.0, max_load)
		apply_force(up * load, contact - xf.origin)

		# Tyre frame on the ground plane.
		var wf := fwd
		if front:
			wf = fwd.rotated(up, -steer_angle)
		wf = (wf - normal * wf.dot(normal)).normalized()
		var ws := wf.cross(normal)
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(ws)

		var surf_grip := (grip_road if on_road else grip_ground) if classic else grip_road * float(Surfaces.get_value(surf, "grip", 1.0))
		_grip_ratio_sum += surf_grip / grip_road
		var ratio_prev := _wheel_ratio[i]
		_wheel_ratio[i] = surf_grip / grip_road
		_wheel_special[i] = not classic
		# Surface factors on the car's own tunables (1 on asphalt and the ground).
		var f_rear := 1.0 if classic else float(Surfaces.get_value(surf, "rear_grip", 1.0))
		var f_power := 1.0 if classic else float(Surfaces.get_value(surf, "power_oversteer", 1.0))
		var f_coast := 1.0 if classic else float(Surfaces.get_value(surf, "coast", 1.0))
		var f_brake := 1.0 if classic else float(Surfaces.get_value(surf, "brake", 1.0))
		_drift_loss_sum += 1.0 if classic else float(Surfaces.get_value(surf, "drift_loss", 1.0))
		var mu := surf_grip * (front_grip if front else rear_grip * f_rear)
		if not front and handbrake_input and (not drift_mode or forward_speed < drift_min_speed and absf(steer_input) >= drift_steer_threshold):
			mu *= handbrake_rear_grip
		var grip := mu * load
		# Largest force that only cancels this wheel's sliding within one step.
		var stop := corner_mass / delta

		# Lateral: slip-angle curve, peak at peak_slip, easing to slide_grip beyond.
		var alpha := atan2(v_lat, maxf(absf(v_long), low_speed_slip))
		var ps := peak_slip_deg if classic else peak_slip_deg * float(Surfaces.get_value(surf, "peak_slip", 1.0))
		var sg := slide_grip if classic else minf(slide_grip * float(Surfaces.get_value(surf, "slide_grip", 1.0)), 1.0)
		var x := alpha / deg_to_rad(ps)
		var shape := x if absf(x) <= 1.0 else signf(x) * lerpf(1.0, sg, clampf((absf(x) - 1.0) / 1.5, 0.0, 1.0))
		var f_lat := -grip * shape
		if not front and throttle_input > 0.0 and forward_speed > -0.5:
			var rv := clampf(forward_speed / top_speed, 0.0, 1.0)
			f_lat *= 1.0 - (power_oversteer if f_power == 1.0 else minf(power_oversteer * f_power, 0.9)) * throttle_input * (1.0 - rv * rv)
		f_lat = clampf(f_lat, -absf(v_lat) * stop, absf(v_lat) * stop)

		# Longitudinal.
		var f_long := 0.0
		var braking := 0.0 # magnitude of force opposing v_long
		if not front:
			if throttle_input > 0.0:
				if forward_speed > -0.5:
					var r := clampf(forward_speed / top_eff, 0.0, 1.0)
					f_long += throttle_input * mass * 0.5 * launch_accel * (1.0 - r * r)
				else:
					braking += throttle_input * mass * brake_decel * (1.0 - brake_front_bias) * 0.5
			if brake_input > 0.0 and forward_speed < 0.5:
				var r := clampf(-forward_speed / reverse_speed, 0.0, 1.0)
				f_long -= brake_input * mass * 0.5 * reverse_accel * (1.0 - r * r)
			if handbrake_input and drift_state == Drift.NONE:
				# Pivot (drift_mode, slow, steering): the rear slides instead of locking up.
				var pivot := drift_mode and forward_speed < drift_min_speed and absf(steer_input) >= drift_steer_threshold
				braking += mass * 0.5 * handbrake_decel * (DRIFT_PIVOT_BRAKE if pivot else 1.0)
			if throttle_input <= 0.0 and brake_input <= 0.0 and forward_speed > 0.5:
				braking += mass * 0.5 * engine_braking * f_coast
			if nitro_level > 0.0 and forward_speed > -0.5:
				var rn := clampf(forward_speed / top_eff, 0.0, 1.0)
				f_long += nitro_level * mass * 0.5 * nitro_accel * (1.0 - rn * rn)
			if forward_speed > top_speed and nitro_level < 1.0:
				braking += mass * 0.5 * nitro_overspeed_drag * (forward_speed - top_speed) * (1.0 - nitro_level)
		if brake_input > 0.0 and forward_speed >= 0.5:
			var bias := brake_front_bias if front else 1.0 - brake_front_bias
			braking += brake_input * mass * brake_decel * bias * 0.5 * f_brake
		braking += corner_mass * rolling_decel * (f_coast if throttle_input <= 0.0 else 1.0)
		if not on_road:
			braking += corner_mass * offroad_drag * absf(v_long)
		elif not classic:
			braking += corner_mass * float(Surfaces.get_value(surf, "drag", 0.0)) * absf(v_long)
		# Split grip (one wheel of an axle on snow or dirt, the other not): the
		# grippier wheel brakes no harder than its partner can (select-low, as
		# ABS does), so braking does not yank the car round. Never on asphalt
		# and plain ground alone.
		var pair := i ^ 1
		if braking > 0.0 and (_wheel_special[i] or _wheel_special[pair]) and ratio_prev > _wheel_ratio[pair]:
			braking *= _wheel_ratio[pair] / maxf(ratio_prev, 1e-3)
		# Brakes and drag only ever bring the contact patch to rest, never reverse it.
		f_long -= signf(v_long) * minf(braking, absf(v_long) * stop)

		# Friction ellipse (a circle when grip_long_ratio is 1).
		var f := Vector2(f_long, f_lat)
		var g_long := grip * grip_long_ratio
		wheel_usage[i] = Vector2(f_long / maxf(g_long, 1e-6), x).length()
		var use := Vector2(f_long / maxf(g_long, 1e-6), f_lat / maxf(grip, 1e-6)).length()
		wheel_slide[i] = clampf((absf(x) - 1.0) / 1.5, 0.0, 1.0)
		# Wheelspin: drive asking for more than the tyre has left (rear, under power).
		wheel_spin[i] = clampf((use - 1.0) * 2.0, 0.0, 1.0) if not front and f_long > 0.0 else 0.0
		if use > 1.0:
			f /= use
		f *= 1.0 - _drift_w
		apply_force(wf * f.x + ws * f.y, contact - xf.origin)

	_apply_drift_forces(delta, up, fwd)
	if wheels_grounded == 0 and nitro_level > 0.0:
		# In the air the push goes straight on the body (no steering from it).
		var rn := clampf(forward_speed / top_eff, 0.0, 1.0)
		var flat := (fwd - Vector3.UP * fwd.dot(Vector3.UP)).normalized()
		apply_central_force(flat * mass * nitro_accel * nitro_level * (1.0 - rn * rn))
	air_time = 0.0 if wheels_grounded > 0 else air_time + delta
	if wheels_grounded == 0:
		_stabilise_in_air(up)
	_update_dust()
	_update_visuals(delta)


func _update_steering(delta: float) -> void:
	var target := clampf(steer_input, -1.0, 1.0)
	var rate: float
	if steer_analog:
		target = signf(target) * pow(absf(target), stick_steer_exponent)
		rate = stick_steer_speed
	else:
		rate = steer_speed if absf(target) > absf(_steer_state) and signf(target) == signf(_steer_state) or _steer_state == 0.0 else steer_return_speed
	_steer_state = move_toward(_steer_state, target, rate * delta)
	var t := clampf(absf(forward_speed) / top_speed, 0.0, 1.0)
	var lock := deg_to_rad(lerpf(max_steer_low_deg, max_steer_high_deg, t))
	if countersteer_open_deg > 0.0 and forward_speed > 1.0 and _steer_state != 0.0 and signf(_steer_state) == signf(slip_angle):
		lock = lerpf(lock, deg_to_rad(max_steer_low_deg), clampf(absf(slip_angle) / deg_to_rad(countersteer_open_deg), 0.0, 1.0))
	steer_lock = lock
	var angle := _steer_state * lock
	if forward_speed > 1.0:
		var full := deg_to_rad(max_steer_low_deg)
		var assist := clampf(slip_angle, -full, full) * counter_steer_assist
		# Steering with the assist (counter-steering) adds to it; steering against
		# it (into the slide) fades it out, so the player's input always wins.
		if signf(assist) != signf(_steer_state):
			assist *= 1.0 - absf(_steer_state)
		angle += assist
	if _drift_w > 0.0:
		# In a drift the front wheels point along the direction of travel
		# (counter-steered), a little toward the inside with the stick.
		var inside := clampf(steer_input * drift_dir, -1.0, 1.0)
		angle = lerpf(angle, -drift_dir * drift_angle + drift_dir * inside * deg_to_rad(5.0), _drift_w)
	steer_angle = clampf(angle, -deg_to_rad(max_steer_low_deg), deg_to_rad(max_steer_low_deg))


## Top speed with the nitro's gain at its current level.
func boosted_top_speed() -> float:
	return top_speed * (1.0 + nitro_top_gain * nitro_level)


## Nitro tank: burns while held (and not empty), refills from drifting and a
## slow trickle when not burning; the push ramps in and out.
func _update_nitro(delta: float) -> void:
	var burn := nitro_enabled and nitro_input and nitro_tank > (0.0 if _nitro_held else NITRO_MIN_START)
	if burn and not _nitro_held:
		nitro_ignitions += 1
		nitro_time = 0.0
	_nitro_held = burn
	nitro_level = move_toward(nitro_level, 1.0 if burn else 0.0, delta / nitro_ramp_time)
	if burn:
		nitro_tank = maxf(nitro_tank - delta, 0.0)
		nitro_time += delta
	else:
		nitro_time = 0.0
		var fill := 0.0
		if drift_state == Drift.DRIFT:
			fill += nitro_drift_refill * nitro_capacity
		if nitro_trickle_time > 0.0:
			fill += nitro_capacity / nitro_trickle_time
		nitro_tank = minf(nitro_tank + fill * delta, nitro_capacity)


## Fills the nitro tank (a new game).
func refill_nitro() -> void:
	nitro_tank = nitro_capacity
	nitro_level = 0.0
	nitro_time = 0.0
	_nitro_held = false


## Starts, keeps and ends the handbrake drift (see the Drift export group).
func _update_drift_state(delta: float) -> void:
	if not handbrake_input:
		_hb_armed = true
	var inside := clampf(steer_input * drift_dir, -1.0, 1.0)
	drift_angle = -slip_angle * drift_dir if drift_dir != 0.0 else 0.0
	match drift_state:
		Drift.NONE:
			_drift_w = 0.0
			if drift_mode and handbrake_input and _hb_armed and absf(steer_input) >= drift_steer_threshold \
					and forward_speed >= drift_min_speed and wheels_grounded >= 2:
				drift_state = Drift.DRIFT
				drift_dir = signf(steer_input)
				drift_time = 0.0
				boost_charge = 0.0
				boost_left = 0.0
				_hb_armed = false
				drift_angle = -slip_angle * drift_dir
		Drift.DRIFT:
			drift_time += delta
			_drift_w = minf(_drift_w + delta / DRIFT_BLEND_TIME, 1.0)
			if drift_time >= DRIFT_BOOST_MIN_TIME:
				boost_charge = clampf(drift_time / drift_boost_charge_time, 0.0, 1.0)
			var keep := handbrake_input or throttle_input > 0.3 and inside > 0.2
			var spun := drift_angle > deg_to_rad(drift_angle_max_deg + 30.0) # knocked round (impact)
			var slow := forward_speed < drift_min_speed * 0.8
			if not keep or inside < -0.5 or slow or spun or air_time > drift_air_time or not drift_mode:
				drift_state = Drift.EXIT
				_exit_time = 0.0
				if not spun and not slow and drift_time >= DRIFT_BOOST_MIN_TIME and drift_boost_accel > 0.0:
					boost_left = drift_boost_time
					boost_power = boost_charge
				boost_charge = 0.0
		Drift.EXIT:
			_exit_time += delta
			_drift_w = minf(_drift_w, clampf(absf(drift_angle) / deg_to_rad(DRIFT_EXIT_BLEND_DEG), 0.0, 1.0))
			if absf(drift_angle) < deg_to_rad(DRIFT_EXIT_DONE_DEG) or _exit_time > DRIFT_EXIT_MAX_TIME:
				drift_state = Drift.NONE
				_drift_w = 0.0
	if boost_left > 0.0 and brake_input > 0.1:
		boost_left = 0.0 # braking cancels the boost


## The drift as forces on the body: a sideways force bending the path into the
## arc the stick asks for, a longitudinal one for the speed loss, and a yaw
## torque that holds the body angle (in the exit: brings it back to 0). Also
## the exit boost. Scaled by how many wheels touch the ground.
func _apply_drift_forces(delta: float, up: Vector3, fwd: Vector3) -> void:
	var g_frac := wheels_grounded / 4.0
	if boost_left > 0.0:
		var f := (fwd - up * fwd.dot(up)).normalized()
		apply_central_force(f * mass * drift_boost_accel * boost_power * g_frac)
		if wheels_grounded > 0:
			boost_left = maxf(boost_left - delta, 0.0) # held over while airborne, delivered on landing
	if drift_state == Drift.NONE:
		drift_radius = 0.0
		if handbrake_input and drift_mode and absf(slip_angle) > deg_to_rad(drift_angle_max_deg):
			# Handbrake pivot at low speed: the same ceiling, so it cannot spin.
			var over := absf(slip_angle) - deg_to_rad(drift_angle_max_deg)
			_yaw_toward(signf(slip_angle) * drift_rotate_rate * over * 2.0, -angular_velocity.dot(up), g_frac, up)
		return
	var vh := linear_velocity - up * linear_velocity.dot(up)
	var spd := vh.length()
	if spd < 0.3:
		return
	var vdir := vh / spd
	var side := vdir.cross(up) # right of the direction of travel
	var r := -angular_velocity.dot(up) # yaw rate to the right
	var inside := clampf(steer_input * drift_dir, -1.0, 1.0)
	if drift_state == Drift.DRIFT:
		var on_road := float(wheels_on_road) / maxf(wheels_grounded, 1.0)
		var surface := lerpf(grip_ground, grip_road, on_road) / grip_road
		if _special_surface:
			surface = _grip_ratio_sum / maxf(wheels_grounded, 1.0)
		var kappa := drift_carve * (drift_carve_neutral + (1.0 - drift_carve_neutral) * inside if inside >= 0.0 else drift_carve_neutral * (1.0 + inside))
		var a_lat := minf(spd * spd * kappa, drift_grip * G * surface) * g_frac
		drift_radius = spd * spd / a_lat if a_lat > 1e-3 else INF
		apply_central_force(side * drift_dir * mass * a_lat * _drift_w)
		var a_long := -drift_speed_loss * (_drift_loss_sum / maxf(wheels_grounded, 1.0) if _special_surface else 1.0) - (1.0 - throttle_input) * (rolling_decel + engine_braking) \
				- brake_input * brake_decel * 0.5 - offroad_drag * spd * (1.0 - on_road)
		apply_central_force(vdir * mass * a_long * g_frac * _drift_w)
		drift_target = deg_to_rad(clampf(drift_angle_deg + drift_angle_steer_deg * inside, 5.0, drift_angle_max_deg))
		var rate := drift_rotate_rate * (drift_target - drift_angle)
		var over := drift_angle - deg_to_rad(drift_angle_max_deg)
		if over > 0.0:
			rate = minf(rate, -drift_rotate_rate * 3.0 * over)
		_yaw_toward(drift_dir * (a_lat / spd + rate), r, g_frac * _drift_w, up)
	else:
		drift_target = 0.0
		drift_radius = 0.0
		# Straighten along the direction of travel: body angle to 0, first order (no overshoot).
		_yaw_toward(drift_dir * -drift_rotate_rate * 1.5 * drift_angle, r, g_frac, up)


## In the air: damp pitch and roll rates and pull the body gently level.
func _stabilise_in_air(up: Vector3) -> void:
	var w := angular_velocity
	var w_tilt := w - Vector3.UP * w.dot(Vector3.UP) # everything but yaw about world up
	var level := up.cross(Vector3.UP) # axis that rotates `up` toward world up
	var alpha := -w_tilt * air_damping + level * air_level
	apply_torque(Basis(global_basis.get_rotation_quaternion()) * (inertia * (global_basis.inverse() * alpha)))


## Yaw torque toward the wanted yaw rate (to the right), capped.
func _yaw_toward(want: float, r: float, scale: float, up: Vector3) -> void:
	var iy := inertia.y
	var tau := clampf(iy * DRIFT_YAW_GAIN * (want - r), -iy * DRIFT_YAW_ACCEL_MAX, iy * DRIFT_YAW_ACCEL_MAX)
	apply_torque(-up * tau * scale)


func _update_visuals(delta: float) -> void:
	for i in 4:
		var w := _wheel_nodes[i]
		var m := _mounts[i]
		w.position = Vector3(m.x, m.y - _wheel_drop[i], m.z) + _visual_offset[i]
		var wf := -global_basis.z
		if i < 2:
			wf = wf.rotated(global_basis.y, -steer_angle)
		var vl := linear_velocity.dot(wf)
		_wheel_spin[i] = fmod(_wheel_spin[i] + vl / wheel_radius * delta, TAU)
		var yaw := -steer_angle if i < 2 else 0.0
		w.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -_wheel_spin[i])
	var lim := deg_to_rad(max_lean_deg)
	var roll := clampf(deg_to_rad(lean_deg_per_g) * local_accel.x / G, -lim, lim)
	var pitch := clampf(deg_to_rad(pitch_deg_per_g) * local_accel.z / G, -lim, lim)
	if wheels_grounded == 0:
		roll = 0.0
		pitch = 0.0
	_lean.rotation = Vector3(pitch, 0.0, roll)


## Puts the car at `xf` (on the ground plane) standing still.
var _dust: Dust


## Dust behind the rear wheels when they slide, spin or drift on a dusty surface.
func _update_dust() -> void:
	var colour := Color.TRANSPARENT
	var k := 0.0
	for i in [2, 3]:
		var surf := wheel_surface[i]
		if surf == &"" or Surfaces.is_classic(surf):
			continue
		var c: Variant = Surfaces.get_value(surf, "dust", null)
		if c == null:
			continue
		colour = c
		k = maxf(k, maxf(wheel_slide[i], wheel_spin[i]))
		k = maxf(k, maxf(wheel_slide[i - 2], 0.0) * 0.7)
	if colour.a > 0.0:
		var spd := clampf(absf(forward_speed) / 3.0, 0.0, 1.0)
		if drift_state == Drift.DRIFT:
			k = maxf(k, 0.8)
		k *= maxf(spd, wheel_spin[2])
	if _dust == null:
		if colour.a == 0.0 or k <= 0.12:
			return
		_dust = Dust.new()
		_dust.car = self
		add_child(_dust)
	var rear := (_mounts[2] + _mounts[3]) * 0.5 if _mounts.size() == 4 else Vector3(0.0, 0.0, 0.4)
	_dust.feed(colour, k, Vector3(rear.x, rear.y - 0.12, rear.z + 0.05))


func teleport(xf: Transform3D) -> void:
	global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * 0.02)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	local_accel = Vector3.ZERO
	_steer_state = 0.0
	drift_state = Drift.NONE
	_drift_w = 0.0
	boost_left = 0.0
	boost_charge = 0.0
	nitro_level = 0.0
	nitro_time = 0.0
	_nitro_held = false
	reset_physics_interpolation()


## Most compressed wheel: 0 = at rest height or below, 1 = at the bump stop.
func suspension_compression() -> float:
	var c := 0.0
	for i in 4:
		c = maxf(c, (travel_up - _wheel_drop[i]) / maxf(travel_up, 1e-4))
	return clampf(c, 0.0, 1.0)


func is_upright() -> bool:
	return global_basis.y.dot(Vector3.UP) > 0.8
