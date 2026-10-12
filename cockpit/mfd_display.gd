class_name MfdDisplay
extends Control
## Kokpit çok fonksiyonlu ekranı (SubViewport içinde çizilir). Kendi kendine yeniden çizmez:
## CockpitModule kokpit kamerası etkinken ~12 Hz'de refresh() çağırır (performans).
## Sayfalar: PFD (yapay ufuk), MOTOR (N2/EGT/yakıt/hidrolik), RADAR (temaslar), HSI (pusula
## gülü, eve yön, harita), SİLAH (askı istasyonları). Alt kenardaki OSB yazıları ekranın
## çerçevesindeki tuşlarla hizalı; ekrana tıklamak sonraki sayfaya geçer.

enum Page { PFD, ENGINE, RADAR, HSI, STORES }
const PAGE_NAMES := ["PFD", "MOTOR", "RADAR", "HSI", "SİLAH"]

const GREEN := Color(0.35, 1.0, 0.55)
const AMBER := Color(1.0, 0.7, 0.2)
const RED := Color(1.0, 0.25, 0.2)
const CYAN := Color(0.35, 0.85, 1.0)
const DIM := Color(0.45, 0.55, 0.5)
const SKY := Color(0.15, 0.4, 0.75)
const GROUND := Color(0.45, 0.3, 0.15)
const BG := Color(0.01, 0.02, 0.02)

var page := Page.PFD
var pages: Array[int] = [Page.PFD]   ## tıklayınca dönülen sayfalar
var vessel: Vessel
var _font := SystemFont.new()


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Consolas", "Arial"])


func refresh() -> void:
	queue_redraw()


func next_page() -> void:
	if pages.size() > 1:
		page = pages[(pages.find(page) + 1) % pages.size()]
		queue_redraw()


func page_name() -> String:
	return PAGE_NAMES[page]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if not is_instance_valid(vessel) or not vessel.has_power():
		return   # güç yok: ekran karanlık
	match page:
		Page.PFD: _pfd()
		Page.ENGINE: _engine()
		Page.RADAR: _radar()
		Page.HSI: _hsi()
		Page.STORES: _stores()
	_osb()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.35, 0.35), false, 4.0)


## Alt kenar: çerçevedeki 5 tuşa denk gelen sayfa adları (seçili kutulu).
func _osb() -> void:
	for i in mini(pages.size(), 5):
		var cx := size.x * (0.1 + i * 0.2)
		var txt: String = PAGE_NAMES[pages[i]]
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var p := Vector2(cx - w * 0.5, size.y - 6)
		if pages[i] == page:
			draw_rect(Rect2(p + Vector2(-3, -12), Vector2(w + 6, 15)), GREEN, false, 1.5)
		_t(p, txt, 11, GREEN if pages[i] == page else DIM)


# ------------------------------------------------------------------ PFD

