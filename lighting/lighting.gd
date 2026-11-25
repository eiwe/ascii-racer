## Lighting modes for a scene rendered by AsciiRenderer: the environment, the
## sun and the switches for the lighting ideas (shadow hatching, glint on the
## car, a sun that moves), as a table of modes. The game world and the demo scene
## both build their light with this, so the demo capture can shoot every mode.
##
## Mode 1 ("classic") is the original look and is fixed: same environment, same
## sun, same shadow filter, nothing else touched. The other modes are
## experiments; their sun can be swung round and raised with set_sun().
##
## Use: `var l := Lighting.new(); l.build(world)` instead of creating a
## WorldEnvironment and a sun, then register what the modes act on (ground,
## car, renderer) and call set_mode().
class_name Lighting
extends Node

signal changed

## The modes, in key order (1-5). Keys of an entry:
##   name             shown on the HUD
##   classic          true = the original lighting, nothing else applies
##   sun_az, sun_el   sun direction, degrees (azimuth: 0 = north / -z, 90 = east / +x)
##   sun_color, sun_energy
##   ambient_color, ambient_energy
##   ground           ground albedo (the ground is near-black in classic, so
##                    shadows on it would not show)
##   track            brightness of the track surfaces (add_surfaces()): the warm
##                    low sun on the blue asphalt reads darker than classic
##   shadow_hard      hard shadow filter (no per-pixel rotating samples: stable glyphs)
##   shadow_distance, shadow_size   reach and resolution of the sun's shadow map
##   hatch            draw shadow as its own texture (AsciiRenderer.shadow_hatch)
##   glint            glossy bodywork on the car so it catches the sun, plus a rim light
##   sweep            the sun swings round once a minute (shadows sweep over the scene)
const MODES: Array[Dictionary] = [
	{"name": "classic", "classic": true},
	{"name": "low sun", "sun_az": 240.0, "sun_el": 22.0, "sun_color": Color(1.0, 0.8, 0.58), "sun_energy": 3.4,
		"ambient_color": Color(0.42, 0.52, 0.85), "ambient_energy": 0.3, "ground": Color(0.2, 0.21, 0.17), "track": 1.25,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192},
	{"name": "hatched", "sun_az": 240.0, "sun_el": 22.0, "sun_color": Color(1.0, 0.8, 0.58), "sun_energy": 3.4,
		"ambient_color": Color(0.42, 0.52, 0.85), "ambient_energy": 0.3, "ground": Color(0.2, 0.21, 0.17), "track": 1.25,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "hatch": true},
	{"name": "glint", "sun_az": 240.0, "sun_el": 22.0, "sun_color": Color(1.0, 0.8, 0.58), "sun_energy": 3.4,
		"ambient_color": Color(0.42, 0.52, 0.85), "ambient_energy": 0.3, "ground": Color(0.2, 0.21, 0.17), "track": 1.25,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "glint": true},
	{"name": "sweep", "sun_az": 240.0, "sun_el": 22.0, "sun_color": Color(1.0, 0.8, 0.58), "sun_energy": 3.4,
		"ambient_color": Color(0.42, 0.52, 0.85), "ambient_energy": 0.3, "ground": Color(0.2, 0.21, 0.17), "track": 1.25,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "sweep": true},
]

## The classic (original) lighting values.
const CLASSIC_FROM: Vector3 = Vector3(-0.45, 1.6, 0.9)
const CLASSIC_ENERGY: float = 1.25
const CLASSIC_AMBIENT: Color = Color(0.55, 0.6, 0.75)
const CLASSIC_AMBIENT_ENERGY: float = 0.45
const CLASSIC_SHADOW_DISTANCE: float = 40.0
## Sun elevation limits for set_sun().
const SUN_EL_RANGE: Vector2 = Vector2(4.0, 85.0)

var environment: Environment
var sun: DirectionalLight3D
## Registered by the scene: what the modes act on.
var ground: GeometryInstance3D
var car: Node3D
var renderer: AsciiRenderer

var mode: int = 0
## The adjustable sun of modes 2-5 (degrees).
var sun_az: float = 240.0
var sun_el: float = 22.0

