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
var _drag: AudioStreamPlayer3D        ## iniş takımı / hava freni hava gürültüsü
var _scrape: AudioStreamPlayer3D      ## gövde zemine sürtünüyor
var _vel_prev := Vector3.ZERO
var _air_vs := 0.0                    ## teker yere değmeden önceki dikey hız
var _impact_cd := 0.0
var _creak_t := 1.0
var _contact := false
var _scrape_lin := 0.0


func setup(v: Vessel) -> void:
	vessel = v
	v.part_destroyed.connect(_on_part_destroyed)
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
		_drag = _loop(anchor, "", Vector3(0, -1.0, 1.0), false, Synth.get_stream("drag_rumble"))
		_scrape = _loop(anchor, "", Vector3(0, -1.0, 0.0), false, Synth.get_stream("scrape"))


func _loop(part: Part, file: String, offset: Vector3, rear: bool, stream: AudioStream = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream if stream else Sfx.looped(file)
	p.volume_db = -80.0
	p.unit_size = 18.0
	p.max_distance = 6000.0
	# uzaklıkta tiz sesler havada söner (uzaktaki jet boğuk gürler)
	p.attenuation_filter_cutoff_hz = 3200.0
	p.attenuation_filter_db = -30.0
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
	# kendi uçağımızın kabininden: egzoz gürültüsü gövdeden süzülür (kanal filtresine ek kısma)
	var ck := AudioManager.cockpit_of(vessel) * (1.0 - InteriorAudio.canopy_amount(vessel) * 0.5)

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
			e.prop.volume_db -= 5.0 * ck
		e.roar.volume_db -= 8.0 * ck
		e.hiss.volume_db -= 10.0 * ck
		e.burner.volume_db -= 6.0 * ck
		e.whine.volume_db -= 3.0 * ck
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
		_airflow.volume_db -= 4.0 * ck     # kabinde rüzgarı InteriorAudio verir
		if is_instance_valid(_drag):
			var qn := clampf(q / 40000.0 * 2.2, 0.0, 1.0)
			var brake := 0.0
			for m in vessel.modules:
				if m is AirbrakeModule:
					brake = maxf(brake, m.deploy)
			var d := qn * (0.55 * vessel.gear_deploy() + 0.85 * brake)
			_drag.volume_db = linear_to_db(maxf(d, 0.0001)) - 2.0 - 6.0 * ck
			_drag.pitch_scale = 0.8 + 0.3 * clampf(speed / 250.0, 0.0, 1.0)

	# stall titremesi ve top gümbürtüsü
	if is_instance_valid(_buffet):
		var aoa := absf(vessel.aoa_deg())
		var b := clampf((aoa - 10.0) / 8.0, 0.0, 1.0) * clampf(vessel.airspeed() / 60.0, 0.0, 1.0)
		# ses hızı civarında şok dalgası titremesi (transonik)
		b = maxf(b, clampf(1.0 - absf(vessel.mach() - 1.0) / 0.07, 0.0, 1.0) * 0.55)
		# kanat tipine göre titreşim (düz kanatta stall öncesi sert, deltada hafif; kalın kanatta şok)
		b = maxf(b, vessel.wing_buffet() * 0.9)
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
			if m.grounded and not was and _air_vs < -3.0:
				# sert iniş: amortisör dibe vurur; çok sertse gövde çatırdar
				var k := clampf((-_air_vs - 3.0) / 5.0, 0.0, 1.0)
				Sfx.play_stream_at(Synth.get_stream("thud"), m.part.global_position, linear_to_db(0.35 + 0.65 * k) + 4.0, randf_range(0.85, 1.0), 1500.0)
				if _air_vs < -6.0:
					Sfx.play_stream_at(Synth.get_stream("crunch_%d" % (randi() % 3)), m.part.global_position, linear_to_db(k) + 2.0, randf_range(0.8, 1.0), 1500.0)
				AudioManager.cockpit_impact(vessel, 0.3 + 0.7 * k)
				_air_vs = 0.0
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


# ------------------------------------------------------------------ darbeler ve sürtünme

func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel) or vessel.parts.is_empty():
		return
	_impact_cd -= delta
	var v := vessel.linear_velocity
	var dv := (v - _vel_prev).length()
	_vel_prev = v
	var any_wheel := false
	for m in vessel.modules:
		if m is LandingGearModule and m.grounded:
			any_wheel = true
	if not any_wheel:
		_air_vs = vessel.vertical_speed()
	var contacts := vessel.get_contact_count()
	# gövde / parça bir şeye çarptı: tek adımda ani hız değişimi (aerodinamik kuvvetlerin çok üstünde)
	var hit := contacts > 0 and (dv > 2.5 or (not _contact and dv > 1.2))
	if hit and _impact_cd <= 0.0:
		var k := clampf((dv - 1.0) / 12.0, 0.15, 1.0)
		var pos := vessel.com_global() - vessel.up() * 1.0
		Sfx.play_stream_at(Synth.get_stream("crunch_%d" % (randi() % 3)), pos, linear_to_db(k) + 6.0, randf_range(0.8, 1.1), 2000.0)
		if k > 0.4:
			Sfx.play_at("impact_metal_%d.ogg" % (1 + randi() % 2), pos, linear_to_db(k) - 2.0, randf_range(0.6, 0.8), 1200.0)
		AudioManager.cockpit_impact(vessel, k)
		_impact_cd = 0.18
	_contact = contacts > 0
	# sürtünme: gövde (teker değil) zemine değerken kayıyor
	if is_instance_valid(_scrape):
		var slide := vessel.ground_speed() if contacts > 0 else 0.0
		var target := clampf((slide - 2.0) / 40.0, 0.0, 1.0)

		_scrape_lin = move_toward(_scrape_lin, target, delta * 4.0)
		_scrape.volume_db = linear_to_db(maxf(_scrape_lin, 0.0001)) + 3.0
		_scrape.pitch_scale = 0.75 + clampf(slide / 80.0, 0.0, 0.6)
	# aşırı yük: gövde gıcırdar (yapı limitine yaklaşınca sıklaşır)
	_creak_t -= delta
	if vessel.max_stress > 0.65 and _creak_t <= 0.0:
		var s := clampf((vessel.max_stress - 0.65) / 0.35, 0.0, 1.0)
		_creak_t = lerpf(1.6, 0.5, s) * randf_range(0.8, 1.2)
		var ck := AudioManager.cockpit_of(vessel)
		Sfx.play_stream_at(Synth.get_stream("creak_%d" % (randi() % 2)), vessel.com_global(), linear_to_db(0.3 + 0.7 * s) - 4.0 + 4.0 * ck, randf_range(0.85, 1.15), 400.0)


