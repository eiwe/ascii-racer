## Handling presets for a Car: named sets of its exported tunables, switchable
## while driving, plus a `custom` preset saved to (and loaded from)
## user://car_tuning.cfg. `balanced` is the car's own exported defaults; the
## other presets are overrides on top of it. Also lists the curated parameters
## the tuning panel shows.
class_name CarTuning
extends RefCounted

const SAVE_PATH: String = "user://car_tuning.cfg"
const CUSTOM: String = "custom"

## Preset name -> overrides of `balanced`, in cycle order. Measured with the
## drive test (`--preset=<name>`); see the [summary] block it prints.
const OVERRIDES: Dictionary = {
	"balanced": {},
	# Loose and playful: throttle and lift-off step the rear out (power_oversteer,
	# engine_braking, a slightly higher CoM), slides keep most of their grip and
	# the assist catches them. The handbrake drift holds the most angle and loses
	# the least speed.
	"drift": {
		"power_oversteer": 0.6,
		"engine_braking": 3.0,
		"com_height": 0.07,
		"launch_accel": 10.0,
		"slide_grip": 0.9,
		"peak_slip_deg": 8.0,
		"counter_steer_assist": 0.9,
		"max_steer_high_deg": 7.5,
		"handbrake_rear_grip": 0.65,
		"handbrake_decel": 2.0,
		"drift_angle_deg": 30.0,
		"drift_angle_steer_deg": 10.0,
		"drift_angle_max_deg": 50.0,
		"drift_rotate_rate": 9.0,
		"drift_carve": 0.6,
		"drift_speed_loss": 0.3,
	},
	# Precise and planted: more grip at both ends with a sharp peak (grip falls
	# away past it, so sliding is slow), quicker steering and yaw, stiff springs,
	# little assist, strong brakes, less body motion. The handbrake drift is
	# shallow, snaps in quickly and carves tight.
	"grip": {
		"front_grip": 1.15,
		"rear_grip": 1.15,
		"peak_slip_deg": 5.5,
		"slide_grip": 0.7,
		"counter_steer_assist": 0.15,
		"steer_speed": 10.0,
		"steer_return_speed": 14.0,
		"stick_steer_speed": 60.0,
		"max_steer_high_deg": 9.0,
		"inertia_per_mass": Vector3(0.07, 0.075, 0.035),
		"spring_hz": 4.0,
		"damping_ratio": 0.8,
		"brake_decel": 13.0,
		"handbrake_rear_grip": 0.5,
		"drift_angle_deg": 18.0,
		"drift_angle_steer_deg": 6.0,
		"drift_angle_max_deg": 35.0,
		"drift_rotate_rate": 11.0,
		"drift_carve": 0.6,
		"drift_grip": 1.5,
		"drift_speed_loss": 0.6,
		"lean_deg_per_g": 4.0,
		"pitch_deg_per_g": 2.0,
	},
	# Weighty with momentum: more yaw and pitch inertia, slow steering, soft
	# springs and a higher CoM (visible lean and dive), less grip and weaker
	# brakes, slow to accelerate but coasts further: wide lines, lift early. The
	# handbrake drift needs more speed, swings in slowly and carves wider.
	"heavy": {
		"inertia_per_mass": Vector3(0.09, 0.12, 0.035),
		"com_height": 0.08,
		"steer_speed": 3.5,
		"steer_return_speed": 5.0,
		"stick_steer_speed": 10.0,
		"max_steer_low_deg": 23.0,
		"max_steer_high_deg": 6.0,
		"top_speed": 9.0,
		"launch_accel": 6.0,
		"brake_decel": 7.5,
		"rolling_decel": 0.5,
		"grip_road": 1.2,
		"slide_grip": 0.75,
		"spring_hz": 2.2,
		"damping_ratio": 0.45,
		"lean_deg_per_g": 10.0,
		"pitch_deg_per_g": 9.0,
		"max_lean_deg": 10.0,
		"drift_min_speed": 3.0,
		"drift_angle_deg": 22.0,
		"drift_rotate_rate": 4.5,
		"drift_carve": 0.45,
		"drift_grip": 1.25,
		"drift_speed_loss": 0.5,
	},
}

