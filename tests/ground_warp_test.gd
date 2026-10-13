extends Node
## --groundwarptest=N: pistte park freniyle zaman sarma xN; uçak zıplıyor / kayıyor mu?
var main: Node

func _ready() -> void:
	await get_tree().create_timer(2.0).timeout
	var v: Vessel = main.vessel
	v.parking_brake = true
	await get_tree().create_timer(1.0).timeout
	var k := int(Game.args.get("groundwarptest", "25"))
	main.time_warp.set_level(main.time_warp.LEVELS.find(k))
	var p0 := v.global_position
	var vmax := 0.0
	var amax := 0.0
	var t := 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		vmax = maxf(vmax, v.linear_velocity.length())
		amax = maxf(amax, v.radar_altitude())
	print("GROUNDWARP x%d (seviye x%d): 30 oyun-sn, en hızlı %.2f m/s, en yüksek %.2f m, kayma %.2f m, parça %d" % [k, main.time_warp.LEVELS[main.time_warp.level], vmax, amax, v.global_position.distance_to(p0), v.parts.size()])
	get_tree().quit()