var _ground_classic: Color = Color.BLACK
var _surfaces: Dictionary = {} ## Material -> its own albedo (scaled by the mode's "track")
var _rim: DirectionalLight3D
var _glint_materials: Dictionary = {} ## MeshInstance3D -> Array of [surface, original material]
var _shadow_size_classic: int = 4096
var _specular_classic: float = 1.0
## True once set_sun() moved the sun: switching modes then keeps it.
var _sun_moved: bool = false


static func mode_index(name_or_number: String) -> int:
	if name_or_number.is_valid_int():
		return clampi(name_or_number.to_int() - 1, 0, MODES.size() - 1)
	for i in MODES.size():
		if MODES[i].name == name_or_number.replace("_", " ").replace("-", " "):
			return i
	return -1


## Creates the environment and the sun under `parent`, exactly as the classic
## scenes always did, and adds this node there too.
func build(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = CLASSIC_AMBIENT
	env.ambient_light_energy = CLASSIC_AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	environment = env

	# Light from high up, a little from screen-left and toward the camera, so
	# top / left / right faces of the blocky models get clearly different values.
	sun = DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-CLASSIC_FROM.normalized(), Vector3.UP)
	sun.light_energy = CLASSIC_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = CLASSIC_SHADOW_DISTANCE
	parent.add_child(sun)
	_specular_classic = sun.light_specular
	name = "Lighting"
	parent.add_child(self)
	_shadow_size_classic = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)


func set_ground(g: GeometryInstance3D) -> void:
	ground = g
	var m := g.material_override as StandardMaterial3D
	if m != null:
		_ground_classic = m.albedo_color


