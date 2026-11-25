## Lighting modes for a scene rendered by AsciiRenderer: the environment, the
## sun and the switches for the lighting ideas (shadow hatching, glint on the
## car, a sun that moves), as a table of modes. The game world and the demo scene
## both build their light with this, so the demo capture can shoot every mode.
##
## Mode 1 ("sunset") is the default, by the owner's choice. "classic" (mode 3)
## is the original look and is fixed: same environment, same sun, same shadow
## filter, nothing else touched; it is the reference the renderer's output is
## compared against byte for byte. In the other modes the sun (the moon at
## night) can be swung round and raised with set_sun().
##
## Use: `var l := Lighting.new(); l.build(world)` instead of creating a
## WorldEnvironment and a sun, then register what the modes act on (ground,
## car, renderer) and call set_mode().
class_name Lighting
extends Node

signal changed

## The modes, in key order (1-9). Keys of an entry:
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
##   sky              a sky instead of the black void, drawn as characters like
##                    the rest (AsciiRenderer.sky_enabled): "sunset" (sunset
##                    clouds, sunset_sky.gdshader) or "night" (moon and stars,
##                    night_sky.gdshader); perspective views fade into it with
##                    depth fog over "fog" (begin, end; default SKY_FOG)
##   night            every car carries lights (CarLights: headlight beam with
##                    shadows, head and tail lamps, a red glow behind)
const MODES: Array[Dictionary] = [
	{"name": "sunset", "sun_az": 240.0, "sun_el": 14.0, "sun_color": Color(1.0, 0.72, 0.48), "sun_energy": 3.6,
		"ambient_color": Color(0.42, 0.45, 0.75), "ambient_energy": 0.32, "ground": Color(0.2, 0.21, 0.17), "track": 1.25,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "glint": true, "sky": "sunset"},
	{"name": "night", "sun_az": 200.0, "sun_el": 38.0, "sun_color": Color(0.62, 0.72, 1.0), "sun_energy": 1.0,
		"ambient_color": Color(0.36, 0.46, 0.9), "ambient_energy": 0.55, "ground": Color(0.15, 0.18, 0.2), "track": 1.6,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "sky": "night", "fog": Vector2(18.0, 55.0), "night": true},
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
	# Times of day for the level select (after the numbered experiments, so their
	# numbers and the capture names stay put). Morning: a low, cooler-gold sun in
	# the east under a dawn sky; noon: a high white sun, short shadows, blue sky.
	{"name": "morning", "sun_az": 110.0, "sun_el": 17.0, "sun_color": Color(1.0, 0.82, 0.66), "sun_energy": 3.3,
		"ambient_color": Color(0.5, 0.56, 0.82), "ambient_energy": 0.34, "ground": Color(0.19, 0.21, 0.17), "track": 1.2,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "glint": true, "sky": "morning"},
	{"name": "noon", "sun_az": 200.0, "sun_el": 62.0, "sun_color": Color(1.0, 0.98, 0.94), "sun_energy": 2.5,
		"ambient_color": Color(0.6, 0.7, 0.95), "ambient_energy": 0.42, "ground": Color(0.16, 0.2, 0.13), "track": 1.05,
		"shadow_hard": true, "shadow_distance": 60.0, "shadow_size": 8192, "glint": true, "sky": "noon"},
]
## Times of day (level select) -> mode index.
const TIME_MODES: Dictionary = {"morning": 7, "noon": 8, "night": 1}
## The mode a scene starts in (sunset).
const DEFAULT_MODE: int = 0

## The Compatibility renderer (web build) adds its separate light passes (lights
## with shadows) in sRGB space, so lit surfaces come out brighter than under
## Forward+; its lights also fall off differently. These factors on the mode's
## energies were fitted so its ASCII output (the demo capture) matches the
## Forward+ one as closely as one number per light can (by mode name: [ambient,
## sun, headlight beam, tail glow]; the four low-sun modes share sunset's). Not
## used under Forward+.
const COMPAT_ENERGY: Dictionary = {
	"sunset": [1.0, 0.55, 1.0, 1.0],
	"night": [0.6, 0.5, 0.45, 0.15],
	"classic": [0.85, 0.5, 1.0, 1.0],
	"low sun": [1.0, 0.55, 1.0, 1.0],
	"hatched": [1.0, 0.55, 1.0, 1.0],
	"glint": [1.0, 0.55, 1.0, 1.0],
	"sweep": [1.0, 0.55, 1.0, 1.0],
	"morning": [1.0, 0.6, 1.0, 1.0],
	"noon": [1.0, 0.6, 1.0, 1.0],
}
static var compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
## Index of classic (the byte-identity reference).
const CLASSIC_MODE: int = 2

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
## The adjustable sun (the moon at night) of every mode but classic (degrees).
var sun_az: float = 240.0
var sun_el: float = 22.0

