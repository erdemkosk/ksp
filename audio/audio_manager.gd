class_name AudioManager
extends Node
## Ses kanalları ve ortam sesleri.
##   World    — dış dünya sesleri (mesafe + hava sönümü, Doppler: AudioStreamPlayer3D)
##   Cockpit  — kokpit görünümünde dış sesler: güçlü alçak geçiren filtre + kısık ses +
##              küçük kabin yankısı. Kanopi açılınca filtre açılır, ses yükselir.
##   Interior — kabin içi katmanlar (InteriorAudio): gövde uğultusu, rüzgar hışırtısı,
##              titreşim, pilot nefesi / zorlanma, isabet tıkırtıları
##   UI       — düğmeler, uyarı tonları
## Ortam: rüzgar, yağmur, gök gürültüsü (şimşekten sonra mesafeye göre gecikmeli), sesli uyarılar.
## Test / hata ayıklama: --audioprobe (2 sn'de bir katman dökümü), --audiotest (sentetik
## durum tablosu + kamera kipleri arasında otomatik geçiş).

const BUS_INTERIOR := "Interior"
const COCKPIT_CUTOFF_CLOSED := 850.0
const COCKPIT_CUTOFF_OPEN := 6500.0

static var instance: AudioManager
static var _stun_filters: Array = []

var camera: FlightCamera
var player: PlayerController:
	set(p):
		player = p
		if _interior:
			_interior.player = p
var vessel: Vessel:
	set(v):
		vessel = v
		if _warnings:
			_warnings.vessel = v
		if _interior:
			_interior.vessel = v

var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _warnings: WarningVoice
var _interior: InteriorAudio
var _cockpit_mix := 0.0
var _pending_thunder: Array[float] = []
var _warm := 0
var _debug := false
var _debug_t := 0.0
var _test_t := 0.0


func _ready() -> void:
	instance = self
	_setup_buses()
	_wind = _ambient("wind.ogg")
	_rain = _ambient("rain.ogg")
	_warnings = WarningVoice.new()
	_warnings.vessel = vessel
	add_child(_warnings)
	_interior = InteriorAudio.new()
	_interior.vessel = vessel
	_interior.player = player
	add_child(_interior)
	_debug = Game.args.has("audioprobe") or Game.args.has("audiotest")
	if Game.args.has("audiotest"):
		_self_test()


func _ambient(file: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.looped(file)
	p.volume_db = -80.0
	p.bus = Sfx.BUS_WORLD
	add_child(p)
	p.play()
	return p


func _setup_buses() -> void:
	if AudioServer.get_bus_index(Sfx.BUS_WORLD) == -1:
		for name in [Sfx.BUS_WORLD, Sfx.BUS_COCKPIT, Sfx.BUS_UI]:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")
		var cp := AudioServer.get_bus_index(Sfx.BUS_COCKPIT)
		var lp := AudioEffectLowPassFilter.new()     # efekt 0: kabin filtresi (kanopiyle değişir)
		lp.cutoff_hz = COCKPIT_CUTOFF_CLOSED
		lp.resonance = 0.55
		AudioServer.add_bus_effect(cp, lp)
		var room := AudioEffectReverb.new()
		room.room_size = 0.08
		room.damping = 0.8
		room.wet = 0.12
		room.dry = 1.0
		AudioServer.add_bus_effect(cp, room)
		AudioServer.set_bus_volume_db(cp, -6.0)
		# patlama sersemlemesi: dünya ve kokpit kanallarında açılıp kapanan alçak geçiren filtre
		for bus in [Sfx.BUS_WORLD, Sfx.BUS_COCKPIT]:
			var f := AudioEffectLowPassFilter.new()
			f.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), f)
			_stun_filters.append(f)
		# Tüm sesleri sınırlayan yumuşak limiter (patlamalarda bozulma olmasın)
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	if AudioServer.get_bus_index(BUS_INTERIOR) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_INTERIOR)
		AudioServer.set_bus_send(idx, "Master")
		var f := AudioEffectLowPassFilter.new()
		f.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(idx, f)
		_stun_filters.append(f)


## Kokpit kanalının kabin filtresi (efekt 0).
func _cockpit_filter() -> AudioEffectLowPassFilter:
	var cp := AudioServer.get_bus_index(Sfx.BUS_COCKPIT)
	if cp == -1 or AudioServer.get_bus_effect_count(cp) == 0:
		return null
	return AudioServer.get_bus_effect(cp, 0) as AudioEffectLowPassFilter


## Şimşek çaktı: gök gürültüsü 1–5 sn sonra gelir.
func thunder() -> void:
	_pending_thunder.append(randf_range(1.0, 5.0))


