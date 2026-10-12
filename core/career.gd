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
	"passenger_cabin", "drag_chute", "airbrake"]
const MISSIONS_FOR_LEVEL := {1: 0, 2: 2, 3: 5}

signal changed

var money := START_MONEY
var unlocked := {}            ## parça id -> true
var completed := {}           ## görev id -> kaç kez
var total_earned := 0
var flights := 0


func _ready() -> void:
	_load()
	if unlocked.is_empty():
		for id in STARTER_PARTS:
			unlocked[id] = true


func sandbox() -> bool:
	return bool(Game.settings.get("sandbox", false))


func is_unlocked(id: String) -> bool:
	return sandbox() or unlocked.has(id)


## Ar-Ge bedeli: parça fiyatının 4 katı (bir kez ödenir).
func unlock_price(id: String) -> int:
	return int(PartLibrary.get_def(id).get("cost", 500)) * 4


func can_unlock(id: String) -> bool:
	return not is_unlocked(id) and money >= unlock_price(id)


func unlock(id: String) -> bool:
	if not can_unlock(id):
		return false
	money -= unlock_price(id)
	unlocked[id] = true
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
	if sandbox():
		return 0
	var gain := 0
	if success:
		var first := int(completed.get(id, 0)) == 0
		gain = mission_reward(level) if first else mission_reward(level) / 2
		completed[id] = int(completed.get(id, 0)) + 1
	else:
		gain = 500 * level   # katılım payı
	money += gain
	total_earned += gain
	save()
	changed.emit()
	return gain


## Uçak kaybedildi: parça bedelinin yarısı (sigorta payı).
func aircraft_lost(craft_cost: int) -> int:
	if sandbox():
		return 0
	var loss := mini(craft_cost / 2, money)
	money -= loss
	save()
	changed.emit()
	return loss


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
			"total_earned": total_earned, "flights": flights}, "\t"))


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


func reset() -> void:
	money = START_MONEY
	unlocked.clear()
	for id in STARTER_PARTS:
		unlocked[id] = true
	completed.clear()
	total_earned = 0
	save()
	changed.emit()
