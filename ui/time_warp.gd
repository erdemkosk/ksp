class_name TimeWarp
extends Control
## KSP tarzı zaman ileri sarma (sağ üst). "." hızlandırır, "," yavaşlatır, "/" normale döner.
## Fizik ileri sarma: adım boyu sabit kalır (1/60 s), saniyedeki fizik adımı katlanır → uçuş
## modeli bozulmaz, yalnız işlemci yükü artar. x10 ve üstü yalnız sakin seyirde (yerden yüksek,
## düşük G, yakında tehdit yok); koşul bozulunca sarma kendiliğinden düşer (KSP gibi).

const LEVELS := [1, 2, 3, 4, 10, 25]
const SAFE_LEVEL := 3          ## bu indekse kadar (x4) her koşulda serbest; üstü sakin seyir ister
const BASE_TICKS := 60
const MAX_TICKS := 600         ## x25'te adım 1/24 s olur: yalnız düz seyirde kullanılır
const W := 236.0
const H := 52.0

var main: Node
var level := 0
var _hover := -1
var _blocked_msg := ""
var _msg_t := 0.0
var _font: Font
var _font_bold: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size = Vector2(W, H)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_font = f
	var fb := SystemFont.new()
	fb.font_names = f.font_names
	fb.font_weight = 700
	_font_bold = fb
	if Game.args.has("warp"):
		(func() -> void: set_level(LEVELS.find(int(Game.args["warp"])))).call_deferred()


func _exit_tree() -> void:
	_apply(1)


func _vessel() -> Vessel:
	var v: Vessel = main.vessel if main else null
	return v if is_instance_valid(v) and v.is_inside_tree() else null


## Şu an izin verilen en yüksek seviye indeksi ve (kısıtlıysa) nedeni.
func max_allowed() -> Array:
	if get_tree().paused:
		return [0, "duraklatıldı"]
	if main and main.pilot != null:
		return [0, "pilot dışarıda"]
	var v := _vessel()
	if v == null:
		return [0, "uçak yok"]
	if absf(v.g_force) > 5.5:
		return [1, "yüksek G"]
	for m: Missile in Missile.active:
		if is_instance_valid(m) and m.target == v:
			return [0, "füze geliyor!"]
	var agl := v.radar_altitude()
	var landed := v.linear_velocity.length() < 40.0 and agl < 5.0
	if landed:
		# yerde (taksi, bekleme, motor ısınması): x10'a kadar. x25'te fizik adımı 1/24 sn olur,
		# iniş takımı yayları sekip uçağı zıplatır; o yüzden yalnız park freni çekili ve dururken.
		if v.linear_velocity.length() < 0.5 and v.parking_brake:
			return [LEVELS.size() - 1, ""]
		return [4, "x25 için: park freni çek, dur"]
	if agl < 40.0:
		return [1, "yere çok yakın"]
	if agl < 600.0 or absf(v.g_force - 1.0) > 0.6:
		return [SAFE_LEVEL, "sakin seyir değil (600 m+, düz uçuş)"]
	if is_instance_valid(main.get("enemy")) and (main.enemy as Vessel).com_global().distance_to(v.com_global()) < 12000.0:
		return [SAFE_LEVEL, "yakında düşman"]
	return [LEVELS.size() - 1, ""]


func set_level(i: int) -> void:
	i = clampi(i, 0, LEVELS.size() - 1)
	var lim: Array = max_allowed()
	if i > int(lim[0]):
		_blocked_msg = "x%d için: %s" % [LEVELS[i], lim[1]]
		_msg_t = 2.5
		i = int(lim[0])
	if i == level:
		return
	level = i
	Sfx.click()
	_apply(LEVELS[level])
	_redraw_t = 0.0


