class_name MedalView
## Rütbe apoleti ve madalya kurdeleleri (çizimle, doku yok). Hangar kadro paneli,
## madalya ayrıntı penceresi ve uçuş raporu kullanır. Veri: Medals.

const GOLD := Color(1.0, 0.82, 0.3)
const NAVY := Color(0.07, 0.11, 0.24)


## Omuz apoleti: lacivert zemin, altın yıldızlar; üst subayda defne, generalde altın şerit.
class RankBadge extends Control:
	var rank := 0

	func _draw() -> void:
		var r: Dictionary = Medals.RANKS[clampi(rank, 0, Medals.RANKS.size() - 1)]
		var s := size
		var sb := StyleBoxFlat.new()
		sb.bg_color = NAVY
		sb.set_corner_radius_all(4)
		sb.corner_radius_top_left = int(s.y * 0.5)
		sb.corner_radius_bottom_left = int(s.y * 0.5)
		sb.border_color = Color(MedalView.GOLD, 0.8)
		sb.set_border_width_all(1)
		draw_style_box(sb, Rect2(Vector2.ZERO, s))
		var x0 := s.y * 0.55
		if r["general"]:
			draw_rect(Rect2(s.x - 7.0, 2.0, 4.0, s.y - 4.0), MedalView.GOLD)
		var n: int = r["stars"]
		var avail := s.x - x0 - (12.0 if r["general"] else 6.0)
		var rad := minf(s.y * 0.28, avail / (n * 2.4))
		var cy := s.y * (0.42 if r["wreath"] else 0.5)
		for i in n:
			var cx := x0 + avail * (i + 0.5) / n
			MedalView.draw_star(self, Vector2(cx, cy), rad, MedalView.GOLD if rank > 0 else Color(0.85, 0.85, 0.9))
		if r["wreath"]:
			# defne dalı: yıldızların altında iki yay
			var c := Vector2(x0 + avail * 0.5, s.y * 0.15)
			draw_arc(c, s.y * 0.68, deg_to_rad(40), deg_to_rad(80), 6, MedalView.GOLD, 1.5, true)
			draw_arc(c, s.y * 0.68, deg_to_rad(100), deg_to_rad(140), 6, MedalView.GOLD, 1.5, true)
		# düğme
		draw_circle(Vector2(s.y * 0.3, s.y * 0.5), 2.2, Color(MedalView.GOLD, 0.9))


## Madalya kurdelesi: zemin rengi, ortada şerit, kenarlarda ince çizgi. Kazanılmadıysa soluk.
class Ribbon extends Control:
	var colors: Array = [Color.GRAY, Color.WHITE]
	var earned := true

	func _draw() -> void:
		var s := size
		var a := colors[0] as Color
		var b := colors[1] as Color
		if not earned:
			a = Color(a.v * 0.35, a.v * 0.35, a.v * 0.38)
			b = Color(b.v * 0.4, b.v * 0.4, b.v * 0.42)
		draw_rect(Rect2(Vector2.ZERO, s), a)
		draw_rect(Rect2(s.x * 0.4, 0, s.x * 0.2, s.y), b)
		draw_rect(Rect2(1.5, 0, 1.5, s.y), b)
		draw_rect(Rect2(s.x - 3.0, 0, 1.5, s.y), b)
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.5), false, 1.0)


