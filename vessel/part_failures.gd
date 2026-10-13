class_name PartFailures
extends Node
## Prototip parça arızaları (oyuncu uçağı). Designs.reliability düştükçe olasılık artar.
## Adil olsun diye: seyrek (uçuş başına en çok MAX_EVENTS sürekli arıza, aralarında COOLDOWN),
## kalkıştan ve alçak irtifadan sonra, her zaman uyarı + telsizle duyurulur, çoğu toparlanır:
##   motor   — söner (rüzgârla yeniden ateşleme / I ile marş) ya da geçici güç kaybı
##   takım   — açılmaz; G ile toplayıp yeniden açınca kurtulur (3. denemede acil açma)
##   füze    — ateşlenmez (hang-fire), sonraki basışta çalışır
##   radar   — 10-20 sn yayın kesilir, kendini yeniden başlatır
##   pod     — donar (kilit kopar), 12-20 sn sonra yeniden başlar
## Gemi modüllerinden SONRA işler (process_physics_priority): füzenin bu basışını iptal edebilmek,
## takımın açılmasını geri alabilmek için.

const MAX_EVENTS := 2
const COOLDOWN := 150.0
const GRACE := 45.0             ## doğduktan sonra ilk arızaya kadar en az (sn)
const RATE_PER_HOUR := 2.5      ## (1 - güvenilirlik) başına saatlik sürekli arıza olasılığı
const GEAR_CHANCE := 0.35       ## (1 - güvenilirlik) × bu: takım açarken sıkışma
const MISFIRE_CHANCE := 0.3     ## (1 - güvenilirlik) × bu: füze basışında hang-fire

var vessel: Vessel
var main: Node
var rate_mul := 1.0
var log_print := false

var _t := 0.0
var _cool := 0.0
var _events := 0
var _tick := 0.0
var _protos := {}               ## Part -> güvenilirlik
## etkin arızalar
var _engine_out := {}           ## EngineModule -> {t, relit}
var _power_loss := {}           ## EngineModule -> {t, limit}
var _radar_t := 0.0
var _pod_t := 0.0
var _pod_az := 0.0
var _pod_el := 0.0
var _gear_jam := {}             ## LandingGearModule -> sıkışma konumu
var _gear_tries := 0
var _gear_jams := 0
var _last_gear := true
var _mis_rolled := false
var _mis_pending := false
var _mis_kind := -1
var _mis_count := 0
var _fire_prev := false


## Oyuncu uçağına bağla (prototip parça yoksa bağlanmaz). --prototest: uçaktaki motor, takım,
## füze, radar ve pod parçaları düşük güvenilirlikli prototip sayılır, arıza hızı artar.
static func attach(v: Vessel, m: Node) -> PartFailures:
	if not is_instance_valid(v):
		return null
	var test := Game.args.has("prototest")
	if test:
		for p in v.parts:
			if _kind(p) != "" and String(Game.args.get("protoonly", _kind(p))) == _kind(p):
				Career.designs_data.get_or_add("rel", {})[p.part_id] = {"h": 0.0, "m": 0.0}
	var protos := {}
	for p in v.parts:
		if _kind(p) != "":
			var r := Designs.reliability(p.part_id)
			if r < Designs.MATURE:
				protos[p] = r
	if protos.is_empty():
		return null
	var f := PartFailures.new()
	f.name = "PartFailures"
	f.vessel = v
	f.main = m
	f._protos = protos
	f._last_gear = v.gear_down
	if test:
		f.rate_mul = float(Game.args.get("protorate", 40.0))
		f.log_print = true
	f.process_physics_priority = 50
	v.add_child(f)
	if f.log_print:
		var names := PackedStringArray()
		for p: Part in protos:
			names.append("%s %%%d" % [p.part_id, roundi(protos[p] * 100.0)])
		print("PROTO: prototip parçalar: ", ", ".join(names))
	return f


## Arızası takip edilen modül türü (yoksa boş).
static func _kind(p: Part) -> String:
	for mod in p.modules:
		if mod is EngineModule:
			return "engine"
		if mod is LandingGearModule:
			return "gear"
		if mod is MissileModule:
			return "missile"
		if mod is RadarModule:
			return "radar"
		if mod is TargetingPodModule:
			return "pod"
	return ""


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel) or vessel.parts.is_empty() or not vessel.has_pilot():
		return
	_t += delta
	_cool = maxf(_cool - delta, 0.0)
	_update_active(delta)
	_check_gear()
	_check_missile()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if _events >= MAX_EVENTS or _cool > 0.0 or _t < GRACE or vessel.radar_altitude() < 150.0:
		return
	for p: Part in _protos.keys():
		if not is_instance_valid(p) or not p in vessel.parts:
			_protos.erase(p)
			continue
		var k := _kind(p)
		if k == "gear" or k == "missile":
			continue   # olay anında zarlanır
		var chance := (1.0 - float(_protos[p])) * RATE_PER_HOUR / 3600.0 * rate_mul
		if randf() < chance:
			_fail(p, k)
			return


