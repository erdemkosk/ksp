class_name InteriorAudio
extends Node
## Oyuncu uçağının kabin içi sesleri (yalnız kokpit görünümünde):
##   gövde uğultusu (motor titreşimi + hava akışı), rüzgar hışırtısı (dinamik basınçla,
##   kanopi açıkken çok daha gür), stall / ses hızı titremesi, iniş takımı + hava freni
##   gürültüsü, pilotun nefesi (G ile hızlanır), 5 G üstü anti-G zorlanma iniltisi
##   (L-1: "nnngh" + "hık"), zorlanmadan sonra ağır nefes ve kendi uçağımıza mermi
##   isabetinde metal tıkırtıları. Katmanlar "Interior" kanalında çalar (alçak geçiren yok).
## Karışım saf bir fonksiyondur (compute_mix): test argümanı --audiotest bunu yazdırır.

const BREATHING := "res://audio/sfx/breathing.mp3"
const STRAIN_ON := 5.0       ## bu G'nin üstünde pilot zorlanma manevrası yapar
const STRAIN_OFF := 4.4

var vessel: Vessel
var player: PlayerController
var cockpit_mix := 0.0       ## AudioManager yazar (0 dış görünüm, 1 kokpit)

var _layers := {}            ## ad -> AudioStreamPlayer
var _breath: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _tick: AudioStreamPlayer
var _straining := false
var _strain_time := 0.0
var _recovery := 0.0         ## zorlanmadan sonra ağır nefes süresi (s)
var _voice_gap := 0.0
var _release_next := false
var _hits_prev := 0
var _hp_prev := -1.0
var _tick_cd := 0.0
var last_mix := {}           ## hata ayıklama: son hesaplanan katmanlar


func _ready() -> void:
	for k in ["rumble", "hiss", "wind_low", "buffet", "drag_rumble"]:
		var p := AudioStreamPlayer.new()
		p.stream = Synth.get_stream(k)
		p.bus = AudioManager.BUS_INTERIOR
		p.volume_db = -80.0
		add_child(p)
		_layers[k] = p
	_breath = AudioStreamPlayer.new()
	var stream: AudioStream = load(BREATHING)
	if stream is AudioStreamMP3:
		stream = stream.duplicate()
		stream.loop = true
	_breath.stream = stream
	_breath.volume_db = -80.0
	_breath.bus = AudioManager.BUS_INTERIOR
	add_child(_breath)
	_voice = AudioStreamPlayer.new()
	_voice.bus = AudioManager.BUS_INTERIOR
	add_child(_voice)
	_tick = AudioStreamPlayer.new()
	_tick.bus = AudioManager.BUS_INTERIOR
	_tick.max_polyphony = 4
	add_child(_tick)


## Uçak durumundan karışım girdileri.
func gather_state() -> Dictionary:
	var v := vessel
	var speed := v.airspeed()
	var n2 := 0.0
	var flame := 0.0
	var ab := 0.0
	for m in v.modules:
		if m is EngineModule:
			n2 = maxf(n2, m.n2)
			flame = maxf(flame, m.flame_level())
			ab = maxf(ab, m.afterburner)
	var stalled := 0.0
	var brake := 0.0
	for m in v.modules:
		if m is WingModule and m.stalled:
			stalled = 1.0
		elif m is AirbrakeModule:
			brake = maxf(brake, m.deploy)
	var c := v.cockpit()
	var grounded := v.radar_altitude() < 3.0
	return {
		"cockpit": cockpit_mix,
		"canopy": canopy_amount(v),
		"q": 0.5 * v.air_density() * speed * speed,
		"speed": speed,
		"mach": v.mach(),
		"n2": n2, "flame": flame, "ab": ab,
		"aoa": absf(v.aoa_deg()) if speed > 5.0 else 0.0,
		"stalled": 0.0 if grounded else stalled,
		"gear": v.gear_deploy(),
		"airbrake": brake,
	}


## Kanopinin açıklığı 0..1 (animasyon değeri varsa onu, yoksa komutu kullanır).
static func canopy_amount(v: Vessel) -> float:
	var c := v.cockpit()
	if c == null:
		return 0.0
	var t: Variant = c.get("_canopy_t")
	if t is float:
		return t
	return 1.0 if c.canopy_open else 0.0


