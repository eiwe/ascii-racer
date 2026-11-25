## Everything the car sounds like, driven by its state each physics step.
##
## Engine: recorded loops at known engine speeds (SoundTable engine_loop_*:
## `rpm` each), all playing, each pitched to the simulated engine speed and
## crossfaded between its neighbours on a log-rpm scale (equal power), so one
## loop hands over to the next without a level or pitch step. The simulated
## engine speed comes from a virtual automatic gearbox that exists only for
## the sound (the car has no gears): revs climb through each gear, drop at the
## shift with a short throttle cut, and free-rev with the clutch in at a
## standstill. Volume and brightness (a low-pass on the Engine bus) follow the
## load: on the throttle louder and brighter than coasting.
##
## Tyres: a squeal loop that follows how far past the grip limit the tyres are
## and the speed, and a skid loop for the handbrake drift; silent in the air and
## off the road. Chassis: a landing thump scaled by the vertical speed at
## touchdown, a knock for kerbs and bumps (suspension spikes), impacts by the
## velocity change (solid things and cones sound different). Nitro: a burst at
## ignition and a sustained hiss while burning.
class_name CarAudio
extends Node

## Virtual gearbox: top speed of each gear (u/s at SHIFT_UP_RPM), idle, shift
## points, redline, and the free rev with the clutch in at a standstill.
const GEAR_TOP: PackedFloat32Array = [3.0, 5.2, 7.6, 10.0, 13.5]
const IDLE_RPM: float = 850.0
const SHIFT_UP_RPM: float = 4300.0
const SHIFT_DOWN_RPM: float = 2500.0
## Coasting downshifts lower (no rev flare at every gear while slowing).
const SHIFT_DOWN_COAST_RPM: float = 1600.0
const REDLINE_RPM: float = 4700.0
const CLUTCH_RPM: float = 3400.0 ## extra revs at full throttle standing still
const CLUTCH_SPEED: float = 2.5 ## below this the clutch slips (u/s)
const SHIFT_TIME: float = 0.16 ## throttle cut at an upshift (s)
## Engine speed response (s): toward the wheels' revs, and free-revving.
const RPM_TAU: float = 0.05
const FREE_REV_TAU: float = 0.18
## Engine level: coasting vs full load (dB), plus this much from idle to redline.
const ENGINE_COAST_DB: float = -8.0
const ENGINE_LOAD_DB: float = 0.0
const ENGINE_RPM_DB: float = 4.0
## Brightness: Engine bus low-pass cutoff, coasting at idle -> full load at redline.
const ENGINE_LP: Vector2 = Vector2(1200.0, 9000.0)
## Pitch-scale limits per loop (beyond them the loop is faded out).
const PITCH_LIMIT: Vector2 = Vector2(0.55, 1.9)
## Tyres: the squeal is an event, not a constant: it starts only well past the
## grip limit (tyre usage, 1 = at the limit: 1.25 = slip angle 25 % past the
## grip peak, or the friction circle overrun that much by wheelspin or a locked
## brake) and is full this much further on; a body slip angle beyond
## SLIP_FROM_DEG adds to it. A gate with hysteresis keeps it from chattering:
## it opens above SQUEAL_ON and closes below SQUEAL_OFF.
const SQUEAL_FROM: float = 1.25
const SQUEAL_SPAN: float = 0.6
const SLIP_FROM_DEG: float = 12.0
const SLIP_SPAN_DEG: float = 20.0
const SQUEAL_ON: float = 0.12
const SQUEAL_OFF: float = 0.04
const TYRE_ATTACK: float = 0.06
const TYRE_RELEASE: float = 0.18
## Chassis.
const LAND_MIN_AIR: float = 0.12 ## s in the air before a touchdown counts as a landing
const LAND_FULL_VY: float = 4.0 ## u/s downward = full thump
const KERB_SPIKE: float = 0.22 ## suspension compression jump in one step
const KERB_GAP: float = 0.09
const IMPACT_FULL_DV: float = 4.0

var car: Car
var table: SoundTable
## Told the squeal level each step (it ducks the race music); may be null.
var director: AudioDirector
## Secondary car (the opponent): engine only, on the Opponent bus, at
## SECONDARY_DB and fading with its distance from `listener` (the player's car).
## Contact sounds between the cars are the player's CarAudio's.
var secondary: bool = false
var listener: Node3D
const SECONDARY_DB: float = -9.0
## Distance (units) at which a secondary car is 6 dB quieter than up close.
const SECONDARY_REF: float = 3.0
## False silences everything (fades out); the reel and the game both drive it.
var active: bool = true

