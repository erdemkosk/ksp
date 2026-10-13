class_name WingFlight
extends Node
## Oyuncunun kanat adamı uçuşu: kadrodan seçilen ikinci pilot (Crew.wingman) oyuncunun
## uçağının aynısıyla birlikte uçar. Pistte başlarsa arkada bekler, oyuncu kalkınca kalkar;
## havada başlarsa doğrudan kolda. Telsiz emirleri (F2 → Kanat adamı…) command() ile gelir.
## Düşürmeleri kendine yazılır (son 12 sn'de ateş ettiği / füzesinin izlediği hedef düşerse);
## görev sayımı take_kills() ile bunları oyuncuya yazmaz. Vurulursa fırlatma şansı, pilot
## yaralanabilir ya da kaybedilebilir; uçak kaybı kariyerde kasadan düşer (test uçuşunda yok).
## Uçuş kapanınca (close) tecrübe, düşürme ve durum pilota işlenir.

const CALL := "KANAT 2"
## Görev başarısı / sağ dönüş / düşürme başına XP
const XP_SUCCESS := 60
const XP_SURVIVE := 20
const XP_KILL := 40

static var active: WingFlight

var main: Node
var ship: Vessel
var ai: Wingman
var pilot_idx := -1
var pilot_name := ""
var kills := 0
## "" uçuyor · "üste" indi · "fırlattı" · "yaralı" · "kayıp"
var outcome := ""
var money_lost := 0

var _unclaimed := 0
var _engaged: Array = []        # [Vessel, son ateş zamanı]
var _t := 0.0
var _start_parts := 0
var _hit_cd := 0.0
var _bingo := false
var _winchester := false
var _lead_lost := false
var _closed := false
var _hud: Control
## Pistte beklerken kanat adamının altındaki arazi çarpışma yaması (oyuncununki onu izlemez)
var _ground: TerrainCollision


## Uçuş başında çağrılır: kanat adamı atanmışsa (ve uçak silahlıysa) doğurur.
## Testlerde kadro gerçek kayıttır: yalnız --wingman / --wingmantest ile.
static func setup(m: Node) -> void:
	active = null
	var v: Vessel = m.vessel
	if not is_instance_valid(v) or float(m._time) > 0.0:
		return   # kayıttan devam: kanat adamı yok
	var idx: int = Crew.wingman_index()
	if Crew._testing():
		if not (Game.args.has("wingman") or Game.args.has("wingmantest")):
			return
		if idx < 0:
			for i in Crew.pilots.size():
				if i != Crew.selected and Crew.can_fly(i):
					idx = i
					break
		if idx < 0:
			# testte kadroda ikinci pilot yoksa geçici bir pilot (kayıt testte yazılmaz)
			Crew.pilots.append(Crew._new_pilot(2))
			idx = Crew.pilots.size() - 1
	if Crew._testing():
		print("WingFlight.setup: idx=%d silah=%d pilot=%d" % [idx, v.weapons().size(), Crew.pilots.size()])
	if idx < 0 or v.weapons().is_empty():
		return
	var wf := WingFlight.new()
	wf.name = "WingFlight"
	wf.main = m
	wf.pilot_idx = idx
	m.add_child(wf)
	wf._spawn()


func _exit_tree() -> void:
	if active == self:
		active = null


func flying() -> bool:
	return outcome == "" and _ok(ship)


static func _ok(v: Variant) -> bool:
	return is_instance_valid(v) and not v.parts.is_empty() and v.cockpit() != null and v.has_pilot()


