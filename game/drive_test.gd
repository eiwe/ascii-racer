## `--drivetest=<dir>`: scripted inputs and measurements for tuning the car,
## an autopilot lap, screenshots and the grid-snap check. Writes results.txt and
## PNGs into <dir>, then quits. Run with `--fixed-fps 120` so every frame is one
## physics step (deterministic, faster than real time).
##   --dtonly=spawn,lap,...  run only these tests (names as in _run)
##   --snapdump              also save the grid-snap cell/scene buffers
## The handling preset under test is the game's (`--preset=<name>`). The pad,
## panel and rumble tests inject joypad events for device 0 (a real pad must be
## connected; the rumble test briefly vibrates it). Saving `custom` writes to
## <dir>/car_tuning.cfg, never to user://. Ends with a [summary] block of the
## headline numbers, one `key value` per line, for comparing presets.
##
## Adds a flat, invisible road-grip test pad south of the circuit (x -10..30,
## z -45..-8) and a test tree on it at (25, -40), and a runway east of the
## circuit up to the east straight (at s KERB_S) for the kerb test. Trees of the
## world that stand on either are removed.
class_name DriveTest
extends Node

const SHOT_SIZE: Vector2i = Vector2i(1600, 900)
## Where on the east straight the kerb test crosses it.
const KERB_S: float = 51.0
## An off-road point inside the east lobe (for the reset tests).
const INFIELD: Vector3 = Vector3(22.0, 0.0, 14.0)

var game: Node
var out_dir: String = ""

var car: Car
var track: Track
var world: Node3D
var renderer: AsciiRenderer
var camera: FollowCamera
var _log: PackedStringArray = []
var _autopilot: Autopilot
## Headline numbers for the [summary] block, in insertion order.
var _m: Dictionary = {}


func _ready() -> void:
	car = game.car
	track = game.track
	world = game.world
	renderer = game.renderer
	camera = game.camera
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.controls.enabled = false
	game.controls.hud.visible = false
	game.panel.enabled = false
	game.rumble.set_enabled(false)
	game.tuning.save_path = out_dir.path_join("car_tuning.cfg")
	game.countdown_enabled = false # the countdown scenario turns it on for itself
	renderer.fixed_output_size = SHOT_SIZE
	_build_pad()
	_run.call_deferred()


func _build_pad() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Track.LAYER_SURFACE
	body.collision_mask = 0
	body.set_meta("surface", &"road")
	var k := track.pose_at(KERB_S).origin
	var edge := Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH
	var rects: Array[Rect2] = [Rect2(-10.0, -45.0, 40.0, 37.0), Rect2(k.x + edge, k.z - 1.5, 30.0, 3.0)]
	for prop in world.props.get_children():
		for r in rects:
			if prop is StaticBody3D and r.grow(1.5).has_point(Vector2(prop.position.x, prop.position.z)):
				prop.free()
				break
	for r in rects:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 0.2, r.size.y)
		cs.shape = box
		cs.position = Vector3(r.get_center().x, Track.ROAD_Y - 0.1, r.get_center().y)
		body.add_child(cs)
	world.add_child(body)
	world.add_tree(Vector3(25.0, 0.0, -40.0), false, 1.5)


func log_line(s: String) -> void:
	print(s)
	_log.append(s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _inputs(steer: float, throttle: float, brake: float, hb: bool) -> void:
	car.steer_input = steer
	car.throttle_input = throttle
	car.brake_input = brake
	car.handbrake_input = hb


func _place(pos: Vector3, heading: Vector3, speed: float = 0.0) -> void:
	_inputs(0.0, 0.0, 0.0, false)
	car.teleport(Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), Vector3(pos.x, Track.ROAD_Y, pos.z)))
	if speed > 0.0:
		car.linear_velocity = heading.normalized() * speed
	game.laps.resync()
	camera.snap_to_target()
	await _frames(1)


## Puts the car on the circuit at `s` (lateral offset), facing along it, at `speed`.
func _place_on_track(s: float, lateral: float = 0.0, speed: float = 0.0) -> void:
	_inputs(0.0, 0.0, 0.0, false)
	var xf := track.pose_at(s, lateral)
	car.teleport(xf)
	if speed > 0.0:
		car.linear_velocity = -xf.basis.z * speed
	game.laps.resync()
	camera.snap_to_target()
	await _frames(1)


func _speed() -> float:
	var v := car.linear_velocity
	return Vector2(v.x, v.z).length()


func _yaw() -> float:
	var f := -car.global_basis.z
	return atan2(f.x, -f.z)


## Drives at `target` speed (throttle/brake P-control) with the given steering for `frames`.
func _hold_speed(target: float, steer: float, frames: int) -> void:
	for i in frames:
		var v := car.forward_speed
		_inputs(steer, clampf((target - v) * 1.5, 0.0, 1.0), 0.0, false)
		await _frames(1)


func _shot(file: String, raw: bool = false) -> void:
	renderer.raw_view = raw
	for i in 3:
		await RenderingServer.frame_post_draw
	renderer.get_output_image().save_png(out_dir.path_join(file))
	renderer.raw_view = false
	log_line("  screenshot " + file)


func _run() -> void:
	get_tree().paused = false
	car.player_input = false
	if not renderer.is_atlas_ready():
		await renderer.atlas_ready
	var t0 := Time.get_ticks_msec()
	log_line("drivetest: car mass %.2f, physics %d Hz, track length %.1f, preset %s" % [car.mass, Engine.physics_ticks_per_second, track.length, game.tuning.current])
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dtonly="):
			only = arg.trim_prefix("--dtonly=")
	for t: String in ["spawn", "accel_brake", "corners", "limit", "nitro", "nitro_shots", "turns", "handbrake", "drift", "feel", "offroad", "kerbs", "tree", "cones", "jump", "bridge", "reset_bridge", "keys",
			"pad", "panel", "rumble", "lap", "drift_lap", "demo_laps", "drift_shot", "panel_shot", "halo", "chase", "lighting", "glint", "sweep", "top_down", "grid_snap", "light_stability", "light_fps", "light_roundtrip", "glint_lap", "audio", "pause", "opp_laps", "opp_block", "opp_shove", "opp_start", "opp_menu", "opp_shots", "countdown", "view_ahead", "night", "hud_shots"]:
		if only == "" or t in only.split(","):
			await call("_test_" + t)
	log_line("\n[summary] preset %s" % game.tuning.current)
	for k: String in _m:
		log_line("  %s %s" % [k, _m[k]])
	log_line("drivetest done in %.1f s real time" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(out_dir.path_join("results.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\n")
	f.close()
	game.audio.quit()


func _test_spawn() -> void:
	log_line("\n[spawn] grid pose, no input, 3 s")
	car.teleport(world.grid_pose())
	camera.snap_to_target()
	var p_mid := Vector3.ZERO
	var max_v_late := 0.0
	var max_w_late := 0.0
	for i in 360:
		await _frames(1)
		if i == 180:
			p_mid = car.global_position
		if i > 180:
			max_v_late = maxf(max_v_late, car.linear_velocity.length())
			max_w_late = maxf(max_w_late, car.angular_velocity.length())
	var p_end := car.global_position
	log_line("  origin y %.4f (road %.3f), tilt %.3f deg, wheels grounded %d" % [p_end.y, Track.ROAD_Y,
		rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)), car.wheels_grounded])
	log_line("  drift over last 1.5 s: %.6f units; max |v| %.6f u/s, max |w| %.6f rad/s" % [
		p_mid.distance_to(p_end), max_v_late, max_w_late])
	await _shot("00_spawn.png")


func _test_accel_brake() -> void:
	log_line("\n[accel] test pad, full throttle 4.5 s from rest")
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _frames(30)
	var top := 0.0
	var trace := PackedFloat32Array()
	for i in 540:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		trace.append(car.forward_speed)
		top = maxf(top, car.forward_speed)
	var t95 := -1.0
	var t90 := -1.0
	for i in trace.size():
		if t90 < 0.0 and trace[i] >= 0.9 * top:
			t90 = (i + 1) / 120.0
		if trace[i] >= 0.95 * top:
			t95 = (i + 1) / 120.0
			break
	var steps := PackedStringArray()
	for k in range(30, 540, 30):
		steps.append("%.2f" % trace[k - 1])
	log_line("  top speed %.2f u/s; 90%% at %.2f s, 95%% at %.2f s" % [top, t90, t95])
	_m["top_speed"] = "%.2f" % top
	_m["t90"] = "%.2f s" % t90
	log_line("  speed every 0.25 s: " + ", ".join(steps))

	log_line("[brake] full brake from %.2f u/s" % car.forward_speed)
	var p0 := car.global_position
	var v0 := car.forward_speed
	var frames := 0
	var max_pitch := 0.0
	while car.forward_speed > 0.05 and frames < 600:
		_inputs(0.0, 0.0, 1.0, false)
		await _frames(1)
		frames += 1
		max_pitch = maxf(max_pitch, absf(car.get_node("Lean").rotation.x))
		if frames == 20:
			await _shot("01_braking.png")
	_inputs(0.0, 0.0, 0.0, false)
	log_line("  stopped from %.2f in %.2f s over %.2f units (mean decel %.1f u/s^2); visual pitch max %.1f deg" % [
		v0, frames / 120.0, p0.distance_to(car.global_position), v0 / (frames / 120.0), rad_to_deg(max_pitch)])
	_m["brake"] = "%.2f s / %.2f u" % [frames / 120.0, p0.distance_to(car.global_position)]
	_m["brake_pitch"] = "%.1f deg" % rad_to_deg(max_pitch)
	await _frames(60)
	log_line("  after stop: forward speed %.3f (brake released)" % car.forward_speed)


func _radius_over(frames: int, steer: float, target_speed: float) -> Array:
	# Holds speed and steering, returns [mean radius v/w, mean speed] over the last half.
	var rs := 0.0
	var vs := 0.0
	var n := 0
	for i in frames:
		if target_speed > 0.0:
			_inputs(steer, clampf((target_speed - car.forward_speed) * 1.5, 0.0, 1.0), 0.0, false)
		else:
			_inputs(steer, 1.0, 0.0, false)
		await _frames(1)
		if i >= frames / 2:
			var w := absf(car.angular_velocity.y)
			if w > 1e-3:
				rs += _speed() / w
				vs += _speed()
				n += 1
	return [rs / maxi(n, 1), vs / maxi(n, 1)]


func _test_turns() -> void:
	log_line("\n[turn] full right lock at low speed (holding 1.5 u/s), 6 s")
	await _place(Vector3(0.0, 0.0, -26.0), Vector3.RIGHT)
	await _hold_speed(1.5, 0.0, 120)
	var r: Array = await _radius_over(720, 1.0, 1.5)
	log_line("  radius %.2f at %.2f u/s (front wheel angle %.1f deg)" % [r[0], r[1], rad_to_deg(car.steer_angle)])
	_m["radius_low"] = "%.2f" % r[0]

	log_line("[turn] full lock at top speed, throttle held")
	await _place(Vector3(-8.0, 0.0, -26.0), Vector3.RIGHT)
	await _hold_speed(9.0, 0.0, 420)
	var v0 := car.forward_speed
	var y0 := _yaw()
	var early := 0.0
	var max_slip := 0.0
	var max_lean := 0.0
	for i in 360:
		_inputs(1.0, 1.0, 0.0, false)
		await _frames(1)
		max_slip = maxf(max_slip, absf(car.slip_angle))
		max_lean = maxf(max_lean, absf(car.get_node("Lean").rotation.z) + car.global_basis.y.angle_to(Vector3.UP))
		if i == 59:
			early = _speed() / maxf(absf(car.angular_velocity.y), 1e-3)
			await _shot("02_turn_top_speed.png")
	var late := _speed() / maxf(absf(car.angular_velocity.y), 1e-3)
	log_line("  entry %.2f u/s: radius after 0.5 s %.2f; after 3 s %.2f at %.2f u/s; max body slip %.1f deg; yaw %.0f deg" % [
		v0, early, late, _speed(), rad_to_deg(max_slip), rad_to_deg(absf(wrapf(_yaw() - y0, -PI, PI)))])
	log_line("  max body lean (physical + visual) %.1f deg" % rad_to_deg(max_lean))
	_m["radius_top"] = "%.2f (3 s: %.2f)" % [early, late]
	_m["turn_in_slip"] = "%.1f deg" % rad_to_deg(max_slip)
	_m["lean"] = "%.1f deg" % rad_to_deg(max_lean)

	log_line("[turn] full lock at top speed, lifting off (throttle 0)")
	await _place(Vector3(-8.0, 0.0, -26.0), Vector3.RIGHT)
	await _hold_speed(9.0, 0.0, 420)
	var lift_slip := 0.0
	for i in 120:
		_inputs(1.0, 0.0, 0.0, false)
		await _frames(1)
		lift_slip = maxf(lift_slip, absf(car.slip_angle))
	log_line("  after 1 s: radius %.2f at %.2f u/s; max body slip %.1f deg" % [_speed() / maxf(absf(car.angular_velocity.y), 1e-3), _speed(), rad_to_deg(lift_slip)])
	_m["lift_radius"] = "%.2f" % (_speed() / maxf(absf(car.angular_velocity.y), 1e-3))


func _test_handbrake() -> void:
	for hb in [false, true]:
		log_line("\n[handbrake=%s] from 5 u/s: full right lock 0.8 s, then straighten 1 s" % hb)
		await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
		await _hold_speed(5.0, 0.0, 240)
		var y0 := _yaw()
		var max_slip := 0.0
		for i in 96:
			_inputs(1.0, 0.0, 0.0, hb)
			await _frames(1)
			max_slip = maxf(max_slip, absf(car.slip_angle))
			if hb and i == 50:
				await _shot("03_handbrake_turn.png")
		var yaw_turn := rad_to_deg(absf(wrapf(_yaw() - y0, -PI, PI)))
		log_line("  yaw after 0.8 s: %.0f deg, speed %.2f, max body slip %.1f deg" % [yaw_turn, _speed(), rad_to_deg(max_slip)])
		_m["handbrake_yaw" if hb else "no_handbrake_yaw"] = "%.0f deg (slip %.0f)" % [yaw_turn, rad_to_deg(max_slip)]

	# The catch tests use the handbrake only to provoke a slide in the tyre model,
	# so they run with the classic handbrake (drift_mode off).
	var dm := car.drift_mode
	car.drift_mode = false
	log_line("\n[catch] (classic handbrake) 5.5 u/s, handbrake + full right 0.5 s, then counter-steer (left) with throttle until straight")
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _hold_speed(5.5, 0.0, 240)
	var y0 := _yaw()
	for i in 60:
		_inputs(1.0, 0.6, 0.0, true)
		await _frames(1)
	var slip0 := car.slip_angle
	var caught := -1.0
	var max_slip := absf(slip0)
	for i in 240:
		# Counter-steer against the slide; ease off once it is nearly gone.
		var s := clampf(-car.slip_angle / deg_to_rad(15.0), -1.0, 1.0)
		_inputs(s, 0.5, 0.0, false)
		await _frames(1)
		max_slip = maxf(max_slip, absf(car.slip_angle))
		if caught < 0.0 and absf(car.slip_angle) < deg_to_rad(4.0) and absf(car.angular_velocity.y) < 0.4:
			caught = (i + 1) / 120.0
	log_line("  slip at release %.1f deg, max %.1f; caught (slip < 4 deg, yaw rate < 0.4) after %s; total yaw %.0f deg; speed %.2f" % [
		rad_to_deg(slip0), rad_to_deg(max_slip), ("%.2f s" % caught) if caught >= 0.0 else "NEVER",
		rad_to_deg(absf(wrapf(_yaw() - y0, -PI, PI))), _speed()])
	_m["catch"] = ("%.2f s" % caught) if caught >= 0.0 else "NEVER"

	log_line("[no catch] (classic handbrake) same, but steering left straight (0) after the handbrake")
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _hold_speed(5.5, 0.0, 240)
	y0 = _yaw()
	for i in 60:
		_inputs(1.0, 0.6, 0.0, true)
		await _frames(1)
	max_slip = 0.0
	for i in 240:
		_inputs(0.0, 0.5, 0.0, false)
		await _frames(1)
		max_slip = maxf(max_slip, absf(car.slip_angle))
	log_line("  max slip %.1f deg, total yaw %.0f deg, final slip %.1f deg" % [rad_to_deg(max_slip),
		rad_to_deg(absf(wrapf(_yaw() - y0, -PI, PI))), rad_to_deg(car.slip_angle)])
	_m["no_catch_yaw"] = "%.0f deg" % rad_to_deg(absf(wrapf(_yaw() - y0, -PI, PI)))
	car.drift_mode = dm


func _test_offroad() -> void:
	log_line("\n[off-road] open ground, full throttle 6 s from rest")
	await _place(Vector3(60.0, 0.0, -30.0), Vector3.RIGHT)
	await _frames(30)
	var top := 0.0
	var t95 := -1.0
	var trace := PackedFloat32Array()
	for i in 720:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		trace.append(car.forward_speed)
		top = maxf(top, car.forward_speed)
	for i in trace.size():
		if trace[i] >= 0.95 * top:
			t95 = (i + 1) / 120.0
			break
	log_line("  top speed %.2f u/s (95%% at %.2f s), wheels on road %d" % [top, t95, car.wheels_on_road])
	_m["offroad_top"] = "%.2f" % top
	log_line("[off-road] turn radius full lock at that speed")
	var r: Array = await _radius_over(360, 1.0, 0.0)
	log_line("  radius %.2f at %.2f u/s" % [r[0], r[1]])


## Watches the car for `frames`, returning [max height of origin above road, max |vy|, max tilt deg, min speed].
func _watch(frames: int, steer: float, throttle: float, brake_if: Callable = Callable()) -> Array:
	var max_h := 0.0
	var max_vy := 0.0
	var max_tilt := 0.0
	var air := 0
	for i in frames:
		var br := 1.0 if brake_if.is_valid() and brake_if.call() else 0.0
		_inputs(steer, 0.0 if br > 0.0 else throttle, br, false)
		await _frames(1)
		max_h = maxf(max_h, car.global_position.y - Track.ROAD_Y)
		max_vy = maxf(max_vy, absf(car.linear_velocity.y))
		max_tilt = maxf(max_tilt, rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)))
		if car.wheels_grounded == 0:
			air += 1
	return [max_h, max_vy, max_tilt, air]


func _test_kerbs() -> void:
	var k := track.pose_at(KERB_S)
	var west := k.basis.x # the east straight runs south; its right is west (the infield)
	log_line("\n[kerb 90 deg] runway at top speed straight across the east straight (kerb, road, kerb, ground)")
	await _place(k.origin - west * 30.0, west)
	var hit_speed := 0.0
	while (car.global_position - k.origin).dot(west) < -1.8:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		hit_speed = car.forward_speed
	var w: Array = await _watch(150, 0.0, 1.0, func() -> bool: return (car.global_position - k.origin).dot(west) > 6.0)
	log_line("  hit the kerb at %.2f u/s: max origin height %.3f, max |vy| %.2f, max tilt %.1f deg, airborne %d frames; upright %s, ends %.2f past the centre line, speed %.2f" % [
		hit_speed, w[0], w[1], w[2], w[3], car.is_upright(), (car.global_position - k.origin).dot(west), _speed()])
	_m["kerb_90"] = "at %.2f u/s: tilt %.1f deg, airborne %d frames, upright %s" % [hit_speed, w[2], w[3], car.is_upright()]

	log_line("[kerb re-entry ~35 deg] from the infield ground onto the east straight at off-road speed")
	var start := track.pose_at(KERB_S - 8.0, 7.0).origin
	var target := track.pose_at(KERB_S + 2.0, 0.0).origin
	await _place(start, target - start)
	var spd := 0.0
	var prog := track.progress(car.global_position)
	while track.lateral_offset(car.global_position, prog) > Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH + 0.3:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		prog = track.progress(car.global_position, prog)
		spd = _speed()
	w = await _watch(120, 0.0, 1.0)
	log_line("  hit the kerb at %.2f u/s: max origin height %.3f, max |vy| %.2f, max tilt %.1f deg, airborne %d frames; upright %s, ends at (%.1f, %.1f)" % [
		spd, w[0], w[1], w[2], w[3], car.is_upright(), car.global_position.x, car.global_position.z])

	log_line("[kerb exit ~20 deg] east straight at 7.5 u/s, steering off into the infield")
	await _place_on_track(KERB_S - 7.0, 0.0, 7.5)
	for i in 20:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
	spd = _speed()
	for i in 30:
		_inputs(0.5, 1.0, 0.0, false)
		await _frames(1)
	w = await _watch(90, 0.0, 0.0)
	log_line("  at %.2f u/s: max origin height %.3f, max |vy| %.2f, max tilt %.1f deg, airborne %d frames; upright %s, ends at (%.1f, %.1f)" % [
		spd, w[0], w[1], w[2], w[3], car.is_upright(), car.global_position.x, car.global_position.z])


func _test_tree() -> void:
	log_line("\n[tree] head-on into a tree at top speed")
	await _place(Vector3(-8.0, 0.0, -40.0), Vector3.RIGHT)
	var spd := 0.0
	while car.global_position.x < 24.0 and spd >= 0.0:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		if car.linear_velocity.x < spd - 2.0:
			break
		spd = car.linear_velocity.x
	var w: Array = await _watch(240, 0.0, 0.0)
	log_line("  impact at %.2f u/s: max origin height %.3f, max |vy| %.2f, max tilt %.1f deg; after 2 s upright %s, speed %.2f, at x %.2f" % [
		spd, w[0], w[1], w[2], car.is_upright(), _speed(), car.global_position.x])
	log_line("[reset] R from there puts the car back at the last on-road pose")
	game.reset_car()
	await _frames(60)
	log_line("  after reset: at (%.2f, %.2f), upright %s, wheels on road %d" % [car.global_position.x, car.global_position.z,
		car.is_upright(), car.wheels_on_road])