func _pfd() -> void:
	var c := size * 0.5 + Vector2(0, -6)
	var r := size.x * 0.34
	var roll := deg_to_rad(vessel.roll_deg())
	var pitch_px := vessel.pitch_deg() * 3.0
	# ufuk: dönen gök/yer
	draw_set_transform(c, -roll, Vector2.ONE)
	draw_rect(Rect2(-r * 2, -r * 2 + pitch_px, r * 4, r * 2), SKY)
	draw_rect(Rect2(-r * 2, pitch_px, r * 4, r * 2), GROUND)
	draw_line(Vector2(-r * 2, pitch_px), Vector2(r * 2, pitch_px), Color.WHITE, 2.0)
	for p in [-20, -10, 10, 20]:
		var y: float = pitch_px - p * 3.0
		draw_line(Vector2(-20, y), Vector2(20, y), Color.WHITE, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# maske
	draw_rect(Rect2(0, 0, size.x, c.y - r), BG)
	draw_rect(Rect2(0, c.y + r, size.x, size.y), BG)
	draw_rect(Rect2(0, 0, c.x - r, size.y), BG)
	draw_rect(Rect2(c.x + r, 0, size.x, size.y), BG)
	# yatış ölçeği
	for a: int in [-45, -30, -20, -10, 0, 10, 20, 30, 45]:
		var ang := deg_to_rad(a) - PI * 0.5
		var l := 10.0 if a % 30 == 0 else 6.0
		draw_line(c + Vector2(cos(ang), sin(ang)) * (r + 2), c + Vector2(cos(ang), sin(ang)) * (r + 2 + l), Color.WHITE, 1.5)
	var ra := -roll - PI * 0.5
	draw_colored_polygon(PackedVector2Array([c + Vector2(cos(ra), sin(ra)) * (r - 1),
		c + Vector2(cos(ra + 0.06), sin(ra + 0.06)) * (r - 11), c + Vector2(cos(ra - 0.06), sin(ra - 0.06)) * (r - 11)]), AMBER)
	# uçak sembolü
	draw_line(c + Vector2(-40, 0), c + Vector2(-12, 0), AMBER, 4.0)
	draw_line(c + Vector2(12, 0), c + Vector2(40, 0), AMBER, 4.0)
	draw_circle(c, 4.0, AMBER)
	_box_text(Vector2(6, 20), "%d" % (vessel.airspeed() * 3.6), 18)
	_t(Vector2(8, 52), "km/sa", 11, GREEN)
	_box_text(Vector2(size.x - 66, 20), "%d" % vessel.altitude(), 18)
	_t(Vector2(size.x - 64, 52), "m", 11, GREEN)
	_t(Vector2(size.x * 0.5 - 14, 18), "%03d" % roundi(vessel.heading_deg()), 15, GREEN)
	_t(Vector2(8, size.y - 40), "G %.1f" % vessel.g_force, 14, GREEN)
	_t(Vector2(8, size.y - 24), "α %.0f°" % vessel.aoa_deg(), 14, GREEN)
	_t(Vector2(size.x - 78, size.y - 40), "VS %+d" % vessel.vertical_speed(), 14, GREEN)
	_t(Vector2(size.x - 78, size.y - 24), "M %.2f" % vessel.mach(), 14, GREEN)


# ------------------------------------------------------------------ MOTOR

func _engine() -> void:
	var eng: EngineModule = vessel.engines()[0] if not vessel.engines().is_empty() else null
	var state_txt := "KAPALI"
	var state_col := AMBER
	if eng and eng.state == EngineModule.State.CRANKING:
		state_txt = "MARŞ"
	elif eng and eng.flameout:
		state_txt = "SÖNDÜ"
		state_col = RED
	elif eng and eng.is_running():
		state_txt = "ÇALIŞIYOR"
		state_col = GREEN
	_t(Vector2(10, 20), "MOTOR", 14, DIM)
	_t(Vector2(66, 20), state_txt, 14, state_col)
	if vessel.jfs_on:
		_t(Vector2(size.x - 52, 20), "JFS", 14, AMBER)
	var n2 := eng.n2 if eng else 0.0
	var ab := eng.afterburner if eng else 0.0
	var egt := (180.0 + n2 * 560.0 + ab * 140.0) if eng and eng.is_running() else 20.0 + n2 * 300.0
	_arc_gauge(Vector2(64, 78), 40, n2 / 1.05, "N2", "%d%%" % (n2 * 100.0), n2 > 1.02)
	_arc_gauge(Vector2(size.x - 64, 78), 40, egt / 950.0, "EGT", "%d°" % egt, egt > 850.0)
	if ab > 0.05:
		_t(Vector2(size.x * 0.5 - 12, 84), "AB", 16, AMBER)
	var thrust := vessel.total_thrust() / 1000.0
	var fuel_ratio := vessel.fuel_amount() / maxf(vessel.fuel_capacity(), 1.0)
	var ff := (eng.fuel_rate * eng.throttle * (1.0 + ab * 2.0) * 3600.0) if eng and eng.is_running() else 0.0
	_bar(Vector2(10, 138), "GAZ", vessel.ctrl_throttle, "%d%%" % (vessel.ctrl_throttle * 100))
	_bar(Vector2(10, 160), "İTKİ", thrust / 90.0, "%d kN" % thrust)
	_bar(Vector2(10, 182), "YAKIT", fuel_ratio, "%d kg" % vessel.fuel_amount(), AMBER if fuel_ratio < 0.15 else GREEN)
	_bar(Vector2(10, 204), "HİD", vessel.hydraulics, "%d%%" % (vessel.hydraulics * 100.0), AMBER if vessel.hydraulics < 0.5 else GREEN)
	_t(Vector2(10, 228), "FF %d kg/sa" % ff, 12, GREEN)
	_t(Vector2(110, 228), "TAKIM " + ("AŞ" if vessel.gear_down else "YK"), 12, GREEN if vessel.gear_down else DIM)
	_t(Vector2(186, 228), "FREN" if vessel.parking_brake else "", 12, AMBER)


func _arc_gauge(c: Vector2, r: float, value: float, label: String, text: String, warn: bool) -> void:
	var a0 := deg_to_rad(150.0)
	var a1 := deg_to_rad(390.0)
	draw_arc(c, r, a0, a1, 32, Color(1, 1, 1, 0.25), 3.0)
	draw_arc(c, r, deg_to_rad(360.0), a1, 8, RED, 3.0)
	var v := clampf(value, 0.0, 1.0)
	var col := RED if warn else GREEN
	if v > 0.001:
		draw_arc(c, r - 5, a0, lerpf(a0, a1, v), 24, col, 6.0)
	var na := lerpf(a0, a1, v)
	draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 2), Color.WHITE, 2.0)
	_t(c + Vector2(-12, 26), label, 12, DIM)
	_t(c + Vector2(-16, 8), text, 14, col)


