## The game's sound outside the car: the bus layout, the music (two tracks,
## each looped with a crossfade, and crossfaded into each other), the mix
## context (menu / race / paused), the player's volume settings and mute.
##
## Buses (created here):
##   Master   hard limiter (nothing clips)
##     Music      the music; low-passed while paused
##     SFX        everything the car makes; silent while paused
##       Engine     (low-pass for brightness, set by CarAudio)
##       Tyres
##       Effects    landing, kerbs, impacts, nitro
##     Preview    the SFX test blip of the pause menu (audible while paused)
##
## The balance: during a race the car is the foreground and the music a bed
## under it; in the reel and menus the music leads and the car sits well under
## it. The player's two sliders trim that balance (100 % = the balance below).
class_name AudioDirector
extends Node

enum Context { MENU, RACE, PAUSED }

const SETTINGS_PATH: String = "user://audio_settings.cfg"
## Music level by context (dB on the Music bus at 100 %), and the car's level
## in the reel (dB on the SFX bus). Set by measurement (drive test `audio`).
const MUSIC_MENU_DB: float = -0.5
const MUSIC_RACE_DB: float = -2.5
const MUSIC_PAUSED_DB: float = -8.0
const SFX_MENU_DB: float = -13.0
const SFX_RACE_DB: float = 0.0
## Room for the tyre squeal (the player's grip warning) in the race music: a
## fixed dip where the squeal sits (EQ6 bands 1 kHz, 3.2 kHz; dB) and a duck
## of the whole music while the tyres squeal (dB at full squeal).
const MUSIC_EQ_1K_DB: float = -1.0
const MUSIC_EQ_3K_DB: float = -2.0
const SQUEAL_DUCK_DB: float = -5.0
## Low-pass on the music while paused (Hz).
const PAUSE_LOWPASS_HZ: float = 900.0
## How fast the context levels move (dB per second), and the track crossfade (s).
const LEVEL_RATE: float = 30.0
const TRACK_FADE: float = 1.6
const LIMITER_CEILING_DB: float = -1.0
## Slider steps (0..1 in this many steps).
const SLIDER_STEPS: int = 20

var table: SoundTable
var context: Context = Context.MENU
## The player's trims, 0..1 (perceptual: gain = (slider / DEFAULT_VOLUME)^2, so
## the default is the designed balance with headroom above it; 0 = silent).
const DEFAULT_VOLUME: float = 0.8
var master_volume: float = DEFAULT_VOLUME
var music_volume: float = DEFAULT_VOLUME
var sfx_volume: float = DEFAULT_VOLUME
var muted: bool = false
## The pause menu's other setting, kept in the same file ([game] section):
## the AI opponent's difficulty, 0 = off, 1..5.
const DEFAULT_OPPONENT_LEVEL: int = 3
var opponent_level: int = DEFAULT_OPPONENT_LEVEL
## The isometric camera's zoom: 0 = AUTO, 1.. = FollowCamera.ZOOM_STEPS[n - 1].
var zoom_setting: int = 0
## The selected track ([game] track) and per track ([track.<id>]) its time of
## day, opponent level and best lap (-1 = none). `opponent_level` is the
## selected track's level (the pause menu edits it).
const TIMES: PackedStringArray = ["morning", "noon", "night"]
const DEFAULT_TIME: String = "morning"
var track_id: String = Tracks.DEFAULT_ID
var track_settings: Dictionary = {} ## id -> {time, opponent, best}
## The glyph size the player chose with - / = ([display] section; 0 = none, the
## platform default applies) and the display scale (AsciiControls.display_scale)
## it was chosen at, so it can be kept the same size on another display.
var glyph_px: int = 0
var glyph_scale: float = 1.0
## Phone settings ([phone] section, written only when a phone set one): flip
## (steering), rows (glyph size), camera ("chase" / "iso").
var phone: Dictionary = {}
var settings_path: String = SETTINGS_PATH
## True when a volume or the mute changed since the settings were loaded or saved.
var dirty: bool = false
## 0..1 squeal / skid level from CarAudio (ducks the music in a race).
var squeal_level: float = 0.0
var _duck_db: float = 0.0

