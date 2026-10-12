class_name UiWindow
extends PanelContainer
## Başlık çubuğundan sürüklenebilen, kapatılabilen küçük pencere (KSP uygulama pencereleri gibi).

signal closed

var body: VBoxContainer

var _dragging := false
var _drag_offset := Vector2.ZERO


static func create(title: String, theme_res: Theme) -> UiWindow:
	var w := UiWindow.new()
	w.theme = theme_res
	w.mouse_filter = Control.MOUSE_FILTER_STOP
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	w.add_child(root)

	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(lbl)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		w.visible = false
		w.closed.emit())
	bar.add_child(close)
	bar.gui_input.connect(w._on_bar_input)
	root.add_child(bar)
	root.add_child(HSeparator.new())

	w.body = VBoxContainer.new()
	w.body.add_theme_constant_override("separation", 4)
	root.add_child(w.body)
	return w


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _dragging:
		var vp := get_viewport_rect().size
		global_position = (get_global_mouse_position() - _drag_offset).clamp(Vector2.ZERO, vp - size)
