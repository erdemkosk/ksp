class_name Ace
extends Node
## Düşman ası "Kara Doğan": siyah-kırmızı özel avcı (crafts/kara_dogan.json, KD-01), as beceri,
## telsizde kişilik. Görev kurulumunun sonunda MissionManager.setup → attach() çağrılır;
## ne yapacağına Campaign.ace_plan karar verir:
##   cameo  — Perde 1: oyuncu havalanınca filo arkadaşı Kartal-3 katılır, Kara Doğan gelir,
##            onu düşürür (gerekirse senaryo) ve çekip gider
##   hunt   — Perde 2: oyuncunun önüne çıkar; hasar alınca ("Bir dahaki sefere, pilot!") ya da
##            yakıtı bitince kaçar; düşürülürse paraşütle kurtulur, geri döner
##   voice  — Perde 3 sıradan görev: yalnız telsizde bir laf
##   finale — "Son Darbe": iki eskortla düşman karargâhı üzerinde; kaçmaz. Düşerse görev başarılı
## Karşılaşma sonu Campaign.note_encounter'a yazılır (gerçek kariyer uçuşu ya da --acetest).
## Test: `--mission=it --acemode=hunt --aiplayer --acetest` (bkz. --acetest çıktısı).

const NAME := "Kara Doğan"
const CALL := "KARA DOĞAN"
const CRAFT := "res://crafts/kara_dogan.json"
const ESCORT_CRAFT := "res://crafts/kartal_2s.json"
const MATE_CRAFT := "res://crafts/kartal_1.json"
const MATE_CALL := "KARTAL 3"
const HQ_CALL := "ŞAHİN GÖZÜ"
const SKILL := 0.95
## Bu sağlık oranının altına düşünce kaçar (final hariç)
const RETREAT_HP := 0.88
## Final: karargâh üzerindeki devriye noktası (yüzey xz) ve irtifası
const FINALE_XZ := Vector2(-24000, -12000)
const FINALE_ALT := 8500.0

const TAUNTS := {
	"hunt": ["Yine mi sen? Bakalım bu sefer hangarda ne pişirmişler.", "Uçağın ağır, Güneyli. Dönüşte bunu hissediyorum.",
		"Altıma gelmeye çalışma, oradan güneşi göremezsin.", "Kuyruğundayım. Hissediyor musun?"],
	"finale": ["Burası benim göğüm. Her bulutu tanırım.", "Eskortlarım düşerse ne olur? Hiç. Ben kalırım.",
		"Kaç uçak tasarladın beni yenmek için? Bir tane daha yap.", "Seni bekliyordum, Güneyli."],
	"cameo": ["Bir tane eksik olsun.", "Güneyliler… kanatları kâğıttan."],
	"voice": ["Seni radarımda görüyorum, Güneyli. Karargâhta bekliyorum.", "Bugün değil. Ama yakında, kendi göğümde.",
		"Kara Doğan dinliyor. Acele et, pilot; sabrım uzun değil."],
}

var mm: MissionManager
var main: Node
var mode := ""
var ship: Vessel
var ai: AIPilot
var friend: Vessel
var escorts: Array[Vessel] = []
## wait · fight · leave · gone
var phase := "wait"
var result := ""
## Karşılaşma Campaign'e yazılır mı (gerçek kariyer uçuşu ya da --acetest)
var real := false
var _t := 0.0
var _phase_t := 0.0
var _airborne := 0.0
var _hp0 := 0.0
var _said := {}
var _taunt_t := 35.0
var _recorded := false
var _friend_parts := 0
var _friend_down := false
var _log_t := 0.0


