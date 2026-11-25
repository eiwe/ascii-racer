## The ASCII RACER logo, drawn into the renderer's overlay cell layer: heavy
## block capitals with a forward slant, a cool drop-shadow extrusion, speed
## lines and a chequered flag, animated in (decode, speed lines, glint), held,
## then cleared away to a small title in the corner. Also the "press any key"
## prompt. Everything that defines the look is in this file: edit the
## constants below to try a different logo.
##
## Letters are hand-made bitmaps on a 6 x 7 design grid (LETTERS). They are
## scaled to the cell grid, sheared by SLANT, and sampled at 2 x 3 points per
## cell; full cells get FILL_GLYPH, partial (edge) cells the glyph whose shape
## best matches the coverage, so slanted edges come out as / and the like.
class_name AsciiLogo
extends RefCounted

# --- wordmark --------------------------------------------------------------------

## Lines of text, top to bottom (one line: ["ASCII RACER"]).
const LINES: Array[String] = ["ASCII", "RACER"]
## Horizontal offset of each line, in design units (a stagger reads as motion).
const LINE_INDENT: Array[float] = [0.0, 3.0]
## Letter bitmaps, 7 rows; "#" = ink. Widths may differ.
const LETTERS: Dictionary = {
	"A": [".####.", "##..##", "##..##", "######", "##..##", "##..##", "##..##"],
	"S": [".#####", "##....", "##....", ".####.", "....##", "....##", "#####."],
	"C": [".#####", "##....", "##....", "##....", "##....", "##....", ".#####"],
	"I": ["##", "##", "##", "##", "##", "##", "##"],
	"R": ["#####.", "##..##", "##..##", "#####.", "##.##.", "##..##", "##..##"],
	"E": ["######", "##....", "##....", "#####.", "##....", "##....", "######"],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
}
const LETTER_GAP: float = 1.0 ## design units between letters
const LINE_GAP: float = 1.4 ## design units between lines
## Forward lean: x shift per unit of height (0.25 = about 14 degrees).
const SLANT: float = 0.3
## Width : height of one design unit on screen (pixels), >1 = extended letters.
const UNIT_ASPECT: float = 1.15
## Size: the widest line spans this share of the grid width, unless the whole
## logo would then be taller than MAX_HEIGHT of the grid height.
const WIDTH: float = 0.68
const MAX_HEIGHT: float = 0.42
## Centre of the logo, as a fraction of the grid (x, y).
const CENTRE: Vector2 = Vector2(0.5, 0.31)

# --- glyphs and colours --------------------------------------------------------------

const FILL_GLYPH: String = "#"
## Partial letter cells: a slanted side (ink left or right) gets SIDE_GLYPH, a
## lower edge LOW_GLYPH; an upper edge is filled if at least half covered.
const SIDE_GLYPH: String = "/"
const LOW_GLYPH: String = "_"
## Shadow / extrusion: offset (design units, down-right) and its glyphs.
const SHADOW_OFFSET: Vector2 = Vector2(0.55, 0.6)
const SHADOW_GLYPHS: String = ":;=+/\\|-_.,'`"
const SHADOW_FILL: String = "="
## Letter gradient from top to bottom of each line.
const COLOURS: Array[Color] = [Color("ffe45c"), Color("ffa21f"), Color("ff5a1a"), Color("e0241d")]
const SHADOW_COLOUR: Color = Color("2a4f8f")
const SHADOW_BG: Color = Color("0b1426")
const HIGHLIGHT: Color = Color("ffffff")
## How much the top rim of each stroke is lifted toward HIGHLIGHT.
const RIM: float = 0.45
## Behind the letters: cover the scene this much (1 = solid black under letters).
const LETTER_COVER: float = 1.0
## A soft dark plate under the whole logo box, for contrast with the scene.
const PLATE: float = 0.5
const PLATE_MARGIN: Vector2i = Vector2i(4, 2)
const PLATE_FEATHER: Vector2 = Vector2(6.0, 2.0) ## cells over which the plate fades out

# --- extras ---------------------------------------------------------------------------

