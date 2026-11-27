## Touch controls while driving (phone only), in one of four schemes (the pause
## menu's CONTROLS, saved as [phone] controls):
##
## - BUTTONS (default): `<` `>` bottom left for the left thumb, BRAKE and NITRO
##   bottom right. The steer buttons go through the car's key path (as A / D,
##   including the slower turn-in at speed); a finger sliding from one to the
##   other switches direction; both held = straight.
## - SLIDER: the left thumb lands anywhere in the left half and slides;
##   steering is proportional to the distance from where it landed (analogue,
##   the stick path), full at SLIDER_TRAVEL x window height, with a small dead
##   zone and a curve; past full travel the origin follows the thumb. BRAKE and
##   NITRO as in BUTTONS.
## - SPLIT: holding the left half steers left, the right half right (key path);
##   both halves = brake, steering straight. A small NITRO above the nitro bar.
## - TILT: TiltInput steers (and the level display turns the picture); BRAKE
##   and NITRO as in BUTTONS.
##
## Every scheme: a small pause button top right; throttle automatic whenever
## the race is live (lights out, not paused, the player driving) and brake is
## not held. All inside the safe area, sized from its height, in plain outlines
## and the HUD font. Fingers are tracked by touch index, so steering, BRAKE and
## NITRO work together. Keyboard and gamepad keep working alongside.
class_name TouchControls
extends CanvasLayer

const HUD_FONT: Font = preload("res://assets/fonts/HackNerdFontMono-Regular.ttf")
const INK: Color = Color("c8ccdc")
const INK_DIM: Color = Color(0.78, 0.8, 0.86, 0.55)
const INK_FAINT: Color = Color(0.78, 0.8, 0.86, 0.18)
const NITRO_INK: Color = Color("7fe8ff")
const FILL: Color = Color(0.02, 0.025, 0.05, 0.35)
## Button sizes as fractions of the safe area's height.
const BUTTON_SIZE: Vector2 = Vector2(0.34, 0.24)
const SMALL_SIZE: Vector2 = Vector2(0.24, 0.14)
const PAUSE_SIZE: float = 0.12
const MARGIN: float = 0.04
const GAP: float = 0.025
## SLIDER: full lock at this travel (x window height), the dead zone (share of
## the travel) and the curve: wheel = sign * amount^SLIDER_EXPONENT.
const SLIDER_TRAVEL: float = 0.32
const SLIDER_DEAD: float = 0.05
const SLIDER_EXPONENT: float = 1.3
## Frame-rate record for the pause menu (seconds of racing kept).
const FPS_WINDOW: float = 5.0

var game: Node
var car: Car
## The driving aids (the brake assist's throttle strength); null = none.
var assist: PhoneAssist
## SLIDER sensitivity: the travel to full lock is SLIDER_TRAVEL / sensitivity.
var slider_sensitivity: float = 1.0
## "buttons", "slider", "split" or "tilt".
var scheme: String = Mobile.CONTROLS[0]
## Finger index -> {kind, x, origin}: kind "brake", "nitro", "pause",
## "left" / "right" (steer buttons), "slider", "half_l" / "half_r" (SPLIT), "".
var fingers: Dictionary = {}
## True while the controls are on screen (the player is driving, no menu).
var shown: bool = false
## True while the automatic throttle is pressing `throttle`.
var auto_throttle: bool = false
## SLIDER: the steering it gives, -1..1 (after the dead zone and curve).
var slider_steer: float = 0.0

var _view: Control
var _held := {"brake": false, "nitro": false}
var _slider_holding: bool = false
var _thr: float = 0.0
var _frame_t: PackedFloat64Array = [] # ticks (s) of the frames drawn while racing
var _last_tick: float = -1.0


func _ready() -> void:
	layer = 11
	process_physics_priority = -100 # before the car reads its inputs
	process_mode = Node.PROCESS_MODE_ALWAYS # notices the pause (and hides)
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_controls)
	add_child(_view)


