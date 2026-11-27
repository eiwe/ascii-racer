## Game controller: driving HUD with telemetry, lap timer, car reset, handling
## presets and the tuning panel, pad rumble, the iso / chase camera switch (Q,
## pad B), lighting modes (keys 1-9, the sun on J L I K), the G (grid snap)
## and V (rumble) keys, the see-through halo in the bridge,
## attract mode (the demo reel it opens on; Esc returns to it), and the
## `--drivetest=<dir>` scripted test mode.
##   --play                     start in the game, skipping the reel
##   --lighting=<name|1-9>      start in this lighting mode (default 1 sunset)
##   --track=<id>               start on this track (with --play; default: the saved one)
##   --time=<morning|noon|night>   its time of day (with --play; default: the track's saved one)
##   --preset=<name>            start with this handling preset
##   --tune=prop=value,...      then override single tunables (quick experiments)
##   --attractshots=<dir>       capture the reel (see Attract)
##   --attracttest=<dir>        check starting and leaving the reel (see AttractTest)
extends Node

const DRIVE_KEYS: String = """Keys  WASD drive (arrows too while tuning is closed)  Space handbrake
      Shift nitro  R reset  Q camera  G grid snap  V rumble  F1 tuning  F2 F3 preset  F5 save
      1-9 lighting  J L swing sun  I K raise / lower sun (moon at night; not in classic)
      Esc menu  M mute
Pad   L-stick steer  RT throttle  LT brake  A handbrake  L-stick click nitro  Y reset  B camera
      R-stick look (chase)  Start menu  Back tuning  LB RB preset  R-stick click save"""
## How often the last on-track position is remembered for R.
const SAFE_POSE_INTERVAL: float = 0.25
const FLASH_TIME: float = 1.5
## Default glyph size at a display scale of 2 (a Retina Mac, Windows at 200 %);
## at 1 it is AsciiSettings.glyph_px (9). Between 1 and 2 it is interpolated,
## above 2 it grows in proportion (glyph_default_for).
const RETINA_GLYPH_PX: int = 20
## Web build: default glyph size at a device pixel ratio of 2 (the page is drawn
## in device pixels), and at 1. Web glyphs are a little larger than desktop ones.
const WEB_HIDPI_GLYPH_PX: int = 22
const WEB_GLYPH_PX: int = 12
## The default never puts more text rows than this on the screen's full height
## in device pixels, whatever scale the screen reports (a 4K monitor at 100 %
## reports 1): the owner's 9 px desktop and 12 px web glyphs on a 1440-high
## screen.
const MAX_ROWS_DESKTOP: int = 160
const MAX_ROWS_WEB: int = 120

@onready var renderer: AsciiRenderer = $AsciiRenderer
# The renderer moves its children into its SceneViewport during its own _ready.
@onready var world: Node3D = renderer.scene_viewport.get_node("World")

var controls: AsciiControls
var lighting: Lighting
var laps: LapTimer
var car: Car
var track: Track
var camera: FollowCamera
var tuning: CarTuning
var panel: TuningPanel
var rumble: PadRumble
var chase: ChaseCamera
## true = rear chase view, false = isometric (the default).
var chase_view: bool = false
## Chase view: far geometry dissolves into the void over this depth range.
const CHASE_FADE: Vector2 = Vector2(12.0, 32.0)
var chase_fade: bool = true
var attract: Attract
var nitro_hud: NitroHud
var audio: AudioDirector
var car_audio: CarAudio
var pause_menu: PauseMenu
## The AI opponent while it is on and a race is played (null otherwise).
var opponent: Opponent
## The start lights (every start from the grid). Scripted tests turn them off.
var race_start: RaceStart
var countdown_enabled: bool = true
## Web only, until the first key or click: the start screen that lets the
## browser switch on sound before the reel (see WebStart).
var web_start: WebStart
## Between the reel and a race (see LevelSelect).
var level_select: LevelSelect
## The eased move between the iso and chase views (see ViewBlend).
var view_blend: ViewBlend
## Phone only (Mobile.active()): tilt steering and the touch buttons.
var tilt: TiltInput
var touch: TouchControls
var phone_assist: PhoneAssist

