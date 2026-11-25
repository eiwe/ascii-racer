## The circuits as data; Track builds whichever is selected.
##
## Keys of a definition:
##   id, name                 stable id (saved settings) and the name shown
##   layout                   turtle walk (see Track): ["S", length] / ["A", radius, degrees];
##                            exactly two straights of length -1 are solved for closure
##   start_heading_deg, origin   where the walk starts
##   elevation                ranges of raised road: {from, to, rise: [y0, y1], shape:
##                            "ease" | "kick" | "flat", deck (bridge span), jump (part of a jump),
##                            clear_speed / roll_speed (the drivers' take-off speeds; without them
##                            they take the jump flat out)}
##   bank                     ranges of banked road: {from, to, deg (outside of the turn up), ease_in, ease_out}
##   surface                  the road's base surface id (Surfaces)
##   patches                  {from, to, surface, u: [u0, u1] (across, - = left; optional = full width)}
##   start_s                  start line (distance along the centre line)
##   checkpoints              fractions of the lap that must be passed in order
##   kerbs                    true = kerbs beside flat road (else plain edges)
##   theme                    scenery: {trees, tree_seed, cones, gate, ground, kerb_colours}
##   time_tweaks              per time of day ("morning" | "noon" | "night"): lighting
##                            overrides of the mode's table keys (sun_az, sun_energy, ...), see Lighting.tweaks
##   description              one line for the level select
##   tests                    drive-test places (optional): block [[name, s, u, yaw]], shove [[name, s]]
class_name Tracks
extends RefCounted

const FIGURE_EIGHT: Dictionary = {
	"id": "figure_eight",
	"name": "FIGURE EIGHT",
	"description": "asphalt, a bridge and a table-top jump",
	"layout": [
		["S", 6.0], # bridge deck and ramp down
		["A", 8.0, 45.0], # sweeper onto the main straight (still on the ramp)
		["S", 22.0], # main straight: start line, jump
		["A", 6.0, 90.0],
		["S", 9.25],
		["A", 4.0, 90.0], # tightest right-hander
		["S", 3.0],
		["A", 14.0, -20.0], # flat-out S
		["A", 14.0, 20.0],
		["S", 2.0],
		["A", 12.0, 45.0], # fast sweeper onto the diagonal
		["S", 15.33], # diagonal: passes under the bridge
		["S", -1.0],
		["A", 8.0, -45.0],
		["S", 8.0],
		["A", 5.0, -180.0], # hairpin
		["S", -1.0],
		["A", 8.0, -45.0], # sweeper onto the ramp up
		["S", 6.0],
	],
	"start_heading_deg": -45.0,
	"origin": Vector2(0.0, 12.0),
	"elevation": [
		# Bridge over the crossing at s = 0: deck road 1.6 above the ground road
		# (underside 1.4 above it). 13-long cosine ramps: steepest 11 deg.
		{"from": -16.5, "to": -3.5, "rise": [0.0, 1.6], "shape": "ease"},
		{"from": -3.5, "to": 3.5, "rise": [1.6, 1.6], "shape": "flat", "deck": true},
		{"from": 3.5, "to": 16.5, "rise": [1.6, 0.0], "shape": "ease"},
		# Table-top jump on the main straight: kicker, table, landing.
		{"from": 21.0, "to": 24.0, "rise": [0.0, 0.3], "shape": "kick", "jump": true},
		{"from": 24.0, "to": 26.0, "rise": [0.3, 0.3], "shape": "flat", "jump": true},
		{"from": 26.0, "to": 33.5, "rise": [0.3, 0.0], "shape": "ease", "jump": true},
	],
	"bank": [],
	"surface": &"road",
	"patches": [],
	"start_s": 19.5,
	"checkpoints": [0.3, 0.65],
	"kerbs": true,
	"theme": {"trees": true, "tree_seed": 7, "cones": true, "gate": true},
	"time_tweaks": {},
}

