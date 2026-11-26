## Rear chase view (Forza Horizon style): a perspective camera behind and
## above the car, looking past it down the road.
##
## It follows the direction of travel with a little lag (a blend of where the
## car points and where it is going), so slides and drifts show the car's
## angle; height is smoothed (more in the air) so crests and the jump do not
## jolt it. Field of view widens and the camera pulls back with speed. The
## right stick orbits it round the car (cam_look_* actions), easing back to the
## chase position after a pause. Geometry between car and camera (bridge deck,
## walls, pillars, trees, the ground) pulls the camera in so the car stays in view.
class_name ChaseCamera
extends Camera3D

@export var target: Car
## Distance behind the pivot and its pitch above the horizontal.
@export_range(0.5, 10.0, 0.05) var distance: float = 2.5
@export_range(0.0, 60.0, 0.5) var pitch_deg: float = 17.0
## Pivot height above the car's origin (the point orbited and looked past).
@export_range(0.0, 2.0, 0.05) var pivot_height: float = 0.35
## How far ahead of the pivot the camera looks.
@export_range(0.0, 10.0, 0.1) var look_ahead: float = 2.0
## Field of view (vertical, degrees) standing still and at top speed.
@export_range(20.0, 120.0, 0.5) var fov_slow: float = 58.0
@export_range(20.0, 120.0, 0.5) var fov_fast: float = 68.0
## Extra distance at top speed.
@export_range(0.0, 3.0, 0.05) var speed_pull_back: float = 0.6
## Nitro: extra field of view (degrees) and pull-back at a full burn.
@export_range(0.0, 30.0, 0.5) var nitro_fov_kick: float = 9.0
@export_range(0.0, 2.0, 0.05) var nitro_pull_back: float = 0.35
## How quickly the camera turns to follow the car (1/s), and how much the
## direction of travel (vs where the car points) counts when moving forward.
@export_range(0.5, 20.0, 0.1) var heading_rate: float = 4.0
@export_range(0.0, 1.0, 0.05) var travel_weight: float = 0.6
## Height smoothing (1/s), on the ground and in the air.
@export_range(0.5, 30.0, 0.5) var height_rate: float = 8.0
@export_range(0.1, 30.0, 0.1) var air_height_rate: float = 2.0
## Right stick: orbit speeds (rad/s at full deflection), pitch limits (added
## to pitch_deg), and the return to the chase position after release.
@export_range(0.5, 10.0, 0.1) var orbit_speed: float = 3.0
@export_range(0.1, 5.0, 0.1) var orbit_pitch_speed: float = 1.2
@export_range(-60.0, 0.0, 1.0) var orbit_pitch_min_deg: float = -12.0
@export_range(0.0, 80.0, 1.0) var orbit_pitch_max_deg: float = 50.0
@export_range(0.0, 3.0, 0.05) var recentre_delay: float = 0.6
@export_range(0.5, 20.0, 0.5) var recentre_rate: float = 3.0
## Line of sight: closest the camera may be pulled in, and how fast it moves
## back out once clear (u/s).
@export_range(0.1, 3.0, 0.05) var min_distance: float = 0.5
@export_range(0.5, 20.0, 0.5) var unblock_speed: float = 4.0

## Multiplies `distance` (the , and . keys).
## Keep following while another camera is current (the view blend reads it).
var drive_when_hidden: bool = false
var distance_scale: float = 1.0:
	set(v):
		distance_scale = clampf(v, 0.5, 2.5)
## Orbit offsets from the right stick (radians).
var orbit_yaw: float = 0.0
var orbit_pitch: float = 0.0
## Read-outs for tests and the HUD.
var blocked: bool = false

var _yaw: float = 0.0 ## chase heading (radians, like atan2(dir.x, -dir.z))
var _pivot_y: float = 0.0
var _dist: float = 0.0 ## current distance after line of sight
var _idle: float = 0.0 ## seconds since the stick was last moved
var _last_pivot: Vector3 = Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	near = 0.05
	far = 60.0
	fov = fov_slow
	# Placed every frame from the interpolated car; never interpolate it again.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 100 # after game logic, before the renderer copies the camera
	_ray.collision_mask = Track.LAYER_SURFACE | Track.LAYER_PROPS
	_ray.hit_back_faces = true


