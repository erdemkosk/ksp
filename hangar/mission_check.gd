class_name MissionCheck
extends PanelContainer
## Hangar mühendislik masası: görev kartı (istek) + canlı kontrol listesi.
## Görev kartındaki kısıtlar (menzil, yük, pist, tehditler, süre, hedef irtifa/hız, gece/hava,
## "needs" etiketleri) önizleme uçağın tahmini performansıyla karşılaştırılır; her düzenlemede
## ✓/⚠/✗ satırları ve genel karar ("Görev için uygun / Riskli / Yetersiz") güncellenir.
##
## Statik yardımcılar başka yerlerden de kullanılır:
##   estimate(v)        → performans tahmini (hangar istatistik paneli de bunu kullanır)
##   card_for(op)       → op["card"] ya da sabit görevler için tanım + brifingten türetilmiş kart
##   evaluate(card, e)  → kontrol listesi satırları ve karar

const OK := 0
const WARN := 1
const FAIL := 2
const ICONS := ["✓", "⚠", "✗"]
const COLORS := [Color(0.45, 1.0, 0.6), Color(1.0, 0.8, 0.35), Color(1.0, 0.45, 0.4)]
const VERDICTS := ["Görev için uygun", "Riskli", "Yetersiz"]
const CLIMB_STEP := 500.0
const CLIMB_TOP := 15000.0
const VMAX_ALTS := [0.0, 4000.0, 8000.0, 12000.0]
## radar güdümlü tehditler (chaff / ECM / radar avcısı işe yarar)
const RADAR_THREATS := ["sam", "sam_lr", "lr_sam", "radar", "ewr", "ship", "ships", "warship", "frigate", "carrier", "naval"]
const AIR_THREATS := ["fighter", "fighters", "cap", "ace", "air", "interceptor", "awacs"]
const IR_THREATS := ["manpads", "ir_sam", "shorad"]
const GUN_THREATS := ["aaa", "flak", "gun"]

## Sabit görevler için türetilmiş kart bilgisi (kartı olmayan "Göreve çık" için).
const STATIC_CARDS := {
	"egitim": {"needs": []},
	"kesif": {"needs": []},
	"kara": {"needs": ["guns_or_missiles"], "threats": [{"kind": "aaa", "n": 2, "range_km": 3.0}, {"kind": "fighter", "n": 1}]},
	"onleme": {"needs": ["climb", "speed", "guns_or_missiles"], "target_alt_m": 4000.0},
	"it": {"needs": ["agility", "guns_or_missiles"], "threats": [{"kind": "fighter", "n": 1}]},
	"heli": {"needs": ["guns_or_missiles"]},
	"sam": {"needs": [], "threats": [{"kind": "sam", "n": 2, "range_km": 9.0}, {"kind": "aaa", "n": 3, "range_km": 3.0}]},
	"sead": {"needs": ["anti_radar"], "threats": [{"kind": "sam_lr", "n": 1, "range_km": 40.0}, {"kind": "sam", "n": 2, "range_km": 9.0}, {"kind": "manpads", "n": 1, "range_km": 4.0}]},
	"derin": {"needs": ["payload", "range"], "payload_kg": 750.0, "threats": [{"kind": "ewr", "n": 1, "range_km": 30.0}, {"kind": "sam", "n": 1, "range_km": 9.0}, {"kind": "manpads", "n": 3, "range_km": 4.0}, {"kind": "fighter", "n": 2}]},
	"ussaldiri": {"needs": ["payload"], "payload_kg": 1000.0, "threats": [{"kind": "aaa", "n": 4, "range_km": 3.0}, {"kind": "sam", "n": 1, "range_km": 9.0}, {"kind": "manpads", "n": 2, "range_km": 4.0}, {"kind": "fighter", "n": 2}]},
	"uzak": {"needs": ["standoff"], "threats": [{"kind": "sam_lr", "n": 1, "range_km": 40.0}]},
	"deniz": {"needs": ["anti_ship"], "threats": [{"kind": "ship", "n": 2, "range_km": 12.0}]},
	"filo": {"needs": ["anti_ship"], "threats": [{"kind": "ship", "n": 3, "range_km": 16.0}, {"kind": "fighter", "n": 2}]},
	"firkateyn": {"needs": ["anti_ship"], "threats": [{"kind": "ship", "n": 2, "range_km": 16.0}]},
	"devriye": {"needs": ["anti_ship"], "threats": [{"kind": "ship", "n": 3, "range_km": 12.0}]},
	"ikmal": {"needs": ["probe"]},
	"yolcu": {"needs": ["passengers"], "passengers": 6},
	"tasima": {"needs": ["passengers", "range"], "passengers": 6, "runway_m": 1800.0},
	"kurtarma": {"needs": ["passengers", "short_runway", "low_slow"], "passengers": 3, "runway_m": 500.0},
	"kargo": {"needs": ["cargo"], "payload_kg": 900.0},
	"nakliye": {"needs": ["cargo", "range"], "payload_kg": 2400.0, "runway_m": 1800.0},
}

