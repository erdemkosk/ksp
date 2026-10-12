class_name DamageFx
extends Node3D
## Parça hasarının görünür izleri (parçanın çocuğu; parça koparsa enkazla birlikte gider):
##   • is / yanık: sağlık düştükçe parçanın üstüne koyulaşan lekeli kararma (5 kademe)
##   • kurşun delikleri / patlama yanıkları: isabet noktasına Decal (parça başına sınırlı)
##   • duman: %65 altında ince gri, %35 altında koyu kalın duman izi
##   • yangın: motor %40 / dolu yakıt tankı %30 altında alev, ışık; yangın parçayı yakmaya devam eder
##   • yakıt sızıntısı: delik tanktan beyaz buhar izi, yakıt azalır
##   • kopma: kopan parçayla kalan parçanın birleşim yüzüne yırtık metal kapak, kıvılcım, duman

const MAX_HOLES := 10               ## parça başına iz (dolunca en eskisi taşınır)
const MAX_HOLES_TOTAL := 260        ## tüm sahnede iz (Forward+ kümeli decal sınırının altında)
const SOOT_LEVELS := 5

static var _scorch := []            # kademeli is kaplama malzemeleri
static var _hole_tex: Array[Texture2D] = []
static var _blast_tex: Texture2D
static var _all_holes: Array[Decal] = []
static var _tear_frame := -1
static var _tear_trails := 0        # bu fizik karesinde açılan kopma duman izi sayısı

var part: Part
var _level := -1
var _smoke: PuffTrail
var _heavy := false
var _fire: PuffTrail
var _leak: PuffTrail
var _light: OmniLight3D
var _holes: Array[Decal] = []


static func for_part(p: Part) -> DamageFx:
	for c in p.get_children():
		if c is DamageFx:
			return c
	var fx := DamageFx.new()
	fx.name = "DamageFx"
	fx.part = p
	p.add_child(fx)
	return fx


static func _scorch_mat(level: int) -> Material:
	if _scorch.is_empty():
		var noise := FastNoiseLite.new()
		noise.frequency = 0.022
		noise.fractal_octaves = 5
		for i in SOOT_LEVELS:
			var tex := NoiseTexture2D.new()
			tex.width = 256
			tex.height = 256
			tex.seamless = true
			tex.noise = noise
			var g := Gradient.new()
			var cut: float = [0.6, 0.5, 0.4, 0.3, 0.18][i]
			g.set_color(0, Color(0.035, 0.028, 0.022, 0.0))
			g.set_offset(0, cut)
			g.set_color(1, Color(0.025, 0.02, 0.016, [0.6, 0.72, 0.82, 0.9, 0.95][i]))
			g.set_offset(1, cut + 0.26)
			tex.color_ramp = g
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = tex
			m.roughness = 0.95
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.3
			m.render_priority = 1
			_scorch.append(m)
	return _scorch[level]


