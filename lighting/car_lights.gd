## A car's lights for the night lighting mode: a headlight beam (one shadowed
## spot light, warm white, reaching past a braking distance and wide enough to
## light both kerbs), the two headlamps and two tail lamps as small glowing
## blocks, and a faint red glow on the road behind that brightens under braking.
## Added to every car in the "lit_cars" group by Lighting while night is on,
## and removed when it is switched off.
class_name CarLights
extends Node3D

## Beam: from the front of the body, aimed a little down so the pool on the
## road starts just ahead of the car and fades out about BEAM_RANGE ahead.
const BEAM_POS: Vector3 = Vector3(0.0, 0.32, -0.62)
const BEAM_DOWN_DEG: float = 16.0
const BEAM_RANGE: float = 13.0
const BEAM_ANGLE_DEG: float = 55.0
const BEAM_ENERGY: float = 22.0
const BEAM_ATTENUATION: float = 0.55
const BEAM_COLOR: Color = Color(1.0, 0.9, 0.74)
## Lamp blocks (car local, at the body's corners).
const HEAD_LAMPS: Array[Vector3] = [Vector3(-0.15, 0.25, -0.43), Vector3(0.15, 0.25, -0.43)]
const TAIL_LAMPS: Array[Vector3] = [Vector3(-0.17, 0.26, 0.43), Vector3(0.17, 0.26, 0.43)]
const LAMP_SIZE: Vector3 = Vector3(0.09, 0.05, 0.03)
const HEAD_LAMP_COLOR: Color = Color(1.0, 0.95, 0.82)
const TAIL_COLOR: Color = Color(0.75, 0.04, 0.02)
const TAIL_BRAKE_COLOR: Color = Color(1.0, 0.16, 0.1)
## Red glow on the road behind the car (no shadows): idle and braking.
const GLOW_POS: Vector3 = Vector3(0.0, 0.3, 0.62)
const GLOW_RANGE: float = 1.6
const GLOW_ENERGY: Vector2 = Vector2(0.7, 2.2)
const GLOW_COLOR: Color = Color(1.0, 0.1, 0.05)

var car: Car
## Energy factors for the beam and the tail glow (Lighting.COMPAT_ENERGY under
## the Compatibility renderer; 1 otherwise).
var beam_scale: float = 1.0
var glow_scale: float = 1.0
var beam: SpotLight3D
var _tail_mat: StandardMaterial3D
var _glow: OmniLight3D
var _brake: float = 0.0


static func lamp_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _ready() -> void:
	name = "CarLights"
	beam = SpotLight3D.new()
	beam.name = "Beam"
	beam.position = BEAM_POS
	beam.rotation = Vector3(deg_to_rad(-BEAM_DOWN_DEG), 0.0, 0.0)
	beam.spot_range = BEAM_RANGE
	beam.spot_angle = BEAM_ANGLE_DEG
	beam.spot_angle_attenuation = 0.35
	beam.spot_attenuation = BEAM_ATTENUATION
	beam.light_energy = BEAM_ENERGY * beam_scale
	beam.light_color = BEAM_COLOR
	beam.light_specular = 0.0 # view dependent: shifts glyphs as the camera moves
	beam.shadow_enabled = true
	beam.shadow_bias = 0.04
	add_child(beam)
	var head := lamp_material(HEAD_LAMP_COLOR)
	_tail_mat = lamp_material(TAIL_COLOR)
	for p in HEAD_LAMPS:
		_lamp(p, head)
	for p in TAIL_LAMPS:
		_lamp(p, _tail_mat)
	_glow = OmniLight3D.new()
	_glow.name = "TailGlow"
	_glow.position = GLOW_POS
	_glow.omni_range = GLOW_RANGE
	_glow.light_energy = GLOW_ENERGY.x * glow_scale
	_glow.light_color = GLOW_COLOR
	_glow.light_specular = 0.0
	_glow.shadow_enabled = false
	add_child(_glow)


func _lamp(p: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = LAMP_SIZE
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	if car == null:
		return
	var braking := car.brake_input > 0.1 or car.handbrake_input
	_brake = move_toward(_brake, 1.0 if braking else 0.0, delta * 12.0)
	_tail_mat.albedo_color = TAIL_COLOR.lerp(TAIL_BRAKE_COLOR, _brake)
	_glow.light_energy = lerpf(GLOW_ENERGY.x, GLOW_ENERGY.y, _brake) * glow_scale