var _safe_pose: Transform3D
var _safe_timer: float = 0.0
var _halo_light: OmniLight3D
var _halo_light_level: float = 0.0
var _under_cover: bool = false
var _cover_ray := PhysicsRayQueryParameters3D.new()
var _pad_text: String = ""
var _flash: String = ""
var _flash_timer: float = 0.0


func _ready() -> void:
	# Smooth motion between physics ticks (the car moves at 120 Hz). Scene-local,
	# so the demo is unaffected.
	get_tree().physics_interpolation = true
	car = world.car
	track = world.track
	camera = world.camera
	camera.renderer = renderer
	camera.snap_to_target()
	laps = LapTimer.new(track)
	laps.lap_completed.connect(_on_lap)
	_safe_pose = world.grid_pose()

	# The default glyph size follows the display (9 px glyphs are too small to
	# read as characters on a dense screen).
	_scripted = scripted_run()
	_display_scale = AsciiControls.display_scale()
	_display_default = default_glyph_px()
	renderer.settings.glyph_px = _display_default

	controls = AsciiControls.new()
	controls.renderer = renderer
	controls.keys_text = DRIVE_KEYS
	add_child(controls)
	controls.zoom_requested.connect(_on_zoom)
	# The web build's g-buffer (Compatibility renderer) must cut the bridge's halo too.
	renderer.gbuffer_twin_shaders[HaloOccluder.SHADER] = preload("res://game/shaders/halo_gbuffer.gdshader")
	lighting = world.lighting
	lighting.renderer = renderer
	lighting.set_mode(lighting.mode) # again, now that it can reach the renderer (sky, hatching)
	controls.mode_requested.connect(func(i: int) -> void:
		lighting.set_mode(i)
		flash("lighting %d %s" % [i + 1, lighting.mode_name()]))
	chase = world.chase
	view_blend = ViewBlend.new()
	view_blend.name = "ViewBlend"
	view_blend.iso = camera
	view_blend.chase = chase
	world.add_child(view_blend)
	view_blend.finished.connect(func(on: bool) -> void: set_chase_view(on))
	_halo_light = OmniLight3D.new()
	_halo_light.name = "HaloLight"
	_halo_light.shadow_enabled = false
	_halo_light.omni_range = HALO_LIGHT_RANGE
	_halo_light.light_energy = 0.0
	_halo_light.visible = false
	world.add_child(_halo_light)
	_cover_ray.collision_mask = Track.LAYER_SURFACE
	_cover_ray.exclude = [car.get_rid()]

	tuning = CarTuning.new(car)
	panel = TuningPanel.new()
	panel.tuning = tuning
	panel.car = car
	add_child(panel)
	panel.preset_changed.connect(func(p: String) -> void: flash("preset " + p))
	panel.saved.connect(func(path: String) -> void: flash("saved custom" if path != "" else "SAVE FAILED"))
	rumble = PadRumble.new()
	rumble.car = car
	add_child(rumble)
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _update_pad_text())
	_update_pad_text()

	# Paused (the menu): the renderer keeps drawing (the menu is in its overlay),
	# the world under it stops.
	renderer.process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	# A glyph size the player chose (saved with the settings) replaces the
	# platform default; scripted runs keep the default so their output does not
	# depend on the settings file. (The phone has its own size: rows.)
	if Mobile.active():
		_display_default = default_glyph_px()
		renderer.settings.glyph_px = _display_default
	elif not _scripted and audio.glyph_px > 0:
		renderer.settings.glyph_px = chosen_glyph_px()
	controls.glyph_size_changed.connect(_on_glyph_size_changed)
	car_audio = CarAudio.new()
	car_audio.name = "CarAudio"
	car_audio.car = car
	car_audio.table = audio.table
	car_audio.director = audio
	add_child(car_audio)
	pause_menu = PauseMenu.new()
	pause_menu.game = self
	pause_menu.renderer = renderer
	pause_menu.audio = audio
	add_child(pause_menu)
	# The debug HUD's legend stays out of the menu (the game is paused under it,
	# so _process below does not run until it closes).
	pause_menu.opened.connect(func() -> void:
		controls.legend_allowed = false
		controls.legend.visible = false)

	level_select = LevelSelect.new()
	level_select.name = "LevelSelect"
	level_select.game = self
	add_child(level_select)

	race_start = RaceStart.new()
	race_start.name = "RaceStart"
	race_start.game = self
	add_child(race_start)

	nitro_hud = NitroHud.new()
	nitro_hud.game = self
	nitro_hud.car = car
	nitro_hud.renderer = renderer
	add_child(nitro_hud)

	if Mobile.active():
		_setup_mobile()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			tuning.select(arg.trim_prefix("--preset="))
		elif arg.begins_with("--lighting="):
			var li := Lighting.mode_index(arg.trim_prefix("--lighting="))
			if li < 0:
				push_warning("unknown lighting mode " + arg)
			else:
				lighting.set_mode(li)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tune="):
			for kv in arg.trim_prefix("--tune=").split(",", false):
				var p := kv.split("=")
				car.set_indexed(p[0], str_to_var(p[1]))
			car.refresh_tuning()
	var scripted := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--drivetest="):
			var test := DriveTest.new()
			test.game = self
			test.out_dir = arg.trim_prefix("--drivetest=")
			add_child(test)
			scripted = true
	if not scripted and OS.get_cmdline_user_args().has("--play"):
		# The saved track and its time of day (or --track= / --time=).
		var tid := audio.track_id
		var tod := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--track="):
				tid = arg.trim_prefix("--track=")
			elif arg.begins_with("--time="):
				tod = arg.trim_prefix("--time=")
		audio.select_track(Tracks.get_def(tid).id)
		set_track(audio.track_id)
		if not _lighting_arg():
			apply_time_of_day(tod if tod != "" else audio.track_time(audio.track_id))
		race_start.tip_pending = not Mobile.active() # the camera tip before the first lights
		reset_to_grid() # the start lights
		update_opponent(true)
		set_chase_view(start_in_chase())
	if not scripted and not OS.get_cmdline_user_args().has("--play"):
		attract = Attract.new()
		attract.game = self
		add_child(attract)
		nitro_hud.attract = attract
		if Mobile.active():
			attract.logo.prompt_text = "TAP TO START"
		if WebStart.needed():
			# The browser has not allowed sound yet: the first key or click
			# switches it on and then starts the reel (and its music) from the top.
			web_start = WebStart.new()
			web_start.game = self
			web_start.finished.connect(func() -> void:
				web_start = null
				attract.start(true))
			add_child(web_start)
		else:
			attract.start(true)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--attracttest="):
				var at := AttractTest.new()
				at.game = self
				at.out_dir = arg.trim_prefix("--attracttest=")
				add_child(at)


