class_name VesselBuilder
## Craft JSON'undan (parça listesi) Vessel oluşturur.

const MODULE_SCRIPTS := {
	"wing": preload("res://vessel/modules/wing_module.gd"),
	"control_surface": preload("res://vessel/modules/control_surface_module.gd"),
	"engine": preload("res://vessel/modules/engine_module.gd"),
	"fuel_tank": preload("res://vessel/modules/fuel_tank_module.gd"),
	"cockpit": preload("res://vessel/modules/cockpit_module.gd"),
	"body_drag": preload("res://vessel/modules/body_drag_module.gd"),
	"landing_gear": preload("res://vessel/modules/landing_gear_module.gd"),
	"gun": preload("res://vessel/modules/gun_module.gd"),
	"missile": preload("res://vessel/modules/missile_module.gd"),
	"radar": preload("res://vessel/modules/radar_module.gd"),
	"flare": preload("res://vessel/modules/flare_module.gd"),
	"bomb": preload("res://vessel/modules/bomb_module.gd"),
	"intake": preload("res://vessel/modules/intake_module.gd"),
	"airbrake": preload("res://vessel/modules/airbrake_module.gd"),
	"chute": preload("res://vessel/modules/chute_module.gd"),
	"passenger": preload("res://vessel/modules/passenger_module.gd"),
	"cargo": preload("res://vessel/modules/cargo_module.gd"),
	"targeting_pod": preload("res://vessel/modules/targeting_pod_module.gd"),
}

const PAINT := Color(0.56, 0.61, 0.66)
const PAINT_DARK := Color(0.45, 0.49, 0.54)

## Boya şemaları (hangarda seçilir; craft["paint"]["scheme"])
const PAINT_SCHEMES := {
	"gri": [0, Color(0.56, 0.61, 0.66), Color(0.45, 0.49, 0.54), Color(0.3, 0.33, 0.36)],
	"kamuflaj": [1, Color(0.36, 0.4, 0.28), Color(0.42, 0.34, 0.24), Color(0.2, 0.25, 0.18)],
	"deniz": [1, Color(0.38, 0.45, 0.55), Color(0.3, 0.36, 0.46), Color(0.52, 0.58, 0.66)],
	"çöl": [3, Color(0.72, 0.62, 0.45), Color(0.5, 0.4, 0.28), Color(0.4, 0.33, 0.24)],
	"sivil": [2, Color(0.93, 0.94, 0.95), Color(0.15, 0.32, 0.6), Color(0.75, 0.12, 0.1)],
	"kırmızı-beyaz": [2, Color(0.94, 0.94, 0.94), Color(0.78, 0.1, 0.08), Color(0.78, 0.1, 0.08)],
	"gece": [0, Color(0.16, 0.17, 0.19), Color(0.12, 0.12, 0.14), Color(0.1, 0.1, 0.1)],
}
static var paint := {}            ## şu an kurulan uçağın boyası
static var _materials := {}
static var _mesh_cache := {}


