class_name DesignDashboard
extends Control
## Hangarın tasarım panosu: sayı listesi yerine bakınca anlaşılan görseller.
##   • Karakter (altıgen): hız, çeviklik, tırmanma, menzil, ateş gücü, dayanıklılık — uçağın
##     "kişiliği" bir bakışta; önceki hâli soluk çizgiyle (değişikliğin etkisi görünsün)
##   • Denge: gövde boyunca ağırlık merkezi (sarı), yakıt bitince (soluk sarı), kaldırma merkezi
##     (mavi); arası yeşilse kararlı, mavi öndeyse kırmızı — terazi dengesizliğe göre eğilir
##   • Göstergeler: itki / ağırlık, kanat yüklemesi, hava alığı (ibre + renkli bölge)
##   • Pist: 2400 m pist üstünde kalkış mesafesi (yetmezse kırmızı taşar)
## Veri hangar._update_stats'tan set_data ile gelir; ayrıntılı sayılar "Ayrıntılar"da kalır.

const W := 276.0
const ACC := Color(0.45, 1.0, 0.65)
const DIM := Color(0.6, 0.68, 0.76)
const GOOD := Color(0.35, 0.95, 0.5)
const WARN := Color(1.0, 0.8, 0.25)
const BAD := Color(1.0, 0.32, 0.25)
const AXES := ["Hız", "Çeviklik", "Tırmanma", "Menzil", "Ateş gücü", "Dayanıklılık"]

var _d := {}
var _scores: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _prev: Array[float] = []
var _font: Font
var _bold: SystemFont


func _ready() -> void:
	custom_minimum_size = Vector2(W, 470)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = ThemeDB.fallback_font
	_bold = SystemFont.new()
	_bold.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold.font_weight = 700


## d: {empty, v0_kmh, mach, climb, range_km, tw, wing_load, intake, dto, guns, missiles, bombs,
##     hp, mass, com_z, col_z, dry_z, z_min, z_max, has_col}
func set_data(d: Dictionary) -> void:
	if not _scores.is_empty() and _scores.max() > 0.0:
		_prev = _scores.duplicate()
	_d = d
	if d.get("empty", false):
		_scores = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	else:
		var wl := float(d.get("wing_load", 400.0))
		var tw := float(d.get("tw", 0.0))
		_scores = [
			clampf(float(d.get("v0_kmh", 0.0)) / 1800.0, 0.0, 1.0),
			clampf((1.0 - (wl - 150.0) / 500.0) * 0.6 + tw * 0.35, 0.0, 1.0),
			clampf(float(d.get("climb", 0.0)) / 220.0, 0.0, 1.0),
			clampf(float(d.get("range_km", 0.0)) / 1400.0, 0.0, 1.0),
			clampf(float(d.get("guns", 0)) * 0.18 + float(d.get("missiles", 0)) * 0.11 + float(d.get("bombs", 0)) * 0.08, 0.0, 1.0),
			clampf(float(d.get("hp", 0.0)) / maxf(float(d.get("mass", 1.0)), 1.0) * 6.0, 0.0, 1.0),
		]
	tooltip_text = _tooltip()
	queue_redraw()


func _tooltip() -> String:
	if _d.is_empty() or _d.get("empty", false):
		return ""
	return "Hız %d km/sa (M%.2f) · tırmanma %d m/s · menzil %d km\nİtki/ağırlık %.2f · kanat yüklemesi %d kg/m² · hava alığı %%%d · kalkış %d m" % [
		_d.get("v0_kmh", 0), _d.get("mach", 0.0), _d.get("climb", 0), _d.get("range_km", 0),
		_d.get("tw", 0.0), _d.get("wing_load", 0), float(_d.get("intake", 1.0)) * 100.0, _d.get("dto", 0)]


func _draw() -> void:
	if _d.is_empty() or _d.get("empty", false):
		_text(Vector2(0, 20), "Kokpitle başla — uçağın karakteri burada belirir", 13, DIM)
		return
	_draw_radar(Vector2(W * 0.5, 118), 82.0)
	_draw_balance(Rect2(0, 236, W, 72))
	_draw_gauges(Rect2(0, 318, W, 92))
	_draw_runway(Rect2(0, 420, W, 46))


func _text(pos: Vector2, s: String, size: int, col: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_bold if bold else _font, pos, s, align, width, size, col)


# ------------------------------------------------------------------ karakter (altıgen)

