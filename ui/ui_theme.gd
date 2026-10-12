class_name UiTheme
## Ortak arayüz teması (ana menü, hangar, uçuş pencereleri, duraklatma, brifing):
## koyu cam paneller, ince kenar, yeşil vurgu, yuvarlak köşeler, Bahnschrift yazı.

const ACCENT := Color(0.45, 1.0, 0.65)
const TEXT := Color(0.9, 0.93, 0.95)
const DIM := Color(0.65, 0.72, 0.8)
const PANEL := Color(0.04, 0.06, 0.08, 0.9)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	t.default_font = font
	t.default_font_size = 15
	var panel := flat(PANEL, 10)
	panel.border_color = Color(1, 1, 1, 0.1)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(12)
	for cls in ["PanelContainer", "PopupPanel", "Panel"]:
		t.set_stylebox("panel", cls, panel)
	var btn := flat(Color(0.09, 0.12, 0.15, 0.95), 6)
	btn.border_color = Color(1, 1, 1, 0.12)
	btn.set_border_width_all(1)
	var hover := btn.duplicate()
	hover.bg_color = Color(0.14, 0.2, 0.24)
	hover.border_color = Color(ACCENT, 0.4)
	var pressed := btn.duplicate()
	pressed.bg_color = Color(0.12, 0.42, 0.28)
	pressed.border_color = Color(ACCENT, 0.7)
	var disabled := btn.duplicate()
	disabled.bg_color = Color(0.07, 0.08, 0.09, 0.8)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	var edit := flat(Color(0.02, 0.03, 0.04, 0.9), 5)
	edit.border_color = Color(1, 1, 1, 0.12)
	edit.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_f := edit.duplicate()
	edit_f.border_color = Color(ACCENT, 0.6)
	t.set_stylebox("focus", "LineEdit", edit_f)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	var bar_bg := flat(Color(1, 1, 1, 0.08), 4)
	var bar_fill := flat(Color(0.35, 0.7, 1.0), 4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	var slider := flat(Color(1, 1, 1, 0.1), 3)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	var grab := flat(Color(ACCENT, 0.6), 3)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var tip := flat(Color(0.02, 0.03, 0.04, 0.95), 6)
	tip.set_content_margin_all(8)
	tip.border_color = Color(ACCENT, 0.3)
	tip.set_border_width_all(1)
	t.set_stylebox("panel", "TooltipPanel", tip)
	_theme = t
	return t


static func flat(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func title(text: String, size := 20) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func big_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 52)
	b.add_theme_font_size_override("font_size", 19)
	if primary:
		b.add_theme_stylebox_override("normal", flat(Color(0.12, 0.5, 0.28), 8))
		b.add_theme_stylebox_override("hover", flat(Color(0.16, 0.62, 0.35), 8))
	b.pressed.connect(cb)
	return b


## Paneller fare üstünde değilken ayardaki saydamlığa iner (ekran kalabalığı azalır).
static func fade_panel(c: Control, delta: float) -> void:
	var hovered := c.get_global_rect().has_point(c.get_global_mouse_position()) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	var target := 1.0 if hovered else float(Game.settings.get("panel_alpha", 0.6))
	c.modulate.a = move_toward(c.modulate.a, target, delta * 3.0)