## Switches the world to track `id` (a Tracks id): the circuit and its scenery
## are rebuilt, the lap timer, the opponent and the safe pose follow. The car
## is not moved (reset_to_grid() does that).
func set_track(id: String) -> void:
	var def := Tracks.get_def(id)
	var had_opponent := opponent != null
	if had_opponent:
		remove_opponent()
	if not world.load_track(def):
		if had_opponent:
			update_opponent(false)
		return
	track = world.track
	laps = LapTimer.new(track)
	laps.lap_completed.connect(_on_lap)
	_safe_pose = world.grid_pose()
	if renderer.shadow_hatch:
		renderer._apply_shadow_hatch() # light twins for the new meshes


## Lights the world for a time of day ("morning", "noon", "night").
func apply_time_of_day(t: String) -> void:
	lighting.set_mode(Lighting.TIME_MODES.get(t, Lighting.TIME_MODES[AudioDirector.DEFAULT_TIME]))


func _lighting_arg() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lighting="):
			return true
	return false


## A lap was completed: kept as the track's best if it is.
func _on_lap(t: float) -> void:
	if audio.record_lap(world.track_def.id, t):
		flash("best lap %s" % LapTimer.fmt(t))


## Puts the car on the grid at rest with the lap timer reset (start of a game).
func reset_to_grid() -> void:
	_safe_pose = world.grid_pose()
	car.teleport(_safe_pose)
	car.refill_nitro()
	car_audio.reset()
	laps.reset()
	if opponent != null:
		opponent.to_grid() # side by side
	camera.snap_to_target()
	chase.snap_to_target()
	if countdown_enabled and (attract == null or not attract.active):
		race_start.start()