func _test_cones() -> void:
	log_line("\n[cones] driving through the two cones beside the east straight at 6 u/s")
	var edge := Track.ROAD_HALF_WIDTH + Track.KERB_WIDTH + 0.35
	var cones: Array[RigidBody3D] = []
	for c in world.props.get_children():
		for cs: float in world.CONE_PAIR_S:
			var q := track.pose_at(cs, -edge).origin
			if c is RigidBody3D and Vector2(c.position.x - q.x, c.position.z - q.z).length() < 0.3:
				cones.append(c)
	var before: Array[Vector3] = []
	for c in cones:
		before.append(c.global_position)
	await _place_on_track(44.2, -edge, 6.0)
	var max_tilt := 0.0
	for i in 150:
		_inputs(0.0, clampf((6.0 - car.forward_speed) * 1.5, 0.0, 1.0), 0.0, false)
		await _frames(1)
		max_tilt = maxf(max_tilt, rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)))
	for i in cones.size():
		var c := cones[i]
		log_line("  cone at (%.1f, %.1f): moved %.2f, tilted %.0f deg, sleeping %s" % [before[i].x, before[i].z,
			before[i].distance_to(c.global_position), rad_to_deg(c.global_basis.y.angle_to(Vector3.UP)), c.sleeping])
	log_line("  car: speed after %.2f, max tilt %.1f deg, upright %s" % [_speed(), max_tilt, car.is_upright()])
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _test_keys() -> void:
	log_line("\n[keys] injected key events through the InputMap and the HUD/render keys")
	game.controls.enabled = true
	car.player_input = true
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	car.player_input = true
	var res := PackedStringArray()
	for pair: Array in [[KEY_W, "throttle_input"], [KEY_UP, "throttle_input"], [KEY_S, "brake_input"], [KEY_DOWN, "brake_input"]]:
		_key(pair[0], true)
		await _frames(2)
		res.append("%s->%s %.1f" % [OS.get_keycode_string(pair[0]), pair[1], car.get(pair[1])])
		_key(pair[0], false)
	for pair: Array in [[KEY_A, -1.0], [KEY_LEFT, -1.0], [KEY_D, 1.0], [KEY_RIGHT, 1.0]]:
		_key(pair[0], true)
		await _frames(2)
		res.append("%s->steer %.1f" % [OS.get_keycode_string(pair[0]), car.steer_input])
		_key(pair[0], false)
	_key(KEY_SPACE, true)
	await _frames(2)
	res.append("Space->handbrake %s" % car.handbrake_input)
	_key(KEY_SPACE, false)
	log_line("  " + ", ".join(res))
	var snap0 := camera.snap_to_grid
	_key(KEY_G, true)
	_key(KEY_G, false)
	var m0: String = game.lighting.mode_name()
	_key(KEY_4, true)
	_key(KEY_4, false)
	var m1: String = game.lighting.mode_name()
	# Sun keys in lighting 4 (low sun): L swings it round, I raises it (held 0.5 s each).
	var az0: float = game.lighting.sun_az
	var el0: float = game.lighting.sun_el
	_key(KEY_L, true)
	await _frames(60)
	_key(KEY_L, false)
	_key(KEY_I, true)
	await _frames(60)
	_key(KEY_I, false)
	await _frames(2)
	log_line("  4 then L, I held 0.5 s: sun az %.1f -> %.1f, el %.1f -> %.1f; HUD \"%s\"" % [
		az0, game.lighting.sun_az, el0, game.lighting.sun_el, game.controls.mode_text])
	game.lighting.reset_sun()
	_key(KEY_3, true)
	_key(KEY_3, false)
	_key(KEY_L, true)
	await _frames(30)
	_key(KEY_L, false)
	log_line("  3 then L: classic sun unchanged %s" %
		game.lighting.sun.basis.is_equal_approx(Basis.looking_at(-Lighting.CLASSIC_FROM.normalized(), Vector3.UP)))
	var z0 := camera.size
	_key(KEY_COMMA, true)
	_key(KEY_COMMA, false)
	var z1 := camera.size
	_key(KEY_PERIOD, true)
	_key(KEY_PERIOD, false)
	log_line("  G: snap %s -> %s; 4: lighting %s -> %s (3 restores %s); ,: zoom %.1f -> %.1f (. restores %.1f)" % [
		snap0, camera.snap_to_grid, m0, m1, game.lighting.mode_name(), z0, z1, camera.size])
	camera.snap_to_grid = snap0
	# R: drive off the road onto the pad... then reset (the pad counts as road, so use the circuit).
	car.player_input = false
	await _place(INFIELD, Vector3.RIGHT)
	car.player_input = true
	_key(KEY_R, true)
	await _frames(2)
	_key(KEY_R, false)
	await _frames(30)
	log_line("  R: car from the infield %s reset to (%.2f, %.2f), on road %d wheels" % [INFIELD, car.global_position.x,
		car.global_position.z, car.wheels_on_road])
	car.player_input = false
	game.controls.enabled = false


func _test_lap() -> void:
	log_line("\n[autopilot] from the grid until two laps are complete")
	_inputs(0.0, 0.0, 0.0, false)
	car.teleport(world.grid_pose())
	game.laps.reset()
	camera.snap_to_target()
	await _frames(60)
	_autopilot = Autopilot.new()
	_autopilot.car = car
	_autopilot.track = track
	add_child(_autopilot)
	var laps: LapTimer = game.laps
	var completed: Array[float] = []
	laps.lap_completed.connect(func(t: float) -> void: completed.append(t))
	var off_frames := 0
	var air_frames := 0
	var max_lat := 0.0
	var frames := 0
	var t_real := Time.get_ticks_usec()
	var shots := {18.0: "10_lap_straight", 38.0: "11_lap_corner", 122.0: "12_lap_hairpin", 66.0: "13_lap_s_bend",
		78.0: "17_lap_sweeper", 26.5: "18_lap_jump", 1.0: "19_lap_on_bridge", 99.6: "20_lap_under_bridge"}
	var taken := {}
	var max_v := 0.0
	var started_frames := -1
	while completed.size() < 2 and frames < 120 * 90:
		await _frames(1)
		frames += 1
		max_v = maxf(max_v, car.forward_speed)
		if car.wheels_grounded > car.wheels_on_road:
			off_frames += 1 # a wheel on the ground (off the road), not counting the air
		if car.wheels_grounded == 0:
			air_frames += 1
		max_lat = maxf(max_lat, absf(track.lateral_offset(car.global_position, laps.progress)))
		if laps.lap == 2:
			for s: float in shots:
				if not taken.has(s) and absf(laps.progress - s) < 0.2:
					taken[s] = true
					log_line("  at s %.1f: speed %.2f, steer %.1f deg, slip %.1f deg, lean accel %.1f u/s^2" % [
						s, car.forward_speed, rad_to_deg(car.steer_angle), rad_to_deg(car.slip_angle), car.local_accel.x])
					await _shot(shots[s] + ".png")
					await _shot(shots[s] + "_raw.png", true)
					if s == 18.0:
						# The whole window, HUD included (the window may not be 1600x900).
						game.controls.hud.visible = true
						for k in 3:
							await RenderingServer.frame_post_draw
						get_viewport().get_texture().get_image().save_png(out_dir.path_join("15_window_with_hud.png"))
						game.controls.hud.visible = false
						log_line("  screenshot 15_window_with_hud.png (window %s)" % get_window().size)
	var secs := (Time.get_ticks_usec() - t_real) / 1e6
	log_line("  laps: %s (best %s); %d frames with a wheel off the road, %d frames airborne; max |lateral| %.2f; max speed %.2f" % [
		", ".join(completed.map(func(t: float) -> String: return LapTimer.fmt(t))), LapTimer.fmt(laps.best),
		off_frames, air_frames, max_lat, max_v])
	_m["autopilot_laps"] = "%s (%d frames off road, %d airborne, max lateral %.2f)" % [
		", ".join(completed.map(func(t: float) -> String: return LapTimer.fmt(t))) if completed.size() > 0 else "NONE", off_frames, air_frames, max_lat]
	log_line("  throughput: %d frames in %.1f s real = %.0f fps (vsync off, fixed 120 Hz steps)" % [frames, secs, frames / secs])
	_autopilot.enabled = false
	_autopilot.queue_free()
	_inputs(0.0, 0.0, 0.0, false)


func _test_drift_shot() -> void:
	log_line("\n[drift] into the hairpin at 6.5 u/s, handbrake + full right, throttle on")
	var s := 112.0
	var xf := track.pose_at(s)
	await _place(xf.origin, -xf.basis.z, 6.5)
	var max_slip := 0.0
	var shot := false
	for i in 90:
		_inputs(1.0, 1.0, 0.0, i < 35)
		await _frames(1)
		max_slip = maxf(max_slip, absf(car.slip_angle))
		if not shot and absf(car.slip_angle) > deg_to_rad(25.0):
			shot = true
			log_line("  shot at %.2f s: slip %.1f deg, speed %.2f, front wheels %.1f deg" % [(i + 1) / 120.0,
				rad_to_deg(car.slip_angle), _speed(), rad_to_deg(car.steer_angle)])
			await _shot("14_drift.png")
			await _shot("14_drift_raw.png", true)
	log_line("  max slip %.1f deg" % rad_to_deg(max_slip))
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(120)


func _test_top_down() -> void:
	log_line("\n[top-down] raw 3D view of the whole circuit")
	var keep_target := camera.target
	camera.target = null
	var keep_rot := camera.rotation
	var keep_size := camera.size
	camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	var aspect := float(SHOT_SIZE.x) / SHOT_SIZE.y
	camera.size = maxf(track.bounds.size.z, track.bounds.size.x / aspect) * 1.08
	var c := track.bounds.get_center()
	camera.global_position = Vector3(c.x, 30.0, c.z)
	await _shot("20_top_down_raw.png", true)
	await _shot("21_top_down_ascii.png")
	camera.rotation = keep_rot
	camera.size = keep_size
	camera.target = keep_target
	log_line("  circuit bounds x %.1f..%.1f, z %.1f..%.1f (incl. 1 unit margin)" % [track.bounds.position.x,
		track.bounds.end.x, track.bounds.position.z, track.bounds.end.z])


func _test_grid_snap() -> void:
	log_line("\n[grid snap] static scene, two camera positions, cell buffers compared")
	var snap_keep := camera.snap_to_grid
	car.teleport(Transform3D(Basis.IDENTITY, Vector3(150.0, Track.ROAD_Y, 150.0)))
	var keep_target := camera.target
	camera.target = null
	await _frames(30)
	# A static view round a tree near the middle of the circuit.
	var tree_p := Vector3.ZERO
	var best := INF
	for prop in world.props.get_children():
		if prop is StaticBody3D and prop.position.distance_to(track.bounds.get_center()) < best and prop.position.distance_to(track.point_at(Track.START_S)) > 4.0:
			best = prop.position.distance_to(track.bounds.get_center())
			tree_p = prop.position
	var a := Vector3(tree_p.x, 0.15, tree_p.z - 1.0)
	var b := a + Vector3(1.37, 0.0, 0.83)
	# Passes: snapping on, snapping off, then two diagnostics with
	# snapping on that remove what the snapping cannot: Godot's soft shadow filter
	# rotates its sample disk per *screen* pixel (penumbras cannot survive a
	# scroll), and its shading uses per-pixel view vectors from the camera
	# position even in ortho, so it changes a little when the camera moves.
	#   2: hard shadows.  3: camera pushed 280 units back (near-parallel view
	#   rays; this also puts everything past the 40-unit shadow distance).
	for pass_i in 4:
		var snap := pass_i != 1
		var hard := pass_i == 2
		var far_cam := pass_i == 3
		camera.far = 400.0 if far_cam else 60.0
		RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_HARD if hard else ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
		camera.snap_to_grid = snap
		camera.focus = a
		camera._place()
		if far_cam:
			camera.global_position += camera.global_basis.z * 280.0
		await _settle()
		var pa := camera.global_position
		var ia := renderer.cell_viewport.get_texture().get_image()
		var sa := renderer.scene_viewport.get_texture().get_image()
		var tree_c := _cell_of(Vector3(tree_p.x, 0.4, tree_p.z))
		camera.focus = b
		camera._place()
		if far_cam:
			camera.global_position += camera.global_basis.z * 280.0
		await _settle()
		var pb := camera.global_position
		var ib := renderer.cell_viewport.get_texture().get_image()
		var sb := renderer.scene_viewport.get_texture().get_image()
		var step := renderer.snap_step(camera)
		var cell := Vector2(float(renderer.pitch.x) / renderer.output_size.x * camera.size * renderer.scene_viewport.size.x / renderer.scene_viewport.size.y,
			float(renderer.pitch.y) / renderer.output_size.y * camera.size)
		var bas := camera.global_basis
		var d := pb - pa
		var shift := Vector2(d.dot(bas.x) / cell.x, -d.dot(bas.y) / cell.y) # cells, screen x right / y down
		var si := Vector2i(roundi(shift.x), roundi(shift.y))
		var res := _compare(ia, ib, si, tree_c)
		log_line("  snap %s%s: cell %.4f x %.4f world, snap step %.4f x %.4f; camera moved %.3f cells right, %.3f cells down" % [
			"ON " if snap else "OFF", " [diagnostic: hard shadows]" if hard else (" [diagnostic: camera 280 further back, no shadows]" if far_cam else ""), cell.x, cell.y, step.x, step.y, shift.x, -shift.y])
		log_line("    overlap %d cells: glyph differs in %d, ink colour differs in %d, background differs in %d; tree box (%s): %d/%d glyphs differ" % res)
		if OS.get_cmdline_user_args().has("--snapdump"):
			ia.save_png(out_dir.path_join("30_cells_%d_a.png" % pass_i))
			ib.save_png(out_dir.path_join("30_cells_%d_b.png" % pass_i))
			sa.save_png(out_dir.path_join("30_scene_%d_a.png" % pass_i))
			sb.save_png(out_dir.path_join("30_scene_%d_b.png" % pass_i))
	camera.snap_to_grid = snap_keep
	camera.far = 60.0
	camera.target = keep_target
	RenderingServer.directional_soft_shadow_filter_set_quality(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))


func _settle() -> void:
	for i in 6:
		await RenderingServer.frame_post_draw


## Compares cells of frame A with frame B shifted by `s` cells (a static point
## at cell c in A is at c - s in B). Also reports a box round the test tree.
func _compare(ia: Image, ib: Image, s: Vector2i, tree_c: Vector2i) -> Array:
	var cols := renderer.cols
	var rows := renderer.rows
	var glyph := 0
	var ink := 0
	var bg := 0
	var n := 0
	var box := Rect2i(tree_c - Vector2i(12, 10), Vector2i(24, 18))
	var tree_n := 0
	var tree_diff := 0
	for y in rows:
		for x in cols:
			var xb := x - s.x
			var yb := y - s.y
			if xb < 0 or yb < 0 or xb >= cols or yb >= rows:
				continue
			n += 1
			var k := AsciiRenderer.SLOTS
			var a0 := ia.get_pixel(x * k, y)
			var b0 := ib.get_pixel(xb * k, yb)
			var a2 := ia.get_pixel(x * k + k - 1, y)
			var b2 := ib.get_pixel(xb * k + k - 1, yb)
			var gd := roundi(a0.a * 255.0) != roundi(b0.a * 255.0)
			if gd:
				glyph += 1
			if not a0.is_equal_approx(b0) and not gd:
				ink += 1
			if not a2.is_equal_approx(b2):
				bg += 1
			if box.has_point(Vector2i(x, y)):
				tree_n += 1
				if gd:
					tree_diff += 1
	return [n, glyph, ink, bg, str(box), tree_diff, tree_n]


func _cell_of(p: Vector3) -> Vector2i:
	var uv := camera.unproject_position(p) / Vector2(renderer.scene_viewport.size)
	return Vector2i(int(uv.x * renderer.output_size.x / renderer.pitch.x), int(uv.y * renderer.output_size.y / renderer.pitch.y))


## Handling character: power oversteer, the assist against a held lock, and how
## long a slide can be held with a fixed simple controller.
func _test_feel() -> void:
	log_line("\n[response] step steer: 5 u/s straight, then 0.6 right held (speed held); time to 90% of the yaw rate after 1.5 s")
	await _place(Vector3(-8.0, 0.0, -26.0), Vector3.RIGHT)
	await _hold_speed(5.0, 0.0, 240)
	var yr := PackedFloat32Array()
	for i in 180:
		_inputs(0.6, clampf((5.0 - car.forward_speed) * 1.5, 0.0, 1.0), 0.0, false)
		await _frames(1)
		yr.append(absf(car.angular_velocity.y))
	var t90 := -1.0
	var peak := 0.0
	for i in yr.size():
		peak = maxf(peak, yr[i])
		if t90 < 0.0 and yr[i] >= 0.9 * yr[yr.size() - 1]:
			t90 = (i + 1) / 120.0
	log_line("  yaw rate after 1.5 s %.2f rad/s, 90%% reached after %.2f s, overshoot peak %.2f" % [yr[yr.size() - 1], t90, peak])
	_m["step_steer_t90"] = "%.2f s (overshoot %.0f%%)" % [t90, 100.0 * (peak / maxf(yr[yr.size() - 1], 1e-3) - 1.0)]

	log_line("[power] steady 4.5 u/s at 0.8 right lock, then full throttle with the lock held 1 s")
	for catch_it in [false, true]:
		await _place(Vector3(-8.0, 0.0, -26.0), Vector3.RIGHT)
		await _hold_speed(4.5, 0.0, 180)
		await _hold_speed(4.5, 0.8, 240)
		var slip0 := absf(car.slip_angle)
		var max_slip := 0.0
		var t20 := -1.0
		var caught := -1.0
		var stepped := -1
		for i in 240 if catch_it else 120:
			var thr := 1.0
			var st := 0.8
			if catch_it and stepped >= 0:
				# Rear stepped out: counter-steer against the slip, half throttle.
				st = clampf(car.slip_angle / deg_to_rad(15.0), -1.0, 1.0)
				thr = 0.5
			_inputs(st, thr, 0.0, false)
			await _frames(1)
			var sl := absf(car.slip_angle)
			max_slip = maxf(max_slip, sl)
			if t20 < 0.0 and sl > deg_to_rad(20.0):
				t20 = (i + 1) / 120.0
				stepped = i
			if catch_it and stepped >= 0 and caught < 0.0 and sl < deg_to_rad(6.0) and absf(car.angular_velocity.y) < 1.5:
				caught = (i - stepped) / 120.0
				break
		if not catch_it:
			log_line("  lock held: body slip %.1f -> max %.1f deg; slip passed 20 deg after %s" % [rad_to_deg(slip0), rad_to_deg(max_slip), ("%.2f s" % t20) if t20 >= 0.0 else "never"])
			_m["power_slip"] = "%.1f -> %.1f deg (20 deg after %s)" % [rad_to_deg(slip0), rad_to_deg(max_slip), ("%.2f s" % t20) if t20 >= 0.0 else "never"]
		elif t20 >= 0.0:
			log_line("  counter-steer + half throttle once past 20 deg: max slip %.1f deg, caught (slip < 6, yaw rate < 1.5) after %s" % [rad_to_deg(max_slip), ("%.2f s" % caught) if caught >= 0.0 else "NEVER"])
			_m["power_catch"] = ("%.2f s (max slip %.0f deg)" % [caught, rad_to_deg(max_slip)]) if caught >= 0.0 else "NEVER"
		else:
			_m["power_catch"] = "n/a (never past 20 deg)"

	log_line("[lift-off] steady 6 u/s at 0.6 right lock, then lift (throttle 0) 0.75 s")
	await _place(Vector3(-8.0, 0.0, -26.0), Vector3.RIGHT)
	await _hold_speed(6.0, 0.0, 300)
	await _hold_speed(6.0, 0.6, 120)
	var slip0 := absf(car.slip_angle)
	var max_slip := 0.0
	var w0 := absf(car.angular_velocity.y)
	var max_w := 0.0
	for i in 90:
		_inputs(0.6, 0.0, 0.0, false)
		await _frames(1)
		max_slip = maxf(max_slip, absf(car.slip_angle))
		max_w = maxf(max_w, absf(car.angular_velocity.y))
	log_line("  body slip %.1f -> max %.1f deg; yaw rate %.2f -> max %.2f rad/s; speed %.2f" % [
		rad_to_deg(slip0), rad_to_deg(max_slip), w0, max_w, _speed()])
	_m["liftoff_slip"] = "%.1f -> %.1f deg" % [rad_to_deg(slip0), rad_to_deg(max_slip)]

	var dm := car.drift_mode
	car.drift_mode = false # the handbrake only provokes a tyre slide here
	log_line("[assist vs held lock] (classic handbrake) 6 u/s, handbrake + full right 0.4 s, then keep full right with throttle 0.6 s")
	for centred in [false, true]:
		await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
		await _hold_speed(6.0, 0.0, 240)
		for i in 48:
			_inputs(1.0, 0.6, 0.0, true)
			await _frames(1)
		var worst := INF
		var worst_lock := 0.0
		var at_slip := 0.0
		var sum := 0.0
		var n := 0
		for i in 72:
			_inputs(0.0 if centred else 1.0, 0.6, 0.0, false)
			await _frames(1)
			if absf(car.slip_angle) > deg_to_rad(10.0):
				var a := car.steer_angle
				sum += a
				n += 1
				if not centred and a / car.steer_lock < worst:
					worst = a / car.steer_lock
					worst_lock = car.steer_lock
					at_slip = car.slip_angle
		if centred:
			log_line("  stick centred: mean front wheel angle while sliding %.1f deg (assist %.2f counter-steers on its own)" % [
				rad_to_deg(sum / maxi(n, 1)), car.counter_steer_assist])
			_m["assist_centred"] = "%.1f deg" % rad_to_deg(sum / maxi(n, 1))
		else:
			log_line("  full right held: front wheels never below %.0f%% of the lock over %d sliding frames (worst %.1f of %.1f deg, at slip %.1f deg)" % [
				worst * 100.0 if n > 0 else 0.0, n, rad_to_deg(worst * worst_lock), rad_to_deg(worst_lock), rad_to_deg(at_slip)])
			_m["assist_held_lock"] = "%.0f%% of lock" % (worst * 100.0 if n > 0 else 0.0)

	log_line("[hold] (classic handbrake, tyre model) 5.5 u/s, handbrake + full right until slip > 15 deg, then a PD slip controller (counter-steer and throttle) aims for 25 deg, up to 4 s; best of 5 steering offsets")
	var best: Array = []
	var row := PackedStringArray()
	for offset in [-0.4, -0.2, 0.0, 0.2, 0.4]:
		var r: Array = await _hold_slide(offset)
		row.append("%+.1f:%.2f%s" % [offset, r[0], "S" if r[3] == "spin" else ""])
		if best.is_empty() or r[0] > best[0]:
			best = r + [offset]
	log_line("    seconds held by offset (S = spun): " + " ".join(row))
	log_line("  best: held %.2f s at offset %+.1f, mean slip %.1f deg, mean speed %.2f; ended by %s" % [best[0], best[4], best[1], best[2], best[3]])
	var full := 0
	for t in row:
		if t.ends_with(":4.00"):
			full += 1
	_m["tyre_slide_hold"] = "%.2f s at %.0f deg, %.2f u/s (%s); full 4 s for %d/5 offsets" % [best[0], best[1], best[2], best[3], full]
	car.drift_mode = dm
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(120)
	_inputs(0.0, 0.0, 0.0, false)


