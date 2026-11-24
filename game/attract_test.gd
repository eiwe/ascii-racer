## `--attracttest=<dir>`: checks attract mode with injected input and writes
## results.txt plus a few screenshots into <dir>, then quits. Run in real time
## (no --fixed-fps) so the frame rate it reports is meaningful.
##   - fps during the reel
##   - each kind of press starts the game (key, pad button, trigger, F1) and does
##     nothing else (Q must not switch the camera, F1 must not open the panel,
##     A must not hold the handbrake)
##   - the game starts on the grid at rest, iso camera, HUD on, overlay off
##   - Esc returns to the reel and the logo plays again
class_name AttractTest
extends Node

var game: Node
var out_dir: String = ""
var _log: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _line(s: String) -> void:
	print(s)
	_log.append(s)


func _wait(seconds: float) -> void:
	var t := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < t:
		await get_tree().process_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _button(b: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = pressed
	Input.parse_input_event(e)


func _axis(a: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	game.renderer.get_output_image().save_png(out_dir.path_join(file))


func _state() -> String:
	var car: Car = game.car
	var grid: Transform3D = game.world.grid_pose()
	var cam: Camera3D = game.renderer.scene_viewport.get_camera_3d()
	return "attract %s, player_input %s, car %.2f from the grid at %.2f u/s, handbrake %s, camera %s, chase_view %s, HUD %s, panel open %s, overlay %s, lap started %s" % [
		game.attract.active, car.player_input, car.global_position.distance_to(grid.origin), car.linear_velocity.length(),
		car.handbrake_input, "iso" if cam == game.camera else cam.get_class(), game.chase_view, game.controls.hud.visible,
		game.panel.is_open, game.renderer.overlay_enabled, game.laps.started]


func _run() -> void:
	var a: Attract = game.attract
	_line("attract test: %s" % ("reel running" if a.active else "NOT IN ATTRACT MODE"))
	# Frame rate with vsync off (what the reel costs), at a few points.
	var vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var samples := PackedStringArray()
	for t: float in [1.0, 3.0, 5.0, 8.0, 12.0]:
		while a._t < t:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for i in 60:
			await get_tree().process_frame
		samples.append("%.0f s: %.0f" % [t, 60.0 / ((Time.get_ticks_usec() - t0) / 1e6)])
	DisplayServer.window_set_vsync_mode(vsync)
	_line("fps during the reel, vsync off (window %s, output %s): %s" % [get_window().size, game.renderer.output_size, ", ".join(samples)])
	await _wait(1.0)
	_line("fps with vsync as configured: %d" % Engine.get_frames_per_second())
	await _shot("01_reel.png")

	var presses := [
		["key Q", func(p: bool) -> void: _key(KEY_Q, p)],
		["pad A", func(p: bool) -> void: _button(JOY_BUTTON_A, p)],
		["right trigger", func(p: bool) -> void: _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9 if p else 0.0)],
		["key F1", func(p: bool) -> void: _key(KEY_F1, p)],
	]
	for i in presses.size():
		var name: String = presses[i][0]
		var press: Callable = presses[i][1]
		press.call(true)
		await _wait(0.25)
		if i == 0:
			await _shot("02_wipe.png")
		await _wait(0.1)
		press.call(false)
		await _wait(0.6)
		_line("%s starts the game: %s" % [name, _state()])
		if i == 0:
			await _shot("03_game.png")
			# Drive off a little, then Esc back to the reel.
			_key(KEY_W, true)
			await _wait(1.0)
			_key(KEY_W, false)
		_key(KEY_ESCAPE, true)
		_key(KEY_ESCAPE, false)
		await _wait(0.6)
		_line("  Esc: back to the reel %s, logo restarted (reel time %.2f s), %s" % [a.active, a._t, _state()])
		if i == 0:
			await _wait(1.0)
			await _shot("04_reel_again.png")
		await _wait(1.0)
	var f := FileAccess.open(out_dir.path_join("results.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\n")
	f.close()
	get_tree().quit()