func _bar(pos: Vector2, label: String, value: float, text: String, col := GREEN) -> void:
	_t(pos + Vector2(0, 12), label, 12, Color(0.7, 0.8, 0.75))
	var bar := Rect2(pos + Vector2(48, 2), Vector2(120, 11))
	draw_rect(bar, Color(1, 1, 1, 0.1))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(value, 0.0, 1.0), bar.size.y)), col)
	_t(pos + Vector2(174, 12), text, 12, col)


# ------------------------------------------------------------------ RADAR

func _radar() -> void:
	var radar := vessel.radar()
	var o := Vector2(size.x * 0.5, size.y - 30)
	var R := size.y - 52.0
	_t(Vector2(8, 18), "RDR", 14, GREEN)
	if radar == null:
		_t(Vector2(size.x * 0.5 - 40, size.y * 0.5), "RADAR YOK", 16, DIM)
		return
	var on := vessel.radar_on
	var cone := radar.cone
	var rng := radar.range_m
	_t(Vector2(48, 18), "YAYIN" if on else "BEKLE", 14, GREEN if on else AMBER)
	_t(Vector2(size.x - 64, 18), "%d km" % (rng / 1000.0), 14, GREEN)
	# sektör ve menzil halkaları
	var col := Color(GREEN, 0.35)
	for k in [1, 2, 3]:
		draw_arc(o, R * k / 3.0, -PI * 0.5 - cone, -PI * 0.5 + cone, 24, col, 1.0)
	for s: float in [-1.0, 0.0, 1.0]:
		var a := -PI * 0.5 + cone * s
		draw_line(o, o + Vector2(cos(a), sin(a)) * R, col, 1.0)
	if not on:
		return
	# tarama çizgisi
	var sweep := -PI * 0.5 + cone * sin(Time.get_ticks_msec() / 700.0)
	draw_line(o, o + Vector2(cos(sweep), sin(sweep)) * R, Color(GREEN, 0.8), 2.0)
	var inv := vessel.global_basis.inverse()
	var me := vessel.com_global()
	for c in radar.contacts:
		if not is_instance_valid(c):
			continue
		var l: Vector3 = inv * (c.com_global() - me)
		var d := Vector2(l.x, l.z).length()
		var bearing := atan2(l.x, -l.z)
		var p := o + Vector2(sin(bearing), -cos(bearing)) * minf(d / rng, 1.0) * R
		var hostile: bool = c.team != vessel.team
		var cc := AMBER if hostile else GREEN
		if hostile:
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), cc, false, 2.0)
		else:
			draw_circle(p, 5.0, cc, false, 2.0)
		# yön çizgisi (hedefin burnu)
		var hf: Vector3 = inv * c.forward()
		draw_line(p, p + Vector2(hf.x, hf.z).normalized() * 12.0, cc, 1.5)
		var dalt := (c.altitude() - vessel.altitude()) / 100.0
		_t(p + Vector2(7, -4), "%+d" % roundi(dalt), 10, cc)
	_t(Vector2(8, 38), "TEMAS %d" % radar.contacts.size(), 12, GREEN)
	if vessel.incoming_missile() != null and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.3:
		_t(Vector2(size.x * 0.5 - 22, 42), "FÜZE", 18, RED)


