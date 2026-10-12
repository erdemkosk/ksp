class_name RunwayLights
## Pist ışıkları: ekranda sabit boyda parlayan noktalar (uzaktan ve gece görünür).
##   • kenar ışıkları (beyaz, son 600 m sarı), eşik (yeşil) ve pist sonu (kırmızı)
##   • yaklaşma ışık hattı: eşikten 900 m dışarıya, 300 m'de çapraz bar, sıralı çakar ("tavşan")
##   • PAPI: dokunma noktasının solunda 4 ışık; bakış açısı 3°'deyken 2 beyaz + 2 kırmızı
##     (hepsi beyaz = çok yüksek, hepsi kırmızı = çok alçak)

static var _dot: ImageTexture


static func dot_texture() -> ImageTexture:
	if _dot:
		return _dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.6)))
	_dot = ImageTexture.create_from_image(img)
	return _dot


static func light_material(col: Color, size := 0.006) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.fixed_size = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = dot_texture()
	m.albedo_color = col * 1.8
	m.no_depth_test = false
	m.set_meta("size", size)
	return m


## Noktaları tek MultiMesh olarak ekle (yerel konumlar).
static func points(root: Node3D, pts: Array[Vector3], col: Color, size := 0.0045) -> MultiMeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = light_material(col, size)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 4000.0
	root.add_child(mmi)
	return mmi


## Pistin tüm ışıkları. rl: uzunluk, rw: genişlik. Pist yerel z ekseni boyunca.
static func build(root: Node3D, rl: float, rw: float) -> void:
	var edge: Array[Vector3] = []
	var amber: Array[Vector3] = []
	var z := -rl * 0.5
	while z <= rl * 0.5 + 0.1:
		for x in [-rw * 0.5 - 2.0, rw * 0.5 + 2.0]:
			if absf(z) > rl * 0.5 - 600.0:
				amber.append(Vector3(x, 0.4, z))
			else:
				edge.append(Vector3(x, 0.4, z))
		z += 60.0
	points(root, edge, Color(1.0, 0.95, 0.85))
	points(root, amber, Color(1.0, 0.75, 0.3))
	for side in [-1.0, 1.0]:
		var thr: Array[Vector3] = []
		for i in 14:
			thr.append(Vector3(-rw * 0.5 + 1.5 + i * (rw - 3.0) / 13.0, 0.4, side * (rl * 0.5 + 3.0)))
		points(root, thr, Color(0.3, 1.0, 0.45), 0.007)
		# yaklaşma hattı (eşiğin dışında, pist ekseninde)
		var app: Array[Vector3] = []
		var d := 60.0
		while d <= 900.0:
			for k in [-1.5, 0.0, 1.5]:
				app.append(Vector3(k, 1.5, side * (rl * 0.5 + d)))
			d += 30.0
		for k in range(-6, 7):
			app.append(Vector3(k * 2.5, 1.5, side * (rl * 0.5 + 300.0)))
		points(root, app, Color(1.0, 0.95, 0.85), 0.0055)
		var rabbit := ApproachStrobe.new()
		rabbit.side = side
		rabbit.start = rl * 0.5 + 900.0
		rabbit.end_z = rl * 0.5 + 60.0
		root.add_child(rabbit)
		# PAPI: yaklaşan uçağın solunda, eşikten 300 m içeride
		var papi := Papi.new()
		# +z ucundan gelen uçak -z yönünde uçar: solu -x; -z ucundan gelen +z yönünde: solu +x
		papi.position = Vector3(-side * (rw * 0.5 + 15.0), 0.0, side * (rl * 0.5 - 300.0))
		papi.outward = 1.0 if papi.position.x > 0.0 else -1.0
		root.add_child(papi)


## Yaklaşma hattında saniyede iki kez dışarıdan içeriye koşan çakar ("tavşan").
class ApproachStrobe extends Node3D:
	var side := 1.0
	var start := 2100.0
	var end_z := 1260.0
	var _mi: MeshInstance3D
	var _t := 0.0

	func _ready() -> void:
		_mi = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.012)
		q.material = RunwayLights.light_material(Color(0.8, 0.9, 1.0), 0.012)
		_mi.mesh = q
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)

	func _process(delta: float) -> void:
		_t = fmod(_t + delta, 0.5)
		var k := _t / 0.5
		var steps := 22
		var i := int(k * steps)
		_mi.position = Vector3(0, 2.0, side * lerpf(start, end_z, float(i) / steps))
		_mi.visible = i < steps


## PAPI: 4 ışık, her biri bakış açısı kendi eşiğinin üstündeyse beyaz, altındaysa kırmızı.
class Papi extends Node3D:
	const ANGLES := [2.5, 2.83, 3.17, 3.5]     # pistten uzaktakinden yakındakine
	var outward := 1.0
	var _units: Array[MeshInstance3D] = []
	var _white: StandardMaterial3D
	var _red: StandardMaterial3D

	func _ready() -> void:
		_white = RunwayLights.light_material(Color(1.0, 1.0, 0.95), 0.009)
		_red = RunwayLights.light_material(Color(1.0, 0.15, 0.1), 0.009)
		for i in 4:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.009, 0.009)
			mi.mesh = q
			mi.position = Vector3(outward * (27.0 - i * 9.0), 1.0, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_units.append(mi)
			var box := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(1.6, 0.9, 0.8)
			box.mesh = b
			box.position = mi.position - Vector3(0, 0.45, 0)
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(0.2, 0.2, 0.2)
			box.material_override = bm
			add_child(box)

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var up := global_basis.y.normalized()
		for i in 4:
			var to := cam.global_position - _units[i].global_position
			var elev := rad_to_deg(asin(clampf(to.normalized().dot(up), -1.0, 1.0)))
			_units[i].material_override = _white if elev > ANGLES[i] else _red
