extends Node
## --air --fxtest=klasör : görsel efekt ekran görüntüleri ("test" ile biter: kadro/kariyer kaydına yazılmaz)
##   1_nozzle_ab.png      art yakıcıda kızaran lüle (arkadan)
##   2_nozzle_cooling.png motor kapandıktan 8 sn sonra soğuyan lüle
##   3_vapor.png          Mach 1'de buhar konisi (yandan)
##   4_wear_new.png / 5_wear_old.png   aynı açıdan yeni ve çok eskimiş boya

var main: Node
var _hold_speed := 0.0


func _ready() -> void:
	process_physics_priority = -100
	var dir := String(Game.args["fxtest"])
	var cam: FlightCamera = main.camera
	var v: Vessel = main.vessel
	await get_tree().create_timer(1.0).timeout
	cam.mode = FlightCamera.Mode.CHASE
	# 4-5: boya — önce, uçak sağlamken ve hız değiştirmeden (zorlanmış hız uçağı bozabiliyor)
	cam.orbit_yaw = deg_to_rad(150.0)
	cam.orbit_elevation = deg_to_rad(22.0)
	cam.distance = 13.0
	VesselBuilder._apply_weathering(v, 0.0)
	await get_tree().create_timer(1.5).timeout
	await _shot(dir + "/4_wear_new.png")
	VesselBuilder._apply_weathering(v, 1.0)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/5_wear_old.png")
	VesselBuilder._apply_weathering(v, 0.4)
	# 1-2: lüle
	main.player.throttle = 1.0
	cam.orbit_yaw = deg_to_rad(25.0)
	cam.orbit_elevation = deg_to_rad(-6.0)
	cam.distance = 12.0
	await get_tree().create_timer(6.0).timeout
	await _shot(dir + "/1_nozzle_ab.png")
	print("FX ısı (AB): %.2f" % _heat(v))
	v.shutdown_engines()
	main.player.throttle = 0.0
	await get_tree().create_timer(8.0).timeout
	await _shot(dir + "/2_nozzle_cooling.png")
	print("FX ısı (8 sn sonra): %.2f" % _heat(v))
	# 3: buhar konisi
	# hız kademeli artar (bir anda zorlanırsa uçak aşırı yükten parçalanır)
	_hold_speed = v.airspeed()
	var tw := create_tween()
	tw.tween_property(self, "_hold_speed", Atmosphere.SPEED_OF_SOUND * 1.0, 3.0)
	cam.orbit_yaw = deg_to_rad(100.0)
	cam.orbit_elevation = deg_to_rad(8.0)
	cam.distance = 22.0
	await get_tree().create_timer(3.6).timeout
	await _shot(dir + "/3_vapor.png")
	var fxn: AeroFx = v.get_node_or_null("AeroFx")
	print("FX Mach: %.2f  koni görünür=%s  yoğunluk=%s  ölçek=%s" % [v.mach(), fxn._cone.visible, fxn._cone_mat.get_shader_parameter("intensity"), fxn._cone.scale])
	# 6: yapı zorlanması — kopma hızının %97'sine kademeli (StressFx rengi, kanat bükülmesi, KOPAR çizgisi)
	var lim := StructLimits.estimate(v, v.air_density())
	print("FX yapı sınırı (bu irtifa): %d km/sa, %.1f G, ilk: %s" % [float(lim["vne"]) * 3.6, lim["g"], lim["vne_part"]])
	if float(lim["vne"]) > 0.0:
		var tw2 := create_tween()
		# çok hızlıda kovalama kamerası geride kalıyor: makul hızda tut, yükü dayanımı düşürerek getir
		tw2.tween_property(self, "_hold_speed", minf(float(lim["vne"]) * 0.9, 280.0), 4.0)
		cam.orbit_yaw = deg_to_rad(140.0)
		cam.orbit_elevation = deg_to_rad(18.0)
		cam.distance = 16.0
		await get_tree().create_timer(4.2).timeout
		# bu hızda yük ~%40: rengi görmek için dayanımı kademeli düşür (yalnız bu test), yük %85'e
		# varınca dur (zorlanmış hız titreşimli: bir anda düşürünce uçak parçalanıyordu)
		for i in 70:
			if v.max_stress > 0.85 or v.parts.is_empty():
				break
			for p in v.parts:
				p.strength *= 0.93
			await get_tree().create_timer(0.1).timeout
		await get_tree().create_timer(0.3).timeout
		await _shot(dir + "/6_stress.png")
		var worst: Part = null
		for p in v.parts:
			if worst == null or p.stress > worst.stress:
				worst = p
		print("FX zorlanma: hız %d km/sa  en yüksek yük %%%d (%s)" % [v.airspeed() * 3.6, v.max_stress * 100.0, worst.title if worst else "-"])
	_hold_speed = 0.0
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _hold_speed > 0.0 and is_instance_valid(main.vessel):
		var v: Vessel = main.vessel
		# irtifa sabit: yatay ileri yönde (bulut katmanına tırmanmasın)
		var up := Planet.up_at(v.global_position)
		var f := (v.forward() - up * v.forward().dot(up)).normalized()
		v.linear_velocity = f * _hold_speed
		v.angular_velocity = Vector3.ZERO


func _heat(v: Vessel) -> float:
	for e: EngineModule in v.engines():
		return e.heat
	return -1.0


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("FX görüntü: ", path)
