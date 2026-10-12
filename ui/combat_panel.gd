class_name CombatPanel
extends Control
## Ekranın solundaki SAVAŞ PANELİ (sağdaki kumanda panelinin eşi, aynı görünüm).
##   • MASTER ARM (kapaklı) ve FLARE düğmesi (kalan fişek)
##   • Silah kartları: TOP / FÜZE / BOMBA — tıkla ya da V; kalan cephane çubuğu, seçili olan yanar
##   • Durum satırı: emniyet / arayıcı / KİLİT + mesafe / CCIP
##   • Radar ekranı (burun yukarı, koni, temaslar, bize gelen füzeler)
##   • YAPI şeması: uçağın üstten görünüşü, her parça yük ve hasarına göre yeşil → sarı → kırmızı;
##     G göstergesi ve "yapı limiti ~X G" (bu yükte ilk kopacak parçaya göre tahmin)
##   • Tuş ipuçları. Kenardaki sekme ya da M tuşu ile katlanır.

const W := 280.0
const H := 544.0
const PANEL_BG := Color(0.13, 0.15, 0.15, 0.94)
const PANEL_EDGE := Color(0.32, 0.35, 0.35)
const ENGRAVE := Color(0.86, 0.88, 0.84)
const DIM := Color(0.55, 0.6, 0.6)
const LIT_GREEN := Color(0.35, 1.0, 0.5)
const LIT_AMBER := Color(1.0, 0.72, 0.2)
const RED := Color(1.0, 0.28, 0.22)
const GUARD_RED := Color(0.78, 0.1, 0.08)
const ENEMY := Color(1.0, 0.35, 0.3)
const FRIEND := Color(0.4, 0.8, 1.0)
const WEAPON_NAMES := ["TOP", "FÜZE", "BOMBA", "KARGO"]

var vessel: Vessel
var camera: FlightCamera
var combat: CombatHud
var collapsed := false

var _font := SystemFont.new()
var _bold := SystemFont.new()
var _slide := 0.0
var _hover := ""
var _cover_open := false
var _cover_t := 0.0
var _press := {}
var _sweep := 0.0
var _g_limit := 0.0
var _last_vessel: Vessel


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	mouse_filter = Control.MOUSE_FILTER_STOP


func _visible_now() -> bool:
	return is_instance_valid(vessel) and vessel.is_inside_tree() and is_instance_valid(camera) \
		and not camera.is_eva() and vessel.has_pilot() and Hud.panels_open


func _process(delta: float) -> void:
	visible = _visible_now()
	if not visible:
		return
	UiTheme.fade_panel(self, delta)
	# silahsız (sivil) uçakta panel katlı başlar
	if vessel != _last_vessel:
		_last_vessel = vessel
		collapsed = vessel.available_weapons().is_empty() and vessel.flares_left() == 0
	_slide = move_toward(_slide, 1.0 if collapsed else 0.0, delta * 5.0)
	var vp := get_viewport_rect().size
	size = Vector2(W + 26, H)
	# sol üstte, başlık satırının altında (sol alt eylem panelinin)
	position = Vector2(-W * _slide, 64.0)
	_sweep += delta
	if _cover_open:
		_cover_t += delta
		if _cover_t > 4.0 and not vessel.master_arm:
			_cover_open = false
	for k in _press.keys():
		_press[k] = move_toward(_press[k], 0.0, delta * 6.0)
	# yapı limiti tahmini: yük ~ G ile orantılı → limit = G / yük oranı (yumuşatılmış)
	if vessel.max_stress > 0.05:
		var lim := maxf(absf(vessel.g_force), 1.0) / vessel.max_stress
		_g_limit = lim if _g_limit <= 0.0 else lerpf(_g_limit, lim, delta * 2.0)
	queue_redraw()


# ------------------------------------------------------------------ düzen

func _tab_rect() -> Rect2:
	return Rect2(W, 0, 26, 110)


func _arm_rect() -> Rect2:
	return Rect2(14, 54, 122, 62)


func _flare_rect() -> Rect2:
	return Rect2(144, 54, 122, 62)


