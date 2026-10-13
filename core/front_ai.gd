class_name FrontAI
## Yaşayan cephe (stratejik katman): her sefer gününde (gerçek kariyer görevi) düşman da hamle yapar.
## Hamleler önceden haber verilir ve haritada görünür; oyuncunun karşılık vermek için birkaç günü var:
##   baskin  — bombardıman uçakları dost bölgeye / üsse baskın hazırlar → Önleme ile durdur,
##             yoksa onarım kasadan çıkar (bölge el değiştirmez)
##   konvoy  — zırhlı konvoy çekişmeli bölgeye ilerler → Kara Saldırısı ile durdur, yoksa bölge düşer
##   taarruz — düşman dost bölgeye yüklenir → Kara Saldırısı ile hazırlığı boz, yoksa bölge çekişmeli
## Aynı anda en çok MAX_ACTIVE tehdit; her biri ayrı bölgede. İlk günler ve 2. seviye görevler
## açılmadan önce (karşılık verilemezse) düşman eski kuraldaki gibi doğrudan ilerler.
## Uçuş sırasında taarruz paketinin önlenmesi (AmbientAir) bağlı baskını boşa çıkarır.
##
## Durum Career.threats'te: [{id, kind, region, from, days, mission, day}]

const MAX_ACTIVE := 2
## Bu günden önce yeni tehdit yok (sefer ısınsın)
const FIRST_DAY := 3
## Haber verildikten sonra kaç görev günü içinde önlenmeli
const WARN_DAYS := 2
## Göz ardı edilen baskının onarımı (üs / diğer bölge)
const RAID_COST_BASE := 3000
const RAID_COST_REGION := 2000
## Acil görevi başarıyla yapınca ek prim; uçuşta taarruz paketini önleme primi
const URGENT_BONUS := 1000
const INTERCEPT_BONUS := 1500

const KINDS := {
	"baskin": {"label": "HAVA BASKINI", "name": "hava baskını", "mission": "onleme", "action": "Önle"},
	"konvoy": {"label": "KONVOY", "name": "konvoy", "mission": "kara", "action": "Konvoyu durdur"},
	"taarruz": {"label": "TAARRUZ", "name": "taarruz", "mission": "kara", "action": "Taarruzu boz"},
}


static func active() -> Array:
	return Career.threats


static func threat_at(region_id: String) -> Dictionary:
	for t: Dictionary in Career.threats:
		if t["region"] == region_id:
			return t
	return {}


## Haritadaki acil harekâtlar (Front.operations'a eklenir / var olanı işaretler).
static func urgent_ops() -> Array:
	var out := []
	for t: Dictionary in Career.threats:
		out.append({"mission": t["mission"], "region": t["region"], "combat": true, "urgent": true, "threat": int(t["id"]), "days": int(t["days"])})
	return out


## Haritadaki kısa etiket: "BASKIN · 2 gün"
static func short_text(t: Dictionary) -> String:
	var d := int(t["days"])
	return "%s · %s" % [KINDS[t["kind"]]["label"], "SON GÜN" if d <= 1 else "%d gün" % d]


## Ayrıntılı açıklama (harekât paneli, karargâh mesajı).
static func describe(t: Dictionary) -> String:
	var r := String(Front.region(t["region"]).get("name", "?"))
	var src := String(Front.region(t["from"]).get("name", "kuzey"))
	var d := int(t["days"])
	var when := "Bugün son gün" if d <= 1 else "%d gün içinde" % d
	match String(t["kind"]):
		"baskin":
			return "Düşman bombardıman uçakları %s üzerinden %s bölgesine baskın hazırlıyor. %s önle; önlenmezse onarım ₺ %d." % [src, r, when, _raid_cost(t["region"])]
		"konvoy":
			return "Düşman zırhlı konvoyu %s yönünden %s bölgesine ilerliyor. %s durdur; durdurulmazsa bölge düşmana geçer." % [src, r, when]
		_:
			return "Düşman %s yönünden %s bölgesine taarruz hazırlıyor. %s hazırlığı boz; bozulmazsa bölge çekişmeli olur." % [src, r, when]