## Brings the opponent in line with the setting (AudioDirector.opponent_level):
## removes it when off; adds it when on (both cars back on the grid when
## `regrid`); a level change keeps both cars where they are.
func update_opponent(regrid: bool) -> void:
	var level := audio.opponent_level
	if level <= 0:
		remove_opponent()
		return
	if opponent == null:
		opponent = Opponent.new()
		opponent.name = "OpponentRace"
		opponent.game = self
		opponent.level = level
		add_child(opponent)
		if regrid:
			reset_to_grid()
	elif opponent.level != level:
		opponent.set_level(level)


func remove_opponent() -> void:
	if opponent != null:
		opponent.queue_free()
		remove_child(opponent)
		opponent = null


## , and . : iso zoom, or chase distance in the chase view.
func _on_zoom(step: int) -> void:
	if chase_view:
		chase.distance_scale *= pow(1.15, step)
	else:
		camera.zoom_index += step


## Switches between the isometric and the chase camera. The iso camera keeps
## following in the background, so switching back restores its framing (zoom,
## snapping, look-ahead) exactly as it would have been.
## Switches views at once (scripted runs, the reel); the player's camera key
## blends instead (blend_view).
func set_chase_view(on: bool) -> void:
	chase_view = on
	if view_blend.active:
		view_blend.cancel()
	lighting.fog_offset = 0.0
	if on:
		chase.current = true
		chase.snap_to_target()
	else:
		camera.current = true
	renderer.distance_fade = CHASE_FADE if on and chase_fade else Vector2.ZERO


## The view a race starts in: isometric, or on the phone the chase view unless
## the player chose the isometric one in the pause menu.
func start_in_chase() -> bool:
	return Mobile.active() and audio.phone_get("camera", "chase") != "iso"


## The player's view switch: an eased move (ViewBlend); pressing again mid-move reverses it.
func blend_view(on: bool) -> void:
	chase_view = on
	view_blend.start(on)


func _update_pad_text(pads: Array[int] = Input.get_connected_joypads()) -> void:
	_pad_text = "no gamepad" if pads.is_empty() else "pad: " + Input.get_joy_name(pads[0])


func flash(text: String) -> void:
	_flash = text
	_flash_timer = FLASH_TIME


## Height of the halo's target above the car's origin (about the middle of the car).
const HALO_TARGET_HEIGHT: float = 0.2
## A shadowless light that follows the car while it is under cover in the iso view.
const HALO_LIGHT_ENERGY: float = 1.4
const HALO_LIGHT_RANGE: float = 2.4
const HALO_LIGHT_HEIGHT: float = 0.9
const HALO_LIGHT_FADE: float = 5.0 ## per second


