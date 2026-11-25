## Demo diorama: a ring of toy track, props, and the Toy Racer driving round
## it on a scripted circle, with an orthographic isometric follow camera.
extends Node3D

const KIT: String = "res://assets/kenney_toy-car-kit/"
const TRACK_RADIUS: float = 4.0
## Track pieces' meshes sit 1 unit below their origin; the road surface is 0.1 above their base.
const ROAD_Y: float = 0.1
const WHEEL_RADIUS: float = 0.125
const CAM_YAW_DEG: float = 45.0
const CAM_PITCH_DEG: float = -35.0
const CAM_DISTANCE: float = 20.0
const TRACK_TINT: Color = Color(0.5, 0.5, 0.55)

## Orthographic camera heights; index ZOOM_DEFAULT is the default.
## At the capture pose the car's long axis spans ~0.85 world units on screen:
## 5.4 -> ~16 cells long at 14 px glyphs, 2.1 -> ~40 cells.
const ZOOM_LEVELS: Array[float] = [12.0, 9.0, 7.0, 5.4, 4.0, 3.0, 2.1, 1.5]
const ZOOM_DEFAULT: int = 3
const ZOOM_CLOSE: int = 6

@export var speed: float = 1.1 ## world units per second along the track
@export var paused: bool = false

var angle: float = deg_to_rad(240.0) ## position on the ring (radians)
var wheel_spin: float = 0.0
var zoom_index: int = ZOOM_DEFAULT:
	set(v):
		zoom_index = clampi(v, 0, ZOOM_LEVELS.size() - 1)
		if camera != null:
			camera.size = ZOOM_LEVELS[zoom_index]

var camera: Camera3D
var car: Node3D
var lighting: Lighting
var _wheels: Array[Node3D] = []


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_track()
	_build_props()
	car = _spawn("vehicle-racer", Vector3.ZERO, 0.0)
	lighting.car = car
	car.add_to_group(Lighting.LIT_CARS)
	for w in ["wheel-fl", "wheel-fr", "wheel-bl", "wheel-br"]:
		var n := car.find_child(w, true, false) as Node3D
		if n != null:
			_wheels.append(n)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ZOOM_LEVELS[zoom_index]
	camera.near = 0.5
	camera.far = 60.0
	camera.rotation = Vector3(deg_to_rad(CAM_PITCH_DEG), deg_to_rad(CAM_YAW_DEG), 0.0)
	add_child(camera)
	camera.current = true
	_update_pose()
	lighting.set_mode(Lighting.DEFAULT_MODE)


func _process(delta: float) -> void:
	if not paused:
		angle = fmod(angle + speed / TRACK_RADIUS * delta, TAU)
		wheel_spin = fmod(wheel_spin + speed / WHEEL_RADIUS * delta, TAU)
	_update_pose()


## Freeze the car at a ring angle (degrees) with a fixed wheel rotation.
func set_pose(angle_deg: float, spin: float = 0.0) -> void:
	angle = deg_to_rad(angle_deg)
	wheel_spin = spin
	_update_pose()


func _update_pose() -> void:
	var pos := Vector3(cos(angle), 0.0, sin(angle)) * TRACK_RADIUS + Vector3(0.0, ROAD_Y, 0.0)
	var fwd := Vector3(-sin(angle), 0.0, cos(angle))
	car.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	for w in _wheels:
		w.rotation.x = -wheel_spin
	var back := camera.basis.z
	camera.position = pos + Vector3(0.0, 0.15, 0.0) + back * CAM_DISTANCE


func _spawn(file: String, pos: Vector3, yaw_deg: float, scale_f: float = 1.0) -> Node3D:
	var scene := load(KIT + file + ".glb") as PackedScene
	var n := scene.instantiate() as Node3D
	n.position = pos
	n.rotation.y = deg_to_rad(yaw_deg)
	n.scale = Vector3.ONE * scale_f
	add_child(n)
	return n


## Multiplies the albedo of every mesh under `node` by `tint`.
func _tint(node: Node, tint: Color) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var base := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if base == null:
			continue
		var mat := base.duplicate() as StandardMaterial3D
		mat.albedo_color = base.albedo_color * tint
		mi.material_override = mat


func _build_environment() -> void:
	lighting = Lighting.new()
	lighting.build(self)


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120.0, 120.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.075, 0.09, 0.08)
	mat.roughness = 1.0
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.material_override = mat
	add_child(ground)
	lighting.set_ground(ground)


func _build_track() -> void:
	# Four large corners make a ring of radius 4 round the origin. A corner's
	# centre line runs from its origin (heading +Z) round a centre at local (-4, 0).
	for k in 4:
		var rot := Basis(Vector3.UP, k * PI * 0.5)
		var piece := _spawn("track-road-wide-corner-large", Vector3.ZERO, 0.0)
		piece.transform = Transform3D(rot, rot * Vector3(TRACK_RADIUS, 1.0, 0.0))
		# Darker than the kit's colours so the car is the brightest thing on screen.
		_tint(piece, TRACK_TINT)
		lighting.add_surfaces(piece)


func _build_props() -> void:
	# Finish gate across the road ahead of the default pose (road runs along +X at 270 deg).
	_spawn("gate-finish", Vector3(0.0, ROAD_Y, -TRACK_RADIUS), 90.0, 1.3)
	_spawn("gate", Vector3(0.0, ROAD_Y, TRACK_RADIUS), 90.0, 1.3)
	# Cones along the inside kerb.
	for a in [195.0, 215.0, 300.0, 320.0, 30.0, 60.0, 120.0]:
		var r := deg_to_rad(a)
		_spawn("item-cone", Vector3(cos(r), 0.0, sin(r)) * 2.6, a)
	# A loose stack of item boxes in the infield.
	_spawn("item-box", Vector3(-0.6, 0.0, -1.2), 10.0)
	_spawn("item-box", Vector3(-0.1, 0.0, -1.0), 35.0)
	_spawn("item-box", Vector3(-0.35, 0.445, -1.1), 20.0)
	_spawn("item-box", Vector3(1.0, 0.0, 0.6), 0.0)
	# Trees outside the ring and in the middle.
	var trees := [
		[-4.8, -4.6, "tree-pine", 1.6], [-6.2, -2.2, "tree", 1.4], [-3.2, -6.6, "tree", 1.8],
		[1.8, -6.3, "tree-pine", 1.5], [4.6, -5.0, "tree", 1.3], [6.4, -1.4, "tree-pine", 1.7],
		[6.0, 3.6, "tree", 1.5], [2.4, 6.4, "tree-pine", 1.4], [-2.8, 6.0, "tree", 1.6],
		[-6.6, 2.4, "tree-pine", 1.5], [0.4, 0.2, "tree", 1.2], [-1.2, 0.9, "tree-pine", 1.0],
	]
	for t in trees:
		_spawn(t[2], Vector3(t[0], 0.0, t[1]), t[0] * 37.0, t[3])
	_spawn("item-banana", Vector3(cos(deg_to_rad(150.0)), 0.0, sin(deg_to_rad(150.0))) * TRACK_RADIUS + Vector3(0.3, ROAD_Y, 0.0), 0.0)