## Read-outs (tests, HUD).
var rpm: float = IDLE_RPM
var gear: int = 1
var load: float = 0.0
var squeal: float = 0.0
var skid: float = 0.0
var engine_weights: PackedFloat32Array = []
var engine_pitches: PackedFloat32Array = []
var events: Array = [] ## recent one-shots: [time s, role, volume 0..1]
var shifts: int = 0

var _engine: Array[AudioStreamPlayer] = []
var _engine_rpm: PackedFloat32Array = []
var _engine_gain: PackedFloat32Array = []
var _squeal: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _nitro: AudioStreamPlayer
var _shots: Dictionary = {} ## role -> AudioStreamPlayer
var _shift_t: float = 0.0
var _was_air: float = 0.0
var _since_landing: float = 1.0
var _squeal_gate: bool = false
var _prev_vy: float = 0.0
var _prev_v: Vector3 = Vector3.ZERO
var _prev_comp: float = 0.0
var _kerb_t: float = 0.0
var _ignitions: int = 0
var _pending_hits: Array = []
var _time: float = 0.0
var _fade: float = 0.0 ## 0..1 master fade of all loops (active)
var _engine_bus: int = -1


func _ready() -> void:
	_engine_bus = AudioServer.get_bus_index("Engine") if not secondary else -1
	for l: Array in table.engine_loops():
		var p := _loop_player(l[1], &"Opponent" if secondary else &"Engine")
		_engine.append(p)
		_engine_rpm.append(l[0])
		_engine_gain.append(table.gain_db(l[1]))
	engine_weights.resize(_engine.size())
	engine_pitches.resize(_engine.size())
	if secondary:
		return
	_squeal = _loop_player("tyre_squeal", &"Tyres")
	_skid = _loop_player("tyre_skid", &"Tyres")
	_nitro = _loop_player("nitro_sustain", &"Effects")
	for role: String in ["land", "kerb", "impact_solid", "impact_cone", "nitro_ignite"]:
		var s := table.stream(role)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = &"Effects"
		p.max_polyphony = 4
		add_child(p)
		_shots[role] = p
	car.contact_monitor = true
	car.max_contacts_reported = 4
	car.body_entered.connect(_on_body_entered)


