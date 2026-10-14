class_name VesselBuilder
## Craft JSON'undan (parça listesi) Vessel oluşturur.

const MODULE_SCRIPTS := {
	"wing": preload("res://vessel/modules/wing_module.gd"),
	"control_surface": preload("res://vessel/modules/control_surface_module.gd"),
	"engine": preload("res://vessel/modules/engine_module.gd"),
	"booster": preload("res://vessel/modules/booster_module.gd"),
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
	"ramp": preload("res://vessel/modules/ramp_module.gd"),
	"targeting_pod": preload("res://vessel/modules/targeting_pod_module.gd"),
	"ecm": preload("res://vessel/modules/ecm_module.gd"),
	"irst": preload("res://vessel/modules/irst_module.gd"),
	"refuel_probe": preload("res://vessel/modules/refuel_probe_module.gd"),
	"splitter": preload("res://vessel/modules/splitter_module.gd"),
	"bomb_bay": preload("res://vessel/modules/bomb_bay_module.gd"),
	"tail_turret": preload("res://vessel/modules/tail_turret_module.gd"),
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
		if e.has("axis"):
			e["axis"] = [float(e["axis"][0]) * k, float(e["axis"][1]) * k]
	craft["units"] = s
	return craft


static func build(craft: Dictionary) -> Vessel:
	normalize(craft)
	paint = craft.get("paint", {})
	var vessel := Vessel.new()
	vessel.craft_name = craft.get("name", "İsimsiz")
	vessel.name = "Vessel"
	var t0 := Time.get_ticks_usec()
	for entry: Dictionary in craft.get("parts", []):
		var sc: float = entry.get("scale", 1.0)
		for c in entry_copies(entry):
			_add_part(vessel, entry["part"], c["pos"], c["rot"], c["flip"], sc, entry)
	var t1 := Time.get_ticks_usec()
	_add_fillets(vessel)
	_add_transitions(vessel)
	var t2 := Time.get_ticks_usec()
	_add_pylons(vessel)
	var t3 := Time.get_ticks_usec()
	_add_decals(vessel)
	if Game.args.has("buildprobe"):
		print("  parçalar %.1f · fileto %.1f · pilon %.1f · çıkartma %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (Time.get_ticks_usec() - t3) / 1000.0])
	_apply_weathering(vessel, clampf(float(craft.get("wear", 0.0)), 0.0, 1.0))
	return vessel


## Boya yıpranması (paint.gdshader instance uniform'ları): her boyalı ağa uçağın eskime düzeyi,
## uçağın ileri/yukarı yönü (ağ uzayında) ve en yakın is kaynağı yazılır. Is kaynakları: jet /
## roket lüle ağızları ve top namluları. Yeni uçakta is hafif, eskidikçe koyulaşır.
static func _apply_weathering(v: Vessel, wear: float) -> void:
	v.set_meta("wear", wear)   # EngineModule: lüle ısı renklerinin kalıcılığı
	var srcs: Array = []   # [uçak uzayında konum, yarıçap, şiddet]
	for p in v.parts:
		var r := maxf(p.size.x, p.size.y)
		for m in p.modules:
			if (m is EngineModule and not m.prop) or m is BoosterModule:
				srcs.append([p.position + p.basis.z.normalized() * p.size.z * 0.5, r * 1.3, 1.0])
			elif m is GunModule:
				srcs.append([p.position - p.basis.z.normalized() * p.size.z * 0.5, r * 0.9, 0.85])
	var soot_k := 0.3 + 0.7 * wear
	for p in v.parts:
		var stack: Array[Node] = [p]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			if mi == null or not (mi.material_override is ShaderMaterial) or not mi.material_override.has_meta("paint"):
				continue
			# ağ → uçak uzayı (parça dönüşümü × parça içindeki düğüm zinciri)
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != v:
				xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var inv := xf.affine_inverse()
			mi.set_instance_shader_parameter("wear", wear)
			mi.set_instance_shader_parameter("fwd_m", (inv.basis * Vector3.FORWARD).normalized())
			mi.set_instance_shader_parameter("up_m", (inv.basis * Vector3.UP).normalized())
			# ağın merkezine en çok etki eden is kaynağı
			var center := xf * (mi.get_aabb().get_center() if mi.mesh else Vector3.ZERO)
			var best: Array = []
			var best_w := 0.02
			for s: Array in srcs:
				var d := (center - (s[0] as Vector3)).length() / float(s[1])
				var w := float(s[2]) * exp(-d * d * 0.5)
				if w > best_w:
					best_w = w
					best = s
			if best.is_empty():
				mi.set_instance_shader_parameter("soot_src", Vector4.ZERO)
			else:
				var lpos := inv * (best[0] as Vector3)
				mi.set_instance_shader_parameter("soot_src", Vector4(lpos.x, lpos.y, lpos.z, float(best[2]) * soot_k))
				mi.set_instance_shader_parameter("soot_r", float(best[1]) * inv.basis.x.length())


static var MIRROR := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)


## Kaydın simetri kopyalarının dönüşümleri: [{xf, mirror}] — ilki her zaman kaydın kendisi (birim).
## Ayna: X' = M·X·M (YZ düzlemine göre; geometri ters çevrilmez, "flip" görseli ters çevirir).
## Radyal n: X' = S_k·X, S_k = eksen (axis: [x, y], Z yönünde) çevresinde 360°·k/n dönüş.
static func copy_ops(entry: Dictionary) -> Array[Dictionary]:
	var ops: Array[Dictionary] = [{"xf": Transform3D.IDENTITY, "mirror": false}]
	if entry.get("mirror", false):
		ops.append({"xf": MIRROR, "mirror": true})
	elif int(entry.get("radial", 1)) > 1:
		var n := int(entry["radial"])
		var ax: Array = entry.get("axis", [0, 0])
		var c := Vector3(float(ax[0]), float(ax[1]), 0.0)
		for k in range(1, n):
			var r := Transform3D(Basis(Vector3.BACK, TAU * k / n), Vector3.ZERO)
			ops.append({"xf": Transform3D(Basis.IDENTITY, c) * r * Transform3D(Basis.IDENTITY, -c), "mirror": false})
	return ops


static func apply_op(op: Dictionary, x: Transform3D) -> Transform3D:
	var s: Transform3D = op["xf"]
	return s * x * s if op["mirror"] else s * x


## Kaydın kendi dönüşümü (ölçeksiz).
static func entry_xform(entry: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(_vec(entry.get("rot", [0, 0, 0])) * (PI / 180.0)), _vec(entry.get("pos", [0, 0, 0])))


## Kayda dönüşüm yaz (konum 1 mm'ye, açı 0.01°'ye yuvarlanır; sıfır dönüş yazılmaz).
static func set_entry_xform(entry: Dictionary, x: Transform3D) -> void:
	var p := x.origin.snapped(Vector3.ONE * 0.001)
	entry["pos"] = [p.x, p.y, p.z]
	var r := (x.basis.orthonormalized().get_euler() * (180.0 / PI)).snapped(Vector3.ONE * 0.01)
	if r.is_zero_approx():
		entry.erase("rot")
	else:
		entry["rot"] = [r.x, r.y, r.z]


## Kaydın uçakta oluşturduğu tüm parçalar: [{pos, rot (derece), flip}].
static func entry_copies(entry: Dictionary) -> Array[Dictionary]:
	var pos := _vec(entry.get("pos", [0, 0, 0]))
	var rot := _vec(entry.get("rot", [0, 0, 0]))
	var flip: bool = entry.get("flip", false)
	var out: Array[Dictionary] = [{"pos": pos, "rot": rot, "flip": flip}]
	if entry.get("mirror", false):
		# YZ düzlemine göre ayna: x ters, y/z dönüşleri ters (M·X·M ile aynı, Euler açısı korunur)
		out.append({"pos": Vector3(-pos.x, pos.y, pos.z), "rot": Vector3(rot.x, -rot.y, -rot.z), "flip": not flip})
		return out
	var ops := copy_ops(entry)
	var base := entry_xform(entry)
	for i in range(1, ops.size()):
		var x := apply_op(ops[i], base)
		out.append({"pos": x.origin, "rot": x.basis.orthonormalized().get_euler() * (180.0 / PI), "flip": flip})
	return out


## Hangarda büyütülüp küçültülebilen kategoriler.
const SCALABLE := ["gövde", "motor", "kanat", "kontrol", "sensör", "kokpit", "iniş takımı"]


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
		# iniş takımı: boy ve teker ölçekle, yay/sönüm taşıdığı kütleyle (hacim) büyür
		for key in ["rest_length", "wheel_radius"]:
			if m.has(key):
				m[key] = float(m[key]) * s
		for key in ["spring", "damper"]:
			if m.has(key):
				m[key] = float(m[key]) * s3
	d["visual_pivot"] = (def.get("visual_pivot", Vector3.ZERO) as Vector3) * s
	d["_scale"] = float(def.get("_scale", 1.0)) * s
	return d


## Gövdesi uzunluk / genişlik / yükseklik ayrı ayrı ayarlanabilen kategoriler (kayıtta "stretch").
const STRETCHABLE := ["gövde", "motor", "sensör"]


## Kaydın parça tanımı: ayarlanabilir kanat kendi biçiminden kurulur, ardından ölçek ve esneme.
static func entry_def(id: String, entry: Dictionary, sc := 1.0) -> Dictionary:
	var base := PartLibrary.get_def(id)
	if base.get("procedural", "") == "wing" and entry.has("wing"):
		base = PartLibrary.custom_wing_def(entry["wing"])
	var def := scaled_def(base, sc)
	if entry.has("stretch") and def.get("category", "") in STRETCHABLE:
		def = stretched_def(def, _vec(entry["stretch"]))
	return def


## Eksen başına esneme st = (genişlik, yükseklik, uzunluk) çarpanı. Kütle ve yakıt hacimle,
## ön alan ve itki kesit alanıyla (x·y), yan alan y·z ile değişir. Görsel düğüm de aynı oranla.
static func stretched_def(def: Dictionary, st: Vector3) -> Dictionary:
	st = st.clamp(Vector3.ONE * 0.4, Vector3.ONE * 3.0)
	if st.is_equal_approx(Vector3.ONE):
		return def
	var d := def.duplicate(true)
	var vol := st.x * st.y * st.z
	var sec := st.x * st.y
	d["mass"] = float(def.get("mass", 100.0)) * vol
	d["hp"] = float(def.get("hp", 100.0)) * sqrt(vol)
	d["cost"] = int(float(def.get("cost", 0)) * sqrt(vol))
	d["size"] = (def.get("size", Vector3.ONE) as Vector3) * st
	for c: Dictionary in d.get("colliders", []):
		c["pos"] = (c.get("pos", Vector3.ZERO) as Vector3) * st
		if c.has("r"):
			c["r"] = float(c["r"]) * (st.x + st.y) * 0.5
		if c.has("len"):
			c["len"] = float(c["len"]) * st.z
		if c.has("size"):
			c["size"] = (c["size"] as Vector3) * st
	for m: Dictionary in d.get("modules", []):
		for key in ["front_area", "max_thrust", "fuel_rate"]:
			if m.has(key):
				m[key] = float(m[key]) * sec
		if m.has("side_area"):
			m["side_area"] = float(m["side_area"]) * st.y * st.z
		if m.has("area"):
			m["area"] = float(m["area"]) * st.x * st.z
		for key in ["capacity", "fuel"]:
			if m.has(key):
				m[key] = float(m[key]) * vol
	d["visual_pivot"] = (def.get("visual_pivot", Vector3.ZERO) as Vector3) * st
	d["_stretch"] = st
	return d


static func _add_part(vessel: Vessel, id: String, pos: Vector3, rot_deg: Vector3, mirrored: bool, sc := 1.0, entry := {}) -> void:
	var def := entry_def(id, entry, sc)
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
	part.set_meta("flip", mirrored)   # ayna kopya: pervane ters döner (EngineModule)

	var visual := Node3D.new()
	visual.name = "Visual"
	visual.position = def.get("visual_pivot", Vector3.ZERO)
	visual.scale = (def.get("_stretch", Vector3.ONE) as Vector3) * float(def.get("_scale", 1.0))
	if mirrored and def.get("mirror_visual", false):
		visual.scale.x = -visual.scale.x
	var visuals: Array = def.get("visuals", [])
	# ayarlanabilir kanat: ağ önbelleği biçime göre ayrı
	var shape_key := ("#%d" % str(entry.get("wing")).hash()) if def.get("procedural", "") == "wing" else ""
	# "noscale": insan boyundaki görseller (kokpit içi) dünya ölçeğiyle büyümez
	var fixed: Node3D = null
	for i in visuals.size():
		var v: Dictionary = visuals[i]
		var mi := _make_mesh(v, "%s:%d%s" % [id, i, shape_key])
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
		# aynalı kopyada kanadın aerodinamik merkezi de aynalanır (kök iç tarafta kalsın)
		if mirrored and module is WingModule:
			module.ac_offset.x = -module.ac_offset.x
		part.add_module(module)
	apply_tweaks(part, entry)

	# dayanım: tanımda kN verilmemişse dolu kütlesinin 14 katı (14 G)
	part.strength = float(def.get("strength_kn", 0.0)) * 1000.0
	if part.strength <= 0.0:
		part.strength = part.get_mass() * 9.81 * 14.0
	# kaldırma yüzeyleri hafif ama geniş: yükü alanla orantılı taşırlar (m² başına 60 kN ≈ uçak
	# ağırlığının ~12 katı). Yoksa sert manevrada elevon / kanat kendiliğinden hasar alıyordu.
	for m: Dictionary in def.get("modules", []):
		if m.get("type", "") in ["wing", "control_surface"]:
			var per_m2 := 90000.0 if m["type"] == "control_surface" else 60000.0
			part.strength = maxf(part.strength, float(m.get("area", 1.0)) * per_m2)
	vessel.add_child(part)
	vessel.parts.append(part)

	# Çarpışma şekilleri RigidBody'nin doğrudan çocuğu olmalı.
	for c: Dictionary in def.get("colliders", []):
		var shape := _make_collider(c)
		shape.transform = part.transform * shape.transform
		vessel.add_child(shape)
		part.colliders.append(shape)


## Hangarda parça penceresinden ayarlananlar (kayıtta tutulur): yakıt doluluğu, kontrol yüzeyi
## eksenleri ve sapma açısı, afterburner kilidi.
static func apply_tweaks(part: Part, entry: Dictionary) -> void:
	for m in part.modules:
		if m is FuelTankModule and entry.has("fuel"):
			m.fuel = m.capacity * clampf(float(entry["fuel"]), 0.0, 1.0)
		elif m is ControlSurfaceModule:
			if entry.has("axes"):
				var a: Array = entry["axes"]
				m.axis_mask = Vector3(float(a[0]), float(a[1]), float(a[2]))
			if entry.has("deflect"):
				m.max_deflection = deg_to_rad(float(entry["deflect"]))
		elif m is EngineModule:
			if entry.get("no_ab", false):
				m.no_ab = true
			if entry.has("thrust_limit"):
				m.thrust_limit = clampf(float(entry["thrust_limit"]), 0.1, 1.0)


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
			mi.set_meta("wing_mesh", true)   # _wing_spot (kokarda yeri) bu ağı okur
		"wing_sections":
			if not _mesh_cache.has(cache_key):
				_mesh_cache[cache_key] = MeshFactory.wing_sections(v["secs"], v["thick"])
			mi.mesh = _mesh_cache[cache_key]
			mi.set_meta("wing_mesh", true)
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
	if v.has("inner") and mi.material_override is ShaderMaterial:
		mi.set_instance_shader_parameter("inner_sign", float(v["inner"]))
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
			# yer: kanadın gerçek ağından — kökten uca %45'te, o kesitin veter ortası; üstte ve altta.
			# (parça kutusundan tahmin oklu / daralan kanatlarda kokardayı kanadın dışına koyuyordu)
			var spot := _wing_spot(p, 0.45)
			var r := clampf(p.size.z * 0.38, 0.4, 1.1)
			var top := Vector3(signf(p.position.x) * p.size.x * 0.22, half_t, p.size.z * 0.05)
			var bottom := top - Vector3(0, half_t * 2.0, 0)
			if not spot.is_empty():
				r = minf(r, float(spot["chord"]) * 0.62)
				top = spot["top"]
				bottom = spot["bottom"]
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _roundel_texture()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.roughness = 0.5
			for face in [[top + Vector3(0, 0.012, 0), -90.0], [bottom - Vector3(0, 0.012, 0), 90.0]]:
				var q := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2(r, r)
				q.mesh = qm
				q.material_override = mat
				q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				q.position = face[0]
				q.rotation_degrees = Vector3(face[1], 0, 0)
				p.add_child(q)


## Kanadın ağ noktalarından (parça uzayında) kökten uca `k` oranındaki kesit: {top, bottom, chord}.
## Kök = gövde eksenine yakın uç. Kanat ağı bulunamazsa boş sözlük.
static func _wing_spot(p: Part, k: float) -> Dictionary:
	var pts := PackedVector3Array()
	var stack: Array[Node] = [p]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or not mi.mesh is ArrayMesh or not mi.has_meta("wing_mesh"):
			continue
		# ağdan parçaya dönüşüm (ağaçta olmayabilir: global yerine zinciri çarp)
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != p and cur is Node3D:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for vtx in (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			pts.append(xf * vtx)
		break
	if pts.size() < 8:
		return {}
	var x0 := INF
	var x1 := -INF
	for q in pts:
		x0 = minf(x0, q.x)
		x1 = maxf(x1, q.x)
	var root := x0 if absf(p.position.x + x0) < absf(p.position.x + x1) else x1
	var tip := x1 if root == x0 else x0
	var xs := lerpf(root, tip, k)
	# ağ kesit halkalarından oluşur (çoğu kanatta yalnız kök ve uç): halkaları x'e göre grupla,
	# xs'yi çevreleyen iki halkanın veter / kalınlık değerlerini ara değerle
	var rings := {}   # yuvarlanmış x → [zmin, zmax, ytop, ybot]
	for q in pts:
		var key := snappedf(q.x, 0.02)
		var r: Array = rings.get(key, [INF, -INF, -INF, INF])
		rings[key] = [minf(r[0], q.z), maxf(r[1], q.z), maxf(r[2], q.y), minf(r[3], q.y)]
	var keys := rings.keys()
	keys.sort()
	var lo: float = keys[0]
	var hi: float = keys[-1]
	for kx: float in keys:
		if kx <= xs:
			lo = kx
		if kx >= xs:
			hi = kx
			break
	var a: Array = rings[lo]
	var b: Array = rings[hi]
	var t := 0.0 if is_equal_approx(lo, hi) else (xs - lo) / (hi - lo)
	var zmin := lerpf(a[0], b[0], t)
	var zmax := lerpf(a[1], b[1], t)
	if zmax - zmin < 0.2:
		return {}
	var zc := (zmin + zmax) * 0.5
	return {"top": Vector3(xs, lerpf(a[2], b[2], t), zc), "bottom": Vector3(xs, lerpf(a[3], b[3], t), zc), "chord": zmax - zmin}


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
		var reach := clampf(chord * 0.16, 0.3, 0.75)      # kanat üstüne yayılma
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
		mi.scale = Vector3(reach, minf(thick * 1.7, 0.45), 1.0)
		p.add_child(mi)


# ------------------------------------------------------------------ gövde geçişleri

## Uç uca takılı iki gövde parçasının yarıçapı farklıysa (gövde 0.65 → motor 0.55, kokpit → ince
## kuyruk) arada keskin bir basamak kalıyordu: uçak "boru dizisi" gibi görünüyordu. Büyük parçadan
## küçüğe yumuşakça daralan bir geçiş kaportası eklenir (büyük parçanın boyasıyla, ona bağlı).
## Oyuncunun kendi tasarımlarında da çalışır.
static func _add_transitions(v: Vessel) -> void:
	var ends: Array[Dictionary] = []
	for p in v.parts:
		var e := _body_ends(p)
		if not e.is_empty():
			ends.append(e)
	for a in ends:
		for b in ends:
			if a == b:
				continue
			# a'nın arka yüzü b'nin ön yüzüne değiyor mu (aynı eksende)
			if Vector2(a["x"] - b["x"], a["y"] - b["y"]).length() > 0.12 or absf(float(a["zr"]) - float(b["zf"])) > 0.25:
				continue
			var ra: float = a["rr"]
			var rb: float = b["rf"]
			if absf(ra - rb) < 0.05 or minf(ra, rb) < 0.08:
				continue
			var big: Dictionary = a if ra > rb else b
			var r_big := maxf(ra, rb)
			var r_small := minf(ra, rb)
			var joint: float = (float(a["zr"]) + float(b["zf"])) * 0.5
			var length := clampf((r_big - r_small) * 3.0, 0.35, 1.6)
			# büyük parça öndeyse kaporta geriye (+z), arkadaysa öne (-z) uzanır
			var dir := 1.0 if big == a else -1.0
			var prof: Array = []
			for i in 9:
				var t := float(i) / 8.0
				var r := lerpf(r_big, r_small, 0.5 - 0.5 * cos(PI * t)) + 0.004   # yumuşak (kosinüs) daralma
				prof.append(Vector2(joint + dir * (t * length - 0.02), r))
			if dir < 0.0:
				prof.reverse()
			_fairing(big["part"], prof)


## Gövde parçasının araç uzayında uç bilgisi: ön/arka z, ön/arka yarıçap, eksen x/y. Uygun değilse {}.
static func _body_ends(p: Part) -> Dictionary:
	var zdir := p.basis.z.normalized()
	if absf(zdir.z) < 0.97 or not p.modules.any(func(m: PartModule) -> bool: return m is BodyDragModule):
		return {}
	var s := float(p.def.get("_scale", 1.0))
	var zmin := INF
	var zmax := -INF
	var rf := 0.0
	var rr := 0.0
	for vis: Dictionary in p.def.get("visuals", []):
		# yalnız gövde kabuğu: alev / ısı dalgası (motorun 7 m arkasına uzanır), cam, iç yüzey sayılmaz
		if vis.get("type", "") != "lathe" or vis.has("arc_from") or vis.has("parent") or not (String(vis.get("mat", "paint")) in ["paint", "paint_dark", "metal"]):
			continue
		var off: Vector3 = vis.get("pos", Vector3.ZERO)
		for pt: Vector2 in vis.get("profile", []):
			var z := pt.x + off.z
			if z < zmin - 0.001:
				zmin = z
				rf = pt.y
			elif absf(z - zmin) <= 0.001:
				rf = maxf(rf, pt.y)
			if z > zmax + 0.001:
				zmax = z
				rr = pt.y
			elif absf(z - zmax) <= 0.001:
				rr = maxf(rr, pt.y)
	if zmin == INF:
		return {}
	var sg := signf(zdir.z)
	var za := p.position.z + zmin * s * sg
	var zb := p.position.z + zmax * s * sg
	return {"part": p, "x": p.position.x, "y": p.position.y,
		"zf": minf(za, zb), "zr": maxf(za, zb),
		"rf": (rf if sg > 0.0 else rr) * s, "rr": (rr if sg > 0.0 else rf) * s}


## Araç uzayında z ekseni boyunca bir döndürme kaportası; parçaya bağlanır (parça uzayına çevrilir).
static func _fairing(p: Part, prof_vessel: Array) -> void:
	var sg := signf(p.basis.z.normalized().z)
	var local: Array = []
	for q: Vector2 in prof_vessel:
		local.append(Vector2((q.x - p.position.z) * sg, q.y))
	if sg < 0.0:
		local.reverse()
	var mi := MeshInstance3D.new()
	mi.name = "Transition"
	mi.mesh = MeshFactory.lathe(local, 32)
	# büyük parçanın boyası (renk / desen aynı kalsın)
	var mat: Material = null
	for n in p.find_children("*", "MeshInstance3D", true, false):
		var mo := (n as MeshInstance3D).material_override
		if mo is ShaderMaterial and mo.has_meta("paint"):
			mat = mo
			break
	mi.material_override = mat if mat else material("paint")
	p.add_child(mi)
	# parça uzayında (parça düğümü ölçeksiz; ölçek Visual'da): lathe ekseni parçanın z'si, kökte


static var _cockpit_panel: ShaderMaterial


## Kokpit iç yüzey malzemesi (paylaşılan; panel ışığı CockpitModule'den).
static func cockpit_panel_material() -> ShaderMaterial:
	if _cockpit_panel == null:
		_cockpit_panel = ShaderMaterial.new()
		_cockpit_panel.shader = preload("res://vessel/cockpit_panel.gdshader")
	return _cockpit_panel


# ------------------------------------------------------------------ motor / pod pilonları

## Kanadın (ya da gövdenin) altına boşlukla takılan motor ve podları yukarıdaki yüzeye bağlayan
## aerodinamik pilon: önü yuvarlak, arkası sivri, ince bir dikey kanatçık. Kurulumda otomatik.
static func _add_pylons(v: Vessel) -> void:
	# Asılı parçalar (motor gondolu, pod, ray, harici yük) ve ana takımlar havada durmasın: bağlantı
	# noktasından yukarı ışın atıp üstteki gerçek yüzeye (kanat altı / gövde) olan boşluğu ölçer,
	# arayı pilon ya da takım dikmesi uzantısıyla doldurur. Oyuncunun kendi tasarımlarında da çalışır.
	# aynı uçak tekrar kurulunca (yapay zekâ doğarken) ışın testleri önbellekten: ~25 ms tasarruf
	_sig = _craft_sig(v)
	var faces := {}
	for p in v.parts:
		var gear := false
		var hang: bool = p.def.get("category", "") == "harici"
		for m in p.modules:
			if m is LandingGearModule:
				gear = true
			elif m is EngineModule or m is TargetingPodModule or m is BombModule or m is MissileModule or m is GunModule:
				hang = true
		# gövdenin üstüne oturan parçalar (radar diski, sensör, sırt yükü): altındaki yüzeye dikme
		if not gear and not hang and p.def.get("mount", "") == "surface" and p.position.y > 0.3:
			var bu := _cached_box(v, p, faces)
			if bu.size != Vector3.ZERO:
				var bottom := Vector3(bu.get_center().x, bu.position.y + 0.02, bu.get_center().z)
				var gd := _cached_gap(v, p, bottom, Vector3.DOWN, faces)
				if gd > 0.04 and gd < 2.5:
					var pl := MeshInstance3D.new()
					pl.name = "Pylon"
					var bm := BoxMesh.new()
					bm.size = Vector3(clampf(bu.size.x * 0.06, 0.12, 0.3), gd + 0.16, clampf(bu.size.z * 0.4, 0.4, 2.5))
					pl.mesh = bm
					pl.material_override = material("paint_dark")
					pl.position = p.transform.affine_inverse() * (bottom - Vector3(0, gd * 0.5, 0))
					pl.basis = p.basis.inverse()
					p.add_child(pl)
			continue
		if not gear and not hang:
			continue
		var box := _cached_box(v, p, faces)
		if box.size == Vector3.ZERO:
			continue
		if gear:
			var top := p.position + Vector3(0, 0.02, 0)
			var gap := _cached_gap(v, p, top, Vector3.UP, faces)
			if gap > 0.03 and gap < 2.5:
				_add_gear_mount(p, gap + 0.06)
			continue
		# gövdenin içine gömülü (eksene yakın, dibi gövdenin içinde) parçalar pilon istemez
		var top_pt := Vector3(box.get_center().x, box.end.y - 0.02, box.get_center().z)
		var gap2 := _cached_gap(v, p, top_pt, Vector3.UP, faces)
		if gap2 < 0.04 or gap2 > 2.5:
			continue
		var length := clampf(box.size.z * 0.6, 0.35, 3.5)
		var height := gap2 + 0.12
		var w := clampf(box.size.x * 0.14, 0.05, 0.2)
		var prof := [Vector2(-length * 0.5, 0.0), Vector2(-length * 0.45, 0.6), Vector2(-length * 0.3, 1.0),
			Vector2(length * 0.2, 0.85), Vector2(length * 0.5, 0.0)]
		var mi := MeshInstance3D.new()
		mi.name = "Pylon"
		mi.mesh = MeshFactory.lathe(prof, 12)
		mi.material_override = material("paint_dark")
		var center := Vector3(top_pt.x, top_pt.y + height * 0.5 - 0.04, top_pt.z)
		mi.position = p.transform.affine_inverse() * center
		mi.basis = p.basis.inverse() * Basis().scaled(Vector3(w, height * 0.5, 1.0))
		p.add_child(mi)


static var _sig := ""
static var _gap_cache := {}

static func _craft_sig(v: Vessel) -> String:
	var s := PackedStringArray()
	for p in v.parts:
		s.append("%s%s%s%.3f" % [p.part_id, p.position.snapped(Vector3.ONE * 0.001), p.rotation.snapped(Vector3.ONE * 0.001), p.size.x])
	return str(hash("|".join(s)))


static func _cached_gap(v: Vessel, p: Part, from: Vector3, dir: Vector3, faces: Dictionary) -> float:
	var key := "%s:%d:%s:%s" % [_sig, v.parts.find(p), from.snapped(Vector3.ONE * 0.001), dir]
	if not _gap_cache.has(key):
		if _gap_cache.size() > 4000:
			_gap_cache.clear()
		_gap_cache[key] = _gap_dir(v, p, from, dir, faces)
	return _gap_cache[key]


static func _cached_box(v: Vessel, p: Part, faces: Dictionary) -> AABB:
	var key := "%s:%d:box" % [_sig, v.parts.find(p)]
	if not _gap_cache.has(key):
		_faces_of(p, faces)
		_gap_cache[key] = faces[str(p.get_instance_id())]
	return _gap_cache[key]


## Parçanın üçgenleri ve kutusu, ilk gerektiğinde (önbellek isabetinde hiç hesaplanmaz).
static func _faces_of(p: Part, faces: Dictionary) -> Array:
	if not faces.has(p):
		faces[p] = _part_faces(p)
		faces[str(p.get_instance_id())] = _faces_aabb(faces[p]) if not (faces[p] as Array).is_empty() else AABB()
	return faces[p]

## Takım dikmesinin üstüne, kanat altına / gövdeye uzanan sabit bağlantı borusu ve küçük kaporta.
static func _add_gear_mount(p: Part, len: float) -> void:
	var vis := p.get_node_or_null("Visual") as Node3D
	if vis == null:
		return
	var s := absf(vis.scale.y)
	var r := clampf(p.size.x * 0.12, 0.06, 0.16)
	var mi := MeshInstance3D.new()
	mi.name = "StrutMount"
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 1.15 / s
	cyl.bottom_radius = r / s
	cyl.height = len / s
	mi.mesh = cyl
	mi.material_override = material("metal")
	mi.position = Vector3(0, len * 0.5 / s, 0)
	vis.add_child(mi)
	# yan destek (çapraz dikme) kanadın altına doğru
	var brace := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = r * 0.45 / s
	bc.bottom_radius = r * 0.45 / s
	bc.height = len * 1.1 / s
	brace.mesh = bc
	brace.material_override = material("metal")
	var side := -signf(p.position.x) if absf(p.position.x) > 0.2 else 1.0
	brace.position = Vector3(side * len * 0.22 / s, len * 0.45 / s, 0)
	brace.rotation = Vector3(0, 0, side * 0.45)
	vis.add_child(brace)


## (from) noktasından (dir) yönünde (yukarı / aşağı) ilk başka-parça yüzeyine olan mesafe; yoksa INF.
static func _gap_dir(v: Vessel, self_part: Part, from: Vector3, dir: Vector3, faces: Dictionary) -> float:
	var best := INF
	for o in v.parts:
		if o == self_part:
			continue
		var tris: Array = _faces_of(o, faces)
		var ob: AABB = faces[str(o.get_instance_id())]
		if tris.is_empty() or from.x < ob.position.x or from.x > ob.end.x or from.z < ob.position.z or from.z > ob.end.z:
			continue
		for t in range(0, tris.size(), 3):
			var a: Vector3 = tris[t]
			var b: Vector3 = tris[t + 1]
			var c: Vector3 = tris[t + 2]
			if from.x < minf(a.x, minf(b.x, c.x)) or from.x > maxf(a.x, maxf(b.x, c.x)):
				continue
			if from.z < minf(a.z, minf(b.z, c.z)) or from.z > maxf(a.z, maxf(b.z, c.z)):
				continue
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
			if hit != null:
				best = minf(best, absf((hit as Vector3).y - from.y))
	return best


## (from) noktasından yukarı (+y) ilk başka-parça yüzeyine olan mesafe; yoksa INF.
static func _gap_above(v: Vessel, self_part: Part, from: Vector3, faces: Dictionary) -> float:
	var best := INF
	for o in v.parts:
		if o == self_part:
			continue
		var tris: Array = faces[o]
		for t in range(0, tris.size(), 3):
			var a: Vector3 = tris[t]
			var b: Vector3 = tris[t + 1]
			var c: Vector3 = tris[t + 2]
			if from.x < minf(a.x, minf(b.x, c.x)) or from.x > maxf(a.x, maxf(b.x, c.x)):
				continue
			if from.z < minf(a.z, minf(b.z, c.z)) or from.z > maxf(a.z, maxf(b.z, c.z)):
				continue
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.UP, a, b, c)
			if hit != null:
				best = minf(best, (hit as Vector3).y - from.y)
	return best


## Parçanın taşıt uzayındaki görünür, opak üçgenleri (efekt ve cam hariç).
static func _part_faces(p: Part) -> Array:
	var out := []
	var stack: Array[Node] = [p]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if not nd is MeshInstance3D:
			continue
		var mi := nd as MeshInstance3D
		if mi.mesh == null or mi.name == "Pylon":
			continue
		var mo := mi.material_override
		if mo is StandardMaterial3D and (mo.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mo.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
			continue
		if mo is ShaderMaterial and not mo.has_meta("paint"):
			continue
		var xf := Transform3D.IDENTITY
		var c: Node = mi
		while c != null and c != p.get_parent():
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		for f in mi.mesh.get_faces():
			out.append(xf * f)
	return out


static func _faces_aabb(tris: Array) -> AABB:
	var b := AABB(tris[0], Vector3.ZERO)
	for t in tris:
		b = b.expand(t)
	return b
