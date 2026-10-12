class_name GroundTarget
extends StaticBody3D
## Basit yer hedefi (zırhlı araç). Canı biter: patlar, yanık kabuğa döner, duman tüter.

const LAYER := 8

var hp := 600.0
var destroyed := false
## Görev sayacına girer mi (konvoy aracı evet, refakat uçaksavarı hayır)
var objective := true
var unit_name := "Zırhlı araç"
## Ateş eden birimlerin hedef seçimi için
var team := "düşman"
var _hull: Node3D
var _turret: Node3D


static func create(pos: Vector3, yaw: float) -> GroundTarget:
	var t := GroundTarget.new()
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.2, 6.5)
	cs.shape = box
	cs.position = Vector3(0, 1.1, 0)
	t.add_child(cs)
	t._hull = _mesh(t, Vector3(3.4, 1.3, 6.5), Vector3(0, 0.85, 0), Color(0.33, 0.36, 0.26))
	t._turret = _mesh(t, Vector3(2.2, 0.8, 2.6), Vector3(0, 1.9, -0.3), Color(0.3, 0.33, 0.24))
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.12
	cyl.height = 3.8
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(-90, 0, 0)
	barrel.position = Vector3(0, 0, -2.6)
	barrel.material_override = t._hull.material_override
	t._turret.add_child(barrel)
	for side in [-1.0, 1.0]:
		_mesh(t, Vector3(0.7, 0.9, 6.7), Vector3(side * 1.55, 0.45, 0), Color(0.12, 0.12, 0.11))
	t.position = pos
	t.rotation.y = yaw
	return t


static func _mesh(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	parent.add_child(mi)
	return mi


func take_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		destroyed = true
		var up := Planet.up_at(global_position)
		Effects.explosion(FloatingOrigin.world_root, global_position + up * 1.5, up, 2.5)
		Sfx.explosion(global_position, 2.0)
		_burn(self)
		if _turret:
			_turret.position += Vector3(randf_range(-1, 1), 0.8, randf_range(-1, 1))
			_turret.rotation_degrees = Vector3(randf_range(-25, 25), randf_range(0, 360), randf_range(-25, 25))
		_on_destroyed()
		var smoke := Effects.smoke_column()
		add_child(smoke)
		smoke.position = Vector3(0, 2, 0)


## Alt sınıflar için: yok olunca ek davranış (helikopter düşer, kamyon durur…).
func _on_destroyed() -> void:
	pass


## Tüm görselleri yanık kabuk rengine çevir.
static func _burn(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = c.material_override.duplicate()
			m.albedo_color = Color(0.07, 0.065, 0.06)
			m.emission_enabled = false
			c.material_override = m
		_burn(c)


## En yakın düşman uçağı (oyuncu ya da dost), menzil içinde.
func nearest_enemy_vessel(max_range: float) -> Vessel:
	var best: Vessel = null
	var bd := max_range
	for n in get_parent().get_children():
		if n is Vessel and n.team != team and not n.parts.is_empty() and n.has_pilot():
			var d: float = n.com_global().distance_to(global_position)
			if d < bd:
				bd = d
				best = n
	return best


## Arada arazi var mı (radar / görüş hattı).
func line_of_sight(to: Vector3) -> bool:
	# arazi çarpışması yalnız odak çevresinde var: hattı arazi yüksekliğiyle örnekle
	var from := global_position + Planet.up_at(global_position) * 4.0
	for i in range(1, 20):
		var p := from.lerp(to, i / 20.0)
		if Planet.altitude(p) < TerrainGen.height(Planet.surface_dir(p)) + 2.0:
			return false
	return true
