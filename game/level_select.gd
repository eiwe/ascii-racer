## The level select, between the reel and a race: a large live preview of the
## selected track (the whole circuit from a high, slowly orbiting camera, lit
## for its time of day), big < > arrows at the screen edges (the tracks wrap,
## so both always show), the track's name in the logo's block letters with a
## line of facts, and three rows: TIME OF DAY, OPPONENT, START. All drawn in
## the renderer's overlay cell layer.
##
## Controls: with the preview focused left / right change the track; up / down
## move between the preview and the rows; left / right change a row; Enter,
## Space or pad A start from anywhere; Esc or pad B go back to the reel. Pad
## d-pad and left stick work throughout; a mouse click on an arrow, a row or
## START works too.
##
## Changing the track wipes over the swap (the world rebuilds the circuit
## under the wipe). The selection and each track's time of day and opponent
## level are saved with the settings.
class_name LevelSelect
extends Node

signal start_requested
signal back_requested

enum Focus { PREVIEW, TIME, OPPONENT, START }
const TIMES: PackedStringArray = ["morning", "noon", "night"]
const WIPE_TIME: float = 0.45
const ORBIT_SPEED: float = 0.09 ## rad/s
const STICK_THRESHOLD: float = 0.55

const INK: Color = Color("c8ccdc")
const INK_DIM: Color = Color("6a7088")
const INK_SEL: Color = Color("ffcf5c")
const ACCENT: Color = Color("ff8a1f")
const PANEL_BG: Color = Color(0.02, 0.025, 0.05)

var game: Node
var active: bool = false
var focus: int = Focus.PREVIEW
var index: int = 0 ## into Tracks.ALL

var _cam: Camera3D
var _angle: float = 0.0
var _t: float = 0.0
var _logo := AsciiLogo.new()
var _wipe: float = -1.0
var _wipe_dir: int = 0
var _stick := Vector2i.ZERO
## Clickable areas this frame (overlay cells): [Rect2i, action].
var _hits: Array = []


func _ready() -> void:
	process_priority = 115 # after NitroHud / RaceStart, before the pause menu's draw


func track_id() -> String:
	return Tracks.ALL[index].id


## Shows the select on the saved track (loading it into the world).
func open() -> void:
	active = true
	_t = 0.0
	focus = Focus.PREVIEW
	_wipe = -1.0
	index = maxi(Tracks.ids().find(game.audio.track_id), 0)
	_show_track()
	_cam = Camera3D.new()
	_cam.name = "SelectCamera"
	_cam.fov = 42.0
	_cam.near = 0.5
	_cam.far = 2000.0 # the spread-out ground reaches the corners at 21:9
	game.world.add_child(_cam)
	_cam.current = true
	game.lighting.fog_suppressed = true
	game.renderer.distance_fade = Vector2.ZERO
	_place_camera(0.0)


func close() -> void:
	if not active:
		return
	active = false
	game.lighting.fog_suppressed = false
	_set_ground_scale(1.0)
	game.lighting.set_mode(game.lighting.mode) # the mode's own shadow distance
	if _cam != null:
		_cam.queue_free()
		_cam = null
	game.set_chase_view(false)
	var ov: AsciiOverlay = game.renderer.get_overlay()
	if ov != null:
		ov.clear()


## The selected track in the world, its saved time of day lit, the car on its grid.
func _show_track() -> void:
	game.set_track(track_id())
	game.apply_time_of_day(game.audio.track_time(track_id()))
	game.car.player_input = false
	game.car.teleport(game.world.grid_pose())
	_set_ground_scale(PREVIEW_GROUND_SCALE)
	# The preview camera is further away than the sun's shadow distance (set for
	# race cameras): extend it, or the far ground changes brightness along a line.
	game.lighting.sun.directional_shadow_max_distance = PREVIEW_SHADOW_DISTANCE


## The preview sees further than any race camera: the ground plane is spread
## out while it shows, so its edges stay off screen (21:9 too).
const PREVIEW_GROUND_SCALE: float = 4.0
const PREVIEW_SHADOW_DISTANCE: float = 400.0


