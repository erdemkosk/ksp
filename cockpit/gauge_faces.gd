class_name GaugeFaces
extends Control
## Analog yedek göstergelerin kadranları: 512x512 dokuda 2x2 atlas (bir kez çizilir).
##   0 sol üst: hava hızı (0-1200 km/sa, 300° tarama)   1 sağ üst: irtifa (0-9 x100 m)
##   2 sol alt: yakıt (B..D, 240°)                      3 sağ alt: hidrolik (%, 240°)
## İbreler CockpitModule'de 3B olarak döner; açılar needle_* ile hesaplanır.

const CELL := 256.0

var _font := SystemFont.new()


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Consolas", "Arial"])
	size = Vector2(CELL * 2, CELL * 2)


## Saat yönünde, tepeden derece.
static func needle_asi(kmh: float) -> float:
	return -150.0 + clampf(kmh / 1200.0, 0.0, 1.0) * 300.0


static func needle_sweep240(f: float) -> float:
	return -120.0 + clampf(f, 0.0, 1.0) * 240.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.025))
	# hava hızı
	var c := Vector2(CELL * 0.5, CELL * 0.5)
	_ring(c)
	for i in 61:
		var v := i * 20.0
		var major := i % 5 == 0
		_tick(c, needle_asi(v), 22.0 if major else 11.0, 4.0 if major else 2.0)
		if major:
			_label(c, needle_asi(v), 78.0, str(int(v / 100.0)), 26)
	_center_text(c + Vector2(0, 46), "KM/SA x100", 15)
	_center_text(c + Vector2(0, -36), "HIZ", 18)
	# irtifa
	c = Vector2(CELL * 1.5, CELL * 0.5)
	_ring(c)
	for i in 50:
		var major := i % 5 == 0
		_tick(c, i * 7.2, 22.0 if major else 11.0, 4.0 if major else 2.0)
		if major:
			_label(c, i * 7.2, 78.0, str(i / 5), 30)
	_center_text(c + Vector2(0, 46), "M x100", 15)
	_center_text(c + Vector2(0, -36), "İRTİFA", 18)
	# yakıt
	c = Vector2(CELL * 0.5, CELL * 1.5)
	_ring(c)
	for i in 9:
		_tick(c, needle_sweep240(i / 8.0), 22.0 if i % 2 == 0 else 12.0, 4.0)
	_label(c, needle_sweep240(0.0), 78.0, "B", 30, Color(1.0, 0.3, 0.2))
	_label(c, needle_sweep240(0.5), 78.0, "½", 30)
	_label(c, needle_sweep240(1.0), 78.0, "D", 30)
	_arc_band(c, needle_sweep240(0.0), needle_sweep240(0.15), Color(1.0, 0.3, 0.2))
	_center_text(c + Vector2(0, 52), "YAKIT", 20)
	# hidrolik
	c = Vector2(CELL * 1.5, CELL * 1.5)
	_ring(c)
	for i in 11:
		_tick(c, needle_sweep240(i / 10.0), 22.0 if i % 5 == 0 else 12.0, 4.0)
	_label(c, needle_sweep240(0.0), 78.0, "0", 28)
	_label(c, needle_sweep240(0.5), 78.0, "50", 28)
	_label(c, needle_sweep240(1.0), 78.0, "100", 28)
	_arc_band(c, needle_sweep240(0.0), needle_sweep240(0.45), Color(1.0, 0.7, 0.2))
	_center_text(c + Vector2(0, 52), "HİD %", 20)


func _ring(c: Vector2) -> void:
	draw_circle(c, CELL * 0.5 - 2, Color(0.05, 0.05, 0.055))
	draw_arc(c, CELL * 0.5 - 6, 0, TAU, 64, Color(0.5, 0.5, 0.5), 3.0)


func _dir(deg: float) -> Vector2:
	var a := deg_to_rad(deg) - PI * 0.5
	return Vector2(cos(a), sin(a))


func _tick(c: Vector2, deg: float, length: float, width: float) -> void:
	var d := _dir(deg)
	var r := CELL * 0.5 - 12
	draw_line(c + d * r, c + d * (r - length), Color(0.95, 0.95, 0.92), width)


func _arc_band(c: Vector2, d0: float, d1: float, col: Color) -> void:
	draw_arc(c, CELL * 0.5 - 16, deg_to_rad(d0) - PI * 0.5, deg_to_rad(d1) - PI * 0.5, 16, col, 8.0)


func _label(c: Vector2, deg: float, inset: float, text: String, fs: int, col := Color(0.95, 0.95, 0.92)) -> void:
	var p := c + _dir(deg) * (CELL * 0.5 - inset)
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, p + Vector2(-sz.x * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _center_text(p: Vector2, text: String, fs: int) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, p + Vector2(-sz.x * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.78, 0.75))
