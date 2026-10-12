class_name PuffTrail
extends MultiMeshInstance3D
## Duman / alev izi: kaynağın arkasında kameraya dönük duman bulutları (puf) bırakır.
## GPU parçacıkları dünya uzayında kaldığı için kayan orijin dünyayı kaydırınca iz uçağın
## önüne "ışınlanıyordu"; burada puflar dünya uzayında CPU'da tutulur ve kaydırmayla birlikte
## kaydırılır. Puflar katedilen mesafeye göre bırakılır (hızlı füzede iz kopmaz) ve kaynak
## dursa da zamanla bırakılmaya devam eder (yanan parça). Kaynak yok olunca puflar sönene
## kadar kalır, sonra iz kendini siler.

var source: Node3D
var offset := Vector3.ZERO          ## kaynağın yerel uzayında
var emitting := true
var spacing := 2.5                  ## iki puf arası en fazla mesafe (m)
var rate := 12.0                    ## kaynak dururken saniyede puf
var life := 5.0
var size0 := 1.0
var size1 := 5.0
var c0 := Color(0.95, 0.95, 0.95, 0.75)
var c1 := Color(0.8, 0.8, 0.8, 0.0)
var drift := 1.5                    ## pufların rastgele dağılma hızı (m/s)
var rise := 0.0                     ## sıcak duman yukarı yükselir (m/s)
var jitter := 0.3                   ## doğuş konumu saçılması (m)
var max_puffs := 400

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _last := Vector3.ZERO
var _has_last := false
var _since := 0.0
var _mm := MultiMesh.new()


## Hazır tipler: "missile", "flare", "smoke", "fire", "leak"
static func create(src: Node3D, local := Vector3.ZERO, kind := "missile") -> PuffTrail:
	var t := PuffTrail.new()
	t.source = src
	t.offset = local
	match kind:
		"flare":
			t.spacing = 1.6
			t.life = 3.5
			t.size0 = 0.7
			t.size1 = 3.6
			t.c0 = Color(0.98, 0.97, 0.95, 0.8)
			t.drift = 1.0
		"smoke":
			t.spacing = 2.5
			t.life = 4.5
			t.size0 = 1.4
			t.size1 = 7.0
			t.c0 = Color(0.1, 0.095, 0.09, 0.8)
			t.c1 = Color(0.3, 0.3, 0.3, 0.0)
			t.rise = 1.2
			t.rate = 10.0
		"fire":
			t.spacing = 0.9
			t.life = 0.6
			t.size0 = 1.3
			t.size1 = 2.4
			t.c0 = Color(1.0, 0.85, 0.4, 1.0)
			t.c1 = Color(0.9, 0.2, 0.05, 0.0)
			t.drift = 1.0
			t.rate = 30.0
		"leak":
			t.spacing = 1.2
			t.life = 2.2
			t.size0 = 0.4
			t.size1 = 2.8
			t.c0 = Color(0.92, 0.94, 0.95, 0.55)
			t.c1 = Color(0.9, 0.9, 0.9, 0.0)
			t.drift = 0.8
	var root: Node = FloatingOrigin.world_root if FloatingOrigin.world_root else src.get_tree().current_scene
	root.add_child(t)
	if kind == "fire":
		(t.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return t


func _ready() -> void:
	add_to_group("origin_fixed")
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	Effects._init_resources()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = q
	_mm.instance_count = max_puffs
	_mm.visible_instance_count = 0
	multimesh = _mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Effects._puff_texture()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	FloatingOrigin.shifted.connect(_on_shift)


func _on_shift(s: Vector3) -> void:
	for i in _pos.size():
		_pos[i] -= s
	_last -= s


func _emit_at(p: Vector3) -> void:
	if _pos.size() >= max_puffs:
		_drop(0)
	_pos.append(p + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jitter)
	_vel.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * drift * randf_range(0.3, 1.0))
	_age.append(0.0)
	_spin.append(randf_range(0.85, 1.15))


func _drop(i: int) -> void:
	_pos.remove_at(i)
	_vel.remove_at(i)
	_age.remove_at(i)
	_spin.remove_at(i)


func _process(delta: float) -> void:
	var alive := is_instance_valid(source) and source.is_inside_tree()
	if alive and emitting:
		var p := source.global_transform * offset
		if not _has_last:
			_last = p
			_has_last = true
			_emit_at(p)
		var d := p.distance_to(_last)
		_since += delta
		if d >= spacing:
			# katedilen yol boyunca eşit aralıklı puflar (hızlı kaynakta kopuk nokta olmasın)
			var n := mini(int(d / spacing), 60)
			for i in n:
				_emit_at(_last.lerp(p, float(i + 1) / n))
			_last = p
			_since = 0.0
		elif _since >= 1.0 / rate:
			_emit_at(p)
			_last = p
			_since = 0.0
	else:
		_has_last = false
	# yaşlandır, sürüklen
	var i := 0
	var up := Planet.up_at(_pos[0]) if rise != 0.0 and _pos.size() > 0 else Vector3.ZERO
	while i < _age.size():
		_age[i] += delta
		if _age[i] >= life:
			_drop(i)
			continue
		_vel[i] *= exp(-0.6 * delta)
		_pos[i] += (_vel[i] + up * rise) * delta
		i += 1
	var n := _pos.size()
	_mm.visible_instance_count = n
	for k in n:
		var t := _age[k] / life
		var s := lerpf(size0, size1, sqrt(t)) * _spin[k]
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[k]))
		var col := c0.lerp(c1, t)
		col.a = lerpf(c0.a, c1.a, t) * (1.0 - smoothstep(0.75, 1.0, t)) * smoothstep(0.0, 0.05, t + 0.02)
		_mm.set_instance_color(k, col)
	if not alive and n == 0:
		queue_free()
