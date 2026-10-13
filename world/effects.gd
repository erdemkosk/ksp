class_name Effects
## Tek seferlik görsel efektler: patlama alevi + duman, su sıçraması.
## Efektler dünya köküne eklenir ve kendi kendini siler.

static var _fire_mat: ParticleProcessMaterial
static var _smoke_mat: ParticleProcessMaterial
static var _splash_mat: ParticleProcessMaterial
static var _fire_mesh: QuadMesh
static var _smoke_mesh: QuadMesh
static var _splash_mesh: QuadMesh


## Patlama: boyut (size ~0.8 füze … 4 ağır bomba) ateş topunu, dumanı, parlamayı ölçekler.
## Önceden `size` yalnız parçacık sayısını değiştiriyordu: her patlama aynı 3.5 m'lik topu
## çiziyordu, yüksekten görünmüyordu. Şimdi: parlama ışığı + beyaz çakma, ateş topu, yerdeyse
## toprak fışkırması ve şok halkası, uzun kalan koyu duman sütunu.
static func explosion(parent: Node3D, pos: Vector3, up: Vector3, size: float) -> void:
	_init_resources()
	var s := clampf(size, 0.5, 6.0)
	var near_ground := Planet.altitude(pos) - maxf(TerrainGen.height(Planet.surface_dir(pos)), 0.0) < 8.0 * s
	_flash(parent, pos, s)
	_burst(parent, pos, up, _fire_mat, _fire_mesh, int(26 + 12 * s), 0.7 + 0.25 * s, s)
	_burst(parent, pos, up, _smoke_mat, _smoke_mesh, int(18 + 8 * s), 4.0 + 2.0 * s, s * 1.2)
	if near_ground:
		dust(parent, pos, up)
		_burst(parent, pos, up, _debris_mat(), _dust_mesh, int(20 + 10 * s), 1.6 + 0.3 * s, s * 2.5)
		_ring(parent, pos, up, s)


static var _debris: ParticleProcessMaterial


## Yer patlamasında yukarı fışkıran toprak ve moloz (yerçekimiyle geri düşer).
static func _debris_mat() -> ParticleProcessMaterial:
	if _debris:
		return _debris
	_debris = ParticleProcessMaterial.new()
	_debris.direction = Vector3.UP
	_debris.spread = 28.0
	_debris.initial_velocity_min = 10.0
	_debris.initial_velocity_max = 22.0
	_debris.gravity = Vector3(0, -12.0, 0)
	_debris.scale_min = 0.5
	_debris.scale_max = 1.4
	_debris.angle_min = -180.0
	_debris.angle_max = 180.0
	_debris.color_ramp = _ramp([Color(0.3, 0.25, 0.18, 0.95), Color(0.28, 0.24, 0.18, 0.7), Color(0.35, 0.32, 0.28, 0.0)])
	return _debris


## Kısa beyaz çakma (ışık + parlak küre): uzaktan da görünür, çevreyi bir an aydınlatır.
static func _flash(parent: Node3D, pos: Vector3, s: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 10.0
	light.omni_range = 40.0 * s
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35 + 0.1 * s).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)
	# kameraya dönük yumuşak kenarlı parlak bulut (küre düz soluk bir disk gibi görünüyordu)
	var ball := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	ball.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _puff_texture()
	m.albedo_color = Color(1.0, 0.8, 0.5, 1.0)
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 7.0 * s
	var tb := ball.create_tween().set_parallel(true)
	tb.tween_property(ball, "scale", Vector3.ONE * 16.0 * s, 0.35).set_ease(Tween.EASE_OUT)
	tb.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tb.chain().tween_callback(ball.queue_free)


## Yerde genişleyen şok / toz halkası.
static func _ring(parent: Node3D, pos: Vector3, up: Vector3, s: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.56, 0.48, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	mi.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), pos + up * 0.5)
	mi.scale = Vector3(2.0, 0.6, 2.0) * s
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(14.0, 0.3, 14.0) * s, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(mi.queue_free)


static func splash(parent: Node3D, pos: Vector3, up: Vector3, size: float) -> void:
	_init_resources()
	_burst(parent, pos, up, _splash_mat, _splash_mesh, int(60 * size), 1.8, size)


