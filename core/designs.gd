class_name Designs
extends RefCounted
## Oyuncunun tasarımları: prototip parça güvenilirliği, tasarım hizmet kayıtları ve seri üretim
## (filo tipi). Veri Career.designs_data içinde tutulur, yalnız Career.save ile yazılır
## (Crew._testing() testlerde kaydı engeller).
##
## • Prototip: Ar-Ge'de yeni açılan parça %60 güvenilirlikle başlar; o parçayla uçulan saat ve
##   görevlerle olgunlaşır (~%99). %95 üstü "olgun": arıza yok. Başlangıç parçaları ve eski
##   kayıtta zaten açık olanlar olgun sayılır. Arızaları PartFailures sürer.
## • Hizmet kaydı: tasarım başına uçuş, görev, başarı, düşürme, kayıp, saat, ilk uçuş günü.
## • Seri üretim: kalıp bedeli + birim bedeli (Career.craft_cost). Üretimdeki tasarım filo tipi
##   olur: kanat adamı (WingFlight) ve dost ortam devriyeleri (AmbientAir) onunla uçar.

const PROTO_START := 0.60
const MATURE := 0.95
const MAX_REL := 0.99
## Olgunlaşma: deneyim = saat + 0.5 × görev (+ arıza raporları); bu kadar deneyimde kalan payın %63'ü kapanır
const MATURE_SCALE := 2.0
const TOOLING_BASE := 5000

## Uçuş başı anlık değerler (begin_flight)
static var _start_kills := 0
## Bu uçuştaki prototip arızaları: parça id -> sayı (PartFailures yazar)
static var flight_failures := {}


static func _d() -> Dictionary:
	var d: Dictionary = Career.designs_data
	for k in ["rel", "rec", "prod"]:
		if not d.has(k) or typeof(d[k]) != TYPE_DICTIONARY:
			d[k] = {}
	if not d.has("fleet"):
		d["fleet"] = ""
	if Game.args.has("protodemo") and not d.has("demo"):
		# hangar ekran görüntüsü: birkaç prototip parça ve sahte hizmet kaydı (kayıt yazılmaz: *demo)
		d["demo"] = true
		for id in ["jet_engine_big", "radar_missile_rail", "targeting_pod"]:
			Career.unlocked[id] = true
		d["rel"]["jet_engine_big"] = {"h": 0.1, "m": 0.0}
		d["rel"]["radar_missile_rail"] = {"h": 0.5, "m": 2.0}
		d["rel"]["targeting_pod"] = {"h": 3.0, "m": 6.0}
		d["rec"]["ad:" + String(Game.args.get("demoname", "Kartal-1"))] = {"name": "Kartal-1", "flights": 17, "missions": 14,
			"success": 11, "kills": 9, "losses": 2, "hours": 4.6, "first_day": 3}
	return d


# ------------------------------------------------------------------ prototip güvenilirliği

## Ar-Ge'de yeni açılan parça prototip olarak başlar (Career.unlock çağırır).
static func on_research(id: String) -> void:
	if id in Career.STARTER_PARTS:
		return
	_d()["rel"][id] = {"h": 0.0, "m": 0.0}


static func reliability(id: String) -> float:
	var rel: Dictionary = _d()["rel"]
	if Career.sandbox() or not rel.has(id):
		return 1.0
	var r: Dictionary = rel[id]
	var exp_pts := float(r.get("h", 0.0)) + 0.5 * float(r.get("m", 0.0))
	return MAX_REL - (MAX_REL - PROTO_START) * exp(-exp_pts / MATURE_SCALE)


static func is_proto(id: String) -> bool:
	return reliability(id) < MATURE


## Hangar rozeti: "PROTOTİP %62" (olgunsa boş).
static func badge(id: String) -> String:
	return "PROTOTİP %%%d" % floori(reliability(id) * 100.0) if is_proto(id) else ""