func _fail(p: Part, k: String) -> void:
	var r: float = _protos[p]
	match k:
		"engine":
			var e := _module(p, EngineModule) as EngineModule
			if e == null or not e.is_running() or _engine_out.has(e) or _power_loss.has(e):
				return
			if randf() < lerpf(0.7, 0.3, (r - Designs.PROTO_START) / (Designs.MATURE - Designs.PROTO_START)):
				e.shutdown()
				_engine_out[e] = {"t": 0.0}
				vessel.failures["eng%d" % p.get_instance_id()] = "MOTOR SÖNDÜ (prototip) — yeniden ateşleme"
				_announce("MOTOR ARIZASI! %s söndü — hızı koru, yeniden ateşlenecek (I: marş)" % p.title,
					"Motor arızası! Motor söndü, yeniden ateşlemeyi deniyorum.", "Engine failure! Flameout, attempting relight.")
			else:
				_power_loss[e] = {"t": randf_range(25.0, 50.0), "limit": e.thrust_limit}
				e.thrust_limit *= 0.55
				vessel.failures["eng%d" % p.get_instance_id()] = "MOTOR GÜÇ KAYBI %55 (prototip)"
				_announce("MOTOR ARIZASI! %s güç kaybediyor (%%55)" % p.title,
					"Motor arızası! Güç kaybı var.", "Engine trouble, losing power.")
		"radar":
			if not vessel.radar_on:
				return
			_radar_t = randf_range(10.0, 20.0)
			vessel.radar_on = false
			vessel.failures["proto_radar"] = "RADAR ARIZASI — yeniden başlatılıyor"
			_announce("RADAR ARIZASI — radar kendini yeniden başlatıyor", "Radar arızası, yeniden başlatıyorum.", "Radar failure, rebooting.")
		"pod":
			var pod := _module(p, TargetingPodModule) as TargetingPodModule
			if pod == null:
				return
			_pod_t = randf_range(12.0, 20.0)
			_pod_az = pod.az
			_pod_el = pod.el
			pod.tracking = false
			pod.track_node = null
			vessel.failures["proto_pod"] = "POD DONDU — yeniden başlatılıyor"
			_announce("HEDEFLEME PODU DONDU — kilit koptu, pod yeniden başlıyor", "Pod dondu, yeniden başlatıyorum.", "Pod frozen, rebooting.")
		_:
			return
	_count(p)


## Bir prototip arızası sayıldı (rapor ve olgunlaşma verisi).
func _count(p: Part) -> void:
	_events += 1
	_cool = COOLDOWN
	Designs.flight_failures[p.part_id] = int(Designs.flight_failures.get(p.part_id, 0)) + 1


func _update_active(delta: float) -> void:
	for e: EngineModule in _engine_out.keys():
		if not is_instance_valid(e) or not is_instance_valid(e.part):
			_engine_out.erase(e)
			continue
		var s: Dictionary = _engine_out[e]
		s["t"] = float(s["t"]) + delta
		var key := "eng%d" % e.part.get_instance_id()
		if e.is_running():
			_engine_out.erase(e)
			vessel.failures.erase(key)
			_announce("Motor yeniden çalıştı", "Motor yeniden çalıştı.", "Engine relit.", false)
		elif e.state == EngineModule.State.OFF and float(s["t"]) > 9.0 and vessel.airspeed() > 90.0 and e.n2 >= 0.13 and vessel.fuel_amount() > 0.0:
			e.state = EngineModule.State.CRANKING   # rüzgârla dönen çekirdek: JFS'siz yeniden ateşleme
			vessel.system_message.emit("Yeniden ateşleme…")
		elif e.state == EngineModule.State.OFF and e.n2 < 0.13 and not s.has("told"):
			s["told"] = true
			vessel.system_message.emit("Devir düştü — I ile marş et (batarya + JFS)")
	for e: EngineModule in _power_loss.keys():
		if not is_instance_valid(e) or not is_instance_valid(e.part):
			_power_loss.erase(e)
			continue
		var s: Dictionary = _power_loss[e]
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			e.thrust_limit = float(s["limit"])
			_power_loss.erase(e)
			vessel.failures.erase("eng%d" % e.part.get_instance_id())
			_announce("Motor gücü normale döndü", "Motor gücü normal.", "Engine power restored.", false)
	if _radar_t > 0.0:
		_radar_t -= delta
		vessel.radar_on = false
		if _radar_t <= 0.0:
			vessel.radar_on = true
			vessel.failures.erase("proto_radar")
			_announce("Radar yeniden çalışıyor", "Radar geri geldi.", "Radar back online.", false)
	if _pod_t > 0.0:
		_pod_t -= delta
		var pod: TargetingPodModule = null
		for m in vessel.modules:
			if m is TargetingPodModule:
				pod = m
		if pod:
			pod.az = _pod_az
			pod.el = _pod_el
			pod.tracking = false
			pod.track_node = null
		if _pod_t <= 0.0:
			vessel.failures.erase("proto_pod")
			_announce("Pod yeniden çalışıyor", "Pod geri geldi.", "Pod back online.", false)
	for g: LandingGearModule in _gear_jam.keys():
		if not is_instance_valid(g):
			_gear_jam.erase(g)
			continue
		if vessel.gear_down:
			g.deploy = minf(g.deploy, float(_gear_jam[g]))   # açılamıyor