func _apply(k: int) -> void:
	Engine.time_scale = float(k)
	var ticks := mini(BASE_TICKS * k, MAX_TICKS)
	Engine.physics_ticks_per_second = ticks
	Engine.max_physics_steps_per_frame = maxi(8, ceili(ticks / 30.0) + 2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("time_faster"):
		set_level(level + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_slower"):
		set_level(level - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_normal"):
		set_level(0)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _slot_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := _slot_at(event.position)
		if s >= 0:
			set_level(s)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _slot_rect(i: int) -> Rect2:
	return Rect2(78 + i * 25, 9, 22, 22)


func _slot_at(p: Vector2) -> int:
	for i in LEVELS.size():
		if _slot_rect(i).grow(2).has_point(p):
			return i
	return -1


func _process(delta: float) -> void:
	position = Vector2(get_viewport_rect().size.x - W - 18, 14)
	_msg_t = maxf(_msg_t - delta / maxf(Engine.time_scale, 1.0), 0.0)
	# koşul bozulunca sarmayı düşür
	if level > 0:
		var lim: Array = max_allowed()
		if level > int(lim[0]):
			level = int(lim[0])
			_apply(LEVELS[level])
			_blocked_msg = "Zaman normale döndü: %s" % lim[1] if level == 0 else "Sarma x%d: %s" % [LEVELS[level], lim[1]]
			_msg_t = 3.0
			Sfx.click()
	# çizim saniyede ~8 kez yeter (ya da mesaj / fare üstündeyken her kare)
	_redraw_t -= delta
	if _redraw_t <= 0.0 or _msg_t > 0.0 or _hover >= 0:
		_redraw_t = 0.12
		_lim_cache = int(max_allowed()[0])
		queue_redraw()


var _redraw_t := 0.0
var _lim_cache := 0


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.05, 0.78 * Game.settings.get("panel_alpha", 1.0))
	sb.border_color = Color(1.0, 0.78, 0.3, 0.55) if level > 0 else Color(0.5, 0.7, 0.8, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	var accent := Color(1.0, 0.8, 0.3) if level > 0 else Color(0.6, 0.75, 0.85)
	draw_string(_font_bold, Vector2(12, 19), "ZAMAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.72, 0.8))
	draw_string(_font_bold, Vector2(12, 40), "x%d" % LEVELS[level], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, accent)
	var lim := _lim_cache
	for i in LEVELS.size():
		var sr := _slot_rect(i)
		var on := i <= level
		var allowed := i <= lim
		var col: Color
		if i == 0:
			col = Color(0.45, 1.0, 0.6) if level == 0 else Color(0.45, 0.6, 0.55)
		elif on:
			col = Color(1.0, 0.8, 0.3) if i <= SAFE_LEVEL else Color(1.0, 0.5, 0.25)
		else:
			col = Color(0.4, 0.48, 0.55, 0.9 if allowed else 0.3)
		if i == _hover:
			draw_rect(sr.grow(2), Color(1, 1, 1, 0.08))
		if i == 0:
			# normal hız: ▶ tek ok
			var c := sr.get_center()
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -7), c + Vector2(7, 0), c + Vector2(-6, 7)]), col)
		else:
			var c := sr.get_center()
			var pts := PackedVector2Array([c + Vector2(-8, -8), c + Vector2(6, 0), c + Vector2(-8, 8)])
			if on:
				draw_colored_polygon(pts, col)
			else:
				pts.append(pts[0])
				draw_polyline(pts, col, 1.5, true)
		if i == SAFE_LEVEL:
			draw_line(Vector2(sr.end.x + 1.5, 8), Vector2(sr.end.x + 1.5, 32), Color(1, 1, 1, 0.15), 1.0)
	draw_string(_font, Vector2(80, 46), ",  yavaş    .  hızlı    /  normal", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.62, 0.7, 0.8))
	if _msg_t > 0.0:
		var a := clampf(_msg_t, 0.0, 1.0)
		var tw := _font.get_string_size(_blocked_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var mr := Rect2(-tw - 30, 14, tw + 20, 24)
		var msb := StyleBoxFlat.new()
		msb.bg_color = Color(0.1, 0.05, 0.02, 0.8 * a)
		msb.set_corner_radius_all(6)
		draw_style_box(msb, mr)
		draw_string(_font, mr.position + Vector2(10, 17), _blocked_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.45, a))
