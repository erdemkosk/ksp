class_name Synth
## Kodla üretilen sesler (dosya yok): rüzgar hışırtısı, gövde uğultusu, titreşim (buffet),
## sürtünme, çatırtı, metal tıkırtısı, gövde gıcırtısı, pilotun G-zorlanma iniltisi ve
## uyarı tonları. Her ses ilk istekte bir kez üretilir ve önbellekte tutulur.
## Döngüler uçları çapraz karıştırılarak kesintisiz yapılır.

const RATE := 22050

static var _cache := {}

## Isınma listesi: AudioManager bunları kare kare üretir (uçuşta takılma olmasın).
const ALL := ["rumble", "hiss", "wind_low", "buffet", "drag_rumble", "scrape",
	"tick_0", "tick_1", "tick_2", "crunch_0", "crunch_1", "crunch_2", "thud", "creak_0", "creak_1",
	"strain_0", "strain_1", "release_0", "release_1",
	"tone_pullup", "tone_stall", "tone_overg", "tone_fire", "tone_fuel", "tone_missile",
	"tone_lock", "tone_caution", "tone_altitude"]


static func get_stream(key: String) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var s := _make(key)
	_cache[key] = s
	return s


static func is_ready(key: String) -> bool:
	return _cache.has(key)


static func _make(key: String) -> AudioStreamWAV:
	# "crunch_2" → tür "crunch", çeşit 2
	var base := key
	var idx := 0
	var us := key.rfind("_")
	if us > 0 and key.substr(us + 1).is_valid_int():
		base = key.substr(0, us)
		idx = int(key.substr(us + 1))
	match base:
		"rumble": return _noise_loop(3.0, 0.018, 0.004, 0.0, 11)
		"hiss": return _noise_loop(2.5, 0.55, 0.12, 0.0, 12)
		"wind_low": return _noise_loop(3.0, 0.08, 0.01, 0.35, 13)
		"drag_rumble": return _noise_loop(2.0, 0.035, 0.006, 0.6, 14)
		"buffet": return _buffet()
		"scrape": return _scrape()
		"tick": return _tick(idx)
		"crunch": return _crunch(idx)
		"thud": return _thud()
		"creak": return _creak(idx)
		"strain": return _strain(idx)
		"release": return _release(idx)
		"tone_pullup": return _tone_pullup()
		"tone_stall": return _tone_stall()
		"tone_overg": return _beeps([1500.0, 1500.0, 1500.0], 0.08, 0.06)
		"tone_fire": return _bell()
		"tone_fuel": return _chime([880.0, 660.0])
		"tone_missile": return _warble()
		"tone_lock": return _beeps([1000.0, 1000.0], 0.14, 0.1)
		"tone_caution": return _chime([720.0])
		"tone_altitude": return _beeps([700.0, 520.0], 0.18, 0.06)
	push_warning("Synth: bilinmeyen ses " + key)
	return _to_wav(PackedFloat32Array([0.0]), false)


# ------------------------------------------------------------------ yardımcılar

