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
		if m.has("ac_offset"):
			m["ac_offset"] = (m["ac_offset"] as Vector3) * s
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
		] + _missile_visuals(2.9, 0.07, false),
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

	# radar güdümlü orta menzil füzesi: radarla seçilmiş (F4) hedefe atılır, uçak radarı izlerken
	# yarı aktif güdüm, son 7 km'de kendi radarını açar (bağımsız). Fişek/chaff ve dik kaçış (çentik) kandırabilir.
	_defs["radar_missile_rail"] = {
		"title": "RF-1 Radar Füzesi + Ray", "category": "silah", "mass": 30.0, "hp": 60.0, "cost": 3400,
		"size": Vector3(0.36, 0.45, 3.7),
		"visuals": [
			{"type": "box", "size": Vector3(0.07, 0.2, 2.0), "pos": Vector3(0, 0.06, 0), "mat": "paint_dark"},
		] + _missile_visuals(3.6, 0.09, true),
		"colliders": [{"type": "box", "size": Vector3(0.24, 0.4, 3.6)}],
		"modules": [
			{"type": "missile", "guidance": "radar"},
			{"type": "body_drag", "front_area": 0.07, "side_area": 0.55, "cd_front": 0.2, "cd_side": 0.6},
		],
	}


	# --- karşı tedbir ve dış yükler
	_defs["flare_pod"] = {
		"title": "Karşı Tedbir Fişekliği (flare + chaff)", "category": "savunma", "mass": 70.0, "hp": 60.0, "cost": 1100,
		"size": Vector3(0.36, 0.26, 1.0), "chaff_capable": true,
		"visuals": [
			{"type": "box", "size": Vector3(0.36, 0.22, 1.0), "mat": "paint_dark"},
			{"type": "box", "size": Vector3(0.3, 0.02, 0.38), "pos": Vector3(0, -0.115, -0.2), "mat": "dark"},
			{"type": "box", "size": Vector3(0.3, 0.02, 0.38), "pos": Vector3(0, -0.115, 0.22), "mat": "metal"},
			{"type": "box", "size": Vector3(0.37, 0.05, 0.08), "pos": Vector3(0, 0, -0.42), "mat": "yellow"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.36, 0.24, 1.0)}],
		"modules": [
			{"type": "flare", "count": 30, "chaff": 20},
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
		] + _intake_visuals(Vector3.ZERO, 0.21, 0.36, -0.8, 1.6),
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


## Pervaneli motor kaportasının ön ve arka kapakları: kaporta açık uçlu bir boru — önde
## pervane göbeği ile kaporta arasında koyu motor yüzü (soğutma girişi), arkada egzoz kapağı;
## yoksa içinden gökyüzü görünür. Adları "Cap…": turboprop kendi boyuna göre yeniden kurar.
static func _cowl_caps(front_z: float, front_r: float, rear_z: float, rear_r: float) -> Array:
	return [
		{"type": "cyl", "name": "CapFront", "axis": "z", "r": front_r, "len": 0.03, "pos": Vector3(0, 0, front_z), "mat": "dark"},
		{"type": "lathe", "name": "CapFrontRing", "profile": [Vector2(front_z + 0.02, front_r * 0.98), Vector2(front_z + 0.03, front_r * 0.6)], "mat": "metal"},
		{"type": "lathe", "name": "CapRear", "profile": [Vector2(rear_z, rear_r), Vector2(rear_z + 0.25, rear_r * 0.55), Vector2(rear_z + 0.3, 0.0)], "mat": "paint_dark"},
	]


