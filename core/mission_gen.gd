class_name MissionGen
## Prosedürel görev üreteci: görevler "kısıtlı bir istek" olarak gelir, oyuncu uçağını ona göre
## tasarlar ("Dereköy köprüsü 22 km kuzeyde, yolda 2 SAM var, 2 ton patlayıcı lazım, pist 700 m").
##
## Şablonlar canlı cepheye bağlıdır: bölgenin sahibi (Front), düşman hamleleri (FrontAI acil
## görevleri şablona dönüşür), dünyadaki köprüler / yollar / deniz / dağlar. Konum, saat, hava,
## düşman gücü (sefer günü ve bölge derinliğiyle artar) ve görev içi olaylar kartın tohumundan
## üretilir: aynı gün aynı bölge hep aynı kartı verir; kart Game.mission_card'da taşınır, böylece
## harita, hangar, brifing ve uçuş birebir aynı görevi görür. Düşman doktrini (Doctrine)
## oyuncunun alışkanlıklarına göre kartı değiştirir.
##
## Kart (veri sözleşmesi, başka modüller okur): id, template, title, brief, region, target_xz,
## base_xz, range_km, payload_kg, runway_m, threats [{kind, n, range_km}], time_limit_s,
## target_alt_m, target_mach, night, weather, needs, reward, seed, events, doctrine.
## Ek (uçuş için): level, combat, units, fighters, path, points, site, start, hour, tanker…

const BASE_XZ := Vector2(0, 0)
## Ana Üs pistinin kuzey ucu (yüzey z) ve kalkış noktasından kullanılabilir tam uzunluk
const RUNWAY_END_Z := -1200.0
const FULL_RUNWAY := 2300.0
const HERKUL := "res://crafts/herkul.json"
const ECM_FIGHTER := "res://crafts/kartal_2e.json"

const TEMPLATES := {
	"kopru": {"title": "Köprü İmha", "glyph": "KP", "combat": true, "level": 2, "reward": 8000},
	"sam": {"title": "SAM Bastırma", "glyph": "SB", "combat": true, "level": 3, "reward": 10000},
	"konvoy": {"title": "Konvoy Avı", "glyph": "KV", "combat": true, "level": 2, "reward": 7000},
	"onleme": {"title": "Önleme", "glyph": "ÖN", "combat": true, "level": 2, "reward": 7500},
	"eskort": {"title": "Eskort", "glyph": "ES", "combat": false, "level": 2, "reward": 6500},
	"kurtarma": {"title": "Kurtarma Örtüsü", "glyph": "KT", "combat": false, "level": 2, "reward": 6500},
	"yuk": {"title": "Yük Bırakma", "glyph": "YB", "combat": false, "level": 2, "reward": 6000},
	"kesif": {"title": "Keşif", "glyph": "KŞ", "combat": true, "level": 1, "reward": 5500},
	"gemi": {"title": "Gemi Saldırısı", "glyph": "GS", "combat": true, "level": 3, "reward": 11000},
	"derin": {"title": "Derin Saldırı", "glyph": "DS", "combat": true, "level": 3, "reward": 12000},
}

## Bölgeye uygun şablonlar (sahibine göre süzülür)
const POOLS := {
	"anaus": ["onleme"],
	"sahil": ["yuk", "kurtarma", "eskort", "onleme"],
	"bati": ["yuk", "kurtarma", "eskort", "kesif"],
	"ovakoy": ["konvoy", "kopru", "kesif", "kurtarma"],
	"orta": ["kopru", "sam", "konvoy", "kesif", "yuk"],
	"derekoy": ["sam", "kopru", "derin"],
	"kuzeykent": ["konvoy", "derin", "kopru"],
	"kuzeyhava": ["derin", "sam"],
	"dogudeniz": ["gemi"],
}
## Dost bölgede yapılabilen (destek / savunma) şablonlar
const SUPPORT := ["yuk", "kurtarma", "eskort", "onleme"]
## FrontAI hamlesi → karşı görev şablonu
const URGENT_TEMPLATE := {"baskin": "onleme", "konvoy": "konvoy", "taarruz": "konvoy"}
## Perde ağırlıklarında şablonun karşılığı olan sabit görev
const ALIAS := {"kopru": "kara", "konvoy": "kara", "gemi": "deniz", "eskort": "ustunluk", "kurtarma": "heli", "yuk": "kesif"}

## Tehdit menzilleri (km): brifing ve kontrol listesi
const RANGES := {"sam": 9.0, "lrsam": 40.0, "aaa": 3.0, "manpads": 4.0, "radar": 60.0, "ship": 12.0,
	"frigate": 16.0, "escort": 1.4, "hunters": 1.4}

static var _cache := {}
static var _cache_day := -1


# ------------------------------------------------------------------ cephe bağlantısı

## Front.operations() için üretilmiş harekâtlar: önce düşman hamlelerine karşı acil görevler
## (aynı bölgede başka üretilmiş görev olmaz), sonra her uygun bölgeye bir görev.
static func ops() -> Array:
	var out := []
	var busy := {}
	for u: Dictionary in FrontAI.urgent_ops():
		var t := _threat_by_id(int(u.get("threat", -1)))
		var op: Dictionary = u.duplicate()
		op["mission"] = "gen"
		op["template"] = String(URGENT_TEMPLATE.get(String(t.get("kind", "konvoy")), "konvoy"))
		op["from"] = String(t.get("from", ""))
		op["card"] = make_card(op)
		out.append(op)
		busy[String(u["region"])] = true
	for r: Dictionary in Front.REGIONS:
		var rid: String = r["id"]
		if busy.has(rid):
			continue
		if not Campaign.allows("gen", rid):
			continue   # perde kapısı (derin bölgeler ilk perdede kapalı)
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(hash("pick|%s|%d" % [rid, Career.day]))
		var tpl := _pick(pool_for(rid), rng)
		if tpl == "":
			continue
		var op := {"mission": "gen", "region": rid, "combat": bool(TEMPLATES[tpl]["combat"]), "template": tpl, "slot": 0}
		op["card"] = make_card(op)
		out.append(op)
	return out


