class_name PartLibrary
## Tüm parça tanımları. Şimdilik kodda; ileride her parça kendi klasöründe
## veri dosyası (.tres/.json) + model olacak, bu sınıf onları tarayıp yükleyecek.
##
## Görsel tipleri:
##   "lathe" profile=[Vector2(z, r)...]   döndürme gövdesi (MeshFactory.lathe)
##   "wing"  span, root, tip, sweep, thick  profilli kanat (MeshFactory.wing)
##   "cyl" (axis z/y/x, r / r_front / r_back, len), "box" (size), "sphere" (r, scale)
## "mat": paint, paint_dark, radome, metal, dark, rubber, glass, hud_glass, screen, glow, flame
## "parent": başka bir görselin adı (ona bağlanır). "name": modüllerin bulacağı ad.
## Eksen kuralı: -Z ileri, +Y yukarı, +X sağ. Kanatlarda X = açıklık (kök -X), Z = veter.

static var _defs := {}

## Dünya ölçeği: parçalar 1.3 kat büyük (gövde 1.7 m çap) — insan boyu (pilot, koltuk, kokpit
## içi, cam) ölçeklenmez. Kütle, alan, itki, yakıt ve dayanım s² ile büyür: uçuş performansı
## (kanat yükü, itki/ağırlık, menzil, G limiti) aynı kalır, uçak sadece gerçek boyutuna gelir.
const WORLD_SCALE := 1.3


static func get_def(id: String) -> Dictionary:
	if _defs.is_empty():
		_init_defs()
	return _defs.get(id, {})


static func ids() -> Array:
	if _defs.is_empty():
		_init_defs()
	return _defs.keys()


static func _init_defs() -> void:
	_register_all()
	for id in _defs:
		_globalize(_defs[id], WORLD_SCALE)


## Parça tanımını dünya ölçeğine getirir (bkz. WORLD_SCALE).
static func _globalize(d: Dictionary, s: float) -> void:
	var s2 := s * s
	d["mass"] = float(d.get("mass", 100.0)) * s2
	d["hp"] = float(d.get("hp", 100.0)) * s2
	d["size"] = (d.get("size", Vector3.ONE) as Vector3) * s
	if d.has("strength_kn"):
		d["strength_kn"] = float(d["strength_kn"]) * s2
	for c: Dictionary in d.get("colliders", []):
		c["pos"] = (c.get("pos", Vector3.ZERO) as Vector3) * s
		for key in ["r", "len"]:
			if c.has(key):
				c[key] = float(c[key]) * s
		if c.has("size"):
			c["size"] = (c["size"] as Vector3) * s
	for m: Dictionary in d.get("modules", []):
		if m.get("type", "") == "landing_gear" and not m.has("drag_area"):
			m["drag_area"] = 0.25 if m.get("steerable", false) else 0.4
		for key in ["area", "front_area", "side_area", "max_thrust", "fuel_rate", "capacity", "fuel", "spring", "damper", "drag_area"]:
			if m.has(key):
				m[key] = float(m[key]) * s2
		for key in ["rest_length", "wheel_radius"]:
			if m.has(key):
				m[key] = float(m[key]) * s
	d["visual_pivot"] = (d.get("visual_pivot", Vector3.ZERO) as Vector3) * s
	d["_scale"] = s


