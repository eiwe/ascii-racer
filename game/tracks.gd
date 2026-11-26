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
##                            they take the jump flat out), roll_level (levels up to it roll the jump)}
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
	# Turned so the isometric camera (looking from +x +z, 45 deg in the turtle's
	# heading convention) sits in the one quadrant neither banked turn's outside
	# faces: it looks down into both bowls instead of at the back of the walls.
	"start_heading_deg": 180.0,
	"origin": Vector2(20.0, 20.0),
	# Jumps sit well clear of the banked turns: banked road is lifted (its low
	# edge stays on the ground), and the lift eases in and out over 8, gently
	# enough that even nitro speed does not take off where it ends.
	"elevation": [
		# Table-top: kicker, a 5-long table, a landing slope; 11 of run-out to turn 1.
		{"from": 11.0, "to": 14.0, "rise": [0.0, 0.45], "shape": "kick", "jump": true, "clear_speed": 11.0, "roll_speed": 6.0, "roll_level": 0},
		{"from": 14.0, "to": 19.0, "rise": [0.45, 0.45], "shape": "flat", "jump": true, "clear_speed": 11.0, "roll_speed": 6.0, "roll_level": 0},
		{"from": 19.0, "to": 25.0, "rise": [0.45, 0.0], "shape": "ease", "jump": true, "clear_speed": 11.0, "roll_speed": 6.0, "roll_level": 0},
		# Double: kicker, a dip, a second hump with a short face and a long back
		# (the landing); clear it from the first lip, or roll both.
		{"from": 73.5, "to": 76.0, "rise": [0.0, 0.4], "shape": "kick", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0, "roll_level": 2},
		{"from": 76.0, "to": 78.0, "rise": [0.4, 0.0], "shape": "ease", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0, "roll_level": 2},
		{"from": 79.0, "to": 80.5, "rise": [0.0, 0.4], "shape": "ease", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0, "roll_level": 2},
		{"from": 80.5, "to": 85.0, "rise": [0.4, 0.0], "shape": "ease", "jump": true, "clear_speed": 10.5, "roll_speed": 6.0, "roll_level": 2},
		# Step-down: up onto a plateau, a step down to a lower table, a long
		# landing slope.
		{"from": 139.5, "to": 144.5, "rise": [0.0, 0.6], "shape": "ease", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0, "roll_level": 1},
		{"from": 144.5, "to": 146.5, "rise": [0.6, 0.6], "shape": "flat", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0, "roll_level": 1},
		{"from": 146.5, "to": 147.7, "rise": [0.6, 0.25], "shape": "ease", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0, "roll_level": 1},
		{"from": 147.7, "to": 148.5, "rise": [0.25, 0.25], "shape": "flat", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0, "roll_level": 1},
		{"from": 148.5, "to": 153.5, "rise": [0.25, 0.0], "shape": "ease", "jump": true, "clear_speed": 9.0, "roll_speed": 6.0, "roll_level": 1},
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
		"tour": [["grid", 2.5], ["table_top", 17.5], ["bank1", 53.0], ["double", 80.0], ["hairpin", 96.5], ["bank2", 122.0], ["step_down", 146.0], ["flat_right", 164.5]],
	},
	"kerbs": false,
	"theme": {"arena": true, "trees": true, "tree_seed": 11, "tree_keep": 0.07, "cones": false, "gate": true, "markers": true},
	# Greener, darker surround so the ochre track stands out; a dustier,
	# warmer morning sun from across the back straight.
	"time_tweaks": {
		"morning": {"sun_az": 250.0, "sun_color": Color(1.0, 0.78, 0.58), "ground": Color(0.1, 0.15, 0.08), "track": 1.55},
		"noon": {"ground": Color(0.08, 0.13, 0.06), "track": 1.2},
		"night": {"ground": Color(0.07, 0.1, 0.09), "track": 1.8},
	},
}