## Görev kurulumu sonunda çağrılır. Planı yoksa null.
static func attach(m: MissionManager) -> Ace:
	Campaign.flight_started()
	var id := String(m.def.get("id", ""))
	var plan := String(Game.args.get("acemode", "")) if Game.args.has("acemode") else Campaign.ace_plan(id)
	if id == Campaign.FINALE:
		plan = "finale"
	if plan == "" or not is_instance_valid(m.main.vessel):
		return null
	var a := Ace.new()
	a.name = "Ace"
	a.mm = m
	a.main = m.main
	a.mode = plan
	a.real = (not Career.sandbox() and not Game.test_flight) or Game.args.has("acetest")
	m.add_child(a)
	if plan == "finale":
		a._setup_finale()
	if Crew._testing():
		print("ACE attach mode=%s mission=%s real=%s" % [plan, id, a.real])
	return a


## Finale brifingi ve Perde 3 sayfası için istihbarat: uçağın gerçek değerlerinden.
static func intel_text() -> String:
	var craft := VesselBuilder.load_craft(CRAFT)
	var mass := 0.0
	var thrust := 0.0
	var ir := 0
	var rf := 0
	for e: Dictionary in craft.get("parts", []):
		var id := String(e.get("part", ""))
		var d := PartLibrary.get_def(id)
		var k := 2 if e.get("mirror", false) else 1
		mass += float(d.get("mass", 0.0)) * k
		for m: Dictionary in d.get("modules", []):
			if m.get("type", "") == "engine":
				thrust += float(m.get("max_thrust", 0.0)) * k
		if id == "missile_rail" or id == "wingtip_rail":
			ir += k
		elif id == "radar_missile_rail":
			rf += k
	return "Kara Doğan'ın uçağı KD-01: ikiz motor, afterburner ile ~%d kN itki, ~%.1f t boş. %.0f-%.0f km'de devriye uçar, dalışla saldırır. %d radar füzesi, %d IR füze, top, ECM, flare. İki eskortla karargâhı korur." % [
		int(thrust / 1000.0), mass / 1000.0, FINALE_ALT / 1000.0 - 1.0, FINALE_ALT / 1000.0 + 1.5, rf, ir]


# ------------------------------------------------------------------ doğurma

func _spawn(pos: Vector3, dir: Vector3, path: String, title: String, team: String, skill: float, paint := {}) -> Vessel:
	var up := (pos - Planet.center()).normalized()
	dir = (dir - up * dir.dot(up)).normalized()
	var craft := VesselBuilder.load_craft(path)
	if not paint.is_empty():
		craft["paint"] = paint
	var e := VesselBuilder.build(craft)
	e.name = title.validate_node_name()
	e.craft_name = title
	e.team = team
	e.transform = Transform3D(Basis.looking_at(dir, up), pos)
	e.linear_velocity = dir * 230.0
	main.world.add_child(e)
	e.set_gear_instant(false)
	e.set_hot()
	e.lights_on = true
	var p := AIPilot.new()
	p.vessel = e
	p.skill = skill
	p.aggressive = true
	p.altitude = (pos - Planet.center()).length() - Planet.RADIUS
	p.speed = 240.0
	p.leg_time = 50.0
	e.add_child(p)
	return e


func _spawn_ace(pos: Vector3, dir: Vector3) -> void:
	ship = _spawn(pos, dir, CRAFT, NAME, "düşman", SKILL)
	ai = AIPilot.of(ship)
	_hp0 = _hp_sum()
	phase = "fight"
	_phase_t = 0.0


func _setup_finale() -> void:
	mm.objectives = [mm._obj("Kara Doğan'ı düşür"), mm._obj("Eskortlar (0/2, isteğe bağlı)"), mm._obj("Hayatta kal")]
	var p := MissionManager.world_point(FINALE_XZ.x, FINALE_XZ.y, FINALE_ALT)
	var to_base := MissionManager.world_point(0, 0, FINALE_ALT) - p
	_spawn_ace(p, to_base)
	ai.altitude = FINALE_ALT
	mm._enemies.append(ship)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var ep := MissionManager.world_point(FINALE_XZ.x + side * 900.0, FINALE_XZ.y + 700.0, FINALE_ALT - 1200.0)
		var e := _spawn(ep, to_base, ESCORT_CRAFT, "Kara Doğan Eskort %d" % (i + 1), "düşman", 0.7, {"scheme": "gece", "number": "KD-%02d" % (i + 2)})
		if i == 0:
			AIPilot.pair(ship, e)
		escorts.append(e)
		mm._enemies.append(e)
	_say(TAUNTS["finale"][3])


