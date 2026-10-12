class_name MeshFactory
## Prosedürel parça modelleri: döndürme (lathe) gövdeleri ve NACA profilli kanatlar.
## Eksenler: -Z ileri. Kanatlarda X = açıklık (kök -X tarafında), Y = yukarı.


## profile: [Vector2(z, yarıçap), ...] önden arkaya. Aynı noktayı iki kez yazmak sert kenar yapar.
## y_scale < 1 basık (oval) kesit verir. arc_from/arc_to (derece, 90 = üst) ile kısmi
## gövde yapılır (ör. üstü açık kokpit: 132 → 408).
static func lathe(profile: Array, segments := 32, y_scale := 1.0, arc_from := 0.0, arc_to := 360.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := profile.size()
	for i in rings:
		var p: Vector2 = profile[i]
		var prev: Vector2 = profile[maxi(i - 1, 0)]
		var next: Vector2 = profile[mini(i + 1, rings - 1)]
		var tangent := next - prev
		if next.is_equal_approx(p) and i > 0:
			tangent = p - prev      # sert kenarın ilk noktası: geriye bak
		elif prev.is_equal_approx(p) and i < rings - 1:
			tangent = next - p      # sert kenarın ikinci noktası: ileriye bak
		# 2B normal: (z bileşeni, radyal bileşen)
		var n2 := Vector2(-tangent.y, tangent.x).normalized()
		for s in segments + 1:
			var a := deg_to_rad(lerpf(arc_from, arc_to, float(s) / segments))
			var c := cos(a)
			var sn := sin(a)
			verts.append(Vector3(c * p.y, sn * p.y * y_scale, p.x))
			normals.append(Vector3(c * n2.y * y_scale, sn * n2.y, n2.x).normalized())
			uvs.append(Vector2(float(s) / segments, float(i) / maxf(rings - 1, 1)))
	var w := segments + 1
	for i in rings - 1:
		for s in segments:
			var a := i * w + s
			indices.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	return _mesh(verts, normals, uvs, indices)


## Sivrilen, ok açılı kanat. thickness = kalınlık/veter oranı.
static func wing(span: float, root_chord: float, tip_chord: float, sweep: float, thickness: float) -> ArrayMesh:
	var pts := 12
	var ring: Array[Vector2] = []
	for k in range(pts, -1, -1):   # üst yüzey: firar kenarı → hücum kenarı
		var x := (1.0 - cos(PI * k / pts)) * 0.5
		ring.append(Vector2(x, _naca(x, thickness)))
	for k in range(1, pts + 1):     # alt yüzey: hücum → firar
		var x := (1.0 - cos(PI * k / pts)) * 0.5
		ring.append(Vector2(x, -_naca(x, thickness)))

	var ring_normals: Array[Vector2] = []
	for k in ring.size():
		var t := ring[mini(k + 1, ring.size() - 1)] - ring[maxi(k - 1, 0)]
		ring_normals.append(Vector2(t.y, -t.x).normalized())

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var sections := []
	for side in 2:
		var t := float(side)
		var chord := lerpf(root_chord, tip_chord, t)
		var le := -root_chord * 0.5 + sweep * t
		var x := lerpf(-span * 0.5, span * 0.5, t)
		var sec := []
		for k in ring.size():
			sec.append(Vector3(x, ring[k].y * chord, le + ring[k].x * chord))
		sections.append(sec)
		for k in ring.size():
			verts.append(sec[k])
			normals.append(Vector3(0, ring_normals[k].y, ring_normals[k].x))
			uvs.append(Vector2(ring[k].x, t))
	var n := ring.size()
	for k in n - 1:
		indices.append_array([k, k + 1, n + k, k + 1, n + k + 1, n + k])
	# Kök ve uç kapakları
	for side in 2:
		var base := verts.size()
		var sec: Array = sections[side]
		var center := Vector3.ZERO
		for v in sec:
			center += v
		center /= sec.size()
		var nrm := Vector3(-1 if side == 0 else 1, 0, 0)
		verts.append(center)
		normals.append(nrm)
		uvs.append(Vector2(0.5, side))
		for v in sec:
			verts.append(v)
			normals.append(nrm)
			uvs.append(Vector2(0.5, side))
		for k in sec.size() - 1:
			indices.append_array([base, base + 1 + k, base + 2 + k])
	return _mesh(verts, normals, uvs, indices)


## Çok panelli kanat (kırık delta, uçan kanat): secs = [Vector3(x, hücum kenarı z, veter), ...]
## kökten uca. Her bölüm NACA kesiti; bölümler arası yüzey, kök ve uç kapakları.
static func wing_sections(secs: Array, thickness: float) -> ArrayMesh:
	var pts := 12
	var ring: Array[Vector2] = []
	for k in range(pts, -1, -1):
		var x := (1.0 - cos(PI * k / pts)) * 0.5
		ring.append(Vector2(x, _naca(x, thickness)))
	for k in range(1, pts + 1):
		var x := (1.0 - cos(PI * k / pts)) * 0.5
		ring.append(Vector2(x, -_naca(x, thickness)))
	var ring_normals: Array[Vector2] = []
	for k in ring.size():
		var t := ring[mini(k + 1, ring.size() - 1)] - ring[maxi(k - 1, 0)]
		ring_normals.append(Vector2(t.y, -t.x).normalized())
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var n := ring.size()
	var rings_pos: Array = []
	for si in secs.size():
		var s: Vector3 = secs[si]
		var sec := []
		for k in n:
			var v := Vector3(s.x, ring[k].y * s.z, s.y + ring[k].x * s.z)
			sec.append(v)
			verts.append(v)
			normals.append(Vector3(0, ring_normals[k].y, ring_normals[k].x))
			uvs.append(Vector2(ring[k].x, float(si) / maxf(secs.size() - 1, 1)))
		rings_pos.append(sec)
	for si in secs.size() - 1:
		var a := si * n
		var b := (si + 1) * n
		for k in n - 1:
			indices.append_array([a + k, a + k + 1, b + k, a + k + 1, b + k + 1, b + k])
	for end in [0, secs.size() - 1]:
		var sec: Array = rings_pos[end]
		var base := verts.size()
		var center := Vector3.ZERO
		for v in sec:
			center += v
		center /= sec.size()
		var nrm := Vector3(-1 if end == 0 else 1, 0, 0)
		verts.append(center)
		normals.append(nrm)
		uvs.append(Vector2(0.5, 0.5))
		for v in sec:
			verts.append(v)
			normals.append(nrm)
			uvs.append(Vector2(0.5, 0.5))
		for k in sec.size() - 1:
			indices.append_array([base, base + 1 + k, base + 2 + k])
	return _mesh(verts, normals, uvs, indices)


static func _naca(x: float, t: float) -> float:
	return 5.0 * t * (0.2969 * sqrt(x) - 0.1260 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
