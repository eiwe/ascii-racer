## The circuits as data; Track builds whichever is selected.
##
## Keys of a definition:
##   id, name                 stable id (saved settings) and the name shown
##   layout                   turtle walk (see Track): ["S", length] / ["A", radius, degrees];
##                            exactly two straights of length -1 are solved for closure
##   start_heading_deg, origin   where the walk starts
##   elevation                ranges of raised road: {from, to, rise: [y0, y1], shape:
##                            "ease" | "kick" | "flat", deck (bridge span), jump (part of a jump)}
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

## A first draft of the dirt track, here to prove the foundation (banking,
## surfaces, several jump shapes, switching tracks); phase 2 makes it the real
## thing. An oval with banked ends, a double and a step-down on the back
## straight and a dirt surface.
const DUST_BOWL: Dictionary = {
	"id": "dust_bowl",
	"name": "DUST BOWL",
	"description": "dirt, banked turns and jumps (draft)",
	# A rounded rectangle (about 112 long): front straight, banked turns 1-2,
	# back straight with a double and a step-down, banked turns 3-4.
	"layout": [
		["S", -1.0], # front straight (solved: 20)
		["A", 9.0, 90.0],
		["S", 8.0],
		["A", 9.0, 90.0],
		["S", 20.0], # back straight: double, step-down
		["A", 9.0, 90.0],
		["S", -1.0], # (solved: 8)
		["A", 9.0, 90.0],
	],
	"start_heading_deg": 0.0,
	"origin": Vector2(-10.0, 10.0),
	"elevation": [
		{"from": 58.0, "to": 59.5, "rise": [0.0, 0.25], "shape": "kick", "jump": true},
		{"from": 59.5, "to": 61.0, "rise": [0.25, 0.0], "shape": "ease", "jump": true},
		{"from": 62.5, "to": 64.0, "rise": [0.0, 0.25], "shape": "kick", "jump": true},
		{"from": 64.0, "to": 65.5, "rise": [0.25, 0.0], "shape": "ease", "jump": true},
		{"from": 67.0, "to": 68.5, "rise": [0.0, 0.35], "shape": "kick", "jump": true},
		{"from": 68.5, "to": 70.0, "rise": [0.35, 0.35], "shape": "flat", "jump": true},
		{"from": 70.0, "to": 72.0, "rise": [0.35, 0.0], "shape": "ease", "jump": true},
	],
	"bank": [
		{"from": 20.0, "to": 56.3, "deg": 22.0, "ease_in": 4.0, "ease_out": 4.0},
		{"from": 76.3, "to": 112.5, "deg": 22.0, "ease_in": 4.0, "ease_out": 4.0},
	],
	"surface": &"dirt",
	"patches": [{"from": 2.0, "to": 18.0, "surface": &"road", "u": [-1.35, 0.0]}],
	"start_s": 10.0,
	"checkpoints": [0.3, 0.65],
	"kerbs": false,
	"theme": {"trees": true, "tree_seed": 11, "cones": false, "gate": true},
	# A dustier, warmer morning sun from across the back straight.
	"time_tweaks": {"morning": {"sun_az": 70.0, "sun_color": Color(1.0, 0.76, 0.56)}},
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
