extends Node3D
## Ana menü: arkada gün batımı göğünde yavaşça dönen son uçağın, solda menü.
## Hızlı Uçuş · Görevler · Hangar · Kadro · Ayarlar · Çıkış

var _cam: Camera3D
var _plane: Node3D
var _t := 0.0


func _ready() -> void:
	# uçuş/test argümanlarıyla açıldıysa doğrudan ilgili sahneye
	if not Game.args.is_empty() and not Game.args.has("menu"):
		var target := "res://hangar/hangar.tscn" if Game.args.has("hangar") else "res://main.tscn"
		get_tree().change_scene_to_file.call_deferred(target)
		return
	TerrainGen.init()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FloatingOrigin.world_root = self
	FloatingOrigin.offset_x = 0.0
	FloatingOrigin.offset_y = 0.0
	FloatingOrigin.offset_z = 0.0
	Planet.reset()
	_build_scene()
	_build_ui()


func _build_scene() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.16, 0.24, 0.42)
	sky.sky_horizon_color = Color(0.95, 0.62, 0.4)
	sky.ground_horizon_color = Color(0.5, 0.36, 0.3)
	sky.ground_bottom_color = Color(0.1, 0.1, 0.12)
	sky.sun_angle_max = 30.0
	var s := Sky.new()
	s.sky_material = sky
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.fog_enabled = false
	env.fog_light_color = Color(0.9, 0.6, 0.45)
	env.fog_density = 0.00025
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-12, -60, 0)
	sun.light_color = Color(1.0, 0.78, 0.6)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var craft: Dictionary = Game.flight_craft if not Game.flight_craft.is_empty() else VesselBuilder.load_craft("res://crafts/kartal_1.json")
	var v := VesselBuilder.build(craft)
	v.freeze = true
	add_child(v)
	v.set_physics_process(false)
	v.set_gear_instant(false)
	_plane = v
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)


func _process(delta: float) -> void:
	_t += delta
	if Game.args.has("screenshot") and _t > float(Game.args.get("shot-time", "3")):
		var path: String = Game.args["screenshot"]
		Game.args.erase("screenshot")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
	if _plane == null:
		return
	# hafif süzülme + yatış, kamera yavaşça etrafında döner
	_plane.rotation = Vector3(sin(_t * 0.4) * 0.05, 0.0, sin(_t * 0.3) * 0.15)
	_plane.position = Vector3(0, sin(_t * 0.6) * 0.3, 0)
	var a := _t * 0.12 + 2.2
	_cam.position = Vector3(sin(a) * 20.0, -4.0 + sin(_t * 0.2) * 1.0, cos(a) * 20.0)
	_cam.look_at(Vector3(3.5, 0, 0), Vector3.UP)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	# sol tarafta yarı saydam şerit
	var strip := ColorRect.new()
	strip.color = Color(0.02, 0.03, 0.04, 0.72)
	strip.anchor_bottom = 1.0
	strip.offset_right = 420
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	var box := VBoxContainer.new()
	box.position = Vector2(56, 120)
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)
	var title := Label.new()
	title.text = "HANGAR\nSAVAŞLARI"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Parça parça uçak yap · uç · savaş · kurtar"
	sub.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	box.add_child(gap)
	if FlightSave.exists():
		var cont := UiTheme.big_button("⟲  Devam et", _continue, true)
		cont.tooltip_text = FlightSave.info()
		box.add_child(cont)
	box.add_child(UiTheme.big_button("▶  Hızlı Uçuş", _quick_flight, true))
	box.add_child(UiTheme.big_button("Görevler", _go.bind("missions")))
	box.add_child(UiTheme.big_button("Hangar  (uçak tasarla)", _go.bind("")))
	box.add_child(UiTheme.big_button("Kadro", _go.bind("crew")))
	box.add_child(UiTheme.big_button("Ayarlar", func() -> void: SettingsDialog.open(self)))
	box.add_child(UiTheme.big_button("Çıkış", func() -> void: get_tree().quit()))
	var p := Crew.current()
	var info := Label.new()
	info.text = ("Pilot: %s  ·  Seviye %d  ·  %d uçuş" % [p.get("name", "—"), p.get("level", 1), p.get("flights", 0)] if not p.is_empty() else "") + ("   ·   Serbest mod" if Career.sandbox() else "   ·   Kasa ₺ %d   ·   %d görev tamamlandı" % [Career.money, Career.missions_done()])
	info.add_theme_color_override("font_color", UiTheme.DIM)
	info.position = Vector2(56, 0)
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.offset_top = -48
	root.add_child(info)


func _continue() -> void:
	var d := FlightSave.load_data()
	if d.is_empty():
		return
	Game.resume = d
	Game.mission = ""
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://main.tscn")


func _quick_flight() -> void:
	if not Crew.can_fly(Crew.selected):
		_go("crew")
		return
	if Game.flight_craft.is_empty():
		Game.flight_craft = VesselBuilder.load_craft("res://crafts/kartal_1.json")
	Game.mission = ""
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://main.tscn")


func _go(action: String) -> void:
	Game.hangar_action = action
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://hangar/hangar.tscn")
