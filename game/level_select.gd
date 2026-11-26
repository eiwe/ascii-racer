## The level select, between the reel and a race: a large live preview of the
## selected circuit (a map-like view from high up that sways gently around the
## orientation that fills the screen best, lit for its time of day but brighter
## than in a race, so the track reads as a map), big < > arrows at the screen
## edges (the circuits wrap), the name in the logo's block letters with a line
## of facts, and a strip of rows at the bottom: TIME OF DAY, OPPONENT, START.
## All drawn in the renderer's overlay cell layer.
##
## Controls: with the preview focused left / right change the circuit; up / down
## move between the preview and the rows; left / right change a row; Enter,
## Space or pad A start from anywhere; Esc or pad B go back to the reel. Pad
## d-pad and left stick work throughout; a mouse click on an arrow, a row or
## START works too.
##
## Layout: the title band at the top and the rows strip at the bottom are laid
## out first (_layout); the circuit is fitted into the rectangle left between
## them and the arrows, so nothing overlaps at any size or aspect.
##
## Changing the circuit wipes over the swap (the world rebuilds it under the
## wipe). The selection and each circuit's time of day and opponent level are
## saved with the settings.
class_name LevelSelect
extends Node

signal start_requested
signal back_requested

enum Focus { PREVIEW, TIME, OPPONENT, START }
const TIMES: PackedStringArray = ["morning", "noon", "night"]
const WIPE_TIME: float = 0.45
const STICK_THRESHOLD: float = 0.55

## Preview camera: a narrow lens from high up (close to a map), swaying this far
## either side of the best-fitting heading, once per SWAY_PERIOD, with a slower
## small change of height.
const PREVIEW_FOV: float = 34.0
const ELEVATION_DEG: float = 62.0
const ELEVATION_DRIFT_DEG: float = 2.5
const SWAY_DEG: float = 15.0
const SWAY_PERIOD: float = 16.0
const DRIFT_PERIOD: float = 23.0
## Share of the free rectangle the circuit may use (room for the sway's drift).
const FIT_MARGIN: float = 0.94

## The preview is a map: brighter than the race look so the track, kerbs,
## jumps and walls read at any time of day, while sun colour and direction
## still tell the times apart (Lighting.preview; the race modes are untouched).
const PREVIEW_LIGHT: Dictionary = {
	"morning": {"ambient_energy": 0.85, "track": 1.85, "ground": Color(0.13, 0.15, 0.12)},
	"noon": {"ambient_energy": 0.5, "track": 1.35, "ground": Color(0.1, 0.13, 0.08)},
	"night": {"ambient_energy": 1.35, "track": 2.5, "sun_energy": 1.6, "ground": Color(0.07, 0.09, 0.12)},
}
## The preview sees further than any race camera: the visible ground plane is
## spread out while it shows (and its g-buffer twin with it), and the sun's
## shadows reach as far as the camera sees.
const PREVIEW_GROUND_SCALE: float = 4.0
const PREVIEW_SHADOW_DISTANCE: float = 400.0

const INK: Color = Color("c8ccdc")
const INK_DIM: Color = Color("6a7088")
const INK_SEL: Color = Color("ffcf5c")
const ACCENT: Color = Color("ff8a1f")
const PANEL_BG: Color = Color(0.02, 0.025, 0.05)
const SEL_BG: Color = Color(0.16, 0.12, 0.03)

var game: Node
var active: bool = false
var focus: int = Focus.PREVIEW
var index: int = 0 ## into Tracks.ALL

var _cam: Camera3D
var _t: float = 0.0
var _logo := AsciiLogo.new()
var _wipe: float = -1.0
var _wipe_dir: int = 0
var _stick := Vector2i.ZERO
## Clickable areas this frame (overlay cells): [Rect2i, action].
var _hits: Array = []

## Fit state: outline points of the circuit, the best heading for this circuit
## and screen shape, the camera distance and the sideways / vertical pan.
var _pts: PackedVector3Array = []
var _fit_key: String = ""
var _base_yaw: float = 0.0
var _dist: float = 50.0
var _pan: Vector2 = Vector2.ZERO
var _centre: Vector3 = Vector3.ZERO


var _log_preview: bool = false
var _log_next: float = 0.0


func _ready() -> void:
	process_priority = 115 # after NitroHud / RaceStart, before the pause menu's draw
	_log_preview = OS.get_cmdline_user_args().has("--previewlog")