## Perde ağırlığıyla (Campaign.mission_weights; şablon adı ya da benzer sabit görev) şablon seç.
static func _pick(pool: Array, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = Campaign.mission_weights() if not Career.sandbox() else {}
	var total := 0.0
	var ws := []
	for t: String in pool:
		var x := float(w.get(t, w.get(String(ALIAS.get(t, t)), 1.0)))
		ws.append(maxf(x, 0.0))
		total += maxf(x, 0.0)
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= float(ws[i])
		if roll <= 0.0 and float(ws[i]) > 0.0:
			return pool[i]
	return pool[pool.size() - 1]


## Bölgenin şu anki sahibine göre yapılabilecek şablonlar.
static func pool_for(rid: String) -> Array:
	var pool: Array = POOLS.get(rid, [])
	if Front.attackable(rid):
		var c := pool.filter(func(t: String) -> bool: return not t in SUPPORT)
		return c if not c.is_empty() else ["konvoy"]
	if Front.owner(rid) == Front.DOST:
		return pool.filter(func(t: String) -> bool: return t in SUPPORT)
	return []


static func _threat_by_id(id: int) -> Dictionary:
	for t: Dictionary in Career.threats:
		if int(t["id"]) == id:
			return t
	return {}


## Haritada kısa simge.
static func glyph(op: Dictionary) -> String:
	var c: Dictionary = op.get("card", {})
	return String(TEMPLATES.get(String(c.get("template", "")), {}).get("glyph", "•"))


## MissionManager.get_def("gen") karşılığı: uçuşun başlatılması için görev tanımı.
static func def_for(card: Dictionary) -> Dictionary:
	if card.is_empty():
		return {}
	var d := {"id": "gen", "title": card.get("title", "Görev"), "level": int(card.get("level", 2)),
		"brief": card.get("brief", ""), "start": card.get("start", "runway_hot"),
		"alt": float(card.get("start_alt", 1500.0)), "z": float(card.get("start_z", 0.0))}
	if float(card.get("time_limit_s", 0.0)) > 0.0:
		d["time"] = float(card["time_limit_s"])
	return d


# ------------------------------------------------------------------ kart

## Harekâttan görev kartı. Üretilmiş harekâtta op["card"] doğrudan döner; sabit görevlerde
## (MissionManager.DEFS) yaklaşık bir kart (kısıtlar) üretilir.
static func make_card(op: Dictionary) -> Dictionary:
	if op.has("card") and not (op["card"] as Dictionary).is_empty():
		return op["card"]
	var mid := String(op.get("mission", "gen"))
	if mid != "gen" and mid != "":
		return _static_card(op)
	var rid := String(op.get("region", "anaus"))
	var tpl := String(op.get("template", ""))
	if not TEMPLATES.has(tpl):
		var pool := pool_for(rid)
		tpl = String(pool[0]) if not pool.is_empty() else "konvoy"
	if _cache_day != Career.day:
		_cache.clear()
		_cache_day = Career.day
	var key := "%s|%s|%d|%d|%d|%d" % [tpl, rid, Career.day, int(op.get("slot", 0)), int(op.get("threat", -1)), Doctrine.version()]
	if not _cache.has(key):
		_cache[key] = _build(tpl, rid, op, absi(hash(key)))
	return (_cache[key] as Dictionary).duplicate(true)


static func _build(tpl: String, rid: String, op: Dictionary, seed_v: int) -> Dictionary:
	TerrainGen.init()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var region := Front.region(rid)
	var c: Vector2 = region.get("xz", Vector2.ZERO)
	var diff := clampf((Career.day - 1) / 14.0, 0.0, 1.0) + (0.15 if Front.owner(rid) == Front.DUSMAN else 0.0)
	var info: Dictionary = TEMPLATES[tpl]
	var card := {"id": "gen_%s_%s_g%d_%d" % [tpl, rid, Career.day, seed_v % 10000], "template": tpl,
		"title": info["title"], "brief": "", "region": rid, "target_xz": c, "base_xz": BASE_XZ,
		"range_km": 0.0, "payload_kg": 0.0, "runway_m": FULL_RUNWAY, "threats": [], "time_limit_s": 0.0,
		"target_alt_m": 0.0, "target_mach": 0.0, "night": false, "weather": Weather.Preset.CLEAR,
		"needs": [], "reward": 0, "seed": seed_v, "events": [], "doctrine": [],
		"level": int(info["level"]), "combat": bool(info["combat"]), "diff": diff,
		"units": [], "fighters": [], "points": [], "start": "runway_hot", "hour": 12.0,
		"tanker": false, "rtb": false, "lead": ""}
	if op.has("threat"):
		card["threat"] = int(op["threat"])
		card["urgent"] = true
		card["combat"] = true
	_environment(card, rng)
	match tpl:
		"kopru":
			_t_kopru(card, rng, c, diff)
		"sam":
			_t_sam(card, rng, c, diff)
		"konvoy":
			_t_konvoy(card, rng, c, diff, String(op.get("from", "")))
		"onleme":
			_t_onleme(card, rng, rid, c, diff, String(op.get("from", "")))
		"eskort":
			_t_eskort(card, rng, c, diff)
		"kurtarma":
			_t_kurtarma(card, rng, c, diff)
		"yuk":
			_t_yuk(card, rng, c, diff)
		"kesif":
			_t_kesif(card, rng, c, diff)
		"gemi":
			_t_gemi(card, rng, c, diff)
		"derin":
			_t_derin(card, rng, c, diff)
	Doctrine.adapt(card, rng)
	_finish_card(card, rng)
	return card


## Saat ve hava (gece önlemesi daha olası; yük bırakmada fırtına yok).
static func _environment(card: Dictionary, rng: RandomNumberGenerator) -> void:
	var tpl := String(card["template"])
	card["night"] = rng.randf() < (0.4 if tpl == "onleme" else 0.18)
	card["hour"] = [21.5, 23.0, 1.0, 3.5][rng.randi() % 4] if card["night"] else snappedf(rng.randf_range(7.0, 17.0), 0.25)
	var weights := [40.0, 30.0, 15.0, 5.0 if tpl != "yuk" else 0.0, 10.0]
	var roll := rng.randf() * 100.0
	var w := 0
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			w = i
			break
	card["weather"] = w


static func _unit(card: Dictionary, type: String, xz: Vector2, obj := false, extra := {}) -> void:
	var u := {"type": type, "xz": xz, "obj": obj}
	u.merge(extra, true)
	(card["units"] as Array).append(u)


static func _h(xz: Vector2) -> float:
	return TerrainGen.height(Vector3(xz.x, TerrainGen.RADIUS, xz.y).normalized())


static func _polar(rng: RandomNumberGenerator, r1: float, r2: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(r1, r2)


static func _in_world(p: Vector2) -> Vector2:
	return p.clamp(FlightMap.WORLD_LO + Vector2(1500, 1500), FlightMap.WORLD_HI - Vector2(1500, 1500))


## Merkezin r1..r2 çevresinde kara üstünde, olabildiğince düz bir nokta.
static func _land(rng: RandomNumberGenerator, c: Vector2, r1: float, r2: float) -> Vector2:
	var best := c
	var bs := INF
	for i in 24:
		var p := _in_world(c + _polar(rng, r1, r2))
		var h := _h(p)
		if h < 6.0:
			continue
		var s := 0.0
		for o: Vector2 in [Vector2(150, 0), Vector2(-150, 0), Vector2(0, 150), Vector2(0, -150)]:
			s = maxf(s, absf(_h(p + o) - h))
		if s < bs:
			bs = s
			best = p
		if s < 4.0:
			break
	if bs == INF and c.distance_to(BASE_XZ) > 500.0:
		# kara yok (bölge merkezi denizde): kıyıya, üsse doğru genişleterek ara
		return _land(rng, c.lerp(BASE_XZ, 0.2), r1, clampf(r2 * 2.0, 1500.0, 8000.0))
	return best


## Derin deniz noktası (merkeze yakın).
static func _sea(rng: RandomNumberGenerator, c: Vector2, r: float) -> Vector2:
	for i in 120:
		var p := _in_world(c + _polar(rng, 0.0, r * (1.0 + i / 40.0)))
		if _h(p) < -30.0:
			return p
	return MissionManager._sea_points(1)[0]


## Yüksek ve tepesi düz bir nokta (dağ karakolu).
static func _hill(rng: RandomNumberGenerator, c: Vector2, r: float) -> Vector2:
	var best := c
	var bs := -INF
	for i in 60:
		var p := _in_world(c + _polar(rng, 0.0, r))
		var h := _h(p)
		var flat := 0.0
		for o: Vector2 in [Vector2(90, 0), Vector2(-90, 0), Vector2(0, 90), Vector2(0, -90)]:
			flat = maxf(flat, absf(_h(p + o) - h))
		var s := h - flat * 6.0 - (100000.0 if h < 20.0 else 0.0)
		if s > bs:
			bs = s
			best = p
	if _h(best) < 20.0 and r < 20000.0:
		return _hill(rng, c.lerp(BASE_XZ, 0.4), r * 1.6)   # bölge denizde: kıyıya doğru ara
	return best


## Merkezden en yakın düşman bölgesine yön (yoksa kuzey).
static func _enemy_dir(c: Vector2) -> Vector2:
	var best := Vector2(0, -1)
	var bd := INF
	for r: Dictionary in Front.REGIONS:
		if Front.owner(r["id"]) == Front.DUSMAN:
			var d: float = c.distance_to(r["xz"])
			if d > 100.0 and d < bd:
				bd = d
				best = ((r["xz"] as Vector2) - c).normalized()
	return best


static func _compass(v: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	return ["kuzey", "kuzeydoğu", "doğu", "güneydoğu", "güney", "güneybatı", "batı", "kuzeybatı"][int(round(a / 45.0)) % 8]


static func _town_near(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for t: Dictionary in Towns.TOWNS:
		var d: float = p.distance_to(t["xz"])
		if d < bd:
			bd = d
			best = t["name"]
	return best if bd < 9000.0 else ""


static func _where(card: Dictionary, p: Vector2) -> String:
	var v := p - BASE_XZ
	var loc := {"kuzey": "kuzeyinde", "kuzeydoğu": "kuzeydoğusunda", "doğu": "doğusunda", "güneydoğu": "güneydoğusunda",
		"güney": "güneyinde", "güneybatı": "güneybatısında", "batı": "batısında", "kuzeybatı": "kuzeybatısında"}
	return ("üssün %d km %s" % [int(round(v.length() / 1000.0)), loc[_compass(v)]]) if v.length() > 1500.0 else "üssün hemen yanında"


static func _sound(alt: float) -> float:
	return 340.0 - 0.0041 * minf(alt, 11000.0)


static func _fighter(card: Dictionary, xz: Vector2, alt: float, n: int, trigger: String, v := 0.0, extra := {}) -> void:
	var f := {"xz": xz, "alt": alt, "n": n, "trigger": trigger, "v": v, "role": "fighter"}
	f.merge(extra, true)
	(card["fighters"] as Array).append(f)


# ------------------------------------------------------------------ şablonlar

static func _t_kopru(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var best := {}
	var bd := 9000.0
	for b: Dictionary in Towns.bridges():
		var d: float = c.distance_to(b["xz"])
		if d < bd:
			bd = d
			best = b
	var payload := snappedf(lerpf(1000.0, 3000.0, clampf(diff * 0.8 + rng.randf() * 0.4, 0.0, 1.0)), 250.0)
	card["payload_kg"] = payload
	var name := ""
	if not best.is_empty():
		var xz: Vector2 = best["xz"]
		card["target_xz"] = xz
		var town := _town_near(xz)
		name = ("%s köprüsü" % town) if town != "" else "Nehir köprüsü"
		_unit(card, "bridge", xz, true, {"hp": payload * 4.0, "name": name, "dir": best["dir"], "width": float(best["width"]), "level": float(best["level"])})
	else:
		var xz := _land(rng, c, 500.0, 3000.0)
		card["target_xz"] = xz
		card["title"] = "İkmal Deposu İmha"
		name = "%s ikmal deposu" % Front.region(String(card["region"])).get("name", "")
		_unit(card, "depot", xz, true, {"hp": payload * 4.0, "name": name})
	var t: Vector2 = card["target_xz"]
	for i in 1 + int(round(diff * 2.0)):
		_unit(card, "aaa", t + _polar(rng, 250.0, 650.0))
	# yolda SAM: rotanın son yarısında, yana kaymış
	if rng.randf() < 0.45 + diff * 0.5:
		var dir := (t - BASE_XZ).normalized()
		for i in 1 + int(diff * 1.5):
			var p := BASE_XZ.lerp(t, rng.randf_range(0.5, 0.8)) + dir.orthogonal() * rng.randf_range(-3000.0, 3000.0)
			_unit(card, "sam", _land(rng, p, 0.0, 800.0))
	if diff > 0.3 and rng.randf() < 0.6:
		_fighter(card, t + _enemy_dir(t) * 6000.0, 2800.0, 1 + int(diff), "alert")
	if rng.randf() < 0.3:
		card["runway_m"] = snappedf(rng.randf_range(600.0, 1000.0), 50.0)
	card["lead"] = "%s %s. Düşman ikmali bu köprüden geçiyor; yıkmak için en az %s patlayıcı lazım (top ya da füze yetmez)." % [name, _where(card, t), _kg(payload)] \
		if not best.is_empty() else "%s %s. Depoyu yerle bir etmek için en az %s patlayıcı lazım." % [name, _where(card, t), _kg(payload)]
	_maybe_tanker(card, rng)


static func _t_sam(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var t := _land(rng, c, 0.0, 2500.0)
	card["target_xz"] = t
	var n := 2 + (1 if diff > 0.5 or rng.randf() < 0.25 else 0)
	for i in n:
		var p := _land(rng, t + Vector2.from_angle(TAU * i / n + rng.randf() * 0.8) * rng.randf_range(900.0, 2200.0), 0.0, 400.0)
		_unit(card, "sam", p, true)
		_unit(card, "aaa", p + _polar(rng, 200.0, 400.0))
	if diff > 0.3 or rng.randf() < 0.4:
		_unit(card, "radar", _land(rng, t + _enemy_dir(t) * 3000.0, 0.0, 800.0), true)
	if diff > 0.75:
		_unit(card, "lrsam", _land(rng, t + _enemy_dir(t) * 5000.0, 0.0, 800.0), true)
	if rng.randf() < 0.5:
		_unit(card, "manpads", t + _polar(rng, 500.0, 1500.0))
	if diff > 0.45:
		_fighter(card, t + _enemy_dir(t) * 8000.0, 3500.0, 2, "alert")
	card["lead"] = "%s bölgesinde %d SAM rampası %s hava sahasını kapatıyor (9 km, yerden 120 m üstünü görür). Hepsini sustur: arkadan kara harekâtı gelecek." % [
		Front.region(String(card["region"])).get("name", ""), n, _where(card, t)]


## Konvoy: bölgeye en yakın yolda, dost tarafa (üsse yakın uca) doğru iner. Yol yoksa arazide.
static func _t_konvoy(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float, from_rid: String) -> void:
	var path := _convoy_path(c, rng)
	card["path"] = path
	card["target_xz"] = path[0]
	var n := 4 + int(diff * 3.0) + rng.randi() % 2
	var armored := 2 + int(diff * 2.0)
	var escorts := 1 + int(diff * 2.0)
	_unit(card, "convoy", path[0], true, {"n": n, "armored": mini(armored, n), "escort": escorts})
	var length := 0.0
	for i in path.size() - 1:
		length += (path[i] as Vector2).distance_to(path[i + 1])
	card["time_limit_s"] = clampf(snappedf(length / 11.0, 30.0), 360.0, 1500.0)
	var goal: Vector2 = path[path.size() - 1]
	card["goal_xz"] = goal
	if diff > 0.2 or rng.randf() < 0.4:
		_fighter(card, path[0] + _enemy_dir(path[0]) * 3000.0, 2200.0, 1, "alert")
	if rng.randf() < 0.4 + diff * 0.3:
		_unit(card, "manpads", (path[0] as Vector2).lerp(goal, 0.3) + _polar(rng, 200.0, 600.0))
	if rng.randf() < 0.25:
		card["runway_m"] = snappedf(rng.randf_range(700.0, 1100.0), 50.0)
	var urg := "Taarruz hazırlığı: " if from_rid != "" and card.get("urgent", false) else ""
	var dest := _town_near(goal)
	card["lead"] = "%sdüşman konvoyu (%d araç, %d zırhlı, %d makineli refakat) %s ilerliyor; %s varmadan durdur. Saldırıda araçlar dağılıp ormana / köye saklanır." % [
		urg, n, mini(armored, n), escorts, _where(card, path[0]), (dest + "'e") if dest != "" else "hedefine"]
	if urg == "":
		card["lead"] = String(card["lead"]).substr(0, 1).to_upper() + String(card["lead"]).substr(1)


static func _convoy_path(c: Vector2, rng: RandomNumberGenerator) -> Array:
	var best_road := -1
	var best_i := 0
	var bd := INF
	var roads := []
	for ri in Towns.ROADS.size():
		var s := Towns.road_samples(Towns.ROADS[ri])
		roads.append(s)
		for i in s.size():
			var d := c.distance_to(s[i])
			if d < bd:
				bd = d
				best_road = ri
				best_i = i
	var out := []
	if best_road >= 0 and bd < 7000.0:
		var s: Array = roads[best_road]
		# dost uç: üsse yakın olan
		var forward := (s[s.size() - 1] as Vector2).length() < (s[0] as Vector2).length()
		var step := 1 if forward else -1
		var i0 := clampi(best_i - step * (60 + rng.randi() % 40), 0, s.size() - 1)
		var i := i0
		var length := 0.0
		while i >= 0 and i < s.size() and length < 14000.0:
			out.append(s[i])
			if out.size() > 1:
				length += (out[out.size() - 2] as Vector2).distance_to(s[i])
			i += step
		if out.size() >= 2 and length > 2500.0:
			return out
		out.clear()
	# yol yok: arazide üsse doğru
	# (kara üstünde bir başlangıç; üsse doğru, denize girmeyen ilk yön)
	var start := _land(rng, c, 0.0, 4000.0)
	var dir0 := (BASE_XZ - start).normalized()
	var best_dir := dir0
	var best_k := -1
	for a: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var dir := dir0.rotated(a)
		var k := 0
		while k < 40 and _h(start + dir * (k + 1) * 200.0) > 2.0:
			k += 1
		if k > best_k:
			best_k = k
			best_dir = dir
		if k >= 40:
			break
	for k in maxi(best_k, 12) + 1:
		out.append(start + best_dir * k * 200.0)
	return out


static func _t_onleme(card: Dictionary, rng: RandomNumberGenerator, rid: String, c: Vector2, diff: float, from_rid: String) -> void:
	var defend := Vector2(0, 600) if rid == "anaus" else c
	var src: Vector2 = Front.region(from_rid).get("xz", Vector2.ZERO) if from_rid != "" else Vector2.ZERO
	if src == Vector2.ZERO:
		src = Front.region("kuzeyhava")["xz"] if Front.owner("kuzeyhava") == Front.DUSMAN else defend + _enemy_dir(defend) * 25000.0
	var dir := (defend - src).normalized()
	var alt := snappedf(rng.randf_range(4000.0, 9500.0), 500.0)
	var mach := snappedf(rng.randf_range(0.6, 0.9), 0.05)
	var v := mach * _sound(alt)
	# bombardımanlar düşman bölgesinden kalkar; uyarı süresi = kalkışlarına kadar bekleme + uçuş
	var start := _in_world(src + (src - defend).normalized() * 3000.0)
	var flight := start.distance_to(defend) / v
	var tl := maxf(rng.randf_range(330.0, 450.0) - diff * 60.0, flight + 60.0)
	var delay := snappedf(tl - flight, 5.0)
	tl = delay + flight
	var n := 2 + int(diff * 1.6)
	card["target_xz"] = start
	card["defend_xz"] = defend
	card["target_alt_m"] = alt
	card["target_mach"] = mach
	card["time_limit_s"] = snappedf(tl, 10.0)
	card["launch_s"] = delay
	card["bombers"] = n
	_fighter(card, start, alt, n, "clock", delay, {"role": "bomber", "to": defend, "speed": v})
	if diff > 0.4:
		_fighter(card, start + dir.orthogonal() * 1200.0, alt + 500.0, 1 + int(diff), "clock", delay, {"role": "escort", "to": defend, "speed": v * 1.05})
	var place := "üsse" if rid == "anaus" else "%s bölgesine" % Front.region(rid).get("name", "")
	card["lead"] = "%s%d bombardıman uçağı %s üzerinden %d m'de Mach %.2f ile %s geliyor. %d dakikan var: hedefe 3 km yaklaşmadan hepsini düşür." % [
		"Gece önleme: " if card["night"] else "Önleme: ", n, _compass(src - defend), int(alt), mach, place, int(tl / 60.0)]


static func _t_eskort(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var dest := _land(rng, c + _enemy_dir(c) * rng.randf_range(2000.0, 4500.0), 0.0, 1500.0)
	card["target_xz"] = dest
	# rota boyunca en yüksek arazinin 700 m üstü
	var top := 0.0
	for k in 21:
		top = maxf(top, _h(Vector2(0, 2500).lerp(dest, k / 20.0)))
	var alt := clampf(snappedf(top + 700.0, 100.0), 1500.0, 4000.0)
	card["start"] = "air"
	card["start_alt"] = alt
	card["start_z"] = 2500.0
	card["escort_alt"] = alt
	var dir := (dest - Vector2(0, 2500)).normalized()
	var dist := Vector2(0, 2500).distance_to(dest)
	var waves := 1 + (1 if diff > 0.35 or rng.randf() < 0.4 else 0)
	for w in waves:
		var at := clampf(dist / 120.0 * (0.25 + 0.4 * w) , 40.0, 400.0)
		var p := Vector2(0, 2500) + dir * minf(dist, 120.0 * at + 9000.0) + dir.orthogonal() * rng.randf_range(-5000.0, 5000.0)
		_fighter(card, _in_world(p), alt + 600.0, 2 if w > 0 or diff > 0.3 else 1, "time", at)
	card["lead"] = "Herkül nakliye uçağı %s bölgesindeki birliğe mühimmat götürüyor (%d km). Düşman avcıları yolu kesecek: nakliyeyi koru, varana kadar yanında kal. Herkül yavaş (430 km/sa), sen de yavaşta iyi uçmalısın." % [
		Front.region(String(card["region"])).get("name", ""), int(dist / 1000.0)]


static func _t_kurtarma(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var site := _land(rng, c, 500.0, 3500.0)
	card["target_xz"] = site
	card["site"] = site
	var from := _land(rng, site + _enemy_dir(site) * rng.randf_range(4000.0, 5500.0), 0.0, 600.0)
	_unit(card, "hunters", from, true, {"n": 2 + int(diff * 2.0), "to": site})
	if rng.randf() < 0.3 + diff * 0.4:
		_unit(card, "manpads", site.lerp(from, 0.5) + _polar(rng, 100.0, 500.0))
	if diff > 0.5:
		_fighter(card, site + _enemy_dir(site) * 9000.0, 2000.0, 1, "near", 6.0)
	if rng.randf() < 0.3:
		card["runway_m"] = snappedf(rng.randf_range(700.0, 1000.0), 50.0)
	var town := _town_near(site)
	card["lead"] = "Pilotumuz %s%s paraşütle indi, telsizi açık. Düşman arama timi (%d araç) yolda. Helikopter gelene kadar bölgeyi koru: araçları pilotun 250 m yakınına sokma. Yavaş ve alçakta iyi dönen, topu olan bir uçak işini kolaylaştırır." % [
		("%s yakınında, " % town) if town != "" else "", _where(card, site), 2 + int(diff * 2.0)]


static func _t_yuk(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var site := _hill(rng, c, 5000.0)
	card["target_xz"] = site
	card["site"] = site
	var n := 2 + int(diff * 2.0)
	var radius := snappedf(lerpf(160.0, 100.0, clampf(diff, 0.0, 1.0)), 10.0)
	card["crates"] = n
	card["zone_m"] = radius
	card["payload_kg"] = n * CargoModule.CRATE_MASS
	if diff > 0.3 and rng.randf() < 0.6:
		_unit(card, "manpads", site + _enemy_dir(site) * rng.randf_range(1500.0, 2500.0))
	if rng.randf() < 0.35:
		card["runway_m"] = snappedf(rng.randf_range(600.0, 900.0), 50.0)
	card["lead"] = ("Dağdaki" if _h(site) > 300.0 else "Tepedeki") + " karakol (%d m) kuşatıldı, %s. %d sandık mühimmat ve ilaç bırak (%s): sandıklar %d m'lik bölgeye inmeli. Vadi dar; yavaş ve çevik uçman gerek." % [
		int(_h(site)), _where(card, site), n, _kg(n * CargoModule.CRATE_MASS), int(radius)]


static func _t_kesif(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var pts := []
	for i in 3:
		pts.append(_land(rng, c + Vector2.from_angle(TAU * i / 3.0 + rng.randf()) * rng.randf_range(1500.0, 4500.0), 0.0, 600.0))
	card["points"] = pts
	card["target_xz"] = pts[0]
	var agl := snappedf(rng.randf_range(250.0, 600.0), 50.0)
	card["agl_max"] = agl
	card["rtb"] = true
	_unit(card, "aaa", (pts[rng.randi() % 3] as Vector2) + _polar(rng, 300.0, 700.0))
	if diff > 0.3 or rng.randf() < 0.35:
		_unit(card, "radar", _land(rng, c + _enemy_dir(c) * 5000.0, 0.0, 900.0))
	if diff > 0.5:
		_unit(card, "sam", _land(rng, c, 0.0, 2000.0))
	card["lead"] = "%s bölgesinde düşman yığınağı var mı, görmemiz lazım: üç noktanın üzerinden yerden %d m'nin altında geç, fotoğrafları üsse getir." % [
		Front.region(String(card["region"])).get("name", ""), int(agl)]


static func _t_gemi(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var t := _sea(rng, c, 4000.0)
	card["target_xz"] = t
	var n := 2 + (1 if diff > 0.6 else 0)
	for i in n:
		var p := _sea(rng, t + Vector2.from_angle(TAU * i / n) * 1800.0, 600.0) if i > 0 else t
		_unit(card, "frigate" if (i == 0 and diff > 0.45) else "ship", p, true, {"heading": rng.randf() * TAU})
	if diff > 0.5:
		_fighter(card, t + _enemy_dir(t) * 9000.0, 3000.0, 2, "alert")
	card["lead"] = "%s açıklarında %d düşman gemisi %s seyrediyor. Her biri SAM (12–16 km) ve gelen füzeyi düşüren yakın savunma topu taşıyor. Hepsini batır: gemi savar füze ya da ağır bomba." % [
		Front.region(String(card["region"])).get("name", ""), n, _where(card, t)]
	_maybe_tanker(card, rng)


static func _t_derin(card: Dictionary, rng: RandomNumberGenerator, c: Vector2, diff: float) -> void:
	var t := _land(rng, c + (c - BASE_XZ).normalized() * rng.randf_range(2000.0, 5000.0), 0.0, 1500.0)
	card["target_xz"] = t
	card["rtb"] = true
	var n := 2 + (1 if diff > 0.4 else 0)
	for i in n:
		_unit(card, "depot", t + _polar(rng, 0.0, 700.0) if i > 0 else t, true, {"hp": 1500.0, "name": "Mühimmat deposu"})
	card["payload_kg"] = n * 250.0
	var dir := (t - BASE_XZ).normalized()
	_unit(card, "radar", _land(rng, BASE_XZ.lerp(t, rng.randf_range(0.45, 0.65)) + dir.orthogonal() * rng.randf_range(-2500.0, 2500.0), 0.0, 600.0))
	for i in 1 + int(diff * 1.5):
		_unit(card, "sam", _land(rng, t + _polar(rng, 600.0, 1500.0), 0.0, 300.0))
	for i in 1 + int(diff * 2.0):
		_unit(card, "manpads", t + _polar(rng, 400.0, 1200.0))
	_unit(card, "aaa", t + _polar(rng, 200.0, 500.0))
	_fighter(card, t + _enemy_dir(t) * 9000.0, 3000.0, 1 + int(diff * 1.5), "alert")
	card["lead"] = "%s derinliklerinde %d mühimmat deposu, %s. Yolda bir erken uyarı radarı var: görülürsen avcı kalkar. Radarın altından gir, depoları vur ve üsse dön." % [
		Front.region(String(card["region"])).get("name", ""), n, _where(card, t)]
	_maybe_tanker(card, rng)


## Uzun rotada bazen dost tanker bekler (yolun ortasında, ikmal probu gerekir).
static func _maybe_tanker(card: Dictionary, rng: RandomNumberGenerator) -> void:
	var t: Vector2 = card["target_xz"]
	if t.length() > 20000.0 and rng.randf() < 0.55:
		card["tanker"] = true
		card["tanker_xz"] = BASE_XZ.lerp(t, 0.35) + (t - BASE_XZ).normalized().orthogonal() * 3000.0


# ------------------------------------------------------------------ kartı tamamla

static func _finish_card(card: Dictionary, rng: RandomNumberGenerator) -> void:
	var tpl := String(card["template"])
	var t: Vector2 = card["target_xz"]
	var far := t.length()
	for p: Vector2 in card.get("points", []):
		far = maxf(far, p.length())
	card["range_km"] = snappedf(far / 1000.0, 0.1)
	if tpl == "onleme":
		card["range_km"] = snappedf((t.lerp(card["defend_xz"], 0.5) - BASE_XZ).length() / 1000.0, 0.1)
	# tehdit özeti
	var count := {}
	for u: Dictionary in card["units"]:
		var k := String(u["type"])
		var kind: String = {"sam": "sam", "lrsam": "lrsam", "aaa": "aaa", "manpads": "aaa", "radar": "radar", "ship": "ship", "frigate": "ship"}.get(k, "")
		var n := 1
		if k == "convoy":
			kind = "aaa"
			n = int(u.get("escort", 0))
			k = "escort"
		elif k == "hunters":
			kind = "aaa"
			n = int(u.get("n", 2))
		if kind == "" or n <= 0:
			continue
		var rk: float = RANGES.get(k, 3.0)
		var key := "%s|%s" % [kind, rk]
		if not count.has(key):
			count[key] = {"kind": "sam" if kind == "lrsam" else kind, "n": 0, "range_km": rk}
		count[key]["n"] += n
	var fn := 0
	for f: Dictionary in card["fighters"]:
		if f.get("role", "fighter") != "bomber":
			fn += int(f["n"])
	var threats: Array = count.values()
	if fn > 0:
		threats.append({"kind": "fighters", "n": fn, "range_km": 16.0 if card.get("enemy_ecm", false) else 8.0})
	card["threats"] = threats
	# ihtiyaçlar
	var needs := []
	if float(card["payload_kg"]) > 0.0:
		needs.append("cargo" if tpl == "yuk" else "payload")
	if float(card["range_km"]) > 22.0 or tpl in ["derin", "eskort"] and float(card["range_km"]) > 15.0:
		needs.append("range")
	if float(card["runway_m"]) < 1300.0:
		needs.append("short_runway")
	match tpl:
		"onleme":
			needs.append_array(["speed", "climb", "guns_or_missiles"])
		"yuk":
			needs.append_array(["low_slow", "agility"])
		"sam":
			needs.append("anti_radar")
		"gemi":
			needs.append("anti_ship")
		"kesif":
			needs.append("recon")
		"eskort", "kurtarma":
			needs.append_array(["guns_or_missiles", "low_slow"])
		"konvoy":
			needs.append("guns_or_missiles")
	card["needs"] = needs
	# ödül
	var tn := 0
	for th: Dictionary in threats:
		tn += int(th["n"])
	var base := float(TEMPLATES[tpl]["reward"])
	card["reward"] = int(snappedf(base * (1.0 + 0.6 * clampf(float(card["diff"]), 0.0, 1.2)) + 350.0 * tn, 100.0))
	_events(card, rng)
	# brifing metni
	var parts := PackedStringArray([String(card["lead"])])
	var tl := threat_text(card)
	if tl != "":
		parts.append("Bölgede: %s." % tl)
	if float(card["runway_m"]) < FULL_RUNWAY - 50.0:
		parts.append("Pist kısa (%d m): krater onarımı sürüyor, kalkış koşun buna sığmalı." % int(card["runway_m"]))
	if float(card["range_km"]) > 18.0 and tpl != "onleme":
		parts.append("Dönüşte tanker (Deve) rotanın üçte birinde bekliyor; ikmal probu gerekir." if card["tanker"] else "Dönüşte ikmal yok.")
	if float(card["time_limit_s"]) > 0.0 and tpl != "onleme":
		parts.append("Süre %d dakika." % int(float(card["time_limit_s"]) / 60.0))
	var env := "Gece" if card["night"] else "Saat %s" % Weather.format_hour(float(card["hour"]))
	parts.append("%s, hava %s." % [env, String(Weather.PRESETS[int(card["weather"])]["name"]).to_lower()])
	card["brief"] = " ".join(parts)
	card.erase("lead")


## "2 SAM (9 km), 3 uçaksavar (3 km), 2 avcı"
static func threat_text(card: Dictionary) -> String:
	var out := PackedStringArray()
	for th: Dictionary in card.get("threats", []):
		var n := int(th["n"])
		var rk := float(th["range_km"])
		match String(th["kind"]):
			"sam":
				out.append("%d %s (%d km)" % [n, "uzun menzilli SAM" if rk > 20.0 else "SAM", int(rk)])
			"aaa":
				out.append("%d uçaksavar / makineli (%.1f km)" % [n, rk] if rk < 2.0 else "%d uçaksavar (%d km)" % [n, int(rk)])
			"radar":
				out.append("%d erken uyarı radarı (%d km)" % [n, int(rk)])
			"ship":
				out.append("%d savaş gemisi" % n)
			"fighters":
				out.append("%d düşman avcı" % n)
	return ", ".join(out)


static func _kg(kg: float) -> String:
	return ("%.1f ton" % (kg / 1000.0)).replace(".0 ton", " ton") if kg >= 1000.0 else "%d kg" % int(kg)


## Görev içi olaylar (0–2): hedef yer değiştirir, pusu, düşen dost pilot, tanker iptali.
static func _events(card: Dictionary, rng: RandomNumberGenerator) -> void:
	var tpl := String(card["template"])
	var cands := []
	if tpl in ["sam", "derin", "kesif", "yuk"]:
		cands.append("relocate")
	if tpl != "yuk":
		cands.append("ambush")
	if not tpl in ["kurtarma", "onleme"]:
		cands.append("downed")
	if card["tanker"]:
		cands.append("tanker_cancel")
	var roll := rng.randf()
	var n := 0 if roll < 0.35 else (1 if roll < 0.8 else 2)
	var t: Vector2 = card["target_xz"]
	var evs := []
	for i in mini(n, cands.size()):
		var k: String = cands.pop_at(rng.randi() % cands.size())
		match k:
			"relocate":
				var d := _polar(rng, 2000.0, 3500.0)
				if tpl == "yuk":
					d = _hill(rng, t + d, 1200.0) - t
				evs.append({"kind": k, "trigger": "near", "v": 13.0, "delta": d})
			"ambush":
				evs.append({"kind": k, "trigger": "time", "v": snappedf(rng.randf_range(70.0, 200.0), 5.0), "n": 2 + rng.randi() % 3})
			"downed":
				var mid := BASE_XZ.lerp(t, rng.randf_range(0.4, 0.7)) + (t - BASE_XZ).normalized().orthogonal() * rng.randf_range(-3000.0, 3000.0)
				evs.append({"kind": k, "trigger": "time", "v": snappedf(rng.randf_range(90.0, 220.0), 5.0), "xz": _land(rng, mid, 0.0, 1500.0)})
			"tanker_cancel":
				evs.append({"kind": k, "trigger": "time", "v": snappedf(rng.randf_range(60.0, 150.0), 5.0)})
	card["events"] = evs


# ------------------------------------------------------------------ sabit görevler için kart

const STATIC_NEEDS := {
	"kara": ["payload", "guns_or_missiles"], "kesif": ["recon"], "it": ["agility", "guns_or_missiles"],
	"sam": ["anti_radar", "payload"], "heli": ["guns_or_missiles", "low_slow"], "ustunluk": ["guns_or_missiles", "range"],
	"onleme": ["speed", "climb", "guns_or_missiles"], "ikmal": ["low_slow"], "yolcu": [], "kurtarma": ["short_runway", "low_slow"],
	"kargo": ["cargo", "low_slow"], "filo": ["anti_ship", "range"], "firkateyn": ["anti_ship"], "devriye": ["anti_ship"],
	"sead": ["anti_radar"], "derin": ["payload", "range"], "ussaldiri": ["payload"], "uzak": ["range"], "deniz": ["anti_ship"],
	"nakliye": ["cargo"], "tasima": [],
}


static func _static_card(op: Dictionary) -> Dictionary:
	var id := String(op["mission"])
	var def := MissionManager.get_def(id)
	var info := MissionManager.briefing(id)
	var target := Vector2.ZERO
	for p: Array in info.get("points", []):
		if String(p[0]) != "Sen":
			target = p[1]
			break
	var threats := []
	for s: String in Front.INTEL.get(id, {}).get("threats", []):
		if s.contains("SAM"):
			threats.append({"kind": "sam", "n": 2, "range_km": 9.0})
		elif s.contains("uçaksavar") or s.contains("Uçaksavar"):
			threats.append({"kind": "aaa", "n": 2, "range_km": 3.0})
		elif s.contains("avcı") or s.contains("pilot") or s.contains("as"):
			threats.append({"kind": "fighters", "n": 1, "range_km": 8.0})
	return {"id": "static_" + id, "template": id, "title": def.get("title", id), "brief": def.get("brief", ""),
		"region": String(op.get("region", "")), "target_xz": target, "base_xz": BASE_XZ,
		"range_km": snappedf(target.length() / 1000.0, 0.1), "payload_kg": 500.0 if id in ["kara", "derin", "sam"] else 0.0,
		"runway_m": FULL_RUNWAY, "threats": threats, "time_limit_s": float(def.get("time", 0.0)),
		"target_alt_m": 4000.0 if id == "onleme" else 0.0, "target_mach": 0.5 if id == "onleme" else 0.0,
		"night": false, "weather": Weather.preset, "needs": STATIC_NEEDS.get(id, []),
		"reward": Career.mission_reward(int(def.get("level", 1))), "seed": absi(hash(id)), "events": [], "doctrine": [],
		"level": int(def.get("level", 1)), "combat": id in Front.COMBAT, "static": true}


# ------------------------------------------------------------------ test

## `--menu --missiongentest`: 30 kart (bölgeler × günler) üret ve yaz (kayıt yazılmaz).
static func run_test() -> void:
	Game.mode = "career"
	Front.new_campaign()
	var day0 := Career.day
	var seen := {}
	var n := 0
	for day in [1, 4, 8, 12, 16]:
		Career.day = day
		if day == 8:
			Career.front["ovakoy"] = Front.DOST
			Career.front["derekoy"] = Front.CEKISME
			Career.front["dogudeniz"] = Front.CEKISME
			Career.completed["egitim"] = 1
			Career.completed["kesif"] = 1
			FrontAI.spawn_threat("baskin")
			FrontAI.spawn_threat("konvoy")
		if day == 12:
			Career.doctrine = {"n": 4, "agl": 140.0, "mach": 0.95, "w": {"radar": 6.0, "ir": 1.0, "gun": 1.0, "bomb": 4.0, "arm": 0.0}, "bomb_agl": 3500.0, "ecm": 0.6, "chaff": 4.0}
		for op: Dictionary in Front.operations():
			if op["mission"] != "gen":
				continue
			var c: Dictionary = op["card"]
			seen[c["template"]] = int(seen.get(c["template"], 0)) + 1
			n += 1
			print("CARD d%d %-9s %-10s %s  hedef=(%.0f,%.0f) %.1f km  yük=%d kg  pist=%d m  süre=%d  alt=%d M%.2f  gece=%s hava=%d  ödül=%d  olay=%s%s" % [
				day, c["template"], c["region"], "ACİL" if op.get("urgent", false) else "    ",
				(c["target_xz"] as Vector2).x, (c["target_xz"] as Vector2).y, c["range_km"], int(c["payload_kg"]), int(c["runway_m"]),
				int(c["time_limit_s"]), int(c["target_alt_m"]), c["target_mach"], c["night"], c["weather"], c["reward"],
				",".join((c["events"] as Array).map(func(e: Dictionary) -> String: return e["kind"])), ""])
			print("     needs=%s  threats=%s" % [",".join(c["needs"]), threat_text(c)])
			print("     ", c["brief"])
			for l: String in c["doctrine"]:
				print("     ", l)
			# aynı tohum aynı kart
			var again := make_card(op.duplicate().merged({"card": {}}, true))
			if again["brief"] != c["brief"]:
				print("     !! DETERMINISM FAIL")
	print("MISSIONGEN cards=%d templates=%s" % [n, seen])
	Career.day = day0


# ------------------------------------------------------------------ arayüz yardımcıları

const NEED_TEXT := {"payload": "patlayıcı yükü", "range": "menzil", "short_runway": "kısa kalkış", "speed": "hız",
	"climb": "tırmanış", "agility": "çeviklik", "low_slow": "alçak ve yavaş uçuş", "anti_radar": "radar avcısı füze / chaff / ECM",
	"anti_ship": "gemi savar silah", "cargo": "kargo bölmesi", "recon": "alçakta kararlı uçuş", "guns_or_missiles": "top ya da füze"}


## Kartın kısıtları, kısa satırlar (cephe paneli, brifing, hangar).
static func constraint_lines(c: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("Menzil: %.0f km (tek yön)%s" % [float(c.get("range_km", 0.0)), "  ·  dönüşte tanker var" if c.get("tanker", false) else ("  ·  dönüşte ikmal yok" if float(c.get("range_km", 0.0)) > 18.0 else "")])
	if float(c.get("payload_kg", 0.0)) > 0.0:
		out.append("%s: en az %s" % ["Kargo" if c.get("template", "") == "yuk" else "Patlayıcı", _kg(float(c["payload_kg"]))])
	out.append("Pist: %d m%s" % [int(c.get("runway_m", FULL_RUNWAY)), "  (KISA)" if float(c.get("runway_m", FULL_RUNWAY)) < 1300.0 else ""])
	if float(c.get("target_alt_m", 0.0)) > 0.0:
		out.append("Hedef: %d m, Mach %.2f" % [int(c["target_alt_m"]), float(c.get("target_mach", 0.0))])
	if float(c.get("time_limit_s", 0.0)) > 0.0:
		out.append("Süre: %d:%02d" % [int(c["time_limit_s"]) / 60, int(c["time_limit_s"]) % 60])
	if c.has("agl_max"):
		out.append("Keşif irtifası: < %d m AGL" % int(c["agl_max"]))
	var env := "Gece" if c.get("night", false) else "Gündüz %s" % Weather.format_hour(float(c.get("hour", 12.0)))
	out.append("%s  ·  %s" % [env, Weather.PRESETS[int(c.get("weather", 0))]["name"]])
	var needs := PackedStringArray()
	for n: String in c.get("needs", []):
		needs.append(String(NEED_TEXT.get(n, n)))
	if not needs.is_empty():
		out.append("Gerekenler: " + ", ".join(needs))
	return out


## Cephe panelinin İSTİHBARAT bölümü: tehdit satırları ve öneri.
static func intel(c: Dictionary) -> Dictionary:
	var th := []
	for t: Dictionary in c.get("threats", []):
		th.append(threat_text({"threats": [t]}))
	var needs := PackedStringArray()
	for n: String in c.get("needs", []):
		needs.append(String(NEED_TEXT.get(n, n)))
	return {"threats": th, "advice": ("Tasarım: " + ", ".join(needs) + ".") if not needs.is_empty() else "Uçağı göreve göre hazırla."}