## One slide-holding attempt; returns [seconds held, mean slip deg, mean speed, how it ended].
## The slide counts while body slip stays within 12..75 deg.
func _hold_slide(offset: float) -> Array:
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _hold_speed(5.5, 0.0, 240)
	for i in 72:
		_inputs(1.0, 0.8, 0.0, true)
		await _frames(1)
		if absf(car.slip_angle) > deg_to_rad(15.0):
			break
	var held := 0
	var how := "time limit"
	var speeds := 0.0
	var slips := 0.0
	var prev := absf(car.slip_angle)
	for i in 480:
		# Right-hand drift (slip negative). Too much slip, or slip growing -> more
		# counter-steer (left) and less throttle; too little -> the opposite.
		var sl := absf(car.slip_angle)
		var e := (sl - deg_to_rad(25.0)) / deg_to_rad(15.0)
		var de := (sl - prev) * 120.0 * 0.25 / deg_to_rad(15.0)
		prev = sl
		_inputs(clampf(offset - e - de, -1.0, 1.0), clampf(0.8 - 0.5 * (e + de), 0.2, 1.0), 0.0, false)
		await _frames(1)
		sl = absf(car.slip_angle)
		if sl > deg_to_rad(75.0):
			how = "spin"
			break
		if sl < deg_to_rad(12.0):
			how = "grip"
			break
		held += 1
		speeds += _speed()
		slips += sl
	return [held / 120.0, rad_to_deg(slips / maxi(held, 1)), speeds / maxi(held, 1), how]


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _joy_button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _tap(button: JoyButton) -> void:
	_joy_button(button, true)
	await _frames(1)
	_joy_button(button, false)
	await _frames(1)


func _tap_key(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(1)


## Frames until the front wheels reach `frac` of `target_deg` (sign included), at most `limit`.
func _frames_to_angle(target_deg: float, frac: float, limit: int = 120) -> int:
	for i in limit:
		await _frames(1)
		if car.steer_angle * signf(target_deg) >= absf(deg_to_rad(target_deg)) * frac - 1e-4:
			return i + 1
	return -1


func _test_pad() -> void:
	log_line("\n[pad] injected joypad events (device 0, %s) through the InputMap" % (Input.get_joy_name(0) if Input.get_connected_joypads().has(0) else "NOT CONNECTED"))
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	car.player_input = true
	var lock := car.max_steer_low_deg
	# Response to a full flick, standing still (no assist, full lock).
	_joy_axis(JOY_AXIS_LEFT_X, 1.0)
	var f_stick := await _frames_to_angle(lock, 0.9)
	var analog := car.steer_analog
	_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	var centre_stick := 0
	for i in 120:
		if absf(car.steer_angle) < deg_to_rad(0.1 * lock):
			break
		centre_stick += 1
		await _frames(1)
	await _frames(60)
	_key(KEY_D, true)
	var f_key := await _frames_to_angle(lock, 0.9)
	var key_analog := car.steer_analog
	_key(KEY_D, false)
	var centre_key := 0
	for i in 120:
		await _frames(1)
		centre_key += 1
		if absf(car.steer_angle) < deg_to_rad(0.1 * lock):
			break
	log_line("  full right, 90%% of lock: stick %d frames (%.0f ms, analog=%s), key D %d frames (%.0f ms, analog=%s); release to 10%%: stick %d frames, key %d frames" % [
		f_stick, f_stick / 0.12, analog, f_key, f_key / 0.12, key_analog, centre_stick, centre_key])
	_m["steer_90pct_stick_key"] = "%.0f ms / %.0f ms" % [f_stick / 0.12, f_key / 0.12]
	# Response curve.
	var curve := PackedStringArray()
	for x in [0.2, 0.5, 0.8, 1.0]:
		_joy_axis(JOY_AXIS_LEFT_X, -x)
		await _frames(30)
		curve.append("%.1f -> %.0f%%" % [-x, 100.0 * car.steer_angle / deg_to_rad(lock)])
	_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(30)
	log_line("  stick -> wheel (fraction of lock, deadzone %.2f, exponent %.2f): %s" % [InputMap.action_get_deadzone(&"steer_left"), car.stick_steer_exponent, ", ".join(curve)])
	# Switching mid-drive: stick held, then key while stick centred, then stick again.
	_joy_axis(JOY_AXIS_LEFT_X, 0.6)
	await _frames(10)
	var s1 := "%s %.2f" % ["pad" if car.steer_analog else "key", car.steer_input]
	_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	_key(KEY_A, true)
	await _frames(10)
	var s2 := "%s %.2f" % ["pad" if car.steer_analog else "key", car.steer_input]
	_joy_axis(JOY_AXIS_LEFT_X, 0.6)
	await _frames(2)
	var s3 := "%s %.2f" % ["pad" if car.steer_analog else "key", car.steer_input]
	_key(KEY_A, false)
	await _frames(2)
	var s4 := "%s %.2f" % ["pad" if car.steer_analog else "key", car.steer_input]
	_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(30)
	log_line("  switching: stick 0.6 -> %s; stick released + A held -> %s; stick 0.6 with A still held -> %s (a held key wins); A released, stick 0.6 -> %s" % [s1, s2, s3, s4])
	# Triggers.
	var trig := PackedStringArray()
	for pair: Array in [[JOY_AXIS_TRIGGER_RIGHT, "throttle_input"], [JOY_AXIS_TRIGGER_LEFT, "brake_input"]]:
		var vals := PackedStringArray()
		for x in [0.03, 0.25, 0.5, 0.75, 1.0]:
			_joy_axis(pair[0], x)
			await _frames(1)
			vals.append("%.2f->%.2f" % [x, car.get(pair[1])])
		_joy_axis(pair[0], 0.0)
		await _frames(1)
		trig.append("%s %s" % ["RT throttle" if pair[0] == JOY_AXIS_TRIGGER_RIGHT else "LT brake", " ".join(vals)])
	log_line("  triggers (deadzone %.2f): %s" % [InputMap.action_get_deadzone(&"throttle"), "; ".join(trig)])
	# Buttons.
	var res := PackedStringArray()
	_joy_button(JOY_BUTTON_A, true)
	await _frames(2)
	res.append("A->handbrake %s" % car.handbrake_input)
	_joy_button(JOY_BUTTON_A, false)
	await _frames(1)
	for b: JoyButton in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		_joy_button(b, true)
		await _frames(10)
		res.append("D-pad %s->steer %.1f" % ["left" if b == JOY_BUTTON_DPAD_LEFT else "right", car.steer_input])
		_joy_button(b, false)
	log_line("  " + ", ".join(res))
	for b: JoyButton in [JOY_BUTTON_Y]: # Back opens the tuning panel now
		car.player_input = false
		await _place(INFIELD, Vector3.RIGHT)
		car.player_input = true
		await _tap(b)
		await _frames(10)
		log_line("  %s: car from the infield reset to (%.2f, %.2f), on road %d wheels" % [
			"Y" if b == JOY_BUTTON_Y else "Back", car.global_position.x, car.global_position.z, car.wheels_on_road])
	car.player_input = false
	# No pad / hotplug, by calling the handlers with an empty device list (the real
	# pad may or may not be there).
	var real := Input.get_connected_joypads()
	var r: PadRumble = game.rumble
	var dev0 := r.device
	game._update_pad_text([] as Array[int])
	var none_text: String = game._pad_text
	r._on_joy_connection_changed(r.device, false, [] as Array[int])
	var dev_unplugged := r.device
	r.set_enabled(true)
	var calls := r.start_calls
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _hold_speed(5.0, 0.0, 60)
	for i in 30:
		_inputs(1.0, 0.6, 0.0, true)
		await _frames(1)
	var calls_unplugged := r.start_calls - calls
	r.set_enabled(false)
	Input.joy_connection_changed.emit(0, true) # as on reconnect: both handlers run
	log_line("  hotplug: real pads %s; HUD with no pads '%s'; rumble device %d -> %d after unplug, %d vibration calls while sliding; reconnect signal -> HUD '%s', rumble device %d" % [
		real, none_text, dev0, dev_unplugged, calls_unplugged, game._pad_text, r.device])
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)


func _test_panel() -> void:
	log_line("\n[panel] tuning panel and presets, pad then keyboard")
	var panel: TuningPanel = game.panel
	var tun: CarTuning = game.tuning
	var start_preset := tun.current
	panel.enabled = true
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	car.player_input = true
	var res := PackedStringArray()
	# Presets while closed.
	var seq := PackedStringArray([tun.current])
	for i in tun.names.size():
		await _tap(JOY_BUTTON_RIGHT_SHOULDER)
		seq.append(tun.current)
	res.append("RB x%d: %s" % [tun.names.size(), " > ".join(seq)])
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	res.append("LB: %s (rear_grip now %.2f = preset %.2f)" % [tun.current, car.rear_grip, float(tun.presets[tun.current]["rear_grip"])])
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	res.append("RB: %s" % tun.current)
	log_line("  closed: " + "; ".join(res))
	res.clear()
	tun.select("balanced")
	# Open, navigate, adjust, hold to repeat, reset.
	await _tap(JOY_BUTTON_BACK)
	res.append("Back: open %s, arrows drive %s" % [panel.is_open, car.arrow_keys_drive])
	var sel0 := panel.selected
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_UP)
	res.append("down,down,up: row %d -> %d (%s)" % [sel0, panel.selected, CarTuning.PANEL[panel.selected][1]])
	var path: String = CarTuning.PANEL[panel.selected][1]
	var v0 := float(car.get_indexed(path))
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	var v1 := float(car.get_indexed(path))
	await _tap(JOY_BUTTON_DPAD_LEFT)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	var v2 := float(car.get_indexed(path))
	res.append("right: %.2f -> %.2f, left x2 -> %.2f (modified %s)" % [v0, v1, v2, tun.is_modified(path)])
	_joy_button(JOY_BUTTON_DPAD_RIGHT, true)
	await _frames(120)
	_joy_button(JOY_BUTTON_DPAD_RIGHT, false)
	await _frames(1)
	var v3 := float(car.get_indexed(path))
	res.append("held right 1 s: %.2f -> %.2f (%d steps)" % [v2, v3, roundi((v3 - v2) / float(CarTuning.PANEL[panel.selected][3]))])
	await _tap(JOY_BUTTON_X)
	res.append("X: reset to %.2f (modified %s)" % [float(car.get_indexed(path)), tun.is_modified(path)])
	log_line("  pad: " + "; ".join(res))
	res.clear()
	# Save custom with a change, reload it into a fresh CarTuning.
	panel.selected = CarTuning.PANEL.find(CarTuning.PANEL.filter(func(e: Array) -> bool: return e[1] == "rear_grip")[0])
	await _tap(JOY_BUTTON_DPAD_LEFT)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	var saved_rear := car.rear_grip
	var cfg := tun.save_path
	if FileAccess.file_exists(cfg):
		DirAccess.remove_absolute(cfg)
	await _tap(JOY_BUTTON_RIGHT_STICK)
	var reload := CarTuning.new(car, cfg)
	res.append("R-stick: saved %s (exists %s), preset now %s; reloaded: custom in cycle %s, custom rear_grip %.2f (saved %.2f)" % [
		cfg, FileAccess.file_exists(cfg), tun.current, reload.names.has(CarTuning.CUSTOM),
		float(reload.presets.get(CarTuning.CUSTOM, {}).get("rear_grip", -1.0)), saved_rear])
	tun.select("balanced")
	var rear_bal := car.rear_grip
	reload.select(CarTuning.CUSTOM)
	res.append("select custom from reload: rear_grip %.2f -> %.2f" % [rear_bal, car.rear_grip])
	tun.select("balanced")
	await _tap(JOY_BUTTON_BACK)
	res.append("Back: open %s, arrows drive %s" % [panel.is_open, car.arrow_keys_drive])
	log_line("  pad: " + "; ".join(res))
	res.clear()
	# Keyboard: F1, arrows navigate (and do not drive) while open, WASD drives, Backspace, F2/F3, F5.
	await _tap_key(KEY_F1)
	res.append("F1: open %s" % panel.is_open)
	var row0 := panel.selected
	await _tap_key(KEY_DOWN)
	res.append("Down: row %d -> %d" % [row0, panel.selected])
	path = CarTuning.PANEL[panel.selected][1]
	v0 = float(car.get_indexed(path))
	_key(KEY_RIGHT, true)
	await _frames(2)
	var steer_arrow := car.steer_input
	_key(KEY_RIGHT, false)
	await _frames(1)
	res.append("Right: %s %.3f -> %.3f, steer %.1f (arrows do not drive)" % [path, v0, float(car.get_indexed(path)), steer_arrow])
	_key(KEY_UP, true)
	await _frames(2)
	var thr_arrow := car.throttle_input
	_key(KEY_UP, false)
	await _frames(1)
	_key(KEY_W, true)
	await _frames(2)
	var thr_w := car.throttle_input
	_key(KEY_W, false)
	_key(KEY_D, true)
	await _frames(2)
	var steer_d := car.steer_input
	_key(KEY_D, false)
	await _frames(1)
	res.append("Up throttle %.1f (moved selection to row %d), W throttle %.1f, D steer %.1f" % [thr_arrow, panel.selected, thr_w, steer_d])
	await _tap_key(KEY_DOWN)
	await _tap_key(KEY_RIGHT)
	var mod := tun.is_modified(path)
	await _tap_key(KEY_BACKSPACE)
	res.append("Right then Backspace: modified %s -> %s" % [mod, tun.is_modified(path)])
	await _tap_key(KEY_F3)
	var p1 := tun.current
	await _tap_key(KEY_F3)
	var p2 := tun.current
	await _tap_key(KEY_F2)
	res.append("F3, F3, F2: %s, %s, %s" % [p1, p2, tun.current])
	tun.select("balanced")
	DirAccess.remove_absolute(cfg)
	await _tap_key(KEY_F5)
	res.append("F5: saved %s, preset %s" % [FileAccess.file_exists(cfg), tun.current])
	await _tap_key(KEY_F1)
	_key(KEY_UP, true)
	await _frames(2)
	res.append("F1: open %s; Up throttle %.1f again" % [panel.is_open, car.throttle_input])
	_key(KEY_UP, false)
	await _frames(1)
	log_line("  keys: " + "; ".join(res))
	tun.select(start_preset)
	panel.enabled = false
	car.player_input = false


func _test_rumble() -> void:
	log_line("\n[rumble] vibration calls (device %d); a connected pad vibrates briefly, the test cannot feel it" % game.rumble.device)
	var r: PadRumble = game.rumble
	r.set_enabled(true)
	if r.device < 0:
		r.device = 0
	if not Input.get_connected_joypads().has(r.device):
		log_line("  (no gamepad connected as device %d: the calls only set Input's vibration state, nothing vibrates)" % r.device)
	var dev := r.device
	var st := func() -> String:
		var v := Input.get_joy_vibration_strength(dev)
		return "weak %.2f strong %.2f (%s, calls start %d stop %d)" % [v.x, v.y, "running" if r.running else "stopped", r.start_calls, r.stop_calls]
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _frames(10)
	log_line("  at rest: " + st.call())
	await _hold_speed(5.0, 0.0, 120)
	log_line("  straight at 5 u/s: " + st.call())
	var peak := Vector2.ZERO
	for i in 40:
		_inputs(1.0, 0.6, 0.0, true)
		await _frames(1)
		peak = peak.max(Input.get_joy_vibration_strength(dev))
	log_line("  handbrake slide: peak weak %.2f strong %.2f; now %s" % [peak.x, peak.y, st.call()])
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(150)
	log_line("  braked to a stop: " + st.call())
	await _place(Vector3(60.0, 0.0, -30.0), Vector3.RIGHT)
	peak = Vector2.ZERO
	for i in 180:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		peak = peak.max(Input.get_joy_vibration_strength(dev))
	log_line("  off-road at %.1f u/s: peak weak %.2f strong %.2f" % [_speed(), peak.x, peak.y])
	await _place(Vector3(-8.0, 0.0, -40.0), Vector3.RIGHT)
	while car.global_position.x < 23.0:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
	peak = Vector2.ZERO
	for i in 60:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		peak = peak.max(Input.get_joy_vibration_strength(dev))
	log_line("  tree impact: peak weak %.2f strong %.2f" % [peak.x, peak.y])
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	await _hold_speed(5.0, 0.0, 60)
	for i in 30:
		_inputs(1.0, 0.6, 0.0, true)
		await _frames(1)
	var before: String = st.call()
	game.controls.enabled = true
	await _tap_key(KEY_V)
	log_line("  V while sliding: %s -> enabled %s, %s" % [before, r.enabled, st.call()])
	for i in 30:
		_inputs(1.0, 0.6, 0.0, true)
		await _frames(1)
	log_line("  still sliding with rumble off: " + st.call())
	await _tap_key(KEY_V)
	game.controls.enabled = false
	r.set_enabled(false)
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(120)
	log_line("  test end (rumble disabled again): " + st.call())


## The whole window with the HUD (telemetry) and the tuning panel open, mid-corner.
func _test_panel_shot() -> void:
	log_line("\n[panel shot] HUD + tuning panel mid-corner, in a handbrake drift")
	var s := 76.0
	var xf := track.pose_at(s)
	await _place(xf.origin, -xf.basis.z, 5.5)
	for i in 30:
		_inputs(0.8, 1.0, 0.0, true)
		await _frames(1)
	game.controls.hud.visible = true
	game.panel.set_open(true)
	game.panel.selected = 7
	car.rear_grip -= 0.1
	for i in 6:
		_inputs(0.8, 1.0, 0.0, true)
		await _frames(1)
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("16_window_tuning.png"))
	log_line("  screenshot 16_window_tuning.png (window %s); HUD status:\n%s" % [get_window().size, game.controls.status_text])
	game.tuning.select(game.tuning.current)
	game.panel.set_open(false)
	game.controls.hud.visible = false
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)



## Heading of the horizontal velocity (same convention as _yaw).
func _vh() -> float:
	var v := car.linear_velocity
	return atan2(v.x, -v.z)


## Run-up to `speed` on the test pad heading +x at z `z`, from x -9.
func _runup(speed: float, z: float = -30.0, frames: int = 300) -> void:
	await _place(Vector3(-9.0, 0.0, z), Vector3.RIGHT)
	await _hold_speed(speed, 0.0, frames)


