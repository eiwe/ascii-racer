## Lap timing from centre-line progress. The first forward crossing of the start
## line starts lap 1; later crossings count as a lap only after passing the
## checkpoints in order, so reversing over the line or cutting the circuit short
## does not count.
class_name LapTimer
extends RefCounted

signal lap_completed(time: float)

## Checkpoints as fractions of the lap, measured from the start line.
const CHECKPOINTS: Array[float] = [0.3, 0.65]
## Window (world units) after a line in which crossing it is recognised.
const WINDOW: float = 4.0

var track: Track
var started: bool = false
var lap: int = 0 ## current lap number (1-based once started)
var current: float = 0.0
var last: float = -1.0
var best: float = -1.0
var next_checkpoint: int = 0
var progress: float = -1.0 ## last centre-line position (s)

var _prev_rel: float = -1.0


func _init(t: Track) -> void:
	track = t


## Call every physics step with the car position.
func update(pos: Vector3, delta: float) -> void:
	progress = track.progress(pos, progress)
	var rel := fposmod(progress - Track.START_S, track.length)
	if started:
		current += delta
	if next_checkpoint < CHECKPOINTS.size():
		var cp := CHECKPOINTS[next_checkpoint] * track.length
		if rel >= cp and rel < cp + WINDOW:
			next_checkpoint += 1
	if _prev_rel >= 0.0 and _prev_rel > track.length - WINDOW and rel < WINDOW:
		_cross_line()
	_prev_rel = rel


func _cross_line() -> void:
	if not started:
		started = true
		lap = 1
		current = 0.0
		next_checkpoint = 0
		return
	if next_checkpoint < CHECKPOINTS.size():
		return
	last = current
	if best < 0.0 or last < best:
		best = last
	lap += 1
	current = 0.0
	next_checkpoint = 0
	lap_completed.emit(last)


## A standing start (lights out): lap 1 runs from now. The car is on the grid
## just behind the line; crossing it moments later does not count as a lap
## (the checkpoints have not been passed).
func start_standing() -> void:
	started = true
	lap = 1
	current = 0.0
	next_checkpoint = 0


## Back to "not started", times cleared.
func reset() -> void:
	started = false
	lap = 0
	current = 0.0
	last = -1.0
	best = -1.0
	next_checkpoint = 0
	resync()


## Forget the position history (after a teleport), keeping the times.
func resync() -> void:
	progress = -1.0
	_prev_rel = -1.0


static func fmt(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
