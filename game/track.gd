## The circuit, generated from a centre line: a closed figure-of-eight with a
## bridge where it crosses itself and a table-top jump, extruded into road,
## kerbs, walls and supports, with collision built from the same data. Also
## the centre-line queries (lap progress, reset position, autopilot).
##
## Which circuit: `def` (a Tracks definition, set before the node enters the
## tree); the default is track 1, the figure of eight. Banking ("bank" ranges)
## rolls the road, kerbs and walls together; surfaces ("surface", "patches")
## give road faces their own colliders with a `surface` meta (Surfaces).
##
## Editing: LAYOUT is a turtle walk from the origin heading north-east (the
## bridge deck is over the origin). Each entry is a straight ["S", length] or an
## arc ["A", radius, degrees] (+ = right turn). Exactly two straights have
## length -1: they are solved so the walk closes; they must not be parallel.
## ELEVATION raises ranges of the centre line (s from the origin, may be
## negative = before the end of the lap): "ease" is a cosine ramp, "kick" a
## parabolic kicker (steepest at its end), "flat" holds; "deck" marks the
## bridge span (open underneath, on pillars). Raised ranges get walls instead
## of kerbs. _ready() checks that the walk closes and that the strands cross
## under the deck, and complains if not.
##
## Look: the road copies the kit's `track-road-wide` colours (colormap.png) and
## TRACK_TINT; the kerbs and walls use the kit rail's red and white blocks.
class_name Track
extends Node3D

## Road surface height on flat ground.
const ROAD_Y: float = 0.1
## Ground collider top; a hair under the road so wheel casts on the road hit the road.
const GROUND_Y: float = 0.098
## Visible ground plane, under the road so the two never z-fight.
const GROUND_VISUAL_Y: float = 0.095
## Half width of the drivable road (asphalt).
const ROAD_HALF_WIDTH: float = 1.35
## Pale edge line: its inner and outer offset from the centre (kit: 0.1 inside the edge).
const LINE_IN: float = 1.15
const LINE_OUT: float = 1.25
## Kerb beside flat road: a low ridge the car drives over.
const KERB_WIDTH: float = 0.3
const KERB_HEIGHT: float = 0.06
## Wall beside raised road (the kit rail): thickness and height above the road.
const WALL_THICK: float = 0.1
const WALL_HEIGHT: float = 0.25
## Road height above the ground at which a ramp's walls reach full height.
const WALL_TAPER: float = 0.35
## Deck slab thickness under the bridge road.
const DECK_THICK: float = 0.2
## Length of each red / white block on kerbs and walls.
const STRIPE: float = 0.5
const TRACK_TINT: Color = Color(0.5, 0.5, 0.55)
const SAMPLE_STEP: float = 0.1
const MESH_STEP: float = 0.25

## Kit colours (colormap.png texels of track-road-wide-straight).
const COL_ASPHALT: Color = Color("5a6179")
const COL_LINE: Color = Color("c0c1d9")
const COL_RED: Color = Color("fa6c42")
const COL_WHITE: Color = Color("faf7fc")
const COL_WALL_INNER: Color = Color("d0d2e1")
const COL_WALL_OUTER: Color = Color("c0c1d9")
const COL_SIDE: Color = Color("63677e")
const COL_UNDER: Color = Color("3f4250")
const COL_PILLAR: Color = Color("525563")

## Physics layers.
const LAYER_SURFACE: int = 1 ## ground and road: what wheels stand on
const LAYER_CAR: int = 2
const LAYER_PROPS: int = 4

## The circuit (a Tracks definition).
var def: Dictionary = Tracks.FIGURE_EIGHT
## Its parts, from `def`.
var LAYOUT: Array:
	get: return def.layout
var START_HEADING_DEG: float:
	get: return def.start_heading_deg
var ORIGIN: Vector2:
	get: return def.origin
var ELEVATION: Array:
	get: return def.elevation
## Start line of this circuit (START_S below is track 1's, kept for its tests).
var start_s: float:
	get: return def.start_s
## Base surface of the road.
var surface: StringName:
	get: return def.get("surface", Surfaces.ROAD)

## Track 1's start line (on the main straight); other circuits: start_s.
const START_S: float = 19.5
## Deck supports: distance from the deck centre along the road, offset across it.
const PILLAR_S: float = 3.0
const PILLAR_U: float = 1.1
const PILLAR_SIZE: float = 0.3