## `-- --previewlog` (also in a web build's index.html "args"): prints, every 2 s,
## the share of the preview where the g-buffer shows no geometry (sky). In a
## map view looking down it must be 0.
func _log_sky() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = (game.renderer as AsciiRenderer).gbuffer_viewport.get_texture().get_image()
	var n := 0
	var bgc := 0
	for y in range(0, img.get_height(), 6):
		for x in range(0, img.get_width(), 6):
			n += 1
			if img.get_pixel(x, y).b >= 0.9999:
				bgc += 1
	print("[preview] %s t %.1f yaw %.0f: sky share %.3f%% (g-buffer %s, format %d)" % [track_id(), _t,
		rad_to_deg(_base_yaw), 100.0 * bgc / maxf(n, 1), img.get_size(), img.get_format()])


func track_id() -> String:
	return Tracks.ALL[index].id


## Shows the select on the saved circuit (loading it into the world).
func open() -> void:
	active = true
	_t = 0.0
	focus = Focus.PREVIEW
	_wipe = -1.0
	index = maxi(Tracks.ids().find(game.audio.track_id), 0)
	_cam = Camera3D.new()
	_cam.name = "SelectCamera"
	_cam.fov = PREVIEW_FOV
	_cam.near = 1.0
	_cam.far = 2000.0
	game.world.add_child(_cam)
	_cam.current = true
	game.lighting.fog_suppressed = true
	game.renderer.distance_fade = Vector2.ZERO
	_show_track()
	_place_camera()


func close() -> void:
	if not active:
		return
	active = false
	game.lighting.fog_suppressed = false
	game.lighting.preview = {}
	_set_ground_scale(1.0)
	game.lighting.set_mode(game.lighting.mode) # the race look and shadow distance again
	if _cam != null:
		_cam.queue_free()
		_cam = null
	game.set_chase_view(false)
	var ov: AsciiOverlay = game.renderer.get_overlay()
	if ov != null:
		ov.clear()


## The selected circuit in the world, its saved time of day lit (preview look),
## the car on its grid.
func _show_track() -> void:
	game.set_track(track_id())
	game.lighting.preview = _preview_light()
	game.apply_time_of_day(game.audio.track_time(track_id()))
	game.car.player_input = false
	game.car.teleport(game.world.grid_pose())
	_set_ground_scale(PREVIEW_GROUND_SCALE)
	game.lighting.sun.directional_shadow_max_distance = PREVIEW_SHADOW_DISTANCE
	_sample_outline()
	_fit_key = ""


## Applies a time of day in the preview look.
func _apply_time(t: String) -> void:
	game.lighting.preview = _preview_light()
	game.apply_time_of_day(t)
	game.lighting.sun.directional_shadow_max_distance = PREVIEW_SHADOW_DISTANCE


## PREVIEW_LIGHT for the shown circuit: where the circuit sets its own ground
## colour for a time of day (Frost Pass's snowfield), the preview keeps that
## colour, a little darker, instead of the dark ground meant for the others.
func _preview_light() -> Dictionary:
	var out: Dictionary = PREVIEW_LIGHT.duplicate(true)
	var tw: Dictionary = Tracks.ALL[index].get("time_tweaks", {})
	for t: String in out:
		if tw.has(t) and (tw[t] as Dictionary).has("ground"):
			out[t]["ground"] = (tw[t]["ground"] as Color).darkened(0.45)
	return out


func _set_ground_scale(f: float) -> void:
	var g := game.track.get_node_or_null("Ground") as Node3D if game.track != null else null
	if g != null:
		g.scale = Vector3(f, 1.0, f)


# --- preview camera --------------------------------------------------------------------

## Points along both road edges (and the walls' tops), what has to fit on screen.
func _sample_outline() -> void:
	_pts = PackedVector3Array()
	var tr: Track = game.track
	var n := 120
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in n:
		var s := tr.length * i / n
		for u: float in [-Track.ROAD_HALF_WIDTH - 0.6, Track.ROAD_HALF_WIDTH + 0.6]:
			var p := tr.pose_at(s, u).origin
			_pts.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
	_centre = (lo + hi) * 0.5


func _aspect() -> float:
	var sz: Vector2 = Vector2(game.renderer.scene_viewport.size)
	return sz.x / maxf(sz.y, 1.0)


func _pose(yaw: float, el: float, d: float, pan: Vector2) -> Transform3D:
	var dir := Vector3(cos(yaw) * cos(el), sin(el), sin(yaw) * cos(el))
	var b := Basis.looking_at(-dir, Vector3.UP)
	return Transform3D(b, _centre + dir * d + b.x * pan.x + b.y * pan.y)


