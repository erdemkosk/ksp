class_name Doctrine
extends RefCounted
## Düşman doktrini: düşman, oyuncunun kariyer görevlerindeki alışkanlıklarını öğrenir ve üretilen
## görevlerde (MissionGen) karşı tedbir alır. Alışkanlıklar Career.doctrine'de (career.json)
## üstel ortalama olarak tutulur (son görevler daha ağır basar):
##   agl      — hedefe yaklaşırken (10 km içi) ortalama yerden yükseklik
##   mach     — aynı bölgede ortalama hız
##   w        — silah kullanımı: radar / ir / gun / bomb / arm / ship (atış sayısı; top 40 mermi = 1)
##   bomb_agl — bomba bırakma yüksekliği
##   ecm      — havada ECM açık geçen süre oranı;  chaff — görev başına chaff
## Karşı tedbirler: alçak giriş → uçaksavar + omuzdan SAM; radar füzesi → ECM'li avcılar;
## yüksekten bombalama → uzun menzilli SAM; top → temkinli (daha becerikli, çift uçan) pilotlar;
## ECM → erken uyarı radarı (yayını izler); radar avcısı füze → SAM'ların yanına uçaksavar;
## hızlı giriş → fazladan önleme avcısı.

const ALPHA := 0.4
const KEYS := ["radar", "ir", "gun", "bomb", "arm", "ship"]


static func data() -> Dictionary:
	return Career.doctrine


## Kart önbelleği için: doktrin her kayıtta değişir.
static func version() -> int:
	return int(Career.doctrine.get("n", 0))


## Uçuş sonu (gerçek kariyer görevi): tracker özetini alışkanlıklara kat.
static func record(s: Dictionary) -> void:
	var d := Career.doctrine
	var first := int(d.get("n", 0)) == 0
	var a := 1.0 if first else ALPHA
	if float(s.get("agl", -1.0)) >= 0.0:
		d["agl"] = lerpf(float(d.get("agl", s["agl"])), float(s["agl"]), a if d.has("agl") else 1.0)
		d["mach"] = lerpf(float(d.get("mach", s["mach"])), float(s["mach"]), a if d.has("mach") else 1.0)
	if float(s.get("bomb_agl", -1.0)) >= 0.0:
		d["bomb_agl"] = lerpf(float(d.get("bomb_agl", s["bomb_agl"])), float(s["bomb_agl"]), a if d.has("bomb_agl") else 1.0)
	var w: Dictionary = d.get("w", {})
	var sw: Dictionary = s.get("w", {})
	for k: String in KEYS:
		w[k] = lerpf(float(w.get(k, 0.0)), float(sw.get(k, 0.0)), a)
	d["w"] = w
	d["ecm"] = lerpf(float(d.get("ecm", 0.0)), float(s.get("ecm", 0.0)), a)
	d["chaff"] = lerpf(float(d.get("chaff", 0.0)), float(s.get("chaff", 0.0)), a)
	d["n"] = int(d.get("n", 0)) + 1
	Career.doctrine = d


## Silah payı (0..1).
static func share(k: String) -> float:
	var w: Dictionary = Career.doctrine.get("w", {})
	var total := 0.0
	for x: String in KEYS:
		total += float(w.get(x, 0.0))
	return float(w.get(k, 0.0)) / total if total > 0.5 else 0.0


## Etkin alışkanlıklar (kimlik → açıklama).
static func habits() -> Dictionary:
	var d := Career.doctrine
	var h := {}
	if int(d.get("n", 0)) < 1:
		return h
	if d.has("agl") and float(d["agl"]) < 220.0:
		h["low"] = "sen genelde alçaktan giriyorsun"
	if share("radar") > 0.4:
		h["radar"] = "radar füzelerine güveniyorsun"
	if d.has("bomb_agl") and float(d["bomb_agl"]) > 2500.0 and share("bomb") > 0.2:
		h["high_bomb"] = "yüksekten bombalıyorsun"
	if share("gun") > 0.45:
		h["gun"] = "yakın dövüşte topa güveniyorsun"
	if float(d.get("ecm", 0.0)) > 0.35:
		h["ecm"] = "ECM podunu hep açık tutuyorsun"
	if share("arm") > 0.25:
		h["arm"] = "SAM radarlarını radar avcısı füzeyle vuruyorsun"
	if d.has("mach") and float(d["mach"]) > 0.92:
		h["fast"] = "hedefe ses hızına yakın giriyorsun"
	return h