## Centre line samples (3D, road surface).
var points: PackedVector3Array = PackedVector3Array()
## Unit tangents (3D, follow the slope).
var tangents: PackedVector3Array = PackedVector3Array()
## Signed curvature (+ = right turn) at each sample.
var curvature: PackedFloat32Array = PackedFloat32Array()
## Banking (roll, radians, + = right side up) at each sample.
var banks: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
## World AABB of the road for framing.
var bounds: AABB
## Where the strands cross (on the lower road) and the deck road height there.
var crossing_point: Vector3 = Vector3.ZERO
var deck_y: float = 0.0
## The bridge deck's visible mesh (a halo occluder, see HaloOccluder).
var deck_mesh: MeshInstance3D

var track_body: StaticBody3D
var structure_body: StaticBody3D
var ground_body: StaticBody3D

var _segs: Array = [] ## resolved LAYOUT: [kind, length, curvature]
var _ds: float = SAMPLE_STEP ## actual sample spacing (length / samples)


func _ready() -> void:
	_resolve_layout()
	_sample()
	_build_ground()
	_build_road()
	if has_bridge():
		_find_crossing()


# --- centre line ------------------------------------------------------------

## Turns LAYOUT into segments with the two free straights solved for closure.
func _resolve_layout() -> void:
	var free: Array[int] = []
	for i in LAYOUT.size():
		if LAYOUT[i][0] == "S" and LAYOUT[i][1] < 0.0:
			free.append(i)
	if free.size() != 2:
		push_error("track LAYOUT needs exactly two free straights (length -1), has %d" % free.size())
	var base := _walk_end(free, Vector2.ZERO)
	var e1 := _walk_end(free, Vector2(1.0, 0.0)) - base
	var e2 := _walk_end(free, Vector2(0.0, 1.0)) - base
	var det := e1.x * e2.y - e1.y * e2.x
	var l := Vector2.ZERO
	if absf(det) > 1e-6:
		l = Vector2((-base.x * e2.y + base.y * e2.x) / det, (-e1.x * base.y + e1.y * base.x) / det)
	else:
		push_error("track LAYOUT: the two free straights are parallel")
	if l.x < 0.0 or l.y < 0.0:
		push_error("track LAYOUT does not close with positive free straights (%s)" % l)
	_segs.clear()
	for i in LAYOUT.size():
		var e: Array = LAYOUT[i]
		if e[0] == "S":
			var len_s: float = e[1]
			if i == free[0]:
				len_s = l.x
			elif free.size() > 1 and i == free[1]:
				len_s = l.y
			_segs.append(["S", len_s, 0.0])
		else:
			var r: float = e[1]
			var a: float = deg_to_rad(e[2])
			_segs.append(["A", r * absf(a), signf(a) / r])
	var heading_end := deg_to_rad(START_HEADING_DEG)
	for s: Array in _segs:
		heading_end += s[1] * s[2]
	var end := _walk_end(free, l)
	if end.length() > 0.01 or absf(wrapf(heading_end - deg_to_rad(START_HEADING_DEG), -PI, PI)) > 0.01:
		push_error("track layout does not close: ends at %s, heading off by %.2f deg" % [end,
			rad_to_deg(wrapf(heading_end - deg_to_rad(START_HEADING_DEG), -PI, PI))])


## End position of the walk with the free straights set to `l`.
func _walk_end(free: Array[int], l: Vector2) -> Vector2:
	var p := Vector2.ZERO
	var h := deg_to_rad(START_HEADING_DEG)
	for i in LAYOUT.size():
		var e: Array = LAYOUT[i]
		if e[0] == "S":
			var len_s: float = e[1]
			if i == free[0]:
				len_s = l.x
			elif free.size() > 1 and i == free[1]:
				len_s = l.y
			p += Vector2(cos(h), sin(h)) * len_s
		else:
			var r: float = e[1]
			var a: float = deg_to_rad(e[2])
			p += _arc_offset(h, a, r)
			h += a
	return p


## Displacement (x, z) of an arc of radius r turning by a (+ = right) from heading h.
static func _arc_offset(h: float, a: float, r: float) -> Vector2:
	var k := r * signf(a)
	return Vector2(sin(h + a) - sin(h), -(cos(h + a) - cos(h))) * k


