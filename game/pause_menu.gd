## The in-game menu (Esc, pad Start), drawn in the renderer's overlay cell layer
## over the dimmed scene, in the logo's block letters where the grid has room
## and in plain cells where it does not. Opening it pauses the game (physics,
## lap timer, the reel's driver; no input reaches the car); the music keeps
## playing, lowered and muffled, and the car's sounds go silent.
##
## In a race: Resume, Restart, Opponent, Zoom, Volume, Music, SFX, Sound check,
## Return to title, Quit. From the reel: Start race, Opponent, Zoom, Volume,
## Music, SFX, Sound check, Quit (closing it goes back to the reel).
##
## Keys: Up/Down or W/S move, Left/Right or A/D adjust, Enter or Space choose,
## Esc close. Pad: Start opens and closes, D-pad or left stick move and adjust,
## A chooses, B goes back. Volumes are saved when the menu closes.
class_name PauseMenu
extends Node

signal opened
signal closed

enum Item { RESUME, RESTART, CHANGE_TRACK, START_RACE, OPPONENT, ZOOM, VOLUME, MUSIC, SFX, SOUND_CHECK, TITLE, QUIT, CAMERA, GLYPH, FLIP }
const LABELS: Dictionary = {
	Item.RESUME: "RESUME", Item.RESTART: "RESTART", Item.CHANGE_TRACK: "CHANGE TRACK", Item.START_RACE: "START RACE",
	Item.OPPONENT: "OPPONENT", Item.ZOOM: "ZOOM", Item.VOLUME: "VOLUME", Item.MUSIC: "MUSIC", Item.SFX: "SFX", Item.SOUND_CHECK: "SOUND CHECK",
	Item.TITLE: "TO TITLE", Item.QUIT: "QUIT",
	Item.CAMERA: "CAMERA", Item.GLYPH: "GLYPH SIZE", Item.FLIP: "FLIP STEERING",
}
## Phone rows (Mobile.active()), after ZOOM. A later row joins this list.
const PHONE_ITEMS: Array[int] = [Item.CAMERA, Item.GLYPH, Item.FLIP]
## Phone: rows this many cells apart, and taps ignored this long after opening
## (the tap that opened it). While open, the glyphs grow so the menu fills the
## height (phone_menu_px): single-cell text at the phone's driving size is too
## small to read or tap.
const PHONE_ROW_H: int = 2
const PHONE_TAP_GRACE: float = 0.2
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
var _opponent_at_open: int = 0
## Phone: [cell rect, item index, value x, bar width] per row, from the last draw.
var _hits: Array = []


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
		if game.get("attract") != null:
			items.append(Item.CHANGE_TRACK)
	if Mobile.active():
		# No sound check on the phone (a row less to fit); the phone's own rows.
		items.append_array([Item.OPPONENT, Item.ZOOM])
		items.append_array(PHONE_ITEMS)
		items.append_array([Item.VOLUME, Item.MUSIC, Item.SFX])
	else:
		items.append_array([Item.OPPONENT, Item.ZOOM, Item.VOLUME, Item.MUSIC, Item.SFX, Item.SOUND_CHECK])
	if not reel and game.get("attract") != null:
		items.append(Item.TITLE)
	if not OS.has_feature("web"):
		items.append(Item.QUIT) # a browser page cannot quit
	selected = 0
	_opponent_at_open = audio.opponent_level
	if Mobile.active():
		renderer.settings.glyph_px = phone_menu_px()
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
	if Mobile.active() and game.has_method("default_glyph_px"):
		renderer.settings.glyph_px = game.default_glyph_px() # the driving size again
	audio.stop_audition()
	audio.save_settings()
	get_tree().paused = false
	# The opponent setting applies on closing (in a race; the reel is solo).
	if not in_reel and audio.opponent_level != _opponent_at_open and game.has_method("update_opponent"):
		game.update_opponent(_opponent_at_open == 0)
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
	if Mobile.active():
		var mb := event as InputEventMouseButton
		var mm := event as InputEventMouseMotion
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tap(mb.position, false)
		elif mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			tap(mm.position, true)
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
		Item.OPPONENT:
			audio.set_opponent_level(clampi(audio.opponent_level + dir.x, 0, 5))
		Item.ZOOM:
			audio.set_zoom_setting(clampi(audio.zoom_setting + dir.x, 0, FollowCamera.ZOOM_STEPS.size()))
		Item.VOLUME:
			audio.set_master_volume(audio.master_volume + dir.x / float(AudioDirector.SLIDER_STEPS))
		Item.MUSIC:
			audio.set_music_volume(audio.music_volume + dir.x / float(AudioDirector.SLIDER_STEPS))
		Item.SFX:
			audio.set_sfx_volume(audio.sfx_volume + dir.x / float(AudioDirector.SLIDER_STEPS))
		Item.SOUND_CHECK:
			check_index = posmod(check_index + dir.x, CHECK.size())
			audio.stop_audition()
		Item.CAMERA:
			var chase: bool = audio.phone_get("camera", "chase") == "iso"
			audio.phone_set("camera", "chase" if chase else "iso")
			if not in_reel and game.has_method("set_chase_view"):
				game.set_chase_view(chase)
		Item.GLYPH:
			# Larger glyphs = fewer rows.
			game.set_phone_rows(game.phone_rows() - dir.x * Mobile.ROWS_STEP)
		Item.FLIP:
			audio.phone_set("flip", not bool(audio.phone_get("flip", false)))
			if game.get("tilt") != null:
				game.tilt.flip = bool(audio.phone_get("flip", false))


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
		Item.CHANGE_TRACK:
			close()
			game.attract.change_track()
		Item.SOUND_CHECK:
			audio.audition(CHECK[check_index][0])
		Item.TITLE:
			close()
			game.attract.start(false)
		Item.QUIT:
			audio.quit()
		Item.OPPONENT, Item.VOLUME, Item.MUSIC, Item.SFX, Item.CAMERA, Item.GLYPH, Item.FLIP:
			_move(Vector2i.RIGHT)
		Item.ZOOM:
			# Enter cycles, back to AUTO after the farthest step.
			audio.set_zoom_setting((audio.zoom_setting + 1) % (FollowCamera.ZOOM_STEPS.size() + 1))


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
	var row_h := 6 if big else (PHONE_ROW_H if Mobile.active() else 2)
	_hits.clear()
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
		_hits.append([Rect2i(x0 - 2, y - (row_h - 1) / 2, w + 4, row_h), i, vx, bar_w])
		match it:
			Item.CAMERA, Item.GLYPH, Item.FLIP:
				var txt := "< %s >" % phone_value(it)
				if big:
					_logo.draw_mini(txt, vx, vy, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
				else:
					ov.text(vx, vy, txt, ink)
				if sel:
					# Beside the value in plain cells, under it with block letters.
					if big:
						ov.text(vx, vy + 5, phone_note(it), INK_DIM)
					else:
						ov.text(vx + txt.length() + 2, vy, phone_note(it), INK_DIM)
			Item.OPPONENT:
				var v := "OFF" if audio.opponent_level == 0 else str(audio.opponent_level)
				var txt := "< %s >" % v
				if big:
					_logo.draw_mini(txt, vx, vy, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
				else:
					ov.text(vx, vy, txt, ink)
				if sel:
					ov.text(vx, vy + (5 if big else 1), "applies when the menu closes" if not in_reel else "for the next race", INK_DIM)
			Item.ZOOM:
				var txt := "< %s >" % zoom_text(audio.zoom_setting)
				if big:
					_logo.draw_mini(txt, vx, vy, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
				else:
					ov.text(vx, vy, txt, ink)
				if sel:
					ov.text(vx, vy + (5 if big else 1), "iso view: AUTO fits the window; higher numbers show more", INK_DIM)
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
	if Mobile.active():
		hint = "Tap a row   tap < or > to change   Back resumes" + ("  [MUTED]" if audio.muted else "")
	if hint.length() > w:
		hint = "Arrows  Enter  Esc" + (" [MUTED]" if audio.muted else "")
	ov.text(x0 + (w - hint.length()) / 2, y0 + h - 1, hint, INK_DIM)


## Phone: the glyph size while the menu is open, so its rows (title, items,
## hint) fill about the window height; never smaller than the driving size.
func phone_menu_px() -> int:
	var need := 5 + 3 + items.size() * PHONE_ROW_H + 3 + 4
	var h := renderer.get_viewport().get_visible_rect().size.y
	return clampi(floori(h / float(need)), renderer.settings.glyph_px, 64)


## A phone row's value.
func phone_value(it: int) -> String:
	match it:
		Item.CAMERA:
			return "CHASE" if audio.phone_get("camera", "chase") != "iso" else "ISO"
		Item.GLYPH:
			return "%d PX" % game.default_glyph_px()
		Item.FLIP:
			return "ON" if bool(audio.phone_get("flip", false)) else "OFF"
	return ""


func phone_note(it: int) -> String:
	match it:
		Item.CAMERA:
			return "the view races start in"
		Item.GLYPH:
			return "%d rows on the screen" % game.phone_rows()
		Item.FLIP:
			return "if tilting right steers left"
	return ""


## Phone: a tap (or, on a volume bar, a drag) at `pos` in window pixels. A tap
## on a row selects it; on its value, the left half steps down and the right
## half up (a bar takes the tapped level); on an action row it chooses it.
func tap(pos: Vector2, drag: bool) -> void:
	if _t < PHONE_TAP_GRACE and not drag:
		return
	var r := renderer
	var win := r.get_viewport().get_visible_rect().size
	var cell := Vector2i((pos * Vector2(r.output_size) / win / Vector2(r.pitch)).floor())
	for h: Array in _hits:
		if not (h[0] as Rect2i).has_point(cell):
			continue
		var i: int = h[1]
		var it: int = items[i]
		var vx: int = h[2]
		var bar_w: int = h[3]
		selected = i
		if it in [Item.VOLUME, Item.MUSIC, Item.SFX] and cell.x >= vx:
			var v := clampf(float(cell.x - vx) / float(bar_w), 0.0, 1.0)
			match it:
				Item.VOLUME: audio.set_master_volume(v)
				Item.MUSIC: audio.set_music_volume(v)
				Item.SFX: audio.set_sfx_volume(v)
			return
		if drag:
			return
		var adjustable := it in [Item.OPPONENT, Item.ZOOM, Item.SOUND_CHECK, Item.CAMERA, Item.GLYPH, Item.FLIP]
		if adjustable:
			if cell.x >= vx:
				var txt_w := ("< %s >" % (phone_value(it) if it in PHONE_ITEMS else "XXXX")).length()
				_move(Vector2i.LEFT if cell.x < vx + txt_w / 2 else Vector2i.RIGHT)
		else:
			_choose()
		return


## The ZOOM row's value: AUTO or the step's multiplier.
static func zoom_text(z: int) -> String:
	if z <= 0:
		return "AUTO"
	return "%.2f" % FollowCamera.ZOOM_STEPS[clampi(z - 1, 0, FollowCamera.ZOOM_STEPS.size() - 1)]


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
