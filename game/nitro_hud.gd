## The nitro tank as part of the ASCII picture: a bar drawn in the renderer's
## overlay cell layer (bottom centre, clear of the debug HUD and the tuning
## panel), and the burn's look: a flame trail of glyphs behind the car and, in
## the chase view, speed lines streaming out from the middle of the screen.
##
## Runs after Attract (which owns the overlay during the demo reel and its
## wipes) and draws nothing while the reel or a wipe is on screen.
class_name NitroHud
extends Node

## Bar width in cells: cols / BAR_COLS_DIV, clamped to BAR_WIDTH.
const BAR_COLS_DIV: float = 6.0
const BAR_WIDTH: Vector2i = Vector2i(12, 48)
const LABEL: String = "NITRO"
## Cells left free under the bar (bottom margin).
const BAR_MARGIN: int = 1
## Partial cell glyphs, by fill quarter, and the full / empty glyphs.
const PART_GLYPHS: String = ".:=#"
const FULL_GLYPH: String = "#"
const EMPTY_GLYPH: String = "."
const HOT_GLYPHS: String = "#%@#"
const INK_COLD: Color = Color("ffb020")
const INK_WARM: Color = Color("ff6a1a")
const INK_HOT: Color = Color("fff2b0")
const INK_EMPTY: Color = Color("4a4f66")
const INK_LABEL: Color = Color("ffcf5c")
const INK_REFILL: Color = Color("7fe8ff")
const INK_ALERT: Color = Color("ff4040")
const BG: Color = Color(0.02, 0.02, 0.04)
## Flame trail: length in cells at full burn (scaled with the car's size on
## screen), and its glyphs from the car outward.
const FLAME_GLYPHS: String = "@#*=~-"
const FLAME_INKS: Array[Color] = [Color("fff8d0"), Color("ffe070"), Color("ffb030"), Color("ff7a20"), Color("e04818"), Color("902010")]
## Chase view speed lines.
const SPEED_LINES: int = 44
## Wind streaks around the car while burning (both views).
const STREAKS: int = 6
const SPEED_LINE_INK: Color = Color("bfd8ff")

var game: Node
var car: Car
var renderer: AsciiRenderer
var attract: Attract
## False hides the bar and the effects (the overlay is left alone).
var enabled: bool = true
## Race standing from the opponent ("P1 +1.8"), drawn bottom left; "" = none.
var race_text: String = ""
const RACE_INK_LEAD: Color = Color("ffe45c")
const RACE_INK_TRAIL: Color = Color("ff7a5c")
var _logo := AsciiLogo.new()

var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _empty_flash: float = 0.0


func _ready() -> void:
	process_priority = 100 # after Attract, which clears the overlay first
	_rng.seed = 1234


func _process(delta: float) -> void:
	_t += delta
	if not enabled or car == null or renderer == null:
		return
	if attract != null and attract.busy():
		return
	var ov := renderer.get_overlay()
	if ov == null or ov.cols < 4 or ov.rows < 4:
		return
	ov.clear()
	renderer.overlay_enabled = true
	if car.nitro_input and car.nitro_level <= 0.0 and car.nitro_tank < Car.NITRO_MIN_START:
		_empty_flash = 0.6
	_empty_flash = maxf(_empty_flash - delta, 0.0)
	if car.nitro_level > 0.0:
		_draw_flame(ov)
		if renderer.scene_viewport.get_camera_3d() is ChaseCamera:
			_draw_speed_lines(ov)
	_draw_bar(ov)
	if race_text != "":
		_draw_race(ov)