## Position (x, z), heading and signed curvature at arc length s.
func _eval(s: float) -> Array:
	s = fposmod(s, length) if length > 0.0 else s
	var p := ORIGIN
	var h := deg_to_rad(START_HEADING_DEG)
	for seg: Array in _segs:
		var l: float = seg[1]
		var k: float = seg[2]
		var t := minf(s, l)
		if k == 0.0:
			p += Vector2(cos(h), sin(h)) * t
		else:
			p += _arc_offset(h, k * t, 1.0 / absf(k))
			h += k * t
		if s <= l:
			return [p, h, k]
		s -= l
	return [p, h, 0.0]


## Height of the road above ROAD_Y at arc length s.
func height_at(s: float) -> float:
	var e := _elevation_entry(s)
	if e.is_empty():
		return 0.0
	var s0: float = e.from
	var s1: float = e.to
	var x := fposmod(s - s0, length)
	var t := clampf(x / (s1 - s0), 0.0, 1.0)
	var y0: float = e.rise[0]
	var y1: float = e.rise[1]
	match e.shape:
		"ease":
			return lerpf(y0, y1, 0.5 - 0.5 * cos(PI * t))
		"kick":
			return lerpf(y0, y1, t * t)
	return y0


func _elevation_entry(s: float) -> Dictionary:
	for e: Dictionary in ELEVATION:
		var s0: float = e.from
		var s1: float = e.to
		var x := fposmod(s - s0, length)
		if x <= s1 - s0:
			return e
	return {}


var _bank_sides: Dictionary = {} ## bank range -> -1 / +1


## Which way a bank range rolls: the outside of the turning it covers up (from
## the curvature summed over the range; right turns: left side up, roll < 0).
func _bank_side(b: Dictionary) -> float:
	if _bank_sides.has(b):
		return _bank_sides[b]
	var s0: float = b.from
	var s1: float = b.to
	var turn := 0.0
	var n := 40
	for i in n:
		turn += float(_eval(s0 + (s1 - s0) * (i + 0.5) / n)[2])
	var side := -1.0 if turn > 0.0 else 1.0
	_bank_sides[b] = side
	return side


## Road height at s above ROAD_Y: the elevation, plus on banked road the lift
## that keeps its low edge at ground level (none without banking).
func lift_at(s: float) -> float:
	var b := bank_at(s)
	if b == 0.0:
		return height_at(s)
	return height_at(s) + (ROAD_HALF_WIDTH + WALL_THICK) * absf(sin(b))


## 0 = flat road with kerbs, 1 = raised (walls, solid underneath; also banked
## road), 2 = bridge deck.
func structure_at(s: float) -> int:
	var e := _elevation_entry(s)
	if e.is_empty():
		return 1 if bank_at(s) != 0.0 else 0
	return 2 if e.get("deck", false) else 1


## True when the circuit has a bridge deck (and so needs the halo).
func has_bridge() -> bool:
	for e: Dictionary in ELEVATION:
		if e.get("deck", false):
			return true
	return false


## Banking (roll) at arc length s, radians (+ = right side up), eased in and
## out. A bank range's "deg" raises the outside of the turn it covers (the side
## comes from the curvature in the middle of the range).
func bank_at(s: float) -> float:
	for b: Dictionary in def.get("bank", []):
		var s0: float = b.from
		var s1: float = b.to
		var x := fposmod(s - s0, length)
		if x > s1 - s0:
			continue
		var side := _bank_side(b)
		var k := 1.0
		var ein: float = b.get("ease_in", 0.0)
		var eout: float = b.get("ease_out", 0.0)
		if ein > 0.0 and x < ein:
			k = 0.5 - 0.5 * cos(PI * x / ein)
		elif eout > 0.0 and x > (s1 - s0) - eout:
			k = 0.5 - 0.5 * cos(PI * ((s1 - s0) - x) / eout)
		return deg_to_rad(float(b.deg)) * k * side
	return 0.0


## Surface under a point `u` across the road (- = left) at arc length s.
func surface_at(s: float, u: float = 0.0) -> StringName:
	for p: Dictionary in def.get("patches", []):
		var s0: float = p.from
		var s1: float = p.to
		if fposmod(s - s0, length) > s1 - s0:
			continue
		var r: Array = p.get("u", [-INF, INF])
		if u >= float(r[0]) and u <= float(r[1]):
			return p.surface
	return surface