static func _register_all() -> void:
	_defs["nose_cone"] = {
		"title": "Burun Konisi", "category": "gövde", "mass": 60.0, "hp": 80.0, "cost": 150,
		"size": Vector3(1.3, 1.3, 1.5),
		"visuals": [
			{"type": "lathe", "profile": _ogive(-0.75, 1.5, 0.65), "mat": "paint"},
		],
		"colliders": [{"type": "cyl", "r": 0.45, "len": 1.4}],
		"modules": [{"type": "body_drag", "front_area": 1.33, "side_area": 1.0, "cd_front": 0.08, "cd_side": 0.5}],
	}

	_defs["radar_nose"] = {
		"title": "Radar Burnu (Radom)", "category": "sensör", "mass": 180.0, "hp": 90.0, "cost": 2500,
		"size": Vector3(1.3, 1.3, 1.8),
		"visuals": [
			{"type": "lathe", "profile": _ogive(-0.9, 1.8, 0.65), "mat": "radome"},
			{"type": "cyl", "r": 0.025, "len": 0.7, "pos": Vector3(0, 0, -1.2), "mat": "metal"},
		],
		"colliders": [{"type": "cyl", "r": 0.45, "len": 1.7}],
		"modules": [
			{"type": "radar", "range": 18000.0, "cone_deg": 60.0},
			{"type": "body_drag", "front_area": 1.33, "side_area": 1.2, "cd_front": 0.08, "cd_side": 0.5},
		],
	}

	_defs["targeting_pod"] = {
		"title": "Hedefleme Podu (FLIR/TV)", "category": "sensör", "mass": 210.0, "hp": 90.0, "cost": 3200,
		"size": Vector3(0.5, 0.5, 2.3),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-0.9, 0.2), Vector2(-0.7, 0.24), Vector2(0.9, 0.24), Vector2(1.15, 0.12)], "mat": "paint_dark"},
			{"type": "box", "size": Vector3(0.12, 0.2, 0.9), "pos": Vector3(0, 0.3, 0.1), "mat": "paint_dark"},
			# döner optik başlık: yönde dönen gövde + yükselişte dönen top, koyu pencere
			{"type": "sphere", "name": "Head", "r": 0.17, "pos": Vector3(0, 0, -1.0), "mat": "paint_dark"},
			{"type": "sphere", "name": "Ball", "parent": "Head", "r": 0.2, "pos": Vector3(0, 0, -0.1), "mat": "metal"},
			{"type": "cyl", "parent": "Ball", "axis": "z", "r": 0.09, "len": 0.05, "pos": Vector3(0, 0, -0.18), "mat": "glass"},
		],
		"colliders": [{"type": "cyl", "r": 0.24, "len": 2.2}],
		"modules": [
			{"type": "targeting_pod"},
			{"type": "body_drag", "front_area": 0.18, "side_area": 1.0, "cd_front": 0.12, "cd_side": 0.5},
		],
	}

	_defs["gun_pod"] = {
		"title": "20 mm Top Podu", "category": "silah", "mass": 280.0, "hp": 120.0, "cost": 1800,
		"size": Vector3(0.45, 0.45, 2.6),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.3, 0.08), Vector2(-1.0, 0.2), Vector2(1.0, 0.22), Vector2(1.3, 0.12)], "mat": "paint_dark"},
			{"type": "cyl", "r": 0.04, "len": 0.9, "pos": Vector3(0, 0, -1.6), "mat": "metal"},
		],
		"colliders": [{"type": "cyl", "r": 0.22, "len": 2.6}],
		"modules": [
			{"type": "gun", "rate": 50.0, "muzzle_velocity": 1000.0, "damage": 28.0, "ammo": 500},
			{"type": "body_drag", "front_area": 0.15, "side_area": 1.0, "cd_front": 0.1, "cd_side": 0.6},
		],
	}

	_defs["missile_rail"] = {
		"title": "IR Füze + Ray", "category": "silah", "mass": 25.0, "hp": 60.0, "cost": 1500,
		"size": Vector3(0.3, 0.35, 2.9),
		"visuals": [
			{"type": "box", "size": Vector3(0.06, 0.18, 1.6), "pos": Vector3(0, 0.05, 0), "mat": "paint_dark"},
			{"type": "lathe", "name": "Missile", "profile": [Vector2(-1.45, 0.0), Vector2(-1.25, 0.07), Vector2(1.4, 0.07), Vector2(1.45, 0.05)], "pos": Vector3(0, -0.12, 0), "mat": "paint", "color": Color(0.86, 0.87, 0.85), "segments": 16},
		],
		"colliders": [{"type": "box", "size": Vector3(0.2, 0.3, 2.8)}],
		"modules": [
			{"type": "missile"},
			{"type": "body_drag", "front_area": 0.05, "side_area": 0.4, "cd_front": 0.2, "cd_side": 0.6},
		],
	}

	_defs["cockpit_mk1"] = _cockpit("Mk1 Savaş Kokpiti", "fighter", 900.0, 1500)
	_defs["cockpit_civil"] = _cockpit("Sivil Kokpit (yan yana 2 kişi)", "civil", 760.0, 1300)

	_defs["tank_long"] = _tank("Uzun Yakıt Tankı", 4.0, 400.0, 1200.0)
	_defs["tank_short"] = _tank("Kısa Yakıt Tankı", 2.0, 200.0, 600.0)

	_defs["jet_engine"] = {
		"title": "J-70 Jet Motoru", "category": "motor", "mass": 1100.0, "hp": 200.0, "cost": 3000,
		"size": Vector3(1.2, 1.2, 2.5),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.25, 0.65), Vector2(0.4, 0.64), Vector2(1.0, 0.58), Vector2(1.25, 0.53)], "mat": "paint_dark"},
			{"type": "lathe", "profile": [Vector2(1.15, 0.53), Vector2(1.62, 0.46), Vector2(1.62, 0.46), Vector2(1.62, 0.4), Vector2(1.62, 0.4), Vector2(1.2, 0.4)], "mat": "metal"},
			{"type": "cyl", "r": 0.41, "len": 0.02, "pos": Vector3(0, 0, 1.4), "mat": "dark"},
			{"type": "lathe", "name": "Exhaust", "profile": [Vector2(0, 0.4), Vector2(0.6, 0.37), Vector2(2.0, 0.26), Vector2(4.2, 0.0)], "pos": Vector3(0, 0, 1.6), "mat": "flame", "segments": 24},
			{"type": "lathe", "name": "ExhaustCore", "profile": [Vector2(0, 0.3), Vector2(0.4, 0.27), Vector2(1.3, 0.12), Vector2(2.0, 0.0)], "pos": Vector3(0, 0, 1.6), "mat": "flame_core", "segments": 20},
			{"type": "lathe", "name": "HeatHaze", "profile": [Vector2(0, 0.42), Vector2(2.5, 0.8), Vector2(7.0, 1.4)], "pos": Vector3(0, 0, 1.65), "mat": "heat_haze", "segments": 16},
		],
		"colliders": [{"type": "cyl", "r": 0.6, "len": 2.5}],
		"modules": [
			{"type": "engine", "max_thrust": 70000.0, "fuel_rate": 2.0, "spool_rate": 0.6},
			{"type": "body_drag", "front_area": 1.13, "side_area": 3.0, "cd_front": 0.1},
		],
	}

	_defs["wing_main"] = _wing("Ana Kanat", Vector3(4.0, 0.2, 2.5), 350.0, 10.0, 4.0, 16.0,
		{"span": 4.0, "root": 3.0, "tip": 1.6, "sweep": 1.0, "thick": 0.09})
	_defs["wing_small"] = _wing("Küçük Kanat", Vector3(2.0, 0.14, 1.5), 120.0, 3.0, 3.0, 18.0,
		{"span": 2.0, "root": 1.8, "tip": 1.0, "sweep": 0.7, "thick": 0.1})

	_defs["elevon"] = _control_surface("Elevon", Vector3(1.5, 0.08, 0.8), 40.0, 1.2, 20.0, -0.4,
		{"span": 1.5, "root": 0.8, "tip": 0.8, "sweep": 0.0, "thick": 0.06})
	_defs["stabilator"] = _control_surface("Stabilatör (tam hareketli kuyruk)", Vector3(2.0, 0.12, 1.5), 130.0, 3.0, 18.0, 0.0,
		{"span": 2.0, "root": 1.7, "tip": 0.9, "sweep": 0.6, "thick": 0.06})

	_defs["gear_main"] = _gear("Ana İniş Takımı", 120.0, 0.35, 120000.0, 16000.0, false)
	# yapısal dayanımlar (kN): kanat ~12-13 G, takımlar yüksek hızda açılırsa kopar
	_defs["wing_main"]["strength_kn"] = 420.0
	_defs["wing_small"]["strength_kn"] = 120.0
	_defs["stabilator"]["strength_kn"] = 140.0
	_defs["elevon"]["strength_kn"] = 45.0
	_defs["gear_main"]["strength_kn"] = 30.0
	_defs["jet_engine"]["strength_kn"] = 300.0   # kendi ataleti + afterburner itkisi
	_defs["gear_nose"] = _gear("Burun İniş Takımı", 70.0, 0.28, 60000.0, 8000.0, true)
	_defs["gear_nose"]["strength_kn"] = 18.0

	# --- motorlar: J-70'in ölçeklenmiş kardeşleri
	_defs["jet_engine_small"] = _engine_variant("J-40 Hafif Motor", 0.75, 520.0, 38000.0, 1.0, 0.8, 1800)
	_defs["jet_engine_big"] = _engine_variant("J-120 Ağır Motor (AB)", 1.2, 1900.0, 125000.0, 3.4, 0.45, 5200)

	# --- kanat ve kontrol
	_defs["wing_delta"] = _wing("Delta Kanat", Vector3(4.5, 0.22, 5.0), 520.0, 15.0, 2.2, 24.0,
		{"span": 4.5, "root": 5.0, "tip": 0.6, "sweep": 4.2, "thick": 0.06})
	_defs["wing_delta"]["strength_kn"] = 560.0
	_defs["rudder"] = _control_surface("Dümen (dikey kuyruğa)", Vector3(1.6, 0.08, 0.9), 45.0, 1.5, 25.0, -0.45,
		{"span": 1.6, "root": 0.9, "tip": 0.6, "sweep": 0.35, "thick": 0.06})
	_defs["rudder"]["strength_kn"] = 50.0

	# --- karşı tedbir ve dış yükler
	_defs["flare_pod"] = {
		"title": "Flare Fişekliği", "category": "savunma", "mass": 60.0, "hp": 60.0, "cost": 900,
		"size": Vector3(0.36, 0.26, 1.0),
		"visuals": [
			{"type": "box", "size": Vector3(0.36, 0.22, 1.0), "mat": "paint_dark"},
			{"type": "box", "size": Vector3(0.3, 0.02, 0.8), "pos": Vector3(0, -0.115, 0), "mat": "dark"},
			{"type": "box", "size": Vector3(0.37, 0.05, 0.08), "pos": Vector3(0, 0, -0.42), "mat": "yellow"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.36, 0.24, 1.0)}],
		"modules": [
			{"type": "flare", "count": 30},
			{"type": "body_drag", "front_area": 0.08, "side_area": 0.3, "cd_front": 0.3, "cd_side": 0.6},
		],
	}
	_defs["bomb_rail"] = {
		"title": "250 kg Bomba + Askı", "category": "silah", "mass": 30.0, "hp": 70.0, "cost": 1100,
		"size": Vector3(0.45, 0.7, 2.3),
		"visuals": [
			{"type": "box", "size": Vector3(0.08, 0.2, 1.0), "pos": Vector3(0, 0.12, 0), "mat": "paint_dark"},
			{"type": "lathe", "name": "Bomb", "profile": [Vector2(-1.1, 0.0), Vector2(-0.8, 0.16), Vector2(0.5, 0.17), Vector2(1.0, 0.07)],
				"pos": Vector3(0, -0.18, 0), "mat": "paint", "color": Color(0.33, 0.37, 0.28), "segments": 16},
		],
		"colliders": [{"type": "box", "size": Vector3(0.36, 0.5, 2.1)}],
		"modules": [
			{"type": "bomb"},
			{"type": "body_drag", "front_area": 0.1, "side_area": 0.7, "cd_front": 0.25, "cd_side": 0.6},
		],
	}
	_defs["drop_tank"] = {
		"title": "Harici Yakıt Tankı", "category": "harici", "mass": 90.0, "hp": 60.0, "cost": 500,
		"size": Vector3(0.7, 0.8, 3.4),
		"visuals": [
			{"type": "box", "size": Vector3(0.08, 0.18, 0.9), "pos": Vector3(0, 0.31, 0), "mat": "paint_dark"},
			{"type": "lathe", "profile": [Vector2(-1.7, 0.0), Vector2(-1.2, 0.28), Vector2(-0.6, 0.35), Vector2(0.8, 0.35), Vector2(1.5, 0.2), Vector2(1.7, 0.0)],
				"pos": Vector3(0, -0.05, 0), "mat": "paint"},
		],
		"colliders": [{"type": "cyl", "r": 0.35, "len": 3.2, "pos": Vector3(0, -0.05, 0)}],
		"modules": [
			{"type": "fuel_tank", "capacity": 700.0},
			{"type": "body_drag", "front_area": 0.38, "side_area": 1.9, "cd_front": 0.06, "cd_side": 0.5},
		],
	}
	_register_extra()