## Ham örneklerden 16 bit WAV (tepe 0.9'a normalize).
static func _to_wav(buf: PackedFloat32Array, loop: bool, peak := 0.9) -> AudioStreamWAV:
	var m := 0.0001
	for x in buf:
		m = maxf(m, absf(x))
	var k := peak / m
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, clampi(int(buf[i] * k * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


## n + f örnekten n örneklik kesintisiz döngü: kuyruk başa eşit güçle karıştırılır.
static func _seamless(a: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var f := a.size() - n
	var out := a.slice(0, n)
	for i in f:
		var t := float(i) / f
		out[i] = a[i] * sqrt(t) + a[n + i] * sqrt(1.0 - t)
	return out


## Filtreli gürültü döngüsü. lp: tek kutuplu alçak geçiren katsayısı (0..1, büyük = parlak),
## hp: yüksek geçiren (DC/çok alçak kesim) katsayısı, wobble: yavaş genlik dalgalanması.
static func _noise_loop(seconds: float, lp: float, hp: float, wobble: float, seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := int(seconds * RATE)
	var fade := RATE / 4
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var y := 0.0
	var y2 := 0.0
	var low := 0.0
	var wob := 1.0
	var wob_t := 1.0
	for i in buf.size():
		var x := rng.randf_range(-1.0, 1.0)
		y += (x - y) * lp
		y2 += (y - y2) * lp      # iki kutup: daha yumuşak eğim
		low += (y2 - low) * hp
		if i % 2205 == 0:
			wob_t = 1.0 - rng.randf() * wobble
		wob += (wob_t - wob) * 0.0008
		buf[i] = (y2 - low) * wob
	return _to_wav(_seamless(buf, n), true, 0.8)


## Stall titremesi: alçak gürültü + düzensiz 7–13 Hz gövde darbeleri.
static func _buffet() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var n := RATE * 2
	var buf := PackedFloat32Array()
	buf.resize(n)
	var y := 0.0
	var y2 := 0.0
	var env := 0.0
	var next := 0
	var amp := 1.0
	for i in n:
		if i >= next and i < n - RATE / 20:
			next = i + int(RATE / rng.randf_range(7.0, 13.0))
			amp = rng.randf_range(0.4, 1.0)
			env = amp
		env *= 0.9975
		var x := rng.randf_range(-1.0, 1.0)
		y += (x - y) * 0.03
		y2 += (y - y2) * 0.03
		buf[i] = y2 * (0.25 + env)
	# uçlar: son darbe sönmüş olur, başa kısa yumuşatma
	for i in 400:
		buf[i] *= float(i) / 400.0
		buf[n - 1 - i] *= float(i) / 400.0
	return _to_wav(buf, true, 0.85)


## Gövde zemine sürtünüyor: parlak bant gürültüsü + rastgele cızırtı taneleri + hafif ötüş.
static func _scrape() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var n := RATE * 2
	var fade := RATE / 5
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var y := 0.0
	var low := 0.0
	var grain := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		y += (x - y) * 0.35
		low += (y - low) * 0.08
		if rng.randf() < 0.004:
			grain = rng.randf_range(0.5, 1.5)
		grain *= 0.996
		var squeal := sin(TAU * (1650.0 * t + 6.0 * sin(TAU * 3.0 * t))) * 0.12
		buf[i] = (y - low) * (0.5 + grain) + squeal * (0.5 + 0.5 * sin(TAU * 0.7 * t))
	return _to_wav(_seamless(buf, n), true, 0.8)


## Mermi isabeti (kokpitten): kısa, sert, armonik olmayan metal "tınk".
static func _tick(v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 + v
	var n := int(RATE * 0.16)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var base: float = [2650.0, 3100.0, 2300.0][v % 3]
	var parts := [[1.0, 1.0], [1.58, 0.6], [2.31, 0.45], [3.17, 0.3]]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p in parts:
			s += sin(TAU * base * float(p[0]) * t) * float(p[1]) * exp(-t * (40.0 + 25.0 * float(p[0])))
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 900.0) * 1.6
		var knock := sin(TAU * 180.0 * t) * exp(-t * 60.0) * 0.7
		buf[i] = s + click + knock
	return _to_wav(buf, false)


## Çatırtı / ezilme: alçak darbe + parçalanan metal taneleri (3 çeşit).
static func _crunch(v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51 + v * 7
	var len_s := 0.7 + 0.15 * v
	var n := int(RATE * len_s)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var y := 0.0
	var grain := 0.0
	var ring_f := rng.randf_range(380.0, 620.0)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * (5.0 + 2.0 * v))
		if rng.randf() < 0.012 * env + 0.001:
			grain = rng.randf_range(0.6, 1.4)
		grain *= 0.993
		var x := rng.randf_range(-1.0, 1.0)
		y += (x - y) * (0.25 + 0.4 * env)
		var thump := sin(TAU * (70.0 - 30.0 * t) * t) * exp(-t * 14.0) * 1.8
		var ring := sin(TAU * ring_f * t + 3.0 * sin(TAU * 37.0 * t)) * exp(-t * 9.0) * 0.25
		buf[i] = y * (0.4 * env + grain * env) * 1.4 + thump + ring
	return _to_wav(buf, false)


## Sert iniş / takım dibe vurma: kalın gümbürtü.
static func _thud() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var n := int(RATE * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.06
		buf[i] = sin(TAU * (55.0 - 25.0 * t) * t) * exp(-t * 10.0) * 1.5 + y * exp(-t * 18.0) * 2.0 \
			+ sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.15
	return _to_wav(buf, false)


## Gövde gıcırtısı (aşırı yükte): yapış-kay darbe dizisi rezonanstan geçer.
static func _creak(v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71 + v
	var n := int(RATE * 0.9)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var f0 := 35.0 + 15.0 * v
	var r1 := _Reso.new(320.0 + 90.0 * v, 0.995)
	var r2 := _Reso.new(1150.0 + 200.0 * v, 0.99)
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / 0.9)
		var rate := f0 * (1.0 + 0.6 * sin(TAU * 1.3 * t + v)) + rng.randf_range(-6.0, 6.0)
		phase += rate / RATE
		var pulse := 0.0
		if phase >= 1.0:
			phase -= 1.0
			pulse = rng.randf_range(0.6, 1.0)
		buf[i] = (r1.step(pulse) + r2.step(pulse) * 0.4) * env
	return _to_wav(buf, false, 0.8)


# ------------------------------------------------------------------ pilot sesi

## İki kutuplu rezonatör (formant / gövde modu).
class _Reso:
	var a1: float
	var a2: float
	var g: float
	var y1 := 0.0
	var y2 := 0.0

	func _init(freq: float, r: float) -> void:
		a1 = 2.0 * r * cos(TAU * freq / Synth.RATE)
		a2 = -r * r
		g = 1.0 - r

	func step(x: float) -> float:
		var y := g * x + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		return y


## Sesli gırtlak darbesi + formantlar: maskenin içinden boğuk insan sesi.
static func _voiced(buf: PackedFloat32Array, f0_from: float, f0_to: float, formants: Array, breath: float,
		env_fn: Callable, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var res: Array[_Reso] = []
	for f in formants:
		res.append(_Reso.new(float(f[0]), float(f[1])))
	var phase := 0.0
	var n := buf.size()
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		var f0 := lerpf(f0_from, f0_to, u) * (1.0 + 0.03 * sin(TAU * 6.0 * u * n / RATE) + rng.randf_range(-0.01, 0.01))
		phase += f0 / RATE
		var src := 0.0
		if phase >= 1.0:
			phase -= 1.0
			src = 1.0
		src += rng.randf_range(-1.0, 1.0) * breath
		var s := 0.0
		for k in res.size():
			s += res[k].step(src) * (1.0 if k == 0 else 0.6 / k)
		lp += (s - lp) * 0.45   # maske boğuklaştırır
		buf[i] = lp * float(env_fn.call(u))


## Anti-G zorlanması (L-1): dişler kenetli, boğazdan sıkılan uzun "nnngh".
static func _strain(v: int) -> AudioStreamWAV:
	var dur := 1.1 + 0.25 * v
	var buf := PackedFloat32Array()
	buf.resize(int(RATE * dur))
	_voiced(buf, 112.0 - 8.0 * v, 98.0, [[300.0, 0.985], [1050.0, 0.975], [2300.0, 0.97]], 0.35,
		func(u: float) -> float: return smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.82, 1.0, u)) * (0.75 + 0.25 * sin(TAU * 3.0 * u)), 81 + v)
	return _to_wav(buf, false, 0.85)


## Zorlanma arası hızlı nefes: "hık" (gırtlak açılır) + kısa nefes alma hışırtısı.
static func _release(v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 + v
	var dur := 0.55
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hik := PackedFloat32Array()
	hik.resize(int(RATE * 0.12))
	_voiced(hik, 150.0 + 15.0 * v, 120.0, [[650.0, 0.98], [1300.0, 0.97]], 0.8,
		func(u: float) -> float: return smoothstep(0.0, 0.05, u) * (1.0 - u), 95 + v)
	var y := 0.0
	var low := 0.0
	var hik_peak := 0.0001
	for x in hik:
		hik_peak = maxf(hik_peak, absf(x))
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		if i < hik.size():
			s += hik[i] / hik_peak * 0.8
		# nefes alma: bant gürültüsü (maske valfi), 0.18 sn'den sonra
		var inh := smoothstep(0.17, 0.25, t) * (1.0 - smoothstep(0.42, 0.55, t))
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.3
		low += (y - low) * 0.05
		s += (y - low) * inh * 0.9
		buf[i] = s
	return _to_wav(buf, false, 0.8)


# ------------------------------------------------------------------ uyarı tonları

static func _sq(phase: float) -> float:
	# yumuşatılmış kare dalga (sert ama kulak tırmalamayan)
	return clampf(sin(TAU * phase) * 3.0, -1.0, 1.0)


## PULL UP: iki "vuup" süpürmesi (yükselen siren).
static func _tone_pullup() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var seg := fmod(t, 0.45)
		var on := 1.0 if seg < 0.36 else 0.0
		var f := lerpf(420.0, 1050.0, seg / 0.36)
		ph += f / RATE
		buf[i] = _sq(ph) * on * smoothstep(0.0, 0.01, seg) * (1.0 - smoothstep(0.34, 0.36, seg))
	return _to_wav(buf, false, 0.7)


## STALL: titreyen boğuk korna (12 Hz tıkırtılı).
static func _tone_stall() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var am := 0.5 + 0.5 * signf(sin(TAU * 12.0 * t))
		var s := _sq(330.0 * t) * 0.7 + sin(TAU * 660.0 * t) * 0.3
		buf[i] = s * am * smoothstep(0.0, 0.01, t) * (1.0 - smoothstep(0.46, 0.5, t))
	return _to_wav(buf, false, 0.65)


## Kısa bip dizisi.
static func _beeps(freqs: Array, on_s: float, off_s: float) -> AudioStreamWAV:
	var n := int(RATE * (on_s + off_s) * freqs.size())
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var k := mini(int(t / (on_s + off_s)), freqs.size() - 1)
		var u := t - k * (on_s + off_s)
		var on := smoothstep(0.0, 0.004, u) * (1.0 - smoothstep(on_s - 0.006, on_s, u))
		buf[i] = (sin(TAU * float(freqs[k]) * t) * 0.8 + _sq(float(freqs[k]) * t) * 0.2) * on
	return _to_wav(buf, false, 0.65)


## Yangın zili: hızlı vurulan, armonik olmayan çan.
static func _bell() -> AudioStreamWAV:
	var n := int(RATE * 1.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var u := fmod(t, 1.0 / 7.0)
		var e := exp(-u * 30.0)
		buf[i] = (sin(TAU * 820.0 * t) + sin(TAU * 2010.0 * t) * 0.6 + sin(TAU * 2730.0 * t) * 0.4) * e
	return _to_wav(buf, false, 0.6)


## Yumuşak çan (yakıt / genel ikaz): inen iki nota.
static func _chime(freqs: Array) -> AudioStreamWAV:
	var step := 0.32
	var n := int(RATE * (step * freqs.size() + 0.5))
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in freqs.size():
			var u := t - k * step
			if u >= 0.0:
				var f := float(freqs[k])
				s += (sin(TAU * f * u) + sin(TAU * f * 2.0 * u) * 0.25) * exp(-u * 4.5) * smoothstep(0.0, 0.005, u)
		buf[i] = s
	return _to_wav(buf, false, 0.6)


## Füze atışı: iki tonlu hızlı titreşim (RWR "launch" uyarısından farklı tını).
static func _warble() -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 1250.0 if fmod(t, 0.1) < 0.05 else 1650.0
		ph += f / RATE
		buf[i] = sin(TAU * ph) * smoothstep(0.0, 0.01, t) * (1.0 - smoothstep(0.56, 0.6, t))
	return _to_wav(buf, false, 0.6)
