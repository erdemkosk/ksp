extends Node
## Kanat çifti testi: oyuncu uçağı yapay zekaya verilir, 5 km önüne düşman çifti (lider +
## kanat adamı) bize doğru konur. Her saniye üç uçağın durumu/manevrası; sonunda durum süreleri,
## en düşük yer yüksekliği, atılan füze/flare, kim düştü (yere çakılma ayrı sayılır).
## godot -- --wingtest --aiplayer [--dumb] [--skill=0.6] [--enemy_skill=as] [--duration=90] [--alt=2500]
## (--aiplayer serbest uçuşta etkisizdir; kayıtları koruyan test bayrağı olarak gerekir)

var main: Node
var _t := 0.0
var _next := 0.0
var _ai: AIPilot
var _ships: Array[Vessel] = []
var _names := ["BİZ", "LİDER", "KANAT"]
var _min_agl := [INF, INF, INF]
var _state_time := [{}, {}, {}]
var _start_msl := [0, 0, 0]
var _start_flr := [0, 0, 0]
var _dead := ["", "", ""]


func _ready() -> void:
	if not Crew._testing():
		push_error("wingtest: --aiplayer ile çalıştır (kayıtlar korunmalı)")
		get_tree().quit()
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v: Vessel = main.vessel
	var e: Vessel = main.enemy
	var w: Vessel = main.enemy_wing
	# çifti 5 km önümüze, bize doğru koy; kanat adamı liderin sağ arkasında
	var b := v.global_basis.rotated(v.up(), PI)
	var pos := v.global_position + v.forward() * 5000.0 + v.up() * 200.0
	e.global_transform = Transform3D(b, pos)
	w.global_transform = Transform3D(b, pos + b.x * 350.0 + b.z * 150.0 + v.up() * 40.0)
	for x: Vessel in [e, w]:
		AIPilot.of(x).aggressive = not Game.args.has("passive")
		x.linear_velocity = -b.z * 200.0
		x.reset_physics_interpolation()
	_ai = AIPilot.new()
	_ai.aggressive = not Game.args.has("dumb")
	_ai.vessel = v
	_ai.skill = AIPilot.level(String(Game.args.get("skill", "0.6")))
	v.add_child(_ai)
	v.master_arm = true
	_ships = [v, e, w]
	for i in 3:
		_start_msl[i] = _ships[i].missiles_left() + _ships[i].radar_missiles_left()
		_start_flr[i] = _ships[i].flares_left()
	# --solo: kanat adamı yok (bire bir)
	if Game.args.has("solo"):
		_dead[2] = "yok"
		w.queue_free()


func _alive(x: Variant) -> bool:
	return is_instance_valid(x) and not x.parts.is_empty() and x.cockpit() != null and x.has_pilot()


func _physics_process(delta: float) -> void:
	if _ai == null:
		return
	_t += delta
	for i in 3:
		var x: Variant = _ships[i]
		if _dead[i] != "":
			continue
		if _alive(x) and x.radar_altitude() < -5.0:
			_dead[i] = "ARAZİYE GİRDİ"
			print("  %s araziye girdi t=%.1f (parça=%d)" % [_names[i], _t, x.parts.size()])
			continue
		if not _alive(x):
			var agl := x.radar_altitude() if is_instance_valid(x) else -1.0
			# ağır hasarlıyken (parça kaybı) yere düştüyse vurulmuş say; sağlamken çakıldıysa pilot hatası
			var crashed := agl < 40.0 and agl > -1.0 and x.parts.size() >= 18
			_dead[i] = "YERE ÇAKILDI (sağlam!)" if crashed else "VURULDU"
			print("  %s düştü t=%.1f (%s, yer=%.0f)" % [_names[i], _t, _dead[i], agl])
			continue
		_min_agl[i] = minf(_min_agl[i], x.radar_altitude())
		var ai := AIPilot.of(x)
		if ai:
			var sn: String = AIPilot.STATE_NAMES[ai.state]
			_state_time[i][sn] = float(_state_time[i].get(sn, 0.0)) + delta
	if _t >= _next:
		_next += 1.0
		var line := "t=%3d" % _t
		for i in 3:
			var x: Variant = _ships[i]
			var ai := AIPilot.of(x)
			if _dead[i] != "" or ai == null:
				line += " | %s -" % _names[i]
				continue
			var d := x.com_global().distance_to(_ships[0].com_global()) if i > 0 and _alive(_ships[0]) else 0.0
			line += " | %s %s yer=%d hız=%d G=%+.1f d=%d p=%d [%s]" % [_names[i], AIPilot.STATE_NAMES[ai.state], x.radar_altitude(), x.airspeed(), x.g_force, d, x.parts.size(), ai.dbg]
		print(line)
	var all_enemy_dead: bool = _dead[1] != "" and _dead[2] != ""
	if _dead[0] != "" or all_enemy_dead or _t > float(Game.args.get("duration", "90")):
		print("KANAT TESTİ BİTTİ t=%.1f" % _t)
		for i in 3:
			var x: Variant = _ships[i]
			var msl := 0
			var flr := 0
			if is_instance_valid(x):
				msl = _start_msl[i] - x.missiles_left() - x.radar_missiles_left()
				flr = _start_flr[i] - x.flares_left()
			var gt := AIPilot.of(x).gun_time if is_instance_valid(x) and AIPilot.of(x) else 0.0
			print("  %s: %s  en düşük yer=%.0f m  füze=%d flare=%d top=%.1fs  durumlar=%s" % [_names[i], _dead[i] if _dead[i] != "" else "sağ", _min_agl[i], msl, flr, gt, _state_time[i]])
		get_tree().quit()