## Hava alıkları, ek aerodinamik yüzeyler ve frenler.
static func _register_extra() -> void:
	_defs["intake_side"] = {
		"title": "Yan Hava Alığı", "category": "hava alığı", "mass": 90.0, "hp": 80.0, "cost": 600,
		"size": Vector3(0.45, 0.75, 1.6),
		"visuals": [
			{"type": "box", "size": Vector3(0.42, 0.72, 1.6), "mat": "paint"},
			{"type": "box", "size": Vector3(0.34, 0.62, 0.02), "pos": Vector3(0, 0, -0.8), "mat": "dark"},
			{"type": "box", "size": Vector3(0.44, 0.06, 0.3), "pos": Vector3(0, 0.33, -0.66), "rot": Vector3(-12, 0, 0), "mat": "paint_dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.42, 0.72, 1.6)}],
		"modules": [
			{"type": "intake", "area": 0.45},
			{"type": "body_drag", "front_area": 0.1, "side_area": 1.1, "cd_front": 0.15, "cd_side": 0.6},
		],
	}
	_defs["intake_nose"] = {
		"title": "Burun Hava Alığı (halka)", "category": "gövde", "mass": 160.0, "hp": 110.0, "cost": 900,
		"size": Vector3(1.3, 1.3, 1.4),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-0.7, 0.5), Vector2(-0.55, 0.6), Vector2(0.7, 0.65)], "mat": "paint"},
			{"type": "lathe", "profile": [Vector2(-0.7, 0.48), Vector2(0.4, 0.45)], "mat": "dark"},
			{"type": "lathe", "profile": [Vector2(-1.0, 0.0), Vector2(-0.6, 0.2), Vector2(0.2, 0.26)], "mat": "radome"},
		],
		"colliders": [{"type": "cyl", "r": 0.65, "len": 1.4}],
		"modules": [
			{"type": "intake", "area": 0.9},
			{"type": "body_drag", "front_area": 0.5, "side_area": 1.6, "cd_front": 0.12},
		],
	}
	_defs["canard"] = _control_surface("Kanard (ön kanatçık)", Vector3(1.4, 0.08, 1.1), 40.0, 1.5, 22.0, 0.0,
		{"span": 1.4, "root": 1.1, "tip": 0.55, "sweep": 0.6, "thick": 0.05})
	_defs["canard"]["strength_kn"] = 60.0
	_defs["wing_swept"] = _wing("Ok Kanat (yüksek hız)", Vector3(5.0, 0.16, 3.4), 430.0, 12.0, 4.4, 14.0,
		{"span": 5.0, "root": 3.4, "tip": 1.0, "sweep": 2.8, "thick": 0.045})
	_defs["wing_swept"]["strength_kn"] = 440.0
	_defs["fin_vertical"] = _wing("Dikey Kuyruk", Vector3(2.3, 0.14, 2.6), 150.0, 3.8, 1.7, 22.0,
		{"span": 2.3, "root": 2.6, "tip": 1.0, "sweep": 1.7, "thick": 0.06})
	_defs["fin_vertical"]["strength_kn"] = 140.0
	_defs["airbrake"] = {
		"title": "Hava Freni (B)", "category": "fren", "mass": 70.0, "hp": 70.0, "cost": 700,
		"strength_kn": 60.0,
		"size": Vector3(0.7, 0.1, 1.2),
		# gövdenin üstüne (r 0.65) yüzeyle aynı hizada oturan kavisli kapak; parça merkezi gövde
		# yüzeyinde. Kapak ön kenarından menteşeli: açılınca arka kenar kalkar, altta oyuk ve piston.
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-0.6, 0.645), Vector2(0.6, 0.645)], "arc_from": 62.0, "arc_to": 118.0, "segments": 12, "pos": Vector3(0, -0.65, 0), "mat": "dark"},
			{"type": "box", "name": "Panel", "size": Vector3(0.02, 0.02, 0.02), "pos": Vector3(0, 0.0, -0.58), "mat": "paint_dark"},
			{"type": "lathe", "parent": "Panel", "profile": [Vector2(0.0, 0.658), Vector2(1.14, 0.658)], "arc_from": 64.0, "arc_to": 116.0, "segments": 12, "pos": Vector3(0, -0.655, 0), "mat": "paint"},
			{"type": "cyl", "parent": "Panel", "axis": "y", "r": 0.025, "len": 0.3, "pos": Vector3(0, -0.13, 0.75), "mat": "metal"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.6, 0.08, 1.2)}],
		"modules": [{"type": "airbrake", "area": 1.1, "cd": 1.25}],
	}
	_defs["drag_chute"] = {
		"title": "Fren Paraşütü (yerde B)", "category": "fren", "mass": 45.0, "hp": 50.0, "cost": 400,
		"size": Vector3(0.5, 0.5, 0.8),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-0.4, 0.25), Vector2(0.3, 0.25), Vector2(0.4, 0.18)], "mat": "paint_dark"},
			{"type": "cyl", "r": 0.2, "len": 0.04, "pos": Vector3(0, 0, 0.42), "mat": "yellow"},
		],
		"colliders": [{"type": "cyl", "r": 0.25, "len": 0.8}],
		"modules": [{"type": "chute", "area": 18.0}],
	}
	# yumuşak geçişler: gövde (r 0.65) ile büyük/küçük motor arası, sivri kuyruk
	for spec in [["adapter_big", "Geçiş Konisi (büyük motora)", 0.65, 0.78], ["adapter_small", "Geçiş Konisi (küçük motora)", 0.65, 0.49], ["tail_cone", "Kuyruk Konisi", 0.65, 0.22]]:
		var r0: float = spec[2]
		var r1: float = spec[3]
		var ln := 1.6 if spec[0] == "tail_cone" else 0.8
		_defs[spec[0]] = {
			"title": spec[1], "category": "gövde", "mass": 70.0 * ln, "hp": 90.0, "cost": 200,
			"size": Vector3(maxf(r0, r1) * 2.0, maxf(r0, r1) * 2.0, ln),
			"visuals": [{"type": "lathe", "profile": [Vector2(-ln * 0.5, r0), Vector2(-ln * 0.1, lerpf(r0, r1, 0.45)), Vector2(ln * 0.5, r1)], "mat": "paint"}],
			"colliders": [{"type": "cyl", "r": (r0 + r1) * 0.5, "len": ln}],
			"modules": [{"type": "body_drag", "front_area": 0.4, "side_area": ln * 1.2, "cd_front": 0.05}],
		}
	_register_civil()