func _spawn() -> void:
	active = self
	var p: Dictionary = Crew.pilots[pilot_idx]
	pilot_name = String(p["name"])
	var lead: Vessel = main.vessel
	# seri üretimdeki filo tipi varsa onunla uçar (Designs), yoksa liderin uçağının kopyası
	var data: Dictionary = Designs.wing_craft(main.spawned_craft as Dictionary)
	if Designs.is_fleet(data):
		set_meta("design_key", Designs.key(data))
		set_meta("design_name", String(data.get("name", "")))
		set_meta("cost", Career.craft_cost(data))
	var paint: Dictionary = data.get("paint", {})
	paint["number"] = "2"
	data["paint"] = paint
	ship = VesselBuilder.build(data)
	ship.name = "Wingman"
	ship.craft_name = "Kanat 2"
	ship.team = lead.team
	for m in ship.modules:
		if m is CockpitModule:
			m.pilot_name = pilot_name
		elif m is GunModule:
			m.spread_deg *= 1.45 - 0.15 * int(p.get("nisan", 1))
	var b := lead.global_basis
	var grounded := lead.radar_altitude() < 10.0
	if grounded:
		# pistte sağ arkada bekle
		ship.transform = Transform3D(b, lead.global_position + b.x * 14.0 + b.z * 160.0)
	else:
		var up := Planet.up_at(lead.global_position)
		ship.transform = Transform3D(b, lead.global_position + b.x * Wingman.SLOT.x + b.z * Wingman.SLOT.z + up * Wingman.SLOT.y)
		ship.linear_velocity = lead.linear_velocity
	main.world.add_child(ship)
	ship.set_gear_instant(grounded)
	ship.set_hot()
	ship.parking_brake = grounded
	ship.lights_on = true
	ship.part_destroyed.connect(_on_part_lost)
	if grounded:
		_ground = TerrainCollision.new()
		_ground.name = "WingmanGround"
		_ground.target = ship
		main.terrain.add_child(_ground)
		_ground.rebuild_now(main.terrain.to_local(ship.global_position))
	_start_parts = ship.parts.size()
	ai = Wingman.new()
	ai.vessel = ship
	ai.lead = lead
	ai.skill = pilot_skill(p)
	ai.speed = 220.0
	ai.on_runway = grounded
	ship.add_child(ai)
	_hud = WingmanHud.new()
	_hud.flight = self
	main.hud.add_child(_hud)
	print("KANAT ADAMI: %s  beceri=%.2f  %s" % [pilot_name, ai.skill, "pistte" if grounded else "havada"])
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if flying():
			say("Lider, Kanat 2 hazır. %s" % ("Kalkışınızdan sonra kalkıyorum." if grounded else "Sağ kolundayım."),
				"Lead, Two is ready."))


## Kadro pilotundan yapay zeka becerisi (0.25..0.95): yetenek yıldızları ve seviye.
static func pilot_skill(p: Dictionary) -> float:
	var stars := int(p.get("ucus", 1)) + int(p.get("nisan", 1)) + int(p.get("dayanim", 1))
	return clampf(0.25 + float(stars - 3) / 12.0 * 0.55 + int(p.get("level", 1)) * 0.02, 0.25, 0.95)


## En yakın havaalanı (dünya noktası).
static func home_point(v: Vessel) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var xz: Vector2 = a["xz"]
		var p := MissionManager.world_point(xz.x, xz.y, float(a["elev"]))
		var d := p.distance_to(v.com_global())
		if d < best_d:
			best_d = d
			best = p
	return best


# ------------------------------------------------------------------ telsiz

func say(tr: String, en := "", sender := CALL) -> void:
	if Crew._testing():
		print("TELSİZ %s: %s" % [sender, tr])
	var r: Radio = main.radio
	if r and r.enabled and bool(Game.settings.get("radio", true)) and r._queue.size() < 4:
		r.say(tr, en if en != "" else tr, sender)
	elif main.hud:
		main.hud.radio_message(sender, tr)


