## Touch controls while driving (phone only): BRAKE bottom left, NITRO bottom
## right, a small pause button in the top right corner, all inside the safe
## area and sized from the window height. Plain outlines and text in the HUD's
## font, like the rest of the game's on-screen text.
##
## Throttle is automatic: full whenever the race is live (lights out, not
## paused, the player driving) and brake is not held. Holding BRAKE at a
## standstill reverses, as the brake key does. Each finger is tracked by its
## touch index, so BRAKE and NITRO can be held together. The buttons feed the
## existing input actions (throttle, brake, nitro), so a keyboard or gamepad
## still works alongside them.
class_name TouchControls
extends CanvasLayer

const HUD_FONT: Font = preload("res://assets/fonts/HackNerdFontMono-Regular.ttf")
const INK: Color = Color("c8ccdc")
const INK_DIM: Color = Color(0.78, 0.8, 0.86, 0.55)
const ACCENT: Color = Color("ff8a1f")
const NITRO_INK: Color = Color("7fe8ff")
const FILL: Color = Color(0.02, 0.025, 0.05, 0.35)
## Button sizes as fractions of the safe area's height.
const BUTTON_SIZE: Vector2 = Vector2(0.34, 0.24)
const PAUSE_SIZE: float = 0.12
const MARGIN: float = 0.04

var game: Node
var car: Car
## Finger index -> "brake", "nitro", "pause" or "" (a touch on nothing).
var fingers: Dictionary = {}
## True while the buttons are on screen (the player is driving, no menu).
var shown: bool = false
## True while the automatic throttle is pressing `throttle`.
var auto_throttle: bool = false

var _view: Control
var _held := {"brake": false, "nitro": false}


func _ready() -> void:
	layer = 11
	process_physics_priority = -100 # before the car reads its inputs
	process_mode = Node.PROCESS_MODE_ALWAYS # notices the pause (and hides)
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_buttons)
	add_child(_view)


## The buttons' rectangles in viewport pixels.
func rects() -> Dictionary:
	var safe := Mobile.safe_rect(_view.get_viewport())
	var h := safe.size.y
	var m := h * MARGIN
	var bs := Vector2(h * BUTTON_SIZE.x, h * BUTTON_SIZE.y)
	var ps := h * PAUSE_SIZE
	return {
		"brake": Rect2(Vector2(safe.position.x + m, safe.end.y - m - bs.y), bs),
		"nitro": Rect2(Vector2(safe.end.x - m - bs.x, safe.end.y - m - bs.y), bs),
		"pause": Rect2(Vector2(safe.end.x - m - ps, safe.position.y + m), Vector2(ps, ps)),
	}


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
	_view.queue_redraw()


func _physics_process(_delta: float) -> void:
	var brake := false
	var nitro := false
	if shown:
		for b: String in fingers.values():
			brake = brake or b == "brake"
			nitro = nitro or b == "nitro"
	_set_action("brake", brake)
	_set_action("nitro", nitro)
	# Automatic throttle: lights out, driving, brake not held (from any source).
	var live: bool = shown and not game.race_start.counting
	var want := live and not Input.is_action_pressed(&"brake")
	if want != auto_throttle:
		auto_throttle = want
		if want:
			Input.action_press(&"throttle")
		else:
			Input.action_release(&"throttle")


func _set_action(action: String, on: bool) -> void:
	if on == _held[action]:
		return
	_held[action] = on
	if on:
		Input.action_press(StringName(action))
	else:
		Input.action_release(StringName(action))


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null or not shown:
		return
	if t.pressed:
		var hit := ""
		var r := rects()
		for k: String in r:
			if (r[k] as Rect2).grow(r[k].size.y * 0.15).has_point(t.position):
				hit = k
		fingers[t.index] = hit
		if hit == "pause":
			game.pause_menu.open(false)
		if hit != "":
			get_viewport().set_input_as_handled()
	else:
		fingers.erase(t.index)


func _draw_buttons() -> void:
	if not shown:
		return
	var r := rects()
	var held := {}
	for b: String in fingers.values():
		held[b] = true
	_button(r.brake, "BRAKE", INK, held.has("brake"))
	var ink := NITRO_INK if car.nitro_tank > 0.05 else INK_DIM
	_button(r.nitro, "NITRO", ink, held.has("nitro"))
	_button(r.pause, "||", INK, held.has("pause"))


## A plain outlined box with its label; filled a little while held.
func _button(rect: Rect2, label: String, ink: Color, held: bool) -> void:
	var w := maxf(rect.size.y * 0.035, 2.0)
	_view.draw_rect(rect, Color(ink, 0.22) if held else FILL)
	_view.draw_rect(rect, ink if held else Color(ink, 0.75), false, w)
	var size := roundi(rect.size.y * (0.5 if label.length() <= 2 else 0.3))
	var tw := HUD_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := rect.position + Vector2((rect.size.x - tw) * 0.5, rect.size.y * 0.5 + size * 0.35)
	_view.draw_string(HUD_FONT, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
