class_name DesignDebrief
extends RefCounted
## Uçuş sonu "TASARIM DEĞERLENDİRMESİ": görev kartı + Game.last_result + uçulan tasarımın tahmini
## performansından (kart["design"], hangarda MissionCheck.estimate) tasarımın görevde nasıl
## davrandığını anlatır: yakıt payı, varış süresi, tespit, hasar, G; S/A/B/C notu ve bir sonraki
## tasarım için kısa öneri. Görev üreticisi sonucu kendisi doldurur; eksik alanları fill_result tamamlar.

const GRADE_COLORS := {"S": Color(1.0, 0.85, 0.35), "A": Color(0.45, 1.0, 0.6), "B": Color(0.55, 0.8, 1.0), "C": Color(1.0, 0.5, 0.4)}


## main._show_report: kart varsa sonucun eksik alanlarını uçuştan doldur (var olanlara dokunmaz).
static func fill_result(m: Node, ok := true) -> void:
	if Game.mission_card.is_empty():
		return
	var r := Game.last_result
	if not r.has("card"):
		r["card"] = Game.mission_card
	var v: Vessel = m.get("vessel")
	if is_instance_valid(v):
		if not r.has("fuel_left_kg"):
			r["fuel_left_kg"] = v.fuel_amount()
		if not r.has("damage_taken") and not v.parts.is_empty():
			var dmg := 0.0
			for p in v.parts:
				dmg += 1.0 - p.health_ratio()
			r["damage_taken"] = dmg / v.parts.size()
	var fs: FlightStats = m.get("flight_stats")
	if is_instance_valid(fs):
		if not r.has("max_g"):
			r["max_g"] = fs.max_g
		r["max_kmh"] = fs.max_kmh
		r["stall_time"] = fs.stall_time
		r["cstalls"] = fs.cstalls
		r["fuel_start_kg"] = fs.fuel_start
	if not r.has("time_s"):
		r["time_s"] = float(m.get("_time"))
	var mm: MissionManager = m.get("mission")
	if mm != null and is_instance_valid(mm) and not mm.def.is_empty():
		if not r.has("kills"):
			r["kills"] = mm.kills
		if not r.has("success"):
			r["success"] = mm.state == "success"
		if not r.has("mission_time_s"):
			r["mission_time_s"] = mm.elapsed
	if not r.has("success"):
		r["success"] = ok and not bool(r.get("rehearsal", false))
	r["lost"] = bool(m.get("_ejected")) or not ok
	Game.last_result = r


## Rapor bölümü (FlightReport kutusuna eklenir).
static func build(r: Dictionary, card: Dictionary) -> Control:
	var a := analyze(r, card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var t := Label.new()
	t.text = "TASARIM DEĞERLENDİRMESİ"
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	head.add_child(t)
	var g := Label.new()
	var grade := String(a["grade"])
	g.text = " %s " % grade
	g.add_theme_font_size_override("font_size", 22)
	var gc: Color = GRADE_COLORS.get(grade, Color.WHITE)
	g.add_theme_color_override("font_color", gc)
	var gs := UiTheme.flat(Color(gc, 0.14), 6)
	gs.border_color = gc
	gs.set_border_width_all(1)
	g.add_theme_stylebox_override("normal", gs)
	g.tooltip_text = "Not: sonuç + tasarım payları (süre, yakıt, görünmezlik, hasar) — puan %d/100" % int(a["score"])
	head.add_child(g)
	if bool(r.get("rehearsal", false)):
		var pr := Label.new()
		pr.text = "(prova)"
		pr.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		head.add_child(pr)
	for it: Array in a["lines"]:
		var lb := Label.new()
		lb.text = ("+ " if int(it[0]) > 0 else ("− " if int(it[0]) < 0 else "· ")) + String(it[1])
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size.x = 520
		lb.add_theme_font_size_override("font_size", 14)
		lb.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65) if int(it[0]) > 0 else (Color(1.0, 0.6, 0.5) if int(it[0]) < 0 else Color(0.85, 0.88, 0.92)))
		box.add_child(lb)
	var s := Label.new()
	s.text = "Sonraki tasarım: " + String(a["suggestion"])
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.custom_minimum_size.x = 520
	s.add_theme_font_size_override("font_size", 14)
	s.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(s)
	return box