## The see-through halo in bridges and other occluders (HaloOccluder): follows
## the car, and only for the isometric camera; perspective cameras keep the car
## in view by themselves (line of sight).
func _update_halo(delta: float) -> void:
	var iso := renderer.scene_viewport.get_camera_3d() == camera
	var iso_w := 1.0 if iso else 0.0
	if view_blend.active:
		# Mid-switch: the halo shrinks away (or grows back) with the iso share,
		# and the chase view's fades sit as far behind the car as at the chase end.
		iso_w = 1.0 - view_blend.weight
		iso = iso_w > 0.5
		renderer.distance_fade = CHASE_FADE + Vector2.ONE * view_blend.extra_distance if chase_fade else Vector2.ZERO
		lighting.fog_offset = view_blend.extra_distance
	var origin := car.get_global_transform_interpolated().origin
	HaloOccluder.set_target(origin + Vector3.UP * HALO_TARGET_HEIGHT, HaloOccluder.RADIUS * iso_w)
	# Under cover the car sits in the occluder's shadow and would be a dim shape
	# in the hole: light it, and the patch of road around it, while it is there.
	_halo_light_level = move_toward(_halo_light_level, 1.0 if iso and _under_cover else 0.0, delta * HALO_LIGHT_FADE)
	_halo_light.visible = _halo_light_level > 0.01
	_halo_light.light_energy = HALO_LIGHT_ENERGY * _halo_light_level
	_halo_light.global_position = origin + Vector3.UP * HALO_LIGHT_HEIGHT


## True when a drivable surface (a bridge deck) is overhead. Physics frames only.
func _check_under_cover() -> void:
	var from := car.global_position + Vector3.UP * 0.6
	_cover_ray.from = from
	_cover_ray.to = from + Vector3.UP * 4.0
	_under_cover = not world.get_world_3d().direct_space_state.intersect_ray(_cover_ray).is_empty()


func _physics_process(delta: float) -> void:
	_check_under_cover()
	laps.update(car.global_position, delta)
	_safe_timer += delta
	if _safe_timer >= SAFE_POSE_INTERVAL:
		_safe_timer = 0.0
		if car.wheels_on_road == 4 and car.is_upright() and track.is_on_road(car.global_position, laps.progress):
			_safe_pose = track.pose_at(laps.progress, clampf(track.lateral_offset(car.global_position, laps.progress), -0.5, 0.5))
	if car.player_input and not race_start.counting and Input.is_action_just_pressed(&"reset_car"):
		reset_car()


## Puts the car back on the road at the last place it was safely on it.
func reset_car() -> void:
	car.teleport(_safe_pose)
	laps.resync()
	camera.snap_to_target()
	chase.snap_to_target()


var _display_log_t: float = -1.0
var _scripted: bool = false
var _display_scale: float = 1.0
var _display_default: int = 0
var _display_t: float = 0.0


## The default glyph size on this display (glyph_default_for). Scripted runs
## keep the fixed sizes their baselines were made with: 9 px, 20 px at scale 2.
func default_glyph_px() -> int:
	if Mobile.active():
		return Mobile.glyph_px(get_viewport().get_visible_rect().size.y, phone_rows())
	if _scripted:
		return RETINA_GLYPH_PX if AsciiControls.display_scale() >= 2.0 else AsciiSettings.new().glyph_px
	return glyph_default_for(OS.has_feature("web"), AsciiControls.display_scale(), DisplayServer.screen_get_size().y)


## The default glyph size for a display: by its scale (desktop 9 px at 1 and
## 20 at 2, web 12 and 22; interpolated between, in proportion above), but at
## least the screen height in device pixels over MAX_ROWS_DESKTOP / _WEB.
static func glyph_default_for(web: bool, scale: float, screen_h: int) -> int:
	var lo := WEB_GLYPH_PX if web else AsciiSettings.new().glyph_px
	var hi := WEB_HIDPI_GLYPH_PX if web else RETINA_GLYPH_PX
	var px := lo
	if scale > 2.0:
		px = roundi(hi * scale / 2.0)
	elif scale > 1.0:
		px = roundi(lerpf(lo, hi, scale - 1.0))
	if screen_h > 0:
		px = maxi(px, ceili(float(screen_h) / float(MAX_ROWS_WEB if web else MAX_ROWS_DESKTOP)))
	return clampi(px, 6, 64)


## The player's saved glyph size, kept the same physical size on this display:
## scaled by this display's scale over the one it was chosen at (24 px chosen
## on a 2x screen is 12 px on a 1x one), within 6..64 px. 0 if none is saved.
func chosen_glyph_px() -> int:
	if audio == null or audio.glyph_px <= 0:
		return 0
	return clampi(roundi(audio.glyph_px * AsciiControls.display_scale() / audio.glyph_scale), 6, 64)