## Chequered flag in the space after the shorter line(s): squares per side.
const FLAG: bool = true
const FLAG_SQUARES: Vector2i = Vector2i(5, 5)
const FLAG_LIGHT: Color = Color("eef0f5")
## Speed lines trailing behind each line: design-unit rows, glyphs from the
## letter outward, and length as a share of the space to the left.
const SPEED_LINES: bool = true
const SPEED_ROWS: Array[float] = [0.5, 2.3, 4.1, 5.9]
const SPEED_GLYPHS: String = "==--~-.."
const SPEED_LENGTH: Vector2 = Vector2(0.45, 0.85)

# --- timing (seconds from start) -------------------------------------------------

## Decode: cells scramble, then resolve in a sweep from left to right.
const DECODE: bool = true
const DECODE_START: float = 0.3
const DECODE_SWEEP: float = 1.5
const DECODE_JITTER: float = 0.3
const SCRAMBLE_LEAD: float = 0.55 ## how long a cell scrambles before it resolves
const SCRAMBLE_RATE: float = 14.0 ## scramble glyph changes per second
const SCRAMBLE_GLYPHS: String = "!#$%&*+<>?@[]{}/\\|~=^01"
## Speed lines streak in from the left.
const SPEED_IN: float = 1.7
const SPEED_IN_TIME: float = 0.45
## A bright glint sweeps diagonally across the finished letters.
const GLINT: bool = true
const GLINT_START: float = 2.6
const GLINT_TIME: float = 0.9
const GLINT_WIDTH: float = 7.0 ## cells
const GLINT_LEAN: float = 1.2 ## cells of x per row (diagonal)
## Hold, then clear away (decode in reverse) to the small corner title.
const HOLD_END: float = 6.0
const EXIT_TIME: float = 0.7
## Small persistent title in the top-left corner (mini font).
const TITLE: String = "ASCII RACER"
const TITLE_IN: float = 6.5
const TITLE_POS: Vector2i = Vector2i(3, 2)

# --- mini block font (title and prompt) -------------------------------------------------