var _ground_classic: Color = Color.BLACK
var _surfaces: Dictionary = {} ## Material -> its own albedo (scaled by the mode's "track")
var _rim: DirectionalLight3D
var _glint_materials: Dictionary = {} ## MeshInstance3D -> Array of [surface, original material]
var _shadow_size_classic: int = 4096
var _specular_classic: float = 1.0
var _positional_filter: int = -1
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
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# The Compatibility renderer (web build) draws shadowed lights as extra
		# passes blended into the sRGB output, so they add up encoded and the
		# scene comes out much too bright. A post-process makes it render into
		# a linear buffer first, where they add up as in Forward+: glow at zero
		# strength is that post-process, with no visible effect of its own.
		env.glow_enabled = true
		env.glow_intensity = 0.001
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

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
	_positional_filter = ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)


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


## Forgets the registered track surfaces (before a new circuit registers its own).
func clear_surfaces() -> void:
	_set_track_gain(1.0)
	_surfaces.clear()


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
## The current track's overrides per mode name (Tracks' time_tweaks: the time
## names are the mode names), merged over the mode's table in set_mode.
var tweaks: Dictionary = {}


func set_mode(index: int) -> void:
	mode = clampi(index, 0, MODES.size() - 1)
	var m: Dictionary = MODES[mode]
	if tweaks.has(m.name):
		m = m.merged(tweaks[m.name], true)
	var classic: bool = m.get("classic", false)
	if classic:
		sun.basis = Basis.looking_at(-CLASSIC_FROM.normalized(), Vector3.UP)
		sun.light_color = Color.WHITE
		sun.light_energy = CLASSIC_ENERGY * _compat_factor(1)
		sun.light_specular = _specular_classic
		sun.directional_shadow_max_distance = CLASSIC_SHADOW_DISTANCE
		environment.ambient_light_color = CLASSIC_AMBIENT
		environment.ambient_light_energy = CLASSIC_AMBIENT_ENERGY * _compat_factor(0)
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
		sun.light_energy = m.get("sun_energy", CLASSIC_ENERGY) * _compat_factor(1)
		# No specular from the sun: it depends on the view vector, which shifts
		# with the camera even in ortho, and on the brighter ground it tipped
		# whole bands of cells across a glyph threshold when the camera moved.
		sun.light_specular = 0.0
		sun.directional_shadow_max_distance = m.get("shadow_distance", CLASSIC_SHADOW_DISTANCE)
		environment.ambient_light_color = m.get("ambient_color", CLASSIC_AMBIENT)
		environment.ambient_light_energy = m.get("ambient_energy", CLASSIC_AMBIENT_ENERGY) * _compat_factor(0)
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
	_set_sky("" if classic else String(m.get("sky", "")), m.get("fog", SKY_FOG))
	_set_night(not classic and m.get("night", false))
	changed.emit()


## Swings / raises the sun (the moon at night) (degrees); classic ignores it.
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
const SUN_KEYS_HELP: String = "J L swing sun  I K raise / lower sun (the moon at night; not in classic)"


## J / L swing the sun round, I / K raise and lower it (not in classic). Call every
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


## HUD text: mode name and, but for classic, the sun (or moon).
func describe() -> String:
	if is_classic():
		return "lighting %d %s" % [mode + 1, mode_name()]
	return "lighting %d %s   %s az %d el %d" % [mode + 1, mode_name(), "moon" if MODES[mode].get("night", false) else "sun",
		roundi(sun_az), roundi(sun_el)]


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
			if mi.get_parent() is CarLights:
				continue # the night lamps come and go; they are not bodywork
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
		for k: Variant in _glint_materials:
			if not is_instance_valid(k):
				continue
			var mi := k as MeshInstance3D
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


# --- sky --------------------------------------------------------------------------

