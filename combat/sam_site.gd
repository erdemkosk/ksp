class_name SamSite
extends GroundTarget
## Yerden havaya füze (SAM) rampası: dönen arama radarı + 4 tüplü fırlatıcı.
## Uçak menzile (9 km) girip arazinin üstünde görünür olunca (yerden 120 m+) radar kilitlenir,
## birkaç saniye sonra füze atar. Füzeler oyuncunun IR füzesiyle aynı güdümü kullanır; flare
## ve sert manevra ile atlatılır. Alçak uçuş (arazi maskeleme) radardan saklar.

const RANGE := 9000.0
const MIN_AGL := 120.0
const LOCK_TIME := 3.5
const RELOAD := 13.0

var missiles := 4
var _radar: Node3D
var _launcher: Node3D
var _lock_t := 0.0
var _cool := 4.0
var _target: Vessel
var _warned := false


static func create_sam(pos: Vector3, yaw: float) -> SamSite:
	var t := SamSite.new()
	t.hp = 450.0
	t.unit_name = "SAM rampası"
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 3.0, 8.0)
	cs.shape = box
	cs.position = Vector3(0, 1.5, 0)
	t.add_child(cs)
	var olive := Color(0.3, 0.33, 0.24)
	t._hull = _mesh(t, Vector3(3.0, 1.4, 8.0), Vector3(0, 1.0, 0), olive)
	_mesh(t, Vector3(2.8, 1.5, 2.2), Vector3(0, 2.2, -2.8), olive.darkened(0.1))      # kabin
	for side in [-1.0, 1.0]:
		for k in 4:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.55
			cyl.height = 0.5
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(side * 1.5, 0.55, -3.0 + k * 2.0)
			w.material_override = _mat(Color(0.1, 0.1, 0.1))
			t.add_child(w)
	# fırlatıcı: 4 tüp, 45° yukarı bakar, dönebilir
	t._launcher = Node3D.new()
	t._launcher.position = Vector3(0, 2.0, 1.4)
	t.add_child(t._launcher)
	for i in 4:
		var tube := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.28
		cyl.height = 5.0
		tube.mesh = cyl
		tube.position = Vector3((i % 2 - 0.5) * 0.62, 0.6 + (i / 2) * 0.62, 0)
		tube.rotation_degrees = Vector3(-45, 0, 0)
		tube.material_override = _mat(Color(0.36, 0.4, 0.3))
		t._launcher.add_child(tube)
	t._turret = t._launcher
	# radar anteni
	t._radar = Node3D.new()
	t._radar.position = Vector3(0, 3.4, -2.8)
	t.add_child(t._radar)
	var dish := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 1.0, 0.12)
	dish.mesh = bm
	dish.position = Vector3(0, 0.5, 0)
	dish.material_override = _mat(Color(0.75, 0.75, 0.7))
	t._radar.add_child(dish)
	t.position = pos
	t.rotation.y = yaw
	return t


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_radar.rotate_y(delta * (6.0 if _target else 2.0))
	_cool -= delta
	var v := nearest_enemy_vessel(RANGE)
	var visible_ok := false
	if v:
		var agl := v.radar_altitude()
		visible_ok = agl > MIN_AGL and line_of_sight(v.com_global())
	if visible_ok:
		_target = v
		_lock_t += delta
		# fırlatıcı hedefe döner
		var local := to_local(v.com_global())
		_launcher.rotation.y = lerp_angle(_launcher.rotation.y, atan2(-local.x, -local.z), 1.0 - exp(-2.0 * delta))
		if not _warned:
			_warned = true
			v.system_message.emit("RADAR UYARISI: SAM kilitleniyor!")
		if _lock_t > LOCK_TIME and _cool <= 0.0 and missiles > 0:
			_fire(v)
	else:
		_target = null
		_lock_t = maxf(_lock_t - delta * 2.0, 0.0)
		_warned = false


func _fire(v: Vessel) -> void:
	missiles -= 1
	_cool = RELOAD
	var up := Planet.up_at(global_position)
	var to := (v.com_global() - global_position).normalized()
	var m := Missile.new()
	m.velocity = (up * 0.7 + to * 0.3).normalized() * 45.0
	m.target = v
	get_parent().add_child(m)
	m.global_position = _launcher.global_position + up * 2.5
	m.look_at(m.global_position + m.velocity, up)
	Sfx.play_at("missile_launch.ogg", m.global_position, 6.0, 0.85, 8000.0)
	v.system_message.emit("SAM ATIŞI! — flare at, sert dön, alçal")


func _on_destroyed() -> void:
	missiles = 0