static func _raid_cost(region_id: String) -> int:
	return RAID_COST_BASE if Front.region(region_id).get("fixed", false) else RAID_COST_REGION


## Sefer günü bitti (Front.mission_result içinden): eşleşen tehdidi çöz, diğerlerinin süresini
## işlet, düşmanın yeni hamlesini seç. Döndürür: rapor satırları.
static func turn(mission_id: String, region_id: String, success: bool) -> PackedStringArray:
	var out := PackedStringArray()
	# 1) bu görev bir tehdide karşılık mı
	for t: Dictionary in Career.threats.duplicate():
		var gen_match := mission_id == "gen" and int(Game.mission_card.get("threat", -1)) == int(t["id"])
		if gen_match or (t["mission"] == mission_id and t["region"] == region_id):
			Career.threats.erase(t)
			var name := String(Front.region(region_id).get("name", ""))
			if success:
				Career.money += URGENT_BONUS
				out.append("ACİL GÖREV: %s önlendi (+%d ₺ prim)." % [KINDS[t["kind"]]["name"], URGENT_BONUS])
				Front._news("%s bölgesindeki düşman hazırlığı dağıtıldı. Zamanında yetiştin, pilot." % name, "good")
			else:
				out.append("ACİL GÖREV başarısız: %s önlenemedi." % KINDS[t["kind"]]["name"])
	# 2) süre işler, dolanlar gerçekleşir
	for t: Dictionary in Career.threats.duplicate():
		t["days"] = int(t["days"]) - 1
		if int(t["days"]) <= 0:
			Career.threats.erase(t)
			out.append_array(_execute(t))
	# 3) düşmanın yeni hamlesi
	if Front.status() == "running":
		var counter_day := Career.day % Front.COUNTER_EVERY == 0
		if not can_warn():
			# karşılık verilemeyecek kadar erken: eski kural (her üç günde doğrudan ilerleme)
			if counter_day and (not success or randf() < 0.5):
				out.append_array(_direct_push())
		elif Career.threats.size() < MAX_ACTIVE and randf() < (0.8 if counter_day else 0.3):
			var t := spawn_threat()
			if not t.is_empty():
				out.append("DÜŞMAN HAREKETİ: %s → %s (%d gün)." % [KINDS[t["kind"]]["label"], Front.region(t["region"])["name"], int(t["days"])])
	return out


## Uyarılı tehdit için şartlar: ilk günler geçti, karşı görevler (2. seviye) açık.
static func can_warn() -> bool:
	return Career.day >= FIRST_DAY and Career.mission_open(2)


static func _direct_push() -> PackedStringArray:
	var out := PackedStringArray()
	var hit := Front._push_enemy()
	if hit != "":
		out.append("KARŞI TAARRUZ: düşman %s bölgesine yüklendi (%s)." % [Front.region(hit)["name"], Front.OWNER_NAMES[Front.owner(hit)]])
		Front._news("Acil: düşman karşı taarruza geçti, %s %s. Hattı tutmamız lazım." % [Front.region(hit)["name"], "çekişmeli" if Front.owner(hit) == Front.CEKISME else "düştü"], "bad")
	return out


