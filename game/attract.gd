## Attract mode: the demo reel the game opens on. The car drives itself
## (DemoDriver), the ShotDirector cuts between camera shots, the ASCII RACER
## logo plays in and the prompt blinks, all drawn in the renderer's overlay
## cell layer. Any key, button or trigger starts the game (that press does
## nothing else); Esc in the game comes back here.
##
## --attractshots=<dir> [--attractsize=WxH]: from a cold start, saves the
## ASCII output every SHOT_INTERVAL through the logo, then every
## SHOT_INTERVAL_REEL until REEL_SECONDS, and quits.
class_name Attract
extends Node

signal started_game

## Glyph wipe used for the start of the game, the reel and quiet resets.
const WIPE_TIME: float = 0.5
const WIPE_GLYPHS: String = "#%@&$*+=:/\\|"
const WIPE_INK: Color = Color("ff8a1f")
const SHOT_INTERVAL: float = 0.25
const SHOT_INTERVAL_REEL: float = 0.5
const LOGO_SHOTS_UNTIL: float = 8.0
const REEL_SECONDS: float = 44.0

var game: Node
var active: bool = false
var logo := AsciiLogo.new()
var driver: DemoDriver
var director: ShotDirector
var cine: CineCamera

var _t: float = 0.0 ## seconds since the reel started
var _overlay: AsciiOverlay
var _wipe: float = -1.0 ## 0..1 while wiping, -1 otherwise
var _wipe_mid: Callable = Callable()
var _wipe_mid_done: bool = false
var _rumble_was: bool = true
## The player's handling (preset name and every value) while the reel drives
## the balanced setup it is tuned for.
var _player_preset: String = ""
var _player_values: Dictionary = {}
## The reel always drives this preset.
const REEL_PRESET: String = "balanced"
var _capture_dir: String = ""


func _ready() -> void:
	process_priority = 95 # after the director, before the renderer
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--attractshots="):
			_capture_dir = arg.trim_prefix("--attractshots=")
		elif arg.begins_with("--attractsize="):
			var wh := arg.trim_prefix("--attractsize=").split("x")
			game.renderer.fixed_output_size = Vector2i(int(wh[0]), int(wh[1]))
	game.level_select.start_requested.connect(_on_select_start)
	game.level_select.back_requested.connect(_on_select_back)
	cine = CineCamera.new()
	cine.target = game.car
	game.world.add_child(cine)
	if _capture_dir != "":
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_capture.call_deferred()


## Enters the reel. `cold` = straight away (game start), otherwise via a wipe
## (coming back from a race or the level select: the reel always runs on track 1
## in the default lighting).
func start(cold: bool) -> void:
	if cold:
		_enter()
	else:
		_wipe_to(func() -> void:
			if game.level_select.active:
				game.level_select.close()
			game.set_track(Tracks.DEFAULT_ID)
			game.lighting.set_mode(Lighting.DEFAULT_MODE)
			_enter())


func _enter() -> void:
	active = true
	_t = 0.0
	var g := game
	g.car.player_input = false
	g.controls.hud.visible = false
	g.controls.enabled = false
	g.panel.set_open(false)
	g.panel.enabled = false
	_rumble_was = g.rumble.enabled
	g.rumble.set_enabled(false)
	_player_preset = g.tuning.current
	_player_values = g.tuning.capture()
	g.tuning.select(REEL_PRESET)
	g.car.nitro_enabled = false # the reel's driver does not use it
	g.race_start.cancel() # no start lights in the reel
	g.remove_opponent() # the reel is solo
	g.car.nitro_input = false
	g.car.teleport(g.world.grid_pose())
	g.laps.reset()
	_overlay = g.renderer.get_overlay()
	logo.overlay = _overlay
	logo.atlas = g.renderer.atlas
	logo.pitch = g.renderer.pitch
	if driver == null:
		driver = DemoDriver.new()
		driver.car = g.car
		driver.track = g.track
		add_child(driver)
		driver.reset_requested.connect(_quiet_reset)
	driver.restart()
	if director == null:
		director = ShotDirector.new()
		director.game = g
		director.car = g.car
		director.track = g.track
		director.iso = g.camera
		director.chase = g.chase
		director.cine = cine
		director.renderer = g.renderer
		add_child(director)
	director.hold = true
	director.reset("chase") # the logo sits in the sky above the car
	g.chase_view = false


## True while the reel or a wipe owns the overlay (NitroHud leaves it alone).
func busy() -> bool:
	return active or _wipe >= 0.0 or game.level_select != null and game.level_select.active


## Leaves the reel for the level select, then (START) the game: car on the
## grid at rest, iso camera, HUD on.
func start_game() -> void:
	if not active:
		return
	active = false
	_wipe_to(_open_select)


## From a race (the pause menu's CHANGE TRACK): back to the level select.
func change_track() -> void:
	_wipe_to(func() -> void:
		game.race_start.cancel()
		game.remove_opponent()
		game.car.player_input = false
		game.controls.enabled = false
		game.panel.set_open(false)
		game.panel.enabled = false
		game.level_select.open())


func _open_select() -> void:
	if driver != null:
		driver.queue_free()
		driver = null
	if director != null:
		director.queue_free()
		director = null
	game.level_select.open()


func _on_select_start() -> void:
	_wipe_to(func() -> void:
		game.level_select.close()
		_begin_play())


