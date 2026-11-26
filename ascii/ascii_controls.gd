## Render-setting keys and the HUD panel for an AsciiRenderer, shared by scenes.
##
## Keys: 1-9 mode (emitted as `mode_requested`; the scene decides what a mode
## is, e.g. lighting), [ ] squeeze, ; ' vertical squeeze, - = glyph size,
## , . zoom (emitted as `zoom_requested`, the scene owns its camera), C colour,
## B bg tint, Tab raw 3D, H hud, P screenshot. Scenes add their own lines to the
## panel with `status_text` (above the settings) and `keys_text` (below), and
## name the current mode with `mode_text`.
##
## The panel starts hidden; while it is hidden a small dim legend in the top
## left corner says how to open it (scenes can hide the legend too, e.g. during
## a title sequence, with `legend_allowed`).
class_name AsciiControls
extends Node

signal zoom_requested(step: int)
## The player changed the glyph size with - or = (the new size in px).
signal glyph_size_changed(px: int)
## Keys 1-9: index 0..8.
signal mode_requested(index: int)

const SQUEEZE_STEP: float = 0.05
const BG_LEVELS: Array[float] = [0.0, 0.15, 0.3]
const HUD_FONT: Font = preload("res://assets/fonts/HackNerdFontMono-Regular.ttf")
const LEGEND_TEXT: String = "H  debug menu"
const LEGEND_COLOR: Color = Color(0.72, 0.74, 0.8, 0.85)
const LEGEND_BG: Color = Color(0.0, 0.0, 0.0, 0.6)
const KEYS_HELP: String = """1-9 mode   [ ] squeeze   ; ' v-squeeze
- = glyph size   , . zoom   C colour   B bg tint
Tab raw 3D   H hud   P screenshot"""

@export var renderer: AsciiRenderer
## When false, keys are ignored (e.g. during scripted captures).
@export var enabled: bool = true
## Scene-specific lines shown at the top of the panel.
var status_text: String = ""
## Scene-specific key help shown at the bottom of the panel.
var keys_text: String = ""
## Name of the scene's current mode (keys 1-9), shown at the top of the settings.
var mode_text: String = ""

## False hides the legend (the scene's own reasons: a title sequence, a menu).
var legend_allowed: bool = true
## More shortcuts for the legend, after the debug one (e.g. "Q  camera"); "" = none.
var legend_extra: String = ""

var hud: CanvasLayer
var legend: Control
var _label: Label
var _panel: PanelContainer
var _legend_layer: CanvasLayer
var _legend_label: Label
var _legend_style: StyleBoxFlat


## UI scale for high-density displays: how many device pixels make one logical
## (CSS-sized) pixel, so fixed pixel sizes look the same size everywhere. Under
## 1.2 counts as 1; otherwise snapped to 0.05. Can change at runtime (browser
## zoom, another monitor).
static func display_scale() -> float:
	var s := reported_scale()
	return 1.0 if s < 1.2 else snappedf(s, 0.05)


## When above 0, the HUD, legend and tuning panel text use this scale instead
## of display_scale() (the phone sets it from the window height).
static var ui_scale_override: float = 0.0


## The scale for the HUD, legend and panel text: display_scale(), unless
## ui_scale_override is set.
static func ui_scale() -> float:
	return ui_scale_override if ui_scale_override > 0.0 else display_scale()


## What the platform reports, by the source Godot implements there: the device
## pixel ratio in a browser; the backing scale on macOS (1 or 2); Windows'
## scaling setting through the effective DPI (96 at 100 %); the output scale on
## Wayland. X11 has no per-output scale (its DPI is the monitor's physical
## density, often wrong), so it is 1 there; the glyph default's row limit
## covers dense screens that report 1.
static func reported_scale() -> float:
	if OS.has_feature("web") or OS.get_name() == "macOS":
		return DisplayServer.screen_get_scale()
	if OS.get_name() == "Windows":
		return DisplayServer.screen_get_dpi() / 96.0
	if DisplayServer.get_name() == "Wayland":
		return DisplayServer.screen_get_scale()
	return 1.0


## The glyph size measured independently of the display: [logical px (glyph px
## over display_scale()), text rows on the screen's full height in device px].
static func glyph_measure(px: int) -> Vector2:
	return Vector2(px / display_scale(), float(DisplayServer.screen_get_size().y) / maxf(px, 1.0))


func _ready() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	hud.visible = false # minimised: the legend below says how to open it
	_legend_layer = CanvasLayer.new()
	_legend_layer.layer = 10
	add_child(_legend_layer)
	# A small plate so the text reads over busy glyphs, still discreet.
	var plate := PanelContainer.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = LEGEND_BG
	plate.add_theme_stylebox_override("panel", plate_style)
	_legend_style = plate_style
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := Label.new()
	text.text = LEGEND_TEXT
	text.add_theme_font_override("font", HUD_FONT)
	text.add_theme_color_override("font_color", LEGEND_COLOR)
	plate.add_child(text)
	_legend_label = text
	_legend_layer.add_child(plate)
	legend = plate
	var panel := PanelContainer.new()
	_panel = panel
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
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	panel.add_child(_label)
	apply_scale()


## Sizes the HUD and legend text for ui_scale() (again when it changes).
func apply_scale() -> void:
	var k := ui_scale()
	_legend_style.set_content_margin_all(3.0 * k)
	_legend_style.content_margin_left = 6.0 * k
	_legend_style.content_margin_right = 6.0 * k
	legend.position = Vector2(8.0, 8.0) * k
	_legend_label.add_theme_font_size_override("font_size", roundi(13.0 * k))
	_label.add_theme_font_size_override("font_size", roundi(13.0 * k))
	legend.reset_size()


## The open panel's rectangle in window pixels (empty while hidden).
func panel_rect() -> Rect2:
	return _panel.get_global_rect() if hud.visible and _panel != null else Rect2()


func _process(_delta: float) -> void:
	legend.visible = not hud.visible and legend_allowed
	var lt := LEGEND_TEXT if legend_extra == "" else LEGEND_TEXT + "    " + legend_extra
	if _legend_label.text != lt:
		_legend_label.text = lt
		legend.reset_size() # shrink the plate again when the text gets shorter
	if not hud.visible or renderer == null:
		return
	var s := renderer.settings
	var cam := renderer.scene_viewport.get_camera_3d()
	var gm := glyph_measure(s.glyph_px)
	var text := "%s%s   %d fps\nglyph %d px (%.1f logical, %d rows/screen)  box %dx%d  pitch %dx%d  squeeze %.2f x %.2f\ngrid %d x %d   zoom %.1f   colour %s   bg %.2f\n%s" % [
		mode_text, "  [RAW 3D]" if renderer.raw_view else "", Engine.get_frames_per_second(),
		s.glyph_px, gm.x, roundi(gm.y), renderer.glyph_box.x, renderer.glyph_box.y, renderer.pitch.x, renderer.pitch.y,
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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			mode_requested.emit(k.keycode - KEY_1)
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
			glyph_size_changed.emit(s.glyph_px)
		KEY_EQUAL:
			s.glyph_px += 1
			glyph_size_changed.emit(s.glyph_px)
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
		"raw" if renderer.raw_view else mode_text.validate_filename(), roundi(s.squeeze_x * 100.0)]
	await RenderingServer.frame_post_draw
	renderer.get_output_image().save_png(file)
	print("saved ", ProjectSettings.globalize_path(file))