var card := {}
var est := {}
var result := {}            ## son evaluate() sonucu
var _body: RichTextLabel
var _verdict: Label
var _info: Label
var _folded := false


static func create(c: Dictionary) -> MissionCheck:
	var m := MissionCheck.new()
	m.card = c
	return m


func _ready() -> void:
	var sb := UiTheme.flat(Color(0.03, 0.05, 0.06, 0.93), 10)
	sb.border_color = Color(1.0, 0.82, 0.4, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := Label.new()
	t.text = "GÖREV KARTI  ·  " + String(card.get("title", "Görev"))
	t.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	t.add_theme_font_size_override("font_size", 15)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	var fold := Button.new()
	fold.text = "▾"
	fold.flat = true
	fold.focus_mode = Control.FOCUS_NONE
	fold.tooltip_text = "Kartı daralt / aç"
	head.add_child(fold)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_info.text = _card_text(card)
	box.add_child(_info)
	var sep := HSeparator.new()
	box.add_child(sep)
	_verdict = Label.new()
	_verdict.add_theme_font_size_override("font_size", 16)
	box.add_child(_verdict)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_body)
	fold.pressed.connect(func() -> void:
		_folded = not _folded
		fold.text = "▸" if _folded else "▾"
		_info.visible = not _folded
		sep.visible = not _folded
		_body.visible = not _folded)
	_render()


## Önizleme uçağı değişti: tahmini yenile, listeyi yeniden yaz.
func refresh(v: Vessel) -> void:
	est = estimate(v) if is_instance_valid(v) and not v.parts.is_empty() else {}
	result = evaluate(card, est)
	_render()


func _render() -> void:
	if _body == null:
		return
	if result.is_empty():
		result = evaluate(card, est)
	var vd := int(result.get("verdict", FAIL))
	_verdict.text = "KARAR:  " + VERDICTS[vd]
	_verdict.add_theme_color_override("font_color", COLORS[vd])
	var lines := PackedStringArray()
	for it: Array in result.get("items", []):
		lines.append("[color=#%s]%s  %s[/color]" % [COLORS[int(it[0])].to_html(false), ICONS[int(it[0])], String(it[1])])
	_body.text = "\n".join(lines)


## Karar 2 (yetersiz) satırları — "Tamam" onay penceresi için.
func failures() -> PackedStringArray:
	var out := PackedStringArray()
	for it: Array in result.get("items", []):
		if int(it[0]) == FAIL:
			out.append(String(it[1]))
	return out


# ------------------------------------------------------------------ kart

## op'tan görev kartı: kart varsa o (eksik anahtarlar tamamlanır), yoksa sabit görevden türetilir.
static func card_for(op: Dictionary) -> Dictionary:
	var c: Dictionary = (op.get("card", {}) as Dictionary).duplicate(true) if op.get("card", {}) is Dictionary else {}
	var mid := String(op.get("mission", ""))
	if c.is_empty() and mid != "":
		# görev üreticisinin kartı (sabit görevler için tanımdan türetilir) + buradaki ek istekler
		c = MissionGen.make_card(op).duplicate(true)
		var extra: Dictionary = STATIC_CARDS.get(mid, {})
		for k in extra:
			if k == "needs" and c.get("needs", []) is Array:
				for n: String in extra["needs"]:
					if not n in (c["needs"] as Array):
						(c["needs"] as Array).append(n)
			elif k == "threats" and not (c.get("threats", []) as Array).is_empty():
				continue
			else:
				c[k] = extra[k]
	if c.is_empty():
		c = derive_card(mid)
	if not c.has("region") and op.has("region"):
		c["region"] = op["region"]
	return c


static func derive_card(id: String) -> Dictionary:
	var def := MissionManager.get_def(id)
	if def.is_empty():
		return {}
	var c := {"id": id, "template": "static", "title": def.get("title", id), "brief": def.get("brief", ""),
		"base_xz": Vector2.ZERO, "needs": [], "threats": []}
	var info := MissionManager.briefing(id)
	var target := Vector2.INF
	for p: Array in info.get("points", []):
		if String(p[0]) == "Sen" or String(p[0]).begins_with("Ana Üs"):
			continue
		var col: Color = p[2]
		if target == Vector2.INF or col.r > 0.9 and col.g < 0.5:
			target = p[1]
			if col.r > 0.9 and col.g < 0.5:
				break
	if target != Vector2.INF:
		c["target_xz"] = target
		c["range_km"] = target.length() / 1000.0
	if def.has("time"):
		c["time_limit_s"] = float(def["time"])
	var extra: Dictionary = STATIC_CARDS.get(id, {})
	for k in extra:
		c[k] = extra[k]
	return c


