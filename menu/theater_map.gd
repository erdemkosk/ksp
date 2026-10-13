class_name TheaterMap
extends Control
## Kariyer ekranındaki cephe haritası: gölgeli arazi, bölgeler (dost / çekişmeli / düşman renkli),
## cephe hattı, düşman ilerleme okları, kasabalar, havaalanları ve harekât işaretleri.
## Harekât işaretine tıklayınca `op_selected` yayınlanır.

signal op_selected(op: Dictionary)

const LO := Vector2(-34000, -30000)
const HI := Vector2(18000, 22000)
const GRID := 180
const OWN_GRID := 260

static var _terrain: ImageTexture

var _owner_tex: ImageTexture
var _ops: Array = []
var _op_pos: Array[Vector2] = []
var hovered := -1
var selected := -1
var _t := 0.0
var _font: Font
var _bold: SystemFont


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_font = UiTheme.get_theme().default_font
	_bold = SystemFont.new()
	_bold.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold.font_weight = 700
	if _terrain == null:
		_build_terrain()
	refresh()


## Cephe durumu değişti: bölge renklerini ve harekât listesini yeniden kur.
func refresh() -> void:
	_build_owner()
	_ops = Front.operations()
	selected = -1
	queue_redraw()


func select_mission(mission_id: String, region_id: String) -> void:
	for i in _ops.size():
		if _ops[i]["mission"] == mission_id and _ops[i]["region"] == region_id:
			selected = i
			op_selected.emit(_ops[i])
			queue_redraw()
			return


## İlk açılabilir savaş harekâtını seç (ekran açılınca boş kalmasın).
func select_first() -> void:
	for i in _ops.size():
		if _ops[i].get("urgent", false):
			selected = i
			op_selected.emit(_ops[i])
			queue_redraw()
			return
	for i in _ops.size():
		if _ops[i]["combat"] and Front.owner(_ops[i]["region"]) != Front.DOST:
			selected = i
			op_selected.emit(_ops[i])
			queue_redraw()
			return


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()


static func _build_terrain() -> void:
	TerrainGen.init()
	var hs := PackedFloat32Array()
	hs.resize(GRID * GRID)
	for j in GRID:
		for i in GRID:
			var x := lerpf(LO.x, HI.x, (i + 0.5) / GRID)
			var z := lerpf(LO.y, HI.y, (j + 0.5) / GRID)
			hs[j * GRID + i] = TerrainGen.height(Vector3(x, TerrainGen.RADIUS, z).normalized())
	var img := Image.create(GRID, GRID, false, Image.FORMAT_RGB8)
	var cell := (HI.x - LO.x) / GRID
	for j in GRID:
		for i in GRID:
			var h := hs[j * GRID + i]
			var col: Color
			if h < 0.5:
				col = Color(0.07, 0.13, 0.21).lerp(Color(0.03, 0.06, 0.12), clampf(-h / 300.0, 0.0, 1.0))
			else:
				if h < 400.0:
					col = Color(0.2, 0.27, 0.17).lerp(Color(0.31, 0.32, 0.22), h / 400.0)
				else:
					col = Color(0.36, 0.33, 0.27).lerp(Color(0.8, 0.8, 0.82), clampf((h - 1100.0) / 900.0, 0.0, 1.0))
				# tepe gölgesi (kuzeybatıdan ışık)
				var hx := hs[j * GRID + mini(i + 1, GRID - 1)] - hs[j * GRID + maxi(i - 1, 0)]
				var hz := hs[mini(j + 1, GRID - 1) * GRID + i] - hs[maxi(j - 1, 0) * GRID + i]
				var shade := clampf(1.0 - (hx + hz) / (cell * 2.0) * 1.6, 0.55, 1.35)
				col = Color(col.r * shade, col.g * shade, col.b * shade)
			img.set_pixel(i, j, col)
	_terrain = ImageTexture.create_from_image(img)


static func _nearest_region(xz: Vector2) -> int:
	var best := 0
	var bd := INF
	for k in Front.REGIONS.size():
		var d: float = xz.distance_squared_to(Front.REGIONS[k]["xz"])
		if d < bd:
			bd = d
			best = k
	return best