## The handbrake drift: entry, hold, carving, steering, tap, exit and boost,
## plain handbrake, and a 180-degree turn drift vs grip.
func _test_drift() -> void:
	log_line("\n[drift hold] handbrake + full right + full throttle held 2.5 s (drift_mode %s, target %.0f deg, ceiling %.0f deg)" % [
		car.drift_mode, car.drift_angle_deg + car.drift_angle_steer_deg, car.drift_angle_max_deg])
	for entry in [5.0, 9.0]:
		await _runup(entry, -32.0, 360)
		var v0 := car.forward_speed
		var y0 := _yaw()
		var t_reach := -1.0
		var peak := 0.0
		var settled := 0.0
		var n := 0
		var v15 := 0.0
		var h_a := 0.0
		var spd_sum := 0.0
		var yaw_acc := 0.0
		var path_acc := 0.0
		var y_prev := _yaw()
		var p_prev := _vh()
		for i in 300:
			_inputs(1.0, 1.0, 0.0, true)
			await _frames(1)
			yaw_acc += wrapf(_yaw() - y_prev, -PI, PI)
			path_acc += wrapf(_vh() - p_prev, -PI, PI)
			y_prev = _yaw()
			p_prev = _vh()
			var b := car.drift_angle
			peak = maxf(peak, b)
			if t_reach < 0.0 and car.drift_state == Car.Drift.DRIFT and b >= 0.9 * car.drift_target:
				t_reach = (i + 1) / 120.0
			if i == 179:
				v15 = _speed()
				h_a = path_acc
			if i >= 180:
				settled += b
				spd_sum += _speed()
				n += 1
		var dh := absf(path_acc - h_a)
		var radius := (spd_sum / n) * (n / 120.0) / maxf(dh, 1e-3)
		var yaw := rad_to_deg(absf(yaw_acc))
		var path_turn := rad_to_deg(absf(path_acc))
		log_line("  entry %.2f u/s: angle %.0f%% of target after %s; settles at %.1f deg (peak %.1f); speed after 1.5 s %.2f (%.0f%%); arc radius (last 1 s) %.2f; in 2.5 s body yawed %.0f deg, path turned %.0f deg; still drifting %s" % [
			v0, 90.0, ("%.2f s" % t_reach) if t_reach >= 0.0 else "never", rad_to_deg(settled / n), rad_to_deg(peak),
			v15, 100.0 * v15 / v0, radius, yaw, path_turn, car.drift_state == Car.Drift.DRIFT])
		_m["drift_%s" % ("5" if entry < 6.0 else "top")] = "entry %.1f: 90%% angle %s, settles %.0f (peak %.0f) deg, speed 1.5 s %.0f%%, radius %.2f" % [
			v0, ("%.2f s" % t_reach) if t_reach >= 0.0 else "never", rad_to_deg(settled / n), rad_to_deg(peak), 100.0 * v15 / v0, radius]
		await _settle_car()

	log_line("[drift steer] entry 5.5 u/s, full right 0.5 s, then the stick held 1 s (handbrake and throttle held)")
	var mod := PackedStringArray()
	for st in [1.0, 0.5, 0.0, -0.3]:
		await _runup(5.5, -32.0, 300)
		for i in 60:
			_inputs(1.0, 1.0, 0.0, true)
			await _frames(1)
		var h_a := 0.0
		var spd_sum := 0.0
		var b_sum := 0.0
		for i in 120:
			_inputs(st, 1.0, 0.0, true)
			await _frames(1)
			if i == 47:
				h_a = _vh()
			if i >= 48:
				spd_sum += _speed()
				b_sum += car.drift_angle
		var dh := absf(wrapf(_vh() - h_a, -PI, PI))
		mod.append("stick %+.1f: radius %.2f, angle %.0f deg, speed %.2f" % [st, (spd_sum / 72.0) * 0.6 / maxf(dh, 1e-3), rad_to_deg(b_sum / 72.0), _speed()])
		await _settle_car()
	log_line("  " + "; ".join(mod))
	var radii := PackedStringArray()
	for x in mod:
		radii.append(x.get_slice(",", 0))
	_m["drift_steer_radius"] = ", ".join(radii)

	log_line("[drift tap] entry 5.5 u/s: handbrake 0.2 s with full right + throttle, released; stick 0.8 + throttle 1.5 s; then stick centred")
	await _runup(5.5, -32.0, 300)
	for i in 24:
		_inputs(1.0, 1.0, 0.0, true)
		await _frames(1)
	var alive := 0
	var b_min := INF
	for i in 180:
		_inputs(0.8, 1.0, 0.0, false)
		await _frames(1)
		if car.drift_state == Car.Drift.DRIFT:
			alive += 1
			if i > 30:
				b_min = minf(b_min, car.drift_angle)
	var t_end := -1.0
	var t5 := -1.0
	for i in 120:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
		if t_end < 0.0 and car.drift_state != Car.Drift.DRIFT:
			t_end = (i + 1) / 120.0
		if t5 < 0.0 and absf(car.slip_angle) < deg_to_rad(5.0):
			t5 = (i + 1) / 120.0
	log_line("  drifting %.2f of 1.5 s after release (angle never below %.1f deg after 0.25 s); stick centred: drift ends after %s, slip < 5 deg after %s" % [
		alive / 120.0, rad_to_deg(b_min) if b_min < INF else 0.0, ("%.2f s" % t_end) if t_end >= 0.0 else "NEVER", ("%.2f s" % t5) if t5 >= 0.0 else "NEVER"])
	_m["drift_tap"] = "sustained %.2f/1.50 s; centring ends it in %s" % [alive / 120.0, ("%.2f s" % t_end) if t_end >= 0.0 else "NEVER"]
	await _settle_car()

	log_line("[drift exit] entry 5.5 u/s, drift (handbrake + full right + throttle), then let go (stick centred, handbrake up, throttle held 1 s)")
	var boost_keep := car.drift_boost_accel
	for len_s in [0.5, 2.0]:
		var res := []
		for boost_on in [true, false]:
			car.drift_boost_accel = boost_keep if boost_on else 0.0
			await _runup(5.5, -32.0, 300)
			for i in int(len_s * 120.0):
				_inputs(1.0, 1.0, 0.0, true)
				await _frames(1)
			var v_exit := _speed()
			var t_ok := -1.0
			var over := 0.0
			var power := 0.0
			for i in 120:
				_inputs(0.0, 1.0, 0.0, false)
				await _frames(1)
				if t_ok < 0.0 and absf(car.slip_angle) < deg_to_rad(5.0):
					t_ok = (i + 1) / 120.0
				over = maxf(over, -car.drift_angle)
				if i == 0:
					power = car.boost_power if car.boost_left > 0.0 else 0.0
			res.append([v_exit, t_ok, over, _speed(), power])
			await _settle_car()
		car.drift_boost_accel = boost_keep
		var a: Array = res[0]
		var b: Array = res[1]
		log_line("  after %.1f s: slip < 5 deg after %s, overshoot the other way %.1f deg, speed %.2f -> %.2f after 1 s (%.0f%%); boost charge %.0f%% gave +%.2f u/s (vs boost off: %.2f)" % [
			len_s, ("%.2f s" % a[1]) if a[1] >= 0.0 else "NEVER", rad_to_deg(a[2]), a[0], a[3], 100.0 * a[3] / a[0], a[4] * 100.0, a[3] - b[3], b[3]])
		_m["drift_exit_%.1fs" % len_s] = "slip<5 after %s, overshoot %.1f deg, speed kept %.0f%%, boost +%.2f u/s" % [
			("%.2f s" % a[1]) if a[1] >= 0.0 else "NEVER", rad_to_deg(a[2]), 100.0 * a[3] / a[0], a[3] - b[3]]

	log_line("[handbrake plain] 6 u/s, handbrake only (no steer, no throttle) 1 s; 1.5 u/s with full right 1 s (throttle 0 and 0.5); standstill 1 s")
	await _runup(6.0, -32.0, 300)
	var y0 := _yaw()
	var v0 := _speed()
	for i in 120:
		_inputs(0.0, 0.0, 0.0, true)
		await _frames(1)
	var straight := "yaw %.1f deg, %.2f -> %.2f u/s (%.1f u/s^2)" % [rad_to_deg(absf(wrapf(_yaw() - y0, -PI, PI))), v0, _speed(), (v0 - _speed())]
	var pivot := ""
	for thr in [0.0, 0.5]:
		await _runup(1.5, -32.0, 240)
		y0 = _yaw()
		var yaw_acc := 0.0
		var slip_max := 0.0
		for i in 120:
			var yp := _yaw()
			_inputs(1.0, thr, 0.0, true)
			await _frames(1)
			yaw_acc += wrapf(_yaw() - yp, -PI, PI)
			slip_max = maxf(slip_max, absf(car.slip_angle))
		pivot += "%sthrottle %.1f: yaw %.0f deg in 1 s (max slip %.0f deg), speed %.2f" % ["" if thr == 0.0 else "; ", thr, rad_to_deg(absf(yaw_acc)), rad_to_deg(slip_max), _speed()]
		await _settle_car()
	await _place(Vector3(-9.0, 0.0, -32.0), Vector3.RIGHT)
	await _frames(30)
	var p0 := car.global_position
	for i in 120:
		_inputs(0.0, 0.0, 0.0, true)
		await _frames(1)
	log_line("  straight: %s; low-speed pivot: %s; standstill moved %.4f" % [straight, pivot, p0.distance_to(car.global_position)])
	_m["hb_straight"] = straight
	_m["hb_pivot"] = pivot

	log_line("[180 turn] from top speed at x 8: time until the path has turned 180 deg, exit speed then, and 0.5 s later")
	var best_grip: Array = []
	var grip_rows := PackedStringArray()
	for vt in [2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 6.0, 9.0]:
		var r: Array = await _u_turn(false, vt)
		grip_rows.append("%.1f:%.2fs/%.2f" % [vt, r[0], r[1]])
		if r[0] > 0.0 and (best_grip.is_empty() or r[0] < best_grip[0]):
			best_grip = r + [vt]
	var best_drift: Array = []
	var drift_rows := PackedStringArray()
	for vt in [4.0, 5.0, 6.0, 9.0]:
		var r: Array = await _u_turn(true, vt)
		drift_rows.append("%.1f:%.2fs/%.2f" % [vt, r[0], r[1]])
		if r[0] > 0.0 and (best_drift.is_empty() or r[0] < best_drift[0]):
			best_drift = r + [vt]
	log_line("  grip line (brake to v, then full lock holding v) v:time/exit speed: " + " ".join(grip_rows))
	log_line("  drift (brake to v, then handbrake + full right + throttle) v:time/exit speed: " + " ".join(drift_rows))
	for pair: Array in [["grip", best_grip], ["drift", best_drift]]:
		var r: Array = pair[1]
		if r.is_empty():
			log_line("  best %s: never completed" % pair[0])
			continue
		log_line("  best %s: entry %.1f -> %.2f s, exit speed %.2f (0.5 s later %.2f), width %.2f, overshoot past x 8 %.2f" % [pair[0], r[5], r[0], r[1], r[2], r[3], r[4]])
		_m["uturn_%s" % pair[0]] = "%.2f s, exit %.2f (0.5 s later %.2f), width %.2f" % [r[0], r[1], r[2], r[3]]


## A 180: run-up at top speed, from x 8 brake to `vt` (if lower), then turn right
## (drift: handbrake + full right + throttle; grip: full lock holding vt) until the
## path has turned 180 deg. Returns [time, exit speed, speed 0.5 s later, width (z span), max x past 8].
func _u_turn(drift: bool, vt: float) -> Array:
	await _place(Vector3(-12.0, 0.0, -38.0), Vector3.RIGHT)
	while car.global_position.x < 8.0:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
	var h0 := _vh()
	var z0 := car.global_position.z
	var zmax := z0
	var xmax := car.global_position.x
	var t := 0
	var braking := vt < car.forward_speed - 0.1
	while t < 600:
		if braking and car.forward_speed <= vt:
			braking = false
		if braking:
			_inputs(0.0, 0.0, 1.0, false)
		elif drift:
			_inputs(1.0, 1.0, 0.0, true)
		else:
			_inputs(1.0, clampf((vt - car.forward_speed) * 1.5, 0.0, 1.0), 0.0, false)
		await _frames(1)
		t += 1
		zmax = maxf(zmax, car.global_position.z)
		xmax = maxf(xmax, car.global_position.x)
		if absf(wrapf(_vh() - h0, -PI, PI)) >= PI * 0.98 and t > 30:
			break
	var ok := t < 600
	var v_exit := _speed()
	for i in 60:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
	var r := [t / 120.0 if ok else -1.0, v_exit, _speed(), zmax - z0, xmax - 8.0]
	await _settle_car()
	return r


## Brake to a stop with everything released (between drift runs).
func _settle_car() -> void:
	for i in 90:
		_inputs(0.0, 0.0, 1.0, false)
		await _frames(1)
	_inputs(0.0, 0.0, 0.0, false)



## Two autopilot laps taking the radius-2 snake hairpins with the handbrake drift.
func _test_drift_lap() -> void:
	log_line("\n[drift laps] autopilot, drifting corners with curvature >= 0.19 (R4, R5 hairpin), two laps")
	_inputs(0.0, 0.0, 0.0, false)
	car.teleport(world.grid_pose())
	game.laps.reset()
	camera.snap_to_target()
	await _frames(60)
	var ap := Autopilot.new()
	ap.car = car
	ap.track = track
	ap.drift_corners = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--driftap="):
			var p := arg.trim_prefix("--driftap=").split(",")
			ap.drift_entry_ahead = p[0].to_float()
			ap.drift_steer_base = p[1].to_float()
			ap.drift_steer_gain = p[2].to_float()
	add_child(ap)
	var laps: LapTimer = game.laps
	var completed: Array[float] = []
	laps.lap_completed.connect(func(t: float) -> void: completed.append(t))
	var off := 0
	var max_lat := 0.0
	var drift_frames := 0
	var max_angle := 0.0
	var frames := 0
	while completed.size() < 2 and frames < 120 * 90:
		await _frames(1)
		frames += 1
		if car.wheels_on_road < 4:
			off += 1
		max_lat = maxf(max_lat, absf(track.lateral_offset(car.global_position, laps.progress)))
		if car.drift_state == Car.Drift.DRIFT:
			drift_frames += 1
			max_angle = maxf(max_angle, car.drift_angle)
	log_line("  laps: %s; %d drifts started, %.1f s drifting, max drift angle %.0f deg; %d frames with < 4 wheels on road; max |lateral| %.2f" % [
		", ".join(completed.map(func(t: float) -> String: return LapTimer.fmt(t))) if completed.size() > 0 else "NONE",
		ap.drifts_started, drift_frames / 120.0, rad_to_deg(max_angle), off, max_lat])
	_m["drift_autopilot_laps"] = "%s (%d drifts, %d frames off road, max lateral %.2f)" % [
		", ".join(completed.map(func(t: float) -> String: return LapTimer.fmt(t))) if completed.size() > 0 else "NONE", ap.drifts_started, off, max_lat]
	ap.enabled = false
	ap.queue_free()
	_inputs(0.0, 0.0, 0.0, false)



## Starts an autopilot that holds `target` speed along the circuit (its own
## steering, no braking for corners). Stop it with _stop_line().
func _start_line(target: float) -> Autopilot:
	var ap := Autopilot.new()
	ap.car = car
	ap.track = track
	ap.max_speed = target
	ap.lateral_accel = 1000.0 # never slow down for corners
	add_child(ap)
	return ap


func _stop_line(ap: Autopilot) -> void:
	ap.enabled = false
	ap.queue_free()
	_inputs(0.0, 0.0, 0.0, false)


## The table-top jump at top speed, about 50% and 25%.
func _test_jump() -> void:
	log_line("\n[jump] table-top on the main straight (kicker s 21..24 to 0.3 high, table to 26, landing slope to 33.5)")
	for frac: float in [1.0, 0.5, 0.25]:
		var v := car.top_speed * 0.91 * frac
		await _place_on_track(16.0, 0.0, v)
		var take_off := -1
		var land := -1
		var p0 := Vector3.ZERO
		var p1 := Vector3.ZERO
		var max_h := 0.0
		var air_tilt := 0.0
		var land_tilt := 0.0
		var bounce := 0
		var v_take := 0.0
		var was_air := false
		var land_s := -1.0
		var comp := 0.0
		var prog := track.progress(car.global_position)
		var ap := _start_line(v + (0.8 if frac >= 1.0 else 0.0))
		for i in 360:
			await _frames(1)
			prog = track.progress(car.global_position, prog)
			var air := car.wheels_grounded == 0
			if air and take_off < 0:
				take_off = i
				p0 = car.global_position
				v_take = _speed()
			if take_off >= 0 and land < 0:
				max_h = maxf(max_h, car.global_position.y - (Track.ROAD_Y + track.height_at(prog)))
				air_tilt = maxf(air_tilt, rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)))
				if not air and i - take_off > 2:
					land = i
					p1 = car.global_position
					land_s = prog
			if land >= 0 and i - land < 60:
				comp = maxf(comp, car.suspension_compression())
				land_tilt = maxf(land_tilt, rad_to_deg(car.global_basis.y.angle_to(track.pose_at(prog).basis.y)))
				if air and not was_air:
					bounce += 1
			was_air = air
			if land >= 0 and i - land > 120 or take_off < 0 and prog > 33.0 and prog < 40.0:
				break
			if take_off >= 0 and land < 0 and i - take_off == 18 and frac >= 1.0:
				await _shot("22_jump_mid_air.png")
		_stop_line(ap)
		if take_off < 0:
			log_line("  %3.0f%% (%.1f u/s): rolled over the table without leaving the ground; upright %s, at s %.1f, speed %.2f" % [frac * 100.0, v, car.is_upright(), prog, _speed()])
			_m["jump_%d" % roundi(frac * 100.0)] = "no air (rolled over), upright %s" % car.is_upright()
			continue
		var air_t := (land - take_off) / 120.0 if land >= 0 else -1.0
		var dist := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		log_line("  %3.0f%% (%.1f u/s, %.2f at take-off): air %.2f s over %.2f u, highest %.2f above the road below, tilt in the air max %.1f deg; lands at s %.1f (slope 26..33.5), suspension max %d%% after landing, tilt max %.1f deg vs the road, %d bounce(s); upright %s, speed %.2f" % [
			frac * 100.0, v, v_take, air_t, dist, max_h, air_tilt, land_s, roundi(comp * 100.0), land_tilt, bounce, car.is_upright(), _speed()])
		_m["jump_%d" % roundi(frac * 100.0)] = "air %.2f s, %.2f u, lands s %.1f, suspension %d%%, peak %.2f, landing tilt %.1f deg, bounces %d, upright %s" % [
			air_t, dist, land_s, roundi(comp * 100.0), max_h, land_tilt, bounce, car.is_upright()]
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)


## Over the bridge at top speed (ramps, crest, sweeper), and under it.
func _test_bridge() -> void:
	log_line("\n[bridge over] from the hairpin exit at 7.5 u/s, full throttle over the ramps and deck to the main straight")
	await _place_on_track(track.length - 16.0, 0.0, 7.5)
	var air := 0
	var comp := 0.0
	var max_vy := 0.0
	var max_tilt := 0.0
	var max_y := 0.0
	var top_speed := 0.0
	var prog := track.progress(car.global_position)
	var ap := _start_line(8.5)
	var shot := false
	for i in 600:
		await _frames(1)
		prog = track.progress(car.global_position, prog)
		if car.wheels_grounded == 0:
			air += 1
		comp = maxf(comp, car.suspension_compression())
		max_vy = maxf(max_vy, absf(car.linear_velocity.y))
		max_tilt = maxf(max_tilt, rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)))
		max_y = maxf(max_y, car.global_position.y)
		top_speed = maxf(top_speed, _speed())
		if not shot and prog > 0.5 and prog < 3.0:
			shot = true
			await _shot("23_on_bridge.png")
		if prog > 17.0 and prog < 40.0:
			break
	_stop_line(ap)
	log_line("  airborne %d frames, max suspension compression %.0f%% (100%% = bump stop), max |vy| %.2f, max tilt %.1f deg, highest y %.2f (deck road %.2f), max speed %.2f; ends at s %.1f, on road %d wheels, upright %s" % [
		air, comp * 100.0, max_vy, max_tilt, max_y, track.deck_y, top_speed, prog, car.wheels_on_road, car.is_upright()])
	_m["bridge_over"] = "airborne %d frames, compression max %.0f%%, tilt %.1f deg, speed %.2f" % [air, comp * 100.0, max_tilt, top_speed]

	log_line("[bridge under] down the diagonal at 7.5 u/s, under the deck")
	await _place_on_track(86.0, 0.0, 7.5)
	var min_gap := INF
	var cut := false
	var hits := 0
	var v_prev := _speed()
	prog = track.progress(car.global_position)
	ap = _start_line(8.5)
	shot = false
	for i in 400:
		await _frames(1)
		prog = track.progress(car.global_position, prog)
		var c := track.crossing_point
		if Vector2(car.global_position.x - c.x, car.global_position.z - c.z).length() < 2.0:
			min_gap = minf(min_gap, track.deck_y - Track.DECK_THICK - (car.global_position.y + 0.45))
			cut = cut or HaloOccluder.radius_now > 0.0
			if not shot:
				shot = true
				await _shot("24_under_bridge_halo.png")
		if _speed() < v_prev - 0.5:
			hits += 1
		v_prev = _speed()
		if prog > 106.0 and prog < 120.0:
			break
	_stop_line(ap)
	await _frames(2)
	log_line("  passed under: clearance above the car roof %.2f, halo open in the iso view while under %s, sudden speed losses %d; ends at s %.1f, speed %.2f" % [
		min_gap, cut, hits, prog, _speed()])
	_m["bridge_under"] = "clearance %.2f, halo %s, speed losses %d" % [min_gap, cut, hits]
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)


## R on the bridge and under it: the reset puts the car back at the right height.
func _test_reset_bridge() -> void:
	log_line("\n[reset bridge] drive onto the deck / under it, knock the car off the road, press R")
	for c: Array in [["on the deck", track.length - 3.0, 1.0], ["under the deck", 96.0, 99.9]]:
		await _place_on_track(c[1], 0.0, 3.0)
		var prog := track.progress(car.global_position)
		var ap := _start_line(3.0)
		for i in 600:
			await _frames(1)
			prog = track.progress(car.global_position, prog)
			if prog >= c[2] and prog < c[2] + 3.0:
				break
		_stop_line(ap)
		_inputs(0.0, 0.0, 1.0, false)
		await _frames(40)
		var y_before := car.global_position.y
		car.teleport(Transform3D(Basis.IDENTITY, INFIELD + Vector3.UP * Track.ROAD_Y))
		await _frames(5)
		game.reset_car()
		await _frames(60)
		var s := track.progress(car.global_position)
		log_line("  %s (car at y %.2f): reset to (%.2f, %.2f, %.2f), road height there %.2f, on road %d wheels, upright %s" % [
			c[0], y_before, car.global_position.x, car.global_position.y, car.global_position.z, track.point_at(s).y, car.wheels_on_road, car.is_upright()])
		_m["reset_" + String(c[0]).replace(" ", "_")] = "y %.2f (road %.2f), on road %d" % [car.global_position.y, track.point_at(s).y, car.wheels_on_road]



## Drives the circuit with the autopilot from s0 until progress reaches s1, then
## takes an ASCII screenshot (the chase or iso view, whichever is current).
func _drive_and_shot(s0: float, s1: float, speed: float, file: String, when_air: bool = false) -> void:
	await _place_on_track(s0, 0.0, speed)
	game.chase.snap_to_target()
	var prog := track.progress(car.global_position)
	var ap := _start_line(speed)
	for i in 900:
		await _frames(1)
		prog = track.progress(car.global_position, prog)
		if when_air and car.wheels_grounded == 0 and car.air_time > 0.1 or not when_air and absf(wrapf(prog - s1, -track.length * 0.5, track.length * 0.5)) < 0.15:
			break
	await _shot(file)
	_stop_line(ap)


func _stick(x: float, y: float) -> void:
	_joy_axis(JOY_AXIS_RIGHT_X, x)
	_joy_axis(JOY_AXIS_RIGHT_Y, y)


