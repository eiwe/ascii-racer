## Render-setting keys and the HUD panel for an AsciiRenderer, shared by scenes.
##
## Keys: 1-5 method, [ ] squeeze, ; ' vertical squeeze, - = glyph size,
## , . zoom (emitted as `zoom_requested`, the scene owns its camera), C colour,
## B bg tint, Tab raw 3D, H hud, P screenshot. Scenes add their own lines to the
## panel with `status_text` (above the settings) and `keys_text` (below).
class_name AsciiControls
extends Node

signal zoom_requested(step: int)

const SQUEEZE_STEP: float = 0.05
const BG_LEVELS: Array[float] = [0.0, 0.15, 0.3]
const HUD_FONT: Font = preload("res://assets/fonts/HackNerdFontMono-Regular.ttf")
const KEYS_HELP: String = """1-5 method   [ ] squeeze   ; ' v-squeeze
- = glyph size   , . zoom   C colour   B bg tint
Tab raw 3D   H hud   P screenshot"""

@export var renderer: AsciiRenderer
## When false, keys are ignored (e.g. during scripted captures).
@export var enabled: bool = true
## Scene-specific lines shown at the top of the panel.
var status_text: String = ""
## Scene-specific key help shown at the bottom of the panel.
var keys_text: String = ""

var hud: CanvasLayer
var _label: Label


## UI scale for high-density displays: 2.0 on a Retina Mac, where one logical
## pixel is two physical ones and fixed pixel sizes look half as big; 1.0 elsewhere.
static func display_scale() -> float:
	if OS.get_name() != "macOS":
		return 1.0
	var s := DisplayServer.screen_get_scale()
	return s if s >= 1.5 else 1.0


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
	panel.position = Vector2(8.0, 8.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_override("font", HUD_FONT)
	_label.add_theme_font_size_override("font_size", roundi(13.0 * display_scale()))
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	panel.add_child(_label)


func _process(_delta: float) -> void:
	if not hud.visible or renderer == null:
		return
	var s := renderer.settings
	var cam := renderer.scene_viewport.get_camera_3d()
	var text := "%s%s   %d fps\nglyph %dpx (%dx%d)  pitch %dx%d  squeeze %.2f x %.2f\ngrid %d x %d   zoom %.1f   colour %s   bg %.2f\n%s" % [
		s.method_name(), "  [RAW 3D]" if renderer.raw_view else "", Engine.get_frames_per_second(),
		s.glyph_px, renderer.glyph_box.x, renderer.glyph_box.y, renderer.pitch.x, renderer.pitch.y,
		s.squeeze_x, s.squeeze_y, renderer.cols, renderer.rows, cam.size if cam != null else 0.0,
		"full" if s.color_mode == AsciiSettings.ColorMode.FULL else "mono", s.bg_strength, KEYS_HELP]
	if status_text != "":
		text = status_text + "\n\n" + text
	if keys_text != "":
		text += "\n" + keys_text
	_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not enabled or renderer == null:
		return
	var s := renderer.settings
	match k.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			s.method = (k.keycode - KEY_1) as AsciiSettings.Method
		KEY_BRACKETLEFT:
			set_squeeze(s.squeeze_x - SQUEEZE_STEP, s.squeeze_y - SQUEEZE_STEP)
		KEY_BRACKETRIGHT:
			set_squeeze(s.squeeze_x + SQUEEZE_STEP, s.squeeze_y + SQUEEZE_STEP)
		KEY_SEMICOLON:
			set_squeeze(s.squeeze_x, s.squeeze_y - SQUEEZE_STEP)
		KEY_APOSTROPHE:
			set_squeeze(s.squeeze_x, s.squeeze_y + SQUEEZE_STEP)
		KEY_MINUS:
			s.glyph_px -= 1
		KEY_EQUAL:
			s.glyph_px += 1
		KEY_COMMA:
			zoom_requested.emit(-1)
		KEY_PERIOD:
			zoom_requested.emit(1)
		KEY_C:
			s.color_mode = AsciiSettings.ColorMode.MONO if s.color_mode == AsciiSettings.ColorMode.FULL else AsciiSettings.ColorMode.FULL
		KEY_B:
			var i := BG_LEVELS.find(s.bg_strength)
			s.bg_strength = BG_LEVELS[(i + 1) % BG_LEVELS.size()]
		KEY_TAB:
			renderer.raw_view = not renderer.raw_view
		KEY_H:
			hud.visible = not hud.visible
		KEY_P:
			screenshot()
		_:
			return
	get_viewport().set_input_as_handled()


func set_squeeze(x: float, y: float) -> void:
	# Snap to the step so repeated presses land on round values.
	var s := renderer.settings
	s.squeeze_x = snappedf(x, 0.01)
	s.squeeze_y = snappedf(y, 0.01)


## Saves what is on screen (ASCII, or raw 3D in raw view) to user://shots.
func screenshot() -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var s := renderer.settings
	var file := "%s/%s_%s_sq%03d.png" % [dir, Time.get_datetime_string_from_system().replace(":", "-"),
		"raw" if renderer.raw_view else s.method_name(), roundi(s.squeeze_x * 100.0)]
	await RenderingServer.frame_post_draw
	renderer.get_output_image().save_png(file)
	print("saved ", ProjectSettings.globalize_path(file))
