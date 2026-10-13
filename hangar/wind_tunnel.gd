class_name WindTunnel
extends Node3D
## Hangar rüzgâr tüneli: uçak uçmadan, seçilen hız / hücum açısı / yandan kayma / irtifada her
## kanadın hücum açısı ve kaldırması hesaplanır (WingModule'ün kendi formülleri; uçuş koduna
## dokunmaz) ve görselleştirilir:
##   • AKIŞ: kanatlar kaldırma oranına göre renklenir (mavi → yeşil → sarı), stall'da kırmızı;
##     uçağın önündeki ızgaradan akan duman çizgileri kanadın arkasında aşağı sapar, stall'da
##     çalkantılı ve kırmızı, transonik şokta sarı.
##   • YÜK: seçilen G'de her parçanın yükü / dayanımı (yeşil → kırmızı, %100 üstü kırılır).
##   • Grafik: kaldırma katsayısı (CL) – hücum açısı eğrisi, stall noktası, o anki çalışma noktası.
## "Açıyı G'ye göre bul": verilen hızda istenen G'yi verecek hücum açısı aranır (çekilemiyorsa
## uyarır — o hızda o G stall'a sokar).

var hangar: Node          ## hangar.gd (_preview, _craft_root, _set_overlay)
var ui_root: Control

var speed_kmh := 450.0
var aoa_deg := 5.0
var beta_deg := 0.0
var alt_m := 1000.0
var g_load := 3.0
var solve_g := false
var view_mode := 0        ## 0 akış, 1 yük

var _open := false
var _dirty := true
var _vessel_ref: Vessel
var _panel: PanelContainer
var _graph: Control
var _info: Label
var _lines: MeshInstance3D
var _line_mesh: ImmediateMesh
var _mats := {}
var _painted: Array[Part] = []
var _curve: Array[Vector2] = []    ## (hücum açısı°, CL)
var _cur := Vector2.ZERO           ## o anki (hücum açısı°, CL)
var _stall_deg := 15.0
var _aoa_label: Label


func is_open() -> bool:
	return _open


func open() -> void:
	if _panel == null:
		_build_ui()
	_open = true
	_panel.visible = true
	if _lines:
		_lines.visible = true
	_dirty = true


func close() -> void:
	_open = false
	if _panel:
		_panel.visible = false
	if _lines:
		_lines.visible = false
	_clear_paint()


func _process(_delta: float) -> void:
	if not _open:
		return
	var v: Vessel = hangar.get("_preview")
	if v != _vessel_ref:
		_vessel_ref = v
		_painted.clear()      # uçak yeniden kuruldu: eski parçalar gitti
		_dirty = true
	if _dirty:
		_dirty = false
		_recompute()


# ------------------------------------------------------------------ hesap

## Uçağın havaya göre hız yönü (uçak uzayında, birim): burun -Z; hücum açısı α'da hız burnun
## altından gelir; yandan kayma β'da (sağa kayma pozitif) hız sağa döner.
static func flow_dir(alpha: float, beta: float) -> Vector3:
	var v0 := Vector3(0.0, -sin(alpha), -cos(alpha))
	return Basis(Vector3.UP, -beta) * v0


