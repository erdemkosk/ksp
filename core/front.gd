class_name Front
## Cephe seferi (kariyer modu): harita bölgelere ayrılır, her bölgenin sahibi dost / çekişmeli /
## düşmandır. Bölgede yapılan harekât başarılıysa cephe bir adım kuzeye, başarısızsa güneye kayar.
## Düşman da hamle yapar (FrontAI): baskın / konvoy / taarruz önceden haber verilir, önlenmezse
## bölge ya da para kaybedilir. Bütün bölgeler dost olunca sefer kazanılır,
## Ana Üs dışında her yer düşmana geçerse kaybedilir.
##
## Durum Career'da tutulur (career.json): front (bölge → sahip), day, news (karargâh mesajları).
## Bu dosya yalnız sabit veri ve kuralları içerir.

const DOST := 0
const CEKISME := 1
const DUSMAN := 2
const OWNER_NAMES := ["Dost", "Çekişmeli", "Düşman"]
const OWNER_COLORS := [Color(0.3, 0.75, 1.0), Color(1.0, 0.72, 0.25), Color(1.0, 0.3, 0.26)]

const COMMANDER := "Alb. Kaya"
const COMMANDER_TITLE := "Hava Harekât Merkezi"

## Pilot kaybında ailesine ödenen tazminat (kariyer)
const PILOT_LOSS_COST := 5000
## Bu kadar uçuşta bir düşman karşı taarruza geçer
const COUNTER_EVERY := 3

const REGIONS := [
	{"id": "anaus", "name": "Ana Üs", "xz": Vector2(0, 0), "start": DOST, "fixed": true,
		"missions": ["onleme", "egitim", "ikmal"]},
	{"id": "sahil", "name": "Güney Sahili", "xz": Vector2(10000, 5000), "start": DOST,
		"missions": ["yolcu", "kurtarma", "kargo", "devriye"]},
	{"id": "bati", "name": "Batı Tepeleri", "xz": Vector2(-14000, 2000), "start": DOST, "missions": []},
	{"id": "ovakoy", "name": "Ovaköy Yolu", "xz": Vector2(-8000, -8000), "start": CEKISME,
		"missions": ["kara", "kesif"]},
	{"id": "orta", "name": "Orta Vadi", "xz": Vector2(4000, -10000), "start": CEKISME,
		"missions": ["it", "kesif"]},
	{"id": "derekoy", "name": "Dereköy", "xz": Vector2(6000, -21000), "start": DUSMAN,
		"missions": ["sam", "heli"]},
	{"id": "kuzeykent", "name": "Kuzeykent", "xz": Vector2(-19000, -20000), "start": DUSMAN,
		"missions": ["kara", "ustunluk"]},
	{"id": "kuzeyhava", "name": "Kuzey Havaalanı", "xz": Vector2(-28000, -11000), "start": DUSMAN,
		"missions": ["ustunluk", "it"]},
	{"id": "dogudeniz", "name": "Doğu Denizi", "xz": Vector2(15500, -21000), "start": DUSMAN,
		"missions": ["filo", "firkateyn"]},
]

const NEIGHBORS := {
	"anaus": ["sahil", "bati", "ovakoy", "orta"],
	"sahil": ["anaus", "orta"],
	"bati": ["anaus", "ovakoy"],
	"ovakoy": ["anaus", "bati", "orta", "kuzeykent"],
	"orta": ["anaus", "sahil", "ovakoy", "derekoy", "dogudeniz"],
	"derekoy": ["orta", "kuzeykent", "dogudeniz"],
	"kuzeykent": ["ovakoy", "derekoy", "kuzeyhava"],
	"kuzeyhava": ["kuzeykent"],
	"dogudeniz": ["orta", "derekoy"],
}

## Savaş görevleri cepheyi oynatır; diğerleri (destek / eğitim) yalnız para ve tecrübe verir.
const COMBAT := ["kara", "kesif", "it", "sam", "heli", "ustunluk", "onleme", "filo", "firkateyn", "sead", "sondarbe"]

