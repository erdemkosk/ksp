class_name AudioManager
extends Node
## Ses kanalları ve ortam sesleri.
##   World   — dış dünya sesleri
##   Cockpit — kokpit görünümünde dış sesler: alçak geçiren filtre + küçük kabin yankısı
##   UI      — düğmeler, uyarı bipleri
## Ortam: rüzgar, yağmur, gök gürültüsü (şimşekten sonra mesafeye göre gecikmeli),
## kokpitte pilotun oksijen maskesi nefesi (yüksek G'de hızlanır), sesli uyarılar.

const BREATHING := "res://audio/sfx/breathing.mp3"

static var instance: AudioManager
static var _stun_filters: Array = []

var camera: FlightCamera
var player: PlayerController
var vessel: Vessel:
	set(v):
		vessel = v
		if _warnings:
			_warnings.vessel = v

var _breath: AudioStreamPlayer
var _breath_volume := 0.0
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _warnings: WarningVoice
var _cockpit_mix := 0.0
var _pending_thunder: Array[float] = []


func _ready() -> void:
	instance = self
	_setup_buses()
	_breath = AudioStreamPlayer.new()
	var stream: AudioStream = load(BREATHING)
	if stream is AudioStreamMP3:
		stream.loop = true
	_breath.stream = stream
	_breath.volume_db = -80.0
	_breath.bus = Sfx.BUS_UI
	add_child(_breath)

	_wind = _ambient("wind.ogg")
	_rain = _ambient("rain.ogg")
	_warnings = WarningVoice.new()
	_warnings.vessel = vessel
	add_child(_warnings)


func _ambient(file: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.looped(file)
	p.volume_db = -80.0
	p.bus = Sfx.BUS_WORLD
	add_child(p)
	p.play()
	return p


func _setup_buses() -> void:
	if AudioServer.get_bus_index(Sfx.BUS_WORLD) != -1:
		return
	for name in [Sfx.BUS_WORLD, Sfx.BUS_COCKPIT, Sfx.BUS_UI]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	var cp := AudioServer.get_bus_index(Sfx.BUS_COCKPIT)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 1300.0
	lp.resonance = 0.6
	AudioServer.add_bus_effect(cp, lp)
	var room := AudioEffectReverb.new()
	room.room_size = 0.08
	room.damping = 0.8
	room.wet = 0.12
	room.dry = 1.0
	AudioServer.add_bus_effect(cp, room)
	AudioServer.set_bus_volume_db(cp, -3.0)
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


## Şimşek çaktı: gök gürültüsü 1–5 sn sonra gelir.
func thunder() -> void:
	_pending_thunder.append(randf_range(1.0, 5.0))


func _process(delta: float) -> void:
	var in_cockpit := is_instance_valid(camera) and is_instance_valid(vessel) \
		and camera.mode == FlightCamera.Mode.COCKPIT and not camera.is_eva() and vessel.has_pilot()
	Sfx.in_cockpit = in_cockpit
	_cockpit_mix = move_toward(_cockpit_mix, 1.0 if in_cockpit else 0.0, delta * 4.0)
	var ambient_bus := Sfx.world_bus()
	_wind.bus = ambient_bus
	_rain.bus = ambient_bus

	# Rüzgar ve yağmur
	var c: Dictionary = Weather.current
	var cam_pos := camera.global_position if is_instance_valid(camera) else Vector3.ZERO
	var alt := Planet.altitude(cam_pos)
	var wind_amt := clampf(Weather.wind_at(cam_pos).length() / 20.0, 0.0, 1.0) * (1.0 - smoothstep(3000.0, 8000.0, alt))
	_wind.volume_db = linear_to_db(maxf(wind_amt * 0.8, 0.0001)) - 6.0
	_wind.pitch_scale = 0.8 + wind_amt * 0.4
	var rain_amt := float(c["rain"]) * (1.0 - smoothstep(4000.0, 8000.0, alt))
	_rain.volume_db = linear_to_db(maxf(rain_amt, 0.0001)) - 2.0 + _cockpit_mix * 4.0

	# Gök gürültüsü
	for i in range(_pending_thunder.size() - 1, -1, -1):
		_pending_thunder[i] -= delta
		if _pending_thunder[i] <= 0.0:
			_pending_thunder.remove_at(i)
			Sfx.play_ui("thunder_%d.ogg" % (1 + randi() % 3), randf_range(-4.0, 2.0), randf_range(0.85, 1.05))

	_update_breathing(delta, in_cockpit)


func _update_breathing(delta: float, in_cockpit: bool) -> void:
	# G yükünde zorlanan nefes her görünümde duyulur (pilot bayılmak üzere)
	var strain_p: float = player.g_strain if player else 0.0
	var want := 1.0 if in_cockpit else clampf((strain_p - 0.15) * 2.0, 0.0, 1.0)
	_breath_volume = move_toward(_breath_volume, want, delta * 2.0)
	if _breath_volume <= 0.0:
		if _breath.playing:
			_breath.stop()
		return
	if not _breath.playing:
		_breath.play()
	var g := absf(vessel.g_force)
	var strain := maxf(clampf((g - 1.5) / 6.0, 0.0, 1.0), clampf(strain_p, 0.0, 1.0))
	_breath.pitch_scale = lerpf(1.0, 1.35, strain)
	_breath.volume_db = linear_to_db(_breath_volume * lerpf(0.45, 0.9, strain))


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
