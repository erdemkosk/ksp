class_name FlightPanels
extends Control
## Sağ üstte araç çubuğu + açılır pencereler: Uçuş bilgisi, Otopilot, Ortam, Tuşlar.

const HELP := [
	["UÇUŞ", [["W / S", "burun aşağı / yukarı"], ["Q / E", "yatış"], ["A / D", "sapma"],
		["Shift / Ctrl", "gaz + / −"], ["Z / X", "tam gaz / gaz kes"], ["Alt + W/S", "trim"], ["T", "SAS"], ["U", "otopilot"]]],
	["SİSTEMLER", [["G", "iniş takımı"], ["B / P", "fren / park freni"], ["N", "kumanda paneli"], ["I", "motor aç / kapa"], ["L", "ışıklar"],
		["K", "kanopi"], ["F", "dışarı çık / uçağa bin"], ["R / H", "piste dön / havada başla"]]],
	["FARE / PANEL", [["TAB", "fareyle uçuş aç / kapa (isteğe bağlı)"], ["N", "paneller (savaş, kumanda, pencereler)"], ["Alt (basılı)", "geçici imleç"], ["Esc", "duraklat"]]],
	["EYLEMLER", [["1-9", "eylem paneli (paraşüt, hava freni, takım, pilot indirsin, uçuşu bitir)"], ["⌫ ⌫", "FIRLATMA KOLTUĞU"], ["F2", "telsiz: kalkış / iniş izni, yön, hava, mayday"], ["M", "harita"], ["F9 / F10", "kaydet / kayıttan devam"], ["F8", "hedefleme podu (numpad: kaydır 8/2/4/6, +/- yakın, 5 kilit, 0 mod)"], ["F11", "tam ekran"], ["Enter", "inince uçuşu / görevi bitir"]]],
	["SAVAŞ", [["Space", "ateş (füze kilitsiz de atılır)"], ["V", "silah seç (top / füze / bomba)"], ["F4 / tık", "radar hedefi seç"], ["O", "flare at"], ["F7", "saldırgan düşman"], ["J", "hangar"]]],
	["KAMERA", [["C", "takip / kokpit / serbest"], ["Sağ tık + sürükle", "etrafa bak"], ["Sağ tık (parça)", "parça penceresi"], ["Tekerlek", "yakınlaş"],
		["Orta tık", "bakışı sıfırla"], ["Sol tık (kokpit)", "anahtarları kullan"]]],
	["DÜNYA", [["F5 / F6", "hava durumu / saat"], ["F3", "aerodinamik debug"], ["F1", "tuşlar penceresi"]]],
]

var vessel: Vessel
var player: PlayerController

var _theme: Theme
var _windows := {}
var _flight_labels := {}
var _fuel_bar: ProgressBar
var _ap_buttons := {}
var _ap_values := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_theme = UiTheme.get_theme()

	var bar := HBoxContainer.new()
	bar.theme = _theme
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-16, 14)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)

	_add_window(bar, "flight", "Uçuş", _build_flight(), Vector2(-300, 70))
	_add_window(bar, "autopilot", "Otopilot", _build_autopilot(), Vector2(-620, 70))
	_add_window(bar, "env", "Ortam", _build_env(), Vector2(-300, 420))
	_add_window(bar, "help", "Tuşlar", _build_help(), Vector2(-760, 70))
	if Game.args.has("help"):     # tuş penceresi başta kapalı (F1 ile açılır)
		toggle("help")


func toggle(id: String) -> void:
	var w: UiWindow = _windows[id]["window"]
	w.visible = not w.visible
	_windows[id]["button"].button_pressed = w.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		toggle("help")
	elif event.is_action_pressed("autopilot_toggle") and player and is_instance_valid(vessel):
		player.toggle_autopilot()


func _process(_delta: float) -> void:
	visible = Hud.panels_open
	if not is_instance_valid(vessel) or not vessel.is_inside_tree():
		return
	if _windows["flight"]["window"].visible:
		_update_flight()
	if _windows["autopilot"]["window"].visible:
		_update_autopilot()


# ------------------------------------------------------------------ pencereler

