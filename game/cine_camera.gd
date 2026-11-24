## Cinematic camera for the demo reel: a perspective camera that either stands
## at a fixed place and pans to follow the car (trackside, low, high wide), or
## orbits the car slowly. Positions are set by the ShotDirector; the camera only
## aims, smooths and frames.
class_name CineCamera
extends Camera3D

enum Mode { FIXED, ORBIT }

var target: Car
var mode: Mode = Mode.FIXED
## FIXED: where the camera stands, and how far ahead of the car it aims (s).
var anchor: Vector3 = Vector3.ZERO
var lead_time: float = 0.12
## Framing: field of view at a reference distance; nearer = wider, farther = tighter.
var fov_near: float = 62.0
var fov_far: float = 34.0
var fov_range: Vector2 = Vector2(3.0, 18.0)
## ORBIT: radius, height above the car, angular speed (rad/s), current angle.
var orbit_radius: float = 3.4
var orbit_height: float = 1.1
var orbit_speed: float = 0.35
var orbit_angle: float = 0.0
## How quickly the aim follows the car (1/s).
var aim_rate: float = 10.0

var _aim: Vector3 = Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	near = 0.05
	far = 90.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 100
	_ray.collision_mask = Track.LAYER_SURFACE | Track.LAYER_PROPS
	_ray.hit_back_faces = true


func _car_point() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * 0.25


## Starts a shot: jumps the aim to the car (no swing from the last shot).
func begin() -> void:
	_aim = _car_point() + target.linear_velocity * lead_time
	_place(0.0)


func _process(delta: float) -> void:
	if target == null or not current:
		return
	if mode == Mode.ORBIT:
		orbit_angle += orbit_speed * delta
	_place(delta)


func _place(delta: float) -> void:
	var car := _car_point()
	var want := car + target.linear_velocity * lead_time
	_aim = want if delta <= 0.0 else _aim.lerp(want, 1.0 - exp(-aim_rate * delta))
	var pos := anchor
	if mode == Mode.ORBIT:
		pos = car + Vector3(sin(orbit_angle), 0.0, cos(orbit_angle)) * orbit_radius + Vector3.UP * orbit_height
	global_position = pos
	if not _aim.is_equal_approx(pos):
		look_at(_aim, Vector3.UP)
	var d := pos.distance_to(car)
	fov = lerpf(fov_near, fov_far, clampf((d - fov_range.x) / (fov_range.y - fov_range.x), 0.0, 1.0))


## Distance from the camera to the car.
func car_distance() -> float:
	return global_position.distance_to(_car_point())


## Whether the car is in the picture and not hidden: it counts as seen if a
## clear line reaches any of a few points on it (low, high, front).
func sees_car() -> bool:
	var origin := target.get_global_transform_interpolated().origin
	if not is_position_in_frustum(origin + Vector3.UP * 0.25):
		return false
	var fwd := -target.global_basis.z * 0.35
	for p: Vector3 in [origin + Vector3.UP * 0.15, origin + Vector3.UP * 0.45, origin + fwd + Vector3.UP * 0.3]:
		if _clear_to(p):
			return true
	return false


func _clear_to(p: Vector3) -> bool:
	var exclude: Array[RID] = [target.get_rid()]
	for i in 4:
		_ray.from = global_position
		_ray.to = p
		_ray.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if hit.is_empty():
			return true
		if hit.collider is RigidBody3D:
			exclude.append(hit.rid)
			continue
		return false
	return true
