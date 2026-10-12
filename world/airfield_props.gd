class_name AirfieldProps
## Havaalanı küçük detayları: rüzgar tulumu (rüzgarın estiği yöne döner, şiddetiyle dikleşir),
## kule tepesinde dönen yeşil/beyaz havaalanı feneri, pistte iniş lastik izleri.


## Kırmızı-beyaz rüzgar tulumu.
class Windsock extends Node3D:
	var _sock: Node3D
	var _t := 0.0

	func _ready() -> void:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.09
		cyl.height = 7.0
		pole.mesh = cyl
		pole.position = Vector3(0, 3.5, 0)
		pole.material_override = SamSite._mat(Color(0.85, 0.85, 0.85))
		add_child(pole)
		_sock = Node3D.new()
		_sock.position = Vector3(0, 6.8, 0)
		add_child(_sock)
		for i in 5:
			var seg := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.42 - i * 0.05
			c.bottom_radius = 0.37 - i * 0.05
			c.height = 0.7
			c.cap_top = false
			c.cap_bottom = false
			seg.mesh = c
			seg.rotation_degrees = Vector3(90, 0, 0)
			seg.position = Vector3(0, 0, 0.35 + i * 0.7)
			var m := SamSite._mat(Color(0.95, 0.35, 0.1) if i % 2 == 0 else Color(0.95, 0.95, 0.92))
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			seg.material_override = m
			_sock.add_child(seg)

	func _process(delta: float) -> void:
		_t += delta
		var w := Weather.wind_at(global_position)
		var local := global_basis.inverse() * w
		var speed := Vector2(local.x, local.z).length()
		var yaw := atan2(local.x, local.z) if speed > 0.3 else _sock.rotation.y
		# rüzgar yokken sarkık (aşağı), 8 m/s üstünde yatay; hafif çırpınma
		var droop := lerpf(1.3, 0.05, clampf(speed / 8.0, 0.0, 1.0)) + sin(_t * 7.0) * 0.04 * clampf(speed / 5.0, 0.0, 1.0)
		_sock.rotation = Vector3(droop, lerp_angle(_sock.rotation.y, yaw, 1.0 - exp(-2.0 * delta)), 0)


## Kule tepesinde dönen fener: yeşil ve beyaz ışık sırayla görünür.
class Beacon extends Node3D:
	var _rot: Node3D
	var _lights: Array[MeshInstance3D] = []

	func _ready() -> void:
		_rot = Node3D.new()
		add_child(_rot)
		for i in 2:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.012, 0.012)
			q.material = RunwayLights.light_material(Color(0.3, 1.0, 0.45) if i == 0 else Color(1.0, 1.0, 0.95), 0.012)
			mi.mesh = q
			mi.position = Vector3(0.5 if i == 0 else -0.5, 0, 0)
			_rot.add_child(mi)
			_lights.append(mi)

	func _process(delta: float) -> void:
		_rot.rotate_y(delta * TAU / 4.0)
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		# ışık kameraya bakan yüzdeyken parlar (dönen projektör)
		for mi in _lights:
			var outward := (mi.global_position - global_position).normalized()
			var to_cam := (cam.global_position - global_position).normalized()
			mi.visible = outward.dot(to_cam) > 0.6


## Pistte lastik izleri (her iniş bir çift koyu iz bırakır).
class SkidMarks extends MultiMeshInstance3D:
	static var instance: SkidMarks
	const MAX := 240
	var _n := 0

	func _ready() -> void:
		instance = self
		var q := QuadMesh.new()
		q.size = Vector2(0.32, 9.0)
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		q.orientation = PlaneMesh.FACE_Y
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.03, 0.03, 0.03, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = m
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = q
		multimesh.instance_count = MAX
		multimesh.visible_instance_count = 0
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		extra_cull_margin = 5000.0

	func _exit_tree() -> void:
		if instance == self:
			instance = null

	## Dünya konumu ve gidiş yönü: iz tekerin arkasına uzanır.
	static func add(pos: Vector3, dir: Vector3) -> void:
		if instance == null:
			return
		var up := Planet.up_at(pos)
		var f := (dir - up * dir.dot(up)).normalized()
		var x := f.cross(up).normalized()
		var p := pos - f * 4.5 + up * 0.08
		var xf := instance.global_transform.affine_inverse() * Transform3D(Basis(x, up, -f), p)
		var i := instance._n % MAX
		instance.multimesh.set_instance_transform(i, xf)
		instance._n += 1
		instance.multimesh.visible_instance_count = mini(instance._n, MAX)
