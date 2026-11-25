## Renders its 3D children as ASCII.
##
## Add your world (camera included) as children of this node; on ready they
## are moved into the internal SceneViewport. Pipeline:
##   SceneViewport (lit colour) + GBufferViewport (view normal + linear depth,
##   shares the world, mirrors the camera) -> CellViewport (one texel per cell
##   per slot, glyph decision) -> OutputViewport (compose glyph atlas) -> screen.
class_name AsciiRenderer
extends Node

signal grid_changed
signal atlas_ready

const SLOTS: int = 2 ## cell texels: glyph + ink, background
## Visual layer (20) that only the gbuffer camera renders: holds the export quad.
const GBUFFER_LAYER: int = 1 << 19
## Visual layer (18) of the white lighting twins used by shadow hatching.
const LIGHT_LAYER: int = 1 << 17
const RAMP_LUT_SIZE: int = 64
const RAMP_MAX: int = 32
const SHAPE_MAX: int = 128

const DEFAULT_FONT: Font = preload("res://assets/fonts/HackNerdFontMono-Bold.ttf")
## Loaded only under Forward+: it reads the normal buffer, which the
## Compatibility renderer does not have (its shader would not compile there).
const GBUFFER_SHADER_PATH: String = "res://ascii/shaders/gbuffer.gdshader"
const GBUFFER_TWIN_SHADER: Shader = preload("res://ascii/shaders/gbuffer_twin.gdshader")
const CELLS_SHADER: Shader = preload("res://ascii/shaders/cells.gdshader")
const COMPOSE_SHADER: Shader = preload("res://ascii/shaders/compose.gdshader")

@export var settings: AsciiSettings
## Output resolution; (0, 0) = follow the window.
@export var fixed_output_size: Vector2i = Vector2i.ZERO:
	set(v):
		fixed_output_size = v
		if is_node_ready():
			_relayout()

## Show the plain 3D render instead of ASCII (scene rendered at full scale).
## Distance fade for perspective views: (begin, end) view depth over which far
## geometry dissolves into the void; (0, 0) = off (the default, and always off
## for orthographic cameras).
var distance_fade: Vector2 = Vector2.ZERO

## Shadow hatching: cells in shadow are drawn as their own texture (sparse
## diagonal hatching in a cool ink), and cells on the lit/shadow boundary get a
## glyph shaped like the boundary. Needs lighting separated from surface colour,
## so while on, a third viewport renders the world as lighting only: every mesh
## gets a white twin on LIGHT_LAYER that only that viewport sees.
## (Viewport.DEBUG_DRAW_LIGHTING would be simpler but does nothing in exported
## release builds.) Off (the default): no viewport, no twins, no cost, no change.
var shadow_hatch: bool = false:
	set(v):
		shadow_hatch = v
		if is_node_ready():
			_apply_shadow_hatch()
## Hatching look: a sample whose lighting-pass brightness (luma) is below
## hatch_threshold counts as shadow; the hatch glyph and its ink (dimmed with
## the cell's own brightness).
var hatch_threshold: float = 0.35
var hatch_glyph: String = "/"
var hatch_ink: Color = Color(0.35, 0.55, 1.0)
## Every hatch_period-th diagonal of cells carries a hatch glyph.
var hatch_period: int = 3
## Glyphs the lit/shadow boundary may use (line-like, so the edge reads as a line).
var hatch_edge_chars: String = "_-'\"^/\\|.,`"
const HATCH_EDGE_MAX: int = 16
## Lighting-only render of the scene while shadow_hatch is on (else null).
var light_viewport: SubViewport

## Sky: background cells (where the scene has no geometry) are drawn from the
## scene's colour like everything else instead of as empty cells, and the
## distance fade is off (the scene fades into its sky itself). Off (the
## default): output unchanged.
var sky_enabled: bool = false:
	set(v):
		sky_enabled = v
		if is_node_ready():
			_cells_material.set_shader_parameter("sky_on", v)

## With the sky on: sky cells get fill-ramp glyphs only (no shape matching), so
## small points of light (stars) draw as one steady glyph rather than as letter
## shapes that change as the camera turns. Off (the default): output unchanged.
var sky_ramp_only: bool = false:
	set(v):
		sky_ramp_only = v
		if is_node_ready():
			_cells_material.set_shader_parameter("sky_ramp", v)

