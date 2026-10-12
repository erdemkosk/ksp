class_name TerrainProps
## Ağaç ve ev modelleri (MultiMesh ile çok sayıda çizilir). Gece ev pencereleri yanar.

static var _wall_mat: ShaderMaterial


static func conifer() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 3.0 - k * 0.75
		cone.height = 5.0 - k * 0.6
		cone.radial_segments = 7
		cone.rings = 0
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 4.2 + k * 2.4, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.11, 0.22, 0.12)))
	_add_trunk(mesh, 2.2)
	return mesh


static func broadleaf() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs := [[Vector3(0, 5.5, 0), 3.0], [Vector3(1.4, 4.6, 0.6), 2.2], [Vector3(-1.2, 4.8, -0.8), 2.3]]
	for b in blobs:
		var s := SphereMesh.new()
		s.radius = b[1]
		s.height = b[1] * 1.7
		s.radial_segments = 8
		s.rings = 4
		st.append_from(s, 0, Transform3D(Basis(), b[0]))
	st.commit(mesh)
	mesh.surface_set_material(0, _mat(Color(0.2, 0.32, 0.12)))
	_add_trunk(mesh, 3.5)
	return mesh


## 1x1x1 birim ev; örnek dönüşümü boyutlandırır.
static func house() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := BoxMesh.new()
	st.append_from(walls, 0, Transform3D(Basis(), Vector3(0, 0.5, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, _house_wall_material())
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := PrismMesh.new()
	roof.size = Vector3(1.12, 0.45, 1.08)
	st2.append_from(roof, 0, Transform3D(Basis(), Vector3(0, 1.225, 0)))
	st2.commit(mesh)
	mesh.surface_set_material(1, _mat(Color(0.62, 0.24, 0.16)))
	return mesh


static func _add_trunk(mesh: ArrayMesh, h: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = h
	trunk.radial_segments = 5
	trunk.rings = 0
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _mat(Color(0.3, 0.22, 0.15)))


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


## Gece pencereleri yanan ev duvarı.
static func _house_wall_material() -> ShaderMaterial:
	if _wall_mat == null:
		_wall_mat = ShaderMaterial.new()
		_wall_mat.shader = preload("res://world/terrain/house_wall.gdshader")
	return _wall_mat


## 0 gündüz, 1 gece (SkyController çağırır).
static func set_night(n: float) -> void:
	if _wall_mat:
		_wall_mat.set_shader_parameter("night", n)
