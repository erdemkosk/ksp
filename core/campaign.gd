class_name Campaign
## Üç perdelik kariyer hikâyesi; kahraman oyuncunun tasarladığı uçak:
##   Perde 1 · SAVUNMA        — az parça, kısa menzil: önleme ve yakın destekle ev bölgelerini tut.
##   Perde 2 · KARŞI TAARRUZ  — menzil ve yük: SAM ağı, filo, Kuzeykent. Ar-Ge'de uzun menzil parçaları.
##   Perde 3 · SON DARBE      — düşman ası Kara Doğan (Ace) ve karargâhı Kuzey Havaalanı.
## Perde hedefleri cepheye (Front) bağlı; görev sonunda (Front.mission_result → on_mission) bakılır.
## Geçişte karargâh brifingi: Alb. Kaya, dinlenen düşman telsizi ve filo arkadaşlarından sayfalar
## (Career.news'e "from" alanıyla; kariyer ekranı ayrıca sinematik bir kaplama gösterir).
## Perde kapıları sorgulanabilir: act(), allows(görev, bölge), mission_weights(), part_act(parça).
##
## Durum Career.campaign'de (career.json). Eski kayıtta yoksa cepheden makul perde çıkarılır.

const ACTS := {
	1: {"title": "SAVUNMA", "tag": "Evi koru: önleme ve yakın destek"},
	2: {"title": "KARŞI TAARRUZ", "tag": "Menzil ve yük: SAM ağı, filo, Kuzeykent"},
	3: {"title": "SON DARBE", "tag": "Kara Doğan ve düşman karargâhı"},
}
const HOME := ["anaus", "sahil", "bati"]
const DEEP := ["derekoy", "kuzeykent", "kuzeyhava", "dogudeniz"]
const HQ_REGION := "kuzeyhava"
const DEF_WINS := 4
const FINALE := "sondarbe"
## Konuşanlar (brifing sayfası başlığı)
const SPEAKERS := {
	"kaya": "Alb. Kaya, Hava Harekât Merkezi",
	"enemy": "DİNLENEN TELSİZ  ·  Gen. Volkan Sert, Kuzey Ordusu",
	"ace": "AÇIK FREKANS  ·  Kara Doğan",
	"ece": "Yzb. Ece Polat, filo komutan yardımcısı",
	"deniz": "Ütğm. Deniz Arslan (Kartal-3)",
}
## Ar-Ge'de bu perdeden önce açılamayan parçalar (diğerleri Perde 1'den açık)
const PART_ACT := {
	"drop_tank": 2, "refuel_probe": 2, "wingtip_tank": 2, "jet_engine_big": 2, "twin_adapter": 2,
	"turbofan": 2, "bomb_bay": 2, "harm_rail": 2, "ship_missile_rail": 2, "lgb_rail": 2, "targeting_pod": 2,
	"cargo_bay_heavy": 2, "gear_main_heavy": 2, "gear_nose_heavy": 2, "tail_turret": 2,
	"gear_main_tandem": 2, "gear_nose_short": 2,
	"ramjet": 3, "jet_engine_tvc": 3, "cruise_missile_rail": 3, "awacs_dome": 3, "nose_chine": 3,
	"lifting_body": 3, "tail_v": 3, "rocket_engine": 3,
}
## Görev üreticisi / harekât listesi için perde ağırlıkları (yoksa 1)
const WEIGHTS := {
	1: {"onleme": 3.0, "kara": 2.5, "it": 1.5, "kesif": 1.5, "heli": 1.0, "devriye": 1.5, "ustunluk": 0.5,
		"sam": 0.0, "sead": 0.0, "derin": 0.0, "ussaldiri": 0.0, "uzak": 0.0, "filo": 0.0, "firkateyn": 0.0, FINALE: 0.0},
	2: {"sam": 3.0, "sead": 3.0, "filo": 2.5, "firkateyn": 2.0, "derin": 2.0, "kara": 1.5, "ustunluk": 1.5,
		"onleme": 1.0, "deniz": 1.5, "ussaldiri": 1.0, "uzak": 0.5, FINALE: 0.0},
	3: {FINALE: 5.0, "ussaldiri": 3.0, "uzak": 2.5, "ustunluk": 2.5, "derin": 2.0, "it": 1.5, "onleme": 0.5},
}
## Asın görünebileceği (havada savaş) görevler
const ACE_MISSIONS := ["onleme", "kara", "it", "kesif", "heli", "ustunluk", "sam", "sead", "derin", "ussaldiri",
	"filo", "firkateyn", "devriye", "deniz", "uzak", "gen"]