## Whether the overlay cell layer (get_overlay()) is drawn.
var overlay_enabled: bool = false

var raw_view: bool = false:
	set(v):
		raw_view = v
		if is_node_ready():
			_relayout()

var scene_viewport: SubViewport
var gbuffer_viewport: SubViewport
var cell_viewport: SubViewport
var output_viewport: SubViewport
var atlas: GlyphAtlas

var cols: int = 0
var rows: int = 0
var pitch: Vector2i = Vector2i.ONE
var glyph_box: Vector2i = Vector2i.ONE
var output_size: Vector2i = Vector2i.ONE

var _world: World3D
var _gbuffer_camera: Camera3D
var _gbuffer_material: ShaderMaterial
var _cells_rect: ColorRect
var _cells_material: ShaderMaterial
var _compose_rect: ColorRect
var _compose_material: ShaderMaterial
var _display: TextureRect
var _atlas_key: Array = []
var _overlay: AsciiOverlay
var _light_camera: Camera3D
var _light_twins: Array[MeshInstance3D] = []
var _light_material: StandardMaterial3D

## Under the Compatibility renderer (the web build; desktop runs Forward+) there
## is no normal buffer for gbuffer.gdshader to read. There the g-buffer is drawn
## from twins instead: every visible mesh gets a child on GBUFFER_LAYER with an
## unshaded material that writes view normal and depth (gbuffer_twin.gdshader),
## and the g-buffer camera sees only those. Nothing of this exists under Forward+.
var compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
## Compatibility only: twin shaders for meshes whose own material is a
## ShaderMaterial with one of these shaders (key) - for shaders that discard
## fragments, so the twin cuts the same holes (e.g. the halo occluder).
var gbuffer_twin_shaders: Dictionary = {}
var _gbuffer_twin_material: ShaderMaterial
var _gbuffer_twin_materials: Dictionary = {} ## Shader -> ShaderMaterial
var _gbuffer_twins: Dictionary = {} ## original MeshInstance3D -> its twin


func _ready() -> void:
	process_priority = 1000 # mirror the camera after game code has moved it
	if settings == null:
		settings = AsciiSettings.new()
	_build_pipeline()
	for c in get_children():
		remove_child(c)
		scene_viewport.add_child(c)
	if compat:
		_sync_twins.call_deferred()
	settings.changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_relayout)
	_rebuild_atlas()


## The overlay cell layer (created on first use, sized to the grid) and turns
## it on. See AsciiOverlay.
func get_overlay() -> AsciiOverlay:
	if _overlay == null:
		_overlay = AsciiOverlay.new()
		_overlay.atlas = atlas
		_overlay.resize(cols, rows)
		_cells_material.set_shader_parameter("overlay_tex", _overlay.texture)
	overlay_enabled = true
	return _overlay


func _apply_shadow_hatch() -> void:
	if shadow_hatch and light_viewport == null:
		light_viewport = SubViewport.new()
		light_viewport.name = "LightViewport"
		light_viewport.world_3d = _world
		light_viewport.msaa_3d = scene_viewport.msaa_3d
		light_viewport.size = scene_viewport.size
		add_child(light_viewport, false, INTERNAL_MODE_FRONT)
		_light_camera = Camera3D.new()
		_light_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		light_viewport.add_child(_light_camera)
		_light_camera.current = true
	_set_light_twins(shadow_hatch)
	if light_viewport != null:
		light_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shadow_hatch else SubViewport.UPDATE_DISABLED
		_cells_material.set_shader_parameter("light_tex", light_viewport.get_texture())
	_cells_material.set_shader_parameter("hatch_on", shadow_hatch)
	if atlas.ready_to_use:
		_cells_material.set_shader_parameter("hatch_glyph", atlas.index_of(hatch_glyph))
	_cells_material.set_shader_parameter("hatch_threshold", hatch_threshold)
	_cells_material.set_shader_parameter("hatch_ink", Vector3(hatch_ink.r, hatch_ink.g, hatch_ink.b))
	_cells_material.set_shader_parameter("hatch_period", hatch_period)