## Bir kanadın bu akıştaki durumu (WingModule'ün uçuştaki hesabının statik kopyası).
static func eval_wing(m: WingModule, vdir: Vector3, q: float, mach: float) -> Dictionary:
	if not m._shape_ready:
		m._read_shape()
	var b := m.part.transform.basis.orthonormalized()
	var span := b.x
	var n := b.y
	var ch := -b.z
	var v := vdir - span * vdir.dot(span)
	var spd := v.length()
	var out := {"aoa": 0.0, "cl": 0.0, "lift": Vector3.ZERO, "stalled": false, "shock": 0.0,
		"cl_max": m.lift_slope * m.stall_angle}
	if spd < 0.01:
		return out
	var aoa := atan2(-v.dot(n), v.dot(ch))
	var cl := m.lift_coefficient(aoa)
	if m.is_delta:
		cl += 2.0 * pow(sin(aoa), 2.0) * cos(aoa) * signf(aoa) * (1.0 - smoothstep(deg_to_rad(35.0), deg_to_rad(55.0), absf(aoa)))
	var flow := -v / spd
	var lift_dir := n - flow * n.dot(flow)
	if lift_dir.length_squared() > 1e-6:
		lift_dir = lift_dir.normalized()
	out["aoa"] = aoa
	out["cl"] = cl
	out["lift"] = lift_dir * cl * q * m.area * spd * spd
	out["stalled"] = absf(aoa) > m.stall_angle
	out["shock"] = smoothstep(m.mach_dd - 0.03, m.mach_dd + 0.08, mach) * (1.0 - smoothstep(1.15, 1.4, mach))
	return out


## Bütün kanatların toplam kaldırması (uçağın yukarı ekseninde, N).
static func total_lift(wings: Array, alpha: float, beta: float, q: float, mach: float) -> float:
	var vdir := flow_dir(alpha, beta)
	var sum := 0.0
	for m: WingModule in wings:
		var r := eval_wing(m, vdir, q, mach)
		sum += (r["lift"] as Vector3).y
	return sum


func _wings(v: Vessel) -> Array:
	var out: Array = []
	for m in v.modules:
		if m is WingModule:
			out.append(m)
	return out


