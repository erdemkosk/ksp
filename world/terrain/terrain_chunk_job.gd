class_name TerrainChunkJob
extends RefCounted
## Küp-küre üzerindeki bir arazi parçasını (chunk) iş parçacığında üretir:
## kara mesh'i, deniz yüzeyi mesh'i ve (yakın parçalarda) ağaç/ev konumları.
##
## Hassasiyet: 600 km yarıçapta 32-bit float ~6 cm hata verir. Bu yüzden yön ve konum
## hesapları GDScript float'larıyla (64-bit) bileşen bileşen yapılır; mesh köşeleri
## parçanın merkezine göre küçük sayılar olarak saklanır.

const RES := 32
const PROP_LEVEL := 16          ## ağaç aday ızgarası bu seviyenin hücreleri (~14 m)
const MIN_PROP_LEVEL := 11      ## bundan kaba parçalarda obje yok
const SEA_LEVEL := 0.0

# Girdi
var face_normal := Vector3.UP
var face_u := Vector3.RIGHT
var face_v := Vector3.BACK
var level := 0
var ix := 0
var iy := 0

# Çıktı
var origin := PackedFloat64Array([0, 0, 0])   ## parça merkezinin gezegene göre konumu
var land_arrays := []
var ocean_arrays := []
var conifers: Array[Transform3D] = []
var broadleaves: Array[Transform3D] = []
var houses: Array[Transform3D] = []


static func warp(t: float) -> float:
	return tan(t * PI * 0.25)


## Küp yüzü parametresinden (u, v ∈ [-1, 1]) birim yön (64-bit bileşenler).
func dir_at(u: float, v: float) -> PackedFloat64Array:
	var wu := warp(u)
	var wv := warp(v)
	var x := face_normal.x + face_u.x * wu + face_v.x * wv
	var y := face_normal.y + face_u.y * wu + face_v.y * wv
	var z := face_normal.z + face_u.z * wu + face_v.z * wv
	var l := sqrt(x * x + y * y + z * z)
	return PackedFloat64Array([x / l, y / l, z / l])


func run() -> void:
	var cells := 1 << level
	var du := 2.0 / cells
	var u0 := -1.0 + ix * du
	var v0 := -1.0 + iy * du
	var step := du / RES
	var R := TerrainGen.RADIUS

	var dc := dir_at(u0 + du * 0.5, v0 + du * 0.5)
	origin = PackedFloat64Array([dc[0] * R, dc[1] * R, dc[2] * R])

	# (RES+3)^2 örnek: kenarda bir halka fazlası normaller için
	var n := RES + 3
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var pz := PackedFloat64Array()
	var hs := PackedFloat32Array()
	var dirs := PackedVector3Array()
	px.resize(n * n)
	py.resize(n * n)
	pz.resize(n * n)
	hs.resize(n * n)
	dirs.resize(n * n)
	for j in n:
		for i in n:
			var d := dir_at(u0 + (i - 1) * step, v0 + (j - 1) * step)
			var dv := Vector3(d[0], d[1], d[2])
			var h := TerrainGen.height(dv)
			var k := j * n + i
			var r := R + h
			px[k] = d[0] * r - origin[0]
			py[k] = d[1] * r - origin[1]
			pz[k] = d[2] * r - origin[2]
			hs[k] = h
			dirs[k] = dv

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var any_sea := false
	for j in RES + 1:
		for i in RES + 1:
			var k := (j + 1) * n + (i + 1)
			verts.append(Vector3(px[k], py[k], pz[k]))
			var tu := Vector3(px[k + 1] - px[k - 1], py[k + 1] - py[k - 1], pz[k + 1] - pz[k - 1])
			var tv := Vector3(px[k + n] - px[k - n], py[k + n] - py[k - n], pz[k + n] - pz[k - n])
			var nrm := tu.cross(tv).normalized()
			if nrm.dot(dirs[k]) < 0.0:
				nrm = -nrm
			normals.append(nrm)
			colors.append(Color(TerrainGen.forest(dirs[k]), 0.0, 0.0))
			uv2.append(Vector2(hs[k], 1.0 - nrm.dot(dirs[k])))
			if hs[k] < 1.0:
				any_sea = true

	var w := RES + 1
	var indices := PackedInt32Array()
	for j in RES:
		for i in RES:
			var a := j * w + i
			indices.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])

	# Etek (skirt): LOD sınırlarındaki çatlakları gizler; merkeze doğru iner
	var cell_m := du * R * 0.8 / RES
	var skirt := cell_m * 1.5 + 5.0
	var edges := [[], [], [], []]
	for k in w:
		edges[0].append(k)
		edges[1].append(RES * w + k)
		edges[2].append(k * w)
		edges[3].append(k * w + RES)
	for edge in edges:
		var base := verts.size()
		for idx in edge:
			var gk: int = (int(idx / w) + 1) * n + (idx % w) + 1
			verts.append(verts[idx] - dirs[gk] * skirt)
			normals.append(normals[idx])
			colors.append(colors[idx])
			uv2.append(uv2[idx])
		for k in edge.size() - 1:
			var v0i: int = edge[k]
			var v1i: int = edge[k + 1]
			indices.append_array([v0i, v1i, base + k, v1i, base + k + 1, base + k])

	land_arrays.resize(Mesh.ARRAY_MAX)
	land_arrays[Mesh.ARRAY_VERTEX] = verts
	land_arrays[Mesh.ARRAY_NORMAL] = normals
	land_arrays[Mesh.ARRAY_COLOR] = colors
	land_arrays[Mesh.ARRAY_TEX_UV2] = uv2
	land_arrays[Mesh.ARRAY_INDEX] = indices

	if any_sea:
		_build_ocean(n, hs, dirs, R)
	if level >= MIN_PROP_LEVEL:
		_place_props(u0, v0, du, R)


