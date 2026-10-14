extends Node
## Kariyer: para (₺), açılmış parçalar, tamamlanan görevler. user://career.json'a kaydedilir.
## KSP döngüsü: görev yap → para kazan → Ar-Ge'de yeni parça aç → daha iyi uçak → zor görev.
##
## • Görev ödülü: zorluk ★ başına; ilk tamamlamada tam, sonrakilerde yarısı.
## • Uçak kaybı (düşme, fırlatma): uçağın parça bedelinin yarısı sigorta payı olarak düşülür.
##   Meydanda güvenli iniş ücretsizdir (uçak geri alınır).
## • Görev kilitleri: ★★ görev için 2, ★★★ görev için 5 tamamlanmış görev gerekir.
## • Ayarlardan "Serbest mod" açılırsa her şey açıktır, para kullanılmaz.

const SAVE_PATH := "user://career.json"
const START_MONEY := 25000
const STARTER_PARTS := ["cockpit_mk1", "cockpit_civil", "nose_cone", "radar_nose", "tank_long", "tank_short",
	"wing_main", "wing_small", "wing_straight", "elevon", "stabilator", "fin_vertical", "rudder",
	"gear_main", "gear_nose", "jet_engine", "prop_engine", "gun_pod", "missile_rail", "flare_pod",
	"passenger_cabin", "drag_chute", "airbrake", "pylon", "tail_cone"]
const MISSIONS_FOR_LEVEL := {1: 0, 2: 2, 3: 5}

signal changed

var money := START_MONEY
var unlocked := {}            ## parça id -> true
var completed := {}           ## görev id -> kaç kez
var total_earned := 0
var flights := 0
## Cephe seferi (Front): bölge → sahip, sefer günü, karargâh mesajları
var front := {}
var day := 1
var news := []
## Düşmanın haber verilmiş hamleleri (FrontAI): [{id, kind, region, from, days, mission, day}]
var threats := []
## Son görevin cephe sonuçları (uçuş raporuna yazılır)
var front_lines := PackedStringArray()
## Tasarımlar: prototip güvenilirliği, hizmet kayıtları, seri üretim (bkz. Designs)
var designs_data := {}
## Üç perdelik hikâye: perde, hedef sayaçları, as karşılaşmaları (bkz. Campaign)
var campaign := {}
## Düşman doktrini: oyuncunun alışkanlıkları (bkz. Doctrine)
var doctrine := {}
## Enkazdan tersine mühendislik: parça id → Ar-Ge indirimi (0…0.6), düşürülen düşmanlardan
var salvage := {}


func _ready() -> void:
	_load()
	if unlocked.is_empty():
		for id in STARTER_PARTS:
			unlocked[id] = true
	if front.is_empty():
		Front.new_campaign()


func sandbox() -> bool:
	return Game.mode == "free"


func is_unlocked(id: String) -> bool:
	return sandbox() or unlocked.has(id)


## Ar-Ge bedeli: parça fiyatının 4 katı (bir kez ödenir).
func unlock_price(id: String) -> int:
	var base := int(PartLibrary.get_def(id).get("cost", 500)) * 4
	return int(base * (1.0 - clampf(float(salvage.get(id, 0.0)), 0.0, 0.6)))


func can_unlock(id: String) -> bool:
	return not is_unlocked(id) and money >= unlock_price(id) and Campaign.part_allowed(id)


func unlock(id: String) -> bool:
	if not can_unlock(id):
		return false
	money -= unlock_price(id)
	unlocked[id] = true
	Designs.on_research(id)   # yeni parça prototip olarak başlar
	save()
	changed.emit()
	return true


func missions_done() -> int:
	var n := 0
	for k in completed:
		n += 1 if int(completed[k]) > 0 else 0
	return n


func mission_open(level: int) -> bool:
	return sandbox() or missions_done() >= int(MISSIONS_FOR_LEVEL.get(level, 0))


static func mission_reward(level: int) -> int:
	return [0, 6000, 11000, 18000][clampi(level, 0, 3)]


## Görev bitti: ödülü öde, kaydı tut. Döndürür: kazanılan para.
func mission_finished(id: String, level: int, success: bool) -> int:
	front_lines = PackedStringArray()
	if sandbox() or Game.test_flight:
		return 0
	var gain := 0
	if success:
		if id == "gen":
			# üretilmiş görev: kartın ödülü; şablon başına sayılır (görev kilitleri için)
			gain = int(Game.mission_card.get("reward", mission_reward(level)))
			var key := "gen_" + String(Game.mission_card.get("template", ""))
			completed[key] = int(completed.get(key, 0)) + 1
		else:
			var first := int(completed.get(id, 0)) == 0
			gain = mission_reward(level) if first else mission_reward(level) / 2
			completed[id] = int(completed.get(id, 0)) + 1
	else:
		gain = 500 * level   # katılım payı
	money += gain
	total_earned += gain
	if Game.mission_region != "" or id in Front.COMBAT:
		var rid := Game.mission_region
		if rid == "" and not Front.regions_for(id).is_empty():
			rid = Front.regions_for(id)[0]
		front_lines = Front.mission_result(id, rid, success)
	save()
	changed.emit()
	return gain