## Süresi dolan tehdit gerçekleşir.
static func _execute(t: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var rid: String = t["region"]
	var r := Front.region(rid)
	# seri üretimdeki filo tipi (Designs) iyi bir tasarımsa hamleyi ara sıra boşa çıkarır
	if randf() < 0.15 * Designs.fleet_quality():
		out.append("FİLO: %s uçaklarımız %s bölgesine yönelen %s hamlesini durdurdu." % [Designs.fleet_name(), r["name"], KINDS[t["kind"]]["name"]])
		Front._news("%s filomuz %s üzerinde düşmanı geri püskürttü. Tasarımın işe yarıyor." % [Designs.fleet_name(), r["name"]], "good")
		return out
	match String(t["kind"]):
		"baskin":
			var c := mini(_raid_cost(rid), Career.money)
			Career.money -= c
			out.append("BASKIN: %s bombalandı, onarım -%d ₺." % [r["name"], c])
			Front._news("Önleyemediğimiz bombardıman %s bölgesini vurdu. Onarım kasadan çıktı: %d ₺." % [r["name"], c], "bad")
		_:
			var o := Front.owner(rid)
			if r.get("fixed", false) or o == Front.DUSMAN:
				return out
			# bu arada komşu düşman bölgeleri alındıysa hamle ikmalsiz kalır, boşa çıkar
			if _enemy_neighbor(rid) == "":
				out.append("%s bölgesine yönelen düşman %s ikmalsiz kaldı, dağıldı." % [r["name"], KINDS[t["kind"]]["name"]])
				Front._news("%s bölgesine yönelen %s, arkasındaki bölgeyi aldığımız için dağıldı." % [r["name"], KINDS[t["kind"]]["name"]], "good")
				return out
			Career.front[rid] = o + 1
			var now := Front.owner(rid)
			var what := "düşman konvoyu %s bölgesine ulaştı" % r["name"] if t["kind"] == "konvoy" else "düşman taarruzu %s bölgesinde hattı yardı" % r["name"]
			out.append("CEPHE: %s, bölge artık %s." % [what, Front.OWNER_NAMES[now].to_lower()])
			Front._news("Uyarmıştım: %s. Bölge artık %s." % [what, Front.OWNER_NAMES[now].to_lower()], "bad")
	return out


## Yeni bir düşman hamlesi seç ve haber ver. Döndürür: tehdit (yoksa boş).
static func spawn_threat(kind := "") -> Dictionary:
	var cands := []   # [kind, region, from, ağırlık]
	for r: Dictionary in Front.REGIONS:
		var id: String = r["id"]
		if not threat_at(id).is_empty():
			continue
		var o := Front.owner(id)
		var src := _enemy_neighbor(id)
		if o == Front.CEKISME and src != "":
			cands.append(["konvoy", id, src, 4.0])
		elif o == Front.DOST and not r.get("fixed", false) and src != "":
			cands.append(["taarruz", id, src, 3.0])
		if o == Front.DOST:
			var base := _raid_source(id)
			if base != "":
				cands.append(["baskin", id, base, 3.0 if r.get("fixed", false) else 1.0])
	if kind != "":
		cands = cands.filter(func(c: Array) -> bool: return c[0] == kind)
	if cands.is_empty():
		return {}
	var total := 0.0
	for c: Array in cands:
		total += c[3]
	var roll := randf() * total
	var pick: Array = cands[-1]
	for c: Array in cands:
		roll -= c[3]
		if roll <= 0.0:
			pick = c
			break
	var t := {"id": randi() % 1000000, "kind": pick[0], "region": pick[1], "from": pick[2], "days": WARN_DAYS,
		"mission": KINDS[pick[0]]["mission"], "day": Career.day}
	Career.threats.append(t)
	Front._news("ACİL: " + describe(t), "bad")
	return t


## Bölgeye komşu düşman bölgesi (yoksa "").
static func _enemy_neighbor(id: String) -> String:
	var opts := []
	for n: String in Front.NEIGHBORS.get(id, []):
		if Front.owner(n) == Front.DUSMAN:
			opts.append(n)
	return "" if opts.is_empty() else String(opts.pick_random())


## Baskının kalkacağı düşman bölgesi: Kuzey Havaalanı düşmandaysa o, değilse en yakın düşman bölgesi.
static func _raid_source(target: String) -> String:
	if Front.owner("kuzeyhava") == Front.DUSMAN:
		return "kuzeyhava"
	var best := ""
	var bd := INF
	var p: Vector2 = Front.region(target)["xz"]
	for r: Dictionary in Front.REGIONS:
		if Front.owner(r["id"]) == Front.DUSMAN and p.distance_to(r["xz"]) < bd:
			bd = p.distance_to(r["xz"])
			best = r["id"]
	return best


## Uçuşta taarruz paketi önlendi (AmbientAir): bağlı baskın boşa çıkar, prim. Döndürür: mesaj.
static func strike_intercepted(region_id: String) -> String:
	if Career.sandbox() or Game.test_flight:
		return "Taarruz paketi önlendi!"
	var t := {}
	for x: Dictionary in Career.threats:
		if x["kind"] == "baskin" and (x["region"] == region_id or t.is_empty()):
			t = x
	var bonus := INTERCEPT_BONUS if not t.is_empty() else URGENT_BONUS
	Career.money += bonus
	if not t.is_empty():
		Career.threats.erase(t)
		Front._news("Taarruz paketini havada dağıttın; %s bölgesine baskın yapılamayacak. Prim: %d ₺." % [Front.region(t["region"])["name"], bonus], "good")
	else:
		Front._news("Alarm kalkışıyla bir düşman taarruz paketini önledin. Prim: %d ₺." % bonus, "good")
	Career.save()
	return "ÖNLEME BAŞARILI  +%d ₺%s" % [bonus, "  ·  baskın boşa çıktı" if not t.is_empty() else ""]


## Uçuşta açık baskın tehdidi (taarruz paketi bunu temsil eder). Yoksa boş.
static func pending_raid() -> Dictionary:
	if Career.sandbox():
		return {}
	for t: Dictionary in Career.threats:
		if t["kind"] == "baskin":
			return t
	return {}


## `--menu --frontaidemo`: haritada örnek tehditler (kayıt yazılmaz).
static func seed_demo() -> void:
	Front.new_campaign()
	Career.completed["egitim"] = 1
	Career.completed["kesif"] = 1
	Career.day = 4
	Career.front["ovakoy"] = Front.CEKISME
	spawn_threat("konvoy")
	spawn_threat("baskin")
	Career.threats[-1]["days"] = 1


## `--menu --frontaitest`: birkaç sefer günü oynat (bazı tehditler önlenir, bazıları göz ardı
## edilir), olayları ve bölge değişimlerini yaz (kayıt yazılmaz).
static func run_test() -> void:
	seed(7)
	Game.mode = "career"
	Game.test_flight = false
	Front.new_campaign()
	print("FRONTAI start ", Career.front)
	var plan := [["kesif", "ovakoy", true], ["egitim", "anaus", true], ["kara", "ovakoy", true], ["it", "orta", false]]
	for i in 14:
		var m: Array = plan[i] if i < plan.size() else []
		if m.is_empty():
			# tek günlerde acil görevi yap (başarı %70), çift günlerde ihmal et
			var urg := urgent_ops()
			if i % 2 == 1 and not urg.is_empty():
				m = [urg[0]["mission"], urg[0]["region"], randf() < 0.7]
			else:
				m = ["kesif", "ovakoy", randf() < 0.5]
		Game.mission_region = m[1]
		var before: Dictionary = Career.front.duplicate()
		Career.mission_finished(m[0], int(MissionManager.get_def(m[0]).get("level", 1)), m[2])
		var changes := []
		for k: String in Career.front:
			if int(before.get(k, -1)) != int(Career.front[k]):
				changes.append("%s %s→%s" % [k, Front.OWNER_NAMES[int(before.get(k, 0))], Front.OWNER_NAMES[int(Career.front[k])]])
		print("DAY %d %s@%s %s | money %d | %s" % [Career.day, m[0], m[1], "OK" if m[2] else "FAIL", Career.money, ", ".join(Career.front_lines)])
		if not changes.is_empty():
			print("   REGION ", ", ".join(changes))
		for t: Dictionary in Career.threats:
			print("   THREAT ", short_text(t), " @", t["region"], " ← ", t["from"], " (", t["mission"], ")")
		if Front.status() != "running":
			print("   STATUS ", Front.status())
			break
	var ops := Front.operations()
	var urgent := ops.filter(func(o: Dictionary) -> bool: return o.get("urgent", false))
	print("FRONTAI ops=%d urgent=%d status=%s news=%d" % [ops.size(), urgent.size(), Front.status(), Career.news.size()])
	print("FRONTAI intercept: ", strike_intercepted("anaus"))