## 5-row letters; each "#" is a block of cells (pixel size per use below), and
## rows lean right by `slant` cells (whole cells keep the steps clean).
const MINI: Dictionary = {
	"A": [".##.", "#..#", "####", "#..#", "#..#"],
	"B": ["###.", "#..#", "###.", "#..#", "###."],
	"C": [".###", "#...", "#...", "#...", ".###"],
	"E": ["####", "#...", "###.", "#...", "####"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"K": ["#..#", "#.#.", "##..", "#.#.", "#..#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
	"O": [".##.", "#..#", "#..#", "#..#", ".##."],
	"P": ["###.", "#..#", "###.", "#...", "#..."],
	"R": ["###.", "#..#", "###.", "#.#.", "#..#"],
	"S": [".###", "#...", ".##.", "...#", "###."],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#..#", "#..#", "#..#", "#..#", ".##."],
	"Y": ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
	"D": ["###.", "#..#", "#..#", "#..#", "###."],
	"F": ["####", "#...", "###.", "#...", "#..."],
	"G": [".###", "#...", "#.##", "#..#", ".###"],
	"H": ["#..#", "#..#", "####", "#..#", "#..#"],
	"L": ["#...", "#...", "#...", "#...", "####"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"Q": [".##.", "#..#", "#..#", "#.##", ".###"],
	"V": ["#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"Z": ["####", "...#", "..#.", ".#..", "####"],
	"0": [".##.", "#..#", "#..#", "#..#", ".##."],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###.", "...#", ".##.", "#...", "####"],
	"3": ["###.", "...#", ".##.", "...#", "###."],
	"4": ["#..#", "#..#", "####", "...#", "...#"],
	"5": ["####", "#...", "###.", "...#", "###."],
	"6": [".##.", "#...", "###.", "#..#", ".##."],
	"7": ["####", "...#", "..#.", ".#..", ".#.."],
	"8": [".##.", "#..#", ".##.", "#..#", ".##."],
	"9": [".##.", "#..#", ".###", "...#", ".##."],
	"%": ["#..#", "...#", "..#.", ".#..", "#..#"],
	">": ["#..", ".#.", "..#", ".#.", "#.."],
	"<": ["..#", ".#.", "#..", ".#.", "..#"],
	"+": ["...", ".#.", "###", ".#.", "..."],
	"-": ["...", "...", "###", "...", "..."],
	".": [".", ".", ".", ".", "#"],
	" ": ["..", "..", "..", "..", ".."],
}
const MINI_GLYPH: String = "#"
## Title: small, upright. Prompt: square pixels (2 x 1 cells) leaning one cell
## per row; on grids too narrow for that, 1 x 1 and upright.
const TITLE_PIXEL: Vector2i = Vector2i(1, 1)
const TITLE_SLANT: int = 0
const PROMPT_PIXEL: Vector2i = Vector2i(2, 1)
const PROMPT_SLANT: int = 1
const PROMPT_MAX_WIDTH: float = 0.8 ## share of the grid width

# --- prompt ---------------------------------------------------------------------------

const PROMPT: String = "PRESS ANY KEY OR BUTTON"
const PROMPT_IN: float = 6.8
const PROMPT_Y: float = 0.84 ## fraction of the grid height (top of the letters)
const PROMPT_PERIOD: float = 1.6 ## seconds per slow blink (a fade, not a flash)
const PROMPT_INK: Color = Color("f2f2f2")
const PROMPT_ACCENT: Color = Color("ff8a1f")

## Total time until the logo has finished its intro and the prompt is up.
const DONE: float = PROMPT_IN

var overlay: AsciiOverlay
## What draw_prompt() says (the web build's start screen says something else).
var prompt_text: String = PROMPT
var atlas: GlyphAtlas
## Size of a cell in pixels (renderer pitch), for the unit aspect.
var pitch: Vector2i = Vector2i(5, 10)

var _grid: Vector2i = Vector2i.ZERO
var _chars: String = ""
## Laid-out cells: [x, y, glyph, colour, kind, reveal time] (kind 0 letter, 1 shadow, 2 flag light, 3 flag dark).
var _cells: Array = []
## Speed lines: [y, x_from, x_to, colour] (x_to = the letter edge).
var _streaks: Array = []
var _box: Rect2i = Rect2i()
var _rng := RandomNumberGenerator.new()
var _scramble: PackedInt32Array = PackedInt32Array()
## The plate as cover-texel offsets and strengths (0..1), built with the layout.
var _plate_index: PackedInt32Array = PackedInt32Array()
var _plate_amount: PackedFloat32Array = PackedFloat32Array()
## The finished logo (after the glint, before the exit) drawn once and reused.
var _still: PackedByteArray = PackedByteArray()


## Recomputes the layout if the grid or the atlas changed.
func _ensure_layout() -> void:
	if overlay == null or atlas == null or not atlas.ready_to_use:
		return
	var g := Vector2i(overlay.cols, overlay.rows)
	if g == _grid and atlas.chars == _chars:
		return
	_grid = g
	_chars = atlas.chars
	_still = PackedByteArray()
	_layout()


static func _letter(c: String) -> Array:
	return LETTERS.get(c, LETTERS[" "])


static func _line_width(line: String) -> float:
	var w := 0.0
	for i in line.length():
		w += (_letter(line[i])[0] as String).length()
		if i > 0:
			w += LETTER_GAP
	return w


## Ink at design-unit point (ux, uy) of the wordmark, before shearing: 1 letter,
## 2 flag light square, 3 flag dark square, 0 none.
func _sample(ux: float, uy: float) -> int:
	for li in LINES.size():
		var top := li * (7.0 + LINE_GAP)
		var ly := uy - top
		if ly < 0.0 or ly >= 7.0:
			continue
		# Shear: higher rows lean further right.
		var lx := ux - LINE_INDENT[li] - SLANT * (7.0 - ly)
		var x := 0.0
		var line := LINES[li]
		for i in line.length():
			var bm := _letter(line[i])
			var w := float((bm[0] as String).length())
			if lx >= x and lx < x + w:
				return 1 if (bm[int(ly)] as String)[int(lx - x)] == "#" else 0
			x += w + LETTER_GAP
		if FLAG:
			var fx := lx - x
			var widest := 0.0
			for l in LINES:
				widest = maxf(widest, _line_width(l))
			var room: float = widest + float(LINE_INDENT.max()) - LINE_INDENT[li] - (x - LETTER_GAP)
			if room >= FLAG_SQUARES.x + LETTER_GAP and fx >= 0.0 and fx < room - LETTER_GAP:
				var sq := Vector2((room - LETTER_GAP) / FLAG_SQUARES.x, 7.0 / FLAG_SQUARES.y)
				var cx := int(fx / sq.x)
				var cy := int(ly / sq.y)
				return 2 if (cx + cy) % 2 == 0 else 3
	return 0


func _layout() -> void:
	_cells.clear()
	_streaks.clear()
	_rng.seed = 1234
	_scramble = atlas.indices(SCRAMBLE_GLYPHS, SCRAMBLE_GLYPHS.length())
	var cols := float(_grid.x)
	var rows := float(_grid.y)
	var widest := 0.0
	for li in LINES.size():
		widest = maxf(widest, _line_width(LINES[li]) + LINE_INDENT[li])
	var w_units := widest + SLANT * 7.0 + SHADOW_OFFSET.x
	var h_units := LINES.size() * 7.0 + (LINES.size() - 1) * LINE_GAP + SHADOW_OFFSET.y
	var ux := WIDTH * cols / w_units # cells per unit, x
	var uy := ux * float(pitch.x) / (float(pitch.y) * UNIT_ASPECT)
	if uy * h_units > MAX_HEIGHT * rows:
		var k := MAX_HEIGHT * rows / (uy * h_units)
		ux *= k
		uy *= k
	var size := Vector2(w_units * ux, h_units * uy)
	var origin := Vector2(CENTRE.x * cols, CENTRE.y * rows) - size * 0.5
	_box = Rect2i(Vector2i(origin.floor()), Vector2i(size.ceil()) + Vector2i.ONE)
	_layout_plate()

	var shadow_set := atlas.indices(SHADOW_GLYPHS, SHADOW_GLYPHS.length())
	var fill := atlas.index_of(FILL_GLYPH)
	var shadow_fill := atlas.index_of(SHADOW_FILL)
	var letter_cov := {}
	for y in range(_box.position.y, _box.end.y):
		for x in range(_box.position.x, _box.end.x):
			# 2 x 3 sub-samples (2 x 2 points each) per cell.
			var sub_l := PackedFloat32Array([0, 0, 0, 0, 0, 0])
			var sub_s := PackedFloat32Array([0, 0, 0, 0, 0, 0])
			var flag := 0
			for sy in 3:
				for sx in 2:
					for py in 2:
						for px in 2:
							var cx := x + (sx + (px + 0.5) * 0.5) * 0.5
							var cy := y + (sy + (py + 0.5) * 0.5) / 3.0
							var u := Vector2((cx - origin.x) / ux, (cy - origin.y) / uy)
							var k := _sample(u.x, u.y)
							if k == 1:
								sub_l[sy * 2 + sx] += 0.25
							elif k >= 2:
								flag = k
							elif _sample(u.x - SHADOW_OFFSET.x, u.y - SHADOW_OFFSET.y) == 1:
								sub_s[sy * 2 + sx] += 0.25
			var cov_l := _mean(sub_l)
			var cov_s := _mean(sub_s)
			var t := DECODE_START + DECODE_SWEEP * float(x - _box.position.x) / maxf(_box.size.x, 1.0) + _rng.randf() * DECODE_JITTER
			if cov_l > 0.12:
				var g := fill if cov_l >= 0.9 else _edge_glyph(sub_l, cov_l)
				if g >= 0:
					_cells.append([x, y, g, _letter_colour(origin, uy, y), 0, t])
					letter_cov[Vector2i(x, y)] = cov_l
			elif flag == 2:
				_cells.append([x, y, fill, FLAG_LIGHT, 2, t])
			elif flag == 3:
				_cells.append([x, y, 0, Color.BLACK, 3, t])
			elif cov_s > 0.12:
				var g := shadow_fill if cov_s >= 0.9 else _match(sub_s, shadow_set)
				_cells.append([x, y, g, SHADOW_COLOUR, 1, t + 0.1])
	# Top rim highlight: letter cells with no letter above them.
	for c: Array in _cells:
		if c[4] == 0 and not letter_cov.has(Vector2i(c[0], c[1] - 1)):
			c[3] = (c[3] as Color).lerp(HIGHLIGHT, RIM)
	# Speed lines behind each line's first letter.
	if SPEED_LINES:
		for li in LINES.size():
			var top := li * (7.0 + LINE_GAP)
			for r: float in SPEED_ROWS:
				var y := int(origin.y + (top + r + 0.5) * uy)
				var lx := LINE_INDENT[li] + SLANT * (7.0 - r - 0.5)
				var x_to := int(origin.x + lx * ux) - 2
				var length := _rng.randf_range(SPEED_LENGTH.x, SPEED_LENGTH.y) * x_to
				_streaks.append([y, int(x_to - length), x_to, _gradient((r + 0.5) / 7.0)])


## The plate's cells (feathered rectangle behind the logo).
func _layout_plate() -> void:
	_plate_index.clear()
	_plate_amount.clear()
	var r := _box.grow_individual(PLATE_MARGIN.x, PLATE_MARGIN.y, PLATE_MARGIN.x, PLATE_MARGIN.y)
	var f := Vector2i(PLATE_FEATHER.ceil())
	for y in range(r.position.y - f.y, r.end.y + f.y):
		for x in range(r.position.x - f.x, r.end.x + f.x):
			var dx := maxf(maxf(r.position.x - x, x - (r.end.x - 1)), 0.0) / PLATE_FEATHER.x
			var dy := maxf(maxf(r.position.y - y, y - (r.end.y - 1)), 0.0) / PLATE_FEATHER.y
			var k := 1.0 - clampf(maxf(dx, dy), 0.0, 1.0)
			var i := overlay.cover_index(x, y)
			if k > 0.0 and i >= 0:
				_plate_index.append(i)
				_plate_amount.append(k * k)


func _letter_colour(origin: Vector2, uy: float, y: int) -> Color:
	var u := (y + 0.5 - origin.y) / uy
	for li in LINES.size():
		var top := li * (7.0 + LINE_GAP)
		if u >= top - 0.5 and u < top + 7.5:
			return _gradient(clampf((u - top) / 7.0, 0.0, 1.0))
	return COLOURS[0]


static func _gradient(t: float) -> Color:
	var n := COLOURS.size() - 1
	var f := clampf(t, 0.0, 1.0) * n
	var i := mini(int(f), n - 1)
	return COLOURS[i].lerp(COLOURS[i + 1], f - i)


## Glyph for a partly covered letter cell (sub = 2 x 3 coverage), or -1 for none.
func _edge_glyph(sub: PackedFloat32Array, cov: float) -> int:
	var left := sub[0] + sub[2] + sub[4]
	var right := sub[1] + sub[3] + sub[5]
	var top := sub[0] + sub[1]
	var bottom := sub[4] + sub[5]
	if absf(left - right) > absf(top - bottom):
		return atlas.index_of(SIDE_GLYPH) if cov >= 0.25 else -1
	if cov >= 0.5:
		return atlas.index_of(FILL_GLYPH)
	if bottom > top and cov >= 0.2:
		return atlas.index_of(LOW_GLYPH)
	return -1


static func _mean(v: PackedFloat32Array) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()


## Glyph (from `candidates`) whose shape vector best matches the coverage `sub`.
func _match(sub: PackedFloat32Array, candidates: PackedInt32Array) -> int:
	var mx := 0.0
	for v in sub:
		mx = maxf(mx, v)
	var best := candidates[0]
	var best_d := INF
	var cmax := 0.0
	for gi in candidates:
		cmax = maxf(cmax, atlas.coverage[gi])
	var cov := _mean(sub)
	for gi in candidates:
		var sv := atlas.shape_vectors[gi]
		var smax := 0.0
		for v in sv:
			smax = maxf(smax, v)
		var d := 0.0
		for k in 6:
			var a := sub[k] / maxf(mx, 1e-3)
			var b := sv[k] / maxf(smax, 1e-3)
			d += (a - b) * (a - b)
		d += 2.0 * pow(cov - atlas.coverage[gi] / maxf(cmax, 1e-3), 2.0)
		if d < best_d:
			best_d = d
			best = gi
	return best


func _scramble_glyph(x: int, y: int, t: float) -> int:
	var k := int(t * SCRAMBLE_RATE) + x * 7 + y * 13
	return _scramble[posmod(hash(k) , _scramble.size())]


## Draws the logo as it looks `t` seconds after it started. Returns false
## once it has fully gone (after the exit).
func draw(t: float) -> bool:
	_ensure_layout()
	if _cells.is_empty():
		return t < HOLD_END + EXIT_TIME
	var exit := t - HOLD_END
	if exit > EXIT_TIME + DECODE_JITTER:
		return false
	# Plate.
	# Finished and not changing (after the glint, before the exit): reuse it.
	var still := t >= GLINT_START + GLINT_TIME + 0.05 and exit < 0.0
	if still and not _still.is_empty():
		overlay.set_buffer(_still)
		return true
	if PLATE > 0.0 and exit < 0.0:
		var a := PLATE * clampf((t - DECODE_START + 0.2) / 0.5, 0.0, 1.0) * 255.0
		for i in _plate_index.size():
			overlay.cover_raw(_plate_index[i], int(a * _plate_amount[i]))
	var bw := maxf(_box.size.x, 1.0)
	for c: Array in _cells:
		var x: int = c[0]
		var y: int = c[1]
		var reveal: float = c[5] if DECODE else 0.0
		var kind: int = c[4]
		# Exit: the same sweep in reverse, cells scramble then vanish.
		var gone := HOLD_END + EXIT_TIME * float(x - _box.position.x) / bw + (reveal - DECODE_START) * 0.15
		if t >= gone:
			continue
		if t < reveal - SCRAMBLE_LEAD:
			continue
		var col: Color = c[3]
		if t < reveal or t > gone - 0.18:
			# Scrambling: a random glyph in a dimmer ink.
			if kind == 3:
				continue
			overlay.cover(x, y, LETTER_COVER)
			overlay.put(x, y, _scramble_glyph(x, y, t), col.darkened(0.45))
			continue
		if kind == 1:
			overlay.cover(x, y, LETTER_COVER, SHADOW_BG)
		else:
			overlay.cover(x, y, LETTER_COVER)
		if kind == 3:
			continue
		if GLINT and kind != 1:
			var gt := (t - GLINT_START) / GLINT_TIME
			if gt > 0.0 and gt < 1.0:
				var front := _box.position.x - GLINT_WIDTH * 2.0 + gt * (bw + GLINT_WIDTH * 4.0)
				var d := absf(x - front - (y - _box.position.y) * GLINT_LEAN)
				if d < GLINT_WIDTH:
					col = col.lerp(HIGHLIGHT, 0.9 * (1.0 - d / GLINT_WIDTH))
		overlay.put(x, y, c[2], col)
	if SPEED_LINES:
		_draw_streaks(t, exit)
	if still:
		_still = overlay.get_buffer()
	return true


func _draw_streaks(t: float, exit: float) -> void:
	var p := clampf((t - SPEED_IN) / SPEED_IN_TIME, 0.0, 1.0)
	if p <= 0.0:
		return
	p = 1.0 - pow(1.0 - p, 3.0) # ease out: fast in, settles
	for s: Array in _streaks:
		var y: int = s[0]
		var x0: int = s[1]
		var x1: int = s[2]
		var col: Color = s[3]
		# The head travels from the left edge to the letter; the tail follows.
		var head := lerpf(-10.0, float(x1), p)
		var tail := lerpf(-10.0 - (x1 - x0), float(x0), p)
		if exit > 0.0:
			tail = lerpf(tail, head, clampf(exit / (EXIT_TIME * 0.6), 0.0, 1.0))
		for x in range(int(maxf(tail, 0.0)), int(head) + 1):
			var f := float(x1 - x) / maxf(x1 - x0, 1.0) # 0 at the letter, 1 at the tail
			var gi := mini(int(f * SPEED_GLYPHS.length()), SPEED_GLYPHS.length() - 1)
			overlay.put_char(x, y, SPEED_GLYPHS[gi], col.darkened(clampf(f * 0.85, 0.0, 0.85)))


## Width in cells of `text` in the mini font.
static func mini_width(text: String, pixel: Vector2i, slant: int) -> int:
	var w := 0
	for i in text.length():
		var g: Array = MINI.get(text[i], MINI[" "])
		w += ((g[0] as String).length() + 1) * pixel.x
	return w + slant * 4 * pixel.y


## Draws `text` in the mini font with its top-left at (x, y). `colour` is
## called with the letter's position along the text (0..1); cover darkens the
## scene behind the letters.
func draw_mini(text: String, x: int, y: int, pixel: Vector2i, slant: int, colour: Callable, cover_amount: float) -> void:
	var g := overlay.glyph(MINI_GLYPH)
	var cx := x
	var n := maxf(text.length() - 1, 1.0)
	for i in text.length():
		var bm: Array = MINI.get(text[i], MINI[" "])
		var col: Color = colour.call(float(i) / n)
		var w := (bm[0] as String).length()
		for r in 5:
			var row := bm[r] as String
			for py in pixel.y:
				var lean := slant * (5 * pixel.y - 1 - (r * pixel.y + py))
				for c in w:
					if row[c] != "#":
						continue
					for px in pixel.x:
						var gx := cx + c * pixel.x + px + lean
						var gy := y + r * pixel.y + py
						if cover_amount > 0.0:
							overlay.cover(gx, gy, cover_amount)
						overlay.put(gx, gy, g, col)
		cx += (w + 1) * pixel.x


## The small title in the corner, faded in by `alpha` (0..1).
func draw_title(alpha: float) -> void:
	if alpha <= 0.0 or overlay == null:
		return
	var p := TITLE_POS
	var w := mini_width(TITLE, TITLE_PIXEL, TITLE_SLANT)
	for yy in range(p.y - 1, p.y + 5 * TITLE_PIXEL.y + 1):
		for xx in range(p.x - 2, p.x + w + 2):
			overlay.cover(xx, yy, 0.55 * alpha)
	draw_mini(TITLE, p.x, p.y, TITLE_PIXEL, TITLE_SLANT, func(f: float) -> Color: return _gradient(f).lerp(Color.BLACK, 1.0 - alpha), alpha)


## The prompt, `t` seconds after it appeared: a slow fade in and out.
func draw_prompt(t: float) -> void:
	if t < 0.0 or overlay == null:
		return
	var pixel := PROMPT_PIXEL
	var slant := PROMPT_SLANT
	if mini_width(prompt_text, pixel, slant) > PROMPT_MAX_WIDTH * overlay.cols:
		pixel = Vector2i.ONE
		slant = 0
	var w := mini_width(prompt_text, pixel, slant)
	var x := (overlay.cols - w) / 2
	var y := int(PROMPT_Y * overlay.rows)
	var h := 5 * pixel.y
	var fade_in := clampf(t / 0.4, 0.0, 1.0)
	var pulse := 0.6 + 0.4 * cos(TAU * t / PROMPT_PERIOD)
	var k := fade_in * pulse
	# A dark band with accent rules above and below.
	for yy in range(y - 2, y + h + 2):
		for xx in range(x - 6, x + w + 6):
			overlay.cover(xx, yy, 0.7 * fade_in)
	var rule := overlay.glyph("-")
	for xx in range(x - 6, x + w + 6):
		var edge := 1.0 - absf(float(xx - x - w * 0.5)) / (w * 0.5 + 6.0)
		var c := PROMPT_ACCENT.lerp(Color.BLACK, 1.0 - fade_in * clampf(edge * 1.5, 0.0, 1.0))
		overlay.put(xx, y - 2, rule, c)
		overlay.put(xx, y + h + 1, rule, c)
	draw_mini(prompt_text, x, y, pixel, slant, func(_f: float) -> Color: return PROMPT_INK.lerp(Color.BLACK, 1.0 - k), 0.0)