func _loop_player(role: String, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = table.stream(role)
	p.volume_db = -80.0
	add_child(p)
	return p


func _on_body_entered(body: Node) -> void:
	if body is CollisionObject3D and (body as CollisionObject3D).collision_layer & Track.LAYER_SURFACE:
		return # the road and ground (landings are handled from the wheels)
	_pending_hits.append(body)


## Puts the engine at idle in first and silences the tyres (a reset or a new game).
func reset() -> void:
	rpm = IDLE_RPM
	gear = 1
	squeal = 0.0
	skid = 0.0
	_shift_t = 0.0
	_was_air = 0.0
	_prev_v = car.linear_velocity
	_prev_comp = car.suspension_compression()
	_pending_hits.clear()


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_time += delta
	_fade = move_toward(_fade, 1.0 if active else 0.0, delta / 0.25)
	_update_engine(delta)
	if secondary:
		_apply()
		return
	_update_tyres(delta)
	_update_chassis(delta)
	_update_nitro()
	_apply()
	if director != null:
		director.squeal_level = maxf(squeal, skid) * _fade


func _update_engine(delta: float) -> void:
	var v := absf(car.forward_speed)
	var thr := car.throttle_input if car.forward_speed > -0.5 else car.brake_input
	var grounded := car.wheels_grounded > 0
	# Gear from the road speed, with hysteresis between the shift points.
	var wheel_rpm := v / GEAR_TOP[gear - 1] * SHIFT_UP_RPM
	if wheel_rpm > SHIFT_UP_RPM and gear < GEAR_TOP.size() and grounded:
		gear += 1
		shifts += 1
		_shift_t = SHIFT_TIME
	elif wheel_rpm < lerpf(SHIFT_DOWN_COAST_RPM, SHIFT_DOWN_RPM, thr) and gear > 1:
		gear -= 1
	wheel_rpm = v / GEAR_TOP[gear - 1] * SHIFT_UP_RPM
	_shift_t = maxf(_shift_t - delta, 0.0)
	load = 0.0 if _shift_t > 0.0 else thr
	var target := wheel_rpm
	var tau := RPM_TAU
	var clutch := clampf(1.0 - v / CLUTCH_SPEED, 0.0, 1.0) if gear == 1 else 0.0
	if clutch > 0.0:
		target = maxf(target, IDLE_RPM + load * CLUTCH_RPM * clutch)
		tau = lerpf(RPM_TAU, FREE_REV_TAU, clutch)
	if not grounded:
		target = wheel_rpm * (1.0 + 0.2 * load) # wheels spin free in the air
		tau = FREE_REV_TAU
	var spin := 0.0
	for i in [2, 3]:
		spin = maxf(spin, car.wheel_usage[i] - 1.0)
	if load > 0.3 and spin > 0.05:
		target *= 1.0 + minf(spin * 0.4, 0.2) # wheelspin flare
	target *= 1.0 + 0.06 * car.nitro_level
	target = clampf(maxf(target, IDLE_RPM), IDLE_RPM, REDLINE_RPM)
	rpm += (target - rpm) * (1.0 - exp(-delta / tau))
	# Loop weights: equal-power crossfade between neighbours on log rpm.
	var n := _engine.size()
	for i in n:
		engine_weights[i] = 0.0
		engine_pitches[i] = rpm / _engine_rpm[i]
	if n == 0:
		return
	var lr := log(rpm)
	if rpm <= _engine_rpm[0]:
		engine_weights[0] = 1.0
	elif rpm >= _engine_rpm[n - 1]:
		engine_weights[n - 1] = 1.0
	else:
		for i in n - 1:
			if rpm >= _engine_rpm[i] and rpm < _engine_rpm[i + 1]:
				var t := (lr - log(_engine_rpm[i])) / (log(_engine_rpm[i + 1]) - log(_engine_rpm[i]))
				engine_weights[i] = cos(t * PI * 0.5)
				engine_weights[i + 1] = sin(t * PI * 0.5)


func _update_tyres(delta: float) -> void:
	var speed := car.linear_velocity.length()
	var road := float(car.wheels_on_road) / 4.0
	var usage := 0.0
	for i in 4:
		usage = maxf(usage, car.wheel_usage[i])
	var slide := clampf((usage - SQUEAL_FROM) / SQUEAL_SPAN, 0.0, 1.0)
	var slip := clampf((absf(rad_to_deg(car.slip_angle)) - SLIP_FROM_DEG) / SLIP_SPAN_DEG, 0.0, 1.0)
	var drifting := car.drift_state == Car.Drift.DRIFT
	var want_squeal := maxf(slide, slip) * clampf(speed / 3.0, 0.0, 1.0) * road
	var want_skid := 0.0
	if drifting:
		want_skid = clampf(absf(car.drift_angle) / deg_to_rad(20.0), 0.3, 1.0) * clampf(speed / 3.0, 0.0, 1.0) * road
		want_squeal *= 0.35
	if want_squeal > SQUEAL_ON:
		_squeal_gate = true
	elif want_squeal < SQUEAL_OFF:
		_squeal_gate = false
	if not _squeal_gate:
		want_squeal = 0.0
	if car.wheels_grounded == 0 or _since_landing < 0.2:
		want_squeal = 0.0 # in the air, and the jolt of a landing (the thump covers it)
		want_skid = 0.0 if car.wheels_grounded == 0 else want_skid
	squeal = _follow(squeal, want_squeal, delta)
	skid = _follow(skid, want_skid, delta)


static func _follow(cur: float, want: float, delta: float) -> float:
	var tau := TYRE_ATTACK if want > cur else TYRE_RELEASE
	return cur + (want - cur) * (1.0 - exp(-delta / tau))


func _update_chassis(delta: float) -> void:
	var v := car.linear_velocity
	var comp := car.suspension_compression()
	var grounded := car.wheels_grounded > 0
	# Landing: touchdown after a while in the air, scaled by the drop speed.
	if grounded and _was_air >= LAND_MIN_AIR:
		var s := clampf(maxf(-_prev_vy - 0.3, 0.0) / LAND_FULL_VY, 0.0, 1.0)
		s = maxf(s, comp * 0.6)
		_shot("land", 0.25 + 0.75 * s, 1.0 - 0.12 * s)
		_since_landing = 0.0
		_kerb_t = KERB_GAP * 2.0
	_was_air = 0.0 if grounded else _was_air + delta
	_since_landing += delta
	_prev_vy = v.y
	# Kerbs and bumps: a sudden jump in suspension compression.
	_kerb_t = maxf(_kerb_t - delta, 0.0)
	if grounded and comp - _prev_comp > KERB_SPIKE and _kerb_t <= 0.0 and v.length() > 1.0:
		_shot("kerb", clampf((comp - _prev_comp) * 2.0, 0.3, 1.0) * clampf(v.length() / 6.0, 0.4, 1.0), randf_range(0.92, 1.08))
		_kerb_t = KERB_GAP
	_prev_comp = comp
	# Impacts: what was hit since the last step, by the velocity change.
	var dv := (v - _prev_v).length()
	for body: Node in _pending_hits:
		if body is Car:
			_shot("impact_solid", clampf(dv / IMPACT_FULL_DV, 0.3, 1.0), randf_range(0.9, 1.0)) # the other car
		elif body is RigidBody3D:
			_shot("impact_cone", clampf(v.length() / 6.0, 0.3, 1.0), randf_range(0.9, 1.15))
		else:
			_shot("impact_solid", clampf(dv / IMPACT_FULL_DV, 0.25, 1.0), randf_range(0.95, 1.05))
	_pending_hits.clear()
	_prev_v = v


func _update_nitro() -> void:
	if car.nitro_ignitions != _ignitions:
		_ignitions = car.nitro_ignitions
		_shot("nitro_ignite", 1.0, 1.0)


func _shot(role: String, vol: float, pitch: float) -> void:
	events.append([_time, role, vol])
	if events.size() > 64:
		events.pop_front()
	if not active or not _shots.has(role):
		return
	var p: AudioStreamPlayer = _shots[role]
	p.volume_db = linear_to_db(maxf(vol, 1e-4)) + table.gain_db(role)
	p.pitch_scale = pitch
	p.play()


func _apply() -> void:
	var f := _fade
	var rpm_frac := clampf((rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM), 0.0, 1.0)
	var engine_db := lerpf(ENGINE_COAST_DB, ENGINE_LOAD_DB, load) + ENGINE_RPM_DB * rpm_frac
	if secondary:
		var d := car.global_position.distance_to(listener.global_position) if is_instance_valid(listener) else 0.0
		engine_db += SECONDARY_DB - 20.0 * log(1.0 + d / SECONDARY_REF) / log(10.0) * 1.0
	for i in _engine.size():
		var p := _engine[i]
		var pitch := engine_pitches[i]
		var w := engine_weights[i]
		# Fade a loop out beyond its moderate pitch range (the neighbour covers it).
		if pitch < PITCH_LIMIT.x:
			w *= clampf(pitch / PITCH_LIMIT.x, 0.0, 1.0)
		_set_loop(p, w * f, clampf(pitch, 0.3, 2.5), engine_db + _engine_gain[i])
	if _engine_bus >= 0 and AudioServer.get_bus_effect_count(_engine_bus) > 0:
		var lp := AudioServer.get_bus_effect(_engine_bus, 0) as AudioEffectLowPassFilter
		lp.cutoff_hz = lerpf(ENGINE_LP.x, ENGINE_LP.y, clampf(0.65 * load + 0.35 * rpm_frac, 0.0, 1.0))
	if secondary:
		return
	var speed := car.linear_velocity.length()
	_set_loop(_squeal, squeal * f, 0.9 + 0.18 * squeal + 0.012 * speed, table.gain_db("tyre_squeal"))
	_set_loop(_skid, skid * f, 0.85 + 0.025 * speed, table.gain_db("tyre_skid"))
	_set_loop(_nitro, car.nitro_level * f, 0.95 + 0.1 * car.nitro_level, table.gain_db("nitro_sustain"))


## A loop at `amount` (0..1, perceptual) and pitch: started when it becomes
## audible, stopped when silent (so nothing runs at -80 dB for nothing).
static func _set_loop(p: AudioStreamPlayer, amount: float, pitch: float, gain_db: float) -> void:
	if p.stream == null:
		return
	# Loops keep running when silent (stopping and restarting them leaves
	# playbacks fading out in the audio server, which then outlive a quit).
	p.volume_db = linear_to_db(maxf(amount, 1e-5)) + gain_db if amount > 0.002 else -80.0
	p.pitch_scale = pitch
	if not p.playing:
		p.play()

