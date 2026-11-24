## See-through halo for things that hide the car from the camera (the bridge;
## later tunnels or overpasses): occluder meshes use the halo_occluder shader,
## which opens a round hole around the line from the car to the camera wherever
## the occluder is in the way. Everything is driven by global shader uniforms,
## so one call per frame (set_target) moves every hole.
##
## add_occluder() gives a mesh two instances: the visible one with the halo
## material (casts no shadow) and a shadow-only one with the plain material, so
## shadows stay whole.
class_name HaloOccluder
extends RefCounted

const SHADER: Shader = preload("res://game/shaders/halo_occluder.gdshader")
## Hole radius in world units (the car is 0.875 long), the width of the dithered
## rim inside it, how far above the target an occluder must be to be cut, and
## the dither cell size (about two glyph rows at the default zoom).
const RADIUS: float = 1.1
const SOFTNESS: float = 0.4
const MARGIN: float = 0.5
const DITHER: float = 0.09

static var _material_cache: Dictionary = {}
## The radius last set (0 = closed), for tests and HUDs.
static var radius_now: float = 0.0


## The halo material with the track's albedo tint (shared per tint).
static func material(tint: Color) -> ShaderMaterial:
	if not _material_cache.has(tint):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo", tint)
		_material_cache[tint] = m
	return _material_cache[tint]


## Adds `mesh` under `parent` as an occluder: returns the visible instance.
static func add_occluder(parent: Node3D, node_name: String, mesh: Mesh, tint: Color) -> MeshInstance3D:
	var visible := MeshInstance3D.new()
	visible.name = node_name
	visible.mesh = mesh
	visible.material_override = material(tint)
	visible.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visible)
	var shadow := MeshInstance3D.new()
	shadow.name = node_name + "Shadow"
	shadow.mesh = mesh
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(shadow)
	return visible


## Where the hole looks at (world position, e.g. the middle of the car); radius
## 0 closes every hole.
static func set_target(target: Vector3, radius: float = RADIUS) -> void:
	radius_now = radius
	RenderingServer.global_shader_parameter_set(&"halo_target", target)
	RenderingServer.global_shader_parameter_set(&"halo_radius", radius)
	RenderingServer.global_shader_parameter_set(&"halo_softness", SOFTNESS)
	RenderingServer.global_shader_parameter_set(&"halo_margin", MARGIN)
	RenderingServer.global_shader_parameter_set(&"halo_dither", DITHER)