## Frost Pass: an asphalt mountain road with snow on parts of it. About 170
## long: the start straight, a climbing sweeper, a snowy straight up into the
## first switchback hairpin (brake early or slide past it), a climb to the
## second switchback, a crest that lightens the car, the long downhill sweeper
## with snow on its inside two-thirds (the short way on snow or the long way
## on asphalt), a chicane, the snow-covered drift corner, and the long straight
## home with snow along one edge. No jumps, no banking: the climb, the crest
## and the descent are the character. Raised road has guard rails.
const FROST_PASS: Dictionary = {
	"id": "frost_pass",
	"name": "FROST PASS",
	"description": "mountain asphalt, switchbacks and snow",
	"layout": [
		["S", -1.0], # start straight (solved: 25.7)
		["A", 9.0, 60.0], # climbing sweeper (s 25.7 .. 35.1)
		["S", 11.0], # snowy straight up to the first switchback
		["A", 3.5, 180.0], # switchback 1 (s 46.1 .. 57.1)
		["S", 10.0], # climb
		["A", 3.5, -180.0], # switchback 2 (s 67.1 .. 78.1)
		["S", 6.0], # the crest
		["A", 12.0, 120.0], # long downhill sweeper (s 84.1 .. 109.2)
		["S", 9.0],
		["A", 5.0, -40.0], # chicane
		["A", 5.0, 40.0],
		["A", 6.0, 90.0], # the snow drift corner (s 125.2 .. 134.6)
		["S", -1.0], # straight home (solved: 24.9)
		["A", 7.0, 90.0], # onto the start straight (s 159.5 .. 170.5)
	],
	"start_heading_deg": 0.0,
	"origin": Vector2(-16.0, -19.0),
	"elevation": [
		{"from": 36.0, "to": 46.0, "rise": [0.0, 0.7], "shape": "ease"},
		{"from": 46.0, "to": 57.2, "rise": [0.7, 0.7], "shape": "flat"},
		{"from": 57.2, "to": 67.0, "rise": [0.7, 1.4], "shape": "ease"},
		{"from": 67.0, "to": 78.2, "rise": [1.4, 1.4], "shape": "flat"},
		{"from": 78.2, "to": 82.0, "rise": [1.4, 1.6], "shape": "ease"},
		# The crest: over the top in 6; it lightens the car at speed but keeps
		# its wheels down even on nitro.
		{"from": 82.0, "to": 88.0, "rise": [1.6, 1.45], "shape": "ease"},
		{"from": 88.0, "to": 112.0, "rise": [1.45, 0.1], "shape": "ease"},
		{"from": 112.0, "to": 118.0, "rise": [0.1, 0.0], "shape": "ease"},
	],
	"bank": [],
	"surface": &"road",
	# About a third of the lap under snow, of different kinds; tapered ends.
	"patches": [
		{"from": 35.5, "to": 45.5, "surface": &"snow", "taper": 2.0}, # the straight into switchback 1
		{"from": 78.6, "to": 83.6, "surface": &"snow", "u": [0.5, 1.35], "taper": 1.5}, # switchback 2's exit, outside edge
		{"from": 85.0, "to": 108.5, "surface": &"snow", "u": [-0.45, 1.35], "taper": 3.0}, # the sweeper's inside two-thirds
		{"from": 125.0, "to": 135.5, "surface": &"snow", "taper": 1.5}, # the drift corner
		{"from": 142.0, "to": 152.0, "surface": &"snow", "u": [-1.35, -0.6], "taper": 2.0}, # along one edge of the straight home
	],
	"start_s": 5.0,
	"checkpoints": [0.3, 0.65],
	"tests": {
		"block": [["on the line, start straight", 18.0, 0.0, 0.0], ["across switchback 1's exit", 59.0, -0.2, 90.0]],
		"shove": [["start straight", 15.0], ["the sweeper", 95.0]],
		# [name, s start, s end, speed, lateral, brake from s (-1: none), nitro]
		"abuse": [
			["snowy straight, braking late for switchback 1", 33.0, 62.0, 11.0, 0.0, 44.5, false],
			["switchback 1 entered 20% too fast", 42.0, 62.0, 8.0, 0.0, -1.0, false],
			["switchback 2 entered 20% too fast", 63.0, 82.0, 8.0, 0.0, -1.0, false],
			["the drift corner 20% too fast", 119.0, 140.0, 7.9, 0.0, -1.0, false],
			["the drift corner on nitro", 120.5, 140.0, 13.5, 0.0, -1.0, true],
			["the sweeper on its snow, 20% too fast", 84.0, 112.0, 11.2, 0.6, -1.0, false],
			["the sweeper half on snow (left wheels)", 84.0, 112.0, 10.0, -0.45, -1.0, false],
			["the sweeper on nitro", 82.0, 112.0, 13.5, 0.0, -1.0, true],
			["straight home, edge snow, braking hard", 138.0, 162.0, 11.0, -0.9, 145.0, false],
			["the crest at nitro speed", 74.0, 95.0, 13.5, 0.0, -1.0, true],
		],
		"tour": [["grid", 2.5], ["climb", 31.0], ["snow_straight", 43.0], ["switchback1", 52.0], ["switchback2", 73.0], ["crest", 84.0],
			["sweeper", 97.0], ["chicane", 122.0], ["drift_corner", 131.0], ["straight_home", 148.0]],
	},
	"kerbs": true,
	"theme": {"mountain": true, "snow": true, "trees": true, "tree_seed": 5, "tree_keep": 0.2, "cones": false, "gate": true, "poles": true, "snowbanks": true},
	# A snowfield a few steps below white (bright ground fills the screen with
	# dense characters), the road darker, the snow on it brighter.
	"time_tweaks": {
		"morning": {"ground": Color(0.56, 0.6, 0.72), "track": 1.1},
		"noon": {"ground": Color(0.46, 0.5, 0.6), "track": 1.0},
		"night": {"ground": Color(0.24, 0.29, 0.42), "track": 1.5},
	},
}

const ALL: Array[Dictionary] = [FIGURE_EIGHT, DUST_BOWL, FROST_PASS]
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
