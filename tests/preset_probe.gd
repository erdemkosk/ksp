extends Node
## --presetprobe: crafts/ içindeki her hazır uçağı kurar, parçaların görsel ağları arasındaki en
## kısa yüzey mesafesini ölçer ve gövdeye bağlı olmayan ("havada duran") parçaları listeler.
## Bağlantı: iki parçanın yüzeyleri TOL'dan yakınsa bağlı sayılır; kökten (kokpit) ulaşılamayan
## parçalar ve en yakın komşusuna boşlukları yazılır.

const TOL := 0.12          ## m: bu kadar boşluk "değiyor" sayılır
const MAX_VERTS := 160

var main: Node


func _ready() -> void:
	await get_tree().process_frame
	var dir := DirAccess.open("res://crafts")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	var only: String = str(Game.args.get("presetprobe", ""))
	for f in files:
		if only != "" and only != "true" and not f.begins_with(only):
			continue
		_probe("res://crafts/" + f)
	get_tree().quit()


func _probe(path: String) -> void:
	var craft := VesselBuilder.load_craft(path)
	var v := VesselBuilder.build(craft)
	var n := v.parts.size()
	var data: Array = []          # her parça: {aabb, verts, tris}
	for p in v.parts:
		data.append(_geometry(v, p))
	if Game.args.has("sizes"):
		for i in n:
			if not (data[i] as Dictionary).is_empty():
				var bb: AABB = data[i]["aabb"]
				print("  %s  min %s  max %s" % [v.parts[i].part_id, _fmt(bb.position / PartLibrary.WORLD_SCALE), _fmt(bb.end / PartLibrary.WORLD_SCALE)])
	# komşuluk: en kısa yüzey mesafesi
	var dist := {}
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = data[i]
			var b: Dictionary = data[j]
			if a.is_empty() or b.is_empty():
				continue
			if not (a["aabb"] as AABB).grow(TOL).intersects(b["aabb"]):
				continue
			var d := minf(_vert_to_mesh(a["verts"], b), _vert_to_mesh(b["verts"], a))
			dist[Vector2i(i, j)] = d
	# kökten erişim (ilk kokpit, yoksa ilk parça)
	var root := 0
	for i in n:
		if v.parts[i].part_id.begins_with("cockpit"):
			root = i
			break
	var seen := {root: true}
	var queue := [root]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		for k: Vector2i in dist.keys():
			if dist[k] > TOL:
				continue
			var o := -1
			if k.x == c:
				o = k.y
			elif k.y == c:
				o = k.x
			if o >= 0 and not seen.has(o):
				seen[o] = true
				queue.append(o)
	var bad := PackedStringArray()
	for i in n:
		if seen.has(i) or (data[i] as Dictionary).is_empty():
			continue
		# en yakın bağlı parça ve boşluk
		var best := INF
		var who := ""
		for j in n:
			if j == i or not seen.has(j):
				continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			var d: float = dist.get(key, INF)
			if d < best:
				best = d
				who = v.parts[j].part_id
		var p: Part = v.parts[i]
		bad.append("    HAVADA: %s @ %s  gövdeye bağlı en yakın %s, boşluk %s" % [p.part_id, _fmt(p.position / PartLibrary.WORLD_SCALE), who, ("%.2f m" % best) if best < INF else "çok uzak"])
	print("PRESET %s  parça %d  %s" % [path.get_file(), n, "TAMAM" if bad.is_empty() else "%d parça bağlı değil" % bad.size()])
	for l in bad:
		print(l)
	v.free()


func _fmt(p: Vector3) -> String:
	return "[%.2f, %.2f, %.2f]" % [p.x, p.y, p.z]


## Parçanın taşıt uzayındaki görsel üçgenleri (efekt / saydam ağlar hariç).
func _geometry(v: Vessel, p: Part) -> Dictionary:
	var verts := PackedVector3Array()
	var tris := PackedVector3Array()
	var aabb := AABB()
	var first := true
	var stack: Array[Node] = [p]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if not nd is MeshInstance3D or not nd.visible:
			continue
		var mi := nd as MeshInstance3D
		if mi.mesh == null:
			continue
		var mo := mi.material_override
		if mo is StandardMaterial3D and (mo.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mo.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
			continue
		if mo is ShaderMaterial and not mo.has_meta("paint"):
			continue
		var xf := _to_vessel(v, mi)
		var faces := mi.mesh.get_faces()
		for k in faces.size():
			var w := xf * faces[k]
			tris.append(w)
			if first:
				aabb = AABB(w, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(w)
	if first:
		return {}
	# örnek köşeler: tekrarsız, en fazla MAX_VERTS
	var uniq := {}
	for w in tris:
		uniq[Vector3i(roundi(w.x * 20.0), roundi(w.y * 20.0), roundi(w.z * 20.0))] = w
	var all: Array = uniq.values()
	var step := maxi(1, all.size() / MAX_VERTS)
	for k in range(0, all.size(), step):
		verts.append(all[k])
	return {"aabb": aabb, "verts": verts, "tris": tris}


func _to_vessel(v: Vessel, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != v:
		xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


func _vert_to_mesh(verts: PackedVector3Array, m: Dictionary) -> float:
	var tris: PackedVector3Array = m["tris"]
	var box: AABB = (m["aabb"] as AABB).grow(TOL * 2.0)
	var best := INF
	for p in verts:
		if not box.has_point(p):
			continue
		for t in range(0, tris.size(), 3):
			var a := tris[t]
			var b := tris[t + 1]
			var c := tris[t + 2]
			# hızlı eleme: üçgen kutusu
			if p.x < minf(a.x, minf(b.x, c.x)) - best or p.x > maxf(a.x, maxf(b.x, c.x)) + best:
				continue
			if p.y < minf(a.y, minf(b.y, c.y)) - best or p.y > maxf(a.y, maxf(b.y, c.y)) + best:
				continue
			if p.z < minf(a.z, minf(b.z, c.z)) - best or p.z > maxf(a.z, maxf(b.z, c.z)) + best:
				continue
			var d := p.distance_to(_closest_on_tri(p, a, b, c))
			if d < best:
				best = d
				if best < 0.01:
					return best
	return best


## Üçgen üzerindeki en yakın nokta (Ericson, Real-Time Collision Detection 5.1.5).
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)