## Grip of the road at s (across its width, the lowest), as a factor on asphalt.
func grip_at(s: float) -> float:
	var g := float(Surfaces.get_value(surface, "grip", 1.0))
	for p: Dictionary in def.get("patches", []):
		if fposmod(s - float(p.from), length) <= float(p.to) - float(p.from):
			g = minf(g, float(Surfaces.get_value(p.surface, "grip", 1.0)))
	return g


## Cornering acceleration a driver can plan for at s, given what it would
## plan on flat asphalt (`a_lat`): scaled by the surface's grip, and on banked
## road more, as the road pushes the car round: g (mu + tan b) / (1 - mu tan b).
## On flat asphalt it is exactly a_lat.
func corner_accel(a_lat: float, s: float) -> float:
	var g := grip_at(s)
	var a := a_lat if g == 1.0 else a_lat * g
	var b := absf(bank_at(s))
	if b == 0.0:
		return a
	var mu := a / Car.G
	var tb := tan(b)
	return Car.G * (mu + tb) / maxf(1.0 - mu * tb, 0.35)


## Flat-out stretches (s ranges): over each jump, from a little before its
## kicker to the end of its landing (drivers keep the throttle down there).
func flat_out_ranges() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cur := Vector2(-1.0, -1.0)
	for e: Dictionary in ELEVATION:
		if not e.get("jump", false):
			continue
		var s0: float = e.from
		var s1: float = e.to
		if cur.x >= 0.0 and s0 - 2.0 <= cur.y + 0.01:
			cur.y = maxf(cur.y, s1)
		else:
			if cur.x >= 0.0:
				out.append(cur)
			cur = Vector2(s0 - 2.0, s1)
	if cur.x >= 0.0:
		out.append(cur)
	return out


func _sample() -> void:
	length = 0.0
	for seg: Array in _segs:
		length += seg[1]
	var n := roundi(length / SAMPLE_STEP)
	_ds = length / n
	points.resize(n)
	tangents.resize(n)
	curvature.resize(n)
	banks.resize(n)
	for i in n:
		var s := i * _ds
		var e := _eval(s)
		var p: Vector2 = e[0]
		var h: float = e[1]
		points[i] = Vector3(p.x, ROAD_Y + lift_at(s), p.y)
		var slope := (lift_at(s + 0.05) - lift_at(s - 0.05)) / 0.1
		tangents[i] = Vector3(cos(h), slope, sin(h)).normalized()
		curvature[i] = e[2]
		banks[i] = bank_at(s)
	bounds = AABB(points[0], Vector3.ZERO)
	for q in points:
		bounds = bounds.expand(q)
	bounds = bounds.grow(1.0)


## Finds where the centre line crosses itself and checks it is under the deck.
func _find_crossing() -> void:
	var n := points.size()
	var best := INF
	for i in range(0, n, 2):
		for j in range(i + int(20.0 / _ds), n, 2):
			if (n - j + i) * _ds < 20.0:
				continue
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[j].x, points[j].z)
			var d := a.distance_squared_to(b)
			if d < best:
				best = d
				var lo := i if points[i].y < points[j].y else j
				var hi := j if lo == i else i
				crossing_point = points[lo]
				deck_y = points[hi].y
				if structure_at(hi * _ds) != 2:
					push_warning("track crosses itself at %s outside the bridge deck" % points[lo])
	if best > 0.25:
		push_warning("track does not cross itself (closest %.2f)" % sqrt(best))


# --- geometry -----------------------------------------------------------------

## Horizontal unit vector to the right of tangent `t`.
static func _right(t: Vector3) -> Vector3:
	return Vector3(-t.z, 0.0, t.x).normalized()