func in_cockpit_view() -> bool:
	return is_instance_valid(camera) and is_instance_valid(vessel) \
		and camera.mode == FlightCamera.Mode.COCKPIT and not camera.is_eva() and vessel.has_pilot()


func _process(delta: float) -> void:
	# kodla üretilen sesleri kare başına birer birer hazırla (ilk kullanımda takılmasın)
	if _warm < Synth.ALL.size():
		Synth.get_stream(Synth.ALL[_warm])
		_warm += 1

	var in_cockpit := in_cockpit_view()
	Sfx.in_cockpit = in_cockpit
	_cockpit_mix = move_toward(_cockpit_mix, 1.0 if in_cockpit else 0.0, delta * 4.0)
	_interior.cockpit_mix = _cockpit_mix
	var ambient_bus := Sfx.world_bus()
	_wind.bus = ambient_bus
	_rain.bus = ambient_bus

	# kabin filtresi: kanopi kapalı → boğuk ve kısık; açık → dış ses neredeyse olduğu gibi
	var canopy := InteriorAudio.canopy_amount(vessel) if is_instance_valid(vessel) else 0.0
	var lp := _cockpit_filter()
	if lp:
		lp.cutoff_hz = lerpf(COCKPIT_CUTOFF_CLOSED, COCKPIT_CUTOFF_OPEN, pow(canopy, 0.7))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_COCKPIT), lerpf(-6.0, -1.0, canopy))

	# Rüzgar ve yağmur
	var c: Dictionary = Weather.current
	var cam_pos := camera.global_position if is_instance_valid(camera) else Vector3.ZERO
	var alt := Planet.altitude(cam_pos)
	var wind_amt := clampf(Weather.wind_at(cam_pos).length() / 20.0, 0.0, 1.0) * (1.0 - smoothstep(3000.0, 8000.0, alt))
	_wind.volume_db = linear_to_db(maxf(wind_amt * 0.8, 0.0001)) - 6.0
	_wind.pitch_scale = 0.8 + wind_amt * 0.4
	var rain_amt := float(c["rain"]) * (1.0 - smoothstep(4000.0, 8000.0, alt))
	# kabinde yağmur kanopiye vurur: daha yakın ve gür
	_rain.volume_db = linear_to_db(maxf(rain_amt, 0.0001)) - 2.0 + _cockpit_mix * 6.0

	# Gök gürültüsü
	for i in range(_pending_thunder.size() - 1, -1, -1):
		_pending_thunder[i] -= delta
		if _pending_thunder[i] <= 0.0:
			_pending_thunder.remove_at(i)
			Sfx.play_ui("thunder_%d.ogg" % (1 + randi() % 3), randf_range(-4.0, 2.0), randf_range(0.85, 1.05))

	if _debug:
		_debug_t -= delta
		if _debug_t <= 0.0:
			_debug_t = 1.0 if Game.args.has("audiotest") else 2.0
			print(debug_report())
	if Game.args.has("audiotest"):
		_test_step(delta)


## Bir kaynak kendi uçağımızın kabin içinden mi duyuluyor? (VesselAudio motoru kısar)
static func cockpit_of(v: Vessel) -> float:
	if instance == null or instance.vessel != v:
		return 0.0
	return instance._cockpit_mix


## Kabinde hissedilen darbe (VesselAudio çağırır).
static func cockpit_impact(v: Vessel, strength: float) -> void:
	if instance and instance.vessel == v and instance._interior:
		instance._interior.impact(strength)


# ------------------------------------------------------------------ test / hata ayıklama