## Uçuş içi hikâye satırı (görev sonucu kaydedilmeden önce gelen as karşılaşması)
static var _pending_beat := ""
static var _flight_done := false


static func st() -> Dictionary:
	if Career.campaign.is_empty():
		Career.campaign = _infer()
	elif not Career.campaign.has("_v"):
		# kısmi / eski biçim: eksik alanları tamamla
		var b := _blank(int(Career.campaign.get("act", 1)))
		Career.campaign.merge(b, false)
		(Career.campaign["ace"] as Dictionary).merge(b["ace"], false)
		(Career.campaign["stats"] as Dictionary).merge(b["stats"], false)
	return Career.campaign


static func act() -> int:
	return int(st().get("act", 1))


static func act_title(a := -1) -> String:
	a = act() if a < 0 else a
	return "PERDE %d  ·  %s" % [a, ACTS[a]["title"]]


static func ace() -> Dictionary:
	return st()["ace"]


static func ace_defeated() -> bool:
	return bool(ace().get("defeated", false))


static func won() -> bool:
	return bool(st().get("won", false))


static func _blank(a := 1) -> Dictionary:
	return {"act": a, "_v": 1, "act_day": {"1": 1}, "def_wins": 0, "act_missions": 0, "flags": {},
		"ace": {"encounters": [], "cameo": false, "hunts": 0, "last_hunt": -9, "defeated": false, "downed": 0},
		"stats": {"missions": 0, "wins": 0, "fails": 0}, "won": false, "brief": a, "victory_seen": false}


## Yeni sefer (Front.new_campaign): Perde 1 ve açılış brifingi.
static func reset() -> void:
	Career.campaign = _blank(1)
	_pending_beat = ""
	_brief_pages(1)


## Eski kayıt (perde durumu yok): cephe durumundan perdeyi çıkar. Brifing yeniden gösterilir.
static func _infer() -> Dictionary:
	var a := 1
	var own := func(id: String) -> bool: return Front.owner(id) == Front.DOST
	if own.call("kuzeykent") or (own.call("derekoy") and own.call("dogudeniz")):
		a = 3
	elif (own.call("ovakoy") or own.call("orta")) and Front.count(Front.DOST) >= 4:
		a = 2
	var d := _blank(a)
	d["act_day"] = {str(a): Career.day}
	d["ace"]["cameo"] = a > 1
	return d


# ------------------------------------------------------------------ hedefler

## Perde hedefleri: [{text, done}]
static func goals(a := -1) -> Array:
	a = act() if a < 0 else a
	var s := st()
	var o := func(id: String) -> int: return Front.owner(id)
	match a:
		1:
			var home := HOME.all(func(id: String) -> bool: return o.call(id) == Front.DOST)
			var w := mini(int(s["def_wins"]), DEF_WINS)
			return [{"text": "Ev bölgelerini tut (Ana Üs, Güney Sahili, Batı Tepeleri)", "done": home},
				{"text": "Savunma harekâtı kazan (%d/%d)" % [w, DEF_WINS], "done": w >= DEF_WINS},
				{"text": "Ovaköy Yolu ya da Orta Vadi'yi geri al", "done": o.call("ovakoy") == Front.DOST or o.call("orta") == Front.DOST}]
		2:
			var f: Dictionary = s["flags"]
			return [{"text": "Dereköy SAM ağını çökert (SAM / SEAD harekâtı)", "done": bool(f.get("sam_net", false)) or o.call("derekoy") == Front.DOST},
				{"text": "Doğu Denizi filosunu batır (Filo / Fırkateyn)", "done": bool(f.get("fleet", false)) or o.call("dogudeniz") == Front.DOST},
				{"text": "Kuzeykent'i al", "done": o.call("kuzeykent") == Front.DOST}]
		_:
			return [{"text": "Kara Doğan'ı düşür (Son Darbe harekâtı)", "done": ace_defeated()},
				{"text": "Kuzey Havaalanı'nı (düşman karargâhı) al", "done": o.call(HQ_REGION) == Front.DOST}]


