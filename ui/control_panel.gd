class_name ControlPanel
extends Control
## Dış kameralarda (takip/serbest) ekranın sağındaki kumanda paneli.
## Kokpitteki anahtarların aynısı: batarya, JFS, marş, kapaklı yakıt kesme ve master arm,
## SAS, otopilot, iniş takımı, park freni, kanopi, ışıklar + N2, G ve yapı yükü göstergeleri.
## Gerçek uçak paneli gibi çizilir. Kenardaki sekme ya da N tuşu ile katlanır.

const W := 280.0
const PANEL_BG := Color(0.13, 0.15, 0.15, 0.94)
const PANEL_EDGE := Color(0.32, 0.35, 0.35)
const ENGRAVE := Color(0.86, 0.88, 0.84)
const LIT_GREEN := Color(0.35, 1.0, 0.5)
const LIT_AMBER := Color(1.0, 0.72, 0.2)
const GUARD_RED := Color(0.78, 0.1, 0.08)

var vessel: Vessel
var player: PlayerController
var camera: FlightCamera
var collapsed := false

var _font := SystemFont.new()
var _font_bold := SystemFont.new()
var _items: Array[Dictionary] = []
var _hover := -1
var _covers := {}          # kalem adı -> kapak açık mı
var _cover_timer := {}
var _press := {}           # kalem adı -> basılma animasyonu
var _slide := 0.0          # 0 açık, 1 katlanmış


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_font_bold.font_names = _font.font_names
	_font_bold.font_weight = 700
	mouse_filter = Control.MOUSE_FILTER_STOP
	_define_items()


func _define_items() -> void:
	# [ad, tür, bölüm satırı, sütun, durum, eylem]
	_add("BATARYA", "toggle", 0, 0, func() -> bool: return vessel.battery_on,
		func() -> void: vessel.battery_on = not vessel.battery_on)
	_add("JFS", "button", 0, 1, func() -> bool: return vessel.jfs_on,
		func() -> void: vessel.jfs_on = not vessel.jfs_on and vessel.has_power())
	_add("MOTOR ÇALIŞTIR", "button", 1, 0, func() -> bool: return _starting(),
		func() -> void: vessel.start_engines())
	_add("YAKIT KES", "guarded", 1, 1, func() -> bool: return not vessel.engines_running(),
		func() -> void: vessel.shutdown_engines())
	_add("SAS", "toggle", 2, 0, func() -> bool: return vessel.sas,
		func() -> void: vessel.sas = not vessel.sas)
	_add("OTOPİLOT", "button", 2, 1, func() -> bool: return vessel.autopilot_active,
		func() -> void: player.toggle_autopilot())
	_add("İNİŞ TAKIMI", "gear", 3, 0, func() -> bool: return vessel.gear_down,
		func() -> void: vessel.gear_down = not vessel.gear_down)
	_add("PARK FRENİ", "toggle", 3, 1, func() -> bool: return vessel.parking_brake,
		func() -> void: vessel.parking_brake = not vessel.parking_brake)
	_add("KANOPİ", "button", 4, 0, func() -> bool: return vessel.cockpit() != null and vessel.cockpit().canopy_open,
		func() -> void:
			if vessel.cockpit():
				vessel.cockpit().canopy_open = not vessel.cockpit().canopy_open)
	_add("SEYİR IŞIKLARI", "toggle", 4, 1, func() -> bool: return vessel.lights_on,
		func() -> void: vessel.lights_on = not vessel.lights_on)
	_add("MASTER ARM", "guarded", 5, 0, func() -> bool: return vessel.master_arm,
		func() -> void: vessel.master_arm = not vessel.master_arm)
	_add("KOKPİT IŞIĞI", "button", 5, 1, func() -> bool: return vessel.cockpit_light,
		func() -> void: vessel.cockpit_light = not vessel.cockpit_light)


func _add(label: String, kind: String, row: int, col: int, getter: Callable, action: Callable) -> void:
	_items.append({"label": label, "kind": kind, "row": row, "col": col, "get": getter, "act": action})


func _starting() -> bool:
	for e in vessel.engines():
		if e.state == EngineModule.State.CRANKING:
			return true
	return false


func _visible_now() -> bool:
	return is_instance_valid(vessel) and vessel.is_inside_tree() and is_instance_valid(camera) \
		and camera.mode != FlightCamera.Mode.COCKPIT and not camera.is_eva() and vessel.has_pilot() and Hud.panels_open