## The tuning panel's entries: [group, property path, label, step]. A path may
## name a vector component ("inertia_per_mass:y").
const PANEL: Array = [
	["Steering", "max_steer_high_deg", "lock fast (deg)", 0.5],
	["Steering", "steer_speed", "key steer rate", 0.5],
	["Steering", "counter_steer_assist", "c-steer assist", 0.05],
	["Tyres", "grip_road", "road grip", 0.05],
	["Tyres", "front_grip", "front grip", 0.05],
	["Tyres", "rear_grip", "rear grip", 0.05],
	["Tyres", "peak_slip_deg", "peak slip (deg)", 0.5],
	["Tyres", "slide_grip", "slide grip", 0.05],
	["Tyres", "power_oversteer", "power oversteer", 0.05],
	["Engine", "launch_accel", "launch accel", 0.5],
	["Engine", "top_speed", "top speed", 0.25],
	["Engine", "brake_decel", "brake decel", 0.5],
	["Engine", "engine_braking", "engine braking", 0.25],
	["Chassis", "com_height", "CoM height", 0.01],
	["Chassis", "inertia_per_mass:y", "yaw inertia", 0.005],
	["Chassis", "spring_hz", "spring (Hz)", 0.1],
	["Drift", "drift_angle_deg", "drift angle", 1.0],
	["Drift", "drift_carve", "drift carve", 0.05],
	["Drift", "drift_speed_loss", "drift speed loss", 0.1],
	["Drift", "drift_boost_accel", "drift boost", 0.25],
	["Visual", "lean_deg_per_g", "lean / g", 0.5],
]

var car: Car
## Preset name -> {property: value} with every tunable.
var presets: Dictionary = {}
var names: PackedStringArray = []
var current: String = "balanced"
var save_path: String = SAVE_PATH


func _init(c: Car, path: String = SAVE_PATH) -> void:
	car = c
	save_path = path
	var base := capture()
	for n: String in OVERRIDES:
		presets[n] = base.merged(OVERRIDES[n], true)
		names.append(n)
	load_custom()


## Names of the car's exported tunables.
func tunables() -> PackedStringArray:
	var out := PackedStringArray()
	for p in car.get_property_list():
		var u: int = p.usage
		if u & PROPERTY_USAGE_SCRIPT_VARIABLE and u & PROPERTY_USAGE_EDITOR:
			out.append(p.name)
	return out


## The car's current values of every tunable.
func capture() -> Dictionary:
	var d := {}
	for n in tunables():
		d[n] = car.get(n)
	return d


func select(preset: String) -> void:
	if not presets.has(preset):
		push_warning("no handling preset '%s'" % preset)
		return
	current = preset
	car.apply_tuning(presets[preset])


## Selects the next (step 1) or previous (-1) preset and returns its name.
func cycle(step: int) -> String:
	var i := names.find(current)
	select(names[posmod(i + step, names.size())])
	return current


## The current preset's value for a panel path.
func preset_value(path: String) -> Variant:
	var parts := path.split(":")
	var v: Variant = presets[current][parts[0]]
	if parts.size() > 1:
		v = v[parts[1]]
	return v


## Whether the car's value for `path` differs from the current preset's.
func is_modified(path: String) -> bool:
	return not is_equal_approx(float(car.get_indexed(path)), float(preset_value(path)))


func modified_count() -> int:
	var n := 0
	for e: Array in PANEL:
		if is_modified(e[1]):
			n += 1
	return n


## Sets one panel value on the car (clamped to the export range).
func set_value(path: String, value: float) -> void:
	var r := value_range(path)
	car.set_indexed(path, clampf(value, r.x, r.y))
	car.refresh_tuning()


func reset_value(path: String) -> void:
	set_value(path, float(preset_value(path)))


## [min, max] from the property's export range (vector components: 0.01..0.5).
func value_range(path: String) -> Vector2:
	if path.contains(":"):
		return Vector2(0.01, 0.5)
	for p in car.get_property_list():
		if p.name == path and p.hint == PROPERTY_HINT_RANGE:
			var h: PackedStringArray = (p.hint_string as String).split(",")
			return Vector2(h[0].to_float(), h[1].to_float())
	return Vector2(-INF, INF)


## Saves the car's current values as the `custom` preset (and selects it).
## Returns the absolute path written, or "" on failure.
func save_custom() -> String:
	var cfg := ConfigFile.new()
	var values := capture()
	for k: String in values:
		cfg.set_value(CUSTOM, k, values[k])
	cfg.set_value("meta", "based_on", current)
	var err := cfg.save(save_path)
	if err != OK:
		push_error("could not save tuning to %s (%s)" % [save_path, error_string(err)])
		return ""
	presets[CUSTOM] = values
	if not names.has(CUSTOM):
		names.append(CUSTOM)
	current = CUSTOM
	var abs_path := ProjectSettings.globalize_path(save_path)
	print("saved handling preset '%s' to %s" % [CUSTOM, abs_path])
	return abs_path


## Loads `custom` from the save file if there is one. Unknown keys are ignored;
## missing ones keep the balanced value.
func load_custom() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK or not cfg.has_section(CUSTOM):
		push_warning("could not read tuning from %s" % save_path)
		return false
	var values: Dictionary = (presets["balanced"] as Dictionary).duplicate()
	for k in cfg.get_section_keys(CUSTOM):
		if values.has(k):
			values[k] = cfg.get_value(CUSTOM, k)
	presets[CUSTOM] = values
	if not names.has(CUSTOM):
		names.append(CUSTOM)
	return true