## Registers the materials of every mesh under `root` (but the ground) as track
## surfaces, whose albedo the mode's "track" value scales.
func add_surfaces(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi == ground or mi.mesh == null:
			continue
		var mats: Array[Material] = []
		if mi.material_override != null:
			mats.append(mi.material_override)
		else:
			for si in mi.mesh.get_surface_count():
				if mi.get_active_material(si) != null:
					mats.append(mi.get_active_material(si))
		for m in mats:
			if _surfaces.has(m):
				continue
			if m is StandardMaterial3D:
				_surfaces[m] = (m as StandardMaterial3D).albedo_color
			elif m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("albedo") is Color:
				_surfaces[m] = (m as ShaderMaterial).get_shader_parameter("albedo")


func _set_track_gain(k: float) -> void:
	for m: Material in _surfaces:
		var c: Color = _surfaces[m]
		var v := c if k == 1.0 else Color(c.r * k, c.g * k, c.b * k, c.a)
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = v
		else:
			(m as ShaderMaterial).set_shader_parameter("albedo", v)


func mode_name() -> String:
	return MODES[mode].name


func is_classic() -> bool:
	return MODES[mode].get("classic", false)


## Switches to mode `index` (0-based).
func set_mode(index: int) -> void:
	mode = clampi(index, 0, MODES.size() - 1)
	var m: Dictionary = MODES[mode]
	var classic: bool = m.get("classic", false)
	if classic:
		sun.basis = Basis.looking_at(-CLASSIC_FROM.normalized(), Vector3.UP)
		sun.light_color = Color.WHITE
		sun.light_energy = CLASSIC_ENERGY
		sun.light_specular = _specular_classic
		sun.directional_shadow_max_distance = CLASSIC_SHADOW_DISTANCE
		environment.ambient_light_color = CLASSIC_AMBIENT
		environment.ambient_light_energy = CLASSIC_AMBIENT_ENERGY
		RenderingServer.directional_soft_shadow_filter_set_quality(ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
		RenderingServer.directional_shadow_atlas_set_size(_shadow_size_classic, true)
		if ground != null:
			(ground.material_override as StandardMaterial3D).albedo_color = _ground_classic
		_set_track_gain(1.0)
	else:
		sun_az = m.get("sun_az", sun_az) if not _sun_moved else sun_az
		sun_el = m.get("sun_el", sun_el) if not _sun_moved else sun_el
		_aim_sun()
		sun.light_color = m.get("sun_color", Color.WHITE)
		sun.light_energy = m.get("sun_energy", CLASSIC_ENERGY)
		# No specular from the sun: it depends on the view vector, which shifts
		# with the camera even in ortho, and on the brighter ground it tipped
		# whole bands of cells across a glyph threshold when the camera moved.
		sun.light_specular = 0.0
		sun.directional_shadow_max_distance = m.get("shadow_distance", CLASSIC_SHADOW_DISTANCE)
		environment.ambient_light_color = m.get("ambient_color", CLASSIC_AMBIENT)
		environment.ambient_light_energy = m.get("ambient_energy", CLASSIC_AMBIENT_ENERGY)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_HARD if m.get("shadow_hard", false) else ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
		RenderingServer.directional_shadow_atlas_set_size(m.get("shadow_size", _shadow_size_classic), true)
		if ground != null:
			(ground.material_override as StandardMaterial3D).albedo_color = m.get("ground", _ground_classic)
		_set_track_gain(m.get("track", 1.0))
	if renderer != null:
		renderer.shadow_hatch = not classic and m.get("hatch", false)
	_set_glint(not classic and m.get("glint", false))
	changed.emit()


## Swings / raises the sun of modes 2-5 (degrees); classic ignores it.
func set_sun(azimuth: float, elevation: float) -> void:
	if is_classic():
		return
	_sun_moved = true
	sun_az = fposmod(azimuth, 360.0)
	sun_el = clampf(elevation, SUN_EL_RANGE.x, SUN_EL_RANGE.y)
	_aim_sun()
	changed.emit()


## Back to the mode's own sun (forgets set_sun()).
func reset_sun() -> void:
	_sun_moved = false
	set_mode(mode)


## For captures: the current mode with its sun frozen; the sweep mode shows the
## sun `sweep_seconds` into its turn.
func set_mode_frozen(index: int, sweep_seconds: float = 15.0) -> void:
	sweep_running = false
	_sun_moved = false
	set_mode(index)
	if MODES[mode].get("sweep", false):
		set_sun(sun_az + 360.0 / SWEEP_PERIOD * sweep_seconds, sun_el)
		_sun_moved = false


## Sun keys: degrees per second while held.
const SUN_SWING_RATE: float = 45.0
const SUN_RAISE_RATE: float = 15.0
const SUN_KEYS_HELP: String = "J L swing sun  I K raise / lower sun (lighting 2-5)"


## J / L swing the sun round, I / K raise and lower it (modes 2-5). Call every
## frame while the scene takes keys.
func update_sun_keys(delta: float) -> void:
	if is_classic():
		return
	var swing := float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J))
	var raise := float(Input.is_physical_key_pressed(KEY_I)) - float(Input.is_physical_key_pressed(KEY_K))
	if swing != 0.0 or raise != 0.0:
		set_sun(sun_az + swing * SUN_SWING_RATE * delta, sun_el + raise * SUN_RAISE_RATE * delta)


## Direction the sunlight comes from (unit vector toward the sun).
func sun_from() -> Vector3:
	var az := deg_to_rad(sun_az)
	var el := deg_to_rad(sun_el)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _aim_sun() -> void:
	sun.basis = Basis.looking_at(-sun_from(), Vector3.UP)
	if _rim != null:
		_aim_rim()


## HUD text: mode name and, for modes 2-5, the sun.
func describe() -> String:
	if is_classic():
		return "lighting 1 %s" % mode_name()
	return "lighting %d %s   sun az %d el %d" % [mode + 1, mode_name(), roundi(sun_az), roundi(sun_el)]


# --- glint ----------------------------------------------------------------------

## Layer bit only the car's meshes carry while glint is on, so the rim light
## reaches the car and nothing else (bit 20 is AsciiRenderer.GBUFFER_LAYER).
const GLINT_LAYER: int = 1 << 18
const GLINT_SHADER: Shader = preload("res://lighting/glint.gdshader")
## The highlight (see glint.gdshader): source direction in view space (upper
## left, toward the camera), size, strength, colour, and how much of the real
## faces shows through the smooth ellipsoid.
const GLINT_SOURCE: Vector3 = Vector3(-0.45, 0.75, 0.5)
## Sharpness per view: the car is small on screen in the iso (orthographic) view,
## so its highlight is wider there to cover a few cells.
const GLINT_SHARPNESS_ORTHO: float = 90.0
const GLINT_SHARPNESS_PERSPECTIVE: float = 160.0
const GLINT_ENERGY: float = 1.6
const GLINT_TINT: Color = Color(1.0, 0.95, 0.85)
const GLINT_FACET: float = 0.25
## Rim (kicker) light from the side opposite the sun, low, cool: outlines the
## shadow side of the car.
const RIM_ENERGY: float = 0.6
const RIM_COLOR: Color = Color(0.6, 0.75, 1.0)

