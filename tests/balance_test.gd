extends Node
## --air --balancetest [--craft=...] : hazır uçak denge karnesi (tek satır "BAL ...").
##   A) eller serbest, SAS açık, %80 gaz, 8 sn: irtifa kayması, en büyük |G-1|, yunuslama salınımı
##   B) tam çubuk 4 sn: en büyük G ve hücum açısı, pilot bayıldı mı, en büyük G yükü (strain)
##   C) bırak, 4 sn toparlan
##   D) tam sağa yatış 2 sn: yatış hızı (°/sn)
##   E) eller serbest, SAS kapalı, 5 sn: en büyük |G-1|, en büyük yunuslama hızı (ıraksıyor mu)

var main: Node


func _ready() -> void:
	process_physics_priority = -100
	var v: Vessel = main.vessel
	var pc: PlayerController = main.player
	await get_tree().create_timer(1.0).timeout
	pc.throttle = 0.8
	var fcs := pc._fcs()
	var tol := pc.g_tolerance()
	# kararlılık payı (hangardaki hesap): + kaldırma merkezi ağırlık merkezinin arkasında
	var col := Vector3.ZERO
	var col_area := 0.0
	for m in v.modules:
		if m is WingModule and absf(m.part.basis.y.y) > 0.7:
			col += m.ac_local() * m.area
			col_area += m.area
	var margin := (col / maxf(col_area, 0.01)).z - v.com_local.z
	print("BALM %s pay=%+.2f m kütle=%d kg" % [v.craft_name, margin, v.mass])
	# A
	var alt0 := v.altitude()
	var a := await _watch(v, pc, 8.0)
	var dalt := v.altitude() - alt0
	# B
	Input.action_press("pitch_up")
	var b := await _watch(v, pc, 4.0)
	Input.action_release("pitch_up")
	# C
	await _watch(v, pc, 4.0)
	# D
	var bank0 := _bank(v)
	Input.action_press("roll_right")
	var t := 0.0
	var roll_rate := 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		roll_rate = maxf(roll_rate, absf(rad_to_deg(v.local_angular_velocity().z)))
	Input.action_release("roll_right")
	await _watch(v, pc, 3.0)
	# E
	v.sas = false
	var e := await _watch(v, pc, 5.0)
	v.sas = true
	print("BAL %-28s fcs=%-5s tol=%.1f | A Δirtifa=%+5d m |G-1|=%.2f q=%.2f | B G=%.1f α=%.0f° strain=%.2f bayıldı=%s | D yatış=%3d°/s | E |G-1|=%.2f q=%.2f bayıldı=%s | hız=%d km/sa" % [
		v.craft_name, fcs, tol, dalt, a["dg"], a["q"], b["g"], b["aoa"], b["strain"], b["out"], roll_rate, e["dg"], e["q"], e["out"], v.airspeed() * 3.6])
	get_tree().quit()


func _bank(v: Vessel) -> float:
	var up := Planet.up_at(v.global_position)
	return rad_to_deg(asin(clampf(v.global_basis.x.dot(up), -1.0, 1.0)))


## Süre boyunca: en büyük G, |G-1|, hücum açısı, yunuslama hızı (rad/s), G yükü, bayılma.
func _watch(v: Vessel, pc: PlayerController, secs: float) -> Dictionary:
	var r := {"g": -INF, "dg": 0.0, "aoa": 0.0, "q": 0.0, "strain": 0.0, "out": false}
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(v) or v.parts.is_empty():
			break
		r["g"] = maxf(r["g"], v.g_force)
		r["dg"] = maxf(r["dg"], absf(v.g_force - 1.0))
		r["aoa"] = maxf(r["aoa"], v.aoa_deg())
		r["q"] = maxf(r["q"], absf(v.local_angular_velocity().x))
		r["strain"] = maxf(r["strain"], pc.g_strain)
		r["out"] = r["out"] or pc.blackout
		if Game.args.has("balverbose") and fmod(t, 0.25) < get_physics_process_delta_time():
			print("BALV t=%.2f G=%+.2f q=%+.3f α=%+.1f kumanda=%+.2f trim=%+.2f hız=%d irt=%d" % [
				t, v.g_force, v.local_angular_velocity().x, v.aoa_deg(), v.ctrl_pitch, pc._auto_trim, v.airspeed() * 3.6, v.altitude()])
	return r
