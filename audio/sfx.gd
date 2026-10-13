class_name Sfx
## Ses kaynakları ve tek seferlik ses çalma yardımcıları.
## Tüm sesler CC0 (bkz. audio/CREDITS.md) veya ffmpeg ile sentezlendi.

const DIR := "res://audio/sfx/"
const BUS_WORLD := "World"
const BUS_COCKPIT := "Cockpit"
const BUS_UI := "UI"

## Kokpit görünümündeyken dış sesler boğuk kabin kanalına gider (AudioManager yazar).
static var in_cockpit := false
static var _cache := {}


static func stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var s: AudioStream = load(DIR + name)
		_cache[name] = s
	return _cache[name]


static func looped(name: String) -> AudioStream:
	var s := stream(name).duplicate() as AudioStream
	if s is AudioStreamOggVorbis:
		s.loop = true
	elif s is AudioStreamMP3:
		s.loop = true
	return s


static func world_bus() -> String:
	return BUS_COCKPIT if in_cockpit else BUS_WORLD


## Dünyada bir noktada tek seferlik 3B ses.
static func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 3000.0) -> void:
	var root := FloatingOrigin.world_root
	if root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 15.0
	p.max_distance = max_distance
	p.bus = world_bus()
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.position = pos   # dünya kökü hep orijinde (çocukları kayar), konum doğrudan verilir
	p.autoplay = true
	root.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)


## 2B arayüz / kokpit içi tek seferlik ses.
static func play_ui(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = BUS_UI
	p.autoplay = true
	tree.root.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)


## Hazır bir akışı (ör. Synth sesi) 2B tek seferlik çal.
static func play_ui_stream(s: AudioStream, volume_db := 0.0, pitch := 1.0, bus := BUS_UI) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	p.autoplay = true
	tree.root.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)


## Hazır bir akışı dünyada bir noktada 3B tek seferlik çal.
static func play_stream_at(s: AudioStream, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 2000.0) -> void:
	var root := FloatingOrigin.world_root
	if root == null or s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 15.0
	p.max_distance = max_distance
	p.bus = world_bus()
	p.attenuation_filter_cutoff_hz = 4000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.position = pos
	p.autoplay = true
	root.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)


static func click() -> void:
	play_ui("switch_%d.ogg" % (2 + randi() % 3), -6.0, randf_range(0.95, 1.08))


static func explosion(pos: Vector3, size: float) -> void:
	var name: String = ["explosion_1.ogg", "explosion_2.ogg"][randi() % 2]
	play_at(name, pos, linear_to_db(clampf(size, 0.5, 3.0) / 2.0) + 6.0, randf_range(0.8, 1.0), 6000.0)
	play_at("explosion_crunch.ogg", pos, -2.0, randf_range(0.85, 1.1), 2500.0)


static func splash(pos: Vector3, size: float) -> void:
	play_at("splash.ogg", pos, linear_to_db(clampf(size, 0.4, 3.5) / 2.0) + 4.0, randf_range(0.75, 1.1), 2500.0)


static var _creaks: Array[AudioStreamWAV] = []
static var _crack: AudioStreamWAV


## Yük altında metal gıcırtısı: sürtünme-kayma ("stick-slip") darbeleri, gövdenin iki rezonansını
## (alçak inilti + metalik tını) uyarır; darbe sıklığı yavaşça kayar. Üç çeşit (tekrar duyulmasın).
static func creak_stream(i: int) -> AudioStreamWAV:
	while _creaks.size() < 3:
		var k := _creaks.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7100 + k * 31
		var rate := 22050
		var dur := 0.55 + 0.2 * k
		var n := int(rate * dur)
		var data := PackedByteArray()
		data.resize(n * 2)
		var res := [[190.0 + 40.0 * k, 0.9965, 1.0], [520.0 + 90.0 * k, 0.9975, 0.55], [1350.0, 0.996, 0.18]]
		var st: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]   # rezonatör durumları (y1, y2)
		var phase := 0.0
		var f0 := rng.randf_range(28.0, 45.0)
		var f1 := rng.randf_range(60.0, 110.0)
		for j in n:
			var t := float(j) / rate
			var u := t / dur
			var env := sin(PI * u) * (0.6 + 0.4 * sin(u * 17.0 + k))
			phase += lerpf(f0, f1, u) * (1.0 + rng.randf_range(-0.25, 0.25)) / rate
			var x := 0.0
			if phase >= 1.0:
				phase -= 1.0
				x = env * rng.randf_range(0.6, 1.0)
			var s := 0.0
			for r in 3:
				var w: float = TAU * float(res[r][0]) / rate
				var R: float = res[r][1]
				var y := 2.0 * R * cos(w) * st[r].x - R * R * st[r].y + x
				st[r] = Vector2(y, st[r].x)
				s += y * float(res[r][2])
			data.encode_s16(j * 2, clampi(int(clampf(s * 0.05, -1.0, 1.0) * 30000.0), -32768, 32767))
		var w2 := AudioStreamWAV.new()
		w2.format = AudioStreamWAV.FORMAT_16_BITS
		w2.mix_rate = rate
		w2.data = data
		_creaks.append(w2)
	return _creaks[i % 3]


