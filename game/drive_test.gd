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
	for t: String in ["spawn", "accel_brake", "turns", "handbrake", "drift", "feel", "offroad", "kerbs", "tree", "cones", "jump", "bridge", "reset_bridge", "keys",
			"pad", "panel", "rumble", "lap", "drift_lap", "drift_shot", "panel_shot", "chase", "top_down", "grid_snap"]:
		if only == "" or t in only.split(","):
			await call("_test_" + t)
	log_line("\n[summary] preset %s" % game.tuning.current)
	for k: String in _m:
		log_line("  %s %s" % [k, _m[k]])
	log_line("drivetest done in %.1f s real time" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(out_dir.path_join("results.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\n")
	f.close()
	get_tree().quit()


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
	var m0 := renderer.settings.method
	_key(KEY_2, true)
	_key(KEY_2, false)
	var m1 := renderer.settings.method
	_key(KEY_3, true)
	_key(KEY_3, false)
	var z0 := camera.size
	_key(KEY_COMMA, true)
	_key(KEY_COMMA, false)
	var z1 := camera.size
	_key(KEY_PERIOD, true)
	_key(KEY_PERIOD, false)
	log_line("  G: snap %s -> %s; 2: method %s -> %s (3 restores %s); ,: zoom %.1f -> %.1f (. restores %.1f)" % [
		snap0, camera.snap_to_grid, AsciiSettings.METHOD_NAMES[m0], AsciiSettings.METHOD_NAMES[m1],
		renderer.settings.method_name(), z0, z1, camera.size])
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
			var a0 := ia.get_pixel(x * 3, y)
			var b0 := ib.get_pixel(xb * 3, yb)
			var a2 := ia.get_pixel(x * 3 + 2, y)
			var b2 := ib.get_pixel(xb * 3 + 2, yb)
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
	for b: JoyButton in [JOY_BUTTON_Y, JOY_BUTTON_BACK]:
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
	await _tap(JOY_BUTTON_START)
	res.append("Start: open %s, arrows drive %s" % [panel.is_open, car.arrow_keys_drive])
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
	await _tap(JOY_BUTTON_START)
	res.append("Start: open %s, arrows drive %s" % [panel.is_open, car.arrow_keys_drive])
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
	log_line("\n[jump] table-top on the main straight (kicker s 22.5..25.5 to 0.6 high, table to 27, landing to 31.5)")
	for frac: float in [1.0, 0.5, 0.25]:
		var v := 7.7 * frac
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
			if land >= 0 and i - land < 60:
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
		log_line("  %3.0f%% (%.1f u/s, %.2f at take-off): air %.2f s over %.2f u, highest %.2f above the road below, tilt in the air max %.1f deg; after landing tilt max %.1f deg vs the road, %d bounce(s); upright %s, speed %.2f" % [
			frac * 100.0, v, v_take, air_t, dist, max_h, air_tilt, land_tilt, bounce, car.is_upright(), _speed()])
		_m["jump_%d" % roundi(frac * 100.0)] = "air %.2f s, %.2f u, peak %.2f, landing tilt %.1f deg, bounces %d, upright %s" % [
			air_t, dist, max_h, land_tilt, bounce, car.is_upright()]
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
			cut = cut or track.deck_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if not shot:
				shot = true
				await _shot("24_under_bridge_cutaway.png")
		if _speed() < v_prev - 0.5:
			hits += 1
		v_prev = _speed()
		if prog > 106.0 and prog < 120.0:
			break
	_stop_line(ap)
	await _frames(2)
	log_line("  passed under: clearance above the car roof %.2f, deck cut away while under %s, sudden speed losses %d; ends at s %.1f, speed %.2f, deck shown again %s" % [
		min_gap, cut, hits, prog, _speed(), track.deck_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON])
	_m["bridge_under"] = "clearance %.2f, cutaway %s, speed losses %d" % [min_gap, cut, hits]
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
## distance fade, the five render methods in perspective, fps.
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

	# Every render method in perspective.
	var m0 := renderer.settings.method
	for m in AsciiSettings.METHOD_NAMES.size():
		renderer.settings.method = m as AsciiSettings.Method
		await _shot("38_chase_method_%d_%s.png" % [m + 1, AsciiSettings.METHOD_NAMES[m]])
	renderer.settings.method = m0

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
