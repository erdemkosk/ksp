class_name StressFx
extends Node
## Yapı zorlanmasını yazı okumadan hissettirir (main.gd oyuncu uçağını `vessel`e yazar).
## Kaynak: her parçanın Part.stress'i (Vessel._structural_loads; 1.0 = dayanım, 1.6 = anında kopar).
##   • renk (dış görüş): %70 sarı → %90 kırmızı → %100 üstü yanıp söner (paint.gdshader stress_glow)
##   • kanat bükülmesi: yük altında uçlar kalkar; çok zorlanınca / ses duvarında uç titrer (flex)
##   • ses: %60 üstü metal gıcırtısı, yük arttıkça sıklaşır; %90 üstü "tak" çatlama
##   • %90 üstü: zorlanan parçadan seyrek kıvılcım / perçin

const GLOW_FROM := 0.7
const CREAK_FROM := 0.6
const CRACK_FROM := 0.9
const FLEX_K := 0.006          ## stress 1.0'da 1 m açıklıkta 6 mm kalkma (5 m'de ~15 cm)

var vessel: Vessel
var _meshes := {}              ## Part → Array[GeometryInstance3D] (boya shader'lı ağlar)
var _roots := {}               ## Part → Array: kanat ağı başına Vector4(uçak yukarısı ağ uzayında xyz, kök x) ya da null
var _last := {}                ## Part → son yazılan glow şiddeti (gereksiz yazma olmasın)
var _n_parts := -1
var _t := 0.0
var _creak_t := 0.0
var _crack_t := 0.0
var _creak_i := 0
var _bound: Vessel             ## caches hangi uçak için toplandı


func _process(delta: float) -> void:
	if not is_instance_valid(vessel) or vessel.parts.is_empty():
		return
	if vessel != _bound or vessel.parts.size() != _n_parts:
		_bound = vessel
		_last.clear()
		_collect()
	_t += delta
	var cam := get_viewport().get_camera_3d() as FlightCamera
	var outside := cam == null or cam.mode != FlightCamera.Mode.COCKPIT
	var up := vessel.global_basis.y
	var worst := 0.0
	var worst_part: Part = null
	var buzz := clampf(1.0 - absf(vessel.mach() - 1.0) / 0.08, 0.0, 1.0)   # ses duvarı titreşimi
	for p: Part in vessel.parts:
		if not is_instance_valid(p):
			continue
		var s := p.stress
		if s > worst:
			worst = s
			worst_part = p
		# renk
		var a := 0.0
		var col := Color(1.0, 0.85, 0.15)
		if outside and s > GLOW_FROM:
			var k := smoothstep(GLOW_FROM, CRACK_FROM, s)
			col = Color(1.0, 0.85, 0.15).lerp(Color(1.0, 0.12, 0.05), k)
			a = lerpf(0.3, 0.85, k)
			if s >= 1.0:
				a *= 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * TAU * 5.0))
		var last: float = _last.get(p, 0.0)
		if a > 0.0 or last > 0.0:
			_last[p] = a
			for gi: GeometryInstance3D in _meshes.get(p, []):
				gi.set_instance_shader_parameter("stress_glow", Color(col, a))
		# kanat bükülmesi + uç titremesi
		var roots: Array = _roots.get(p, [])
		if not roots.is_empty():
			var dir := 1.0 if p.aero_load.dot(up) >= 0.0 else -1.0
			var f := FLEX_K * clampf(s, 0.0, 1.6) * dir
			var shake := maxf(smoothstep(0.8, 1.2, s), buzz * 0.6)
			f += sin(_t * 41.0 + p.position.x) * FLEX_K * 0.35 * shake
			var list: Array = _meshes.get(p, [])
			for i in list.size():
				var r: Variant = roots[i]
				if r is Vector4:
					var u: Vector4 = r
					(list[i] as GeometryInstance3D).set_instance_shader_parameter("flex", Vector4(u.x * f, u.y * f, u.z * f, u.w))
	_sounds(worst, worst_part, delta)


## Gıcırtı sıklaşır, %90'da çatlama; %90'da zorlanan parçadan kıvılcım.
func _sounds(worst: float, p: Part, delta: float) -> void:
	_creak_t -= delta
	_crack_t -= delta
	if p == null:
		return
	if worst > CREAK_FROM and _creak_t <= 0.0:
		var k := clampf((worst - CREAK_FROM) / 0.4, 0.0, 1.0)
		_creak_t = lerpf(1.6, 0.3, k) * randf_range(0.7, 1.3)
		_creak_i += 1
		Sfx.play_ui_stream(Sfx.creak_stream(_creak_i), lerpf(-16.0, -3.0, k), randf_range(0.85, 1.15) * lerpf(0.9, 1.15, k), Sfx.world_bus())
	if worst > CRACK_FROM and _crack_t <= 0.0:
		var k2 := clampf((worst - CRACK_FROM) / 0.5, 0.0, 1.0)
		_crack_t = lerpf(1.2, 0.25, k2) * randf_range(0.6, 1.4)
		Sfx.play_ui_stream(Sfx.crack_stream(), lerpf(-8.0, 0.0, k2), randf_range(0.8, 1.25), Sfx.world_bus())
		if FloatingOrigin.world_root:
			var n := (p.global_position - vessel.global_position).normalized()
			if n == Vector3.ZERO:
				n = vessel.global_basis.y
			Effects.sparks(FloatingOrigin.world_root, p.global_position + n * 0.3, n)


## Boya shader'lı ağları ve kanatların kök konumunu topla (parça sayısı değişince yeniden).
func _collect() -> void:
	_n_parts = vessel.parts.size()
	_meshes.clear()
	_roots.clear()
	for p: Part in vessel.parts:
		var list: Array[GeometryInstance3D] = []
		var roots: Array = []
		var wing := false
		for m in p.modules:
			if m is WingModule and absf(p.basis.y.y) > 0.6 and absf(p.basis.x.x) > 0.8:
				wing = true
		var stack: Array[Node] = [p]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is GPUParticles3D or n is CockpitSwitch:
				continue
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			if mi and mi.material_override is ShaderMaterial and mi.material_override.has_meta("paint"):
				list.append(mi)
				var root: Variant = null
				if wing:
					# gövde ekseni (x = 0, parçanın y/z'sinde) bu ağın uzayında; ağın x'i yana bakmalı
					var xf := vessel.global_transform.affine_inverse() * mi.global_transform
					if absf(xf.basis.x.normalized().x) > 0.8:
						var rx := (xf.affine_inverse() * Vector3(0.0, p.position.y, p.position.z)).x
						var u := (xf.basis.inverse() * Vector3.UP).normalized()
						root = Vector4(u.x, u.y, u.z, rx)
				roots.append(root)
		_meshes[p] = list
		if wing:
			_roots[p] = roots
