## Fixed-angle isometric orthographic camera that follows a target with
## smoothing and look-ahead, and optionally snaps to the ASCII cell grid so the
## static world scrolls in whole cells (no glyph shimmer).
##
## Zoom (`zoom_choice`, the pause menu's ZOOM setting): a fixed step is a plain
## multiplier on the base zoom (ZOOM_LEVELS[zoom_index], the , . keys) with the
## car centred. AUTO (the default) frames a window narrower than 21:9 so it
## shows about as much road ahead as a 21:9 window does: mostly by looking
## further ahead with calm, heavily smoothed motion (see GLIDE_*), partly by
## zooming out a little by aspect. At 21:9 and wider AUTO is exactly the fixed
## framing at 1x.
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
## windows (capped). At n = 0 AUTO is exactly the fixed framing at 1x.
const AUTO_WIDE_ASPECT: float = 21.0 / 9.0
const AUTO_REF_ASPECT: float = 16.0 / 9.0
const AUTO_NARROW_MAX: float = 1.6
## Zoom out by n x this, at most AUTO_ZOOM_MAX (the car stays at least 1 / 1.3 =
## 77% of its fixed-zoom size). A constant for a given window: the zoom does not
## move while the view travels.
const AUTO_ASPECT_ZOOM: float = 0.12
const AUTO_ZOOM_MAX: float = 1.3
## AUTO's framing for narrow windows ("glide"): rather than the fixed framing's
## quick look-ahead, the camera looks ahead along a strongly smoothed velocity
## (critically damped, so it never overshoots): on straights and fast bends the
## road ahead gets the screen; through a hairpin the smoothed direction averages
## out and the offset fades instead of swinging round, then grows again on the
## exit, as one move. The camera follows the car's position with a critically
## damped spring (continuous acceleration, no kicks), with the lag it would
## build at a steady speed fed forward so the framing does not drift with speed.
## A small bias along the car's heading frames the road ahead on the grid; it
## turns very slowly, so spins and drifts do not swing the view.
## Look-ahead: smoothed velocity x this many seconds (x n), at most this far (x n).
var glide_ahead_time: float = 0.2
var glide_ahead_max: float = 2.1
## Angular frequencies (rad/s) of the velocity smoothing and of the follow spring.
var glide_velocity_w: float = 0.9
var glide_follow_w: float = 10.0
## The velocity used to feed the follow spring's lag forward is smoothed only
## lightly (rad/s), so it keeps up with the car through corners.
var glide_feed_w: float = 8.0
## Standing bias along the heading (x n) and its smoothing (rad/s).
var glide_heading_bias: float = 0.8
var glide_heading_w: float = 0.8

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
## The fixed framing's state (also AUTO's at n = 0).
var _fixed_focus: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO
## AUTO's glide state: follow spring position and velocity, smoothed target
## velocity and its rate, heading bias and its rate.
var _gp: Vector3 = Vector3.ZERO
var _gv: Vector3 = Vector3.ZERO
var _sv: Vector3 = Vector3.ZERO
var _sv_rate: Vector3 = Vector3.ZERO
var _hb: Vector3 = Vector3.ZERO
var _hb_rate: Vector3 = Vector3.ZERO
var _fv: Vector3 = Vector3.ZERO
var _fv_rate: Vector3 = Vector3.ZERO


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
	var n := narrowness()
	_ahead = Vector3.ZERO
	_fixed_focus = _target_pos()
	_sv = _target_vel()
	_sv_rate = Vector3.ZERO
	_hb = _heading_bias(n)
	_hb_rate = Vector3.ZERO
	_fv = _sv
	_fv_rate = Vector3.ZERO
	_gp = _target_pos()
	_gv = _sv
	focus = _fixed_focus.lerp(_glide_goal(n), _glide_mix(n))
	_apply_size(n)
	_place()


func _process(delta: float) -> void:
	if target == null:
		return
	var vel := _target_vel()
	var n := narrowness()
	# The fixed framing (exactly as it always was).
	var want := (vel * look_ahead_time).limit_length(max_look_ahead)
	_ahead = _ahead.lerp(want, 1.0 - exp(-look_ahead_rate * delta))
	_fixed_focus = _fixed_focus.lerp(_target_pos() + _ahead, 1.0 - exp(-follow_rate * delta))
	# AUTO's glide (state kept up to date always, so switching is seamless).
	_damp(delta, glide_velocity_w, vel, "_sv", "_sv_rate")
	_damp(delta, glide_heading_w, _heading_bias(n), "_hb", "_hb_rate")
	_damp(delta, glide_feed_w, vel, "_fv", "_fv_rate")
	# Follow spring on the car's position; the lag a critically damped spring
	# builds at a steady velocity (2 v / w) is fed forward from the smoothed velocity.
	var goal := _target_pos() + _fv * (2.0 / glide_follow_w)
	var w := glide_follow_w
	_gv += (w * w * (goal - _gp) - 2.0 * w * _gv) * delta
	_gp += _gv * delta
	focus = _fixed_focus.lerp(_glide_goal(n), _glide_mix(n))
	_apply_size(n)
	_place()


## AUTO's look point: the followed car position plus the smoothed look-ahead
## and the heading bias.
func _glide_goal(n: float) -> Vector3:
	var ahead := (_sv * glide_ahead_time * n).limit_length(glide_ahead_max * n)
	return _gp + ahead + _hb


## How much of the glide is used: none at n = 0 (wide windows, fixed steps),
## all of it from n = 0.5 on.
func _glide_mix(n: float) -> float:
	return clampf(n * 2.0, 0.0, 1.0)


## One step of a critically damped second-order filter on the member `x` (with
## its rate `r`) toward `goal`: continuous, no overshoot.
func _damp(delta: float, w: float, goal: Vector3, x: StringName, r: StringName) -> void:
	var xv: Vector3 = get(x)
	var rv: Vector3 = get(r)
	rv += (w * w * (goal - xv) - 2.0 * w * rv) * delta
	xv += rv * delta
	set(x, xv)
	set(r, rv)


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
		zoom_factor = minf(1.0 + n * AUTO_ASPECT_ZOOM, AUTO_ZOOM_MAX)
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
	return f.normalized() * glide_heading_bias * n if f.length() > 0.01 else Vector3.ZERO


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