static func act_complete(a := -1) -> bool:
	return goals(a).all(func(g: Dictionary) -> bool: return g["done"])


# ------------------------------------------------------------------ kapılar (görev üreticisi de okur)

## Bu görev bu bölgede şu perdede yapılabilir mi? Acil (FrontAI) görevler hep açıktır.
static func allows(mission_id: String, region_id := "") -> bool:
	if Career.sandbox():
		return true
	var a := act()
	if mission_id == FINALE:
		return a >= 3 and not ace_defeated()
	if float(WEIGHTS[a].get(mission_id, 1.0)) <= 0.0:
		return false
	if a == 1 and region_id in DEEP:
		return false
	if a == 2 and region_id == HQ_REGION:
		return false
	return true


## Görev şablonu → ağırlık (bu perdede; 0: kapalı). Listede olmayanlar 1.
static func mission_weights() -> Dictionary:
	return WEIGHTS[act()]


## Perdenin cepheye eklediği harekâtlar (Front.operations'a eklenir).
static func extra_ops() -> Array:
	var out := []
	if Career.sandbox():
		return out
	var a := act()
	if a >= 2 and not bool(st()["flags"].get("sam_net", false)) and Front.owner("derekoy") != Front.DOST and Front.attackable("derekoy"):
		out.append({"mission": "sead", "region": "derekoy", "combat": true, "campaign": true})
	if a >= 3 and not ace_defeated():
		out.append({"mission": FINALE, "region": HQ_REGION, "combat": true, "campaign": true, "ace": true})
	return out


## Parçanın Ar-Ge'de açılabildiği perde.
static func part_act(id: String) -> int:
	return int(PART_ACT.get(id, 1))


static func part_allowed(id: String) -> bool:
	return Career.sandbox() or part_act(id) <= act()


## Ar-Ge kilidi açıklaması (boşsa açılabilir).
static func part_lock_reason(id: String) -> String:
	if part_allowed(id):
		return ""
	return "Bu parça %s ile Ar-Ge'ye açılır." % act_title(part_act(id))


# ------------------------------------------------------------------ görev sonu