## The controls' rectangles in viewport pixels for the current scheme (and
## "zone": SLIDER's landing area; "divider": SPLIT's middle x, as a thin rect).
func rects() -> Dictionary:
	var vp := _view.get_viewport()
	var safe := Mobile.safe_rect(vp)
	var h := safe.size.y
	var m := h * MARGIN
	var g := h * GAP
	var bs := Vector2(h * BUTTON_SIZE.x, h * BUTTON_SIZE.y)
	var ps := h * PAUSE_SIZE
	var bottom := safe.end.y - m - bs.y
	var r := {"pause": Rect2(Vector2(safe.end.x - m - ps, safe.position.y + m), Vector2(ps, ps))}
	if scheme == "split":
		var ss := Vector2(h * SMALL_SIZE.x, h * SMALL_SIZE.y)
		r["nitro"] = Rect2(Vector2(safe.get_center().x - ss.x * 0.5, _bar_top() - m * 0.5 - ss.y), ss)
		r["divider"] = Rect2(Vector2(safe.get_center().x, safe.position.y), Vector2(1.0, safe.size.y))
		return r
	r["nitro"] = Rect2(Vector2(safe.end.x - m - bs.x, bottom), bs)
	r["brake"] = Rect2(Vector2(safe.end.x - m - 2.0 * bs.x - g, bottom), bs)
	if scheme == "buttons":
		r["left"] = Rect2(Vector2(safe.position.x + m, bottom), bs)
		r["right"] = Rect2(Vector2(safe.position.x + m + bs.x + g, bottom), bs)
	elif scheme == "slider":
		r["zone"] = Rect2(safe.position, Vector2(safe.size.x * 0.5, safe.size.y))
	return r


## Top of the nitro bar (NitroHud: the bottom rows of the overlay), in viewport pixels.
func _bar_top() -> float:
	var vp := _view.get_viewport().get_visible_rect().size
	var r: AsciiRenderer = game.renderer
	var row := r.rows - 1 - NitroHud.BAR_MARGIN - 2 # the bar's top cell row, less its plate
	return row * r.pitch.y * vp.y / float(maxi(r.output_size.y, 1))


## True while the player is driving with no menu, reel or level select up.
func driving() -> bool:
	if car == null or not car.player_input or get_tree().paused:
		return false
	var at: Node = game.get("attract")
	return at == null or not (at as Attract).busy()


func _process(_delta: float) -> void:
	var s := driving()
	if s != shown:
		shown = s
		if not s:
			fingers.clear()
	var want: String = game.phone_controls()
	if want != scheme:
		scheme = want
		fingers.clear()
	# Frame times while racing, for the pause menu's frame-rate line.
	var now := Time.get_ticks_usec() / 1e6
	if s and not game.race_start.counting:
		if _last_tick >= 0.0:
			_frame_t.append(now)
			while _frame_t.size() > 2 and now - _frame_t[0] > FPS_WINDOW:
				_frame_t.remove_at(0)
		_last_tick = now
	else:
		_last_tick = -1.0
	_view.queue_redraw()


## Average and lowest frame rate over the last FPS_WINDOW s of racing:
## Vector2(average fps, the slowest frame as fps); (0, 0) without enough frames.
func fps_stats() -> Vector2:
	if _frame_t.size() < 10:
		return Vector2.ZERO
	var worst := 0.0
	for i in range(1, _frame_t.size()):
		worst = maxf(worst, _frame_t[i] - _frame_t[i - 1])
	var span := _frame_t[-1] - _frame_t[0]
	return Vector2((_frame_t.size() - 1) / span, 1.0 / worst)


func _physics_process(_delta: float) -> void:
	var brake := false
	var nitro := false
	var left := false
	var right := false
	var half_l := false
	var half_r := false
	if shown:
		for f: Dictionary in fingers.values():
			match String(f.kind):
				"brake": brake = true
				"nitro": nitro = true
				"left": left = true
				"right": right = true
				"half_l": half_l = true
				"half_r": half_r = true
	if half_l and half_r:
		brake = true # SPLIT: both halves = brake, straight
	elif half_l or half_r:
		left = half_l
		right = half_r
	car.touch_steer_left = left
	car.touch_steer_right = right
	_set_action("brake", brake)
	_set_action("nitro", nitro)
	_apply_slider()
	# Automatic throttle: lights out, driving, brake not held (from any source).
	var live: bool = shown and not game.race_start.counting
	var thr := 0.0
	if live and not Input.is_action_pressed(&"brake"):
		thr = assist.throttle if assist != null else 1.0
	if thr != _thr or (thr > 0.0) != auto_throttle:
		_thr = thr
		auto_throttle = thr > 0.0
		if auto_throttle:
			Input.action_press(&"throttle", thr)
		else:
			Input.action_release(&"throttle")