## Cross-section of the road at a row: a list of strips, each [points (u, dy),
## colours per span, collision ("road" / "wall"), deck (bool)]. Points run
## clockwise seen looking along the road, so face normals point outwards.
## `ground` is the ground height relative to the road surface.
static func _profile(kind: int, ground: float, stripe: Color, kerbs: bool = true) -> Array:
	var h := ROAD_HALF_WIDTH
	var road := [
		[Vector2(-h, 0.0), Vector2(-LINE_OUT, 0.0), Vector2(-LINE_IN, 0.0), Vector2(LINE_IN, 0.0), Vector2(LINE_OUT, 0.0), Vector2(h, 0.0)],
		[COL_ASPHALT, COL_LINE, COL_ASPHALT, COL_LINE, COL_ASPHALT], "road", kind == 2]
	if kind == 0 and not kerbs:
		return [road]
	if kind == 0:
		var k := KERB_WIDTH
		var top := KERB_HEIGHT
		var left := [
			[Vector2(-h - k, ground), Vector2(-h - k * 0.66, top), Vector2(-h - k * 0.33, top), Vector2(-h, 0.0)],
			[stripe, stripe, stripe], "road", false]
		var right := [
			[Vector2(h, 0.0), Vector2(h + k * 0.33, top), Vector2(h + k * 0.66, top), Vector2(h + k, ground)],
			[stripe, stripe, stripe], "road", false]
		return [left, road, right]
	var w := WALL_THICK
	# Walls grow out of the kerb as the road rises (full height once it is
	# WALL_TAPER above the ground), so a raised stretch never starts with a
	# blunt wall end in the way.
	var wt := lerpf(KERB_HEIGHT, WALL_HEIGHT, clampf(-ground / WALL_TAPER, 0.0, 1.0)) if kind == 1 else WALL_HEIGHT
	var bevel := wt * 0.48
	var bottom := -DECK_THICK if kind == 2 else ground
	var rwall := [
		[Vector2(h, 0.0), Vector2(h, bevel), Vector2(h + w * 0.3, wt), Vector2(h + w * 0.7, wt), Vector2(h + w, bevel), Vector2(h + w, 0.0)],
		[COL_WALL_INNER, stripe, stripe, stripe, COL_WALL_OUTER], "wall", false]
	var lwall := [
		[Vector2(-h - w, 0.0), Vector2(-h - w, bevel), Vector2(-h - w * 0.7, wt), Vector2(-h - w * 0.3, wt), Vector2(-h, bevel), Vector2(-h, 0.0)],
		[COL_WALL_OUTER, stripe, stripe, stripe, COL_WALL_INNER], "wall", false]
	var sides := [
		[Vector2(h + w, 0.0), Vector2(h + w, bottom)], [COL_SIDE], "wall", kind == 2]
	var lsides := [
		[Vector2(-h - w, bottom), Vector2(-h - w, 0.0)], [COL_SIDE], "wall", kind == 2]
	var out := [lsides, lwall, road, rwall, sides]
	if kind == 2:
		out.append([[Vector2(h + w, bottom), Vector2(-h - w, bottom)], [COL_UNDER], "wall", true])
	return out


