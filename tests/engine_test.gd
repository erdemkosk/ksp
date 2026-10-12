extends Node
## --enginetest: yeni motor türlerini dener (ramjet, darbeli jet, TVC, JATO).
## Her test uçağı 6 km'de, hızı her fizik karesinde sabitlenerek itki ölçülür.

var main: Node
var _vessels: Array[Vessel] = []


func _ready() -> void:
	process_physics_priority = -100   # hız sabitleme uçağın fizik karesinden önce
	await get_tree().physics_frame
	print("ENGINE ramjet çarpanı: M0.3=%.2f M1.0=%.2f M2.0=%.2f M3.0=%.2f M4.0=%.2f" % [
		EngineModule.ramjet_factor(0.3), EngineModule.ramjet_factor(1.0), EngineModule.ramjet_factor(2.0),
		EngineModule.ramjet_factor(3.0), EngineModule.ramjet_factor(4.0)])
	for id in ["jet_engine", "ramjet", "pulse_jet"]:
		for mach in [0.3, 0.9, 2.0, 3.0]:
			var thrust := await _thrust_at(id, mach)
			print("ENGINE %-10s M%.1f itki=%6.1f kN" % [id, mach, thrust / 1000.0])
	await _tvc_test()
	await _jato_test()
	get_tree().quit()


func _spawn(parts: Array, nose := "nose_cone") -> Vessel:
	var craft := {"name": "t", "parts": [{"part": nose, "pos": [0, 0, -2.6 if nose == "nose_cone" else -4.0]}, {"part": "tank_long", "pos": [0, 0, 0]}] + parts}
	var v := VesselBuilder.build(craft)
	main.world.add_child(v)
	v.global_position = main.vessel.global_position + Vector3(0, 6000, 400 + _vessels.size() * 60)
	v.sas = false
	v.ctrl_throttle = 0.9   # AB'siz kuru güç
	_vessels.append(v)
	return v


func _hold_speed(v: Vessel, speed: float, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		v.linear_velocity = v.forward() * speed
		v.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _thrust_at(id: String, mach: float) -> float:
	var v := _spawn([{"part": id, "pos": [0, 0, 3.6]}])
	await _hold_speed(v, mach * Atmosphere.SPEED_OF_SOUND, 4.0)
	var t := 0.0
	for e: EngineModule in v.engines():
		t += e.thrust
	v.queue_free()
	return t


func _tvc_test() -> void:
	var v := _spawn([{"part": "jet_engine_tvc", "pos": [0, 0, 3.6]}], "cockpit_mk1")
	var e: EngineModule = v.engines()[0]
	for spec in [["pitch", Vector3(1, 0, 0)], ["yaw", Vector3(0, 1, 0)], ["none", Vector3.ZERO]]:
		v.ctrl_pitch = spec[1].x
		v.ctrl_yaw = spec[1].y
		await _hold_speed(v, 120.0, 1.5)
		var local_dir := e.part.basis * (Basis.from_euler(Vector3(e.gimbal_cmd.x, e.gimbal_cmd.y, 0.0) * e.gimbal) * Vector3.FORWARD)
		var torque := (e.part.position - v.com_local).cross(local_dir * e.thrust)
		print("ENGINE TVC %-5s gimbal=%s tork=(%.0f, %.0f, %.0f) N·m" % [spec[0], e.gimbal_cmd, torque.x, torque.y, torque.z])
	# kokpitli uçak serbest bırakılmaz (çıkışta zaten kapanır)


func _jato_test() -> void:
	var v := _spawn([{"part": "jet_engine", "pos": [0, 0, 3.6]}, {"part": "jato", "pos": [0.95, -0.3, 0.5], "mirror": true}])
	var boosters := v.get_modules_of(BoosterModule)
	print("ENGINE JATO sayısı=%d kütle=%.0f kg" % [boosters.size(), v.mass])
	for b: BoosterModule in boosters:
		b.ignite()
	var total := 0.0
	for s in [1.0, 4.0, 6.0]:
		total += s
		await _hold_speed(v, 80.0, s)
		var b: BoosterModule = boosters[0]
		print("ENGINE JATO t=%.0f sn yanıyor=%s itki=%.1f kN yakıt=%.0f kg ikinci ateşleme=%s" % [total, b.burning(), b.thrust / 1000.0, b.propellant, b.ignite()])
	v.queue_free()