## Karargâhın istihbarat notu: tehditler ve önerilen tasarım.
const INTEL := {
	"kara": {"threats": ["6 araçlık zırhlı konvoy", "2 uçaksavar topu (3 km, alçakta ölümcül)", "Devriye avcı"],
		"advice": "Bomba ya da güçlü top. Uçaksavar menzili dışından CCIP ile vur, avcıya karşı IR füze taşı."},
	"kesif": {"threats": ["Hafif hava savunması", "Uzun rota (3 nokta, 600 m altı)"],
		"advice": "Silah şart değil: hızlı, menzilli ve alçakta dengeli bir uçak. Fazla yakıt al."},
	"it": {"threats": ["Deneyimli düşman ası", "IR füze + top"],
		"advice": "Çevik avcı: yüksek itki/ağırlık, iyi yatış hızı, flare. Ağır askı yükü taşıma."},
	"sam": {"threats": ["2 SAM rampası (9 km, radar güdümlü füze)", "Uçaksavar topları"],
		"advice": "Alçak uç, chaff ve ECM taşı. Bomba ya da lazer güdümlü bomba (hedefleme podu ile)."},
	"heli": {"threats": ["2 saldırı helikopteri (radarda görünmez)", "Alçak irtifa, topla karşılık verirler"],
		"advice": "Top ve IRST. Yavaşta iyi dönen, alçakta kararlı bir uçak."},
	"ustunluk": {"threats": ["3 düşman avcı, iki dalga hâlinde", "Radar ve IR füzeler"],
		"advice": "Radar + radar füzesi (RF-1) ile uzaktan aç, yakın dövüş için IR füze ve flare. Bol yakıt."},
	"onleme": {"threats": ["2 bombardıman uçağı üsse geliyor", "5 dakika süre"],
		"advice": "Hızlı kalkış ve tırmanış: güçlü motor, afterburner, radar füzesi. Pistte motor çalışıyor."},
	"egitim": {"threats": ["Tehdit yok"], "advice": "Yeni bir tasarımı denemek için ideal."},
	"ikmal": {"threats": ["Tehdit yok", "Hassas uçuş"], "advice": "Havada ikmal probu şart, düşük hızda kararlı uçak."},
	"yolcu": {"threats": ["Tehdit yok"], "advice": "6 koltuk (Kırlangıç). Yumuşak uç."},
	"kurtarma": {"threats": ["Kısa, engebeli iniş yeri"], "advice": "Yolcu kabini, fren paraşütü, hava freni."},
	"kargo": {"threats": ["Dar bırakma bölgesi"], "advice": "Kargo bölmesi (Katır). Alçak ve yavaş geç."},
	"filo": {"threats": ["Uçak gemisi: avcı kaldırır (havada en çok 2)", "Muhrip: 76 mm top (6.5 km) + SAM (16 km)", "CIWS gelen füzeyi düşürebilir"],
		"advice": "Çok sayıda gemi savar füzesi taşıyan menzilli bir saldırı uçağı; avcılara karşı IR füze ve flare. Füzeleri birlikte at: CIWS hepsini düşüremez."},
	"firkateyn": {"threats": ["2 fırkateyn: 40 km radar, 16 km SAM", "76 mm baş topu (6.5 km, yakınlık tapalı)"],
		"advice": "En az dört gemi savar füzesi, chaff ve ECM. Topun menziline girme; girersen denizin üstünde alçak ve hızlı geç."},
	"devriye": {"threats": ["3 akıncı korvet: 12 km SAM, CIWS", "Kıyıya varmadan batırılmalı"],
		"advice": "Gemi savar füze ya da bomba. Hızlı çık: akıncılar kıyıya yaklaşıyor."},
	"sead": {"threats": ["Uzun menzilli SAM (40 km) + iki SAM rampası", "Erken uyarı radarı, omuzdan atılan IR füzeler"],
		"advice": "Radar avcısı füze (RA-1), chaff ve ECM. Alçak gir, radar yayınına kilitlen. Menzil için harici tank."},
	"sondarbe": {"threats": ["Kara Doğan: ikiz J-70 + afterburner, 8-10 km'de devriye, çok hızlı tırmanır", "2 RF-1 radar füzesi, 2 IR füze, top, ECM, flare", "İki eskort avcı, düşman karargâhı üzerinde (~30 km)"],
		"advice": "Ona karşı tasarla: daha hızlı (ramjet / itki vektörü), ya da az parçalı ve iç bölmeli (radarda küçük), ya da eskortları da kaldıracak radar füzeli bir paket. Flare ve chaff şart."},
}


