## The table that says which sound file plays which role: a ConfigFile with one
## section per role (`file`, `gain_db`, and per role extras: an engine loop's
## `rpm`, a music track's `xfade_at` and `xfade`). Files are relative to the
## table. The game's table is res://assets/audio/sounds.cfg (written by
## tools/prepare_audio.py); `--soundtable=<path>` loads another one from disk
## (test stand-ins). A role with no section or no file is simply silent.
class_name SoundTable
extends RefCounted

const DEFAULT_PATH: String = "res://assets/audio/sounds.cfg"
## Roles that loop (their streams are set to loop when loaded).
const LOOPED: PackedStringArray = ["tyre_squeal", "tyre_skid", "nitro_sustain", "dirt_roll", "dirt_slide"]

var path: String = DEFAULT_PATH
var _cfg := ConfigFile.new()
var _streams: Dictionary = {}
var loaded: bool = false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--soundtable="):
			path = arg.trim_prefix("--soundtable=")
	if path.begins_with("res://") and not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return
	loaded = _cfg.load(path) == OK


func has(role: String) -> bool:
	return stream(role) != null


func value(role: String, key: String, default: Variant) -> Variant:
	return _cfg.get_value(role, key, default) if _cfg.has_section(role) else default


func gain_db(role: String) -> float:
	return float(value(role, "gain_db", 0.0))


## The role's stream (cached), or null if it has none or the file is missing.
func stream(role: String) -> AudioStream:
	if _streams.has(role):
		return _streams[role]
	var s: AudioStream = null
	var file: String = value(role, "file", "")
	if file != "":
		s = _load(path.get_base_dir().path_join(file))
		if s != null and (role in LOOPED or role.begins_with("engine_loop_")):
			s.set("loop", true)
	_streams[role] = s
	return s


## Engine loops sorted by rpm: [[rpm, role], ...].
func engine_loops() -> Array:
	var out: Array = []
	for sec in _cfg.get_sections():
		if sec.begins_with("engine_loop_") and has(sec):
			out.append([float(_cfg.get_value(sec, "rpm", 1000.0)), sec])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


static func _load(p: String) -> AudioStream:
	if p.begins_with("res://"):
		if not ResourceLoader.exists(p):
			return null
		return load(p) as AudioStream
	if not FileAccess.file_exists(p):
		return null
	match p.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(p)
		"wav":
			return AudioStreamWAV.load_from_file(p)
		"mp3":
			var m := AudioStreamMP3.new()
			m.data = FileAccess.get_file_as_bytes(p)
			return m
	return null