static func _heading_of(v: Vector3) -> float:
	return atan2(v.x, -v.z)


static func _dir(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, -cos(yaw))


## Jump straight behind the car (no smoothing), e.g. after a reset or a toggle.
func snap_to_target() -> void:
	if target == null:
		return
	var xf := target.get_global_transform_interpolated()
	_yaw = _heading_of(-xf.basis.z)
	_pivot_y = xf.origin.y + pivot_height
	_dist = _want_distance()
	_last_pivot = xf.origin
	_place(0.0)


func _want_distance() -> float:
	var t := clampf(target.linear_velocity.length() / maxf(target.top_speed, 0.1), 0.0, 1.0)
	return distance * distance_scale + speed_pull_back * t + nitro_pull_back * target.nitro_level


func _process(delta: float) -> void:
	if target == null or not (current or drive_when_hidden):
		return
	var xf := target.get_global_transform_interpolated()
	if xf.origin.distance_to(_last_pivot) > 3.0:
		snap_to_target() # reset or teleport: no swing across the map
	_last_pivot = xf.origin

	# Heading: blend of the body's heading and the direction of travel.
	var body := _heading_of(-xf.basis.z)
	var v := target.linear_velocity
	v.y = 0.0
	var want := body
	if v.length() > 2.0 and target.forward_speed > 0.5:
		want = lerp_angle(body, _heading_of(v), travel_weight)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-heading_rate * delta))

	var air := target.wheels_grounded == 0
	_pivot_y = lerpf(_pivot_y, xf.origin.y + pivot_height, 1.0 - exp(-(air_height_rate if air else height_rate) * delta))

	# Right stick orbit; ease back after a pause.
	var sx := Input.get_axis(&"cam_look_left", &"cam_look_right")
	var sy := Input.get_axis(&"cam_look_down", &"cam_look_up")
	if sx != 0.0 or sy != 0.0:
		_idle = 0.0
		orbit_yaw = wrapf(orbit_yaw + sx * orbit_speed * delta, -PI, PI)
		orbit_pitch = clampf(orbit_pitch + sy * orbit_pitch_speed * delta, deg_to_rad(orbit_pitch_min_deg), deg_to_rad(orbit_pitch_max_deg))
	else:
		_idle += delta
		if _idle > recentre_delay:
			var k := 1.0 - exp(-recentre_rate * delta)
			orbit_yaw = lerp_angle(orbit_yaw, 0.0, k)
			orbit_pitch = lerpf(orbit_pitch, 0.0, k)

	var t := clampf(target.linear_velocity.length() / maxf(target.top_speed, 0.1), 0.0, 1.0)
	fov = lerpf(fov_slow, fov_fast, t) + nitro_fov_kick * target.nitro_level
	_place(delta)


## Places the camera from the current state; delta 0 = no smoothing.
func _place(delta: float) -> void:
	var origin := target.get_global_transform_interpolated().origin
	var pivot := Vector3(origin.x, _pivot_y, origin.z)
	var yaw := _yaw + orbit_yaw
	var pitch := deg_to_rad(pitch_deg) + orbit_pitch
	var back := -_dir(yaw) * cos(pitch) + Vector3.UP * sin(pitch)
	var want := _want_distance()
	# Line of sight from the car to where the camera wants to be.
	var free := _clear_distance(pivot, back, want)
	blocked = free < want - 0.01
	if delta <= 0.0 or free < _dist:
		_dist = free
	else:
		_dist = minf(free, _dist + unblock_speed * delta)
	var pos := pivot + back * _dist
	global_position = pos
	var look := pivot + _dir(yaw) * look_ahead
	if not look.is_equal_approx(pos):
		look_at(look, Vector3.UP)


## How far along `back` from `pivot` the camera can go before geometry is in the
## way (cones and other loose rigid bodies do not count).
func _clear_distance(pivot: Vector3, back: Vector3, want: float) -> float:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [target.get_rid()]
	var reach := want + 0.25
	for i in 4:
		_ray.from = pivot
		_ray.to = pivot + back * reach
		_ray.exclude = exclude
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			return want
		if hit.collider is RigidBody3D:
			exclude.append(hit.rid)
			continue
		return clampf(pivot.distance_to(hit.position) - 0.25, min_distance, want)
	return want