static func _burst(parent: Node3D, pos: Vector3, up: Vector3, mat: ParticleProcessMaterial, mesh: Mesh, amount: int, life: float, size: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 4)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.process_material = mat
	p.draw_pass_1 = mesh
	p.local_coords = true   # sabit yayıcı: kayan orijinle birlikte kayar
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	parent.add_child(p)
	p.global_position = pos
	# parçacıkların "yukarı"sı yerel gezegen yukarısı olsun
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	# size düğümü ölçekler: yerel koordinatlı parçacıklar (boyut, hız, yayılma) birlikte büyür
	p.global_basis = Basis(x, up, x.cross(up).normalized()).scaled(Vector3.ONE * size)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _init_resources() -> void:
	if _fire_mat:
		return
	_fire_mat = ParticleProcessMaterial.new()
	_fire_mat.direction = Vector3.UP
	_fire_mat.spread = 70.0
	_fire_mat.initial_velocity_min = 7.0
	_fire_mat.initial_velocity_max = 16.0
	_fire_mat.gravity = Vector3(0, 2, 0)
	_fire_mat.damping_min = 4.0
	_fire_mat.damping_max = 8.0
	_fire_mat.scale_min = 0.6
	_fire_mat.scale_max = 1.4
	_fire_mat.color_ramp = _ramp([Color(1, 0.92, 0.65, 1), Color(1, 0.5, 0.12, 0.95), Color(0.22, 0.08, 0.03, 0)])
	_fire_mat.angle_min = -180.0
	_fire_mat.angle_max = 180.0
	_fire_mat.scale_curve = _grow_curve(0.9, 1.6)   # ateş topu hemen büyük başlar
	_fire_mesh = _quad(_billboard_mat(false), 7.0)   # eklemeli değil: gündüz parlak zeminde kayboluyordu

	_smoke_mat = ParticleProcessMaterial.new()
	_smoke_mat.direction = Vector3.UP
	_smoke_mat.spread = 50.0
	_smoke_mat.initial_velocity_min = 2.0
	_smoke_mat.initial_velocity_max = 6.0
	_smoke_mat.gravity = Vector3(0, 1.5, 0)
	_smoke_mat.damping_min = 1.0
	_smoke_mat.damping_max = 2.0
	_smoke_mat.scale_min = 0.6
	_smoke_mat.scale_max = 1.3
	_smoke_mat.color_ramp = _ramp([Color(0.08, 0.07, 0.06, 0.0), Color(0.1, 0.09, 0.08, 0.8), Color(0.3, 0.3, 0.3, 0.0)])
	_smoke_mat.angle_min = -180.0
	_smoke_mat.angle_max = 180.0
	_smoke_mat.scale_curve = _grow_curve(0.3, 1.6)
	_smoke_mesh = _quad(_billboard_mat(false), 12.0)

	_splash_mat = ParticleProcessMaterial.new()
	_splash_mat.direction = Vector3.UP
	_splash_mat.spread = 35.0
	_splash_mat.initial_velocity_min = 6.0
	_splash_mat.initial_velocity_max = 18.0
	_splash_mat.gravity = Vector3(0, -9.8, 0)
	_splash_mat.scale_min = 0.4
	_splash_mat.scale_max = 1.2
	_splash_mat.color_ramp = _ramp([Color(1, 1, 1, 0.85), Color(0.88, 0.92, 0.95, 0.5), Color(0.85, 0.9, 0.95, 0.0)])
	_splash_mat.angle_min = -180.0
	_splash_mat.angle_max = 180.0
	_splash_mat.scale_curve = _grow_curve(0.5, 1.8)
	_splash_mesh = _quad(_billboard_mat(false), 2.5)


static func _billboard_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _puff_texture()
	return m


static var _puff: ImageTexture