## Uçak kaybedildi: parça bedelinin tamamı kasadan çıkar (test uçuşunda kayıp yok).
func aircraft_lost(craft_cost: int) -> int:
	if sandbox() or Game.test_flight:
		return 0
	var loss := mini(craft_cost, money)
	money -= loss
	save()
	changed.emit()
	return loss


## Pilot kaybı: ailesine tazminat. Döndürür: ödenen.
func pilot_lost() -> int:
	if sandbox() or Game.test_flight:
		return 0
	var c := mini(Front.PILOT_LOSS_COST, money)
	money -= c
	save()
	changed.emit()
	return c


static func craft_cost(craft: Dictionary) -> int:
	var c := 0
	for e: Dictionary in craft.get("parts", []):
		c += int(PartLibrary.get_def(String(e.get("part", ""))).get("cost", 0))
	return c


## Uçaktaki kilitli parçalar (başlıklarıyla).
func locked_parts_in(craft: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in craft.get("parts", []):
		var id := String(e.get("part", ""))
		if not is_unlocked(id):
			var t := String(PartLibrary.get_def(id).get("title", id))
			if not t in out:
				out.append(t)
	return out


func _testing() -> bool:
	return Crew._testing()


func save() -> void:
	if _testing():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"money": money, "unlocked": unlocked.keys(), "completed": completed,
			"total_earned": total_earned, "flights": flights,
			"front": front, "day": day, "news": news, "threats": threats, "designs": designs_data, "campaign": campaign, "doctrine": doctrine, "salvage": salvage},"\t"))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	money = int(d.get("money", START_MONEY))
	for id in d.get("unlocked", []):
		unlocked[String(id)] = true
	# sonradan başlangıç listesine eklenen parçalar eski kayıtlarda da açık olsun
	for id in STARTER_PARTS:
		unlocked[id] = true
	for k in d.get("completed", {}):
		completed[String(k)] = int(d["completed"][k])
	total_earned = int(d.get("total_earned", 0))
	flights = int(d.get("flights", 0))
	if typeof(d.get("designs")) == TYPE_DICTIONARY:
		designs_data = d["designs"]
	if typeof(d.get("doctrine")) == TYPE_DICTIONARY:
		doctrine = d["doctrine"]
	if typeof(d.get("salvage")) == TYPE_DICTIONARY:
		salvage = d["salvage"]
	if d.has("front"):
		for k in d["front"]:
			front[String(k)] = int(d["front"][k])
		day = int(d.get("day", 1))
		news = d.get("news", [])
		threats = d.get("threats", [])
		# perde durumu yoksa (eski kayıt) Campaign.st() cepheden çıkarır
		if typeof(d.get("campaign")) == TYPE_DICTIONARY:
			campaign = d["campaign"]
	else:
		# eski kayıt (cephe öncesi): Ar-Ge kilidi yoktu, her şey açılmıştı. Sefer baştan.
		money = START_MONEY
		completed.clear()
		unlocked.clear()
		for id in STARTER_PARTS:
			unlocked[id] = true


func reset() -> void:
	money = START_MONEY
	unlocked.clear()
	for id in STARTER_PARTS:
		unlocked[id] = true
	completed.clear()
	total_earned = 0
	designs_data = {}
	doctrine = {}
	flights = 0
	Front.new_campaign()
	save()
	changed.emit()


## Düşürülen düşmanın enkazından: oyuncunun henüz açmadığı parçalarından birinin Ar-Ge bedeli
## %25 düşer (en çok %60). Mesaj satırı döner ("" = öğrenilecek bir şey yok). Test / serbest modda yok.
func salvage_from(parts: Array) -> String:
	if sandbox() or Game.test_flight:
		return ""
	var cands: Array[String] = []
	for id: String in parts:
		if not unlocked.has(id) and float(salvage.get(id, 0.0)) < 0.6 and not cands.has(id):
			cands.append(id)
	if cands.is_empty():
		return ""
	var id: String = cands[randi() % cands.size()]
	salvage[id] = minf(float(salvage.get(id, 0.0)) + 0.25, 0.6)
	save()
	changed.emit()
	return "ENKAZ İNCELEMESİ: %s — Ar-Ge bedeli %%%d düştü" % [PartLibrary.get_def(id).get("title", id), float(salvage[id]) * 100.0]
