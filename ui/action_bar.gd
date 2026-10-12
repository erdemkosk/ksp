class_name ActionBar
extends Control
## Eylem paneli (sol alt): uçaktaki etkinleştirilebilir parçalar ve sistemler, 1-9 tuşları
## ya da tıklama ile istenen an tetiklenir — KSP'deki eylem grupları gibi. Liste uçağın
## parçalarından kurulur: fren paraşütü, hava freni, iniş takımı, fişek, motor, kanopi,
## otomatik iniş, uçuşu bitir. En altta FIRLAT (fırlatma koltuğu): ⌫ iki kez ya da iki tık.
## F2: telsiz menüsü (kalkış/iniş izni, yön, hava durumu, acil durum); açıkken 1-6 telsizdir.

const ROW_H := 24.0
const W := 236.0
const ACC := Color(0.45, 1.0, 0.65)
const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.32, 0.26)
const DIM := Color(0.6, 0.68, 0.74)

var main: Node
var radio_mode := false
var collapsed := false

var _font := SystemFont.new()
var _bold := SystemFont.new()
var _items: Array[Dictionary] = []
var _hover := -1
var _eject_arm := 0.0
var _flash := {}
var _t := 0.0
var _end_btn: Button
var _end_layer: CanvasLayer


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_end_btn = Button.new()
	_end_btn.focus_mode = Control.FOCUS_NONE
	_end_btn.theme = UiTheme.get_theme()
	_end_btn.add_theme_font_size_override("font_size", 20)
	var sb := UiTheme.flat(Color(0.1, 0.45, 0.25, 0.92), 10)
	sb.set_content_margin_all(12)
	_end_btn.add_theme_stylebox_override("normal", sb)
	var sbh := UiTheme.flat(Color(0.14, 0.58, 0.32, 0.95), 10)
	sbh.set_content_margin_all(12)
	_end_btn.add_theme_stylebox_override("hover", sbh)
	_end_btn.pressed.connect(func() -> void: main.end_flight())
	_end_btn.visible = false
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 9
	add_child(_end_layer)
	_end_layer.add_child(_end_btn)
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	mouse_filter = Control.MOUSE_FILTER_STOP


func _vessel() -> Vessel:
	return main.vessel if main and is_instance_valid(main.vessel) else null


func _active() -> bool:
	if _on_foot():
		return true
	var v := _vessel()
	return v != null and v.is_inside_tree() and v.has_pilot() and not main.camera.is_eva()


## Pilot uçak dışında, yerde (indi ya da paraşütle kurtuldu): sadece uçuşu bitir.
func _on_foot() -> bool:
	return main != null and is_instance_valid(main.pilot) and not main.pilot.airborne


func _process(delta: float) -> void:
	_t += delta
	_update_end_banner()
	_eject_arm = maxf(_eject_arm - delta, 0.0)
	for k in _flash.keys():
		_flash[k] = maxf(float(_flash[k]) - delta * 3.0, 0.0)
	visible = _active()
	if not visible:
		radio_mode = false
		return
	UiTheme.fade_panel(self, delta)
	_items = _radio_items() if radio_mode and not _on_foot() else _action_items()
	var vp := get_viewport_rect().size
	var h := 30.0 + (0.0 if collapsed else _items.size() * ROW_H + 6.0)
	size = Vector2(W, h)
	position = Vector2(14, vp.y - h - 14)
	queue_redraw()


# ------------------------------------------------------------------ öğeler

func _item(label: String, state: String, col: Color, act: Callable, key := "") -> Dictionary:
	return {"label": label, "state": state, "col": col, "act": act, "key": key}