func _draw_bar(ov: AsciiOverlay) -> void:
	var w := clampi(roundi(ov.cols / BAR_COLS_DIV), BAR_WIDTH.x, BAR_WIDTH.y)
	var total := LABEL.length() + 2 + w + 2
	var x0 := (ov.cols - total) / 2
	var y1 := ov.rows - 1 - BAR_MARGIN
	var y0 := y1 - 1
	# Backing plate one cell wider all round.
	for y in range(y0 - 1, y1 + 2):
		for x in range(x0 - 1, x0 + total + 1):
			ov.cover(x, y, 0.88, BG)
	var burning := car.nitro_level > 0.0
	var label_ink := INK_HOT if burning and int(_t * 12.0) % 2 == 0 else INK_LABEL
	if _empty_flash > 0.0:
		ov.text(x0, y0, "EMPTY", INK_ALERT if int(_t * 10.0) % 2 == 0 else INK_EMPTY)
	else:
		ov.text(x0, y0, LABEL, label_ink)
	var bx := x0 + LABEL.length() + 2
	ov.put_char(bx - 1, y0, "[", INK_EMPTY)
	ov.put_char(bx - 1, y1, "[", INK_EMPTY)
	ov.put_char(bx + w, y0, "]", INK_EMPTY)
	ov.put_char(bx + w, y1, "]", INK_EMPTY)
	var frac := clampf(car.nitro_tank / maxf(car.nitro_capacity, 1e-3), 0.0, 1.0)
	var filled := frac * w
	var full := int(filled)
	var part := filled - full
	var refilling := not burning and frac < 1.0
	for i in w:
		var g := EMPTY_GLYPH
		var ink := INK_EMPTY
		if i < full:
			var k := float(i) / maxf(w - 1, 1)
			ink = INK_COLD.lerp(INK_WARM, k)
			g = FULL_GLYPH
			if burning:
				g = HOT_GLYPHS[(i + int(_t * 30.0)) % HOT_GLYPHS.length()]
				ink = ink.lerp(INK_HOT, 0.5 * car.nitro_level)
		elif i == full and part > 0.0:
			g = PART_GLYPHS[clampi(int(part * PART_GLYPHS.length()), 0, PART_GLYPHS.length() - 1)]
			ink = INK_COLD.lerp(INK_WARM, float(i) / maxf(w - 1, 1))
		for y in [y0, y1]:
			ov.put_char(bx + i, y, g, ink)
	# The moving edge: a bright cursor while burning, a blinking refill mark.
	var edge := clampi(full, 0, w - 1)
	if burning and frac > 0.0:
		for y in [y0, y1]:
			ov.put_char(bx + edge, y, ">", INK_HOT)
	elif refilling and int(_t * 4.0) % 2 == 0:
		for y in [y0, y1]:
			ov.put_char(bx + edge, y, "+", INK_REFILL)


## The race standing in block letters at the bottom left, on a dark plate.
func _draw_race(ov: AsciiOverlay) -> void:
	_logo.overlay = ov
	var w := AsciiLogo.mini_width(race_text, Vector2i.ONE, 0)
	var x0 := 3
	var y0 := ov.rows - 1 - BAR_MARGIN - 5
	for y in range(y0 - 1, y0 + 6):
		for x in range(x0 - 2, x0 + w + 1):
			ov.cover(x, y, 0.85, BG)
	var ink := RACE_INK_LEAD if race_text.begins_with("P1") else RACE_INK_TRAIL
	_logo.draw_mini(race_text, x0, y0, Vector2i.ONE, 0, func(_f: float) -> Color: return ink, 0.0)


## Cell (fractional) of a world point, or (-1, -1) when it is behind the camera.
func _cell_of(p: Vector3) -> Vector2:
	var cam := renderer.scene_viewport.get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		return Vector2(-1.0, -1.0)
	var uv := cam.unproject_position(p) / Vector2(renderer.scene_viewport.size)
	return uv * Vector2(renderer.output_size) / Vector2(renderer.pitch)