func _build_road() -> void:
	var road_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()
	var surface_faces: Dictionary = {} ## other surfaces (patches) -> faces
	var main := _MeshData.new()
	var raised := _MeshData.new() # ramps and the jump: can hide the car, so it gets the halo
	var deck := _MeshData.new()
	var n := roundi(length / MESH_STEP)
	var ds := length / n
	var rows: Array = [] # per row: [centre, right]
	for j in n + 1:
		var s := j * ds
		var e := _eval(s)
		var p: Vector2 = e[0]
		var hd: float = e[1]
		var c := Vector3(p.x, ROAD_Y + lift_at(s), p.y)
		var right := Vector3(-sin(hd), 0.0, cos(hd))
		var roll := bank_at(s)
		# Banked: the cross-section turns about the tangent (no roll: exactly the
		# flat right / up vectors).
		var r2 := right * cos(roll) + Vector3.UP * sin(roll)
		var u2 := Vector3.UP * cos(roll) - right * sin(roll)
		rows.append([c, r2, u2])
	for j in n:
		var s_mid := (j + 0.5) * ds
		var kind := structure_at(s_mid)
		var stripe := COL_RED if int(floor(s_mid / STRIPE)) % 2 == 0 else COL_WHITE
		var a: Array = rows[j]
		var b: Array = rows[j + 1]
		var ga := GROUND_VISUAL_Y - (a[0] as Vector3).y
		var gb := GROUND_VISUAL_Y - (b[0] as Vector3).y
		var kerbs: bool = def.get("kerbs", true)
		# Banked: the sides reach down past the ground under the raised outer edge.
		var deep_a := 2.0 * (ROAD_HALF_WIDTH + WALL_THICK) * absf(sin(bank_at(j * ds)))
		var deep_b := 2.0 * (ROAD_HALF_WIDTH + WALL_THICK) * absf(sin(bank_at((j + 1) * ds)))
		var pa := _profile(kind, minf(ga, -0.002) - deep_a, stripe, kerbs)
		var pb := _profile(kind, minf(gb, -0.002) - deep_b, stripe, kerbs)
		_apply_surfaces(pa, pb, s_mid)
		for k in pa.size():
			var strip_a: Array = pa[k]
			var strip_b: Array = pb[k]
			var pts_a: Array = strip_a[0]
			var pts_b: Array = strip_b[0]
			var cols: Array = strip_a[1]
			var target := deck if strip_a[3] else (raised if kind != 0 else main)
			var faces := road_faces if strip_a[2] == "road" else wall_faces
			var span_surf: Array = strip_a[4] if strip_a.size() > 4 else []
			for m in pts_a.size() - 1:
				if not span_surf.is_empty():
					faces = road_faces if span_surf[m] == surface else surface_faces.get(span_surf[m], PackedVector3Array())
				var v00 := _at(a, pts_a[m])
				var v01 := _at(a, pts_a[m + 1])
				var v10 := _at(b, pts_b[m])
				var v11 := _at(b, pts_b[m + 1])
				if v00.is_equal_approx(v01) and v10.is_equal_approx(v11):
					continue
				target.quad(v00, v01, v11, v10, cols[m])
				faces.append_array([v00, v11, v01, v00, v10, v11]) # clockwise from outside, as rendered
				if not span_surf.is_empty() and span_surf[m] != surface:
					surface_faces[span_surf[m]] = faces
		# Wall ends where a raised stretch starts or stops (next to the kerbs).
		var kind_next := structure_at((j + 1.5) * ds)
		if (kind == 0) != (kind_next == 0):
			var row: Array = b
			var fwd := ((rows[(j + 2) % rows.size()][0] as Vector3) - (a[0] as Vector3)).normalized()
			var facing := -fwd if kind == 0 else fwd # toward the kerbs
			var h := ROAD_HALF_WIDTH
			var w := WALL_THICK
			var lift := (row[0] as Vector3).y - GROUND_VISUAL_Y
			var wt := lerpf(KERB_HEIGHT, WALL_HEIGHT, clampf(lift / WALL_TAPER, 0.0, 1.0))
			var bevel := wt * 0.48
			for side: float in [-1.0, 1.0]:
				var q := [Vector2(h, 0.0), Vector2(h, bevel), Vector2(h + w * 0.3, wt), Vector2(h + w * 0.7, wt), Vector2(h + w, bevel), Vector2(h + w, 0.0)]
				var v: Array[Vector3] = []
				for pt: Vector2 in q:
					v.append(_at(row, Vector2(pt.x * side, pt.y)))
				raised.quad_facing(v[0], v[1], v[4], v[5], COL_WALL_OUTER, facing)
				raised.quad_facing(v[1], v[2], v[3], v[4], COL_WHITE, facing)
		# End caps where raised road meets the open deck (the ramp's solid end).
		if kind != kind_next and (kind == 2 or kind_next == 2) and (kind != 0 and kind_next != 0):
			var row: Array = b
			var y0 := GROUND_VISUAL_Y - (row[0] as Vector3).y
			var u := ROAD_HALF_WIDTH + WALL_THICK
			var q0 := _at(row, Vector2(-u, -DECK_THICK))
			var q1 := _at(row, Vector2(u, -DECK_THICK))
			var q2 := _at(row, Vector2(u, y0))
			var q3 := _at(row, Vector2(-u, y0))
			# Face the deck side: toward the deck row.
			if kind == 2:
				raised.quad(q1, q0, q3, q2, COL_SIDE)
			else:
				raised.quad(q0, q1, q2, q3, COL_SIDE)
			wall_faces.append_array([q0, q2, q1, q0, q3, q2])
	# Pillars under the deck.
	var pillars := _MeshData.new()
	for e: Dictionary in ELEVATION:
		if not e.get("deck", false):
			continue
		var mid: float = (float(e.from) + float(e.to)) * 0.5
		for ds_off: float in [-PILLAR_S, PILLAR_S]:
			var s: float = mid + ds_off
			var ev := _eval(s)
			var p: Vector2 = ev[0]
			var hd: float = ev[1]
			var top := ROAD_Y + height_at(s) - DECK_THICK
			for u: float in [-PILLAR_U, PILLAR_U]:
				var c := Vector3(p.x, 0.0, p.y) + Vector3(-sin(hd), 0.0, cos(hd)) * u
				var box := _box_faces(c, PILLAR_SIZE * 0.5, GROUND_VISUAL_Y, top)
				for f in range(0, box.size(), 4):
					pillars.quad(box[f], box[f + 1], box[f + 2], box[f + 3], COL_PILLAR)
					wall_faces.append_array([box[f], box[f + 2], box[f + 1], box[f], box[f + 3], box[f + 2]])
	var mat := _material()
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = main.mesh(mat)
	add_child(mi)
	# Everything of the bridge and the jump that can stand between the iso
	# camera and the car is an occluder with a see-through halo.
	HaloOccluder.add_occluder(self, "Raised", raised.mesh(mat), TRACK_TINT)
	deck_mesh = HaloOccluder.add_occluder(self, "Deck", deck.mesh(mat), TRACK_TINT)
	HaloOccluder.add_occluder(self, "Pillars", pillars.mesh(mat), TRACK_TINT)

	track_body = _static_body("TrackBody", LAYER_SURFACE, road_faces)
	track_body.set_meta("surface", surface)
	for sid: StringName in surface_faces:
		var b := _static_body("TrackBody_" + String(sid), LAYER_SURFACE, surface_faces[sid])
		b.set_meta("surface", sid)
	structure_body = _static_body("StructureBody", LAYER_PROPS, wall_faces)


