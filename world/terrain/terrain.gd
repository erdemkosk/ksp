class_name Terrain
extends Node3D
## Küp-küre quadtree LOD gezegen arazisi. 6 küp yüzü; her biri kameraya yakınlığa göre
## bölünür. En kaba seviyede bile tüm gezegen çizilir (uzaydan bakınca küre görünür).
## Parçalar iş parçacıklarında üretilir; yeni set hazır olana kadar eskiler ekranda kalır.
##
## Bu düğüm floating origin tarafından kaydırılmaz; parçalar kaydırma olunca gezegen
## merkezinin 64-bit konumundan yeniden yerleştirilir (600 km'de bile cm hassasiyet).

const FACES := [
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]
const MAX_LEVEL := 12          ## ~230 m parça, ~7 m köşe aralığı
const SPLIT_FACTOR := 2.3
const MAX_JOBS := 8
const UPDATE_INTERVAL := 0.2
const TEXTURE_PERIOD := 8192.0

var collision: TerrainCollision
var material: ShaderMaterial
var ocean_material: ShaderMaterial

var _chunks := {}     # Vector4i(face, x, y, level) -> Node3D
var _jobs := {}       # Vector4i -> [job, task_id]
var _queue: Array[Vector4i] = []
var _desired := {}
var _timer := 0.0
var _conifer: ArrayMesh
var _broadleaf: ArrayMesh
var _house: ArrayMesh


func _ready() -> void:
	add_to_group("origin_fixed")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	TerrainGen.init()
	_conifer = TerrainProps.conifer()
	_broadleaf = TerrainProps.broadleaf()
	_house = TerrainProps.house()

	material = ShaderMaterial.new()
	material.shader = preload("res://world/terrain/terrain.gdshader")
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	tex.noise = noise
	material.set_shader_parameter("noise_tex", tex)

	ocean_material = ShaderMaterial.new()
	ocean_material.shader = preload("res://world/water.gdshader")
	ocean_material.set_shader_parameter("wave_tex", _wave_tex(3, 0.02))

	collision = TerrainCollision.new()
	collision.name = "Collision"
	add_child(collision)
	FloatingOrigin.shifted.connect(func(_s: Vector3) -> void: _reposition_all())


func _exit_tree() -> void:
	for key in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[key][1])
	_jobs.clear()


## Başlangıçta kamera etrafını beklemeden doldurur.
func generate_now() -> void:
	_update_desired()
	while not _queue.is_empty() or not _jobs.is_empty():
		_start_jobs()
		for key: Vector4i in _jobs.keys():
			WorkerThreadPool.wait_for_task_completion(_jobs[key][1])
			_chunks[key] = _build_chunk(_jobs[key][0])
		_jobs.clear()
	_try_swap()


func _process(delta: float) -> void:
	_collect_finished()
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_INTERVAL
		_update_desired()
	_start_jobs()
	_try_swap()
	var c := Planet.center()
	for m in [material, ocean_material]:
		m.set_shader_parameter("planet_center", c)
		m.set_shader_parameter("planet_axis", Planet.axis)


func _camera_rel() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return Planet.relative(cam.global_position) if cam else Vector3(0, Planet.RADIUS + 100.0, 0)


static func face_dir(face: int, u: float, v: float) -> Vector3:
	var f: Array = FACES[face]
	return (f[0] + f[1] * TerrainChunkJob.warp(u) + f[2] * TerrainChunkJob.warp(v)).normalized()


func _update_desired() -> void:
	var cam := _camera_rel()
	var desired := {}
	for face in 6:
		_subdivide(face, 0, 0, 0, cam, desired)
	_desired = desired
	_queue.clear()
	for key: Vector4i in desired:
		if not _chunks.has(key) and not _jobs.has(key):
			_queue.append(key)
	# yakın (ince) parçalar önce
	_queue.sort_custom(func(a: Vector4i, b: Vector4i) -> bool: return a.w > b.w)


func _subdivide(face: int, x: int, y: int, level: int, cam: Vector3, out: Dictionary) -> void:
	var cells := 1 << level
	var du := 2.0 / cells
	var dc := face_dir(face, -1.0 + (x + 0.5) * du, -1.0 + (y + 0.5) * du)
	var size_m := PI * 0.5 * Planet.RADIUS / cells
	var dist := maxf((cam - dc * Planet.RADIUS).length() - size_m * 0.75, 0.0)
	if level < MAX_LEVEL and dist < size_m * SPLIT_FACTOR:
		for k in 4:
			_subdivide(face, x * 2 + (k & 1), y * 2 + (k >> 1), level + 1, cam, out)
	else:
		out[Vector4i(face, x, y, level)] = true


func _start_jobs() -> void:
	while _jobs.size() < MAX_JOBS and not _queue.is_empty():
		var key: Vector4i = _queue.pop_front()
		if _chunks.has(key) or _jobs.has(key):
			continue
		var job := TerrainChunkJob.new()
		var f: Array = FACES[key.x]
		job.face_normal = f[0]
		job.face_u = f[1]
		job.face_v = f[2]
		job.ix = key.y
		job.iy = key.z
		job.level = key.w
		_jobs[key] = [job, WorkerThreadPool.add_task(job.run)]


func _collect_finished() -> void:
	for key: Vector4i in _jobs.keys():
		var task: int = _jobs[key][1]
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_chunks[key] = _build_chunk(_jobs[key][0])
			_jobs.erase(key)


## Artık istenmeyen bir parçayı, onun alanını kaplayan yeni parçalar hazır olunca siler.
func _try_swap() -> void:
	var missing: Array[Vector4i] = []
	for key: Vector4i in _desired:
		if not _chunks.has(key):
			missing.append(key)
	for key: Vector4i in _chunks.keys():
		if _desired.has(key):
			continue
		var blocked := false
		for m in missing:
			if _overlaps(key, m):
				blocked = true
				break
		if not blocked:
			_chunks[key].queue_free()
			_chunks.erase(key)


func _overlaps(a: Vector4i, b: Vector4i) -> bool:
	if a.x != b.x:
		return false
	var sa := 1 << (MAX_LEVEL - a.w)
	var sb := 1 << (MAX_LEVEL - b.w)
	var ax := a.y * sa
	var ay := a.z * sa
	var bx := b.y * sb
	var by := b.z * sb
	return ax < bx + sb and bx < ax + sa and ay < by + sb and by < ay + sa


func _reposition_all() -> void:
	for key in _chunks:
		_place(_chunks[key])
	collision.reposition()


func _place(root: Node3D) -> void:
	var o: PackedFloat64Array = root.get_meta("origin")
	var c := Planet.center()
	root.position = Vector3(o[0] + c.x, o[1] + c.y, o[2] + c.z)


func _build_chunk(job: TerrainChunkJob) -> Node3D:
	var root := Node3D.new()
	root.set_meta("origin", job.origin)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.land_arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	root.add_child(mi)
	if not job.ocean_arrays.is_empty():
		var om := ArrayMesh.new()
		om.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.ocean_arrays)
		var omi := MeshInstance3D.new()
		omi.mesh = om
		omi.material_override = ocean_material
		omi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(omi)
	_add_multimesh(root, _conifer, job.conifers)
	_add_multimesh(root, _broadleaf, job.broadleaves)
	_add_multimesh(root, _house, job.houses)
	add_child(root)
	_place(root)
	return root


func _add_multimesh(root: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 4500.0
	root.add_child(mmi)


static func _wave_tex(seed: int, freq: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = freq
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	return tex
