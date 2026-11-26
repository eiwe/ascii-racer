## The AI opponent: a red speedster driven by an OpponentDriver at a difficulty
## level (1-5). Physics are the player's: the same Car script with the same
## `balanced` values and the player car's wheel layout (the speedster's body
## and wheels are only drawn where its model has them), so the pace is honest.
## Also tracks the race: distance covered by both cars since the grid, the
## player's position and the gap in seconds (time since the leader passed the
## trailing car's current point), for the HUD.
##
## Created by the game when the opponent is on and a race is being played;
## freeing this node removes the car, its driver and its sound.
class_name Opponent
extends Node

const CAR_SCENE: PackedScene = preload("res://game/car.tscn")
const MODEL: PackedScene = preload("res://assets/kenney_toy-car-kit/vehicle-speedster.glb")
const PAINT: Shader = preload("res://game/shaders/opponent_paint.gdshader")
## The player car's (vehicle-racer) wheel rest positions: fl, fr, bl, br.
const PHYSICS_WHEELS: Array[Vector3] = [Vector3(-0.1875, 0.125, -0.25), Vector3(0.1875, 0.125, -0.25),
	Vector3(-0.1875, 0.125, 0.25), Vector3(0.1875, 0.125, 0.25)]
## The speedster's wheels sit 0.0625 further back: the model is moved forward
## by that so the wheelbase lines up (nothing is stretched).
const MODEL_OFFSET: Vector3 = Vector3(0.0, -0.15, -0.0625)
## Grid: the two cars side by side, this far either side of the centre line.
const GRID_LATERAL: float = 0.6
## Race tracking: a checkpoint every this many units of distance.
const CHECKPOINT: float = 0.5
## Recovery: put back this far behind its last progress if the player is close.
const RESET_CLEARANCE: float = 2.5

var game: Node
var level: int = 3
var car: Car
var driver: OpponentDriver
var sound: CarAudio
var resets: int = 0

var _track: Track
var _d: Vector2 = Vector2.ZERO ## distance covered since the grid: (player, opponent)
var _prev: Vector2 = Vector2(-1.0, -1.0) ## last progress of each
var _times: Array[Dictionary] = [{}, {}] ## checkpoint index -> time, per car
var _t: float = 0.0


## The red car (not yet in the tree).
static func make_car() -> Car:
	var c := CAR_SCENE.instantiate() as Car
	c.name = "Opponent"
	var lean := c.get_node("Lean")
	var old := lean.get_node("Model")
	lean.remove_child(old)
	old.free()
	var m := MODEL.instantiate() as Node3D
	m.name = "Model"
	m.position = MODEL_OFFSET
	lean.add_child(m)
	_paint(m)
	c.physics_wheel_rest = PHYSICS_WHEELS.duplicate()
	return c


## Repaints the body (not the wheels) red; see opponent_paint.gdshader.
static func _paint(model: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("wheel"):
			continue
		var base := mi.get_active_material(0) as StandardMaterial3D
		if base == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = PAINT
		mat.set_shader_parameter("albedo_tex", base.albedo_texture)
		mat.set_shader_parameter("albedo", base.albedo_color)
		mat.set_shader_parameter("roughness", base.roughness)
		mat.set_shader_parameter("specular", base.metallic_specular)
		mi.material_override = mat


func _ready() -> void:
	var world: Node3D = game.world
	_track = game.track
	car = make_car()
	world.add_child(car)
	car.apply_tuning(game.tuning.presets["balanced"])
	car.player_input = false
	car.nitro_enabled = true
	# Solid contact between the two cars.
	car.collision_mask |= Track.LAYER_CAR
	game.car.collision_mask |= Track.LAYER_CAR
	driver = OpponentDriver.make(level)
	driver.car = car
	driver.track = _track
	driver.other = game.car
	add_child(driver)
	driver.reset_requested.connect(_recover)
	sound = CarAudio.new()
	sound.car = car
	sound.table = game.audio.table
	sound.secondary = true
	sound.listener = game.car
	add_child(sound)
	var r: AsciiRenderer = game.renderer
	if r.shadow_hatch:
		r._apply_shadow_hatch() # light twins for the new car (hatched lighting)
	to_grid()


func _exit_tree() -> void:
	if is_instance_valid(game.car):
		game.car.collision_mask &= ~Track.LAYER_CAR
	if is_instance_valid(car):
		car.queue_free()


func set_level(l: int) -> void:
	level = clampi(l, 1, 5)
	driver.apply_level(level)


## Both cars side by side on the grid at rest; the race tracking restarts.
func to_grid() -> void:
	var s: float = _track.start_s - float(game.world.GRID_BACK)
	game.car.teleport(_track.pose_at(s, -GRID_LATERAL))
	car.teleport(_track.pose_at(s, GRID_LATERAL))
	car.refill_nitro()
	driver.restart()
	sound.reset()
	_d = Vector2.ZERO
	_prev = Vector2(-1.0, -1.0)
	_times = [{}, {}]
	_t = 0.0


## Restarts the race tracking from where the cars are now (tests).
func to_grid_tracking_only() -> void:
	_d = Vector2.ZERO
	_prev = Vector2(-1.0, -1.0)
	_times = [{}, {}]
	_t = 0.0


## Stuck, upside down or lost: back on the road at its last progress (a little
## further back if the player is right there).
func _recover() -> void:
	resets += 1
	var s: float = maxf(driver.progress, 0.0)
	var pose := _track.pose_at(s)
	if pose.origin.distance_to(game.car.global_position) < RESET_CLEARANCE:
		pose = _track.pose_at(s - RESET_CLEARANCE * 1.5)
	car.teleport(pose)
	driver.restart()


func _physics_process(delta: float) -> void:
	_t += delta
	var cars: Array[Car] = [game.car, car]
	for i in 2:
		var p := _track.progress(cars[i].global_position, _prev[i])
		if _prev[i] >= 0.0:
			_d[i] += wrapf(p - _prev[i], -_track.length * 0.5, _track.length * 0.5)
		_prev[i] = p
		var k := floori(_d[i] / CHECKPOINT)
		if not _times[i].has(k):
			_times[i][k] = _t


## Player position (1 or 2) and the gap in seconds (+ = the player leads).
func standing() -> Vector2:
	var lead := 0 if _d.x >= _d.y - 0.3 else 1 # level (e.g. on the grid): the player leads
	var trail := 1 - lead
	var k := floori(_d[trail] / CHECKPOINT)
	var gap: float = _t - float(_times[lead].get(k, _t))
	return Vector2(1 if lead == 0 else 2, gap if lead == 0 else -gap)


func status_text() -> String:
	var s := standing()
	return "P%d %+.1f" % [int(s.x), s.y]