## Sivil / yardım parçaları: pervaneli motor, yolcu kabini, kargo bölmesi, düz kanat.
static func _register_civil() -> void:
	var prop_visuals := [
		{"type": "lathe", "profile": [Vector2(-0.5, 0.5), Vector2(0.2, 0.62), Vector2(0.8, 0.6)], "mat": "paint"},
		{"type": "lathe", "name": "Prop", "profile": [Vector2(-0.95, 0.0), Vector2(-0.8, 0.14), Vector2(-0.55, 0.22), Vector2(-0.5, 0.22)], "mat": "metal"},
	]
	_defs["prop_engine"] = {
		"title": "P-26 Pervaneli Motor", "category": "motor", "mass": 380.0, "hp": 140.0, "cost": 1200,
		"size": Vector3(1.25, 1.25, 1.6),
		"visuals": prop_visuals + _prop_blades() + [{"type": "cyl", "name": "PropDisc", "axis": "z", "r": 1.2, "len": 0.01, "pos": Vector3(0, 0, -0.62), "mat": "prop_disc"}],
		"colliders": [{"type": "cyl", "r": 0.6, "len": 1.4, "pos": Vector3(0, 0, 0.1)}],
		"modules": [
			{"type": "engine", "max_thrust": 26000.0, "fuel_rate": 0.35, "spool_rate": 0.5, "prop": true, "prop_vmax": 150.0},
			{"type": "intake", "area": 0.3},
			{"type": "body_drag", "front_area": 1.0, "side_area": 1.6, "cd_front": 0.12},
		],
		"strength_kn": 120.0,
	}
	var cabin := [{"type": "lathe", "profile": [Vector2(-1.5, 0.65), Vector2(1.5, 0.65)], "mat": "paint", "color": Color(0.9, 0.91, 0.92)}]
	for side in [-1.0, 1.0]:
		for i in 5:
			cabin.append({"type": "box", "size": Vector3(0.04, 0.26, 0.3), "pos": Vector3(side * 0.64, 0.12, -1.1 + i * 0.55), "mat": "screen", "color": Color(0.2, 0.3, 0.4)})
	cabin.append({"type": "box", "size": Vector3(0.04, 0.95, 0.6), "pos": Vector3(-0.645, -0.02, 1.15), "mat": "paint_dark"})
	cabin.append({"type": "box", "size": Vector3(1.32, 0.08, 3.0), "pos": Vector3(0, 0.0, 0), "mat": "paint", "color": Color(0.15, 0.35, 0.6)})
	_defs["passenger_cabin"] = {
		"title": "Yolcu Kabini (6 koltuk)", "category": "gövde", "mass": 520.0, "hp": 170.0, "cost": 1100,
		"size": Vector3(1.3, 1.3, 3.0),
		"visuals": cabin,
		"colliders": [{"type": "cyl", "r": 0.65, "len": 3.0}],
		"modules": [
			{"type": "passenger", "seats": 6},
			{"type": "body_drag", "front_area": 1.33, "side_area": 3.9, "cd_front": 0.03},
		],
	}
	_defs["cargo_bay"] = {
		"title": "Kargo Bölmesi (4 sandık)", "category": "gövde", "mass": 450.0, "hp": 170.0, "cost": 900,
		"size": Vector3(1.3, 1.3, 3.0),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.5, 0.65), Vector2(1.5, 0.65)], "mat": "paint", "color": Color(0.42, 0.46, 0.36)},
			{"type": "box", "size": Vector3(0.9, 0.04, 2.4), "pos": Vector3(0, -0.64, 0), "mat": "dark"},
			{"type": "box", "size": Vector3(0.05, 0.03, 2.4), "pos": Vector3(0, -0.66, 0), "mat": "yellow"},
		],
		"colliders": [{"type": "cyl", "r": 0.65, "len": 3.0}],
		"modules": [
			{"type": "cargo", "crates": 4},
			{"type": "body_drag", "front_area": 1.33, "side_area": 3.9, "cd_front": 0.03},
		],
	}
	_defs["wing_straight"] = _wing("Düz Kanat (yüksek kaldırma)", Vector3(5.5, 0.22, 1.9), 260.0, 9.5, 6.5, 17.0,
		{"span": 5.5, "root": 1.9, "tip": 1.3, "sweep": 0.25, "thick": 0.1})
	_defs["wing_straight"]["strength_kn"] = 190.0
	_register_more()


