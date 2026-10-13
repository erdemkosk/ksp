extends Node
## --buildprobe: uçak kurma ve sahneye ekleme süresi (yapay zekâ doğarken takılma).
var main: Node

func _ready() -> void:
	await get_tree().create_timer(2.0).timeout
	for i in 3:
		var craft := VesselBuilder.load_craft("res://crafts/kartal_1.json")
		var t0 := Time.get_ticks_usec()
		var v := VesselBuilder.build(craft)
		var t1 := Time.get_ticks_usec()
		FloatingOrigin.world_root.add_child(v)
		v.global_position = main.vessel.global_position + Vector3(0, 300 + i * 50, 0)
		var t2 := Time.get_ticks_usec()
		await get_tree().process_frame
		var t3 := Time.get_ticks_usec()
		print("BUILD kur %.1f ms · ekle %.1f ms · sonraki kare %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
		v.queue_free()
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