func _add_window(bar: HBoxContainer, id: String, title: String, content: Control, pos: Vector2) -> void:
	var btn := Button.new()
	btn.text = title
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	bar.add_child(btn)
	var w := UiWindow.create(title.to_upper(), _theme)
	w.body.add_child(content)
	w.visible = false
	w.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	w.position = pos
	add_child(w)
	btn.toggled.connect(func(on: bool) -> void: w.visible = on)
	w.closed.connect(func() -> void: btn.button_pressed = false)
	_windows[id] = {"window": w, "button": btn}


func _build_flight() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	for key in ["Hava hızı", "Yer hızı", "İrtifa", "Yerden", "Dikey hız", "Yön", "Yunuslama", "Yatış",
			"Hücum açısı", "Mach", "G", "Gaz", "İtki", "Kütle", "Rüzgar", "Sistemler"]:
		var k := Label.new()
		k.text = key
		k.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
		grid.add_child(k)
		var v := Label.new()
		v.custom_minimum_size.x = 150
		grid.add_child(v)
		_flight_labels[key] = v
	var box := VBoxContainer.new()
	box.add_child(grid)
	var fl := Label.new()
	fl.text = "Yakıt"
	fl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	box.add_child(fl)
	_fuel_bar = ProgressBar.new()
	_fuel_bar.custom_minimum_size = Vector2(240, 16)
	box.add_child(_fuel_bar)
	return box


func _update_flight() -> void:
	var v := vessel
	var wind := Weather.wind_at(v.global_position)
	var vals := {
		"Hava hızı": "%d km/sa" % (v.airspeed() * 3.6),
		"Yer hızı": "%d km/sa" % (v.ground_speed() * 3.6),
		"İrtifa": "%d m" % v.altitude(),
		"Yerden": "%d m" % v.radar_altitude(),
		"Dikey hız": "%+d m/s" % v.vertical_speed(),
		"Yön": "%03d°" % v.heading_deg(),
		"Yunuslama": "%+.1f°" % v.pitch_deg(),
		"Yatış": "%+.1f°" % v.roll_deg(),
		"Hücum açısı": "%+.1f°" % v.aoa_deg(),
		"Mach": "%.2f" % v.mach(),
		"G": "%.1f" % v.g_force,
		"Gaz": "%d%%" % (v.ctrl_throttle * 100.0),
		"İtki": "%d kN" % (v.total_thrust() / 1000.0),
		"Kütle": "%d kg" % v.mass,
		"Rüzgar": "%d m/s" % wind.length(),
		"Sistemler": "%s%s%s%s" % ["TAKIM " if v.gear_down else "", "FREN " if v.parking_brake else "",
			"SAS " if v.sas else "", "" if v.engine_on else "MOTOR-KAPALI"],
	}
	for k in vals:
		_flight_labels[k].text = vals[k]
	_fuel_bar.value = 100.0 * v.fuel_amount() / maxf(v.fuel_capacity(), 1.0)


func _build_autopilot() -> Control:
	var box := VBoxContainer.new()
	box.add_child(_ap_row("level", "Kanat düzle", "", 0.0))
	box.add_child(_ap_row("hold_altitude", "İrtifa tut", "m", 100.0))
	box.add_child(_ap_row("hold_heading", "Yön tut", "°", 10.0))
	box.add_child(_ap_row("hold_speed", "Hız tut", "km/sa", 25.0))
	var off := Button.new()
	off.text = "Hepsini kapat  (U)"
	off.focus_mode = Control.FOCUS_NONE
	off.pressed.connect(func() -> void: player.autopilot.disengage())
	box.add_child(off)
	var hint := Label.new()
	hint.text = "Bir eksene elle dokunmak o ekseni pilota verir."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
	box.add_child(hint)
	return box