## Dust Bowl: a dirt arena, a different lap from Figure Eight's road circuit.
## A lopsided "P" (about 169 long): the front straight with a table-top, banked
## turn 1 (velodrome-style, 26 deg, r 9, half a lap of turning), the back
## straight with a double, a tight flat left hairpin where the dirt makes you
## slide, a short straight into banked turn 2 (24 deg, r 8), the long straight
## with a step-down, and a flat right onto the front straight again. Banked
## turns have a tall tyre wall outside and an apron inside; dirt has no kerbs,
## so berms and a darker edge band mark the edges (Track's arena style).
const DUST_BOWL: Dictionary = {
	"id": "dust_bowl",
	"name": "DUST BOWL",
	"description": "dirt arena, banked turns and jumps",
	"layout": [
		["S", -1.0], # front straight: start, table-top (solved: 39.5)
		["A", 9.0, 180.0], # banked turn 1 (s 39.5 .. 67.8)
		["S", 26.0], # back straight: the double
		["A", 3.5, -90.0], # tight flat left (s 93.8 .. 99.3)
		["S", -1.0], # short straight (solved: 10)
		["A", 8.0, 180.0], # banked turn 2 (s 109.3 .. 134.4)
		["S", 25.5], # long straight: the step-down
		["A", 6.0, 90.0], # flat right onto the front straight (s 159.9 .. 169.3)
	],
	"start_heading_deg": 0.0,
	"origin": Vector2(-20.0, -20.0),
	# Jumps sit well clear of the banked turns: banked road is lifted (its low
	# edge stays on the ground), and the lift eases in and out over 8, gently
	# enough that even nitro speed does not take off where it ends.
	"elevation": [
		# Table-top: kicker, a 5-long table, a landing slope; 11 of run-out to turn 1.
		{"from": 11.0, "to": 14.0, "rise": [0.0, 0.45], "shape": "kick", "jump": true, "clear_speed": 11.0, "roll_speed": 6.0},
		{"from": 14.0, "to": 19.0, "rise": [0.45, 0.45], "shape": "flat", "jump": true, "clear_speed": 11.0, "roll_speed": 6.0},
		{"from": 19.0, "to": 25.0, "rise": [0.45, 0.0], "shape": "ease", "jump": true, "clear_speed": 11.0, "roll_speed": 6.0},
		# Double: kicker, a dip, a second hump with a short face and a long back
		# (the landing); clear it from the first lip, or roll both.
		{"from": 73.5, "to": 76.0, "rise": [0.0, 0.4], "shape": "kick", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0},
		{"from": 76.0, "to": 78.0, "rise": [0.4, 0.0], "shape": "ease", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0},
		{"from": 79.0, "to": 80.5, "rise": [0.0, 0.4], "shape": "ease", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0},
		{"from": 80.5, "to": 85.0, "rise": [0.4, 0.0], "shape": "ease", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0},
		# Step-down: up onto a plateau, a step down to a lower table, a long
		# landing slope.
		{"from": 139.5, "to": 144.5, "rise": [0.0, 0.6], "shape": "ease", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0},
		{"from": 144.5, "to": 146.5, "rise": [0.6, 0.6], "shape": "flat", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0},
		{"from": 146.5, "to": 147.7, "rise": [0.6, 0.25], "shape": "ease", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0},
		{"from": 147.7, "to": 148.5, "rise": [0.25, 0.25], "shape": "flat", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0},
		{"from": 148.5, "to": 153.5, "rise": [0.25, 0.0], "shape": "ease", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0},
	],
	"bank": [
		{"from": 36.5, "to": 70.8, "deg": 26.0, "ease_in": 8.0, "ease_out": 8.0},
		{"from": 106.5, "to": 135.5, "deg": 24.0, "ease_in": 8.0, "ease_out": 8.0},
	],
	"surface": &"dirt",
	"patches": [],
	"start_s": 5.0,
	"checkpoints": [0.3, 0.65],
	# Drive-test places: the player's car parked in the way, and side hits.
	"tests": {
		"block": [["on the line, front straight", 31.0, 0.0, 0.0], ["across the hairpin exit", 101.0, -0.2, 90.0]],
		"shove": [["front straight", 30.0], ["banked turn 1", 52.0]],
	},
	"kerbs": false,
	"theme": {"arena": true, "trees": true, "tree_seed": 11, "tree_keep": 0.07, "cones": false, "gate": true, "markers": true},
	# Greener, darker surround so the ochre track stands out; a dustier,
	# warmer morning sun from across the back straight.
	"time_tweaks": {
		"morning": {"sun_az": 70.0, "sun_color": Color(1.0, 0.78, 0.58), "ground": Color(0.1, 0.15, 0.08), "track": 1.55},
		"noon": {"ground": Color(0.08, 0.13, 0.06), "track": 1.2},
		"night": {"ground": Color(0.07, 0.1, 0.09), "track": 1.8},
	},
}

const ALL: Array[Dictionary] = [FIGURE_EIGHT, DUST_BOWL]
const DEFAULT_ID: String = "figure_eight"


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for d in ALL:
		out.append(d.id)
	return out


static func get_def(id: String) -> Dictionary:
	for d in ALL:
		if d.id == id:
			return d
	return FIGURE_EIGHT
