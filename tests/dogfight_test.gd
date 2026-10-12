extends Node
## İt dalaşı testi: oyuncu uçağını da yapay zekaya verir, düşmanla kafa kafaya başlatır.
## Her saniye durum, mesafe, füze/flare sayıları; kim kazandı yazdırır.

var main: Node
var _t := 0.0
var _next := 0.0
var _ai: AIPilot
var _min_off := 999.0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v: Vessel = main.vessel
	var e: Vessel = main.enemy
	# düşmanı 4 km önümüze, bize doğru koy
	var pos := v.global_position + v.forward() * 4000.0 + v.up() * 200.0
	e.global_transform = Transform3D(v.global_basis.rotated(v.up(), PI), pos)
	e.linear_velocity = -v.linear_velocity
	e.reset_physics_interpolation()
	_ai = AIPilot.new()
	if Game.args.has("dumb"):
		_ai.aggressive = false   # bizimki sadece devriye uçar (düz hedef), yine de füzeden kaçar
	_ai.vessel = v
	_ai.skill = float(Game.args.get("skill", "0.6"))
	v.add_child(_ai)
	v.master_arm = true
	for x: Vessel in [v, e]:
		x.part_destroyed.connect(func(p: Part) -> void: print("  %s: %s koptu (t=%.1f)" % [x.craft_name, p.title, _t]))


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	var e: Vessel = main.enemy
	if _ai == null:
		return
	if is_instance_valid(e):
		_min_off = minf(_min_off, rad_to_deg(v.forward().angle_to(e.com_global() - v.com_global())))
	if _t >= _next:
		_next += 1.0
		var d := v.com_global().distance_to(e.com_global()) if is_instance_valid(e) else -1.0
		var eai: AIPilot = null
		if is_instance_valid(e):
			for c in e.get_children():
				if c is AIPilot:
					eai = c
		print("t=%3d d=%5.0f | biz %s irt=%4d hız=%3d G=%+4.1f füze=%d flare=%d mermi=%d parça=%d | düşman %s irt=%4d füze=%d flare=%d mermi=%d parça=%d | uçuşta füze=%d minaçı=%.1f isabet=%d %s" % [
			_t, d, AIPilot.STATE_NAMES[_ai.state], v.altitude(), v.airspeed(), v.g_force, v.missiles_left(), v.flares_left(), v.gun_ammo(), v.parts.size(),
			AIPilot.STATE_NAMES[eai.state] if eai else "-", e.altitude() if is_instance_valid(e) else 0, e.missiles_left() if is_instance_valid(e) else 0,
			e.flares_left() if is_instance_valid(e) else 0, e.gun_ammo() if is_instance_valid(e) else 0, e.parts.size() if is_instance_valid(e) else 0, Missile.active.size(), _min_off, Damage.vessel_hits, eai.dbg if eai else ""])
		_min_off = 999.0
	var dead_e := not is_instance_valid(e) or e.cockpit() == null or not e.has_pilot()
	var dead_v := v.cockpit() == null or not v.has_pilot()
	if dead_e or dead_v or _t > float(Game.args.get("duration", "120")):
		print("İT DALAŞI BİTTİ t=%.1f  sonuç: %s" % [_t, "BERABERE" if dead_e == dead_v else ("BİZ KAZANDIK" if dead_e else "DÜŞMAN KAZANDI")])
		get_tree().quit()
