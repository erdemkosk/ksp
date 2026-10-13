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
	if Game.args.has("boom"):
		# 7-8: patlama — uçağın önünde yerde ağır bomba (size 3.5) ve havada füze (1.2)
		cam.orbit_yaw = 0.0                    # uçağın arkasından ileri bak
		cam.orbit_elevation = deg_to_rad(8.0)
		cam.distance = 18.0
		await get_tree().create_timer(1.0).timeout
		var up := Planet.up_at(v.global_position)
		var ahead := v.global_position + v.forward() * 900.0
		var ground := ahead - up * (Planet.altitude(ahead) - maxf(TerrainGen.height(Planet.surface_dir(ahead)), 0.0))
		if Game.args.has("boomnear"):
			if Game.args.has("warm"):
				Effects.explosion(FloatingOrigin.world_root, v.global_position - v.forward() * 300.0, up, 1.0)
				await get_tree().create_timer(3.0).timeout
			var cam3 := get_viewport().get_camera_3d()
			# uçak ~190 m/sn gider: patlama 450 m önde ve yanda olsun ki 2 sn kadrajda kalsın
			var near_p := cam3.global_position - cam3.global_basis.z * 260.0 + cam3.global_basis.x * 40.0 + up * 15.0
			Effects.explosion(FloatingOrigin.world_root, near_p, up, 1.5)
			for i in 5:
				await get_tree().create_timer([0.06, 0.15, 0.3, 0.5, 0.6][i]).timeout
				await _shot(dir + "/near_%d.png" % i)
				if i == 1:
					for c in FloatingOrigin.world_root.get_children():
						if c is GPUParticles3D and c.global_position.distance_to(near_p) < 50.0:
							print("FX parçacık: konum mesafe=%.1f yayıyor=%s görünür=%s ölçek=%s ömür=%.2f adet=%d kamera=%.0f m aabb=%s" % [
								c.global_position.distance_to(near_p), c.emitting, c.is_visible_in_tree(), c.global_basis.get_scale(), c.lifetime, c.amount,
								c.global_position.distance_to(cam3.global_position), c.visibility_aabb])
			get_tree().quit()
			return
		Effects.explosion(FloatingOrigin.world_root, ground, up, 3.5)
		Effects.explosion(FloatingOrigin.world_root, v.global_position + v.forward() * 250.0 + v.global_basis.x * 70.0 + up * 25.0, up, 1.2)
		await get_tree().create_timer(0.12).timeout
		var c3 := get_viewport().get_camera_3d()
		var air_p := v.global_position + v.forward() * 250.0 + v.global_basis.x * 70.0 + up * 25.0
		print("FX patlama: yer %s ekranda %s arkada=%s | hava ekranda %s arkada=%s | kök %s" % [ground, c3.unproject_position(ground), c3.is_position_behind(ground), c3.unproject_position(air_p), c3.is_position_behind(air_p), FloatingOrigin.world_root])
		var n_fx := 0
		for c in FloatingOrigin.world_root.get_children():
			if c is GPUParticles3D or c is OmniLight3D:
				n_fx += 1
		print("FX dünya kökünde efekt düğümü: %d" % n_fx)
		await _shot(dir + "/7_boom_flash.png")
		await get_tree().create_timer(1.2).timeout
		await _shot(dir + "/8_boom_smoke.png")
		get_tree().quit()
		return
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