## The chase camera: switching, the views, right-stick orbit, line of sight,
## distance fade, the five lighting modes in perspective, fps.
func _test_chase() -> void:
	log_line("\n[chase] rear chase camera (toggle Q / pad B)")
	var chase: ChaseCamera = game.chase
	game.controls.enabled = true
	car.player_input = false
	await _place_on_track(20.0)
	await _frames(480) # let the iso camera settle on the parked car
	var iso_xf := camera.global_transform
	var iso_size := camera.size
	_key(KEY_Q, true)
	_key(KEY_Q, false)
	await _frames(2)
	var on: bool = game.chase_view and renderer.scene_viewport.get_camera_3d() == chase
	var snap := renderer.snap_step(chase)
	await _tap(JOY_BUTTON_B)
	await _frames(2)
	var back: bool = not game.chase_view and renderer.scene_viewport.get_camera_3d() == camera
	log_line("  Q: chase view %s (renderer camera is the chase camera; perspective, fov %.0f, near %.2f, far %.0f; grid snap step %s = inactive); pad B: back to iso %s, iso transform identical %s, zoom identical %s" % [
		on, chase.fov, chase.near, chase.far, snap, back, camera.global_transform.is_equal_approx(iso_xf), is_equal_approx(camera.size, iso_size)])
	_m["chase_toggle"] = "Q on %s, B off %s, iso framing restored %s" % [on, back, camera.global_transform.is_equal_approx(iso_xf) and is_equal_approx(camera.size, iso_size)]
	game.set_chase_view(true)

	# The views.
	await _drive_and_shot(14.0, 20.5, 7.6, "30_chase_straight.png")
	await _drive_and_shot(72.0, 78.5, 7.0, "31_chase_sweeper.png")
	await _drive_and_shot(17.0, 0.0, 7.7, "33_chase_jump.png", true)
	await _drive_and_shot(track.length - 18.0, 0.5, 7.0, "34_chase_on_bridge.png")
	await _drive_and_shot(88.0, 99.6, 7.0, "35_chase_under_bridge.png")
	log_line("  under the bridge: camera y %.2f (deck underside %.2f), line of sight pulled in %s, distance %.2f" % [
		chase.global_position.y, track.deck_y - Track.DECK_THICK, chase.blocked, chase.global_position.distance_to(car.global_position)])
	# Mid-drift on the pad.
	await _place(Vector3(-8.0, 0.0, -30.0), Vector3.RIGHT)
	chase.snap_to_target()
	await _hold_speed(6.0, 0.0, 240)
	for i in 70:
		_inputs(1.0, 1.0, 0.0, true)
		await _frames(1)
	log_line("  mid-drift: body angle %.0f deg, camera heading vs car heading %.0f deg" % [rad_to_deg(car.drift_angle),
		rad_to_deg(absf(wrapf(ChaseCamera._heading_of(-chase.global_basis.z) - ChaseCamera._heading_of(-car.global_basis.z), -PI, PI)))])
	await _shot("32_chase_drift.png")
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(90)

	# Right stick: held each way, then released (on the east straight).
	await _place_on_track(47.0)
	chase.snap_to_target()
	await _frames(20)
	var looks := PackedStringArray()
	for d: Array in [["left", -1.0, 0.0], ["right", 1.0, 0.0], ["up", 0.0, -1.0], ["down", 0.0, 1.0]]:
		_stick(d[1], d[2])
		await _frames(72)
		looks.append("%s: yaw %+.0f pitch %+.0f deg" % [d[0], rad_to_deg(chase.orbit_yaw), rad_to_deg(chase.orbit_pitch)])
		await _shot("36_chase_look_%s.png" % d[0])
		_stick(0.0, 0.0)
		await _frames(240)
	_stick(-1.0, 0.0)
	var turned := 0.0
	var oy := chase.orbit_yaw
	for i in 240:
		await _frames(1)
		turned += wrapf(chase.orbit_yaw - oy, -PI, PI)
		oy = chase.orbit_yaw
	var full := rad_to_deg(turned)
	_stick(0.0, 0.0)
	await _frames(60)
	var after_05 := rad_to_deg(chase.orbit_yaw)
	await _frames(180)
	log_line("  right stick 0.6 s: %s; held 2 s: orbited %+.0f deg in total (all the way round); released: %+.0f deg after 0.5 s, %+.1f deg after 2 s" % [
		", ".join(looks), full, after_05, rad_to_deg(chase.orbit_yaw)])
	_m["chase_stick"] = "%s; recentres to %+.1f deg 2 s after release" % [", ".join(looks), rad_to_deg(chase.orbit_yaw)]

	# Reset, reverse and spin: no snapping or flipping.
	await _place_on_track(60.0, 0.0, 5.0)
	chase.snap_to_target()
	await _frames(30)
	game.reset_car()
	await _frames(1)
	var d_reset := chase.global_position.distance_to(car.global_position)
	var max_step := 0.0
	await _place_on_track(47.0)
	chase.snap_to_target()
	var prev := ChaseCamera._heading_of(-chase.global_basis.z)
	for i in 240:
		_inputs(0.0, 0.0, 1.0, false) # brake at a standstill = reverse
		await _frames(1)
		var h := ChaseCamera._heading_of(-chase.global_basis.z)
		max_step = maxf(max_step, absf(wrapf(h - prev, -PI, PI)))
		prev = h
	var rev_speed := car.forward_speed
	var max_spin := 0.0
	await _place_on_track(47.0, 0.0, 3.0)
	chase.snap_to_target()
	prev = ChaseCamera._heading_of(-chase.global_basis.z)
	for i in 120:
		car.angular_velocity = Vector3.UP * 8.0
		_inputs(0.0, 0.0, 0.0, false)
		await _frames(1)
		var h := ChaseCamera._heading_of(-chase.global_basis.z)
		max_spin = maxf(max_spin, absf(wrapf(h - prev, -PI, PI)))
		prev = h
	log_line("  after R the camera is %.2f from the car (snapped behind it); reversing at %.2f u/s: largest camera turn per frame %.2f deg; car spun at 8 rad/s: largest camera turn per frame %.2f deg" % [
		d_reset, rev_speed, rad_to_deg(max_step), rad_to_deg(max_spin)])
	_m["chase_stability"] = "reset distance %.2f, reverse max %.2f deg/frame, spin max %.2f deg/frame" % [d_reset, rad_to_deg(max_step), rad_to_deg(max_spin)]
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)

	# Distance fade on / off, looking down the main straight.
	await _place_on_track(13.0)
	chase.snap_to_target()
	await _frames(10)
	await _shot("37_chase_fade_on.png")
	await _shot("37_chase_fade_on_raw.png", true)
	game.chase_fade = false
	game.set_chase_view(true)
	await _shot("37_chase_fade_off.png")
	await _shot("37_chase_fade_off_raw.png", true)
	game.chase_fade = true
	game.set_chase_view(true)

	# Every lighting mode in perspective.
	var m0: int = game.lighting.mode
	for m in Lighting.MODES.size():
		game.lighting.set_mode_frozen(m)
		await _shot("38_chase_lighting_%d_%s.png" % [m + 1, String(Lighting.MODES[m].name).replace(" ", "-")])
	game.lighting.sweep_running = true
	game.lighting.set_mode(m0)

	# Frame rate (real time, vsync off), chase vs iso, on the circuit.
	var fps := []
	for mode in [true, false]:
		game.set_chase_view(mode)
		await _place_on_track(75.0, 0.0, 6.0)
		var ap := _start_line(7.0)
		await _frames(30)
		var t0 := Time.get_ticks_usec()
		for i in 240:
			await RenderingServer.frame_post_draw
		fps.append(240.0 / ((Time.get_ticks_usec() - t0) / 1e6))
		_stop_line(ap)
	log_line("  rendering at %s output: %.0f fps in chase view, %.0f fps in iso view (vsync off; window %s)" % [SHOT_SIZE, fps[0], fps[1], get_window().size])
	_m["chase_fps"] = "%.0f chase / %.0f iso" % [fps[0], fps[1]]
	game.set_chase_view(false)
	game.controls.enabled = false
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(30)



## Steering trace metrics: [mean |rate| (1/s), reversals per second].
func _steer_metrics(trace: PackedFloat32Array) -> Array:
	var rate := 0.0
	var rev := 0
	var last_sign := 0.0
	for i in range(1, trace.size()):
		var d := (trace[i] - trace[i - 1]) * 120.0
		rate += absf(d)
		if absf(d) > 0.05:
			if last_sign != 0.0 and signf(d) != last_sign:
				rev += 1
			last_sign = signf(d)
	var secs := maxf(trace.size() / 120.0, 1e-3)
	return [rate / maxf(trace.size() - 1, 1), rev / secs]


## The attract-mode demo driver over five laps, against the centre-line autopilot.
func _test_demo_laps() -> void:
	var laps_wanted := 5
	log_line("\n[demo laps] the demo-reel driver (DemoDriver), %d laps from the grid" % laps_wanted)
	_inputs(0.0, 0.0, 0.0, false)
	car.teleport(world.grid_pose())
	game.laps.reset()
	camera.snap_to_target()
	await _frames(30)
	var d := DemoDriver.new()
	d.car = car
	d.track = track
	d.rng_seed = 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demotune="):
			for kv in arg.trim_prefix("--demotune=").split(",", false):
				var p := kv.split("=")
				d.set(p[0], int(p[1]) if p[0] == "rng_seed" else float(p[1]))
	add_child(d)
	d.reset_requested.connect(func() -> void:
		log_line("    quiet reset at s %.1f" % d.progress)
		game.reset_car()
		d.restart())
	var laps: LapTimer = game.laps
	var completed: Array[float] = []
	laps.lap_completed.connect(func(t: float) -> void: completed.append(t))
	var trace := PackedFloat32Array()
	var off := 0
	var air := 0
	var max_slip := 0.0
	var was_off := false
	var hairpin_drift := {}
	var jump_air := {}
	var frames := 0
	while completed.size() < laps_wanted and frames < 120 * 60 * laps_wanted:
		await _frames(1)
		frames += 1
		if not laps.started:
			continue
		trace.append(car.steer_input)
		var is_off := car.wheels_grounded > car.wheels_on_road
		if is_off:
			off += 1
			if not was_off:
				log_line("    off the road at s %.1f, lateral %.2f, speed %.2f, steer %.2f" % [d.progress,
					track.lateral_offset(car.global_position, d.progress), _speed(), car.steer_input])
		was_off = is_off
		if car.wheels_grounded == 0:
			air += 1
			if d.progress > 22.0 and d.progress < 33.0:
				jump_air[laps.lap] = int(jump_air.get(laps.lap, 0)) + 1
		max_slip = maxf(max_slip, absf(car.slip_angle))
		if car.drift_state == Car.Drift.DRIFT and d.progress > 112.0 and d.progress < 132.0:
			hairpin_drift[laps.lap] = int(hairpin_drift.get(laps.lap, 0)) + 1
	var times := completed.map(func(t: float) -> String: return "%.2f" % t)
	var mean := 0.0
	for t in completed:
		mean += t
	mean /= maxf(completed.size(), 1)
	var spread := 0.0
	for t in completed:
		spread = maxf(spread, absf(t - mean))
	var dm := _steer_metrics(trace)
	var hp := PackedStringArray()
	var jp := PackedStringArray()
	for l in range(1, laps_wanted + 1):
		hp.append("%.2f" % (int(hairpin_drift.get(l, 0)) / 120.0))
		jp.append("%.2f" % (int(jump_air.get(l, 0)) / 120.0))
	log_line("  laps %s (mean %.2f, +-%.2f); %d frames with a wheel off the road, %d airborne; %d quiet resets; %d drifts; peak slip %.1f deg" % [
		", ".join(times), mean, spread, off, air, d.resets, d.drifts, rad_to_deg(max_slip)])
	log_line("  per lap: hairpin drift seconds %s; jump air seconds %s" % [", ".join(hp), ", ".join(jp)])
	log_line("  steering: mean |rate| %.2f /s, %.2f reversals/s" % [dm[0], dm[1]])
	_m["demo_laps"] = "%s (mean %.2f +-%.2f), off %d, resets %d, drifts %d, peak slip %.0f" % [", ".join(times), mean, spread, off, d.resets, d.drifts, rad_to_deg(max_slip)]
	_m["demo_per_lap"] = "hairpin drift s %s; jump air s %s" % [", ".join(hp), ", ".join(jp)]
	d.queue_free()
	# The old centre-line autopilot over two laps, for the steering comparison.
	_inputs(0.0, 0.0, 0.0, false)
	car.teleport(world.grid_pose())
	laps.reset()
	await _frames(30)
	var ap := Autopilot.new()
	ap.car = car
	ap.track = track
	add_child(ap)
	var trace2 := PackedFloat32Array()
	var done := 0
	var cb := func(_t: float) -> void: done += 1
	laps.lap_completed.connect(func(_t: float) -> void: trace2.append(INF))
	frames = 0
	while frames < 120 * 50:
		await _frames(1)
		frames += 1
		if laps.started:
			trace2.append(car.steer_input)
		if trace2.count(INF) >= 2:
			break
	var clean := PackedFloat32Array()
	for v in trace2:
		if v != INF:
			clean.append(v)
	var am := _steer_metrics(clean)
	log_line("  centre-line autopilot: mean |rate| %.2f /s, %.2f reversals/s" % [am[0], am[1]])
	_m["demo_steering"] = "demo |rate| %.2f/s, %.2f reversals/s vs autopilot %.2f/s, %.2f reversals/s" % [dm[0], dm[1], am[0], am[1]]
	ap.enabled = false
	ap.queue_free()
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(30)



## The see-through halo in the bridge, iso view: the car parked at points along
## the lower road through the crossing, driving through, and on top of the deck.
func _test_halo() -> void:
	log_line("\n[halo] iso view, see-through halo in the bridge (radius %.2f, rim %.2f, dither %.2f)" % [
		HaloOccluder.RADIUS, HaloOccluder.SOFTNESS, HaloOccluder.DITHER])
	game.set_chase_view(false)
	var keep_snap := camera.snap_to_grid
	var sc := track.progress(track.crossing_point)
	for d: float in [-3.0, -1.5, 0.0, 1.0, 2.0, 3.0, 4.5]:
		await _place_on_track(sc + d)
		await _frames(30)
		camera.snap_to_target()
		await _frames(2)
		await _shot("40_halo_parked_%+.1f.png" % d)
		if d == 1.0:
			await _shot("40_halo_parked_%+.1f_raw.png" % d, true)
			HaloOccluder.set_target(Vector3.ZERO, 0.0)
			game.set_process(false)
			await _shot("40_halo_parked_%+.1f_off.png" % d)
			game.set_process(true)
	log_line("  parked at the crossing %+.1f .. %+.1f: shots 40_halo_parked_*" % [-3.0, 4.5])
	# Driving through at speed: a frame every 0.1 s.
	await _place_on_track(sc - 6.0, 0.0, 5.5)
	var ap := _start_line(5.5)
	var n := 0
	var prog := track.progress(car.global_position)
	for i in 300:
		await _frames(1)
		prog = track.progress(car.global_position, prog)
		if i % 12 == 0 and prog > sc - 3.0 and prog < sc + 6.0:
			await _shot("41_halo_drive_%02d_s%+.1f.png" % [n, prog - sc])
			n += 1
		if prog > sc + 6.0 and prog < sc + 20.0:
			break
	_stop_line(ap)
	log_line("  driving through at 5.5 u/s: %d shots 41_halo_drive_*" % n)
	# On top of the deck: nothing may be cut.
	await _place_on_track(0.5)
	await _frames(30)
	camera.snap_to_target()
	await _frames(2)
	await _shot("42_halo_on_deck.png")
	await _shot("42_halo_on_deck_raw.png", true)
	log_line("  on top of the deck: shot 42_halo_on_deck")
	camera.snap_to_grid = keep_snap
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(30)



## Every lighting mode from the same poses: iso (start line, trees, the bridge
## from both strands, the hairpin), chase, and a cinematic shot.
func _test_lighting() -> void:
	log_line("\n[lighting] the five lighting modes from fixed poses")
	var l: Lighting = game.lighting
	var m0 := l.mode
	var sc := track.progress(track.crossing_point)
	# The stretch of road nearest a tree.
	var tree_s := 60.0
	var best := INF
	for prop in world.props.get_children():
		if prop is StaticBody3D and prop.position.distance_to(track.point_at(Track.START_S)) > 5.0:
			var ts := track.progress(prop.position)
			var d := absf(track.lateral_offset(prop.position, ts))
			if d < best:
				best = d
				tree_s = ts
	var poses := [
		["iso_start", Track.START_S - 2.5, "iso"],
		["iso_trees", tree_s, "iso"],
		["iso_bridge_lower", sc - 2.0, "iso"],
		["iso_bridge_upper", 1.0, "iso"],
		["iso_hairpin", 120.0, "iso"],
		["chase_straight", 14.0, "chase"],
		["cine_hairpin", 118.0, "cine"],
	]
	var cine := CineCamera.new()
	cine.target = car
	world.add_child(cine)
	var only_pose := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dtpose="):
			only_pose = arg.trim_prefix("--dtpose=")
	for p: Array in poses:
		if only_pose != "" and p[0] != only_pose:
			continue
		await _place_on_track(p[1])
		await _frames(20)
		match p[2]:
			"iso":
				game.set_chase_view(false)
				camera.snap_to_target()
			"chase":
				game.set_chase_view(true)
			"cine":
				var xf := track.pose_at(122.4, -5.0)
				cine.anchor = xf.origin + Vector3.UP * 2.4
				cine.current = true
				cine.begin()
				renderer.distance_fade = Vector2(cine.car_distance() + 10.0, cine.car_distance() + 30.0)
		for m in Lighting.MODES.size():
			l.set_mode_frozen(m)
			await _frames(3)
			await _shot("50_%s_%d_%s.png" % [p[0], m + 1, String(Lighting.MODES[m].name).replace(" ", "-")])
			if OS.get_cmdline_user_args().has("--dtraw"):
				await _shot("50_%s_%d_%s_raw.png" % [p[0], m + 1, String(Lighting.MODES[m].name).replace(" ", "-")], true)
			if m == 4 and renderer.light_viewport != null and p[0] == "iso_trees":
				renderer.light_viewport.get_texture().get_image().save_png(out_dir.path_join("51_%s_light_pass.png" % p[0]))
		game.set_chase_view(false)
	cine.queue_free()
	l.sweep_running = true
	l.set_mode(m0)
	log_line("  shots 50_<pose>_<mode>.png for %d poses" % poses.size())



## Lighting 6 (glint) through the hairpin in the chase view, against lighting 4
## (same sun, no glint), for the highlight travelling over the car.
func _test_glint() -> void:
	log_line("\n[glint] chase view through the hairpin, lighting 4 vs 6")
	var l: Lighting = game.lighting
	var m0 := l.mode
	game.set_chase_view(true)
	var i := 0
	for s in range(100, 150, 5):
		await _place_on_track(float(s))
		await _frames(30)
		for m: int in [3, 5]:
			l.set_mode(m)
			await _frames(3)
			await _shot("52_glint_%02d_%d.png" % [i, m + 1])
			await _shot("52_glint_%02d_%d_raw.png" % [i, m + 1], true)
		i += 1
	game.set_chase_view(false)
	l.set_mode(m0)




## Lighting 7 (sweep): the sun at six points of its one-minute turn, iso over
## the start line and chase, plus a short live run to check it moves.
func _test_sweep() -> void:
	log_line("\n[sweep] the moving sun")
	var l: Lighting = game.lighting
	var m0 := l.mode
	await _place_on_track(Track.START_S - 2.5)
	await _frames(20)
	camera.snap_to_target()
	for t in range(0, 60, 10):
		l.set_mode_frozen(6, float(t))
		await _frames(3)
		await _shot("53_sweep_iso_%02ds.png" % t)
	l.set_mode_frozen(6, 0.0)
	l.sweep_running = true
	var az0 := l.sun_az
	await _frames(240)
	log_line("  2 s live: sun az %.1f -> %.1f (expect +%.1f)" % [az0, l.sun_az, 2.0 * 360.0 / Lighting.SWEEP_PERIOD])
	l.set_mode(m0)



## Glyph stability per lighting mode: the grid-snap measurement (static view
## round a tree, camera moved by a non-whole number of cells, cell buffers
## compared at the shifted position), snapping on, for every mode.
func _test_light_stability() -> void:
	log_line("\n[light stability] static scene, two camera positions, per lighting mode (snap on)")
	var l: Lighting = game.lighting
	var m0 := l.mode
	var snap_keep := camera.snap_to_grid
	car.teleport(Transform3D(Basis.IDENTITY, Vector3(150.0, Track.ROAD_Y, 150.0)))
	var keep_target := camera.target
	camera.target = null
	await _frames(30)
	var tree_p := Vector3.ZERO
	var best := INF
	for prop in world.props.get_children():
		if prop is StaticBody3D and prop.position.distance_to(track.bounds.get_center()) < best and prop.position.distance_to(track.point_at(Track.START_S)) > 4.0:
			best = prop.position.distance_to(track.bounds.get_center())
			tree_p = prop.position
	camera.snap_to_grid = true
	var moves: Array[Vector3] = [Vector3(1.37, 0.0, 0.83), Vector3(-2.11, 0.0, 0.57), Vector3(0.43, 0.0, -1.91)]
	# The first mode is measured again at the end (the first pass can include
	# settling after the camera was set up).
	for mi in Lighting.MODES.size() + 1:
		var m := mi % Lighting.MODES.size()
		l.set_mode_frozen(m)
		var tot := [0, 0, 0, 0]
		var tree_tot := [0, 0]
		for mv in moves:
			var a := Vector3(tree_p.x, 0.15, tree_p.z - 1.0)
			var b := a + mv
			camera.focus = a
			camera._place()
			await _settle()
			var pa := camera.global_position
			var ia := renderer.cell_viewport.get_texture().get_image()
			var tree_c := _cell_of(Vector3(tree_p.x, 0.4, tree_p.z))
			camera.focus = b
			camera._place()
			await _settle()
			var pb := camera.global_position
			var ib := renderer.cell_viewport.get_texture().get_image()
			var cell := Vector2(float(renderer.pitch.x) / renderer.output_size.x * camera.size * renderer.scene_viewport.size.x / renderer.scene_viewport.size.y,
				float(renderer.pitch.y) / renderer.output_size.y * camera.size)
			var bas := camera.global_basis
			var d := pb - pa
			var si := Vector2i(roundi(d.dot(bas.x) / cell.x), roundi(-d.dot(bas.y) / cell.y))
			var res := _compare(ia, ib, si, tree_c)
			if OS.get_cmdline_user_args().has("--snapdump") and mv == moves[0]:
				ia.save_png(out_dir.path_join("31_cells_m%d_a.png" % (m + 1)))
				ib.save_png(out_dir.path_join("31_cells_m%d_b.png" % (m + 1)))
				renderer.scene_viewport.get_texture().get_image().save_png(out_dir.path_join("31_scene_m%d_b.png" % (m + 1)))
				log_line("    dump shift %s" % si)
			for i in 4:
				tot[i] += res[i]
			tree_tot[0] += res[5]
			tree_tot[1] += res[6]
		_m["stability %s%s glyph diff" % [l.mode_name(), " (again)" if mi >= Lighting.MODES.size() else ""]] = "%d / %d" % [tot[1], tot[0]]
		log_line("  %-8s over %d moves: %d cells compared, glyph differs in %d (%.3f%%), ink in %d, background in %d; tree box %d/%d glyphs" % [
			l.mode_name(), moves.size(), tot[0], tot[1], 100.0 * tot[1] / maxf(tot[0], 1), tot[2], tot[3], tree_tot[0], tree_tot[1]])
	l.sweep_running = true
	l.set_mode(m0)
	camera.snap_to_grid = snap_keep
	camera.target = keep_target



## Frame rate per lighting mode, iso and chase, driving on the circuit (real
## time, vsync off). Classic is measured again at the end, after hatching has
## been on, to check that switching it off returns the cost.
func _test_light_fps() -> void:
	log_line("\n[light fps] frame rate per lighting mode (vsync off; window %s)" % get_window().size)
	var l: Lighting = game.lighting
	var m0 := l.mode
	var order: Array[int] = [2, 3, 4, 5, 6, 0, 1, 2, 3, 2]
	for chase: bool in [false, true]:
		game.set_chase_view(chase)
		var line := []
		for m in order:
			l.set_mode(m)
			await _place_on_track(75.0, 0.0, 6.0)
			var ap := _start_line(7.0)
			await _frames(30)
			var t0 := Time.get_ticks_usec()
			for i in 600:
				await RenderingServer.frame_post_draw
			var fps := 600.0 / ((Time.get_ticks_usec() - t0) / 1e6)
			_stop_line(ap)
			line.append("%s %.0f" % [l.mode_name(), fps])
		log_line("  %s: %s" % ["chase" if chase else "iso  ", ", ".join(line)])
		_m["light fps " + ("chase" if chase else "iso")] = ", ".join(line)
	game.set_chase_view(false)
	l.set_mode(m0)
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(30)