## {"lines": [[+1/0/-1, metin], …], "grade": "S".."C", "score": 0..100, "suggestion": metin}
static func analyze(r: Dictionary, card: Dictionary) -> Dictionary:
	var e: Dictionary = card.get("design", {}) if card.get("design", {}) is Dictionary else {}
	var lines: Array = []
	var add := func(sign: int, text: String) -> void:
		lines.append([sign, text])
	var score := 0.0
	var possible := 0.0
	var wst := {"key": "", "v": 1.0}   # en kötü etken → öneri (lambda yerel değişkeni değiştiremez)
	var note := func(key: String, v: float) -> void:
		if v < float(wst["v"]):
			wst["v"] = v
			wst["key"] = key
	var rehearsal := bool(r.get("rehearsal", false))
	var success := bool(r.get("success", false))
	var limit := float(card.get("time_limit_s", 0.0))
	var km := MissionCheck.one_way_km(card)
	# sonuç
	if not rehearsal:
		possible += 40.0
		if success:
			score += 40.0
		else:
			note.call("fail", 0.0)
	# hangarda karşılanmamış kart istekleri (kontrol listesindeki ✗)
	var chk: Dictionary = card.get("check", {}) if card.get("check", {}) is Dictionary else {}
	if not chk.is_empty():
		possible += 10.0
		var nf := 0
		for it: Variant in chk.get("items", []):
			if it is Array and int(it[0]) == MissionCheck.FAIL:
				nf += 1
				if nf <= 3:
					add.call(-1, "Kart karşılanmamıştı: " + String(it[1]))
		if nf == 0:
			score += 10.0
		else:
			note.call("card", 0.25)
	# süre
	var tt := float(r.get("time_to_target_s", -1.0))
	var verb := "Hedefe %s'de ulaştın"
	if tt < 0.0 and success and not rehearsal:
		tt = float(r.get("mission_time_s", r.get("time_s", -1.0)))
		verb = "Görevi %s'de tamamladın"
	if limit > 0.0:
		possible += 15.0
		if tt >= 0.0:
			var txt := (verb % MissionCheck.dur(tt)) + " (süre %s)" % MissionCheck.dur(limit)
			if tt <= limit * 0.8:
				score += 15.0
				var fast := float(e.get("v0", 0.0)) * 3.6
				add.call(1, txt + ((" — %d km/sa azami hız işe yaradı" % fast) if fast >= 900.0 else ""))
			elif tt <= limit:
				score += 8.0
				add.call(0, txt + " — kıl payı")
				note.call("slow", 0.5)
			else:
				add.call(-1, txt + " — " + _why_slow(e))
				note.call("slow", 0.1)
		elif rehearsal:
			add.call(-1, "Hedef bölgesine varılmadı")
	elif tt > 0.0 and km > 0.0:
		add.call(0, (verb % MissionCheck.dur(tt)) + " (%d km)" % km)
	# tırmanma / alık
	var talt := float(card.get("target_alt_m", 0.0))
	if not e.is_empty():
		if float(e.get("intake_pct", 1.0)) < 0.99:
			add.call(-1, "Hava alığı yetersizdi (%%%d): motor tam güç veremedi, tırmanışta yavaş kaldın" % (float(e["intake_pct"]) * 100.0))
			note.call("intake", 0.2)
		if talt > 0.0:
			var ct := MissionCheck.climb_time(e, talt)
			if ct == INF:
				add.call(-1, "%d m'ye çıkamıyordu (tavan ~%d m): daha güçlü motor / daha geniş kanat" % [talt, float(e.get("ceiling", 0.0))])
				note.call("climb", 0.0)
			elif limit > 0.0 and ct > limit * 0.5:
				add.call(-1, "%d m'ye tırmanma ~%s sürdü: sürenin yarısı tırmanışta geçti" % [talt, MissionCheck.dur(ct)])
				note.call("climb", 0.3)
			else:
				add.call(1, "%d m'ye ~%s'de tırmandın" % [talt, MissionCheck.dur(ct)])
	# yakıt
	var fl := float(r.get("fuel_left_kg", -1.0))
	var cap := float(e.get("fuel", r.get("fuel_start_kg", 0.0)))
	if fl >= 0.0 and cap > 0.0:
		possible += 15.0
		var pct := fl / cap
		var need := km * 2.0
		var roomy := need > 0.0 and float(e.get("range_km", 0.0)) >= need * 1.6
		if pct >= 0.15:
			score += 15.0
			if pct > 0.6 and need > 0.0 and float(card.get("payload_kg", 0.0)) > float(e.get("payload_kg", 0.0)):
				add.call(0, "Yakıtın %%%d'i kullanılmadı: tankı azaltıp daha çok yük taşıyabilirdin" % (pct * 100.0))
			elif roomy:
				add.call(1, "Fazladan tank sayesinde dönüşte %d kg yakıtın kaldı" % fl)
			else:
				add.call(1, "Dönüşte %d kg yakıtın kaldı (%%%d)" % [fl, pct * 100.0])
		elif pct >= 0.05:
			score += 6.0
			add.call(0, "Dönüşte yalnız %d kg yakıt kaldı: menzil yetti ama pay çok azdı" % fl)
			note.call("fuel", 0.4)
		else:
			add.call(-1, "Yakıt bitmek üzereydi (%d kg): ek tank ya da daha verimli motor gerekli" % fl)
			note.call("fuel", 0.05)
	# tespit / kilit
	var det: Variant = r.get("detected_by", [])
	var n_det := 0
	if det is Array:
		n_det = (det as Array).size()
	elif det is int or det is float:
		n_det = int(det)
	var locks := int(r.get("locks", r.get("sam_locks", 0)))
	var who := ""
	if det is Array and not (det as Array).is_empty():
		var names := PackedStringArray()
		for d: Variant in det:
			if names.size() < 3 and not String(d) in names:
				names.append(String(d))
		who = " (" + ", ".join(names) + ")"
	n_det = maxi(n_det, locks)
	var agl := float(r.get("ingress_agl_avg", -1.0))
	var cm := int(e.get("chaff", 0)) > 0 or bool(e.get("ecm", false))
	var threats: Array = card.get("threats", []) if card.get("threats", []) is Array else []
	if not rehearsal and not threats.is_empty():
		possible += 15.0
		if n_det == 0:
			score += 15.0
			if agl >= 0.0 and agl < 250.0:
				add.call(1, "Alçak giriş (ortalama %d m) sayesinde fark edilmedin" % agl)
			elif float(e.get("mach_max", 0.0)) >= 1.2:
				add.call(1, "Hızın sayesinde savunma tepki veremeden geçtin")
			else:
				add.call(1, "Düşman radarı seni hiç kilitlemedi")
		else:
			score += 8.0 if n_det <= 2 else 0.0
			var txt := ("Düşman radarı seni %d kez kilitledi" % locks) if locks > 0 else ("%d düşman sensörü seni gördü%s" % [n_det, who])
			if not cm:
				txt += ": chaff/ECM taşımayı düşün"
				note.call("detected", 0.2 if n_det > 2 else 0.45)
			elif agl > 300.0:
				txt += " — girişte ortalama %d m: daha alçak uç (Shift+U)" % agl
				note.call("high", 0.4)
			add.call(-1, txt)
	elif agl >= 0.0:
		add.call(0, "Hedefe son 15 km'de ortalama %d m yükseklikte girdin%s" % [agl, " (radar altı)" if agl < 150.0 else ""])
	# hasar / ağır yük
	if r.has("damage_taken") and not rehearsal:
		possible += 15.0
		var dmg := float(r["damage_taken"])
		var tw := float(e.get("tw", 1.0))
		if dmg < 0.05:
			score += 15.0
		elif dmg < 0.25:
			score += 8.0
			add.call(0, "Uçak %%%d hasarla döndü" % (dmg * 100.0))
		else:
			add.call(-1, ("Ağır yük yüzünden yavaştın (itki/ağırlık %.2f): avcılar yetişti, %%%d hasar" % [tw, dmg * 100.0]) if tw < 0.6 and float(e.get("payload_kg", 0.0)) > 1000.0 else "Uçak ağır hasar aldı (%%%d)" % (dmg * 100.0))
			note.call("damage", 0.15 if tw < 0.6 else 0.3)
	if bool(r.get("lost", false)) and not rehearsal:
		add.call(-1, "Uçak kaybedildi")
		note.call("damage", 0.0)
	# G / stall
	var g := float(r.get("max_g", 0.0))
	if g >= 7.5:
		add.call(0, "En yüksek %.1f G: gövde sınırına yakın uçtun" % g)
	if float(r.get("stall_time", 0.0)) > 3.0:
		add.call(-1, "Kanatlar %d sn stall'da kaldı: kanat alanı / kaldırma merkezi" % float(r["stall_time"]))
		note.call("stall", 0.35)
	# vuruşlar
	var kills := int(r.get("kills", 0)) + int(r.get("targets_destroyed", 0))
	if kills > 0:
		add.call(1, "%d hedef vuruldu" % kills)
	var notes: Array = r.get("notes", []) if r.get("notes", []) is Array else []
	for n: Variant in notes:
		add.call(0, String(n))
	if lines.is_empty():
		add.call(0, "Değerlendirecek uçuş verisi az (kısa uçuş)")
	var pct_score := score / possible * 100.0 if possible > 0.0 else (70.0 if String(wst["key"]) == "" else 45.0)
	var grade := "S" if pct_score >= 88.0 else ("A" if pct_score >= 72.0 else ("B" if pct_score >= 52.0 else "C"))
	return {"lines": lines, "grade": grade, "score": pct_score, "suggestion": _suggest(String(wst["key"]), e, card)}


