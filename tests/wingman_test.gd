extends Node
## Kanat adamı testi: oyuncu + kanat adamı (WingFlight) havada, önümüze düşman çifti konur.
## Oyuncu uçağını yapay zeka uçurur (--passiveplayer: saldırmaz). Zaman çizelgesinde telsiz
## emirleri verilir (KORU → SALDIR → SERBEST → KOL → ÜS); her 2 sn kanat adamının durumu.
## --runway: pistte başla; test oyuncuyu kaldırır, kanat adamının kalkışı izlenir (düşman yok).
## --noenemy: düşman yok (kol uçuşu / ekran görüntüsü). --noorders: emir verme (KORU kalır).
## --passiveenemy / --passiveplayer: saldırmaz. --wingmenu: telsiz alt menüsü açık. --duration=sn
## godot -- --wingmantest --air --pair --alt=2500 [--enemy_skill=acemi] [--duration=150]

var main: Node
var _t := 0.0
var _next := 0.0
var _ai: AIPilot
var _wf: WingFlight
var _orders := []
var _runway := false
var _end := 150.0


func _ready() -> void:
	_runway = Game.args.has("runway")
	_end = float(Game.args.get("duration", "40" if _runway else "150"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_wf = WingFlight.active
	if _wf == null:
		print("WINGMANTEST: kanat adamı doğmadı!")
		get_tree().quit(1)
		return
	var v: Vessel = main.vessel
	main.player.enabled = false
	if _runway:
		v.set_hot()
		return
	if not Game.args.has("noenemy"):
		main.spawn_enemy(true)
		var e: Vessel = main.enemy
		var w: Vessel = main.enemy_wing
		var b := v.global_basis.rotated(v.up(), PI)
		var pos := v.global_position + v.forward() * 7000.0 + v.up() * 200.0
		e.global_transform = Transform3D(b, pos)
		e.linear_velocity = -b.z * 200.0
		if is_instance_valid(w):
			w.global_transform = Transform3D(b, pos + b.x * 350.0 + b.z * 150.0 + v.up() * 40.0)
			w.linear_velocity = -b.z * 200.0
		for x: Vessel in [e, w]:
			if is_instance_valid(x):
				x.reset_physics_interpolation()
				if Game.args.has("passiveenemy"):
					AIPilot.of(x).aggressive = false
	_ai = AIPilot.new()
	_ai.vessel = v
	_ai.skill = 0.6
	_ai.aggressive = not Game.args.has("passiveplayer")
	v.add_child(_ai)
	v.master_arm = true
	if Game.args.has("noorders"):
		return
	_orders = [[25.0, Wingman.Order.ATTACK], [60.0, Wingman.Order.FREE], [95.0, Wingman.Order.FORM], [120.0, Wingman.Order.RTB]]


func _physics_process(delta: float) -> void:
	if _wf == null:
		return
	_t += delta
	var v: Vessel = main.vessel
	if _runway and is_instance_valid(v):
		_fly_takeoff(v)
	while not _orders.is_empty() and _t >= float(_orders[0][0]):
		var o: int = _orders.pop_front()[1]
		if o == Wingman.Order.ATTACK:
			# oyuncunun seçtiği hedef: en yakın düşman
			v.designated = _nearest_enemy(v)
		print("t=%.0f EMİR: %s" % [_t, Wingman.ORDER_NAMES[o]])
		_wf.command(o)
	if Game.args.has("wingmenu") and _t > 3.0:
		main.action_bar.radio_mode = true
		main.action_bar.wing_mode = true
	if _t >= _next:
		_next += 2.0
		_log(v)
	if _t >= _end:
		print("WINGMANTEST BİTTİ: kanat=%s düşürme=%d  oyuncu=%s  görev düşürme=%s" % [
			_wf.outcome if _wf.outcome != "" else "uçuyor", _wf.kills,
			"sağ" if is_instance_valid(v) and v.has_pilot() and not v.parts.is_empty() else "düştü",
			str(main.mission.kills) if main.mission else "-"])
		for line in WingFlight.on_close(main):
			print("KADRO(K2): ", line)
		get_tree().quit()


func _nearest_enemy(v: Vessel) -> Vessel:
	var best: Vessel = null
	var bd := INF
	for n in main.world.get_children():
		if n is Vessel and n.team == "düşman" and not n.parts.is_empty() and n.has_pilot():
			var d: float = n.com_global().distance_to(v.com_global())
			if d < bd:
				bd = d
				best = n
	return best


func _log(v: Vessel) -> void:
	var w := _wf.ship
	if not is_instance_valid(w) or not is_instance_valid(_wf.ai):
		print("t=%3.0f K2 %s" % [_t, _wf.outcome])
		return
	var ai := _wf.ai
	var d := w.com_global().distance_to(v.com_global()) if is_instance_valid(v) else -1.0
	var tgt := "-"
	if is_instance_valid(ai.target):
		tgt = "%s %.1fkm" % [ai.target.name, ai.target.com_global().distance_to(w.com_global()) / 1000.0]
	var en := 0
	for n in main.world.get_children():
		if n is Vessel and n.team == "düşman" and not n.parts.is_empty() and n.has_pilot():
			en += 1
	print("t=%3.0f K2 emir=%s durum=%s lider=%dm hız=%d irt=%d yakıt=%d%% hedef=%s düşürme=%d düşman=%d top=%.1fs füze=%d  | %s" % [
		_t, Wingman.ORDER_NAMES[ai.order], "KALKIŞ" if ai.on_runway else AIPilot.STATE_NAMES[ai.state], d,
		w.airspeed() * 3.6, w.radar_altitude(), w.fuel_amount() / maxf(w.fuel_capacity(), 1.0) * 100.0,
		tgt, _wf.kills, en, ai.gun_time, w.missiles_left() + w.radar_missiles_left(), ai.dbg])


## Oyuncu uçağının kalkışı (autotest gibi), sonra kuzeye düz tırmanış.
func _fly_takeoff(v: Vessel) -> void:
	var w := v.local_angular_velocity()
	var alt := v.radar_altitude()
	v.parking_brake = false
	v.ctrl_throttle = 0.85
	var tp := 10.0 if v.airspeed() > 75.0 else 0.0
	if alt > 900.0:
		tp = 2.0
	if alt > 60.0:
		v.gear_down = false
	v.ctrl_pitch = clampf((tp - v.pitch_deg()) * 0.08 - w.x * 1.5, -1.0, 1.0)
	v.ctrl_roll = clampf(-v.roll_deg() * 0.04 + w.z * 1.0, -1.0, 1.0)
	var herr := wrapf(0.0 - v.heading_deg(), -180.0, 180.0)
	v.ctrl_yaw = clampf(herr * 0.1, -1.0, 1.0) if alt < 3.5 else clampf(w.y * 2.0, -1.0, 1.0)
