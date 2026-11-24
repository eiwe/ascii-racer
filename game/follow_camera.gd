## Fixed-angle isometric orthographic camera that follows a target with
## smoothing and look-ahead, and optionally snaps to the ASCII cell grid so the
## static world scrolls in whole cells (no glyph shimmer).
class_name FollowCamera
extends Camera3D

const YAW_DEG: float = 45.0
const PITCH_DEG: float = -35.0
const DISTANCE: float = 20.0
## Orthographic heights; ZOOM_DEFAULT (5.4) matches the demo.
const ZOOM_LEVELS: Array[float] = [12.0, 9.0, 7.0, 5.4, 4.0, 3.0, 2.1, 1.5]
const ZOOM_DEFAULT: int = 3

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
		size = ZOOM_LEVELS[zoom_index]

## Smoothed, unsnapped point the camera looks at (on the ground).
var focus: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO


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
	focus = _target_pos()
	_ahead = Vector3.ZERO
	_place()


func _process(delta: float) -> void:
	if target == null:
		return
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
	vel.y = 0.0
	var want := (vel * look_ahead_time).limit_length(max_look_ahead)
	_ahead = _ahead.lerp(want, 1.0 - exp(-look_ahead_rate * delta))
	focus = focus.lerp(_target_pos() + _ahead, 1.0 - exp(-follow_rate * delta))
	_place()


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
