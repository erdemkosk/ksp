class_name Flare
extends Node3D
## Isı tuzağı (flare): çok sıcak yanan magnezyum fişek. Uçaktan atılır, yavaşlayıp düşer,
## ~4 sn yanar. IR füzelerin arayıcısı fişeği motordan daha sıcak görürse ona kayar.

const LIFETIME := 4.0
const DRAG := 0.012

## Etkin fişekler (füzeler tarar).
static var active: Array[Flare] = []

var linear_velocity := Vector3.ZERO
var heat := 2.6

var _age := 0.0
var _light: OmniLight3D
var _core: MeshInstance3D
var _trail: PuffTrail


## Atıldığından beri geçen süre (chaff bulutu ilk saniyelerde etkili).
func age() -> float:
	return _age


static func drop(from: Vessel, count := 2) -> void:
	for i in count:
		var f := Flare.new()
		var side := from.global_basis.x * (1.0 if i % 2 == 0 else -1.0)
		f.linear_velocity = from.linear_velocity + side * randf_range(14.0, 24.0) - from.up() * 18.0 + from.forward() * randf_range(-8.0, 0.0)
		FloatingOrigin.world_root.add_child(f)
		f.global_position = from.com_global() - from.up() * 0.8
	Sfx.play_at("switch_4.ogg", from.com_global(), 2.0, 0.55, 1500.0)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	active.append(self)
	_core = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.7
	_core.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.92, 0.75) * 6.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core.material_override = m
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.6)
	_light.omni_range = 60.0
	_light.light_energy = 6.0
	add_child(_light)
	_trail = PuffTrail.create(self, Vector3.ZERO, "flare")


func _exit_tree() -> void:
	active.erase(self)


func heat_signature() -> float:
	return heat


func heat_position() -> Vector3:
	return global_position


func _physics_process(delta: float) -> void:
	_age += delta
	var speed := linear_velocity.length()
	linear_velocity += (Planet.gravity_at(global_position) - linear_velocity * speed * DRAG) * delta
	global_position += linear_velocity * delta
	var k := clampf(1.0 - _age / LIFETIME, 0.0, 1.0)
	heat = 2.6 * k
	_light.light_energy = 6.0 * k * randf_range(0.75, 1.0)
	_core.scale = Vector3.ONE * (0.4 + k * randf_range(0.7, 1.0))
	if _age > LIFETIME:
		active.erase(self)
		_trail.emitting = false
		queue_free()