## True for the scripted runs (drive test, reel checks, the movie writer used for
## the README media): they keep the default look whatever the settings file says.
static func scripted_run() -> bool:
	if Engine.get_write_movie_path() != "":
		return true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--drivetest=") or arg.begins_with("--attracttest=") or arg.begins_with("--attractshots="):
			return true
	return false


## - / = changed the glyph size: remember it (stepping back to the default
## forgets it, so a later change of the default still reaches this player).
func _on_glyph_size_changed(px: int) -> void:
	if Mobile.active():
		# A keyboard on the phone: kept as rows, like the menu's GLYPH SIZE.
		set_phone_rows(roundi(get_viewport().get_visible_rect().size.y / float(px)))
		return
	if px == default_glyph_px():
		audio.set_glyph_choice(0, 1.0)
	else:
		audio.set_glyph_choice(px, AsciiControls.display_scale())
	audio.save_settings()


## The display scale changes with browser zoom, Windows' scaling setting or a
## move to another monitor (which can also change the screen height). The text
## of the HUD, legend and tuning panel follows, and so does the glyph size: the
## player's own size is kept the same physical size, the default is replaced by
## the new default. Not in scripted runs.
func _check_display(delta: float) -> void:
	_display_t += delta
	if _display_t < 0.5:
		return
	_display_t = 0.0
	if Mobile.active():
		_check_mobile_display()
		return
	var r := AsciiControls.display_scale()
	var d := default_glyph_px()
	var rescaled := not is_equal_approx(r, _display_scale)
	if not rescaled and d == _display_default:
		return
	if audio.glyph_px > 0:
		if rescaled:
			_display_scale = r
			renderer.settings.glyph_px = chosen_glyph_px()
	elif renderer.settings.glyph_px == _display_default:
		renderer.settings.glyph_px = d
	_display_scale = r
	_display_default = d
	if rescaled:
		controls.apply_scale()
		panel.apply_scale()


## `--webdisplaylog`: print the display scale and sizes every two seconds
## (checking the web build's HiDPI handling in a browser console).
func _log_display(delta: float) -> void:
	if _display_log_t < 0.0:
		if not OS.get_cmdline_user_args().has("--webdisplaylog"):
			return
		_display_log_t = 2.0
	_display_log_t += delta
	if _display_log_t < 2.0:
		return
	_display_log_t = 0.0
	print("[settings] master %.2f music %.2f sfx %.2f muted %s opponent %d zoom %d, tuning presets %s current %s" % [
		audio.master_volume, audio.music_volume, audio.sfx_volume, audio.muted, audio.opponent_level, audio.zoom_setting,
		tuning.names, tuning.current])
	var gm := AsciiControls.glyph_measure(renderer.settings.glyph_px)
	print("[display] screen scale %.2f (reported %.3f, dpi %d), screen %s, window %s, output %s, grid %dx%d, glyph %d px (%.1f logical, %d rows/screen; default %d), HUD scale %.2f" % [
		DisplayServer.screen_get_scale(), AsciiControls.reported_scale(), DisplayServer.screen_get_dpi(), DisplayServer.screen_get_size(),
		get_window().size, renderer.output_size, renderer.cols, renderer.rows,
		renderer.settings.glyph_px, gm.x, roundi(gm.y), default_glyph_px(), AsciiControls.display_scale()])


