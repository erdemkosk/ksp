extends Node
## --takeofftest [--craft=...] : pistten kalkış. Tam gaz, eller serbest koşu; kalkış hızında çubuk
## çekilir. Ölçülen: koşuda / kalkışta en büyük yatış açısı, burun kalktı mı (en büyük yunuslama),
## tekerlek kesme süresi, kalkıştan 6 sn sonra yatış. Tek satır "TKO ...".

var main: Node


func _bank(v: Vessel) -> float:
	var up := Planet.up_at(v.global_position)
	return rad_to_deg(asin(clampf(v.global_basis.x.dot(up), -1.0, 1.0)))


func _pitch(v: Vessel) -> float:
	var up := Planet.up_at(v.global_position)
	return rad_to_deg(asin(clampf(v.forward().dot(up), -1.0, 1.0)))


func _ready() -> void:
	await get_tree().create_timer(1.5).timeout
	var v: Vessel = main.vessel
	var pc: PlayerController = main.player
	v.parking_brake = false
	pc.throttle = 1.0
	v.set_hot()   # pistte soğuk doğar (batarya / JFS kapalı): motorlar rölantide başlasın
	v.parking_brake = false
	await get_tree().create_timer(1.0).timeout
	var t := 0.0
	var max_bank_roll := 0.0
	var max_pitch := -90.0
	var liftoff := -1.0
	var pulling := false
	var vr := 0.0
	# kalkış hızı ~ stall × 1.25 (yaklaşık: hangar formülü)
	var area := 0.0
	for m in v.modules:
		if m is WingModule and not m is ControlSurfaceModule and absf(m.part.basis.y.y) > 0.6:
			area += m.area
	vr = sqrt(2.0 * v.mass * 9.81 / (1.225 * maxf(area, 0.1) * 1.2)) * 1.25
	var bank_after := 0.0
	while t < 60.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var ground := v.radar_altitude() < 3.5
		if liftoff < 0.0:
			max_bank_roll = maxf(max_bank_roll, absf(_bank(v)))
			if Game.args.has("tkoverbose") and fmod(t, 0.5) < get_physics_process_delta_time():
				var gs := PackedStringArray()
				for m in v.modules:
					if m is LandingGearModule:
						gs.append("%s%+.1f:%.2f%s" % [m.part.part_id.substr(5, 4), m.part.position.x, m.compression, "" if m.grounded else "✗"])
				if absf(t - 3.0) < 0.02:
					var mass_x := PackedStringArray()
					for p in v.parts:
						if absf(p.position.x) > 0.05:
							mass_x.append("%s@%+.2f:%dkg" % [p.part_id, p.position.x, p.get_mass()])
					print("TKC ağırlık merkezi %s  yana dağılım: %s" % [v.com_local.snapped(Vector3.ONE * 0.001), " ".join(mass_x)])
					for m in v.modules:
						if m is WingModule:
							var up_v: Vector3 = v.global_basis.inverse() * (m.last_lift as Vector3)
							print("TKW %s x=%+.2f yukarı=%s kaldırma(yukarı)=%+.0f N  sapma=%+.1f°" % [m.part.part_id, m.part.position.x, m.part.basis.y.snapped(Vector3.ONE * 0.01),
								up_v.y, rad_to_deg(m.deflection) if m is ControlSurfaceModule else 0.0])
				var w := v.local_angular_velocity()
				print("TKV t=%.1f hız=%d yatış=%+.1f sapma_hızı=%+.2f yatış_hızı=%+.2f kmd(yat=%+.2f sap=%+.2f yun=%+.2f) yanal=%+.1f m/s takım %s" % [t, v.airspeed() * 3.6, _bank(v), w.y, w.z,
					v.ctrl_roll, v.ctrl_yaw, v.ctrl_pitch, v.linear_velocity.dot(v.global_basis.x), " ".join(gs)])
		max_pitch = maxf(max_pitch, _pitch(v))
		if not pulling and v.airspeed() > vr:
			pulling = true
			Input.action_press("pitch_up")
		if pulling and _pitch(v) > 10.0:
			Input.action_release("pitch_up")
		if liftoff < 0.0 and not ground and v.airspeed() > 30.0:
			liftoff = t
		if liftoff > 0.0 and t > liftoff + 6.0:
			bank_after = _bank(v)
			break
	Input.action_release("pitch_up")
	print("TKO %s | kalkış hızı ~%d km/sa | koşuda en büyük yatış %.1f° | en büyük yunuslama %.1f° | tekerlek kesme %s | kalkış+6 sn yatış %+.1f° | hız %d km/sa" % [
		v.craft_name, vr * 3.6, max_bank_roll, max_pitch, ("%.1f sn" % liftoff) if liftoff > 0.0 else "YOK", bank_after, v.airspeed() * 3.6])
	get_tree().quit()
