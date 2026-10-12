class_name Towns
## Adlı kasabalar (bina kümeleri, yüksek bina/kule) ve onları havaalanlarına bağlayan yollar.
## Konumlar başlangıç çerçevesinde yüzey koordinatı: x doğu, z güney (metre).
## Yükseklik TerrainGen'den; yollar araziyi izleyen asfalt şeritler (orta çizgili).

const TOWNS := [
	{"name": "Ovaköy", "xz": Vector2(-10000, -12000), "r": 420.0, "n": 140},
	{"name": "Kuzeykent", "xz": Vector2(-22500, -17200), "r": 650.0, "n": 260},
	{"name": "Yeşilyurt", "xz": Vector2(-20000, -21500), "r": 380.0, "n": 110},
	{"name": "Dereköy", "xz": Vector2(6000, -22000), "r": 350.0, "n": 90},
]

## Yol ağı: her yol bir nokta dizisi (yüzey koordinatı).
const ROADS := [
	[Vector2(300, -650), Vector2(-3000, -5000), Vector2(-7000, -9500), Vector2(-10000, -12000)],
	[Vector2(-10000, -12000), Vector2(-15000, -14500), Vector2(-19500, -16200), Vector2(-22500, -17200)],
	[Vector2(-22500, -17200), Vector2(-24300, -15500), Vector2(-25700, -14400)],
	[Vector2(-10000, -12000), Vector2(-14000, -17500), Vector2(-20000, -21500)],
	[Vector2(-10000, -12000), Vector2(-3000, -17000), Vector2(6000, -22000)],
]

const R := TerrainGen.RADIUS


static func world_at(x: float, z: float, lift := 0.0) -> Vector3:
	var d := Vector3(x, R, z).normalized()
	return Vector3(0, -R, 0) + d * (R + maxf(TerrainGen.height(d), 0.0) + lift)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Towns"
	for t: Dictionary in TOWNS:
		root.add_child(_town(t))
	for r: Array in ROADS:
		root.add_child(_road(r))
	for rv in TerrainGen.rivers:
		root.add_child(_river_mesh(rv))
	for b in bridges():
		root.add_child(_bridge(b))
	return root


## Kasabanın dünya konumu (başlangıç çerçevesinde) — görevler ve radyo için.
static func town_point(name: String) -> Vector2:
	for t: Dictionary in TOWNS:
		if t["name"] == name:
			return t["xz"]
	return Vector2.ZERO


static var _building_mat: ShaderMaterial


## Gece pencere ışıkları (SkyController çağırır).
static func set_night(n: float) -> void:
	if _building_mat:
		_building_mat.set_shader_parameter("night", n)


static func _town(t: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t["name"])
	var c: Vector2 = t["xz"]
	var radius: float = t["r"]
	if _building_mat == null:
		_building_mat = ShaderMaterial.new()
		_building_mat.shader = preload("res://world/building.gdshader")
	var walls: Array[Transform3D] = []
	var wall_cols: Array[Color] = []
	var roofs: Array[Transform3D] = []
	var roof_cols: Array[Color] = []
	var palette := [Color(0.86, 0.82, 0.74), Color(0.78, 0.7, 0.6), Color(0.9, 0.88, 0.84), Color(0.7, 0.6, 0.52),
		Color(0.82, 0.76, 0.66), Color(0.88, 0.8, 0.62), Color(0.75, 0.78, 0.8)]
	var roof_palette := [Color(0.62, 0.22, 0.14), Color(0.55, 0.25, 0.18), Color(0.45, 0.2, 0.15), Color(0.36, 0.34, 0.33)]
	for i in int(t["n"]):
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * radius
		var x := c.x + cos(a) * rr
		var z := c.y + sin(a) * rr
		var d := Vector3(x, R, z).normalized()
		if TerrainGen.height(d) < 1.0 or TerrainGen.in_airfield(d, 200.0):
			continue
		var riv := TerrainGen.river_at(x, z)
		if not riv.is_empty() and float(riv["dist"]) < float(riv["width"]) * 0.5 + 25.0:
			continue
		var center_bias := 1.0 - rr / radius
		var floors := 1 + int(rng.randf() * (2.0 + center_bias * 6.0))
		var house := floors <= 2
		var size := Vector3(rng.randf_range(8, 13), floors * 3.2, rng.randf_range(9, 15)) if house \
			else Vector3(rng.randf_range(12, 22), floors * 3.2, rng.randf_range(12, 26))
		var base := world_at(x, z)
		var up := (base - Vector3(0, -R, 0)).normalized()
		var b := Basis(Vector3(1, 0, 0) - up * up.x, up, Vector3(0, 0, 1) - up * up.z).orthonormalized()
		b = b.rotated(up, rng.randf() * TAU)
		walls.append(Transform3D(b.scaled_local(size), base + up * (size.y * 0.5 - 0.5)))
		wall_cols.append(palette[rng.randi() % palette.size()])
		if house:
			var rh := size.x * 0.32
			roofs.append(Transform3D(b.scaled_local(Vector3(size.x * 1.08, rh, size.z * 1.06)), base + up * (size.y - 0.5)))
			roof_cols.append(roof_palette[rng.randi() % roof_palette.size()])
	# kasaba merkezinde yüksek bina / kule
	var cb := world_at(c.x, c.y)
	var cup := (cb - Vector3(0, -R, 0)).normalized()
	var tb := Basis(Vector3(1, 0, 0) - cup * cup.x, cup, Vector3(0, 0, 1) - cup * cup.z).orthonormalized()
	walls.append(Transform3D(tb.scaled_local(Vector3(9, 38, 9)), cb + cup * 18.5))
	wall_cols.append(Color(0.92, 0.92, 0.9))
	var root := Node3D.new()
	root.name = String(t["name"])
	var box := BoxMesh.new()
	box.material = _building_mat
	root.add_child(_mm(box, walls, wall_cols))
	root.add_child(_mm(_roof_mesh(), roofs, roof_cols))
	return root


