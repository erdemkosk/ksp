class_name BlueprintView
extends Control
## Tasarım bürosunun teknik çizimi: uçağın üç görünüşü (yan, üst, ön) mavi kâğıt üstünde beyaz
## çizgilerle, ölçü okları (boy, açıklık, yükseklik), antet bloğu ve onay mührü. Hangarda
## "Çizim" düğmesiyle açılır. Siluetler parçaların gerçek ağlarından çıkar: her ağın noktaları
## uçak uzayına taşınır, üç düzleme izdüşürülür, dışbükey zarfı çizilir.

const PAPER := Color(0.07, 0.19, 0.36)
const PAPER_DARK := Color(0.05, 0.14, 0.28)
const INK := Color(0.9, 0.95, 1.0, 0.92)
const INK_DIM := Color(0.75, 0.85, 1.0, 0.35)
const GRID := Color(1, 1, 1, 0.06)
const OK_COL := Color(0.35, 0.95, 0.55)
const BAD_COL := Color(1.0, 0.32, 0.25)

var _hulls := {"side": [], "top": [], "front": []}   ## [{pts: PackedVector2Array, kind}]
var _bounds := {}          ## görünüş → Rect2 (metre)
var _info := {}            ## name, length, span, height, mass, warns, date, number
var _font: Font
var _mono: SystemFont


func _ready() -> void:
	# CanvasLayer altında tam ekran çapası boyutu 0 bırakabiliyor: ekran boyutunu doğrudan al
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func() -> void:
		size = get_viewport().get_visible_rect().size
		queue_redraw())
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus.call_deferred()
	_font = ThemeDB.fallback_font
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New"])


## Uçağı (hangar önizlemesi) çizime çevir. info: {name, warns:int, number}
func set_vessel(v: Vessel, info: Dictionary) -> void:
	_info = info.duplicate()
	for k in _hulls:
		_hulls[k] = []
	if not is_instance_valid(v) or v.parts.is_empty():
		queue_redraw()
		return
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in v.parts:
		var kind := _kind(p)
		var stack: Array[Node] = [p]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is GPUParticles3D or n is CockpitSwitch or n is PilotModel or n is Label3D:
				continue
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			var mo := mi.material_override
			if mo is StandardMaterial3D and (mo as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and not mi.mesh is ArrayMesh:
				continue
			var pts := _mesh_points(mi, v)
			if pts.size() < 3:
				continue
			for q in pts:
				lo = lo.min(q)
				hi = hi.max(q)
			_add_hull("side", pts, Vector3(0, 0, 1), Vector3(0, -1, 0), kind)    # x→ burun solda: z, y yukarı
			_add_hull("top", pts, Vector3(0, 0, 1), Vector3(1, 0, 0), kind)     # z sağa, x aşağı
			_add_hull("front", pts, Vector3(1, 0, 0), Vector3(0, -1, 0), kind)  # x sağa, y yukarı
	_bounds = {
		"side": Rect2(Vector2(lo.z, -hi.y), Vector2(hi.z - lo.z, hi.y - lo.y)),
		"top": Rect2(Vector2(lo.z, lo.x), Vector2(hi.z - lo.z, hi.x - lo.x)),
		"front": Rect2(Vector2(lo.x, -hi.y), Vector2(hi.x - lo.x, hi.y - lo.y)),
	}
	_info["length"] = hi.z - lo.z
	_info["span"] = hi.x - lo.x
	_info["height"] = hi.y - lo.y
	_info["mass"] = v.mass
	queue_redraw()


func _kind(p: Part) -> String:
	for m in p.modules:
		if m is ControlSurfaceModule:
			return "control"
		if m is WingModule:
			return "wing"
		if m is EngineModule:
			return "engine"
		if m is GunModule or m is MissileModule or m is BombModule:
			return "weapon"
		if m is LandingGearModule:
			return "gear"
	return "body"


## Ağ noktaları uçak uzayında (seyreltilmiş: en çok ~160 nokta).
func _mesh_points(mi: MeshInstance3D, v: Vessel) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arr: Array = mi.mesh.surface_get_arrays(0) if mi.mesh.get_surface_count() > 0 else []
	if arr.is_empty():
		return out
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var xf := Transform3D.IDENTITY
	var cur: Node = mi
	while cur != null and cur != v:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	var step := maxi(1, verts.size() / 160)
	for i in range(0, verts.size(), step):
		out.append(xf * verts[i])
	return out


func _add_hull(view: String, pts: PackedVector3Array, ax: Vector3, ay: Vector3, kind: String) -> void:
	var flat := PackedVector2Array()
	for q in pts:
		flat.append(Vector2(q.dot(ax), q.dot(ay)))
	var hull := Geometry2D.convex_hull(flat)
	if hull.size() >= 3:
		(_hulls[view] as Array).append({"pts": hull, "kind": kind})


# ------------------------------------------------------------------ çizim

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, PAPER)
	# kâğıt ızgarası
	var g := 24.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
		x += g
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
		y += g
	# çerçeve
	var m := 28.0
	var frame := r.grow(-m)
	draw_rect(frame, INK, false, 2.0)
	draw_rect(frame.grow(-6), INK_DIM, false, 1.0)
	if _bounds.is_empty():
		_text(frame.get_center() - Vector2(160, 0), "ÇİZİLECEK UÇAK YOK", 22, INK)
		return
	# yerleşim: solda üstte yan görünüş, altında üst görünüş; sağda ön görünüş ve antet
	var title_w := 330.0
	var area := Rect2(frame.position + Vector2(20, 20), frame.size - Vector2(title_w + 50, 40))
	var side_r := Rect2(area.position, Vector2(area.size.x, area.size.y * 0.42))
	var top_r := Rect2(area.position + Vector2(0, area.size.y * 0.48), Vector2(area.size.x, area.size.y * 0.52))
	var right := Rect2(Vector2(frame.end.x - title_w - 20, frame.position.y + 20), Vector2(title_w, frame.size.y - 40))
	var front_r := Rect2(right.position, Vector2(right.size.x, right.size.y * 0.42))
	# ortak ölçek: yan ve üst görünüş aynı ölçekte (boy aynı uzunlukta görünsün)
	var b_side: Rect2 = _bounds["side"]
	var b_top: Rect2 = _bounds["top"]
	var b_front: Rect2 = _bounds["front"]
	var s := minf(minf((side_r.size.x - 80) / maxf(b_side.size.x, 0.1), (side_r.size.y - 60) / maxf(b_side.size.y, 0.1)),
		minf((top_r.size.x - 80) / maxf(b_top.size.x, 0.1), (top_r.size.y - 60) / maxf(b_top.size.y, 0.1)))
	var s_front := minf((front_r.size.x - 70) / maxf(b_front.size.x, 0.1), (front_r.size.y - 70) / maxf(b_front.size.y, 0.1))
	s_front = minf(s_front, s * 1.4)
	_view("YAN GÖRÜNÜŞ", side_r, b_side, s, _hulls["side"], "length", "height")
	_view("ÜST GÖRÜNÜŞ", top_r, b_top, s, _hulls["top"], "", "span")
	_view("ÖN GÖRÜNÜŞ", front_r, b_front, s_front, _hulls["front"], "span", "")
	_title_block(Rect2(right.position + Vector2(0, right.size.y * 0.46), Vector2(right.size.x, right.size.y * 0.54)), s)


