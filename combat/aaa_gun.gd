class_name AaaGun
extends GroundTarget
## Uçaksavar topu: çift namlulu 35 mm. 3 km içinde, görüş hattındaki uçağa öncül nişanla
## kısa seriler atar (izli mermi). Hızlı ve yüksek uçan hedefi zor tutturur.

const RANGE := 3000.0
const MUZZLE := 950.0
const DAMAGE := 22.0

var _yaw: Node3D
var _pitch: Node3D
var _burst := 0.0
var _cool := 2.0
var _shot_t := 0.0
var _n := 0


static func create_aaa(pos: Vector3, yaw: float) -> AaaGun:
	var t := AaaGun.new()
	t.hp = 300.0
	t.unit_name = "Uçaksavar"
	t.objective = false
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.6, 3.0)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	t.add_child(cs)
	var col := Color(0.34, 0.36, 0.28)
	t._hull = _mesh(t, Vector3(3.2, 0.6, 3.2), Vector3(0, 0.3, 0), col.darkened(0.2))
	t._yaw = Node3D.new()
	t._yaw.position = Vector3(0, 0.9, 0)
	t.add_child(t._yaw)
	_mesh(t._yaw, Vector3(1.8, 1.0, 1.8), Vector3(0, 0.3, 0), col)
	t._pitch = Node3D.new()
	t._pitch.position = Vector3(0, 0.8, 0)
	t._yaw.add_child(t._pitch)
	for side in [-0.35, 0.35]:
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.1
		cyl.height = 3.2
		barrel.mesh = cyl
		barrel.rotation_degrees = Vector3(-90, 0, 0)
		barrel.position = Vector3(side, 0, -1.6)
		barrel.material_override = SamSite._mat(Color(0.15, 0.15, 0.14))
		t._pitch.add_child(barrel)
	t._turret = t._yaw
	t.position = pos
	t.rotation.y = yaw
	return t


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_cool -= delta
	var v := nearest_enemy_vessel(RANGE)
	if v == null or not line_of_sight(v.com_global()):
		_burst = 0.0
		return
	# öncül nişan: mermi uçuş süresi kadar ileri
	var muzzle := _pitch.global_position
	var tp := v.com_global()
	var t := muzzle.distance_to(tp) / MUZZLE
	for i in 2:
		tp = v.com_global() + v.linear_velocity * t
		t = muzzle.distance_to(tp) / MUZZLE
	tp -= Planet.gravity_at(tp) * 0.5 * t * t
	var local := to_local(tp)
	_yaw.rotation.y = lerp_angle(_yaw.rotation.y, atan2(-local.x, -local.z), 1.0 - exp(-4.0 * delta))
	var hd := Vector2(local.x, local.z).length()
	_pitch.rotation.x = lerp_angle(_pitch.rotation.x, atan2(local.y - 1.7, hd), 1.0 - exp(-4.0 * delta))
	if _burst <= 0.0 and _cool <= 0.0:
		_burst = randf_range(1.0, 2.0)
		_cool = _burst + randf_range(1.5, 3.0)
	if _burst > 0.0:
		_burst -= delta
		_shot_t -= delta
		while _shot_t <= 0.0:
			_shot_t += 0.09
			_shoot()


func _shoot() -> void:
	if ProjectileManager.instance == null:
		return
	_n += 1
	var dir := -_pitch.global_basis.z
	var spread := deg_to_rad(0.7)
	dir = dir.rotated(_pitch.global_basis.x, randf_range(-spread, spread)).rotated(_pitch.global_basis.y, randf_range(-spread, spread))
	var side := _pitch.global_basis.x * (0.35 if _n % 2 == 0 else -0.35)
	var p := _pitch.global_position + side + dir * 3.3
	ProjectileManager.instance.spawn(p, dir * MUZZLE, DAMAGE, _n % 3 == 0, self)
	if _n % 2 == 0:
		Sfx.play_at("gun_stop.ogg", p, 2.0, randf_range(0.55, 0.65), 4000.0)
