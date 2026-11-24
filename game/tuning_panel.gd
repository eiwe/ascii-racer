## Live tuning overlay on the right of the screen: the curated CarTuning.PANEL
## parameters with their values, a * where a value differs from the preset.
##
## Pad: Start toggles; D-pad up/down selects, left/right adjusts (hold to
## repeat); X resets the selected value; LB/RB cycle presets and right-stick
## click saves (both also while closed). Keys: F1 toggles; arrows select/adjust
## while open (they drive again when closed); Backspace resets; F2/F3 presets;
## F5 saves. Emits `preset_changed` and `saved` so the game can flash them.
class_name TuningPanel
extends Node

signal preset_changed(preset: String)
signal saved(path: String)

const HUD_FONT: Font = preload("res://assets/fonts/HackNerdFontMono-Regular.ttf")
const REPEAT_DELAY: float = 0.35
const REPEAT_INTERVAL: float = 0.07
const HELP: String = """D-pad/arrows select, adjust (hold)
X/Bksp reset value  LB RB/F2 F3 preset
RS click/F5 save    Start/F1 close"""

var tuning: CarTuning
var car: Car
## When false, input is ignored (scripted tests turn it on).
var enabled: bool = true
var is_open: bool = false
var selected: int = 0

var hud: CanvasLayer
var _label: Label
var _held: StringName = &""
var _repeat: float = 0.0


func _ready() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.set_content_margin_all(8.0)
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -8.0
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	hud.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_override("font", HUD_FONT)
	_label.add_theme_font_size_override("font_size", roundi(13.0 * AsciiControls.display_scale()))
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	panel.add_child(_label)
	hud.visible = false


func set_open(open: bool) -> void:
	is_open = open
	hud.visible = open
	car.arrow_keys_drive = not open
	_held = &""


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or event.is_echo():
		return
	if event.is_action_pressed(&"tune_toggle"):
		set_open(not is_open)
	elif event.is_action_pressed(&"preset_next"):
		preset_changed.emit(tuning.cycle(1))
	elif event.is_action_pressed(&"preset_prev"):
		preset_changed.emit(tuning.cycle(-1))
	elif event.is_action_pressed(&"tune_save"):
		saved.emit(tuning.save_custom())
	elif is_open and event.is_action_pressed(&"tune_reset"):
		tuning.reset_value(CarTuning.PANEL[selected][1])
	else:
		var hit := false
		for a: StringName in [&"tune_up", &"tune_down", &"tune_left", &"tune_right"]:
			if is_open and event.is_action_pressed(a):
				_act(a)
				_held = a
				_repeat = REPEAT_DELAY
				hit = true
				break
		if not hit:
			return
	get_viewport().set_input_as_handled()


func _act(a: StringName) -> void:
	var n := CarTuning.PANEL.size()
	match a:
		&"tune_up":
			selected = posmod(selected - 1, n)
		&"tune_down":
			selected = posmod(selected + 1, n)
		&"tune_left", &"tune_right":
			var e: Array = CarTuning.PANEL[selected]
			var step: float = e[3]
			var v := float(car.get_indexed(e[1])) + (step if a == &"tune_right" else -step)
			tuning.set_value(e[1], snappedf(v, step))


func _process(delta: float) -> void:
	# Hold to repeat the last select/adjust action.
	if _held != &"":
		if not Input.is_action_pressed(_held) or not is_open:
			_held = &""
		else:
			_repeat -= delta
			while _repeat <= 0.0:
				_act(_held)
				_repeat += REPEAT_INTERVAL
	if is_open:
		_label.text = _text()


static func _fmt(v: float, step: float) -> String:
	var decimals := 0 if step >= 1.0 else (1 if step >= 0.1 else (2 if step >= 0.01 else 3))
	return String.num(v, decimals)


func _text() -> String:
	var mods := tuning.modified_count()
	var lines := PackedStringArray()
	lines.append("TUNING   preset %s%s" % [tuning.current, (" (%d changed)" % mods) if mods > 0 else ""])
	var group := ""
	for i in CarTuning.PANEL.size():
		var e: Array = CarTuning.PANEL[i]
		if e[0] != group:
			group = e[0]
			lines.append(group)
		var v := float(car.get_indexed(e[1]))
		var mark := "*" if tuning.is_modified(e[1]) else " "
		var was := ("  (%s)" % _fmt(float(tuning.preset_value(e[1])), e[3])) if mark == "*" else ""
		lines.append("%s %-17s %7s %s%s" % [">" if i == selected else " ", e[2], _fmt(v, e[3]), mark, was])
	lines.append("")
	lines.append(HELP)
	return "\n".join(lines)