## Classic after visiting every other mode (hatching, glint, the sweep) must be
## the classic frame again, byte for byte (ASCII output and the raw scene).
func _test_light_roundtrip() -> void:
	log_line("\n[light roundtrip] classic, all modes, classic again")
	var l: Lighting = game.lighting
	_inputs(0.0, 0.0, 0.0, false)
	car.teleport(world.grid_pose())
	camera.snap_to_target()
	await _frames(480)
	# Hold the car still: earlier tests can leave it creeping.
	car.freeze = true
	await _frames(10)
	var classic := Lighting.CLASSIC_MODE
	l.set_mode(classic)
	await _settle()
	var a := renderer.get_output_image()
	var ar := renderer.scene_viewport.get_texture().get_image()
	# Control: the same mode again after the same wait, no switching.
	for m in [classic, classic, classic, classic]:
		l.set_mode(m)
		await _settle()
	var c := renderer.get_output_image()
	log_line("  control (classic, no switch): ascii identical %s, raw identical %s" % [
		a.get_data() == c.get_data(), ar.get_data() == renderer.scene_viewport.get_texture().get_image().get_data()])
	for m in Lighting.MODES.size():
		if m == classic:
			continue
		l.set_mode(m)
		l.set_sun(l.sun_az + 33.0, l.sun_el + 5.0)
		await _settle()
	l.set_mode(classic)
	await _settle()
	var b := renderer.get_output_image()
	var br := renderer.scene_viewport.get_texture().get_image()
	var same := a.get_data() == b.get_data()
	var same_raw := ar.get_data() == br.get_data()
	log_line("  classic before == after: ascii %s, raw scene %s" % [same, same_raw])
	_m["classic roundtrip identical"] = same and same_raw
	l.reset_sun()
	l.set_mode(Lighting.DEFAULT_MODE)
	car.freeze = false



## Glint visibility over a full autopilot lap, iso and chase: the same lap is
## driven in lighting 6 with its highlight off (Lighting.glint_highlight) and
## on, and every 6th frame the car's screen box is cropped from the ASCII output
## and the raw scene (54_<view>_<off|on>_<n>_{ascii,raw}.png, boxes in
## 54_boxes.txt), for comparison offline: the difference is the highlight.
## The car poses of the two laps are logged to check that the laps match.
func _test_glint_lap() -> void:
	log_line("\n[glint lap] one autopilot lap per view in lighting 6 with the highlight off and on, car crops every 6th frame")
	var l: Lighting = game.lighting
	var m0 := l.mode
	var boxes := FileAccess.open(out_dir.path_join("54_boxes.txt"), FileAccess.WRITE)
	for chase: bool in [false, true]:
		var view := "chase" if chase else "iso"
		var poses := {}
		for hl: bool in [false, true]:
			var m := 5 # glint
			var tag := "on" if hl else "off"
			l.glint_highlight = hl
			l.set_mode_frozen(m)
			game.set_chase_view(chase)
			await _place_on_track(Track.START_S, 0.0, 0.0)
			await _frames(30)
			var ap := Autopilot.new()
			ap.car = car
			ap.track = track
			ap.max_speed = 7.0
			add_child(ap)
			var n := 0
			var frames := 0
			while frames < 120 * 22.5: # one lap (22.6 s measured)
				await _frames(6)
				frames += 6
				var box := _car_box()
				var out := renderer.get_output_image()
				var raw := renderer.scene_viewport.get_texture().get_image()
				var sc := Vector2(raw.get_size()) / Vector2(out.get_size())
				out.get_region(box).save_png(out_dir.path_join("54_%s_%s_%03d_ascii.png" % [view, tag, n]))
				raw.get_region(Rect2i(Vector2i(Vector2(box.position) * sc), Vector2i(Vector2(box.size) * sc))).save_png(
					out_dir.path_join("54_%s_%s_%03d_raw.png" % [view, tag, n]))
				if not hl:
					poses[n] = car.global_position
					boxes.store_line("%s %d %d %d %d %d %d" % [view, n, box.position.x, box.position.y, box.size.x, box.size.y, renderer.pitch.x * 1000 + renderer.pitch.y])
				elif poses.has(n) and n % 50 == 0:
					log_line("  %s sample %d: car pose differs from the highlight-off lap by %.4f" % [view, n, car.global_position.distance_to(poses[n])])
				n += 1
			_stop_line(ap)
			log_line("  %s highlight %s: %d samples over %.1f s" % [view, tag, n, frames / 120.0])
	boxes.close()
	l.glint_highlight = true
	game.set_chase_view(false)
	l.sweep_running = true
	l.set_mode(m0)


## The car's screen box in output pixels (its body box projected, padded a cell).
func _car_box() -> Rect2i:
	var xf := car.global_transform
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in 8:
		var c := Vector3(0.3 if i & 1 else -0.3, 0.5 if i & 2 else 0.0, 0.5 if i & 4 else -0.5)
		var p := camera.get_viewport().get_camera_3d().unproject_position(xf * c) / Vector2(renderer.scene_viewport.size) * Vector2(renderer.output_size)
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector2(renderer.pitch)
	hi += Vector2(renderer.pitch)
	var r := Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil()))
	return r.intersection(Rect2i(Vector2i.ZERO, renderer.output_size))



## The circuit's corners: [name, s at the arc's start, s at its end, radius, turn
## in degrees (+ = right)], from the resolved layout.
func _corner_list() -> Array:
	var out: Array = []
	var s := 0.0
	for seg: Array in track._segs:
		var l: float = seg[1]
		if seg[0] == "A":
			var k: float = seg[2]
			var deg := rad_to_deg(k * l)
			out.append(["R%d %+.0f" % [roundi(1.0 / absf(k)), deg], s, s + l, 1.0 / absf(k), deg])
		s += l
	return out


## One constant-speed pass through a corner with the centre-line autopilot (no
## braking: it holds `v`). Returns [clean, max |lateral|, max slip deg, wheels
## off the road (frames), spun].
var _runup_max: float = INF
var _trace: PackedStringArray = []
## Measured clean speed per corner name (by _test_corners).
var _corner_clean: Dictionary = {}
## Limit scenarios: entry this much faster than the corner's clean speed.
const OVERCOOK: float = 1.12
## Clean pass: the car's centre stays this close to the centre line (its body on
## the asphalt, not riding a kerb or a wall).
const CORNER_CLEAN_LAT: float = 1.1


func _corner_pass(c: Array, v: float) -> Array:
	var runup := minf(2.0 + v * 0.6, _runup_max)
	await _place_on_track(c[1] - runup, 0.0, v)
	var ap := Autopilot.new()
	ap.car = car
	ap.track = track
	ap.max_speed = v
	ap.lateral_accel = 1000.0
	add_child(ap)
	var max_lat := 0.0
	var max_slip := 0.0
	var off := 0
	var spun := false
	var hint: float = c[1] - runup
	for i in 120 * 8:
		await _frames(1)
		hint = track.progress(car.global_position, hint)
		max_lat = maxf(max_lat, absf(track.lateral_offset(car.global_position, hint)))
		max_slip = maxf(max_slip, absf(car.slip_angle))
		if car.wheels_grounded > car.wheels_on_road:
			off += 1
		var t := track.tangent_at(hint)
		if (-car.global_basis.z).dot(Vector3(t.x, 0.0, t.z).normalized()) < -0.5:
			spun = true
		if fposmod(hint - c[2], track.length) < track.length * 0.5 and fposmod(hint - c[2], track.length) > 2.0 or spun or max_lat > 4.0:
			break
	_stop_line(ap)
	var clean := max_lat <= CORNER_CLEAN_LAT and off == 0 and max_slip < deg_to_rad(12.0) and not spun
	return [clean, max_lat, rad_to_deg(max_slip), off, spun]


## Highest clean constant-speed entry for each corner (bisection on speed),
## against the car's top speed: which corners are flat, which need a lift or
## braking.
func _test_corners() -> void:
	log_line("\n[corners] highest speed held through each corner by the centre-line autopilot (no braking) that stays clean: the body on the asphalt (|lateral| <= %.2f), no wheel off the road, slip < 12 deg" % CORNER_CLEAN_LAT)
	var top := car.top_speed * 0.92
	var rows := PackedStringArray()
	var list := _corner_list()
	for ci in list.size():
		var c: Array = list[ci]
		# Run up from the previous corner's exit at the latest.
		var prev: Array = list[(ci - 1 + list.size()) % list.size()]
		_runup_max = fposmod(c[1] - prev[2], track.length)
		var lo := 2.0
		var hi := top + 1.0
		var at_hi: Array = await _corner_pass(c, hi)
		var why := ""
		if at_hi[0]:
			lo = hi
		else:
			for it in 6:
				var mid := (lo + hi) * 0.5
				var r: Array = await _corner_pass(c, mid)
				if r[0]:
					lo = mid
				else:
					hi = mid
					why = "lat %.2f slip %.0f off %d%s" % [r[1], r[2], r[3], " SPUN" if r[4] else ""]
		var line := "%-8s s %5.1f..%5.1f  clean up to %5.2f u/s%s" % [c[0], c[1], c[2], lo, "  (flat)" if lo >= top else "   first failure above: " + why]
		log_line("  " + line)
		rows.append("%s %.1f" % [c[0], lo])
		_corner_clean[c[0]] = lo
	_m["corner_speeds"] = ", ".join(rows)


## Steering toward the centre line ahead (pure pursuit), as a greedy driver aims.
func _pursuit_steer(hint: float) -> float:
	var v := maxf(car.forward_speed, 0.0)
	var target := track.point_at(hint + 0.9 + 0.22 * v)
	var to := target - car.global_position
	to.y = 0.0
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	var err := fwd.signed_angle_to(to, Vector3.DOWN)
	return clampf(err / maxf(car.steer_lock, deg_to_rad(4.0)) * 1.3, -1.0, 1.0)


## The limit: the same overcooked entry into a corner with (a) no correction
## (keeps aiming at the line, throttle held), (b) a human-like catch (after a
## 0.2 s reaction delay once the slide passes 10 deg: counter-steer with the
## slide and lift, then feed the throttle back in), (c) entering near the limit
## on the throttle and lifting abruptly mid-corner (aiming at the line).
func _test_limit() -> void:
	log_line("\n[limit] overcooked entries (%.2fx the corner's clean speed): a = no correction (steering frozen once sliding, throttle held), b = catch after 0.2 s (counter-steer, lift, throttle back in), c = near-limit entry, lift abruptly 40%% into the corner; spun = nose more than 120 deg from the direction of travel" % OVERCOOK)
	var corners := _corner_list()
	var names := ["R6 +90", "R8 -45"]
	for c: Array in corners:
		if c[0] in names:
			for mode in ["a", "b", "c"]:
				await _limit_run(c, mode)


func _limit_run(c: Array, mode: String) -> void:
	# Entry speed: overcooked by 25% over this corner's clean speed (measured
	# above when run with `corners`; otherwise from the radius and road grip).
	var v_clean: float = _corner_clean.get(c[0], sqrt(car.grip_road * Car.G * 0.72 * c[3]))
	var v := minf(v_clean * (1.0 if mode == "c" else OVERCOOK), car.top_speed * 0.92)
	var s0: float = c[1] - 2.0 - v * 0.5
	await _place_on_track(s0, 0.0, v)
	var hint := s0
	var peak := 0.0
	var spun := false
	var t_slide := -1.0
	var t_catch := -1.0
	var t_rec := -1.0
	var heading0 := 0.0
	var max_rel_yaw := 0.0
	var lifted := false
	var dur := 120 * 6
	for i in dur:
		hint = track.progress(car.global_position, hint)
		var sl := car.slip_angle
		var steer := _pursuit_steer(hint)
		var thr := clampf((v - car.forward_speed) * 1.5 + 0.6, 0.0, 1.0)
		var t := i / 120.0
		var into := fposmod(hint - c[1], track.length)
		into = into if into < track.length * 0.5 else into - track.length
		match mode:
			"a":
				if t_slide < 0.0 and absf(sl) > deg_to_rad(10.0):
					t_slide = t
					heading0 = steer
				if t_slide >= 0.0:
					steer = heading0 # no reaction: the hands stay where they were
			"b":
				if t_slide < 0.0 and absf(sl) > deg_to_rad(10.0):
					t_slide = t
				if t_slide >= 0.0 and t >= t_slide + 0.2:
					# Catch: steer with the slide (counter-steer), lift, then feed the throttle in.
					# Counter-steer with the slide while it is big, back to aiming at
					# the road as it shrinks; lift, then feed the throttle back in.
					var since := t - t_slide - 0.2
					var cs := clampf(sl / deg_to_rad(20.0), -1.0, 1.0)
					steer = lerpf(steer, cs, clampf(absf(sl) / deg_to_rad(12.0), 0.0, 1.0))
					thr = clampf((since - 0.25) * 1.5, 0.0, 0.7)
					if t_catch < 0.0:
						t_catch = t
			"c":
				thr = 1.0
				if into > (c[2] - c[1]) * 0.4:
					thr = 0.0
					lifted = true
		_inputs(steer, thr, 0.0, false)
		await _frames(1)
		var asl := absf(car.slip_angle)
		peak = maxf(peak, asl)
		var tg := track.tangent_at(hint)
		var rel := absf((-car.global_basis.z).signed_angle_to(Vector3(tg.x, 0.0, tg.z), Vector3.UP))
		max_rel_yaw = maxf(max_rel_yaw, rel)
		var vel := car.linear_velocity
		vel.y = 0.0
		var nose := -car.global_basis.z
		nose.y = 0.0
		if vel.length() > 1.0 and nose.angle_to(vel) > deg_to_rad(120.0):
			spun = true
		if peak > deg_to_rad(10.0) and t_rec < 0.0 and asl < deg_to_rad(5.0) and absf(car.angular_velocity.y) < 1.5 and i > 30:
			t_rec = t
		if into > (c[2] - c[1]) + 6.0 or spun and i > 240:
			break
	var lat := track.lateral_offset(car.global_position, hint)
	var line := "%s (%s) entry %.2f u/s: peak slip %.0f deg, max yaw vs road %.0f deg, %s; recovered (slip < 5) %s; ended %+.2f from the centre line (%s), %.2f u/s" % [
		c[0], {"a": "a: no correction", "b": "b: catch after 0.2 s", "c": "c: lift mid-corner"}[mode], v, rad_to_deg(peak), rad_to_deg(max_rel_yaw),
		"SPUN" if spun else "no spin", ("%.2f s after the slide began" % (t_rec - maxf(t_slide, 0.0))) if t_rec >= 0.0 and peak > deg_to_rad(10.0) else ("no slide" if peak <= deg_to_rad(10.0) else "NO"),
		lat, "on road" if absf(lat) <= Track.ROAD_HALF_WIDTH + 0.3 else "OFF ROAD", car.forward_speed]
	log_line("  " + line)
	_m["limit %s %s" % [c[0], mode]] = "peak %.0f deg, %s, %s" % [rad_to_deg(peak), "SPUN" if spun else "no spin", "on road" if absf(lat) <= Track.ROAD_HALF_WIDTH + 0.3 else "off road"]
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)



## Nitro: inputs, the burn from top speed (speed over time, tank), the shove
## from mid speed, feathering, refills, a burn mid-corner, and in the air.
func _test_nitro() -> void:
	log_line("\n[nitro] capacity %.2f s, push %.1f u/s^2, top speed +%d%%, ramp %.2f s, refill: drift %.2f tank/s, trickle %.0f s for a full tank" % [
		car.nitro_capacity, car.nitro_accel, roundi(car.nitro_top_gain * 100.0), car.nitro_ramp_time, car.nitro_drift_refill, car.nitro_trickle_time])
	# Inputs: Shift and the left stick click.
	car.player_input = true
	_key(KEY_SHIFT, true)
	await _frames(2)
	var by_key := car.nitro_input
	_key(KEY_SHIFT, false)
	await _frames(2)
	_joy_button(JOY_BUTTON_LEFT_STICK, true)
	await _frames(2)
	var by_pad := car.nitro_input
	_joy_button(JOY_BUTTON_LEFT_STICK, false)
	await _frames(2)
	var released := not car.nitro_input
	car.player_input = false
	log_line("  input: Shift -> %s, left stick click -> %s, released -> off %s" % [by_key, by_pad, released])
	_m["nitro_input"] = "Shift %s, L-stick %s" % [by_key, by_pad]

	# The burn from top speed on the pad.
	await _place(Vector3(-9.5, 0.0, -30.0), Vector3.RIGHT, 9.8)
	var v0 := car.forward_speed
	car.refill_nitro()
	var trace := PackedStringArray()
	var peak := 0.0
	var empty_at := -1.0
	for i in 120 * 3:
		_inputs(0.0, 1.0, 0.0, false)
		car.nitro_input = i < 120 * 2 # held past empty: it stops by itself
		await _frames(1)
		peak = maxf(peak, car.forward_speed)
		if empty_at < 0.0 and car.nitro_tank <= 0.0:
			empty_at = (i + 1) / 120.0
		if (i + 1) % 30 == 0:
			trace.append("%.2f" % car.forward_speed)
		if i == 90:
			await _shot("60_nitro_burn.png")
	car.nitro_input = false
	log_line("  from %.2f u/s, throttle and nitro held: tank empty after %.2f s, peak %.2f u/s (+%d%%); speed every 0.25 s: %s" % [
		v0, empty_at, peak, roundi((peak / v0 - 1.0) * 100.0), ", ".join(trace)])
	_m["nitro_burn"] = "empty after %.2f s, %.2f -> peak %.2f u/s (+%d%%), back to %.2f after 2 s" % [empty_at, v0, peak, roundi((peak / v0 - 1.0) * 100.0), car.forward_speed]

	# The shove: 0.5 s from 5 u/s, with and without.
	var gain := []
	for burn in [false, true]:
		await _place(Vector3(-9.0, 0.0, -30.0), Vector3.RIGHT, 5.0)
		car.refill_nitro()
		for i in 60:
			_inputs(0.0, 1.0, 0.0, false)
			car.nitro_input = burn
			await _frames(1)
		gain.append(car.forward_speed - 5.0)
	car.nitro_input = false
	log_line("  0.5 s from 5 u/s, full throttle: +%.2f u/s without, +%.2f u/s with nitro" % [gain[0], gain[1]])
	_m["nitro_shove"] = "+%.2f vs +%.2f u/s in 0.5 s from 5" % [gain[0], gain[1]]

	# Feathering: three 0.1 s taps.
	car.refill_nitro()
	var t0 := car.nitro_tank
	for k in 3:
		car.nitro_input = true
		await _frames(12)
		car.nitro_input = false
		await _frames(12)
	log_line("  three 0.1 s taps used %.2f s of tank" % (t0 - car.nitro_tank - 0.0))

	# Refill: trickle from empty for 5 s; drift for 2 s.
	await _place(Vector3(-9.0, 0.0, -30.0), Vector3.RIGHT)
	car.nitro_tank = 0.0
	await _frames(600)
	var trickle := car.nitro_tank / car.nitro_capacity
	await _place(Vector3(-9.0, 0.0, -36.0), Vector3.RIGHT, 6.0)
	car.nitro_tank = 0.0
	var drift_t := 0.0
	for i in 240:
		_inputs(1.0 if i < 30 else 0.7, 1.0, 0.0, true)
		await _frames(1)
		if car.drift_state == Car.Drift.DRIFT:
			drift_t += 1.0 / 120.0
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)
	log_line("  refill: trickle 5 s from empty -> %d%%; %.2f s of drifting (2.5 s total) -> %d%%" % [
		roundi(trickle * 100.0), drift_t, roundi(car.nitro_tank / car.nitro_capacity * 100.0)])
	_m["nitro_refill"] = "trickle 5 s %d%%, drift %.1f s %d%%" % [roundi(trickle * 100.0), drift_t, roundi(car.nitro_tank / car.nitro_capacity * 100.0)]
	# Empty tank: no push.
	await _place(Vector3(-9.0, 0.0, -30.0), Vector3.RIGHT, 5.0)
	car.nitro_tank = 0.0
	car.nitro_input = true
	await _frames(30)
	log_line("  empty tank, nitro held: level %.2f" % car.nitro_level)
	car.nitro_input = false

	# Mid-corner burn: R8 at its clean speed, nitro from the apex.
	var c: Array = []
	for cc: Array in _corner_list():
		if cc[0] == "R8 -45":
			c = cc
			break
	var vc: float = _corner_clean.get("R8 -45", 8.5)
	for burn in [false, true]:
		await _place_on_track(c[1] - 6.0, 0.0, vc)
		car.refill_nitro()
		var hint: float = c[1] - 6.0
		var peak_slip := 0.0
		var max_lat := 0.0
		for i in 120 * 3:
			hint = track.progress(car.global_position, hint)
			var into: float = hint - c[1]
			_inputs(_pursuit_steer(hint), clampf((vc - car.forward_speed) * 1.5 + 0.5, 0.0, 1.0), 0.0, false)
			car.nitro_input = burn and into > (c[2] - c[1]) * 0.3
			await _frames(1)
			peak_slip = maxf(peak_slip, absf(car.slip_angle))
			max_lat = maxf(max_lat, absf(track.lateral_offset(car.global_position, hint)))
		car.nitro_input = false
		log_line("  R8 -45 at %.2f u/s, nitro %s from 30%% in: peak slip %.0f deg, max |lateral| %.2f%s" % [
			vc, "ON" if burn else "off", rad_to_deg(peak_slip), max_lat, " (off the road)" if max_lat > Track.ROAD_HALF_WIDTH else ""])
		_m["nitro_corner_" + ("on" if burn else "off")] = "peak slip %.0f deg, lateral %.2f" % [rad_to_deg(peak_slip), max_lat]

	# In the air: the jump at top speed, nitro from the kicker, vs without.
	var v_jump := car.top_speed * 0.91
	for burn in [false, true]:
		await _place_on_track(16.0, 0.0, v_jump)
		car.refill_nitro()
		var take_off := Vector3.ZERO
		var land := Vector3.ZERO
		var yaw0 := 0.0
		var airborne := false
		var yaw_air := 0.0
		var max_comp := 0.0
		for i in 120 * 3:
			var hint := track.progress(car.global_position, 16.0)
			_inputs(_pursuit_steer(hint), 1.0, 0.0, false)
			car.nitro_input = burn and hint > 19.5
			await _frames(1)
			if not airborne and car.wheels_grounded == 0 and hint > 20.5:
				airborne = true
				take_off = car.global_position
				yaw0 = car.global_rotation.y
			elif airborne and land == Vector3.ZERO and car.wheels_grounded > 0:
				land = car.global_position
				yaw_air = absf(wrapf(car.global_rotation.y - yaw0, -PI, PI))
			if land != Vector3.ZERO:
				max_comp = maxf(max_comp, car.suspension_compression())
				if car.global_position.distance_to(land) > 3.0:
					break
		car.nitro_input = false
		var dist := Vector2(take_off.x, take_off.z).distance_to(Vector2(land.x, land.z))
		var land_s := track.progress(land, 28.0)
		log_line("  jump at %.1f u/s, nitro %s: flight %.2f u, lands at s %.1f (landing slope s 26..33.5), yaw in the air %.1f deg, max compression after landing %d%%" % [
			v_jump, "ON" if burn else "off", dist, land_s, rad_to_deg(yaw_air), roundi(max_comp * 100.0)])
		_m["nitro_jump_" + ("on" if burn else "off")] = "flight %.2f u, lands s %.1f, compression %d%%" % [dist, land_s, roundi(max_comp * 100.0)]
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(60)