## Kartı alışkanlıklara göre değiştir; brifing satırlarını card["doctrine"]'e yaz.
static func adapt(card: Dictionary, rng: RandomNumberGenerator) -> void:
	var h := habits()
	var lines := []
	var t: Vector2 = card["target_xz"]
	var tpl := String(card["template"])
	var ground := bool(card.get("combat", false)) and not tpl in ["onleme", "eskort", "gemi"]
	var units: Array = card["units"]
	var fighters: Array = card["fighters"]
	if h.has("low") and tpl in ["yuk", "kurtarma"]:
		units.append({"type": "manpads", "xz": t + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(800.0, 2000.0), "obj": false})
		lines.append("İstihbarat: düşman bölgeye omuzdan atılan SAM timi soktu (%s)." % h["low"])
	if h.has("low") and ground:
		for i in 2:
			units.append({"type": "aaa", "xz": t + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(400.0, 1200.0), "obj": false})
		units.append({"type": "manpads", "xz": t + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(800.0, 2500.0), "obj": false})
		lines.append("İstihbarat: düşman alçak irtifa uçaksavarlarını artırdı (%s)." % h["low"])
	if h.has("radar") and tpl != "yuk":
		card["enemy_ecm"] = true
		if fighters.filter(func(f: Dictionary) -> bool: return f.get("role", "fighter") != "bomber").is_empty():
			fighters.append({"xz": t + MissionGen._enemy_dir(t) * 8000.0, "alt": 3500.0, "n": 1, "trigger": "alert", "v": 0.0, "role": "fighter"})
		lines.append("İstihbarat: düşman avcılarına ECM podu ve chaff taktı (%s)." % h["radar"])
	if h.has("high_bomb") and ground:
		units.append({"type": "lrsam", "xz": MissionGen._land(rng, t + MissionGen._enemy_dir(t) * rng.randf_range(3500.0, 6000.0), 0.0, 800.0), "obj": false})
		lines.append("İstihbarat: düşman bölgeye uzun menzilli SAM (40 km) konuşlandırdı (%s)." % h["high_bomb"])
	if h.has("gun") and not fighters.is_empty():
		card["enemy_defensive"] = true
		lines.append("İstihbarat: düşman pilotları top menziline girmekten kaçınıyor, çift uçuyor (%s)." % h["gun"])
	if h.has("ecm") and ground:
		units.append({"type": "radar", "xz": MissionGen._land(rng, MissionGen.BASE_XZ.lerp(t, 0.6), 0.0, 2000.0), "obj": false})
		lines.append("İstihbarat: düşman karıştırma yayınını izleyen bir erken uyarı radarı kurdu (%s)." % h["ecm"])
	if h.has("arm"):
		var added := 0
		for u: Dictionary in units.duplicate():
			if u["type"] == "sam" and added < 3:
				units.append({"type": "aaa", "xz": (u["xz"] as Vector2) + Vector2(260, -180), "obj": false})
				added += 1
		if added > 0:
			lines.append("İstihbarat: SAM rampalarının yanına uçaksavar topu kondu (%s)." % h["arm"])
	if h.has("fast") and card.get("combat", false):
		fighters.append({"xz": t + MissionGen._enemy_dir(t) * 10000.0, "alt": 4000.0, "n": 1, "trigger": "near", "v": 15.0, "role": "fighter"})
		lines.append("İstihbarat: düşman önleme avcısını erken kaldıracak (%s)." % h["fast"])
	card["doctrine"] = lines


