class_name TerrainGen
## Gezegenin yükseklik fonksiyonu. Girdi: gezegen merkezinden birim yön (başlangıç çerçevesinde).
## Görsel arazi, çarpışma, ağaç/ev yerleşimi ve radar irtifası hep bunu kullanır.
##
## Havaalanı d = (0,1,0) noktasında; çevresinde doğuda (+X) deniz, batıda dağlar.
## Uzak bölgelerde kıtalar ve okyanuslar 3B gürültüyle oluşur.
## İş parçacıklarından çağrılır: autoload'lara erişmez, sadece sabit ve gürültü kullanır.

const RADIUS := 600000.0
const AIRFIELD_ELEV := 12.0
const AIRFIELD_HALF := Vector2(500.0, 1700.0)
const AIRFIELD_BLEND := 800.0
const TREE_LINE := 1100.0

## Havaalanları: başlangıç çerçevesinde yüzey koordinatı (x doğu, z güney), rakım, yarı boyut.
## 0: Ana Üs (pist kuzey-güney), 1: Kuzey Havaalanı (~30 km kuzeybatı, daha küçük).
const AIRFIELDS := [
	{"name": "Ana Üs", "xz": Vector2(0, 0), "elev": 12.0, "half": Vector2(500.0, 1700.0), "runway": 2400.0},
	{"name": "Kuzey Havaalanı", "xz": Vector2(-26000, -14000), "elev": 30.0, "half": Vector2(380.0, 1300.0), "runway": 1800.0},
]
static var _af_c: Array[Vector3] = []     # merkez yönleri
static var _af_x: Array[Vector3] = []     # teğet doğu
static var _af_z: Array[Vector3] = []     # teğet güney

static var _continent: FastNoiseLite
static var _hills: FastNoiseLite
static var _ridges: FastNoiseLite
static var _detail: FastNoiseLite
static var _forest: FastNoiseLite
static var _village: FastNoiseLite
static var _ranges: FastNoiseLite


## Ana thread'de, iş parçacıkları başlamadan önce çağrılmalı.
static func init() -> void:
	if _continent:
		return
	_continent = _noise(11, 1.0 / 110000.0, 3, FastNoiseLite.FRACTAL_FBM)
	_hills = _noise(23, 1.0 / 3200.0, 4, FastNoiseLite.FRACTAL_FBM)
	_ridges = _noise(37, 1.0 / 8000.0, 5, FastNoiseLite.FRACTAL_RIDGED)
	_detail = _noise(41, 1.0 / 280.0, 3, FastNoiseLite.FRACTAL_FBM)
	_forest = _noise(53, 1.0 / 1600.0, 3, FastNoiseLite.FRACTAL_FBM)
	_village = _noise(67, 1.0 / 2500.0, 2, FastNoiseLite.FRACTAL_FBM)
	_ranges = _noise(79, 1.0 / 45000.0, 3, FastNoiseLite.FRACTAL_FBM)
	for a: Dictionary in AIRFIELDS:
		var xz: Vector2 = a["xz"]
		var c := Vector3(xz.x, RADIUS, xz.y).normalized()
		var ex := (Vector3(1, 0, 0) - c * c.x).normalized()
		_af_c.append(c)
		_af_x.append(ex)
		_af_z.append(ex.cross(c))
	_build_rivers()