## Sağlık değişince çağrılır.
func refresh() -> void:
	var h := part.health_ratio()
	var level := -1
	for i in SOOT_LEVELS:
		if h < [0.85, 0.7, 0.5, 0.3, 0.15][i]:
			level = i
	if level != _level:
		_level = level
		part.damage_overlay = _scorch_mat(level) if level >= 0 else null
		_set_overlay(part.damage_overlay)
	if h < 0.65 and _smoke == null:
		_smoke = PuffTrail.create(self, Vector3.ZERO, "smoke")
		# hafif hasar: ince gri duman
		_smoke.size0 = 0.6
		_smoke.size1 = 3.5
		_smoke.life = 3.0
		_smoke.c0 = Color(0.42, 0.41, 0.4, 0.45)
		_smoke.c1 = Color(0.55, 0.55, 0.55, 0.0)
	if h < 0.35 and _smoke != null and not _heavy:
		# ağır hasar: koyu, kalın duman (PuffTrail özellikleri her karede okunur)
		_heavy = true
		_smoke.size0 = 1.4
		_smoke.size1 = 7.0
		_smoke.life = 4.5
		_smoke.c0 = Color(0.1, 0.095, 0.09, 0.8)
		_smoke.c1 = Color(0.3, 0.3, 0.3, 0.0)
	var engine := _has(EngineModule)
	var tank := _tank()
	var burning := (engine and h < 0.4) or (tank != null and tank.fuel > 30.0 and h < 0.3)
	if burning and _fire == null:
		_fire = PuffTrail.create(self, Vector3.ZERO, "fire")
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.omni_range = 14.0
		add_child(_light)
	if tank != null and h < 0.6 and tank.fuel > 0.0 and _leak == null:
		# buhar delikten çıksın: son isabet noktası varsa oradan
		var at := Vector3.ZERO
		if not _holes.is_empty() and is_instance_valid(_holes[-1]):
			at = to_local(_holes[-1].global_position)
		_leak = PuffTrail.create(self, at, "leak")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(part):
		return
	if _light:
		_light.light_energy = randf_range(2.0, 4.5)
	var v := part.vessel
	# yangın parçayı yakar (sonunda patlar)
	if _fire and is_instance_valid(v) and part in v.parts:
		v.damage_part(part, 4.0 * delta)
	# sızıntı: delikten yakıt akar
	if _leak:
		var tank := _tank()
		if tank and tank.fuel > 0.0:
			tank.fuel = maxf(tank.fuel - (1.0 - part.health_ratio()) * 6.0 * delta, 0.0)
		else:
			_leak.emitting = false


func _has(t: Variant) -> bool:
	for m in part.modules:
		if is_instance_of(m, t):
			return true
	return false


func _tank() -> FuelTankModule:
	for m in part.modules:
		if m is FuelTankModule:
			return m
	return null


func _set_overlay(mat: Material) -> void:
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GPUParticles3D or n is CockpitSwitch:
			continue
		stack.append_array(n.get_children())
		if n is MeshInstance3D and not (n.material_override is ShaderMaterial and not n.material_override.has_meta("paint")):
			n.material_overlay = mat


# ---------------------------------------------------------------- isabet izleri

## Mermi isabeti: dünya konumu + yüzey normali. Parça başına MAX_HOLES iz tutulur.
static func bullet_hole(p: Part, pos: Vector3, normal: Vector3) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	var s := randf_range(0.6, 0.95)
	for_part(p)._add_mark(pos, normal, s, _hole_texture(randi() % 3), 0.5)


## Patlama yanığı: patlama merkezine bakan yüzde büyük is lekesi + şarapnel delikleri.
static func blast_mark(p: Part, blast_pos: Vector3, strength: float) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	var c := p.global_position
	var n := blast_pos - c
	if n.length() < 0.01:
		n = Vector3.UP
	n = n.normalized()
	var reach := maxf(p.size.x, maxf(p.size.y, p.size.z))
	var s := clampf(1.2 + strength * 2.5, 1.2, 3.5)
	# kutu parçanın merkezinden patlama yönüne uzanır; normal_fade arka yüzleri eler
	for_part(p)._add_mark(c + n * reach * 0.3, n, s, _blast_texture(), reach * 0.9)


func _add_mark(pos: Vector3, normal: Vector3, s: float, tex: Texture2D, depth: float) -> void:
	var d: Decal = null
	if _holes.size() >= MAX_HOLES:
		var old: Variant = _holes.pop_front()          # en eskisini yeni yere taşı
		if is_instance_valid(old):
			d = old
	if d == null:
		d = Decal.new()
		d.normal_fade = 0.35
		d.upper_fade = 0.15
		d.lower_fade = 0.15
		d.distance_fade_enabled = true
		d.distance_fade_begin = 220.0
		d.distance_fade_length = 60.0
		d.cull_mask = 0xFFFFF
		# kontrol yüzeyi / iniş takımı görseli hareket eder: iz görselle birlikte dönsün
		var parent: Node3D = part
		var vis := part.get_node_or_null("Visual") as Node3D
		if vis and (_has(ControlSurfaceModule) or _has(LandingGearModule)):
			parent = vis
		parent.add_child(d)
		_all_holes.append(d)
		if _all_holes.size() > MAX_HOLES_TOTAL:
			_trim_global()
	_holes.append(d)
	d.texture_albedo = tex
	d.size = Vector3(s, depth, s)
	var y := normal.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized().rotated(y, randf() * TAU)
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)), pos)
	d.reset_physics_interpolation()


