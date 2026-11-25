## Demo controller: keyboard controls, HUD and the `--capture=<dir>` mode.
extends Node

const CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
const CAPTURE_ANGLE_DEG: float = 240.0
const CAPTURE_SPIN: float = 0.6
const CAPTURE_SQUEEZES: Array[float] = [1.0, 0.7]

@onready var renderer: AsciiRenderer = $AsciiRenderer
# The renderer moves its children into its SceneViewport during its own _ready.
@onready var world: Node3D = renderer.scene_viewport.get_node("World")

var _controls: AsciiControls
var _capture_dir: String = ""
## Capture only files whose name contains this (empty = all).
var _capture_only: String = ""
## Interactive-mode smoke test: run, resize the window, save it, quit.
var _selftest_path: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--only="):
			_capture_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--selftest="):
			_selftest_path = arg.trim_prefix("--selftest=")
		elif arg.begins_with("--set="):
			# --set=<AsciiSettings property>=<value>, e.g. --set=contrast=1.2
			var kv := arg.trim_prefix("--set=").split("=", true, 1)
			if kv.size() == 2 and kv[0] in renderer.settings:
				var cur: Variant = renderer.settings.get(kv[0])
				renderer.settings.set(kv[0], kv[1] if cur is String else str_to_var(kv[1]))
			else:
				push_warning("ignoring " + arg)
	_controls = AsciiControls.new()
	_controls.renderer = renderer
	_controls.keys_text = "Space pause   " + Lighting.SUN_KEYS_HELP
	add_child(_controls)
	_controls.zoom_requested.connect(func(step: int) -> void: world.zoom_index += step)
	world.lighting.renderer = renderer
	world.lighting.set_mode(world.lighting.mode) # again, now that it can reach the renderer
	_controls.mode_requested.connect(func(i: int) -> void: world.lighting.set_mode(i))
	world.lighting.changed.connect(func() -> void: _controls.mode_text = world.lighting.describe())
	_controls.mode_text = world.lighting.describe()
	renderer.grid_changed.connect(_log_grid)
	if _capture_dir != "":
		_run_capture()
	elif _selftest_path != "":
		_run_selftest()


var _last_grid: String = ""


func _log_grid() -> void:
	var g := "grid %dx%d pitch %s output %s" % [renderer.cols, renderer.rows, renderer.pitch, renderer.output_size]
	if g != _last_grid:
		_last_grid = g
		print(g)


func _run_selftest() -> void:
	for i in 120:
		await get_tree().process_frame
	get_window().size = Vector2i(1100, 700)
	for i in 60:
		await get_tree().process_frame
	# Live changes: atlas rebuild (glyph size), squeeze, lighting mode.
	renderer.settings.glyph_px = 12
	world.lighting.set_mode(4) # hatched
	_controls.set_squeeze(0.8, 0.75)
	await renderer.atlas_ready
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_selftest_path)
	await _controls.screenshot()
	print("selftest window=%s grid=%dx%d fps=%d -> %s" % [get_window().size, renderer.cols, renderer.rows,
		Engine.get_frames_per_second(), _selftest_path])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _capture_dir != "":
		return
	if k.keycode == KEY_SPACE:
		world.paused = not world.paused
		get_viewport().set_input_as_handled()


func _settle() -> void:
	for i in 6:
		await RenderingServer.frame_post_draw


func _run_capture() -> void:
	_controls.hud.visible = false
	_controls.enabled = false
	world.paused = true
	world.set_pose(CAPTURE_ANGLE_DEG, CAPTURE_SPIN)
	renderer.fixed_output_size = CAPTURE_SIZE
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	if not renderer.is_atlas_ready():
		await renderer.atlas_ready
	var s := renderer.settings
	await _settle()
	_print_data_check()
	var zooms := {"default": world.ZOOM_DEFAULT, "close": world.ZOOM_CLOSE}
	for zname: String in zooms:
		world.zoom_index = zooms[zname]
		renderer.raw_view = true
		await _settle()
		_save("%s_0_raw3d.png" % zname)
		renderer.raw_view = false
		for sq in CAPTURE_SQUEEZES:
			s.squeeze_x = sq
			s.squeeze_y = sq
			for m in Lighting.MODES.size():
				world.lighting.set_mode_frozen(m)
				await _settle()
				_save("%s_sq%03d_%d_%s.png" % [zname, roundi(sq * 100.0), m + 1, String(Lighting.MODES[m].name).replace(" ", "-")])
				if OS.get_cmdline_user_args().has("--rawmodes") and sq == CAPTURE_SQUEEZES[0]:
					# The 3D scene itself per mode (for comparing renderers).
					renderer.raw_view = true
					await _settle()
					_save("%s_raw_%d_%s.png" % [zname, m + 1, String(Lighting.MODES[m].name).replace(" ", "-")])
					renderer.raw_view = false
					await _settle()
			world.lighting.set_mode(0)
			world.lighting.sweep_running = true
	print("capture done: ", _capture_dir)
	get_tree().quit()


## Sanity check of the intermediate buffers, printed in capture mode: gbuffer
## format and values at a few points, and that cell glyph indices decode exactly.
func _print_data_check() -> void:
	if OS.get_cmdline_user_args().has("--dump"):
		renderer.scene_viewport.get_texture().get_image().save_png(_capture_dir.path_join("dump_scene.png"))
		renderer.cell_viewport.get_texture().get_image().save_png(_capture_dir.path_join("dump_cells.png"))
		var gi := renderer.gbuffer_viewport.get_texture().get_image()
		gi.convert(Image.FORMAT_RGBA8)
		gi.save_png(_capture_dir.path_join("dump_gbuffer.png"))
	var g := renderer.gbuffer_viewport.get_texture().get_image()
	print("gbuffer format=%d size=%s" % [g.get_format(), g.get_size()])
	for p: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.5, 0.48), Vector2(0.95, 0.95)]:
		var c := g.get_pixelv(Vector2i(p * Vector2(g.get_size())))
		var nx := c.r * 2.0 - 1.0
		var ny := c.g * 2.0 - 1.0
		print("  gbuf uv=%s n=(%.3f, %.3f, %.3f) depth=%.4f (%.2f world)" % [p, nx, ny,
			sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny)), c.b, c.b * world.camera.far])
	var cells := renderer.cell_viewport.get_texture().get_image()
	var bad := 0
	var hist := {}
	for y in cells.get_height():
		for x in cells.get_width():
			if x % AsciiRenderer.SLOTS == 2:
				continue
			var a := cells.get_pixel(x, y).a * 255.0
			if absf(a - roundf(a)) > 0.01 or roundf(a) >= renderer.atlas.chars.length():
				bad += 1
			hist[int(roundf(a))] = hist.get(int(roundf(a)), 0) + 1
	print("cells format=%d size=%s bad_indices=%d distinct_glyphs=%d" % [cells.get_format(), cells.get_size(), bad, hist.size()])


func _save(file: String) -> void:
	if _capture_only != "" and not file.contains(_capture_only):
		return
	var path := _capture_dir.path_join(file)
	var err := renderer.get_output_image().save_png(path)
	print("captured ", path, " (", renderer.cols, "x", renderer.rows, ")" if err == OK else ") ERROR %d" % err)


func _process(delta: float) -> void:
	if _controls != null and _controls.enabled:
		world.lighting.update_sun_keys(delta)
		_controls.mode_text = world.lighting.describe()