## Takım açma komutu: prototip takım sıkışabilir; toplayıp yeniden açmak kurtarır.
func _check_gear() -> void:
	var down := vessel.gear_down
	if down == _last_gear:
		return
	_last_gear = down
	if not down:
		return
	if not _gear_jam.is_empty():
		_gear_tries += 1
		if _gear_tries >= 3 or randf() < 0.6:
			_gear_jam.clear()
			vessel.failures.erase("proto_gear")
			_announce("Takım açıldı%s" % (" (acil açma)" if _gear_tries >= 3 else ""), "Takım açıldı, üç yeşil.", "Gear down, three green.", false)
		else:
			_announce("TAKIM HÂLÂ SIKIŞIK — topla (G) ve yeniden dene", "Takım hâlâ sıkışık.", "Gear still stuck.", false)
		return
	if _t < 5.0 or (_gear_jams >= 1 and not log_print):
		return   # uçuş başına bir sıkışma (adil)
	for p: Part in _protos:
		if not is_instance_valid(p) or _kind(p) != "gear":
			continue
		if randf() < (1.0 - float(_protos[p])) * GEAR_CHANCE * minf(rate_mul, 3.0):
			for m in p.modules:
				if m is LandingGearModule:
					_gear_jam[m] = minf(m.deploy, 0.4)
	if not _gear_jam.is_empty():
		_gear_tries = 0
		_gear_jams += 1
		vessel.failures["proto_gear"] = "TAKIM AÇILMADI — G ile topla, yeniden aç"
		_announce("TAKIM ARIZASI! İniş takımı açılmadı — G ile toplayıp yeniden aç",
			"Takım arızası! Takım açılmadı.", "Gear malfunction! Gear won't extend.")
		for m in _gear_jam:
			_count((m as LandingGearModule).part)
			break


## Füze basışı: prototip rayda hang-fire. Zar basıştan önce atılır; modül bu kare
## _fired_this_press'i sıfırladıktan sonra yeniden kurulur, basış boşa gider.
func _check_missile() -> void:
	var first: MissileModule = null
	for m in vessel.modules:
		if m is MissileModule and m.loaded and m.weapon_kind() == vessel.selected_weapon:
			first = m
			break
	var edge := vessel.ctrl_fire and not _fire_prev
	_fire_prev = vessel.ctrl_fire
	if not vessel.ctrl_fire:
		if first == null or not vessel.master_arm:
			_mis_rolled = false
			_mis_pending = false
			return
		if not _mis_rolled or _mis_kind != vessel.selected_weapon:
			_mis_rolled = true
			_mis_kind = vessel.selected_weapon
			_mis_pending = false
			if _protos.has(first.part) and _mis_count < 3 and _t > 5.0:
				_mis_pending = randf() < (1.0 - float(_protos[first.part])) * MISFIRE_CHANCE * minf(rate_mul, 6.0)
		if _mis_pending:
			for m in vessel.modules:
				if m is MissileModule and m.guidance == first.guidance:
					m._fired_this_press = true
		return
	# tetik basılı (yalnız basış anında)
	if not edge:
		return
	if _mis_pending and first != null:
		var why: String = first._blocked()
		if why != "":
			vessel.system_message.emit(why)   # zaten atılamazdı: arıza sayılmaz, beklemede kalır
			return
		_mis_pending = false
		_mis_count += 1
		for m in vessel.modules:
			if m is MissileModule and m.guidance == first.guidance:
				m._fired_this_press = true   # kumanda modüllerden sonra işlediyse de basış boşa gitsin
		Designs.flight_failures[first.part.part_id] = int(Designs.flight_failures.get(first.part.part_id, 0)) + 1
		Sfx.play_ui("switch_2.ogg", -6.0, 0.5)
		_announce("FÜZE ATEŞLENMEDİ (prototip ray, hang-fire) — tekrar bas", "Füze ateşlenmedi!", "Hang fire!")
	_mis_rolled = false


func _module(p: Part, type: Script) -> PartModule:
	for m in p.modules:
		if is_instance_of(m, type):
			return m
	return null


## Uyarı (HUD) + telsiz. warn: uyarı sesi.
func _announce(hud_text: String, tr: String, en: String, warn := true) -> void:
	vessel.system_message.emit(hud_text)
	if warn:
		Sfx.play_ui("switch_2.ogg", -4.0, 0.7)
	var radio: Variant = main.get("radio") if is_instance_valid(main) else null
	if radio and radio.enabled:
		radio.say(tr, en, radio.callsign().to_upper())
	elif is_instance_valid(main) and main.get("hud"):
		main.hud.radio_message("PİLOT", tr)
	if log_print:
		print("PROTO t=%.0f %s" % [_t, hud_text])
