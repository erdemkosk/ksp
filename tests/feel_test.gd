extends Node
## --air --feeltest [--craft=...] : uçuş hissi ölçümü
##   1) 4 sn tam çubuk çek: kumanda sistemi, en büyük hücum açısı ve G (FBW sınırı / mekanikte stall)
##   2) çubuk bırak, SAS kapalı, tam gaz 4 sn: ortalama yatış / sapma hızı (pervane torku)
##   3) Mach 0.85'te düz uçuş: ana kanadın ıraksama Mach'ı, titreşim, şok

var main: Node
var _hold := 0.0


func _ready() -> void:
	process_physics_priority = -100
	var v: Vessel = main.vessel
	await get_tree().create_timer(1.0).timeout
	var pc: PlayerController = main.player
	main.player.throttle = 0.8
	print("FEEL uçak=%s kumanda=%s ana kanat stall=%.1f° FBW sınırı=%.1f°" % [v.craft_name, pc._fcs(), pc._stall_deg, pc._aoa_lim])
	# 1) tam çubuk
	var max_aoa := 0.0
	var max_g := 0.0
	var t := 0.0
	Input.action_press("pitch_up")
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_aoa = maxf(max_aoa, v.aoa_deg())
		max_g = maxf(max_g, v.g_force)
	Input.action_release("pitch_up")
	print("FEEL tam çubuk: en büyük hücum açısı %.1f°  en büyük G %.1f  hız %d km/sa" % [max_aoa, max_g, v.airspeed() * 3.6])
	await get_tree().create_timer(3.0).timeout
	# 2) pervane torku
	v.sas = false
	main.player.throttle = 1.0
	v.angular_velocity = Vector3.ZERO
	var w := Vector3.ZERO
	t = 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		w += v.local_angular_velocity()
	w /= maxf(t * 60.0, 1.0)
	print("FEEL SAS kapalı tam gaz: ortalama açısal hız (yunus %+.3f, sapma %+.3f, yatış %+.3f) rad/s" % [w.x, w.y, w.z])
	v.sas = true
	if is_instance_valid(main.flight_stats):   # rapor, hızın zorla değiştirildiği 3. adımdan önce
		for line in main.flight_stats.report():
			print("FEEL rapor: ", line)
	# 3) transonik
	_hold = v.airspeed()
	var tw := create_tween()
	tw.tween_property(self, "_hold", Atmosphere.SPEED_OF_SOUND * 0.85, 3.0)
	await get_tree().create_timer(3.5).timeout
	var best: WingModule = null
	for m in v.modules:
		if m is WingModule and not m is ControlSurfaceModule and (best == null or m.area > best.area):
			best = m
	if best:
		print("FEEL M%.2f ana kanat: ok açısı %.0f° kalınlık %.3f ıraksama M%.2f delta=%s titreşim %.2f" % [
			v.mach(), rad_to_deg(best.sweep), best.thickness, best.mach_dd, best.is_delta, v.wing_buffet()])
	_hold = 0.0
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _hold > 0.0 and is_instance_valid(main.vessel):
		var v: Vessel = main.vessel
		var up := Planet.up_at(v.global_position)
		var f := (v.forward() - up * v.forward().dot(up)).normalized()
		v.linear_velocity = f * _hold
		v.angular_velocity = Vector3.ZERO