## The nitro bar and the burn, iso and chase, at the default glyph size and the
## Retina 20 px one: burning, half full and refilling, empty with nitro held.
func _test_nitro_shots() -> void:
	log_line("\n[nitro shots] bar and burn effects")
	var px0 := renderer.settings.glyph_px
	for px: int in [px0, 20]:
		if renderer.settings.glyph_px != px:
			renderer.settings.glyph_px = px
			await renderer.atlas_ready
			await _frames(5)
		for chase: bool in [false, true]:
			game.set_chase_view(chase)
			var view := "chase" if chase else "iso"
			await _place_on_track(12.5, 0.0, 8.0)
			car.refill_nitro()
			await _frames(90) # let the empty-tank flash of the previous shot pass
			for i in 50:
				_inputs(_pursuit_steer(track.progress(car.global_position, 12.5)), 1.0, 0.0, false)
				car.nitro_input = true
				await _frames(1)
			await _shot("61_nitro_%dpx_%s_burning.png" % [px, view])
			car.nitro_input = false
			car.nitro_tank = car.nitro_capacity * 0.5
			await _frames(30)
			await _shot("61_nitro_%dpx_%s_half.png" % [px, view])
			car.nitro_tank = 0.0
			car.nitro_input = true
			await _frames(6)
			await _shot("61_nitro_%dpx_%s_empty.png" % [px, view])
			car.nitro_input = false
	game.set_chase_view(false)
	if renderer.settings.glyph_px != px0:
		renderer.settings.glyph_px = px0
		await renderer.atlas_ready
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(30)