func _build_owner() -> void:
	var idx := PackedInt32Array()
	idx.resize(OWN_GRID * OWN_GRID)
	for j in OWN_GRID:
		for i in OWN_GRID:
			var xz := Vector2(lerpf(LO.x, HI.x, (i + 0.5) / OWN_GRID), lerpf(LO.y, HI.y, (j + 0.5) / OWN_GRID))
			idx[j * OWN_GRID + i] = _nearest_region(xz)
	var owners := []
	for r: Dictionary in Front.REGIONS:
		owners.append(Front.owner(r["id"]))
	var img := Image.create(OWN_GRID, OWN_GRID, false, Image.FORMAT_RGBA8)
	for j in OWN_GRID:
		for i in OWN_GRID:
			var k := idx[j * OWN_GRID + i]
			var o: int = owners[k]
			var col: Color = Front.OWNER_COLORS[o]
			var a := 0.2
			# komşu hücre başka bölge mi: sınır çizgisi; sahibi de farklıysa cephe hattı
			var front := false
			var border := false
			for off: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var ni := i + off.x
				var nj := j + off.y
				if ni < 0 or nj < 0 or ni >= OWN_GRID or nj >= OWN_GRID:
					continue
				var nk := idx[nj * OWN_GRID + ni]
				if nk != k:
					border = true
					if owners[nk] != o:
						front = true
			if front:
				col = Color(1.0, 0.92, 0.75)
				a = 0.95
			elif border:
				col = Color(1, 1, 1)
				a = 0.22
			img.set_pixel(i, j, Color(col, a))
	_owner_tex = ImageTexture.create_from_image(img)


func _to_map(xz: Vector2) -> Vector2:
	return (xz - LO) / (HI - LO) * size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _op_at(event.position)
		if h != hovered:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _op_at(event.position)
		if h >= 0:
			selected = h
			Sfx.play_ui("switch_2.ogg", -10.0)
			op_selected.emit(_ops[h])


func _op_at(p: Vector2) -> int:
	for i in _op_pos.size():
		if p.distance_to(_op_pos[i]) < 15.0:
			return i
	return -1


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.06, 0.1))
	if _terrain:
		draw_texture_rect(_terrain, Rect2(Vector2.ZERO, s), false)
	if _owner_tex:
		draw_texture_rect(_owner_tex, Rect2(Vector2.ZERO, s), false)
	# ızgara (5 km)
	var step := 5000.0
	var gx := ceilf(LO.x / step) * step
	while gx < HI.x:
		var x := _to_map(Vector2(gx, 0)).x
		draw_line(Vector2(x, 0), Vector2(x, s.y), Color(1, 1, 1, 0.04), 1.0)
		gx += step
	var gz := ceilf(LO.y / step) * step
	while gz < HI.y:
		var y := _to_map(Vector2(0, gz)).y
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(1, 1, 1, 0.04), 1.0)
		gz += step
	# yollar, kasabalar
	for road: Array in Towns.ROADS:
		var line := PackedVector2Array()
		for p: Vector2 in road:
			line.append(_to_map(p))
		draw_polyline(line, Color(0.85, 0.8, 0.68, 0.35), 1.5, true)
	for t: Dictionary in Towns.TOWNS:
		var m := _to_map(t["xz"])
		draw_circle(m, 3.0, Color(0.95, 0.9, 0.78, 0.7))
		# bölge adıyla çakışan kasaba adı yazılmaz
		if (t["xz"] as Vector2).distance_to(Front.region(Front.REGIONS[_nearest_region(t["xz"])]["id"])["xz"]) < 4000.0:
			continue
		draw_string(_font, m + Vector2(6, 12), t["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.9, 0.78, 0.55))
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var m := _to_map(a["xz"])
		draw_line(m + Vector2(-7, 5), m + Vector2(7, -5), Color(0.85, 0.92, 1.0), 3.0)
	_draw_threat_arrows()
	_draw_enemy_moves()
	# bölge adları
	for r: Dictionary in Front.REGIONS:
		var o := Front.owner(r["id"])
		var m := _to_map(r["xz"])
		var col: Color = Front.OWNER_COLORS[o]
		var name := String(r["name"]).to_upper()
		var w := _bold.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(_bold, m + Vector2(-w * 0.5 + 1, -33 + 1), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.7))
		draw_string(_bold, m + Vector2(-w * 0.5, -33), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))
		var tag: String = Front.OWNER_NAMES[o]
		var tw := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, m + Vector2(-tw * 0.5, -19), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		if r.get("fixed", false):
			_draw_base(m - Vector2(0, 2))
	_draw_ops()
	_draw_event_list()
	# çerçeve, pusula, ölçek, lejant
	draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.18), false, 1.5)
	draw_string(_bold, Vector2(s.x - 30, 30), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([Vector2(s.x - 25, 36), Vector2(s.x - 30, 52), Vector2(s.x - 20, 52)]), Color(1, 1, 1, 0.8))
	var px := 10000.0 / (HI.x - LO.x) * s.x
	draw_line(Vector2(16, s.y - 16), Vector2(16 + px, s.y - 16), Color.WHITE, 2.0)
	draw_string(_font, Vector2(16, s.y - 22), "10 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var lx := s.x - 300.0
	for i in 3:
		var c: Color = Front.OWNER_COLORS[i]
		draw_rect(Rect2(Vector2(lx + i * 96, s.y - 25), Vector2(12, 12)), Color(c, 0.85))
		draw_string(_font, Vector2(lx + i * 96 + 17, s.y - 14), Front.OWNER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))


