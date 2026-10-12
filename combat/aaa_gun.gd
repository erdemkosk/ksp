class_name AaaGun
extends GroundTarget
## Uçaksavar topu: çift namlulu 35 mm. 3 km içinde, görüş hattındaki uçağı izler; mermi uçuş
## süresi yetiyorsa (~2.4 km) öncül nişanla (hız + ivme, sürükleme ve düşüş telafili) kısa
## seriler atar (izli mermi, namlu alevi). Taret dönüş hızı sınırlı: hızlı geçen alçak uçağı
## yakalayamaz. Sakinken nişancı geç tepki verir; alarmda tehdit yönüne döner ve hızlı açar.
## İsabet alınca mürettebat siper alır (birkaç saniye susar, namlu iner).

const RANGE := 3000.0
const MUZZLE := 950.0
const DAMAGE := 22.0

var _yaw: Node3D
var _pitch: Node3D
var _gun: GunMount
var _target: Vessel
var _los := false
var _los_t := 0.0
var _react := 0.0          ## hedef görüldükten sonra ilk atışa kalan süre
var _quiet := 0.0          ## siper: susma süresi


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
	var muzzles: Array[Vector3] = [Vector3(-0.35, 0, -3.3), Vector3(0.35, 0, -3.3)]
	t._gun = GunMount.new(t, t._yaw, t._pitch, muzzles)
	t._gun.muzzle_speed = MUZZLE
	t._gun.damage = DAMAGE
	t._gun.add_flash(0.45)
	t.position = pos
	t.rotation.y = yaw
	return t


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_alert_tick(delta)
	_quiet -= delta
	var v := nearest_enemy_vessel(RANGE)
	if v != _target:
		_target = v
		_los_t = 0.0
		# sakin nişancı geç fark eder; alarmdaki hazır bekler
		_react = randf_range(0.4, 0.9) if alerted() else randf_range(1.8, 3.2)
	if v and _los_t <= 0.0:
		_los_t = 0.25
		_los = line_of_sight(v.com_global())
	_los_t -= delta
	if _quiet > 0.0:
		# siperde: namlu aşağı, ateş yok
		_gun.rest(delta, null, deg_to_rad(-3.0))
		return
	if v == null or not _los:
		_gun.rest(delta, threat_point())
		return
	_react -= delta
	_gun.engage(v, delta, _react <= 0.0)


func _on_hit(amount: float) -> void:
	# mürettebat siper alır (her isabette değil; ağır isabette kesin)
	if _quiet <= 0.0 and (amount > 60.0 or randf() < 0.35):
		_quiet = randf_range(4.0, 8.0)
		_react = randf_range(0.8, 1.5)


## Testler için: atılan mermi sayısı / sessiz mi.
func shots() -> int:
	return _gun.shots


func quiet() -> bool:
	return _quiet > 0.0