## White twins of every mesh in the scene, seen only by the lighting camera,
## so it sees the scene's lighting on a white world. Shadow casters are culled
## by the camera's mask as well, so the twins cast like their originals (each
## camera gets the same shadows, from one or the other).
## Lights are culled by camera cull masks too, so they join LIGHT_LAYER meanwhile.
func _set_light_twins(on: bool) -> void:
	for l: Light3D in scene_viewport.find_children("*", "Light3D", true, false):
		if on:
			l.layers |= LIGHT_LAYER
		else:
			l.layers &= ~LIGHT_LAYER
	for t in _light_twins:
		if is_instance_valid(t):
			t.get_parent().remove_child(t)
			t.free()
	_light_twins.clear()
	if not on:
		return
	if _light_material == null:
		_light_material = StandardMaterial3D.new()
		_light_material.albedo_color = Color.WHITE
		_light_material.roughness = 1.0
	for mi: MeshInstance3D in scene_viewport.find_children("*", "MeshInstance3D", true, false):
		if mi.layers & (GBUFFER_LAYER | LIGHT_LAYER) or mi.mesh == null:
			continue
		var t := MeshInstance3D.new()
		t.name = "LightTwin"
		t.mesh = mi.mesh
		t.material_override = _light_material
		t.layers = LIGHT_LAYER
		t.cast_shadow = mi.cast_shadow
		mi.add_child(t, false, INTERNAL_MODE_BACK)
		_light_twins.append(t)


# --- Compatibility g-buffer twins --------------------------------------------------

func _on_node_added(n: Node) -> void:
	if n is MeshInstance3D and scene_viewport.is_ancestor_of(n):
		_sync_twins.call_deferred()


## Gives every visible mesh in the scene its g-buffer twin and drops twins
## whose original is gone (Compatibility only).
func _sync_twins() -> void:
	for k: Variant in _gbuffer_twins.keys():
		if not is_instance_valid(k):
			_gbuffer_twins.erase(k)
	for mi: MeshInstance3D in scene_viewport.find_children("*", "MeshInstance3D", true, false):
		if _gbuffer_twins.has(mi) or mi.layers & (GBUFFER_LAYER | LIGHT_LAYER) \
				or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var t := MeshInstance3D.new()
		t.name = "GBufferTwin"
		t.mesh = mi.mesh
		t.material_override = _twin_material_for(mi)
		t.layers = GBUFFER_LAYER
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.add_child(t, false, INTERNAL_MODE_BACK)
		_gbuffer_twins[mi] = t


func _twin_material_for(mi: MeshInstance3D) -> ShaderMaterial:
	var sm := mi.material_override as ShaderMaterial
	if sm != null and gbuffer_twin_shaders.has(sm.shader):
		var sh: Shader = gbuffer_twin_shaders[sm.shader]
		if not _gbuffer_twin_materials.has(sh):
			var m := ShaderMaterial.new()
			m.shader = sh
			_gbuffer_twin_materials[sh] = m
		return _gbuffer_twin_materials[sh]
	return _gbuffer_twin_material


func is_atlas_ready() -> bool:
	return atlas.ready_to_use


## Image of what is currently shown (ASCII output, or the raw 3D in raw view).
func get_output_image() -> Image:
	var vp := scene_viewport if raw_view else output_viewport
	return vp.get_texture().get_image()


## Smallest camera move, in world units along the camera's right and up axes,
## that shifts the picture by whole cells AND whole scene pixels (the cell pass
## samples the scene bilinearly, so a half-pixel shift would change glyphs).
## That is k cells per axis, k >= 1; (0, 0) if there is no grid yet.
func snap_step(cam: Camera3D) -> Vector2:
	if cam == null or cols == 0 or cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return Vector2.ZERO
	var scene := Vector2(scene_viewport.size)
	var out := Vector2(output_size)
	var extent := Vector2(cam.size * scene.x / scene.y, cam.size) # visible world size
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		extent = Vector2(cam.size, cam.size * scene.y / scene.x)
	var step := Vector2.ZERO
	for a in 2:
		var px_per_cell := float(pitch[a]) * scene[a] / out[a] # scene pixels per cell
		# Fewest cells that land (nearest to) on whole scene pixels. With an odd
		# output size the scene is not exactly scene_scale of it and nothing is exact;
		# then take the closest of a few small steps rather than a huge one.
		var k := 1
		var best := INF
		for n in range(1, 5):
			var err := absf(px_per_cell * n - roundf(px_per_cell * n))
			if err < best - 1e-3:
				best = err
				k = n
		step[a] = k * float(pitch[a]) / out[a] * extent[a]
	return step