static func _why_slow(e: Dictionary) -> String:
	if e.is_empty():
		return "daha hızlı bir tasarım gerekli"
	if float(e.get("intake_pct", 1.0)) < 0.99:
		return "hava alığı yetersizdi, motor tam güç veremedi"
	if float(e.get("tw", 1.0)) < 0.5:
		return "itki/ağırlık %.2f: ağır uçak, güçlü motor ya da hafif yük" % float(e["tw"])
	return "azami hız %d km/sa yetmedi" % (float(e.get("v0", 0.0)) * 3.6)


static func _suggest(worst: String, e: Dictionary, card: Dictionary) -> String:
	match worst:
		"fuel":
			return "ek yakıt tankı ya da daha verimli (art yakıcısız/pervaneli) motor; gerekirse ikmal probu."
		"slow":
			return "daha güçlü motor ya da art yakıcı, daha az sürükleme (az pilon, ince gövde)."
		"climb", "intake":
			return "hava alığını büyüt ve itki/ağırlığı 1'in üstüne çıkar."
		"detected":
			return "chaff kovanı ve ECM podu ekle; radar avcısı füze tehdidi baştan susturur."
		"high":
			return "girişte alçak uç (arazi takibi Shift+U); hızlı ve alçak tasarım radarı yener."
		"damage":
			return "yükü hafiflet ya da kendini koruyacak hava-hava füzesi ve flare taşı."
		"stall":
			return "kanat alanını artır ya da kaldırma merkezini biraz geriye al."
		"card":
			return "kalkıştan önce kontrol listesindeki ✗ satırlarını kapat (yük, menzil, pist…)."
		"fail":
			return "kontrol listesindeki ✗ satırlarını kapat, önce GÖREV PROVASI'nda dene."
	if e.is_empty():
		return "hangarda görev kartını kontrol listesiyle karşıla."
	return "bu tasarım %s görevine uygun — aynı tasarımı seri olarak kullanabilirsin." % String(card.get("title", "bu"))


