class_name AeroFx
extends Node3D
## Hız ve G hissi veren hava efektleri (her uçakta):
##   • kanat ucu girdapları: yüksek G ya da hücum açısında kanat uçlarından ince beyaz iz
##   • kanat üstü yoğuşma: yüksek G'de kanadın üstünde anlık buhar bulutu (nemli havada daha çok)
##   • motor izi (kontrail): 8 km üstünde motordan uzun beyaz iz
##   • buhar konisi: Mach ~0.95–1.05 arasında gövdeyi saran yoğuşma konisi
##   • ses duvarı: Mach 1 geçilince sonik patlama sesi, genişleyen şok halkası, sarsıntı
##   • lastik dumanı: hızlı iniş temasında tekerden duman

var vessel: Vessel
var _tips: Array[Dictionary] = []      # {part, local, trail}
var _vapor: Array[Dictionary] = []     # {part, particles}
var _contrails: Array[Dictionary] = [] # {engine, trail}
var _cone: MeshInstance3D
var _cone_mat: ShaderMaterial
var _grounded := {}
var _supersonic := false
var _flash := 0.0


func _ready() -> void:
	for p in vessel.parts:
		var wing: WingModule = null
		for m in p.modules:
			if m is WingModule and not m is ControlSurfaceModule:
				wing = m
		if wing and absf(p.position.x) > 0.8 and wing.area > 2.0:
			var tip := Vector3(signf(p.position.x) * p.size.x * 0.5, 0, p.size.z * 0.15)
			_tips.append({"part": p, "local": tip, "trail": _ribbon(p, tip, 0.1, 3.5, 1.6, Color(1, 1, 1, 0.6), 1.0)})
			var v := _particles(p, Vector3.ZERO, 2.0, 0.22, Color(1, 1, 1, 0.38), 180, true)
			var pm: ParticleProcessMaterial = v.process_material
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(p.size.x * 0.45, 0.15, p.size.z * 0.3)
			_vapor.append({"part": p, "particles": v})
	for e in vessel.engines():
		if not e.prop:
			var tr := _ribbon(e.part, Vector3(0, 0, e.part.size.z * 0.5 + 2.0), 0.8, 7.0, 30.0, Color(1, 1, 1, 0.5), 6.0)
			_contrails.append({"engine": e, "trail": tr})
	# buhar konisi: birim boyutlu kabuk (z 0..1, yarıçap ~1), gövdenin en kalın yerine ölçeklenir
	_cone = MeshInstance3D.new()
	_cone.mesh = MeshFactory.lathe([Vector2(0.0, 1.0), Vector2(0.06, 1.35), Vector2(0.25, 1.9), Vector2(0.55, 2.4), Vector2(1.0, 2.7)], 40)
	_cone_mat = ShaderMaterial.new()
	_cone_mat.shader = preload("res://vessel/vapor_cone.gdshader")
	_cone.material_override = _cone_mat
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone.visible = false
	vessel.add_child(_cone)
	_place_cone()


## Koni gövdenin en kalın yerinde: gövde yarıçapı ve kanat kökünün önü (yoksa ağırlık merkezi).
func _place_cone() -> void:
	var radius := 0.6
	var axis_y := 0.0
	for p in vessel.parts:
		if p.def.get("category", "") in ["kokpit", "gövde", "motor"] and absf(p.position.x) < 0.3:
			if maxf(p.size.x, p.size.y) * 0.5 > radius:
				radius = maxf(p.size.x, p.size.y) * 0.5
				axis_y = p.position.y
	var z := vessel.com_local.z
	var area := 0.0
	var zs := 0.0
	for m in vessel.modules:
		if m is WingModule and not m is ControlSurfaceModule and absf(m.part.basis.y.y) > 0.6:
			zs += (m.part.position.z - m.part.size.z * 0.35) * m.area
			area += m.area
	if area > 0.0:
		z = zs / area
	_cone_base = Vector3(0.0, axis_y, z)
	_cone_r = radius * 1.12
	_cone.position = _cone_base
	_cone.scale = Vector3(_cone_r, _cone_r, _cone_r * 4.5)


var _cone_base := Vector3.ZERO
var _cone_r := 1.0
var _sun: DirectionalLight3D


func _sun_dir() -> Vector3:
	if not is_instance_valid(_sun):
		for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (n as DirectionalLight3D).visible:
				_sun = n
				break
	return -_sun.global_basis.z if is_instance_valid(_sun) else Vector3.UP