## Sivil / yardım parçaları: pervaneli motor, yolcu kabini, kargo bölmesi, düz kanat.
static func _register_civil() -> void:
	var prop_visuals := [
		{"type": "lathe", "profile": [Vector2(-0.5, 0.5), Vector2(0.2, 0.62), Vector2(0.8, 0.6)], "mat": "paint"},
		{"type": "lathe", "name": "Prop", "profile": [Vector2(-0.95, 0.0), Vector2(-0.8, 0.14), Vector2(-0.55, 0.22), Vector2(-0.5, 0.22)], "mat": "metal"},
	]
	_defs["prop_engine"] = {
		"title": "P-26 Pervaneli Motor", "category": "motor", "mass": 380.0, "hp": 140.0, "cost": 1200,
		"size": Vector3(1.25, 1.25, 1.6),
		"visuals": prop_visuals + _prop_blades() + [{"type": "cyl", "name": "PropDisc", "axis": "z", "r": 1.2, "len": 0.01, "pos": Vector3(0, 0, -0.62), "mat": "prop_disc"}]
			+ _cowl_caps(-0.48, 0.49, 0.79, 0.59),
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
	# nakliye uçağı (C-130 gibi): makaralı zeminli ağır kargo bölmesi ve arkası yükselen rampa
	var hold := (_defs["cargo_bay"] as Dictionary).duplicate(true)
	hold["title"] = "Ağır Kargo Bölmesi (10 sandık)"
	hold["mass"] = 620.0
	hold["hp"] = 220.0
	hold["cost"] = 1600
	for sx in [-0.25, 0.25]:      # makaralı yük rayları (altta, görünür şerit)
		hold["visuals"].append({"type": "box", "size": Vector3(0.06, 0.03, 2.8), "pos": Vector3(sx, -0.63, 0), "mat": "metal"})
	hold["visuals"].append({"type": "box", "size": Vector3(0.04, 0.22, 0.22), "pos": Vector3(-0.645, 0.18, -1.0), "mat": "screen", "color": Color(0.2, 0.3, 0.4)})
	hold["modules"][0] = {"type": "cargo", "crates": 10}
	_defs["cargo_bay_heavy"] = hold
	_defs["cargo_ramp"] = {
		"title": "Kargo Rampası (arka yük kapısı, 2 sandık)", "category": "gövde", "mass": 380.0, "hp": 170.0, "cost": 1100,
		"size": Vector3(1.3, 1.3, 3.0),
		"visuals": [
			# arkaya doğru incelen kuyruk bölümü; altta yukarı kalkık rampa kapısı
			{"type": "lathe", "profile": [Vector2(-1.5, 0.65), Vector2(-0.6, 0.64), Vector2(0.4, 0.55), Vector2(1.2, 0.4), Vector2(1.5, 0.32)], "mat": "paint", "color": Color(0.42, 0.46, 0.36)},
			{"type": "box", "size": Vector3(0.95, 0.05, 2.3), "pos": Vector3(0, -0.47, 0.05), "rot": Vector3(-9.0, 0, 0), "mat": "paint_dark"},
			{"type": "box", "size": Vector3(1.0, 0.04, 0.04), "pos": Vector3(0, -0.63, -1.1), "mat": "dark"},
			{"type": "box", "size": Vector3(0.05, 0.03, 2.2), "pos": Vector3(0, -0.5, 0.05), "rot": Vector3(-9.0, 0, 0), "mat": "yellow"},
		],
		"colliders": [{"type": "cyl", "r": 0.55, "len": 3.0}],
		"modules": [
			{"type": "cargo", "crates": 2},
			{"type": "body_drag", "front_area": 1.33, "side_area": 3.2, "cd_front": 0.03},
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


## Raydaki füze: gövde, arayıcı başlık, orta (ya da ön) ve kuyruk kanatçıkları (X düzeni).
## Hepsi "Missile" düğümünün altında: fırlatınca birlikte gizlenir.
## Uçuştaki füze (Missile) de aynı modeli kullanır: raydaki ile havadaki aynı görünür.
static func _missile_visuals(length: float, r: float, radar: bool, body := Color(0.88, 0.89, 0.87)) -> Array:
	var h := length * 0.5
	var nose := 0.4 if radar else 0.32
	var out := [
		{"type": "lathe", "name": "Missile", "segments": 20, "pos": Vector3(0, -0.05 - r, 0), "mat": "paint", "color": body,
			"profile": [Vector2(-h + nose - 0.02, r * 0.95), Vector2(-h + nose + 0.06, r), Vector2(h - 0.12, r), Vector2(h - 0.02, r * 0.82), Vector2(h, r * 0.72)]},
		# burun: IR'de koyu cam kubbe (arayıcı), radarda boyalı sivri radom
		{"type": "lathe", "parent": "Missile", "segments": 20, "mat": "radome" if radar else "dark",
			"profile": _ogive(-h, nose, r * 0.95)},
		# bantlar: sarı (canlı harp başlığı), kahverengi (roket motoru), kablo kanalı, metal lüle
		{"type": "cyl", "parent": "Missile", "r": r * 1.02, "len": 0.05, "pos": Vector3(0, 0, -h + nose + 0.22), "mat": "yellow"},
		{"type": "cyl", "parent": "Missile", "r": r * 1.02, "len": 0.04, "pos": Vector3(0, 0, -h + length * 0.45), "mat": "paint", "color": Color(0.48, 0.32, 0.16)},
		{"type": "box", "parent": "Missile", "size": Vector3(r * 0.35, r * 0.3, length * 0.55), "pos": Vector3(0, r * 0.98, 0.05), "mat": "paint", "color": body.darkened(0.12)},
		{"type": "lathe", "parent": "Missile", "segments": 16, "mat": "metal",
			"profile": [Vector2(h - 0.02, r * 0.72), Vector2(h + 0.06, r * 0.62), Vector2(h + 0.06, r * 0.5), Vector2(h - 0.04, r * 0.45)]},
	]
	# X düzeni kanatçıklar: ön (IR: küçük kanard, radar: geniş orta kanat) ve kuyruk; her biri
	# kökü gövdede, uca doğru incelen ok açılı ince yüzey (4 kol ayrı ayrı)
	var fin_z := [-h + nose + 0.45, h - 0.24] if not radar else [-0.12, h - 0.24]
	var fin_span := [r * 2.0, r * 2.6] if not radar else [r * 2.8, r * 2.4]
	var fin_chord := [0.2, 0.36] if not radar else [0.62, 0.34]
	for i in 2:
		for k in 4:
			var roll := 45.0 + 90.0 * k
			var dir := Vector3(cos(deg_to_rad(roll)), sin(deg_to_rad(roll)), 0.0)
			out.append({"type": "wing", "parent": "Missile", "span": fin_span[i], "root": fin_chord[i], "tip": fin_chord[i] * 0.32,
				"sweep": fin_chord[i] * 0.6, "thick": 0.05, "pos": Vector3(0, 0, fin_z[i]) + dir * (r * 0.9 + fin_span[i] * 0.5),
				"rot": Vector3(0, 0, roll), "mat": "paint", "color": body.darkened(0.06)})
	return out


## Hava alığı kabuğu: oval ağız (rx × ry), ince dudak, içe doğru kararan kanal ve gövdeye
## sivrilerek karışan arka kaporta. z0 = ağız (ön), length = toplam boy.
static func _intake_visuals(center: Vector3, rx: float, ry: float, z0: float, length: float) -> Array:
	var ys := ry / rx
	return [
		{"type": "lathe", "segments": 28, "y_scale": ys, "pos": center, "mat": "paint", "profile": [
			Vector2(z0, rx * 0.9), Vector2(z0 + 0.05, rx), Vector2(z0 + length * 0.4, rx * 1.03),
			Vector2(z0 + length * 0.75, rx * 0.78), Vector2(z0 + length, rx * 0.12)]},
		# dudak: ağzın önündeki halka yüz
		{"type": "lathe", "segments": 28, "y_scale": ys, "pos": center, "mat": "paint_dark",
			"profile": [Vector2(z0, rx * 0.8), Vector2(z0, rx * 0.9)]},
		# kanal: içeri daralan koyu huni
		{"type": "lathe", "segments": 28, "y_scale": ys, "pos": center, "mat": "dark",
			"profile": [Vector2(z0, rx * 0.8), Vector2(z0 + length * 0.3, rx * 0.55), Vector2(z0 + length * 0.32, 0.0)]},
	]


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
	# menteşe tarafı biraz öne uzar ve kanadın firar kenarının altına girer: arada boşluk görünmesin
	var tuck := 0.14
	visual["root"] = float(visual["root"]) + tuck
	visual["tip"] = float(visual["tip"]) + tuck
	visual["type"] = "wing"
	visual["mat"] = "paint_dark"
	visual["pos"] = Vector3(0, 0, -hinge_z - tuck * 0.5)
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
static func _cockpit(title: String, layout: String, mass: float, cost: int, canopy_style := "") -> Dictionary:
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
		{"type": "lathe", "profile": [Vector2(open_from, 0.65), Vector2(open_to, 0.65)], "mat": "paint", "color": paint, "arc_from": arc_from, "arc_to": arc_to, "inner": 1.0},
		{"type": "lathe", "profile": [Vector2(open_to, 0.65), Vector2(1.5, 0.65)], "mat": "paint", "color": paint},
		{"type": "lathe", "profile": [Vector2(open_from, 0.62), Vector2(open_to, 0.62)], "mat": "interior", "color": Color(0.11, 0.115, 0.12), "arc_from": arc_from, "arc_to": arc_to},
		{"type": "cyl", "r": 0.62, "len": 0.02, "pos": Vector3(0, 0, open_from), "mat": "interior", "color": Color(0.11, 0.115, 0.12)},
		{"type": "cyl", "r": 0.62, "len": 0.02, "pos": Vector3(0, 0, open_to), "mat": "interior", "color": Color(0.11, 0.115, 0.12)},
		{"type": "box", "size": Vector3(1.0 if civil else 0.8, 0.04, 1.7), "pos": Vector3(0, 0.05, -0.1) + d, "noscale": true, "mat": "dark"},
		# gösterge paneli (pilota bakar, üstü geriye yatık), göz siperi, panel altı
		{"type": "box", "size": Vector3(1.22 if civil else 0.74, 0.36, 0.05), "pos": Vector3(0, 0.69, pz - 0.035) + d, "noscale": true, "rot": Vector3(-15, 0, 0), "mat": "interior"},
		{"type": "box", "size": Vector3(1.26 if civil else 0.8, 0.05, 0.2 if civil else 0.3), "pos": Vector3(0, 0.89, pz - (0.13 if civil else 0.17)) + d, "noscale": true, "mat": "dark"},
		{"type": "box", "size": Vector3(1.1 if civil else 0.7, 0.3, 0.4), "pos": Vector3(0, 0.38, pz - 0.2) + d, "noscale": true, "mat": "interior"},
	]
	if civil:
		for sx in [-0.3, 0.3]:
			v.append_array(_seat_visuals(Vector3(sx, 0, 0.12) + d, 8.0, Color(0.32, 0.22, 0.15), 0.82))
			# pedallar CockpitModule'de (sapma girdisiyle hareket eder)
		v.append({"type": "box", "size": Vector3(1.32, 0.12, 2.9), "pos": Vector3(0, -0.05, 0), "mat": "paint", "color": Color(0.15, 0.35, 0.6)})
	else:
		v.append_array(_seat_visuals(Vector3(0, 0, 0.18) + d, 12.0, Color(0.11, 0.11, 0.12)))
		# yan konsollar, kanopi rayları, yan hava girişleri (pedallar CockpitModule'de, hareketli)
		for sx in [-0.36, 0.36]:
			v.append({"type": "box", "size": Vector3(0.14, 0.06, 0.62), "pos": Vector3(sx, 0.46, -0.04) + d, "noscale": true, "mat": "interior"})
			v.append({"type": "box", "size": Vector3(0.05, 0.05, 1.75), "pos": Vector3(sx * 1.22, 0.49, 0.12), "mat": "paint_dark"})
			v.append_array(_intake_visuals(Vector3(sx * 2.05, -0.08, 0.0), 0.21, 0.39, 0.09, 1.41))
	return {
		"title": title, "category": "kokpit", "mass": mass, "hp": 250.0, "cost": cost,
		"size": Vector3(1.3, 1.3, 3.0),
		"visuals": v,
		"colliders": [{"type": "cyl", "r": 0.65, "len": 3.0}],
		"modules": [
			{"type": "cockpit", "layout": layout, "canopy_style": canopy_style},
			{"type": "intake", "area": 0.6 if not civil else 0.0},
			{"type": "fuel_tank", "capacity": 150.0},
			{"type": "body_drag", "front_area": 1.33, "side_area": 3.9, "cd_front": 0.12 if not civil else 0.06},
		],
	}


## Yolcu uçağı burun kokpiti: kokpit burnun kendisidir — sivri burun, ön üst yüzeyde gövdeye
## gömülü (akışla aynı yüzeyde) ön camlar ve çerçeve dikmeleri; açılır kanopi yok, giriş yandaki
## kapıdan. İç düzen sivil (yan yana iki pilot, boynuz lövyeler, 4 ekran), gövdeye daha gömülü.
## Fırlatma koltuğu yoktur. Arka ucu yolcu kabiniyle aynı çapta (0.65).
static func _airliner_cockpit() -> Dictionary:
	var paint := Color(0.92, 0.93, 0.94)
	var drop := -0.4                    # iç düzen (CockpitModule "drop" ile aynı): baş tavana değmesin
	var d := Vector3(0, drop, 0)
	var pz := -0.42
	var tip := [Vector2(-2.0, 0.0), Vector2(-1.9, 0.17), Vector2(-1.75, 0.3), Vector2(-1.55, 0.41)]
	# cam bandı burnun ucundan gösterge panelinin hemen önüne kadar (ölçekli kokpitte de pilota yakın)
	var band := [Vector2(-1.55, 0.41), Vector2(-1.3, 0.5), Vector2(-1.05, 0.57), Vector2(-0.8, 0.62), Vector2(-0.55, 0.645), Vector2(-0.3, 0.65)]
	var body := [Vector2(-0.3, 0.65), Vector2(2.0, 0.65)]
	var inset := func(prof: Array, dr: float) -> Array:
		var out := []
		for p: Vector2 in prof:
			out.append(Vector2(p.x, maxf(p.y + dr, 0.0)))
		return out
	var v := [
		{"type": "lathe", "profile": tip, "mat": "paint", "color": paint},
		# ön cam bandı: alt kısım boya, üst 150° cam (aynı yüzeyde, önde ve yanlarda), cam dikmeleri koyu
		{"type": "lathe", "profile": band, "mat": "paint", "color": paint, "arc_from": 165.0, "arc_to": 375.0, "inner": 1.0},
		{"type": "lathe", "profile": band, "mat": "glass", "color": Color(0.1, 0.16, 0.24, 0.42), "arc_from": 15.0, "arc_to": 165.0},
		{"type": "lathe", "profile": body, "mat": "paint", "color": paint, "inner": 1.0},
		# iç yüzeyler: cam bandının altı, kabin duvarı, arka perde ve ön kapak
		{"type": "lathe", "profile": inset.call(band, -0.03), "mat": "interior", "arc_from": 165.0, "arc_to": 375.0},
		{"type": "lathe", "profile": [Vector2(-0.3, 0.62), Vector2(0.95, 0.62)], "mat": "interior"},
		{"type": "cyl", "r": 0.62, "len": 0.02, "pos": Vector3(0, 0, 0.95), "mat": "interior"},
		{"type": "cyl", "r": 0.39, "len": 0.02, "pos": Vector3(0, 0, -1.55), "mat": "interior"},
		# taban, gösterge paneli, göz siperi, panel altı (insan boyu, ölçeklenmez)
		{"type": "box", "size": Vector3(1.0, 0.04, 1.7), "pos": Vector3(0, 0.05, -0.1) + d, "noscale": true, "mat": "dark"},
		{"type": "box", "size": Vector3(1.22, 0.36, 0.05), "pos": Vector3(0, 0.69, pz - 0.035) + d, "noscale": true, "rot": Vector3(-15, 0, 0), "mat": "interior"},
		{"type": "box", "size": Vector3(1.26, 0.05, 0.2), "pos": Vector3(0, 0.89, pz - 0.13) + d, "noscale": true, "mat": "dark"},
		{"type": "box", "size": Vector3(1.1, 0.3, 0.4), "pos": Vector3(0, 0.38, pz - 0.2) + d, "noscale": true, "mat": "interior"},
		# yanda giriş kapısı ve yan cam, gövde bandı (kabinle aynı renk)
		{"type": "box", "size": Vector3(0.04, 0.95, 0.6), "pos": Vector3(-0.645, -0.02, 1.35), "mat": "paint_dark"},
		{"type": "box", "size": Vector3(1.32, 0.12, 2.6), "pos": Vector3(0, -0.05, 0.7), "mat": "paint", "color": Color(0.15, 0.35, 0.6)},
	]
	# cam dikmeleri: ortada ve iki yanda (cam bandının üstünde, ince koyu şeritler)
	for a in [[87.5, 92.5], [52.0, 55.0], [125.0, 128.0], [15.0, 18.0], [162.0, 165.0]]:
		v.append({"type": "lathe", "profile": inset.call(band, 0.006), "mat": "paint_dark", "arc_from": a[0], "arc_to": a[1]})
	for sx in [-0.3, 0.3]:
		v.append_array(_seat_visuals(Vector3(sx, 0, 0.12) + d, 8.0, Color(0.32, 0.22, 0.15), 0.82))
	return {
		"title": "Yolcu Uçağı Burun Kokpiti (2 pilot, fırlatma yok)", "category": "kokpit", "mass": 980.0, "hp": 280.0, "cost": 1800,
		"fcs": "fbw", "g_limit": 2.5,   # yolcu uçağı FBW: yolcuyu ve gövdeyi korur, 2.5 G üstüne çekmez
		"size": Vector3(1.3, 1.3, 4.0),
		"visuals": v,
		"colliders": [{"type": "cyl", "r": 0.65, "len": 2.8, "pos": Vector3(0, 0, 0.6)}, {"type": "cyl", "r": 0.45, "len": 1.2, "pos": Vector3(0, 0, -1.4)}],
		"modules": [
			{"type": "cockpit", "layout": "civil", "canopy_style": "airliner", "drop": drop, "no_eject": true},
			{"type": "fuel_tank", "capacity": 150.0},
			{"type": "body_drag", "front_area": 1.33, "side_area": 4.8, "cd_front": 0.04},
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
	# egzoz dumanı: eski tip turbojetler ve darbeli jet duman bırakır, turbofan temiz yanar
	for spec in [["jet_engine", 0.35], ["jet_engine_small", 0.5], ["jet_engine_big", 0.25]]:
		if _defs.has(spec[0]):
			((_defs[spec[0]]["modules"] as Array)[0] as Dictionary)["smoke"] = spec[1]
	# yolcu / nakliye uçakları için uzun bacaklı ağır takımlar: büyük gondol motorları yere değmesin
	var gh := _gear("Ağır Ana İniş Takımı (4 teker)", 420.0, 0.42, 420000.0, 52000.0, false)
	gh["size"] = Vector3(1.2, 2.0, 1.4)
	(gh["modules"] as Array)[0]["rest_length"] = 2.0
	gh["visuals"] = [
		{"type": "cyl", "name": "Strut", "axis": "y", "r": 0.13, "len": 2.0, "pos": Vector3(0, -1.0, 0), "mat": "metal"},
		{"type": "cyl", "axis": "y", "r": 0.17, "len": 0.8, "pos": Vector3(0, -0.4, 0), "mat": "paint_dark"},
		# "Wheel" düğümü (x ekseninde silindir) Z çevresinde 90° dönük: çocukları onun yerel
		# çerçevesinde — yerel y = dünya -x (aks yönü), yerel x = dünya y. Dünya (wx, 0, wz) → (0, -wx, wz).
		{"type": "cyl", "name": "Wheel", "axis": "x", "r": 0.1, "len": 0.72, "pos": Vector3(0, -2.0, 0), "mat": "metal"},
		{"type": "box", "parent": "Wheel", "size": Vector3(0.12, 0.2, 1.5), "mat": "metal"},
	]
	for wz in [-0.6, 0.6]:
		for wx in [-0.24, 0.24]:
			gh["visuals"].append({"type": "cyl", "parent": "Wheel", "axis": "y", "r": 0.42, "len": 0.28, "pos": Vector3(0, -wx, wz), "mat": "rubber"})
			gh["visuals"].append({"type": "cyl", "parent": "Wheel", "axis": "y", "r": 0.24, "len": 0.3, "pos": Vector3(0, -wx, wz), "mat": "metal"})
	gh["strength_kn"] = 160.0
	gh["cost"] = 1200
	_defs["gear_main_heavy"] = gh
	var gn := _gear("Ağır Burun Takımı (çift teker)", 160.0, 0.32, 150000.0, 20000.0, true)
	gn["size"] = Vector3(0.8, 1.8, 0.8)
	(gn["modules"] as Array)[0]["rest_length"] = 1.8
	gn["visuals"] = [
		{"type": "cyl", "name": "Strut", "axis": "y", "r": 0.1, "len": 1.8, "pos": Vector3(0, -0.9, 0), "mat": "metal"},
		{"type": "cyl", "axis": "y", "r": 0.13, "len": 0.6, "pos": Vector3(0, -0.3, 0), "mat": "paint_dark"},
		{"type": "cyl", "name": "Wheel", "axis": "x", "r": 0.12, "len": 0.6, "pos": Vector3(0, -1.8, 0), "mat": "metal"},
	]
	for wx in [-0.19, 0.19]:   # çocuklar dönük "Wheel" çerçevesinde (yukarıdaki ağır ana takıma bak)
		gn["visuals"].append({"type": "cyl", "parent": "Wheel", "axis": "y", "r": 0.32, "len": 0.2, "pos": Vector3(0, -wx, 0), "mat": "rubber"})
		gn["visuals"].append({"type": "cyl", "parent": "Wheel", "axis": "y", "r": 0.18, "len": 0.22, "pos": Vector3(0, -wx, 0), "mat": "metal"})
	gn["strength_kn"] = 70.0
	gn["cost"] = 600
	_defs["gear_nose_heavy"] = gn
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
		if v.get("parent", "") != "Prop" and v.get("name", "") != "PropDisc" and not String(v.get("name", "")).begins_with("Cap"):
			vis.append(v)
	vis[0]["profile"] = [Vector2(-0.5, 0.5), Vector2(0.4, 0.64), Vector2(1.6, 0.6)]
	vis.append_array(_cowl_caps(-0.48, 0.49, 1.6, 0.6))   # uzun kaportanın ön yüzü ve arka kapağı
	for i in 4:
		var a := deg_to_rad(i * 90.0)
		vis.append({"type": "box", "parent": "Prop", "size": Vector3(0.2, 1.55, 0.05), "pos": Vector3(-sin(a), cos(a), 0.0) * 0.8 + Vector3(0, 0, -0.62), "rot": Vector3(0, 16, i * 90.0), "mat": "dark"})
	vis.append({"type": "cyl", "name": "PropDisc", "axis": "z", "r": 1.6, "len": 0.01, "pos": Vector3(0, 0, -0.62), "mat": "prop_disc"})
	tp["visuals"] = vis
	tp["modules"][0] = {"type": "engine", "max_thrust": 58000.0, "fuel_rate": 0.7, "spool_rate": 0.45, "prop": true, "prop_vmax": 200.0}
	tp["modules"][1] = {"type": "intake", "area": 0.45}
	_defs["turboprop"] = tp
	_register_engines()
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
		] + _intake_visuals(Vector3.ZERO, 0.5, 0.3, -1.1, 2.2),
		"colliders": [{"type": "box", "size": Vector3(1.0, 0.62, 2.2)}],
		"modules": [
			{"type": "intake", "area": 0.85},
			{"type": "body_drag", "front_area": 0.2, "side_area": 1.3, "cd_front": 0.15, "cd_side": 0.6},
		],
	}
	_register_systems()


## Farklı çalışan motorlar: ramjet (yalnız hızlıyken), itki yönlendirmeli (TVC), darbeli jet
## (ucuz, yavaş uçak için), katı yakıtlı kalkış roketi (JATO, yüzeye takılır, bir kez yanar).
static func _register_engines() -> void:
	_defs["ramjet"] = {
		"title": "RJ-30 Ramjet (Mach 1.3+)", "category": "motor", "mass": 700.0, "hp": 160.0, "cost": 4600,
		"size": Vector3(1.0, 1.0, 3.4),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.7, 0.38), Vector2(-1.45, 0.5), Vector2(1.3, 0.5), Vector2(1.7, 0.44)], "mat": "paint_dark"},
			{"type": "lathe", "profile": [Vector2(-2.1, 0.0), Vector2(-1.7, 0.16), Vector2(-1.3, 0.27), Vector2(-1.0, 0.27)], "mat": "metal"},
			{"type": "lathe", "profile": [Vector2(1.6, 0.44), Vector2(1.85, 0.4), Vector2(1.85, 0.34), Vector2(1.6, 0.34)], "mat": "metal"},
			{"type": "lathe", "name": "Exhaust", "profile": [Vector2(0, 0.36), Vector2(0.6, 0.34), Vector2(2.4, 0.24), Vector2(5.0, 0.0)], "pos": Vector3(0, 0, 1.85), "mat": "flame", "segments": 24},
			{"type": "lathe", "name": "ExhaustCore", "profile": [Vector2(0, 0.28), Vector2(0.5, 0.25), Vector2(1.5, 0.1), Vector2(2.2, 0.0)], "pos": Vector3(0, 0, 1.85), "mat": "flame_core", "segments": 20},
			{"type": "lathe", "name": "HeatHaze", "profile": [Vector2(0, 0.4), Vector2(2.5, 0.75), Vector2(7.0, 1.3)], "pos": Vector3(0, 0, 1.9), "mat": "heat_haze", "segments": 16},
		],
		"colliders": [{"type": "cyl", "r": 0.5, "len": 3.4}],
		"modules": [
			{"type": "engine", "max_thrust": 60000.0, "fuel_rate": 2.4, "spool_rate": 0.8, "ramjet": true},
			{"type": "intake", "area": 0.45},
			{"type": "body_drag", "front_area": 0.8, "side_area": 3.2, "cd_front": 0.08},
		],
		"strength_kn": 400.0,
	}

	var tv := _engine_variant("J-100V Vektörel İtki (TVC)", 1.1, 1500.0, 95000.0, 2.6, 0.55, 6800)
	(tv["modules"] as Array)[0]["gimbal_deg"] = 15.0
	# lüle ayrı düğüm: menteşesi lülenin ön ucunda, oradan döner
	var hinge := 1.15 * 1.1
	var noz: Dictionary = tv["visuals"][1]
	noz["name"] = "Nozzle"
	var prof: Array = []
	for p: Vector2 in noz["profile"]:
		prof.append(p - Vector2(hinge, 0.0))
	noz["profile"] = prof
	noz["pos"] = Vector3(0, 0, hinge)
	noz["mat"] = "dark"
	var disc: Dictionary = tv["visuals"][2]
	disc["parent"] = "Nozzle"
	disc["pos"] = (disc["pos"] as Vector3) - Vector3(0, 0, hinge)
	_defs["jet_engine_tvc"] = tv

	_defs["pulse_jet"] = {
		"title": "PJ-1 Darbeli Jet (ucuz, Mach 0.7'ye kadar)", "category": "motor", "mass": 170.0, "hp": 90.0, "cost": 700,
		"size": Vector3(0.7, 0.7, 3.2),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.6, 0.3), Vector2(-1.35, 0.34), Vector2(-0.5, 0.34), Vector2(-0.1, 0.2), Vector2(1.6, 0.19), Vector2(1.6, 0.15)], "mat": "paint_dark"},
			{"type": "cyl", "r": 0.3, "len": 0.04, "pos": Vector3(0, 0, -1.6), "mat": "dark"},
			{"type": "lathe", "name": "Exhaust", "profile": [Vector2(0, 0.18), Vector2(0.4, 0.2), Vector2(1.2, 0.1), Vector2(1.8, 0.0)], "pos": Vector3(0, 0, 1.6), "mat": "flame", "segments": 20},
			{"type": "lathe", "name": "ExhaustCore", "profile": [Vector2(0, 0.13), Vector2(0.6, 0.08), Vector2(1.0, 0.0)], "pos": Vector3(0, 0, 1.6), "mat": "flame_core", "segments": 16},
		],
		"colliders": [{"type": "cyl", "r": 0.34, "len": 3.2}],
		"modules": [
			{"type": "engine", "max_thrust": 15000.0, "fuel_rate": 0.9, "spool_rate": 1.5, "pulse_mach": 0.7, "smoke": 0.6},
			{"type": "intake", "area": 0.12},
			{"type": "body_drag", "front_area": 0.36, "side_area": 2.0, "cd_front": 0.1},
		],
		"strength_kn": 90.0,
	}

	_defs["jato"] = {
		"title": "JATO-1 Kalkış Roketi (10 sn, yüzeye)", "category": "motor", "mass": 45.0, "hp": 60.0, "cost": 400,
		"size": Vector3(0.5, 0.5, 1.8), "mount": "surface",
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-0.9, 0.0), Vector2(-0.75, 0.18), Vector2(-0.6, 0.24), Vector2(0.7, 0.24), Vector2(0.9, 0.16)], "mat": "metal"},
			{"type": "lathe", "profile": [Vector2(-0.35, 0.248), Vector2(-0.1, 0.248)], "mat": "yellow"},
			{"type": "lathe", "name": "Exhaust", "profile": [Vector2(0, 0.16), Vector2(0.5, 0.2), Vector2(1.8, 0.12), Vector2(3.0, 0.0)], "pos": Vector3(0, 0, 0.9), "mat": "flame", "segments": 16},
			{"type": "lathe", "name": "ExhaustCore", "profile": [Vector2(0, 0.12), Vector2(0.5, 0.1), Vector2(1.2, 0.0)], "pos": Vector3(0, 0, 0.9), "mat": "flame_core", "segments": 12},
		],
		"colliders": [{"type": "cyl", "r": 0.25, "len": 1.8}],
		"modules": [
			{"type": "booster", "thrust": 30000.0, "burn_time": 10.0, "propellant": 120.0},
			{"type": "body_drag", "front_area": 0.2, "side_area": 0.9, "cd_front": 0.15},
		],
		"strength_kn": 80.0,
	}


