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
	if c.linear_velocity.length() > 1.0:
		c.look_at(c.global_position + c.linear_velocity, from.up())   # şeritler uçuş yönünde saçılır
	Sfx.play_at("switch_2.ogg", from.com_global(), 0.0, 0.45, 1200.0)


func age() -> float:
	return _age


## Etkinlik 0..1: açılırken artar, birkaç saniyede söner.
func strength() -> float:
	return clampf(_age / 0.3, 0.0, 1.0) * clampf(1.0 - (_age - 1.0) / 2.5, 0.0, 1.0)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	active.append(self)
	# şeritler: uçağın hızının bir kısmıyla çıkar, hava direnciyle hızla yavaşlar, dönerek parıldar
	# ve yavaşça süzülür (görünür olsun diye gerçek boyundan büyük çizilir)
	_cloud = GPUParticles3D.new()
	_cloud.amount = 700
	_cloud.lifetime = VISUAL_LIFE
	_cloud.one_shot = true
	_cloud.explosiveness = 0.9
	_cloud.local_coords = false
	_cloud.visibility_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8
	# düğüm uçuş yönüne bakar (drop): şeritler o yönde uçağın hızının bir kısmıyla çıkar, saçılır
	var spd := linear_velocity.length()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 40.0
	pm.initial_velocity_min = spd * 0.35 + 4.0
	pm.initial_velocity_max = spd * 0.8 + 14.0
	pm.gravity = Vector3(0, -0.9, 0)
	pm.damping_min = 25.0
	pm.damping_max = 55.0
	pm.angular_velocity_min = -900.0
	pm.angular_velocity_max = 900.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 4.0
	pm.color_ramp = Effects._ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	_cloud.process_material = pm
	var strip := QuadMesh.new()
	strip.size = Vector2(0.06, 0.55)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.9, 0.93)
	m.metallic = 1.0
	m.roughness = 0.1
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.6, 0.62, 0.66)
	m.emission_energy_multiplier = 0.6
	strip.material = m
	_cloud.draw_pass_1 = strip
	add_child(_cloud)
	_cloud.emitting = true
	# gümüşi pus: şerit bulutunun uzaktan görünen yumuşak kütlesi, genişleyip dağılır
	Effects._init_resources()
	_haze = GPUParticles3D.new()
	_haze.amount = 28
	_haze.lifetime = 5.0
	_haze.one_shot = true
	_haze.explosiveness = 0.95
	_haze.local_coords = false
	_haze.visibility_aabb = _cloud.visibility_aabb
	var hm := ParticleProcessMaterial.new()
	hm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	hm.emission_sphere_radius = 1.5
	hm.spread = 180.0
	hm.direction = Vector3(0, 0, -1)
	hm.initial_velocity_min = spd * 0.3
	hm.initial_velocity_max = spd * 0.6 + 6.0
	hm.damping_min = 20.0
	hm.damping_max = 35.0
	hm.gravity = Vector3(0, -0.4, 0)
	hm.angle_min = -180.0
	hm.angle_max = 180.0
	hm.scale_curve = Effects._grow_curve(0.5, 2.4)
	hm.color_ramp = Effects._ramp([Color(0.82, 0.84, 0.88, 0.0), Color(0.82, 0.84, 0.88, 0.32), Color(0.8, 0.82, 0.86, 0.0)])
	_haze.process_material = hm
	_haze.draw_pass_1 = Effects._quad(Effects._billboard_mat(false), 4.0)
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_haze)
	_haze.emitting = true


const VISUAL_LIFE := 9.0       ## şeritler görünür kalır (radar etkisi strength() ile daha kısa)
var _haze: GPUParticles3D


func _exit_tree() -> void:
	active.erase(self)


func _physics_process(delta: float) -> void:
	_age += delta
	linear_velocity += (Planet.gravity_at(global_position) * 0.05 - linear_velocity * DRAG * linear_velocity.length() * 0.02) * delta
	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, delta * 25.0)
	global_position += linear_velocity * delta
	if _age > VISUAL_LIFE:
		queue_free()


## Hedefin yakınında taze chaff bulutu var mı (radar kilidi kırma şansı için 0..1 etkinlik).
static func near(p: Vector3, radius := 150.0) -> float:
	var best := 0.0
	for c in active:
		if is_instance_valid(c) and c.global_position.distance_to(p) < radius:
			best = maxf(best, c.strength())
	return best