## Road colour and splits for this row's surfaces: with a base surface other
## than asphalt the road takes its colour (no painted lines); patches split the
## road strip at their edges and colour their spans. Adds the span surfaces as
## a fifth entry of the road strip.
func _apply_surfaces(pa: Array, pb: Array, s_mid: float) -> void:
	var patches: Array = def.get("patches", [])
	if surface == Surfaces.ROAD and patches.is_empty():
		return
	for prof: Array in [pa, pb]:
		for strip: Array in prof:
			var pts0: Array = strip[0]
			if strip[2] != "road" or pts0.size() != 6 or absf((pts0[0] as Vector2).x + ROAD_HALF_WIDTH) > 0.001 \
					or absf((pts0[5] as Vector2).x - ROAD_HALF_WIDTH) > 0.001:
				continue # not the road strip (a kerb)
			var us: Array = [-ROAD_HALF_WIDTH, -LINE_OUT, -LINE_IN, LINE_IN, LINE_OUT, ROAD_HALF_WIDTH] if surface == Surfaces.ROAD \
					else [-ROAD_HALF_WIDTH, ROAD_HALF_WIDTH]
			for p: Dictionary in patches:
				if fposmod(s_mid - float(p.from), length) > float(p.to) - float(p.from):
					continue
				var r: Array = p.get("u", [-ROAD_HALF_WIDTH, ROAD_HALF_WIDTH])
				for v: float in [float(r[0]), float(r[1])]:
					if v > -ROAD_HALF_WIDTH and v < ROAD_HALF_WIDTH and not us.has(v):
						us.append(v)
			us.sort()
			var pts: Array = []
			var cols: Array = []
			var surfs: Array = []
			for k in us.size():
				pts.append(Vector2(us[k], 0.0))
			for k in us.size() - 1:
				var mid: float = (us[k] + us[k + 1]) * 0.5
				var sid := surface_at(s_mid, mid)
				surfs.append(sid)
				if sid == Surfaces.ROAD:
					cols.append(COL_LINE if absf(mid) > LINE_IN and absf(mid) < LINE_OUT else COL_ASPHALT)
				else:
					cols.append(Surfaces.get_value(sid, "colour", COL_ASPHALT))
			strip[0] = pts
			strip[1] = cols
			strip.append(surfs)


## World position of a profile point (u across to the right, dy up) on a row.
static func _at(row: Array, q: Vector2) -> Vector3:
	var up: Vector3 = row[2] if row.size() > 2 else Vector3.UP
	return (row[0] as Vector3) + (row[1] as Vector3) * q.x + up * q.y


## Four-vertex faces (outward winding as _MeshData.quad expects) of an upright box.
static func _box_faces(c: Vector3, h: float, y0: float, y1: float) -> PackedVector3Array:
	var o := PackedVector3Array()
	var x0 := c.x - h
	var x1 := c.x + h
	var z0 := c.z - h
	var z1 := c.z + h
	# Each side seen from outside: top-left, top-right, bottom-right, bottom-left.
	o.append_array([Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x1, y0, z1)]) # +z
	o.append_array([Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x0, y0, z0)]) # -z
	o.append_array([Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0)]) # +x
	o.append_array([Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x0, y0, z1)]) # -x
	return o


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = TRACK_TINT
	m.roughness = 1.0
	return m