static func region(id: String) -> Dictionary:
	for r: Dictionary in REGIONS:
		if r["id"] == id:
			return r
	return {}


static func owner(id: String) -> int:
	return int(Career.front.get(id, region(id).get("start", DUSMAN)))


static func fresh_state() -> Dictionary:
	var d := {}
	for r: Dictionary in REGIONS:
		d[r["id"]] = int(r["start"])
	return d


## Görevin cephede bağlı olduğu bölgeler (en öndeki ilk sırada).
static func regions_for(mission_id: String) -> Array:
	var out := []
	for r: Dictionary in REGIONS:
		if mission_id in r["missions"]:
			out.append(r["id"])
	return out


## Bölgeye harekât yapılabilir mi: çekişmeli ya da dost / çekişmeli bölgeye komşu düşman bölgesi.
## Dost bölgelerde yalnız destek görevleri (ve Ana Üs savunması) olur.
static func attackable(id: String) -> bool:
	var o := owner(id)
	if o == CEKISME:
		return true
	if o == DUSMAN:
		for n: String in NEIGHBORS.get(id, []):
			if owner(n) != DUSMAN:
				return true
	return false


## Kariyerde açık harekâtlar: [{mission, region}] (savaş) ve destek görevleri.
static func operations() -> Array:
	var out := []
	for r: Dictionary in REGIONS:
		var rid: String = r["id"]
		for m: String in r["missions"]:
			if not Campaign.allows(m, rid):
				continue   # perde kapısı (Campaign)
			if m in COMBAT and m != "onleme":
				if attackable(rid):
					out.append({"mission": m, "region": rid, "combat": true})
			else:
				out.append({"mission": m, "region": rid, "combat": m in COMBAT})
	out.append_array(Campaign.extra_ops())   # perde harekâtları: SEAD, Son Darbe
	# üretilmiş görevler (MissionGen): her uygun bölgeye bir "istek"; düşman hamlelerine karşı acil
	# görevler de şablona dönüşür (op["mission"] = "gen", op["card"] = kart)
	out.append_array(MissionGen.ops())
	return out


static func count(o: int) -> int:
	var n := 0
	for r: Dictionary in REGIONS:
		n += 1 if owner(r["id"]) == o else 0
	return n


static func status() -> String:
	# zafer: hikâye bitti (Kara Doğan düştü + karargâh) ya da her yer bizde ve as da düştü
	if Campaign.won() or (count(DOST) == REGIONS.size() and Campaign.ace_defeated()):
		return "victory"
	if count(DUSMAN) == REGIONS.size() - 1:
		return "defeat"
	return "running"


