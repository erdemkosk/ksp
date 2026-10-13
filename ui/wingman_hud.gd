class_name WingmanHud
extends Control
## Kanat adamı göstergesi: ekranda "K2" işareti (dost rengi, mesafe), ekran dışındaysa kenarda
## ok; eylem panelinin üstünde durum satırı (pilot, emir, durum, yakıt).

const FRIEND := Color(0.4, 0.8, 1.0)
const SHADOW := Color(0, 0, 0, 0.6)

var flight: WingFlight
var _font := SystemFont.new()
var _bold := SystemFont.new()


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	visible = is_instance_valid(flight) and is_instance_valid(flight.main) and is_instance_valid(flight.main.vessel)
	queue_redraw()


func _text(p: Vector2, t: String, sz: int, col: Color, f: Font = null) -> void:
	var font := f if f else _font
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, p + Vector2(-w * 0.5 + 1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, SHADOW)
	draw_string(font, p + Vector2(-w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw() -> void:
	if size.x < 50.0:
		return
	var m: Node = flight.main
	var cam: Camera3D = m.camera
	var me: Vessel = m.vessel
	var ship := flight.ship
	var status := ""
	if flight.flying():
		var ai := flight.ai
		var st: String = "KALKIŞ" if ai.on_runway else AIPilot.STATE_NAMES[ai.state]
		var cap := ship.fuel_capacity()
		var fuel := ship.fuel_amount() / cap * 100.0 if cap > 0.0 else 100.0
		status = "K2 %s  ·  %s  ·  %s  ·  yakıt %%%d" % [flight.pilot_name, Wingman.ORDER_NAMES[ai.order], st, fuel]
		# işaret
		var p := ship.com_global()
		var d := p.distance_to(me.com_global())
		var dt := "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % d
		if not cam.is_position_behind(p):
			var sp := cam.unproject_position(p)
			if Rect2(Vector2.ZERO, size).grow(-20).has_point(sp):
				var r := clampf(4000.0 / maxf(d, 1.0), 9.0, 22.0)
				var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0), sp + Vector2(0, -r)])
				draw_polyline(pts, SHADOW, 3.0)
				draw_polyline(pts, FRIEND, 1.6)
				_text(sp + Vector2(0, -r - 6), "K2", 13, FRIEND, _bold)
				_text(sp + Vector2(0, r + 15), dt, 11, FRIEND)
				_status(status)
				return
		# ekran dışı: kenarda ok
		var local := cam.global_basis.inverse() * (p - cam.global_position)
		var dir := Vector2(local.x, -local.y)
		dir = dir.normalized() if dir.length() > 0.001 else Vector2.UP
		var c := size * 0.5
		var e := c + dir * (minf(c.x, c.y) - 46.0)
		var n := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([e + dir * 12, e + n * 7, e - n * 7]), Color(FRIEND, 0.85))
		_text(e - dir * 16 + Vector2(0, 4), "K2 " + dt, 11, FRIEND, _bold)
	else:
		match flight.outcome:
			"üste":
				status = "K2 %s  ·  üste" % flight.pilot_name
			"kayıp":
				status = "K2 %s  ·  DÜŞTÜ" % flight.pilot_name
			_:
				status = "K2 %s  ·  fırlattı" % flight.pilot_name
	_status(status)


## Durum satırı: eylem panelinin hemen üstü.
func _status(t: String) -> void:
	# savaş panelinde kanat adamı bölümü açıksa durum satırı orada; burada tekrarlama
	var cp: Variant = flight.main.hud.get("combat_panel") if is_instance_valid(flight.main.hud) else null
	if cp is Control and (cp as Control).visible and not bool((cp as Control).get("collapsed")):
		return
	var bar: Control = flight.main.action_bar
	var y := bar.position.y - 10.0 if is_instance_valid(bar) and bar.visible else size.y - 20.0
	draw_string(_font, Vector2(15, y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SHADOW)
	draw_string(_font, Vector2(14, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FRIEND if flight.flying() else Color(1.0, 0.72, 0.25))
