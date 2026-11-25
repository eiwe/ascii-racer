## Game world: lighting (same as the demo), the circuit, props, the car, the
## isometric follow camera and the chase camera. Built in _ready, before the AsciiRenderer moves it into its
## SceneViewport.
extends Node3D

const KIT: String = "res://assets/kenney_toy-car-kit/"
const CAR_SCENE: PackedScene = preload("res://game/car.tscn")
const GRID_BACK: float = 2.5 ## spawn distance behind the start line

var track: Track
var car: Car
var camera: FollowCamera
var chase: ChaseCamera
var props: Node3D
var lighting: Lighting
## The finish gate over the start line (a static body).
var gate: StaticBody3D



func _ready() -> void:
	_build_environment()
	track = Track.new()
	track.name = "Track"
	add_child(track)
	props = Node3D.new()
	props.name = "Props"
	add_child(props)
	_build_props()
	car = CAR_SCENE.instantiate() as Car
	add_child(car)
	lighting.set_ground(track.get_node("Ground") as GeometryInstance3D)
	lighting.add_surfaces(track)
	lighting.car = car
	car.global_transform = grid_pose()
	camera = FollowCamera.new()
	camera.target = car
	add_child(camera)
	camera.current = true
	camera.snap_to_target()
	chase = ChaseCamera.new()
	chase.target = car
	add_child(chase)
	lighting.set_mode(Lighting.DEFAULT_MODE)


## Where the car starts: on the centre line, behind the start line.
func grid_pose() -> Transform3D:
	return track.pose_at(Track.START_S - GRID_BACK)


# Environment and sun: see Lighting (shared with the demo scene).
func _build_environment() -> void:
	lighting = Lighting.new()
	lighting.build(self)


func _model(file: String) -> Node3D:
	return (load(KIT + file + ".glb") as PackedScene).instantiate() as Node3D


