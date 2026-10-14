extends Node
## --spawntest[=klasör] [--craft=...] : pistte doğuş: takımlar açık mı, yerde mi, doğarken hasar / arıza
## (hidrolik sızıntı) oluyor mu. 0.2, 1, 3 sn'de durum; klasör verildiyse spawn.png.

var main: Node


func _ready() -> void:
	for t in [0.2, 0.8, 2.0]:
		await get_tree().create_timer(t).timeout
		var v: Vessel = main.vessel
		var gears := []
		for m in v.modules:
			if m is LandingGearModule:
				gears.append("%s açık=%.2f yerde=%s sıkışma=%.2f" % [m.part.part_id, m.deploy, m.grounded, m.compression])
		var hurt := 0
		for p in v.parts:
			if p.health_ratio() < 0.999:
				hurt += 1
		print("SPAWN t+%.1f %s | yerden %.2f m | hasarlı parça %d | arızalar %s | takımlar: %s" % [t, v.craft_name, v.radar_altitude(), hurt, v.failures.values(), "; ".join(gears)])
	var dir := str(Game.args.get("spawntest", ""))
	if dir != "" and dir != "true":
		main.camera.orbit_yaw = deg_to_rad(110.0)
		main.camera.orbit_elevation = deg_to_rad(5.0)
		main.camera.distance = 14.0
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/spawn_%s.png" % str(Game.args.get("craft", "kartal")).get_file().get_basename())
	get_tree().quit()