static func _prop_blades() -> Array:
	var out := []
	for i in 3:
		var a := deg_to_rad(i * 120.0)
		out.append({"type": "box", "parent": "Prop", "size": Vector3(0.17, 1.2, 0.04), "pos": Vector3(-sin(a), cos(a), 0.0) * 0.62 + Vector3(0, 0, -0.62),
			"rot": Vector3(0, 14, i * 120.0), "mat": "dark"})
	return out


## J-70'i k katsayısıyla ölçekleyen motor tanımı (görseller, çarpışma, boyut).
static func _engine_variant(title: String, k: float, mass: float, thrust: float, fuel_rate: float, spool: float, cost: int) -> Dictionary:
	var d: Dictionary = _defs["jet_engine"].duplicate(true)
	d["title"] = title
	d["mass"] = mass
	d["cost"] = cost
	d["hp"] = 200.0 * k
	d["size"] = (d["size"] as Vector3) * k
	d["strength_kn"] = thrust / 1000.0 * 4.0
	for v: Dictionary in d["visuals"]:
		if v.has("profile"):
			var prof: Array = []
			for p: Vector2 in v["profile"]:
				prof.append(p * k)
			v["profile"] = prof
		for key in ["r", "len"]:
			if v.has(key):
				v[key] = float(v[key]) * k
		if v.has("pos"):
			v["pos"] = (v["pos"] as Vector3) * k
	for c: Dictionary in d["colliders"]:
		c["r"] = float(c["r"]) * k
		c["len"] = float(c["len"]) * k
	d["modules"] = [
		{"type": "engine", "max_thrust": thrust, "fuel_rate": fuel_rate, "spool_rate": spool},
		{"type": "body_drag", "front_area": 1.13 * k * k, "side_area": 3.0 * k * k, "cd_front": 0.1},
	]
	return d