static func load_craft(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Craft okunamadı: %s" % path)
		return {}
	return normalize(data)


## Eski birimle kaydedilmiş uçak (dünya ölçeğinden önce): konumları yeni ölçeğe çevir.
## "units" alanı tasarımın hangi ölçekte yapıldığını tutar; dönüşüm bir kez yapılır.
static func normalize(craft: Dictionary) -> Dictionary:
	var u := float(craft.get("units", 1.0))
	var s := PartLibrary.WORLD_SCALE
	if is_equal_approx(u, s):
		return craft
	var k := s / u
	for e: Dictionary in craft.get("parts", []):
		var p: Array = e.get("pos", [0, 0, 0])
		e["pos"] = [float(p[0]) * k, float(p[1]) * k, float(p[2]) * k]
	craft["units"] = s
	return craft


static func build(craft: Dictionary) -> Vessel:
	normalize(craft)
	paint = craft.get("paint", {})
	var vessel := Vessel.new()
	vessel.craft_name = craft.get("name", "İsimsiz")
	vessel.name = "Vessel"
	for entry: Dictionary in craft.get("parts", []):
		var pos := _vec(entry.get("pos", [0, 0, 0]))
		var rot := _vec(entry.get("rot", [0, 0, 0]))
		var sc: float = entry.get("scale", 1.0)
		_add_part(vessel, entry["part"], pos, rot, false, sc)
		if entry.get("mirror", false):
			# YZ düzlemine göre ayna: x ters, y/z dönüşleri ters
			_add_part(vessel, entry["part"], Vector3(-pos.x, pos.y, pos.z), Vector3(rot.x, -rot.y, -rot.z), true, sc)
	_add_fillets(vessel)
	_add_decals(vessel)
	return vessel


## Hangarda büyütülüp küçültülebilen kategoriler.
const SCALABLE := ["gövde", "motor", "kanat", "kontrol", "sensör"]


## Ölçek s: boyutlar s, alanlar/itki s², hacim (yakıt, tank kütlesi) s³ ile değişir.
static func scaled_def(def: Dictionary, s: float) -> Dictionary:
	if is_equal_approx(s, 1.0) or not def.get("category", "") in SCALABLE:
		return def
	var d := def.duplicate(true)
	var s2 := s * s
	var s3 := s2 * s
	var volumetric: bool = def.get("category", "") in ["gövde", "sensör"]
	d["mass"] = float(def.get("mass", 100.0)) * (s3 if volumetric else s2)
	d["hp"] = float(def.get("hp", 100.0)) * s2
	d["cost"] = int(float(def.get("cost", 0)) * s2)
	d["size"] = (def.get("size", Vector3.ONE) as Vector3) * s
	if def.has("strength_kn"):
		d["strength_kn"] = float(def["strength_kn"]) * s2
	for c: Dictionary in d.get("colliders", []):
		c["pos"] = (c.get("pos", Vector3.ZERO) as Vector3) * s
		if c.has("r"):
			c["r"] = float(c["r"]) * s
		if c.has("len"):
			c["len"] = float(c["len"]) * s
		if c.has("size"):
			c["size"] = (c["size"] as Vector3) * s
	for m: Dictionary in d.get("modules", []):
		for key in ["area", "front_area", "side_area", "max_thrust", "fuel_rate"]:
			if m.has(key):
				m[key] = float(m[key]) * s2
		for key in ["capacity", "fuel"]:
			if m.has(key):
				m[key] = float(m[key]) * s3
	d["visual_pivot"] = (def.get("visual_pivot", Vector3.ZERO) as Vector3) * s
	d["_scale"] = float(def.get("_scale", 1.0)) * s
	return d


static func _add_part(vessel: Vessel, id: String, pos: Vector3, rot_deg: Vector3, mirrored: bool, sc := 1.0) -> void:
	var def := scaled_def(PartLibrary.get_def(id), sc)
	if def.is_empty():
		push_error("Bilinmeyen parça: %s" % id)
		return
	var part := Part.new()
	part.name = "%s_%d" % [id, vessel.parts.size()]
	part.part_id = id
	part.def = def
	part.title = def.get("title", id)
	part.dry_mass = def.get("mass", 100.0)
	part.max_hp = def.get("hp", 100.0)
	part.hp = part.max_hp
	part.size = def.get("size", Vector3.ONE)
	part.position = pos
	part.rotation_degrees = rot_deg

	var visual := Node3D.new()
	visual.name = "Visual"
	visual.position = def.get("visual_pivot", Vector3.ZERO)
	visual.scale = Vector3.ONE * float(def.get("_scale", 1.0))
	if mirrored and def.get("mirror_visual", false):
		visual.scale.x = -visual.scale.x
	var visuals: Array = def.get("visuals", [])
	# "noscale": insan boyundaki görseller (kokpit içi) dünya ölçeğiyle büyümez
	var fixed: Node3D = null
	for i in visuals.size():
		var v: Dictionary = visuals[i]
		var mi := _make_mesh(v, "%s:%d" % [id, i])
		var parent: Node3D = visual.find_child(String(v["parent"]), true, false) as Node3D if v.has("parent") else visual
		if v.get("noscale", false) and not v.has("parent"):
			if fixed == null:
				fixed = Node3D.new()
				fixed.name = "VisualFixed"
				part.add_child(fixed)
			parent = fixed
		parent.add_child(mi)
	part.add_child(visual)

	for m: Dictionary in def.get("modules", []):
		var script: Script = MODULE_SCRIPTS.get(m["type"])
		if script == null:
			push_error("Bilinmeyen modül: %s" % m["type"])
			continue
		var module: PartModule = script.new()
		module.name = m["type"]
		module.setup(m)
		part.add_module(module)

	# dayanım: tanımda kN verilmemişse dolu kütlesinin 14 katı (14 G)
	part.strength = float(def.get("strength_kn", 0.0)) * 1000.0
	if part.strength <= 0.0:
		part.strength = part.get_mass() * 9.81 * 14.0
	vessel.add_child(part)
	vessel.parts.append(part)

	# Çarpışma şekilleri RigidBody'nin doğrudan çocuğu olmalı.
	for c: Dictionary in def.get("colliders", []):
		var shape := _make_collider(c)
		shape.transform = part.transform * shape.transform
		vessel.add_child(shape)
		part.colliders.append(shape)


static func _make_mesh(v: Dictionary, cache_key: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if v.has("name"):
		mi.name = v["name"]
	var base_rot := Vector3.ZERO
	match v["type"]:
		"lathe":
			if not _mesh_cache.has(cache_key):
				_mesh_cache[cache_key] = MeshFactory.lathe(v["profile"], v.get("segments", 32), v.get("y_scale", 1.0),
					v.get("arc_from", 0.0), v.get("arc_to", 360.0))
			mi.mesh = _mesh_cache[cache_key]
		"wing":
			if not _mesh_cache.has(cache_key):
				_mesh_cache[cache_key] = MeshFactory.wing(v["span"], v["root"], v["tip"], v["sweep"], v["thick"])
			mi.mesh = _mesh_cache[cache_key]
		"cyl":
			var mesh := CylinderMesh.new()
			var r: float = v.get("r", 0.5)
			# CylinderMesh +Y ekseninde; "ön" ucu top_radius.
			mesh.top_radius = v.get("r_front", r)
			mesh.bottom_radius = v.get("r_back", r)
			mesh.height = v["len"]
			mesh.radial_segments = 24
			mi.mesh = mesh
			match v.get("axis", "z"):
				"z": base_rot = Vector3(-90, 0, 0)
				"x": base_rot = Vector3(0, 0, 90)
		"box":
			var mesh := BoxMesh.new()
			mesh.size = v["size"]
			mi.mesh = mesh
		"sphere":
			var mesh := SphereMesh.new()
			mesh.radius = v["r"]
			mesh.height = v["r"] * 2.0
			mesh.radial_segments = 32
			mesh.rings = 16
			mi.mesh = mesh
			mi.scale = v.get("scale", Vector3.ONE)
	mi.rotation_degrees = base_rot + v.get("rot", Vector3.ZERO)
	mi.position = v.get("pos", Vector3.ZERO)
	var mat_name: String = v.get("mat", "paint")
	mi.material_override = material(mat_name, v.get("color", Color(0, 0, 0, 0)))
	if mat_name in ["flame", "flame_core", "heat_haze", "glow", "glass", "hud_glass", "screen"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func material(mat_name: String, color := Color(0, 0, 0, 0)) -> Material:
	if mat_name == "interior" and color.a <= 0.0:
		return cockpit_panel_material()
	if (mat_name == "paint" or mat_name == "paint_dark") and color.a <= 0.0:
		return _paint_material(mat_name == "paint_dark")
	var key := "%s_%s" % [mat_name, color.to_html()]
	if _materials.has(key):
		return _materials[key]
	var custom := color.a > 0.0
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match mat_name:
		"paint", "paint_dark":
			m.albedo_color = color if custom else (PAINT if mat_name == "paint" else PAINT_DARK)
			m.metallic = 0.35
			m.roughness = 0.42
			m.clearcoat_enabled = true
			m.clearcoat = 0.35
			m.clearcoat_roughness = 0.3
		"radome":
			m.albedo_color = color if custom else Color(0.3, 0.31, 0.33)
			m.roughness = 0.6
		"metal":
			m.albedo_color = color if custom else Color(0.33, 0.34, 0.36)
			m.metallic = 0.9
			m.roughness = 0.3
		"dark":
			m.albedo_color = color if custom else Color(0.07, 0.07, 0.08)
			m.roughness = 0.75
		"interior":
			m.albedo_color = color if custom else Color(0.22, 0.23, 0.25)
			m.roughness = 0.7
		"seat":
			m.albedo_color = color if custom else Color(0.11, 0.11, 0.12)
			m.roughness = 0.85
		"button":
			m.albedo_color = Color(0.16, 0.17, 0.18)
			m.roughness = 0.5
		"screen_amber":
			m.albedo_color = Color(0.05, 0.03, 0.0)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.6, 0.15)
			m.emission_energy_multiplier = 0.5
		"lamp_amber", "lamp_green", "lamp_red":
			var lc: Color = {"lamp_amber": Color(1.0, 0.65, 0.1), "lamp_green": Color(0.2, 1.0, 0.35), "lamp_red": Color(1.0, 0.15, 0.1)}[mat_name]
			m.albedo_color = lc * 0.3
			m.emission_enabled = true
			m.emission = lc
			m.emission_energy_multiplier = 2.5
		"yellow":
			m.albedo_color = Color(0.95, 0.75, 0.1)
			m.roughness = 0.6
		"rubber":
			m.albedo_color = Color(0.04, 0.04, 0.04)
			m.roughness = 0.95
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.55, 0.65, 0.75, 0.08)
			m.metallic = 0.25
			m.roughness = 0.02
			m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		"hud_glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.3, 1.0, 0.5, 0.04)
		"screen":
			m.albedo_color = Color(0.02, 0.05, 0.04)
			m.emission_enabled = true
			m.emission = color if custom else Color(0.15, 0.7, 0.45)
			m.emission_energy_multiplier = 0.25
		"prop_disc":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.12, 0.12, 0.12, 0.22)
			m.roughness = 0.8
		"glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.45, 0.15) * 3.0
		"flame", "flame_core":
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://vessel/flame.gdshader")
			if mat_name == "flame_core":
				sm.set_shader_parameter("color_near", Color(0.85, 0.92, 1.0))
				sm.set_shader_parameter("color_far", Color(1.0, 0.75, 0.45))
				sm.set_shader_parameter("intensity", 2.2)
				sm.set_shader_parameter("diamond_count", 4.0)
			_materials[key] = sm
			return sm
		"heat_haze":
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://vessel/heat_haze.gdshader")
			var noise := FastNoiseLite.new()
			noise.frequency = 0.03
			var tex := NoiseTexture2D.new()
			tex.width = 256
			tex.height = 256
			tex.seamless = true
			tex.noise = noise
			sm.set_shader_parameter("noise_tex", tex)
			_materials[key] = sm
			return sm
		_:
			m.albedo_color = color if custom else Color.MAGENTA
	_materials[key] = m
	return m