## Saf karışım: durum → {katman: [doğrusal ses, perde]}.
static func compute_mix(s: Dictionary) -> Dictionary:
	var c: float = s.get("cockpit", 0.0)
	var canopy: float = s.get("canopy", 0.0)
	var qn := clampf(float(s.get("q", 0.0)) / 40000.0, 0.0, 1.5)
	var q1 := minf(qn, 1.0)
	var speed: float = s.get("speed", 0.0)
	var n2: float = s.get("n2", 0.0)
	var flame: float = s.get("flame", 0.0)
	var ab: float = s.get("ab", 0.0)
	var aoa: float = s.get("aoa", 0.0)
	var mach: float = s.get("mach", 0.0)
	var out := {}
	# rüzgar hışırtısı: kanopi kapalıyken ince ve kısık; açıkken gür ve pürüzlü
	out["hiss"] = [c * (0.06 + 0.5 * sqrt(q1)) * (1.0 + 2.5 * canopy), 0.8 + 0.35 * q1 - 0.1 * canopy]
	out["wind_low"] = [c * (0.18 * q1 + canopy * clampf(qn * 1.6 + speed / 120.0, 0.0, 1.3)), 0.75 + 0.35 * q1]
	# gövde uğultusu: motor titreşimi (yanma + afterburner) ve hava akışının gövdeye vuruşu
	var eng := (0.12 + 0.4 * flame + 0.4 * ab) * smoothstep(0.03, 0.2, n2)
	out["rumble"] = [c * clampf(eng + 0.22 * q1, 0.0, 1.0), 0.65 + 0.45 * n2 + 0.15 * ab]
	# titreşim: stall yakını hücum açısı, ses hızı geçişi
	var b := clampf((aoa - 11.0) / 7.0, 0.0, 1.0) * clampf(speed / 60.0, 0.0, 1.0)
	b = maxf(b, float(s.get("stalled", 0.0)) * 0.8 * clampf(speed / 50.0, 0.0, 1.0))
	b = maxf(b, clampf(1.0 - absf(mach - 1.0) / 0.07, 0.0, 1.0) * 0.5)
	out["buffet"] = [c * b, 0.85 + 0.25 * q1]
	# iniş takımı ve hava freni açıkken hava akışı gürültüsü
	var drag := clampf(qn * 2.2, 0.0, 1.0) * (0.55 * float(s.get("gear", 0.0)) + 0.85 * float(s.get("airbrake", 0.0)))
	out["drag_rumble"] = [c * drag, 0.8 + 0.3 * q1]
	return out


## Pilotun nefes katmanı: [mp3 ses, mp3 perde]; zorlanırken nefes tutulur (0).
static func breath_mix(c: float, g: float, straining: bool, recovery: float) -> Array:
	if straining:
		return [0.0, 1.0]
	var exert := clampf((absf(g) - 1.5) / 3.5, 0.0, 1.0)
	var rec := clampf(recovery / 6.0, 0.0, 1.0)
	var vol := lerpf(0.4, 0.75, exert)
	vol = maxf(vol, lerpf(vol, 1.0, rec))
	var pitch := maxf(lerpf(1.0, 1.3, exert), lerpf(1.0, 1.5, rec))
	return [c * vol, pitch]


func _process(delta: float) -> void:
	var ok := is_instance_valid(vessel) and not vessel.parts.is_empty() and vessel.has_pilot()
	var c := cockpit_mix if ok else 0.0
	if c <= 0.001:
		for p: AudioStreamPlayer in _layers.values():
			if p.playing:
				p.stop()
		if _breath.playing:
			_breath.stop()
		_straining = false
		_recovery = 0.0
		last_mix = {}
		_track_hits(ok, false)
		return
	var mix := compute_mix(gather_state())
	last_mix = mix
	for k in mix:
		var p: AudioStreamPlayer = _layers[k]
		var lin: float = mix[k][0]
		p.volume_db = linear_to_db(maxf(lin, 0.0001))
		p.pitch_scale = clampf(mix[k][1], 0.3, 3.0)
		if lin > 0.002 and not p.playing:
			p.play(randf() * 1.5)
		elif lin <= 0.002 and p.playing:
			p.stop()
	_pilot(delta, c)
	_track_hits(ok, true)