## The circuit's extent on screen (normalised device coordinates, y up).
func _bbox(xf: Transform3D, tan_v: float, aspect: float) -> Rect2:
	var inv := xf.affine_inverse()
	var mn := Vector2(INF, INF)
	var mx := -mn
	for p in _pts:
		var q := inv * p
		var z := maxf(-q.z, 0.01)
		var v := Vector2(q.x / (z * tan_v * aspect), q.y / (z * tan_v))
		mn = mn.min(v)
		mx = mx.max(v)
	return Rect2(mn, mx - mn)


## Distance and pan that fit the circuit into `r` from this heading.
func _fit(yaw: float, el: float, r: Rect2, d: float, pan: Vector2, steps: int, fit_dist: bool) -> Array:
	var tan_v := tan(deg_to_rad(PREVIEW_FOV) * 0.5)
	var aspect := _aspect()
	for i in steps:
		var bb := _bbox(_pose(yaw, el, d, pan), tan_v, aspect)
		var off := bb.get_center() - r.get_center()
		pan += Vector2(off.x * d * tan_v * aspect, off.y * d * tan_v)
		if fit_dist:
			d *= maxf(bb.size.x / r.size.x, bb.size.y / r.size.y)
	return [d, pan]


## The free rectangle (normalised device coordinates, y up) from the layout.
func _view_ndc() -> Rect2:
	var ov: AsciiOverlay = game.renderer.get_overlay()
	if ov == null or ov.cols == 0:
		return Rect2(-0.8, -0.6, 1.6, 1.4)
	var l := _layout(ov.cols, ov.rows)
	var v: Rect2i = l.view
	var x0 := float(v.position.x) / ov.cols * 2.0 - 1.0
	var x1 := float(v.end.x) / ov.cols * 2.0 - 1.0
	var y_top := 1.0 - float(v.position.y) / ov.rows * 2.0
	var y_bot := 1.0 - float(v.end.y) / ov.rows * 2.0
	var r := Rect2(x0, y_bot, x1 - x0, y_top - y_bot)
	return r.grow_individual(-r.size.x * (1.0 - FIT_MARGIN) * 0.5, -r.size.y * (1.0 - FIT_MARGIN) * 0.5,
		-r.size.x * (1.0 - FIT_MARGIN) * 0.5, -r.size.y * (1.0 - FIT_MARGIN) * 0.5)


## Picks the heading (and distance) that shows the circuit largest over the
## whole sway, for this circuit and screen shape. Cheap enough to redo on a
## track change or a resize.
func _choose_heading(r: Rect2) -> void:
	var el := deg_to_rad(ELEVATION_DEG)
	var best_d := INF
	var d0 := 60.0
	for k in 18:
		var yaw := TAU * k / 18.0
		var worst := 0.0
		for sw: float in [-SWAY_DEG, -SWAY_DEG * 0.5, 0.0, SWAY_DEG * 0.5, SWAY_DEG]:
			for de: float in [-ELEVATION_DRIFT_DEG, ELEVATION_DRIFT_DEG]:
				var f := _fit(yaw + deg_to_rad(sw), el + deg_to_rad(de), r, d0, Vector2.ZERO, 12, true)
				worst = maxf(worst, f[0])
		if worst < best_d:
			best_d = worst
			_base_yaw = yaw
	_dist = best_d
	_pan = Vector2.ZERO


func _place_camera() -> void:
	if _cam == null or _pts.is_empty():
		return
	var r := _view_ndc()
	var key := "%s %.3f %s" % [track_id(), _aspect(), r]
	if key != _fit_key:
		_fit_key = key
		_choose_heading(r)
	var yaw := _base_yaw + deg_to_rad(SWAY_DEG) * sin(TAU * _t / SWAY_PERIOD)
	var el := deg_to_rad(ELEVATION_DEG + ELEVATION_DRIFT_DEG * sin(TAU * _t / DRIFT_PERIOD))
	# Distance fixed for the sway; the pan keeps the circuit centred in the free area.
	var f := _fit(yaw, el, r, _dist, _pan, 2, false)
	_pan = f[1]
	_cam.global_transform = _pose(yaw, el, _dist, _pan)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _cam != null and is_instance_valid(_cam):
		_place_camera()
	if _log_preview and _t >= _log_next:
		_log_next = _t + 2.0
		_log_sky()
	if _wipe >= 0.0:
		var before := _wipe
		_wipe += delta / WIPE_TIME
		if before < 0.5 and _wipe >= 0.5:
			index = posmod(index + _wipe_dir, Tracks.ALL.size())
			game.audio.select_track(track_id())
			_show_track()
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
			_apply_time(nt)
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


# --- layout and drawing ------------------------------------------------------------------