static func _make_collider(c: Dictionary) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	match c["type"]:
		"cyl":
			var shape := CylinderShape3D.new()
			shape.radius = c["r"]
			shape.height = c["len"]
			cs.shape = shape
			cs.rotation_degrees = Vector3(90, 0, 0)
		"box":
			var shape := BoxShape3D.new()
			shape.size = c["size"]
			cs.shape = shape
	cs.position = c.get("pos", Vector3.ZERO)
	return cs


static func _vec(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Şemaya göre boya malzemesi (shader). Şema + renkler aynıysa paylaşılır.
static func _paint_material(dark: bool) -> Material:
	var scheme_name: String = paint.get("scheme", "gri")
	var s: Array = PAINT_SCHEMES.get(scheme_name, PAINT_SCHEMES["gri"])
	var c1: Color = s[1]
	if paint.has("color1"):
		c1 = Color.html(paint["color1"])
	var key := "paint_%s_%s_%s" % [scheme_name, c1.to_html(), dark]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://vessel/paint.gdshader")
	m.set_shader_parameter("scheme", s[0])
	m.set_shader_parameter("color1", c1)
	m.set_shader_parameter("color2", s[2])
	m.set_shader_parameter("color3", s[3])
	m.set_shader_parameter("dark", 1.0 if dark else 0.0)
	m.set_meta("paint", true)
	_materials[key] = m
	return m


static var _roundel: ImageTexture


## Arma: kırmızı daire, beyaz halka, kırmızı göbek (kanat üstleri).
static func _roundel_texture() -> ImageTexture:
	if _roundel:
		return _roundel
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var red := Color(0.78, 0.08, 0.07)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var c := Color(0, 0, 0, 0)
			if d < 1.0:
				c = red
			if d < 0.72:
				c = Color(0.95, 0.95, 0.93)
			if d < 0.36:
				c = red
			# kenar yumuşatma
			c.a *= clampf((1.0 - d) * n * 0.5, 0.0, 1.0) if d < 1.0 else 0.0
			img.set_pixel(x, y, c)
	_roundel = ImageTexture.create_from_image(img)
	return _roundel


## Kuyruk numarası (dikey kuyruklarda, iki yanda) ve kanat üstü armalar.
static func _add_decals(vessel: Vessel) -> void:
	var number: String = str(paint.get("number", ""))
	for p in vessel.parts:
		var is_wing := false
		for m in p.modules:
			if m is WingModule and not m is ControlSurfaceModule:
				is_wing = true
		if not is_wing:
			continue
		var vertical := absf(absf(p.rotation_degrees.z) - 90.0) < 25.0
		var half_t := p.size.y * 0.5 + 0.012
		if vertical and not number.is_empty():
			for side in [1.0, -1.0]:
				var l := Label3D.new()
				l.text = number
				l.font_size = 160
				l.outline_size = 0
				l.pixel_size = 0.004 * minf(1.0, 3.0 / maxf(number.length(), 1)) * clampf(p.size.z / 2.5, 0.6, 1.4)
				l.modulate = Color(0.08, 0.08, 0.09) if paint.get("scheme", "gri") != "gece" else Color(0.85, 0.85, 0.8)
				l.double_sided = false
				var n := Vector3(0, side, 0)
				var up := Vector3(1, 0, 0)
				var right := up.cross(n)
				l.transform = Transform3D(Basis(right, up, n), Vector3(p.size.x * 0.05, side * half_t, p.size.z * 0.1))
				p.add_child(l)
		elif not vertical and absf(p.position.x) > 0.8 and p.size.x > 1.5:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			var r := clampf(p.size.z * 0.38, 0.4, 1.1)
			qm.size = Vector2(r, r)
			q.mesh = qm
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _roundel_texture()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.roughness = 0.5
			q.material_override = mat
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var tip := signf(p.position.x)
			q.position = Vector3(tip * p.size.x * 0.22, half_t + 0.01, p.size.z * 0.05)
			q.rotation_degrees = Vector3(-90, 0, 0)
			p.add_child(q)


# ------------------------------------------------------------------ kanat kökü kaportası

## Kanat ve dikey kuyrukların gövdeye değdiği köke yassı, damla biçimli bir geçiş kaportası
## (gerçek uçaklardaki "wing root fillet"): keskin levha-silindir birleşimini yumuşatır.
## Kaporta kanat parçasına bağlıdır (kanat koparsa onunla gider).
static func _add_fillets(v: Vessel) -> void:
	var bodies: Array[Part] = []
	for p in v.parts:
		for m in p.modules:
			if m is BodyDragModule and absf(p.basis.z.normalized().z) > 0.9:
				bodies.append(p)
	for p in v.parts:
		var wing: WingModule = null
		for m in p.modules:
			if m is WingModule and not m is ControlSurfaceModule:
				wing = m
		if wing == null:
			continue
		var span := p.basis.x.normalized()
		var half := p.size.x * 0.5
		var ends := [p.position + span * half, p.position - span * half]
		var best_d := INF
		var root_sign := 1.0
		var body: Part = null
		for i in 2:
			var e: Vector3 = ends[i]
			for b in bodies:
				var r := maxf(b.size.x, b.size.y) * 0.5
				var d := Vector2(e.x - b.position.x, e.y - b.position.y).length()
				var dz := absf(e.z - b.position.z) - b.size.z * 0.5
				if dz < 0.5 and d < r * 1.25 and d < best_d:
					best_d = d
					body = b
					root_sign = 1.0 if i == 0 else -1.0
		if body == null:
			continue
		var chord := p.size.z
		var thick := maxf(p.size.y, 0.12)
		var reach := clampf(chord * 0.3, 0.4, 1.4)       # kanat üstüne yayılma
		var prof := [Vector2(-chord * 0.62, 0.0), Vector2(-chord * 0.5, 0.45), Vector2(-chord * 0.25, 0.85),
			Vector2(0.0, 1.0), Vector2(chord * 0.3, 0.8), Vector2(chord * 0.55, 0.3), Vector2(chord * 0.64, 0.0)]
		var mi := MeshInstance3D.new()
		mi.name = "RootFillet"
		mi.mesh = MeshFactory.lathe(prof, 24)
		mi.material_override = material("paint")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# kanadın gövde yüzeyinden çıktığı nokta: kökten uca doğru, gövde ekseninden yarıçap kadar uzakta
		var br := maxf(body.size.x, body.size.y) * 0.5
		var root_v := p.position + span * root_sign * half
		var out_dir := -span * root_sign
		var t_surf := 0.0
		var t := 0.0
		while t < half * 2.0:
			var q := root_v + out_dir * t
			if Vector2(q.x - body.position.x, q.y - body.position.y).length() >= br * 0.97:
				t_surf = t
				break
			t += 0.04
		var local_root := Vector3(root_sign * (half - t_surf), 0.0, 0.0)
		# parça uzayında; x: açıklık yönü, y: kalınlık. Yarısı gövdeye gömülü
		mi.position = local_root - Vector3(root_sign * reach * 0.15, 0.0, chord * 0.04)
		mi.scale = Vector3(reach, thick * 2.2, 1.0)
		p.add_child(mi)


static var _cockpit_panel: ShaderMaterial


## Kokpit iç yüzey malzemesi (paylaşılan; panel ışığı CockpitModule'den).
static func cockpit_panel_material() -> ShaderMaterial:
	if _cockpit_panel == null:
		_cockpit_panel = ShaderMaterial.new()
		_cockpit_panel.shader = preload("res://vessel/cockpit_panel.gdshader")
	return _cockpit_panel