## Askı, güdümlü bomba, ECM, IRST, ikiz motor adaptörü, kuyruk konileri, ikmal probu, ayırıcı.
## "mount": hangarda nereye takılır — "pylon" (askıya), "tip" (kanat ucuna), "surface" (yüzeye dik).
static func _register_systems() -> void:
	# kanat / gövde altı askı noktası: silah ve dış yükler buna "tak" diye yapışır
	_defs["pylon"] = {
		"title": "Askı Noktası (pylon)", "category": "harici", "mass": 35.0, "hp": 80.0, "cost": 150,
		"size": Vector3(0.2, 0.4, 1.7), "pylon": true,
		"visuals": [
			{"type": "lathe", "segments": 12, "y_scale": 2.6, "mat": "paint_dark", "profile": [
				Vector2(-0.85, 0.0), Vector2(-0.55, 0.07), Vector2(0.4, 0.08), Vector2(0.85, 0.0)]},
			{"type": "box", "size": Vector3(0.05, 0.04, 0.9), "pos": Vector3(0, -0.2, 0), "mat": "metal"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.18, 0.4, 1.6)}],
		"modules": [{"type": "body_drag", "front_area": 0.03, "side_area": 0.5, "cd_front": 0.12, "cd_side": 0.6}],
	}

	# lazer güdümlü bomba: hedefleme podunun işaretlediği noktaya süzülür
	_defs["lgb_rail"] = {
		"title": "LGB-250 Lazer Güdümlü Bomba", "category": "silah", "mass": 30.0, "hp": 70.0, "cost": 2600,
		"size": Vector3(0.45, 0.7, 2.6),
		"visuals": [
			{"type": "box", "size": Vector3(0.08, 0.2, 1.0), "pos": Vector3(0, 0.12, 0), "mat": "paint_dark"},
			{"type": "lathe", "name": "Bomb", "segments": 16, "pos": Vector3(0, -0.18, 0), "mat": "paint", "color": Color(0.33, 0.37, 0.28),
				"profile": [Vector2(-1.1, 0.1), Vector2(-0.8, 0.16), Vector2(0.5, 0.17), Vector2(1.1, 0.07)]},
			# arayıcı başlık (cam burun) ve ön kanard / arka kanatlar
			{"type": "lathe", "parent": "Bomb", "segments": 16, "mat": "glass", "profile": _ogive(-1.3, 0.25, 0.1)},
			{"type": "cyl", "parent": "Bomb", "r": 0.11, "len": 0.25, "pos": Vector3(0, 0, -1.05), "mat": "metal"},
			{"type": "box", "parent": "Bomb", "size": Vector3(0.55, 0.01, 0.16), "pos": Vector3(0, 0, -0.85), "rot": Vector3(0, 0, 45), "mat": "paint_dark"},
			{"type": "box", "parent": "Bomb", "size": Vector3(0.55, 0.01, 0.16), "pos": Vector3(0, 0, -0.85), "rot": Vector3(0, 0, 135), "mat": "paint_dark"},
			{"type": "box", "parent": "Bomb", "size": Vector3(0.75, 0.01, 0.35), "pos": Vector3(0, 0, 0.85), "rot": Vector3(0, 0, 45), "mat": "paint", "color": Color(0.3, 0.34, 0.26)},
			{"type": "box", "parent": "Bomb", "size": Vector3(0.75, 0.01, 0.35), "pos": Vector3(0, 0, 0.85), "rot": Vector3(0, 0, 135), "mat": "paint", "color": Color(0.3, 0.34, 0.26)},
			{"type": "cyl", "parent": "Bomb", "r": 0.175, "len": 0.05, "pos": Vector3(0, 0, -0.55), "mat": "yellow"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.36, 0.5, 2.4)}],
		"modules": [
			{"type": "bomb", "guided": true},
			{"type": "body_drag", "front_area": 0.1, "side_area": 0.7, "cd_front": 0.25, "cd_side": 0.6},
		],
	}

	# elektronik karıştırıcı: düşman radarlarının menzilini kısaltır, ama seni yayın yapan
	# bir hedef yapar (düşman RWR'ı ve yapay zekâsı seni daha uzaktan fark eder)
	_defs["ecm_pod"] = {
		"title": "ECM Karıştırıcı Pod", "category": "savunma", "mass": 160.0, "hp": 80.0, "cost": 3800,
		"size": Vector3(0.4, 0.45, 2.4),
		"visuals": [
			{"type": "box", "size": Vector3(0.07, 0.16, 1.0), "pos": Vector3(0, 0.16, 0), "mat": "paint_dark"},
			{"type": "lathe", "segments": 16, "pos": Vector3(0, -0.05, 0), "mat": "paint_dark", "profile": [
				Vector2(-1.2, 0.0), Vector2(-1.0, 0.13), Vector2(-0.7, 0.18), Vector2(0.9, 0.18), Vector2(1.2, 0.08)]},
			{"type": "lathe", "segments": 16, "pos": Vector3(0, -0.05, 0), "mat": "radome", "profile": _ogive(-1.21, 0.4, 0.15)},
			{"type": "lathe", "segments": 16, "pos": Vector3(0, -0.05, 2.0), "mat": "radome", "profile": [
				Vector2(-1.1, 0.08), Vector2(-0.85, 0.0)]},
			{"type": "box", "size": Vector3(0.3, 0.02, 0.5), "pos": Vector3(0, -0.24, 0.2), "mat": "dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.36, 0.4, 2.3)}],
		"modules": [
			{"type": "ecm"},
			{"type": "body_drag", "front_area": 0.1, "side_area": 0.8, "cd_front": 0.15, "cd_side": 0.6},
		],
	}

	# kızılötesi arama-izleme: radar açmadan ısıyla hedef bulur (RWR'da görünmez)
	_defs["irst"] = {
		"title": "IRST Kızılötesi Arayıcı", "category": "sensör", "mass": 70.0, "hp": 60.0, "cost": 2800,
		"size": Vector3(0.45, 0.4, 0.7), "mount": "surface",
		"visuals": [
			{"type": "lathe", "segments": 20, "y_scale": 0.7, "mat": "paint", "profile": [
				Vector2(-0.35, 0.0), Vector2(-0.15, 0.2), Vector2(0.15, 0.2), Vector2(0.35, 0.05)]},
			{"type": "sphere", "r": 0.15, "pos": Vector3(0, 0.06, -0.2), "mat": "glass"},
			{"type": "sphere", "r": 0.12, "pos": Vector3(0, 0.06, -0.2), "mat": "screen_amber"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.4, 0.3, 0.7)}],
		"modules": [
			{"type": "irst", "range": 14000.0, "cone_deg": 55.0},
			{"type": "body_drag", "front_area": 0.05, "side_area": 0.15, "cd_front": 0.2, "cd_side": 0.6},
		],
	}

	# ikiz motor adaptörü: önü tek gövde, arkası yan yana iki motor yuvası
	_defs["twin_adapter"] = {
		"title": "İkiz Motor Adaptörü", "category": "gövde", "mass": 260.0, "hp": 180.0, "cost": 1100,
		"size": Vector3(2.7, 1.3, 2.0), "rear_nodes": [-0.255, 0.255],
		"visuals": [
			{"type": "lathe", "segments": 28, "mat": "paint", "profile": [Vector2(-1.0, 0.65), Vector2(0.0, 0.66)]},
			{"type": "lathe", "segments": 28, "pos": Vector3(-0.69, 0, 0), "mat": "paint", "profile": [
				Vector2(-0.8, 0.05), Vector2(-0.3, 0.5), Vector2(0.3, 0.64), Vector2(1.0, 0.65)]},
			{"type": "lathe", "segments": 28, "pos": Vector3(0.69, 0, 0), "mat": "paint", "profile": [
				Vector2(-0.8, 0.05), Vector2(-0.3, 0.5), Vector2(0.3, 0.64), Vector2(1.0, 0.65)]},
			{"type": "box", "size": Vector3(1.38, 0.9, 1.4), "pos": Vector3(0, 0, 0.3), "mat": "paint"},
			{"type": "box", "size": Vector3(0.2, 1.22, 0.04), "pos": Vector3(0, 0, 0.99), "mat": "paint_dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(2.6, 1.25, 2.0)}],
		"modules": [
			{"type": "fuel_tank", "capacity": 250.0},
			{"type": "body_drag", "front_area": 1.6, "side_area": 2.4, "cd_front": 0.05},
		],
	}

	# havada ikmal probu: tankerin sepetine sokunca yakıt alır (burnun yanına / üstüne)
	_defs["refuel_probe"] = {
		"title": "Havada İkmal Probu", "category": "harici", "mass": 45.0, "hp": 60.0, "cost": 900,
		"size": Vector3(0.3, 0.3, 2.2), "mount": "surface",
		"visuals": [
			{"type": "lathe", "segments": 12, "mat": "paint", "profile": [
				Vector2(-1.1, 0.0), Vector2(-1.05, 0.045), Vector2(-0.95, 0.06), Vector2(0.4, 0.07), Vector2(0.9, 0.13), Vector2(1.1, 0.08)]},
			{"type": "cyl", "r": 0.05, "len": 0.08, "pos": Vector3(0, 0, -0.98), "mat": "metal"},
			{"type": "box", "size": Vector3(0.12, 0.14, 0.7), "pos": Vector3(0, -0.06, 0.65), "mat": "paint_dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.2, 0.25, 2.1)}],
		"modules": [
			{"type": "refuel_probe"},
			{"type": "body_drag", "front_area": 0.02, "side_area": 0.25, "cd_front": 0.2, "cd_side": 0.6},
		],
	}

	# sınır tabaka ayırıcı: yan / alt alığın yanına; gövdenin yavaş havasını alıktan uzak tutar
	_defs["intake_splitter"] = {
		"title": "Sınır Tabaka Ayırıcı", "category": "hava alığı", "mass": 15.0, "hp": 40.0, "cost": 250,
		"size": Vector3(0.08, 0.7, 1.0), "mount": "surface",
		"visuals": [
			{"type": "box", "size": Vector3(0.03, 0.66, 0.9), "mat": "paint_dark"},
			{"type": "box", "size": Vector3(0.03, 0.62, 0.12), "pos": Vector3(0, 0, -0.5), "rot": Vector3(0, 30, 0), "mat": "metal"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.06, 0.66, 0.9)}],
		"modules": [{"type": "splitter"}],
	}

	# kanat ucu füze rayı: kanadın ucuna takılır, IR füze taşır ve uç plakası gibi indüklenen
	# direnci biraz azaltır
	_defs["wingtip_rail"] = {
		"title": "Kanat Ucu IR Füze Rayı", "category": "silah", "mass": 35.0, "hp": 60.0, "cost": 1700,
		"size": Vector3(0.24, 0.3, 3.0), "mount": "tip", "tip_device": true,
		"visuals": [
			{"type": "box", "size": Vector3(0.12, 0.16, 2.2), "pos": Vector3(0, 0.03, 0.1), "mat": "paint_dark"},
		] + _missile_visuals(2.9, 0.07, false),
		"colliders": [{"type": "box", "size": Vector3(0.22, 0.28, 2.9)}],
		"modules": [
			{"type": "missile"},
			{"type": "body_drag", "front_area": 0.04, "side_area": 0.45, "cd_front": 0.18, "cd_side": 0.6},
		],
	}
	_defs["winglet"]["tip_device"] = true
	# ayrı chaff kovanı (yalnız chaff, çok paket)
	_defs["chaff_pod"] = {
		"title": "Chaff Kovanı", "category": "savunma", "mass": 55.0, "hp": 50.0, "cost": 800, "chaff_capable": true,
		"size": Vector3(0.32, 0.24, 0.9),
		"visuals": [
			{"type": "box", "size": Vector3(0.32, 0.2, 0.9), "mat": "paint_dark"},
			{"type": "box", "size": Vector3(0.26, 0.02, 0.7), "pos": Vector3(0, -0.105, 0), "mat": "metal"},
			{"type": "box", "size": Vector3(0.33, 0.04, 0.06), "pos": Vector3(0, 0, -0.38), "mat": "paint", "color": Color(0.3, 0.55, 0.9)},
		],
		"colliders": [{"type": "box", "size": Vector3(0.32, 0.22, 0.9)}],
		"modules": [
			{"type": "flare", "count": 0, "chaff": 40},
			{"type": "body_drag", "front_area": 0.07, "side_area": 0.25, "cd_front": 0.3, "cd_side": 0.6},
		],
	}
	_register_shapes()
	_register_strike()


# ------------------------------------------------------------------ biçim parçaları

## Saldırı silahları ve bombardıman takımı: radar avcısı, seyir ve gemi savar füzeleri,
## süzülen / misket / 1000 kg bombalar, iç bomba bölmesi, kuyruk tareti.
static func _register_strike() -> void:
	_defs["harm_rail"] = {
		"title": "RA-1 Radar Avcısı Füze (HARM)", "category": "silah", "mass": 35.0, "hp": 60.0, "cost": 4200,
		"size": Vector3(0.4, 0.5, 4.2),
		"visuals": [
			{"type": "box", "size": Vector3(0.08, 0.22, 2.2), "pos": Vector3(0, 0.08, 0), "mat": "paint_dark"},
		] + _missile_visuals(4.1, 0.12, true),
		"colliders": [{"type": "box", "size": Vector3(0.3, 0.45, 4.1)}],
		"modules": [
			{"type": "missile", "guidance": "arm"},
			{"type": "body_drag", "front_area": 0.08, "side_area": 0.7, "cd_front": 0.2, "cd_side": 0.6},
		],
	}
	_defs["ship_missile_rail"] = {
		"title": "GS-1 Gemi Savar Füze", "category": "silah", "mass": 45.0, "hp": 70.0, "cost": 5200,
		"size": Vector3(0.6, 0.6, 4.8),
		"visuals": [
			{"type": "box", "size": Vector3(0.1, 0.22, 2.4), "pos": Vector3(0, 0.12, 0), "mat": "paint_dark"},
			{"type": "lathe", "name": "Missile", "segments": 16, "pos": Vector3(0, -0.2, 0), "mat": "paint", "color": Color(0.42, 0.45, 0.4),
				"profile": [Vector2(-2.3, 0.0), Vector2(-1.9, 0.15), Vector2(-1.6, 0.18), Vector2(2.3, 0.18)]},
			{"type": "box", "parent": "Missile", "size": Vector3(0.9, 0.02, 0.5), "pos": Vector3(0, 0, 0.3), "rot": Vector3(0, 0, 45), "mat": "paint_dark"},
			{"type": "box", "parent": "Missile", "size": Vector3(0.9, 0.02, 0.5), "pos": Vector3(0, 0, 0.3), "rot": Vector3(0, 0, 135), "mat": "paint_dark"},
			{"type": "box", "parent": "Missile", "size": Vector3(0.7, 0.02, 0.35), "pos": Vector3(0, 0, 2.0), "rot": Vector3(0, 0, 45), "mat": "paint_dark"},
			{"type": "box", "parent": "Missile", "size": Vector3(0.7, 0.02, 0.35), "pos": Vector3(0, 0, 2.0), "rot": Vector3(0, 0, 135), "mat": "paint_dark"},
			{"type": "box", "parent": "Missile", "size": Vector3(0.16, 0.06, 0.5), "pos": Vector3(0, -0.17, -0.6), "mat": "dark"},   # alık
		],
		"colliders": [{"type": "box", "size": Vector3(0.5, 0.55, 4.7)}],
		"modules": [
			{"type": "missile", "guidance": "ship"},
			{"type": "body_drag", "front_area": 0.12, "side_area": 0.9, "cd_front": 0.2, "cd_side": 0.6},
		],
	}
	_defs["cruise_missile_rail"] = {
		"title": "SF-1 Seyir Füzesi (110 km, GPS)", "category": "silah", "mass": 60.0, "hp": 90.0, "cost": 9000,
		"size": Vector3(0.9, 0.9, 5.4),
		"visuals": [
			{"type": "box", "size": Vector3(0.12, 0.26, 2.8), "pos": Vector3(0, 0.2, 0), "mat": "paint_dark"},
			{"type": "lathe", "name": "Missile", "segments": 18, "pos": Vector3(0, -0.2, 0), "mat": "paint", "color": Color(0.4, 0.43, 0.38),
				"profile": [Vector2(-2.6, 0.0), Vector2(-2.3, 0.2), Vector2(-1.9, 0.28), Vector2(2.4, 0.28), Vector2(2.6, 0.2)]},
			{"type": "box", "parent": "Missile", "size": Vector3(0.6, 0.03, 2.4), "pos": Vector3(0, 0.27, 0.2), "mat": "paint_dark"},   # katlı kanat
			{"type": "box", "parent": "Missile", "size": Vector3(0.22, 0.12, 0.7), "pos": Vector3(0, -0.28, 1.4), "mat": "dark"},     # motor alığı
			{"type": "box", "parent": "Missile", "size": Vector3(0.75, 0.02, 0.4), "pos": Vector3(0, 0, 2.3), "rot": Vector3(0, 0, 45), "mat": "paint_dark"},
			{"type": "box", "parent": "Missile", "size": Vector3(0.75, 0.02, 0.4), "pos": Vector3(0, 0, 2.3), "rot": Vector3(0, 0, 135), "mat": "paint_dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(0.7, 0.8, 5.3)}],
		"modules": [
			{"type": "missile", "guidance": "cruise"},
			{"type": "body_drag", "front_area": 0.25, "side_area": 1.6, "cd_front": 0.2, "cd_side": 0.6},
		],
	}
	for spec in [["glide_bomb", "SB-500 Süzülen Bomba (GPS, 25 km)", "glide", 1.25, Color(0.38, 0.4, 0.34), 3600],
			["cluster_bomb", "MB-400 Misket Bombası", "cluster", 1.2, Color(0.36, 0.38, 0.33), 1900],
			["heavy_bomb", "1000 kg Bomba", "heavy", 1.6, Color(0.3, 0.33, 0.26), 2400]]:
		var k: float = spec[3]
		var vis := [
			{"type": "box", "size": Vector3(0.1, 0.22, 1.2 * k), "pos": Vector3(0, 0.14 * k, 0), "mat": "paint_dark"},
			{"type": "lathe", "name": "Bomb", "segments": 16, "pos": Vector3(0, -0.18 * k, 0), "mat": "paint", "color": spec[4],
				"profile": [Vector2(-1.1 * k, 0.0), Vector2(-0.8 * k, 0.16 * k), Vector2(0.5 * k, 0.17 * k), Vector2(1.0 * k, 0.07 * k)]},
		]
		for i in 4:
			vis.append({"type": "box", "parent": "Bomb", "size": Vector3(0.02, 0.36 * k, 0.3 * k), "pos": Vector3(0, 0, 0.95 * k),
				"rot": Vector3(0, 0, 45 + i * 90), "mat": "paint", "color": spec[4]})
		if spec[2] == "glide":
			vis.append({"type": "box", "parent": "Bomb", "size": Vector3(0.5, 0.03, 1.6), "pos": Vector3(0, 0.2, -0.1), "mat": "paint_dark"})
		elif spec[2] == "cluster":
			vis.append({"type": "cyl", "parent": "Bomb", "r": 0.19 * k, "len": 0.04, "pos": Vector3(0, 0, -0.2), "mat": "yellow"})
		_defs[spec[0]] = {
			"title": spec[1], "category": "silah", "mass": 30.0, "hp": 70.0, "cost": spec[5],
			"size": Vector3(0.45 * k, 0.7 * k, 2.3 * k),
			"visuals": vis,
			"colliders": [{"type": "box", "size": Vector3(0.36 * k, 0.5 * k, 2.1 * k)}],
			"modules": [
				{"type": "bomb", "kind": spec[2]},
				{"type": "body_drag", "front_area": 0.1 * k * k, "side_area": 0.7 * k * k, "cd_front": 0.25, "cd_side": 0.6},
			],
		}

	# iç bomba bölmesi: gövde parçası, altında iki kapak (açılınca sürükleme + RCS)
	_defs["bomb_bay"] = {
		"title": "İç Bomba Bölmesi (8 × 250 kg)", "category": "gövde", "mass": 520.0, "hp": 200.0, "cost": 3000,
		"size": Vector3(1.3, 1.3, 3.6),
		"visuals": [
			{"type": "lathe", "profile": [Vector2(-1.8, 0.65), Vector2(1.8, 0.65)], "mat": "paint", "arc_from": -40.0, "arc_to": 220.0},
			{"type": "box", "size": Vector3(1.1, 0.04, 3.4), "pos": Vector3(0, 0.1, 0), "mat": "dark"},
			{"type": "box", "size": Vector3(0.04, 0.6, 3.4), "pos": Vector3(-0.5, -0.2, 0), "mat": "dark"},
			{"type": "box", "size": Vector3(0.04, 0.6, 3.4), "pos": Vector3(0.5, -0.2, 0), "mat": "dark"},
			{"type": "box", "name": "DoorL", "size": Vector3(0.02, 0.02, 0.02), "pos": Vector3(-0.5, -0.42, 0), "mat": "paint"},
			{"type": "box", "parent": "DoorL", "size": Vector3(0.5, 0.04, 3.4), "pos": Vector3(0.25, 0, 0), "mat": "paint"},
			{"type": "box", "name": "DoorR", "size": Vector3(0.02, 0.02, 0.02), "pos": Vector3(0.5, -0.42, 0), "mat": "paint"},
			{"type": "box", "parent": "DoorR", "size": Vector3(0.5, 0.04, 3.4), "pos": Vector3(-0.25, 0, 0), "mat": "paint"},
		],
		"colliders": [{"type": "cyl", "r": 0.65, "len": 3.6}],
		"modules": [
			{"type": "bomb_bay", "bombs": 8},
			{"type": "body_drag", "front_area": 1.33, "side_area": 4.6, "cd_front": 0.03},
		],
	}
	# AWACS radar diski: gövde üstünde iki ayak üstünde dönen disk, 80 km her yönü tarar
	_defs["awacs_dome"] = {
		"title": "AWACS Radar Diski (80 km, 360°)", "category": "sensör", "mass": 900.0, "hp": 150.0, "cost": 9000, "mount": "surface",
		"size": Vector3(5.0, 1.6, 5.0),
		"visuals": [
			{"type": "box", "size": Vector3(0.25, 1.0, 0.8), "pos": Vector3(0, -0.3, -0.8), "mat": "paint_dark"},
			{"type": "box", "size": Vector3(0.25, 1.0, 0.8), "pos": Vector3(0, -0.3, 0.8), "mat": "paint_dark"},
			{"type": "cyl", "name": "Dome", "axis": "y", "r": 2.5, "len": 0.5, "pos": Vector3(0, 0.45, 0), "mat": "paint", "color": Color(0.9, 0.9, 0.88)},
			{"type": "box", "parent": "Dome", "size": Vector3(4.6, 0.52, 0.6), "mat": "dark"},
		],
		"colliders": [{"type": "box", "size": Vector3(5.0, 1.0, 5.0), "pos": Vector3(0, 0.3, 0)}],
		"modules": [
			{"type": "radar", "range": 80000.0, "cone_deg": 180.0},
			{"type": "body_drag", "front_area": 1.3, "side_area": 2.5, "cd_front": 0.3},
		],
	}
	# kuyruk taret yuvası: gövdenin en arkasına; arkaya bakan çift namlulu otomatik taret
	_defs["tail_turret"] = {
		"title": "Kuyruk Tareti (otomatik topçu)", "category": "gövde", "mass": 320.0, "hp": 160.0, "cost": 2600,
		"size": Vector3(1.3, 1.3, 2.0),
		"visuals": [{"type": "lathe", "mat": "paint", "profile": [
			Vector2(-1.0, 0.65), Vector2(-0.2, 0.58), Vector2(0.6, 0.42), Vector2(1.0, 0.3), Vector2(1.0, 0.0)]}],
		"colliders": [{"type": "cyl", "r": 0.55, "len": 1.9}],
		"modules": [
			{"type": "tail_turret", "ammo": 1200},
			{"type": "body_drag", "front_area": 1.33, "side_area": 2.0, "cd_front": 0.04},
		],
	}


## Ayarlanabilir kanadın hazır biçimleri (yarım kanat, dünya ölçeğinden önceki birimlerle).
## sweep: dış panelin hücum kenarı ok açısı (°, eksi = ters ok); crank: kırılma noktası
## (açıklığın oranı, 0 = yok), crank_sweep: iç panelin ok açısı. Firar kenarı düz çizgi.
const WING_PRESETS := {
	"Delta": {"span": 4.5, "root": 6.0, "tip": 0.4, "sweep": 50.0, "thick": 0.045, "crank": 0.0, "crank_sweep": 0.0},
	"Kırık delta": {"span": 4.8, "root": 6.5, "tip": 0.6, "sweep": 40.0, "thick": 0.045, "crank": 0.35, "crank_sweep": 62.0},
	"Ok kanat": {"span": 5.0, "root": 3.4, "tip": 1.2, "sweep": 35.0, "thick": 0.05, "crank": 0.0, "crank_sweep": 0.0},
	"Trapez": {"span": 3.4, "root": 2.6, "tip": 1.2, "sweep": 27.0, "thick": 0.07, "crank": 0.0, "crank_sweep": 0.0},
	"Düz kanat": {"span": 5.5, "root": 2.0, "tip": 1.4, "sweep": 3.0, "thick": 0.11, "crank": 0.0, "crank_sweep": 0.0},
	"Ters ok": {"span": 4.6, "root": 2.8, "tip": 1.4, "sweep": -25.0, "thick": 0.06, "crank": 0.0, "crank_sweep": 0.0},
	"Uçan kanat": {"span": 8.0, "root": 6.0, "tip": 1.4, "sweep": 30.0, "thick": 0.11, "crank": 0.25, "crank_sweep": 55.0},
}


## Ayarlanabilir kanat parametrelerinden bölümler: [Vector3(x, hücum z, veter)], z merkezli.
static func wing_sections(p: Dictionary) -> Array:
	var span := clampf(float(p.get("span", 4.0)), 0.5, 14.0)
	var c0 := clampf(float(p.get("root", 3.0)), 0.3, 10.0)
	var c1 := clampf(float(p.get("tip", 1.2)), 0.05, c0 * 2.0)
	var sw := deg_to_rad(clampf(float(p.get("sweep", 25.0)), -45.0, 75.0))
	var k := clampf(float(p.get("crank", 0.0)), 0.0, 0.85)
	var le_tip := 0.0
	var secs: Array = [Vector3(0.0, 0.0, c0)]
	if k > 0.02:
		var le_k := tan(deg_to_rad(clampf(float(p.get("crank_sweep", 55.0)), -45.0, 80.0))) * k * span
		le_tip = le_k + tan(sw) * (1.0 - k) * span
		# firar kenarı kökten uca düz: kırılmadaki veter ondan çıkar
		var te_k := lerpf(c0, le_tip + c1, k)
		secs.append(Vector3(k * span, le_k, maxf(te_k - le_k, 0.1)))
	else:
		le_tip = tan(sw) * span
	secs.append(Vector3(span, le_tip, c1))
	# x: kök -span/2; z: kutunun ortası 0
	var zmin := INF
	var zmax := -INF
	for s: Vector3 in secs:
		zmin = minf(zmin, s.y)
		zmax = maxf(zmax, s.y + s.z)
	var zc := (zmin + zmax) * 0.5
	var out: Array = []
	for s: Vector3 in secs:
		out.append(Vector3(s.x - span * 0.5, s.y - zc, s.z))
	return out


## Ayarlanabilir kanadın tam tanımı (dünya ölçeğinde): alan, en-boy oranı, stall açısı, kütle,
## dayanım ve aerodinamik merkez (ortalama veterin çeyreği) biçimden hesaplanır.
static func custom_wing_def(p: Dictionary, world := true) -> Dictionary:
	var secs := wing_sections(p)
	var thick := clampf(float(p.get("thick", 0.06)), 0.02, 0.16)
	var span: float = (secs[-1] as Vector3).x - (secs[0] as Vector3).x
	var area := 0.0
	var ac := Vector2.ZERO        # (x, z) alanla ağırlıklı
	var zmin := INF
	var zmax := -INF
	for i in secs.size() - 1:
		var a: Vector3 = secs[i]
		var b: Vector3 = secs[i + 1]
		var w := b.x - a.x
		var pa := (a.z + b.z) * 0.5 * w
		var lam := b.z / maxf(a.z, 0.01)
		var y_mac := w / 3.0 * (1.0 + 2.0 * lam) / (1.0 + lam)
		var mac := 2.0 / 3.0 * a.z * (1.0 + lam + lam * lam) / (1.0 + lam)
		var le := lerpf(a.y, b.y, y_mac / maxf(w, 0.01))
		ac += Vector2(a.x + y_mac, le + 0.25 * mac) * pa
		area += pa
	for s: Vector3 in secs:
		zmin = minf(zmin, s.y)
		zmax = maxf(zmax, s.y + s.z)
	ac /= maxf(area, 0.01)
	var ar := 2.0 * span * span / maxf(area, 0.01)
	var size := Vector3(span, maxf((secs[0] as Vector3).z * thick, 0.06), zmax - zmin)
	var d := {
		"title": "Ayarlanabilir Kanat", "category": "kanat", "mass": area * 34.0, "hp": 60.0 + area * 9.0,
		"cost": int(area * 80), "size": size, "mirror_visual": true, "procedural": "wing", "strength_kn": area * 40.0,
		"visuals": [{"type": "wing_sections", "secs": secs, "thick": thick, "mat": "paint"}],
		"colliders": [{"type": "box", "size": size}],
		"modules": [{"type": "wing", "area": area, "aspect_ratio": ar, "stall_deg": clampf(10.0 + 16.0 / ar, 13.0, 32.0),
			"cd0": 0.012, "ac_offset": Vector3(ac.x, 0.0, ac.y)}],
	}
	if world:
		_globalize(d, WORLD_SCALE)
	return d


## Gövde biçimleri, kokpit çeşitleri, kuyruk ve kaporta parçaları.
static func _register_shapes() -> void:
	# ayarlanabilir kanat: varsayılan biçim trapez; uçaktaki her kopya kendi "wing" ayarıyla kurulur
	_defs["wing_custom"] = custom_wing_def(WING_PRESETS["Trapez"], false)

	# LERX: kanat kökünden kokpite uzanan çok oklu ince yüzey (yüksek hücum açısında kaldırma)
	_defs["lerx"] = _wing("LERX (kanat kökü uzantısı)", Vector3(0.9, 0.06, 4.0), 45.0, 1.8, 0.8, 34.0,
		{"span": 0.9, "root": 4.0, "tip": 0.15, "sweep": 3.7, "thick": 0.03})
	_defs["lerx"]["strength_kn"] = 60.0

	# kuyruk yüzeyleri: tam hareketli V kuyruk (yunuslama + sapma kendiliğinden karışır), gövde altı kanatçığı
	_defs["tail_v"] = _control_surface("V Kuyruk Yüzeyi (tam hareketli)", Vector3(2.2, 0.1, 1.8), 120.0, 3.2, 18.0, 0.0,
		{"span": 2.2, "root": 1.8, "tip": 0.8, "sweep": 1.0, "thick": 0.06})
	_defs["tail_v"]["strength_kn"] = 130.0
	_defs["ventral_fin"] = _wing("Gövde Altı Kanatçığı", Vector3(0.8, 0.06, 1.4), 20.0, 0.7, 1.2, 25.0,
		{"span": 0.8, "root": 1.4, "tip": 0.6, "sweep": 0.7, "thick": 0.05})

	# kokpit çeşitleri (savaş düzeni; kanopi biçimi farklı)
	_defs["cockpit_bubble"] = _cockpit("Balon Kanopili Kokpit (tam görüş)", "fighter", 880.0, 1900, "bubble")
	_defs["cockpit_framed"] = _cockpit("Çerçeveli Klasik Kokpit", "fighter", 920.0, 1200, "framed")
	_defs["cockpit_low"] = _cockpit("Alçak Gömük Kokpit", "fighter", 900.0, 1700, "low")
	_defs["cockpit_airliner"] = _airliner_cockpit()

	# keskin burun: elmas kesitli (chine) sivri burun
	_defs["nose_chine"] = {
		"title": "Keskin Burun (elmas kesit)", "category": "gövde", "mass": 70.0, "hp": 80.0, "cost": 300,
		"size": Vector3(1.3, 1.3, 2.2),
		"visuals": [{"type": "lathe", "segments": 4, "y_scale": 0.62, "mat": "paint", "profile": _ogive(-1.1, 2.2, 0.75)},
			{"type": "lathe", "segments": 24, "mat": "paint", "profile": [Vector2(0.6, 0.55), Vector2(1.1, 0.65)]}],
		"colliders": [{"type": "cyl", "r": 0.45, "len": 2.1}],
		"modules": [{"type": "body_drag", "front_area": 1.33, "side_area": 1.3, "cd_front": 0.07, "cd_side": 0.5}],
	}

	# taşıyıcı gövde: geniş, basık, kaldırma üreten orta gövde (F-22 / F-35 gibi kanatla kaynaşık)
	_defs["lifting_body"] = {
		"title": "Taşıyıcı Gövde (geniş, basık)", "category": "gövde", "mass": 900.0, "hp": 260.0, "cost": 2400,
		"size": Vector3(3.0, 1.25, 4.0),
		"visuals": [
			{"type": "lathe", "segments": 32, "y_scale": 0.42, "mat": "paint", "profile": [
				Vector2(-2.0, 0.0), Vector2(-2.0, 1.2), Vector2(-1.2, 1.5), Vector2(0.6, 1.52), Vector2(1.6, 1.35), Vector2(2.0, 1.2), Vector2(2.0, 0.0)]},
		],
		"colliders": [{"type": "box", "size": Vector3(2.9, 1.2, 3.9)}],
		"modules": [
			{"type": "fuel_tank", "capacity": 1800.0},
			{"type": "wing", "area": 7.0, "aspect_ratio": 1.0, "stall_deg": 32.0, "cd0": 0.02},
			{"type": "body_drag", "front_area": 1.9, "side_area": 5.0, "cd_front": 0.05},
		],
	}

	# sırt kamburu ve gövde altı kaportası (yüzeye takılır, uzunluğu ayarlanabilir)
	for spec in [["spine_dorsal", "Sırt Kamburu (kokpit arkası)", 0.0, 180.0, -1.0], ["fairing_ventral", "Gövde Altı Kaportası", 180.0, 360.0, 1.0]]:
		_defs[spec[0]] = {
			"title": spec[1], "category": "gövde", "mass": 60.0, "hp": 70.0, "cost": 250, "mount": "surface",
			"size": Vector3(0.75, 0.38, 4.0),
			"visuals": [{"type": "lathe", "segments": 20, "arc_from": spec[2], "arc_to": spec[3], "mat": "paint",
				"pos": Vector3(0, spec[4] * 0.19, 0),
				"profile": [Vector2(-2.0, 0.04), Vector2(-1.3, 0.3), Vector2(0.9, 0.36), Vector2(2.0, 0.12)]}],
			"colliders": [{"type": "box", "size": Vector3(0.7, 0.35, 3.9)}],
			"modules": [{"type": "fuel_tank", "capacity": 120.0}, {"type": "body_drag", "front_area": 0.05, "side_area": 0.8, "cd_front": 0.05}],
		}

	# kuyruk kirişi: kanattan arkaya uzanan ince gövde (çift kirişli tasarımlar)
	_defs["tail_boom"] = {
		"title": "Kuyruk Kirişi (ince, uzun)", "category": "gövde", "mass": 160.0, "hp": 120.0, "cost": 500, "mount": "surface",
		"size": Vector3(0.6, 0.6, 7.0),
		"visuals": [{"type": "lathe", "segments": 20, "mat": "paint", "profile": [
			Vector2(-3.5, 0.0), Vector2(-3.1, 0.24), Vector2(-2.2, 0.3), Vector2(2.6, 0.24), Vector2(3.5, 0.16), Vector2(3.5, 0.0)]}],
		"colliders": [{"type": "cyl", "r": 0.28, "len": 6.9}],
		"modules": [{"type": "body_drag", "front_area": 0.28, "side_area": 3.4, "cd_front": 0.06}],
		"strength_kn": 180.0,
	}

	# kanat ucu tankı: uca takılır, yakıt + uç plakası etkisi
	_defs["wingtip_tank"] = {
		"title": "Kanat Ucu Yakıt Tankı", "category": "harici", "mass": 70.0, "hp": 60.0, "cost": 450, "mount": "tip", "tip_device": true,
		"size": Vector3(0.6, 0.6, 3.2),
		"visuals": [{"type": "lathe", "segments": 18, "mat": "paint", "profile": [
			Vector2(-1.6, 0.0), Vector2(-1.2, 0.24), Vector2(-0.5, 0.3), Vector2(0.9, 0.3), Vector2(1.6, 0.06)]}],
		"colliders": [{"type": "cyl", "r": 0.28, "len": 3.1}],
		"modules": [{"type": "fuel_tank", "capacity": 450.0}, {"type": "body_drag", "front_area": 0.28, "side_area": 1.6, "cd_front": 0.05}],
	}