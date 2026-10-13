class_name CampaignUi
## Kariyer ekranı için hikâye arayüzü (Campaign): perde başlığı + hedefler, perde geçişi
## brifingi (sinematik sayfalar: konuşan, daktilo metni) ve zafer ekranı (sefer istatistikleri).

const GOLD := Color(1.0, 0.85, 0.4)
const ACT_COLORS := {1: Color(0.45, 0.85, 1.0), 2: Color(1.0, 0.62, 0.3), 3: Color(1.0, 0.36, 0.32), 4: Color(1.0, 0.85, 0.4)}
const SPEAKER_COLORS := {"kaya": Color(1.0, 0.85, 0.4), "enemy": Color(1.0, 0.45, 0.38), "ace": Color(1.0, 0.3, 0.3),
	"ece": Color(0.55, 0.9, 1.0), "deniz": Color(0.6, 1.0, 0.7)}


static func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.font_weight = 700
		l.add_theme_font_override("font", f)
	return l


static func _panel(border: Color, bg := Color(0.03, 0.045, 0.06, 0.92)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.flat(bg, 10)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Küçük perde kartı: "PERDE 2 · KARŞI TAARRUZ" + hedef satırları. fill_header ile doldurulur.
static func header_box() -> PanelContainer:
	var p := _panel(Color(1, 1, 1, 0.2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	return p


static func fill_header(p: PanelContainer) -> void:
	var v: VBoxContainer = p.get_child(0)
	for c in v.get_children():
		c.queue_free()
	if Career.sandbox():
		p.visible = false
		return
	p.visible = true
	var a := Campaign.act()
	var col: Color = ACT_COLORS[a]
	(p.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(col, 0.6)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := _label(Campaign.act_title() if not Campaign.won() else "SEFER KAZANILDI", 15, col, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(_label("Kara Doğan: %s" % ("düştü" if Campaign.ace_defeated() else "%d karşılaşma" % Campaign.ace()["encounters"].size()), 12, Color(1.0, 0.5, 0.45)))
	for g: Dictionary in Campaign.goals():
		var l := _label(("✔  " if g["done"] else "▢  ") + String(g["text"]), 13, Color(0.6, 1.0, 0.7) if g["done"] else Color(0.85, 0.88, 0.92))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 420
		v.add_child(l)


## Perde geçişi brifingi: tam ekran kaplama, büyük perde başlığı, sayfalar (◀ ▶, Atla).
## a: perde (1-3) ya da 4 (zafer öncesi son sözler). Kapanınca on_done.
static func briefing(parent: Control, a: int, on_done: Callable) -> Control:
	var pages := Campaign.pages(a)
	var root := Control.new()
	root.name = "CampaignBrief"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var col: Color = ACT_COLORS.get(a, GOLD)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(820, 0)
	box.offset_left = -410
	box.offset_right = 410
	box.offset_top = -230
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var kicker := _label("KARARGÂH BRİFİNGİ" if a <= 3 else "SON TELSİZ KAYITLARI", 14, Color(1, 1, 1, 0.55), true)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var title := _label(("PERDE %d" % a) if a <= 3 else "ZAFER", 54, col, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label(String(Campaign.ACTS[a]["title"]) + "  ·  " + String(Campaign.ACTS[a]["tag"]) if a <= 3 else "Kuzey Havaalanı düştü", 18, Color(0.9, 0.92, 0.95), true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var card := _panel(Color(col, 0.6), Color(0.02, 0.03, 0.045, 0.96))
	card.custom_minimum_size.y = 190
	box.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var who := _label("", 14, GOLD, true)
	cv.add_child(who)
	var text := _label("", 19, Color(0.92, 0.94, 0.97))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 780
	cv.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var count := _label("", 13, Color(1, 1, 1, 0.5))
	var idx := [0]
	var close := func() -> void:
		root.queue_free()
		on_done.call()
	var show := func() -> void:
		var p: Array = pages[idx[0]]
		who.text = Campaign.SPEAKERS.get(p[0], "")
		who.add_theme_color_override("font_color", SPEAKER_COLORS.get(p[0], GOLD))
		text.text = "“%s”" % p[1]
		text.visible_ratio = 0.0
		root.create_tween().tween_property(text, "visible_ratio", 1.0, clampf(String(p[1]).length() / 110.0, 0.5, 3.0))
		count.text = "%d / %d" % [idx[0] + 1, pages.size()]
	var prev := UiTheme.big_button("◀", func() -> void:
		idx[0] = maxi(idx[0] - 1, 0)
		show.call())
	var next := UiTheme.big_button("Devam  ▶", func() -> void:
		if text.visible_ratio < 1.0:
			text.visible_ratio = 1.0
			return
		if idx[0] + 1 >= pages.size():
			close.call()
		else:
			idx[0] += 1
			show.call(), true)
	row.add_child(prev)
	row.add_child(count)
	row.add_child(next)
	row.add_child(UiTheme.big_button("Atla", close))
	if pages.is_empty():
		close.call()
	else:
		show.call()
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.6)
	return root


## Zafer ekranı: sefer istatistikleri ve yeni sefer.
static func victory(parent: Control, on_new: Callable, on_close: Callable) -> Control:
	var root := Control.new()
	root.name = "CampaignVictory"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(640, 0)
	box.offset_left = -320
	box.offset_right = 320
	box.offset_top = -300
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	var t := _label("ZAFER", 72, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := _label("Kara Doğan düştü, Kuzey Havaalanı bizde. Gök Cephesi kapandı.", 18, Color(0.9, 0.92, 0.95))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	var card := _panel(Color(GOLD, 0.6))
	box.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for row: Array in Campaign.victory_stats():
		grid.add_child(_label(String(row[0]), 15, Color(1, 1, 1, 0.6)))
		grid.add_child(_label(String(row[1]), 15, Color.WHITE, true))
	var enc := PackedStringArray()
	for e: Dictionary in Campaign.ace()["encounters"]:
		enc.append("Gün %d · P%d · %s" % [int(e["day"]), int(e["act"]), String(Ace.STORY.get(e["result"], e["result"])).get_slice(":", 0).get_slice(";", 0)])
	if not enc.is_empty():
		var l := _label("KARA DOĞAN DOSYASI\n" + "\n".join(enc), 13, Color(1.0, 0.65, 0.6))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 620
		box.add_child(l)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	box.add_child(row2)
	row2.add_child(UiTheme.big_button("Cepheye bak", func() -> void:
		root.queue_free()
		on_close.call()))
	row2.add_child(UiTheme.big_button("Yeni sefer", func() -> void:
		root.queue_free()
		on_new.call(), true))
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 1.0)
	return root


## `--menu --campaigndemo=N`: ekran görüntüsü için örnek perde durumu (kayıt yazılmaz).
## N = 1..3 (o perdenin brifingi açık), 4 = zafer ekranı, 0 = brifingsiz kariyer ekranı.
static func seed_demo(n: int) -> void:
	Game.mode = "career"
	Front.new_campaign()
	var s := Campaign.st()
	Career.completed["egitim"] = 1
	Career.completed["kesif"] = 1
	Career.completed["kara"] = 2
	s["def_wins"] = 4
	s["ace"]["cameo"] = true
	s["ace"]["encounters"] = [{"day": 4, "act": 1, "mode": "cameo", "result": "cameo", "mission": "kara"}]
	Career.front["ovakoy"] = Front.DOST
	Career.day = 7
	var a := clampi(n, 0, 4)   # 5: zafer ekranı (brifingsiz)
	if a >= 2 or a == 0:
		s["act"] = 2
		s["act_day"]["2"] = 7
		s["act_missions"] = 2
		s["flags"]["sam_net"] = true
		s["ace"]["encounters"].append({"day": 9, "act": 2, "mode": "hunt", "result": "escaped_damaged", "mission": "sam"})
		s["ace"]["hunts"] = 1
		Career.front["orta"] = Front.DOST
		Career.front["derekoy"] = Front.CEKISME
		Career.day = 11
		Campaign._brief_pages(2)
	if a >= 3:
		s["act"] = 3
		s["act_day"]["3"] = 15
		s["flags"]["fleet"] = true
		for r in ["derekoy", "kuzeykent", "dogudeniz"]:
			Career.front[r] = Front.DOST
		Career.day = 16
		Campaign._brief_pages(3)
	if a >= 4:
		s["ace"]["defeated"] = true
		s["ace"]["encounters"].append({"day": 19, "act": 3, "mode": "finale", "result": "defeated", "mission": "sondarbe"})
		s["stats"] = {"missions": 21, "wins": 16, "fails": 5}
		s["act_day"]["4"] = 20
		Career.front["kuzeyhava"] = Front.DOST
		Career.day = 20
		s["won"] = true
		Campaign._brief_pages(4)
	s["brief"] = a if a in [1, 2, 3] else 0
	s["victory_seen"] = n < 4
	s["victory_brief"] = n >= 5