static func _trim_global() -> void:
	# önce enkazla silinmiş (geçersiz) izleri at, hâlâ fazlaysa en eskileri sil
	for i in range(_all_holes.size() - 1, -1, -1):
		if not is_instance_valid(_all_holes[i]):
			_all_holes.remove_at(i)
	while _all_holes.size() > MAX_HOLES_TOTAL:
		var d: Decal = _all_holes.pop_front()
		d.free()


## Kurşun deliği dokusu: kara delik, yırtık açık metal ağız, etrafında is halesi.
static func _hole_texture(variant: int) -> Texture2D:
	if _hole_tex.is_empty():
		var noise := FastNoiseLite.new()
		noise.frequency = 0.09
		noise.fractal_octaves = 3
		for k in 3:
			noise.seed = 17 + k * 31
			var n := 96
			var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
			var ph := [randf() * TAU, randf() * TAU, randf() * TAU]
			for py in n:
				for px in n:
					var u := (px + 0.5) / n * 2.0 - 1.0
					var v := (py + 0.5) / n * 2.0 - 1.0
					var r := sqrt(u * u + v * v)
					var a := atan2(v, u)
					var jag := sin(a * 5.0 + ph[0]) * 0.5 + sin(a * 9.0 + ph[1]) * 0.3 + sin(a * 14.0 + ph[2]) * 0.2
					var mott := noise.get_noise_2d(px * 2.0, py * 2.0) * 0.5 + 0.5
					var rh := 0.15 * (1.0 + 0.3 * jag)
					var rr := rh + 0.07 * (1.0 + 0.8 * absf(jag))
					var col: Color
					if r < rh:
						col = Color(0.01, 0.01, 0.01, 1.0)
					elif r < rr:
						# yırtılıp dışa kıvrılmış açık metal
						var t := (r - rh) / maxf(rr - rh, 0.001)
						col = Color(0.62, 0.6, 0.56, 1.0).lerp(Color(0.3, 0.28, 0.26, 1.0), t)
					else:
						var t := clampf((r - rr) / (0.95 - rr), 0.0, 1.0)
						var al := (1.0 - t) * (1.0 - t) * (0.55 + 0.45 * mott) * 0.92
						col = Color(0.04, 0.035, 0.03, clampf(al, 0.0, 1.0))
					img.set_pixel(px, py, col)
			img.generate_mipmaps()
			_hole_tex.append(ImageTexture.create_from_image(img))
	return _hole_tex[variant % _hole_tex.size()]


