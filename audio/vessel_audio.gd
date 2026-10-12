class_name VesselAudio
extends Node
## Bir aracın sesleri: motor katmanları (uğultu, hışırtı, türbin vınlaması, afterburner),
## hava akışı, iniş takımı motoru, kanopi, teker sürtünmesi ve yuvarlanma.
## Sesler parçalara takılı 3B kaynaklardır; parça koparsa ses de onunla gider.

class EngineVoice:
	var engine: EngineModule
	var roar: AudioStreamPlayer3D
	var hiss: AudioStreamPlayer3D
	var whine: AudioStreamPlayer3D
	var burner: AudioStreamPlayer3D
	var prop: AudioStreamPlayer3D
	var lit := false

var vessel: Vessel
var _engines: Array[EngineVoice] = []
var _airflow: AudioStreamPlayer3D
var _roll: AudioStreamPlayer3D
var _jfs: AudioStreamPlayer3D
var _players: Array[AudioStreamPlayer3D] = []
var _gear_prev := -1.0
var _gear_moving := false
var _canopy_prev := false
var _grounded_prev := {}
var _buffet: AudioStreamPlayer3D
var _rumble: AudioStreamPlayer3D


func setup(v: Vessel) -> void:
	vessel = v
	for m in v.modules:
		if m is EngineModule:
			var e := EngineVoice.new()
			e.engine = m
			# egzoz sesi arkaya yönlü: kaynak +Z'ye (geriye) bakar
			e.roar = _loop(m.part, "engine_roar.ogg", Vector3(0, 0, 3.0), true)
			e.hiss = _loop(m.part, "engine_hiss.ogg", Vector3(0, 0, 3.0), true)
			e.whine = _loop(m.part, "engine_whine.ogg", Vector3(0, 0, -1.0), false)
			e.burner = _loop(m.part, "afterburner.ogg", Vector3(0, 0, 4.0), true)
			if m.prop:
				e.prop = _loop(m.part, "prop_loop.ogg", Vector3(0, 0, -1.0), false)
			_engines.append(e)
			if _jfs == null:
				_jfs = _loop(m.part, "jfs.ogg", Vector3(0, -0.5, -1.5), false)
	var cockpit := v.cockpit_part()
	var anchor: Part = cockpit if cockpit else (v.parts[0] if not v.parts.is_empty() else null)
	if anchor:
		_airflow = _loop(anchor, "airflow.ogg", Vector3(0, 0.8, 0), false)
		_roll = _loop(anchor, "tire_roll.ogg", Vector3(0, -1.5, 3.0), false)
		_buffet = _loop(anchor, "buffet_loop.ogg", Vector3(0, 0, 0.5), false)
		_rumble = _loop(anchor, "gun_rumble.ogg", Vector3(0, 0, -1.0), false)