## Perçin / kiriş çatlaması: sert tık + kısa gürültü patlaması + çınlayan iki yüksek rezonans.
static func crack_stream() -> AudioStreamWAV:
	if _crack:
		return _crack
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var rate := 22050
	var n := int(rate * 0.3)
	var data := PackedByteArray()
	data.resize(n * 2)
	var res := [[1250.0, 0.9985, 1.0], [2900.0, 0.998, 0.6], [430.0, 0.997, 0.8]]
	var st: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for j in n:
		var t := float(j) / rate
		var x := (1.0 if j == 0 else 0.0) + rng.randf_range(-1.0, 1.0) * exp(-t / 0.004) * 0.8
		var s := x * 0.5
		for r in 3:
			var w: float = TAU * float(res[r][0]) / rate
			var R: float = res[r][1]
			var y := 2.0 * R * cos(w) * st[r].x - R * R * st[r].y + x
			st[r] = Vector2(y, st[r].x)
			s += y * float(res[r][2]) * 0.08
		data.encode_s16(j * 2, clampi(int(clampf(s, -1.0, 1.0) * 30000.0), -32768, 32767))
	_crack = AudioStreamWAV.new()
	_crack.format = AudioStreamWAV.FORMAT_16_BITS
	_crack.mix_rate = rate
	_crack.data = data
	return _crack


static var _boom: AudioStreamWAV


## Ses duvarı patlaması: gerçekteki gibi çift "N-dalgası" (burun ve kuyruk şoku, ~0.13 sn
## arayla iki sert çatlama) ve ardından alçak frekanslı gürleme. Kodla sentezlenir.
static func sonic_boom_stream() -> AudioStreamWAV:
	if _boom:
		return _boom
	var rate := 44100
	var n := int(rate * 2.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947
	var lp_noise := 0.0
	var lp_out := 0.0
	var T := 0.085
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for start in [0.0, 0.13]:
			var u: float = t - start
			if u >= 0.0 and u < T:
				s += (1.0 - 2.0 * u / T) * 0.9
		# gürleme: alçak geçirgen gürültü, yavaş söner
		lp_noise += (rng.randf_range(-1.0, 1.0) - lp_noise) * 0.018
		s += lp_noise * 5.0 * exp(-t / 0.55) * smoothstep(0.0, 0.03, t)
		# yumuşatma (dijital sertliği al)
		lp_out += (s - lp_out) * 0.35
		var v := clampi(int(clampf(lp_out * 0.75, -1.0, 1.0) * 32000.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	_boom = AudioStreamWAV.new()
	_boom.format = AudioStreamWAV.FORMAT_16_BITS
	_boom.mix_rate = rate
	_boom.stereo = false
	_boom.data = data
	return _boom


## Ses duvarı patlamasını bir noktada çal (uzaktan da duyulur).
static func sonic_boom(pos: Vector3, volume_db := 6.0) -> void:
	var root := FloatingOrigin.world_root
	if root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = sonic_boom_stream()
	p.volume_db = volume_db
	p.unit_size = 60.0
	p.max_distance = 15000.0
	p.bus = world_bus()
	p.position = pos
	p.autoplay = true
	root.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)