var _glint_material: ShaderMaterial
## Test hook: false keeps glint mode but drops its highlight (for measuring it).
var glint_highlight: bool = true:
	set(v):
		glint_highlight = v
		if _glint_material != null:
			_glint_material.set_shader_parameter("energy", GLINT_ENERGY if v else 0.0)


## The car's body (its largest mesh) gets the glint material; every car mesh
## joins GLINT_LAYER for the rim light.
func _set_glint(on: bool) -> void:
	if car == null:
		return
	if on and _glint_materials.is_empty():
		var body: MeshInstance3D
		var meshes: Array[MeshInstance3D] = []
		for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
			if mi.layers & AsciiRenderer.LIGHT_LAYER:
				continue # a shadow-hatching twin
			meshes.append(mi)
			if body == null or mi.get_aabb().get_volume() > body.get_aabb().get_volume():
				body = mi
		for mi in meshes:
			_glint_materials[mi] = []
			mi.layers |= GLINT_LAYER
		if body != null:
			var base := body.get_active_material(0) as StandardMaterial3D
			if base != null:
				var aabb := body.get_aabb()
				_glint_material = ShaderMaterial.new()
				_glint_material.shader = GLINT_SHADER
				_glint_material.set_shader_parameter("albedo_tex", base.albedo_texture)
				_glint_material.set_shader_parameter("albedo", base.albedo_color)
				_glint_material.set_shader_parameter("roughness", base.roughness)
				_glint_material.set_shader_parameter("specular", base.metallic_specular)
				_glint_material.set_shader_parameter("body_centre", aabb.get_center())
				_glint_material.set_shader_parameter("body_half", aabb.size * 0.5)
				_glint_material.set_shader_parameter("source_view", GLINT_SOURCE)
				_glint_material.set_shader_parameter("energy", GLINT_ENERGY if glint_highlight else 0.0)
				_glint_material.set_shader_parameter("tint", GLINT_TINT)
				_glint_material.set_shader_parameter("facet", GLINT_FACET)
				_glint_materials[body] = [[0, body.get_surface_override_material(0)]]
				body.set_surface_override_material(0, _glint_material)
		_rim = DirectionalLight3D.new()
		_rim.name = "RimLight"
		_rim.light_energy = RIM_ENERGY
		_rim.light_color = RIM_COLOR
		_rim.light_specular = 0.0
		_rim.shadow_enabled = false
		_rim.light_cull_mask = GLINT_LAYER
		add_child(_rim)
		_aim_rim()
	elif not on and not _glint_materials.is_empty():
		for mi: MeshInstance3D in _glint_materials:
			for e: Array in _glint_materials[mi]:
				mi.set_surface_override_material(e[0], e[1])
			mi.layers &= ~GLINT_LAYER
		_glint_materials.clear()
		_glint_material = null
		_rim.queue_free()
		_rim = null


func _aim_rim() -> void:
	var f := sun_from()
	_rim.basis = Basis.looking_at(Vector3(f.x, -0.25, f.z).normalized(), Vector3.UP)


# --- sweep ----------------------------------------------------------------------

## Sweep: the sun swings once round the sky in this many seconds.
const SWEEP_PERIOD: float = 60.0

## False holds the sweep (captures that need a fixed sun).
var sweep_running: bool = true


func _process(delta: float) -> void:
	if _glint_material != null:
		var cam := get_viewport().get_camera_3d()
		var ortho := cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL
		_glint_material.set_shader_parameter("sharpness", GLINT_SHARPNESS_ORTHO if ortho else GLINT_SHARPNESS_PERSPECTIVE)
	if sweep_running and MODES[mode].get("sweep", false):
		set_sun(sun_az + 360.0 / SWEEP_PERIOD * delta, sun_el)