# ------------------------------------------------------------------ pilot

func _pilot(delta: float, c: float) -> void:
	var g := vessel.g_force
	var strain_p: float = player.g_strain if is_instance_valid(player) else 0.0
	var blackout: bool = player.blackout if is_instance_valid(player) else false
	_voice_gap -= delta
	if blackout:
		# bayıldı: ses yok
		_straining = false
		_breath.volume_db = -80.0
		return
	var want := g > STRAIN_ON or (g > 3.5 and strain_p > 0.5)
	if _straining and g < STRAIN_OFF and strain_p < 0.4:
		_straining = false
		_recovery = clampf(_strain_time * 1.5, 3.0, 10.0)
	elif not _straining and want:
		_straining = true
		_strain_time = 0.0
		_release_next = false
	if _straining:
		_strain_time += delta
		# L-1 döngüsü: ~3 sn zorlanma, araya hızlı "hık" + nefes
		if not _voice.playing and _voice_gap <= 0.0:
			var key := ("release_%d" if _release_next else "strain_%d") % (randi() % 2)
			_voice.stream = Synth.get_stream(key)
			var hard := clampf((g - STRAIN_ON) / 4.0, 0.0, 1.0)
			_voice.volume_db = linear_to_db(c * lerpf(0.55, 0.9, hard))
			_voice.pitch_scale = randf_range(0.95, 1.05) + 0.06 * hard
			_voice.play()
			_voice_gap = 0.05
			_release_next = not _release_next
	else:
		_recovery = maxf(_recovery - delta, 0.0)
	var b := breath_mix(c, g, _straining, _recovery)
	var lin: float = b[0]
	_breath.volume_db = linear_to_db(maxf(lin, 0.0001))
	_breath.pitch_scale = b[1]
	if lin > 0.002 and not _breath.playing:
		_breath.play(randf() * 3.0)


func is_straining() -> bool:
	return _straining


func recovery() -> float:
	return _recovery


# ------------------------------------------------------------------ isabetler

## Bize isabet eden mermi: toplam parça canı düştü ve mermi sayacı arttı → metal "tınk".
func _track_hits(ok: bool, in_cockpit: bool) -> void:
	_tick_cd -= get_process_delta_time()
	var hits := Damage.vessel_hits
	var hp := 0.0
	if ok:
		for p in vessel.parts:
			if is_instance_valid(p):
				hp += p.hp
	if ok and _hp_prev >= 0.0 and hits > _hits_prev and hp < _hp_prev - 0.01 and _tick_cd <= 0.0:
		var n := mini(hits - _hits_prev, 3)
		for i in n:
			get_tree().create_timer(i * randf_range(0.03, 0.07)).timeout.connect(_play_tick.bind(in_cockpit))
		_tick_cd = 0.04
	_hits_prev = hits
	_hp_prev = hp if ok else -1.0


func _play_tick(in_cockpit: bool) -> void:
	if not is_instance_valid(_tick):
		return
	_tick.stream = Synth.get_stream("tick_%d" % (randi() % 3))
	_tick.volume_db = (0.0 if in_cockpit else -9.0) + randf_range(-3.0, 0.0)
	_tick.pitch_scale = randf_range(0.85, 1.2)
	_tick.play()


## Kabinde hissedilen darbe (VesselAudio çağırır): sert iniş, çarpma, parça kopması.
func impact(strength: float) -> void:
	if cockpit_mix < 0.05 or not is_instance_valid(vessel):
		return
	var p := AudioStreamPlayer.new()
	p.stream = Synth.get_stream("thud" if strength < 0.5 else "crunch_%d" % (randi() % 3))
	p.bus = AudioManager.BUS_INTERIOR
	p.volume_db = linear_to_db(clampf(strength, 0.15, 1.0) * cockpit_mix) + 2.0
	p.pitch_scale = randf_range(0.8, 1.0)
	p.autoplay = true
	add_child(p)
	p.finished.connect(p.queue_free)