## Telsiz emri (F2 → Kanat adamı…).
func command(o: Wingman.Order) -> void:
	if not flying():
		return
	var me: String = main.radio.callsign().to_upper() if main.radio else "LİDER"
	match o:
		Wingman.Order.ATTACK:
			say("Kanat 2, hedefime saldır.", "Two, engage my target.", me)
			var t := _lead_target()
			if t == null:
				say("Kanat 2: hedef göremiyorum, kolundayım.", "Two, no joy.")
				return
			ai.set_order(o, t)
			say("Kanat 2: anlaşıldı, %s saldırıyorum." % _bearing_text(t), "Two, engaging.")
		Wingman.Order.COVER:
			say("Kanat 2, beni koru.", "Two, cover me.", me)
			ai.set_order(o)
			say("Kanat 2: anlaşıldı, arkanı kolluyorum.", "Two, covering.")
		Wingman.Order.FREE:
			say("Kanat 2, dağıl, serbest avlan.", "Two, break, free hunt.", me)
			ai.set_order(o)
			say("Kanat 2: anlaşıldı, serbest avdayım.", "Two, hunting.")
		Wingman.Order.FORM:
			say("Kanat 2, kola dön.", "Two, rejoin.", me)
			ai.set_order(o)
			say("Kanat 2: anlaşıldı, kola dönüyorum.", "Two, rejoining.")
		Wingman.Order.RTB:
			say("Kanat 2, üsse dön.", "Two, return to base.", me)
			ai.set_order(o)
			say("Kanat 2: anlaşıldı, üsse dönüyorum. İyi avlar lider.", "Two, RTB.")


## Oyuncunun hedefi: seçili (designated), füze arayıcısının kilidi ya da burnunun önündeki düşman.
func _lead_target() -> Vessel:
	var v: Vessel = main.vessel
	if not is_instance_valid(v):
		return null
	if _enemy(v.designated):
		return v.designated
	for m in v.modules:
		if m is MissileModule and _enemy(m.target):
			return m.target
	var best: Vessel = null
	var best_a := deg_to_rad(20.0)
	for n in main.world.get_children():
		if _enemy(n):
			var to: Vector3 = n.com_global() - v.com_global()
			var a := v.forward().angle_to(to)
			if to.length() < 15000.0 and a < best_a:
				best_a = a
				best = n
	return best


func _enemy(n: Variant) -> bool:
	return n is Vessel and _ok(n) and n.team != ship.team and n.team != "sivil"


func _bearing_text(t: Vessel) -> String:
	var d := t.com_global().distance_to(ship.com_global())
	return "%d kilometredeki hedefe" % roundi(d / 1000.0) if d > 1500.0 else "hedefe"


# ------------------------------------------------------------------ uçuş takibi

func _physics_process(delta: float) -> void:
	_t += delta
	_hit_cd -= delta
	_update_ground()
	_track_kills()
	if outcome != "":
		return
	if not is_instance_valid(ship) or ship.parts.is_empty() or ship.cockpit() == null:
		_shot_down(true)
		return
	if not ship.has_pilot():
		return
	var lead: Vessel = main.vessel
	ai.lead = lead
	if not _ok(lead) and not _lead_lost and ai.order != Wingman.Order.RTB:
		_lead_lost = true
		ai.set_order(Wingman.Order.RTB)
		say("Lider düştü! Kanat 2 bölgeden çıkıyor, üsse dönüyorum.", "Lead is down, Two is RTB.")
	# ağır hasar: uçak uçamaz hale geldi → fırlat
	var crippled := ship.parts.size() < _start_parts * 0.65 \
		or (ship.parts.size() < _start_parts * 0.9 and ship.vertical_speed() < -70.0 and ship.radar_altitude() < 1200.0)
	if crippled and not ai.on_runway:
		_shot_down(false)
		return
	_check_fuel_ammo()
	if ai.order == Wingman.Order.RTB:
		var hd := ship.com_global().distance_to(home_point(ship))
		var far := _ok(lead) and ship.com_global().distance_to(lead.com_global()) > 20000.0
		if hd < 3000.0 or far or (_lead_lost and _t > 0.0 and hd < 6000.0):
			_landed()


func _check_fuel_ammo() -> void:
	var cap := ship.fuel_capacity()
	var f := ship.fuel_amount() / cap if cap > 0.0 else 1.0
	if f < 0.25 and not _bingo:
		_bingo = true
		say("Kanat 2: bingo yakıt, yüzde %d kaldı." % roundi(f * 100.0), "Two, bingo fuel.")
	if f < 0.12 and ai.order != Wingman.Order.RTB:
		ai.set_order(Wingman.Order.RTB)
		say("Kanat 2: yakıt kritik, üsse dönüyorum.", "Two, fuel critical, RTB.")
	if not _winchester and ship.gun_ammo() <= 0 and ship.missiles_left() + ship.radar_missiles_left() <= 0:
		_winchester = true
		if ai.order != Wingman.Order.RTB:
			ai.set_order(Wingman.Order.FORM)
		say("Kanat 2: mühimmat bitti, kolda kalıyorum.", "Two, winchester.")