func _static_body(body_name: String, layer: int, faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(160.0, 160.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.075, 0.09, 0.08)
	mat.roughness = 1.0
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.material_override = mat
	ground.position = Vector3(bounds.get_center().x, GROUND_VISUAL_Y, bounds.get_center().z)
	add_child(ground)

	ground_body = StaticBody3D.new()
	ground_body.name = "GroundBody"
	ground_body.collision_layer = LAYER_SURFACE
	ground_body.collision_mask = 0
	ground_body.set_meta("surface", &"ground")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, GROUND_Y - 0.5, 0.0)
	ground_body.add_child(shape)
	add_child(ground_body)


## Flat-shaded triangle soup with vertex colours.
class _MeshData:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## A quad a-b-c-d, wound so that (b - a) x (d - a) is its outward normal.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		var n := (b - a).cross(d - a)
		if n.length_squared() < 1e-12:
			n = (c - b).cross(a - b)
		n = n.normalized()
		# Godot's front faces are clockwise seen from outside.
		for v in [a, c, b, a, d, c]:
			verts.append(v)
			normals.append(n)
			colors.append(col)

	## As quad(), flipped if needed so the face points along `dir`.
	func quad_facing(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, dir: Vector3) -> void:
		if (b - a).cross(d - a).dot(dir) < 0.0:
			quad(a, d, c, b, col)
		else:
			quad(a, b, c, d, col)

	func mesh(mat: Material) -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


# --- centre line queries -------------------------------------------------------

func index_at(s: float) -> int:
	return posmod(int(floor(s / _ds)), points.size())


func point_at(s: float) -> Vector3:
	var s0 := fposmod(s, length)
	var i := int(s0 / _ds)
	var f := s0 / _ds - i
	return points[i % points.size()].lerp(points[(i + 1) % points.size()], f)


func tangent_at(s: float) -> Vector3:
	return tangents[index_at(s)]


## Distance along the centre line of the sample nearest `pos`, in 3D with height
## weighted up (so on the bridge and under it pick the right strand). With a
## `hint` (previous result) only a window around it is searched.
func progress(pos: Vector3, hint: float = -1.0) -> float:
	var n := points.size()
	var best := INF
	var best_i := 0
	if hint >= 0.0:
		var c := index_at(hint)
		for k in range(-40, 41):
			var i := posmod(c + k, n)
			var d := _dist2(points[i], pos)
			if d < best:
				best = d
				best_i = i
		# Far from where we thought (teleport, or cut across): full search.
		if best <= 9.0:
			return best_i * _ds
		best = INF
	for i in n:
		var d := _dist2(points[i], pos)
		if d < best:
			best = d
			best_i = i
	return best_i * _ds


static func _dist2(p: Vector3, q: Vector3) -> float:
	var dy := (q.y - p.y) * 3.0
	return (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) + dy * dy


## Signed distance from the centre line (+ = right of the direction of travel).
func lateral_offset(pos: Vector3, s: float) -> float:
	var i := index_at(s)
	return (pos - points[i]).dot(_right(tangents[i]))


func is_on_road(pos: Vector3, s: float) -> bool:
	return absf(lateral_offset(pos, s)) < ROAD_HALF_WIDTH


## Largest |curvature| on the centre line within [s, s + ahead].
func max_curvature(s: float, ahead: float) -> float:
	var m := 0.0
	var n := int(ahead / _ds)
	var i0 := index_at(s)
	for k in n:
		m = maxf(m, absf(curvature[(i0 + k) % points.size()]))
	return m


## Transform of a car standing on the centre line at `s`, facing along it.
func pose_at(s: float, lateral: float = 0.0) -> Transform3D:
	var t := tangent_at(s)
	var roll := banks[index_at(s)] if banks.size() > 0 else 0.0
	if roll == 0.0:
		var p := point_at(s) + _right(t) * lateral
		return Transform3D(Basis.looking_at(t, Vector3.UP), p)
	# Banked: across the rolled road, standing on it.
	var r := _right(t)
	var r2 := r * cos(roll) + Vector3.UP * sin(roll)
	var up := Vector3.UP * cos(roll) - r * sin(roll)
	return Transform3D(Basis.looking_at(t, up), point_at(s) + r2 * lateral)
