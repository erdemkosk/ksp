class_name Missile
extends Node3D
## Isı güdümlü (IR) füze. Kendi basit fiziğiyle uçar: roket motoru, yerçekimi, sürükleme.
## Güdüm: oransal güdüm (proportional navigation) — görüş hattının dönme hızıyla orantılı
## yanal ivme. Arayıcı başlık koni içindeki en güçlü ısı kaynağını izler; hedef koniden
## çıkarsa kilit kopar. Yakınlık tapası hedefe yaklaşınca patlatır (alan hasarı).

const BURN_TIME := 2.6
const THRUST_ACCEL := 260.0     ## m/s² (≈26 G)
const MAX_G := 35.0
const NAV_GAIN := 4.0
const SEEKER_CONE := deg_to_rad(30.0)
const FUSE_RANGE := 9.0
const BLAST_RADIUS := 15.0
const BLAST_DAMAGE := 420.0
const LIFETIME := 22.0
const DRAG := 0.0009

var velocity := Vector3.ZERO
var target: Node3D           ## Vessel ya da Flare (ikisi de heat_position/heat_signature/linear_velocity sunar)
var victim: Vessel           ## fırlatıldığında kilitli olunan uçak (füze uyarısı için)

## Uçuştaki füzeler (füze yaklaşma uyarısı ve yapay zeka kaçınması için).
static var active: Array[Missile] = []
var shooter: Vessel

var _age := 0.0
var _prev_los := Vector3.ZERO
var _decoy_timer := 0.0
var _scan_timer := 0.0
var _trail: PuffTrail
var _motor: AudioStreamPlayer3D
var _flame: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 2.8
	body.mesh = cyl
	body.rotation_degrees = Vector3(-90, 0, 0)
	body.material_override = VesselBuilder.material("paint", Color(0.85, 0.86, 0.84))
	add_child(body)
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.0
	cone.height = 1.6
	_flame.mesh = cone
	_flame.rotation_degrees = Vector3(-90, 0, 0)
	_flame.position = Vector3(0, 0, 2.2)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.7, 0.3) * 3.0
	_flame.material_override = fm
	add_child(_flame)
	_trail = PuffTrail.create(self, Vector3(0, 0, 1.5), "missile")
	_motor = AudioStreamPlayer3D.new()
	_motor.stream = Sfx.looped("missile_motor.ogg")
	_motor.unit_size = 20.0
	_motor.max_distance = 4000.0
	_motor.bus = Sfx.world_bus()
	_motor.autoplay = true
	add_child(_motor)
	FloatingOrigin.shifted.connect(_on_shift)
	active.append(self)
	if target is Vessel:
		victim = target


func _exit_tree() -> void:
	active.erase(self)


## Arayıcı konisindeki fişekler: hedeften daha parlak görünen bir fişek arayıcıyı kandırabilir.
## Her 0.15 sn'de bir şans; fişek ne kadar sıcak ve hedefe göre ne kadar yakınsa şans o kadar yüksek.
func _check_decoys(pos: Vector3, fwd: Vector3) -> void:
	if not target is Vessel:
		return
	var t_heat: float = target.heat_signature() / maxf(pos.distance_squared_to(target.heat_position()), 1.0)
	for f in Flare.active:
		var to := f.global_position - pos
		if fwd.angle_to(to) > SEEKER_CONE:
			continue
		var f_heat := f.heat / maxf(to.length_squared(), 1.0)
		var ratio := f_heat / maxf(t_heat, 1e-9)
		if ratio > 0.6 and randf() < clampf(0.12 + 0.1 * ratio, 0.0, 0.55):
			target = f
			return


## Kilitsiz atılan ya da kilidi kopan füze: önündeki koniyi tarar, en sıcak düşmana kilitlenir.
func _acquire(pos: Vector3, fwd: Vector3) -> void:
	var best_score := 0.0
	for node in get_parent().get_children():
		if node is Vessel and node != shooter and not node.parts.is_empty() and (shooter == null or not is_instance_valid(shooter) or node.team != shooter.team):
			var to: Vector3 = node.heat_position() - pos
			var d := to.length()
			if d > MissileModule.SEEK_RANGE or fwd.angle_to(to) > SEEKER_CONE:
				continue
			var score: float = node.heat_signature() / (d * d) * 1e6
			if score > best_score and score > 0.02:
				best_score = score
				target = node
	if target is Vessel and victim == null:
		victim = target
		_prev_los = Vector3.ZERO


func _on_shift(_s: Vector3) -> void:
	_prev_los = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_age += delta
	var pos := global_position
	var accel := Planet.gravity_at(pos)
	var speed := velocity.length()
	var fwd := velocity.normalized() if speed > 1.0 else -global_basis.z

	if _age < BURN_TIME:
		accel += fwd * THRUST_ACCEL
	else:
		_flame.visible = false
		_motor.volume_db = move_toward(_motor.volume_db, -60.0, delta * 30.0)
	var rho := Atmosphere.density(Planet.altitude(pos))
	accel -= velocity * speed * DRAG * rho / 1.225

	# Arayıcı ve güdüm (ilk 0.25 sn serbest uçuş: uçaktan güvenle ayrılsın)
	_scan_timer -= delta
	if not is_instance_valid(target) and _age > 0.25 and _scan_timer <= 0.0:
		_scan_timer = 0.2
		_acquire(pos, fwd)
	_decoy_timer -= delta
	if _decoy_timer <= 0.0 and is_instance_valid(target) and _age > 0.25:
		_decoy_timer = 0.15
		_check_decoys(pos, fwd)
	if is_instance_valid(target) and target.is_inside_tree() and _age > 0.25:
		var tpos: Vector3 = target.heat_position()
		var los := tpos - pos
		var dist := los.length()
		if fwd.angle_to(los) > SEEKER_CONE * 1.6 or target.heat_signature() < 0.02:
			target = null   # hedef arayıcı konisinden çıktı / soğudu: kilit koptu
		else:
			var los_dir := los / dist
			if _prev_los != Vector3.ZERO:
				var los_rate := (los_dir - _prev_los) / delta
				var closing: float = (velocity - target.linear_velocity).dot(los_dir)
				var cmd := los_rate * NAV_GAIN * maxf(closing, 100.0)
				cmd -= fwd * cmd.dot(fwd)
				accel += cmd.limit_length(MAX_G * 9.81)
			_prev_los = los_dir
			if dist < FUSE_RANGE:
				_detonate()
				return

	velocity += accel * delta
	var new_pos := pos + velocity * delta
	# çarpma (zemin, araç)
	var q := PhysicsRayQueryParameters3D.create(pos, new_pos, 1 | 2 | 8)
	if is_instance_valid(shooter) and _age < 1.0:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		_detonate()
		return
	global_position = new_pos
	if velocity.length() > 1.0:
		look_at(new_pos + velocity, Planet.up_at(new_pos))
	if _age > LIFETIME or Planet.altitude(new_pos) < 0.0:
		_detonate()


func _detonate() -> void:
	Damage.explosion(global_position, BLAST_RADIUS, BLAST_DAMAGE, null)
	# duman izi bir süre havada kalsın
	_trail.emitting = false
	queue_free()
