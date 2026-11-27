## The phone build's switch and its phone-only sizes. Everything phone-specific
## asks Mobile.active(): true on a phone (the OS feature "mobile", the Android
## export) and on the desktop with the test flag `-- --mobile`, which runs the
## phone layout and input in a window (touch from the mouse, tilt from the
## pointer or the left stick). Desktop and web never see any of it.
class_name Mobile
extends RefCounted

## Phone glyph size: this many text rows on the window height (1080 high: 18 px).
const DEFAULT_ROWS: int = 60
## The pause menu's GLYPH SIZE steps through rows in these steps.
const ROWS_STEP: int = 6
const MIN_ROWS: int = 30
const MAX_ROWS: int = 96
## UI scale (HUD and panel text, buttons): 1.0 at this window height.
const UI_REF_HEIGHT: float = 420.0
## Level display: the largest turn of the picture (degrees); beyond it the
## picture turns with the phone. `-- --levelmax=<deg>` overrides it (tests).
const LEVEL_MAX_DEG: float = 30.0
## Touch steering schemes (the pause menu's CONTROLS, [phone] controls), in
## menu order; the first is the default.
const CONTROLS: PackedStringArray = ["slider", "buttons", "split", "tilt"]
## Driving aids ([phone] keys, pause menu): defaults, ranges and steps. Each
## has a value that turns it off: grip margin 0, steer assist 0, brake assist off.
const GRIP_MARGIN_DEFAULT: float = 1.15
const GRIP_MARGIN_RANGE: Vector3 = Vector3(1.0, 1.6, 0.05) ## min, max, step (and 0 = OFF below the min)
const GRIP_ON_KEYS_DEFAULT: bool = true ## the grip-limited lock for BUTTONS / SPLIT too
const STEER_ASSIST_DEFAULT: float = 0.5
const STEER_ASSIST_RANGE: Vector3 = Vector3(0.0, 1.0, 0.25)
const BRAKE_ASSIST_DEFAULT: bool = true
const CORNER_SPEED_DEFAULT: float = 1.0
const CORNER_SPEED_RANGE: Vector3 = Vector3(0.8, 1.2, 0.05)
const SENSITIVITY_DEFAULT: float = 1.0
const SENSITIVITY_RANGE: Vector3 = Vector3(0.5, 2.0, 0.1)


## A [phone] value stepped by `dir` steps within its range (rounded to the step).
static func step_value(v: float, dir: int, range: Vector3) -> float:
	return clampf(snappedf(v + dir * range.z, range.z), range.x, range.y)


static func level_max_deg() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levelmax="):
			return arg.trim_prefix("--levelmax=").to_float()
	return LEVEL_MAX_DEG

static var _active: int = -1


## True on a phone, or with `-- --mobile` on the desktop.
static func active() -> bool:
	if _active < 0:
		_active = 1 if OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--mobile") else 0
	return _active == 1


## True only on a real phone (not the desktop simulation): sensors, the safe
## area and app focus come from the device.
static func device() -> bool:
	return OS.has_feature("mobile")


## The phone's glyph size: the window height over `rows`, within the
## renderer's 6..64 px.
static func glyph_px(window_h: float, rows: int) -> int:
	return clampi(roundi(window_h / float(maxi(rows, 1))), 6, 64)


## Text and control scale from the window height (a phone's reported display
## scale is not reliable).
static func ui_scale(window_h: float) -> float:
	return maxf(window_h / UI_REF_HEIGHT, 1.0)


## The part of the viewport clear of notches and rounded corners, in viewport
## pixels. On the desktop simulation: the whole viewport.
static func safe_rect(vp: Viewport) -> Rect2:
	var full := vp.get_visible_rect()
	if not device():
		return full
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return full
	# Screen pixels to viewport pixels (the window fills the screen on a phone).
	var k := full.size / win
	var r := Rect2((safe.position - Vector2(DisplayServer.window_get_position())) * k, safe.size * k)
	return r.intersection(full) if r.has_area() else full
