class_name FlightMap
extends CanvasLayer
## Uçuşta bölge haritası (M): arazi, yollar, kasabalar, havaalanları (pist yönüyle), görev
## hedefi ve birimleri, radar temasları, kurtarma helikopteri, uçağın konumu / yönü ve
## geçtiği yol. Tekerlek: yakınlaştır (uçak merkezde), M / Esc: kapat. Oyun durmaz.

const WORLD_LO := Vector2(-34000, -30000)
const WORLD_HI := Vector2(18000, 22000)
const GRID := 140

static var _tex: ImageTexture
## Harita açık mı (fare yakalamayı bırakmak için)
static var showing := false

var main: Node
var _root: Control
var _map: Control
var _zoom := 1.0
var _trail: Array[Vector2] = []
var _trail_t := 0.0
var _font: Font


func _ready() -> void:
	layer = 12
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_map = Control.new()
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_input)
	_root.add_child(_map)
	_font = UiTheme.get_theme().default_font


func toggle() -> void:
	_root.visible = not _root.visible
	showing = _root.visible
	if _root.visible and _tex == null:
		_build_texture()


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _root.visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom * 1.4, 16.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom / 1.4, 1.0)


static func _build_texture() -> void:
	TerrainGen.init()
	var img := Image.create(GRID, GRID, false, Image.FORMAT_RGB8)
	for j in GRID:
		for i in GRID:
			var x := lerpf(WORLD_LO.x, WORLD_HI.x, (i + 0.5) / GRID)
			var z := lerpf(WORLD_LO.y, WORLD_HI.y, (j + 0.5) / GRID)
			var h := TerrainGen.height(Vector3(x, TerrainGen.RADIUS, z).normalized())
			var col: Color
			if h < 0.5:
				col = Color(0.1, 0.2, 0.32).lerp(Color(0.05, 0.1, 0.2), clampf(-h / 300.0, 0.0, 1.0))
			elif h < 400.0:
				col = Color(0.22, 0.32, 0.18).lerp(Color(0.36, 0.38, 0.24), h / 400.0)
			else:
				col = Color(0.42, 0.38, 0.3).lerp(Color(0.85, 0.85, 0.85), clampf((h - 1100.0) / 900.0, 0.0, 1.0))
			img.set_pixel(i, j, col)
	_tex = ImageTexture.create_from_image(img)


## Dünya konumu → başlangıç çerçevesi (doğu, güney) metre.
static func to_xz(world: Vector3) -> Vector2:
	var p := world - Planet.center()
	var d := p.normalized()
	# world_point'in tersi: d = (x, R, z).normalized()
	return Vector2(d.x / d.y, d.z / d.y) * Planet.RADIUS


func _process(delta: float) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.vessel):
		return
	var focus: Node3D = main.pilot if is_instance_valid(main.pilot) else main.vessel
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 1.0
		_trail.append(to_xz(focus.global_position))
		if _trail.size() > 900:
			_trail.remove_at(0)
	if _root.visible:
		var s := _root.get_viewport_rect().size
		var side := minf(s.x - 120.0, s.y - 120.0)
		_map.position = (s - Vector2(side, side)) * 0.5
		_map.size = Vector2(side, side)
		_map.queue_redraw()


func _view() -> Rect2:
	var full := Rect2(WORLD_LO, WORLD_HI - WORLD_LO)
	if _zoom <= 1.01:
		return full
	var focus: Node3D = main.pilot if is_instance_valid(main.pilot) else main.vessel
	var c := to_xz(focus.global_position)
	var sz := full.size / _zoom
	return Rect2(c - sz * 0.5, sz)


func _to_map(xz: Vector2, view: Rect2) -> Vector2:
	return (xz - view.position) / view.size * _map.size