func _draw_radar(c: Vector2, r: float) -> void:
	var n := AXES.size()
	var pts := func(vals: Array, scale: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in n:
			var a := -PI * 0.5 + TAU * i / n
			out.append(c + Vector2(cos(a), sin(a)) * r * scale * clampf(float(vals[i]), 0.04, 1.0))
		return out
	# ızgara
	for ring in [0.33, 0.66, 1.0]:
		var g: PackedVector2Array = pts.call([1, 1, 1, 1, 1, 1], ring)
		g.append(g[0])
		draw_polyline(g, Color(1, 1, 1, 0.1), 1.0, true)
	for i in n:
		var a := -PI * 0.5 + TAU * i / n
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(1, 1, 1, 0.08), 1.0)
	# önceki hâl (soluk) ve şimdiki
	if _prev.size() == n:
		var pp: PackedVector2Array = pts.call(_prev, 1.0)
		pp.append(pp[0])
		draw_polyline(pp, Color(1, 1, 1, 0.25), 1.0, true)
	var cur: PackedVector2Array = pts.call(_scores, 1.0)
	draw_colored_polygon(cur, Color(ACC, 0.22))
	cur.append(cur[0])
	draw_polyline(cur, ACC, 2.0, true)
	# eksen adları ve noktalar (değişim oku: ▲ arttı / ▼ azaldı)
	for i in n:
		var a := -PI * 0.5 + TAU * i / n
		var d := Vector2(cos(a), sin(a))
		draw_circle(c + d * r * clampf(_scores[i], 0.04, 1.0), 3.0, ACC)
		var lp := c + d * (r + 18.0)
		var label: String = AXES[i]
		if _prev.size() == n and absf(_scores[i] - _prev[i]) > 0.02:
			label += " ▲" if _scores[i] > _prev[i] else " ▼"
		var col := DIM
		if _prev.size() == n and absf(_scores[i] - _prev[i]) > 0.02:
			col = GOOD if _scores[i] > _prev[i] else BAD
		_text(lp + Vector2(-50, 5), label, 13, col, false, HORIZONTAL_ALIGNMENT_CENTER, 100.0)


# ------------------------------------------------------------------ denge

