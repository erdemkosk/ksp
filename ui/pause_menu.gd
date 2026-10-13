class_name PauseMenu
extends CanvasLayer
## Esc: oyunu duraklatır. Devam · Yeniden başlat · Ayarlar · Hangar · Ana menü.

var main: Node
var _root: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var t := UiTheme.title("DURAKLATILDI", 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(UiTheme.big_button("▶  Devam", toggle, true))
	box.add_child(UiTheme.big_button("Yeniden başlat", _restart))
	box.add_child(UiTheme.big_button("Ayarlar", func() -> void:
		var d := SettingsDialog.open(self)
		d.changed.connect(func() -> void:
			if main and main.player:
				main.player.apply_pilot())))
	box.add_child(UiTheme.big_button("Hangar", _hangar))
	box.add_child(UiTheme.big_button("Ana menü", _menu))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_root.visible = not _root.visible
	get_tree().paused = _root.visible
	if _root.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _leave() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# kariyerde gerçek görevi yarıda bırakmak geri çekilme sayılır: görev başarısız, cephe geriler
	if main and main.mission and main.mission.state == "running" and not Career.sandbox() and not Game.test_flight:
		var d: Dictionary = main.mission.def
		main.mission.state = "fail"
		Career.mission_finished(String(d.get("id", "")), int(d.get("level", 1)), false)
	if main:
		main.close_flight(false)
	FloatingOrigin.reset_world()
	FloatingOrigin.world_root = null
	Planet.reset()


func _restart() -> void:
	_leave()
	get_tree().reload_current_scene()


func _hangar() -> void:
	_leave()
	get_tree().change_scene_to_file("res://hangar/hangar.tscn")


func _menu() -> void:
	_leave()
	get_tree().change_scene_to_file("res://menu/main_menu.tscn")