static func _noise(seed: int, freq: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


## Havaalanından yüzey üzerindeki mesafe (metre).
static func _airfield_distance(d: Vector3) -> float:
	return acos(clampf(d.y, -1.0, 1.0)) * RADIUS


## > 0 kara, < 0 deniz.
static func land_mask(d: Vector3) -> float:
	var p := d * RADIUS
	var m := _continent.get_noise_3d(p.x, p.y, p.z) * 1.3 + 0.02
	var dist := _airfield_distance(d)
	# Havaalanı bölgesi: doğuda kıyı, batıda iç kesim
	var local := 1.0 - smoothstep(60000.0, 220000.0, dist)
	if local > 0.0:
		var regional := _continent.get_noise_3d(p.x * 3.4, p.y * 3.4, p.z * 3.4) * 0.8 + 0.2 - p.x / 22000.0
		m = lerpf(m, regional, local)
	# havaalanları çevresi her zaman kara (koruma sadece yakında; uzakta denizleri sıfıra çekmemeli)
	var guard := 0.0
	for i in _af_c.size():
		var ad := acos(clampf(d.dot(_af_c[i]), -1.0, 1.0)) * RADIUS
		guard = maxf(guard, 0.35 * (1.0 - smoothstep(2500.0, 7000.0, ad)))
	return maxf(m, guard) if guard > 0.0 else m


static func height(d: Vector3) -> float:
	var p := d * RADIUS
	var m := land_mask(d)
	var h: float
	if m > 0.0:
		var coast := smoothstep(0.0, 0.2, m)
		var hill := _hills.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5
		var ridge := _ridges.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5
		# sıradağlar: ayrı bir düşük frekanslı gürültüyle kuşaklar hâlinde, aralarda ovalar
		var ranges := _ranges.get_noise_3d(p.x, p.y, p.z)
		var mountain := smoothstep(0.08, 0.45, ranges) * smoothstep(0.05, 0.35, m)
		h = coast * (4.0 + hill * hill * 160.0) + mountain * ridge * ridge * 2200.0
		h += _detail.get_noise_3d(p.x, p.y, p.z) * 5.0 * coast
	else:
		# kıta sahanlığı sonra derin okyanus (m=-0.01 → ~-38 m, m=-0.5 → ~-710 m)
		h = -pow(-m, 0.75) * 1200.0
	# nehir yatakları (havaalanı düzlüklerinden önce: pistler hiçbir zaman oyulmaz)
	if _rivers_ready and d.y > 0.9:
		h = _carve_rivers(d.x / d.y * RADIUS, d.z / d.y * RADIUS, h)
	# havaalanı düzlükleri (her havaalanının teğet düzleminde dikdörtgen)
	for i in _af_c.size():
		var c := _af_c[i]
		if d.dot(c) < 0.9995:
			continue
		var a: Dictionary = AIRFIELDS[i]
		var half: Vector2 = a["half"]
		var rel := p - c * RADIUS
		var lx := rel.dot(_af_x[i])
		var lz := rel.dot(_af_z[i])
		var dx := maxf(absf(lx) - half.x, 0.0)
		var dz := maxf(absf(lz) - half.y, 0.0)
		var t := smoothstep(0.0, AIRFIELD_BLEND, sqrt(dx * dx + dz * dz))
		# teğet düzlemde düz: küre yüzeyi uzaklaştıkça d²/2R kadar alçalır, onu telafi et
		var flat: float = float(a["elev"]) + (lx * lx + lz * lz) / (2.0 * RADIUS)
		h = lerpf(flat, h, t)
	return h


## 0..1 orman yoğunluğu.
static func forest(d: Vector3) -> float:
	var p := d * RADIUS
	return smoothstep(0.0, 0.3, _forest.get_noise_3d(p.x, p.y, p.z))


## 0..1 yerleşim yoğunluğu.
static func village(d: Vector3) -> float:
	var p := d * RADIUS
	return smoothstep(0.35, 0.6, _village.get_noise_3d(p.x, p.y, p.z))


static func in_airfield(d: Vector3, margin: float) -> bool:
	for i in _af_c.size():
		if d.dot(_af_c[i]) < 0.999:
			continue
		var half: Vector2 = AIRFIELDS[i]["half"]
		var rel := d * RADIUS - _af_c[i] * RADIUS
		if absf(rel.dot(_af_x[i])) < half.x + margin and absf(rel.dot(_af_z[i])) < half.y + margin:
			return true
	return false


## Havaalanının başlangıç çerçevesindeki dönüşümü (kayan orijin sıfırken): başlangıç noktası
## pist merkezi, x doğu, y yukarı, z güney (pist z boyunca).
static func airfield_transform(i: int) -> Transform3D:
	var c := _af_c[i]
	var origin := Vector3(0, -RADIUS, 0) + c * (RADIUS + float(AIRFIELDS[i]["elev"]))
	return Transform3D(Basis(_af_x[i], c, _af_z[i]), origin)


# ------------------------------------------------------------------ nehirler
# Dağlardaki kaynaklardan her adımda en alçak komşuya akarak denize inen yollar. Yükseklik
# fonksiyonu bu yollar boyunca yatak oyar (su seviyesi akış yönünde hiç yükselmez).
# Konumlar başlangıç çerçevesinde (x doğu, z güney).

## Her nehir: {"pts": PackedVector2Array, "level": PackedFloat32Array, "width": PackedFloat32Array, "box": Rect2}
static var rivers: Array[Dictionary] = []
static var _rivers_ready := false
const RIVER_BANK := 90.0


static func _h_xz(x: float, z: float) -> float:
	return height(Vector3(x, RADIUS, z).normalized())


## Nehir yolları (ara noktalar, başlangıç çerçevesi). Son nokta denizde ya da (kol için) ana
## nehrin üstünde. Kıvrımlar ve su seviyesi koddan üretilir.
const RIVER_PATHS := [
	# ana nehir: kuzey dağları → Ovaköy doğusu → koy
	[Vector2(-15000, -28500), Vector2(-13000, -23000), Vector2(-10500, -18500), Vector2(-7500, -14500),
		Vector2(-5200, -10800), Vector2(-3000, -8800), Vector2(-500, -8300)],
	# kol: batı dağları → Kuzeykent ile Yeşilyurt arası → ana nehre katılır
	[Vector2(-30500, -25500), Vector2(-26500, -21500), Vector2(-21500, -19300), Vector2(-16500, -17500),
		Vector2(-12800, -17200), Vector2(-10500, -18500)],
	# güney nehri: güney dağları → Ana Üs'ün 4 km güneyi → deniz
	[Vector2(-15000, 9500), Vector2(-11000, 6500), Vector2(-6500, 5200), Vector2(-2000, 4600),
		Vector2(2500, 5200), Vector2(7000, 5600), Vector2(9500, 5800)],
]


static func _build_rivers() -> void:
	rivers.clear()
	_grid.clear()
	_rivers_ready = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for wp: Array in RIVER_PATHS:
		# 80 m adımlarla, yana sinüs kıvrımları (genlik yolun ortasında büyük)
		var pts: Array[Vector2] = []
		var phase := rng.randf() * TAU
		for i in wp.size() - 1:
			var a: Vector2 = wp[i]
			var b: Vector2 = wp[i + 1]
			var n := maxi(int(a.distance_to(b) / 80.0), 1)
			var perp := (b - a).normalized().orthogonal()
			for k in n:
				var t := float(k) / n
				var s := pts.size() * 80.0
				var amp := (130.0 + 90.0 * sin(s / 3100.0 + phase)) * sin(t * PI)
				pts.append(a.lerp(b, t) + perp * sin(s / 520.0 + phase) * amp)
		pts.append(wp[wp.size() - 1])
		for it in 2:
			var sm: Array[Vector2] = [pts[0]]
			for i in pts.size() - 1:
				sm.append(pts[i].lerp(pts[i + 1], 0.25))
				sm.append(pts[i].lerp(pts[i + 1], 0.75))
			sm.append(pts[pts.size() - 1])
			pts = sm
		var out := PackedVector2Array()
		var level := PackedFloat32Array()
		var width := PackedFloat32Array()
		var lv := INF
		var box := Rect2(pts[0], Vector2.ZERO)
		for i in pts.size():
			var h := _h_xz(pts[i].x, pts[i].y)
			lv = maxf(minf(lv, h - 1.5), 0.0)
			# kol ana nehre katılırken onun seviyesine iner
			if rivers.size() > 0 and i == pts.size() - 1:
				var main_r := river_at(pts[i].x, pts[i].y)
				if not main_r.is_empty():
					lv = minf(lv, float(main_r["level"]))
			out.append(pts[i])
			level.append(lv)
			width.append(lerpf(16.0, 60.0, pow(float(i) / pts.size(), 0.8)))
			box = box.expand(pts[i])
		rivers.append({"pts": out, "level": level, "width": width, "box": box.grow(RIVER_BANK + 80.0)})
		_index_river(rivers.size() - 1)
	_rivers_ready = true


## Bölüt ızgarası: hücre -> [[nehir, bölüt], ...] (yükseklik sorgusu yalnız yakın hücreleri tarar)
static var _grid := {}
const GRID := 400.0


static func _index_river(ri: int) -> void:
	var pts: PackedVector2Array = rivers[ri]["pts"]
	var reach := RIVER_BANK + 50.0
	for i in pts.size() - 1:
		var lo := pts[i].min(pts[i + 1]) - Vector2(reach, reach)
		var hi := pts[i].max(pts[i + 1]) + Vector2(reach, reach)
		for gx in range(int(floor(lo.x / GRID)), int(floor(hi.x / GRID)) + 1):
			for gz in range(int(floor(lo.y / GRID)), int(floor(hi.y / GRID)) + 1):
				var key := Vector2i(gx, gz)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(Vector2i(ri, i))


## Noktaya en yakın nehir: {dist, level, width, dir (akış yönü)} ya da {}.
static func river_at(x: float, z: float) -> Dictionary:
	var q := Vector2(x, z)
	var best := {}
	var bd := INF
	var cell: Variant = _grid.get(Vector2i(int(floor(x / GRID)), int(floor(z / GRID))))
	if cell == null:
		return best
	for ref: Vector2i in cell:
		var r: Dictionary = rivers[ref.x]
		var pts: PackedVector2Array = r["pts"]
		var i := ref.y
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		if d < bd:
			bd = d
			var lv: PackedFloat32Array = r["level"]
			var wd: PackedFloat32Array = r["width"]
			best = {"dist": d, "level": lerpf(lv[i], lv[i + 1], t), "width": lerpf(wd[i], wd[i + 1], t), "dir": ab.normalized()}
	return best


static func _carve_rivers(x: float, z: float, h: float) -> float:
	var r := river_at(x, z)
	if r.is_empty():
		return h
	var half := float(r["width"]) * 0.5
	var d := float(r["dist"])
	if d > half + RIVER_BANK:
		return h
	var lv := float(r["level"])
	if d < half:
		var k := d / half
		return minf(h, lv - 0.6 - 2.4 * (1.0 - k * k))
	# kıyı: arazi su seviyesinin biraz üstüne yumuşakça iner
	return minf(h, lerpf(lv + 0.7, h, smoothstep(half, half + RIVER_BANK, d)))