const SKY_SHADERS: Dictionary = {
	"sunset": preload("res://lighting/sunset_sky.gdshader"),
	"night": preload("res://lighting/night_sky.gdshader"),
	"morning": preload("res://lighting/sunset_sky.gdshader"),
	"noon": preload("res://lighting/sunset_sky.gdshader"),
}
## Sky shader parameters per kind (on top of the shader's defaults).
const SKY_PARAMS: Dictionary = {
	"morning": {"zenith": Color(0.16, 0.24, 0.48), "high": Color(0.55, 0.5, 0.66), "low": Color(0.98, 0.7, 0.5),
		"band": Color(1.0, 0.84, 0.6), "below": Color(0.1, 0.09, 0.1), "sky_energy": 0.95,
		"cloud_lit": Color(1.0, 0.86, 0.74), "cloud_shade": Color(0.6, 0.58, 0.7), "cloud_under": Color(0.45, 0.42, 0.55)},
	"noon": {"zenith": Color(0.12, 0.32, 0.78), "high": Color(0.3, 0.55, 0.92), "low": Color(0.62, 0.78, 0.96),
		"band": Color(0.82, 0.9, 0.99), "below": Color(0.16, 0.2, 0.24), "sky_energy": 0.95,
		"cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.78, 0.8, 0.88), "cloud_under": Color(0.62, 0.66, 0.76)},
}
## Perspective views fade into the sky over this depth range (world units).
const SKY_FOG: Vector2 = Vector2(14.0, 42.0)
## The Compatibility renderer (web build) does not take the fog's colour from
## the sky as Forward+ does (aerial perspective: each pixel fogs toward the sky
## in its own direction, which for the ground is the dark sky below the
## horizon). It fogs toward one flat colour instead (grey by default, which drew
## a pale band of characters along the horizon), so it gets the colour distant
## ground reaches under Forward+, measured from its frames.
const COMPAT_FOG_COLOR: Dictionary = {
	"sunset": Color8(33, 24, 56),
	"night": Color8(15, 22, 50),
	"morning": Color8(100, 88, 120),
	"noon": Color8(70, 92, 175),
}

var _skies: Dictionary = {} ## name -> Sky
var _sky_on: bool = false
## True while a far view (the level select's preview) must not fade into the sky.
var fog_suppressed: bool = false
## Pushes the sky's depth fog back by this much (the view blend's extra distance).
var fog_offset: float = 0.0
var _fog: Vector2 = SKY_FOG


## `kind`: a key of SKY_SHADERS, or "" for none (the black void).
func _set_sky(kind: String, fog: Vector2 = SKY_FOG) -> void:
	var on := kind != ""
	_sky_on = on
	if on:
		if not _skies.has(kind):
			var mat := ShaderMaterial.new()
			mat.shader = SKY_SHADERS[kind]
			var params: Dictionary = SKY_PARAMS.get(kind, {})
			for k: String in params:
				mat.set_shader_parameter(k, params[k])
			var sky := Sky.new()
			sky.sky_material = mat
			_skies[kind] = sky
		environment.sky = _skies[kind]
		environment.background_mode = Environment.BG_SKY
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		_fog = fog
		environment.fog_depth_begin = fog.x
		environment.fog_depth_end = fog.y
		if compat:
			environment.fog_light_color = COMPAT_FOG_COLOR.get(kind, Color(0.5, 0.5, 0.5))
		environment.fog_density = 1.0
		environment.fog_aerial_perspective = 1.0
		environment.fog_sky_affect = 0.0
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.sky = null
		environment.fog_enabled = false
	if renderer != null:
		renderer.sky_enabled = on
		renderer.sky_ramp_only = kind == "night"


# --- night ------------------------------------------------------------------------

## Cars in this group get CarLights while night is on (Car adds itself; the
## demo scene adds its model).
const LIT_CARS: StringName = &"lit_cars"

var _night: bool = false


func _set_night(on: bool) -> void:
	_night = on
	if not is_inside_tree():
		return
	# Hard shadows from the headlights too (stable glyphs), as for the sun.
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_HARD if on else _positional_filter as RenderingServer.ShadowQuality)
	if not on:
		for c in get_tree().get_nodes_in_group(LIT_CARS):
			var l := c.find_child("CarLights", true, false)
			if l != null:
				l.get_parent().remove_child(l)
				l.queue_free()
	else:
		_light_cars()


## Gives every car in LIT_CARS its lights (once).
func _light_cars() -> void:
	for c: Node in get_tree().get_nodes_in_group(LIT_CARS):
		if c.find_child("CarLights", true, false) != null:
			continue
		var l := CarLights.new()
		l.car = c as Car # null for a plain model (the demo scene's car)
		l.beam_scale = _compat_factor(2)
		l.glow_scale = _compat_factor(3)
		var lean := c.get_node_or_null("Lean") as Node3D
		if lean != null:
			l.position = -lean.position # car-local positions, but leaning with the body
			lean.add_child(l)
		else:
			c.add_child(l)


## The mode's Compatibility factor `i` (see COMPAT_ENERGY); 1 under Forward+.
func _compat_factor(i: int) -> float:
	if not compat:
		return 1.0
	var f: Array = COMPAT_ENERGY.get(mode_name(), [1.0, 1.0, 1.0, 1.0])
	return f[i]


func _process(delta: float) -> void:
	if _night:
		_light_cars() # cars that arrived since (the opponent)
	if _sky_on:
		var cam := get_viewport().get_camera_3d()
		environment.fog_enabled = cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE and not fog_suppressed
		if fog_offset != 0.0 or environment.fog_depth_begin != _fog.x:
			environment.fog_depth_begin = _fog.x + fog_offset
			environment.fog_depth_end = _fog.y + fog_offset
	if _glint_material != null:
		var cam := get_viewport().get_camera_3d()
		var ortho := cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL
		_glint_material.set_shader_parameter("sharpness", GLINT_SHARPNESS_ORTHO if ortho else GLINT_SHARPNESS_PERSPECTIVE)
	if sweep_running and MODES[mode].get("sweep", false):
		set_sun(sun_az + 360.0 / SWEEP_PERIOD * delta, sun_el)
