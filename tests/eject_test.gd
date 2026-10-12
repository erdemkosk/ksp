extends Node
## --ejecttest: 2 sn sonra fırlatır; pilotun irtifası/hızı ve iniş sonucu yazılır.
## --eject-at=N saniye; --ejectshot=yol ile N+shot sn sonra ekran görüntüsü.

var main: Node
var _t := 0.0
var _done := false


func _physics_process(delta: float) -> void:
	_t += delta
	var at := float(Game.args.get("eject-at", "2"))
	if Game.args.has("radio") and _t < delta * 1.5:
		for k in ["takeoff", "landing", "vector", "weather", "mayday"]:
			main.radio.request(k)
		print("TELSİZ kuyruk=%d" % main.radio._queue.size())
	if _t > at and not _done:
		_done = true
		main.eject()
	if is_instance_valid(main.pilot) and fmod(_t, 1.0) < delta:
		var p: PilotCharacter = main.pilot
		print("t=%.0f pilot alt=%.0f v=%.1f vs=%.1f chute=%s air=%s | uçak parça=%d" % [_t, Planet.altitude(p.global_position), p.velocity.length(),
			p.velocity.dot(Planet.up_at(p.global_position)), p.chute_open, p.airborne, main.vessel.parts.size() if is_instance_valid(main.vessel) else -1])
	if Game.args.has("rescue") and _done and is_instance_valid(main.pilot) and not main.pilot.airborne:
		var h: Helicopter = main.rescue_heli
		if is_instance_valid(h) and fmod(_t, 2.0) < delta:
			print("t=%.0f heli durum=%s mesafe=%.0f hız=%.1f" % [_t, h.state, h.global_position.distance_to(main.pilot.global_position), h.velocity.length()])
		if is_instance_valid(h) and h.state == "landed" and not main._rescued:
			main.pilot.global_position = h.global_position + Planet.up_at(h.global_position) * 1.0 + h.global_basis.x * 4.0
		if main._rescued and h.state == "leave":
			print("RESCUETEST helikopter kalktı, pilot kurtarıldı")
			get_tree().quit()
		return
	if _done and is_instance_valid(main.pilot) and not main.pilot.airborne and _t > at + 3.0:
		print("EJECTTEST indi; güvenli=%s bitirilebilir=%s" % [main._pilot_safe, main.can_end_flight()])
		if Game.args.has("report"):
			set_physics_process(false)
			process_mode = Node.PROCESS_MODE_ALWAYS
			main.end_flight()
			for i in 10:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(String(Game.args["report"]))
		get_tree().quit()
	if _t > 240.0:
		print("EJECTTEST zaman aşımı")
		get_tree().quit()