# ------------------------------------------------------------------ HSI / harita

func _hsi() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 6)
	var r := size.x * 0.36
	var hdg := deg_to_rad(vessel.heading_deg())
	var map_range := 20000.0
	# harita: yakındaki uçaklar (burun yukarı)
	var b := vessel.local_frame()
	var me := vessel.com_global()
	if vessel.get_parent():
		for n in vessel.get_parent().get_children():
			if n is Vessel and n != vessel and not n.parts.is_empty():
				var p := _map_point(c, r, b, me, n.com_global(), hdg, map_range)
				if p.x > -9000.0:
					draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), AMBER if n.team != vessel.team else CYAN)
	# pusula gülü
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.8), 1.5)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(1, 1, 1, 0.15), 1.0)
	for i in 36:
		var a := deg_to_rad(i * 10.0) - hdg - PI * 0.5
		var l := 10.0 if i % 3 == 0 else 5.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * r, c + dir * (r - l), Color.WHITE, 1.5)
		if i % 3 == 0:
			var lbl: String = {0: "K", 9: "D", 18: "G", 27: "B"}.get(i, str(i))
			var w := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_t(c + dir * (r - 20) + Vector2(-w * 0.5, 5), lbl, 12, GREEN if i % 9 == 0 else Color.WHITE)
	# eve (havaalanı) yön oku
	var home := _home_position()
	if home != Vector3.INF:
		var d := home - me
		var brg := atan2(d.dot(b.x), -d.dot(b.z))
		var a := brg - hdg - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		draw_line(c - dir * (r - 14), c + dir * (r - 14), CYAN, 2.5)
		draw_colored_polygon(PackedVector2Array([c + dir * (r - 4), c + dir * (r - 18) + dir.orthogonal() * 7,
			c + dir * (r - 18) - dir.orthogonal() * 7]), CYAN)
		_t(Vector2(8, size.y - 24), "EV %.1f km" % (d.length() / 1000.0), 12, CYAN)
		_t(Vector2(8, size.y - 40), "BRG %03d" % fposmod(rad_to_deg(brg), 360.0), 12, CYAN)
	# uçak sembolü ve gösterge çizgisi
	draw_line(c + Vector2(0, -10), c + Vector2(0, 12), AMBER, 3.0)
	draw_line(c + Vector2(-10, -2), c + Vector2(10, -2), AMBER, 3.0)
	draw_line(c + Vector2(-5, 10), c + Vector2(5, 10), AMBER, 2.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r + 1), c + Vector2(-6, -r - 9), c + Vector2(6, -r - 9)]), AMBER)
	_box_text(Vector2(size.x * 0.5 - 22, 2), "%03d" % roundi(vessel.heading_deg()), 16)
	_t(Vector2(8, 18), "YH %d" % (vessel.ground_speed() * 3.6), 12, GREEN)
	_t(Vector2(size.x - 70, 18), "20 km", 12, DIM)
	_t(Vector2(size.x - 82, size.y - 24), "RALT %d" % vessel.radar_altitude(), 12, GREEN)