func _process(delta: float) -> void:
	_log_display(delta)
	if not _scripted or Mobile.active():
		_check_display(delta)
	if tilt != null:
		tilt.enabled = car.player_input and not race_start.counting and phone_controls() == "tilt"
		update_level()
	nitro_hud.race_text = opponent.status_text() if opponent != null and not race_start.counting else ""
	camera.zoom_choice = audio.zoom_setting
	# The camera shortcut joins the corner legend (once the start's camera tip,
	# if any, has faded).
	controls.legend_extra = "" if race_start.tip_showing() else RaceStart.camera_keys() + "  camera"
	# The debug HUD's legend: not over the reel (logo, prompt) or the menu.
	controls.legend_allowed = (attract == null or not attract.busy()) and not pause_menu.is_open and web_start == null and not Mobile.active()
	# Music and mix: the menu track leads under the reel, the race track is a
	# bed under the car in play (the pause menu sets its own context).
	if web_start != null:
		audio.set_context(AudioDirector.Context.MENU)
		audio.play_music("") # nothing could be heard yet; the reel starts it from the top
	elif attract != null and attract.busy():
		audio.set_context(AudioDirector.Context.MENU)
		audio.play_music("menu")
	else:
		audio.set_context(AudioDirector.Context.RACE)
		# Under the start lights the music is held back; it comes in at lights out.
		audio.play_music("" if race_start.counting else "race")
	controls.mode_text = lighting.describe()
	if controls.enabled:
		lighting.update_sun_keys(delta)
	_update_halo(delta)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var mods := tuning.modified_count()
	var preset := ">> %s <<" % _flash.to_upper() if _flash_timer > 0.0 else "preset %s%s" % [tuning.current, " (modified)" if mods > 0 else ""]
	var rumble_text := "rumble off" if not rumble.enabled or rumble.strength <= 0.0 else "rumble %d%%" % roundi(rumble.strength * 100.0)
	controls.status_text = "%5.1f u/s   lap %d   %s   %s\ncurrent %s   last %s   best %s\n%s   %s   %s\n%s" % [
		car.linear_velocity.length(), laps.lap,
		"on road" if car.wheels_on_road >= 2 else "OFF ROAD", "chase view" if chase_view else ("iso, snap on" if camera.snap_to_grid else "iso, snap off"),
		LapTimer.fmt(laps.current if laps.started else -1.0), LapTimer.fmt(laps.last), LapTimer.fmt(laps.best),
		preset, _pad_text, rumble_text, telemetry()]


## Three lines: steering in vs out, pedals; body slip, grip use per axle,
## sliding wheels; the handbrake drift (state, angle vs target, arc) and boost.
func telemetry() -> String:
	var u := car.wheel_usage
	var slide := PackedStringArray()
	for i in 4:
		slide.append(["FL", "FR", "RL", "RR"][i] if u[i] > 1.0 else "--")
	var drift := "drift --"
	match car.drift_state:
		Car.Drift.DRIFT:
			drift = "DRIFT %s  angle %4.1f / %4.1f deg  arc r %4.1f" % ["R" if car.drift_dir > 0.0 else "L",
				rad_to_deg(car.drift_angle), rad_to_deg(car.drift_target), minf(car.drift_radius, 99.0)]
		Car.Drift.EXIT:
			drift = "drift exit  angle %4.1f deg" % rad_to_deg(car.drift_angle)
	var boost := "boost charge %3d%%" % roundi(car.boost_charge * 100.0)
	if car.boost_left > 0.0:
		boost = "BOOST %3d%% (%.1f s)" % [roundi(car.boost_power * 100.0), car.boost_left]
	return "steer %+.2f %s -> wheels %+5.1f / %4.1f deg   thr %.2f  brk %.2f  %s\nslip %+5.1f deg   grip used F %3d%%  R %3d%%   sliding %s\n%s   %s" % [
		car.steer_input, "pad" if car.steer_analog else "key", rad_to_deg(car.steer_angle), rad_to_deg(car.steer_lock),
		car.throttle_input, car.brake_input, "HANDBRAKE" if car.handbrake_input else "",
		rad_to_deg(car.slip_angle), roundi((u[0] + u[1]) * 50.0), roundi((u[2] + u[3]) * 50.0), " ".join(slide), drift, boost]


func _unhandled_input(event: InputEvent) -> void:
	if not controls.enabled:
		return
	if event.is_action_pressed(&"camera_toggle"):
		blend_view(not chase_view)
		flash("chase view" if chase_view else "iso view")
		race_start.dismiss_tip()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"rumble_toggle"):
		rumble.set_enabled(not rumble.enabled)
		flash("rumble " + ("on" if rumble.enabled else "off"))
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_G:
		camera.snap_to_grid = not camera.snap_to_grid
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_M:
		flash("sound muted" if audio.toggle_mute() else "sound on")
		audio.save_settings()
		get_viewport().set_input_as_handled()


