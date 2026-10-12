class_name WorldLife
extends Node3D
## Dünyadaki canlılık:
##   • yollarda gidip gelen arabalar ve kamyonlar (gece farlarıyla)
##   • denizde seyreden gemiler (köpük iziyle)
##   • kasabaların ve kıyının üstünde dönen kuş sürüleri
##   • apronda park etmiş uçaklar (dekor)
## Konumlar başlangıç çerçevesinde (doğu, güney) tutulur ve her karede dünyaya çevrilir,
## böylece kayan orijinden etkilenmez.

const CAR_COUNT := 36
const CAR_COLORS := [Color(0.75, 0.1, 0.08), Color(0.9, 0.9, 0.88), Color(0.12, 0.12, 0.14), Color(0.2, 0.3, 0.55),
	Color(0.55, 0.56, 0.58), Color(0.85, 0.7, 0.2), Color(0.25, 0.4, 0.25)]

var _cars: Array[Dictionary] = []      # {road, seg, t, dir, speed, h, frame}
var _car_mm: MultiMesh
var _lights_mm: MultiMesh
var _ships: Array[Dictionary] = []     # {node, c (Vector2), r, a, speed, wake}
var _birds: Array[Dictionary] = []    # {c, r, alt, a, speed, phase}
var _bird_mm: MultiMesh
var _frame := 0


static func build() -> WorldLife:
	var w := WorldLife.new()
	w.name = "WorldLife"
	return w


func _ready() -> void:
	add_to_group("origin_fixed")
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	_build_cars()
	_build_ships()
	_build_birds()


# ------------------------------------------------------------------ arabalar

func _build_cars() -> void:
	var body := _car_mesh()
	_car_mm = MultiMesh.new()
	_car_mm.transform_format = MultiMesh.TRANSFORM_3D
	_car_mm.use_colors = true
	_car_mm.mesh = body
	_car_mm.instance_count = CAR_COUNT
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _car_mm
	mmi.extra_cull_margin = 30000.0
	add_child(mmi)
	# farlar (gece görünür noktalar)
	var q := QuadMesh.new()
	q.size = Vector2(0.004, 0.004)
	q.material = RunwayLights.light_material(Color(1.0, 0.92, 0.7), 0.004)
	_lights_mm = MultiMesh.new()
	_lights_mm.transform_format = MultiMesh.TRANSFORM_3D
	_lights_mm.mesh = q
	_lights_mm.instance_count = CAR_COUNT
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = _lights_mm
	lmi.extra_cull_margin = 30000.0
	add_child(lmi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in CAR_COUNT:
		var road: Array = Towns.ROADS[rng.randi() % Towns.ROADS.size()]
		var truck := rng.randf() < 0.25
		_cars.append({"road": road, "seg": rng.randi() % (road.size() - 1), "t": rng.randf(), "dir": 1 if rng.randf() < 0.5 else -1,
			"speed": rng.randf_range(14.0, 24.0) * (0.75 if truck else 1.0), "h": -1.0, "truck": truck})
		_car_mm.set_instance_color(i, Color(0.35, 0.38, 0.3) if truck else CAR_COLORS[rng.randi() % CAR_COLORS.size()])


static func _car_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(1.8, 0.7, 4.3), Vector3(0, 0.6, 0))
	_box(st, Vector3(1.6, 0.6, 2.2), Vector3(0, 1.2, 0.2))
	for z in [-1.4, 1.4]:
		for x in [-0.85, 0.85]:
			_box(st, Vector3(0.25, 0.6, 0.6), Vector3(x, 0.3, z))
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	mat.metallic = 0.3
	m.surface_set_material(0, mat)
	return m