var _music_bus: int = -1
var _sfx_bus: int = -1
var _preview_bus: int = -1
var _music_db: float = MUSIC_MENU_DB
var _sfx_db: float = SFX_MENU_DB
var _track: String = ""
var _tracks: Dictionary = {} ## name -> MusicLoop
var _preview: AudioStreamPlayer
## Measurement: "music" or "sfx" mutes the other bus (`--audiomix=`).
var solo: String = ""
## Tests: force a context and track ("" = follow the game).
var forced_track: String = ""
var forced_context: int = -1
## `--quitafter=<seconds>`: quit through quit() (sound stopped first) after this
## long, for automated runs. (The engine's own --quit-after ends the program on
## a frame count while sounds may be mid-play, which Godot can report as leaked
## audio playbacks at exit.)
var _quit_after_s: float = -1.0
var _frames: int = 0
var _quitting: bool = false
## True once stop_all() ran (quitting): nothing plays any more.
var stopped: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audiosettings="):
			settings_path = arg.trim_prefix("--audiosettings=")
		elif arg.begins_with("--audiomix="):
			solo = arg.trim_prefix("--audiomix=")
	# Quitting with sounds mid-play can leave their playbacks behind in the
	# audio server (leak errors at exit), so every quit goes through quit():
	# all sound stopped, a moment for the mixer, then quit.
	get_tree().auto_accept_quit = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quitafter="):
			_quit_after_s = arg.trim_prefix("--quitafter=").to_float()
	table = SoundTable.new()
	_setup_buses()
	load_settings()
	for name: String in ["menu", "race"]:
		var m := MusicLoop.new()
		m.name = "Music_" + name
		m.stream = table.stream("music_" + name)
		m.xfade_at = float(table.value("music_" + name, "xfade_at", 0.0))
		m.xfade = float(table.value("music_" + name, "xfade", 1.0))
		m.gain_db = table.gain_db("music_" + name)
		m.bus = &"Music"
		add_child(m)
		_tracks[name] = m
	_preview = AudioStreamPlayer.new()
	_preview.bus = &"Preview"
	add_child(_preview)
	_apply_levels(true)


static func bus_index(bus_name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, send)
	return i


func _setup_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = LIMITER_CEILING_DB
		AudioServer.add_bus_effect(0, lim)
	_music_bus = bus_index("Music", "Master")
	if AudioServer.get_bus_effect_count(_music_bus) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = PAUSE_LOWPASS_HZ
		AudioServer.add_bus_effect(_music_bus, lp)
		AudioServer.set_bus_effect_enabled(_music_bus, 0, false)
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(3, MUSIC_EQ_1K_DB)
		eq.set_band_gain_db(4, MUSIC_EQ_3K_DB)
		AudioServer.add_bus_effect(_music_bus, eq)
	_sfx_bus = bus_index("SFX", "Master")
	var engine := bus_index("Engine", "SFX")
	if AudioServer.get_bus_effect_count(engine) == 0:
		AudioServer.add_bus_effect(engine, AudioEffectLowPassFilter.new())
	bus_index("Tyres", "SFX")
	bus_index("Effects", "SFX")
	bus_index("Opponent", "SFX")
	_preview_bus = bus_index("Preview", "Master")


## Which music plays: "menu", "race" or "" (none). Crossfades; the track that
## keeps playing is not restarted.
func play_music(track: String) -> void:
	if forced_track != "":
		track = forced_track
	if track == _track:
		return
	_track = track
	for n: String in _tracks:
		(_tracks[n] as MusicLoop).fade_to(1.0 if n == track else 0.0, TRACK_FADE)


func current_track() -> String:
	return _track


func set_context(c: Context) -> void:
	context = c if forced_context < 0 or c == Context.PAUSED else forced_context as Context
	if context == Context.PAUSED:
		_sfx_db = -80.0 # the car goes silent at once


## `--webaudiolog`: print the music players' state once a second (checking
## the web build's audio start in a browser console).
var _audio_log_t: float = -1.0


func _log_audio(delta: float) -> void:
	if _audio_log_t < 0.0:
		if not OS.get_cmdline_user_args().has("--webaudiolog"):
			return
		_audio_log_t = 0.0
	_audio_log_t += delta
	if _audio_log_t < 1.0:
		return
	_audio_log_t = 0.0
	var parts := PackedStringArray()
	for n: String in _tracks:
		var m: MusicLoop = _tracks[n]
		var p: AudioStreamPlayer = m._players[m._active]
		parts.append("%s level %.2f playing %s pos %.2f" % [n, m.level, p.playing, p.get_playback_position()])
	print("[audio] t %.1f track %s context %d | %s" % [Time.get_ticks_msec() / 1000.0, _track, context, " | ".join(parts)])