func _on_part_lost(_p: Part) -> void:
	if outcome == "" and _hit_cd <= 0.0 and is_instance_valid(ship) and ship.has_pilot():
		_hit_cd = 12.0
		say("Kanat 2: vuruldum! Hasar var, devam ediyorum.", "Two, I'm hit!")


## Düşürme: son 12 sn'de topla ateş ettiği ya da füzesinin izlediği hedef düşerse.
func _track_kills() -> void:
	if is_instance_valid(ship) and is_instance_valid(ai):
		if ship.ctrl_fire and ship.selected_weapon == Vessel.WEAPON_GUN and _ok(ai.target):
			_mark(ai.target)
		for mi in Missile.active:
			if is_instance_valid(mi) and mi.shooter == ship and _ok(mi.victim):
				_mark(mi.victim)
	for i in range(_engaged.size() - 1, -1, -1):
		var e: Array = _engaged[i]
		if not _ok(e[0]):
			_engaged.remove_at(i)
			if _t - float(e[1]) < 12.0:
				kills += 1
				_unclaimed += 1
				print("KANAT ADAMI DÜŞÜRDÜ: toplam %d  t=%.0f" % [kills, _t])
				say("Kanat 2: düşürdüm! Bir düşman aşağıda.", "Two, splash one!")
				if ai and ai.order == Wingman.Order.ATTACK:
					ai.set_order(Wingman.Order.COVER)
		elif _t - float(e[1]) > 30.0:
			_engaged.remove_at(i)


func _mark(v: Vessel) -> void:
	for e: Array in _engaged:
		if e[0] == v:
			e[1] = _t
			return
	_engaged.append([v, _t])


## Görev / serbest uçuş sayımı: yeni düşürmelerden kaçı kanat adamının (oyuncuya yazılmaz).
static func take_kills(n: int) -> int:
	if active == null or not is_instance_valid(active):
		return 0
	active._track_kills()
	var k := mini(active._unclaimed, n)
	active._unclaimed -= k
	return k


## Vuruldu. destroyed: kokpit/uçak parçalandı (pilot büyük olasılıkla kayıp);
## değilse uçamaz hale geldi, fırlatma koltuğu.
func _shot_down(destroyed: bool) -> void:
	var can_eject := not destroyed and is_instance_valid(ship) and ship.cockpit() != null and ship.cockpit().can_eject()
	var survive := randf() < (0.92 if can_eject else 0.35)
	if Game.args.has("wingmantest") and Game.args.has("wingsurvive"):
		survive = true
	if can_eject:
		var c := ship.cockpit()
		c.occupied = false
		c.jettison_canopy()
		ship.ctrl_fire = false
	outcome = ("yaralı" if randf() < 0.35 else "fırlattı") if survive else "kayıp"
	print("KANAT ADAMI VURULDU: %s  (%s)" % [outcome, "parçalandı" if destroyed else "fırlatma"])
	if can_eject or survive:
		say("Kanat 2: vuruldum, kumanda yok! Fırlatıyorum!", "Two is hit, ejecting!")
		say("Kanat 2'nin paraşütü görüldü, kurtarma ekibi yolda.", "Chute observed, rescue en route.", "ŞAHİN GÖZÜ")
	else:
		say("Kanat 2 düştü! Paraşüt görülmedi.", "Two is down, no chute.", "ŞAHİN GÖZÜ")
	money_lost = Career.aircraft_lost(int(get_meta("cost", main.craft_cost))) if int(get_meta("cost", main.craft_cost)) > 0 else 0
	if money_lost > 0:
		main.hud.show_message("Kanat adamının uçağı kaybedildi: -%d ₺" % money_lost, 4.0)


