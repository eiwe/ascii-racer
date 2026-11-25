## The start: F1-style lights. Five red lamps come on one at a time, about a
## second apart, each with a beep; after the fifth a random hold (so the start
## cannot be timed by rhythm), then all five go out at once with a longer,
## higher beep: that is the start. The gantry then slides up off the screen.
##
## While the lights run both cars are held on the grid (frozen in place: the
## player can blip the throttle and hear the engine rev, but nothing moves and
## nitro cannot be used), the race music is held back, and the race standing is
## hidden. At lights out the player's car is released; the opponent follows
## after a reaction time that depends on its level.
##
## Drawn in the renderer's overlay cell layer, top centre. Pauses with the game
## (it carries on where it was); cancel() stops it at once (back to the reel).
## Started by Game.reset_to_grid() for every start from the grid.
class_name RaceStart
extends Node

signal lights_out

const LAMPS: int = 5
## First lamp after this long, then one a second.
const FIRST_LAMP: float = 0.6
const LAMP_INTERVAL: float = 1.0
## Random hold after the fifth lamp (s).
const HOLD: Vector2 = Vector2(0.6, 1.8)
## After lights out the gantry slides up out of view over this long.
const CLEAR_TIME: float = 0.8
## Opponent reaction after lights out (s): level 1 .. level 5, and the random spread.
const REACTION: Vector2 = Vector2(0.45, 0.15)
const REACTION_SPREAD: float = 0.05

const HOUSING: Color = Color(0.03, 0.03, 0.035)
const FRAME_INK: Color = Color("6b6f80")
const OFF_INK: Color = Color("2c2e38")
const LIT_CORE: Color = Color("ff6a50")
const LIT_EDGE: Color = Color("d01818")

var game: Node
## True from start() until lights out.
var counting: bool = false
## Seconds since start() (while counting) and the hold drawn for this start.
var t: float = 0.0
var hold: float = 1.0
## Read-outs for tests: when the lights went out (t) and how many starts.
var starts: int = 0
var opponent_delay: float = 0.0

var _lit: int = 0
var _after: float = -1.0 ## seconds since lights out while the gantry clears (-1 = not drawn)
var _opp_wait: float = -1.0
var _rng := RandomNumberGenerator.new()
var _beep: AudioStreamPlayer
var _go: AudioStreamPlayer


func _ready() -> void:
	process_priority = 105 # after NitroHud (it clears the overlay), before PauseMenu
	_rng.randomize()
	_beep = _player("start_beep")
	_go = _player("start_go")