static func _mm(mesh: Mesh, xs: Array[Transform3D], cols: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## Beşik çatı: birim taban (x, z: -0.5..0.5), tepe y = 1, mahya z boyunca.
static func _roof_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5),
		Vector3(0, 1, -0.5), Vector3(0, 1, 0.5)]
	for tri in [[0, 4, 5], [0, 5, 3], [1, 2, 5], [1, 5, 4], [0, 1, 4], [3, 5, 2]]:
		for k in tri:
			st.add_vertex(p[k])
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	return m


static func _road(pts: Array) -> MeshInstance3D:
	# noktaları 30 m aralıkla sık örnekle, hafif kıvrım ekle
	var samples := road_samples(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 4.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_ok := false
	for i in samples.size():
		var s := samples[i]
		var d := Vector3(s.x, R, s.y).normalized()
		var h := road_height(s.x, s.y)
		var ok := h > 0.6
		var p := Vector3(0, -R, 0) + d * (R + h + 0.35)
		var nxt: Vector2 = samples[mini(i + 1, samples.size() - 1)]
		var prv: Vector2 = samples[maxi(i - 1, 0)]
		var dir2 := (nxt - prv).normalized()
		var up := (p - Vector3(0, -R, 0)).normalized()
		var fwd := (Vector3(dir2.x, 0, dir2.y) - up * Vector3(dir2.x, 0, dir2.y).dot(up)).normalized()
		var side := fwd.cross(up).normalized()
		var l := p - side * w
		var r := p + side * w
		if ok and prev_ok:
			# asfalt
			st.set_color(Color(0.2, 0.2, 0.21))
			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(r)
			st.add_vertex(prev_l)
			st.add_vertex(r)
			st.add_vertex(prev_r)
			# kesik orta çizgi
			if i % 2 == 0:
				var c0 := (prev_l + prev_r) * 0.5 + up * 0.05
				var c1 := (l + r) * 0.5 + up * 0.05
				var cw := side * 0.18
				st.set_color(Color(0.9, 0.88, 0.8))
				st.add_vertex(c0 - cw)
				st.add_vertex(c1 - cw)
				st.add_vertex(c1 + cw)
				st.add_vertex(c0 - cw)
				st.add_vertex(c1 + cw)
				st.add_vertex(c0 + cw)
		prev_l = l
		prev_r = r
		prev_ok = ok
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Yolun kıvrımlı örnek noktaları (30 m aralık) — yol çizimi ve köprü bulma aynı yolu kullanır.
static func road_samples(pts: Array) -> Array[Vector2]:
	var samples: Array[Vector2] = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / 30.0)
		var perp := (b - a).normalized().orthogonal()
		for k in n:
			var t := float(k) / n
			var wob := sin(t * PI * 3.0 + i) * 60.0 * sin(t * PI)
			samples.append(a.lerp(b, t) + perp * wob)
	samples.append(pts[-1])
	return samples