func debug_report() -> String:
	var lines := PackedStringArray()
	var mode := "?"
	if is_instance_valid(camera):
		mode = FlightCamera.MODE_NAMES[camera.mode]
	var lp := _cockpit_filter()
	lines.append("[SES] kamera=%s kokpit=%.2f kanopi=%.2f kabin_lp=%dHz kabin_db=%.1f" % [mode, _cockpit_mix,
		InteriorAudio.canopy_amount(vessel) if is_instance_valid(vessel) else 0.0, int(lp.cutoff_hz) if lp else 0,
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_COCKPIT))])
	if is_instance_valid(vessel):
		lines.append("[SES]  durum: hız=%.0f q=%.0f G=%.1f AoA=%.1f radar=%.0f vs=%.1f takım=%.2f" % [vessel.airspeed(),
			0.5 * vessel.air_density() * vessel.airspeed() * vessel.airspeed(), vessel.g_force, vessel.aoa_deg(),
			vessel.radar_altitude(), vessel.vertical_speed(), vessel.gear_deploy()])
		var va := vessel.get_node_or_null("Audio") as VesselAudio
		if va:
			lines.append("[SES]  dış: " + va.debug_layers())
	var parts := PackedStringArray()
	for k in _interior.last_mix:
		parts.append("%s=%.1fdB" % [k, linear_to_db(maxf(float(_interior.last_mix[k][0]), 0.0001))])
	lines.append("[SES]  iç: %s | nefes=%s zorlanma=%s toparlanma=%.1f" % [", ".join(parts) if not parts.is_empty() else "(sessiz)",
		"%.1fdB/x%.2f" % [_interior._breath.volume_db, _interior._breath.pitch_scale] if _interior._breath.playing else "yok",
		_interior.is_straining(), _interior.recovery()])
	lines.append("[SES]  uyarılar: %s (ton=%s, tts=%s)" % [", ".join(_warnings.active()) if not _warnings.active().is_empty() else "-",
		_warnings._tone_name if _warnings._tone.playing else "-", _warnings.enabled])
	return "\n".join(lines)


## Sentetik durumlar için karışım tablosu ve tüm sentez seslerinin üretimi.
func _self_test() -> void:
	var t0 := Time.get_ticks_msec()
	for k in Synth.ALL:
		var s := Synth.get_stream(k)
		var peak := 0
		for i in range(0, s.data.size(), 2):
			peak = maxi(peak, absi(s.data.decode_s16(i)))
		if s.data.size() < 100 or peak < 8000:
			push_error("[SES-TEST] sentez sesi boş/sessiz: %s (tepe %d)" % [k, peak])
	_warm = Synth.ALL.size()
	print("[SES-TEST] %d sentez sesi üretildi (%d ms)" % [Synth.ALL.size(), Time.get_ticks_msec() - t0])
	var cases := {
		"dış görünüm, 250 m/s": {"cockpit": 0.0, "q": 38000.0, "speed": 250.0, "n2": 0.9, "flame": 0.9},
		"kokpit, rölanti yerde": {"cockpit": 1.0, "q": 0.0, "speed": 0.0, "n2": 0.25, "flame": 0.2, "gear": 1.0},
		"kokpit, seyir 200 m/s": {"cockpit": 1.0, "q": 24000.0, "speed": 200.0, "n2": 0.85, "flame": 0.85},
		"kokpit, kanopi açık 60 m/s": {"cockpit": 1.0, "canopy": 1.0, "q": 2200.0, "speed": 60.0, "n2": 0.5, "flame": 0.5},
		"kokpit, stall yakını": {"cockpit": 1.0, "q": 6000.0, "speed": 100.0, "n2": 0.9, "flame": 0.9, "aoa": 17.0, "stalled": 1.0},
		"kokpit, takım+fren 120 m/s": {"cockpit": 1.0, "q": 8800.0, "speed": 120.0, "n2": 0.6, "flame": 0.6, "gear": 1.0, "airbrake": 1.0},
		"kokpit, afterburner M1.0": {"cockpit": 1.0, "q": 60000.0, "speed": 330.0, "mach": 1.0, "n2": 1.0, "flame": 1.0, "ab": 1.0},
	}
	for name in cases:
		var mix := InteriorAudio.compute_mix(cases[name])
		var parts := PackedStringArray()
		for k in mix:
			parts.append("%s=%.1fdB" % [k, linear_to_db(maxf(float(mix[k][0]), 0.0001))])
		print("[SES-TEST] %-28s %s" % [name, ", ".join(parts)])
	for g in [1.0, 3.0, 6.0]:
		for strain in [false, true]:
			var b := InteriorAudio.breath_mix(1.0, g, strain, 0.0)
			print("[SES-TEST] nefes G=%.0f zorlanma=%s → %.1fdB x%.2f" % [g, strain, linear_to_db(maxf(b[0], 0.0001)), b[1]])
	var rb := InteriorAudio.breath_mix(1.0, 1.0, false, 6.0)
	print("[SES-TEST] nefes toparlanma (G=1, 6 sn) → %.1fdB x%.2f" % [linear_to_db(rb[0]), rb[1]])
	print("[SES-TEST] dış görünümde nefes: %.1fdB" % linear_to_db(maxf(InteriorAudio.breath_mix(0.0, 6.0, false, 0.0)[0], 0.0001)))