# ------------------------------------------------------------------ akış

func _physics_process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	var v: Vessel = main.vessel
	if Game.args.has("acetest"):
		_test_log(delta, v)
	# görev bitti: karşılaşmayı o anki durumla yaz (rapor iniş sonrası açılır)
	if not _recorded and phase in ["fight", "leave"] and mm.state != "running":
		_record(_default_result())
	match phase:
		"wait":
			_wait(delta, v)
		"fight":
			_fight(delta, v)
		"leave":
			_leave(v)


func _wait(delta: float, v: Vessel) -> void:
	if not is_instance_valid(v) or mm.state != "running":
		if mm.state != "running":
			phase = "gone"
		return
	if v.radar_altitude() > 150.0 and v.airspeed() > 80.0:
		_airborne += delta
	var need := float(Game.args.get("acedelay", {"cameo": 35.0, "voice": 60.0}.get(mode, 60.0)))
	if _airborne < need:
		return
	var up := v.up()
	var fwd := v.forward()
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var me := v.com_global()
	match mode:
		"voice":
			_say(TAUNTS["voice"].pick_random())
			phase = "gone"
		"cameo":
			var fp := me - right * 2500.0 + up * 150.0
			friend = _spawn(fp, fwd, MATE_CRAFT, "Kartal-3", v.team, 0.3, {"scheme": "gri", "number": "03"})
			_friend_parts = friend.parts.size()
			_say("Kartal-3 katılıyor, solunda üç kilometrede. Bugün sakin görünüyor.", MATE_CALL)
			_spawn_ace(fp - fwd * 4500.0 + up * 900.0, fwd)
		_:
			var side := right * randf_range(-3000.0, 3000.0)
			var ap := me + fwd * 9000.0 + side + up * 1500.0
			_spawn_ace(ap, me - ap)
			_say(TAUNTS["hunt"][0])
			_say("Dikkat, kuzeyden hızlı bir temas! İmza… Kara Doğan!", HQ_CALL)


func _fight(delta: float, v: Vessel) -> void:
	if _dead(ship):
		_on_dead()
		return
	if not _player_ok(v):
		_once("gloat", "Söylemiştim, Güneyli. Kâğıttan kanatlar.")
		_taunt_t = 999.0
	_taunt_t -= delta
	if _taunt_t <= 0.0 and mode in ["hunt", "finale"]:
		_taunt_t = randf_range(35.0, 55.0)
		_say(TAUNTS[mode].pick_random())
	var hp := _hp_ratio()
	match mode:
		"cameo":
			if not _friend_down:
				if _phase_t > 8.0:
					_once("mate_six", "Arkamda biri var! Siyah bir uçak… çok hızlı!", MATE_CALL)
				if _dead(friend) or friend.parts.size() < _friend_parts * 0.75:
					_friend_down = true
					_phase_t = 0.0
					_say("Vuruldum! Vuruldum! Atlıyorum!", MATE_CALL)
					_say(TAUNTS["cameo"][0])
				elif _phase_t > 45.0 and is_instance_valid(friend):
					_script_kill_friend()
				if hp < 0.6:   # kameoda kolay kaçmaz: önce Kartal-3
					_retreat("Bir dahaki sefere, pilot!", "escaped_damaged")
			elif _phase_t > 5.0:
				_once("hq_cameo", "Kartal-3 düştü, paraşüt görüldü. O uçak… Kara Doğan'dı.", HQ_CALL)
				_retreat("Bugünlük bu kadar. Seninle sonra ilgileneceğim, Güneyli.", "cameo")
		"hunt":
			if hp < RETREAT_HP:
				_retreat("Bir dahaki sefere, pilot!", "escaped_damaged")
			elif _phase_t > float(Game.args.get("acefuel", "240")):
				_retreat("Yakıt… Şanslısın, Güneyli. Yine karşılaşacağız.", "escaped")
			elif not _player_ok(v):
				_retreat("Bugünlük yeter. Kuzeye dönüyorum.", "player_down")
		"finale":
			var dead := escorts.filter(func(e: Vessel) -> bool: return _dead(e)).size()
			mm.objectives[1]["text"] = "Eskortlar (%d/2, isteğe bağlı)" % dead
			mm.objectives[1]["done"] = dead >= 2
			if dead >= 2:
				_once("alone", "Yalnız kaldım, ha? Daha iyi. Kimse araya girmez.")
			if hp < 0.55:
				_once("hurt", "Bu… bu olamaz! Kimin tasarımı bu uçak?")
			if mm.state == "running":
				mm.nav_point = ship.com_global()
				mm.nav_label = "KARA DOĞAN"