# --- phone (Mobile.active()) ---------------------------------------------------------

## Phone layout and input: touch (from the mouse with --mobile), tilt, the
## touch buttons, text sized from the window height, the race standing at the
## top (the buttons take the bottom corners).
func _setup_mobile() -> void:
	if not Mobile.device():
		Input.emulate_touch_from_mouse = true
	AsciiControls.ui_scale_override = Mobile.ui_scale(get_viewport().get_visible_rect().size.y)
	controls.apply_scale()
	panel.apply_scale()
	nitro_hud.race_top = true
	tilt = TiltInput.new()
	tilt.name = "TiltInput"
	tilt.car = car
	tilt.flip = bool(audio.phone_get("flip", false))
	add_child(tilt)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.game = self
	touch.car = car
	add_child(touch)
	phone_assist = PhoneAssist.new()
	phone_assist.name = "PhoneAssist"
	phone_assist.game = self
	phone_assist.car = car
	add_child(phone_assist)
	touch.assist = phone_assist


## Phone: the level display (pause menu LEVEL DISPLAY, saved, on by default)
## while a race is on screen; off in the reel and the level select.
func update_level() -> void:
	if tilt == null:
		return
	var on := bool(audio.phone_get("level", true)) and phone_controls() == "tilt" and in_race()
	renderer.level_max = deg_to_rad(Mobile.level_max_deg()) if on else 0.0
	renderer.level_angle = tilt.display_roll if on else 0.0


## The phone's touch steering scheme (Mobile.CONTROLS).
func phone_controls() -> String:
	var c := String(audio.phone_get("controls", Mobile.CONTROLS[0]))
	return c if Mobile.CONTROLS.has(c) else Mobile.CONTROLS[0]


## The phone's glyph size setting: text rows on the window height.
func phone_rows() -> int:
	if audio == null:
		return Mobile.DEFAULT_ROWS # before the settings are loaded (the first frame)
	return clampi(int(audio.phone_get("rows", Mobile.DEFAULT_ROWS)), Mobile.MIN_ROWS, Mobile.MAX_ROWS)


func set_phone_rows(rows: int) -> void:
	rows = clampi(rows, Mobile.MIN_ROWS, Mobile.MAX_ROWS)
	audio.phone_set("rows", rows)
	audio.save_settings()
	_display_default = default_glyph_px()
	if not pause_menu.is_open: # the menu sets its own size while open
		renderer.settings.glyph_px = _display_default


## Phone: the window height sets the text scale and the glyph size (rotation,
## split screen).
func _check_mobile_display() -> void:
	var k := Mobile.ui_scale(get_viewport().get_visible_rect().size.y)
	if not is_equal_approx(k, AsciiControls.ui_scale_override):
		AsciiControls.ui_scale_override = k
		controls.apply_scale()
		panel.apply_scale()
	var d := default_glyph_px()
	if d != _display_default:
		if renderer.settings.glyph_px == _display_default:
			renderer.settings.glyph_px = d
		_display_default = d


## True while the player is in a race (not the reel, the level select or a wipe).
func in_race() -> bool:
	return car.player_input and (attract == null or not attract.busy())


## Phone back button (and the pause button): in a race it pauses and resumes,
## in the level select it goes back to the reel, in a menu it closes it.
func mobile_back() -> void:
	if pause_menu.is_open:
		pause_menu.back()
	elif level_select != null and level_select.active:
		level_select.go_back()
	elif in_race():
		pause_menu.open(false)


func _notification(what: int) -> void:
	if not Mobile.active():
		return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			mobile_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# The app went to the background: a race waits in the pause menu.
			# (Device only: a desktop test window losing focus must not pause.)
			if Mobile.device() and in_race() and not pause_menu.is_open:
				pause_menu.open(false)
