class_name FlightReport
extends CanvasLayer
## Uçuş sonu raporu: uçak yerde durunca ya da pilot paraşütle indikten sonra "Uçuşu bitir".
## Süre, uçuş bilgileri ve pilotun kazandığı tecrübe; Hangar · Tekrar uç · Ana menü.

var main: Node
var title_text := "UÇUŞ RAPORU"
var lines: PackedStringArray = []
var good := true


static func open(m: Node, title: String, info: PackedStringArray, success := true) -> FlightReport:
	var r := FlightReport.new()
	r.main = m
	r.title_text = title
	r.lines = info
	r.good = success
	m.add_child(r)
	return r


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	var sb := UiTheme.flat(Color(0.03, 0.045, 0.06, 0.97), 14)
	sb.set_content_margin_all(26)
	sb.border_color = Color(0.45, 1.0, 0.65) if good else Color(1.0, 0.45, 0.35)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 460
	panel.add_child(box)
	var t := UiTheme.title(title_text, 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65) if good else Color(1.0, 0.5, 0.4))
	box.add_child(t)
	for l in lines:
		if l.begins_with("MADALYA") or l.begins_with("TERFİ"):
			box.add_child(MedalView.report_line(l))   # kurdele / apolet ile vurgulu satır
			continue
		var lb := Label.new()
		lb.text = l
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if l.begins_with("SEVİYE") or "XP" in l:
			lb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		elif l.begins_with("◆"):
			lb.add_theme_color_override("font_color", Color(1.0, 0.62, 0.42))   # hikâye satırı (Campaign)
		box.add_child(lb)
	# görev kartıyla uçulduysa: tasarım değerlendirmesi (DesignDebrief)
	if not Game.mission_card.is_empty():
		box.add_child(DesignDebrief.build(Game.last_result, Game.mission_card))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiTheme.big_button("Hangar", func() -> void: _go("res://hangar/hangar.tscn"), true))
	row.add_child(UiTheme.big_button("Tekrar uç", func() -> void: _go("")))
	row.add_child(UiTheme.big_button("Ana menü" if Career.sandbox() else "Cephe haritası", func() -> void: _go("res://menu/main_menu.tscn")))


func _go(scene: String) -> void:
	get_tree().paused = false
	if scene != "":
		Game.mission = ""
		Game.mission_card = {}       # hangarda kart hazırlıktan (pending_op) yeniden gelir
		if not scene.begins_with("res://hangar"):
			Game.rehearsal = false
	FloatingOrigin.reset_world()
	FloatingOrigin.world_root = null
	Planet.reset()
	if scene == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(scene)
