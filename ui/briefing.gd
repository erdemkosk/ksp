class_name Briefing
extends PopupPanel
## Görev brifingi: solda bölge haritası (kara/deniz/dağ, havaalanları, kasabalar, yollar,
## görev noktaları), sağda görev adı, zorluk, açıklama, hedefler, uçak ve pilot; BAŞLA / Geri.

var mission_id := ""
var on_start: Callable
var _map: Control
var _pts := []
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _grid: Image
var _grid_tex: ImageTexture


static func open(parent: Node, id: String, craft_name: String, start: Callable) -> Briefing:
	var b := Briefing.new()
	b.mission_id = id
	b.on_start = start
	b.theme = UiTheme.get_theme()
	var sb := UiTheme.flat(Color(0.035, 0.05, 0.065, 0.985), 12)
	sb.set_content_margin_all(16)
	sb.border_color = Color(UiTheme.ACCENT, 0.3)
	sb.set_border_width_all(1)
	b.add_theme_stylebox_override("panel", sb)
	parent.add_child(b)
	b._build(craft_name)
	b.popup_centered(Vector2i(1060, 700 if id == "gen" else 600))
	b.popup_hide.connect(b.queue_free)
	return b


func _build(craft_name: String) -> void:
	TerrainGen.init()
	var def := MissionManager.get_def(mission_id)
	var info := MissionManager.briefing(mission_id)
	_pts = info["points"]
	_compute_bounds()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	_map = Control.new()
	_map.custom_minimum_size = Vector2(560, 560)
	_map.draw.connect(_draw_map)
	_map.clip_contents = true
	row.add_child(_map)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 440
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	col.add_child(UiTheme.title("BRİFİNG", 14))
	var t := Label.new()
	t.text = "%s   %s" % [def.get("title", ""), "★".repeat(int(def.get("level", 1))) + "☆".repeat(3 - int(def.get("level", 1)))]
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	col.add_child(t)
	var brief := Label.new()
	brief.text = def.get("brief", "")
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size.x = 430
	brief.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
	col.add_child(brief)
	if mission_id == "gen":
		# üretilmiş görev: isteğin kısıtları ve düşman doktrini (istihbarat)
		var card := GenMission.card_now()
		col.add_child(UiTheme.title("İSTEK", 14))
		for l: String in MissionGen.constraint_lines(card):
			var cl := Label.new()
			cl.text = "■  " + l
			cl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
			col.add_child(cl)
		var tt := MissionGen.threat_text(card)
		for l: String in ([("Tehdit: " + tt)] if tt != "" else []) + Array(card.get("doctrine", [])):
			var dl := Label.new()
			dl.text = l
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size.x = 430
			dl.add_theme_color_override("font_color", Color(1.0, 0.66, 0.45))
			col.add_child(dl)
	col.add_child(UiTheme.title("HEDEFLER", 14))
	for o in info["objectives"]:
		var l := Label.new()
		l.text = "○  " + String(o)
		col.add_child(l)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	var p := Crew.current()
	var who := Label.new()
	who.text = "Uçak: %s\nPilot: %s  (Sv %d)\nKalkış: %s" % [craft_name, p.get("name", "—"), p.get("level", 1),
		{"runway": "pistte soğuk", "runway_hot": "pistte, motor çalışıyor", "air": "havada"}.get(def.get("start", "runway"), "")]
	who.add_theme_color_override("font_color", UiTheme.DIM)
	col.add_child(who)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	col.add_child(btns)
	var back := Button.new()
	back.text = "  ◀ Geri  "
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(hide)
	btns.add_child(back)
	var go := UiTheme.big_button("BAŞLA  ▶", func() -> void:
		hide()
		on_start.call(), true)
	go.custom_minimum_size = Vector2(240, 48)
	btns.add_child(go)