func _draw_balance(r: Rect2) -> void:
	_text(r.position + Vector2(0, 10), "DENGE", 13, DIM, true)
	var has_col: bool = _d.get("has_col", false)
	var com: float = _d.get("com_z", 0.0)
	var col: float = _d.get("col_z", 0.0)
	var dry: float = _d.get("dry_z", com)
	var z0: float = _d.get("z_min", com - 5.0)
	var z1: float = _d.get("z_max", com + 5.0)
	var margin := col - com      # pozitif: kaldırma merkezi arkada (kararlı)
	var state := "KARARLI" if margin >= 0.4 else ("ÇOK ÇEVİK — zor uçar" if margin >= 0.0 else "KARARSIZ")
	var scol := GOOD if margin >= 0.4 else (WARN if margin >= 0.0 else BAD)
	if not has_col:
		state = "KANAT YOK"
		scol = BAD
	_text(r.position + Vector2(0, 10), state, 13, scol, true, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)
	# terazi: gövde çizgisi, dengesizliğe göre eğik; burun solda
	var y := r.position.y + 40.0
	var x0 := r.position.x + 18.0
	var x1 := r.end.x - 18.0
	var to_x := func(z: float) -> float:
		return lerpf(x0, x1, clampf((z - z0) / maxf(z1 - z0, 0.1), 0.0, 1.0))
	var tilt := clampf(-margin * 0.06, -0.12, 0.12) if has_col else 0.0
	var mid := (x0 + x1) * 0.5
	var y_at := func(x: float) -> float:
		return y + (x - mid) * tilt
	draw_line(Vector2(x0, y_at.call(x0)), Vector2(x1, y_at.call(x1)), Color(0.75, 0.8, 0.85), 3.0, true)
	_text(Vector2(x0 - 16, y + 4), "◀", 11, DIM)
	# destek üçgeni ağırlık merkezinin altında
	var cx: float = to_x.call(com)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y_at.call(cx) + 3), Vector2(cx - 7, y + 18), Vector2(cx + 7, y + 18)]), Color(0.4, 0.42, 0.45))
	if has_col:
		var lx: float = to_x.call(col)
		# ağırlık – kaldırma arası bölge
		var zc := GOOD if margin >= 0.4 else (WARN if margin >= 0.0 else BAD)
		draw_rect(Rect2(minf(cx, lx), y - 6, absf(lx - cx), 12), Color(zc, 0.35))
		draw_circle(Vector2(lx, y_at.call(lx)), 6.0, Color(0.25, 0.6, 1.0))
		_text(Vector2(lx - 30, y - 11), "kaldırma", 11, Color(0.5, 0.75, 1.0), false, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	var dx: float = to_x.call(dry)
	draw_circle(Vector2(dx, y_at.call(dx)), 4.0, Color(1.0, 0.85, 0.1, 0.35))
	draw_circle(Vector2(cx, y_at.call(cx)), 6.0, Color(1.0, 0.85, 0.1))
	_text(Vector2(cx - 30, y + 32), "ağırlık", 11, Color(1.0, 0.85, 0.3), false, HORIZONTAL_ALIGNMENT_CENTER, 60.0)


# ------------------------------------------------------------------ göstergeler

func _draw_gauges(r: Rect2) -> void:
	var tw: float = _d.get("tw", 0.0)
	var wl: float = _d.get("wing_load", 0.0)
	var intake: float = _d.get("intake", 1.0)
	var w3 := r.size.x / 3.0
	# itki/ağırlık: 0..2, 1 = dikey tırmanır; düşük kırmızı
	_gauge(Vector2(r.position.x + w3 * 0.5, r.position.y + 52), tw / 2.0, [[0.0, 0.17, BAD], [0.17, 0.35, WARN], [0.35, 1.0, GOOD]],
		"İTKİ/AĞIRLIK", "%.2f" % tw)
	# kanat yüklemesi: 100..800 kg/m²; düşük = çevik, yüksek = hızlı ama yavaş dönüş
	_gauge(Vector2(r.position.x + w3 * 1.5, r.position.y + 52), (wl - 100.0) / 700.0, [[0.0, 0.45, GOOD], [0.45, 0.75, WARN], [0.75, 1.0, BAD]],
		"KANAT YÜKÜ", "%d" % wl)
	# hava alığı: %0..150; %100 altı motor boğulur
	_gauge(Vector2(r.position.x + w3 * 2.5, r.position.y + 52), intake / 1.5, [[0.0, 0.66, BAD], [0.66, 0.7, WARN], [0.7, 1.0, GOOD]],
		"HAVA ALIĞI", ("%%%d" % (intake * 100.0)) if intake <= 1.5 else "%150+")


func _gauge(c: Vector2, v: float, bands: Array, title: String, value: String) -> void:
	var rad := 34.0
	var a0 := PI * 0.85
	var a1 := PI * 2.15
	for b in bands:
		var s := lerpf(a0, a1, float(b[0]))
		var e := lerpf(a0, a1, float(b[1]))
		draw_arc(c, rad, s, e, 16, Color(b[2] as Color, 0.55), 5.0, true)
	var a := lerpf(a0, a1, clampf(v, 0.0, 1.0))
	draw_line(c, c + Vector2(cos(a), sin(a)) * (rad - 2.0), Color.WHITE, 2.0, true)
	draw_circle(c, 3.0, Color.WHITE)
	_text(c + Vector2(-46, 21), value, 15, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, 92.0)
	_text(c + Vector2(-46, -41), title, 11, DIM, false, HORIZONTAL_ALIGNMENT_CENTER, 92.0)


# ------------------------------------------------------------------ pist

func _draw_runway(r: Rect2) -> void:
	var dto: float = _d.get("dto", 0.0)
	var can: bool = _d.get("can_roll", true)
	_text(r.position + Vector2(0, 10), "KALKIŞ", 13, DIM, true)
	var y := r.position.y + 26.0
	var x0 := r.position.x
	var w := r.size.x
	draw_rect(Rect2(x0, y, w, 10), Color(0.18, 0.19, 0.2))
	for i in 12:
		draw_rect(Rect2(x0 + 6 + i * (w / 12.0), y + 4, w / 30.0, 2), Color(1, 1, 1, 0.35))
	var frac := dto / 2400.0
	var col := GOOD if frac < 0.6 else (WARN if frac < 1.0 else BAD)
	if not can:
		col = BAD
		frac = 1.0
	draw_rect(Rect2(x0, y + 1, w * minf(frac, 1.0), 8), Color(col, 0.75))
	var label := ("%d m" % dto) if can else "KALKAMAZ"
	if can and frac > 1.0:
		label += "  — pist yetmez"
	_text(r.position + Vector2(0, 10), label, 13, col, true, HORIZONTAL_ALIGNMENT_RIGHT, w)