func _leave(v: Vessel) -> void:
	if _dead(ship):
		_on_dead()
		return
	# 60 sn sonra kaçmış sayılır; gözden çıkınca (12 km) kaybolur
	if not _recorded and _phase_t > 60.0:
		_record(result)
	var far := not is_instance_valid(v) or ship.com_global().distance_to(v.com_global()) > 12000.0
	if far or _phase_t > 300.0:
		if not _recorded:
			_record(result)
		phase = "gone"
		if is_instance_valid(ship):
			ship.queue_free()


## Kaç: saldırganlığı bırak, oyuncudan uzağa yüksel ve hızlan.
func _retreat(line: String, res: String) -> void:
	if phase != "fight":
		return
	result = res
	phase = "leave"
	_phase_t = 0.0
	_say(line)
	if ai == null:
		return
	ai.aggressive = false
	ai.target = null
	ai.threat = null
	var v: Vessel = main.vessel
	var away := ship.com_global() - (v.com_global() if is_instance_valid(v) else ship.com_global() + ship.forward())
	var b := ship.local_frame()
	var hdg := fposmod(rad_to_deg(atan2(away.dot(b.x), -away.dot(b.z))), 360.0)
	ai.speed = 320.0
	ai.altitude = 9500.0
	ai.leg_time = 1.0e9
	ai._ap.target_heading = hdg
	ai._ap.target_altitude = 9500.0
	ai._ap.target_speed = 320.0
	ai.state = AIPilot.State.PATROL
	ai._t = 0.0


## Kameo güvencesi: as Kartal-3'ü kendisi düşüremediyse kanadı kopar (senaryo).
func _script_kill_friend() -> void:
	for p in friend.parts:
		for m in p.modules:
			if m is WingModule:
				friend.destroy_part(p)
				return


func _on_dead() -> void:
	if phase == "gone":
		return
	phase = "gone"
	if mode == "finale":
		_say("Kara Doğan düştü! Tekrar ediyorum, Kara Doğan düştü!", HQ_CALL)
		_record("defeated")
		if mm.state == "running":
			mm.objectives[0]["done"] = true
			mm.objectives[2]["done"] = true
			mm._finish(true, "")
	else:
		# kendi görev sayımında değil: düşürme oyuncuya yazılır
		Crew.add_kill()
		mm._message("KARA DOĞAN DÜŞTÜ!  +40 XP", 4.0)
		_say("Paraşüt! Kara Doğan atladı, düşman hattına süzülüyor.", HQ_CALL)
		_record("downed")


# ------------------------------------------------------------------ kayıt

func _default_result() -> String:
	if result != "":
		return result
	match mode:
		"cameo":
			return "cameo" if _friend_down else "cameo_missed"
		"finale":
			return "defeated" if _dead(ship) else "finale_lost"
	return "escaped"


