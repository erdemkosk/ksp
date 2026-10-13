extends Node
## Pilot kadrosu (KSP'deki Kerbal'lar gibi). user://crew.json'a kaydedilir.
##
## Her pilotun üç yeteneği vardır (1..5 yıldız):
##   uçuş        — kumanda tepkisi ve SAS hassasiyeti; yumuşak inişte daha çok tecrübe
##   nişancılık  — top saçılması daralır
##   dayanım     — G bayılma (G-LOC) eşiği yükselir
## Uçuşlardan tecrübe (XP) kazanır: görev, düşürülen uçak, iniş. Seviye atlayınca en çok
## kullandığı alandaki yetenek artar. Kokpit parçalanırsa pilot "kayıp" olur.

const SAVE_PATH := "user://crew.json"
const MAX_PILOTS := 8
const SKILLS := ["ucus", "nisan", "dayanim"]
const SKILL_NAMES := {"ucus": "Uçuş", "nisan": "Nişancılık", "dayanim": "G dayanımı"}
const FIRST := ["Ayşe", "Mert", "Elif", "Can", "Zeynep", "Emre", "Deniz", "Burak", "Selin", "Kaan",
	"Ece", "Barış", "Derya", "Onur", "Yasemin", "Tolga", "Nehir", "Umut", "Defne", "Arda"]
const LAST := ["Kaya", "Demir", "Şahin", "Yıldız", "Arslan", "Çelik", "Aydın", "Koç", "Kurt", "Özdemir",
	"Polat", "Erdem", "Aksoy", "Tekin", "Bulut", "Karaca"]

var pilots: Array[Dictionary] = []
var selected := 0
## Kanat adamı olarak götürülen pilot (kadro indeksi, -1: yok; WingFlight)
var wingman := -1
## Bu uçuşta kazanılanlar (uçuş bitince ya da görev sonunda işlenir)
var flight_log := {"xp": 0, "nisan": 0, "dayanim": 0, "ucus": 0}
## Madalya sayaçları (pilot sözlüğünde; eski kayıtta yoksa 0). km ve max_g ondalıklı. Bkz. Medals.
const STAT_KEYS := ["ground_kills", "ships", "ejections", "landings", "soft_landings", "storm_landings",
	"night_missions", "missions", "rescues", "damaged_returns", "km", "max_g"]
## Bu uçuşun madalya sayaçları (uçuş sonunda pilota eklenir; max_g için en büyüğü alınır)
var flight_stats := {}


func _ready() -> void:
	_load()
	if pilots.is_empty():
		for i in 4:
			pilots.append(_new_pilot(2 if i == 0 else 1))
		save()


func _new_pilot(base := 1) -> Dictionary:
	var used := []
	for p in pilots:
		used.append(p["name"])
	var name := ""
	for i in 30:
		name = "%s %s" % [FIRST[randi() % FIRST.size()], LAST[randi() % LAST.size()]]
		if not name in used:
			break
	return _ensure({"name": name, "ucus": base + randi() % 2, "nisan": base + randi() % 2, "dayanim": base + randi() % 2,
		"xp": 0, "level": 1, "flights": 0, "kills": 0, "status": "hazır"})


func current() -> Dictionary:
	if pilots.is_empty():
		return {}
	selected = clampi(selected, 0, pilots.size() - 1)
	return pilots[selected]


func skill(key: String) -> int:
	var p := current()
	return int(p.get(key, 1)) if not p.is_empty() else 1


func can_fly(i: int) -> bool:
	return i >= 0 and i < pilots.size() and pilots[i]["status"] == "hazır"


## Uçabilecek kanat adamı indeksi (seçili pilot değil, hazır), yoksa -1.
func wingman_index() -> int:
	return wingman if wingman != selected and can_fly(wingman) else -1


func hire() -> bool:
	if pilots.size() >= MAX_PILOTS:
		return false
	pilots.append(_new_pilot(1))
	save()
	return true


func fire_pilot(i: int) -> void:
	if i >= 0 and i < pilots.size() and pilots.size() > 1:
		pilots.remove_at(i)
		wingman = -1 if wingman == i else (wingman - 1 if wingman > i else wingman)
		selected = clampi(selected, 0, pilots.size() - 1)
		save()


## Seviye n için gereken toplam XP.
static func xp_for(level: int) -> int:
	return 60 * level * level


## Uçuş sırasında tecrübe kaydet (alan: hangi yetenek kullanıldı).
func award(xp: int, area := "ucus") -> void:
	flight_log["xp"] += xp
	flight_log[area] = int(flight_log.get(area, 0)) + xp