## Parça ipucu satırı (tanımdan; tanımda id olmadığı için başlıktan bulunur).
static func tooltip_line(def: Dictionary) -> String:
	var title := String(def.get("title", ""))
	for id: String in _d()["rel"]:
		if String(PartLibrary.get_def(id).get("title", "")) == title:
			var r := reliability(id)
			if r < MATURE:
				return "⚠ PROTOTİP — güvenilirlik %%%d (uçtukça olgunlaşır; uçuşta arıza yapabilir)" % floori(r * 100.0)
			return "Olgun parça — güvenilirlik %%%d" % floori(r * 100.0)
	return ""


## Uçaktaki prototip parça id'leri (tekrarsız).
static func proto_parts_in(craft: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in craft.get("parts", []):
		var id := String(e.get("part", ""))
		if is_proto(id) and not id in out:
			out.append(id)
	return out


# ------------------------------------------------------------------ tasarım kimliği ve kayıt

static func key(craft: Dictionary) -> String:
	var id := String(craft.get("design_id", ""))
	return id if id != "" else "ad:" + String(craft.get("name", "İsimsiz"))


## Kaydederken kalıcı kimlik ver (yeni ad = yeni tasarım). İsimle tutulan eski kayıt taşınır.
static func ensure_id(craft: Dictionary) -> void:
	var name := String(craft.get("name", "İsimsiz"))
	if String(craft.get("design_id", "")) != "" and String(craft.get("design_name", "")) == name:
		return
	var id := "%s_%d" % [name.validate_filename().to_lower(), int(Time.get_unix_time_from_system()) % 1000000]
	var rec: Dictionary = _d()["rec"]
	if rec.has("ad:" + name) and not rec.has(id):
		rec[id] = rec["ad:" + name]
		rec.erase("ad:" + name)
	craft["design_id"] = id
	craft["design_name"] = name


static func record(craft: Dictionary) -> Dictionary:
	return _d()["rec"].get(key(craft), {})


static func _new_record(name: String) -> Dictionary:
	return {"name": name, "flights": 0, "missions": 0, "success": 0, "kills": 0, "losses": 0, "hours": 0.0, "first_day": Career.day}


## "Kartal-3: 14 görev, 9 düşürme, 2 kayıp" (kayıt yoksa boş).
static func service_line(craft: Dictionary) -> String:
	var r := record(craft)
	if r.is_empty():
		return ""
	return "%s: %d görev (%d başarılı), %d düşürme, %d kayıp · %d uçuş, %.1f sa · ilk uçuş %d. gün" % [
		String(craft.get("name", r.get("name", ""))), int(r.get("missions", 0)), int(r.get("success", 0)),
		int(r.get("kills", 0)), int(r.get("losses", 0)), int(r.get("flights", 0)), float(r.get("hours", 0.0)),
		int(r.get("first_day", 1))]


static func short_line(craft: Dictionary) -> String:
	var r := record(craft)
	if r.is_empty():
		return ""
	return "%d görev · %d düşürme · %d kayıp" % [int(r.get("missions", 0)), int(r.get("kills", 0)), int(r.get("losses", 0))]


## Hangar istatistik panelinin altına eklenecek blok.
static func stats_block(craft: Dictionary) -> String:
	var lines := PackedStringArray()
	var s := service_line(craft)
	if s != "":
		lines.append("Hizmet geçmişi: " + s)
	if is_fleet(craft):
		lines.append("SERİ ÜRETİMDE — filo tipi (kanat adamı ve dost devriyeler)")
	var protos := proto_parts_in(craft)
	if not protos.is_empty():
		var items := PackedStringArray()
		for id in protos:
			items.append("%s %%%d" % [PartLibrary.get_def(id).get("title", id), floori(reliability(id) * 100.0)])
		lines.append("Prototip parçalar: " + ", ".join(items))
	return "" if lines.is_empty() else "\n\n" + "\n".join(lines)


## Uçuş başında (main._spawn).
static func begin_flight(_craft: Dictionary) -> void:
	_start_kills = int(Crew.current().get("kills", 0))
	flight_failures = {}


## Uçuş bitti (main.close_flight, Crew.end_flight'tan önce). Döndürür: rapor satırları.
static func note_flight(craft: Dictionary, main: Node, killed: bool) -> PackedStringArray:
	var out := PackedStringArray()
	if craft.is_empty() or Career.sandbox():
		return out
	var hours := float(main.get("_time")) / 3600.0
	if hours < 0.01:
		return out   # kalkmadan kapatılan / kayıttan dönülen uçuş
	var mission: Variant = main.get("mission")
	var has_mission: bool = mission != null and not (mission.def as Dictionary).is_empty()
	var success: bool = has_mission and mission.state == "success"
	var test: bool = Game.test_flight
	# prototip parçalar olgunlaşır (test uçuşunda yarı hızda: simülatör verisi)
	var rel: Dictionary = _d()["rel"]
	for id in proto_parts_in(craft):
		var before := reliability(id)
		var r: Dictionary = rel[id]
		r["h"] = float(r.get("h", 0.0)) + hours * (0.5 if test else 1.0)
		r["m"] = float(r.get("m", 0.0)) + (0.0 if test or not has_mission else 1.0) + 0.5 * int(flight_failures.get(id, 0))
		var after := reliability(id)
		var t := String(PartLibrary.get_def(id).get("title", id))
		if after >= MATURE:
			out.append("%s artık OLGUN (güvenilirlik %%%d)." % [t, floori(after * 100.0)])
		else:
			out.append("Prototip %s: güvenilirlik %%%d → %%%d" % [t, floori(before * 100.0), floori(after * 100.0)])
	if test:
		Career.save()
		return out
	# hizmet kaydı
	var k := key(craft)
	var recs: Dictionary = _d()["rec"]
	if not recs.has(k):
		recs[k] = _new_record(String(craft.get("name", "İsimsiz")))
	var r: Dictionary = recs[k]
	var kills := maxi(int(Crew.current().get("kills", 0)) - _start_kills, 0)
	kills += int(Crew.flight_stats.get("ground_kills", 0)) + int(Crew.flight_stats.get("ships", 0))
	var lost: bool = killed or bool(main.get("_ejected")) or int(main.get("money_lost")) > 0
	r["flights"] = int(r.get("flights", 0)) + 1
	r["hours"] = float(r.get("hours", 0.0)) + hours
	r["kills"] = int(r.get("kills", 0)) + kills
	if has_mission:
		r["missions"] = int(r.get("missions", 0)) + 1
	if success:
		r["success"] = int(r.get("success", 0)) + 1
	if lost:
		r["losses"] = int(r.get("losses", 0)) + 1
	if has_mission:
		out.append("%s hizmet kaydı: %d. görev%s" % [String(craft.get("name", "")), int(r["missions"]), " (uçak kaybı)" if lost else ""])
	else:
		out.append("%s hizmet kaydı: %d. uçuş" % [String(craft.get("name", "")), int(r["flights"])])
	# kanat adamı filo tipiyle uçtuysa onun kaydına da işlenir
	var wf: Variant = WingFlight.active
	if is_instance_valid(wf) and wf.has_meta("design_key") and String(wf.get_meta("design_key")) != k:
		var fk := String(wf.get_meta("design_key"))
		if not recs.has(fk):
			recs[fk] = _new_record(String(wf.get_meta("design_name", "")))
		var fr: Dictionary = recs[fk]
		fr["flights"] = int(fr.get("flights", 0)) + 1
		fr["hours"] = float(fr.get("hours", 0.0)) + hours
		fr["kills"] = int(fr.get("kills", 0)) + int(wf.kills)
		if has_mission:
			fr["missions"] = int(fr.get("missions", 0)) + 1
		if success:
			fr["success"] = int(fr.get("success", 0)) + 1
		if String(wf.outcome) in ["kayıp", "yaralı", "fırlattı"]:
			fr["losses"] = int(fr.get("losses", 0)) + 1
	Career.save()
	return out


# ------------------------------------------------------------------ seri üretim / filo

## Filoya uygun mu: kokpit, motor, kanat ve silah. Döndürür: engel nedeni (yoksa boş).
static func flyable(craft: Dictionary) -> String:
	var has := {}
	var mass := 0.0
	var thrust := 0.0
	for e: Dictionary in craft.get("parts", []):
		var def := PartLibrary.get_def(String(e.get("part", "")))
		var n := 2 if e.get("mirror", false) else 1
		mass += float(def.get("mass", 0.0)) * n
		for m: Dictionary in def.get("modules", []):
			var t := String(m.get("type", ""))
			has[t] = true
			if t == "engine":
				thrust += float(m.get("max_thrust", 0.0)) * n
			elif t == "fuel_tank":
				mass += float(m.get("capacity", 0.0)) * n
	if not has.has("cockpit"):
		return "kokpit yok"
	if thrust <= 0.0:
		return "motor yok"
	if not (has.has("wing") or has.has("wing_sections")):
		return "kanat yok"
	if not (has.has("gun") or has.has("missile")):
		return "silahsız (top ya da füze gerekir)"
	if thrust / maxf(mass * 9.81, 1.0) < 0.3:
		return "itki çok düşük"
	return ""


static func production_cost(craft: Dictionary) -> Dictionary:
	var unit := Career.craft_cost(craft)
	var tooling := TOOLING_BASE + unit / 4
	return {"unit": unit, "tooling": tooling, "total": 0 if Career.sandbox() else unit + tooling}


static func is_fleet(craft: Dictionary) -> bool:
	return String(_d()["fleet"]) != "" and String(_d()["fleet"]) == String(craft.get("design_id", "-"))


## Seri üretime al. Döndürür: hata (yoksa boş). Tasarımın kimliği olmalı (ensure_id).
static func produce(craft: Dictionary) -> String:
	var why := flyable(craft)
	if why != "":
		return "Seri üretime uygun değil: " + why
	if not Career.locked_parts_in(craft).is_empty():
		return "Kilitli parça var (Ar-Ge gerekir)"
	var c := production_cost(craft)
	if Career.money < int(c["total"]):
		return "Para yetmiyor (%d ₺ gerekir)" % int(c["total"])
	if String(craft.get("design_id", "")) == "":
		ensure_id(craft)
	Career.money -= int(c["total"])
	var snap := craft.duplicate(true)
	snap.erase("wear")
	_d()["prod"][String(craft["design_id"])] = {"name": String(craft.get("name", "")), "craft": snap, "day": Career.day}
	_d()["fleet"] = String(craft["design_id"])
	_q_time = -100000
	Career.save()
	Career.changed.emit()
	return ""


static func fleet_name() -> String:
	var p: Dictionary = _d()["prod"].get(String(_d()["fleet"]), {})
	return String(p.get("name", ""))


## Filo tipinin uçak sözlüğü (kopya); yoksa ya da uçamazsa {}.
static func fleet_craft() -> Dictionary:
	var p: Dictionary = _d()["prod"].get(String(_d()["fleet"]), {})
	var c: Dictionary = p.get("craft", {})
	if c.is_empty() or flyable(c) != "":
		return {}
	return c.duplicate(true)


## Kanat adamının uçağı: filo tipi varsa o, yoksa liderin uçağının kopyası.
static func wing_craft(lead_craft: Dictionary) -> Dictionary:
	var f := fleet_craft()
	return f if not f.is_empty() else lead_craft.duplicate(true)


## Filo tipinin kalitesi 0..1 (silah, sensör, itki/ağırlık, hizmet başarısı). Filo yoksa 0.
static var _q_cache := -1.0
static var _q_time := -100000

static func fleet_quality() -> float:
	if Time.get_ticks_msec() - _q_time < 5000 and _q_cache >= 0.0:
		return _q_cache
	_q_time = Time.get_ticks_msec()
	_q_cache = _fleet_quality()
	return _q_cache


static func _fleet_quality() -> float:
	var c := fleet_craft()
	if c.is_empty():
		return 0.0
	var q := 0.0
	var missiles := 0
	var mass := 0.0
	var thrust := 0.0
	for e: Dictionary in c.get("parts", []):
		var def := PartLibrary.get_def(String(e.get("part", "")))
		var n := 2 if e.get("mirror", false) else 1
		mass += float(def.get("mass", 0.0)) * n
		for m: Dictionary in def.get("modules", []):
			match String(m.get("type", "")):
				"gun":
					q = maxf(q, 0.2)
				"missile":
					missiles += n
				"radar":
					q += 0.05
				"engine":
					thrust += float(m.get("max_thrust", 0.0)) * n
				"fuel_tank":
					mass += float(m.get("capacity", 0.0)) * 0.5 * n
	q += minf(missiles, 4) * 0.1
	q += clampf((thrust / maxf(mass * 9.81, 1.0) - 0.5) * 0.5, 0.0, 0.25)
	var r: Dictionary = _d()["rec"].get(String(_d()["fleet"]), {})
	var ms := int(r.get("missions", 0))
	if ms > 0:
		q += 0.1 * float(r.get("success", 0)) / ms - 0.1 * float(r.get("losses", 0)) / ms
	return clampf(q, 0.0, 1.0)


# ------------------------------------------------------------------ testler

## --servicetest: sahte uçuşlar işle, kayıtları ve prototip olgunlaşmasını yazdır (diske yazılmaz).
static func run_service_test() -> void:
	var craft := {"name": "Kartal-3", "parts": [{"part": "cockpit_mk1"}, {"part": "jet_engine_big"},
		{"part": "wing_main", "mirror": true}, {"part": "gun_pod"}, {"part": "radar_missile_rail", "mirror": true}]}
	on_research("jet_engine_big")
	on_research("radar_missile_rail")
	on_research("jet_engine")   # başlangıç parçası: prototip olmamalı
	print("SERVICE rozetler: big=%s rail=%s jet=%s" % [badge("jet_engine_big"), badge("radar_missile_rail"), badge("jet_engine")])
	var fake := _FakeMain.new()
	fake._time = 300.0
	print("SERVICE kimliksiz: ", " | ".join(note_flight(craft, fake, false)))
	ensure_id(craft)   # isimle tutulan kayıt kimliğe taşınmalı
	print("SERVICE id=%s  taşınan kayıt: %s" % [craft["design_id"], service_line(craft)])
	for i in 8:
		fake._time = 600.0 + i * 60.0
		fake.money_lost = 1 if i == 3 else 0
		fake.mission = _FakeMission.new("success" if i % 3 != 2 else "fail")
		if i == 1:
			flight_failures = {"jet_engine_big": 1}
		var lines := note_flight(craft, fake, false)
		flight_failures = {}
		print("SERVICE görev %d: %s" % [i + 1, " | ".join(lines)])
	print("SERVICE kayıt: ", service_line(craft))
	print("SERVICE kısa: ", short_line(craft))
	print("SERVICE blok: ", stats_block(craft).strip_edges())
	print("SERVICE uygunluk: '%s'  maliyet: %s" % [flyable(craft), production_cost(craft)])
	fake.free()


class _FakeMission extends RefCounted:
	var def := {"id": "test"}
	var state := ""
	func _init(s: String) -> void:
		state = s


class _FakeMain extends Node:
	var _time := 600.0
	var mission: Variant = null
	var _ejected := false
	var money_lost := 0