static func _ogive(z_front: float, length: float, radius: float) -> Array:
	var pts := []
	for i in 13:
		var t := i / 12.0
		pts.append(Vector2(z_front + length * t, radius * sqrt(1.0 - (1.0 - t) * (1.0 - t))))
	return pts


static func _tank(title: String, length: float, dry: float, fuel: float) -> Dictionary:
	var half := length * 0.5
	var visuals := [{"type": "lathe", "profile": [Vector2(-half, 0.65), Vector2(half, 0.65)], "mat": "paint"}]
	var z := -half + 0.6
	while z < half - 0.3:
		visuals.append({"type": "cyl", "r": 0.653, "len": 0.025, "pos": Vector3(0, 0, z), "mat": "paint_dark"})
		z += 1.2
	return {
		"title": title, "category": "gövde", "mass": dry, "hp": 150.0, "cost": int(length * 150),
		"size": Vector3(1.3, 1.3, length),
		"visuals": visuals,
		"colliders": [{"type": "cyl", "r": 0.65, "len": length}],
		"modules": [
			{"type": "fuel_tank", "capacity": fuel},
			{"type": "body_drag", "front_area": 1.33, "side_area": 1.3 * length, "cd_front": 0.03},
		],
	}


static func _wing(title: String, size: Vector3, mass: float, area: float, aspect: float, stall: float, shape: Dictionary) -> Dictionary:
	var visual := shape.duplicate()
	visual["type"] = "wing"
	visual["mat"] = "paint"
	return {
		"title": title, "category": "kanat", "mass": mass, "hp": 150.0, "cost": int(area * 80),
		"size": size, "mirror_visual": true,
		"visuals": [visual],
		"colliders": [{"type": "box", "size": size}],
		"modules": [{"type": "wing", "area": area, "aspect_ratio": aspect, "stall_deg": stall, "cd0": 0.012}],
	}


## hinge_z: menteşe konumu (yerel z). Görsel bu noktanın etrafında döner.
static func _control_surface(title: String, size: Vector3, mass: float, area: float, max_defl: float, hinge_z: float, shape: Dictionary) -> Dictionary:
	var visual := shape.duplicate()
	visual["type"] = "wing"
	visual["mat"] = "paint_dark"
	visual["pos"] = Vector3(0, 0, -hinge_z)
	return {
		"title": title, "category": "kontrol", "mass": mass, "hp": 60.0, "cost": int(area * 150),
		"size": size, "mirror_visual": true,
		"visual_pivot": Vector3(0, 0, hinge_z),
		"visuals": [visual],
		"colliders": [{"type": "box", "size": size}],
		"modules": [{"type": "control_surface", "area": area, "aspect_ratio": 4.0, "stall_deg": 16.0,
			"cd0": 0.015, "max_deflection_deg": max_defl}],
	}


static func _gear(title: String, mass: float, wheel_r: float, spring: float, damper: float, steerable: bool) -> Dictionary:
	var rest := 1.2
	return {
		"title": title, "category": "iniş takımı", "mass": mass, "hp": 80.0, "cost": 400,
		"size": Vector3(0.4, rest, 0.6),
		"visuals": [
			{"type": "cyl", "name": "Strut", "axis": "y", "r": 0.07, "len": rest, "pos": Vector3(0, -rest * 0.5, 0), "mat": "metal"},
			{"type": "cyl", "name": "Wheel", "axis": "x", "r": wheel_r, "len": 0.24, "pos": Vector3(0, -rest, 0), "mat": "rubber"},
			{"type": "cyl", "parent": "Wheel", "axis": "y", "r": wheel_r * 0.55, "len": 0.26, "mat": "metal"},
		],
		"colliders": [],
		"modules": [{"type": "landing_gear", "rest_length": rest, "wheel_radius": wheel_r, "spring": spring,
			"damper": damper, "steerable": steerable}],
	}


