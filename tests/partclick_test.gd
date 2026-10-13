extends Node
## --air --partclicktest : uçuşta bir parçanın ekran konumuna gerçek sağ tık (bas + bırak) gönderir,
## parça penceresi açıldı mı yazar. Açılmazsa tıklamayı hangi düğümün yuttuğunu arar.

var main: Node


func _ready() -> void:
	await get_tree().create_timer(2.5).timeout
	var cam: FlightCamera = main.camera
	var v: Vessel = main.vessel
	var pw: PartWindows = main.hud.part_windows
	var target: Part = null
	for p in v.parts:
		if p.part_id.begins_with("wing"):
			target = p
			break
	if target == null:
		target = v.parts[0]
	var sp := cam.unproject_position(target.global_position)
	print("PCT kamera modu=%d  imleç modu=%d  hedef=%s ekran=%s  ışın parçası=%s  gui üstte=%s" % [
		cam.mode, Input.mouse_mode, target.title, sp, pw._part_at(sp), get_viewport().gui_get_hovered_control()])
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = sp
		e.global_position = sp
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	print("PCT pencere sayısı=%d  aktif=%s  katman boyutu=%s  ekran=%s" % [pw._windows.size(), pw._active(), pw.size, get_viewport().get_visible_rect().size])
	for p in pw._windows:
		var w: Control = pw._windows[p]["window"]
		print("PCT pencere %s konum=%s boyut=%s görünür=%s" % [p.title, w.position, w.size, w.is_visible_in_tree()])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/../pct.png")
	get_tree().quit()
