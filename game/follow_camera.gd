## Fixed-angle isometric orthographic camera that follows a target with
## smoothing and look-ahead, and optionally snaps to the ASCII cell grid so the
## static world scrolls in whole cells (no glyph shimmer).
##
## Zoom (`zoom_choice`, the pause menu's ZOOM setting): a fixed step is a plain
## multiplier on the base zoom (ZOOM_LEVELS[zoom_index], the , . keys). AUTO
## (the default) frames a window narrower than 21:9 so it shows about as much
## road ahead as a 21:9 window did with the fixed framing: mostly by looking
## further ahead (the car sits behind the centre and the road ahead gets the
## screen), partly by zooming out a little by aspect and, slowly, with speed.
## At 21:9 and wider AUTO is exactly the fixed framing at 1x.
class_name FollowCamera
extends Camera3D

const YAW_DEG: float = 45.0
const PITCH_DEG: float = -35.0
const DISTANCE: float = 20.0
## Orthographic heights; ZOOM_DEFAULT (5.4) matches the demo.
const ZOOM_LEVELS: Array[float] = [12.0, 9.0, 7.0, 5.4, 4.0, 3.0, 2.1, 1.5]
const ZOOM_DEFAULT: int = 3
## Fixed zoom steps (zoom_choice 1..): multipliers on the base, near to far.
const ZOOM_STEPS: Array[float] = [0.85, 1.0, 1.15, 1.3, 1.5]

## AUTO. "Narrowness" n: 0 at 21:9 and wider, 1 at 16:9, more for narrower
## windows (capped). Everything AUTO adds scales with n.
const AUTO_WIDE_ASPECT: float = 21.0 / 9.0
const AUTO_REF_ASPECT: float = 16.0 / 9.0
const AUTO_NARROW_MAX: float = 1.6
## Zoom out by n x (aspect part + speed part x speed / AUTO_SPEED_REF), at most
## AUTO_ZOOM_MAX (the car stays at least 1 / 1.3 = 77% of its fixed-zoom size).
const AUTO_ASPECT_ZOOM: float = 0.12
const AUTO_SPEED_ZOOM: float = 0.06
const AUTO_ZOOM_MAX: float = 1.3
const AUTO_SPEED_REF: float = 11.6
## The speed used for zooming follows the car's speed this slowly (1/s), so the
## zoom drifts rather than pumps (no hunting through esses or under braking).
const AUTO_SPEED_RATE: float = 0.7
## Extra look-ahead: n x this many seconds of travel more, up to n x this much
## further, plus a standing bias along the car's heading (so the grid and slow
## corners frame the road ahead too) that turns with the car at this rate (1/s).
const AUTO_EXTRA_TIME: float = 0.25
const AUTO_EXTRA_MAX: float = 1.6
const AUTO_HEADING_BIAS: float = 0.8
const AUTO_HEADING_RATE: float = 1.5

@export var target: Node3D
## The renderer that draws this camera (provides the cell size for snapping).
@export var renderer: AsciiRenderer
@export var snap_to_grid: bool = false
## Seconds of travel to look ahead (along the target's velocity).
@export_range(0.0, 2.0, 0.05) var look_ahead_time: float = 0.3
@export_range(0.0, 10.0, 0.1) var max_look_ahead: float = 2.2
## How quickly the look-ahead offset follows changes of velocity (1/s).
@export_range(0.1, 20.0, 0.1) var look_ahead_rate: float = 2.5
## How quickly the camera catches up with its goal (1/s).
@export_range(0.1, 30.0, 0.1) var follow_rate: float = 6.0

var zoom_index: int = ZOOM_DEFAULT:
	set(v):
		zoom_index = clampi(v, 0, ZOOM_LEVELS.size() - 1)
		size = ZOOM_LEVELS[zoom_index] * zoom_factor
## 0 = AUTO, 1.. = ZOOM_STEPS[zoom_choice - 1].
var zoom_choice: int = 0
## The multiplier on the base zoom in use (read-out).
var zoom_factor: float = 1.0

## Smoothed, unsnapped point the camera looks at (on the ground).
var focus: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO
var _bias: Vector3 = Vector3.ZERO
var _speed_s: float = 0.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = ZOOM_LEVELS[zoom_index]
	near = 0.5
	far = 60.0
	rotation = Vector3(deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0)
	# Positioned every frame from the interpolated target; never interpolate it again.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 100 # after the game logic, before the renderer copies the camera


## Jump straight to the target (no smoothing), e.g. after a reset.
func snap_to_target() -> void:
	if target == null:
		return
	_ahead = Vector3.ZERO
	_bias = _heading_bias(narrowness())
	_speed_s = _target_vel().length()
	focus = _target_pos() + _bias
	_apply_size(narrowness())
	_place()


func _process(delta: float) -> void:
	if target == null:
		return
	var vel := _target_vel()
	var n := narrowness()
	var want := (vel * (look_ahead_time + n * AUTO_EXTRA_TIME)).limit_length(max_look_ahead + n * AUTO_EXTRA_MAX)
	_ahead = _ahead.lerp(want, 1.0 - exp(-look_ahead_rate * delta))
	_bias = _bias.lerp(_heading_bias(n), 1.0 - exp(-AUTO_HEADING_RATE * delta))
	_speed_s = lerpf(_speed_s, vel.length(), 1.0 - exp(-AUTO_SPEED_RATE * delta))
	focus = focus.lerp(_target_pos() + _ahead + _bias, 1.0 - exp(-follow_rate * delta))
	_apply_size(n)
	_place()


## How much AUTO adds for this window's shape (0 with a fixed zoom step).
func narrowness() -> float:
	if zoom_choice != 0:
		return 0.0
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	if vs.y <= 0.0:
		return 0.0
	return clampf((AUTO_WIDE_ASPECT - vs.x / vs.y) / (AUTO_WIDE_ASPECT - AUTO_REF_ASPECT), 0.0, AUTO_NARROW_MAX)


func _apply_size(n: float) -> void:
	if zoom_choice != 0:
		zoom_factor = ZOOM_STEPS[clampi(zoom_choice - 1, 0, ZOOM_STEPS.size() - 1)]
	else:
		# No speed part while snapping to the grid: snapping needs a steady cell size.
		var sp := 0.0 if snap_to_grid else clampf(_speed_s / AUTO_SPEED_REF, 0.0, 1.0)
		zoom_factor = minf(1.0 + n * (AUTO_ASPECT_ZOOM + AUTO_SPEED_ZOOM * sp), AUTO_ZOOM_MAX)
	size = ZOOM_LEVELS[zoom_index] * zoom_factor


func _target_vel() -> Vector3:
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
	vel.y = 0.0
	return vel


func _heading_bias(n: float) -> Vector3:
	if n <= 0.0 or target == null:
		return Vector3.ZERO
	var f := -target.get_global_transform_interpolated().basis.z
	f.y = 0.0
	return f.normalized() * AUTO_HEADING_BIAS * n if f.length() > 0.01 else Vector3.ZERO


func _target_pos() -> Vector3:
	# The car's origin is at its wheel contacts: look just above it (on flat road
	# this is y 0.15, as before the track had height).
	var p := target.get_global_transform_interpolated().origin
	return p + Vector3.UP * 0.05


func _place() -> void:
	var pos := focus + global_basis.z * DISTANCE
	if snap_to_grid and renderer != null:
		pos = renderer.snap_camera_position(self, pos)
	global_position = pos