func _static_prop(file: String, pos: Vector3, yaw_deg: float, scale_v: Variant, shape: Shape3D, shape_offset: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Track.LAYER_PROPS
	body.collision_mask = 0
	body.position = Vector3(pos.x, Track.GROUND_VISUAL_Y, pos.z)
	body.rotation.y = deg_to_rad(yaw_deg)
	var m := _model(file)
	m.scale = scale_v if scale_v is Vector3 else Vector3.ONE * float(scale_v)
	body.add_child(m)
	if shape != null:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = shape_offset
		body.add_child(cs)
	props.add_child(body)
	return body


func add_tree(pos: Vector3, pine: bool, scale_f: float) -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.16 * scale_f
	trunk.height = 0.8 * scale_f
	_static_prop("tree-pine" if pine else "tree", pos, pos.x * 37.0, scale_f, trunk, Vector3(0.0, trunk.height * 0.5, 0.0))


func add_cone(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.02
	body.collision_layer = Track.LAYER_PROPS
	body.collision_mask = Track.LAYER_SURFACE | Track.LAYER_CAR | Track.LAYER_PROPS
	body.position = Vector3(pos.x, Track.GROUND_Y + 0.002, pos.z)
	var m := _model("item-cone")
	body.add_child(m)
	# Cone-shaped hull (not a cylinder), so a bumper tips it over instead of wedging under it.
	var cs := CollisionShape3D.new()
	var mi := m.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	cs.shape = mi.mesh.create_convex_shape(true, true)
	body.add_child(cs)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0.0, 0.05, 0.0)
	props.add_child(body)


## The kit finish gate: distance of a leg's inner foot from the gate's centre
## (model units), and how high the legs' colliders go (world units; above it
## the legs curve into the arch, out of a car's reach).
const GATE_LEG_INNER: float = 0.457
const GATE_LEG_SOLID_HEIGHT: float = 1.05

## Tree clearance from the centre line (road edge + kerb + this much).
const TREE_CLEARANCE: float = 2.0
const TREE_SEED: int = 7


func _build_props() -> void:
	# Finish gate over the start line. The kit gate's legs are 0.457 from its
	# centre at their inner foot (they lean in as they rise into the arch);
	# scaled so that foot stands just outside the asphalt, on the kerbs, so the
	# whole road is open between them. Each leg is solid up to LEG_SOLID_HEIGHT:
	# its collider is the convex hull of its own mesh there, so what you see is
	# what you hit, and a car sliding along it meets smooth faces, not box corners.
	var gate_pos := track.point_at(Track.START_S)
	var t := track.tangent_at(Track.START_S)
	var half := Track.ROAD_HALF_WIDTH + 0.02
	gate = _static_prop("gate-finish", gate_pos, rad_to_deg(atan2(t.x, t.z)), Vector3(half / GATE_LEG_INNER, 1.6, 1.6), null, Vector3.ZERO)
	var inv := gate.global_transform.affine_inverse()
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for mi: MeshInstance3D in gate.find_children("*", "MeshInstance3D", true, false):
			var xf := inv * mi.global_transform
			var faces := mi.mesh.get_faces()
			for i in faces.size():
				var q := xf * faces[i]
				if q.x * side <= 0.5:
					continue
				if q.y <= GATE_LEG_SOLID_HEIGHT:
					pts.append(q)
				# Where the triangle's edges cross the cut height (so the hull
				# reaches it even between widely spaced vertices).
				var nxt := xf * faces[i - i % 3 + (i + 1) % 3]
				if (q.y - GATE_LEG_SOLID_HEIGHT) * (nxt.y - GATE_LEG_SOLID_HEIGHT) < 0.0:
					pts.append(q.lerp(nxt, (GATE_LEG_SOLID_HEIGHT - q.y) / (nxt.y - q.y)))
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		var cs := CollisionShape3D.new()
		cs.name = "Leg"
		cs.shape = hull
		gate.add_child(cs)
	# The top beam too (high above the car; it is there so the chase camera's
	# line of sight sees it).
	var top := 0.0
	for mi: MeshInstance3D in gate.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (mi.global_transform * mi.mesh.get_aabb()).end.y)
	var beam := CollisionShape3D.new()
	var beam_box := BoxShape3D.new()
	beam_box.size = Vector3(half * 2.0 + 0.3, 0.3, 0.3)
	beam.shape = beam_box
	beam.position = Vector3(0.0, top - gate.global_position.y - 0.2, 0.0)
	gate.add_child(beam)

	# Trees: a seeded scatter over the area round the circuit, kept well clear
	# of the road (and of the gate).
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED
	var area := track.bounds.grow(9.0)
	var clear := Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH + TREE_CLEARANCE
	var step := 3.4
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.z
		while z < area.end.z:
			var p := Vector3(x + rng.randf_range(-1.3, 1.3), 0.0, z + rng.randf_range(-1.3, 1.3))
			var keep := rng.randf() < 0.24
			var pine := rng.randf() < 0.5
			var sc := rng.randf_range(1.15, 1.65)
			z += step
			if not keep or _road_distance(p) < clear + 0.25 * sc or p.distance_to(Vector3(gate_pos.x, 0.0, gate_pos.z)) < 4.0:
				continue
			add_tree(p, pine, sc)
		x += step

	# Cones: just inside the apexes of the tight corners, and a pair beside the
	# east straight (the drive test runs through those).
	var edge := Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH + 0.35
	for c in corner_apexes(1.0 / 6.5):
		var s: float = c[0]
		var side: float = c[1]
		for ds: float in [-0.5, 0.5]:
			var xf := track.pose_at(s + ds, side * edge)
			add_cone(xf.origin)
	for s: float in CONE_PAIR_S:
		add_cone(track.pose_at(s, -edge).origin)


## Arc lengths along the east straight of the two cones beside it (outside, left).
const CONE_PAIR_S: Array[float] = [47.0, 48.5]


## Middle of every corner at least this curved: [[s, side (+1 = inside on the right)], ...].
func corner_apexes(min_curvature: float) -> Array:
	var out := []
	var n := track.points.size()
	var ds := track.length / n
	var i := 0
	while i < n:
		var k := track.curvature[i]
		if absf(k) < min_curvature:
			i += 1
			continue
		var j := i
		while j < n and signf(track.curvature[j]) == signf(k) and absf(track.curvature[j]) >= min_curvature:
			j += 1
		out.append([(i + j) * 0.5 * ds, signf(k)])
		i = j
	return out


## Horizontal distance from `p` to the nearest centre-line sample.
func _road_distance(p: Vector3) -> float:
	var best := INF
	for i in range(0, track.points.size(), 3):
		var q := track.points[i]
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length_squared())
	return sqrt(best)
