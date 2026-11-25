## The in-game menu (Esc, pad Start), drawn in the renderer's overlay cell layer
## over the dimmed scene, in the logo's block letters where the grid has room
## and in plain cells where it does not. Opening it pauses the game (physics,
## lap timer, the reel's driver; no input reaches the car); the music keeps
## playing, lowered and muffled, and the car's sounds go silent.
##
## In a race: Resume, Restart, Music, SFX, Sound check, Return to title, Quit.
## From the reel: Start race, Music, SFX, Sound check, Quit (closing it goes
## back to the reel).
##
## Keys: Up/Down or W/S move, Left/Right or A/D adjust, Enter or Space choose,
## Esc close. Pad: Start opens and closes, D-pad or left stick move and adjust,
## A chooses, B goes back. Volumes are saved when the menu closes.
class_name PauseMenu
extends Node

signal opened
signal closed

enum Item { RESUME, RESTART, START_RACE, VOLUME, MUSIC, SFX, SOUND_CHECK, TITLE, QUIT }
const LABELS: Dictionary = {
	Item.RESUME: "RESUME", Item.RESTART: "RESTART", Item.START_RACE: "START RACE",
	Item.VOLUME: "VOLUME", Item.MUSIC: "MUSIC", Item.SFX: "SFX", Item.SOUND_CHECK: "SOUND CHECK",
	Item.TITLE: "TO TITLE", Item.QUIT: "QUIT",
}
## Sound check: roles and how they are named.
const CHECK: Array = [
	["engine_loop_0", "ENGINE IDLE"], ["engine_loop_1", "ENGINE MID"], ["engine_loop_2", "ENGINE HIGH"],
	["tyre_squeal", "TYRE SQUEAL"], ["tyre_skid", "DRIFT SKID"], ["land", "LANDING"], ["kerb", "KERB KNOCK"],
	["impact_solid", "IMPACT WALL"], ["impact_cone", "IMPACT CONE"], ["nitro_ignite", "NITRO BURST"],
	["nitro_sustain", "NITRO HISS"], ["music_menu", "MENU MUSIC"], ["music_race", "RACE MUSIC"],
]
const DIM: float = 0.62
const PANEL_BG: Color = Color(0.02, 0.025, 0.05)
const INK: Color = Color("c8ccdc")
const INK_DIM: Color = Color("5c6178")
const INK_SEL: Color = Color("ffcf5c")
const ACCENT: Color = Color("ff8a1f")
const BAR_FILL: Color = Color("ffb020")
const STICK_THRESHOLD: float = 0.55
const REPEAT_DELAY: float = 0.35
const REPEAT_INTERVAL: float = 0.08

var game: Node
var renderer: AsciiRenderer
var audio: AudioDirector
var is_open: bool = false
var in_reel: bool = false
var items: Array[int] = []
var selected: int = 0
var check_index: int = 0

var _logo := AsciiLogo.new()
var _t: float = 0.0
var _stick := Vector2i.ZERO
var _hold_dir := Vector2i.ZERO
var _hold_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 110 # after NitroHud: the menu owns the overlay while open


func open(reel: bool) -> void:
	if is_open:
		return
	in_reel = reel
	items.clear()
	if reel:
		items.append(Item.START_RACE)
	else:
		items.append_array([Item.RESUME, Item.RESTART])
	items.append_array([Item.VOLUME, Item.MUSIC, Item.SFX, Item.SOUND_CHECK])
	if not reel and game.get("attract") != null:
		items.append(Item.TITLE)
	items.append(Item.QUIT)
	selected = 0
	is_open = true
	_t = 0.0
	get_tree().paused = true
	audio.set_context(AudioDirector.Context.PAUSED)
	if game.get("rumble") != null:
		game.rumble.stop()
	renderer.overlay_enabled = true
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	audio.stop_audition()
	audio.save_settings()
	get_tree().paused = false
	var ov := renderer.get_overlay()
	if ov != null:
		ov.clear()
	closed.emit()


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	# Held direction repeats (keys and stick).
	if _hold_dir != Vector2i.ZERO:
		_hold_t += delta
		if _hold_t > REPEAT_DELAY:
			_hold_t -= REPEAT_INTERVAL
			_move(_hold_dir)
	_draw()


