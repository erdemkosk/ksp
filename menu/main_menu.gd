extends Node3D
## Ana menü. Arkada gün batımında süzülen uçak; üç ekran:
##   home   — logo, iki mod kartı (Kariyer · Serbest Uçuş), devam et / ayarlar / çıkış
##   career — cephe haritası, karargâh mesajları, harekât istihbaratı, uçak ve pilot, test / gerçek uçuş
##   free   — uçak listesi (arkadaki uçak değişir), başlangıç ve görev seçimi, hangar
## `-- --menu --menuscreen=career --screenshot=x.png` ile ekran görüntüsü alınabilir.

const GAME_TITLE := "GÖK CEPHESİ"
const GAME_TAGLINE := "Tasarla  ·  Uç  ·  Cepheyi geri al"
const USER_DIR := "user://crafts/"
const DEFAULT_CRAFT := "res://crafts/kartal_1.json"
const GROUPS := ["Avcı", "Saldırı", "Destek & Nakliye", "Deneysel", "Sivil", "Benim uçaklarım", "Diğer"]
const HangarScript := preload("res://hangar/hangar.gd")

var _cam: Camera3D
var _plane: Node3D
var _plane_radius := 8.0
var _t := 0.0
var _cam_offset := 0.0

var _root: Control
var _screens := {}
var _screen := ""
var _toast: Label
var _bold: SystemFont

# kariyer
var _map: TheaterMap
var _op: Dictionary = {}
var _op_box: VBoxContainer
var _news_label: Label
var _news_head: Label
var _news_idx := -1
var _craft_label: Label
var _craft_pick: OptionButton
var _pilot_label: Label
var _top_info: Label
var _end_banner: PanelContainer
var _act_box: PanelContainer        ## perde başlığı + hedefler (CampaignUi)

# serbest
var _crafts: Array = []          ## [{data, group}]
var _free_sel := -1
var _free_name: Label
var _free_desc: Label
var _free_stats: Label
var _free_start: OptionButton
var _free_weather: OptionButton
var _free_hour: OptionButton
var _free_mission: OptionButton
var _free_list: VBoxContainer


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
	Game.test_flight = false
	_bold = SystemFont.new()
	_bold.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold.font_weight = 700
	_load_crafts()
	_build_scene()
	_build_ui()
	if Game.args.has("fronttest"):
		_front_test()
		return
	if Game.args.has("frontaitest"):
		FrontAI.run_test()
		get_tree().quit()
		return
	if Game.args.has("campaigntest"):
		Campaign.run_test()
		get_tree().quit()
		return
	if Game.args.has("campaigndemo"):
		CampaignUi.seed_demo(int(Game.args.get("campaigndemo", "2")))
	if Game.args.has("frontaidemo"):
		FrontAI.seed_demo()
	var first := String(Game.args.get("menuscreen", Game.menu_screen))
	_show(first if first in _screens else "home", true)
	if Game.args.has("genbriefdemo"):   # test: üretilmiş görevin brifingi (ekran görüntüsü)
		(func() -> void:
			for op: Dictionary in Front.operations():
				if op["mission"] == "gen" and String(op["card"]["template"]) == String(Game.args.get("gentemplate", op["card"]["template"])):
					Game.mission_card = op["card"]
					Briefing.open(self, "gen", "Kartal-1", func() -> void: pass)
					break).call_deferred()


# ------------------------------------------------------------------ 3B arka plan

func _build_scene() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.1, 0.16, 0.32)
	sky.sky_horizon_color = Color(0.98, 0.58, 0.36)
	sky.ground_horizon_color = Color(0.52, 0.34, 0.28)
	sky.ground_bottom_color = Color(0.08, 0.08, 0.1)
	sky.sun_angle_max = 30.0
	sky.sun_curve = 0.08
	var s := Sky.new()
	s.sky_material = sky
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-12, -60, 0)
	sun.light_color = Color(1.0, 0.78, 0.6)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 120, 0)
	fill.light_color = Color(0.5, 0.65, 1.0)
	fill.light_energy = 0.35
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	var craft: Dictionary = Game.flight_craft if not Game.flight_craft.is_empty() else VesselBuilder.load_craft(DEFAULT_CRAFT)
	_set_plane(craft)


## Arkadaki uçağı değiştir; kamera uzaklığı uçağın boyuna göre.
func _set_plane(craft: Dictionary) -> void:
	if is_instance_valid(_plane):
		_plane.queue_free()
	var holder := Node3D.new()
	add_child(holder)
	var v := VesselBuilder.build(craft.duplicate(true))
	v.freeze = true
	holder.add_child(v)
	v.set_physics_process(false)
	v.set_gear_instant(false)
	var box := AABB()
	var first := true
	for p in v.parts:
		var b: AABB = p.local_aabb(0.0)
		box = b if first else box.merge(b)
		first = false
	v.position = -box.get_center()
	_plane = holder
	_plane_radius = maxf(box.size.length() * 0.5, 3.0)