func _recompute() -> void:
	var v: Vessel = hangar.get("_preview")
	if not is_instance_valid(v) or v.parts.is_empty():
		_info.text = "Uçak yok."
		_draw_lines([], [])
		return
	var wings := _wings(v)
	var spd := speed_kmh / 3.6
	var rho := Atmosphere.density(alt_m)
	var q := 0.5 * rho * spd * spd
	var mach := spd / Atmosphere.SPEED_OF_SOUND
	var beta := deg_to_rad(beta_deg)
	var weight := v.mass * 9.81
	var s_total := 0.0
	for m: WingModule in wings:
		if absf(m.part.basis.y.y) > 0.6:
			s_total += m.area
	# eğri: -5°…30° CL (yatay kanat alanına göre)
	_curve.clear()
	var best_cl := -INF
	_stall_deg = 15.0
	for i in 36:
		var a := float(i) - 5.0
		var l := total_lift(wings, deg_to_rad(a), beta, q, mach)
		var cl := l / maxf(q * s_total, 1.0)
		_curve.append(Vector2(a, cl))
		if cl > best_cl:
			best_cl = cl
			_stall_deg = a
	# çalışma noktası: verilen açı ya da istenen G'yi veren açı
	var alpha := deg_to_rad(aoa_deg)
	var cant := false
	if solve_g:
		var need := g_load * weight
		var found := false
		var a2 := -5.0
		while a2 <= _stall_deg:
			if total_lift(wings, deg_to_rad(a2), beta, q, mach) >= need:
				found = true
				break
			a2 += 0.25
		alpha = deg_to_rad(minf(a2, _stall_deg))
		cant = not found
		aoa_deg = rad_to_deg(alpha)
		if _aoa_label:
			_aoa_label.text = "%+.1f°" % aoa_deg
	var vdir := flow_dir(alpha, beta)
	var results := {}
	var lift_sum := Vector3.ZERO
	var stalled_n := 0
	var shock := 0.0
	for m: WingModule in wings:
		var r := eval_wing(m, vdir, q, mach)
		results[m.part] = r
		lift_sum += r["lift"] as Vector3
		if r["stalled"]:
			stalled_n += 1
		shock = maxf(shock, float(r["shock"]))
	var g_now := lift_sum.y / maxf(weight, 1.0)
	_cur = Vector2(rad_to_deg(alpha), lift_sum.y / maxf(q * s_total, 1.0))
	# boyama
	var worst := 0.0
	var worst_name := ""
	for p in v.parts:
		var col := Color(0, 0, 0, 0)
		if view_mode == 0:
			if results.has(p):
				var r: Dictionary = results[p]
				if r["stalled"]:
					col = Color(1.0, 0.15, 0.1)
				else:
					var k := clampf(absf(float(r["cl"])) / maxf(float(r["cl_max"]), 0.01), 0.0, 1.0)
					col = Color(0.2, 0.45, 1.0).lerp(Color(0.2, 1.0, 0.4), minf(k * 1.6, 1.0)).lerp(Color(1.0, 0.9, 0.2), smoothstep(0.6, 1.0, k))
		else:
			# yük: kanatta kendi kaldırması, diğer parçalarda ataleti (n × ağırlık) / dayanım
			var force := 0.0
			if results.has(p):
				var rp: Dictionary = results[p]
				force = (rp["lift"] as Vector3).length()
			else:
				force = absf(g_now) * p.get_mass() * 9.81
			var ratio := force / maxf(p.strength, 1.0)
			if ratio > worst:
				worst = ratio
				worst_name = p.title
			col = Color(0.2, 1.0, 0.4).lerp(Color(1.0, 0.85, 0.2), clampf(ratio * 1.5, 0.0, 1.0)).lerp(Color(1.0, 0.1, 0.05), smoothstep(0.65, 1.0, ratio))
		_paint(p, col)
	_draw_streamlines(v, wings, results, vdir)
	# bilgi
	var lines := PackedStringArray()
	lines.append("Mach %.2f  ·  dinamik basınç %d Pa  ·  kanat alanı %.1f m²" % [mach, q, s_total])
	lines.append("Kaldırma %d kN  =  %.1f G   (ağırlık %d kN)" % [lift_sum.y / 1000.0, g_now, weight / 1000.0])
	lines.append("Stall açısı ~%d°  ·  CL en çok %.2f" % [_stall_deg, best_cl])
	if stalled_n > 0:
		lines.append("⚠ %d yüzey stall'da" % stalled_n)
	if shock > 0.2:
		lines.append("⚠ Transonik şok (titreşim, Mach tuck)")
	if solve_g and cant:
		lines.append("⚠ Bu hızda %.1f G çekilemez — stall'a girer" % g_load)
	if view_mode == 1 and worst_name != "":
		lines.append(("⚠ " if worst > 1.0 else "") + "En çok zorlanan: %s (%%%d)" % [worst_name, worst * 100.0])
	_info.text = "\n".join(lines)
	_graph.queue_redraw()


# ------------------------------------------------------------------ boyama

func _mat(c: Color) -> StandardMaterial3D:
	var key := Color(snappedf(c.r, 0.05), snappedf(c.g, 0.05), snappedf(c.b, 0.05)).to_html(false)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = Color(c, 0.55)
	_mats[key] = m
	return m


func _paint(p: Part, c: Color) -> void:
	if c.a <= 0.0:
		hangar.call("_set_overlay", p, null)
		return
	hangar.call("_set_overlay", p, _mat(c))
	if not p in _painted:
		_painted.append(p)


func _clear_paint() -> void:
	for p in _painted:
		if is_instance_valid(p):
			hangar.call("_set_overlay", p, null)
	_painted.clear()


# ------------------------------------------------------------------ duman çizgileri

