## All tunables of the ASCII renderer. Assign one to AsciiRenderer.settings;
## any change emits `changed` and the renderer re-applies it live.
class_name AsciiSettings
extends Resource

enum ColorMode { FULL, MONO }

@export_group("Glyphs")
## Font used to build the glyph atlas. Null = bundled Hack Nerd Font Mono Bold.
@export var font: Font:
	set(v):
		font = v
		emit_changed()
## Font size in pixels; the glyph box is font advance x line height at this size.
@export_range(6, 64, 1) var glyph_px: int = 9:
	set(v):
		glyph_px = clampi(v, 6, 64)
		emit_changed()
## Characters in the atlas (index 0 is always space). Empty = printable ASCII 32..126.
@export var charset: String = "":
	set(v):
		charset = v
		emit_changed()
## Horizontal cell pitch as a fraction of the glyph box. < 1 packs glyphs so they overlap.
@export_range(0.5, 1.0, 0.01) var squeeze_x: float = 0.8:
	set(v):
		squeeze_x = clampf(v, 0.5, 1.0)
		emit_changed()
## Vertical cell pitch as a fraction of the glyph box.
@export_range(0.5, 1.0, 0.01) var squeeze_y: float = 0.8:
	set(v):
		squeeze_y = clampf(v, 0.5, 1.0)
		emit_changed()

@export_group("Scene")
## Resolution of the 3D render relative to the output.
@export_range(0.125, 1.0, 0.025) var scene_scale: float = 0.5:
	set(v):
		scene_scale = clampf(v, 0.125, 1.0)
		emit_changed()

@export_group("Tone")
## Applied to luminance before glyph mapping: L' = pow(clamp((L*exposure - 0.5)*contrast + 0.5), 1/gamma).
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.0:
	set(v):
		exposure = v
		emit_changed()
@export_range(0.1, 4.0, 0.01) var contrast: float = 1.35:
	set(v):
		contrast = v
		emit_changed()
@export_range(0.2, 4.0, 0.01) var gamma: float = 1.0:
	set(v):
		gamma = v
		emit_changed()

@export_group("Colour")
@export var color_mode: ColorMode = ColorMode.FULL:
	set(v):
		color_mode = v
		emit_changed()
## Ink colour in MONO mode.
@export var mono_color: Color = Color(0.45, 1.0, 0.55):
	set(v):
		mono_color = v
		emit_changed()
## 0 = ink is the raw cell colour, 1 = hue pushed to full value (density carries brightness).
@export_range(0.0, 1.0, 0.01) var color_boost: float = 0.6:
	set(v):
		color_boost = v
		emit_changed()
## Cell background = cell colour * this (0 = pure black behind glyphs).
@export_range(0.0, 1.0, 0.01) var bg_strength: float = 0.3:
	set(v):
		bg_strength = v
		emit_changed()

@export_group("Ramp")
## Fill ramp for flat cells (see shape_flat_threshold); sorted by measured glyph
## coverage at build time, so order does not matter.
@export var ramp_chars: String = " .,:;-=+*o#%@":
	set(v):
		ramp_chars = v
		emit_changed()

@export_group("Shape")
## Exponent that exaggerates sub-cell contrast before shape matching (1 = none).
@export_range(1.0, 8.0, 0.1) var shape_contrast: float = 2.5:
	set(v):
		shape_contrast = v
		emit_changed()

## Cells whose sub-cell tone range (max - min) is below this use the ramp glyph
## instead: flat areas get calm fill, only structure gets shape-matched glyphs.
@export_range(0.0, 1.0, 0.01) var shape_flat_threshold: float = 0.2:
	set(v):
		shape_flat_threshold = v
		emit_changed()

## Weight on glyph ink placed where the cell is darker than the glyph (1 = plain L2).
## > 1 keeps silhouettes clean at the cost of some contour glyphs.
@export_range(1.0, 4.0, 0.05) var shape_ink_penalty: float = 1.5:
	set(v):
		shape_ink_penalty = v
		emit_changed()
## Distance handicap for glyphs outside ramp_chars, so letters only win where clearly better.
@export_range(0.0, 0.3, 0.005) var shape_ramp_bias: float = 0.04:
	set(v):
		shape_ramp_bias = v
		emit_changed()

## Candidate glyphs for shape matching. Empty = every glyph in the atlas.
@export var shape_chars: String = "":
	set(v):
		shape_chars = v
		emit_changed()