func _process(delta: float) -> void:
	_t += delta
	if Game.args.has("screenshot") and _t > float(Game.args.get("shot-time", "3")):
		var path: String = Game.args["screenshot"]
		Game.args.erase("screenshot")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
	if not is_instance_valid(_plane):
		return
	# hafif süzülme + yatış, kamera yavaşça etrafında döner
	_plane.rotation = Vector3(sin(_t * 0.4) * 0.05, 0.0, sin(_t * 0.3) * 0.15)
	_plane.position = Vector3(0, sin(_t * 0.6) * 0.3, 0)
	var a := _t * 0.12 + 2.2
	var dist := _plane_radius * 2.6
	_cam.position = Vector3(sin(a) * dist, -dist * 0.2 + sin(_t * 0.2) * 1.0, cos(a) * dist)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	var target_off: float = {"home": -0.28, "free": -0.12}.get(_screen, 0.0) * dist * 0.5
	_cam_offset = lerpf(_cam_offset, target_off, minf(delta * 2.5, 1.0))
	_cam.h_offset = _cam_offset


# ------------------------------------------------------------------ ekranlar

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	_screens["home"] = _build_home()
	_screens["career"] = _build_career()
	_screens["free"] = _build_free()
	for k in _screens:
		_root.add_child(_screens[k])
		_screens[k].visible = false
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -70
	_toast.offset_bottom = -40
	_toast.offset_left = -500
	_toast.offset_right = 500
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)


func _show(name: String, instant := false) -> void:
	_screen = name
	Game.menu_screen = name
	for k in _screens:
		var c: Control = _screens[k]
		if k == name:
			c.visible = true
			c.modulate.a = 1.0 if instant else 0.0
			if not instant:
				create_tween().tween_property(c, "modulate:a", 1.0, 0.25)
		else:
			c.visible = false
	match name:
		"career":
			_refresh_career()
		"free":
			if _free_sel >= 0:
				_set_plane(_crafts[_free_sel]["data"])