## Üsse indi (benzetim): uçak sahneden kalkar, pilot sağ döner.
func _landed() -> void:
	outcome = "üste"
	print("KANAT ADAMI ÜSSE İNDİ t=%.0f" % _t)
	say("Kanat 2 üsse indi.", "Two is on deck.")
	if is_instance_valid(ship):
		ship.queue_free()


## Kalkış yaması: kalkışta yer çarpışması; kalkıştan sonra (ya da uçak gidince) kaldırılır.
func _update_ground() -> void:
	if _ground == null:
		return
	if not is_instance_valid(ship) or (not ai.on_runway and ship.radar_altitude() > 200.0):
		_ground.queue_free()
		_ground = null
		return
	_ground.reposition()


# ------------------------------------------------------------------ uçuş sonu (kadro)

## main.close_flight çağırır: yaralı pilotlar iyileşir, kanat adamının uçuşu işlenir.
static func on_close(m: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if Game.test_flight:
		if active and is_instance_valid(active):
			active._closed = true
			out.append("Kanat adamı: test uçuşu, işlenmedi.")
		return out
	var wf: WingFlight = active if active and is_instance_valid(active) and active.main == m else null
	# yaralılar her uçuşta iyileşir (2 uçuş sonra hazır)
	for i in Crew.pilots.size():
		var p: Dictionary = Crew.pilots[i]
		if p.get("status", "") == "yaralı" and not (wf and i == wf.pilot_idx):
			p["heal"] = int(p.get("heal", 1)) - 1
			if int(p["heal"]) <= 0:
				p["status"] = "hazır"
				p.erase("heal")
				out.append("%s iyileşti, uçuşa hazır." % p["name"])
	if wf and not wf._closed:
		wf._closed = true
		out.append_array(wf._close())
	Crew.save()
	return out


func _close() -> PackedStringArray:
	var out := PackedStringArray()
	if pilot_idx < 0 or pilot_idx >= Crew.pilots.size() or Crew.pilots[pilot_idx]["name"] != pilot_name:
		return out
	var p: Dictionary = Crew.pilots[pilot_idx]
	p["flights"] = int(p["flights"]) + 1
	p["kills"] = int(p["kills"]) + kills
	var killed := outcome == "kayıp"
	var xp := kills * XP_KILL
	if not killed:
		xp += XP_SURVIVE
	if main.mission and main.mission.state == "success" and not killed:
		xp += XP_SUCCESS
	var head := "Kanat 2 %s: %d düşürme" % [pilot_name, kills]
	match outcome:
		"kayıp":
			if Career.sandbox():
				out.append("%s — düştü (serbest mod: kadroya geri döner)." % head)
			else:
				p["status"] = "kayıp"
				out.append("%s — KAYIP." % head)
				var comp := Career.pilot_lost()
				if comp > 0:
					out.append("Pilot tazminatı: -%d ₺" % comp)
		"yaralı":
			if Career.sandbox():
				out.append("%s — fırlattı, hafif yaralı (serbest mod: hemen hazır)." % head)
			else:
				p["status"] = "yaralı"
				p["heal"] = 2
				out.append("%s — fırlattı, yaralı (2 uçuş dinlenecek)." % head)
		"fırlattı":
			out.append("%s — fırlattı, kurtarıldı." % head)
		_:
			out.append("%s — sağ döndü." % head)
	if money_lost > 0:
		out.append("Kanat adamının uçağı (bedeli): -%d ₺" % money_lost)
	if xp > 0 and not killed:
		p["xp"] = int(p["xp"]) + xp
		out.append("%s +%d XP" % [pilot_name, xp])
		while int(p["xp"]) >= Crew.xp_for(int(p["level"])) and int(p["level"]) < 10:
			p["level"] = int(p["level"]) + 1
			var best := "nisan" if kills > 0 else "ucus"
			if int(p[best]) >= 5:
				for k in Crew.SKILLS:
					if int(p[k]) < 5:
						best = k
						break
			p[best] = mini(int(p[best]) + 1, 5)
			out.append("%s SEVİYE %d!  %s +1" % [pilot_name, p["level"], Crew.SKILL_NAMES[best]])
	return out