func _action_items() -> Array[Dictionary]:
	var v := _vessel()
	var out: Array[Dictionary] = []
	if _on_foot():
		out.append(_item("Uçuşu bitir", "RAPOR", ACC, main.end_flight))
		if not main._ejected:
			out.append(_item("Uçağa bin", "F", DIM, main.try_board))
		return out
	var chutes := v.get_modules_of(ChuteModule)
	if not chutes.is_empty():
		var c: ChuteModule = chutes[0]
		var st: String = ["PAKETTE", "AÇIK", "KULLANILDI"][c.state]
		out.append(_item("Fren paraşütü" if c.state != 1 else "Paraşütü kes", st, ACC if c.state == 0 else (AMBER if c.state == 1 else DIM),
			func() -> void:
				for m in v.get_modules_of(ChuteModule):
					if m.state == 0:
						m.deploy()
					elif m.state == 1:
						m.release()))
	var brakes := v.get_modules_of(AirbrakeModule)
	if not brakes.is_empty():
		var on: bool = brakes[0].hold
		out.append(_item("Hava freni", "AÇIK" if on else "KAPALI", AMBER if on else DIM, func() -> void:
			for m in v.get_modules_of(AirbrakeModule):
				m.hold = not on))
	if not v.get_modules_of(LandingGearModule).is_empty():
		out.append(_item("İniş takımı", "AŞAĞI" if v.gear_down else "YUKARI", ACC if v.gear_down else DIM,
			func() -> void: v.gear_down = not v.gear_down))
	if v.flares_left() > 0:
		out.append(_item("Fişek at", "×%d" % v.flares_left(), ACC, func() -> void: v.drop_flares()))
	if not v.engines().is_empty():
		var run := v.engines_running()
		out.append(_item("Motor", "ÇALIŞIYOR" if run else "KAPALI", ACC if run else DIM, func() -> void:
			if v.engines_running():
				v.shutdown_engines()
			else:
				v.auto_start()))
	if v.cockpit():
		var open := v.cockpit().canopy_open
		out.append(_item("Kanopi", "AÇIK" if open else "KAPALI", AMBER if open else DIM,
			func() -> void: v.cockpit().canopy_open = not v.cockpit().canopy_open))
	if is_instance_valid(main.autoland):
		out.append(_item("Otomatik inişi bırak", "PİLOT İNDİRİYOR", Color(0.4, 0.85, 1.0), main.cancel_autoland))
	elif v.radar_altitude() > 20.0:
		out.append(_item("Pilot indirsin", "OTOMATİK İNİŞ", Color(0.4, 0.85, 1.0), main.start_autoland))
	if main.can_end_flight():
		out.append(_item("Uçuşu bitir", "RAPOR", ACC, main.end_flight))
	for m in v.modules:
		if m is TargetingPodModule:
			out.append(_item("Hedefleme podu", "F8", ACC if main.pod_panel.open else DIM, main.pod_panel.toggle))
			break
	out.append(_item("Telsiz…", "F2", DIM, func() -> void: radio_mode = true))
	out.append(_item("FIRLAT", "⌫ ⌫" if _eject_arm <= 0.0 else "TEKRAR BAS!", RED, _eject_press, "⌫"))
	return out


func _radio_items() -> Array[Dictionary]:
	var r: Radio = main.radio
	var out: Array[Dictionary] = []
	out.append(_item("Kalkış izni iste", "", ACC, func() -> void: r.request("takeoff")))
	out.append(_item("İniş izni iste", "", ACC, func() -> void: r.request("landing")))
	out.append(_item("En yakın meydana yön", "", ACC, func() -> void: r.request("vector")))
	out.append(_item("Hava durumu", "", ACC, func() -> void: r.request("weather")))
	out.append(_item("ACİL DURUM (mayday)", "", RED, func() -> void: r.request("mayday")))
	out.append(_item("Pilot indirsin", "OTOMATİK", Color(0.4, 0.85, 1.0), main.start_autoland))
	out.append(_item("◀ Geri", "F2", DIM, func() -> void: radio_mode = false))
	return out


func _eject_press() -> void:
	if _eject_arm > 0.0:
		_eject_arm = 0.0
		main.eject()
	else:
		_eject_arm = 1.5
		Sfx.play_ui("switch_4.ogg", -6.0, 0.7)


