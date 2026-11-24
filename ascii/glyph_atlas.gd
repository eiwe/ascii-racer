## Runtime glyph atlas: rasterises a charset from a font into a grid of glyph
## boxes (one R8 texture) and measures per-glyph coverage and a 2x3 shape vector.
## Building needs one rendered frame, so build() is a coroutine; `built` fires when done.
class_name GlyphAtlas
extends Node

signal built

const ATLAS_COLS: int = 16
const SHAPE_COLS: int = 2
const SHAPE_ROWS: int = 3

## Characters in atlas order; index 0 is always space.
var chars: String = ""
## Glyph box in pixels (font advance x line height, rounded up).
var box: Vector2i = Vector2i.ONE
var atlas_cols: int = ATLAS_COLS
## R8 texture, ATLAS_COLS x ceil(n / ATLAS_COLS) glyph boxes, coverage in red.
var texture: ImageTexture
## RGBAF, n x 2: row 0 = shape[0..3], row 1 = shape[4], shape[5], coverage, 0.
## Shape components are normalised per component by their maximum over the charset.
var data_texture: ImageTexture
## Mean coverage of each glyph over its whole box (0..1, unnormalised).
var coverage: PackedFloat32Array = PackedFloat32Array()
## Per glyph, the 2x3 shape vector (normalised as in data_texture), for CPU
## glyph matching (e.g. overlay art).
var shape_vectors: Array[PackedFloat32Array] = []
var ready_to_use: bool = false

var _building: bool = false
var _pending: Array = []


func index_of(c: String) -> int:
	var i := chars.find(c)
	return maxi(i, 0)


static func default_charset() -> String:
	var s := ""
	for code in range(32, 127):
		s += char(code)
	return s


## Rebuilds the atlas. Calls made while a build is running are coalesced; the last one wins.
func build(font: Font, size_px: int, charset: String) -> void:
	_pending = [font, size_px, charset]
	if _building:
		return
	_building = true
	while not _pending.is_empty():
		var args: Array = _pending
		_pending = []
		await _build_now(args[0], args[1], args[2])
	_building = false
	built.emit()


func _build_now(font: Font, size_px: int, charset: String) -> void:
	var cs := charset if charset != "" else default_charset()
	# Space first, no duplicates.
	var uniq := " "
	for i in cs.length():
		var c := cs[i]
		if uniq.find(c) < 0:
			uniq += c
	var n := uniq.length()

	var advance := font.get_char_size(ord("M"), size_px).x
	var height := font.get_height(size_px)
	var ascent := font.get_ascent(size_px)
	var bx := Vector2i(maxi(1, ceili(advance)), maxi(1, ceili(height)))
	var rows := ceili(float(n) / ATLAS_COLS)
	var img_size := Vector2i(ATLAS_COLS * bx.x, rows * bx.y)

	var vp := SubViewport.new()
	vp.size = img_size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Node2D.new()
	vp.add_child(canvas)
	var x_off := floorf((bx.x - advance) * 0.5)
	ascent = roundf(ascent)
	canvas.draw.connect(func() -> void:
		for i in n:
			var cell := Vector2(i % ATLAS_COLS, i / ATLAS_COLS) * Vector2(bx)
			canvas.draw_char(font, cell + Vector2(x_off, ascent), uniq[i], size_px, Color.WHITE)
	)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var src := vp.get_texture().get_image()
	vp.queue_free()

	var atlas := Image.create(img_size.x, img_size.y, false, Image.FORMAT_R8)
	for y in img_size.y:
		for x in img_size.x:
			atlas.set_pixel(x, y, Color(src.get_pixel(x, y).a, 0.0, 0.0))

	# Coverage and 2x3 shape vector per glyph. Results are only published at
	# the end, so users never see new indices paired with old textures.
	var cov := PackedFloat32Array()
	cov.resize(n)
	var shapes: Array[PackedFloat32Array] = []
	var shape_max := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	for i in n:
		var org := Vector2i(i % ATLAS_COLS, i / ATLAS_COLS) * bx
		var sums := PackedFloat32Array([0, 0, 0, 0, 0, 0])
		var counts := PackedFloat32Array([0, 0, 0, 0, 0, 0])
		var total := 0.0
		for y in bx.y:
			var sy := mini(y * SHAPE_ROWS / bx.y, SHAPE_ROWS - 1)
			for x in bx.x:
				var sx := mini(x * SHAPE_COLS / bx.x, SHAPE_COLS - 1)
				var a := atlas.get_pixel(org.x + x, org.y + y).r
				var k := sy * SHAPE_COLS + sx
				sums[k] += a
				counts[k] += 1.0
				total += a
		cov[i] = total / float(bx.x * bx.y)
		for k in 6:
			sums[k] /= maxf(counts[k], 1.0)
			shape_max[k] = maxf(shape_max[k], sums[k])
		shapes.append(sums)

	var data := Image.create(n, 2, false, Image.FORMAT_RGBAF)
	var vectors: Array[PackedFloat32Array] = []
	for i in n:
		var s := shapes[i]
		var v := PackedFloat32Array()
		for k in 6:
			v.append(s[k] / maxf(shape_max[k], 1e-4))
		vectors.append(v)
		data.set_pixel(i, 0, Color(v[0], v[1], v[2], v[3]))
		data.set_pixel(i, 1, Color(v[4], v[5], cov[i], 0.0))

	chars = uniq
	box = bx
	coverage = cov
	shape_vectors = vectors
	texture = ImageTexture.create_from_image(atlas)
	data_texture = ImageTexture.create_from_image(data)
	ready_to_use = true


## Indices of `ramp` characters (those present in the atlas), sorted by coverage.
func sorted_ramp(ramp: String) -> PackedInt32Array:
	var idx: Array[int] = []
	for i in ramp.length():
		var j := chars.find(ramp[i])
		if j >= 0 and not idx.has(j):
			idx.append(j)
	if not idx.has(0):
		idx.append(0)
	idx.sort_custom(func(a: int, b: int) -> bool: return coverage[a] < coverage[b])
	return PackedInt32Array(idx)


## LUT of `size` glyph indices mapping tone 0..1 to the ramp glyph whose
## normalised coverage is nearest.
func ramp_lut(ramp: String, size: int) -> PackedInt32Array:
	var idx := sorted_ramp(ramp)
	var lo := coverage[idx[0]]
	var hi := coverage[idx[idx.size() - 1]]
	var lut := PackedInt32Array()
	lut.resize(size)
	for t in size:
		var target := float(t) / float(size - 1)
		var best := idx[0]
		var best_d := INF
		for g in idx:
			var c := (coverage[g] - lo) / maxf(hi - lo, 1e-5)
			var d := absf(c - target)
			if d < best_d:
				best_d = d
				best = g
		lut[t] = best
	return lut


## Glyph indices of `s` in the given order (unknown chars map to space), padded to `size`.
func indices(s: String, size: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(size)
	for i in size:
		out[i] = index_of(s[i]) if i < s.length() else 0
	return out
