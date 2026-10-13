class_name Medals
## Pilot rütbeleri ve madalyaları (sabit veri + kontrol). Sayaçlar pilot sözlüğündedir
## (Crew.STAT_KEYS); uçuş sonunda Crew.end_flight → Medals.evaluate yeni kazanılanları döndürür.
##
## Rütbe: Hava Kuvvetleri sırası; seviye + uçuş sayısıyla terfi (geri düşmez).
## Madalya: tek bir sayacın eşiği (stat >= need). Kazanılan madalya "medals" dizisinde kalır.

## name, kısa ad, gereken seviye, gereken uçuş, yıldız sayısı, defne (üst subay), general
const RANKS := [
	{"name": "Asteğmen", "short": "Astğm.", "level": 1, "flights": 0, "stars": 1, "wreath": false, "general": false},
	{"name": "Teğmen", "short": "Tğm.", "level": 2, "flights": 2, "stars": 1, "wreath": false, "general": false},
	{"name": "Üsteğmen", "short": "Üsttğm.", "level": 3, "flights": 5, "stars": 2, "wreath": false, "general": false},
	{"name": "Yüzbaşı", "short": "Yzb.", "level": 4, "flights": 10, "stars": 3, "wreath": false, "general": false},
	{"name": "Binbaşı", "short": "Bnb.", "level": 5, "flights": 18, "stars": 1, "wreath": true, "general": false},
	{"name": "Yarbay", "short": "Yb.", "level": 7, "flights": 28, "stars": 2, "wreath": true, "general": false},
	{"name": "Albay", "short": "Alb.", "level": 8, "flights": 40, "stars": 3, "wreath": true, "general": false},
	{"name": "Tuğgeneral", "short": "Tuğg.", "level": 10, "flights": 60, "stars": 1, "wreath": true, "general": true},
]

## id, ad, açıklama (ölçüt), sayaç, eşik, kurdele renkleri [zemin, şerit]
const LIST := [
	{"id": "ilk_kan", "name": "İlk Kan", "desc": "İlk hava zaferi: bir düşman uçağı düşür.", "stat": "kills", "need": 1, "colors": [Color(0.75, 0.1, 0.12), Color(1, 1, 1)]},
	{"id": "as", "name": "As Pilot", "desc": "5 düşman uçağı düşür.", "stat": "kills", "need": 5, "colors": [Color(0.1, 0.2, 0.55), Color(1.0, 0.82, 0.25)]},
	{"id": "cifte_as", "name": "Çifte As", "desc": "10 düşman uçağı düşür.", "stat": "kills", "need": 10, "colors": [Color(1.0, 0.82, 0.25), Color(0.1, 0.2, 0.55)]},
	{"id": "gemi_avcisi", "name": "Gemi Avcısı", "desc": "Bir düşman savaş gemisi batır.", "stat": "ships", "need": 1, "colors": [Color(0.05, 0.25, 0.45), Color(0.4, 0.8, 1.0)]},
	{"id": "kara_kartali", "name": "Kara Kartalı", "desc": "10 yer hedefi (araç, SAM, radar, helikopter) yok et.", "stat": "ground_kills", "need": 10, "colors": [Color(0.4, 0.3, 0.12), Color(0.85, 0.65, 0.3)]},
	{"id": "sag_salim", "name": "Sağ Salim", "desc": "Fırlatma koltuğuyla atla ve sağ salim yere in.", "stat": "ejections", "need": 1, "colors": [Color(0.95, 0.5, 0.1), Color(1, 1, 1)]},
	{"id": "yumusak_eller", "name": "Yumuşak Eller", "desc": "10 yumuşak iniş yap (dikey hız 1.5 m/s'den az).", "stat": "soft_landings", "need": 10, "colors": [Color(0.55, 0.8, 0.95), Color(1, 1, 1)]},
	{"id": "usta_inisci", "name": "Usta İnişçi", "desc": "Toplam 100 iniş yap.", "stat": "landings", "need": 100, "colors": [Color(0.2, 0.5, 0.3), Color(1.0, 0.82, 0.25)]},
	{"id": "gece_kusu", "name": "Gece Kuşu", "desc": "Bir görevi gece (yerel saat 20:00–05:30) başarıyla bitir.", "stat": "night_missions", "need": 1, "colors": [Color(0.08, 0.06, 0.25), Color(0.75, 0.75, 1.0)]},
	{"id": "firtina_pilotu", "name": "Fırtına Pilotu", "desc": "Fırtınalı havada uçağı indir.", "stat": "storm_landings", "need": 1, "colors": [Color(0.3, 0.32, 0.38), Color(1.0, 0.9, 0.3)]},
	{"id": "uzun_yol", "name": "Uzun Yol", "desc": "Toplam 1000 km uç.", "stat": "km", "need": 1000, "colors": [Color(0.5, 0.15, 0.45), Color(0.95, 0.75, 0.95)]},
	{"id": "gorev_adami", "name": "Görev Adamı", "desc": "10 görevi başarıyla bitir.", "stat": "missions", "need": 10, "colors": [Color(0.1, 0.45, 0.25), Color(0.9, 0.15, 0.15)]},
	{"id": "kurtarici", "name": "Kurtarıcı", "desc": "Bir kurtarma görevini başarıyla bitir.", "stat": "rescues", "need": 1, "colors": [Color(0.9, 0.9, 0.9), Color(0.85, 0.1, 0.1)]},
	{"id": "demir_bilek", "name": "Demir Bilek", "desc": "Bayılmadan 9 G'yi aş.", "stat": "max_g", "need": 9, "colors": [Color(0.25, 0.25, 0.28), Color(0.9, 0.2, 0.2)]},
	{"id": "yarali_kahraman", "name": "Yaralı Kahraman", "desc": "Ağır hasarlı (bir parçası %40 canın altında) uçağı meydana indir.", "stat": "damaged_returns", "need": 1, "colors": [Color(0.6, 0.05, 0.1), Color(0.95, 0.8, 0.3)]},
	{"id": "kidemli", "name": "Kıdemli", "desc": "50 uçuş tamamla.", "stat": "flights", "need": 50, "colors": [Color(0.35, 0.25, 0.15), Color(0.85, 0.85, 0.85)]},
]