## Audio measurement: scripted scenarios run under the movie writer
## (`--write-movie <file>.avi`, which records the game's audio in step with the
## frames). Logs per frame (60 fps movie time) the scenario and the car sound's
## state to 70_audio_frames.csv, and the scenarios' frame ranges to
## 70_audio_segments.csv, for tools/measure_audio.py.
func _test_audio() -> void:
	log_line("\n[audio] scenarios for the recording (see 70_audio_*.csv)")
	var ca: CarAudio = game.car_audio
	var au: AudioDirector = game.audio
	var rows := PackedStringArray(["frame,scenario,rpm,gear,load,squeal,skid,nitro,speed,master_peak_db,music_peak_db,sfx_peak_db,w0,w1,w2,p0,p1,p2,events"])
	var segs := PackedStringArray(["scenario,first_frame,last_frame"])
	var state := {"scn": "", "frame": 0, "first": 0, "ev": 0}
	var rec := func() -> void:
		state.frame = Engine.get_process_frames() # = the movie writer's frame index
		var w := ca.engine_weights
		var pz := ca.engine_pitches
		var ev := PackedStringArray()
		while state.ev < ca.events.size():
			var e: Array = ca.events[state.ev]
			ev.append("%s:%.2f" % [e[1], e[2]])
			state.ev += 1
		rows.append("%d,%s,%.1f,%d,%.2f,%.3f,%.3f,%.2f,%.2f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s" % [state.frame, state.scn, ca.rpm, ca.gear, ca.load,
			ca.squeal, ca.skid, car.nitro_level, car.linear_velocity.length(),
			AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Music"), 0),
			AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("SFX"), 0),
			w[0] if w.size() > 0 else 0.0, w[1] if w.size() > 1 else 0.0, w[2] if w.size() > 2 else 0.0,
			pz[0] if pz.size() > 0 else 0.0, pz[1] if pz.size() > 1 else 0.0, pz[2] if pz.size() > 2 else 0.0, " ".join(ev)])
	get_tree().process_frame.connect(rec)
	var seg := func(name: String) -> void:
		if state.scn != "":
			segs.append("%s,%d,%d" % [state.scn, state.first, state.frame])
		state.scn = name
		state.first = state.frame + 1
	ca.events.clear()
	# Race: on the pad.
	await _place(Vector3(-9.5, 0.0, -36.0), Vector3.RIGHT)
	await _frames(60)
	seg.call("idle")
	await _frames(240)
	seg.call("free_rev")
	for i in 180:
		_inputs(0.0, 1.0 if i < 90 else 0.0, 0.0, false)
		car.linear_velocity = Vector3.ZERO
		await _frames(1)
	seg.call("launch_full_throttle")
	for i in 120 * 4:
		_inputs(0.0, 1.0, 0.0, false)
		await _frames(1)
	seg.call("coast")
	_inputs(0.0, 0.0, 0.0, false)
	await _frames(240)
	seg.call("brake_stop")
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(240)
	_inputs(0.0, 0.0, 0.0, false)
	# Sustained full throttle at speed (the reference for the level table).
	await _place_on_track(12.5, 0.0, 9.0)
	seg.call("full_throttle_cruise")
	for i in 120 * 2:
		_inputs(_pursuit_steer(track.progress(car.global_position, 12.5)), 1.0, 0.0, false)
		await _frames(1)
	# A corner too fast: squeal.
	await _place_on_track(30.0, 0.0, 9.6)
	seg.call("corner_squeal")
	var h := 30.0
	for i in 120 * 3:
		h = track.progress(car.global_position, h)
		_inputs(_pursuit_steer(h), 1.0, 0.0, false)
		await _frames(1)
	# Handbrake drift on the pad.
	await _place(Vector3(-9.0, 0.0, -36.0), Vector3.RIGHT, 6.5)
	seg.call("drift")
	for i in 120 * 3:
		_inputs(1.0 if i < 30 else 0.7, 1.0, 0.0, true)
		await _frames(1)
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(120)
	# Nitro from mid speed.
	await _place(Vector3(-9.5, 0.0, -30.0), Vector3.RIGHT, 6.0)
	car.refill_nitro()
	seg.call("nitro")
	for i in 120 * 2:
		_inputs(0.0, 1.0, 0.0, false)
		car.nitro_input = i < 180
		await _frames(1)
	car.nitro_input = false
	# Jump landing.
	await _place_on_track(15.0, 0.0, 9.5)
	seg.call("jump_landing")
	h = 15.0
	for i in 120 * 2:
		h = track.progress(car.global_position, h)
		_inputs(_pursuit_steer(h), 1.0, 0.0, false)
		await _frames(1)
	# Into the tree at the end of the pad.
	await _place(Vector3(19.0, 0.0, -40.0), Vector3.RIGHT, 6.0)
	seg.call("impact")
	for i in 120 * 2:
		_inputs(0.0, 0.5, 0.0, false)
		await _frames(1)
	# Everything at once: full throttle in a slide with nitro, landing on the jump.
	await _place_on_track(14.0, 0.0, 9.5)
	car.refill_nitro()
	seg.call("everything")
	h = 14.0
	for i in 120 * 3:
		h = track.progress(car.global_position, h)
		_inputs(_pursuit_steer(h), 1.0, 0.0, i > 200)
		car.nitro_input = i > 30
		await _frames(1)
	car.nitro_input = false
	# Coasting at speed (music still audible?).
	await _place_on_track(12.5, 0.0, 9.0)
	seg.call("coast_at_speed")
	for i in 120 * 2:
		_inputs(_pursuit_steer(track.progress(car.global_position, 12.5)), 0.0, 0.0, false)
		await _frames(1)
	# Paused mid-drive.
	await _place_on_track(12.5, 0.0, 8.0)
	_inputs(0.0, 1.0, 0.0, false)
	await _frames(60)
	game.pause_menu.open(false)
	seg.call("paused")
	for i in 150:
		await get_tree().process_frame
	game.pause_menu.close()
	seg.call("resumed")
	await _frames(120)
	# The reel's mix: menu music, the car under it.
	au.forced_context = AudioDirector.Context.MENU
	au.forced_track = "menu"
	await _frames(240) # the crossfade
	await _place_on_track(12.5, 0.0, 9.0)
	seg.call("reel_mix")
	for i in 120 * 3:
		_inputs(_pursuit_steer(track.progress(car.global_position, 12.5)), 1.0, 0.0, false)
		await _frames(1)
	au.forced_context = -1
	au.forced_track = ""
	seg.call("")
	_inputs(0.0, 0.0, 1.0, false)
	get_tree().process_frame.disconnect(rec)
	var f := FileAccess.open(out_dir.path_join("70_audio_frames.csv"), FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	f = FileAccess.open(out_dir.path_join("70_audio_segments.csv"), FileAccess.WRITE)
	f.store_string("\n".join(segs) + "\n")
	f.close()
	log_line("  %d frames, %d segments, %d gear shifts" % [state.frame, segs.size() - 1, ca.shifts])



## The pause menu: pausing mid-drive, in the air, mid-drift and mid-nitro
## (nothing moves, no lap time, no rumble, the car silent; state and speed
## carry over on resume), menu input, saved volumes, and screenshots at the
## default grid, a small window's grid and the Retina 20 px grid.
func _test_pause() -> void:
	log_line("\n[pause] menu, pausing and resuming")
	var menu: PauseMenu = game.pause_menu
	var au: AudioDirector = game.audio
	au.settings_path = out_dir.path_join("audio_settings.cfg")
	var cases := [["driving", 30.0, 8.0, false, false], ["in the air", 17.0, 9.5, false, false],
		["drifting", 113.0, 7.0, true, false], ["burning nitro", 12.5, 7.0, false, true]]
	for c: Array in cases:
		await _place_on_track(c[1], 0.0, c[2])
		car.refill_nitro()
		game.laps.reset()
		var h: float = c[1]
		var frames := 0
		while frames < 600:
			h = track.progress(car.global_position, h)
			var steer := _pursuit_steer(h)
			if c[3] and frames > 40:
				steer = -1.0
			_inputs(steer, 1.0, 0.0, c[3] and frames > 40)
			car.nitro_input = c[4] and frames > 20
			await _frames(1)
			frames += 1
			if c[0] == "in the air" and car.wheels_grounded == 0 and car.air_time > 0.1:
				break
			if c[3] and car.drift_state == Car.Drift.DRIFT and car.drift_time > 0.4:
				break
			if c[4] and car.nitro_level >= 1.0 and frames > 60:
				break
			if c[0] == "driving" and frames >= 60:
				break
		var p0 := car.global_position
		var v0 := car.linear_velocity
		var lap0: float = game.laps.current
		var drift0 := car.drift_state
		var nitro0 := car.nitro_level
		var tank0 := car.nitro_tank
		menu.open(false)
		for i in 90:
			await get_tree().process_frame
		var moved := car.global_position.distance_to(p0)
		var sfx_muted := AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX"))
		var rumble_off: bool = not game.rumble.running
		var lap_d: float = game.laps.current - lap0
		if c[0] == "driving":
			await _shot("80_pause_menu_default.png")
		menu.close()
		await _frames(1)
		var dv := (car.linear_velocity - v0).length()
		log_line("  %-14s paused 1.5 s: moved %.4f, lap time +%.3f s, rumble off %s, car sound bus muted %s; resumed: speed change over one step %.2f u/s, drift %s -> %s, nitro level %.2f -> %.2f, tank %.2f -> %.2f" % [
			c[0], moved, lap_d, rumble_off, sfx_muted, dv, Car.Drift.keys()[drift0], Car.Drift.keys()[car.drift_state], nitro0, car.nitro_level, tank0, car.nitro_tank])
		_m["pause " + c[0]] = "moved %.4f, lap +%.3f, resume dv %.2f" % [moved, lap_d, dv]
		car.nitro_input = false
		_inputs(0.0, 0.0, 1.0, false)
		await _frames(60)

	# Menu input: open with Esc, down to MUSIC, left twice, Esc closes and saves.
	game.controls.enabled = true
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await get_tree().process_frame
	var opened := menu.is_open and get_tree().paused
	var m0 := au.music_volume
	var target := menu.items.find(PauseMenu.Item.MUSIC)
	for i in target:
		_key(KEY_DOWN, true)
		_key(KEY_DOWN, false)
		await get_tree().process_frame
	for i in 2:
		_key(KEY_LEFT, true)
		_key(KEY_LEFT, false)
		await get_tree().process_frame
	var m1 := au.music_volume
	await get_tree().process_frame
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await get_tree().process_frame
	var closed := not menu.is_open and not get_tree().paused
	var fresh := AudioDirector.new()
	fresh.settings_path = au.settings_path
	fresh.load_settings()
	log_line("  keys: Esc opens %s (items %s); Down x%d, Left x2 on MUSIC: %.2f -> %.2f; Esc closes %s; saved to %s and read back: master %.2f music %.2f sfx %.2f" % [
		opened, menu.items.map(func(it: int) -> String: return PauseMenu.LABELS[it]), target, m0, m1, closed, au.settings_path.get_file(),
		fresh.master_volume, fresh.music_volume, fresh.sfx_volume])
	_m["pause_menu_keys"] = "open %s, music %.2f -> %.2f, close %s, saved music %.2f" % [opened, m0, m1, closed, fresh.music_volume]
	fresh.free()
	au.set_music_volume(m0)
	game.controls.enabled = false

	# Screenshots at the three grid sizes (and the reel's version).
	var px0 := renderer.settings.glyph_px
	for g: Array in [["small_window", px0, Vector2i(800, 880)], ["retina_20px", 20, SHOT_SIZE], ["default", px0, SHOT_SIZE]]:
		renderer.fixed_output_size = g[2]
		if renderer.settings.glyph_px != g[1]:
			renderer.settings.glyph_px = g[1]
			await renderer.atlas_ready
		await _frames(5)
		menu.open(false)
		menu.selected = menu.items.find(PauseMenu.Item.SFX)
		for i in 10:
			await get_tree().process_frame
		await _shot("81_pause_menu_%s.png" % g[0])
		menu.close()
		await _frames(2)
	renderer.fixed_output_size = SHOT_SIZE
	menu.open(true)
	for i in 10:
		await get_tree().process_frame
	await _shot("82_reel_menu_default.png")
	menu.close()
	await _frames(2)



# --- AI opponent ---------------------------------------------------------------

## Turns the opponent on at `level` (without saving the setting): both cars on the grid.
func _opp_on(level: int) -> Opponent:
	game.remove_opponent()
	game.audio.opponent_level = level
	game.update_opponent(true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--opptune="):
			for kv in arg.trim_prefix("--opptune=").split(",", false):
				var p := kv.split("=")
				game.opponent.driver.set(p[0], float(p[1]))
			game.opponent.driver.restart()
	return game.opponent


func _opp_off() -> void:
	game.audio.opponent_level = 0
	game.remove_opponent()


## Parks the player's car on the test pad, frozen (out of the opponent's way).
func _park_player() -> void:
	car.teleport(Transform3D(Basis.IDENTITY, Vector3(-9.0, Track.ROAD_Y, -36.0)))
	car.freeze = true


func _levels() -> Array[int]:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--opplevels="):
			var out: Array[int] = []
			for v in arg.trim_prefix("--opplevels=").split(","):
				out.append(v.to_int())
			return out
	return [1, 2, 3, 4, 5]


func _opp_laps_wanted() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--opplaps="):
			return arg.trim_prefix("--opplaps=").to_int()
	return 6


## Each level alone over a run of laps: lap times (from the start line), resets,
## longest time without progress, off-road time, nitro and drift use.
func _test_opp_laps() -> void:
	var want := _opp_laps_wanted()
	log_line("\n[opponent laps] each level alone, %d laps (the first from a standing start), the player's car parked off the track" % want)
	for level in _levels():
		var opp := _opp_on(level)
		_park_player()
		await _frames(30)
		var oc: Car = opp.car
		var drv: OpponentDriver = opp.driver
		var first_cross: float = world.GRID_BACK
		var times: Array[float] = []
		var t := 0.0
		var last_cross := 0.0
		var next := first_cross
		var stall := 0.0
		var worst_stall := 0.0
		var last_d := 0.0
		var off := 0
		var nitro_frames := 0
		var drift_frames := 0
		var max_slip := 0.0
		while times.size() < want and t < 60.0 * want:
			await _frames(1)
			t += 1.0 / 120.0
			var d: float = opp._d.y
			if d >= next:
				if next > first_cross:
					times.append(t - last_cross)
				last_cross = t
				next += track.length
			if d > last_d + 0.05:
				last_d = d
				stall = 0.0
			else:
				stall += 1.0 / 120.0
				worst_stall = maxf(worst_stall, stall)
			if oc.wheels_grounded > oc.wheels_on_road:
				off += 1
			if oc.nitro_level > 0.0:
				nitro_frames += 1
			if oc.drift_state == Car.Drift.DRIFT:
				drift_frames += 1
			max_slip = maxf(max_slip, absf(oc.slip_angle))
		var flying := times.slice(1) if times.size() > 1 else times
		var mean := 0.0
		for x in flying:
			mean += x
		mean /= maxf(flying.size(), 1)
		var spread := 0.0
		for x in flying:
			spread = maxf(spread, absf(x - mean))
		log_line("  level %d: laps %s; flying laps mean %.2f s (+-%.2f); resets %d; longest without progress %.1f s; %.1f s with a wheel off the road; nitro %.1f s; drifting %.1f s; peak slip %.0f deg" % [
			level, ", ".join(times.map(func(x: float) -> String: return "%.2f" % x)), mean, spread, opp.resets, worst_stall,
			off / 120.0, nitro_frames / 120.0, drift_frames / 120.0, rad_to_deg(max_slip)])
		_m["opp level %d" % level] = "mean %.2f s (+-%.2f) over %d flying laps, resets %d, off %.1f s" % [mean, spread, flying.size(), opp.resets, off / 120.0]
		car.freeze = false
		_opp_off()
		await _frames(5)


## The player's car parked in the way: on the racing line on the main straight,
## and across the hairpin exit. The opponent comes from behind at speed.
func _test_opp_block() -> void:
	log_line("\n[opponent blocked] the player's car parked in the way; does the opponent get past (or recover) and carry on?")
	for c: Array in [["on the line, main straight", 16.0, 0.0, 0.0], ["across the hairpin exit", 129.0, -0.2, 90.0]]:
		for level: int in [2, 5]:
			var opp := _opp_on(level)
			var s: float = c[1]
			var pose := track.pose_at(s, c[2])
			pose.basis = pose.basis.rotated(Vector3.UP, deg_to_rad(c[3]))
			car.teleport(pose)
			var start_s := s - 22.0
			opp.car.teleport(track.pose_at(start_s))
			opp.car.linear_velocity = -track.pose_at(start_s).basis.z * 6.0
			opp.driver.restart()
			opp.to_grid_tracking_only()
			var t := 0.0
			var passed := -1.0
			var hits := 0
			var touching := false
			var resets0 := opp.resets
			var hint := start_s
			while t < 20.0:
				await _frames(1)
				t += 1.0 / 120.0
				hint = track.progress(opp.car.global_position, hint)
				var ahead := wrapf(hint - s, -track.length * 0.5, track.length * 0.5)
				if passed < 0.0 and ahead > 4.0:
					passed = t
				var now_touch := car.get_colliding_bodies().has(opp.car)
				if now_touch and not touching:
					hits += 1
				touching = now_touch
				if passed >= 0.0 and t > passed + 3.0:
					break
			log_line("  %s, level %d: %s; contacts %d; resets %d; player's car moved %.2f" % [c[0], level,
				("past after %.1f s" % passed) if passed >= 0.0 else "NOT PAST in 20 s", hits, opp.resets - resets0, car.global_position.distance_to(pose.origin)])
			_m["opp block %s L%d" % [c[0].get_slice(",", 0), level]] = ("past %.1f s" % passed) if passed >= 0.0 else "NOT PAST"
			_opp_off()
			await _frames(5)


## A scripted hit: the opponent is shoved sideways off the road (and spun) at
## speed; how long until it is back on the road making progress?
func _test_opp_shove() -> void:
	log_line("\n[opponent shoved] a sideways hit at speed on the main straight and in the S")
	for c: Array in [["main straight", 14.0], ["the S", 64.0]]:
		var opp := _opp_on(3)
		_park_player()
		var s0: float = c[1] - 10.0
		opp.car.teleport(track.pose_at(s0))
		opp.car.linear_velocity = -track.pose_at(s0).basis.z * 8.0
		opp.driver.restart()
		await _frames(120)
		var oc: Car = opp.car
		var side := oc.global_basis.x
		oc.apply_central_impulse(side * oc.mass * 7.0)
		oc.apply_torque_impulse(Vector3.UP * oc.mass * 0.25)
		var t := 0.0
		var max_lat := 0.0
		var back := -1.0
		var resets0 := opp.resets
		var hint := track.progress(oc.global_position)
		while t < 15.0:
			await _frames(1)
			t += 1.0 / 120.0
			hint = track.progress(oc.global_position, hint)
			var lat := absf(track.lateral_offset(oc.global_position, hint))
			max_lat = maxf(max_lat, lat)
			var along := oc.linear_velocity.dot(track.tangent_at(hint))
			if back < 0.0 and max_lat > 1.0 and lat < 1.2 and along > 3.0 and absf(oc.slip_angle) < deg_to_rad(15.0):
				back = t
				break
		log_line("  %s: knocked %.2f off the centre line; back on the road and going (> 3 u/s, slip < 15 deg) after %s; resets %d" % [
			c[0], max_lat, ("%.1f s" % back) if back >= 0.0 else "NOT in 15 s", opp.resets - resets0])
		_m["opp shove " + c[0]] = ("rejoined %.1f s" % back) if back >= 0.0 else "NOT REJOINED"
		car.freeze = false
		_opp_off()
		await _frames(5)


## Both cars off the grid together at full throttle (the player driven by the
## plain autopilot) through the first corners.
func _test_opp_start() -> void:
	log_line("\n[opponent start] both cars from the grid, the player on the autopilot, 12 s")
	for level: int in [3, 5]:
		var opp := _opp_on(level)
		await _frames(30)
		var ap := Autopilot.new()
		ap.car = car
		ap.track = track
		add_child(ap)
		var hits := 0
		var touching := false
		var off := Vector2.ZERO
		var slip := Vector2.ZERO
		for i in 120 * 12:
			await _frames(1)
			var now_touch := car.get_colliding_bodies().has(opp.car)
			if now_touch and not touching:
				hits += 1
			touching = now_touch
			if car.wheels_grounded > car.wheels_on_road:
				off.x += 1.0 / 120.0
			if opp.car.wheels_grounded > opp.car.wheels_on_road:
				off.y += 1.0 / 120.0
			slip = Vector2(maxf(slip.x, absf(car.slip_angle)), maxf(slip.y, absf(opp.car.slip_angle)))
		_stop_line(ap)
		var st := opp.standing()
		log_line("  level %d: contacts %d; off-road player %.1f s, opponent %.1f s; peak slip player %.0f, opponent %.0f deg; after 12 s %s; resets %d" % [
			level, hits, off.x, off.y, rad_to_deg(slip.x), rad_to_deg(slip.y), opp.status_text(), opp.resets])
		_m["opp start L%d" % level] = "contacts %d, %s, resets %d" % [hits, opp.status_text(), opp.resets]
		_opp_off()
		_inputs(0.0, 0.0, 1.0, false)
		await _frames(30)


## Off / on / level changes through the pause menu, repeatedly: the car and its
## sound come and go cleanly, and the setting is saved and read back.
func _test_opp_menu() -> void:
	log_line("\n[opponent menu] off / on / level changes from the pause menu")
	var au: AudioDirector = game.audio
	au.settings_path = out_dir.path_join("audio_settings.cfg")
	var menu: PauseMenu = game.pause_menu
	_opp_off()
	await _frames(10)
	var base_nodes := get_tree().get_node_count()
	var base_players := get_tree().root.find_children("*", "AudioStreamPlayer", true, false).size()
	var row := PackedStringArray()
	for level: int in [3, 5, 0, 2, 0, 4, 1, 0]:
		menu.open(false)
		await get_tree().process_frame
		menu.selected = menu.items.find(PauseMenu.Item.OPPONENT)
		var steps := level - au.opponent_level
		for i in absi(steps):
			_key(KEY_RIGHT if steps > 0 else KEY_LEFT, true)
			_key(KEY_RIGHT if steps > 0 else KEY_LEFT, false)
			await get_tree().process_frame
		menu.close()
		await _frames(30)
		var on: bool = game.opponent != null
		row.append("%s:%s%s" % ["off" if level == 0 else str(level), "on" if on else "off",
			"" if (on == (level > 0)) and (not on or game.opponent.level == level) else " WRONG"])
	await _frames(10)
	var nodes := get_tree().get_node_count()
	var players := get_tree().root.find_children("*", "AudioStreamPlayer", true, false).size()
	var fresh := AudioDirector.new()
	fresh.settings_path = au.settings_path
	fresh.load_settings()
	au.set_opponent_level(3)
	au.save_settings()
	var fresh2 := AudioDirector.new()
	fresh2.settings_path = au.settings_path
	fresh2.load_settings()
	log_line("  sequence %s; after it (off): nodes %d (before %d), sound players %d (before %d); saved level read back %d, after setting 3: %d" % [
		" ".join(row), nodes, base_nodes, players, base_players, fresh.opponent_level, fresh2.opponent_level])
	_m["opp menu"] = "%s; nodes %d/%d, players %d/%d" % [" ".join(row), nodes, base_nodes, players, base_players]
	fresh.free()
	fresh2.free()
	_opp_off()


## Screenshots of the two cars: the grid (iso and chase), side by side in a
## corner, the chase view behind the red car, in lighting mode 1.
func _test_opp_shots() -> void:
	log_line("\n[opponent shots]")
	var opp := _opp_on(3)
	await _frames(20)
	await _shot("90_opp_grid_iso.png")
	game.set_chase_view(true)
	await _frames(5)
	await _shot("91_opp_grid_chase.png")
	game.set_chase_view(false)
	# Side by side through the R6 corner.
	var s0 := 30.0
	car.teleport(track.pose_at(s0, -0.6))
	opp.car.teleport(track.pose_at(s0, 0.6))
	for c: Car in [car, opp.car]:
		c.linear_velocity = -track.pose_at(s0).basis.z * 7.0
	opp.driver.restart()
	var ap := Autopilot.new()
	ap.car = car
	ap.track = track
	ap.line_offset = -0.6
	ap.max_speed = 7.5
	add_child(ap)
	await _frames(150)
	camera.snap_to_target()
	await _shot("92_opp_side_by_side_iso.png")
	game.chase.target = opp.car
	game.set_chase_view(true)
	await _frames(60)
	await _shot("93_opp_chase_behind_red.png")
	await _shot("93_opp_chase_behind_red_raw.png", true)
	game.chase.target = car
	game.set_chase_view(false)
	_stop_line(ap)
	_opp_off()



## The start lights: the cars are held until lights out (throttle blips rev
## the engine, nothing moves, no lap time), the hold varies between starts, the
## opponent reacts by level, both cars get through the first corner, pause and
## cancel behave, nothing is left behind. Screenshots of the lamps.
func _test_countdown() -> void:
	log_line("\n[countdown] start lights")
	game.countdown_enabled = true
	var rs: RaceStart = game.race_start
	_opp_off()
	await _frames(10)
	var base_nodes := get_tree().get_node_count()
	var base_players := get_tree().root.find_children("*", "AudioStreamPlayer", true, false).size()
	var holds := PackedStringArray()
	for level: int in [0, 1, 5]:
		var opp: Opponent = null
		if level > 0:
			opp = _opp_on(level)
		else:
			game.reset_to_grid()
		var p0 := car.global_position
		var o0 := opp.car.global_position if opp != null else Vector3.ZERO
		var moved := 0.0
		var max_rpm := 0.0
		var lap_early := false
		var nitro_used := false
		var frames := 0
		while rs.counting and frames < 120 * 10:
			_inputs(0.6, 1.0 if (frames / 30) % 2 == 0 else 0.0, 0.0, false) # blips, steering
			car.nitro_input = true
			await get_tree().process_frame
			frames += 1
			if not rs.counting:
				break # the lights went out during this frame
			moved = maxf(moved, car.global_position.distance_to(p0))
			if opp != null:
				moved = maxf(moved, opp.car.global_position.distance_to(o0))
			max_rpm = maxf(max_rpm, game.car_audio.rpm)
			lap_early = lap_early or game.laps.started
			nitro_used = nitro_used or car.nitro_level > 0.0
		car.nitro_input = false
		holds.append("%.2f" % rs.hold)
		# After lights out: the opponent's reaction, then the first corner with the
		# player on the autopilot.
		var lap_at_go := "lap %d, %.2f s" % [game.laps.lap, game.laps.current]
		var react := -1.0
		var moving := -1.0
		var t := 0.0
		var ap := Autopilot.new()
		ap.car = car
		ap.track = track
		add_child(ap)
		var hits := 0
		var touching := false
		while t < 9.0:
			await _frames(1)
			t += 1.0 / 120.0
			if opp != null and t < 1.0 and int(t * 120.0) % 6 == 0:
				_trace.append("%.2f:thr%.2f cap%.1f bias%.2f v%.2f" % [t, opp.car.throttle_input, opp.driver.speed_cap, opp.driver.lateral_bias, opp.car.forward_speed])
			if opp != null and react < 0.0 and opp.car.throttle_input > 0.5:
				react = t
			if opp != null and moving < 0.0 and opp.car.forward_speed > 0.3:
				moving = t
			if opp != null:
				var now := car.get_colliding_bodies().has(opp.car)
				if now and not touching:
					hits += 1
				touching = now
		var lap_after := "lap %d, %.2f s, checkpoints %d" % [game.laps.lap, game.laps.current, game.laps.next_checkpoint]
		_stop_line(ap)
		if OS.get_cmdline_user_args().has("--cdtrace"):
			log_line("    trace: " + " ".join(_trace))
		_trace.clear()
		log_line("  %s: held for %.2f s (hold after the fifth lamp %.2f s); moved before lights out %.4f; engine revved to %.0f rpm with the car held; nitro used before lights out %s; lap timer started early %s, at lights out %s, 9 s later %s; %s" % [
			"solo" if level == 0 else "opponent level %d" % level, rs.t, rs.hold, moved, max_rpm, nitro_used, lap_early, lap_at_go, lap_after,
			("opponent on the throttle after %.2f s (planned %.2f), moving (> 0.3 u/s) after %.2f s; first 9 s: contacts %d, %s, opponent resets %d" % [react, rs.opponent_delay, moving, hits, opp.status_text(), opp.resets]) if opp != null else "no opponent"])
		_m["countdown " + ("solo" if level == 0 else "L%d" % level)] = "moved %.4f, rpm %.0f, early lap %s%s" % [moved, max_rpm, lap_early,
			(", reaction %.2f s, contacts %d" % [react, hits]) if opp != null else ""]
		_inputs(0.0, 0.0, 1.0, false)
		await _frames(30)
	log_line("  holds over the starts: %s s" % ", ".join(holds))

	# Pause mid-countdown: the lights stop, and carry on after.
	_opp_off()
	game.reset_to_grid()
	while rs.t < 2.2:
		await get_tree().process_frame
	var t_pause := rs.t
	game.pause_menu.open(false)
	for i in 60:
		await get_tree().process_frame
	var t_paused := rs.t
	game.pause_menu.close()
	for i in 30:
		await get_tree().process_frame
	log_line("  pause at %.2f s: after a second paused %.2f s (still counting %s); half a second after resuming %.2f s" % [t_pause, t_paused, rs.counting, rs.t])
	_m["countdown pause"] = "%.2f -> %.2f paused -> %.2f" % [t_pause, t_paused, rs.t]
	# Cancel mid-countdown (what returning to the reel does).
	rs.cancel()
	await _frames(10)
	var beeping := rs._beep.playing or rs._go.playing
	log_line("  cancel: counting %s, car held %s, nitro allowed %s, a beep still playing %s" % [rs.counting, car.freeze, car.nitro_enabled, beeping])
	_m["countdown cancel"] = "counting %s, held %s, beeping %s" % [rs.counting, car.freeze, beeping]

	# Screenshots: two lamps, five lamps, just after lights out; iso and chase.
	var opp := _opp_on(3)
	for chase: bool in [false, true]:
		game.set_chase_view(chase)
		game.reset_to_grid()
		var view := "chase" if chase else "iso"
		while rs._lit < 2:
			await get_tree().process_frame
		await _shot("95_lights_2_%s.png" % view)
		while rs._lit < 5:
			await get_tree().process_frame
		await _shot("96_lights_5_%s.png" % view)
		while rs.counting:
			await get_tree().process_frame
		await _shot("97_lights_out_%s.png" % view)
	# Readability: the Retina 20 px grid and lighting mode 2 (night), three lamps.
	var px0 := renderer.settings.glyph_px
	var mode0: int = game.lighting.mode
	for v: Array in [["retina_iso", 20, mode0, false], ["retina_chase", 20, mode0, true], ["night_iso", px0, 1, false], ["night_chase", px0, 1, true]]:
		if renderer.settings.glyph_px != v[1]:
			renderer.settings.glyph_px = v[1]
			await renderer.atlas_ready
		game.lighting.set_mode(v[2])
		game.set_chase_view(v[3])
		game.reset_to_grid()
		while rs._lit < 3:
			await get_tree().process_frame
		await _shot("98_lights_3_%s.png" % v[0])
	game.lighting.set_mode(mode0)
	game.set_chase_view(false)
	_opp_off()
	game.countdown_enabled = false
	rs.cancel()
	await _frames(20)
	var nodes := get_tree().get_node_count()
	var players := get_tree().root.find_children("*", "AudioStreamPlayer", true, false).size()
	log_line("  afterwards: nodes %d (before %d), sound players %d (before %d)" % [nodes, base_nodes, players, base_players])
	_m["countdown leftovers"] = "nodes %d/%d, players %d/%d" % [nodes, base_nodes, players, base_players]



# --- iso framing: road ahead per aspect ------------------------------------------

## Window shapes (same height, so the same vertical extent at a given zoom).
const VIEW_ASPECTS: Array = [["16x9", Vector2i(1600, 900)], ["16x10", Vector2i(1440, 900)], ["21x9", Vector2i(2100, 900)]]


## World units visible ahead of the car along its heading (ground plane), and
## behind it, in the iso camera; and the car's size on screen (pixels, the
## projected box of its body).
func _view_numbers() -> Dictionary:
	var cam := renderer.scene_viewport.get_camera_3d()
	var rect := Rect2(Vector2.ZERO, Vector2(renderer.scene_viewport.size))
	var xf := car.get_global_transform_interpolated()
	var p := xf.origin
	var h := -xf.basis.z
	h.y = 0.0
	h = h.normalized()
	var out := {}
	for sgn: float in [1.0, -1.0]:
		var lo := 0.0
		var hi := 80.0
		for i in 30:
			var mid := (lo + hi) * 0.5
			if rect.has_point(cam.unproject_position(p + h * mid * sgn)):
				lo = mid
			else:
				hi = mid
		out["ahead" if sgn > 0.0 else "behind"] = lo
	var bb := Rect2(cam.unproject_position(p), Vector2.ZERO)
	for c in 8:
		var local := Vector3(0.25 * (1 if c & 1 else -1), 0.35 * float((c >> 1) & 1), 0.44 * (1 if c & 4 else -1))
		bb = bb.expand(cam.unproject_position(xf * local))
	# In cells: the output is scaled from the scene viewport to the output size.
	var k := float(renderer.output_size.y) / rect.size.y
	out["car_px"] = bb.size * k
	out["car_cells"] = Vector2(bb.size.x * k / renderer.pitch.x, bb.size.y * k / renderer.pitch.y)
	out["size"] = cam.size
	return out


func _test_view_ahead() -> void:
	log_line("\n[view_ahead] iso camera: road visible ahead of the car along its heading (world units)")
	game.set_chase_view(false)
	var keep_choice: int = game.audio.zoom_setting
	# Before = the fixed 1.00 step (exactly the old camera); after = AUTO.
	for setting: Array in [["before", 2], ["after", 0]]:
		game.audio.zoom_setting = setting[1]
		camera.zoom_choice = setting[1]
		for asp: Array in VIEW_ASPECTS:
			renderer.fixed_output_size = asp[1]
			await _frames(3)
			var line := PackedStringArray()
			# Standing: on the grid (the main straight, a 30 deg diagonal on screen)
			# and on the bridge deck (heading straight across the screen).
			var stand := {}
			for st: Array in [["grid", -1.0], ["deck", 3.0]]:
				if st[1] < 0.0:
					game.reset_to_grid()
				else:
					_place_on_track(st[1])
					await _frames(2)
					camera.snap_to_target()
				await _frames(240)
				stand[st[0]] = _view_numbers()
				if setting[0] == "after" or st[0] == "grid":
					await _shot("view_%s_%s_%s_stand.png" % [setting[0], asp[0], st[0]])
			var sv: Dictionary = stand.grid
			line.append("standing: grid %.1f, deck %.1f ahead (size %.2f, car %.1f x %.1f cells)" % [sv.ahead, stand.deck.ahead, sv.size, sv.car_cells.x, sv.car_cells.y])
			# Flat out: down the diagonal (straight up/down the screen) and over the
			# deck (straight across).
			for run: Array in [["diagonal", 60.0, 92.0, 97.0], ["deck", 131.0, 0.5, 5.0]]:
				_place_on_track(run[1], 0.0, 9.0)
				await _frames(2)
				camera.snap_to_target()
				var ap := _start_line(13.0)
				var acc := {"ahead": 0.0, "n": 0, "speed": 0.0, "size": 0.0}
				var shot_done := false
				var seen := false
				for i in 120 * 8:
					await _frames(1)
					var sp := fposmod(game.laps.progress, track.length)
					if sp > run[2] and sp < run[3]:
						seen = true
						var v := _view_numbers()
						acc.ahead += v.ahead
						acc.size += v.size
						acc.speed += car.forward_speed
						acc.n += 1
						if not shot_done and sp > (run[2] + run[3]) * 0.5:
							shot_done = true
							await _shot("view_%s_%s_%s_speed.png" % [setting[0], asp[0], run[0]])
					elif seen:
						break
				_stop_line(ap)
				var n: int = maxi(acc.n, 1)
				line.append("%s at %.1f u/s: %.1f ahead (size %.2f)" % [run[0], acc.speed / n, acc.ahead / n, acc.size / n])
				_m["view %s %s %s" % [setting[0], asp[0], run[0]]] = "%.1f ahead" % (acc.ahead / n)
				_inputs(0.0, 0.0, 1.0, false)
				await _frames(60)
			log_line("  %s %s: %s" % [setting[0], asp[0], "; ".join(line)])
			_m["view %s %s standing" % [setting[0], asp[0]]] = "grid %.1f, deck %.1f ahead, car %.1f x %.1f cells" % [sv.ahead, stand.deck.ahead, sv.car_cells.x, sv.car_cells.y]
	# Zoom smoothness: one autopilot lap at 16:9 in AUTO; the ortho size every
	# frame: range, fastest change, and how often the change reverses direction.
	game.audio.zoom_setting = 0
	camera.zoom_choice = 0
	renderer.fixed_output_size = SHOT_SIZE
	game.reset_to_grid()
	await _frames(60)
	var ap2 := Autopilot.new()
	ap2.car = car
	ap2.track = track
	add_child(ap2)
	var prev := camera.size
	var prev_d := 0.0
	var lo := INF
	var hi := -INF
	var max_rate := 0.0
	var flips := 0
	for i in 120 * 18:
		await get_tree().process_frame
		var d := camera.size - prev
		prev = camera.size
		lo = minf(lo, camera.size)
		hi = maxf(hi, camera.size)
		var dt := get_process_delta_time()
		if dt > 0.0:
			max_rate = maxf(max_rate, absf(d) / dt / camera.size)
		if absf(d) > 1e-5:
			if prev_d != 0.0 and signf(d) != signf(prev_d):
				flips += 1
			prev_d = d
	_stop_line(ap2)
	log_line("  AUTO over a lap at 16:9: ortho size %.2f..%.2f, fastest change %.1f%%/s, direction reversals %d" % [lo, hi, max_rate * 100.0, flips])
	_m["view auto lap"] = "size %.2f..%.2f, max %.1f%%/s, reversals %d" % [lo, hi, max_rate * 100.0, flips]
	game.audio.zoom_setting = keep_choice
	camera.zoom_choice = keep_choice
	renderer.fixed_output_size = SHOT_SIZE
	await _frames(5)


# --- night lighting ---------------------------------------------------------------

## Night (lighting 2) where visibility matters, iso and chase: on the grid, mid
## straight at speed, braking for the hairpin, the R6 after the jump, under the
## bridge, the opponent ahead and behind. --nightmode=<n> shoots another mode
## at the same places (for comparison).
func _test_night() -> void:
	log_line("\n[night] lighting 2 where visibility matters")
	var l: Lighting = game.lighting
	var m0 := l.mode
	var mode := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nightmode="):
			mode = arg.trim_prefix("--nightmode=").to_int() - 1
	l.set_mode(mode)
	var tag := String(Lighting.MODES[mode].name).replace(" ", "-")
	# Where the diagonal passes under the bridge deck.
	var under := 90.0
	var best := INF
	for i in 200:
		var su := 80.0 + i * 0.1
		var d := Vector2(track.point_at(su).x - track.point_at(0.0).x, track.point_at(su).z - track.point_at(0.0).z).length()
		if d < best:
			best = d
			under = su
	# [name, s, speed, opponent offset (0 = none)]
	var poses: Array = [["grid", -1.0, 0.0, 0.0], ["straight", 10.0, 11.0, 0.0], ["hairpin_approach", 104.0, 10.0, 0.0],
		["r6_after_jump", 30.5, 10.5, 0.0], ["under_bridge", under - 2.0, 9.0, 0.0],
		["opp_ahead", 60.5, 9.0, 3.5], ["opp_behind", 60.5, 9.0, -3.0]]
	for p: Array in poses:
		for chase: bool in [false, true]:
			var view := "chase" if chase else "iso"
			var opp: Opponent = null
			if p[3] != 0.0:
				opp = _opp_on(3)
			else:
				_opp_off()
			game.set_chase_view(chase)
			if p[1] < 0.0:
				game.reset_to_grid()
				await _frames(30)
			else:
				_place_on_track(p[1], 0.0, p[2])
				await _frames(2)
				camera.snap_to_target()
				game.chase.snap_to_target()
				if opp != null:
					var xf := track.pose_at(p[1] + p[3], 0.35)
					opp.car.teleport(xf)
					opp.car.linear_velocity = -xf.basis.z * p[2]
					opp.to_grid_tracking_only()
				var ap := _start_line(p[2])
				await _frames(36)
				if p[0] == "hairpin_approach":
					ap.enabled = false
					_inputs(0.0, 0.0, 1.0, false) # braking: brake lights
					await _frames(12)
					ap.queue_free()
				else:
					_stop_line(ap)
			await _shot("90_%s_%s_%s.png" % [tag, p[0], view])
			if OS.get_cmdline_user_args().has("--dtraw"):
				await _shot("90_%s_%s_%s_raw.png" % [tag, p[0], view], true)
	_opp_off()
	game.set_chase_view(false)
	l.set_mode(m0)
	_inputs(0.0, 0.0, 1.0, false)
	await _frames(30)
	log_line("  shots 90_%s_<place>_<view>.png" % tag)



## The minimised debug HUD (its legend) and the open HUD with the start lights,
## as the window shows them (the HUD is not part of the renderer's output), at
## 16:9 and 21:9 and the default and Retina glyph sizes.
func _test_hud_shots() -> void:
	log_line("\n[hud shots] legend and open HUD over the start lights (window captures)")
	var rs: RaceStart = game.race_start
	var win0 := get_window().size
	var px0 := renderer.settings.glyph_px
	renderer.fixed_output_size = Vector2i.ZERO
	game.countdown_enabled = true
	_opp_on(3)
	for w: Array in [["16x9", Vector2i(1600, 900)], ["21x9", Vector2i(2100, 900)]]:
		get_window().size = w[1]
		for g: Array in [["default", px0], ["retina", 20]]:
			if renderer.settings.glyph_px != g[1]:
				renderer.settings.glyph_px = g[1]
				await renderer.atlas_ready
			game.controls.hud.visible = false
			game.reset_to_grid()
			while rs._lit < 3:
				await get_tree().process_frame
			await _window_shot("92_legend_%s_%s.png" % [w[0], g[0]])
			if w[0] == "16x9" and g[0] == "default":
				game.set_chase_view(true)
				await _window_shot("92_legend_16x9_default_chase.png")
				game.set_chase_view(false)
			game.controls.hud.visible = true
			for i in 3:
				await get_tree().process_frame
			await _window_shot("93_hud_open_%s_%s.png" % [w[0], g[0]])
			var hr: Rect2 = game.controls.panel_rect()
			log_line("  %s %s: window %s, legend at %s size %s; HUD panel %s" % [w[0], g[0], get_window().size,
				game.controls.legend.position, game.controls.legend.size, hr])
			game.controls.hud.visible = false
			while rs.counting:
				await get_tree().process_frame
			await _frames(240)
			await _window_shot("94_racing_%s_%s.png" % [w[0], g[0]])
	game.countdown_enabled = false
	rs.cancel()
	_opp_off()
	if renderer.settings.glyph_px != px0:
		renderer.settings.glyph_px = px0
		await renderer.atlas_ready
	get_window().size = win0
	renderer.fixed_output_size = SHOT_SIZE
	await _frames(10)


func _window_shot(file: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
