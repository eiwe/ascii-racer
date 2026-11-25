## Driving surfaces as data. A track's road faces carry a surface id (the
## collider's `surface` meta); the car looks it up per wheel.
##
## "road" (asphalt) and "ground" (off the circuit) keep the car's own tunables
## (Car.grip_road, grip_ground, offroad_drag, peak_slip_deg, slide_grip) so the
## existing handling is unchanged; the others are factors on the asphalt values:
##   grip        x Car.grip_road
##   peak_slip   x Car.peak_slip_deg (a larger angle = the tyre lets go later and softer)
##   slide_grip  x Car.slide_grip (grip left once sliding)
##   drag        extra drag per unit of speed, like Car.offroad_drag (0 = none)
##   on_road     counts as the circuit (lap logic, resets, drift surface)
##   colour      road colour in the generator
##   sound       tyre sound family ("asphalt", "dirt", "snow")
class_name Surfaces
extends RefCounted

const ROAD: StringName = &"road"
const GROUND: StringName = &"ground"

const TABLE: Dictionary = {
	&"road": {"grip": 1.0, "peak_slip": 1.0, "slide_grip": 1.0, "drag": 0.0, "on_road": true, "colour": Color("5a6179"), "sound": "asphalt"},
	&"ground": {"grip": 0.58 / 1.3, "peak_slip": 1.0, "slide_grip": 1.0, "drag": 1.1, "on_road": false, "colour": Color(0.075, 0.09, 0.08), "sound": "asphalt"},
	# Loose dirt: less grip, the tyre lets go early but gently and keeps a fair
	# share once sliding (easy to drift), a little drag.
	&"dirt": {"grip": 0.78, "peak_slip": 1.6, "slide_grip": 1.08, "drag": 0.12, "on_road": true, "colour": Color("8a6a4a"), "sound": "dirt"},
	# Packed snow: low grip, long slides, almost no drag.
	&"snow": {"grip": 0.55, "peak_slip": 1.9, "slide_grip": 1.1, "drag": 0.05, "on_road": true, "colour": Color("dfe6f0"), "sound": "snow"},
}


static func get_value(id: StringName, key: String, fallback: Variant = null) -> Variant:
	var e: Dictionary = TABLE.get(id, TABLE[ROAD])
	return e.get(key, fallback)


## True for the two surfaces the car's own tunables describe exactly.
static func is_classic(id: StringName) -> bool:
	return id == ROAD or id == GROUND