## SLIDER: the first slider finger's distance from its origin, through the
## steering actions (analogue; the car's stick curve undone so the wheel
## follows sign * amount^SLIDER_EXPONENT).
func _apply_slider() -> void:
	slider_steer = 0.0
	if shown and scheme == "slider":
		for f: Dictionary in fingers.values():
			if f.kind == "slider":
				slider_steer = slider_shape(float(f.x) - float(f.origin), _travel())
				break
	if slider_steer == 0.0:
		if _slider_holding:
			Input.action_release(&"steer_left")
			Input.action_release(&"steer_right")
			_slider_holding = false
		return
	var v := pow(absf(slider_steer), 1.0 / maxf(car.stick_steer_exponent, 0.01))
	if slider_steer > 0.0:
		Input.action_release(&"steer_left")
		Input.action_press(&"steer_right", v)
	else:
		Input.action_release(&"steer_right")
		Input.action_press(&"steer_left", v)
	_slider_holding = true


## SLIDER's steering for a sideways distance dx (pixels) with full lock at `travel`.
static func slider_shape(dx: float, travel: float) -> float:
	var a := clampf((absf(dx) / maxf(travel, 1.0) - SLIDER_DEAD) / (1.0 - SLIDER_DEAD), 0.0, 1.0)
	return signf(dx) * pow(a, SLIDER_EXPONENT)


func _travel() -> float:
	return SLIDER_TRAVEL / maxf(slider_sensitivity, 0.01) * _view.get_viewport().get_visible_rect().size.y


## SLIDER's travel to full lock in viewport pixels (with its sensitivity).
func slider_travel() -> float:
	return _travel()


func _set_action(action: String, on: bool) -> void:
	if on == _held[action]:
		return
	_held[action] = on
	if on:
		Input.action_press(StringName(action))
	else:
		Input.action_release(StringName(action))


func _input(event: InputEvent) -> void:
	if not shown:
		return
	var t := event as InputEventScreenTouch
	var d := event as InputEventScreenDrag
	if t != null:
		if not t.pressed:
			fingers.erase(t.index)
			return
		var kind := _hit(t.position)
		fingers[t.index] = {"kind": kind, "x": t.position.x, "origin": t.position.x}
		if kind == "pause":
			game.pause_menu.open(false)
		if kind != "":
			get_viewport().set_input_as_handled()
	elif d != null and fingers.has(d.index):
		var f: Dictionary = fingers[d.index]
		f.x = d.position.x
		match String(f.kind):
			"left", "right":
				# The finger's current side of the two steer buttons.
				var r := rects()
				f.kind = "left" if d.position.x < ((r.left as Rect2).end.x + (r.right as Rect2).position.x) * 0.5 else "right"
			"slider":
				var travel := _travel()
				var dx := float(f.x) - float(f.origin)
				if absf(dx) > travel:
					f.origin = float(f.x) - signf(dx) * travel # past full travel: the origin follows
			"half_l", "half_r":
				f.kind = "half_l" if d.position.x < _view.get_viewport().get_visible_rect().size.x * 0.5 else "half_r"


## What a new touch at `p` controls.
func _hit(p: Vector2) -> String:
	var r := rects()
	for k: String in ["pause", "nitro", "brake", "left", "right"]:
		if r.has(k) and (r[k] as Rect2).grow((r[k] as Rect2).size.y * 0.1).has_point(p):
			return k
	match scheme:
		"slider":
			if (r.zone as Rect2).has_point(p):
				return "slider"
		"split":
			return "half_l" if p.x < (r.divider as Rect2).position.x else "half_r"
	return ""


# --- drawing --------------------------------------------------------------------------