## Kokpit gövdesi: önü ve arkası kapalı, ortası açık kuyu; içinde panel, siper, konsollar,
## koltuk(lar), pedallar. Kanopi/kapı, kumandalar ve anahtarları CockpitModule kurar.
static func _cockpit(title: String, layout: String, mass: float, cost: int) -> Dictionary:
	var civil := layout == "civil"
	var paint := Color(0.92, 0.93, 0.94) if civil else Color(0, 0, 0, 0)
	var open_from := -0.95 if civil else -0.75
	var open_to := 0.85 if civil else 1.0
	var arc_from := 150.0 if civil else 132.0
	var arc_to := 390.0 if civil else 408.0
	var pz := -0.42 if civil else -0.38
	var dy := -0.1 if civil else 0.0      # iç düzen gövdeye gömülü (CockpitModule LAYOUTS "drop" ile aynı)
	var d := Vector3(0, dy, 0)
	var v := [
		{"type": "lathe", "profile": [Vector2(-1.5, 0.65), Vector2(open_from, 0.65)], "mat": "paint", "color": paint},
		{"type": "lathe", "profile": [Vector2(open_from, 0.65), Vector2(open_to, 0.65)], "mat": "paint", "color": paint, "arc_from": arc_from, "arc_to": arc_to},
		{"type": "lathe", "profile": [Vector2(open_to, 0.65), Vector2(1.5, 0.65)], "mat": "paint", "color": paint},
		{"type": "lathe", "profile": [Vector2(open_from, 0.62), Vector2(open_to, 0.62)], "mat": "interior", "arc_from": arc_from, "arc_to": arc_to},
		{"type": "cyl", "r": 0.62, "len": 0.02, "pos": Vector3(0, 0, open_from), "mat": "interior"},
		{"type": "cyl", "r": 0.62, "len": 0.02, "pos": Vector3(0, 0, open_to), "mat": "interior"},
		{"type": "box", "size": Vector3(1.0 if civil else 0.8, 0.04, 1.7), "pos": Vector3(0, 0.05, -0.1) + d, "noscale": true, "mat": "dark"},
		# gösterge paneli (pilota bakar, üstü geriye yatık), göz siperi, panel altı
		{"type": "box", "size": Vector3(1.22 if civil else 0.74, 0.36, 0.05), "pos": Vector3(0, 0.69, pz - 0.035) + d, "noscale": true, "rot": Vector3(-15, 0, 0), "mat": "interior"},
		{"type": "box", "size": Vector3(1.26 if civil else 0.8, 0.05, 0.2 if civil else 0.3), "pos": Vector3(0, 0.89, pz - (0.13 if civil else 0.17)) + d, "noscale": true, "mat": "dark"},
		{"type": "box", "size": Vector3(1.1 if civil else 0.7, 0.3, 0.4), "pos": Vector3(0, 0.38, pz - 0.2) + d, "noscale": true, "mat": "interior"},
	]
	if civil:
		for sx in [-0.3, 0.3]:
			v.append_array(_seat_visuals(Vector3(sx, 0, 0.12) + d, 8.0, Color(0.32, 0.22, 0.15), 0.82))
			for px in [-0.13, 0.13]:
				v.append({"type": "box", "size": Vector3(0.09, 0.13, 0.03), "pos": Vector3(sx + px, 0.14, -0.6) + d, "noscale": true, "rot": Vector3(-30, 0, 0), "mat": "metal"})
		v.append({"type": "box", "size": Vector3(1.32, 0.12, 2.9), "pos": Vector3(0, -0.05, 0), "mat": "paint", "color": Color(0.15, 0.35, 0.6)})
	else:
		v.append_array(_seat_visuals(Vector3(0, 0, 0.18) + d, 12.0, Color(0.11, 0.11, 0.12)))
		# yan konsollar, kanopi rayları, pedallar, yan hava girişleri
		for sx in [-0.36, 0.36]:
			v.append({"type": "box", "size": Vector3(0.14, 0.06, 0.62), "pos": Vector3(sx, 0.46, -0.04) + d, "noscale": true, "mat": "interior"})
			v.append({"type": "box", "size": Vector3(0.05, 0.05, 1.75), "pos": Vector3(sx * 1.22, 0.49, 0.12), "mat": "paint_dark"})
			v.append({"type": "box", "size": Vector3(0.09, 0.13, 0.03), "pos": Vector3(sx * 0.36, 0.14, -0.58) + d, "noscale": true, "rot": Vector3(-30, 0, 0), "mat": "metal"})
			v.append({"type": "box", "size": Vector3(0.42, 0.78, 1.4), "pos": Vector3(sx * 2.05, -0.08, 0.8), "mat": "paint"})
			v.append({"type": "box", "size": Vector3(0.34, 0.68, 0.02), "pos": Vector3(sx * 2.05, -0.08, 0.09), "mat": "dark"})
	return {
		"title": title, "category": "kokpit", "mass": mass, "hp": 250.0, "cost": cost,
		"size": Vector3(1.3, 1.3, 3.0),
		"visuals": v,
		"colliders": [{"type": "cyl", "r": 0.65, "len": 3.0}],
		"modules": [
			{"type": "cockpit", "layout": layout},
			{"type": "intake", "area": 0.6 if not civil else 0.0},
			{"type": "fuel_tank", "capacity": 150.0},
			{"type": "body_drag", "front_area": 1.33, "side_area": 3.9, "cd_front": 0.12 if not civil else 0.06},
		],
	}


## Koltuk: oturak, sırt, başlık; savaşta sarı fırlatma kolları.
static func _seat_visuals(at: Vector3, recline: float, color: Color, tall := 1.0) -> Array:
	var r := Vector3(recline, 0, 0)
	var back := 0.85 * tall
	var out := [
		{"type": "box", "size": Vector3(0.44, 0.1, 0.44), "pos": at + Vector3(0, 0.22, 0.04), "noscale": true, "mat": "seat", "color": color},
		{"type": "box", "size": Vector3(0.46, back, 0.1), "pos": at + Vector3(0, 0.24 + back * 0.5, 0.3), "rot": r, "noscale": true, "mat": "seat", "color": color},
		{"type": "box", "size": Vector3(0.3, 0.2, 0.12), "pos": at + Vector3(0, 0.24 + back + 0.01, 0.4), "rot": r, "noscale": true, "mat": "seat", "color": color},
	]
	if recline > 10.0:
		for sx in [-0.25, 0.25]:
			out.append({"type": "box", "size": Vector3(0.05, 0.6, 0.05), "pos": at + Vector3(sx, 0.62, 0.28), "rot": r, "noscale": true, "mat": "yellow"})
	return out