func _player(role: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Effects"
	p.stream = game.audio.table.stream(role)
	p.volume_db = game.audio.table.gain_db(role)
	add_child(p)
	return p


## A new start: lights from the beginning, both cars held.
func start() -> void:
	counting = true
	t = 0.0
	_lit = 0
	_after = -1.0
	_opp_wait = -1.0
	hold = _rng.randf_range(HOLD.x, HOLD.y)
	starts += 1
	_hold_cars(true)


## Stops at once with nothing held (returning to the reel, quitting).
func cancel() -> void:
	if counting:
		_hold_cars(false)
	counting = false
	_after = -1.0
	_opp_wait = -1.0
	_beep.stop()
	_go.stop()


func _hold_cars(on: bool) -> void:
	var car: Car = game.car
	car.freeze = on
	car.nitro_enabled = not on
	car.nitro_input = false
	if on:
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
	var opp: Opponent = game.opponent
	if opp != null:
		opp.car.freeze = on
		opp.car.nitro_input = false
		opp.driver.set_physics_process(not on)
		if on:
			opp.car.player_input = false
			opp.car.throttle_input = 0.0
			opp.car.brake_input = 0.0
			opp.car.steer_input = 0.0


func _physics_process(delta: float) -> void:
	if _opp_wait >= 0.0:
		_opp_wait -= delta
		if _opp_wait < 0.0:
			var opp: Opponent = game.opponent
			if opp != null:
				opp.driver.launch()
				opp.driver.set_physics_process(true)


func _process(delta: float) -> void:
	if counting:
		t += delta
		var want := clampi(floori((t - FIRST_LAMP) / LAMP_INTERVAL) + 1, 0, LAMPS)
		while _lit < want:
			_lit += 1
			_beep.play()
		if _lit == LAMPS and t >= FIRST_LAMP + (LAMPS - 1) * LAMP_INTERVAL + hold:
			_go_now()
	elif _after >= 0.0:
		_after += delta
		if _after > CLEAR_TIME:
			_after = -1.0
	if counting or _after >= 0.0:
		_draw()


func _go_now() -> void:
	counting = false
	_lit = 0
	_after = 0.0
	_go.play()
	var car: Car = game.car
	car.freeze = false
	car.nitro_enabled = true
	game.laps.start_standing()
	var opp: Opponent = game.opponent
	if opp != null:
		opp.car.freeze = false
		opp.to_grid_tracking_only()
		var k := clampf((opp.level - 1) / 4.0, 0.0, 1.0)
		opponent_delay = lerpf(REACTION.x, REACTION.y, k) + _rng.randf_range(-REACTION_SPREAD, REACTION_SPREAD)
		_opp_wait = opponent_delay
	lights_out.emit()


## The open debug HUD in overlay cells (empty when it is hidden).
func _hud_cells(r: AsciiRenderer) -> Rect2:
	var px: Rect2 = game.controls.panel_rect()
	if px.size.x <= 0.0:
		return Rect2()
	var win := r.get_viewport().get_visible_rect().size
	var k := Vector2(r.output_size) / win / Vector2(r.pitch)
	return Rect2(px.position * k, px.size * k)


## The gantry: a dark housing with five round lamps, top centre. Lamps are
## ellipses in cells (cells are taller than wide) so they look round.
func _draw() -> void:
	var r: AsciiRenderer = game.renderer
	var ov := r.get_overlay()
	if ov == null or ov.cols < 20 or ov.rows < 10:
		return
	r.overlay_enabled = true
	var ry := maxi(2, roundi(ov.rows * 0.045))
	var aspect := float(r.pitch.y) / float(r.pitch.x)
	var rx := maxf(2.0, ry * aspect)
	var gap := maxf(2.0, rx * 0.5)
	var pod := 2.0 * rx + gap
	var w := LAMPS * pod + gap
	var h := 2 * ry + 3
	var x0 := (ov.cols - w) * 0.5
	var y0 := 1
	# The debug HUD, when open, sits in the top left: keep the gantry clear of
	# it (to its right if there is room, else below it).
	var hud := _hud_cells(r)
	if hud.size.x > 0.0 and Rect2(x0, y0, w + 1.0, h).intersects(hud):
		if hud.end.x + 2.0 + w + 1.0 <= ov.cols:
			x0 = hud.end.x + 2.0
		else:
			y0 = ceili(hud.end.y) + 1
	if _after >= 0.0:
		y0 -= roundi(_after / CLEAR_TIME * (h + 3)) # slides up and away
	for y in range(y0, y0 + h):
		for x in range(int(x0), int(x0 + w) + 1):
			ov.cover(x, y, 0.94, HOUSING)
	for x in range(int(x0), int(x0 + w) + 1):
		ov.put_char(x, y0, "=", FRAME_INK)
		ov.put_char(x, y0 + h - 1, "=", FRAME_INK)
	for i in LAMPS:
		var cx := x0 + gap + rx + i * pod
		var cy := y0 + 1.5 + ry
		var lit := counting and i < _lit
		for y in range(floori(cy - ry - 1), ceili(cy + ry + 1)):
			for x in range(floori(cx - rx - 1), ceili(cx + rx + 1)):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				var d := sqrt(dx * dx + dy * dy)
				if d > 1.15:
					continue
				if d > 1.0:
					ov.put_char(x, y, ".", FRAME_INK) # the lamp's rim
				elif lit:
					var g := "@" if d < 0.45 else ("#" if d < 0.8 else "*")
					ov.put_char(x, y, g, LIT_CORE.lerp(LIT_EDGE, clampf(d * 1.1, 0.0, 1.0)))
				else:
					ov.put_char(x, y, "o" if d < 0.8 else ".", OFF_INK)