func _draw_base(m: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		pts.append(m + Vector2(cos(a), sin(a)) * 11.0)
	draw_colored_polygon(pts, Color(0.12, 0.4, 0.75, 0.9))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.75, 0.9, 1.0), 1.5, true)
	draw_string(_bold, m + Vector2(-4, 5), "Ü", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


## Düşman bölgesinden komşu dost / çekişmeli bölgeye kesik, kayan kırmızı oklar.
func _draw_threat_arrows() -> void:
	for r: Dictionary in Front.REGIONS:
		if Front.owner(r["id"]) != Front.DUSMAN:
			continue
		for n: String in Front.NEIGHBORS[r["id"]]:
			if Front.owner(n) == Front.DUSMAN:
				continue
			var a := _to_map(r["xz"])
			var b := _to_map(Front.region(n)["xz"])
			var dir := (b - a).normalized()
			var p0 := a + dir * 26.0
			var p1 := a.lerp(b, 0.62)
			var len := p0.distance_to(p1)
			var dash := 9.0
			var off := fmod(_t * 18.0, dash * 2.0)
			var d := -dash * 2.0 + off
			while d < len:
				var s0 := maxf(d, 0.0)
				var s1 := minf(d + dash, len)
				if s1 > s0:
					draw_line(p0 + dir * s0, p0 + dir * s1, Color(1.0, 0.32, 0.25, 0.75), 2.5)
				d += dash * 2.0
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([p1 + dir * 10.0, p1 + side * 6.0, p1 - side * 6.0]), Color(1.0, 0.32, 0.25, 0.85))