## Test / brifing: alışkanlık özeti.
static func summary() -> String:
	var d := Career.doctrine
	if int(d.get("n", 0)) == 0:
		return "Düşman henüz seni tanımıyor."
	return "Giriş %d m AGL · M%.2f · radar %%%d · IR %%%d · top %%%d · bomba %%%d (%d m) · ARM %%%d · ECM %%%d" % [
		int(d.get("agl", 0.0)), float(d.get("mach", 0.0)), share("radar") * 100.0, share("ir") * 100.0,
		share("gun") * 100.0, share("bomb") * 100.0, int(d.get("bomb_agl", 0.0)), share("arm") * 100.0, float(d.get("ecm", 0.0)) * 100.0]


## Uçuş boyunca alışkanlık ve sonuç verisi toplar (yarım saniyede bir, ucuz). MissionManager ekler.
class Tracker extends Node:
	var mm: MissionManager
	var agl_sum := 0.0
	var mach_sum := 0.0
	var ingress_n := 0
	var bomb_agl_sum := 0.0
	var bomb_n := 0
	var w := {"radar": 0.0, "ir": 0.0, "gun": 0.0, "bomb": 0.0, "arm": 0.0, "ship": 0.0}
	var ecm_t := 0.0
	var air_t := 0.0
	var chaff_used := 0
	var detected := {}
	var finalized := false
	var _t := 0.0
	var _seen_t := 0.0
	var _v: Vessel
	var _ammo := 0
	var _bombs := 0
	var _chaff := 0

	func _physics_process(delta: float) -> void:
		_t += delta
		if _t < 0.5:
			return
		var dt := _t
		_t = 0.0
		var v: Vessel = mm.main.vessel if is_instance_valid(mm.main) else null
		if not is_instance_valid(v) or v.parts.is_empty() or not v.has_pilot():
			return
		if v != _v:
			_v = v
			if not v.weapon_fired.is_connected(_on_fired):
				v.weapon_fired.connect(_on_fired)
			_ammo = _count_ammo(v)
			_bombs = _count_bombs(v)
			_chaff = _count_chaff(v)
		var agl := v.radar_altitude()
		if agl < 5.0:
			return
		air_t += dt
		if v.jamming():
			ecm_t += dt
		var a := _count_ammo(v)
		if a < _ammo:
			w["gun"] += (_ammo - a) / 40.0
		_ammo = a
		var b := _count_bombs(v)
		if b < _bombs:
			w["bomb"] += _bombs - b
			bomb_agl_sum += agl * (_bombs - b)
			bomb_n += _bombs - b
		_bombs = b
		var ch := _count_chaff(v)
		chaff_used += maxi(_chaff - ch, 0)
		_chaff = ch
		# hedefe giriş: 10 km içinde
		var tp := _target(v)
		if tp != Vector3.INF and mm._horiz_dist(v, tp) < 10000.0:
			agl_sum += agl
			mach_sum += v.mach()
			ingress_n += 1
		_seen_t -= dt
		if _seen_t <= 0.0:
			_seen_t = 1.5
			_scan_seen(v)

	func _target(v: Vessel) -> Vector3:
		if mm.nav_point is Vector3:
			return mm.nav_point
		if not Game.mission_card.is_empty() and mm.def.get("id", "") == "gen":
			var t: Vector2 = Game.mission_card.get("target_xz", Vector2.ZERO)
			return MissionManager.world_point(t.x, t.y, 0.0)
		return Vector3.INF

	func _on_fired(kind: int) -> void:
		match kind:
			Vessel.WEAPON_RADAR:
				w["radar"] += 1.0
			Vessel.WEAPON_MISSILE:
				w["ir"] += 1.0
			Vessel.WEAPON_ARM:
				w["arm"] += 1.0
			Vessel.WEAPON_SHIP, Vessel.WEAPON_CRUISE:
				w["ship"] += 1.0

	func _scan_seen(v: Vessel) -> void:
		for s in SamSite.sites:
			if is_instance_valid(s) and not s.destroyed and s.team != v.team and s.global_position.distance_to(v.com_global()) < s.range_m * 1.5 and s.sees(v):
				detected["sam"] = true
		for st in RadarStation.stations:
			if is_instance_valid(st) and not st.destroyed and st.team != v.team and st.sees(v):
				detected["radar"] = true
		for sh in Warship.ships:
			if is_instance_valid(sh) and not sh.destroyed and sh.team != v.team and sh.global_position.distance_to(v.com_global()) < sh.radar_range * 1.6 and sh.sees(v):
				detected["ship"] = true
		for n in v.get_parent().get_children():
			if n is Vessel and n != v and n.team == "düşman" and not n.parts.is_empty():
				var r: RadarModule = n.radar()
				if r and v in r.contacts:
					detected["fighters"] = true

	static func _count_ammo(v: Vessel) -> int:
		var n := 0
		for m in v.modules:
			if m is GunModule:
				n += m.ammo
		return n

	static func _count_bombs(v: Vessel) -> int:
		var n := 0
		for m in v.modules:
			if m is BombModule and m.loaded:
				n += 1
			elif m is BombBayModule:
				n += m.bombs
		return n

	static func _count_chaff(v: Vessel) -> int:
		var n := 0
		for m in v.modules:
			if m is FlareModule:
				n += m.chaff
		return n

	## Alışkanlık özeti (Doctrine.record).
	func summary() -> Dictionary:
		return {"agl": agl_sum / ingress_n if ingress_n > 0 else -1.0, "mach": mach_sum / ingress_n if ingress_n > 0 else 0.0,
			"bomb_agl": bomb_agl_sum / bomb_n if bomb_n > 0 else -1.0, "w": w.duplicate(),
			"ecm": ecm_t / air_t if air_t > 1.0 else 0.0, "chaff": float(chaff_used)}

	## Görev bitti: Game.last_result'u doldur, gerçek kariyer görevinde alışkanlıkları kaydet.
	func finalize(success: bool, notes: Array = []) -> void:
		if finalized:
			return
		finalized = true
		var v: Vessel = mm.main.vessel if is_instance_valid(mm.main) else null
		var alive := is_instance_valid(v) and not v.parts.is_empty()
		var dmg := 1.0
		if alive:
			dmg = 0.0
			for p in v.parts:
				dmg += 1.0 - p.health_ratio()
			dmg /= v.parts.size()
		var destroyed := 0
		for n in mm.main.world.get_children():
			if n is GroundTarget and n.destroyed and n.team == "düşman":
				destroyed += 1
		var fs: FlightStats = mm.main.flight_stats
		var s := summary()
		Game.last_result = {"card": Game.mission_card if mm.def.get("id", "") == "gen" else MissionGen.make_card({"mission": mm.def.get("id", ""), "region": Game.mission_region}),
			"success": success, "fuel_left_kg": v.fuel_amount() if alive else 0.0, "max_g": fs.max_g if is_instance_valid(fs) else 0.0,
			"time_s": mm.elapsed, "kills": mm.kills, "targets_destroyed": destroyed, "damage_taken": dmg,
			"detected_by": detected.keys(), "ingress_agl_avg": s["agl"], "notes": notes,
			"weapons": s["w"], "ingress_mach_avg": s["mach"], "mission": mm.def.get("id", ""), "test_flight": Game.test_flight}
		if not Game.test_flight and not Career.sandbox() and air_t > 20.0:
			Doctrine.record(s)
			Career.save()

	func _exit_tree() -> void:
		if not finalized and is_instance_valid(mm) and not mm.def.is_empty() and air_t > 20.0:
			finalize(mm.state == "success", [mm.fail_reason] if mm.fail_reason != "" else [])
