## Game controller: driving HUD with telemetry, lap timer, car reset, handling
## presets and the tuning panel, pad rumble, the iso / chase camera switch (Q,
## pad B), the G (grid snap) and V (rumble) keys, the bridge-deck cutaway, and
## the `--drivetest=<dir>` scripted test mode.
##   --preset=<name>            start with this handling preset
##   --tune=prop=value,...      then override single tunables (quick experiments)
extends Node

const DRIVE_KEYS: String = """Keys  WASD drive (arrows too while tuning is closed)  Space handbrake
      R reset  Q camera  G grid snap  V rumble  F1 tuning  F2 F3 preset  F5 save
Pad   L-stick steer  RT throttle  LT brake  A handbrake  Y/Back reset  B camera
      R-stick look (chase)  Start tuning  LB RB preset  R-stick click save"""
## How often the last on-track position is remembered for R.
const SAFE_POSE_INTERVAL: float = 0.25
const FLASH_TIME: float = 1.5

@onready var renderer: AsciiRenderer = $AsciiRenderer
# The renderer moves its children into its SceneViewport during its own _ready.
@onready var world: Node3D = renderer.scene_viewport.get_node("World")

var controls: AsciiControls
var laps: LapTimer
var car: Car
var track: Track
var camera: FollowCamera
var tuning: CarTuning
var panel: TuningPanel
var rumble: PadRumble
var chase: ChaseCamera
## true = rear chase view, false = isometric (the default).
var chase_view: bool = false
## Chase view: far geometry dissolves into the void over this depth range.
const CHASE_FADE: Vector2 = Vector2(12.0, 32.0)
var chase_fade: bool = true

var _safe_pose: Transform3D
var _safe_timer: float = 0.0
var _pad_text: String = ""
var _flash: String = ""
var _flash_timer: float = 0.0


func _ready() -> void:
	# Smooth motion between physics ticks (the car moves at 120 Hz). Scene-local,
	# so the demo is unaffected.
	get_tree().physics_interpolation = true
	car = world.car
	track = world.track
	camera = world.camera
	camera.renderer = renderer
	camera.snap_to_target()
	laps = LapTimer.new(track)
	_safe_pose = world.grid_pose()

	controls = AsciiControls.new()
	controls.renderer = renderer
	controls.keys_text = DRIVE_KEYS
	add_child(controls)
	controls.zoom_requested.connect(_on_zoom)
	chase = world.chase

	tuning = CarTuning.new(car)
	panel = TuningPanel.new()
	panel.tuning = tuning
	panel.car = car
	add_child(panel)
	panel.preset_changed.connect(func(p: String) -> void: flash("preset " + p))
	panel.saved.connect(func(path: String) -> void: flash("saved custom" if path != "" else "SAVE FAILED"))
	rumble = PadRumble.new()
	rumble.car = car
	add_child(rumble)
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _update_pad_text())
	_update_pad_text()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			tuning.select(arg.trim_prefix("--preset="))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tune="):
			for kv in arg.trim_prefix("--tune=").split(",", false):
				var p := kv.split("=")
				car.set_indexed(p[0], str_to_var(p[1]))
			car.refresh_tuning()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--drivetest="):
			var test := DriveTest.new()
			test.game = self
			test.out_dir = arg.trim_prefix("--drivetest=")
			add_child(test)


## , and . : iso zoom, or chase distance in the chase view.
func _on_zoom(step: int) -> void:
	if chase_view:
		chase.distance_scale *= pow(1.15, step)
	else:
		camera.zoom_index += step


## Switches between the isometric and the chase camera. The iso camera keeps
## following in the background, so switching back restores its framing (zoom,
## snapping, look-ahead) exactly as it would have been.
func set_chase_view(on: bool) -> void:
	chase_view = on
	if on:
		chase.current = true
		chase.snap_to_target()
		track.deck_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		camera.current = true
	renderer.distance_fade = CHASE_FADE if on and chase_fade else Vector2.ZERO


func _update_pad_text(pads: Array[int] = Input.get_connected_joypads()) -> void:
	_pad_text = "no gamepad" if pads.is_empty() else "pad: " + Input.get_joy_name(pads[0])


func flash(text: String) -> void:
	_flash = text
	_flash_timer = FLASH_TIME


## Hides the bridge deck surface (keeping its walls and its shadow) while the
## car is under it, so the iso camera can see the car.
const DECK_CUTAWAY_RADIUS: float = 6.0