func _on_select_back() -> void:
	start(false)


func _begin_play() -> void:
	var g := game
	if driver != null:
		driver.queue_free()
		driver = null
	if director != null:
		director.queue_free()
		director = null
	var car: Car = g.car
	car.steer_input = 0.0
	car.throttle_input = 0.0
	car.brake_input = 0.0
	car.handbrake_input = false
	g.car.apply_tuning(_player_values)
	g.tuning.current = _player_preset
	g.car.nitro_enabled = true
	g.race_start.tip_pending = true # the camera tip before this game's first lights
	g.reset_to_grid()
	g.update_opponent(true)
	g.set_chase_view(false)
	g.controls.hud.visible = false # minimised; its legend shows in the corner
	g.controls.enabled = true
	g.panel.enabled = true
	g.rumble.set_enabled(_rumble_was)
	car.player_input = true
	started_game.emit()


func _quiet_reset() -> void:
	_wipe_to(func() -> void:
		game.reset_car()
		driver.restart())


## Covers the screen with a glyph wipe, calls `mid` when it is covered, uncovers.
func _wipe_to(mid: Callable) -> void:
	_wipe = 0.0
	_wipe_mid = mid
	_wipe_mid_done = false
	_overlay = game.renderer.get_overlay()


## Any key, button or trigger press starts the game; the press is consumed.
func _input(event: InputEvent) -> void:
	if not active or _capture_dir != "":
		return
	var go := false
	if event is InputEventKey:
		# Esc opens the menu (PauseMenu), M mutes: neither starts a race.
		go = event.pressed and not event.echo and event.keycode != KEY_ESCAPE and event.keycode != KEY_M
		if event.pressed and not event.echo and event.keycode == KEY_M:
			game.audio.toggle_mute()
			game.audio.save_settings()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		go = event.pressed and event.button_index != JOY_BUTTON_START
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		go = (m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT) and m.axis_value > 0.5
	elif event is InputEventMouseButton:
		go = event.pressed
	if go:
		get_viewport().set_input_as_handled()
		start_game()


func _process(delta: float) -> void:
	if _overlay == null:
		return
	_overlay.clear()
	if active:
		_t += delta
		if director != null and director.hold and _t > AsciiLogo.HOLD_END:
			director.hold = false
		logo.pitch = game.renderer.pitch
		logo.draw(_t)
		logo.draw_title(clampf((_t - AsciiLogo.TITLE_IN) / 0.5, 0.0, 1.0))
		logo.draw_prompt(_t - AsciiLogo.PROMPT_IN)
	if _wipe >= 0.0:
		_wipe += delta / WIPE_TIME
		if _wipe >= 0.5 and not _wipe_mid_done:
			_wipe_mid_done = true
			if _wipe_mid.is_valid():
				_wipe_mid.call()
		_draw_wipe(minf(_wipe, 1.0))
		if _wipe >= 1.0:
			_wipe = -1.0
	if not active and _wipe < 0.0:
		_overlay.clear()
		game.renderer.overlay_enabled = false


## A diagonal band of glyphs sweeps across: first covering the screen (0..0.5),
## then uncovering it (0.5..1).
func _draw_wipe(w: float) -> void:
	var cols := _overlay.cols
	var rows := _overlay.rows
	var covering := w < 0.5
	var front := (w * 2.0 if covering else w * 2.0 - 1.0) * 1.4 - 0.2
	var band := 0.12
	for y in rows:
		for x in cols:
			var d := float(x) / cols + 0.2 * float(y) / rows
			var behind := d < front - band
			var in_band := d >= front - band and d < front
			var covered := behind if covering else not (behind or in_band)
			if covered:
				_overlay.cover(x, y, 1.0)
			elif in_band:
				_overlay.cover(x, y, 1.0)
				var k := hash(x * 31 + y * 17 + int(w * 40.0)) % WIPE_GLYPHS.length()
				var f := (front - d) / band
				_overlay.put_char(x, y, WIPE_GLYPHS[k], WIPE_INK.lerp(Color("ffe45c"), f))


## Scripted capture of the reel (see the class doc).
func _capture() -> void:
	var r: AsciiRenderer = game.renderer
	if not r.is_atlas_ready():
		await r.atlas_ready
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if r.fixed_output_size == Vector2i.ZERO:
		r.fixed_output_size = Vector2i(1600, 900)
	var next := 0.0
	var n := 0
	var log := PackedStringArray()
	while _t < REEL_SECONDS:
		await RenderingServer.frame_post_draw
		if _t >= next:
			var file := "%03d_t%05.2f_%s.png" % [n, _t, director.shot if director else "-"]
			r.get_output_image().save_png(_capture_dir.path_join(file))
			log.append("%s  shot %s  s %.1f  speed %.2f  lap %d  fps %d" % [file, director.shot if director else "-",
				driver.progress if driver else -1.0, game.car.linear_velocity.length(), game.laps.lap, Engine.get_frames_per_second()])
			n += 1
			next += SHOT_INTERVAL if _t < LOGO_SHOTS_UNTIL else SHOT_INTERVAL_REEL
	var f := FileAccess.open(_capture_dir.path_join("frames.txt"), FileAccess.WRITE)
	f.store_string("\n".join(log) + "\n")
	f.close()
	game.audio.quit()