## Patlama yanığı dokusu: lekeli is + rastgele şarapnel delikleri.
static func _blast_texture() -> Texture2D:
	if _blast_tex:
		return _blast_tex
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	noise.seed = 5
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var holes := []
	for i in 14:
		holes.append(Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), randf_range(0.015, 0.04)))
	for py in n:
		for px in n:
			var u := (px + 0.5) / n * 2.0 - 1.0
			var v := (py + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var mott := noise.get_noise_2d(px, py) * 0.5 + 0.5
			var al := clampf((1.0 - smoothstep(0.2, 1.0, r + (mott - 0.5) * 0.5)) * 1.1, 0.0, 0.95)
			var col := Color(0.03, 0.025, 0.02, al)
			for h: Vector3 in holes:
				if Vector2(u - h.x, v - h.y).length() < h.z:
					col = Color(0.0, 0.0, 0.0, 1.0)
			img.set_pixel(px, py, col)
	img.generate_mipmaps()
	_blast_tex = ImageTexture.create_from_image(img)
	return _blast_tex


# ---------------------------------------------------------------- kopma

## İki komşu parça ayrılıyor (a kopuyor, b kalıyor ya da tersi). İkisi de henüz aynı aracın
## çocuğuyken çağrılmalı (konumlar araç uzayında karşılaştırılır). Birleşim yüzüne iki tarafta
## da yırtık metal kapak koyar; kıvılcım ve kısa duman izi çıkarır.
static func tear(a: Part, b: Part) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a.get_parent() != b.get_parent():
		return
	var aa := a.local_aabb(0.15)
	var bb := b.local_aabb(0.15)
	var inter := aa.intersection(bb)
	# birleşim normali: merkezler arası uzaklığın iki yarı boyuta oranı en büyük olan eksen
	# (kanat kökü gövdenin yanında: X; arka arkaya iki gövde parçası: Z)
	var dpos := b.position - a.position
	var ha := aa.size * 0.5
	var hb := bb.size * 0.5
	var axis := 0
	var best := -1.0
	for k in 3:
		var sc := absf(dpos[k]) / maxf(ha[k] + hb[k], 0.01)
		if sc > best:
			best = sc
			axis = k
	var center: Vector3
	if inter.size == Vector3.ZERO:
		center = (a.position + b.position) * 0.5
		inter = AABB(center, Vector3.ZERO)
	else:
		center = inter.get_center()
	var dir := Vector3.ZERO
	dir[axis] = 1.0 if (b.position - a.position)[axis] >= 0.0 else -1.0
	# kesit: diğer iki eksendeki çakışma (ince kanat kökü ince, gövde ekleri yuvarlak)
	var ax1 := (axis + 1) % 3
	var ax2 := (axis + 2) % 3
	var w := clampf(inter.size[ax1] - 0.2, 0.3, 3.5)
	var h := clampf(inter.size[ax2] - 0.2, 0.25, 3.5)
	var vb := a.get_parent() as Node3D
	var first := Engine.get_physics_frames() != _tear_frame
	if first:
		_tear_frame = Engine.get_physics_frames()
		_tear_trails = 0
	# kopan taraf (a): b'ye bakan yüz; kalan taraf (b): a'ya bakan yüz
	var smoke_ok := _tear_trails < 4
	if smoke_ok:
		_tear_trails += 2
	_cap(a, center, dir, ax1, ax2, w, h, smoke_ok, 5.0)
	_cap(b, center, -dir, ax1, ax2, w, h, smoke_ok, 12.0)
	# kırılan parça artık kendi isi/dumanını taşısın
	if a.hp <= 0.0:
		for_part(a).refresh()
	if b.hp <= 0.0:
		for_part(b).refresh()
	if vb:
		var gp := vb.global_transform * center
		var gn := (vb.global_basis * -dir).normalized()
		var root: Node3D = FloatingOrigin.world_root if FloatingOrigin.world_root else vb.get_parent() as Node3D
		Effects.sparks(root, gp, gn)
		Effects.sparks(root, gp, -gn)


## Yırtık metal kapağı parçanın çocuğu olarak ekler (yerel uzaya çevirerek).
static func _cap(p: Part, center: Vector3, dir: Vector3, ax1: int, ax2: int, w: float, h: float, smoke: bool, smoke_time: float) -> void:
	var inv := p.transform.affine_inverse()
	var e1 := Vector3.ZERO
	e1[ax1] = 1.0
	var e2 := Vector3.ZERO
	e2[ax2] = 1.0
	# kapak yerel ekseni: X = e1*w, Y = normal, Z = e2*h (araç uzayında), sonra parça uzayına
	var depth := clampf(maxf(w, h) * 0.22, 0.3, 1.0)
	var bas := Basis(e1 * w, dir * depth, e2 * h)
	if bas.determinant() < 0.0:
		bas = Basis(-e1 * w, dir * depth, e2 * h)
	var mi := MeshInstance3D.new()
	mi.name = "TornCap"
	mi.mesh = _torn_mesh()
	if _torn_dark == null:
		_torn_dark = StandardMaterial3D.new()
		_torn_dark.vertex_color_use_as_albedo = true
		_torn_dark.metallic = 0.3
		_torn_dark.roughness = 0.9
		_torn_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	# yırtık kenar: çıplak metal, ilk saniyelerde kor gibi kızgın
	var rim := StandardMaterial3D.new()
	rim.vertex_color_use_as_albedo = true
	rim.metallic = 0.75
	rim.roughness = 0.45
	rim.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim.emission_enabled = true
	rim.emission = Color(1.0, 0.28, 0.04)
	rim.emission_energy_multiplier = 1.2
	mi.set_surface_override_material(0, _torn_dark)
	mi.set_surface_override_material(1, rim)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	mi.transform = inv * Transform3D(bas, center + dir * 0.03)
	mi.reset_physics_interpolation()
	if p.damage_overlay:
		mi.material_overlay = p.damage_overlay
	# kızgın kenarlar soğur
	var tw := mi.create_tween()
	tw.tween_property(rim, "emission_energy_multiplier", 0.0, 2.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if smoke:
		var marker := Node3D.new()
		marker.name = "TornSmoke"
		p.add_child(marker)
		marker.transform = inv * Transform3D(Basis.IDENTITY, center + dir * 0.2)
		var t := PuffTrail.create(marker, Vector3.ZERO, "smoke")
		t.size0 = 0.7
		t.size1 = 4.5
		t.life = 3.5
		t.c0 = Color(0.16, 0.15, 0.14, 0.7)
		t.max_puffs = 160
		marker.get_tree().create_timer(smoke_time).timeout.connect(func() -> void:
			if is_instance_valid(t):
				t.emitting = false)



static var _torn: Array[ArrayMesh] = []
static var _torn_dark: StandardMaterial3D

## Birim yırtık kapak: içe göçmüş koyu merkez (yüzey 0) ve dişli, dışa kıvrık açık metal
## kenar şeritleri (yüzey 1). Düzlem XZ, normal +Y; yarıçap ~0.5 (kapak w/h ile ölçeklenir).
static func _torn_mesh() -> ArrayMesh:
	if _torn.size() < 4:
		var n := 24
		var inner: Array[Vector3] = []
		var outer: Array[Vector3] = []
		for i in n:
			var a := TAU * i / n + randf_range(-0.07, 0.07)
			var dirv := Vector3(cos(a), 0.0, sin(a))
			inner.append(dirv * 0.5 * randf_range(0.6, 0.78) + Vector3(0, randf_range(-0.15, 0.0), 0))
			var spike := i % 2 == 0 and randf() < 0.8
			var ro := 0.5 * (randf_range(1.05, 1.35) if spike else randf_range(0.85, 1.0))
			outer.append(dirv * ro + Vector3(0, randf_range(0.25, 0.6) if spike else randf_range(0.0, 0.15), 0))
		var mesh := ArrayMesh.new()
		# yüzey 0: koyu, içe göçmüş krater
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var c := Vector3(0, -0.3, 0)
		for i in n:
			var j := (i + 1) % n
			st.set_color(Color(0.02, 0.018, 0.016))
			st.add_vertex(c)
			st.set_color(Color(0.1, 0.09, 0.08))
			st.add_vertex(inner[j])
			st.add_vertex(inner[i])
		st.generate_normals()
		st.commit(mesh)
		# yüzey 1: yırtık kenar halkası (içte isli, uçta parlak metal)
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sooty := Color(0.12, 0.11, 0.1)
		var bare := Color(0.6, 0.58, 0.55)
		for i in n:
			var j := (i + 1) % n
			st.set_color(sooty)
			st.add_vertex(inner[i])
			st.add_vertex(inner[j])
			st.set_color(bare)
			st.add_vertex(outer[i])
			st.set_color(sooty)
			st.add_vertex(inner[j])
			st.set_color(bare)
			st.add_vertex(outer[j])
			st.add_vertex(outer[i])
		st.generate_normals()
		st.commit(mesh)
		_torn.append(mesh)
	return _torn[randi() % _torn.size()]