## Parça koptu / parçalandı: metal yırtılması ve ezilme (patlama sesini Vessel çalar).
func _on_part_destroyed(part: Part) -> void:
	if not is_instance_valid(vessel):
		return
	var pos := part.global_position if is_instance_valid(part) and part.is_inside_tree() else vessel.com_global()
	Sfx.play_stream_at(Synth.get_stream("crunch_%d" % (randi() % 3)), pos, 4.0, randf_range(0.7, 0.9), 2500.0)
	Sfx.play_stream_at(Synth.get_stream("creak_%d" % (randi() % 2)), pos, 0.0, randf_range(1.2, 1.5), 1000.0)
	AudioManager.cockpit_impact(vessel, 0.9)


## Hata ayıklama: etkin katmanların sesi (dB).
func debug_layers() -> String:
	var out := PackedStringArray()
	var named := {"airflow": _airflow, "buffet": _buffet, "drag": _drag, "scrape": _scrape, "roll": _roll}
	if not _engines.is_empty():
		var e := _engines[0]
		named["roar"] = e.roar
		named["hiss"] = e.hiss
		named["whine"] = e.whine
		named["burner"] = e.burner
		if e.prop:
			named["prop"] = e.prop
	for k in named:
		var p: Variant = named[k]
		if is_instance_valid(p) and p.volume_db > -60.0:
			out.append("%s=%.1fdB" % [k, p.volume_db])
	var bus: String = str(_airflow.bus) if is_instance_valid(_airflow) else "?"
	return "kanal=%s %s" % [bus, ", ".join(out) if not out.is_empty() else "(sessiz)"]
