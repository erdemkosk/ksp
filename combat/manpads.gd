class_name Manpads
extends GroundTarget
## Omuzdan atılan ısı güdümlü SAM ekibi (iki asker, bir fırlatıcı, kamuflaj ağı). Radarı yok:
## RWR'da GÖRÜNMEZ, yalnız füze kalktığında füze uyarısı çalar. 4.5 km içinde, yerden 3 km'nin
## altında ve görüş hattındaki sıcak uçağa (art yakıcı uzaktan görülür) birkaç saniyelik nişan
## sonrası IR füze atar. Alçak uçuşun bedeli: radardan saklanan uçak bunlara açık kalır.
## Flare ve motoru kısmak işe yarar. Haritada görünmez (keşfedilmemiş).

const RANGE := 4500.0
const MAX_AGL := 3000.0
const RELOAD := 22.0

var rounds := 2
var _aim := 0.0
var _cool := 0.0
var _tube: Node3D


static func create_team() -> Manpads:
	var t := Manpads.new()
	t.unit_name = "Omuzdan atılan SAM ekibi"
	t.hp = 60.0
	t.objective = false
	t.collision_layer = LAYER
	t.collision_mask = 0
	t.set_meta("hidden", true)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.8, 3.0)
	cs.shape = box
	cs.position = Vector3(0, 0.9, 0)
	t.add_child(cs)
	var olive := Color(0.3, 0.33, 0.22)
	# kamuflaj ağı (yassı, yamalı) ve iki asker
	t._hull = _mesh(t, Vector3(4.0, 0.08, 4.0), Vector3(0, 1.7, 0), Color(0.28, 0.32, 0.2))
	for side in [-0.6, 0.6]:
		_mesh(t, Vector3(0.45, 1.1, 0.3), Vector3(side, 0.55, 0), olive)          # gövde
		_mesh(t, Vector3(0.28, 0.28, 0.28), Vector3(side, 1.25, 0), Color(0.22, 0.25, 0.18))   # kask
	t._tube = Node3D.new()
	t._tube.position = Vector3(0.6, 1.25, 0)
	t.add_child(t._tube)
	var tube := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 1.5
	tube.mesh = cyl
	tube.rotation_degrees = Vector3(-90, 0, 0)
	tube.material_override = SamSite._mat(Color(0.2, 0.24, 0.16))
	t._tube.add_child(tube)
	t._turret = t._tube
	return t


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_alert_tick(delta)
	_cool -= delta
	if rounds <= 0 or _cool > 0.0:
		return
	var v := nearest_enemy_vessel(RANGE)
	var ok := v != null and v.radar_altitude() < MAX_AGL and v.heat_signature() > 0.15 and line_of_sight(v.heat_position())
	if not ok:
		_aim = maxf(_aim - delta, 0.0)
		return
	# nişan: alarmdaysa hızlı, sakinse geç fark eder
	_tube.look_at(v.heat_position(), Planet.up_at(global_position))
	_aim += delta * (1.4 if alerted() else 0.6)
	if _aim > 2.5:
		_aim = 0.0
		_fire(v)


func _fire(v: Vessel) -> void:
	rounds -= 1
	_cool = RELOAD
	var m := Missile.new()
	m.guidance = "ir"
	m.team = team
	m.target = v
	var dir := (v.heat_position() - _tube.global_position).normalized()
	m.velocity = dir * 60.0
	get_parent().add_child(m)
	m.global_position = _tube.global_position + dir * 1.5
	m.look_at(m.global_position + dir, Planet.up_at(global_position))
	Sfx.play_at("missile_launch.ogg", m.global_position, 2.0, 1.2, 4000.0)
