## Dust kicked up behind a car whose wheels slide, spin or drift on a dusty
## surface (Surfaces "dust" colour; asphalt has none). A few lit puffs (the
## kit's smoke model) that swell and shrink rather than fade, so they read as
## solid shapes in characters instead of flickering glyph noise. Made by the
## car the first time it needs one (asphalt-only circuits never get any).
class_name Dust
extends Node3D

const KIT_SMOKE: String = "res://assets/kenney_toy-car-kit/smoke.glb"
## Puffs per second at full intensity (per car), and their life.
const RATE: float = 26.0
const LIFE: float = 0.9
const MAX_SCALE: float = 1.9

var car: Car
var _p: CPUParticles3D
var _mat: StandardMaterial3D
var _colour: Color = Color.TRANSPARENT


func _ready() -> void:
	name = "Dust"
	_p = CPUParticles3D.new()
	_p.name = "Puffs"
	_p.amount = ceili(RATE * LIFE) + 2
	_p.lifetime = LIFE
	_p.local_coords = false
	_p.emitting = false
	_p.mesh = _puff_mesh()
	_mat = StandardMaterial3D.new()
	_mat.roughness = 1.0
	# Lit by the sun and the fill, never darkened by shadows (a puff in a
	# shadow read as a black block).
	_mat.disable_receive_shadows = true
	_p.material_override = _mat
	_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = Vector3(0.22, 0.02, 0.05)
	_p.direction = Vector3(0.0, 0.6, 1.0) # up and back (car local +z is the rear)
	_p.spread = 25.0
	_p.initial_velocity_min = 0.4
	_p.initial_velocity_max = 1.1
	_p.gravity = Vector3(0.0, 0.25, 0.0)
	_p.damping_min = 1.5
	_p.damping_max = 2.5
	_p.angle_min = 0.0
	_p.angle_max = 360.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_p.scale_amount_curve = curve
	_p.scale_amount_min = MAX_SCALE * 0.7
	_p.scale_amount_max = MAX_SCALE
	add_child(_p)


func _puff_mesh() -> Mesh:
	var scene := load(KIT_SMOKE) as PackedScene
	if scene != null:
		var n := scene.instantiate()
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		var m: Mesh = (mis[0] as MeshInstance3D).mesh if not mis.is_empty() else null
		n.free()
		if m != null:
			return m
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.5
	s.radial_segments = 8
	s.rings = 4
	return s


## Called by the car each physics step with the surface's dust colour (alpha 0:
## none) and how hard the rear is working (0..1).
func feed(colour: Color, intensity: float, rear: Vector3) -> void:
	position = rear
	var on := colour.a > 0.0 and intensity > 0.12
	if on and colour != _colour:
		_colour = colour
		_mat.albedo_color = colour
	_p.emitting = on
	if on:
		# Harder work, bigger puffs (CPU particles have no rate scale).
		var k := clampf(intensity, 0.3, 1.0)
		_p.scale_amount_min = MAX_SCALE * 0.7 * k
		_p.scale_amount_max = MAX_SCALE * k