## --debriefdemo (hangarda): örnek kart + örnek sonuçla uçuş raporu (ağaç duraklatılmaz, ekran görüntüsü için).
static func demo(h: Node, preview: Vessel) -> void:
	var card := MissionCheck.sample_card()
	if is_instance_valid(preview) and not preview.parts.is_empty():
		var e := MissionCheck.estimate(preview)
		card["design"] = e.duplicate(true)
	card["check"] = MissionCheck.evaluate(card, card.get("design", {}))
	Game.mission_card = card
	var dsg: Dictionary = card.get("design", {})
	Game.last_result = {"card": card, "success": true, "fuel_left_kg": float(dsg.get("fuel", 4000.0)) * 0.22, "max_g": 6.4,
		"time_s": 1260.0, "mission_time_s": 610.0, "time_to_target_s": 250.0, "kills": 1, "targets_destroyed": 2,
		"damage_taken": 0.12, "detected_by": ["SAM 1", "SAM 1", "SAM 2"], "ingress_agl_avg": 420.0,
		"notes": ["Köprünün iki ayağı da yıkıldı"]}
	var info := PackedStringArray(["Kartal-1  ·  Astğm. Test Pilot", "Uçuş süresi 21:00", "Görev: %s — BAŞARILI" % card["title"], "Görev ödülü: +9000 ₺"])
	FlightReport.open(h, "UÇUŞ RAPORU", info, true)
	await h.get_tree().process_frame
	h.get_tree().paused = false