## Uçağın önündeki ızgaradan akış yönünde çizgiler: bir kanadın kutusundan geçerken o kanadın
## CL'si kadar aşağı (aşağı akış) saparlar; stall'daki kanattan geçen çizgi çalkantılı ve kırmızı,
## şoktaki kanattan geçen sarı olur. Uçak uzayında (hangarın Craft düğümü altında).
func _draw_streamlines(v: Vessel, wings: Array, results: Dictionary, vdir: Vector3) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in v.parts:
		var bb := p.local_aabb(0.0)
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
	var air := -vdir      # hava uçağa göre ters yönde akar
	var pts: Array = []
	var cols: Array = []
	var nx := 9
	var ny := 5
	var length := (hi.z - lo.z) + 14.0
	var step := 0.5
	for ix in nx:
		for iy in ny:
			var p := Vector3(lerpf(lo.x - 1.0, hi.x + 1.0, (ix + 0.5) / nx), lerpf(lo.y - 0.6, hi.y + 0.8, (iy + 0.5) / ny), lo.z - 5.0)
			p -= air * 1.0
			var drift := 0.0
			var col := Color(0.85, 0.92, 1.0, 0.7)
			var turb := 0.0
			var s := 0.0
			while s < length:
				var prev := p
				for m: WingModule in wings:
					var lp := m.part.transform.affine_inverse() * p
					var sz := m.part.size
					if absf(lp.x) < sz.x * 0.5 + 0.2 and absf(lp.y) < 1.2 and absf(lp.z) < sz.z * 0.5:
						var r: Dictionary = results.get(m.part, {})
						if r.is_empty():
							continue
						drift -= float(r["cl"]) * 0.06
						if r["stalled"]:
							turb = 1.0
							col = Color(1.0, 0.25, 0.15, 0.85)
						elif float(r["shock"]) > 0.3 and col.r < 0.99:
							col = Color(1.0, 0.85, 0.25, 0.8)
				p += air * step + Vector3(0.0, drift * step, 0.0)
				if turb > 0.0:
					p += Vector3(sin(s * 3.1 + ix) * 0.08, cos(s * 2.3 + iy) * 0.08, 0.0) * turb
				drift *= 0.97
				pts.append(prev)
				pts.append(p)
				cols.append(col)
				cols.append(col)
				s += step
	_draw_lines(pts, cols)


func _draw_lines(pts: Array, cols: Array) -> void:
	if _lines == null:
		_line_mesh = ImmediateMesh.new()
		_lines = MeshInstance3D.new()
		_lines.mesh = _line_mesh
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never;\nvoid fragment() {\n\tfloat d = fract(UV.x * 0.35 - TIME * 1.4);\n\tALBEDO = COLOR.rgb;\n\tALPHA = COLOR.a * (0.3 + 0.7 * step(d, 0.55));\n}\n"
		var sm := ShaderMaterial.new()
		sm.shader = sh
		_lines.material_override = sm
		var root: Node3D = hangar.get("_craft_root")
		root.add_child(_lines)
	_line_mesh.clear_surfaces()
	if pts.is_empty():
		return
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var dist := 0.0
	for i in pts.size():
		if i % 2 == 1:
			dist += (pts[i] as Vector3).distance_to(pts[i - 1])
		_line_mesh.surface_set_color(cols[i])
		_line_mesh.surface_set_uv(Vector2(dist, 0.0))
		_line_mesh.surface_add_vertex(pts[i])
	_line_mesh.surface_end()


# ------------------------------------------------------------------ arayüz

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -88
	ui_root.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 360
	row.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var t := Label.new()
	t.text = "RÜZGÂR TÜNELİ"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	head.add_child(t)
	var mode := OptionButton.new()
	mode.add_item("Akış")
	mode.add_item("Yük")
	mode.focus_mode = Control.FOCUS_NONE
	mode.item_selected.connect(func(i: int) -> void:
		view_mode = i
		_dirty = true)
	head.add_child(mode)
	var close_b := Button.new()
	close_b.text = "✕"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	head.add_child(close_b)
	_slider(col, "Hız", 80.0, 1500.0, 10.0, speed_kmh, "%d km/sa", func(x: float) -> void: speed_kmh = x)
	_aoa_label = _slider(col, "Hücum açısı", -5.0, 30.0, 0.5, aoa_deg, "%+.1f°", func(x: float) -> void: aoa_deg = x)
	_slider(col, "Yan kayma", -15.0, 15.0, 0.5, beta_deg, "%+.1f°", func(x: float) -> void: beta_deg = x)
	_slider(col, "İrtifa", 0.0, 14000.0, 250.0, alt_m, "%d m", func(x: float) -> void: alt_m = x)
	_slider(col, "G", 1.0, 9.0, 0.5, g_load, "%.1f G", func(x: float) -> void: g_load = x)
	var sg := CheckBox.new()
	sg.text = "Açıyı G'ye göre bul"
	sg.focus_mode = Control.FOCUS_NONE
	sg.toggled.connect(func(on: bool) -> void:
		solve_g = on
		_dirty = true)
	col.add_child(sg)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
	col.add_child(_info)
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(330, 220)
	_graph.draw.connect(_draw_graph)
	row.add_child(_graph)