func _draw_ops() -> void:
	_op_pos.clear()
	var per_region := {}
	for i in _ops.size():
		var op: Dictionary = _ops[i]
		var r := Front.region(op["region"])
		var k: int = per_region.get(op["region"], 0)
		per_region[op["region"]] = k + 1
		var n: int = 0
		for o: Dictionary in _ops:
			n += 1 if o["region"] == op["region"] else 0
		var m := _to_map(r["xz"]) + Vector2((k - (n - 1) * 0.5) * 30.0, 22.0 if r.get("fixed", false) else 8.0)
		_op_pos.append(m)
		var combat: bool = op["combat"]
		var col := Color(1.0, 0.35, 0.28) if combat else Color(0.45, 1.0, 0.65)
		if op.get("urgent", false):
			col = Color(1.0, 0.62, 0.2)
		var rad := 10.0
		if combat:
			var pulse := 0.5 + 0.5 * sin(_t * 3.0 + i)
			draw_arc(m, rad + 4.0 + pulse * 6.0, 0, TAU, 32, Color(col, 0.5 * (1.0 - pulse)), 2.0, true)
		if i == hovered or i == selected:
			rad = 13.0
		var pts := PackedVector2Array()
		if combat:
			pts = PackedVector2Array([m + Vector2(0, -rad), m + Vector2(rad, 0), m + Vector2(0, rad), m + Vector2(-rad, 0)])
		else:
			for j in 16:
				pts.append(m + Vector2(cos(TAU * j / 16.0), sin(TAU * j / 16.0)) * rad * 0.85)
		draw_colored_polygon(pts, Color(0.04, 0.06, 0.08, 0.9))
		pts.append(pts[0])
		draw_polyline(pts, col, 2.0, true)
		var done := int(Career.completed.get(op["mission"], 0)) > 0
		var glyph := MissionGen.glyph(op) if op["mission"] == "gen" else _glyph(op["mission"])
		var gw := _bold.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_bold, m + Vector2(-gw * 0.5, 4), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		if op.get("urgent", false):
			draw_circle(m + Vector2(-rad * 0.85, -rad * 0.85), 6.0, Color(1.0, 0.62, 0.2))
			draw_string(_bold, m + Vector2(-rad * 0.85 - 2.0, -rad * 0.85 + 4.5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		if done:
			draw_circle(m + Vector2(rad * 0.8, -rad * 0.8), 3.5, Color(1.0, 0.85, 0.35))
		if i == selected:
			draw_arc(m, rad + 6.0, 0, TAU, 32, Color.WHITE, 2.0, true)
		if i == hovered or i == selected:
			var title := String(op["card"].get("title", "")) if op["mission"] == "gen" else String(MissionManager.get_def(op["mission"]).get("title", ""))
			var tw := _bold.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var box := Rect2(m + Vector2(-tw * 0.5 - 8, 18), Vector2(tw + 16, 22))
			draw_rect(box, Color(0.02, 0.03, 0.05, 0.9))
			draw_rect(box, Color(col, 0.6), false, 1.0)
			draw_string(_bold, box.position + Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


static func _glyph(id: String) -> String:
	return {"kara": "KA", "kesif": "KE", "it": "İD", "sam": "SA", "heli": "HE", "ustunluk": "HÜ", "onleme": "ÖN",
		"egitim": "EĞ", "ikmal": "İK", "yolcu": "YO", "kurtarma": "KU", "kargo": "KR", "filo": "FL", "firkateyn": "FR", "devriye": "DV"}.get(id, "•")


## Düşmanın haber verilmiş hamleleri (FrontAI): kaynaktan hedefe kalın turuncu ok, hedefte nabız
## atan uyarı halkası ve "BASKIN · 2 gün" etiketi.
func _draw_enemy_moves() -> void:
	for t: Dictionary in FrontAI.active():
		var a := _to_map(Front.region(t["from"]).get("xz", Vector2.ZERO))
		var b := _to_map(Front.region(t["region"]).get("xz", Vector2.ZERO))
		var last := int(t["days"]) <= 1
		var col := Color(1.0, 0.3, 0.2) if last else Color(1.0, 0.6, 0.2)
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var p0 := a + dir * 24.0
		var p1 := b - dir * 30.0
		# yay biçimli ok (bölge oklarından ayrılsın)
		var pts := PackedVector2Array()
		var bend := side * minf(a.distance_to(b) * 0.15, 40.0)
		for k in 17:
			var u := k / 16.0
			pts.append(p0.lerp(p1, u) + bend * sin(u * PI))
		draw_polyline(pts, Color(0, 0, 0, 0.5), 7.0, true)
		draw_polyline(pts, Color(col, 0.9), 4.0, true)
		var tip := pts[pts.size() - 1]
		var td := (tip - pts[pts.size() - 3]).normalized()
		var ts := Vector2(-td.y, td.x)
		draw_colored_polygon(PackedVector2Array([tip + td * 14.0, tip + ts * 9.0, tip - ts * 9.0]), col)
		# hedefte uyarı halkası
		var pulse := fmod(_t * (1.6 if last else 1.0), 1.0)
		draw_arc(b, 22.0 + pulse * 22.0, 0, TAU, 40, Color(col, 0.8 * (1.0 - pulse)), 3.0, true)
		draw_arc(b, 22.0, 0, TAU, 40, Color(col, 0.7), 2.0, true)
		var text := "⚠ " + FrontAI.short_text(t)
		var w := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var box := Rect2(b + Vector2(-w * 0.5 - 6, -72), Vector2(w + 12, 19))
		draw_rect(box, Color(0.05, 0.02, 0.0, 0.85))
		draw_rect(box, col, false, 1.5)
		draw_string(_bold, box.position + Vector2(6, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## Sol üstte düşman hareketleri listesi.
func _draw_event_list() -> void:
	var list := FrontAI.active()
	if list.is_empty():
		return
	var lines := PackedStringArray()
	for t: Dictionary in list:
		var title := String(MissionManager.get_def(t["mission"]).get("title", ""))
		lines.append("%s → %s  ·  %s  ·  %s" % [FrontAI.KINDS[t["kind"]]["label"], Front.region(t["region"])["name"], "SON GÜN" if int(t["days"]) <= 1 else "%d gün" % int(t["days"]), title])
	var w := 0.0
	for l in lines:
		w = maxf(w, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var box := Rect2(Vector2(12, 12), Vector2(w + 24, 26 + lines.size() * 19))
	draw_rect(box, Color(0.04, 0.02, 0.01, 0.82))
	draw_rect(box, Color(1.0, 0.6, 0.2, 0.7), false, 1.5)
	draw_string(_bold, box.position + Vector2(10, 17), "DÜŞMAN HAREKETLERİ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.65, 0.3))
	for i in lines.size():
		var last := int(list[i]["days"]) <= 1
		draw_string(_font, box.position + Vector2(12, 36 + i * 19), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.5, 0.4) if last else Color(1, 0.9, 0.8))