func _draw_controls() -> void:
	if not shown:
		return
	var r := rects()
	var held := {}
	var slider_f: Dictionary = {}
	for f: Dictionary in fingers.values():
		held[f.kind] = true
		if f.kind == "slider" and slider_f.is_empty():
			slider_f = f
	if r.has("left"):
		_button(r.left, "<", INK, held.has("left"))
		_button(r.right, ">", INK, held.has("right"))
	if r.has("brake"):
		_button(r.brake, "BRAKE", INK, held.has("brake") or held.has("half_l") and held.has("half_r"))
	var ink := NITRO_INK if car.nitro_tank > 0.05 else INK_DIM
	_button(r.nitro, "NITRO", ink, held.has("nitro"))
	_button(r.pause, "||", INK, held.has("pause"))
	if scheme == "slider":
		if slider_f.is_empty():
			_hint(r.zone, "slide to steer")
		else:
			_slider(slider_f)
	elif scheme == "split":
		var x: float = (r.divider as Rect2).position.x
		var top: float = (r.divider as Rect2).position.y
		var hh: float = (r.divider as Rect2).size.y
		_view.draw_line(Vector2(x, top + hh * 0.2), Vector2(x, (r.nitro as Rect2).position.y - hh * 0.04), INK_FAINT, maxf(hh * 0.004, 1.0))
		var size := roundi(hh * 0.12)
		var y := top + hh * 0.5 + size * 0.35
		var safe := Mobile.safe_rect(_view.get_viewport())
		_view.draw_string(HUD_FONT, Vector2(safe.position.x + hh * 0.08, y), "<", HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			INK_DIM if held.has("half_l") else INK_FAINT)
		_view.draw_string(HUD_FONT, Vector2(safe.end.x - hh * 0.08 - size * 0.6, y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			INK_DIM if held.has("half_r") else INK_FAINT)


## A plain outlined box with its label; filled a little while held.
func _button(rect: Rect2, label: String, ink: Color, held: bool) -> void:
	var w := maxf(rect.size.y * 0.035, 2.0)
	_view.draw_rect(rect, Color(ink, 0.22) if held else FILL)
	_view.draw_rect(rect, ink if held else Color(ink, 0.75), false, w)
	var size := roundi(rect.size.y * (0.5 if label.length() <= 2 else 0.3))
	var tw := HUD_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := rect.position + Vector2((rect.size.x - tw) * 0.5, rect.size.y * 0.5 + size * 0.35)
	_view.draw_string(HUD_FONT, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


## SLIDER's zone when no thumb is down: a faint outline and a word.
func _hint(zone: Rect2, text: String) -> void:
	var z := zone.grow(-zone.size.y * 0.12)
	z.size.y *= 0.55
	z.position.y = zone.get_center().y - z.size.y * 0.1
	_view.draw_rect(z, INK_FAINT, false, maxf(zone.size.y * 0.003, 1.0))
	var size := roundi(zone.size.y * 0.05)
	var tw := HUD_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_view.draw_string(HUD_FONT, Vector2(z.get_center().x - tw * 0.5, z.get_center().y + size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK_FAINT)


## SLIDER's indicator while a thumb is down: a track of full travel each way
## from the origin, a centre tick and a knob where the thumb is.
func _slider(f: Dictionary) -> void:
	var travel := _travel()
	var h := _view.get_viewport().get_visible_rect().size.y
	var y := h * 0.72
	var o := float(f.origin)
	var w := maxf(h * 0.006, 2.0)
	_view.draw_line(Vector2(o - travel, y), Vector2(o + travel, y), INK_DIM, w)
	for e: float in [-travel, 0.0, travel]:
		_view.draw_line(Vector2(o + e, y - h * 0.02), Vector2(o + e, y + h * 0.02), INK_DIM, w)
	var k := h * 0.05
	var x := clampf(float(f.x), o - travel, o + travel)
	var knob := Rect2(Vector2(x - k * 0.5, y - k * 0.5), Vector2(k, k))
	_view.draw_rect(knob, Color(INK, 0.22))
	_view.draw_rect(knob, INK, false, w)