## `pos` with its components along the camera's right and up axes rounded to
## snap_step(), so static geometry moves across the cell grid in whole cells.
## The component along the view axis is kept (it does not move the picture).
func snap_camera_position(cam: Camera3D, pos: Vector3) -> Vector3:
	var step := snap_step(cam)
	if step.x <= 0.0 or step.y <= 0.0:
		return pos
	var b := cam.global_basis.orthonormalized()
	var r := snappedf(pos.dot(b.x), step.x)
	var u := snappedf(pos.dot(b.y), step.y)
	return b.x * r + b.y * u + b.z * pos.dot(b.z)


func _build_pipeline() -> void:
	_world = World3D.new()

	scene_viewport = SubViewport.new()
	scene_viewport.name = "SceneViewport"
	scene_viewport.world_3d = _world
	scene_viewport.msaa_3d = Viewport.MSAA_4X
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(scene_viewport, false, INTERNAL_MODE_FRONT)

	gbuffer_viewport = SubViewport.new()
	gbuffer_viewport.name = "GBufferViewport"
	gbuffer_viewport.world_3d = _world
	gbuffer_viewport.use_hdr_2d = true
	gbuffer_viewport.msaa_3d = Viewport.MSAA_DISABLED
	gbuffer_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gbuffer_viewport, false, INTERNAL_MODE_FRONT)

	_gbuffer_camera = Camera3D.new()
	# Its transform is copied every frame; interpolating it would lag the scene camera.
	_gbuffer_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_gbuffer_camera.cull_mask = GBUFFER_LAYER if compat else 0xFFFFF & ~LIGHT_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Compatibility: the twins write the g-buffer and the clear colour is the
	# background (depth exactly 1.0); Forward+: the quad writes every pixel.
	env.background_color = Color(0.5, 0.5, 1.0) if compat else Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	_gbuffer_camera.environment = env
	gbuffer_viewport.add_child(_gbuffer_camera)
	_gbuffer_camera.current = true

	_gbuffer_material = ShaderMaterial.new()
	if not compat:
		_gbuffer_material.shader = load(GBUFFER_SHADER_PATH)
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	var quad := MeshInstance3D.new()
	quad.mesh = quad_mesh
	quad.material_override = _gbuffer_material
	quad.layers = GBUFFER_LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	quad.extra_cull_margin = 16384.0
	quad.position = Vector3(0.0, 0.0, -1.0)
	if compat:
		quad.free()
		_gbuffer_twin_material = ShaderMaterial.new()
		_gbuffer_twin_material.shader = GBUFFER_TWIN_SHADER
		get_tree().node_added.connect(_on_node_added)
	else:
		_gbuffer_camera.add_child(quad)

	cell_viewport = SubViewport.new()
	cell_viewport.name = "CellViewport"
	cell_viewport.disable_3d = true
	cell_viewport.transparent_bg = true
	cell_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	cell_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(cell_viewport, false, INTERNAL_MODE_FRONT)
	_cells_material = ShaderMaterial.new()
	_cells_material.shader = CELLS_SHADER
	_cells_material.set_shader_parameter("scene_tex", scene_viewport.get_texture())
	_cells_material.set_shader_parameter("gbuf_tex", gbuffer_viewport.get_texture())
	_cells_rect = ColorRect.new()
	_cells_rect.material = _cells_material
	cell_viewport.add_child(_cells_rect)

	output_viewport = SubViewport.new()
	output_viewport.name = "OutputViewport"
	output_viewport.disable_3d = true
	output_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(output_viewport, false, INTERNAL_MODE_FRONT)
	_compose_material = ShaderMaterial.new()
	_compose_material.shader = COMPOSE_SHADER
	_compose_material.set_shader_parameter("cell_tex", cell_viewport.get_texture())
	_compose_rect = ColorRect.new()
	_compose_rect.material = _compose_material
	output_viewport.add_child(_compose_rect)

	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer, false, INTERNAL_MODE_FRONT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	_display = TextureRect.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_display)

	atlas = GlyphAtlas.new()
	atlas.name = "GlyphAtlas"
	add_child(atlas, false, INTERNAL_MODE_BACK)
	atlas.built.connect(_on_atlas_built)