func _process(delta: float) -> void:
	_log_audio(delta)
	_frames += 1
	if _quit_after_s > 0.0 and not _quitting:
		_quit_after_s -= delta
		if _quit_after_s <= 0.0:
			quit()
	_apply_levels(false, delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


## Stops every sound player in the game.
func stop_all() -> void:
	if stopped:
		return
	stopped = true
	for n: Node in get_tree().root.find_children("*", "", true, false):
		if n is CarAudio or n is MusicLoop:
			n.set_process(false)
			n.set_physics_process(false)
	for p: Node in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		(p as AudioStreamPlayer).stop()
	# (No bus mute here: the server only finishes stopped playbacks on buses
	# it is still mixing.)


## Quits after stopping all sound (and giving the audio server a moment).
func quit(code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	save_settings()
	stop_all()
	set_process(false)
	# Real time (not game time: under --fixed-fps frames run much faster than
	# real time), with frames still running so the server can free the sounds.
	var until := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	get_tree().quit(code)


func _context_levels() -> Vector2:
	match context:
		Context.RACE:
			return Vector2(MUSIC_RACE_DB, SFX_RACE_DB)
		Context.PAUSED:
			return Vector2(MUSIC_PAUSED_DB, -80.0)
	return Vector2(MUSIC_MENU_DB, SFX_MENU_DB)


func _apply_levels(snap: bool, delta: float = 0.0) -> void:
	var want := _context_levels()
	if snap:
		_music_db = want.x
		_sfx_db = want.y
	else:
		_music_db = move_toward(_music_db, want.x, LEVEL_RATE * delta)
		# Going silent for the pause is quick; coming back fades in.
		_sfx_db = move_toward(_sfx_db, want.y, (LEVEL_RATE * 8.0 if want.y < _sfx_db else LEVEL_RATE * 2.0) * delta)
	var duck := SQUEAL_DUCK_DB * squeal_level if context == Context.RACE else 0.0
	_duck_db = duck if snap else move_toward(_duck_db, duck, (40.0 if duck < _duck_db else 8.0) * maxf(delta, 0.0))
	AudioServer.set_bus_volume_db(_music_bus, _music_db + _duck_db + slider_db(music_volume))
	AudioServer.set_bus_mute(_music_bus, music_volume <= 0.0 or solo == "sfx")
	AudioServer.set_bus_volume_db(_sfx_bus, maxf(_sfx_db, -80.0) + slider_db(sfx_volume))
	AudioServer.set_bus_mute(_sfx_bus, sfx_volume <= 0.0 or _sfx_db <= -79.0 or solo == "music")
	if solo == "tyres":
		AudioServer.set_bus_mute(_music_bus, true)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Engine"), true)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Effects"), true)
	AudioServer.set_bus_volume_db(_preview_bus, slider_db(sfx_volume))
	AudioServer.set_bus_effect_enabled(_music_bus, 0, context == Context.PAUSED)
	AudioServer.set_bus_volume_db(0, slider_db(master_volume))
	AudioServer.set_bus_mute(0, muted or master_volume <= 0.0)


## Perceptual slider curve: gain = (v / DEFAULT_VOLUME)^2: the default is
## 0 dB, full is +3.9 dB, half the default -12 dB; 0 = silent.
static func slider_db(v: float) -> float:
	return -80.0 if v <= 0.0 else linear_to_db(pow(v / DEFAULT_VOLUME, 2.0))


func set_master_volume(v: float) -> void:
	master_volume = clampf(snappedf(v, 1.0 / SLIDER_STEPS), 0.0, 1.0)
	dirty = true
	_apply_levels(false)
	blip()


func set_music_volume(v: float) -> void:
	music_volume = clampf(snappedf(v, 1.0 / SLIDER_STEPS), 0.0, 1.0)
	dirty = true
	_apply_levels(false)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(snappedf(v, 1.0 / SLIDER_STEPS), 0.0, 1.0)
	dirty = true
	_apply_levels(false)
	blip()


func set_opponent_level(l: int) -> void:
	opponent_level = clampi(l, 0, 5)
	_track_entry(track_id).opponent = opponent_level
	dirty = true


func _track_entry(id: String) -> Dictionary:
	if not track_settings.has(id):
		track_settings[id] = {"time": DEFAULT_TIME, "opponent": DEFAULT_OPPONENT_LEVEL, "best": -1.0}
	return track_settings[id]


## Selects a track: its opponent level becomes the current one.
func select_track(id: String) -> void:
	track_id = id
	opponent_level = int(_track_entry(id).opponent)
	dirty = true


func track_time(id: String) -> String:
	return String(_track_entry(id).time)


func set_track_time(id: String, t: String) -> void:
	_track_entry(id).time = t if TIMES.has(t) else DEFAULT_TIME
	dirty = true


func track_opponent(id: String) -> int:
	return int(_track_entry(id).opponent)


