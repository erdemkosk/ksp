class_name StructLimits
## Yapı sınırları tahmini: uçak düz uçuşta hangi hızda, ve kaç G'de kopar; ilk giden parça.
## Uçuştaki Vessel._structural_loads'un statik yaklaşığı (yük = dış kuvvet − parça ataleti):
##   • kanat (yatay): G başına kaldırma payı (alan / toplam alan × ağırlık) − kendi ağırlığı
##   • diğer parçalar: G başına kendi ağırlığı
##   • hız: gövde parçasının ön sürüklemesi (BodyDragModule ile aynı cd kuralı + dalga direnci),
##     kanadın cd0 sürüklemesi; 1 G ağırlıkla vektörel toplanır
## Motor itkisi hesaba katılmaz (hızla değil gazla büyür).


## {g, g_part, vne (m/s, bu yoğunlukta; 0 = bulunamadı), vne_part}
static func estimate(v: Vessel, rho := Atmosphere.SEA_LEVEL_DENSITY) -> Dictionary:
	var out := {"g": 0.0, "g_part": "", "vne": 0.0, "vne_part": ""}
	if not is_instance_valid(v) or v.parts.is_empty():
		return out
	var weight := v.mass * 9.81
	var s_total := 0.0
	for m in v.modules:
		if m is WingModule and absf(m.part.basis.y.y) > 0.6:
			s_total += m.area
	# parça başına: G başına yük (N/G), ön sürükleme katsayısı × alan (cd·A), dayanım
	var rows: Array[Dictionary] = []
	for p in v.parts:
		var per_g := p.get_mass() * 9.81
		var lift := 0.0
		var cda := 0.0
		var wave := false
		for m in p.modules:
			if m is WingModule:
				if absf(p.basis.y.y) > 0.6 and s_total > 0.0:
					lift += weight * m.area / s_total
				cda += m.cd0 * m.area
				wave = true
			elif m is BodyDragModule:
				var cd: float = m.cd_front
				if m.front_open and not m.front_round:
					cd = maxf(cd, BodyDragModule.BLUNT_CD)
				if m.rear_open and not m.rear_tapered:
					cd += BodyDragModule.BASE_CD
				cda += cd * m.front_area
				wave = true
		rows.append({"title": p.title, "per_g": absf(lift - per_g), "cda": cda, "wave": wave, "strength": maxf(p.strength, 1.0)})
	# G sınırı
	var best_g := INF
	for r in rows:
		if float(r["per_g"]) > 1.0:
			var g := float(r["strength"]) / float(r["per_g"])
			if g < best_g:
				best_g = g
				out["g_part"] = r["title"]
	out["g"] = best_g if best_g < INF else 0.0
	# hız sınırı: 30 m/s'den 5 m/s adımlarla, ilk %100 aşan parça
	var s := 30.0
	while s <= 1400.0:
		var q := 0.5 * rho * s * s
		var wd := Atmosphere.wave_drag(s / Atmosphere.SPEED_OF_SOUND)
		for r in rows:
			var drag := q * float(r["cda"]) * (wd if r["wave"] else 1.0)
			var load := Vector2(drag, float(r["per_g"])).length()
			if load >= float(r["strength"]):
				out["vne"] = s
				out["vne_part"] = r["title"]
				return out
		s += 5.0
	return out
