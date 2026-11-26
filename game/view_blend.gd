## The move between the isometric (orthographic) and the chase (perspective)
## camera when the player switches views: one eased dolly-zoom.
##
## The isometric end is reproduced by a perspective camera with a very narrow
## field of view from far away, looking at the same point along the same axis
## with the same visible height, which is all but orthographic; the chase end
## is the chase camera's own pose. In between the field of view and the
## visible height change together on a log scale, the look point slides, the
## orientation turns (slerp), and the whole move follows a smoothstep in time:
## it starts and stops with zero speed and never overshoots. The real camera
## takes over at the end. Starting again mid-move reverses from where it is.
##
## While it runs, `weight` (0 = isometric, 1 = chase) lets the view-bound
## effects follow: the chase view's distance fade and the sky's depth fog are
## pushed back by the camera's extra distance (so they are as at the chase end
## around the car), and the iso view's halo fades with it.
class_name ViewBlend
extends Camera3D

const DURATION: float = 0.55
const ISO_FOV_DEG: float = 1.5

var iso: FollowCamera
var chase: ChaseCamera
var active: bool = false
## Eased position of the move, 0 = isometric .. 1 = chase.
var weight: float = 0.0
## How much further from the scene than the chase camera it is (world units).
var extra_distance: float = 0.0

var _p: float = 0.0 ## linear progress 0..1
var _goal: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 101 # after the iso (100) and the chase camera have placed themselves


## Starts (or reverses) a move toward the chase view (`to_chase`) or back.
func start(to_chase: bool) -> void:
	_goal = 1.0 if to_chase else 0.0
	if not active:
		_p = 0.0 if to_chase else 1.0
		active = true
		chase.drive_when_hidden = true
		if to_chase:
			chase.snap_to_target()
	_pose(_ease(_p))
	current = true


## Stops at once (an instant switch took over).
func cancel() -> void:
	active = false
	chase.drive_when_hidden = false
	weight = 1.0 if _goal > 0.5 else 0.0
	extra_distance = 0.0


## Finished: the real camera of the goal view is current again.
signal finished(to_chase: bool)


func _process(delta: float) -> void:
	if not active:
		return
	_p = move_toward(_p, _goal, delta / DURATION)
	_pose(_ease(_p))
	if _p == _goal:
		cancel()
		finished.emit(_goal > 0.5)


static func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


func _pose(e: float) -> void:
	weight = e
	# Isometric end: what the ortho camera sees, as a far, narrow perspective.
	var bi := iso.global_basis
	var look_i := iso.global_position - bi.z * FollowCamera.DISTANCE
	var tan_i := tan(deg_to_rad(ISO_FOV_DEG) * 0.5)
	var h_i := iso.size
	# Chase end: its pose, its look point at the car's depth.
	var bc := chase.global_basis
	var pc := chase.global_position
	var car_p := chase.target.global_position if chase.target != null else pc - bc.z * 4.0
	var d_c := maxf((car_p - pc).dot(-bc.z), 1.0)
	var look_c := pc - bc.z * d_c
	var tan_c := tan(deg_to_rad(chase.fov) * 0.5)
	var h_c := 2.0 * d_c * tan_c
	# Between: log-space field of view and visible height, slerped orientation.
	var tan_e := exp(lerpf(log(tan_i), log(tan_c), e))
	var h_e := exp(lerpf(log(h_i), log(h_c), e))
	var d := h_e / (2.0 * tan_e)
	var b := Basis(bi.get_rotation_quaternion().slerp(bc.get_rotation_quaternion(), e))
	var look := look_i.lerp(look_c, e)
	projection = Camera3D.PROJECTION_PERSPECTIVE
	keep_aspect = iso.keep_aspect
	fov = rad_to_deg(2.0 * atan(tan_e))
	near = maxf(0.05, d - 60.0)
	far = d + 140.0
	global_transform = Transform3D(b, look + b.z * d)
	extra_distance = maxf(d - d_c, 0.0)
