class_name SettingsDialog
extends PopupPanel
## Ayarlar: fareyle uçuş, fare hassasiyeti, ana ses, kokpit görüş açısı, kamera sarsıntısı,
## telsiz konuşmaları. Değişiklikler hemen uygulanır ve kaydedilir.

signal changed


static func open(parent: Node) -> SettingsDialog:
	var d := SettingsDialog.new()
	d.theme = UiTheme.get_theme()
	parent.add_child(d)
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	d._build()
	d.popup_centered(Vector2i(460, 420))
	d.popup_hide.connect(d.queue_free)
	return d


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	box.add_child(UiTheme.title("AYARLAR"))
	var s: Dictionary = Game.settings
	_check(box, "Fareyle uçuşla başla (TAB ile de açılır)", "mouse_aim")
	_slider(box, "Fare hassasiyeti", "mouse_sens", 0.3, 2.5, 0.05)
	_slider(box, "Ana ses", "volume", 0.0, 1.0, 0.01)
	_slider(box, "Kokpit görüş açısı (°)", "fov", 60.0, 100.0, 1.0)
	_slider(box, "Kamera sarsıntısı", "shake", 0.0, 1.5, 0.05)
	_slider(box, "Panel saydamlığı (fare üstünde değilken)", "panel_alpha", 0.2, 1.0, 0.05)
	_check(box, "Telsiz konuşmaları (kule, radar)", "radio")
	_check(box, "G sınırlayıcı (pilotu bayıltacak manevrayı kumanda kısar)", "g_limit")
	_check(box, "Tam ekran (F11)", "fullscreen")
	_check(box, "Serbest mod (tüm parçalar ve görevler açık, para yok)", "sandbox")
	var hint := Label.new()
	hint.text = "Gamepad: sol çubuk burun/yatış, sağ çubuk sapma/gaz, RT ateş, LT fren, LB flare."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var close := Button.new()
	close.text = "Kapat"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	box.add_child(close)


func _check(parent: Control, text: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Game.settings.get(key, true))
	c.toggled.connect(func(on: bool) -> void:
		Game.settings[key] = on
		Game.save_settings()
		changed.emit())
	parent.add_child(c)


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 190
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Game.settings.get(key, lo))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	var v := Label.new()
	v.custom_minimum_size.x = 48
	v.text = "%.2f" % sl.value if hi <= 3.0 else "%d" % sl.value
	sl.value_changed.connect(func(x: float) -> void:
		Game.settings[key] = x
		v.text = "%.2f" % x if hi <= 3.0 else "%d" % x
		Game.save_settings()
		changed.emit())
	row.add_child(sl)
	row.add_child(v)
	parent.add_child(row)
