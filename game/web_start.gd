## Web build only: a start screen before the demo reel while the browser has
## not allowed sound yet. Browsers keep a page's audio suspended until the first
## click or key press; without this screen that press is the one that leaves the
## reel for a race, so the title music would never be heard on first load.
##
## Shows the finished logo over the dimmed grid with "CLICK OR PRESS ANY KEY",
## no music. The first key press or click (which the browser counts as the
## gesture that allows sound) is consumed and starts the reel, logo intro and
## title music from the top; the reel's own "press any key" then works as usual.
## Gamepad buttons are not such a gesture in browsers, so a pad press is
## swallowed and a line under the prompt explains it.
##
## Game decides whether to show it (needed()); while it is up Game treats it
## like the reel (menu context, no music, no HUD legend).
class_name WebStart
extends Node

signal finished

const PROMPT: String = "CLICK OR PRESS ANY KEY"
const PAD_NOTE: String = "a gamepad button cannot switch on sound in a browser: click or press a key"
const NOTE_INK: Color = Color("aab0c4")
const DIM: float = 0.55

var game: Node
var active: bool = true
var _t: float = 0.0
var _pad_note: bool = false
var _logo := AsciiLogo.new()


## True on the web when the browser does not yet let the page play sound (a
## probe AudioContext created now would start suspended).
static func needed() -> bool:
	if not OS.has_feature("web"):
		return false
	var state: Variant = JavaScriptBridge.eval("""(function () {
		try {
			var C = window.AudioContext || window.webkitAudioContext;
			var c = new C(); var s = c.state; c.close(); return s;
		} catch (e) { return "unknown"; }
	})()""", true)
	return str(state) != "running"


func _ready() -> void:
	process_priority = 120 # after NitroHud and the pause menu: owns the overlay while up
	_logo.prompt_text = PROMPT


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	var r: AsciiRenderer = game.renderer
	if not r.is_atlas_ready():
		return
	var ov := r.get_overlay()
	r.overlay_enabled = true
	ov.clear()
	for y in ov.rows:
		for x in ov.cols:
			ov.cover(x, y, DIM)
	_logo.overlay = ov
	_logo.atlas = r.atlas
	_logo.pitch = r.pitch
	_logo.draw(AsciiLogo.GLINT_START + AsciiLogo.GLINT_TIME + 0.1) # the finished logo
	_logo.draw_prompt(_t)
	if _pad_note:
		var y := int(AsciiLogo.PROMPT_Y * ov.rows) + 8
		ov.text((ov.cols - PAD_NOTE.length()) / 2, y, PAD_NOTE, NOTE_INK)


## Every input stops here while the screen is up; a key press or click starts.
func _input(event: InputEvent) -> void:
	if not active:
		return
	var go := false
	if event is InputEventKey:
		# Not Esc: browsers do not count it as the gesture that allows sound.
		go = event.pressed and not event.echo and event.keycode != KEY_ESCAPE
	elif event is InputEventMouseButton:
		go = event.pressed
	elif event is InputEventJoypadButton and event.pressed:
		_pad_note = true
	get_viewport().set_input_as_handled()
	if go:
		active = false
		game.renderer.get_overlay().clear()
		finished.emit()
		queue_free()