## A flame of glyphs from the back of the car, away from its nose on screen:
## a bright core and flickering sides, longer at a full burn.
func _draw_flame(ov: AsciiOverlay) -> void:
	var xf := car.get_global_transform_interpolated()
	var fwd := -xf.basis.z
	var rear := xf.origin + Vector3.UP * 0.18 - fwd * 0.45
	var a := _cell_of(rear)
	var b := _cell_of(rear - fwd * 0.6)
	if a.x < 0.0 or b.x < 0.0:
		return
	var dir := b - a
	var cells_per_unit := dir.length() / 0.6
	if cells_per_unit < 0.5:
		return # pointing at the camera: the car hides it
	dir = dir.normalized()
	var scale := clampf(cells_per_unit / 5.0, 0.8, 3.0)
	var length := (5.0 + 12.0 * car.nitro_level) * scale
	var half_w := 0.6 + 0.9 * scale
	var side := Vector2(-dir.y, dir.x)
	var n := int(length)
	for i in n:
		var f := float(i) / maxf(length, 1.0)
		var width := half_w * (1.0 - f * 0.7)
		for lane in range(-2, 3):
			var off := lane * 0.5
			if absf(off) > width:
				continue
			var core := 1.0 - absf(off) / maxf(width, 0.01)
			if _rng.randf() < 0.1 + 0.6 * f * (1.2 - core):
				continue # ragged edges and tail
			var p := a + dir * (i + 0.5) + side * (off + (_rng.randf() - 0.5) * 0.5)
			var k := clampi(int((f * 0.8 + (1.0 - core) * 0.4) * FLAME_GLYPHS.length() + _rng.randf() * 0.7), 0, FLAME_GLYPHS.length() - 1)
			ov.put_char(int(p.x), int(p.y), FLAME_GLYPHS[k], FLAME_INKS[k].lerp(Color.BLACK, 0.25 * (1.0 - car.nitro_level)))
	_draw_streaks(ov, a, dir, scale)


## Wind streaks along the direction of travel, around and behind the car,
## sliding back each frame.
func _draw_streaks(ov: AsciiOverlay, origin: Vector2, back: Vector2, scale: float) -> void:
	var side := Vector2(-back.y, back.x)
	var g := _line_glyph(back * Vector2(1.0, float(renderer.pitch.y) / float(renderer.pitch.x)))
	for i in STREAKS:
		var lane := (float(i) - STREAKS * 0.5) * 1.7 * scale + sin(i * 12.9898) * 0.8
		var phase := fposmod(_t * 2.2 + float(i) * 0.31, 1.0)
		var start := (-6.0 + 26.0 * phase) * scale
		var ink := SPEED_LINE_INK.lerp(Color.BLACK, 1.0 - car.nitro_level * (1.0 - phase) * 0.8)
		for k in int(3.0 * scale):
			var p := origin + back * (start + k) + side * lane
			ov.put_char(int(p.x), int(p.y), g, ink)


## Streaks radiating from the middle of the screen, moving outward.
func _draw_speed_lines(ov: AsciiOverlay) -> void:
	var c := Vector2(ov.cols, ov.rows) * 0.5
	var aspect := float(renderer.pitch.y) / float(renderer.pitch.x) # cells are taller than wide
	for i in SPEED_LINES:
		var ang := float(i) / SPEED_LINES * TAU + 0.37 * i
		var d := Vector2(cos(ang), sin(ang) / aspect).normalized()
		var phase := fposmod(_t * 1.8 + float(i) * 0.137, 1.0)
		var r0 := lerpf(0.45, 1.1, phase) * c.x
		var g := _line_glyph(d * Vector2(1.0, aspect))
		var ink := SPEED_LINE_INK.lerp(Color.BLACK, 1.0 - car.nitro_level * (1.0 - phase * 0.5))
		var len := 4 + int(c.x * 0.06 * phase)
		for k in len:
			var p := c + d * (r0 + k)
			ov.put_char(int(p.x), int(p.y), g, ink)


static func _line_glyph(d: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(d.y, d.x)), 180.0)
	if a < 22.5 or a >= 157.5:
		return "-"
	if a < 67.5:
		return "\\"
	if a < 112.5:
		return "|"
	return "/"