func set_track_opponent(id: String, l: int) -> void:
	_track_entry(id).opponent = clampi(l, 0, 5)
	if id == track_id:
		opponent_level = clampi(l, 0, 5)
	dirty = true


func best_lap(id: String) -> float:
	return float(_track_entry(id).best)


## Records a lap; true (and saved) when it is the track's best.
func record_lap(id: String, t: float) -> bool:
	var e := _track_entry(id)
	if float(e.best) > 0.0 and t >= float(e.best):
		return false
	e.best = t
	dirty = true
	save_settings()
	return true


func phone_get(key: String, default: Variant) -> Variant:
	return phone.get(key, default)


func phone_set(key: String, value: Variant) -> void:
	if phone.get(key) != value:
		phone[key] = value
		dirty = true


func set_glyph_choice(px: int, scale: float) -> void:
	glyph_px = clampi(px, 0, 64)
	glyph_scale = maxf(scale, 0.5)
	dirty = true


func set_zoom_setting(z: int) -> void:
	zoom_setting = clampi(z, 0, FollowCamera.ZOOM_STEPS.size())
	dirty = true


func toggle_mute() -> bool:
	muted = not muted
	dirty = true
	_apply_levels(false)
	return muted


## A short sound on the Preview bus at the SFX level (audible while paused), so
## the SFX slider can be judged.
func blip(role: String = "kerb") -> void:
	var s := table.stream(role)
	if s == null:
		return
	_preview.stream = s
	_preview.volume_db = table.gain_db(role)
	_preview.play()


## Plays one role on its own (the pause menu's sound check).
func audition(role: String) -> void:
	var s := table.stream(role)
	if s == null:
		return
	_preview.stream = s
	_preview.volume_db = table.gain_db(role)
	_preview.play()


func stop_audition() -> void:
	_preview.stop()


func load_settings() -> void:
	WebStore.restore(settings_path) # web: the browser's copy, if any
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", DEFAULT_VOLUME)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", DEFAULT_VOLUME)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", DEFAULT_VOLUME)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", false))
	opponent_level = clampi(int(cfg.get_value("game", "opponent", DEFAULT_OPPONENT_LEVEL)), 0, 5)
	zoom_setting = clampi(int(cfg.get_value("game", "zoom", 0)), 0, FollowCamera.ZOOM_STEPS.size())
	track_settings.clear()
	for id in Tracks.ids():
		var sec := "track." + id
		var e := _track_entry(id)
		# Before tracks had their own settings the opponent level was global: track 1 keeps it.
		var legacy := opponent_level if id == Tracks.DEFAULT_ID else DEFAULT_OPPONENT_LEVEL
		e.opponent = clampi(int(cfg.get_value(sec, "opponent", legacy)), 0, 5)
		var t := String(cfg.get_value(sec, "time", DEFAULT_TIME))
		e.time = t if TIMES.has(t) else DEFAULT_TIME
		e.best = float(cfg.get_value(sec, "best", -1.0))
	track_id = String(cfg.get_value("game", "track", Tracks.DEFAULT_ID))
	if not Tracks.ids().has(track_id):
		track_id = Tracks.DEFAULT_ID
	opponent_level = int(_track_entry(track_id).opponent)
	glyph_px = clampi(int(cfg.get_value("display", "glyph_px", 0)), 0, 64)
	glyph_scale = maxf(float(cfg.get_value("display", "glyph_scale", 1.0)), 0.5)
	phone = {}
	if cfg.has_section("phone"):
		for k in cfg.get_section_keys("phone"):
			phone[k] = cfg.get_value("phone", k)


## Writes the settings file if anything changed.
func save_settings() -> void:
	if not dirty:
		return
	dirty = false
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("game", "opponent", opponent_level)
	cfg.set_value("game", "zoom", zoom_setting)
	cfg.set_value("game", "track", track_id)
	for id: String in track_settings:
		var e: Dictionary = track_settings[id]
		cfg.set_value("track." + id, "time", e.time)
		cfg.set_value("track." + id, "opponent", e.opponent)
		if float(e.best) > 0.0:
			cfg.set_value("track." + id, "best", e.best)
	if glyph_px > 0:
		cfg.set_value("display", "glyph_px", glyph_px)
		cfg.set_value("display", "glyph_scale", glyph_scale)
	for k: String in phone:
		cfg.set_value("phone", k, phone[k])
	if cfg.save(settings_path) != OK:
		push_warning("could not save audio settings to " + settings_path)
	else:
		WebStore.saved(settings_path) # web: also kept in the browser's localStorage


func _exit_tree() -> void:
	if _preview != null:
		_preview.stop()
		_preview.stream = null
