## `--attracttest=<dir>`: checks attract mode with injected input and writes
## results.txt plus a few screenshots into <dir>, then quits. Run in real time
## (no --fixed-fps) so the frame rate it reports is meaningful.
##   - fps during the reel
##   - each kind of press starts the game (key, pad button, trigger, F1) and does
##     nothing else (Q must not switch the camera, F1 must not open the panel,
##     A must not hold the handbrake)
##   - the game starts on the grid at rest, iso camera, HUD on, overlay off
##   - Esc opens the pause menu (game paused); its "to title" item returns to
##     the reel and the logo plays again
##   - in the reel, Esc and pad Start open the menu instead of starting a race,
##     B / Esc close it back to the reel, and M (mute) does not start a race
class_name AttractTest
extends Node

var game: Node
var out_dir: String = ""
var _log: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	# The start lights are checked by the drive test; --countdown keeps them on
	# here to check the reel's way in and out with them.
	game.countdown_enabled = OS.get_cmdline_user_args().has("--countdown")
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
	return "attract %s, player_input %s, car %.2f from the grid at %.2f u/s, handbrake %s, camera %s, chase_view %s, HUD %s, panel open %s, overlay %s, lap started %s, lights %s, held %s, beeping %s" % [
		game.attract.active, car.player_input, car.global_position.distance_to(grid.origin), car.linear_velocity.length(),
		car.handbrake_input, "iso" if cam == game.camera else cam.get_class(), game.chase_view, game.controls.hud.visible,
		game.panel.is_open, game.renderer.overlay_enabled, game.laps.started,
		game.race_start.counting, car.freeze, game.race_start._beep.playing or game.race_start._go.playing]


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
		await _wait(0.3)
		var menu: PauseMenu = game.pause_menu
		var menu_open := menu.is_open and get_tree().paused
		var items: Array = menu.items.map(func(it: int) -> String: return PauseMenu.LABELS[it])
		if i == 0:
			await _shot("03b_pause_menu.png")
		# Up from the top wraps to QUIT, once more is TO TITLE; Enter chooses it.
		for k in 2:
			_key(KEY_UP, true)
			_key(KEY_UP, false)
			await _wait(0.05)
		var chosen: String = PauseMenu.LABELS[menu.items[menu.selected]]
		_key(KEY_ENTER, true)
		_key(KEY_ENTER, false)
		await _wait(0.6)
		_line("  Esc: menu open and paused %s %s; chose %s: back to the reel %s, logo restarted (reel time %.2f s), %s" % [menu_open, items, chosen, a.active, a._t, _state()])
		if i == 0:
			await _wait(1.0)
			await _shot("04_reel_again.png")
		await _wait(1.0)
	# In the reel: Esc opens the menu (no race), Esc closes it; pad Start opens,
	# B closes; M toggles the mute without starting a race.
	var menu2: PauseMenu = game.pause_menu
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _wait(0.3)
	var r1 := "Esc in the reel: menu %s %s, still in the reel %s" % [menu2.is_open, menu2.items.map(func(it: int) -> String: return PauseMenu.LABELS[it]), a.active]
	await _shot("05_reel_menu.png")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _wait(0.3)
	r1 += "; Esc closes %s (paused %s, reel %s)" % [not menu2.is_open, get_tree().paused, a.active]
	_button(JOY_BUTTON_START, true)
	_button(JOY_BUTTON_START, false)
	await _wait(0.3)
	r1 += "; pad Start opens %s" % menu2.is_open
	_button(JOY_BUTTON_B, true)
	_button(JOY_BUTTON_B, false)
	await _wait(0.3)
	r1 += ", B closes %s, reel %s" % [not menu2.is_open, a.active]
	var muted0: bool = game.audio.muted
	_key(KEY_M, true)
	_key(KEY_M, false)
	await _wait(0.3)
	r1 += "; M: muted %s -> %s, still in the reel %s" % [muted0, game.audio.muted, a.active]
	_key(KEY_M, true)
	_key(KEY_M, false)
	await _wait(0.2)
	_line(r1)
	var f := FileAccess.open(out_dir.path_join("results.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\n")
	f.close()
	game.audio.quit()