func _draw_map() -> void:
	var view := _view()
	var s := _map.size
	var full := Rect2(WORLD_LO, WORLD_HI - WORLD_LO)
	var tl := _to_map(full.position, view)
	var br := _to_map(full.end, view)
	_map.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.1, 0.18))
	if _tex:
		_map.draw_texture_rect(_tex, Rect2(tl, br - tl), false)
	_map.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.25), false, 2.0)
	# yollar ve kasabalar
	for road: Array in Towns.ROADS:
		var line := PackedVector2Array()
		for p: Vector2 in road:
			line.append(_to_map(p, view))
		_map.draw_polyline(line, Color(0.8, 0.76, 0.66, 0.75), 2.0, true)
	for t: Dictionary in Towns.TOWNS:
		var m := _to_map(t["xz"], view)
		_map.draw_circle(m, maxf(float(t["r"]) / view.size.x * s.x, 4.0), Color(0.95, 0.9, 0.75, 0.6))
		_map.draw_string(_font, m + Vector2(8, 4), t["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.9, 0.75))
	for i in TerrainGen.AIRFIELDS.size():
		var a: Dictionary = TerrainGen.AIRFIELDS[i]
		var c: Vector2 = a["xz"]
		var z3 := TerrainGen.airfield_transform(i).basis.z
		var fr := Planet.local_basis(MissionManager.world_point(c.x, c.y, 0.0))
		var dir := Vector2(z3.dot(fr.x), z3.dot(fr.z)).normalized()
		var half := float(a["runway"]) * 0.5
		_map.draw_line(_to_map(c - dir * half, view), _to_map(c + dir * half, view), Color(0.9, 0.95, 1.0), maxf(3.0, _zoom * 1.5))
		_map.draw_string(_font, _to_map(c, view) + Vector2(10, -8), "✈ " + String(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.85, 1.0))
	# görev birimleri ve hedef
	for n in main.world.get_children():
		if n is GroundTarget:
			var col := Color(0.6, 0.6, 0.6) if n.destroyed else (Color(1.0, 0.85, 0.3) if n.team != "düşman" else Color(1.0, 0.35, 0.3))
			var m := _to_map(to_xz(n.global_position), view)
			if n is SamSite and not n.destroyed:
				_map.draw_arc(m, SamSite.RANGE / view.size.x * s.x, 0, TAU, 48, Color(1.0, 0.3, 0.25, 0.35), 1.5)
			_map.draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), col)
	var mm: MissionManager = main.mission
	if mm and mm.nav_point != null:
		var np := _to_map(to_xz(mm.nav_point), view)
		_map.draw_arc(np, 10.0, 0, TAU, 20, Color(1.0, 0.85, 0.3), 2.5)
		_map.draw_string(_font, np + Vector2(12, 5), mm.nav_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.3))
	# uçaklar: radar temasları (düşman / sivil) ve kurtarma helikopteri
	var v: Vessel = main.vessel
	for n in main.world.get_children():
		if n is Vessel and n != v and not n.parts.is_empty():
			var seen: bool = v.radar() != null and n in v.radar().contacts
			if seen or n.team == v.team:
				var col := Color(0.4, 0.8, 1.0) if n.team == v.team else (Color(0.75, 0.78, 0.8) if n.team == "sivil" else Color(1.0, 0.35, 0.3))
				_plane_icon(_to_map(to_xz(n.global_position), view), n.heading_deg(), col, 7.0)
	if is_instance_valid(main.rescue_heli):
		var hm := _to_map(to_xz(main.rescue_heli.global_position), view)
		_map.draw_circle(hm, 5.0, Color(1.0, 0.55, 0.15))
		_map.draw_string(_font, hm + Vector2(8, 4), "Kurtarma", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.55, 0.15))
	# iz ve kendimiz
	if _trail.size() > 1:
		var tr := PackedVector2Array()
		for p in _trail:
			tr.append(_to_map(p, view))
		_map.draw_polyline(tr, Color(0.45, 1.0, 0.65, 0.6), 2.0, true)
	var focus: Node3D = main.pilot if is_instance_valid(main.pilot) else v
	var me := _to_map(to_xz(focus.global_position), view)
	if is_instance_valid(main.pilot):
		_map.draw_circle(me, 6.0, Color(1.0, 0.95, 0.4))
		_map.draw_string(_font, me + Vector2(9, 4), "Pilot", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.95, 0.4))
	else:
		_plane_icon(me, v.heading_deg(), Color(0.45, 1.0, 0.65), 11.0)
	# ölçek ve bilgi
	var km := 5000.0 if view.size.x > 20000.0 else (1000.0 if view.size.x > 4000.0 else 200.0)
	var px := km / view.size.x * s.x
	_map.draw_line(Vector2(16, s.y - 18), Vector2(16 + px, s.y - 18), Color.WHITE, 2.0)
	_map.draw_string(_font, Vector2(16, s.y - 24), "%s" % ("%d km" % (km / 1000.0) if km >= 1000.0 else "%d m" % km), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	_map.draw_string(_font, Vector2(16, 24), "HARİTA  ·  tekerlek: yakınlaştır (x%.1f)  ·  M: kapat" % _zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	_map.draw_string(_font, Vector2(s.x - 26, 26), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	_map.draw_line(Vector2(s.x - 20, 34), Vector2(s.x - 20, 56), Color.WHITE, 2.0)


func _plane_icon(p: Vector2, hdg_deg: float, col: Color, size: float) -> void:
	var a := deg_to_rad(hdg_deg)
	var f := Vector2(sin(a), -cos(a))
	var r := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([p + f * size, p - f * size * 0.6 + r * size * 0.7, p - f * size * 0.3, p - f * size * 0.6 - r * size * 0.7])
	_map.draw_colored_polygon(pts, col)
	_map.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.6), 1.0, true)