## --audiotest: 4–14 sn takip, 14–26 sn kokpit (20. sn kanopi açılır), 26+ serbest kamera;
## uyarı tonları ve darbe sesleri birer kez çalınır.
func _test_step(delta: float) -> void:
	var before := _test_t
	_test_t += delta
	var at := func(t: float) -> bool: return before < t and _test_t >= t
	if not is_instance_valid(camera) or not is_instance_valid(vessel):
		return
	if at.call(4.0):
		camera.mode = FlightCamera.Mode.CHASE
		print("[SES-TEST] kamera → TAKİP")
	if at.call(14.0):
		camera.mode = FlightCamera.Mode.COCKPIT
		print("[SES-TEST] kamera → KOKPİT")
	if at.call(20.0) and vessel.cockpit():
		vessel.cockpit().canopy_open = true
		print("[SES-TEST] kanopi açıldı")
	if at.call(24.0) and vessel.cockpit():
		vessel.cockpit().canopy_open = false
	if at.call(16.0):
		for k in ["tone_pullup", "tone_stall", "tone_overg", "tone_fire", "tone_fuel", "tone_missile"]:
			Sfx.play_ui_stream(Synth.get_stream(k), -20.0)
		_interior.impact(0.3)
		_interior.impact(0.9)
		_interior._play_tick(true)
	if at.call(26.0):
		camera.mode = FlightCamera.Mode.ORBIT
		print("[SES-TEST] kamera → SERBEST")
	# uyarı önceliği: 34–40 sn STALL+BINGO, 37. sn PULL UP eklenir (PULL UP tonu öne geçmeli)
	if at.call(34.0):
		_warnings.forced = PackedStringArray(["STALL", "BINGO"])
	if at.call(37.0):
		_warnings.forced = PackedStringArray(["BINGO", "STALL", "PULL UP"])
	if at.call(40.0):
		_warnings.forced = PackedStringArray()
	# --audiotest=g: kokpitte 30–38 sn arası zorla burun kaldır (yüksek G → zorlanma iniltisi)
	# --audiotest=dive: 30. sn'de dik dalış (arazi yaklaşması → PULL UP)
	var kind := str(Game.args.get("audiotest", ""))
	if kind == "g" and _test_t > 30.0 and _test_t < 38.0:
		camera.mode = FlightCamera.Mode.COCKPIT
		vessel.angular_velocity = vessel.global_basis.x * 0.42
	if kind == "dive" and _test_t > 30.0 and _test_t < 32.5:
		camera.mode = FlightCamera.Mode.COCKPIT
		vessel.angular_velocity = vessel.global_basis.x * -0.3


# ------------------------------------------------------------------ patlama sersemlemesi

var _stun := 0.0
var _ring: AudioStreamPlayer
static var _ring_stream: AudioStreamWAV


## Yakın patlama: kulak çınlar, dış sesler birkaç saniye boğuk gelir. k: 0..1 şiddet.
func stun(k: float) -> void:
	if k < 0.08:
		return
	_stun = clampf(maxf(_stun, k), 0.0, 1.0)
	if _ring == null:
		_ring = AudioStreamPlayer.new()
		_ring.stream = _tinnitus()
		_ring.bus = Sfx.BUS_UI
		add_child(_ring)
	_ring.volume_db = linear_to_db(clampf(k, 0.05, 1.0)) - 14.0
	_ring.play()


## Kulak çınlaması: 3.9 kHz saf ton, yavaşça söner (kodla üretilir).
static func _tinnitus() -> AudioStreamWAV:
	if _ring_stream:
		return _ring_stream
	var rate := 44100
	var n := rate * 4
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := smoothstep(0.0, 0.05, t) * exp(-t / 1.3)
		var s := sin(TAU * 3900.0 * t) * 0.6 + sin(TAU * 4170.0 * t) * 0.15
		data.encode_s16(i * 2, int(s * env * 26000.0))
	_ring_stream = AudioStreamWAV.new()
	_ring_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_ring_stream.mix_rate = rate
	_ring_stream.data = data
	return _ring_stream


## Bir patlamanın kameraya etkisi (Damage.explosion çağırır).
static func near_blast(pos: Vector3, radius: float) -> void:
	if instance == null or not is_instance_valid(instance.camera):
		return
	var d := instance.camera.global_position.distance_to(pos)
	var reach := radius * 6.0
	if d < reach:
		instance.stun((1.0 - d / reach) * clampf(radius / 12.0, 0.4, 1.4))


func _physics_process(delta: float) -> void:
	_stun = move_toward(_stun, 0.0, delta / 3.0)
	var cutoff := lerpf(20000.0, 350.0, pow(_stun, 0.6))
	for f in _stun_filters:
		(f as AudioEffectLowPassFilter).cutoff_hz = cutoff