## Bir görünüş: siluetler + ölçü okları (dim_x: alttaki yatay ölçü, dim_y: soldaki dikey ölçü).
func _view(title: String, box: Rect2, b: Rect2, s: float, hulls: Array, dim_x: String, dim_y: String) -> void:
	_text(box.position + Vector2(0, 14), title, 13, INK_DIM, true)
	var w := b.size * s
	var origin := box.position + (box.size - w) * 0.5 - b.position * s + Vector2(10, 6)
	# önce gövde ve motorlar, üstüne kanat ve kontrol yüzeyleri (çizim okunur olsun)
	for pass_kinds in [["body", "engine", "gear"], ["wing"], ["control", "weapon"]]:
		for h: Dictionary in hulls:
			if not (h["kind"] in pass_kinds):
				continue
			var poly := PackedVector2Array()
			for q: Vector2 in h["pts"]:
				poly.append(origin + q * s)
			var fill := Color(1, 1, 1, 0.05)
			match h["kind"]:
				"control":
					fill = Color(1.0, 0.85, 0.3, 0.12)
				"weapon":
					fill = Color(1.0, 0.45, 0.35, 0.12)
				"engine":
					fill = Color(1, 1, 1, 0.09)
			draw_colored_polygon(poly, fill)
			poly.append(poly[0])
			draw_polyline(poly, INK, 1.2, true)
	var r := Rect2(origin + b.position * s, w)
	# merkez çizgisi (kesikli)
	if title != "ÜST GÖRÜNÜŞ":
		pass
	else:
		var cy := origin.y
		_dashed(Vector2(r.position.x - 14, cy), Vector2(r.end.x + 14, cy))
	if dim_x != "":
		_dim(Vector2(r.position.x, r.end.y + 22), Vector2(r.end.x, r.end.y + 22), float(_info.get(dim_x, 0.0)), r.end.y)
	if dim_y != "":
		_dim_v(Vector2(r.position.x - 24, r.position.y), Vector2(r.position.x - 24, r.end.y), float(_info.get(dim_y, 0.0)), r.position.x)