## Opening (Esc / Start) is handled here too, so it works in the reel and in a
## race alike; while open every input is consumed.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	var b := event as InputEventJoypadButton
	var m := event as InputEventJoypadMotion
	if not is_open:
		var esc := k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE
		var start := b != null and b.pressed and b.button_index == JOY_BUTTON_START
		if (esc or start) and _can_open():
			open(game.attract != null and game.attract.active)
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if k != null:
		var dir := Vector2i.ZERO
		match k.keycode:
			KEY_UP, KEY_W: dir = Vector2i.UP
			KEY_DOWN, KEY_S: dir = Vector2i.DOWN
			KEY_LEFT, KEY_A: dir = Vector2i.LEFT
			KEY_RIGHT, KEY_D: dir = Vector2i.RIGHT
		if dir != Vector2i.ZERO:
			_press(dir, k.pressed, k.echo)
			return
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_choose()
			KEY_ESCAPE:
				close()
			KEY_M:
				audio.toggle_mute()
	elif b != null:
		var dir := Vector2i.ZERO
		match b.button_index:
			JOY_BUTTON_DPAD_UP: dir = Vector2i.UP
			JOY_BUTTON_DPAD_DOWN: dir = Vector2i.DOWN
			JOY_BUTTON_DPAD_LEFT: dir = Vector2i.LEFT
			JOY_BUTTON_DPAD_RIGHT: dir = Vector2i.RIGHT
		if dir != Vector2i.ZERO:
			_press(dir, b.pressed, false)
			return
		if not b.pressed:
			return
		match b.button_index:
			JOY_BUTTON_A:
				_choose()
			JOY_BUTTON_B, JOY_BUTTON_START:
				close()
	elif m != null and (m.axis == JOY_AXIS_LEFT_X or m.axis == JOY_AXIS_LEFT_Y):
		var s := _stick
		var v := 0 if absf(m.axis_value) < STICK_THRESHOLD else int(signf(m.axis_value))
		if m.axis == JOY_AXIS_LEFT_X:
			s.x = v
		else:
			s.y = v
		if s != _stick:
			_stick = s
			var dir := Vector2i(s.x, 0) if s.x != 0 else Vector2i(0, s.y)
			_press(dir, dir != Vector2i.ZERO, false)


func _can_open() -> bool:
	if game.attract != null and game.attract._wipe >= 0.0:
		return false # mid-wipe
	return true


func _press(dir: Vector2i, pressed: bool, echo: bool) -> void:
	if echo:
		return
	if pressed:
		_hold_dir = dir
		_hold_t = 0.0
		_move(dir)
	elif dir == _hold_dir or dir == Vector2i.ZERO:
		_hold_dir = Vector2i.ZERO


func _move(dir: Vector2i) -> void:
	if dir.y != 0:
		selected = posmod(selected + dir.y, items.size())
		return
	match items[selected]:
		Item.VOLUME:
			audio.set_master_volume(audio.master_volume + dir.x / float(AudioDirector.SLIDER_STEPS))
		Item.MUSIC:
			audio.set_music_volume(audio.music_volume + dir.x / float(AudioDirector.SLIDER_STEPS))
		Item.SFX:
			audio.set_sfx_volume(audio.sfx_volume + dir.x / float(AudioDirector.SLIDER_STEPS))
		Item.SOUND_CHECK:
			check_index = posmod(check_index + dir.x, CHECK.size())
			audio.stop_audition()


func _choose() -> void:
	match items[selected]:
		Item.RESUME:
			close()
		Item.RESTART:
			close()
			game.reset_to_grid()
		Item.START_RACE:
			close()
			game.attract.start_game()
		Item.SOUND_CHECK:
			audio.audition(CHECK[check_index][0])
		Item.TITLE:
			close()
			game.attract.start(false)
		Item.QUIT:
			audio.quit()
		Item.VOLUME, Item.MUSIC, Item.SFX:
			_move(Vector2i.RIGHT)


# --- drawing ------------------------------------------------------------------------