static func _box(st: SurfaceTool, size: Vector3, c: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	var arr := b.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		st.add_vertex(verts[i] + c)


func _update_cars(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var night := _night()
	for i in _cars.size():
		var car: Dictionary = _cars[i]
		var road: Array = car["road"]
		var seg: int = car["seg"]
		var a: Vector2 = road[seg]
		var b: Vector2 = road[seg + 1]
		var l := maxf(a.distance_to(b), 1.0)
		car["t"] = float(car["t"]) + int(car["dir"]) * float(car["speed"]) * delta / l
		if car["t"] > 1.0:
			if seg + 2 < road.size():
				car["seg"] = seg + 1
				car["t"] = float(car["t"]) - 1.0
			else:
				car["t"] = 1.0
				car["dir"] = -1
		elif car["t"] < 0.0:
			if seg > 0:
				car["seg"] = seg - 1
				car["t"] = float(car["t"]) + 1.0
			else:
				car["t"] = 0.0
				car["dir"] = 1
		seg = car["seg"]
		a = road[seg]
		b = road[seg + 1]
		var dirv := (b - a).normalized() * int(car["dir"])
		# sağdan gidiş: yön vektörünün sağına 3 m kay
		var xz := a.lerp(b, clampf(car["t"], 0.0, 1.0)) + Vector2(-dirv.y, dirv.x) * 3.0
		# yükseklik pahalı: her araç için 20 karede bir
		if float(car["h"]) < -0.5 or (_frame + i) % 20 == 0:
			car["h"] = Towns.road_height(xz.x, xz.y)
		var pos := MissionManager.world_point(xz.x, xz.y, float(car["h"]) + 0.05)
		var fr := Planet.local_basis(pos)
		var yaw := atan2(-dirv.x, -dirv.y)
		var s := 1.4 if car["truck"] else 1.0
		var xf := Transform3D((fr * Basis(Vector3.UP, yaw)).scaled(Vector3(1, s, s)), pos)
		_car_mm.set_instance_transform(i, xf)
		var far := cam != null and cam.global_position.distance_to(pos) > 12000.0
		_lights_mm.set_instance_transform(i, Transform3D(Basis(), xf * Vector3(0, 0.7, -2.3)) if night and not far else Transform3D(Basis().scaled(Vector3.ZERO), pos))


func _night() -> bool:
	var h := Weather.local_hour(Planet.center() + Vector3(0, Planet.RADIUS, 0))
	return h < 6.5 or h > 19.0


# ------------------------------------------------------------------ gemiler

func _build_ships() -> void:
	# kıyıdan açıkta derin su noktaları ara
	var found: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 400:
		if found.size() >= 4:
			break
		var p := Vector2(rng.randf_range(-30000, 30000), rng.randf_range(-30000, 20000))
		if MissionManager.ground_height(p.x, p.y) > 0.0 or TerrainGen.height(Vector3(p.x, TerrainGen.RADIUS, p.y).normalized()) > -25.0:
			continue
		var ok := true
		for q in found:
			if q.distance_to(p) < 5000.0:
				ok = false
		# rota boyunca da su olsun
		for j in 8:
			var a := TAU * j / 8.0
			var rp := p + Vector2(cos(a), sin(a)) * 900.0
			if TerrainGen.height(Vector3(rp.x, TerrainGen.RADIUS, rp.y).normalized()) > -8.0:
				ok = false
		if ok:
			found.append(p)
	for i in found.size():
		var node := _ship_node(i % 2 == 0)
		add_child(node)
		var wake := PuffTrail.create(node, Vector3(0, 0.5, 30.0), "leak")
		wake.life = 9.0
		wake.size0 = 2.0
		wake.size1 = 9.0
		wake.c0 = Color(0.95, 0.97, 1.0, 0.5)
		wake.spacing = 6.0
		wake.rate = 2.0
		_ships.append({"node": node, "c": found[i], "r": 900.0, "a": rng.randf() * TAU, "speed": rng.randf_range(6.0, 10.0) * (1.0 if i % 2 == 0 else -1.0)})


static func _ship_node(cargo: bool) -> Node3D:
	var n := Node3D.new()
	var hull := MeshInstance3D.new()
	hull.mesh = MeshFactory.lathe([Vector2(-34.0, 0.0), Vector2(-28.0, 4.5), Vector2(24.0, 5.0), Vector2(32.0, 3.5)], 16, 0.55, 180.0, 360.0)
	hull.position = Vector3(0, 2.6, 0)
	hull.material_override = SamSite._mat(Color(0.55, 0.1, 0.08) if cargo else Color(0.85, 0.85, 0.85))
	n.add_child(hull)
	var deck := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(9.0, 0.5, 60.0)
	deck.mesh = b
	deck.position = Vector3(0, 2.7, 0)
	deck.material_override = SamSite._mat(Color(0.3, 0.3, 0.32))
	n.add_child(deck)
	var bridge := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(8.0, 7.0, 7.0)
	bridge.mesh = bb
	bridge.position = Vector3(0, 6.5, 22.0)
	bridge.material_override = SamSite._mat(Color(0.92, 0.92, 0.9))
	n.add_child(bridge)
	if cargo:
		for k in 5:
			var c := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(7.5, 2.6, 6.0)
			c.mesh = cb
			c.position = Vector3(0, 4.3, -20.0 + k * 7.5)
			c.material_override = SamSite._mat([Color(0.15, 0.35, 0.6), Color(0.7, 0.3, 0.1), Color(0.2, 0.5, 0.3)][k % 3])
			n.add_child(c)
	return n


func _update_ships(delta: float) -> void:
	for s in _ships:
		s["a"] = float(s["a"]) + float(s["speed"]) / float(s["r"]) * delta
		var a: float = s["a"]
		var c: Vector2 = s["c"]
		var xz := c + Vector2(cos(a), sin(a)) * float(s["r"])
		var tangent := Vector2(-sin(a), cos(a)) * signf(float(s["speed"]))
		var pos := MissionManager.world_point(xz.x, xz.y, 0.0)
		var fr := Planet.local_basis(pos)
		var roll := sin(Time.get_ticks_msec() * 0.0007 + a * 10.0) * 0.02
		(s["node"] as Node3D).global_transform = Transform3D(fr * Basis(Vector3.UP, atan2(-tangent.x, -tangent.y)) * Basis(Vector3.BACK, roll), pos)


# ------------------------------------------------------------------ kuşlar

func _build_birds() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		st.add_vertex(Vector3(0, 0, -0.15))
		st.add_vertex(Vector3(side * 0.55, 0.12, 0.05))
		st.add_vertex(Vector3(0, 0, 0.2))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var centers: Array[Vector2] = []
	for t: Dictionary in Towns.TOWNS:
		centers.append(t["xz"])
	centers.append(Vector2(2500, -1500))
	centers.append(Vector2(-4000, 1500))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for c in centers:
		for k in 14:
			_birds.append({"c": c + Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200)), "r": rng.randf_range(60.0, 160.0),
				"alt": rng.randf_range(60.0, 180.0), "a": rng.randf() * TAU, "speed": rng.randf_range(9.0, 13.0), "phase": rng.randf() * TAU, "h": -1.0})
	_bird_mm = MultiMesh.new()
	_bird_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bird_mm.mesh = mesh
	_bird_mm.instance_count = _birds.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _bird_mm
	mmi.extra_cull_margin = 30000.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _update_birds(delta: float) -> void:
	var tsec := Time.get_ticks_msec() * 0.001
	for i in _birds.size():
		var b: Dictionary = _birds[i]
		b["a"] = float(b["a"]) + float(b["speed"]) / float(b["r"]) * delta
		var a: float = b["a"]
		var c: Vector2 = b["c"]
		var xz := c + Vector2(cos(a), sin(a)) * float(b["r"])
		if float(b["h"]) < -0.5 or (_frame + i) % 60 == 0:
			b["h"] = MissionManager.ground_height(xz.x, xz.y)
		var alt := float(b["h"]) + float(b["alt"]) + sin(a * 3.0) * 6.0
		var pos := MissionManager.world_point(xz.x, xz.y, alt)
		var fr := Planet.local_basis(pos)
		var tangent := Vector2(-sin(a), cos(a))
		var flap := 0.55 + 0.45 * sin(tsec * 9.0 + float(b["phase"]))
		var bs := Basis(Vector3.UP, atan2(-tangent.x, -tangent.y)) * Basis(Vector3.BACK, 0.25)
		_bird_mm.set_instance_transform(i, Transform3D((fr * bs).scaled(Vector3(1.4, flap * 1.6, 1.4)), pos))