## Uçuş bitti: XP'yi pilota işle, seviye atlat. Döndürür: mesaj satırları.
func end_flight(killed := false) -> PackedStringArray:
	var out := PackedStringArray()
	var p := current()
	if p.is_empty():
		return out
	if Game.test_flight:
		flight_log = {"xp": 0, "nisan": 0, "dayanim": 0, "ucus": 0}
		flight_stats = {}
		out.append("Test uçuşu (simülasyon): tecrübe ve kayıp işlenmedi.")
		return out
	p["flights"] = int(p["flights"]) + 1
	if killed and Career.sandbox():
		out.append("%s düştü (serbest mod: kadroya geri döner)." % p["name"])
	elif killed:
		p["status"] = "kayıp"
		out.append("%s kayıp." % p["name"])
	var gained := int(flight_log["xp"])
	if gained > 0 and not killed:
		p["xp"] = int(p["xp"]) + gained
		out.append("%s +%d XP" % [p["name"], gained])
		while int(p["xp"]) >= xp_for(int(p["level"])) and int(p["level"]) < 10:
			p["level"] = int(p["level"]) + 1
			# en çok tecrübe kazandığı alan gelişir
			var best := "ucus"
			for k in SKILLS:
				if int(flight_log.get(k, 0)) > int(flight_log.get(best, 0)):
					best = k
			if int(p[best]) >= 5:
				for k in SKILLS:
					if int(p[k]) < 5:
						best = k
						break
			p[best] = mini(int(p[best]) + 1, 5)
			out.append("SEVİYE %d!  %s +1" % [p["level"], SKILL_NAMES[best]])
	# madalya sayaçları ve terfi (pilot kayıpsa işlenmez)
	if not killed or Career.sandbox():
		_merge_stats(p)
		out.append_array(Medals.evaluate(p))
	flight_stats = {}
	flight_log = {"xp": 0, "nisan": 0, "dayanim": 0, "ucus": 0}
	save()
	return out


func add_kill() -> void:
	var p := current()
	if not p.is_empty():
		p["kills"] = int(p["kills"]) + 1
	award(40, "nisan")


# ------------------------------------------------------------------ madalya sayaçları

## Eksik madalya/rütbe alanlarını tamamla (yeni pilot ya da eski kayıt).
func _ensure(d: Dictionary) -> Dictionary:
	for k in STAT_KEYS:
		d[k] = float(d.get(k, 0)) if k in ["km", "max_g"] else int(d.get(k, 0))
	if not d.has("medals"):
		# eski kayıt: rütbe mevcut duruma göre, hak edilmiş madalyalar sessizce verilir
		d["medals"] = []
		d["rank"] = Medals.rank_for(d)
		Medals.evaluate(d)
	d["rank"] = int(d.get("rank", 0))
	var arr: Array = []
	for m in d["medals"]:
		arr.append(String(m))
	d["medals"] = arr
	return d


## Bu uçuşa sayaç ekle (uçuş sonunda pilota işlenir).
func note(key: String, amount := 1.0) -> void:
	flight_stats[key] = float(flight_stats.get(key, 0.0)) + amount


## Havada geçen kare: mesafe (km) ve bayılmadan çekilen en yüksek G.
func note_air(delta: float, ground_speed: float, g: float) -> void:
	note("km", ground_speed * delta / 1000.0)
	flight_stats["max_g"] = maxf(float(flight_stats.get("max_g", 0.0)), g)


## İniş (dikey hız, m/s; negatif = alçalma).
func note_landing(vs: float) -> void:
	note("landings")
	if vs > -1.5:
		note("soft_landings")
	if Weather.preset == Weather.Preset.STORM:
		note("storm_landings")


## Görev bitti (pos: uçağın konumu, gece kontrolü için).
func note_mission(success: bool, id: String, pos: Vector3) -> void:
	if not success:
		return
	note("missions")
	if id == "kurtarma":
		note("rescues")
	var h := Weather.local_hour(pos)
	if h >= 20.0 or h < 5.5:
		note("night_missions")


## Düşman yer/deniz hedefi yok edildi (GroundTarget çağırır).
func note_target_destroyed(t: Node) -> void:
	note("ships" if t is Warship else "ground_kills")


func _merge_stats(p: Dictionary) -> void:
	for k: String in flight_stats:
		if k == "max_g":
			p[k] = maxf(float(p.get(k, 0.0)), float(flight_stats[k]))
		elif k == "km":
			p[k] = float(p.get(k, 0.0)) + float(flight_stats[k])
		else:
			p[k] = int(p.get(k, 0)) + int(flight_stats[k])


## Otomatik testler oyuncunun kadro kaydını değiştirmesin.
func _testing() -> bool:
	for k in ["autotest", "crashtest", "starttest", "gtest", "weapontest", "guntest", "dogfight", "missiontest",
			"aiplayer", "bombtest", "droptest", "mousetest", "damagedemo", "damagefx", "pulldemo", "pulltest", "ejecttest", "loaltest", "savetest", "walktest", "missionendtest", "aeroprobe", "breakcheck", "partsprobe", "hangartest", "screenshot"]:
		if Game.args.has(k):
			return true
	# yeni eklenen test argümanları listeye yazılmasa da korunsun: *test, *probe, *demo, balance
	for k: String in Game.args.keys():
		if k.ends_with("test") or k.ends_with("probe") or k.ends_with("demo") or k in ["balance", "sizes", "damagefx"]:
			return true
	return false


func save() -> void:
	if _testing():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"pilots": pilots, "selected": selected, "wingman": wingman}, "\t"))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	pilots.clear()
	for p in data.get("pilots", []):
		var d: Dictionary = p
		for k in ["xp", "level", "flights", "kills", "ucus", "nisan", "dayanim"]:
			d[k] = int(d.get(k, 1))
		pilots.append(_ensure(d))
	selected = int(data.get("selected", 0))
	wingman = int(data.get("wingman", -1))
