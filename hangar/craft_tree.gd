class_name CraftTree
## Uçak tasarımının parça ağacı (KSP gibi): her kayıt bir "uid" ve takıldığı parçanın uid'si
## "parent" taşır (kökte parent = -1). Bir parçayı tutunca / silince / kopyalayınca ona takılı
## her şey (alt ağaç) de gelir. Eski kayıtlarda ağaç parçaların temasından çıkarılır.
##
## Simetri: bir kayıt "mirror" (YZ düzlemine ayna) ya da "radial" + "axis" (Z eksenli dönme
## simetrisi) ile birden çok parça oluşturur (VesselBuilder.entry_copies). Grup taşınırken bu
## kopyalar tutarlı kalsın diye transform_group kuralları uygular.


## Eksik uid'leri ver, parent'ı olmayan kayıtları temas grafiğinden bağla (kök = ilk kokpit,
## yoksa ilk kayıt). preview: craft'tan kurulmuş uçak; part_entry: Part -> kayıt indeksi.
static func ensure(craft: Dictionary, preview: Vessel, part_entry: Dictionary) -> void:
	var parts: Array = craft.get("parts", [])
	if parts.is_empty():
		return
	var next := next_uid(craft)
	for e: Dictionary in parts:
		if not e.has("uid"):
			e["uid"] = next
			next += 1
	var missing: Array[int] = []
	var has_root := false
	for i in parts.size():
		var e: Dictionary = parts[i]
		if not e.has("parent"):
			missing.append(i)
		elif int(e["parent"]) < 0:
			has_root = true
	if missing.is_empty():
		return
	# her kaydın parçaları
	var by_entry := {}
	for p in part_entry:
		var i: int = part_entry[p]
		if not by_entry.has(i):
			by_entry[i] = []
		by_entry[i].append(p)
	var in_tree := {}
	for i in parts.size():
		if not i in missing:
			in_tree[i] = true
	if not has_root:
		var root := missing[0]
		for i in missing:
			if String(PartLibrary.get_def(String(parts[i]["part"])).get("category", "")) == "kokpit":
				root = i
				break
		parts[root]["parent"] = -1
		in_tree[root] = true
		missing.erase(root)
	# dalga dalga: ağaca değen kayıtlar en yakın ağaç kaydına bağlanır
	var progress := true
	while progress and not missing.is_empty():
		progress = false
		var attach := {}
		for i in missing:
			var best := -1
			var best_d := INF
			for j in in_tree:
				var d := _touch_distance(by_entry.get(i, []), by_entry.get(j, []))
				if d < best_d:
					best_d = d
					best = j
			if best >= 0 and best_d < INF:
				attach[i] = best
		for i in attach:
			parts[i]["parent"] = int(parts[attach[i]]["uid"])
			in_tree[i] = true
			missing.erase(i)
			progress = true
	# hiçbir şeye değmeyenler: en yakın ağaç kaydına
	for i in missing:
		var best := -1
		var best_d := INF
		for j in in_tree:
			var d := _center_distance(by_entry.get(i, []), by_entry.get(j, []))
			if d < best_d:
				best_d = d
				best = j
		parts[i]["parent"] = int(parts[best]["uid"]) if best >= 0 else -1
		in_tree[i] = true


## İki kaydın parçaları birbirine değiyorsa merkezleri arası en kısa mesafe, yoksa INF.
static func _touch_distance(a: Array, b: Array) -> float:
	var best := INF
	for p: Part in a:
		var ba := p.local_aabb(0.12)
		for q: Part in b:
			if ba.intersects(q.local_aabb(0.12)):
				best = minf(best, p.position.distance_to(q.position))
	return best


static func _center_distance(a: Array, b: Array) -> float:
	var best := INF
	for p: Part in a:
		for q: Part in b:
			best = minf(best, p.position.distance_to(q.position))
	return best


static func next_uid(craft: Dictionary) -> int:
	var m := 0
	for e: Dictionary in craft.get("parts", []):
		m = maxi(m, int(e.get("uid", 0)))
	return m + 1


static func index_of(craft: Dictionary, uid: int) -> int:
	var parts: Array = craft.get("parts", [])
	for i in parts.size():
		if int(parts[i].get("uid", -999)) == uid:
			return i
	return -1


## Kaydın kendisi ve ona takılı her şey (önce ebeveynler — genişlik öncelikli sıra).
static func subtree(craft: Dictionary, idx: int) -> Array[int]:
	var parts: Array = craft.get("parts", [])
	var out: Array[int] = [idx]
	var k := 0
	while k < out.size():
		var uid := int(parts[out[k]].get("uid", -999))
		for i in parts.size():
			if not i in out and int(parts[i].get("parent", -2)) == uid:
				out.append(i)
		k += 1
	return out


## Kayıtları sil (büyükten küçüğe), silinenlerin kopyalarını döndür (aynı sırada).
static func take(craft: Dictionary, indices: Array[int]) -> Array:
	var parts: Array = craft["parts"]
	var taken: Array = []
	for i in indices:
		taken.append((parts[i] as Dictionary).duplicate(true))
	var sorted := indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		parts.remove_at(i)
	return taken


## Gruba yeni uid'ler ver (kopyalama): iç parent bağları korunur, kökün parent'ı sonra yazılır.
static func renumber(craft: Dictionary, group: Array) -> void:
	var next := next_uid(craft)
	var map := {}
	for e: Dictionary in group:
		map[int(e.get("uid", -1))] = next
		e["uid"] = next
		next += 1
	for e: Dictionary in group:
		var p := int(e.get("parent", -1))
		if map.has(p):
			e["parent"] = map[p]