## Görev bitti (gerçek uçuş, kariyer): cepheyi oynat, karargâh mesajı ekle. Döndürür: rapor satırları.
static func mission_result(mission_id: String, region_id: String, success: bool) -> PackedStringArray:
	var out := PackedStringArray()
	Career.day += 1
	var title := String(MissionManager.get_def(mission_id).get("title", mission_id))
	var combat := mission_id in COMBAT or (mission_id == "gen" and bool(Game.mission_card.get("combat", false)))
	if combat and region_id != "":
		var r := region(region_id)
		var o := owner(region_id)
		if mission_id == "onleme" or (mission_id == "gen" and Game.mission_card.get("template", "") == "onleme" and r.get("fixed", false)):
			if success:
				out.append("Üs savunuldu.")
				_news("Bombardımanlar düştü, üs sağlam. Teşekkürler. Kuzeyde hâlâ iş var.", "good")
			else:
				Career.money = maxi(Career.money - 4000, 0)
				out.append("Üs bombalandı: onarım -4.000 ₺")
				var lost := _push_enemy()
				if lost != "":
					out.append("%s geriledi (%s)." % [region(lost)["name"], OWNER_NAMES[owner(lost)]])
				_news("Bombalar üsse düştü. Pist onarılıyor, kasadan 4.000 ₺ çıktı.%s" % ("" if lost == "" else " Düşman fırsatı kaçırmadı: %s artık %s." % [region(lost)["name"], OWNER_NAMES[owner(lost)].to_lower()]), "bad")
		elif success and o == DOST:
			out.append("%s zaten bizde, hat güçlendi." % r["name"])
		elif success:
			var no := maxi(o - 1, DOST)
			Career.front[region_id] = no
			if no == DOST:
				out.append("CEPHE: %s geri alındı!" % r["name"])
				_news("%s artık bizim. %s" % [r["name"], _next_hint()], "good")
			else:
				out.append("CEPHE: %s bölgesinde hat yarıldı, bölge çekişmeli." % r["name"])
				_news("%s harekâtı başarılı, düşman hattı yarıldı. Bölgeyi tamamen almak için bir harekât daha lazım." % r["name"], "good")
		else:
			if o != DUSMAN and not r.get("fixed", false):
				Career.front[region_id] = mini(o + 1, DUSMAN)
				out.append("CEPHE: %s düşmana kaydı (%s)." % [r["name"], OWNER_NAMES[owner(region_id)]])
			else:
				out.append("CEPHE: %s harekâtı başarısız, hat değişmedi." % r["name"])
			_news("%s harekâtı (%s) başarısız. %s" % [r["name"], title, _design_hint(mission_id)], "bad")
	elif success:
		_news("%s tamamlandı. Halk ve kasa memnun." % title, "info")
	# düşmanın hamlesi: önceden haber verilen baskın / konvoy / taarruz (FrontAI)
	out.append_array(FrontAI.turn(mission_id, region_id, success))
	out.append_array(Campaign.on_mission(mission_id, region_id, success))   # perde hedefleri, hikâye satırı
	match status():
		"victory":
			out.append("ZAFER: düşman karargâhı düştü, sefer kazanıldı!")
			_news("Kuzey Havaalanı'nda bayrak dalgalanıyor, Kara Doğan yok. Bu seferi sen kazandın, pilot.", "good")
		"defeat":
			out.append("CEPHE ÇÖKTÜ: yalnız Ana Üs kaldı.")
			_news("Cephe çöktü, yalnız üs elimizde. Yeni bir sefer planlamamız gerekecek.", "bad")
	Career.save()
	return out


## Düşman bir adım ilerler: düşmana komşu, sabit olmayan, en zayıf dost/çekişmeli bölge.
static func _push_enemy() -> String:
	var cands := []
	for r: Dictionary in REGIONS:
		var id: String = r["id"]
		if r.get("fixed", false) or owner(id) == DUSMAN:
			continue
		for n: String in NEIGHBORS[id]:
			if owner(n) == DUSMAN:
				cands.append(id)
				break
	if cands.is_empty():
		return ""
	# çekişmeli bölgeler önce düşer
	cands.sort_custom(func(a: String, b: String) -> bool: return owner(a) > owner(b))
	var pick: String = cands[0] if randf() < 0.7 else cands.pick_random()
	Career.front[pick] = owner(pick) + 1
	return pick


static func _next_hint() -> String:
	for o: Dictionary in operations():
		if o["combat"] and owner(o["region"]) != DOST:
			return "Sıradaki hedef: %s." % region(o["region"])["name"]
	return ""


static func _design_hint(mission_id: String) -> String:
	var i: Dictionary = INTEL.get(mission_id, {})
	return "Önerim: %s" % i.get("advice", "uçağı gözden geçir.")


static func _news(text: String, kind := "info") -> void:
	Career.news.append({"day": Career.day, "text": text, "kind": kind})
	while Career.news.size() > 14:
		Career.news.remove_at(0)


## Yeni sefer: cephe baştan, karargâhın açılış mesajı.
static func new_campaign() -> void:
	Career.front = fresh_state()
	Career.day = 1
	Career.news = []
	Career.threats = []
	_news("Pilotlar, düşman kuzeyden indi: Ovaköy yolu ve Orta Vadi çekişmeli, Dereköy, Kuzeykent ve Kuzey Havaalanı onların elinde. Elimizde bir avuç uçak ve dar bir bütçe var. Her harekâttan önce istihbaratı oku, uçağını tehdide göre tasarla, istersen önce simülatörde dene. Ama unutma: gerçek uçuşta düşen uçağın bedeli de, kaybettiğimiz pilotun tazminatı da kasadan çıkar.", "info")
	Campaign.reset()   # Perde 1 ve açılış brifingi