## Düzensiz kenarlı yumuşak duman bulutu dokusu (gürültü × radyal sönüm).
static func _puff_texture() -> ImageTexture:
	if _puff:
		return _puff
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.06
	n.fractal_octaves = 4
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5, y - size * 0.5).length() / (size * 0.5)
			var radial := clampf(1.0 - d, 0.0, 1.0)
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(smoothstep(0.0, 0.8, radial) * (0.35 + v * 0.9) - (1.0 - radial) * 0.3, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_puff = ImageTexture.create_from_image(img)
	return _puff


static func _quad(mat: Material, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


static func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _grow_curve(from: float, to: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = maxf(from, to)
	c.add_point(Vector2(0, from))
	c.add_point(Vector2(1, to))
	var t := CurveTexture.new()
	t.curve = c
	return t


static var _spark_mat: ParticleProcessMaterial
static var _spark_mesh: QuadMesh
static var _dust_mat: ParticleProcessMaterial
static var _dust_mesh: QuadMesh


## Mermi isabeti: kısa ömürlü parlak kıvılcımlar.
static func sparks(parent: Node3D, pos: Vector3, normal: Vector3) -> void:
	_init_resources()
	if _spark_mat == null:
		_spark_mat = ParticleProcessMaterial.new()
		_spark_mat.direction = Vector3.UP
		_spark_mat.spread = 60.0
		_spark_mat.initial_velocity_min = 6.0
		_spark_mat.initial_velocity_max = 20.0
		_spark_mat.gravity = Vector3(0, -9.8, 0)
		_spark_mat.scale_min = 0.2
		_spark_mat.scale_max = 0.5
		_spark_mat.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.6, 0.2, 0.9), Color(1, 0.3, 0.1, 0)])
		_spark_mesh = _quad(_billboard_mat(true), 0.6)
	_burst(parent, pos, normal, _spark_mat, _spark_mesh, 10, 0.35, 1.0)


## Zemine düşen mermi: toz/toprak fışkırması.
static func dust(parent: Node3D, pos: Vector3, normal: Vector3) -> void:
	_init_resources()
	if _dust_mat == null:
		_dust_mat = ParticleProcessMaterial.new()
		_dust_mat.direction = Vector3.UP
		_dust_mat.spread = 25.0
		_dust_mat.initial_velocity_min = 3.0
		_dust_mat.initial_velocity_max = 9.0
		_dust_mat.gravity = Vector3(0, -9.8, 0)
		_dust_mat.scale_min = 0.5
		_dust_mat.scale_max = 1.2
		_dust_mat.angle_min = -180.0
		_dust_mat.angle_max = 180.0
		_dust_mat.color_ramp = _ramp([Color(0.45, 0.38, 0.28, 0.8), Color(0.42, 0.36, 0.28, 0.5), Color(0.4, 0.35, 0.3, 0)])
		_dust_mesh = _quad(_billboard_mat(false), 1.8)
	_burst(parent, pos, normal, _dust_mat, _dust_mesh, 6, 1.2, 1.0)


## Füzenin arkasındaki sürekli duman izi (füzenin çocuğu; parçacıklar dünyada kalır).
static func smoke_trail() -> GPUParticles3D:
	_init_resources()
	var p := GPUParticles3D.new()
	p.fixed_fps = 0
	p.amount = 220
	p.lifetime = 5.0
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, 1)
	m.spread = 6.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 3.0
	m.gravity = Vector3.ZERO
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.scale_min = 0.6
	m.scale_max = 1.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.scale_curve = _grow_curve(0.4, 2.6)
	m.color_ramp = _ramp([Color(0.95, 0.95, 0.95, 0.75), Color(0.85, 0.85, 0.85, 0.4), Color(0.8, 0.8, 0.8, 0.0)])
	p.process_material = m
	p.draw_pass_1 = _quad(_billboard_mat(false), 2.2)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	p.emitting = true
	return p


## Yanan hedeften sürekli yükselen koyu duman.
static func smoke_column() -> GPUParticles3D:
	_init_resources()
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 9.0
	p.local_coords = true
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 4.0
	m.gravity = Vector3(0.6, 0.6, 0)
	m.scale_min = 0.8
	m.scale_max = 1.4
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.scale_curve = _grow_curve(0.4, 3.0)
	m.color_ramp = _ramp([Color(0.08, 0.07, 0.06, 0.0), Color(0.1, 0.09, 0.08, 0.7), Color(0.3, 0.3, 0.3, 0.0)])
	p.process_material = m
	p.draw_pass_1 = _quad(_billboard_mat(false), 5.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 400, 400))
	p.emitting = true
	return p
