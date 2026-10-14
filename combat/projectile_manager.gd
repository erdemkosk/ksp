class_name ProjectileManager
extends Node3D
## Tüm top mermileri. Mermiler fizik cismi değildir: dizilerde tutulur, her fizik karesinde
## yerçekimi + sürükleme ile ilerletilir ve önceki konumdan yeni konuma ışın atılarak çarpma
## bulunur. Böylece yüzlerce mermi ucuza uçar. İzli mermiler MultiMesh ile çizilir.
## Dünya kökünün çocuğu değildir (kaydırılmaz); kaydırmada konumları kendisi günceller.

const MAX := 1200
const LIFETIME := 4.0
const DRAG_K := 0.00035     ## 20 mm mermi için kaba sürükleme katsayısı (1/m)

static var instance: ProjectileManager
var _whizz_cd := 0.0

var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _dmg: PackedFloat32Array = PackedFloat32Array()
var _tracer: PackedByteArray = PackedByteArray()
var _owner: Array[Object] = []
var _mm: MultiMesh


func _ready() -> void:
	instance = self
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	FloatingOrigin.shifted.connect(func(s: Vector3) -> void:
		for i in _pos.size():
			_pos[i] -= s)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 9.0)   # hız çizgisi gibi uzun ince iz
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.35) * 4.0
	mesh.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 10000.0
	add_child(mmi)


func spawn(pos: Vector3, vel: Vector3, damage: float, tracer: bool, shooter: Object) -> void:
	if _pos.size() >= MAX:
		return
	_pos.append(pos)
	_vel.append(vel)
	_age.append(0.0)
	_dmg.append(damage)
	_tracer.append(1 if tracer else 0)
	_owner.append(shooter)


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var cam := get_viewport().get_camera_3d() as FlightCamera
	var ear := cam.global_position if cam else Vector3.INF
	var me: Object = cam.target if cam else null
	_whizz_cd -= delta
	var i := 0
	while i < _pos.size():
		var p := _pos[i]
		var v := _vel[i]
		v += Planet.gravity_at(p) * delta
		v -= v * v.length() * DRAG_K * delta
		var np := p + v * delta
		var q := PhysicsRayQueryParameters3D.create(p, np, 1 | 2 | 8)
		q.collide_with_areas = false
		var shooter := _owner[i]
		if is_instance_valid(shooter) and shooter is CollisionObject3D:
			q.exclude = [shooter.get_rid()]
		var hit := space.intersect_ray(q)
		_age[i] += delta
		# yakından geçen düşman mermisi: vızıltı
		if _whizz_cd <= 0.0 and shooter != me and ear != Vector3.INF:
			var seg := np - p
			var tt := clampf((ear - p).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
			var cp := p + seg * tt
			if cp.distance_to(ear) < 14.0:
				Sfx.play_at("bullet_whizz_%d.ogg" % (1 + randi() % 2), cp, 2.0, randf_range(0.85, 1.2), 200.0)
				_whizz_cd = 0.06
		if not hit.is_empty():
			Damage.apply_hit(hit, _dmg[i], v, shooter)
			_remove(i)
			continue
		if _age[i] > LIFETIME or Planet.altitude(np) < -5.0:
			_remove(i)
			continue
		_pos[i] = np
		_vel[i] = v
		i += 1


func _process(_delta: float) -> void:
	var n := 0
	for i in _pos.size():
		if _tracer[i] == 0 or n >= MAX:
			continue
		var v := _vel[i]
		if v.length() < 1.0:
			continue
		var b := Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
		_mm.set_instance_transform(n, Transform3D(b, _pos[i]))
		n += 1
	_mm.visible_instance_count = n


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_age[i] = _age[last]
	_dmg[i] = _dmg[last]
	_tracer[i] = _tracer[last]
	_owner[i] = _owner[last]
	_pos.resize(last)
	_vel.resize(last)
	_age.resize(last)
	_dmg.resize(last)
	_tracer.resize(last)
	_owner.resize(last)
