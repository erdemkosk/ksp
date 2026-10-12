class_name Ils
## Aletli iniş sistemi (ILS): uçak bir pist ucuna yaklaşıyorsa (25 km içinde, ±35° koni,
## burnu pist yönüne yakın) yön (localizer) ve 3° süzülüş (glideslope) sapmasını verir.
## PFD'de macenta iğneler: iğneye doğru uç. Pist adı yöne göre (36 = kuzey).

const GLIDE_DEG := 3.0


## Döndürür: {} ya da {name, dist, loc (°, + = uçak eksenin sağında), gs (°, + = süzülüşün üstünde)}
static func info(v: Vessel) -> Dictionary:
	if not is_instance_valid(v):
		return {}
	var pos := v.com_global()
	var fwd := v.forward()
	var best := {}
	var best_d := INF
	for i in TerrainGen.AIRFIELDS.size():
		var a: Dictionary = TerrainGen.AIRFIELDS[i]
		var xz: Vector2 = a["xz"]
		var elev := float(a["elev"])
		var center := MissionManager.world_point(xz.x, xz.y, elev)
		var up := Planet.up_at(center)
		var z := TerrainGen.airfield_transform(i).basis.z.normalized()
		var half := float(a["runway"]) * 0.5
		for end: float in [-1.0, 1.0]:
			# bu uçtan inen uçak pist boyunca -end*z yönünde uçar
			var land := -z * end
			var thr := center + z * end * half
			var rel := pos - thr
			var s := -rel.dot(land)                      # eşiğe kalan yol (önündeyse +)
			if s < -600.0 or s > 25000.0:
				continue
			var right := land.cross(up).normalized()
			var lat := rel.dot(right)
			if absf(lat) > maxf(s, 0.0) * tan(deg_to_rad(35.0)) + 400.0:
				continue
			var hfwd := (fwd - up * fwd.dot(up)).normalized()
			if hfwd.dot(land) < 0.5:
				continue
			if s < best_d:
				best_d = s
				var height := rel.dot(up)
				var loc := rad_to_deg(atan2(lat, s + half * 2.0))        # anten pistin öbür ucunda
				var gs := rad_to_deg(atan2(height, maxf(s + 300.0, 10.0))) - GLIDE_DEG
				var fr := Planet.local_basis(thr)
				var hdg := fposmod(rad_to_deg(atan2(land.dot(fr.x), -land.dot(fr.z))), 360.0)
				var rwy := int(round(hdg / 10.0))
				if rwy == 0:
					rwy = 36
				best = {"name": "%s %02d" % [a["name"], rwy], "dist": maxf(s, 0.0), "loc": loc, "gs": gs}
	return best
