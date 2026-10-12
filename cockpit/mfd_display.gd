class_name MfdDisplay
extends Control
## Kokpit çok fonksiyonlu ekranı (SubViewport içinde çizilir).
## PFD: yapay ufuk + hız/irtifa. ENGINE: gaz, itki, yakıt, takım, pusula.

enum Page { PFD, ENGINE }

const GREEN := Color(0.35, 1.0, 0.55)
const AMBER := Color(1.0, 0.7, 0.2)
const SKY := Color(0.15, 0.4, 0.75)
const GROUND := Color(0.45, 0.3, 0.15)

var page := Page.PFD
var vessel: Vessel
var _font := SystemFont.new()


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Consolas", "Arial"])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.02))
	if not is_instance_valid(vessel):
		return
	if not vessel.has_power():
		return   # güç yok: ekran karanlık
	if page == Page.PFD:
		_pfd()
	else:
		_engine()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.35, 0.35), false, 6.0)


func _pfd() -> void:
	var c := size * 0.5
	var r := size.x * 0.36
	var roll := deg_to_rad(vessel.roll_deg())
	var pitch_px := vessel.pitch_deg() * 3.0
	# ufuk: dönen gök/yer
	draw_set_transform(c, -roll, Vector2.ONE)
	draw_rect(Rect2(-r * 2, -r * 2 + pitch_px, r * 4, r * 2), SKY)
	draw_rect(Rect2(-r * 2, pitch_px, r * 4, r * 2), GROUND)
	draw_line(Vector2(-r * 2, pitch_px), Vector2(r * 2, pitch_px), Color.WHITE, 2.0)
	for p in [-20, -10, 10, 20]:
		var y: float = pitch_px - p * 3.0
		draw_line(Vector2(-20, y), Vector2(20, y), Color.WHITE, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# maske
	draw_rect(Rect2(0, 0, size.x, c.y - r), Color(0.01, 0.02, 0.02))
	draw_rect(Rect2(0, c.y + r, size.x, size.y), Color(0.01, 0.02, 0.02))
	draw_rect(Rect2(0, 0, c.x - r, size.y), Color(0.01, 0.02, 0.02))
	draw_rect(Rect2(c.x + r, 0, size.x, size.y), Color(0.01, 0.02, 0.02))
	# uçak sembolü
	draw_line(c + Vector2(-40, 0), c + Vector2(-12, 0), AMBER, 4.0)
	draw_line(c + Vector2(12, 0), c + Vector2(40, 0), AMBER, 4.0)
	draw_circle(c, 4.0, AMBER)
	_t(Vector2(10, 26), "%d" % (vessel.airspeed() * 3.6), 20, GREEN)
	_t(Vector2(10, 46), "km/sa", 12, GREEN)
	_t(Vector2(size.x - 80, 26), "%d" % vessel.altitude(), 20, GREEN)
	_t(Vector2(size.x - 80, 46), "m", 12, GREEN)
	_t(Vector2(10, size.y - 14), "G %.1f" % vessel.g_force, 16, GREEN)
	_t(Vector2(size.x - 80, size.y - 14), "VS %+d" % vessel.vertical_speed(), 16, GREEN)


func _engine() -> void:
	var thrust := vessel.total_thrust() / 1000.0
	var eng: EngineModule = vessel.engines()[0] if not vessel.engines().is_empty() else null
	var state_txt := "KAPALI"
	if eng and eng.state == EngineModule.State.CRANKING:
		state_txt = "MARŞ"
	elif eng and eng.is_running():
		state_txt = "ÇALIŞIYOR"
	_t(Vector2(14, 30), "MOTOR", 16, GREEN if vessel.engine_on else AMBER)
	_t(Vector2(170, 30), "N2 %d%%" % ((eng.n2 if eng else 0.0) * 100.0), 14, GREEN)
	_t(Vector2(170, 196), "JFS " + ("AÇIK" if vessel.jfs_on else "-"), 14, AMBER if vessel.jfs_on else Color(0.6, 0.65, 0.65))
	_t(Vector2(84, 30), state_txt, 16, GREEN if vessel.engine_on else AMBER)
	_gauge(Vector2(14, 50), "GAZ", vessel.ctrl_throttle, "%d%%" % (vessel.ctrl_throttle * 100))
	_gauge(Vector2(14, 92), "İTKİ", thrust / 70.0, "%d kN" % thrust)
	var fuel_ratio := vessel.fuel_amount() / maxf(vessel.fuel_capacity(), 1.0)
	_gauge(Vector2(14, 134), "YAKIT", fuel_ratio, "%d kg" % vessel.fuel_amount(), AMBER if fuel_ratio < 0.15 else GREEN)
	_t(Vector2(14, 196), "TAKIM " + ("AŞAĞI" if vessel.gear_down else "YUKARI"), 15, GREEN if vessel.gear_down else Color(0.6, 0.65, 0.65))
	_t(Vector2(14, 218), "FREN " + ("PARK" if vessel.parking_brake else "-"), 15, AMBER if vessel.parking_brake else Color(0.6, 0.65, 0.65))
	# pusula
	var cc := Vector2(size.x - 62, size.y - 58)
	draw_arc(cc, 44, 0, TAU, 32, GREEN, 2.0)
	var h := deg_to_rad(vessel.heading_deg())
	for i in 4:
		var a := -h + i * PI * 0.5 - PI * 0.5
		var label: String = ["K", "D", "G", "B"][i]
		_t(cc + Vector2(cos(a), sin(a)) * 32 - Vector2(5, -6), label, 13, GREEN)
	draw_line(cc, cc + Vector2(0, -40), AMBER, 3.0)


func _gauge(pos: Vector2, label: String, value: float, text: String, col := GREEN) -> void:
	_t(pos + Vector2(0, 14), label, 14, Color(0.7, 0.8, 0.75))
	var bar := Rect2(pos + Vector2(60, 2), Vector2(120, 14))
	draw_rect(bar, Color(1, 1, 1, 0.1))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(value, 0.0, 1.0), bar.size.y)), col)
	_t(pos + Vector2(60, 36), text, 14, col)


func _t(pos: Vector2, text: String, font_size: int, col: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