func _ap_row(field: String, title: String, unit: String, step: float) -> Control:
	var row := HBoxContainer.new()
	var toggle_btn := CheckButton.new()
	toggle_btn.text = title
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.custom_minimum_size.x = 150
	toggle_btn.toggled.connect(func(on: bool) -> void:
		var ap := player.autopilot
		if on and not ap.get(field):
			ap.capture(vessel)
		ap.set(field, on))
	row.add_child(toggle_btn)
	_ap_buttons[field] = toggle_btn
	if step > 0.0:
		var minus := Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		minus.pressed.connect(func() -> void: _ap_adjust(field, -step))
		row.add_child(minus)
		var val := Label.new()
		val.custom_minimum_size.x = 90
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		_ap_values[field] = [val, unit]
		var plus := Button.new()
		plus.text = "+"
		plus.focus_mode = Control.FOCUS_NONE
		plus.pressed.connect(func() -> void: _ap_adjust(field, step))
		row.add_child(plus)
	return row


func _ap_adjust(field: String, step: float) -> void:
	var ap := player.autopilot
	match field:
		"hold_altitude": ap.target_altitude = maxf(ap.target_altitude + step, 50.0)
		"hold_heading": ap.target_heading = fposmod(ap.target_heading + step, 360.0)
		"hold_speed": ap.target_speed = maxf(ap.target_speed + step / 3.6, 40.0)


func _update_autopilot() -> void:
	var ap := player.autopilot
	for field in _ap_buttons:
		_ap_buttons[field].set_pressed_no_signal(ap.get(field))
	_ap_values["hold_altitude"][0].text = "%d m" % ap.target_altitude
	_ap_values["hold_heading"][0].text = "%03d°" % ap.target_heading
	_ap_values["hold_speed"][0].text = "%d km/sa" % (ap.target_speed * 3.6)


func _build_env() -> Control:
	var box := VBoxContainer.new()
	var wl := Label.new()
	wl.text = "Hava durumu  (F5)"
	box.add_child(wl)
	var wgrid := GridContainer.new()
	wgrid.columns = 3
	for p in Weather.PRESETS:
		var b := Button.new()
		b.text = Weather.PRESETS[p]["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: Weather.set_preset(p))
		wgrid.add_child(b)
	box.add_child(wgrid)
	var tl := Label.new()
	tl.text = "Günün saati  (F6)"
	box.add_child(tl)
	var tgrid := HBoxContainer.new()
	for t in Weather.TIMES.size():
		var b := Button.new()
		b.text = Weather.TIMES[t]["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: Weather.set_time(t))
		tgrid.add_child(b)
	box.add_child(tgrid)
	var sl := Label.new()
	sl.text = "Zaman hızı  ( ,  / . )"
	box.add_child(sl)
	var sgrid := HBoxContainer.new()
	for i in Weather.TIME_SCALES.size():
		var b := Button.new()
		b.text = "x%d" % Weather.TIME_SCALES[i]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: Weather.time_scale_index = i)
		sgrid.add_child(b)
	box.add_child(sgrid)
	return box


func _build_help() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	for group in HELP:
		var col := VBoxContainer.new()
		var title := Label.new()
		title.text = group[0]
		title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
		col.add_child(title)
		for row in group[1]:
			var h := HBoxContainer.new()
			var k := Label.new()
			k.text = row[0]
			k.custom_minimum_size.x = 140
			k.add_theme_color_override("font_color", Color(1, 0.85, 0.55))
			h.add_child(k)
			var d := Label.new()
			d.text = row[1]
			h.add_child(d)
			col.add_child(h)
		grid.add_child(col)
	return grid


func _make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	t.default_font = font
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.06, 0.08, 0.86)
	panel.border_color = Color(1, 1, 1, 0.1)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.08, 0.11, 0.14, 0.88)
	btn.border_color = Color(1, 1, 1, 0.12)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(6)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 4
	btn.content_margin_bottom = 4
	var hover := btn.duplicate()
	hover.bg_color = Color(0.14, 0.2, 0.24, 0.95)
	var pressed := btn.duplicate()
	pressed.bg_color = Color(0.12, 0.42, 0.28, 0.95)
	pressed.border_color = Color(0.45, 1.0, 0.65, 0.6)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_color", "Label", Color(0.9, 0.93, 0.95))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.08)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.35, 0.7, 1.0)
	bar_fill.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t