func _update_deck_cutaway() -> void:
	if chase_view:
		return # the chase camera keeps the car in view by itself
	var p := car.global_position
	var c := track.crossing_point
	var under := Vector2(p.x - c.x, p.z - c.z).length() < DECK_CUTAWAY_RADIUS and p.y < track.deck_y - 0.8
	var want := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if under else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if track.deck_mesh.cast_shadow != want:
		track.deck_mesh.cast_shadow = want


func _physics_process(delta: float) -> void:
	_update_deck_cutaway()
	laps.update(car.global_position, delta)
	_safe_timer += delta
	if _safe_timer >= SAFE_POSE_INTERVAL:
		_safe_timer = 0.0
		if car.wheels_on_road == 4 and car.is_upright() and track.is_on_road(car.global_position, laps.progress):
			_safe_pose = track.pose_at(laps.progress, clampf(track.lateral_offset(car.global_position, laps.progress), -0.5, 0.5))
	if car.player_input and Input.is_action_just_pressed(&"reset_car"):
		reset_car()


## Puts the car back on the road at the last place it was safely on it.
func reset_car() -> void:
	car.teleport(_safe_pose)
	laps.resync()
	camera.snap_to_target()
	chase.snap_to_target()


func _process(delta: float) -> void:
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var mods := tuning.modified_count()
	var preset := ">> %s <<" % _flash.to_upper() if _flash_timer > 0.0 else "preset %s%s" % [tuning.current, " (modified)" if mods > 0 else ""]
	var rumble_text := "rumble off" if not rumble.enabled or rumble.strength <= 0.0 else "rumble %d%%" % roundi(rumble.strength * 100.0)
	controls.status_text = "%5.1f u/s   lap %d   %s   %s\ncurrent %s   last %s   best %s\n%s   %s   %s\n%s" % [
		car.linear_velocity.length(), laps.lap,
		"on road" if car.wheels_on_road >= 2 else "OFF ROAD", "chase view" if chase_view else ("iso, snap on" if camera.snap_to_grid else "iso, snap off"),
		LapTimer.fmt(laps.current if laps.started else -1.0), LapTimer.fmt(laps.last), LapTimer.fmt(laps.best),
		preset, _pad_text, rumble_text, telemetry()]


## Three lines: steering in vs out, pedals; body slip, grip use per axle,
## sliding wheels; the handbrake drift (state, angle vs target, arc) and boost.
func telemetry() -> String:
	var u := car.wheel_usage
	var slide := PackedStringArray()
	for i in 4:
		slide.append(["FL", "FR", "RL", "RR"][i] if u[i] > 1.0 else "--")
	var drift := "drift --"
	match car.drift_state:
		Car.Drift.DRIFT:
			drift = "DRIFT %s  angle %4.1f / %4.1f deg  arc r %4.1f" % ["R" if car.drift_dir > 0.0 else "L",
				rad_to_deg(car.drift_angle), rad_to_deg(car.drift_target), minf(car.drift_radius, 99.0)]
		Car.Drift.EXIT:
			drift = "drift exit  angle %4.1f deg" % rad_to_deg(car.drift_angle)
	var boost := "boost charge %3d%%" % roundi(car.boost_charge * 100.0)
	if car.boost_left > 0.0:
		boost = "BOOST %3d%% (%.1f s)" % [roundi(car.boost_power * 100.0), car.boost_left]
	return "steer %+.2f %s -> wheels %+5.1f / %4.1f deg   thr %.2f  brk %.2f  %s\nslip %+5.1f deg   grip used F %3d%%  R %3d%%   sliding %s\n%s   %s" % [
		car.steer_input, "pad" if car.steer_analog else "key", rad_to_deg(car.steer_angle), rad_to_deg(car.steer_lock),
		car.throttle_input, car.brake_input, "HANDBRAKE" if car.handbrake_input else "",
		rad_to_deg(car.slip_angle), roundi((u[0] + u[1]) * 50.0), roundi((u[2] + u[3]) * 50.0), " ".join(slide), drift, boost]


func _unhandled_input(event: InputEvent) -> void:
	if not controls.enabled:
		return
	if event.is_action_pressed(&"camera_toggle"):
		set_chase_view(not chase_view)
		flash("chase view" if chase_view else "iso view")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"rumble_toggle"):
		rumble.set_enabled(not rumble.enabled)
		flash("rumble " + ("on" if rumble.enabled else "off"))
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_G:
		camera.snap_to_grid = not camera.snap_to_grid
		get_viewport().set_input_as_handled()