const STORY := {
	"cameo": "Kara Doğan ilk kez göründü: Kartal-3'ü düşürüp kayboldu. Deniz Arslan paraşütle kurtuldu.",
	"cameo_missed": "Kuzeyden siyah bir uçak geldi, kısa bir dalaştan sonra çekildi: Kara Doğan.",
	"escaped_damaged": "Kara Doğan'ı vurdun; dumanlar içinde kuzeye kaçtı. 'Bir dahaki sefere, pilot!'",
	"escaped": "Kara Doğan dalaştan sıyrılıp kuzeye döndü. Hâlâ orada.",
	"player_down": "Kara Doğan bu turu aldı. Hangarda ona cevap gerek.",
	"downed": "Kara Doğan'ı düşürdün! Paraşütü düşman hattına süzüldü; geri döneceğine eminiz.",
	"defeated": "Kara Doğan düştü. Kuzeyin en iyi pilotu artık yok.",
	"finale_lost": "Kara Doğan bu sefer de ayakta. Karargâh yeni bir tasarım bekliyor.",
}


func _record(res: String) -> void:
	if _recorded:
		return
	_recorded = true
	result = res
	if Crew._testing():
		print("ACE ENCOUNTER mode=%s result=%s t=%.0f hp=%.2f" % [mode, res, _t, _hp_ratio() if is_instance_valid(ship) else 0.0])
	if real:
		Campaign.note_encounter(mode, res, String(mm.def.get("id", "")), String(STORY.get(res, STORY["escaped"])))


func _exit_tree() -> void:
	if not _recorded and phase in ["fight", "leave"]:
		_record(_default_result())


# ------------------------------------------------------------------ yardımcılar

func _dead(e: Variant) -> bool:
	return not is_instance_valid(e) or e.parts.is_empty() or e.cockpit() == null or not e.has_pilot()


func _player_ok(v: Variant) -> bool:
	return is_instance_valid(v) and v.cockpit() != null and (v.has_pilot() or is_instance_valid(main.pilot))


func _hp_sum() -> float:
	var s := 0.0
	if is_instance_valid(ship):
		for p in ship.parts:
			s += p.hp
	return s


func _hp_ratio() -> float:
	return clampf(_hp_sum() / maxf(_hp0, 1.0), 0.0, 1.0)


func _once(key: String, line: String, sender := CALL) -> void:
	if not _said.has(key):
		_said[key] = true
		_say(line, sender)


func _say(tr: String, sender := CALL) -> void:
	if Crew._testing():
		print("TELSİZ %s: %s" % [sender, tr])
	var r: Radio = main.radio
	if r and r.enabled and bool(Game.settings.get("radio", true)) and r._queue.size() < 4:
		r.say(tr, tr, sender)
	elif main.hud:
		main.hud.radio_message(sender, tr)


func _test_log(delta: float, v: Vessel) -> void:
	_log_t -= delta
	if _log_t > 0.0:
		return
	_log_t = 5.0
	if not is_instance_valid(ship) or ship.parts.is_empty():
		print("ACE t=%.0f phase=%s (gemi yok) result=%s mission=%s" % [_t, phase, result, mm.state])
		return
	var d := ship.com_global().distance_to(v.com_global()) if is_instance_valid(v) else -1.0
	print("ACE t=%.0f phase=%s state=%s hp=%.2f d=%.0f alt=%.0f v=%.0f fd=%s mission=%s" % [_t, phase,
		AIPilot.STATE_NAMES[ai.state] if ai else "-", _hp_ratio(), d, ship.altitude(), ship.airspeed(), _friend_down, mm.state])
	if _t > float(Game.args.get("acetime", "200")):
		print("ACE TEST END result=%s encounters=%s" % [result, Campaign.ace()["encounters"]])
		get_tree().quit()