func _run(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	var it := _items[i]
	_flash[i] = 1.0
	if it["label"] != "FIRLAT":
		Sfx.click()
	var was_radio := radio_mode
	it["act"].call()
	if was_radio and it["label"] != "◀ Geri":
		radio_mode = false


# ------------------------------------------------------------------ girdi

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if (k == KEY_ENTER or k == KEY_KP_ENTER) and _end_btn.visible:
		main.end_flight()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F2:
		radio_mode = not radio_mode
		collapsed = false
		Sfx.click()
		get_viewport().set_input_as_handled()
	elif k == KEY_BACKSPACE:
		_eject_press()
		get_viewport().set_input_as_handled()
	elif k >= KEY_1 and k <= KEY_9 and not event.ctrl_pressed and not event.alt_pressed:
		var n := k - KEY_1
		# FIRLAT numarayla tetiklenmez (yanlışlıkla atılmasın): sadece ⌫ ya da tık
		if n < _items.size() and _items[n]["label"] != "FIRLAT":
			_run(n)
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _hit(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y < 28.0:
			collapsed = not collapsed
			Sfx.click()
		else:
			_run(_hit(event.position))
		accept_event()


func _hit(p: Vector2) -> int:
	if collapsed:
		return -1
	var i := int((p.y - 30.0) / ROW_H)
	return i if p.y >= 30.0 and i < _items.size() else -1


# ------------------------------------------------------------------ çizim

func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.02, 0.03, 0.8)
	sb.border_color = Color(ACC, 0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var title := "TELSİZ" if radio_mode else "EYLEMLER"
	draw_string(_bold, Vector2(12, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACC)
	var hint := ("1-%d · F2 kapat" % (_items.size() - 1)) if radio_mode else ("1-9 · F2 telsiz  " + ("▲" if collapsed else "▼"))
	var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_font, Vector2(W - hw - 12, 19), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	if collapsed:
		return
	for i in _items.size():
		var it := _items[i]
		var y := 30.0 + i * ROW_H
		var r := Rect2(6, y, W - 12, ROW_H - 2)
		var eject: bool = it["label"] == "FIRLAT"
		var bg := Color(1, 1, 1, 0.0)
		if eject:
			var pulse := 0.5 + 0.5 * sin(_t * 12.0) if _eject_arm > 0.0 else 0.0
			bg = Color(0.6, 0.06, 0.04, 0.55 + 0.4 * pulse)
		elif i == _hover:
			bg = Color(1, 1, 1, 0.08)
		bg = bg.lerp(Color(ACC, 0.35), float(_flash.get(i, 0.0)))
		if bg.a > 0.0:
			var rb := StyleBoxFlat.new()
			rb.bg_color = bg
			rb.set_corner_radius_all(5)
			draw_style_box(rb, r)
		var key: String = it["key"] if it["key"] != "" else str(i + 1)
		var kr := Rect2(r.position.x + 4, y + 3, 18, ROW_H - 8)
		var kb := StyleBoxFlat.new()
		kb.bg_color = Color(1, 1, 1, 0.1)
		kb.set_corner_radius_all(3)
		draw_style_box(kb, kr)
		var kw := _bold.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_bold, Vector2(kr.get_center().x - kw * 0.5, y + 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_string(_bold if eject else _font, Vector2(r.position.x + 30, y + 16), it["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color.WHITE if eject else Color(0.9, 0.93, 0.95))
		var st: String = it["state"]
		if st != "":
			var sw := _bold.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(_bold, Vector2(r.end.x - sw - 6, y + 15), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, it["col"] if not eject else Color.WHITE)


## Uçak yerde durunca (ya da pilot inince) ekranın üstünde büyük "bitir" düğmesi; Enter da basar.
func _update_end_banner() -> void:
	var show: bool = main != null and is_instance_valid(main.vessel) and main.can_end_flight() and not get_tree().paused and (main.has_flown or main._ejected)
	_end_btn.visible = show
	if not show:
		return
	var in_mission: bool = main.mission != null and not main.mission.def.is_empty()
	_end_btn.text = "  ✓  %s   (Enter)  " % ("GÖREVİ BİTİR" if in_mission else "UÇUŞU BİTİR")
	var vp := get_viewport_rect().size
	_end_btn.reset_size()
	_end_btn.position = Vector2((vp.x - _end_btn.size.x) * 0.5, 70)
