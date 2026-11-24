## A layer of character cells drawn over the rendered scene, in the same grid
## and glyphs: for titles, prompts, transitions or a HUD that is part of the
## ASCII picture rather than ordinary UI.
##
## One cell = a glyph with an ink colour, and a cover amount with a background
## colour. Cover 0 leaves the scene cell alone (an overlay glyph, if any, is
## printed over it); cover 1 replaces the scene cell (glyph and background)
## with the background colour; in between dims it toward that colour. Write
## cells from GDScript (usually every frame, after clear()); the renderer uploads
## the changes and resizes the layer with the grid (grid_changed tells you to
## redraw). Get it with AsciiRenderer.get_overlay(); with no overlay, or with
## AsciiRenderer.overlay_enabled false, the output is exactly as without one.
class_name AsciiOverlay
extends RefCounted

var cols: int = 0
var rows: int = 0
## RGBA8, (cols * 2) x rows: texel 2x = ink RGB + glyph index + 1 (0 = none),
## texel 2x + 1 = background RGB + cover.
var texture: ImageTexture
var atlas: GlyphAtlas

var _data: PackedByteArray = PackedByteArray()
var _image: Image
var _dirty: bool = true
var _glyph_cache: Dictionary = {}
var _cache_chars: String = ""


func resize(c: int, r: int) -> void:
	if c == cols and r == rows and texture != null:
		return
	cols = maxi(c, 1)
	rows = maxi(r, 1)
	_data = PackedByteArray()
	_data.resize(cols * 2 * rows * 4)
	_image = Image.create_from_data(cols * 2, rows, false, Image.FORMAT_RGBA8, _data)
	texture = ImageTexture.create_from_image(_image)
	_dirty = true


## Empties every cell (the scene shows through everywhere).
func clear() -> void:
	_data.fill(0)
	_dirty = true


## Atlas index of a character (space if the atlas does not have it).
func glyph(ch: String) -> int:
	if atlas == null:
		return 0
	if atlas.chars != _cache_chars:
		_glyph_cache.clear()
		_cache_chars = atlas.chars
	if not _glyph_cache.has(ch):
		_glyph_cache[ch] = atlas.index_of(ch)
	return _glyph_cache[ch]


func in_grid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows


## Prints glyph `g` (atlas index) in `ink` at cell (x, y).
func put(x: int, y: int, g: int, ink: Color) -> void:
	if not in_grid(x, y):
		return
	var i := (y * cols * 2 + x * 2) * 4
	_data[i] = clampi(roundi(ink.r * 255.0), 0, 255)
	_data[i + 1] = clampi(roundi(ink.g * 255.0), 0, 255)
	_data[i + 2] = clampi(roundi(ink.b * 255.0), 0, 255)
	_data[i + 3] = clampi(g + 1, 1, 255)
	_dirty = true


func put_char(x: int, y: int, ch: String, ink: Color) -> void:
	put(x, y, glyph(ch), ink)


## Covers the scene cell at (x, y): amount 1 = replaced by `bg`, 0 = untouched.
func cover(x: int, y: int, amount: float, bg: Color = Color.BLACK) -> void:
	if not in_grid(x, y):
		return
	var i := (y * cols * 2 + x * 2 + 1) * 4
	var a := clampi(roundi(amount * 255.0), 0, 255)
	if a < _data[i + 3]:
		return # keep the stronger cover
	_data[i] = clampi(roundi(bg.r * 255.0), 0, 255)
	_data[i + 1] = clampi(roundi(bg.g * 255.0), 0, 255)
	_data[i + 2] = clampi(roundi(bg.b * 255.0), 0, 255)
	_data[i + 3] = a
	_dirty = true


## Removes the glyph at (x, y) (its cover stays).
func erase(x: int, y: int) -> void:
	if in_grid(x, y):
		_data[(y * cols * 2 + x * 2) * 4 + 3] = 0
		_dirty = true


## Prints a string from (x, y) to the right, optionally covering the cells under it.
func text(x: int, y: int, s: String, ink: Color, cover_amount: float = 0.0, bg: Color = Color.BLACK) -> void:
	for i in s.length():
		if cover_amount > 0.0:
			cover(x + i, y, cover_amount, bg)
		if s[i] != " ":
			put_char(x + i, y, s[i], ink)


## A copy of every cell (to restore later with set_buffer(), e.g. to reuse a
## drawing that does not change from frame to frame).
func get_buffer() -> PackedByteArray:
	return _data.duplicate()


func set_buffer(buf: PackedByteArray) -> void:
	if buf.size() == _data.size():
		_data = buf.duplicate() # a copy: clear() and fill() write in place
		_dirty = true


## Byte offset of the cover texel of cell (x, y), for cover_raw().
func cover_index(x: int, y: int) -> int:
	return (y * cols * 2 + x * 2 + 1) * 4 if in_grid(x, y) else -1


## Fast path for many black covers: `index` from cover_index(), `amount` 0..255.
func cover_raw(index: int, amount: int) -> void:
	if index < 0 or amount <= _data[index + 3]:
		return
	_data[index] = 0
	_data[index + 1] = 0
	_data[index + 2] = 0
	_data[index + 3] = amount
	_dirty = true


## Uploads the cells if anything changed (the renderer calls this each frame).
func commit() -> void:
	if not _dirty or texture == null:
		return
	_image.set_data(cols * 2, rows, false, Image.FORMAT_RGBA8, _data)
	texture.update(_image)
	_dirty = false