func _map_point(c: Vector2, r: float, b: Basis, me: Vector3, p: Vector3, hdg: float, rng: float) -> Vector2:
	var d := p - me
	var e := d.dot(b.x) / rng
	var n := -d.dot(b.z) / rng
	var v := Vector2(e, -n).rotated(-hdg) * r
	return c + v if v.length() < r - 4 else Vector2(-9999, 0)


func _home_position() -> Vector3:
	if TerrainGen._af_c.is_empty():
		return Vector3.INF
	return TerrainGen.airfield_transform(0).origin - Vector3(FloatingOrigin.offset_x, FloatingOrigin.offset_y, FloatingOrigin.offset_z)


# ------------------------------------------------------------------ SİLAH (askılar)

func _stores() -> void:
	var c := Vector2(size.x * 0.5, 112)
	var armed := vessel.master_arm
	_t(Vector2(8, 18), "SİLAH", 14, GREEN)
	_t(Vector2(size.x - 62, 18), "ARM" if armed else "SAFE", 14, RED if armed else GREEN)
	# uçak silueti (üstten)
	var sil := PackedVector2Array([c + Vector2(0, -70), c + Vector2(8, -50), c + Vector2(9, -10), c + Vector2(100, 22),
		c + Vector2(100, 32), c + Vector2(9, 26), c + Vector2(8, 52), c + Vector2(34, 66), c + Vector2(34, 72),
		c + Vector2(-34, 72), c + Vector2(-34, 66), c + Vector2(-8, 52), c + Vector2(-9, 26), c + Vector2(-100, 32),
		c + Vector2(-100, 22), c + Vector2(-9, -10), c + Vector2(-8, -50)])
	sil.append(sil[0])
	draw_polyline(sil, Color(GREEN, 0.5), 1.5)
	# istasyonlar: parçanın yanal konumuna göre kanat üstünde
	var inv := vessel.global_transform.affine_inverse()
	var span := 1.0
	for m in vessel.weapons():
		span = maxf(span, absf((inv * (m.part.global_position)).x))
	for m in vessel.weapons():
		var lp: Vector3 = inv * m.part.global_position
		var x := c.x + lp.x / span * 92.0
		var kind := -1
		var loaded := true
		var txt := ""
		if m is GunModule:
			kind = Vessel.WEAPON_GUN
			loaded = m.ammo > 0
			txt = "TOP %d" % m.ammo
			_t(Vector2(c.x - 26, c.y - 76), txt, 11, GREEN if loaded else DIM)
			continue
		elif m is MissileModule:
			kind = m.weapon_kind()
			loaded = m.loaded
			txt = "RDR" if m.radar_guided else "IR"
		elif m is BombModule:
			kind = m.weapon_kind()
			loaded = m.loaded
			txt = "BMB"
		var sel := kind == vessel.selected_weapon
		var col := (AMBER if sel else GREEN) if loaded else DIM
		var y := c.y + 40.0 - absf(lp.x) / span * 10.0
		if loaded:
			draw_rect(Rect2(Vector2(x - 4, y - 18), Vector2(8, 26)), col)
		else:
			draw_rect(Rect2(Vector2(x - 4, y - 18), Vector2(8, 26)), col, false, 1.0)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_t(Vector2(x - w * 0.5, y + 20), txt, 10, col)
	_t(Vector2(8, size.y - 40), "SEÇİLİ: " + vessel.weapon_name(), 12, AMBER)
	_t(Vector2(8, size.y - 24), "FİŞEK %d" % vessel.flares_left(), 12, GREEN)


# ------------------------------------------------------------------ yardımcılar

func _box_text(pos: Vector2, text: String, font_size: int) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_rect(Rect2(pos, Vector2(w + 10, font_size + 8)), BG)
	draw_rect(Rect2(pos, Vector2(w + 10, font_size + 8)), GREEN, false, 1.5)
	_t(pos + Vector2(5, font_size + 2), text, font_size, GREEN)


func _t(pos: Vector2, text: String, font_size: int, col: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
