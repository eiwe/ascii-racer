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
##   rear_grip   x Car.rear_grip (below 1: the rear lets go first, the car rotates)
##   power_oversteer  x Car.power_oversteer (throttle loosens the rear more)
##   coast       x Car.rolling_decel and engine_braking off the throttle
##   brake       x Car.brake_decel (below 1: longer stops)
##   drift_loss  x Car.drift_speed_loss (below 1: longer drifts)
##   bright      drawn without the track's darkening tint (snow must outshine the ground)
##   dust        colour of the dust a sliding or spinning wheel kicks up (none: no dust)
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
	# Loose dirt: less grip, and the tyre lets go at a larger slip angle on a
	# gentler slope and keeps most of its grip once sliding, so the car drifts
	# readily, holds a slide on the throttle and comes back without snapping.
	# Less rear grip and more power oversteer turn the planted asphalt car into
	# one that rotates; more drag off the throttle; drifts lose less speed. No
	# drag on the throttle: top speed and nitro as on asphalt.
	&"dirt": {"grip": 0.78, "peak_slip": 1.6, "slide_grip": 1.1, "drag": 0.0, "rear_grip": 0.95, "power_oversteer": 1.35,
		"coast": 1.35, "brake": 0.8, "drift_loss": 0.65, "on_road": true, "colour": Color("b07a40"), "sound": "dirt", "dust": Color("c8a070")},
	# Packed snow: far less grip than dirt, a broad, forgiving peak, slides
	# that hold and steer, long stops; the rear is not looser than the front and
	# lifting off does little, so the car runs wide rather than spinning; a
	# little wheelspin at launch.
	&"snow": {"grip": 0.57, "peak_slip": 2.0, "slide_grip": 1.12, "drag": 0.0, "rear_grip": 1.0, "power_oversteer": 1.0,
		"coast": 0.9, "brake": 0.62, "drift_loss": 0.75, "on_road": true, "colour": Color("dfe6f0"), "sound": "snow", "dust": Color("eef3fa"), "bright": true},
}


static func get_value(id: StringName, key: String, fallback: Variant = null) -> Variant:
	var e: Dictionary = TABLE.get(id, TABLE[ROAD])
	return e.get(key, fallback)


## True for the two surfaces the car's own tunables describe exactly.
static func is_classic(id: StringName) -> bool:
	return id == ROAD or id == GROUND
