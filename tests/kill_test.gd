extends Node
## --air --killtest[=klasör] : vuruş hissi testi. Oyuncunun 350 m önüne düşman koyar, oyuncu adına
## birkaç isabet + kokpit imhası yapar; isabet işareti, DÜŞÜRÜLDÜ şeridi, yanarak düşüş ve yere
## çarpınca enkaz. Klasör verildiyse kill_*.png ekran görüntüleri.

var main: Node


func _ready() -> void:
	await get_tree().create_timer(1.5).timeout
	var me: Vessel = main.vessel
	var dir := str(Game.args.get("killtest", ""))
	var shots := dir != "" and dir != "true"
	main.spawn_enemy(false)
	var e: Vessel = main.enemy
	var up := Planet.up_at(me.global_position)
	e.global_transform = Transform3D(me.global_basis, me.global_position + me.forward() * 350.0 + me.global_basis.x * 40.0 + up * 20.0)
	e.linear_velocity = me.linear_velocity
	e.set_gear_instant(false)
	await get_tree().create_timer(0.5).timeout
	# birkaç mermi isabeti (oyuncu adına)
	for i in 4:
		var part: Part = e.parts[randi() % e.parts.size()]
		Damage._notify(e, part.global_position, me)
		e.damage_part(part, 15.0)
		await get_tree().create_timer(0.08).timeout
	if shots:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/kill_0_hits.png")
	# kokpiti yok et: düşürme
	Damage._notify(e, e.com_global(), me)
	var cp := e.cockpit_part()
	if cp:
		e.damage_part(cp, 1.0e6)
	await get_tree().create_timer(0.5).timeout
	var kf: KillFeedback = main.kill_feedback
	print("KILL düşürme sayısı=%d  düşen=%d" % [kf.kills, kf._falling.size()])
	if shots:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/kill_1_banner.png")
	# düşüşü izle (kamera düşmana)
	main.camera.target = e
	main.camera.mode = FlightCamera.Mode.CHASE
	main.camera.distance = 40.0
	await get_tree().create_timer(4.0).timeout
	if shots:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/kill_2_falling.png")
	var t := 0.0
	while t < 60.0 and kf._falling.size() > 0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	print("KILL yere çarptı=%s (%.0f sn)  enkaz=%d" % [kf._falling.is_empty(), t, FloatingOrigin.world_root.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Wreck")).size()])
	if shots:
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/kill_3_wreck.png")
		# uçuş sonu raporu (pilot yorumları)
		main.camera.target = main.vessel
		# kayıtlara yazmadan yalnız rapor ekranı (end_flight yerde ister, close_flight kariyere yazar)
		var lines: PackedStringArray = main.flight_stats.report()
		lines.append_array(main.flight_stats.pilot_notes("Astğm. Mert Karaca", kf.kills))
		FlightReport.open(main, "UÇUŞ TAMAMLANDI", lines, true)
		await get_tree().create_timer(1.5, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/kill_4_report.png")
	get_tree().quit()
