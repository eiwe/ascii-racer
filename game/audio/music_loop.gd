## One music track, looped with a crossfade instead of a hard wrap (the tracks
## are full songs, not authored loops): at `xfade_at` seconds a second player
## starts the track from the top and the two crossfade over `xfade` seconds
## (equal power). Also fades the whole track in or out (track changes).
class_name MusicLoop
extends Node

var stream: AudioStream
var xfade_at: float = 0.0 ## seconds into the track where the next pass starts (0 = plain loop)
var xfade: float = 1.0
var gain_db: float = 0.0
var bus: StringName = &"Master"
## Track level 0..1 and where it is heading.
var level: float = 0.0
var target: float = 0.0
var _rate: float = 1.0
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _xf_t: float = -1.0 ## seconds into a crossfade, -1 = none
var passes: int = 0 ## how many times the track has wrapped (tests)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)
	if stream != null:
		stream = stream.duplicate()
		stream.set("loop", xfade_at <= 0.0) # a plain loop only without a crossfade point


func fade_to(v: float, seconds: float) -> void:
	target = v
	_rate = 1.0 / maxf(seconds, 0.01)


func _process(delta: float) -> void:
	if stream == null:
		return
	level = move_toward(level, target, _rate * delta)
	var playing := _players[_active].playing
	if level <= 0.0:
		if playing or _players[1 - _active].playing:
			_players[0].stop()
			_players[1].stop()
			_xf_t = -1.0
		return
	if not playing:
		_players[_active].stream = stream
		_players[_active].play()
	var a := _players[_active]
	var b := _players[1 - _active]
	if xfade_at > 0.0 and _xf_t < 0.0 and a.get_playback_position() >= xfade_at:
		_xf_t = 0.0
		b.stream = stream
		b.play()
		passes += 1
	var g_a := 1.0
	var g_b := 0.0
	if _xf_t >= 0.0:
		_xf_t += delta
		var t := clampf(_xf_t / maxf(xfade, 0.01), 0.0, 1.0)
		g_a = cos(t * PI * 0.5)
		g_b = sin(t * PI * 0.5)
		if t >= 1.0:
			a.stop()
			_active = 1 - _active
			_xf_t = -1.0
			g_a = 0.0
	# Level fades are perceptual: an equal-power-ish curve on the linear gain.
	var lv := level * level
	a.volume_db = linear_to_db(maxf(g_a * lv, 1e-5)) + gain_db
	b.volume_db = linear_to_db(maxf(g_b * lv, 1e-5)) + gain_db