static func _xz(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is Dictionary:
		return Vector2(float(v.get("x", 0.0)), float(v.get("y", v.get("z", 0.0))))
	return Vector2.INF


static func target_xz(c: Dictionary) -> Vector2:
	return _xz(c.get("target_xz", null))


static func base_xz(c: Dictionary) -> Vector2:
	var b := _xz(c.get("base_xz", null))
	return Vector2.ZERO if b == Vector2.INF else b


## Tek yön mesafe (km): kartta yazan ya da üs-hedef arası.
static func one_way_km(c: Dictionary) -> float:
	if float(c.get("range_km", 0.0)) > 0.0:
		return float(c["range_km"])
	var t := target_xz(c)
	return 0.0 if t == Vector2.INF else t.distance_to(base_xz(c)) / 1000.0


## Kart havası → Weather.Preset (-1: belirsiz). Sayı, ad ya da İngilizce anahtar olabilir.
static func weather_preset(w: Variant) -> int:
	if w is int or w is float:
		return clampi(int(w), 0, 4)
	if not w is String or String(w) == "":
		return -1
	var s := String(w).to_lower()
	var keys := {"clear": 0, "açık": 0, "acik": 0, "scattered": 1, "parçalı": 1, "parcali": 1, "parçalı bulutlu": 1,
		"overcast": 2, "kapalı": 2, "kapali": 2, "storm": 3, "fırtına": 3, "firtina": 3, "rain": 3, "yağmur": 3,
		"fog": 4, "sis": 4, "sisli": 4}
	return int(keys.get(s, -1))


static func weather_name(w: Variant) -> String:
	var p := weather_preset(w)
	return String(Weather.PRESETS[p]["name"]) if p >= 0 else ""


static func _card_text(c: Dictionary) -> String:
	if c.is_empty():
		return "Görev kartı yok."
	var parts := PackedStringArray()
	var km := one_way_km(c)
	if km > 0.0:
		parts.append("Hedef %d km (gidiş-dönüş %d)" % [km, km * 2.0])
	if float(c.get("payload_kg", 0.0)) > 0.0:
		parts.append("Yük %s" % tons(float(c["payload_kg"])))
	if float(c.get("runway_m", 0.0)) > 0.0:
		parts.append("Pist %d m" % float(c["runway_m"]))
	if float(c.get("time_limit_s", 0.0)) > 0.0:
		parts.append("Süre %s" % dur(float(c["time_limit_s"])))
	if float(c.get("target_alt_m", 0.0)) > 0.0:
		parts.append("Hedef irtifa %d m" % float(c["target_alt_m"]))
	if float(c.get("target_mach", 0.0)) > 0.0:
		parts.append("Hedef hızı M%.1f" % float(c["target_mach"]))
	if bool(c.get("night", false)):
		parts.append("GECE")
	var wn := weather_name(c.get("weather", ""))
	if wn != "":
		parts.append("Hava: " + wn)
	var thr := PackedStringArray()
	for t: Variant in c.get("threats", []):
		if t is Dictionary:
			thr.append(threat_label(t))
	var brief := String(c.get("brief", ""))
	if brief.length() > 260:
		brief = brief.substr(0, 257) + "…"
	var out := brief
	if not parts.is_empty():
		out += "\n" + "  ·  ".join(parts)
	if not thr.is_empty():
		out += "\nTehdit: " + ", ".join(thr)
	var doc: Array = c.get("doctrine", []) if c.get("doctrine", []) is Array else []
	for i in mini(doc.size(), 2):
		out += "\n» " + String(doc[i])
	return out


static func threat_label(t: Dictionary) -> String:
	var kind := String(t.get("kind", "?"))
	var names := {"sam": "SAM", "sam_lr": "uzun menzilli SAM", "lr_sam": "uzun menzilli SAM", "aaa": "uçaksavar", "flak": "uçaksavar",
		"fighter": "avcı", "fighters": "avcı", "cap": "avcı devriye", "ace": "düşman as", "manpads": "omuzdan SAM",
		"radar": "radar", "ewr": "erken uyarı radarı", "ship": "savaş gemisi", "warship": "savaş gemisi", "frigate": "fırkateyn",
		"carrier": "uçak gemisi", "awacs": "AWACS"}
	var s := String(names.get(kind, kind))
	if int(t.get("n", 1)) > 1:
		s = "%d× %s" % [int(t["n"]), s]
	if float(t.get("range_km", 0.0)) > 0.0:
		s += " (%d km)" % float(t["range_km"])
	return s


## Test kartı (--cardtest): görev üreticisinin sözleşmesindeki bütün anahtarlar.
static func sample_card() -> Dictionary:
	return {"id": "kart_test", "template": "strike", "title": "Gece Köprü Baskını",
		"brief": "Kuzeybatıdaki köprüyü gece yık: düşman ikmal kolu sabaha kadar geçmiş olacak. Öne itilmiş kısa bir toprak pistten kalkılacak.",
		"region": "sahil", "target_xz": Vector2(-18000, -24000), "base_xz": Vector2.ZERO, "range_km": 30.0,
		"payload_kg": 2000.0, "runway_m": 600.0,
		"threats": [{"kind": "sam", "n": 2, "range_km": 9.0}, {"kind": "fighter", "n": 2, "range_km": 0.0}, {"kind": "manpads", "n": 2, "range_km": 4.0}],
		"time_limit_s": 360.0, "target_alt_m": 0.0, "target_mach": 0.0, "night": true, "weather": "overcast",
		"needs": ["payload", "range", "short_runway"], "reward": 9000, "seed": 7, "events": [],
		"doctrine": ["Düşman SAM'ları vadiyi kapatıyor: alçak gir.", "Avcılar alarmdan 4 dk sonra kalkar."]}


# ------------------------------------------------------------------ biçim

static func dur(s: float) -> String:
	if s == INF or is_nan(s):
		return "—"
	var m := int(s) / 60
	var sec := int(s) % 60
	if m == 0:
		return "%d sn" % sec
	return ("%d dk %d sn" % [m, sec]) if sec >= 5 and m < 10 else "%d dk" % roundi(s / 60.0)


static func tons(kg: float) -> String:
	if kg < 1000.0:
		return "%d kg" % kg
	return ("%.1f ton" % (kg / 1000.0)).replace(".", ",").replace(",0 ton", " ton")


# ------------------------------------------------------------------ performans tahmini

static var _cache_key := ""
static var _cache := {}


## Kaba performans tahmini (hangar istatistikleriyle aynı model): sürükleme alanı, itki eğrileri,
## azami hız, kalkış hızı/mesafesi, tırmanma profili, dayanım/menzil; ayrıca yük, mühimmat ve
## sensör/karşı tedbir dökümü. Değerler sade sayı/bool (uçuşa taşınabilir: kart["design"]).
static func estimate(v: Vessel) -> Dictionary:
	# önizleme her düzenlemede yeniden kurulur: aynı uçak için tek hesap (istatistik + kart)
	var key := "%d:%d:%.1f:%.1f" % [v.get_instance_id(), v.parts.size(), v.mass, v.fuel_capacity()]
	if key == _cache_key:
		return _cache
	var e := _estimate(v)
	_cache_key = key
	_cache = e
	return e


static func _estimate(v: Vessel) -> Dictionary:
	var e := {}
	var mass := v.mass
	var dry := 0.0
	for p in v.parts:
		dry += p.dry_mass
	var thrust := 0.0
	var wing_area := 0.0
	var cda := 0.0
	var fuel_rate := 0.0
	var jato := 0.0
	var jato_time := 0.0
	var intake_area := 0.0
	var ramjet := false
	var tvc := false
	var bomb_kg := 0.0
	var bombs := 0
	var heavy_bombs := 0
	var lgb := 0
	var glide := 0
	var crates := 0
	var guns := 0
	var ir := 0
	var radar_m := 0
	var arm := 0
	var ship := 0
	var cruise := 0
	var ag_missile_kg := 0.0
	var ecm := false
	var pod := false
	var radar := false
	var irst := false
	var probe := false
	var chute := false
	for m in v.modules:
		if m is EngineModule:
			thrust += m.max_thrust
			fuel_rate += m.fuel_rate
			ramjet = ramjet or m.ramjet
			tvc = tvc or m.gimbal > 0.0
		elif m is WingModule:
			wing_area += m.area
			cda += m.cd0 * m.area
		elif m is BodyDragModule:
			cda += m.cd_front * m.front_area
		elif m is BoosterModule:
			jato += m.thrust_max
			jato_time = maxf(jato_time, m.burn_time)
		elif m is IntakeModule:
			intake_area += m.area
		elif m is GunModule:
			guns += 1
		elif m is BombModule:
			if m.loaded:
				bombs += 1
				bomb_kg += float(BombModule.MASSES.get(m.kind, BombModule.BOMB_MASS))
				heavy_bombs += 1 if m.kind == "heavy" else 0
				lgb += 1 if m.kind == "lgb" or m.guided else 0
				glide += 1 if m.kind == "glide" else 0
		elif m is BombBayModule:
			bombs += m.bombs
			bomb_kg += m.bombs * BombBayModule.BOMB_MASS
		elif m is CargoModule:
			crates += m.crates
		elif m is MissileModule:
			if not m.loaded:
				continue
			match m.guidance:
				"ir":
					ir += 1
				"radar":
					radar_m += 1
				"arm":
					arm += 1
					ag_missile_kg += float(MissileModule.MASSES["arm"])
				"ship":
					ship += 1
					ag_missile_kg += float(MissileModule.MASSES["ship"])
				"cruise":
					cruise += 1
					ag_missile_kg += float(MissileModule.MASSES["cruise"])
		elif m is EcmModule:
			ecm = true
		elif m is TargetingPodModule:
			pod = true
		elif m is RadarModule:
			radar = true
		elif m is IrstModule:
			irst = true
		elif m is ChuteModule:
			chute = true
		elif m is RefuelProbeModule:
			probe = true
	var static_thrust := thrust_at(v, 0.0, 0.0, true)
	var intake_need := thrust / 70000.0 * 0.5
	e["mass"] = mass
	e["dry"] = dry
	e["fuel"] = v.fuel_capacity()
	e["thrust"] = thrust
	e["static_thrust"] = static_thrust
	e["tw"] = static_thrust / maxf(mass * 9.81, 1.0)
	e["wing_area"] = wing_area
	e["wing_loading"] = mass / maxf(wing_area, 0.1)
	e["intake_pct"] = intake_area / intake_need if intake_need > 0.0 else 1.0
	e["stall_kmh"] = sqrt(2.0 * mass * 9.81 / (1.225 * maxf(wing_area, 0.1) * 1.2)) * 3.6
	e["ramjet"] = ramjet
	e["tvc"] = tvc
	e["jato"] = jato
	e["jato_time"] = jato_time
	e["bomb_kg"] = bomb_kg
	e["bombs"] = bombs
	e["heavy_bombs"] = heavy_bombs
	e["lgb"] = lgb
	e["glide"] = glide
	e["crates"] = crates
	e["cargo_kg"] = crates * CargoModule.CRATE_MASS
	e["payload_kg"] = bomb_kg + ag_missile_kg
	e["guns"] = guns
	e["ir"] = ir
	e["radar_missiles"] = radar_m
	e["arm"] = arm
	e["ship"] = ship
	e["cruise"] = cruise
	e["ecm"] = ecm
	e["pod"] = pod
	e["radar"] = radar
	e["irst"] = irst
	e["probe"] = probe
	e["chaff"] = v.chaff_left()
	e["flares"] = v.flares_left()
	e["seats"] = v.passenger_seats()
	e["flyable"] = thrust > 0.0 and wing_area >= 1.0
	if not e["flyable"]:
		e["range_km"] = 0.0
		e["can_roll"] = false
		return e
	# azami hız: her motor kendi hız eğrisiyle, art yakıcıyla
	var vmax := func(alt: float) -> float:
		var rho := Atmosphere.density(alt)
		var best := 0.0
		for i in 600:
			var s := 20.0 + i * 2.0
			var drag := 0.5 * rho * s * s * cda * Atmosphere.wave_drag(s / Atmosphere.SPEED_OF_SOUND) * 1.25
			if thrust_at(v, s, alt, true) > drag:
				best = s
		return best
	var vm := []
	for a: float in VMAX_ALTS:
		vm.append(vmax.call(a))
	var v0: float = vm[0]
	var v8: float = vm[2]
	var vs := sqrt(2.0 * mass * 9.81 / (1.225 * wing_area * 1.2))
	var vto := vs * 1.2
	# kalkış koşusu: tam güç ortalaması + JATO (yandığı sürece)
	var t_roll := (thrust_at(v, 0.0, 0.0, true) + thrust_at(v, vto, 0.0, true)) * 0.5
	var acc := t_roll / mass - 0.03 * 9.81
	var can_roll := acc > 0.05
	if jato > 0.0:
		var acc_j := (t_roll + jato) / mass - 0.03 * 9.81
		var v_j := acc_j * jato_time
		if acc_j > 0.05 and v_j >= vto:
			acc = acc_j
			can_roll = true
		elif acc_j > 0.05 and acc > 0.05:
			acc = vto / (jato_time + (vto - v_j) / acc)
	var dto := vto * vto / (2.0 * maxf(acc, 0.1)) * 1.15
	var vc := clampf(v0 * 0.6, vs * 1.4, maxf(v0, vs * 1.4))
	var dc := 0.5 * 1.225 * vc * vc * cda * 1.25
	var climb := (thrust_at(v, vc, 0.0, false) - dc) * vc / (mass * 9.81)
	var fuel: float = e["fuel"]
	var endurance := fuel / maxf(fuel_rate * 0.45, 0.01) / 60.0
	# tırmanma profili (tam güç, art yakıcı; sabit eşdeğer hız + indüklenmiş sürükleme)
	var prof := [0.0]
	var t_acc := 0.0
	var h := 0.0
	while h < CLIMB_TOP:
		var hm := h + CLIMB_STEP * 0.5
		var rho := Atmosphere.density(hm)
		var spd := minf(vc * sqrt(1.225 / rho), maxf(_interp(vm, hm) * 0.9, vc))
		var q := 0.5 * rho * spd * spd
		var cl := mass * 9.81 / maxf(q * wing_area, 0.01)
		var drag := q * cda * 1.25 * Atmosphere.wave_drag(spd / Atmosphere.SPEED_OF_SOUND) + q * wing_area * 0.07 * cl * cl
		var roc := (thrust_at(v, spd, hm, true) - drag) * spd / (mass * 9.81)
		if roc < 1.0 or cl > 1.3:
			break
		t_acc += CLIMB_STEP / roc
		prof.append(t_acc)
		h += CLIMB_STEP
	var shift := 0.0
	var dry_pos := Vector3.ZERO
	for p in v.parts:
		dry_pos += p.position * p.dry_mass
	if dry > 0.0:
		shift = (dry_pos / dry).z - v.com_local.z
	e["vmax"] = vm
	e["v0"] = v0
	e["v8"] = v8
	e["mach_max"] = maxf(v0 / Atmosphere.SPEED_OF_SOUND, v8 / 308.0)
	e["vs"] = vs
	e["vto"] = vto
	e["dto"] = dto
	# iniş koşusu: 1.3 Vs ile teker koyma, fren ~0.35 g (+ fren paraşütü)
	var vland := vs * 1.3
	e["dland"] = vland * vland / (2.0 * 9.81 * (0.35 + (0.2 if chute else 0.0))) * 1.2
	e["chute"] = chute
	e["can_roll"] = can_roll
	e["vc"] = vc
	e["climb"] = maxf(climb, 0.0)
	e["climb_profile"] = prof
	e["ceiling"] = (prof.size() - 1) * CLIMB_STEP
	e["endurance_min"] = endurance
	e["range_km"] = endurance * 60.0 * vc * 0.9 / 1000.0
	e["cg_shift"] = shift
	return e


## Diziyi VMAX_ALTS irtifalarına göre doğrusal ara değerle.
static func _interp(vals: Array, alt: float) -> float:
	if vals.is_empty():
		return 0.0
	for i in VMAX_ALTS.size() - 1:
		if alt <= VMAX_ALTS[i + 1]:
			var k := clampf((alt - VMAX_ALTS[i]) / (VMAX_ALTS[i + 1] - VMAX_ALTS[i]), 0.0, 1.0)
			return lerpf(float(vals[i]), float(vals[i + 1]), k)
	return float(vals[vals.size() - 1])


## alt (m) irtifaya tam güçle tırmanma süresi (sn); erişemezse INF.
static func climb_time(e: Dictionary, alt: float) -> float:
	var prof: Array = e.get("climb_profile", [])
	if prof.is_empty():
		return INF
	var f := alt / CLIMB_STEP
	var i := int(f)
	if i + 1 >= prof.size():
		return float(prof[i]) if i < prof.size() and is_equal_approx(f, float(i)) else INF
	return lerpf(float(prof[i]), float(prof[i + 1]), f - i)


## Kalkıştan hedefe varış (sn): irtifaya tırmanma + kalan yol seyir-hücum hızıyla (azami hızın %85'i).
static func time_to_target(e: Dictionary, dist_m: float, alt: float) -> float:
	if not e.get("flyable", false):
		return INF
	var ct := climb_time(e, alt)
	if ct == INF:
		return INF
	var dash := maxf(_interp(e.get("vmax", []), alt) * 0.85, float(e.get("vc", 100.0)))
	var climb_dist := ct * float(e.get("vc", 100.0)) * 0.8
	return ct + maxf(dist_m - climb_dist, 0.0) / dash + 30.0   # +30 sn: kalkış koşusu


## Uçağın toplam itkisi (N): hız s (m/s), irtifa alt (m). EngineModule ile aynı eğriler.
static func thrust_at(v: Vessel, s: float, alt: float, ab: bool) -> float:
	var dr := Atmosphere.density(alt) / Atmosphere.SEA_LEVEL_DENSITY
	var mach := s / Atmosphere.SPEED_OF_SOUND
	var total := 0.0
	for e in v.modules:
		if not e is EngineModule:
			continue
		var k := 1.0 + 0.18 * minf(mach, 1.6) - maxf(mach - 2.2, 0.0) * 0.8
		var floor_k := 0.2
		if e.prop:
			k = clampf(1.0 - pow(s / e.prop_vmax, 2.0) * 0.85, 0.08, 1.0)
		elif e.ramjet:
			k = EngineModule.ramjet_factor(mach)
			floor_k = 0.0
		elif e.pulse_mach > 0.0:
			k = clampf(1.0 - pow(mach / e.pulse_mach, 4.0) * 0.9, 0.05, 1.0)
		elif e.rocket:
			k = 1.0
		var burner: float = EngineModule.AFTERBURNER_THRUST if ab and not (e.no_ab or e.prop or e.rocket) else 1.0
		var dens := 1.0 if e.rocket else pow(dr, 0.7)
		total += e.max_thrust * e.thrust_limit * burner * dens * maxf(k, floor_k)
	return total


# ------------------------------------------------------------------ kontrol listesi

static func _has(c: Dictionary, tag: String) -> bool:
	var n: Variant = c.get("needs", [])
	return n is Array and tag in (n as Array)


static func _threat_kinds(c: Dictionary) -> Array:
	var out := []
	for t: Variant in c.get("threats", []):
		if t is Dictionary:
			out.append(String(t.get("kind", "")).to_lower())
	return out


## Kart ve tahminden kontrol listesi: {"items": [[durum, metin], …], "verdict": 0/1/2}.
static func evaluate(c: Dictionary, e: Dictionary) -> Dictionary:
	var items: Array = []
	var add := func(st: int, text: String) -> void:
		items.append([st, text])
	if c.is_empty():
		return {"items": [], "verdict": OK}
	if e.is_empty() or not e.get("flyable", false):
		add.call(FAIL, "uçak uçamaz: motor ve kanat gerekli")
		return {"items": items, "verdict": FAIL}
	var km := one_way_km(c)
	var kinds := _threat_kinds(c)
	# menzil (gidiş-dönüş, %10 yedek)
	if km > 0.0:
		var need := km * 2.0
		var r: float = e["range_km"]
		var txt := "menzil %d km (gerekli %d km gidiş-dönüş)" % [r, need]
		if r >= need * 1.1:
			add.call(OK, txt)
		elif r >= need:
			add.call(WARN, txt + " — yedek yakıt çok az")
		elif e["probe"]:
			add.call(WARN, txt + " — ikmal probu var, tanker gerekir")
		else:
			add.call(FAIL, txt + " — tank ekle ya da yükü azalt")
	# yük
	var cargo := _has(c, "cargo")
	var pk := float(c.get("payload_kg", 0.0))
	if cargo:
		var ck: float = e["cargo_kg"]
		var ctxt := "kargo %s (%d sandık)" % [tons(ck), e["crates"]]
		if pk > 0.0:
			ctxt = "kargo %s (%s gerekli)" % [tons(ck), tons(pk)]
		add.call(OK if (ck >= pk and int(e["crates"]) > 0) else FAIL, ctxt)
	elif pk > 0.0 or _has(c, "payload"):
		var pl: float = e["payload_kg"]
		if pk > 0.0:
			add.call(OK if pl >= pk else (WARN if pl >= pk * 0.75 else FAIL), "yük %s (%s gerekli)" % [tons(pl), tons(pk)])
		else:
			add.call(OK if pl > 0.0 else FAIL, "yük %s (taarruz mühimmatı gerekli)" % tons(pl))
	# pist
	var rw := float(c.get("runway_m", 0.0))
	if not e["can_roll"]:
		add.call(FAIL, "kalkamaz: düşük hızda itki yok — ek motor ya da JATO")
	else:
		var dto: float = e["dto"]
		var rwl := rw if rw > 0.0 else 2400.0
		var rtxt := "kalkış mesafesi %d m (pist %d m)" % [dto, rwl]
		if dto <= rwl * 0.85:
			if rw > 0.0 or dto > 1600.0:
				add.call(OK, rtxt)
		elif dto <= rwl:
			add.call(WARN, rtxt + " — pist sınırda")
		else:
			add.call(FAIL, rtxt + " — kanat alanı / itki / JATO")
	if rw > 0.0 and (_has(c, "short_runway") or rw < 1500.0) and e.has("dland"):
		var dl: float = e["dland"]
		add.call(OK if dl <= rw * 0.85 else WARN, "iniş mesafesi ~%d m (pist %d m)%s" % [dl, rw, "" if dl <= rw * 0.85 else " — fren paraşütü, daha geniş kanat ya da hafif uçak"])
	if _has(c, "low_slow"):
		var st: float = e["stall_kmh"]
		add.call(OK if st <= 180.0 else (WARN if st <= 240.0 else FAIL), "stall hızı %d km/sa (kısa saha için ≤180)" % st)
	# süre / önleme
	var tl := float(c.get("time_limit_s", 0.0))
	var talt := float(c.get("target_alt_m", 0.0))
	if talt > 0.0:
		var ct := climb_time(e, talt)
		var ctxt2 := "%d m'ye tırmanma %s" % [talt, dur(ct)] if ct != INF else "%d m'ye çıkamaz (tavan ~%d m)" % [talt, e["ceiling"]]
		if tl > 0.0:
			ctxt2 += " (süre %s)" % dur(tl)
			add.call(OK if ct <= tl * 0.5 else (WARN if ct <= tl * 0.8 else FAIL), "önleme: " + ctxt2)
		else:
			add.call(OK if ct <= 360.0 else (WARN if ct != INF else FAIL), ctxt2)
	if tl > 0.0 and km > 0.0:
		var tt := time_to_target(e, km * 1000.0, talt)
		add.call(OK if tt <= tl * 0.8 else (WARN if tt <= tl else FAIL), "hedefe varış ~%s (süre %s)" % [dur(tt), dur(tl)])
	# hız
	var tm := float(c.get("target_mach", 0.0))
	var mm: float = e["mach_max"]
	if tm > 0.0:
		add.call(OK if mm >= tm + 0.15 else (WARN if mm >= tm else FAIL), "azami hız M%.2f (hedef M%.2f)" % [mm, tm])
	elif _has(c, "speed"):
		var kmh: float = float(e["v0"]) * 3.6
		add.call(OK if kmh >= 1000.0 else (WARN if kmh >= 800.0 else FAIL), "azami hız %d km/sa (hızlı uçak gerekli)" % kmh)
	if _has(c, "climb") and talt <= 0.0:
		var cl: float = e["climb"]
		add.call(OK if cl >= 120.0 else (WARN if cl >= 60.0 else FAIL), "tırmanma %d m/s" % cl)
	if _has(c, "agility"):
		var tw: float = e["tw"]
		var wl: float = e["wing_loading"]
		add.call(OK if tw >= 0.9 and wl <= 450.0 else WARN, "çeviklik: itki/ağırlık %.2f, kanat yükü %d kg/m²" % [tw, wl])
	# silah / özel görev ihtiyaçları
	var guns: int = e["guns"]
	var aam: int = int(e["ir"]) + int(e["radar_missiles"])
	if _has(c, "guns_or_missiles"):
		add.call(OK if guns + aam + int(e["bombs"]) > 0 else FAIL, "silah: %d top · %d füze" % [guns, aam] if guns + aam > 0 else "silah yok (top ya da füze gerekli)")
	if _has(c, "anti_radar"):
		if int(e["arm"]) > 0:
			add.call(OK, "radar avcısı füze ×%d" % e["arm"])
		elif e["ecm"]:
			add.call(WARN, "yalnız ECM: radarları yok etmek için radar avcısı (ARM) gerekir")
		else:
			add.call(FAIL, "radar avcısı füze (ARM) yok")
	if _has(c, "anti_ship"):
		if int(e["ship"]) > 0:
			add.call(OK if int(e["ship"]) >= 2 else WARN, "gemi savar füze ×%d%s" % [e["ship"], "" if int(e["ship"]) >= 2 else " — CIWS birini düşürebilir, iki taşı"])
		elif float(e["bomb_kg"]) >= 1000.0:
			add.call(WARN, "gemi savar füze yok: bombayla gemiye yaklaşmak tehlikeli")
		else:
			add.call(FAIL, "gemi savar füze yok")
	if _has(c, "recon"):
		add.call(OK if e["pod"] else FAIL, "keşif: hedefleme podu (kamera)" + ("" if e["pod"] else " gerekli"))
	if _has(c, "standoff"):
		var so := int(e["cruise"]) + int(e["glide"])
		add.call(OK if so > 0 else FAIL, "uzaktan vuruş: seyir füzesi / süzülen bomba ×%d" % so if so > 0 else "seyir füzesi ya da süzülen bomba gerekli")
	if _has(c, "probe"):
		add.call(OK if e["probe"] else FAIL, "havada ikmal probu" + ("" if e["probe"] else " gerekli"))
	if _has(c, "passengers"):
		var need_s := int(c.get("passengers", 1))
		add.call(OK if int(e["seats"]) >= need_s else FAIL, "yolcu koltuğu %d (%d gerekli)" % [e["seats"], need_s])
	if int(e["lgb"]) > 0 and not e["pod"]:
		add.call(WARN, "lazer bomba var ama hedefleme podu yok")
	# tehditler
	var radar_t := kinds.any(func(k: String) -> bool: return k in RADAR_THREATS)
	if radar_t:
		var cm := PackedStringArray()
		if int(e["chaff"]) > 0:
			cm.append("chaff %d" % e["chaff"])
		if e["ecm"]:
			cm.append("ECM")
		if int(e["arm"]) > 0:
			cm.append("ARM")
		var what := "gemi radarına" if kinds.all(func(k: String) -> bool: return not k in RADAR_THREATS or k in ["ship", "ships", "warship", "frigate", "carrier", "naval"]) else "SAM'a"
		if cm.is_empty():
			add.call(WARN, "%s karşı savunma yok (chaff/ECM/radar avcısı önerilir)" % what)
		else:
			add.call(OK, "%s karşı: %s" % [what, ", ".join(cm)])
	if kinds.any(func(k: String) -> bool: return k in AIR_THREATS):
		if aam > 0:
			add.call(OK, "avcılara karşı: %d füze%s" % [aam, " · top" if guns > 0 else ""])
		elif guns > 0:
			add.call(WARN, "avcılara karşı yalnız top — hava-hava füzesi önerilir")
		else:
			add.call(WARN, "avcılara karşı silah yok (kaçmak için hız gerekir)")
	if kinds.any(func(k: String) -> bool: return k in IR_THREATS or k in AIR_THREATS):
		if int(e["flares"]) <= 0:
			add.call(WARN, "flare yok: ısı güdümlü füzelere karşı savunmasız")
	if kinds.any(func(k: String) -> bool: return k in GUN_THREATS) and float(e["v0"]) * 3.6 < 650.0:
		add.call(WARN, "uçaksavar: yavaş uçak alçakta savunmasız — yüksekten ya da hızla geç")
	# gece / hava
	if bool(c.get("night", false)):
		if e["pod"] or e["irst"]:
			add.call(OK, "gece: %s var" % ("hedefleme podu" if e["pod"] else "IRST"))
		else:
			add.call(WARN, "gece: hedefleme podu / gece görüşü önerilir")
	var wp := weather_preset(c.get("weather", ""))
	if wp == Weather.Preset.STORM or wp == Weather.Preset.FOG:
		add.call(OK if e["radar"] or e["pod"] else WARN, "%s: %s" % [weather_name(wp).to_lower(), "radar/pod ile hedef bulunur" if e["radar"] or e["pod"] else "görüş kötü — radar ya da hedefleme podu önerilir"])
	if float(e["intake_pct"]) < 0.99:
		add.call(WARN, "hava alığı yetersiz (%%%d): motor tam güç veremez" % (float(e["intake_pct"]) * 100.0))
	var worst := OK
	for it: Array in items:
		worst = maxi(worst, int(it[0]))
	return {"items": items, "verdict": worst}