## Pilotun hak ettiği rütbe sırası (0..7).
static func rank_for(p: Dictionary) -> int:
	var r := 0
	for i in RANKS.size():
		if int(p.get("level", 1)) >= int(RANKS[i]["level"]) and int(p.get("flights", 0)) >= int(RANKS[i]["flights"]):
			r = i
	return r


static func rank_name(p: Dictionary) -> String:
	return String(RANKS[clampi(int(p.get("rank", 0)), 0, RANKS.size() - 1)]["name"])


static func rank_short(p: Dictionary) -> String:
	return String(RANKS[clampi(int(p.get("rank", 0)), 0, RANKS.size() - 1)]["short"])


static func by_id(id: String) -> Dictionary:
	for m in LIST:
		if m["id"] == id:
			return m
	return {}


static func has(p: Dictionary, id: String) -> bool:
	return id in (p.get("medals", []) as Array)


## Madalyanın ilerlemesi "3 / 10" biçiminde.
static func progress(p: Dictionary, m: Dictionary) -> String:
	var v := float(p.get(m["stat"], 0))
	return "%s / %s" % [_num(minf(v, float(m["need"]))), _num(float(m["need"]))]


static func _num(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.05 or v >= 100.0 else "%.1f" % v


## Yeni kazanılan madalyalar ve terfiyi işle. Döndürür: rapor satırları.
static func evaluate(p: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var got: Array = p.get("medals", [])
	for m in LIST:
		if not m["id"] in got and float(p.get(m["stat"], 0)) >= float(m["need"]):
			got.append(m["id"])
			out.append("MADALYA: %s — %s" % [m["name"], m["desc"]])
	p["medals"] = got
	var r := rank_for(p)
	if r > int(p.get("rank", 0)):
		p["rank"] = r
		out.append("TERFİ: %s %s oldu!" % [p["name"], RANKS[r]["name"]])
	return out