## Ek motorlar, kanatlar ve alıklar.
static func _register_more() -> void:
	# turbofan: art yakıcısız, verimli, büyük ön çap
	var tf := _engine_variant("J-90 Turbofan (verimli, AB yok)", 1.1, 1300.0, 82000.0, 1.1, 0.5, 4200)
	(tf["modules"] as Array)[0]["no_ab"] = true
	tf["visuals"][0]["profile"] = [Vector2(-1.4, 0.74), Vector2(-1.2, 0.76), Vector2(0.6, 0.74), Vector2(1.38, 0.55)]
	tf["visuals"].append({"type": "cyl", "r": 0.62, "len": 0.02, "pos": Vector3(0, 0, -1.36), "mat": "dark"})
	tf["visuals"].append({"type": "lathe", "profile": [Vector2(-1.45, 0.0), Vector2(-1.3, 0.2), Vector2(-1.2, 0.22)], "mat": "metal"})
	# gondol motoru: kendi ön ağzından hava alır (gövde alığına gerek yok)
	(tf["modules"] as Array).append({"type": "intake", "area": 0.75})
	_defs["turbofan"] = tf
	# roket motoru: alık istemez, çok güçlü, yakıtı çok hızlı yakar
	_defs["rocket_engine"] = {
		"title": "R-200 Roket Motoru", "category": "motor", "mass": 480.0, "hp": 150.0, "cost": 3800,
		"size": Vector3(1.2, 1.2, 2.2),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.1, 0.62), Vector2(-0.2, 0.6), Vector2(0.2, 0.32)], "mat": "paint_dark"},
			{"type": "lathe", "profile": [Vector2(0.15, 0.26), Vector2(0.6, 0.4), Vector2(1.1, 0.58)], "mat": "metal"},
			{"type": "lathe", "name": "Exhaust", "profile": [Vector2(0, 0.55), Vector2(1.2, 0.6), Vector2(4.0, 0.42), Vector2(7.0, 0.0)], "pos": Vector3(0, 0, 1.1), "mat": "flame", "segments": 24},
			{"type": "lathe", "name": "ExhaustCore", "profile": [Vector2(0, 0.42), Vector2(0.8, 0.4), Vector2(2.6, 0.15), Vector2(3.4, 0.0)], "pos": Vector3(0, 0, 1.1), "mat": "flame_core", "segments": 20},
		],
		"colliders": [{"type": "cyl", "r": 0.6, "len": 2.2}],
		"modules": [
			{"type": "engine", "max_thrust": 160000.0, "fuel_rate": 14.0, "spool_rate": 2.5, "rocket": true},
			{"type": "body_drag", "front_area": 1.1, "side_area": 2.6, "cd_front": 0.12},
		],
		"strength_kn": 600.0,
	}
	# turboprop: 4 kanatlı büyük pervane
	var tp: Dictionary = _defs["prop_engine"].duplicate(true)
	tp["title"] = "T-60 Turboprop (4 kanat)"
	tp["mass"] = 640.0
	tp["cost"] = 2600
	tp["size"] = Vector3(1.3, 1.3, 2.2)
	var vis := []
	for v: Dictionary in tp["visuals"]:
		if v.get("parent", "") != "Prop" and v.get("name", "") != "PropDisc":
			vis.append(v)
	vis[0]["profile"] = [Vector2(-0.5, 0.5), Vector2(0.4, 0.64), Vector2(1.6, 0.6)]
	for i in 4:
		var a := deg_to_rad(i * 90.0)
		vis.append({"type": "box", "parent": "Prop", "size": Vector3(0.2, 1.55, 0.05), "pos": Vector3(-sin(a), cos(a), 0.0) * 0.8 + Vector3(0, 0, -0.62), "rot": Vector3(0, 16, i * 90.0), "mat": "dark"})
	vis.append({"type": "cyl", "name": "PropDisc", "axis": "z", "r": 1.6, "len": 0.01, "pos": Vector3(0, 0, -0.62), "mat": "prop_disc"})
	tp["visuals"] = vis
	tp["modules"][0] = {"type": "engine", "max_thrust": 58000.0, "fuel_rate": 0.7, "spool_rate": 0.45, "prop": true, "prop_vmax": 200.0}
	tp["modules"][1] = {"type": "intake", "area": 0.45}
	_defs["turboprop"] = tp
	# kanatlar
	_defs["wing_trapez"] = _wing("Trapez Kanat (çevik)", Vector3(3.4, 0.16, 2.6), 300.0, 8.5, 3.2, 18.0,
		{"span": 3.4, "root": 2.6, "tip": 1.2, "sweep": 1.3, "thick": 0.08})
	_defs["wing_trapez"]["strength_kn"] = 380.0
	_defs["wing_glider"] = _wing("Uzun Kanat (planör, verimli)", Vector3(8.0, 0.18, 1.4), 300.0, 11.0, 11.0, 13.0,
		{"span": 8.0, "root": 1.6, "tip": 0.8, "sweep": 0.2, "thick": 0.1})
	_defs["wing_glider"]["strength_kn"] = 150.0
	_defs["winglet"] = _wing("Kanat Ucu Kanatçığı (winglet)", Vector3(0.9, 0.08, 0.8), 25.0, 0.6, 2.0, 20.0,
		{"span": 0.9, "root": 0.8, "tip": 0.35, "sweep": 0.45, "thick": 0.06})
	# çene alığı (gövdenin altına)
	_defs["intake_chin"] = {
		"title": "Çene Hava Alığı (gövde altı)", "category": "hava alığı", "mass": 140.0, "hp": 90.0, "cost": 800,
		"size": Vector3(1.0, 0.7, 2.2),
		"visuals": [
			{"type": "box", "size": Vector3(1.0, 0.62, 2.2), "mat": "paint"},
			{"type": "box", "size": Vector3(0.86, 0.5, 0.02), "pos": Vector3(0, 0, -1.1), "mat": "dark"},
			{"type": "box", "size": Vector3(1.02, 0.06, 0.4), "pos": Vector3(0, -0.29, -0.95), "rot": Vector3(10, 0, 0), "mat": "paint_dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(1.0, 0.62, 2.2)}],
		"modules": [
			{"type": "intake", "area": 0.85},
			{"type": "body_drag", "front_area": 0.2, "side_area": 1.3, "cd_front": 0.15, "cd_side": 0.6},
		],
	}