# ------------------------------------------------------------------ apron dekoru

## Apronda park etmiş uçaklar: uçak tasarımından yalnız görseller alınır (fizik yok).
static func parked(index: int) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Parked%d" % index
	var c := "res://crafts/"
	var specs := [
		[c + "turna.json", Vector3(165, 0, 245), 90.0, "sivil"], [c + "turna.json", Vector3(165, 0, 300), 90.0, "kırmızı-beyaz"],
		[c + "katir.json", Vector3(170, 0, 370), 90.0, "deniz"], [c + "kirlangic.json", Vector3(175, 0, 425), 90.0, "sivil"],
		[c + "kirlangic.json", Vector3(175, 0, 465), 90.0, "kırmızı-beyaz"], [c + "kartal_1.json", Vector3(245, 0, 400), 90.0, "gri"],
		[c + "kartal_1.json", Vector3(245, 0, 440), 90.0, "gri"], [c + "sahin_b.json", Vector3(245, 0, 490), 90.0, "kamuflaj"],
	] if index == 0 else [
		[c + "turna.json", Vector3(165, 0, 270), 90.0, "sivil"], [c + "kirlangic.json", Vector3(175, 0, 340), 90.0, "kırmızı-beyaz"],
		[c + "kartal_1.json", Vector3(245, 0, 380), 90.0, "gri"],
	]
	for sp in specs:
		var craft := VesselBuilder.load_craft(sp[0])
		var civil_paint: bool = sp[3] in ["sivil", "kırmızı-beyaz"]
		craft["paint"] = {"scheme": sp[3], "number": ("TC-%s" % ["PRK", "MLT", "ACR", "JNA", "SKY"][randi() % 5]) if civil_paint else str(10 + randi() % 80)}
		var v := VesselBuilder.build(craft)
		var plane := Node3D.new()
		plane.position = sp[1]
		plane.rotation.y = deg_to_rad(sp[2])
		holder.add_child(plane)
		for p in v.parts:
			var vis := p.get_node_or_null("Visual")
			if vis:
				var xf: Transform3D = p.transform * vis.transform
				p.remove_child(vis)
				plane.add_child(vis)
				vis.transform = xf
		# tekerlek yerden: en alçak noktayı yaklaşık 1.7 m yukarıda tut
		plane.position.y = 2.2 * PartLibrary.WORLD_SCALE + 0.05
		v.free()
	return holder


func _physics_process(delta: float) -> void:
	_frame += 1
	_update_cars(delta)
	_update_ships(delta)
	_update_birds(delta)
