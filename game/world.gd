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
## Which circuit is built (a Tracks definition); load_track() swaps it.
var track_def: Dictionary = Tracks.FIGURE_EIGHT

signal track_changed
## The finish gate over the start line (a static body).
var gate: StaticBody3D



func _ready() -> void:
	_build_environment()
	_build_track()
	car = CAR_SCENE.instantiate() as Car
	add_child(car)
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
	return track.pose_at(track.start_s - GRID_BACK)


## The circuit, its scenery and their lighting registration.
func _build_track() -> void:
	track = Track.new()
	track.name = "Track"
	track.def = track_def
	add_child(track)
	props = Node3D.new()
	props.name = "Props"
	add_child(props)
	_build_props()
	lighting.tweaks = track_def.get("time_tweaks", {})
	lighting.set_ground(track.get_node("Ground") as GeometryInstance3D)
	lighting.add_surfaces(track)


## Swaps the circuit for another (the car stays; Game puts it on the grid).
## Returns false if it is already this one.
func load_track(def: Dictionary) -> bool:
	if def.id == track_def.id and track != null:
		return false
	track_def = def
	lighting.clear_surfaces()
	for n: Node in [track, props]:
		remove_child(n)
		n.free()
	gate = null
	_build_track()
	lighting.set_mode(lighting.mode) # the new materials take the mode's look
	track_changed.emit()
	return true


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
	var theme: Dictionary = track_def.get("theme", {})
	var gate_pos := track.point_at(track.start_s)
	var t := track.tangent_at(track.start_s)
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
	_build_trees(theme, gate_pos)
	_build_cones(theme)
	_build_markers(theme)


func _build_trees(theme: Dictionary, gate_pos: Vector3) -> void:
	if not theme.get("trees", true):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = theme.get("tree_seed", TREE_SEED)
	var area := track.bounds.grow(9.0)
	var clear := Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH + TREE_CLEARANCE + (1.3 if track.arena else 0.0)
	var step := 3.4
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.z
		while z < area.end.z:
			var p := Vector3(x + rng.randf_range(-1.3, 1.3), 0.0, z + rng.randf_range(-1.3, 1.3))
			var keep := rng.randf() < float(theme.get("tree_keep", 0.24))
			var pine := rng.randf() < 0.5
			var sc := rng.randf_range(1.15, 1.65)
			z += step
			if not keep or _road_distance(p) < clear + 0.25 * sc or p.distance_to(Vector3(gate_pos.x, 0.0, gate_pos.z)) < 4.0:
				continue
			add_tree(p, pine, sc)
		x += step



## Cones: just inside the apexes of the tight corners, and on track 1 a pair
## beside the east straight (the drive test runs through those).
func _build_cones(theme: Dictionary) -> void:
	if not theme.get("cones", true):
		return
	var edge := Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH + 0.35
	for c in corner_apexes(1.0 / 6.5):
		var s: float = c[0]
		var side: float = c[1]
		for ds: float in [-0.5, 0.5]:
			var xf := track.pose_at(s + ds, side * edge)
			add_cone(xf.origin)
	if track_def.id == Tracks.FIGURE_EIGHT.id:
		for s: float in CONE_PAIR_S:
			add_cone(track.pose_at(s, -edge).origin)


## Arena markers (theme "markers"): tyre stacks round the outside of the flat
## corners and at the ends of the straights, hay bales beside the jumps. They
## stand just off the berms and are solid (a car sliding wide bumps them).
func _build_markers(theme: Dictionary) -> void:
	if not theme.get("markers", false):
		return
	var h := Track.ROAD_HALF_WIDTH
	# Flat corners (no banking): stacks round the outside, one inside at the apex.
	for c in corner_apexes(1.0 / 7.0):
		var s: float = c[0]
		var side: float = c[1]
		if track.bank_at(s) != 0.0:
			continue
		var span := 6.0
		var ds := -span
		while ds <= span:
			add_tyre_stack(track.pose_at(s + ds, -side * (h + 0.85)).origin)
			ds += 1.0
		add_tyre_stack(track.pose_at(s, side * (h + 0.75)).origin)
	# Jumps: bales along both sides of each raised stretch.
	var s2 := 0.0
	while s2 < track.length:
		if track.structure_at(s2) == 1 and track.bank_at(s2) == 0.0 and track.height_at(s2) > 0.05:
			for u: float in [-1.0, 1.0]:
				add_hay_bale(track.pose_at(s2, u * (h + 1.3 + track.height_at(s2) * 1.2 + 0.35)))
		s2 += 1.6


const TYRE_RADIUS: float = 0.2
const TYRE_HEIGHT: float = 0.11


## Three tyres stacked (a solid cylinder to bump into).
func add_tyre_stack(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Track.LAYER_PROPS
	body.collision_mask = 0
	body.position = Vector3(pos.x, Track.GROUND_Y, pos.z)
	var mesh := CylinderMesh.new()
	mesh.top_radius = TYRE_RADIUS
	mesh.bottom_radius = TYRE_RADIUS
	mesh.height = TYRE_HEIGHT * 0.92
	mesh.radial_segments = 12
	mesh.rings = 1
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _marker_material(Color("2c2c33") if i != 1 else Color("c8c2b0"))
		mi.position = Vector3(0.0, TYRE_HEIGHT * (i + 0.5), 0.0)
		body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = TYRE_RADIUS
	shape.height = TYRE_HEIGHT * 3.0
	cs.shape = shape
	cs.position = Vector3(0.0, TYRE_HEIGHT * 1.5, 0.0)
	body.add_child(cs)
	props.add_child(body)


## A straw bale, long side along the road.
func add_hay_bale(xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Track.LAYER_PROPS
	body.collision_mask = 0
	var fwd := -xf.basis.z
	fwd.y = 0.0
	body.transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), Vector3(xf.origin.x, Track.GROUND_Y, xf.origin.z))
	var size := Vector3(0.36, 0.3, 0.7)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _marker_material(Color("d4b25a"))
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = mi.position
	body.add_child(cs)
	props.add_child(body)


var _marker_materials: Dictionary = {}


func _marker_material(c: Color) -> StandardMaterial3D:
	if not _marker_materials.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_marker_materials[c] = m
	return _marker_materials[c]


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