# ------------------------------------------------------------------ nehirler ve köprüler

static var _bridges: Array = []
static var _bridges_done := false


## Yol-nehir kesişimleri: [{xz, dir (yol), width, level}]
static func bridges() -> Array:
	if _bridges_done:
		return _bridges
	_bridges_done = true
	_bridges.clear()
	for road: Array in ROADS:
		var s := road_samples(road)
		for rv in TerrainGen.rivers:
			var pts: PackedVector2Array = rv["pts"]
			var lv: PackedFloat32Array = rv["level"]
			var wd: PackedFloat32Array = rv["width"]
			for i in s.size() - 1:
				for j in pts.size() - 1:
					var hit: Variant = Geometry2D.segment_intersects_segment(s[i], s[i + 1], pts[j], pts[j + 1])
					if hit != null:
						_bridges.append({"xz": hit, "dir": (s[i + 1] - s[i]).normalized(), "width": wd[j], "level": lv[j]})
	return _bridges


## Yol yüzeyinin yüksekliği: arazi, ama köprü yaklaşımlarında köprü güvertesine rampa.
static func road_height(x: float, z: float) -> float:
	var h := maxf(TerrainGen.height(Vector3(x, R, z).normalized()), 0.0)
	for b in bridges():
		var d := (b["xz"] as Vector2).distance_to(Vector2(x, z))
		var reach := float(b["width"]) * 0.5 + TerrainGen.RIVER_BANK + 60.0
		if d < reach:
			var deck := float(b["level"]) + 5.0
			h = maxf(h, lerpf(deck, h, smoothstep(float(b["width"]) * 0.5 + 8.0, reach, d)))
	return h


static func _river_mesh(rv: Dictionary) -> MeshInstance3D:
	var pts: PackedVector2Array = rv["pts"]
	var lv: PackedFloat32Array = rv["level"]
	var wd: PackedFloat32Array = rv["width"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var side2 := (b - a).normalized().orthogonal() * (wd[i] * 0.5 + 4.0)
		var l2 := pts[i] - side2
		var r2 := pts[i] + side2
		var y := lv[i] + 1.2
		var l := Vector3(0, -R, 0) + Vector3(l2.x, R, l2.y).normalized() * (R + y)
		var r := Vector3(0, -R, 0) + Vector3(r2.x, R, r2.y).normalized() * (R + y)
		if i > 0:
			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(r)
			st.add_vertex(prev_l)
			st.add_vertex(r)
			st.add_vertex(prev_r)
		prev_l = l
		prev_r = r
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.2, 0.19)
	m.roughness = 0.12
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _bridge(b: Dictionary) -> Node3D:
	var xz: Vector2 = b["xz"]
	var dir: Vector2 = b["dir"]
	var w := float(b["width"])
	var deck_h := float(b["level"]) + 5.0
	var pos := Vector3(0, -R, 0) + Vector3(xz.x, R, xz.y).normalized() * (R + deck_h)
	var up := (pos - Vector3(0, -R, 0)).normalized()
	var fwd := Vector3(dir.x, 0, dir.y)
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var side := fwd.cross(up).normalized()
	var n := Node3D.new()
	n.name = "Bridge"
	n.transform = Transform3D(Basis(side, up, -fwd), pos)
	var length := w + 40.0
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.62, 0.6, 0.56)
	concrete.roughness = 0.9
	_bridge_box(n, Vector3(11.0, 1.2, length), Vector3(0, -0.6, 0), concrete)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.2, 0.2, 0.21)
	_bridge_box(n, Vector3(8.4, 0.1, length), Vector3(0, 0.05, 0), asphalt)
	for sx in [-5.3, 5.3]:
		_bridge_box(n, Vector3(0.3, 1.0, length), Vector3(sx, 0.5, 0), concrete)
	# ayaklar: nehir yatağına
	var piers := maxi(int(w / 25.0), 1)
	for k in piers + 1:
		var z := lerpf(-w * 0.5, w * 0.5, float(k) / piers) if piers > 0 else 0.0
		_bridge_box(n, Vector3(2.0, 8.0, 2.0), Vector3(0, -5.0, z), concrete)
	return n


static func _bridge_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
