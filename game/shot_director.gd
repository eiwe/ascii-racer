## Cuts the demo reel between camera shots on a rhythm set by the track: each
## track section has a few shots that suit it (the jump gets a low trackside
## shot, the bridge a high wide one, the hairpin a camera inside the turn), and
## the choice varies from lap to lap. Shots are defined relative to the track
## (s, lateral offset, height), so they follow edits to the layout.
##
## Safety: a cinematic shot that loses the car (out of frame or something
## solid in the way) for LOST_TIME cuts to the chase camera.
class_name ShotDirector
extends Node

signal cut(shot: String)

## Track sections [from s, to s, shots...]; `to` may be past the lap length.
const SECTIONS: Array = [
	[12.3, 22.0, "chase", "pan_straight"],
	[22.0, 34.0, "jump_low", "jump_low", "chase"],
	[34.0, 52.9, "iso", "orbit"],
	[52.9, 74.0, "pan_s", "iso"],
	[74.0, 92.0, "chase", "orbit"],
	[92.0, 106.0, "bridge_under", "iso"],
	[106.0, 114.0, "chase", "iso"],
	[114.0, 131.0, "hairpin", "hairpin", "iso"],
	[131.0, 159.7, "bridge_over", "chase", "iso"],
]
## Cinematic shots. fixed: stand at (s, lateral, height) beside the track (+
## lateral = right of the direction of travel); bridge_*: placed from the
## crossing; orbit: circle the car.
const SHOTS: Dictionary = {
	"pan_straight": {"s": 19.0, "lateral": -3.6, "height": 0.7},
	"jump_low": {"s": 34.0, "lateral": 3.4, "height": 1.8},
	"pan_s": {"s": 66.0, "lateral": 4.2, "height": 1.1},
	"hairpin": {"s": 122.4, "lateral": -5.0, "height": 2.4},
}
const LOST_TIME: float = 0.5

var game: Node
var car: Car
var track: Track
var iso: FollowCamera
var chase: ChaseCamera
var cine: CineCamera
var renderer: AsciiRenderer
## While true the current shot is held (e.g. under the logo).
var hold: bool = false
var shot: String = ""

var _section: int = -1
var _lap: int = 0
var _lost: float = 0.0
var _progress: float = -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	process_priority = 90 # before the cameras place themselves


func reset(first_shot: String = "iso") -> void:
	_section = -1
	_progress = -1.0
	_lost = 0.0
	_take(first_shot)


func _section_at(s: float) -> int:
	for i in SECTIONS.size():
		var a: float = SECTIONS[i][0]
		var b: float = SECTIONS[i][1]
		if s >= a and s < b or s + track.length >= a and s + track.length < b:
			return i
	return 0


func _process(delta: float) -> void:
	if car == null:
		return
	_progress = track.progress(car.global_position, _progress)
	var sec := _section_at(_progress)
	if not hold and sec != _section:
		if _section >= 0 and sec < _section:
			_lap += 1
		_section = sec
		var options: Array = SECTIONS[sec].slice(2)
		# The first two laps show each section's showcase shot (listed first);
		# after that the choice varies.
		_take(options[_rng.randi_range(0, options.size() - 1) if _lap > 1 else 0])
	if cine.current:
		_lost = 0.0 if cine.sees_car() else _lost + delta
		if _lost > LOST_TIME:
			_take("chase")
		var d := cine.car_distance()
		renderer.distance_fade = Vector2(d + 10.0, d + 30.0)


## Cuts to a shot.
func _take(name: String) -> void:
	shot = name
	_lost = 0.0
	match name:
		"iso":
			iso.current = true
			iso.snap_to_target()
			renderer.distance_fade = Vector2.ZERO
		"chase":
			chase.current = true
			chase.snap_to_target()
			renderer.distance_fade = game.CHASE_FADE
		"orbit":
			cine.mode = CineCamera.Mode.ORBIT
			var v := car.linear_velocity
			# Start beside and a little ahead of the car, swinging round behind it.
			cine.orbit_angle = atan2(v.x, v.z) + PI * 0.4
			cine.orbit_speed = -0.45 if _rng.randf() < 0.5 else 0.45
			cine.current = true
			cine.begin()
		"bridge_under", "bridge_over":
			var c := track.crossing_point
			var lower := track.tangent_at(track.progress(c))
			var upper := track.tangent_at(0.0)
			lower.y = 0.0
			upper.y = 0.0
			if name == "bridge_under":
				# On the lower road's verge past the crossing, looking back: the car
				# comes out from under the deck toward the camera.
				cine.anchor = c + lower.normalized() * 6.5 + upper.normalized() * 3.2 + Vector3.UP * 1.3
			else:
				cine.anchor = c + upper.normalized() * 8.0 + lower.normalized() * 5.0 + Vector3.UP * 6.0
			cine.mode = CineCamera.Mode.FIXED
			cine.current = true
			cine.begin()
		_:
			var d: Dictionary = SHOTS.get(name, {})
			if d.is_empty():
				_take("chase")
				return
			var xf := track.pose_at(d.s, d.lateral)
			var p := xf.origin
			cine.anchor = Vector3(p.x, maxf(p.y, Track.ROAD_Y) + d.height, p.z)
			_clear_of_props()
			cine.mode = CineCamera.Mode.FIXED
			cine.current = true
			cine.begin()
	cut.emit(name)


## Lifts a fixed camera above any tree or prop it would stand inside.
func _clear_of_props() -> void:
	var a := cine.anchor
	for p in game.world.props.get_children():
		if p is StaticBody3D and Vector2(p.position.x - a.x, p.position.z - a.z).length() < 1.4:
			a.y = maxf(a.y, 3.2)
	cine.anchor = a