func _particles(parent: Node3D, local: Vector3, size: float, life: float, col: Color, amount: int, burst: bool) -> GPUParticles3D:
	Effects._init_resources()
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.fixed_fps = 0
	p.local_coords = burst      # yoğuşma kanatla birlikte hareket eder
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, 1)
	m.spread = 3.0
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.5
	m.gravity = Vector3.ZERO
	m.scale_curve = Effects._grow_curve(0.6, 1.8)
	m.color_ramp = Effects._ramp([col, Color(col, col.a * 0.6), Color(col, 0.0)])
	m.angle_min = -180.0
	m.angle_max = 180.0
	p.process_material = m
	p.draw_pass_1 = Effects._quad(Effects._billboard_mat(false), size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3000, -3000, -3000), Vector3(6000, 6000, 6000))
	p.position = local
	p.emitting = false
	parent.add_child(p)
	return p


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(vessel) or not vessel.is_inside_tree():
		return
	var speed := vessel.airspeed()
	var g := absf(vessel.g_force)
	var aoa := absf(vessel.aoa_deg())
	var humid := 0.35 + 0.65 * float(Weather.current.get("wet", 0.0)) + 0.3 * float(Weather.current.get("clouds", 0.0))
	var alt := vessel.altitude()
	# kanat ucu girdapları
	var vortex := speed > 70.0 and (g > 3.2 - humid or aoa > 11.0)
	for t in _tips:
		var alive: bool = is_instance_valid(t["part"]) and t["part"] in vessel.parts
		t["trail"].emitting = vortex and alive
		t["trail"].set_level(clampf((g - 2.0) / 4.0, 0.25, 1.0) if aoa < 11.0 else 1.0)
	# kanat üstü yoğuşma
	var vapor := speed > 120.0 and speed < 420.0 and g > 6.2 - humid * 1.5
	for w in _vapor:
		if is_instance_valid(w["part"]) and w["part"] in vessel.parts:
			w["particles"].emitting = vapor
	# kontrail
	for c in _contrails:
		var e: Variant = c["engine"]
		c["trail"].emitting = is_instance_valid(e) and is_instance_valid(e.part) and e.is_running() and alt > 8000.0 and e.part in vessel.parts
	# buhar konisi
	var m := vessel.mach()
	if not _supersonic and m > 1.0:
		_supersonic = true
		_break_barrier()
	elif _supersonic and m < 0.97:
		_supersonic = false
	_flash = maxf(_flash - _delta * 2.0, 0.0)
	var k := maxf(clampf(1.0 - absf(m - 1.0) / 0.06, 0.0, 1.0) * clampf(humid, 0.6, 1.0) * (1.0 if alt < 9000.0 else 0.5), _flash)
	_cone.visible = k > 0.02
	if _cone.visible:
		_cone_mat.set_shader_parameter("intensity", k * randf_range(0.9, 1.0))
		_cone_mat.set_shader_parameter("sun_dir", _sun_dir())
		# ses hızını geçince şok geriye kayar ve koni daralıp uzar
		var past := clampf((m - 0.98) / 0.08, 0.0, 1.0)
		_cone.position = _cone_base + Vector3(0, 0, _cone_r * 1.2 * past)
		_cone.scale = Vector3(_cone_r * (1.0 - 0.15 * past), _cone_r * (1.0 - 0.15 * past), _cone_r * 4.5 * (1.0 + 0.4 * past))
	# lastik dumanı: hızlı temas anında
	for gm in vessel.modules:
		if gm is LandingGearModule:
			var was: bool = _grounded.get(gm, true)
			if gm.grounded and not was and vessel.ground_speed() > 25.0:
				Effects.dust(FloatingOrigin.world_root, gm.part.global_transform * Vector3(0, -gm.rest_length, 0), Planet.up_at(gm.part.global_position))
				Effects.dust(FloatingOrigin.world_root, gm.part.global_transform * Vector3(0, -gm.rest_length, 1.0), Planet.up_at(gm.part.global_position))
			_grounded[gm] = gm.grounded


## Ses duvarı aşıldı: sonik patlama, şok halkası, sarsıntı.
func _break_barrier() -> void:
	_flash = 1.0
	var pos := vessel.com_global()
	Sfx.sonic_boom(pos, 8.0)
	Damage.shake_camera(pos, 0.45, 600.0)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.85
	tor.outer_radius = 1.0
	tor.rings = 32
	tor.ring_segments = 8
	ring.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 1, 1, 0.55)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FloatingOrigin.world_root.add_child(ring)
	var fwd := vessel.forward()
	var x := fwd.cross(vessel.up()).normalized()
	ring.global_transform = Transform3D(Basis(x, fwd, x.cross(fwd)), pos)
	ring.scale = Vector3.ONE * 4.0
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(45, 6, 45), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(ring.queue_free)


func _ribbon(src: Node3D, local: Vector3, width: float, grow: float, life: float, col: Color, step: float) -> TrailRibbon:
	var r := TrailRibbon.new()
	r.source = src
	r.offset = local
	r.width = width
	r.grow = grow
	r.life = life
	r.color = col
	r.min_step = step
	add_child(r)
	return r
