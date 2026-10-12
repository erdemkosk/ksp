extends Node
## Fareyle uçuş testi: nişanı 90° sağa ve 10° yukarı ver, uçağın oraya dönmesini izle.

var main: Node
var _t := 0.0


func _ready() -> void:
	await get_tree().physics_frame
	var v: Vessel = main.vessel
	var fr := Planet.local_basis(v.global_position)
	main.player.mouse_flight = true
	main.player.throttle = 0.8
	main.player.aim_dir = (fr.x * cos(deg_to_rad(10.0)) + fr.y * sin(deg_to_rad(10.0))).normalized()   # doğu, 10° yukarı


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	if fmod(_t, 1.0) < delta:
		var err := rad_to_deg(v.forward().angle_to(main.player.aim_dir))
		print("t=%2d yön=%5.1f yunus=%+5.1f yatış=%+6.1f G=%+4.1f nişan hatası=%5.1f°" % [_t, v.heading_deg(), v.pitch_deg(), v.roll_deg(), v.g_force, err])
	if _t > 14.0:
		get_tree().quit()