func _font() -> Font:
	return settings.font if settings.font != null else DEFAULT_FONT


func _rebuild_atlas() -> void:
	_atlas_key = [_font(), settings.glyph_px, settings.charset]
	atlas.build(_font(), settings.glyph_px, settings.charset)


func _on_settings_changed() -> void:
	if _atlas_key != [_font(), settings.glyph_px, settings.charset]:
		_rebuild_atlas() # relayout happens when it is built
		return
	_apply_glyph_tables()
	_relayout()


func _on_atlas_built() -> void:
	_cells_material.set_shader_parameter("glyph_data", atlas.data_texture)
	_compose_material.set_shader_parameter("atlas_tex", atlas.texture)
	_compose_material.set_shader_parameter("atlas_cols", atlas.atlas_cols)
	_apply_glyph_tables()
	_relayout()
	atlas_ready.emit()


func _apply_glyph_tables() -> void:
	if not atlas.ready_to_use:
		return
	var m := _cells_material
	m.set_shader_parameter("ramp_lut", atlas.ramp_lut(settings.ramp_chars, RAMP_LUT_SIZE))
	m.set_shader_parameter("hatch_glyph", atlas.index_of(hatch_glyph))
	var edge := atlas.sorted_ramp(hatch_edge_chars)
	m.set_shader_parameter("hatch_edge_count", mini(edge.size(), HATCH_EDGE_MAX))
	edge.resize(HATCH_EDGE_MAX)
	m.set_shader_parameter("hatch_edge_glyphs", edge)
	var ramp := atlas.sorted_ramp(settings.ramp_chars)
	ramp.resize(RAMP_MAX)
	m.set_shader_parameter("ramp_glyphs", ramp)
	var cand := PackedInt32Array()
	if settings.shape_chars == "":
		for i in atlas.chars.length():
			cand.append(i)
	else:
		cand = atlas.sorted_ramp(settings.shape_chars) # unique, present in atlas, space included
	m.set_shader_parameter("shape_count", mini(cand.size(), SHAPE_MAX))
	cand.resize(SHAPE_MAX)
	m.set_shader_parameter("shape_glyphs", cand)


func _relayout() -> void:
	if not is_node_ready():
		return
	if fixed_output_size.x > 0 and fixed_output_size.y > 0:
		output_size = fixed_output_size
	else:
		output_size = Vector2i(get_viewport().get_visible_rect().size)
	output_size = output_size.max(Vector2i.ONE)

	var scale := 1.0 if raw_view else settings.scene_scale
	var scene_size := Vector2i((Vector2(output_size) * scale).round()).max(Vector2i.ONE)
	scene_viewport.size = scene_size
	gbuffer_viewport.size = scene_size
	if light_viewport != null:
		light_viewport.size = scene_size
	output_viewport.size = output_size
	_compose_rect.size = Vector2(output_size)
	_display.texture = scene_viewport.get_texture() if raw_view else output_viewport.get_texture()

	if not atlas.ready_to_use:
		return
	glyph_box = atlas.box
	pitch = Vector2i(
		maxi(1, roundi(glyph_box.x * settings.squeeze_x)),
		maxi(1, roundi(glyph_box.y * settings.squeeze_y)))
	cols = ceili(float(output_size.x) / pitch.x)
	rows = ceili(float(output_size.y) / pitch.y)
	cell_viewport.size = Vector2i(cols * SLOTS, rows)
	if _overlay != null:
		_overlay.resize(cols, rows)
		_overlay.clear()
		_cells_material.set_shader_parameter("overlay_tex", _overlay.texture)
	_cells_rect.size = Vector2(cell_viewport.size)

	var m := _cells_material
	m.set_shader_parameter("grid", Vector2i(cols, rows))
	m.set_shader_parameter("pitch_uv", Vector2(pitch) / Vector2(output_size))
	m.set_shader_parameter("exposure", settings.exposure)
	m.set_shader_parameter("contrast", settings.contrast)
	m.set_shader_parameter("gamma", settings.gamma)
	m.set_shader_parameter("color_mode", int(settings.color_mode))
	var mc := settings.mono_color
	m.set_shader_parameter("mono_ink", Vector3(mc.r, mc.g, mc.b))
	m.set_shader_parameter("color_boost", settings.color_boost)
	m.set_shader_parameter("bg_strength", settings.bg_strength)
	m.set_shader_parameter("shape_contrast", settings.shape_contrast)
	m.set_shader_parameter("shape_flat_threshold", settings.shape_flat_threshold)
	m.set_shader_parameter("shape_ink_penalty", settings.shape_ink_penalty)
	m.set_shader_parameter("shape_ramp_bias", settings.shape_ramp_bias)

	var c := _compose_material
	c.set_shader_parameter("grid", Vector2i(cols, rows))
	c.set_shader_parameter("pitch", pitch)
	c.set_shader_parameter("box", glyph_box)
	c.set_shader_parameter("out_size", Vector2(output_size))
	grid_changed.emit()