## Front.mission_result içinden (gerçek kariyer görevi): sayaçlar, bayraklar, perde geçişi.
## Döndürür: uçuş raporu satırları (en çok bir "◆" hikâye satırı).
static func on_mission(mission_id: String, region_id: String, success: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var s := st()
	_flight_done = true
	var combat := mission_id in Front.COMBAT or mission_id in ["sead", "derin", "ussaldiri", "uzak", "deniz", FINALE, "gen"]
	s["stats"]["missions"] = int(s["stats"]["missions"]) + 1
	s["stats"]["wins" if success else "fails"] = int(s["stats"]["wins" if success else "fails"]) + 1
	if combat:
		s["act_missions"] = int(s["act_missions"]) + 1
	if success:
		if combat and act() == 1:
			s["def_wins"] = int(s["def_wins"]) + 1
		if mission_id in ["sam", "sead"]:
			s["flags"]["sam_net"] = true
		if mission_id in ["filo", "firkateyn"]:
			s["flags"]["fleet"] = true
	var beat := _pending_beat
	_pending_beat = ""
	# perde geçişi (görev başına en çok bir)
	var a := act()
	if a < 3 and act_complete(a):
		s["act"] = a + 1
		s["act_day"][str(a + 1)] = Career.day
		s["act_missions"] = 0
		s["brief"] = a + 1
		_brief_pages(a + 1)
		beat = "◆ %s başladı. %s" % [act_title(a + 1), ACTS[a + 1]["tag"]]
	elif a == 3 and act_complete(3) and not won():
		s["won"] = true
		_brief_pages(4)
		s["act_day"]["4"] = Career.day
		beat = "◆ ZAFER: Kara Doğan düştü, karargâh bizde. Sefer bitti!"
	if beat == "":
		beat = _progress_beat()
	if beat != "":
		out.append(beat)
	return out


## Hedef ilerlemesi hakkında kısa hikâye satırı.
static func _progress_beat() -> String:
	for g: Dictionary in goals():
		if not g["done"]:
			return "◆ %s: sıradaki hedef — %s." % [act_title(), g["text"]]
	return ""


## Asla karşılaşma bitti (Ace). Kayıt + hikâye satırı. Görev sonucu zaten işlendiyse rapora eklenir.
static func note_encounter(mode: String, result: String, mission_id: String, line: String) -> void:
	var a := ace()
	a["encounters"].append({"day": Career.day, "act": act(), "mode": mode, "result": result, "mission": mission_id})
	match mode:
		"cameo":
			a["cameo"] = true
		"hunt":
			a["hunts"] = int(a["hunts"]) + 1
			a["last_hunt"] = int(st()["act_missions"])
	if result == "downed":
		a["downed"] = int(a["downed"]) + 1
	if result == "defeated":
		a["defeated"] = true
	var beat := "◆ " + line
	if _flight_done:
		var i := -1
		for k in Career.front_lines.size():
			if Career.front_lines[k].begins_with("◆") and not Career.front_lines[k].begins_with("◆ PERDE") and not Career.front_lines[k].begins_with("◆ ZAFER"):
				i = k
		if i >= 0:
			Career.front_lines[i] = beat
		elif not Array(Career.front_lines).any(func(l: String) -> bool: return l.begins_with("◆")):
			Career.front_lines.append(beat)
		# finalde as düştüyse ve karargâh da bizdeyse zafer (görev zaten işlendi)
		if result == "defeated" and act_complete(3) and not won():
			st()["won"] = true
			st()["act_day"]["4"] = Career.day
			_brief_pages(4)
			Career.front_lines.append("◆ ZAFER: Kara Doğan düştü, karargâh bizde. Sefer bitti!")
	else:
		_pending_beat = beat
	Career.save()


## Bu görevde as ne yapar: "" · "cameo" (Perde 1) · "hunt" (Perde 2) · "voice" · "finale".
static func ace_plan(mission_id: String) -> String:
	if mission_id == FINALE:
		return "finale" if not ace_defeated() or Career.sandbox() or Game.test_flight else ""
	if Career.sandbox() or Game.test_flight or not mission_id in ACE_MISSIONS:
		return ""
	var a := ace()
	var n := int(st()["act_missions"])
	match act():
		1:
			return "cameo" if not bool(a["cameo"]) and n >= 1 else ""
		2:
			if int(a["hunts"]) < 2 and n >= 1 and n - int(a["last_hunt"]) >= 2:
				return "hunt"
		3:
			return "voice" if not ace_defeated() and randf() < 0.5 else ""
	return ""


## Uçuş başında (Ace.attach): uçuş içi hikâye durumu sıfırlanır.
static func flight_started() -> void:
	_pending_beat = ""
	_flight_done = false


# ------------------------------------------------------------------ brifing sayfaları

## Kariyer ekranının göstereceği bekleyen brifing (perde numarası; 4 = zafer, 0 = yok).
static func pending_brief() -> int:
	return int(st().get("brief", 0))


static func brief_seen() -> void:
	st()["brief"] = 0
	Career.save()


## Brifing sayfaları: [[konuşan, metin, tür]]
static func pages(a: int) -> Array:
	match a:
		1:
			return [["kaya", "Pilotlar, kuzey sınırı düştü. Elimizde bir avuç uçak, dar bir bütçe ve kısa menzilli parçalar var. Önce evimizi koruyacağız: Ana Üs, Güney Sahili, Batı Tepeleri. Önleme, yakın destek, hattı tutmak.", "info"],
				["enemy", "Burası Sert. Güneyin havaalanı bir haftada düşer. Önlerine Kara Doğan'ı çıkarın; bir tanesini indirsin, gerisi kendiliğinden dağılır.", "bad"],
				["ece", "Kara Doğan… Kuzeyin en iyi pilotu derler. Simsiyah uçak, gövdede kırmızı şerit, kuyrukta KD-01. Görürsen tek başına dalaşa girme.", "info"],
				["kaya", "Perde 1 hedefleri: dört savunma harekâtı kazan, ev bölgelerini tut, Ovaköy Yolu ya da Orta Vadi'yi geri al. Derin hedefler şimdilik yasak; menzilimiz yetmez.", "info"]]
		2:
			return [["kaya", "Hat tuttu. Şimdi sıra bizde: PERDE 2, KARŞI TAARRUZ. Dereköy'ün SAM ağı, Doğu Denizi'ndeki filo ve Kuzeykent. Ar-Ge'ye uzun menzil parçalarını açtım: harici tank, havada ikmal probu, ağır motor, iç bomba bölmesi, gemi savar ve radar avcısı füzeler.", "good"],
				["deniz", "Hastaneden selam. Kara Doğan beni üç saniyede indirdi, geldiğini görmedim bile. Yüksekten, güneşin içinden dalıyor. Ona aşağıdan yaklaşma.", "info"],
				["enemy", "Hattı Kuzeykent'e çekin. Dereköy bataryaları hazır kalsın. Güneyliler bizim göğümüzde uzun kalamaz; yakıtları biter, dönerler.", "bad"],
				["ece", "Haksız sayılmaz: bugünkü uçaklarımızla Kuzeykent'e gidip dönemeyiz. Yakıt, yük, menzil. Hangarda masaya oturma zamanı.", "info"],
				["kaya", "Perde 2 hedefleri: SAM ağını çökert, filoyu batır, Kuzeykent'i al. Kara Doğan da ortalıkta olacak; hasar alınca kaçmayı iyi bilir.", "info"]]
		3:
			return [["kaya", "PERDE 3, SON DARBE. Kuzey Ordusu Kuzey Havaalanı'na çekildi; karargâhları orada. Ve orada bir de o var.", "good"],
				["ace", "Güneyli pilot. Kaç kez kaçtım senden? Bu sefer yeri ben seçtim: kendi göğüm, kendi üssüm. Gel de al beni.", "bad"],
				["ece", "İstihbarat: %s" % Ace.intel_text(), "info"],
				["kaya", "Ona göre bir uçak tasarla: ondan hızlı ya da radarında görünmeyecek kadar sinsi (az parça, iç bölme), ya da eskortlarını da kaldıracak büyük bir paket. Ar-Ge'de en üst seviye açık: ramjet, itki vektörlü motor, seyir füzesi, AWACS.", "info"],
				["kaya", "Perde 3 hedefleri: Son Darbe harekâtında Kara Doğan'ı düşür ve Kuzey Havaalanı'nı al.", "info"]]
		4:
			return [["enemy", "…bütün birlikler, geri çekilin. Tekrar ediyorum, geri çekilin. Kara Doğan'dan ses yok.", "bad"],
				["deniz", "Koltuk değnekleriyle pistteyim, herkes burada. Bunu sen yaptın, sen ve o uçak.", "good"],
				["kaya", "Bitti, pilot. Kuzey Havaalanı'nda bayrağımız dalgalanıyor. Bu savaşı tek bir uçak kazanmadı; ama her harekâtta doğru uçağı sen tasarladın.", "good"]]
	return []


## Sayfaları karargâh mesajlarına ekle (konuşan "from" alanında).
static func _brief_pages(a: int) -> void:
	for p: Array in pages(a):
		Career.news.append({"day": Career.day, "text": p[1], "kind": p[2], "from": p[0], "act": a})
	while Career.news.size() > 16:
		Career.news.remove_at(0)


## Haber başlığı: konuşan (yoksa Alb. Kaya).
static func speaker(n: Dictionary) -> String:
	return String(SPEAKERS.get(String(n.get("from", "kaya")), SPEAKERS["kaya"]))


# ------------------------------------------------------------------ zafer

## Sefer istatistikleri (zafer ekranı): [[etiket, değer]]
static func victory_stats() -> Array:
	var s := st()
	var kills := 0
	var lost := 0
	for p: Dictionary in Crew.pilots:
		kills += int(p.get("kills", 0))
		lost += 1 if p.get("status", "") == "kayıp" else 0
	var enc: Array = ace()["encounters"]
	var days: Dictionary = s["act_day"]
	var acts := PackedStringArray()
	for a in [1, 2, 3]:
		var d0 := int(days.get(str(a), 0))
		var d1 := int(days.get(str(a + 1), Career.day))
		if d0 > 0:
			acts.append("P%d: %d gün" % [a, maxi(d1 - d0, 1)])
	return [["Sefer süresi", "%d gün  (%s)" % [Career.day, ", ".join(acts)]],
		["Harekât", "%d uçuş · %d başarılı · %d başarısız" % [int(s["stats"]["missions"]), int(s["stats"]["wins"]), int(s["stats"]["fails"])]],
		["Düşürülen uçak", str(kills)],
		["Kara Doğan ile karşılaşma", "%d  (%d kez yere indirildi)" % [enc.size(), int(ace()["downed"])]],
		["Bölgeler", "%d / %d bizde" % [Front.count(Front.DOST), Front.REGIONS.size()]],
		["Kazanılan", "₺ %d" % Career.total_earned],
		["Kaybedilen pilot", str(lost)]]


# ------------------------------------------------------------------ test

## `--menu --campaigntest`: perdeler boyunca görevleri simüle et; geçişleri, kapıları ve as
## karşılaşmalarını yaz (kayıt yazılmaz).
static func run_test() -> void:
	seed(11)
	Game.mode = "career"
	Game.test_flight = false
	Career.campaign = {}
	var inferred := act()
	print("CAMPAIGN eski kayıt (cephe başlangıç) → perde ", inferred)
	Front.new_campaign()
	print("CAMPAIGN start ", act_title(), " brief=", pending_brief(), " news=", Career.news.size())
	print("  part gate: ramjet act %d allowed=%s · drop_tank act %d allowed=%s · can_unlock(drop_tank)=%s" % [part_act("ramjet"), part_allowed("ramjet"), part_act("drop_tank"), part_allowed("drop_tank"), Career.can_unlock("drop_tank")])
	Career.money = 999999
	Career.completed["egitim"] = 1
	Career.completed["kesif"] = 1
	var last_act := act()
	for day in 60:
		var ops := Front.operations()
		var combat := ops.filter(func(o: Dictionary) -> bool: return o["combat"])
		# öncelik: finale > perde hedefi bölgesi > acil > rastgele savaş
		var pick: Dictionary = {}
		for o: Dictionary in combat:
			if o["mission"] == FINALE:
				pick = o
		if pick.is_empty():
			var wants := {1: ["ovakoy", "orta", "anaus"], 2: ["derekoy", "dogudeniz", "kuzeykent", "ovakoy"], 3: [HQ_REGION, "kuzeykent"]}
			var want: Array = wants[act()]
			for r: String in want:
				for o: Dictionary in combat:
					if pick.is_empty() and o["region"] == r and Front.owner(r) != Front.DOST:
						pick = o
		if pick.is_empty():
			for o: Dictionary in combat:
				if o.get("urgent", false) and pick.is_empty():
					pick = o
		if pick.is_empty():
			pick = combat.pick_random() if not combat.is_empty() else {"mission": "onleme", "region": "anaus"}
		var m: String = pick["mission"]
		var gated := ops.filter(func(o: Dictionary) -> bool: return o["region"] in DEEP).map(func(o: Dictionary) -> String: return "%s@%s" % [o["mission"], o["region"]])
		var plan := ace_plan(m)
		flight_started()
		var ok := randf() < (0.8 if m != FINALE else 0.6)
		if plan != "":
			var results := {"cameo": "cameo", "hunt": "escaped_damaged" if randf() < 0.6 else "downed", "finale": "defeated" if ok else "finale_lost", "voice": "voice"}
			var res: String = results[plan]
			if plan == "finale" and not ok:
				pass
			if plan != "voice":
				note_encounter(plan, res, m, "test: %s → %s" % [plan, res])
			print("   ACE %s → %s" % [plan, res])
		Game.mission_region = pick["region"]
		Career.mission_finished(m, int(MissionManager.get_def(m).get("level", 2)), ok)
		print("DAY %d %s %s@%s %s | %s" % [Career.day, act_title(), m, pick["region"], "OK" if ok else "FAIL", ", ".join(Career.front_lines)])
		if day < 3 or act() != last_act:
			print("   deep ops: ", gated)
		if act() != last_act:
			print(">>> GEÇİŞ %s → %s (gün %d) brief=%d sayfalar=%d" % [act_title(last_act), act_title(), Career.day, pending_brief(), pages(act()).size()])
			for p: Array in pages(act()):
				print("      [%s] %s" % [SPEAKERS[p[0]], String(p[1]).left(80)])
			last_act = act()
		for g: Dictionary in goals():
			print("   %s %s" % ["✔" if g["done"] else "·", g["text"]])
		if won() or Front.status() != "running":
			print("STATUS ", Front.status(), " won=", won())
			break
	print("CAMPAIGN encounters: ", ace()["encounters"].map(func(e: Dictionary) -> String: return "%s/%s(P%d)" % [e["mode"], e["result"], e["act"]]))
	for l: Array in victory_stats():
		print("  %s: %s" % l)
	print("CAMPAIGN weights act3: ", mission_weights())