## Where everything goes for a grid of cols x rows: the title band (name, facts),
## the rows strip and hint at the bottom, the arrows, and `view`: the free
## rectangle (cells) the preview fits the circuit into.
func _layout(cols: int, rows: int) -> Dictionary:
	var def: Dictionary = Tracks.ALL[index]
	var big := rows >= 50 and cols >= 120
	var huge := rows >= 100 and cols >= 250
	var l := {"big": big, "huge": huge}
	# Name.
	var npix := Vector2i.ONE
	if huge and AsciiLogo.mini_width(def.name, Vector2i(3, 2), 1) < cols - 60:
		npix = Vector2i(3, 2)
	elif big and AsciiLogo.mini_width(def.name, Vector2i(2, 1), 1) < cols - 30:
		npix = Vector2i(2, 1)
	l.npix = npix
	var name_y: int = 2 if huge else 1
	l.name_y = name_y
	var y: int = name_y + 5 * npix.y + 1
	# Facts: one line in the block font, or two, or plain text.
	var best: float = game.audio.best_lap(def.id)
	var desc := String(def.get("description", "")).to_upper()
	var nums := "%d M   BEST %s   %d / %d" % [roundi(game.track.length), LapTimer.fmt(best) if best > 0.0 else "--",
		index + 1, Tracks.ALL.size()]
	var one := "%s   %s" % [desc, nums]
	var facts: Array = []
	if big and AsciiLogo.mini_width(one, Vector2i.ONE, 0) <= cols - 8:
		facts = [[one, true, y + 1]]
		y += 8
	elif big and AsciiLogo.mini_width(desc, Vector2i.ONE, 0) <= cols - 8:
		facts = [[desc, true, y + 1], [nums, true, y + 7]]
		y += 14
	else:
		facts = [["%s   %s" % [String(def.get("description", "")), nums.to_lower()], false, y]]
		y += 2
	l.facts = facts
	l.top_end = y
	# Bottom: hint, then the rows strip above it.
	l.hint_y = rows - 1
	var items: Array = [
		["TIME OF DAY", "< %s >" % game.audio.track_time(def.id).to_upper()],
		["OPPONENT", "< %s >" % ("OFF" if game.audio.track_opponent(def.id) == 0 else str(game.audio.track_opponent(def.id)))],
		["START", ""],
	]
	var texts: Array = items.map(func(it: Array) -> String: return it[0] if it[1] == "" else "%s  %s" % [it[0], it[1]])
	var gap := 9
	var mini_w := 0
	for t: String in texts:
		mini_w += AsciiLogo.mini_width(t, Vector2i.ONE, 0)
	mini_w += gap * (texts.size() - 1)
	var strip_mini := big and mini_w <= cols - 12
	var strip_h := 5 if strip_mini else 1
	var strip_y: int = rows - 3 - strip_h
	var widths: Array = texts.map(func(t: String) -> int: return AsciiLogo.mini_width(t, Vector2i.ONE, 0) if strip_mini else t.length())
	var total := 0
	for w: int in widths:
		total += w
	total += (gap if strip_mini else 6) * (texts.size() - 1)
	var x := (cols - total) / 2
	var rects: Array = []
	for i in texts.size():
		rects.append(Rect2i(x, strip_y, widths[i], strip_h))
		x += widths[i] + (gap if strip_mini else 6)
	l.strip = {"mini": strip_mini, "y": strip_y, "h": strip_h, "texts": texts, "rects": rects}
	# Arrows: big, at the sides, centred on the free area.
	var k := maxi(1, rows / 24) if big else 1
	var apix := Vector2i(2 * k, k) if big else Vector2i.ONE
	var aw := AsciiLogo.mini_width("<", apix, 0)
	var ah := 5 * apix.y
	var view_top: int = l.top_end + 1
	var view_bot: int = strip_y - 2
	var ay := (view_top + view_bot) / 2 - ah / 2
	l.arrows = {"pix": apix, "w": aw, "h": ah, "y": ay, "left": 2, "right": cols - 2 - aw}
	l.view = Rect2i(aw + 5, view_top, cols - 2 * (aw + 5), maxi(view_bot - view_top, 4))
	return l


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
	var l := _layout(cols, rows)
	var def: Dictionary = Tracks.ALL[index]
	var pulse := 0.65 + 0.35 * cos(_t * 4.0)
	# Name and facts on a plate.
	var npix: Vector2i = l.npix
	var nw := AsciiLogo.mini_width(def.name, npix, 1 if npix.x > 1 else 0)
	var ny: int = l.name_y
	_plate(ov, (cols - nw) / 2 - 3, ny - 1, nw + 6, 5 * npix.y + 2, 0.7, PANEL_BG)
	_logo.draw_mini(def.name, (cols - nw) / 2, ny, npix, 1 if npix.x > 1 else 0, func(f: float) -> Color: return AsciiLogo._gradient(f), 0.0)
	for f: Array in l.facts:
		var txt: String = f[0]
		if f[1]:
			var w := AsciiLogo.mini_width(txt, Vector2i.ONE, 0)
			_plate(ov, (cols - w) / 2 - 2, int(f[2]) - 1, w + 4, 7, 0.8, PANEL_BG)
			_logo.draw_mini(txt, (cols - w) / 2, f[2], Vector2i.ONE, 0, func(_f: float) -> Color: return INK, 0.0)
		else:
			_plate(ov, (cols - txt.length()) / 2 - 2, f[2], txt.length() + 4, 1, 0.85, PANEL_BG)
			ov.text((cols - txt.length()) / 2, f[2], txt, INK)
	# Arrows: bright and pulsing with the preview focused, dim otherwise.
	var a: Dictionary = l.arrows
	var on_preview := focus == Focus.PREVIEW
	var arrow_ink := INK_SEL.lerp(ACCENT, 1.0 - pulse) if on_preview else INK_DIM
	for side: int in [-1, 1]:
		var ax: int = a.left if side < 0 else a.right
		_plate(ov, ax - 1, int(a.y) - 1, int(a.w) + 2, int(a.h) + 2, 0.75, SEL_BG if on_preview else PANEL_BG)
		_logo.draw_mini("<" if side < 0 else ">", ax, a.y, a.pix, 0, func(_f: float) -> Color: return arrow_ink, 0.0)
		_hits.append([Rect2i(ax - 2, int(a.y) - 2, int(a.w) + 4, int(a.h) + 4), "prev" if side < 0 else "next"])
	# A frame round the preview while it has the focus.
	if on_preview:
		_corners(ov, l.view, ACCENT.lerp(PANEL_BG, 0.55 - 0.3 * pulse))
	# Rows strip.
	var st: Dictionary = l.strip
	_plate(ov, 0, int(st.y) - 1, cols, int(st.h) + 2, 0.85, PANEL_BG)
	for i in (st.texts as Array).size():
		var rect: Rect2i = st.rects[i]
		var sel := focus == i + 1
		var ink := INK_SEL if sel else INK
		if sel:
			_plate(ov, rect.position.x - 3, rect.position.y - 1, rect.size.x + 6, rect.size.y + 2, 1.0, SEL_BG)
			var mark := ACCENT.lerp(SEL_BG, 1.0 - pulse)
			if st.mini:
				_logo.draw_mini(">", rect.position.x - 5, rect.position.y, Vector2i.ONE, 0, func(_f: float) -> Color: return mark, 0.0)
			else:
				ov.put_char(rect.position.x - 2, rect.position.y, ">", mark)
		var txt: String = st.texts[i]
		if st.mini:
			_logo.draw_mini(txt, rect.position.x, rect.position.y, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)
		else:
			ov.text(rect.position.x, rect.position.y, txt, ink)
		_hits.append([rect.grow(2), ["time", "opponent", "start"][i]])
	var hint := "Left/Right track   Up/Down select   Enter start   Esc back"
	ov.text((cols - hint.length()) / 2, l.hint_y, hint, INK_DIM, 0.8, PANEL_BG)
	if _wipe >= 0.0:
		_draw_wipe(ov, _wipe)


func _plate(ov: AsciiOverlay, x: int, y: int, w: int, h: int, amount: float, bg: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			ov.cover(xx, yy, amount, bg)


## Corner marks round a rectangle of cells.
func _corners(ov: AsciiOverlay, r: Rect2i, ink: Color) -> void:
	var n := clampi(r.size.x / 12, 2, 8)
	var m := clampi(r.size.y / 8, 1, 4)
	var x0 := r.position.x - 1
	var x1 := r.end.x
	var y0 := r.position.y - 1
	var y1 := r.end.y
	for i in n:
		for y: int in [y0, y1]:
			ov.put_char(x0 + i, y, "-", ink)
			ov.put_char(x1 - i, y, "-", ink)
	for j in m:
		for x: int in [x0, x1]:
			ov.put_char(x, y0 + j, "|", ink)
			ov.put_char(x, y1 - j, "|", ink)
	for c: Vector2i in [Vector2i(x0, y0), Vector2i(x1, y0), Vector2i(x0, y1), Vector2i(x1, y1)]:
		ov.put_char(c.x, c.y, "+", ink)


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
