class_name Chaff
extends Node3D
## Chaff (radar karıştırıcı şerit bulutu): binlerce ince alüminyum şerit havada açılıp yavaşça
## süzülür. Radar füzesinin arayıcısı ve SAM'ın takip radarı buluta kayabilir — bulut taze
## (ilk ~2 sn) ve hedefe yakınken etkili. Görsel: güneşte parıldayan, genişleyen nokta bulutu.

const LIFETIME := 6.0
const DRAG := 0.04

static var active: Array[Chaff] = []

var linear_velocity := Vector3.ZERO
var _age := 0.0
var _cloud: GPUParticles3D


static func drop(from: Vessel) -> void:
	var c := Chaff.new()
	c.linear_velocity = from.linear_velocity * 0.6 - from.up() * 6.0 + from.global_basis.x * randf_range(-6.0, 6.0)
	FloatingOrigin.world_root.add_child(c)
	c.global_position = from.com_global() - from.up() * 0.9 - from.forward() * 2.0
	Sfx.play_at("switch_2.ogg", from.com_global(), 0.0, 0.45, 1200.0)


func age() -> float:
	return _age


## Etkinlik 0..1: açılırken artar, birkaç saniyede söner.
func strength() -> float:
	return clampf(_age / 0.3, 0.0, 1.0) * clampf(1.0 - (_age - 1.0) / 2.5, 0.0, 1.0)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	active.append(self)
	_cloud = GPUParticles3D.new()
	_cloud.amount = 260
	_cloud.lifetime = LIFETIME
	_cloud.one_shot = true
	_cloud.explosiveness = 0.85
	_cloud.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -1.2, 0)
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	_cloud.process_material = pm
	var strip := QuadMesh.new()
	strip.size = Vector2(0.03, 0.22)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.87, 0.9)
	m.metallic = 1.0
	m.roughness = 0.15
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.5, 0.52, 0.55)
	m.emission_energy_multiplier = 0.4
	strip.material = m
	_cloud.draw_pass_1 = strip
	add_child(_cloud)
	_cloud.emitting = true


func _exit_tree() -> void:
	active.erase(self)


func _physics_process(delta: float) -> void:
	_age += delta
	linear_velocity += (Planet.gravity_at(global_position) * 0.05 - linear_velocity * DRAG * linear_velocity.length() * 0.02) * delta
	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, delta * 25.0)
	global_position += linear_velocity * delta
	if _age > LIFETIME:
		queue_free()


## Hedefin yakınında taze chaff bulutu var mı (radar kilidi kırma şansı için 0..1 etkinlik).
static func near(p: Vector3, radius := 150.0) -> float:
	var best := 0.0
	for c in active:
		if is_instance_valid(c) and c.global_position.distance_to(p) < radius:
			best = maxf(best, c.strength())
	return best
