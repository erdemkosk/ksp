extends Node
## --air --craft=res://crafts/herkul.json --rampgeartest[=klasör] : kargo rampası ve takım hız sınırı.
##   1) rampa aç → açılma oranı ve kapının dönüşü; klasör verildiyse ramp_open.png
##   2) takımı yavaşta indir (hasar yok olmalı), sonra hız sınırının üstüne çık → hasar / kopma

var main: Node
var _hold := 0.0


func _ready() -> void:
	process_physics_priority = -100
	var v: Vessel = main.vessel
	var cam: FlightCamera = main.camera
	await get_tree().create_timer(1.0).timeout
	var ramp: RampModule = null
	for m in v.modules:
		if m is RampModule:
			ramp = m
	if ramp == null:
		print("RG rampa yok (Herkül ile çalıştır)")
	else:
		ramp.toggle()
		_hold = 80.0
		await get_tree().create_timer(4.0).timeout
		var door := ramp.part.get_node_or_null("Visual/Ramp") as Node3D
		print("RG rampa açık=%s açılma=%.2f kapı dönüşü=%.1f°" % [ramp.open, ramp.deploy, rad_to_deg(door.rotation.x) if door else -1.0])
		var dir := str(Game.args.get("rampgeartest", ""))
		if dir != "" and dir != "true":
			cam.mode = FlightCamera.Mode.CHASE
			cam.orbit_yaw = deg_to_rad(150.0)
			cam.orbit_elevation = deg_to_rad(-8.0)
			cam.distance = 30.0
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir + "/ramp_open.png")
			print("RG görüntü: ", dir + "/ramp_open.png")
		ramp.toggle()
	# takım: önce sınırın altında, sonra üstünde
	var gear: LandingGearModule = null
	for m in v.modules:
		if m is LandingGearModule:
			gear = m
			break
	if gear == null:
		print("RG takım yok")
		get_tree().quit()
		return
	_hold = gear.max_speed * 0.7
	v.gear_down = true
	await get_tree().create_timer(4.0).timeout
	print("RG yavaş (%d km/sa): takım açılma=%.2f sağlık=%%%d" % [_hold * 3.6, gear.deploy, gear.part.health_ratio() * 100.0])
	# kademeli hızlan (bir anda hız atlatmak ivme yüküyle takımı hemen koparıyordu)
	var tw := create_tween()
	tw.tween_property(self, "_hold", gear.max_speed * 1.25, 3.0)
	await tw.finished
	var n_gear := 0
	for m in v.modules:
		if m is LandingGearModule:
			n_gear += 1
	for i in 6:
		await get_tree().create_timer(0.5).timeout
		var alive := 0
		for m in v.modules:
			if m is LandingGearModule:
				alive += 1
		print("RG hızlı (%d km/sa) t=%.1f: takım %d/%d  ilk takım sağlık=%%%d" % [_hold * 3.6, (i + 1) * 0.5, alive, n_gear, gear.part.health_ratio() * 100.0 if is_instance_valid(gear.part) else 0.0])
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _hold > 0.0 and is_instance_valid(main.vessel):
		var v: Vessel = main.vessel
		var up := Planet.up_at(v.global_position)
		var f := (v.forward() - up * v.forward().dot(up)).normalized()
		v.linear_velocity = f * _hold
		v.angular_velocity = Vector3.ZERO