func _process(delta: float) -> void:
	var show := _visible_now()
	visible = show
	if not show:
		return
	UiTheme.fade_panel(self, delta)
	_slide = move_toward(_slide, 1.0 if collapsed else 0.0, delta * 5.0)
	var vp := get_viewport_rect().size
	size = Vector2(W + 26, 600)
	position = Vector2(vp.x - 26 - W * (1.0 - _slide), vp.y * 0.5 - 300 + 40)
	for k in _cover_timer.keys():
		if _covers.get(k, false):
			_cover_timer[k] += delta
			var item := _item_named(k)
			if _cover_timer[k] > 4.0 and not bool(item["get"].call()):
				_covers[k] = false
	for k in _press.keys():
		_press[k] = move_toward(_press[k], 0.0, delta * 6.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _hit(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Rect2(0, 0, 26, 110).has_point(event.position):
			collapsed = not collapsed
			Sfx.play_ui("switch_3.ogg", -10.0, 0.8)
			accept_event()
			return
		var i := _hit(event.position)
		if i >= 0:
			_activate(_items[i])
		accept_event()


func _activate(item: Dictionary) -> void:
	var name: String = item["label"]
	if item["kind"] == "guarded" and not _covers.get(name, false):
		_covers[name] = true
		_cover_timer[name] = 0.0
		Sfx.play_ui("switch_4.ogg", -8.0, 0.7)
		return
	_cover_timer[name] = 0.0
	_press[name] = 1.0
	Sfx.click()
	item["act"].call()


func _item_named(name: String) -> Dictionary:
	for it in _items:
		if it["label"] == name:
			return it
	return {}


func _item_rect(item: Dictionary) -> Rect2:
	var x := 26.0 + 18.0 + float(item["col"]) * 128.0
	var y := 62.0 + float(item["row"]) * 70.0
	return Rect2(x, y, 116, 56)


func _hit(p: Vector2) -> int:
	for i in _items.size():
		if _item_rect(_items[i]).has_point(p):
			return i
	return -1


# ------------------------------------------------------------------ çizim

func _draw() -> void:
	if not _visible_now():
		return
	# sekme
	var tab := Rect2(0, 0, 26, 110)
	draw_style_box(_box(PANEL_BG, 6), tab)
	draw_string(_font_bold, Vector2(8, 62), "▶" if not collapsed else "◀", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ENGRAVE)
	# panel gövdesi
	var body := Rect2(26, 0, W, size.y)
	draw_style_box(_box(PANEL_BG, 8, PANEL_EDGE), body)
	for c in [Vector2(36, 10), Vector2(26 + W - 10, 10), Vector2(36, size.y - 10), Vector2(26 + W - 10, size.y - 10)]:
		draw_circle(c, 3.5, Color(0.42, 0.44, 0.44))
		draw_line(c - Vector2(2.5, 0), c + Vector2(2.5, 0), Color(0.2, 0.22, 0.22), 1.0)
	_text_c(Vector2(26 + W * 0.5, 34), "KUMANDA PANELİ", 15, ENGRAVE, _font_bold)
	draw_line(Vector2(40, 44), Vector2(26 + W - 14, 44), Color(1, 1, 1, 0.12), 1.0)

	var powered := vessel.has_power()
	for i in _items.size():
		_draw_item(_items[i], i == _hover, powered)

	_draw_gauges(Rect2(26 + 14, 62 + 6 * 70.0, W - 28, 118), powered)


func _draw_item(item: Dictionary, hover: bool, powered: bool) -> void:
	var r := _item_rect(item)
	var on := bool(item["get"].call())
	var name: String = item["label"]
	draw_style_box(_box(Color(0, 0, 0, 0.25 if not hover else 0.45), 6, Color(1, 1, 1, 0.08 if not hover else 0.25)), r)
	var center := r.position + Vector2(r.size.x * 0.5, 22)
	match item["kind"]:
		"button":
			var sq := Rect2(center - Vector2(22, 13), Vector2(44, 26)).grow(-_press.get(name, 0.0) * 2.0)
			var lit := on and powered
			draw_style_box(_box(Color(0.06, 0.07, 0.07), 4, Color(0.4, 0.42, 0.42)), sq)
			var lamp := Rect2(sq.position + Vector2(6, 8), Vector2(sq.size.x - 12, sq.size.y - 16))
			draw_rect(lamp, (LIT_GREEN if name != "MOTOR ÇALIŞTIR" else LIT_AMBER) if lit else Color(0.12, 0.16, 0.13))
			if lit:
				draw_rect(lamp.grow(4), Color(LIT_GREEN, 0.15))
		"gear":
			# tekerlek başlıklı kol + üç takım lambası
			var deploy := vessel.gear_deploy()
			var tip := center + Vector2(-26, 12 if on else -12)
			draw_line(center + Vector2(-26, 0), tip, Color(0.75, 0.76, 0.76), 4.0)
			draw_circle(tip, 7.0, Color(0.92, 0.92, 0.9))
			for k in 3:
				var lc := Color(0.12, 0.12, 0.12)
				if powered and deploy >= 0.99:
					lc = LIT_GREEN
				elif powered and deploy > 0.01:
					lc = Color(1.0, 0.2, 0.15)
				draw_circle(center + Vector2(4 + k * 14, 0), 5.0, lc)
		_:
			# kollu anahtar
			draw_circle(center, 11.0, Color(0.08, 0.09, 0.09))
			draw_arc(center, 11.0, 0, TAU, 24, Color(0.45, 0.47, 0.47), 1.5)
			var tip := center + Vector2(0, -15 if on else 15)
			draw_line(center, tip, Color(0.82, 0.83, 0.83), 4.0)
			draw_circle(tip, 4.5, Color(0.92, 0.92, 0.9))
			if item["kind"] == "guarded":
				var open: bool = _covers.get(name, false)
				var cover := Rect2(center - Vector2(18, 20), Vector2(36, 40))
				if open:
					cover = Rect2(center - Vector2(18, 38), Vector2(36, 14))   # kalkık kapak
				draw_rect(cover, Color(GUARD_RED, 0.92 if not open else 0.85))
				draw_rect(cover, Color(1, 0.5, 0.45, 0.6), false, 1.5)
				for s in 3:
					draw_line(cover.position + Vector2(4, 6 + s * 8), cover.position + Vector2(cover.size.x - 4, 6 + s * 8),
						Color(0.4, 0.04, 0.03, 0.8), 1.0)
	_text_c(r.position + Vector2(r.size.x * 0.5, r.size.y - 6), name, 11, ENGRAVE, _font_bold)


func _draw_gauges(r: Rect2, powered: bool) -> void:
	draw_style_box(_box(Color(0.02, 0.03, 0.03), 6, Color(0.35, 0.38, 0.38)), r)
	if not powered:
		_text_c(r.get_center() + Vector2(0, 5), "GÜÇ YOK", 14, Color(0.5, 0.3, 0.25), _font_bold)
		return
	# N2 kadranı
	var eng: EngineModule = vessel.engines()[0] if not vessel.engines().is_empty() else null
	var n2 := eng.n2 if eng else 0.0
	var c := r.position + Vector2(56, 64)
	draw_arc(c, 38, deg_to_rad(135), deg_to_rad(405), 40, Color(0.25, 0.28, 0.28), 4.0)
	draw_arc(c, 38, deg_to_rad(135), deg_to_rad(135 + 270 * clampf(n2 / 1.1, 0, 1)), 40, LIT_GREEN, 4.0)
	var a := deg_to_rad(135 + 270 * clampf(n2 / 1.1, 0, 1))
	draw_line(c, c + Vector2(cos(a), sin(a)) * 32, Color.WHITE, 2.0)
	_text_c(c + Vector2(0, 26), "N2 %d%%" % (n2 * 100.0), 12, LIT_GREEN)
	var st := "KAPALI"
	if eng and eng.state == EngineModule.State.CRANKING:
		st = "MARŞ"
	elif eng and eng.is_running():
		st = "AB" if eng.afterburner > 0.5 else "ÇALIŞIYOR"
	_text_c(c + Vector2(0, 46), st, 12, LIT_AMBER if st != "ÇALIŞIYOR" else LIT_GREEN, _font_bold)
	# G ve yapı yükü
	var x := r.position.x + 120
	draw_string(_font, Vector2(x, r.position.y + 24), "G  %+.1f" % vessel.g_force, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LIT_GREEN)
	draw_string(_font, Vector2(x, r.position.y + 50), "YAPI YÜKÜ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ENGRAVE)
	var bar := Rect2(x, r.position.y + 56, r.size.x - 132, 10)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var stress := clampf(vessel.max_stress, 0.0, 1.0)
	var col := LIT_GREEN if stress < 0.7 else (LIT_AMBER if stress < 0.9 else Color(1, 0.25, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * stress, bar.size.y)), col)
	draw_string(_font, Vector2(x, r.position.y + 88), "YAKIT %d kg" % vessel.fuel_amount(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ENGRAVE)
	if vessel.master_arm:
		draw_string(_font_bold, Vector2(x, r.position.y + 108), "ARM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.3, 0.25))


func _box(bg: Color, radius: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	return s


func _text_c(pos: Vector2, text: String, font_size: int, col: Color, font: Font = null) -> void:
	var f := font if font else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(f, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