## Kök değiştir: idx'ten eski köke giden yoldaki parent bağları ters çevrilir.
static func reroot(craft: Dictionary, idx: int) -> void:
	var parts: Array = craft["parts"]
	var path: Array[int] = []
	var cur := idx
	var guard := 0
	while cur >= 0 and guard < parts.size() + 1:
		path.append(cur)
		cur = index_of(craft, int(parts[cur].get("parent", -1)))
		guard += 1
	var prev_uid := -1
	for i in path:
		var uid := int(parts[i]["uid"])
		parts[i]["parent"] = prev_uid
		prev_uid = uid


## Kaydın simetrisi: {} yok, {"mirror": true}, {"radial": n, "axis": [x, y]}.
static func sym_of(e: Dictionary) -> Dictionary:
	if e.get("mirror", false):
		return {"mirror": true}
	if int(e.get("radial", 1)) > 1:
		return {"radial": int(e["radial"]), "axis": e.get("axis", [0, 0])}
	return {}


static func set_sym(e: Dictionary, sym: Dictionary) -> void:
	e.erase("mirror")
	e.erase("radial")
	e.erase("axis")
	for k in sym:
		e[k] = sym[k]


static func _transform(e: Dictionary, d: Transform3D) -> void:
	VesselBuilder.set_entry_xform(e, d * VesselBuilder.entry_xform(e))


## D, YZ düzlemine aynayı bozmuyor mu (aynayla değişmeli: X'te kayma yok, yalnız X çevresinde
## dönüş — eksen boyunca kaydırma ya da burun yukarı/aşağı döndürme)?
static func keeps_mirror(d: Transform3D) -> bool:
	var m := VesselBuilder.MIRROR
	return (m * d * m).is_equal_approx(d)


## Simetrik kayıtları açık tek tek kayıtlara çevir (her kopya ayrı kayıt; ayna kopyası "flip").
## Çocukların k. kopyası ebeveynin k. kopyasına bağlanır.
static func expand(craft: Dictionary, group: Array) -> Array:
	var next := next_uid(craft)
	for e: Dictionary in group:
		next = maxi(next, int(e.get("uid", 0)) + 1)
	var out: Array = []
	var copies_of := {}     # eski uid -> [kopya uid'leri]
	for e: Dictionary in group:
		var copies := VesselBuilder.entry_copies(e)
		var uid := int(e.get("uid", -1))
		var parent := int(e.get("parent", -1))
		var pc: Array = copies_of.get(parent, [])
		var mine: Array = []
		for k in copies.size():
			var c: Dictionary = copies[k]
			var ne := e.duplicate(true)
			set_sym(ne, {})
			ne["uid"] = uid if k == 0 else next
			if k > 0:
				next += 1
			var p: Vector3 = c["pos"]
			ne["pos"] = [p.x, p.y, p.z]
			var r: Vector3 = c["rot"]
			if r.is_zero_approx():
				ne.erase("rot")
			else:
				ne["rot"] = [r.x, r.y, r.z]
			if c["flip"]:
				ne["flip"] = true
			else:
				ne.erase("flip")
			if k > 0 and k < pc.size():
				ne["parent"] = pc[k]
			mine.append(ne["uid"])
			out.append(ne)
		copies_of[uid] = mine
	return out


## Taşınan grubu yeni yerine koy: d = yeni kök dönüşümü × eski kök dönüşümünün tersi.
## new_sym: kökün yeni simetrisi. Kurallar:
##   • kök simetrikti (grup bir tarafı temsil ediyor): herkes d ile taşınır; kökle aynı simetriye
##     sahip üyeler yeni simetriyi alır (sağ kanat + kanatçık birlikte karşı tarafa yansır)
##   • kök tekti ve d aynayı bozmuyorsa (eksen boyunca kaydırma): bayraklar korunur
##   • aksi halde simetrik üyeler önce açık kopyalara çevrilir, sonra taşınır; yeni simetri
##     varsa bütün gruba uygulanır (ör. ortadaki podu kanatçıklarıyla yana taşıyıp çiftlemek)
static func transform_group(craft: Dictionary, group: Array, d: Transform3D, new_sym: Dictionary) -> Array:
	if group.is_empty():
		return group
	var root_sym := sym_of(group[0])
	if not root_sym.is_empty():
		for e: Dictionary in group:
			var same := sym_of(e) == root_sym
			_transform(e, d)
			if same:
				set_sym(e, new_sym)
		return group
	# radyal üyeler yalnız dönüşsüz kaydırmada korunabilir (eksen Z yönünde kalmalı)
	var has_radial := false
	for e: Dictionary in group:
		has_radial = has_radial or e.has("radial")
	if new_sym.is_empty() and keeps_mirror(d) and not (has_radial and not d.basis.is_equal_approx(Basis.IDENTITY)):
		for e: Dictionary in group:
			_transform(e, d)
			if e.has("axis"):
				var a: Array = e["axis"]
				var c := d * Vector3(float(a[0]), float(a[1]), 0.0)
				e["axis"] = [c.x, c.y]
		return group
	var out := expand(craft, group)
	for e: Dictionary in out:
		_transform(e, d)
		if not new_sym.is_empty():
			set_sym(e, new_sym)
	return out