func _compute_bounds() -> void:
	var xs: Array[Vector2] = [Vector2(0, 0)]
	for p in _pts:
		xs.append(p[1])
	if mission_id == "tasima":
		xs.append(TerrainGen.AIRFIELDS[1]["xz"])
	_lo = xs[0]
	_hi = xs[0]
	for v in xs:
		_lo = _lo.min(v)
		_hi = _hi.max(v)
	var c := (_lo + _hi) * 0.5
	var half := maxf(maxf(_hi.x - _lo.x, _hi.y - _lo.y) * 0.5 + 3500.0, 7000.0)
	_lo = c - Vector2(half, half)
	_hi = c + Vector2(half, half)
	# arazi renkleri: 80x80 örnek
	var n := 80
	_grid = Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var x := lerpf(_lo.x, _hi.x, (i + 0.5) / n)
			var z := lerpf(_lo.y, _hi.y, (j + 0.5) / n)
			var d := Vector3(x, TerrainGen.RADIUS, z).normalized()
			var h := TerrainGen.height(d)
			var col: Color
			if h < 0.5:
				col = Color(0.1, 0.2, 0.32).lerp(Color(0.05, 0.1, 0.2), clampf(-h / 300.0, 0.0, 1.0))
			elif h < 400.0:
				col = Color(0.22, 0.32, 0.18).lerp(Color(0.36, 0.38, 0.24), h / 400.0)
			else:
				col = Color(0.42, 0.38, 0.3).lerp(Color(0.85, 0.85, 0.85), clampf((h - 1100.0) / 900.0, 0.0, 1.0))
			_grid.set_pixel(i, j, col)
	_grid_tex = ImageTexture.create_from_image(_grid)


func _to_map(xz: Vector2) -> Vector2:
	var s := _map.size
	return Vector2((xz.x - _lo.x) / (_hi.x - _lo.x) * s.x, (xz.y - _lo.y) / (_hi.y - _lo.y) * s.y)


func _draw_map() -> void:
	var s := _map.size
	_map.draw_texture_rect(_grid_tex, Rect2(Vector2.ZERO, s), false)
	_map.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.15), false, 1.0)
	var font := UiTheme.get_theme().default_font
	# yollar
	for road: Array in Towns.ROADS:
		var line := PackedVector2Array()
		for p: Vector2 in road:
			line.append(_to_map(p))
		_map.draw_polyline(line, Color(0.75, 0.72, 0.65, 0.7), 2.0, true)
	# kasabalar
	for t: Dictionary in Towns.TOWNS:
		var m := _to_map(t["xz"])
		_map.draw_circle(m, 5.0, Color(0.95, 0.9, 0.75))
		_map.draw_string(font, m + Vector2(8, 4), t["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.9, 0.75))
	# havaalanları (pist çizgisi)
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var c: Vector2 = a["xz"]
		var half := float(a["runway"]) * 0.5
		_map.draw_line(_to_map(c - Vector2(0, half)), _to_map(c + Vector2(0, half)), Color(0.9, 0.95, 1.0), 4.0)
		_map.draw_string(font, _to_map(c) + Vector2(10, -6), "✈ " + String(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 1.0))
	# görev noktaları
	for p in _pts:
		var m := _to_map(p[1])
		var col: Color = p[2]
		var r := 7.0
		_map.draw_polyline(PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0), m + Vector2(0, -r)]), col, 2.5, true)
		if String(p[0]) != "" and not String(p[0]) in Towns.TOWNS.map(func(t: Dictionary) -> String: return t["name"]):
			_map.draw_string(font, m + Vector2(10, 5), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# kuzey oku ve ölçek
	_map.draw_string(font, Vector2(s.x - 26, 26), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	_map.draw_line(Vector2(s.x - 20, 34), Vector2(s.x - 20, 58), Color.WHITE, 2.0)
	var km := 5000.0
	var px := km / (_hi.x - _lo.x) * s.x
	_map.draw_line(Vector2(14, s.y - 16), Vector2(14 + px, s.y - 16), Color.WHITE, 2.0)
	_map.draw_string(font, Vector2(14, s.y - 22), "5 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