func _flash(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _gradient_strip(width: float, alpha := 0.88) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.02, 0.035, alpha))
	g.set_color(1, Color(0.01, 0.02, 0.035, 0.0))
	g.add_point(0.6, Color(0.01, 0.02, 0.035, alpha * 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_bottom = 1.0
	tr.offset_right = width
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _label(text: String, size := 15, color := UiTheme.TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", _bold)
	return l


func _card_panel(border := Color(1, 1, 1, 0.1), bg := Color(0.03, 0.045, 0.06, 0.9)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.flat(bg, 10)
	sb.set_content_margin_all(16)
	sb.border_color = border
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _small_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 38
	if primary:
		b.add_theme_stylebox_override("normal", UiTheme.flat(Color(0.12, 0.5, 0.28), 6))
		b.add_theme_stylebox_override("hover", UiTheme.flat(Color(0.16, 0.62, 0.35), 6))
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------------ ana ekran

func _build_home() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_gradient_strip(900))
	var box := VBoxContainer.new()
	box.position = Vector2(80, 90)
	box.add_theme_constant_override("separation", 14)
	c.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	box.add_child(head)
	var emblem := Emblem.new()
	emblem.custom_minimum_size = Vector2(96, 96)
	head.add_child(emblem)
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 0)
	tbox.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(tbox)
	var title := _label(GAME_TITLE, 68, Color.WHITE, true)
	title.add_theme_constant_override("outline_size", 0)
	tbox.add_child(title)
	tbox.add_child(_label(GAME_TAGLINE.to_upper(), 16, UiTheme.ACCENT, true))
	var gap := Control.new()
	gap.custom_minimum_size.y = 30
	box.add_child(gap)
	var held := Front.count(Front.DOST)
	var status := Front.status()
	var career_meta := "Gün %d   ·   ₺ %s   ·   %d / %d bölge bizde" % [Career.day, _thousands(Career.money), held, Front.REGIONS.size()]
	if status == "victory":
		career_meta = "ZAFER kazanıldı   ·   yeni bir sefer başlatabilirsin"
	elif status == "defeat":
		career_meta = "Cephe çöktü   ·   yeni bir sefer başlat"
	box.add_child(_mode_card("KARİYER  ·  CEPHE", "Kuzeyden gelen düşmanı geri püskürt. Karargâhın istihbaratına göre uçağını tasarla, simülatörde dene, cepheye çık. Düşen uçağın bedeli kasadan çıkar.", career_meta, Color(1.0, 0.5, 0.35), func() -> void:
		Game.mode = "career"
		_show("career")))
	box.add_child(_mode_card("SERBEST UÇUŞ", "Hazır ya da kendi uçağını seç, istediğin gibi uç ya da hangarda tasarla. Her parça açık, para yok, görevler serbest.", "%d hazır uçak  ·  hangar  ·  bütün görevler" % _crafts.size(), Color(0.45, 0.85, 1.0), func() -> void:
		Game.mode = "free"
		_show("free")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if FlightSave.exists():
		var cont := _small_button("⟲  Kayıttan devam", _continue)
		cont.tooltip_text = FlightSave.info()
		row.add_child(cont)
	row.add_child(_small_button("Ayarlar", func() -> void: SettingsDialog.open(self)))
	row.add_child(_small_button("Çıkış", func() -> void: get_tree().quit()))
	var p := Crew.current()
	var info := _label(("Pilot: %s  ·  Seviye %d  ·  %d uçuş" % [p.get("name", "—"), p.get("level", 1), p.get("flights", 0)]) if not p.is_empty() else "", 14, UiTheme.DIM)
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.offset_left = 80
	info.offset_top = -50
	c.add_child(info)
	var ver := _label("Prototip  ·  Godot 4.7", 12, Color(1, 1, 1, 0.35))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -200
	ver.offset_top = -36
	c.add_child(ver)
	return c


func _mode_card(title: String, desc: String, meta: String, accent: Color, cb: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(620, 128)
	var normal := UiTheme.flat(Color(0.03, 0.05, 0.07, 0.82), 10)
	normal.border_color = Color(1, 1, 1, 0.1)
	normal.set_border_width_all(1)
	normal.border_width_left = 5
	normal.border_color = Color(accent, 0.55)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.06, 0.09, 0.12, 0.95)
	hover.border_color = accent
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func() -> void:
		Sfx.play_ui("switch_3.ogg", -8.0)
		cb.call())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_right = -20
	v.offset_top = 14
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := _label(title + "   ▶", 24, Color.WHITE, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := _label(desc, 14, Color(0.8, 0.85, 0.9))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	var m := _label(meta, 13, accent, true)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(m)
	return b


func _continue() -> void:
	var d := FlightSave.load_data()
	if d.is_empty():
		return
	Game.resume = d
	Game.mission = ""
	Game.mission_region = ""
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://main.tscn")


# ------------------------------------------------------------------ kariyer: cephe

func _build_career() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.025, 0.04, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 24
	outer.offset_right = -24
	outer.offset_top = 16
	outer.offset_bottom = -20
	outer.add_theme_constant_override("separation", 12)
	c.add_child(outer)
	# üst şerit
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	outer.add_child(top)
	top.add_child(_small_button("◀ Ana menü", func() -> void: _show("home")))
	top.add_child(_label("CEPHE", 26, Color.WHITE, true))
	_top_info = _label("", 15, Color(1.0, 0.85, 0.45), true)
	_top_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_top_info)
	top.add_child(_small_button("Hangar · Ar-Ge", func() -> void: _go_hangar("")))
	top.add_child(_small_button("Kadro", func() -> void: _go_hangar("crew")))
	top.add_child(_small_button("Yeni sefer", _ask_new_campaign))
	# harita | sağ sütun
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	outer.add_child(body)
	var map_holder := AspectRatioContainer.new()
	map_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_holder.ratio = 1.0
	map_holder.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	body.add_child(map_holder)
	_map = TheaterMap.new()
	_map.op_selected.connect(_on_op)
	map_holder.add_child(_map)
	_end_banner = _card_panel(Color(1.0, 0.85, 0.4, 0.6), Color(0.02, 0.03, 0.05, 0.94))
	_end_banner.visible = false
	_map.add_child(_end_banner)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 470
	side.add_theme_constant_override("separation", 12)
	body.add_child(side)
	_act_box = CampaignUi.header_box()
	side.add_child(_act_box)
	# karargâh
	var hq := _card_panel(Color(1.0, 0.85, 0.4, 0.35))
	side.add_child(hq)
	var hqv := VBoxContainer.new()
	hqv.add_theme_constant_override("separation", 6)
	hq.add_child(hqv)
	var hqh := HBoxContainer.new()
	hqv.add_child(hqh)
	_news_head = _label("", 13, Color(1.0, 0.85, 0.4), true)
	_news_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hqh.add_child(_news_head)
	var prev := Button.new()
	prev.text = "◀"
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(func() -> void: _browse_news(-1))
	hqh.add_child(prev)
	var nxt := Button.new()
	nxt.text = "▶"
	nxt.focus_mode = Control.FOCUS_NONE
	nxt.pressed.connect(func() -> void: _browse_news(1))
	hqh.add_child(nxt)
	_news_label = _label("", 15, Color(0.9, 0.92, 0.95))
	_news_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_news_label.custom_minimum_size = Vector2(430, 96)
	hqv.add_child(_news_label)
	# harekât
	var opp := _card_panel(Color(1.0, 0.4, 0.3, 0.35))
	opp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(opp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	opp.add_child(scroll)
	_op_box = VBoxContainer.new()
	_op_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_op_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_op_box)
	# uçak ve pilot
	var ac := _card_panel(Color(0.45, 0.85, 1.0, 0.3))
	side.add_child(ac)
	var acv := VBoxContainer.new()
	acv.add_theme_constant_override("separation", 6)
	ac.add_child(acv)
	acv.add_child(_label("UÇAK VE PİLOT", 13, Color(0.45, 0.85, 1.0), true))
	_craft_pick = OptionButton.new()
	_craft_pick.focus_mode = Control.FOCUS_NONE
	_craft_pick.item_selected.connect(_on_craft_pick)
	acv.add_child(_craft_pick)
	_craft_label = _label("", 13, Color(1.0, 0.85, 0.5))
	_craft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_label.custom_minimum_size.x = 430
	acv.add_child(_craft_label)
	_pilot_label = _label("", 13, UiTheme.DIM)
	acv.add_child(_pilot_label)
	return c


func _refresh_career() -> void:
	if Game.flight_craft.is_empty():
		Game.flight_craft = VesselBuilder.load_craft(DEFAULT_CRAFT)
	_top_info.text = "Gün %d   ·   Kasa ₺ %s   ·   Bölgeler: %d dost · %d çekişmeli · %d düşman" % [Career.day, _thousands(Career.money),
		Front.count(Front.DOST), Front.count(Front.CEKISME), Front.count(Front.DUSMAN)]
	_map.refresh()
	CampaignUi.fill_header(_act_box)
	_news_idx = Career.news.size() - 1
	_show_news(true)
	# uçak listesi: önce elimizdeki (hangardan gelen) tasarım
	_craft_pick.clear()
	_craft_pick.add_item("✈  %s  (seçili tasarım)" % Game.flight_craft.get("name", "İsimsiz"), 0)
	for i in _crafts.size():
		var d: Dictionary = _crafts[i]["data"]
		var lock := "" if Career.locked_parts_in(d).is_empty() else "  🔒"
		_craft_pick.add_item("%s  ·  %s%s" % [d.get("name", "?"), _crafts[i]["group"], lock], i + 1)
	_craft_pick.select(0)
	_update_craft_info()
	var p := Crew.current()
	_pilot_label.text = "Pilot: %s  ·  Sv %d  ·  %d uçuş, %d düşürme  ·  %s" % [p.get("name", "—"), p.get("level", 1), p.get("flights", 0), p.get("kills", 0), p.get("status", "")] if not p.is_empty() else "Pilot yok, Kadro'dan al"
	var status := Front.status()
	_end_banner.visible = status != "running"
	if _end_banner.visible:
		for ch in _end_banner.get_children():
			ch.queue_free()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_end_banner.add_child(v)
		v.add_child(_label("ZAFER" if status == "victory" else "CEPHE ÇÖKTÜ", 34, Color(1.0, 0.85, 0.4) if status == "victory" else Color(1.0, 0.45, 0.35), true))
		v.add_child(_label("%d günde sefer kazanıldı: Kara Doğan düştü, karargâh bizde." % Career.day if status == "victory" else "Yalnız Ana Üs elimizde kaldı.", 15))
		v.add_child(_small_button("Yeni sefer başlat", _ask_new_campaign, true))
		_end_banner.position = Vector2(40, 40)
	_op = {}
	_fill_op({})
	_map.select_first.call_deferred()
	_campaign_overlays.call_deferred()


## Hikâye kaplamaları (Campaign): bekleyen perde brifingi, sonra zafer ekranı (bir kez).
func _campaign_overlays() -> void:
	var scr: Control = _screens["career"]
	if Career.sandbox() or not scr.visible or scr.has_node("CampaignBrief") or scr.has_node("CampaignVictory"):
		return
	var a := Campaign.pending_brief()
	if a > 0:
		CampaignUi.briefing(scr, a, func() -> void:
			Campaign.brief_seen()
			_news_idx = Career.news.size() - 1
			_show_news()
			_campaign_overlays())
	elif Campaign.won() and not bool(Campaign.st().get("victory_seen", false)):
		var show_victory := func() -> void:
			CampaignUi.victory(scr, _ask_new_campaign, func() -> void:
				Campaign.st()["victory_seen"] = true
				Career.save())
		if bool(Campaign.st().get("victory_brief", false)):
			show_victory.call()
		else:
			CampaignUi.briefing(scr, 4, func() -> void:
				Campaign.st()["victory_brief"] = true
				show_victory.call())


func _show_news(animate := false) -> void:
	if Career.news.is_empty():
		_news_head.text = "KARARGÂH"
		_news_label.text = ""
		return
	_news_idx = clampi(_news_idx, 0, Career.news.size() - 1)
	var n: Dictionary = Career.news[_news_idx]
	var kind := String(n.get("kind", "info"))
	_news_head.text = "KARARGÂH  ·  %s  ·  Gün %d   (%d/%d)" % [Campaign.speaker(n), int(n.get("day", 1)), _news_idx + 1, Career.news.size()]
	_news_label.text = "“%s”" % n.get("text", "")
	_news_label.add_theme_color_override("font_color", {"good": Color(0.7, 1.0, 0.78), "bad": Color(1.0, 0.72, 0.65)}.get(kind, Color(0.9, 0.92, 0.95)))
	if animate:
		_news_label.visible_ratio = 0.0
		create_tween().tween_property(_news_label, "visible_ratio", 1.0, clampf(_news_label.text.length() / 90.0, 0.6, 3.5))
	else:
		_news_label.visible_ratio = 1.0


func _browse_news(d: int) -> void:
	_news_idx += d
	_show_news()


func _on_op(op: Dictionary) -> void:
	_op = op
	_fill_op(op)


func _fill_op(op: Dictionary) -> void:
	for ch in _op_box.get_children():
		ch.queue_free()
	if op.is_empty():
		_op_box.add_child(_label("HAREKÂT", 13, Color(1.0, 0.45, 0.35), true))
		var h := _label("Haritada bir harekât işaretine tıkla.\n◆ kırmızı: savaş harekâtı (cepheyi oynatır)\n● yeşil: destek görevi (para ve tecrübe)", 14, UiTheme.DIM)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_op_box.add_child(h)
		return
	var id: String = op["mission"]
	var card: Dictionary = op.get("card", {})
	var def := MissionGen.def_for(card) if id == "gen" else MissionManager.get_def(id)
	var r := Front.region(op["region"])
	var level := int(def.get("level", 1))
	var intel: Dictionary = MissionGen.intel(card) if id == "gen" else Front.INTEL.get(id, {})
	_op_box.add_child(_label(("SAVAŞ HAREKÂTI" if op["combat"] else "DESTEK GÖREVİ") + "  ·  " + String(r.get("name", "")).to_upper(), 13, Color(1.0, 0.45, 0.35) if op["combat"] else UiTheme.ACCENT, true))
	_op_box.add_child(_label("%s   %s" % [def.get("title", id), "★".repeat(level) + "☆".repeat(3 - level)], 22, Color.WHITE, true))
	# düşman hamlesine karşı acil görev (FrontAI)
	var threat := FrontAI.threat_at(op["region"]) if op.get("urgent", false) else {}
	if not threat.is_empty():
		var u := _label("⚠ ACİL  ·  " + FrontAI.describe(threat), 14, Color(1.0, 0.62, 0.3), true)
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		u.custom_minimum_size.x = 420
		_op_box.add_child(u)
	var brief := _label(String(def.get("brief", "")), 13, Color(0.8, 0.84, 0.88))
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size.x = 420
	_op_box.add_child(brief)
	if id == "gen":
		_op_box.add_child(_label("İSTEK", 12, Color(1.0, 0.85, 0.4), true))
		for l: String in MissionGen.constraint_lines(card):
			_op_box.add_child(_label("  ■  " + l, 13, Color(0.85, 0.92, 1.0)))
		for l: String in card.get("doctrine", []):
			var dl := _label(l, 13, Color(1.0, 0.62, 0.4))
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size.x = 420
			_op_box.add_child(dl)
	_op_box.add_child(_label("İSTİHBARAT", 12, Color(1.0, 0.85, 0.4), true))
	for t: String in intel.get("threats", []):
		_op_box.add_child(_label("  ▲  " + t, 13, Color(1.0, 0.7, 0.62)))
	var adv := _label("Karargâhın önerisi: " + String(intel.get("advice", "")), 13, Color(0.7, 0.9, 1.0))
	adv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	adv.custom_minimum_size.x = 420
	_op_box.add_child(adv)
	var done := int(Career.completed.get(id, 0))
	var reward := Career.mission_reward(level) if done == 0 else Career.mission_reward(level) / 2
	if id == "gen":
		reward = int(card.get("reward", reward))
		done = 0
	var effect := ""
	if op["combat"] and id != "onleme":
		var o := Front.owner(op["region"])
		effect = "Başarı: %s → %s.  Başarısızlık: bölge gerileyebilir." % [Front.OWNER_NAMES[o], Front.OWNER_NAMES[maxi(o - 1, 0)]]
	elif id == "onleme":
		effect = "Başarısızlık: üs hasarı (-4.000 ₺) ve cephe geriler."
	_op_box.add_child(_label("Ödül ₺ %s%s" % [_thousands(reward), "  (tekrar, yarısı)" if done > 0 else ""], 14, Color(1.0, 0.85, 0.45), true))
	if effect != "":
		var e := _label(effect, 13, UiTheme.DIM)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size.x = 420
		_op_box.add_child(e)
	var cost := Career.craft_cost(Game.flight_craft)
	_op_box.add_child(_label("Risk: uçak kaybı ₺ %s  ·  pilot kaybı ₺ %s" % [_thousands(cost), _thousands(Front.PILOT_LOSS_COST)], 13, Color(1.0, 0.55, 0.45)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_op_box.add_child(row)
	var test := _small_button("Test uçuşu (risksiz)", func() -> void: _launch_op(op, true))
	test.tooltip_text = "Simülasyon: aynı görev, ama ödül, kayıp, tecrübe ve cephe değişimi yok."
	row.add_child(test)
	var go := _small_button("GÖREVE ÇIK  ▶", func() -> void: _prepare_op(op), true)
	go.tooltip_text = "Hangara geç: uçağı hazırla, test uçuşu yap, Tamam deyince göreve başla."
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)


func _on_craft_pick(idx: int) -> void:
	var id := _craft_pick.get_item_id(idx)
	if id > 0:
		Game.flight_craft = (_crafts[id - 1]["data"] as Dictionary).duplicate(true)
		_set_plane(Game.flight_craft)
		_craft_pick.set_item_text(0, "✈  %s  (seçili tasarım)" % Game.flight_craft.get("name", "İsimsiz"))
		_craft_pick.select(0)
	_update_craft_info()
	if not _op.is_empty():
		_fill_op(_op)


func _update_craft_info() -> void:
	var txt := HangarScript._craft_summary(Game.flight_craft)
	_craft_label.text = txt + "\nBedel ₺ %s" % _thousands(Career.craft_cost(Game.flight_craft))


## Göreve çık: önce hangar. Seçili (yoksa varsayılan) uçak açılır; orada tasarlanır, test uçuşu
## yapılır, "Tamam" ile brifinge ve göreve geçilir.
func _prepare_op(op: Dictionary) -> void:
	if Game.flight_craft.is_empty():
		Game.flight_craft = VesselBuilder.load_craft(DEFAULT_CRAFT)
	Game.mode = "career"
	Game.pending_op = op.duplicate(true)
	Game.mission_card = (op.get("card", {}) as Dictionary).duplicate(true)
	Game.menu_screen = "career"
	_go_hangar("")


func _launch_op(op: Dictionary, test: bool) -> void:
	var craft := Game.flight_craft
	if craft.is_empty():
		craft = VesselBuilder.load_craft(DEFAULT_CRAFT)
	var locked := Career.locked_parts_in(craft)
	if not locked.is_empty():
		_flash("Uçakta kilitli parça var (Hangar · Ar-Ge): " + ", ".join(locked))
		return
	if not Crew.can_fly(Crew.selected):
		_flash("Uçacak hazır pilot yok — Kadro'dan pilot seç ya da al")
		return
	var id: String = op["mission"]
	Game.mission_card = (op.get("card", {}) as Dictionary).duplicate(true)
	Briefing.open(self, id, String(craft.get("name", "")) + ("   (TEST UÇUŞU)" if test else ""), func() -> void:
		Game.mission_card = (op.get("card", {}) as Dictionary).duplicate(true)
		Game.mode = "career"
		Game.test_flight = test
		Game.mission = id
		Game.mission_region = op["region"]
		Game.free_start = "runway"
		Game.flight_craft = craft
		Game.menu_screen = "career"
		FloatingOrigin.world_root = null
		get_tree().change_scene_to_file("res://main.tscn"))


func _ask_new_campaign() -> void:
	var d := ConfirmationDialog.new()
	d.theme = UiTheme.get_theme()
	d.title = "Yeni sefer"
	d.dialog_text = "Cephe, kasa, Ar-Ge ve tamamlanan görevler sıfırlanır.\nPilotların kalır. Emin misin?"
	d.ok_button_text = "Yeni sefer başlat"
	d.cancel_button_text = "Vazgeç"
	add_child(d)
	d.confirmed.connect(func() -> void:
		Career.reset()
		_refresh_career()
		_flash("Yeni sefer başladı. Karargâhın brifingini oku."))
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func _go_hangar(action: String) -> void:
	Game.hangar_action = action
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://hangar/hangar.tscn")


# ------------------------------------------------------------------ serbest uçuş

func _load_crafts() -> void:
	_crafts.clear()
	for dir_path in ["res://crafts/", USER_DIR]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		var names := d.get_files()
		names.sort()
		for file in names:
			if not file.ends_with(".json"):
				continue
			var data := VesselBuilder.load_craft(dir_path + file)
			if data.is_empty():
				continue
			var g: String = "Benim uçaklarım" if dir_path == USER_DIR else String(data.get("group", "Diğer"))
			if not g in GROUPS:
				g = "Diğer"
			_crafts.append({"data": data, "group": g})
	_crafts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return GROUPS.find(a["group"]) < GROUPS.find(b["group"]))


func _build_free() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_gradient_strip(620, 0.92))
	var left := VBoxContainer.new()
	left.anchor_bottom = 1.0
	left.offset_left = 40
	left.offset_top = 28
	left.offset_right = 420
	left.offset_bottom = -28
	left.add_theme_constant_override("separation", 10)
	c.add_child(left)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	left.add_child(top)
	top.add_child(_small_button("◀", func() -> void: _show("home")))
	top.add_child(_label("SERBEST UÇUŞ", 26, Color.WHITE, true))
	left.add_child(_label("Para yok, her parça ve görev açık.", 13, UiTheme.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_free_list = VBoxContainer.new()
	_free_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_free_list)
	var group := ButtonGroup.new()
	var last_group := ""
	for i in _crafts.size():
		var g: String = _crafts[i]["group"]
		if g != last_group:
			last_group = g
			var h := _label(g.to_upper(), 12, Color(1.0, 0.82, 0.4), true)
			_free_list.add_child(h)
		var d: Dictionary = _crafts[i]["data"]
		var b := Button.new()
		b.text = "  " + String(d.get("name", "?"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 34
		b.pressed.connect(_free_select.bind(i))
		_free_list.add_child(b)
	var nb := _small_button("+  Yeni uçak tasarla", func() -> void:
		Game.mode = "free"
		Game.flight_craft = {}
		_go_hangar("new"))
	left.add_child(nb)
	# sağ alt: bilgi ve başlangıç
	var panel := _card_panel(Color(0.45, 0.85, 1.0, 0.3), Color(0.02, 0.035, 0.05, 0.9))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -540
	panel.offset_top = -400
	panel.offset_right = -36
	panel.offset_bottom = -32
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_free_name = _label("", 26, Color.WHITE, true)
	v.add_child(_free_name)
	_free_desc = _label("", 14, Color(0.82, 0.86, 0.9))
	_free_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_free_desc.custom_minimum_size.x = 470
	v.add_child(_free_desc)
	_free_stats = _label("", 13, Color(1.0, 0.85, 0.5))
	_free_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_free_stats.custom_minimum_size.x = 470
	v.add_child(_free_stats)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var g1 := GridContainer.new()
	g1.columns = 2
	g1.add_theme_constant_override("h_separation", 12)
	v.add_child(g1)
	g1.add_child(_label("Başlangıç", 14, UiTheme.DIM))
	_free_start = OptionButton.new()
	_free_start.focus_mode = Control.FOCUS_NONE
	_free_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["Pistte, soğuk (motoru sen çalıştır)", "Pistte, motor çalışıyor", "Havada (2 km)"]:
		_free_start.add_item(s)
	_free_start.select(["runway", "hot", "air"].find(Game.free_start) if Game.free_start in ["runway", "hot", "air"] else 0)
	g1.add_child(_free_start)
	g1.add_child(_label("Hava", 14, UiTheme.DIM))
	_free_weather = OptionButton.new()
	_free_weather.focus_mode = Control.FOCUS_NONE
	_free_weather.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_weather.add_item("Olduğu gibi")
	for p in Weather.PRESETS:
		_free_weather.add_item(String(Weather.PRESETS[p]["name"]) + ("  (yağmurlu)" if float(Weather.PRESETS[p]["rain"]) > 0.0 else ""))
	_free_weather.select(Game.free_weather + 1)
	g1.add_child(_free_weather)
	g1.add_child(_label("Saat", 14, UiTheme.DIM))
	_free_hour = OptionButton.new()
	_free_hour.focus_mode = Control.FOCUS_NONE
	_free_hour.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_hour.add_item("Olduğu gibi")
	var hsel := 0
	for i in Weather.TIMES.size():
		_free_hour.add_item("%s  (%s)" % [Weather.TIMES[i]["name"], Weather.format_hour(Weather.TIMES[i]["hour"])])
		if is_equal_approx(float(Weather.TIMES[i]["hour"]), Game.free_hour):
			hsel = i + 1
	_free_hour.select(hsel)
	g1.add_child(_free_hour)
	g1.add_child(_label("Görev", 14, UiTheme.DIM))
	_free_mission = OptionButton.new()
	_free_mission.focus_mode = Control.FOCUS_NONE
	_free_mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_mission.add_item("Serbest dolaş (düşman yok, F7 ile çağır)")
	for d: Dictionary in MissionManager.DEFS:
		var lv := int(d["level"])
		_free_mission.add_item("%s   %s" % [d["title"], "★".repeat(lv)])
	g1.add_child(_free_mission)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(_small_button("Hangarda düzenle", func() -> void:
		if _free_sel >= 0:
			Game.flight_craft = (_crafts[_free_sel]["data"] as Dictionary).duplicate(true)
		Game.mode = "free"
		_go_hangar("")))
	var fly := _small_button("UÇ  ▶", _free_fly, true)
	fly.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly.custom_minimum_size.y = 46
	fly.add_theme_font_size_override("font_size", 19)
	row.add_child(fly)
	# varsayılan seçim: son uçulan uçak ya da ilk
	var pick := 0
	if not Game.flight_craft.is_empty():
		for i in _crafts.size():
			if _crafts[i]["data"].get("name", "") == Game.flight_craft.get("name", "-"):
				pick = i
	if not _crafts.is_empty():
		_free_sel = pick
		_fill_free(pick)
		var btns := _free_list.get_children().filter(func(n: Node) -> bool: return n is Button)
		if pick < btns.size():
			(btns[pick] as Button).button_pressed = true
	return c


func _free_select(i: int) -> void:
	_free_sel = i
	_fill_free(i)
	_set_plane(_crafts[i]["data"])
	Sfx.play_ui("switch_2.ogg", -12.0)


func _fill_free(i: int) -> void:
	var d: Dictionary = _crafts[i]["data"]
	_free_name.text = String(d.get("name", "İsimsiz"))
	_free_desc.text = String(d.get("description", "Açıklama yok."))
	_free_stats.text = HangarScript._craft_summary(d).replace("🔒 Kilitli parça var (Ar-Ge gerekir)", "")


func _free_fly() -> void:
	if _free_sel < 0:
		return
	if not Crew.can_fly(Crew.selected):
		_flash("Uçacak hazır pilot yok — Hangar · Kadro'dan pilot seç")
		return
	Game.mode = "free"
	Game.test_flight = false
	Game.mission_region = ""
	Game.flight_craft = (_crafts[_free_sel]["data"] as Dictionary).duplicate(true)
	Game.free_start = ["runway", "hot", "air"][_free_start.selected]
	Game.free_weather = _free_weather.selected - 1
	Game.free_hour = -1.0 if _free_hour.selected <= 0 else float(Weather.TIMES[_free_hour.selected - 1]["hour"])
	Game.menu_screen = "free"
	var mi := _free_mission.selected
	if mi <= 0:
		Game.mission = ""
		FloatingOrigin.world_root = null
		get_tree().change_scene_to_file("res://main.tscn")
		return
	var id: String = MissionManager.DEFS[mi - 1]["id"]
	Briefing.open(self, id, String(Game.flight_craft.get("name", "")), func() -> void:
		Game.mission = id
		FloatingOrigin.world_root = null
		get_tree().change_scene_to_file("res://main.tscn"))


## `-- --menu --fronttest`: cephe kurallarını sırayla dene, sonuçları yaz, çık (kayıt yazılmaz).
func _front_test() -> void:
	Front.new_campaign()
	Game.mode = "career"
	var steps := [["kara", "ovakoy", true], ["kara", "ovakoy", true], ["sam", "derekoy", false], ["it", "orta", true],
		["onleme", "anaus", false], ["heli", "derekoy", true], ["sam", "derekoy", true]]
	for s: Array in steps:
		Game.mission_region = s[1]
		var gain := Career.mission_finished(s[0], int(MissionManager.get_def(s[0]).get("level", 1)), s[2])
		print("FRONT %s@%s %s +%d -> %s | %s" % [s[0], s[1], "OK" if s[2] else "FAIL", gain, ", ".join(Career.front_lines), Career.front])
	Game.test_flight = true
	print("TEST gain=%d lines=%d" % [Career.mission_finished("kara", 2, true), Career.front_lines.size()])
	print("OPS ", Front.operations().size(), " status ", Front.status(), " news ", Career.news.size())
	get_tree().quit()

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Logo: koyu kalkan içinde yukarı tırmanan delta kanat ve altında kırık cephe hattı.
class Emblem extends Control:
	func _draw() -> void:
		var s := size
		var c := s * 0.5
		var r := minf(s.x, s.y) * 0.5
		var shield := PackedVector2Array()
		for i in 6:
			var a := TAU * i / 6.0 - PI / 2.0
			shield.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(shield, Color(0.06, 0.1, 0.16))
		shield.append(shield[0])
		draw_polyline(shield, Color(0.45, 1.0, 0.65), 2.5, true)
		# cephe hattı (kırık kırmızı çizgi)
		var line := PackedVector2Array([c + Vector2(-r * 0.72, r * 0.42), c + Vector2(-r * 0.35, r * 0.28), c + Vector2(-r * 0.05, r * 0.5), c + Vector2(r * 0.3, r * 0.3), c + Vector2(r * 0.72, r * 0.44)])
		draw_polyline(line, Color(1.0, 0.4, 0.3), 3.0, true)
		# delta kanatlı jet (burun yukarı)
		var k := r * 0.95
		var jet := PackedVector2Array([
			c + Vector2(0, -0.78) * k, c + Vector2(0.09, -0.35) * k, c + Vector2(0.62, 0.22) * k,
			c + Vector2(0.62, 0.32) * k, c + Vector2(0.14, 0.18) * k, c + Vector2(0.24, 0.36) * k,
			c + Vector2(0, 0.3) * k,
			c + Vector2(-0.24, 0.36) * k, c + Vector2(-0.14, 0.18) * k, c + Vector2(-0.62, 0.32) * k,
			c + Vector2(-0.62, 0.22) * k, c + Vector2(-0.09, -0.35) * k])
		draw_colored_polygon(jet, Color(0.92, 0.95, 1.0))
		draw_line(c + Vector2(0, -0.5) * k, c + Vector2(0, 0.2) * k, Color(0.45, 1.0, 0.65, 0.8), 2.0)