static func draw_star(c: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		pts.append(at + Vector2(cos(ang), sin(ang)) * (r if i % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, col)


static func rank_badge(rank: int, sz := Vector2(56, 22)) -> Control:
	var b := RankBadge.new()
	b.rank = rank
	b.custom_minimum_size = sz
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.tooltip_text = String(Medals.RANKS[clampi(rank, 0, Medals.RANKS.size() - 1)]["name"])
	return b


static func ribbon(m: Dictionary, earned: bool, sz := Vector2(28, 10)) -> Control:
	var r := Ribbon.new()
	r.colors = m["colors"]
	r.earned = earned
	r.custom_minimum_size = sz
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.tooltip_text = "%s%s\n%s" % [m["name"], "" if earned else "  (kazanılmadı)", m["desc"]]
	return r


## Kadro satırı: kazanılan kurdeleler + "Madalyalar" ayrıntı düğmesi.
static func medal_row(p: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var got: Array = p.get("medals", [])
	for m in Medals.LIST:
		if m["id"] in got:
			row.add_child(ribbon(m, true))
	if got.is_empty():
		var l := Label.new()
		l.text = "Madalya yok"
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(UiTheme.DIM, 0.7))
		row.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	row.add_child(gap)
	var btn := Button.new()
	btn.text = " Madalyalar %d/%d " % [got.size(), Medals.LIST.size()]
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", UiTheme.ACCENT)
	btn.pressed.connect(func() -> void: open_detail(btn, p))
	row.add_child(btn)
	return row


## Ayrıntı penceresi: tüm madalyalar (kazanılmayanlar soluk, ilerlemeyle) ve sıradaki rütbe.
static func open_detail(from: Control, p: Dictionary) -> PopupPanel:
	var pp := PopupPanel.new()
	pp.theme = UiTheme.get_theme()
	var psb := UiTheme.flat(Color(0.03, 0.045, 0.06, 0.98), 10)
	psb.set_content_margin_all(16)
	psb.border_color = Color(UiTheme.ACCENT, 0.35)
	psb.set_border_width_all(1)
	pp.add_theme_stylebox_override("panel", psb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pp.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	head.add_child(rank_badge(int(p.get("rank", 0)), Vector2(64, 26)))
	head.add_child(UiTheme.title("%s %s — MADALYALAR" % [Medals.rank_name(p), p["name"]], 18))
	var nxt := int(p.get("rank", 0)) + 1
	var sub := Label.new()
	if nxt < Medals.RANKS.size():
		var r: Dictionary = Medals.RANKS[nxt]
		sub.text = "Sıradaki rütbe: %s — seviye %d ve %d uçuş (şu an seviye %d, %d uçuş)" % [r["name"], r["level"], r["flights"], p["level"], p["flights"]]
	else:
		sub.text = "En yüksek rütbe."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", UiTheme.DIM)
	box.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for m in Medals.LIST:
		var earned := Medals.has(p, m["id"])
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.custom_minimum_size.x = 330
		cell.add_child(ribbon(m, earned, Vector2(34, 12)))
		var txt := VBoxContainer.new()
		txt.add_theme_constant_override("separation", 0)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(txt)
		var n := Label.new()
		n.text = m["name"] + ("" if earned else "   " + Medals.progress(p, m))
		n.add_theme_font_size_override("font_size", 14)
		n.add_theme_color_override("font_color", GOLD if earned else Color(UiTheme.DIM, 0.6))
		txt.add_child(n)
		var d := Label.new()
		d.text = m["desc"]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 280
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.75 if earned else 0.4))
		txt.add_child(d)
		grid.add_child(cell)
	# açan pencerenin (kadro popup'ı) çocuğu: iç içe popup, kadro kapanmaz
	from.get_window().add_child(pp)
	pp.popup_hide.connect(pp.queue_free)
	pp.popup_centered(Vector2i(740, 470))
	return pp


## Uçuş raporu satırı: "MADALYA: …" kurdeleyle, "TERFİ: …" apoletle.
static func report_line(l: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	if l.begins_with("TERFİ"):
		for i in range(Medals.RANKS.size() - 1, -1, -1):
			if (" %s oldu" % Medals.RANKS[i]["name"]) in l:
				row.add_child(rank_badge(i))
				break
	else:
		for m in Medals.LIST:
			if l.begins_with("MADALYA: %s " % m["name"]):
				row.add_child(ribbon(m, true, Vector2(34, 12)))
				break
	var lb := Label.new()
	lb.text = l
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.custom_minimum_size.x = 380
	lb.add_theme_color_override("font_color", GOLD if l.begins_with("MADALYA") else UiTheme.ACCENT)
	row.add_child(lb)
	return row