func _weapon_rect(kind: int) -> Rect2:
	return Rect2(14 + kind * 64, 126, 60, 72)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _hit(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _radar_click(event.position):
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(event.position)
		match h:
			"tab":
				collapsed = not collapsed
				Sfx.play_ui("switch_3.ogg", -10.0, 0.8)
			"arm":
				if not _cover_open:
					_cover_open = true
					_cover_t = 0.0
					Sfx.play_ui("switch_4.ogg", -8.0, 0.7)
				else:
					vessel.master_arm = not vessel.master_arm
					_cover_t = 0.0
					_press["arm"] = 1.0
					Sfx.click()
			"flare":
				_press["flare"] = 1.0
				if not vessel.drop_flares():
					Sfx.play_ui("switch_2.ogg", -10.0, 0.6)
			"w0", "w1", "w2", "w3":
				var kind := int(h.substr(1))
				if kind in vessel.available_weapons():
					vessel.selected_weapon = kind
					_press[h] = 1.0
					Sfx.click()
		accept_event()


## Radar ekranında temasa tık: hedef seç (füze arayıcısı önceliği).
func _radar_click(p: Vector2) -> bool:
	var r := Rect2(14, 242, W - 28, 128)
	var radar := vessel.radar()
	if collapsed or not r.has_point(p) or radar == null or not vessel.has_power() or combat == null:
		return false
	var origin := Vector2(r.position.x + r.size.x * 0.5, r.end.y - 8)
	var R := r.size.y - 26.0
	var fr := Planet.local_basis(vessel.global_position)
	var hdg := deg_to_rad(vessel.heading_deg())
	var best: Vessel = null
	var best_d := 16.0
	for t in radar.contacts:
		if is_instance_valid(t) and t.team != vessel.team:
			var d := p.distance_to(_scope_point(t.com_global(), origin, R, radar.range_m, fr, hdg))
			if d < best_d:
				best_d = d
				best = t
	if best:
		combat.designate(best)
	return true


func _hit(p: Vector2) -> String:
	if _tab_rect().has_point(p):
		return "tab"
	if _arm_rect().has_point(p):
		return "arm"
	if _flare_rect().has_point(p):
		return "flare"
	for k in 4:
		if _weapon_rect(k).has_point(p):
			return "w%d" % k
	return ""


# ------------------------------------------------------------------ çizim

func _draw() -> void:
	if not _visible_now():
		return
	var tab := _tab_rect()
	draw_style_box(_box(PANEL_BG, 6), tab)
	draw_string(_bold, tab.position + Vector2(8, 62), "◀" if not collapsed else "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ENGRAVE)
	draw_style_box(_box(PANEL_BG, 8, PANEL_EDGE), Rect2(0, 0, W, H))
	for c in [Vector2(10, 10), Vector2(W - 10, 10), Vector2(10, H - 10), Vector2(W - 10, H - 10)]:
		draw_circle(c, 3.5, Color(0.42, 0.44, 0.44))
		draw_line(c - Vector2(2.5, 0), c + Vector2(2.5, 0), Color(0.2, 0.22, 0.22), 1.0)
	_text_c(Vector2(W * 0.5, 34), "SAVAŞ PANELİ", 15, ENGRAVE, _bold)
	draw_line(Vector2(14, 44), Vector2(W - 14, 44), Color(1, 1, 1, 0.12), 1.0)
	var powered := vessel.has_power()
	_draw_arm(powered)
	_draw_flare(powered)
	for k in 4:
		_draw_weapon(k, powered)
	_draw_status(Rect2(14, 206, W - 28, 30), powered)
	_draw_radar(Rect2(14, 242, W - 28, 128), powered)
	_draw_structure(Rect2(14, 378, W - 28, 140))
	_text_c(Vector2(W * 0.5, H - 14), "Space ateş  ·  V silah  ·  O flare  ·  F4 hedef", 11, DIM, _font)


func _draw_arm(powered: bool) -> void:
	var r := _arm_rect()
	var hov := _hover == "arm"
	draw_style_box(_box(Color(0, 0, 0, 0.25 if not hov else 0.45), 6, Color(1, 1, 1, 0.08 if not hov else 0.25)), r)
	var c := r.position + Vector2(r.size.x * 0.5, 24)
	var on := vessel.master_arm
	draw_circle(c, 11.0, Color(0.08, 0.09, 0.09))
	draw_arc(c, 11.0, 0, TAU, 24, Color(0.45, 0.47, 0.47), 1.5)
	var tip := c + Vector2(0, -15 if on else 15)
	draw_line(c, tip, Color(0.82, 0.83, 0.83), 4.0)
	draw_circle(tip, 4.5, Color(0.92, 0.92, 0.9))
	var cover := Rect2(c - Vector2(18, 20), Vector2(36, 40))
	if _cover_open:
		cover = Rect2(c - Vector2(18, 38), Vector2(36, 14))
	draw_rect(cover, Color(GUARD_RED, 0.9))
	draw_rect(cover, Color(1, 0.5, 0.45, 0.6), false, 1.5)
	# ARM lambası
	var lamp := Rect2(r.end - Vector2(30, 52), Vector2(20, 12))
	draw_rect(lamp, RED if on and powered else Color(0.2, 0.08, 0.07))
	_text_c(r.position + Vector2(r.size.x * 0.5, r.size.y - 6), "MASTER ARM", 11, ENGRAVE, _bold)


func _draw_flare(powered: bool) -> void:
	var r := _flare_rect()
	var hov := _hover == "flare"
	var n := vessel.flares_left()
	draw_style_box(_box(Color(0, 0, 0, 0.25 if not hov else 0.45), 6, Color(1, 1, 1, 0.08 if not hov else 0.25)), r)
	var sq := Rect2(r.position + Vector2(r.size.x * 0.5 - 30, 8), Vector2(60, 30)).grow(-_press.get("flare", 0.0) * 2.0)
	draw_style_box(_box(Color(0.06, 0.07, 0.07), 4, Color(0.4, 0.42, 0.42)), sq)
	var ok := n > 0 and powered
	var flash := _press.get("flare", 0.0) as float
	draw_rect(sq.grow(-6), Color(LIT_AMBER, 0.25 + flash * 0.7) if ok else Color(0.12, 0.12, 0.1))
	_text_c(sq.get_center() + Vector2(0, 6), "%d" % n, 16, LIT_AMBER if ok else DIM, _bold)
	_text_c(r.position + Vector2(r.size.x * 0.5, r.size.y - 6), "FLARE  (O)", 11, ENGRAVE, _bold)


func _draw_weapon(kind: int, powered: bool) -> void:
	var r := _weapon_rect(kind)
	var have := kind in vessel.available_weapons()
	var sel := have and vessel.selected_weapon == kind
	var hov := _hover == "w%d" % kind and have
	var edge := LIT_GREEN if sel else Color(1, 1, 1, 0.08 if not hov else 0.25)
	draw_style_box(_box(Color(0.05, 0.12, 0.08, 0.9) if sel else Color(0, 0, 0, 0.25 if not hov else 0.45), 6, edge), r.grow(-_press.get("w%d" % kind, 0.0) * 2.0))
	var col := (LIT_GREEN if sel else ENGRAVE) if have else Color(0.35, 0.38, 0.38)
	_text_c(r.position + Vector2(r.size.x * 0.5, 22), WEAPON_NAMES[kind], 12, col, _bold)
	var count := 0
	var full := 1
	match kind:
		Vessel.WEAPON_GUN:
			count = vessel.gun_ammo()
			full = 0
			for m in vessel.modules:
				if m is GunModule:
					full += 500
		Vessel.WEAPON_MISSILE:
			count = vessel.missiles_left()
			for m in vessel.modules:
				if m is MissileModule:
					full += 1
			full = maxi(full - 1, 1)
		Vessel.WEAPON_BOMB:
			count = vessel.bombs_left()
			for m in vessel.modules:
				if m is BombModule:
					full += 1
			full = maxi(full - 1, 1)
		Vessel.WEAPON_CARGO:
			count = vessel.cargo_left()
			full = 0
			for m in vessel.modules:
				if m is CargoModule:
					full += 4
	if not have:
		_text_c(r.position + Vector2(r.size.x * 0.5, 46), "yok", 12, Color(0.35, 0.38, 0.38))
		return
	_text_c(r.position + Vector2(r.size.x * 0.5, 46), str(count), 18, Color.WHITE if count > 0 else RED, _bold)
	var bar := Rect2(r.position + Vector2(10, r.size.y - 14), Vector2(r.size.x - 20, 5))
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var f := clampf(float(count) / float(maxi(full, 1)), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), LIT_GREEN if f > 0.3 else LIT_AMBER)


func _draw_status(r: Rect2, powered: bool) -> void:
	draw_style_box(_box(Color(0.02, 0.03, 0.03), 5, Color(0.3, 0.33, 0.33)), r)
	var text := ""
	var col := DIM
	if not powered:
		text = "GÜÇ YOK — BATARYA"
		col = Color(0.6, 0.35, 0.3)
	elif not vessel.master_arm and vessel.selected_weapon != Vessel.WEAPON_CARGO:
		text = "EMNİYETTE — MASTER ARM aç"
		col = LIT_AMBER
	elif vessel.available_weapons().is_empty():
		text = "SİLAH YOK"
	else:
		match vessel.selected_weapon:
			Vessel.WEAPON_GUN:
				text = "TOP HAZIR — Space ile ateş"
				col = LIT_GREEN
			Vessel.WEAPON_MISSILE:
				var t: Vessel = combat.locked_target() if combat else null
				if vessel.missiles_left() == 0:
					text = "FÜZE KALMADI"
					col = RED
				elif t:
					text = "KİLİT  %s  %.1f km" % [t.craft_name, t.com_global().distance_to(vessel.com_global()) / 1000.0]
					col = Color(1, 0.95, 0.4)
				else:
					text = "ARAYICI — burnu hedefe çevir"
					col = LIT_GREEN
			Vessel.WEAPON_BOMB:
				text = "BOMBA — CCIP'e göre bırak" if vessel.bombs_left() > 0 else "BOMBA KALMADI"
				col = LIT_GREEN if vessel.bombs_left() > 0 else RED
			Vessel.WEAPON_CARGO:
				text = "KARGO — işarete göre bırak (%d)" % vessel.cargo_left()
				col = LIT_GREEN if vessel.cargo_left() > 0 else RED
	if vessel.incoming_missile() and fmod(_sweep, 0.5) < 0.3:
		text = "!! FÜZE GELİYOR — FLARE AT (O) !!"
		col = RED
	_text_c(r.get_center() + Vector2(0, 5), text, 13, col, _bold)


func _draw_radar(r: Rect2, powered: bool) -> void:
	draw_style_box(_box(Color(0.02, 0.05, 0.04), 6, Color(0.3, 0.33, 0.33)), r)
	var radar := vessel.radar()
	var green := Color(0.4, 1.0, 0.55)
	draw_string(_bold, r.position + Vector2(8, 16), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	if radar == null:
		_text_c(r.get_center() + Vector2(0, 5), "RADAR PARÇASI YOK", 13, DIM, _bold)
		return
	draw_string(_bold, r.position + Vector2(r.size.x - 50, 16), "%d km" % (radar.range_m / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	if not powered:
		_text_c(r.get_center() + Vector2(0, 5), "GÜÇ YOK", 13, Color(0.6, 0.35, 0.3), _bold)
		return
	var origin := Vector2(r.position.x + r.size.x * 0.5, r.end.y - 8)
	var R := r.size.y - 26.0
	var cone := radar.cone
	for k in [0.33, 0.66, 1.0]:
		draw_arc(origin, R * k, -PI * 0.5 - cone, -PI * 0.5 + cone, 24, Color(green, 0.22), 1.0, true)
	for a in [-cone, 0.0, cone]:
		draw_line(origin, origin + Vector2(sin(a), -cos(a)) * R, Color(green, 0.16), 1.0)
	var sw := sin(_sweep * 1.6) * cone
	draw_line(origin, origin + Vector2(sin(sw), -cos(sw)) * R, Color(green, 0.45), 1.5, true)
	var fr := Planet.local_basis(vessel.global_position)
	var hdg := deg_to_rad(vessel.heading_deg())
	var locked: Vessel = combat.locked_target() if combat else null
	for t in radar.contacts:
		if not is_instance_valid(t):
			continue
		var p := _scope_point(t.com_global(), origin, R, radar.range_m, fr, hdg)
		var col := FRIEND if t.team == vessel.team else (Color(0.72, 0.75, 0.78) if t.team == "sivil" else ENEMY)
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
		draw_string(_font, p + Vector2(7, 4), "%+.1f" % ((t.altitude() - vessel.altitude()) / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		if t == locked:
			draw_arc(p, 8.0, 0, TAU, 16, Color(1, 0.95, 0.4), 1.5)
		if t == vessel.designated:
			draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(0.45, 0.85, 1.0), false, 1.5)
	for mi in Missile.active:
		if mi.victim == vessel:
			var p := _scope_point(mi.global_position, origin, R, radar.range_m, fr, hdg)
			draw_line(p - Vector2(5, 5), p + Vector2(5, 5), ENEMY, 2.0)
			draw_line(p - Vector2(5, -5), p + Vector2(5, -5), ENEMY, 2.0)
	draw_circle(origin, 3.0, green)


func _scope_point(world: Vector3, origin: Vector2, R: float, rng: float, fr: Basis, hdg: float) -> Vector2:
	var to := world - vessel.com_global()
	var lx := to.dot(fr.x)
	var ln := -to.dot(fr.z)
	var b := wrapf(atan2(lx, ln) - hdg, -PI, PI)
	var d := Vector2(lx, ln).length()
	return origin + Vector2(sin(b), -cos(b)) * R * clampf(d / rng, 0.0, 1.0)


## Üstten uçak şeması: parça rengi = max(yük oranı, hasar). G ve yapı limiti.
func _draw_structure(r: Rect2) -> void:
	draw_style_box(_box(Color(0.02, 0.03, 0.03), 6, Color(0.3, 0.33, 0.33)), r)
	draw_string(_bold, r.position + Vector2(8, 16), "YAPI", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	# sağda G ve limit
	var g := vessel.g_force
	var stress := clampf(vessel.max_stress, 0.0, 1.5)
	var gcol := _load_color(stress)
	var gx := r.end.x - 92
	draw_string(_bold, Vector2(gx, r.position.y + 40), "G %+.1f" % g, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, gcol)
	draw_string(_font, Vector2(gx, r.position.y + 62), "yük %d%%" % (stress * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gcol)
	var lim_txt := "limit ~%d G" % _g_limit if _g_limit > 0.0 else "limit —"
	draw_string(_font, Vector2(gx, r.position.y + 80), lim_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	# dikey yük çubuğu
	var bar := Rect2(r.end.x - 18, r.position.y + 22, 8, r.size.y - 34)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var fill := clampf(stress, 0.0, 1.0)
	draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * fill, bar.size.x, bar.size.y * fill), gcol)
	for mark in [0.7, 0.9]:
		var y: float = bar.end.y - bar.size.y * mark
		draw_line(Vector2(bar.position.x - 3, y), Vector2(bar.end.x + 3, y), Color(1, 1, 1, 0.35), 1.0)
	# en zayıf parça
	var weakest: Part = null
	for p in vessel.parts:
		if weakest == null or p.stress > weakest.stress:
			weakest = p
	if weakest and weakest.stress > 0.3:
		draw_string(_font, Vector2(gx, r.position.y + 100), "en çok yüklü:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
		draw_string(_font, Vector2(gx, r.position.y + 114), _short(weakest.title), HORIZONTAL_ALIGNMENT_LEFT, 84, 10, _load_color(weakest.stress))
	# şema alanı
	var area := Rect2(r.position + Vector2(8, 22), Vector2(r.size.x - 116, r.size.y - 30))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var rects: Array = []
	for p in vessel.parts:
		var ext := (p.basis * p.size).abs() * 0.5
		var a := Vector2(p.position.x - ext.x, p.position.z - ext.z)
		var b := Vector2(p.position.x + ext.x, p.position.z + ext.z)
		lo = lo.min(a)
		hi = hi.max(b)
		rects.append([p, a, b, ext.y])
	if rects.is_empty():
		return
	var span := hi - lo
	var k := minf(area.size.x / maxf(span.x, 0.1), area.size.y / maxf(span.y, 0.1))
	var off := area.position + (area.size - span * k) * 0.5
	# önce büyük ve alçak parçalar (gövde üstte görünsün)
	rects.sort_custom(func(x: Array, y: Array) -> bool: return (x[2] - x[1]).length() > (y[2] - y[1]).length())
	for it in rects:
		var p: Part = it[0]
		var a: Vector2 = off + (it[1] - lo) * k
		var b: Vector2 = off + (it[2] - lo) * k
		var load := maxf(p.stress, 1.0 - p.health_ratio())
		var col := _load_color(load)
		var rr := Rect2(a, b - a)
		draw_rect(rr, Color(col, 0.55))
		draw_rect(rr, Color(col, 0.95), false, 1.0)


func _load_color(x: float) -> Color:
	if x < 0.7:
		return LIT_GREEN.lerp(LIT_AMBER, x / 0.7)
	return LIT_AMBER.lerp(RED, clampf((x - 0.7) / 0.3, 0.0, 1.0))


func _short(t: String) -> String:
	return t if t.length() <= 16 else t.substr(0, 15) + "…"


func _box(bg: Color, radius: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	return s


func _text_c(pos: Vector2, text: String, font_size: int, col: Color, font: Font = null) -> void:
	var f := font if font else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(f, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