func _set_ground_scale(f: float) -> void:
	var g := game.track.get_node_or_null("Ground") as Node3D if game.track != null else null
	if g != null:
		g.scale = Vector3(f, 1.0, f)


func _place_camera(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	var b: AABB = game.track.bounds
	var c := b.get_center()
	# Far enough that the circuit's bounding circle fits about 80% of the view,
	# from 62 degrees up; then pitched down a little so the circuit sits above
	# the rows at the bottom of the screen.
	var radius := Vector2(b.size.x, b.size.z).length() * 0.5
	var half := deg_to_rad(_cam.fov) * 0.5
	var d := radius / tan(half * 0.82)
	var el := deg_to_rad(62.0)
	var dir := Vector3(cos(_angle) * cos(el), sin(el), sin(_angle) * cos(el))
	_cam.global_position = c + dir * d
	_cam.look_at(c, Vector3.UP)
	_cam.rotate_object_local(Vector3.RIGHT, -half * 0.22)

func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _cam != null and is_instance_valid(_cam):
		_place_camera(delta)
	if _wipe >= 0.0:
		var before := _wipe
		_wipe += delta / WIPE_TIME
		if before < 0.5 and _wipe >= 0.5:
			index = posmod(index + _wipe_dir, Tracks.ALL.size())
			game.audio.select_track(track_id())
			_show_track()
			_angle = 0.0
		if _wipe >= 1.0:
			_wipe = -1.0
	_draw()


# --- input ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not active:
		return
	var k := event as InputEventKey
	var b := event as InputEventJoypadButton
	var m := event as InputEventJoypadMotion
	var mb := event as InputEventMouseButton
	get_viewport().set_input_as_handled()
	if k != null:
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_LEFT, KEY_A: _move(Vector2i.LEFT)
			KEY_RIGHT, KEY_D: _move(Vector2i.RIGHT)
			KEY_UP, KEY_W: _move(Vector2i.UP)
			KEY_DOWN, KEY_S: _move(Vector2i.DOWN)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _start()
			KEY_ESCAPE: _back()
	elif b != null and b.pressed:
		match b.button_index:
			JOY_BUTTON_DPAD_LEFT: _move(Vector2i.LEFT)
			JOY_BUTTON_DPAD_RIGHT: _move(Vector2i.RIGHT)
			JOY_BUTTON_DPAD_UP: _move(Vector2i.UP)
			JOY_BUTTON_DPAD_DOWN: _move(Vector2i.DOWN)
			JOY_BUTTON_A, JOY_BUTTON_START: _start()
			JOY_BUTTON_B, JOY_BUTTON_BACK: _back()
	elif m != null and (m.axis == JOY_AXIS_LEFT_X or m.axis == JOY_AXIS_LEFT_Y):
		var s := _stick
		var v := 0 if absf(m.axis_value) < STICK_THRESHOLD else int(signf(m.axis_value))
		if m.axis == JOY_AXIS_LEFT_X:
			s.x = v
		else:
			s.y = v
		if s != _stick:
			_stick = s
			if s != Vector2i.ZERO:
				_move(Vector2i(s.x, 0) if s.x != 0 else Vector2i(0, s.y))
	elif mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_click(mb.position)


func _move(dir: Vector2i) -> void:
	if _wipe >= 0.0:
		return
	if dir.y != 0:
		focus = clampi(focus + dir.y, Focus.PREVIEW, Focus.START)
		return
	match focus:
		Focus.PREVIEW:
			_change_track(dir.x)
		Focus.TIME:
			var t := TIMES.find(game.audio.track_time(track_id()))
			var nt := TIMES[posmod(t + dir.x, TIMES.size())]
			game.audio.set_track_time(track_id(), nt)
			game.apply_time_of_day(nt)
		Focus.OPPONENT:
			game.audio.set_track_opponent(track_id(), clampi(game.audio.track_opponent(track_id()) + dir.x, 0, 5))


func _change_track(dir: int) -> void:
	if Tracks.ALL.size() < 2 or _wipe >= 0.0:
		return
	_wipe = 0.0
	_wipe_dir = dir


func _start() -> void:
	if _wipe >= 0.0:
		return
	game.audio.select_track(track_id())
	game.audio.save_settings()
	start_requested.emit()


func _back() -> void:
	game.audio.save_settings()
	back_requested.emit()


## A click on the overlay: the arrows, a row (focus it; on its value, change it) or START.
func _click(pos: Vector2) -> void:
	var r: AsciiRenderer = game.renderer
	var win := r.get_viewport().get_visible_rect().size
	var cell := Vector2i((pos * Vector2(r.output_size) / win / Vector2(r.pitch)).floor())
	for h: Array in _hits:
		if (h[0] as Rect2i).has_point(cell):
			var act: String = h[1]
			match act:
				"prev": _change_track(-1)
				"next": _change_track(1)
				"start": _start()
				"time", "opponent":
					focus = Focus.TIME if act == "time" else Focus.OPPONENT
					_move(Vector2i.RIGHT)
			return


# --- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	var r: AsciiRenderer = game.renderer
	if not r.is_atlas_ready():
		return
	var ov := r.get_overlay()
	r.overlay_enabled = true
	ov.clear()
	_logo.overlay = ov
	_hits.clear()
	var cols := ov.cols
	var rows := ov.rows
	var big := rows >= 50 and cols >= 120
	# Many small cells (a 2x display, a big window): the small lines in the
	# block font too, where they fit.
	var huge := rows >= 100 and cols >= 250
	var def: Dictionary = Tracks.ALL[index]
	# Title, name, facts.
	if huge:
		_mini_line("SELECT TRACK", 1, INK_DIM, cols)
	else:
		ov.text((cols - 12) / 2, 1, "SELECT TRACK", INK_DIM)
	var npix := Vector2i(2, 1) if big and AsciiLogo.mini_width(def.name, Vector2i(2, 1), 1) < cols - 30 else Vector2i.ONE
	if huge and AsciiLogo.mini_width(def.name, Vector2i(3, 2), 1) < cols - 60:
		npix = Vector2i(3, 2)
	var nw := AsciiLogo.mini_width(def.name, npix, 1 if npix.x > 1 else 0)
	var ny := 8 if huge else 3
	for y in range(ny - 1, ny + 5 * npix.y + 3):
		for x in range((cols - nw) / 2 - 3, (cols + nw) / 2 + 3):
			ov.cover(x, y, 0.6, PANEL_BG)
	_logo.draw_mini(def.name, (cols - nw) / 2, ny, npix, 1 if npix.x > 1 else 0, func(f: float) -> Color: return AsciiLogo._gradient(f), 0.0)
	var best: float = game.audio.best_lap(def.id)
	var facts := "%d m   %s   best %s   %d / %d" % [roundi(game.track.length), String(def.get("description", "")),
		LapTimer.fmt(best) if best > 0.0 else "--", index + 1, Tracks.ALL.size()]
	if not (huge and _mini_line(facts.to_upper(), ny + 5 * npix.y + 2, INK, cols)):
		ov.text((cols - facts.length()) / 2, ny + 5 * npix.y + 1, facts, INK)
	# Arrows at the edges.
	var apix := Vector2i(4, 3) if big and rows >= 70 else (Vector2i(3, 2) if big else Vector2i.ONE)
	var aw := AsciiLogo.mini_width("<", apix, 0)
	var ah := 5 * apix.y
	var ay := rows / 2 - ah / 2 - 2
	var pulse := 0.65 + 0.35 * cos(_t * 4.0)
	var arrow_ink := INK_SEL.lerp(PANEL_BG, 1.0 - pulse) if focus == Focus.PREVIEW else INK.lerp(PANEL_BG, 0.25)
	for side: int in [-1, 1]:
		var ax := 2 if side < 0 else cols - 2 - aw
		for y in range(ay - 1, ay + ah + 1):
			for x in range(ax - 1, ax + aw + 1):
				ov.cover(x, y, 0.55, PANEL_BG)
		_logo.draw_mini("<" if side < 0 else ">", ax, ay, apix, 0, func(_f: float) -> Color: return arrow_ink, 0.0)
		_hits.append([Rect2i(ax - 1, ay - 1, aw + 2, ah + 2), "prev" if side < 0 else "next"])
	# Rows.
	var labels := ["TIME OF DAY", "OPPONENT", "START"]
	var values := ["< %s >" % game.audio.track_time(def.id).to_upper(),
		"< %s >" % ("OFF" if game.audio.track_opponent(def.id) == 0 else str(game.audio.track_opponent(def.id))), ""]
	var rpix := Vector2i.ONE
	var row_h := 6 if big else 2
	var lw := 0
	for l: String in labels:
		lw = maxi(lw, AsciiLogo.mini_width(l, rpix, 0) if big else l.length())
	var vw := 0
	for v: String in values:
		vw = maxi(vw, AsciiLogo.mini_width(v, rpix, 0) if big else v.length())
	var gap := 4 * rpix.x
	var pw := lw + gap + vw
	var px := (cols - pw) / 2
	var py := rows - 3 * row_h - (10 if huge else 4)
	for y in range(py - 1, py + 3 * row_h + 1):
		for x in range(px - 4 * rpix.x, px + pw + 4):
			ov.cover(x, y, 0.85, PANEL_BG)
	for i in 3:
		var sel := focus == i + 1
		var ink := INK_SEL if sel else INK
		var y := py + i * row_h
		if sel:
			var mark := ACCENT.lerp(PANEL_BG, 1.0 - pulse)
			if big:
				_logo.draw_mini(">", px - 4 * rpix.x, y, rpix, 0, func(_f: float) -> Color: return mark, 0.0)
			else:
				ov.put_char(px - 2, y, ">", mark)
		var label: String = labels[i]
		var value: String = values[i]
		if big:
			_logo.draw_mini(label, px, y, rpix, 0, func(_f: float) -> Color: return ink, 0.0)
			if value != "":
				_logo.draw_mini(value, px + lw + gap, y, rpix, 0, func(_f: float) -> Color: return ink, 0.0)
		else:
			ov.text(px, y, label, ink)
			ov.text(px + lw + 4, y, value, ink)
		_hits.append([Rect2i(px - 4 * rpix.x, y - 1, pw + 4 + 4 * rpix.x, row_h), ["time", "opponent", "start"][i]])
	var hint := "Left/Right track   Up/Down rows   Enter start   Esc back"
	if not (huge and _mini_line(hint.to_upper(), rows - 6, INK_DIM, cols)):
		ov.text((cols - hint.length()) / 2, rows - 2, hint, INK_DIM)
	if _wipe >= 0.0:
		_draw_wipe(ov, _wipe)


## A centred line in the block font at row y, if it fits; false if not.
func _mini_line(text: String, y: int, ink: Color, cols: int) -> bool:
	var w := AsciiLogo.mini_width(text, Vector2i.ONE, 0)
	if w > cols - 8:
		return false
	var ov := _logo.overlay
	for yy in range(y - 1, y + 6):
		for x in range((cols - w) / 2 - 2, (cols + w) / 2 + 2):
			ov.cover(x, yy, 0.75, PANEL_BG)
	_logo.draw_mini(text, (cols - w) / 2, y, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
	return true


## A glyph wipe across the screen, in the direction of travel: covers to 0.5, uncovers after.
func _draw_wipe(ov: AsciiOverlay, w: float) -> void:
	var cols := ov.cols
	var edge := w * 2.0 if w < 0.5 else (w - 0.5) * 2.0
	var g := ov.glyph("/")
	for y in ov.rows:
		for x in cols:
			var f := float(x) / cols if _wipe_dir > 0 else 1.0 - float(x) / cols
			var covered := f < edge if w < 0.5 else f >= edge
			if covered:
				ov.cover(x, y, 0.97, PANEL_BG)
				if (x + y) % 7 == 0:
					ov.put(x, y, g, ACCENT.lerp(PANEL_BG, 0.6))