func _draw() -> void:
	var ov := renderer.get_overlay()
	if ov == null or ov.cols < 10 or ov.rows < 10:
		return
	_logo.overlay = ov
	ov.clear()
	renderer.overlay_enabled = true
	for y in ov.rows:
		for x in ov.cols:
			ov.cover(x, y, DIM)
	var title := "MENU" if in_reel else "PAUSED"
	var n := items.size()
	# Big labels (block letters) when the grid has the rows for them.
	var big := ov.rows >= 9 + 6 * n + 4 and ov.cols >= 90
	var label_w := 0
	for it in items:
		label_w = maxi(label_w, AsciiLogo.mini_width(LABELS[it], Vector2i.ONE, 0) if big else (LABELS[it] as String).length())
	var bar_w := clampi(ov.cols / 8, 12, 30)
	var value_w := bar_w + 8
	if big:
		var check_w := 0
		for c: Array in CHECK:
			check_w = maxi(check_w, AsciiLogo.mini_width("< %s >" % c[1], Vector2i.ONE, 0))
		value_w = maxi(bar_w + 3 + AsciiLogo.mini_width("100%", Vector2i.ONE, 0), check_w)
	var row_h := 6 if big else 2
	var content_w := label_w + 4 + value_w
	var tpix := Vector2i(2, 1) if AsciiLogo.mini_width(title, Vector2i(2, 1), 1) <= content_w and ov.rows >= 50 else Vector2i.ONE
	var title_w := AsciiLogo.mini_width(title, tpix, 1 if tpix.x > 1 else 0)
	var w := maxi(content_w, title_w) + 8
	var h := 5 * tpix.y + 3 + n * row_h + 3
	var x0 := (ov.cols - w) / 2
	var y0 := maxi((ov.rows - h) / 2, 0)
	for y in range(y0 - 1, y0 + h + 1):
		for x in range(x0 - 2, x0 + w + 2):
			ov.cover(x, y, 0.94, PANEL_BG)
	# Accent rules top and bottom.
	for x in range(x0 - 2, x0 + w + 2):
		ov.put_char(x, y0 - 1, "=", ACCENT.lerp(Color.BLACK, 0.4))
		ov.put_char(x, y0 + h, "=", ACCENT.lerp(Color.BLACK, 0.4))
	_logo.draw_mini(title, x0 + (w - title_w) / 2, y0 + 1, tpix, 1 if tpix.x > 1 else 0, func(f: float) -> Color: return AsciiLogo._gradient(f), 0.0)
	var y := y0 + 5 * tpix.y + 3
	var lx := x0 + 4
	for i in n:
		var it: int = items[i]
		var sel := i == selected
		var ink := INK_SEL if sel else INK
		if sel:
			var blink := 0.65 + 0.35 * cos(_t * 6.0)
			var arrow := ACCENT.lerp(Color.BLACK, 1.0 - blink)
			if big:
				_logo.draw_mini(">", lx - 5, y, Vector2i.ONE, 0, func(_f: float) -> Color: return arrow, 0.0)
			else:
				ov.put_char(lx - 3, y, ">", arrow)
		if big:
			_logo.draw_mini(LABELS[it], lx, y, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
		else:
			ov.text(lx, y, LABELS[it], ink)
		var vx := lx + label_w + 4
		var vy := y
		match it:
			Item.VOLUME:
				_slider(ov, vx, vy, bar_w, audio.master_volume, sel, big)
			Item.MUSIC:
				_slider(ov, vx, vy, bar_w, audio.music_volume, sel, big)
			Item.SFX:
				_slider(ov, vx, vy, bar_w, audio.sfx_volume, sel, big)
			Item.SOUND_CHECK:
				var name: String = CHECK[check_index][1]
				var has := audio.table.has(CHECK[check_index][0])
				var c := ink if has else INK_DIM
				if big:
					_logo.draw_mini("< %s >" % name, vx, vy, Vector2i.ONE, 0, func(_f: float) -> Color: return c, 0.0)
				else:
					ov.text(vx, vy, "< %s >" % name.to_lower(), c)
				if sel:
					ov.text(vx, vy + (5 if big else 1), "Enter / A plays it" if has else "(no file)", INK_DIM)
		y += row_h
	var hint := "Up/Down move  Left/Right adjust  Enter choose  Esc close  M mute" + ("  [MUTED]" if audio.muted else "")
	if hint.length() > w:
		hint = "Arrows  Enter  Esc" + (" [MUTED]" if audio.muted else "")
	ov.text(x0 + (w - hint.length()) / 2, y0 + h - 1, hint, INK_DIM)


## A volume bar: one row of cells, or (big) three rows with the value in block
## letters beside it.
func _slider(ov: AsciiOverlay, x: int, y: int, w: int, v: float, sel: bool, big: bool) -> void:
	var filled := roundi(v * w)
	var rows := [y + 1, y + 2, y + 3] if big else [y]
	for r: int in rows:
		ov.put_char(x, r, "[", INK_DIM)
		ov.put_char(x + 1 + w, r, "]", INK_DIM)
		for i in w:
			var on := i < filled
			var c := BAR_FILL.lerp(ACCENT, float(i) / maxf(w - 1, 1)) if on else INK_DIM
			if on and not sel:
				c = c.lerp(INK, 0.35)
			ov.put_char(x + 1 + i, r, "#" if on else "-", c)
	var label := "%d%%" % roundi(v * 100.0)
	var ink := INK_SEL if sel else INK
	if big:
		_logo.draw_mini(label, x + w + 4, y, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
	else:
		ov.text(x + w + 3, y, "%4s" % label, ink)