## Etiketli kaydırıcı; değer etiketini döndürür (G'ye göre açı bulunca güncellenir).
func _slider(parent: Control, title: String, lo: float, hi: float, step: float, value: float, fmt: String, setter: Callable) -> Label:
	var r := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 92
	l.add_theme_font_size_override("font_size", 12)
	r.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 170
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	r.add_child(s)
	var vl := Label.new()
	vl.text = fmt % value
	vl.custom_minimum_size.x = 70
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.add_theme_font_size_override("font_size", 12)
	r.add_child(vl)
	s.value_changed.connect(func(x: float) -> void:
		setter.call(x)
		vl.text = fmt % x
		_dirty = true)
	parent.add_child(r)
	return vl


func _draw_graph() -> void:
	var sz := _graph.size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.04, 0.06, 0.85)
	bg.set_corner_radius_all(6)
	_graph.draw_style_box(bg, Rect2(Vector2.ZERO, sz))
	if _curve.is_empty():
		return
	var font := ThemeDB.fallback_font
	var pad := Vector2(34, 18)
	var w := sz.x - pad.x - 10.0
	var h := sz.y - pad.y * 2.0
	var cl_lo := -0.5
	var cl_hi := 0.5
	for pt in _curve:
		cl_lo = minf(cl_lo, pt.y)
		cl_hi = maxf(cl_hi, pt.y)
	cl_hi *= 1.1
	var to_px := func(c: Vector2) -> Vector2:
		return Vector2(pad.x + (c.x + 5.0) / 35.0 * w, pad.y + (1.0 - (c.y - cl_lo) / maxf(cl_hi - cl_lo, 0.01)) * h)
	# eksenler: CL = 0 ve hücum açısı = 0
	var axis_col := Color(1, 1, 1, 0.2)
	_graph.draw_line(to_px.call(Vector2(-5, 0)), to_px.call(Vector2(30, 0)), axis_col, 1.0)
	_graph.draw_line(to_px.call(Vector2(0, cl_lo)), to_px.call(Vector2(0, cl_hi)), axis_col, 1.0)
	# stall çizgisi
	var sx: Vector2 = to_px.call(Vector2(_stall_deg, cl_lo))
	_graph.draw_line(sx, Vector2(sx.x, pad.y), Color(1.0, 0.3, 0.2, 0.6), 1.0)
	_graph.draw_string(font, Vector2(sx.x + 3, pad.y + 10), "stall %d°" % _stall_deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.45, 0.35))
	# eğri
	var poly := PackedVector2Array()
	for pt in _curve:
		poly.append(to_px.call(pt))
	_graph.draw_polyline(poly, Color(0.45, 1.0, 0.65), 2.0, true)
	# çalışma noktası
	_graph.draw_circle(to_px.call(_cur), 5.0, Color(1.0, 0.9, 0.3))
	_graph.draw_string(font, Vector2(pad.x, sz.y - 4), "hücum açısı  −5° … 30°", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.76, 0.82))
	_graph.draw_string(font, Vector2(4, pad.y + 8), "CL %.1f" % cl_hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.76, 0.82))
