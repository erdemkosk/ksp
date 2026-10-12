class_name RadarStation
extends GroundTarget
## Radar istasyonu. Erken uyarı (EW): kule üstünde dönen büyük anten, ~60 km. Gördüğü düşman
## uçaklarını takımına bildirir (Detection.report): düşman avcıları ve SAM'lar seni "bilir".
## İlk görüşte `spotted` sinyali (görev avcı kaldırır, havaalanı alarma geçer).
## Uzun menzilli SAM'ın arama radarı da bir RadarStation'dır (kamyon üstünde, 40 km).
## Yayın yaptığı için radar avcısı füzenin (HARM) hedefidir.

signal spotted(v: Vessel)

static var stations: Array[RadarStation] = []

var range_m := 60000.0
var _antenna: Node3D
var _scan := 0.0
var _seen := {}            ## Vessel -> true (ilk görüş sinyali için)


## Sabit erken uyarı radarı: beton bina, kafes kule, dönen ağ anten.
static func create_station(title := "Erken uyarı radarı", reach := 60000.0) -> RadarStation:
	var t := RadarStation.new()
	t.unit_name = title
	t.range_m = reach
	t.hp = 800.0
	_body(t, Vector3(7, 7, 7))
	_mesh(t, Vector3(7, 3.2, 7), Vector3(0, 1.6, 0), Color(0.55, 0.55, 0.52))       # bina
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := _mesh(t, Vector3(0.35, 9.0, 0.35), Vector3(sx * 1.6, 7.6, sz * 1.6), Color(0.42, 0.44, 0.42))
			leg.rotation_degrees = Vector3(sz * 6.0, 0, -sx * 6.0)
	_mesh(t, Vector3(4.2, 0.4, 4.2), Vector3(0, 12.0, 0), Color(0.4, 0.42, 0.4))
	t._antenna = Node3D.new()
	t._antenna.position = Vector3(0, 13.2, 0)
	t.add_child(t._antenna)
	var dish := _mesh(t._antenna, Vector3(11.0, 3.4, 0.3), Vector3(0, 1.4, 0), Color(0.82, 0.83, 0.8))
	dish.rotation_degrees = Vector3(-12, 0, 0)
	for i in 7:
		var rib := _mesh(t._antenna, Vector3(0.12, 3.5, 0.6), Vector3(-5.1 + i * 1.7, 1.4, 0.3), Color(0.5, 0.5, 0.48))
		rib.rotation_degrees = Vector3(-12, 0, 0)
	return t


## Kamyon üstünde arama radarı (uzun menzilli SAM bataryası).
static func create_mobile(title := "SAM arama radarı", reach := 40000.0) -> RadarStation:
	var t := RadarStation.new()
	t.unit_name = title
	t.range_m = reach
	t.hp = 350.0
	_truck_body(t, Color(0.32, 0.35, 0.26))
	t._antenna = Node3D.new()
	t._antenna.position = Vector3(0, 4.6, 1.0)
	t.add_child(t._antenna)
	var dish := _mesh(t._antenna, Vector3(5.5, 2.2, 0.25), Vector3(0, 0.8, 0), Color(0.62, 0.64, 0.58))
	dish.rotation_degrees = Vector3(-15, 0, 0)
	_mesh(t, Vector3(0.5, 2.2, 0.5), Vector3(0, 3.4, 1.0), Color(0.3, 0.33, 0.24))
	return t


## Radarsız / sabit antenli kamyon (SAM takip radarı vb.).
static func make_truck(title: String, hp_value: float, panel: Vector3 = Vector3.ZERO) -> GroundTarget:
	var t := GroundTarget.new()
	t.unit_name = title
	t.hp = hp_value
	_truck_body(t, Color(0.32, 0.35, 0.26))
	if panel != Vector3.ZERO:
		var p := _mesh(t, panel, Vector3(0, 3.6, 1.2), Color(0.6, 0.62, 0.56))
		p.rotation_degrees = Vector3(-35, 0, 0)
	return t


static func _body(t: GroundTarget, size: Vector3) -> void:
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	t.add_child(cs)


static func _truck_body(t: GroundTarget, col: Color) -> void:
	_body(t, Vector3(2.8, 3.0, 8.5))
	t._hull = _mesh(t, Vector3(2.6, 1.4, 6.0), Vector3(0, 1.5, 1.0), col)        # kasa
	_mesh(t, Vector3(2.6, 1.9, 2.0), Vector3(0, 1.7, -3.1), col.darkened(0.1))     # kabin
	_mesh(t, Vector3(2.2, 0.6, 0.05), Vector3(0, 2.2, -4.12), Color(0.12, 0.16, 0.2))  # cam
	for z in [-3.0, 0.2, 2.6]:
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.55
			cyl.height = 0.45
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(side * 1.3, 0.55, z)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.08, 0.08, 0.08)
			w.material_override = m
			t.add_child(w)


func _enter_tree() -> void:
	stations.append(self)


func _exit_tree() -> void:
	stations.erase(self)


func emitting() -> bool:
	return not destroyed


func emitter_position() -> Vector3:
	return _antenna.global_position if _antenna else global_position


func sees(v: Vessel) -> bool:
	return emitting() and Detection.radar_sees(emitter_position(), range_m, v, true)


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_alert_tick(delta)
	if _antenna:
		_antenna.rotate_y(delta * 1.4)
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.5
	for n in get_parent().get_children():
		if n is Vessel and n.team != team and n.team != "sivil" and not n.parts.is_empty() and n.has_pilot():
			if sees(n):
				Detection.report(team, n)
				if not _seen.has(n):
					_seen[n] = true
					spotted.emit(n)
					n.system_message.emit("RWR: ERKEN UYARI RADARI SENİ GÖRDÜ")