## Deniz yüzeyi: en az bir köşesi deniz seviyesinin altında kalan karelerde küre parçası.
func _build_ocean(n: int, hs: PackedFloat32Array, dirs: PackedVector3Array, R: float) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var depth := PackedVector2Array()   # x = deniz tabanı yüksekliği (negatif = derinlik)
	var w := RES + 1
	for j in w:
		for i in w:
			var k := (j + 1) * n + (i + 1)
			var d := dirs[k]
			verts.append(Vector3(d.x * R - origin[0], d.y * R - origin[1], d.z * R - origin[2]))
			normals.append(d)
			depth.append(Vector2(hs[k], 0.0))
	var indices := PackedInt32Array()
	for j in RES:
		for i in RES:
			var k := (j + 1) * n + (i + 1)
			if minf(minf(hs[k], hs[k + 1]), minf(hs[k + n], hs[k + n + 1])) > 2.0:
				continue
			var a := j * w + i
			indices.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	if indices.is_empty():
		return
	ocean_arrays.resize(Mesh.ARRAY_MAX)
	ocean_arrays[Mesh.ARRAY_VERTEX] = verts
	ocean_arrays[Mesh.ARRAY_NORMAL] = normals
	ocean_arrays[Mesh.ARRAY_TEX_UV2] = depth
	ocean_arrays[Mesh.ARRAY_INDEX] = indices


## Konumlar küresel ızgaraya bağlı ve deterministik: LOD değişince ağaçlar zıplamaz.
func _place_props(u0: float, v0: float, du: float, R: float) -> void:
	var sub := 1 << (PROP_LEVEL - level)
	var gstep := du / sub
	var gx0 := ix * sub
	var gy0 := iy * sub
	var face_id := int(face_normal.x * 3 + face_normal.y * 5 + face_normal.z * 7)
	for j in sub:
		for i in sub:
			var gi := gx0 + i
			var gj := gy0 + j
			var r := _rand(face_id, gi, gj, 1)
			var d64 := dir_at(u0 + (i + _rand(face_id, gi, gj, 2)) * gstep, v0 + (j + _rand(face_id, gi, gj, 3)) * gstep)
			var d := Vector3(d64[0], d64[1], d64[2])
			if TerrainGen.in_airfield(d, 150.0):
				continue
			var f := TerrainGen.forest(d)
			var vil := TerrainGen.village(d)
			var want_house := vil > 0.0 and r < vil * 0.3
			var want_tree := r < f * 0.85
			if not want_house and not want_tree:
				continue
			var h := TerrainGen.height(d)
			if h < 2.5 or h > TerrainGen.TREE_LINE:
				continue
			# eğim: teğet yönde 4 m ötedeki yükseklik farkı
			var t := face_u - d * face_u.dot(d)
			var d2 := (d * R + t.normalized() * 4.0).normalized()
			var slope := absf(TerrainGen.height(d2) - h) / 4.0
			var pos := Vector3(d64[0] * (R + h) - origin[0], d64[1] * (R + h) - origin[1], d64[2] * (R + h) - origin[2])
			var yaw := _rand(face_id, gi, gj, 4) * TAU
			var up_basis := _up_basis(d).rotated(d, yaw)
			if want_house and slope < 0.15:
				var s := Vector3(lerpf(7, 13, _rand(face_id, gi, gj, 5)), lerpf(4, 7, _rand(face_id, gi, gj, 6)), lerpf(7, 12, _rand(face_id, gi, gj, 7)))
				houses.append(Transform3D(up_basis * Basis().scaled(s), pos - d * 0.3))
			elif want_tree and slope < 0.6:
				var sc := lerpf(0.7, 1.5, _rand(face_id, gi, gj, 8))
				var tr := Transform3D(up_basis.scaled_local(Vector3(sc, sc, sc)), pos - d * 0.4)
				if h > 450.0 or _rand(face_id, gi, gj, 9) < 0.55:
					conifers.append(tr)
				else:
					broadleaves.append(tr)


static func _up_basis(up: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	return Basis(x, up, x.cross(up).normalized())


static func _rand(f: int, i: int, j: int, k: int) -> float:
	return float(hash(Vector4i(f, i, j, k)) & 0xFFFFFF) / float(0xFFFFFF)