func _process(_delta: float) -> void:
	var cam := scene_viewport.get_camera_3d()
	if cam == null:
		return
	cam.cull_mask &= ~(GBUFFER_LAYER | LIGHT_LAYER)
	var g := _gbuffer_camera
	g.global_transform = cam.global_transform
	g.projection = cam.projection
	g.keep_aspect = cam.keep_aspect
	g.size = cam.size
	g.fov = cam.fov
	g.near = cam.near
	g.far = cam.far
	g.h_offset = cam.h_offset
	g.v_offset = cam.v_offset
	g.frustum_offset = cam.frustum_offset
	if shadow_hatch and _light_camera != null:
		var lc := _light_camera
		lc.cull_mask = LIGHT_LAYER
		lc.global_transform = cam.global_transform
		lc.projection = cam.projection
		lc.keep_aspect = cam.keep_aspect
		lc.size = cam.size
		lc.fov = cam.fov
		lc.near = cam.near
		lc.far = cam.far
		lc.h_offset = cam.h_offset
		lc.v_offset = cam.v_offset
		lc.frustum_offset = cam.frustum_offset
		# Anchor the hatch pattern to the world in ortho: with grid snap the
		# world origin sits at a fixed fraction of a cell, so its cell index
		# moves by whole cells and the hatching moves with the ground.
		var origin := Vector2i.ZERO
		if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			var c := cam.unproject_position(Vector3.ZERO) / Vector2(scene_viewport.size) * Vector2(output_size) / Vector2(pitch)
			origin = Vector2i(floori(c.x + 0.5), floori(c.y + 0.5))
		_cells_material.set_shader_parameter("hatch_origin", origin)

	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	_gbuffer_material.set_shader_parameter("far_plane", cam.far)
	if compat:
		_gbuffer_twin_material.set_shader_parameter("far_plane", cam.far)
		for m: ShaderMaterial in _gbuffer_twin_materials.values():
			m.set_shader_parameter("far_plane", cam.far)
		# Meshes swapped or hidden after their twin was made follow here.
		for k: Variant in _gbuffer_twins:
			var t: Variant = _gbuffer_twins[k]
			if is_instance_valid(k) and is_instance_valid(t) and (t as MeshInstance3D).mesh != (k as MeshInstance3D).mesh:
				(t as MeshInstance3D).mesh = (k as MeshInstance3D).mesh
	_cells_material.set_shader_parameter("far_plane", cam.far)
	var fade := Vector2.ZERO if ortho or sky_enabled else distance_fade
	_cells_material.set_shader_parameter("fade_begin", fade.x)
	_cells_material.set_shader_parameter("fade_end", fade.y)
	var ov := overlay_enabled and _overlay != null and not raw_view
	_cells_material.set_shader_parameter("overlay_on", ov)
	if ov:
		_overlay.commit()