func _dashed(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var n := int(d.length() / 14.0)
	for i in n:
		var t0 := float(i) / n
		var t1 := t0 + 0.6 / n
		draw_line(a + d * t0, a + d * t1, INK_DIM, 1.0)


## Yatay ölçü: uç çizgileri, iki uçlu ok, ortada değer.
func _dim(a: Vector2, b: Vector2, meters: float, from_y: float) -> void:
	draw_line(Vector2(a.x, from_y + 4), Vector2(a.x, a.y + 6), INK_DIM, 1.0)
	draw_line(Vector2(b.x, from_y + 4), Vector2(b.x, b.y + 6), INK_DIM, 1.0)
	draw_line(a, b, INK, 1.0)
	_arrow(a, Vector2.RIGHT)
	_arrow(b, Vector2.LEFT)
	var t := "%.2f m" % meters
	var tw := _mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_rect(Rect2((a + b) * 0.5 - Vector2(tw * 0.5 + 6, 9), Vector2(tw + 12, 18)), PAPER)
	draw_string(_mono, (a + b) * 0.5 + Vector2(-tw * 0.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)


func _dim_v(a: Vector2, b: Vector2, meters: float, from_x: float) -> void:
	draw_line(Vector2(from_x - 4, a.y), Vector2(a.x - 6, a.y), INK_DIM, 1.0)
	draw_line(Vector2(from_x - 4, b.y), Vector2(b.x - 6, b.y), INK_DIM, 1.0)
	draw_line(a, b, INK, 1.0)
	_arrow(a, Vector2.DOWN)
	_arrow(b, Vector2.UP)
	var t := "%.2f m" % meters
	var tw := _mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_set_transform((a + b) * 0.5, -PI * 0.5)
	draw_rect(Rect2(Vector2(-tw * 0.5 - 6, -9), Vector2(tw + 12, 18)), PAPER)
	draw_string(_mono, Vector2(-tw * 0.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	draw_set_transform(Vector2.ZERO)


func _arrow(tip: Vector2, dir: Vector2) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip + dir * 9 + n * 3.5, tip + dir * 9 - n * 3.5]), INK)


## Antet: büro adı, uçak, ölçek, kütle, tarih, çizen; altta onay mührü.
func _title_block(r: Rect2, s: float) -> void:
	draw_rect(r, PAPER_DARK)
	draw_rect(r, INK, false, 1.5)
	var rows := [
		["TASARIM BÜROSU", "HANGAR SAVAŞLARI"],
		["UÇAK", String(_info.get("name", "İsimsiz")).to_upper()],
		["KUYRUK NO", String(_info.get("number", "—"))],
		["BOY / AÇIKLIK", "%.2f m / %.2f m" % [_info.get("length", 0.0), _info.get("span", 0.0)]],
		["YÜKSEKLİK", "%.2f m" % _info.get("height", 0.0)],
		["KÜTLE (DOLU)", "%d kg" % _info.get("mass", 0.0)],
		["ÖLÇEK", "1 : %d" % roundi(1000.0 / maxf(s * 0.264, 0.001))],   # ekranda 1 px ≈ 0.264 mm
		["TARİH", Time.get_date_string_from_system()],
	]
	var rh := minf(30.0, (r.size.y - 120.0) / rows.size())
	for i in rows.size():
		var y := r.position.y + i * rh
		if i > 0:
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), INK_DIM, 1.0)
		draw_string(_mono, Vector2(r.position.x + 8, y + rh * 0.68), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK_DIM)
		draw_string(_mono, Vector2(r.position.x + 118, y + rh * 0.68), rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 124, 13, INK)
	# mühür
	var warns := int(_info.get("warns", 0))
	var ok := warns == 0
	var c := Vector2(r.get_center().x, r.end.y - 58)
	_stamp(c, "ONAYLANDI" if ok else "RED", ("UÇUŞA ELVERİŞLİ" if ok else "%d KUSUR" % warns), OK_COL if ok else BAD_COL, -0.12)


## Lastik mühür: çift çerçeveli eğik dikdörtgen, büyük yazı, altında küçük not.
func _stamp(c: Vector2, word: String, note: String, col: Color, angle: float) -> void:
	draw_set_transform(c, angle)
	var tw := _mono.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var w := maxf(tw + 40.0, 200.0)
	var box := Rect2(Vector2(-w * 0.5, -34), Vector2(w, 68))
	draw_rect(box, Color(col, 0.9), false, 3.0)
	draw_rect(box.grow(-6), Color(col, 0.7), false, 1.5)
	draw_string(_mono, Vector2(-tw * 0.5, 6), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(col, 0.95))
	var nw := _mono.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(_mono, Vector2(-nw * 0.5, 24), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.85))
	draw_set_transform(Vector2.ZERO)


func _text(pos: Vector2, s: String, size: int, col: Color, bold := false) -> void:
	draw_string(_mono if bold else _font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
