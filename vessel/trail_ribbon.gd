class_name TrailRibbon
extends MeshInstance3D
## Sürekli iz şeridi (kanat ucu girdabı, kontrail): kaynağın son konumlarından her karede
## kameraya dönük bir üçgen şerit çizer. Parçacıkların hızlı uçakta kopuk nokta olmasını önler.
## Noktalar dünya uzayında tutulur, kayan orijinde birlikte kaydırılır.

var source: Node3D
var offset := Vector3.ZERO      ## kaynağın yerel uzayında
var width := 0.3
var grow := 1.0                 ## ömrün sonunda genişlik çarpanı
var life := 1.5
var color := Color(1, 1, 1, 0.5)
var emitting := false
var min_step := 1.5

var _pts: Array[Vector3] = []
var _born: Array[float] = []
var _strength: Array[float] = []
var _time := 0.0
var _im := ImmediateMesh.new()
var _level := 1.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	FloatingOrigin.shifted.connect(_on_shift)


## Şiddet 0..1 (ör. G arttıkça iz koyulaşır).
func set_level(x: float) -> void:
	_level = clampf(x, 0.0, 1.0)


func _on_shift(s: Vector3) -> void:
	for i in _pts.size():
		_pts[i] -= s


func _physics_process(delta: float) -> void:
	_time += delta
	while not _born.is_empty() and _time - _born[0] > life:
		_pts.pop_front()
		_born.pop_front()
		_strength.pop_front()
	if emitting and is_instance_valid(source) and source.is_inside_tree():
		var p := source.global_transform * offset
		if _pts.is_empty() or _pts[-1].distance_to(p) > min_step:
			_pts.append(p)
			_born.append(_time)
			_strength.append(_level)
	elif not _pts.is_empty() and _strength[-1] > 0.0:
		# yayın kesildi: bir sonraki nokta görünmez başlasın (şerit bağlanmasın)
		_strength[-1] = 0.0


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _pts.size() < 2:
		return
	var cp := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _pts.size()
	for i in n:
		var p := _pts[i]
		var dir := (_pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)]).normalized()
		var side := (cp - p).cross(dir).normalized()
		var age := clampf((_time - _born[i]) / life, 0.0, 1.0)
		var w := width * lerpf(1.0, grow, age)
		var a := color.a * (1.0 - age) * _strength[i]
		# baş tarafı (en yeni) yumuşak başlasın
		a *= clampf(float(n - 1 - i) / 4.0, 0.0, 1.0)
		var c := Color(color, a)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()