func _loop(part: Part, file: String, offset: Vector3, rear: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.looped(file)
	p.volume_db = -80.0
	p.unit_size = 18.0
	p.max_distance = 6000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.position = offset
	if rear:
		p.rotation_degrees = Vector3(0, 180, 0)
		p.emission_angle_enabled = true
		p.emission_angle_degrees = 70.0
		p.emission_angle_filter_attenuation_db = -10.0
	part.add_child(p)
	p.play(randf() * 2.0)
	_players.append(p)
	return p


func _process(_delta: float) -> void:
	if not is_instance_valid(vessel):
		return
	var bus := Sfx.world_bus()
	for p in _players:
		if is_instance_valid(p):
			p.bus = bus

	for e in _engines:
		if not is_instance_valid(e.roar):
			continue
		var attached := e.engine.vessel != null       # kopmuş motor susar
		var n2 := e.engine.n2 if attached else 0.0
		var flame := e.engine.flame_level() if attached else 0.0
		var ab := e.engine.afterburner if attached else 0.0
		# türbin vınlaması çekirdek devrini izler (marşta da duyulur)
		e.whine.volume_db = linear_to_db(maxf(smoothstep(0.02, 0.25, n2) * (0.45 + 0.3 * n2), 0.0001)) - 16.0
		e.whine.pitch_scale = 0.3 + 0.82 * n2
		# yanma sesleri: ateşlemeden sonra
		e.roar.volume_db = linear_to_db(maxf(flame, 0.0001)) + 2.0
		e.roar.pitch_scale = 0.75 + 0.35 * flame
		e.hiss.volume_db = linear_to_db(maxf(flame * flame * 0.8, 0.0001)) - 2.0
		e.hiss.pitch_scale = 0.85 + 0.3 * flame
		e.burner.volume_db = linear_to_db(maxf(ab, 0.0001)) + 5.0
		e.burner.pitch_scale = 0.9 + 0.15 * ab
		if e.prop:
			# pervaneli motor: jet katmanları susar, pistonlu motor + pervane vızıltısı
			e.roar.volume_db = -80.0
			e.hiss.volume_db = -80.0
			e.burner.volume_db = -80.0
			e.whine.volume_db -= 14.0
			e.prop.volume_db = linear_to_db(maxf(smoothstep(0.05, 0.3, n2) * (0.5 + 0.6 * n2), 0.0001)) + 3.0
			e.prop.pitch_scale = 0.42 + 0.75 * n2
		# ateşleme anı: boğuk bir "vuff"
		if flame > 0.0 and not e.lit:
			Sfx.play_at("ignition.ogg", e.engine.part.global_position, 0.0, randf_range(0.9, 1.05))
			# ateşleme anı: egzozdan kısa bir yanmamış yakıt dumanı
			var puff := PuffTrail.create(e.engine.part, Vector3(0, 0, e.engine.part.size.z * 0.5 + 0.5), "smoke")
			puff.c0 = Color(0.35, 0.34, 0.33, 0.6)
			puff.rate = 25.0
			puff.rise = 0.6
			puff.get_tree().create_timer(1.2).timeout.connect(func() -> void:
				if is_instance_valid(puff):
					puff.emitting = false)
		e.lit = flame > 0.0
	if is_instance_valid(_jfs):
		_jfs.volume_db = linear_to_db(maxf(vessel.jfs_spool, 0.0001)) - 6.0
		_jfs.pitch_scale = 0.35 + 0.65 * vessel.jfs_spool

	# hava akışı: dinamik basınçla artar (kokpitte rüzgar uğultusu)
	if is_instance_valid(_airflow):
		var speed := vessel.airspeed()
		var q := 0.5 * vessel.air_density() * speed * speed
		_airflow.volume_db = linear_to_db(clampf(q / 40000.0, 0.0001, 1.0)) - 4.0
		_airflow.pitch_scale = 0.75 + clampf(speed / 400.0, 0.0, 0.8)
		# hücum açısı ve yan kayma: akış bozulur, uğultu sertleşir
		var lv := vessel.global_basis.inverse() * vessel.linear_velocity
		var slip := absf(lv.x) / maxf(speed, 1.0)
		var rough := clampf((absf(vessel.aoa_deg()) - 6.0) / 14.0 + slip * 3.0, 0.0, 1.0) * clampf(speed / 80.0, 0.0, 1.0)
		_airflow.volume_db += rough * 6.0
		_airflow.pitch_scale -= rough * 0.12
		if vessel.mach() > 1.0:
			# ses üstü: şok dalgasının boğuk gürlemesi
			_airflow.volume_db += 3.0
			_airflow.pitch_scale *= 0.8

	# stall titremesi ve top gümbürtüsü
	if is_instance_valid(_buffet):
		var aoa := absf(vessel.aoa_deg())
		var b := clampf((aoa - 10.0) / 8.0, 0.0, 1.0) * clampf(vessel.airspeed() / 60.0, 0.0, 1.0)
		# ses hızı civarında şok dalgası titremesi (transonik)
		b = maxf(b, clampf(1.0 - absf(vessel.mach() - 1.0) / 0.07, 0.0, 1.0) * 0.55)
		_buffet.volume_db = linear_to_db(maxf(b, 0.0001)) + 2.0
	if is_instance_valid(_rumble):
		var firing := vessel.ctrl_fire and vessel.master_arm and vessel.selected_weapon == Vessel.WEAPON_GUN and vessel.gun_ammo() > 0 and vessel.has_power()
		_rumble.volume_db = 2.0 if firing else -80.0
	_gear_sounds()
	_canopy_sounds()
	_tire_sounds()


func _gear_sounds() -> void:
	var d := vessel.gear_deploy()
	if _gear_prev < 0.0:
		_gear_prev = d
		return
	var moving := absf(d - _gear_prev) > 0.0001
	if moving and not _gear_moving:
		Sfx.play_at("gear_motor.ogg", vessel.com_global(), -20.0, 0.9)
	if not moving and _gear_moving:
		Sfx.play_at("hydraulic_thunk.ogg", vessel.com_global(), -16.0)
	_gear_moving = moving
	_gear_prev = d


func _canopy_sounds() -> void:
	var c := vessel.cockpit()
	if c == null:
		return
	if c.canopy_open != _canopy_prev:
		Sfx.play_at("canopy_motor.ogg", c.part.global_position, -3.0)
		_canopy_prev = c.canopy_open


func _tire_sounds() -> void:
	var rolling := 0.0
	for m in vessel.modules:
		if m is LandingGearModule:
			var was: bool = _grounded_prev.get(m, true)
			if m.grounded and not was and vessel.ground_speed() > 15.0:
				# teker yere değdi: hızla orantılı cıyaklama
				Sfx.play_at("tire_screech.ogg", m.part.global_position, linear_to_db(clampf(vessel.ground_speed() / 80.0, 0.2, 1.0)) - 6.0, randf_range(0.9, 1.1))
				AirfieldProps.SkidMarks.add(m.part.global_position - vessel.global_basis.y * (m.rest_length + m.wheel_radius), vessel.linear_velocity)
			_grounded_prev[m] = m.grounded
			if m.grounded:
				rolling = maxf(rolling, vessel.ground_speed())
	if is_instance_valid(_roll):
		_roll.volume_db = linear_to_db(clampf(rolling / 70.0, 0.0001, 1.0)) - 8.0
		_roll.pitch_scale = 0.7 + clampf(rolling / 120.0, 0.0, 0.8)
