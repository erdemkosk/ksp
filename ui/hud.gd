class_name Hud
extends CanvasLayer
## Savaş uçağı HUD'u: sadece kokpit görünümünde (yunuslama merdiveni, uçuş yolu işareti,
## hız/irtifa/yön şeritleri). Dış kameralarda ekran temiz kalır; bilgiler açılır pencerelerde.
## Her modda: uyarılar, kısa mesajlar, kokpit anahtarı ipucu, EVA yönergeleri.

const HUD_COLOR := Color(0.4, 1.0, 0.6)
const SHADOW := Color(0, 0, 0, 0.55)
const PANEL_BG := Color(0.04, 0.06, 0.08, 0.72)
const WARN := Color(1.0, 0.3, 0.22)
const CARDINALS := {0: "K", 90: "D", 180: "G", 270: "B"}
## N ile açılıp kapanan paneller (savaş paneli, kumanda paneli, pencere çubuğu). Varsayılan açık.
static var panels_open := true

var vessel: Vessel
var player: PlayerController
var camera: FlightCamera
var interaction: CockpitInteraction
var panels: FlightPanels
var control_panel: ControlPanel
var part_windows: PartWindows
var combat: CombatHud
var combat_panel: CombatPanel
var _vignette: TextureRect
var _black: ColorRect
var _gloc_label: Label
## EVA'da uçağa binilebilecek mesafedeyse true (main yazar)
var can_board := false

var _root: Control
var _ladder: Control
var _font: SystemFont
var _font_bold: SystemFont
var _blink := 0.0
var _message := ""
var _message_time := 0.0


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_font_bold = SystemFont.new()
	_font_bold.font_names = _font.font_names
	_font_bold.font_weight = 700

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	add_child(_root)

	_ladder = Control.new()
	_ladder.clip_contents = true
	_ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder.draw.connect(_draw_ladder)
	_root.add_child(_ladder)

	control_panel = ControlPanel.new()
	control_panel.player = player
	control_panel.camera = camera
	add_child(control_panel)
	panels = FlightPanels.new()
	panels.player = player
	add_child(panels)
	combat = CombatHud.new()
	combat.camera = camera
	_root.add_child(combat)
	combat_panel = CombatPanel.new()
	combat_panel.camera = camera
	combat_panel.combat = combat
	add_child(combat_panel)
	part_windows = PartWindows.new()
	part_windows.camera = camera
	part_windows.theme_res = panels._theme
	add_child(part_windows)
	# G perdesi: kenarlardan kararan radyal gradyan + bayılınca tam karartma
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 1))
	grad.add_point(0.45, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 0)
	add_child(_black)
	_gloc_label = Label.new()
	_gloc_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_gloc_label.offset_top = 140
	_gloc_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gloc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gloc_label.add_theme_font_size_override("font_size", 26)
	_gloc_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_gloc_label.add_theme_constant_override("outline_size", 6)
	_gloc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gloc_label)


func show_message(text: String, seconds := 3.0) -> void:
	_message = text
	_message_time = seconds


func _process(delta: float) -> void:
	_clock += delta
	_blink += delta
	_message_time -= delta
	panels.vessel = vessel
	control_panel.vessel = vessel
	combat.vessel = vessel
	combat_panel.vessel = vessel
	_update_gloc(delta)
	var s := _root.size
	_ladder.position = Vector2(s.x * 0.25, s.y * 0.16)
	_ladder.size = Vector2(s.x * 0.5, s.y * 0.64)
	_root.queue_redraw()
	_ladder.queue_redraw()


func _ready_to_draw() -> bool:
	return is_instance_valid(vessel) and vessel.is_inside_tree() and is_instance_valid(camera)


func _in_cockpit() -> bool:
	return camera.mode == FlightCamera.Mode.COCKPIT and not camera.is_eva()


# ---------------------------------------------------------------- ana HUD

func _draw_hud() -> void:
	if not _ready_to_draw():
		return
	var s := _root.size
	var c := Vector2(s.x * 0.5, s.y * 0.48)
	var has_hud := vessel.cockpit() != null and vessel.cockpit().layout == "fighter"
	if _in_cockpit() and vessel.has_power() and has_hud:
		_heading_tape(Vector2(c.x, 46), 460.0, HUD_COLOR)
		_speed_tape(Vector2(c.x - 330, c.y), 300.0, HUD_COLOR)
		_altitude_tape(Vector2(c.x + 330, c.y), 300.0, HUD_COLOR)
		_flight_path_marker(HUD_COLOR)
		_autopilot_badge(Vector2(c.x, s.y - 40))
	elif not camera.is_eva():
		_autopilot_badge(Vector2(c.x, s.y - 40))
	if _in_cockpit():
		_tooltip()   # güç olmasa da anahtarların adı görünsün (bataryayı bulabilmek için)
	if player and player.mouse_flight and camera.mouse_aim != Vector3.ZERO or (player and player._mouse_flight_active() and _in_cockpit()):
		_mouse_aim_markers()
	if not camera.is_eva():
		_world_labels()
		_radio_box(_root.size)
	_info()
	if camera.is_eva():
		_eva_prompt(s)
	else:
		if camera.mode != FlightCamera.Mode.COCKPIT:
			_pfd(s)
		else:
			_hud_ils(c)
		_warnings(Vector2(c.x, 96))
	if _message_time > 0.0:
		_text_c(Vector2(c.x, s.y * 0.3), _message, 22, Color(1, 1, 1, clampf(_message_time, 0.0, 1.0)), _font_bold)


func _info() -> void:
	var pinfo := Crew.current()
	var ptxt := ("  ·  %s (Sv %d)" % [pinfo["name"], pinfo["level"]]) if not pinfo.is_empty() else ""
	var title := "%s  ·  %s%s" % [vessel.craft_name, camera.mode_name(), ptxt]
	var ts := ("  ·  gün x%d" % Weather.time_scale()) if Weather.time_scale() > 1.0 else ""
	var sub := "%s  ·  yerel saat %s%s" % [Weather.preset_name(), Weather.format_hour(Weather.local_hour(vessel.global_position)), ts]
	_text(Vector2(18, 32), title, 17, Color.WHITE, _font_bold)
	_text(Vector2(18, 54), sub, 14, Color(0.78, 0.84, 0.9))


## Her zaman görünen uçuş verisi paneli (sol alt): hava hızı, Mach, irtifa, yerden yükseklik,
## dikey hız, yön. Büyük rakamlar, küçük birimler, cam efektli koyu zemin.
func _flight_strip(s: Vector2) -> void:
	var speed := vessel.airspeed() * 3.6
	var alt := vessel.altitude()
	var radar := vessel.radar_altitude()
	var vs := vessel.vertical_speed()
	var w := 360.0
	var h := 122.0
	var r := Rect2(18, s.y - h - 18, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.72)
	sb.border_color = Color(0.45, 1.0, 0.65, 0.25)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(10)
	_root.draw_style_box(sb, r)
	# iki büyük sütun: HIZ ve İRTİFA
	var accent := Color(0.45, 1.0, 0.65)
	var dim := Color(0.62, 0.7, 0.76)
	var x1 := r.position.x + 18
	var x2 := r.position.x + w * 0.5 + 8
	var y := r.position.y
	_text(Vector2(x1, y + 24), "HAVA HIZI", 11, dim, _font_bold)
	_text(Vector2(x1, y + 62), "%d" % speed, 34, Color.WHITE, _font_bold)
	_text(Vector2(x1 + _font_bold.get_string_size("%d" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 6, y + 62), "km/sa", 13, dim)
	_text(Vector2(x1, y + 86), "M %.2f   ·   yer %d km/sa" % [vessel.mach(), vessel.ground_speed() * 3.6], 13, accent)
	_text(Vector2(x2, y + 24), "İRTİFA", 11, dim, _font_bold)
	var alt_txt := ("%.1f" % (alt / 1000.0)) if alt >= 10000.0 else ("%d" % alt)
	var alt_unit := "km" if alt >= 10000.0 else "m"
	_text(Vector2(x2, y + 62), alt_txt, 34, Color.WHITE, _font_bold)
	_text(Vector2(x2 + _font_bold.get_string_size(alt_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 6, y + 62), alt_unit, 13, dim)
	var vs_col := accent if vs >= -2.0 else (Color(1.0, 0.75, 0.3) if vs > -30.0 else Color(1.0, 0.35, 0.3))
	_text(Vector2(x2, y + 86), "%s %+d m/s" % ["▲" if vs >= 0.0 else "▼", roundi(vs)], 13, vs_col)
	if radar < 2000.0:
		_text(Vector2(x2 + 92, y + 86), "yer %d m" % radar, 13, dim)
	# alt çizgi: yön ve gaz
	_root.draw_line(Vector2(r.position.x + 14, y + 96), Vector2(r.end.x - 14, y + 96), Color(1, 1, 1, 0.08), 1.0)
	_text(Vector2(x1, y + 108), "YÖN %03d°" % vessel.heading_deg(), 11, dim, _font_bold)
	_text(Vector2(x1 + 92, y + 108), "GAZ %d%%" % (vessel.ctrl_throttle * 100.0), 11, dim, _font_bold)
	var gs := clampf(vessel.max_stress, 0.0, 1.0)
	var gcol := Color(0.45, 1.0, 0.65).lerp(Color(1.0, 0.72, 0.2), gs / 0.7) if gs < 0.7 else Color(1.0, 0.72, 0.2).lerp(Color(1.0, 0.28, 0.22), (gs - 0.7) / 0.3)
	_text(Vector2(x2, y + 108), "G %+.1f   yük %d%%" % [vessel.g_force, gs * 100.0], 11, gcol, _font_bold)
	_throttle_gauge(Rect2(r.end.x + 8, r.position.y, 78, h))


func _autopilot_badge(pos: Vector2) -> void:
	if not autoland_status.is_empty():
		_text_c(pos, "OTOMATİK İNİŞ  ·  " + autoland_status, 16, Color(0.4, 0.85, 1.0), _font_bold)
		return
	if player == null or not player.autopilot.any_active():
		return
	var ap := player.autopilot
	var parts := PackedStringArray()
	if ap.hold_altitude:
		parts.append("İRT %d" % ap.target_altitude)
	if ap.hold_heading:
		parts.append("YÖN %03d" % ap.target_heading)
	if ap.hold_speed:
		parts.append("HIZ %d" % (ap.target_speed * 3.6))
	if ap.level and not ap.hold_heading:
		parts.append("DÜZ")
	_text_c(pos, "OTOPİLOT  " + "  ".join(parts), 16, Color(0.4, 0.85, 1.0), _font_bold)


func _tooltip() -> void:
	if interaction == null or not is_instance_valid(interaction.hovered):
		return
	var mp := _root.get_local_mouse_position()
	var text := interaction.hovered.tooltip()
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 20
	var r := Rect2(mp + Vector2(18, 14), Vector2(w, 28))
	_panel(r, 0.85)
	_text(r.position + Vector2(10, 19), text, 15, Color.WHITE)


func _eva_prompt(s: Vector2) -> void:
	var p: PilotCharacter = camera.pilot if camera else null
	if is_instance_valid(p) and p.airborne:
		var up := Planet.up_at(p.global_position)
		var agl := Planet.altitude(p.global_position) - maxf(TerrainGen.height(Planet.surface_dir(p.global_position)), 0.0)
		var box := Rect2(s.x * 0.5 - 170, s.y - 110, 340, 64)
		_panel(box, 0.8)
		_text_c(Vector2(s.x * 0.5, box.position.y + 24), ("PARAŞÜT AÇIK" if p.chute_open else "SERBEST DÜŞÜŞ"), 17, HUD_COLOR if p.chute_open else WARN, _font_bold)
		_text_c(Vector2(s.x * 0.5, box.position.y + 48), "yer %d m   ·   alçalma %.1f m/s" % [roundi(agl), -p.velocity.dot(up)], 15, Color.WHITE)
		_text_c(Vector2(s.x * 0.5, s.y - 30), "A/D W/S paraşütü yönlendir  ·  Sağ tık + sürükle kamera", 15, Color(0.85, 0.9, 0.95))
		return
	var text := "WASD yürü  ·  Shift koş  ·  Ctrl yavaş  ·  Space zıpla  ·  fare: bak  ·  Alt: imleç  ·  F: uçağa bin"
	_text_c(Vector2(s.x * 0.5, s.y - 30), text, 15, Color(0.85, 0.9, 0.95))
	if can_board:
		var r := Rect2(s.x * 0.5 - 120, s.y - 92, 240, 40)
		_panel(r, 0.85)
		_text_c(Vector2(s.x * 0.5, s.y - 65), "F  —  Uçağa bin", 18, HUD_COLOR, _font_bold)

func _heading_tape(center: Vector2, width: float, col: Color) -> void:
	var hdg := vessel.heading_deg()
	var half := width * 0.5
	var start := int(floor((hdg - 32.0) / 5.0)) * 5
	for d in range(start, int(hdg + 33.0), 5):
		var x := center.x + (d - hdg) / 30.0 * half
		if absf(x - center.x) > half:
			continue
		var deg := posmod(d, 360)
		var major := deg % 10 == 0
		_line(Vector2(x, center.y), Vector2(x, center.y + (10.0 if major else 5.0)), col, 1.5)
		if major:
			var label: String = CARDINALS.get(deg, "%02d" % (deg / 10))
			_text_c(Vector2(x, center.y - 4), label, 15, col)
	_line(Vector2(center.x - half, center.y), Vector2(center.x + half, center.y), col, 1.5)
	_line(Vector2(center.x, center.y + 14), Vector2(center.x - 6, center.y + 22), col, 1.5)
	_line(Vector2(center.x, center.y + 14), Vector2(center.x + 6, center.y + 22), col, 1.5)
	_box_text(Vector2(center.x, center.y + 38), "%03d" % roundi(hdg) if roundi(hdg) < 360 else "000", 17, col)


func _speed_tape(center: Vector2, height: float, col: Color) -> void:
	var v := vessel.airspeed() * 3.6
	var half := height * 0.5
	var span := 100.0
	_line(Vector2(center.x, center.y - half), Vector2(center.x, center.y + half), col, 1.5)
	var start := int(floor((v - span) / 10.0)) * 10
	for k in range(maxi(start, 0), int(v + span) + 10, 10):
		var y := center.y - (k - v) / span * half
		if absf(y - center.y) > half:
			continue
		var major := k % 50 == 0
		_line(Vector2(center.x - (12.0 if major else 6.0), y), Vector2(center.x, y), col, 1.5)
		if major and absf(y - center.y) > 16.0:
			_text_r(Vector2(center.x - 16, y + 5), str(k), 14, col)
	_box_text(Vector2(center.x - 48, center.y), "%d" % v, 20, col, 76.0)
	_text_r(Vector2(center.x - 8, center.y + half + 22), "km/sa", 12, col)
	var aoa := ("α %.1f°" % vessel.aoa_deg()) if vessel.airspeed() > 25.0 else "α  —"
	var lines := ["M %.2f" % vessel.mach(), "G %.1f" % vessel.g_force, aoa]
	for i in lines.size():
		_text_r(Vector2(center.x - 8, center.y + half + 46 + i * 20), lines[i], 16, col)


func _altitude_tape(center: Vector2, height: float, col: Color) -> void:
	var alt := vessel.altitude()
	var half := height * 0.5
	var span := 300.0
	_line(Vector2(center.x, center.y - half), Vector2(center.x, center.y + half), col, 1.5)
	var start := int(floor((alt - span) / 50.0)) * 50
	for k in range(start, int(alt + span) + 50, 50):
		var y := center.y - (k - alt) / span * half
		if absf(y - center.y) > half:
			continue
		var major := k % 100 == 0
		_line(Vector2(center.x, y), Vector2(center.x + (12.0 if major else 6.0), y), col, 1.5)
		if major and absf(y - center.y) > 16.0:
			_text(Vector2(center.x + 16, y + 5), str(k), 14, col)
	_box_text(Vector2(center.x + 52, center.y), "%d" % alt, 20, col, 84.0)
	_text(Vector2(center.x + 8, center.y + half + 22), "m", 12, col)
	var radar := vessel.radar_altitude()
	var lines := ["VS %+d" % roundi(vessel.vertical_speed()), ("R %d" % radar) if radar < 1500.0 else ""]
	for i in lines.size():
		_text(Vector2(center.x + 8, center.y + half + 46 + i * 20), lines[i], 16, col)


func _flight_path_marker(col: Color) -> void:
	var vel := vessel.linear_velocity
	if vel.length() < 15.0:
		return
	var p := camera.global_position + vel.normalized() * 1000.0
	if camera.is_position_behind(p):
		return
	var sp := camera.unproject_position(p)
	_circle(sp, 7.0, col)
	_line(sp + Vector2(7, 0), sp + Vector2(20, 0), col, 2.0)
	_line(sp - Vector2(7, 0), sp - Vector2(20, 0), col, 2.0)
	_line(sp - Vector2(0, 7), sp - Vector2(0, 15), col, 2.0)


# ---------------------------------------------------------------- yunuslama merdiveni (kokpit)

func _draw_ladder() -> void:
	if not _ready_to_draw() or not _in_cockpit() or not vessel.has_power() or vessel.cockpit() == null or vessel.cockpit().layout != "fighter":
		return
	var origin := _ladder.position
	var cam_pos := camera.global_position
	var fwd := vessel.forward()
	var up := vessel.up()
	var hf := fwd - up * fwd.dot(up)   # burun yönünün yerel ufka izdüşümü
	if hf.length() < 0.05:
		hf = -vessel.global_basis.y if fwd.dot(up) > 0.0 else vessel.global_basis.y
		hf -= up * hf.dot(up)
	hf = hf.normalized()
	var right := hf.cross(up).normalized()
	var pitch := vessel.pitch_deg()
	var col := HUD_COLOR

	for p in range(-90, 91, 5):
		if absf(p - pitch) > 28.0:
			continue
		var r := deg_to_rad(p)
		var center := cam_pos + (hf * cos(r) + up * sin(r)) * 1000.0
		if camera.is_position_behind(center):
			continue
		var half := 1000.0 * tan(deg_to_rad(12.0 if p == 0 else 6.0))
		var gap := 1000.0 * tan(deg_to_rad(2.0))
		for side: float in [-1.0, 1.0]:
			var a := camera.unproject_position(center + right * gap * side) - origin
			var b := camera.unproject_position(center + right * half * side) - origin
			if p < 0:
				_ladder.draw_dashed_line(a + Vector2(1, 1), b + Vector2(1, 1), SHADOW, 2.0, 8.0)
				_ladder.draw_dashed_line(a, b, col, 2.0, 8.0)
			else:
				_ladder.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), SHADOW, 2.0)
				_ladder.draw_line(a, b, col, 2.0, true)
			if p != 0:
				var hook: Vector2 = (b - a).orthogonal().normalized() * 9.0 * (-side) * (1.0 if p > 0 else -1.0)
				_ladder.draw_line(b, b + hook, col, 2.0, true)
				var label_pos := b + (b - a).normalized() * 22.0
				var label := str(absi(p))
				var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				_ladder.draw_string(_font, label_pos + Vector2(-w * 0.5 + 1, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SHADOW)
				_ladder.draw_string(_font, label_pos + Vector2(-w * 0.5, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

	# burun (waterline) işareti
	var nose := cam_pos + fwd * 1000.0
	if not camera.is_position_behind(nose):
		var n := camera.unproject_position(nose) - origin
		var pts := PackedVector2Array([n + Vector2(-26, 0), n + Vector2(-12, 0), n + Vector2(-6, 9),
			n, n + Vector2(6, 9), n + Vector2(12, 0), n + Vector2(26, 0)])
		_ladder.draw_polyline(pts, col, 2.0, true)


# ---------------------------------------------------------------- paneller

func _warnings(pos: Vector2) -> void:
	_failures(pos + Vector2(0, 46))
	var list := active_warnings(vessel)
	if list.is_empty() or fmod(_blink, 0.8) > 0.55:
		return
	var text := "   ".join(list)
	var w := _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 36
	var r := Rect2(pos.x - w * 0.5, pos.y, w, 38)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.04, 0.02, 0.75)
	sb.border_color = WARN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_root.draw_style_box(sb, r)
	_text_c(Vector2(pos.x, pos.y + 27), text, 22, Color(1, 0.9, 0.85), _font_bold)


## Kısmi arızalar (sarı ikaz paneli): sıkışan yüzey, hidrolik, hasarlı kanat, teklemeyen motor.
func _failures(pos: Vector2) -> void:
	if not vessel.has_pilot() or vessel.failures.is_empty():
		return
	var lines: Array = vessel.failures.values()
	var w := 0.0
	for l in lines:
		w = maxf(w, _font_bold.get_string_size(String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var r := Rect2(pos.x - w * 0.5 - 16, pos.y, w + 32, 12 + lines.size() * 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.17, 0.0, 0.7)
	sb.border_color = Color(1.0, 0.72, 0.2, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	_root.draw_style_box(sb, r)
	for i in lines.size():
		_text_c(Vector2(pos.x, pos.y + 22 + i * 20), "⚠ " + String(lines[i]), 14, Color(1.0, 0.8, 0.35), _font_bold)


## Aktif uyarılar (sesli uyarı sistemi de bunu kullanır).
static func active_warnings(vessel: Vessel) -> PackedStringArray:
	var list := PackedStringArray()
	if not vessel.has_pilot():
		return list
	var speed := vessel.airspeed()
	if speed > 30.0 and absf(vessel.aoa_deg()) > 16.0:
		list.append("STALL")
	var radar := vessel.radar_altitude()
	if radar < 300.0 and vessel.vertical_speed() < -35.0 and vessel.gear_deploy() < 0.5:
		list.append("PULL UP")
	if vessel.gear_deploy() < 0.99 and radar < 120.0 and vessel.vertical_speed() < -2.0 and speed < 110.0:
		list.append("İNİŞ TAKIMI")
	var fuel := vessel.fuel_amount()
	if fuel <= 0.0:
		list.append("YAKIT BİTTİ")
	elif fuel / maxf(vessel.fuel_capacity(), 1.0) < 0.15:
		list.append("YAKIT AZ")
	if vessel.incoming_missile() != null:
		list.insert(0, "FÜZE")
	if vessel.max_stress > 0.85:
		list.insert(0, "OVER G")
	var cockpit := vessel.cockpit()
	if cockpit and cockpit.canopy_open and speed > 30.0:
		list.append("KANOPİ AÇIK")
	return list


func _panel(r: Rect2, alpha := 0.72) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL_BG, alpha)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	_root.draw_style_box(sb, r)


func _bar(pos: Vector2, label: String, value: float, text: String, col: Color) -> void:
	_text(pos, label, 13, Color(0.7, 0.76, 0.82), _font_bold)
	var bar := Rect2(pos.x + 56, pos.y - 11, 180, 10)
	_root.draw_rect(bar, Color(1, 1, 1, 0.1))
	_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(value, 0.0, 1.0), bar.size.y)), col)
	_text(Vector2(bar.end.x + 12, pos.y), text, 15, Color.WHITE)


func _pill(pos: Vector2, label: String, on: bool, col: Color) -> void:
	var r := Rect2(pos, Vector2(86, 24))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.85) if on else Color(1, 1, 1, 0.06)
	sb.border_color = col if on else Color(1, 1, 1, 0.15)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	_root.draw_style_box(sb, r)
	_text_c(pos + Vector2(43, 17), label, 13, Color(0.02, 0.05, 0.05) if on else Color(0.7, 0.75, 0.8), _font_bold)


func _box_text(center: Vector2, text: String, size: int, col: Color, width := 64.0) -> void:
	var r := Rect2(center.x - width * 0.5, center.y - 15, width, 30)
	_root.draw_rect(r, Color(0, 0, 0, 0.45))
	_root.draw_rect(r, col, false, 1.5)
	_text_c(Vector2(center.x, center.y + 7), text, size, col)


func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_root.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), SHADOW, w)
	_root.draw_line(a, b, col, w, true)


func _circle(c: Vector2, r: float, col: Color) -> void:
	_root.draw_arc(c + Vector2(1, 1), r, 0, TAU, 24, SHADOW, 2.0)
	_root.draw_arc(c, r, 0, TAU, 24, col, 2.0, true)


func _text(pos: Vector2, text: String, size: int, col: Color, font: Font = null) -> void:
	var f := font if font else _font
	_root.draw_string(f, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SHADOW)
	_root.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_c(pos: Vector2, text: String, size: int, col: Color, font: Font = null) -> void:
	var f := font if font else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(pos - Vector2(w * 0.5, 0), text, size, col, f)


func _text_r(pos: Vector2, text: String, size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(pos - Vector2(w, 0), text, size, col)


## G-LOC perdesi: gri (pozitif G) ya da kırmızı (negatif G) kenar kararması, bayılınca siyah.
func _update_gloc(delta: float) -> void:
	if player == null or not is_instance_valid(vessel) or camera == null or camera.is_eva() or not vessel.has_pilot():
		_vignette.modulate.a = 0.0
		_black.color.a = move_toward(_black.color.a, 0.0, delta * 2.0)
		return
	var grey := clampf(player.g_strain, 0.0, 1.0)
	var red := clampf(player.red_strain, 0.0, 1.0)
	_vignette.modulate = Color(0.55, 0.0, 0.0) if red > grey else Color(1, 1, 1)
	_vignette.modulate.a = smoothstep(0.3, 1.05, maxf(grey, red)) * 0.8
	var target := 0.94 if player.blackout else smoothstep(0.85, 1.0, maxf(grey, red)) * 0.4
	_black.color = Color(0.25, 0, 0, _black.color.a) if red > grey else Color(0, 0, 0, _black.color.a)
	_black.color.a = move_toward(_black.color.a, target, delta * 1.5)
	# kademeli uyarı yazısı
	var warn := ""
	if player.blackout:
		warn = "PİLOT BAYGIN — kumanda yok"
	elif maxf(grey, red) > 0.5:
		warn = ("G YÜKÜ YÜKSEK  %.1f / %.1f G — çekmeyi azalt" % [vessel.g_force, player.g_tolerance()]) if red <= grey else "NEGATİF G — itmeyi azalt"
	_gloc_label.text = warn
	_gloc_label.visible = not warn.is_empty() and fmod(_blink, 0.7) < 0.5
	_gloc_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if player.blackout or maxf(grey, red) > 0.7 else Color(1.0, 0.8, 0.35))


## Fareyle uçuş işaretleri: daire = farenin nişanı, artı = uçağın burnu (oraya döner).
func _mouse_aim_markers() -> void:
	var cam := camera
	var aim: Vector3 = player.aim_dir
	if aim == Vector3.ZERO:
		return
	var p := cam.global_position + aim * 2000.0
	if not cam.is_position_behind(p):
		var sp := cam.unproject_position(p)
		_root.draw_arc(sp + Vector2(1, 1), 11.0, 0, TAU, 32, SHADOW, 2.0)
		_root.draw_arc(sp, 11.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.0, true)
	var n := cam.global_position + vessel.forward() * 2000.0
	if not cam.is_position_behind(n):
		var np := cam.unproject_position(n)
		var c := Color(1, 1, 1, 0.75)
		_line(np - Vector2(9, 0), np + Vector2(9, 0), c, 2.0)
		_line(np - Vector2(0, 9), np + Vector2(0, 9), c, 2.0)


## Havaalanı ve kasaba etiketleri (yön bulmak için): ✈ havaalanı < 60 km, ⌂ kasaba < 25 km.
func _world_labels() -> void:
	var cam := camera
	var items := []
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var xz: Vector2 = a["xz"]
		items.append(["✈ " + String(a["name"]), MissionManager.world_point(xz.x, xz.y, float(a["elev"]) + 20.0), 60000.0, Color(0.55, 0.85, 1.0)])
	for t: Dictionary in Towns.TOWNS:
		var xz: Vector2 = t["xz"]
		items.append(["⌂ " + String(t["name"]), MissionManager.world_point(xz.x, xz.y, MissionManager.ground_height(xz.x, xz.y) + 40.0), 25000.0, Color(0.95, 0.9, 0.75)])
	for it in items:
		var p: Vector3 = it[1]
		var d := p.distance_to(cam.global_position)
		if d > it[2] or d < 400.0 or cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var a := clampf(1.0 - d / it[2], 0.25, 0.9)
		var col: Color = it[3]
		_root.draw_circle(sp, 3.0, Color(col, a))
		_text(sp + Vector2(8, 4), "%s  %.1f km" % [it[0], d / 1000.0], 12, Color(col, a))


## Gaz göstergesi (hız/irtifa şeridinin yanında, her zaman): dikey çubuk, art yakıcı bölgesi,
## yüzde, motor devri (N2) ve itki.
func _throttle_gauge(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.72)
	sb.border_color = Color(0.45, 1.0, 0.65, 0.25)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(10)
	_root.draw_style_box(sb, r)
	var dim := Color(0.62, 0.7, 0.76)
	_text_c(Vector2(r.get_center().x, r.position.y + 18), "GAZ", 11, dim, _font_bold)
	var thr := clampf(vessel.ctrl_throttle, 0.0, 1.0)
	var bar := Rect2(r.position.x + 12, r.position.y + 26, 18, r.size.y - 38)
	_root.draw_rect(bar, Color(1, 1, 1, 0.08))
	var ab_y := bar.end.y - bar.size.y * EngineModule.AFTERBURNER_THRESHOLD
	# art yakıcı bölgesi
	_root.draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, ab_y - bar.position.y), Color(1.0, 0.5, 0.15, 0.18))
	var fill_h := bar.size.y * thr
	var ab_on := false
	for e in vessel.engines():
		if e.afterburner > 0.3:
			ab_on = true
	var col := Color(1.0, 0.55, 0.2) if thr >= EngineModule.AFTERBURNER_THRESHOLD else Color(0.45, 1.0, 0.65)
	_root.draw_rect(Rect2(bar.position.x, bar.end.y - fill_h, bar.size.x, fill_h), col)
	_root.draw_line(Vector2(bar.position.x - 3, ab_y), Vector2(bar.end.x + 3, ab_y), Color(1.0, 0.6, 0.2), 1.5)
	# yazılar
	var tx := bar.end.x + 8
	_text(Vector2(tx, r.position.y + 48), "%d" % (thr * 100.0), 20, Color.WHITE, _font_bold)
	_text(Vector2(tx, r.position.y + 62), "%", 11, dim)
	var n2 := 0.0
	var kn := 0.0
	for e in vessel.engines():
		n2 = maxf(n2, e.n2)
		kn += e.thrust / 1000.0
	_text(Vector2(tx, r.position.y + 84), "N2 %d" % (n2 * 100.0), 10, dim, _font_bold)
	_text(Vector2(tx, r.position.y + 98), "%d kN" % kn, 10, dim, _font_bold)
	if ab_on:
		_text(Vector2(tx, r.position.y + 114), "AB", 12, Color(1.0, 0.55, 0.2), _font_bold)


# ---------------------------------------------------------------- gösterge kümesi (sol alt)

## Kokpit saatleri gibi dört yuvarlak gösterge: HIZ, İRTİFA, GAZ, G — her zaman görünür.
func _instrument_cluster(s: Vector2) -> void:
	var r := 54.0
	var gap := 14.0
	var w := 4 * (r * 2.0 + gap) + gap
	var h := r * 2.0 + 56.0
	var box := Rect2(18, s.y - h - 14, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.04, 0.05, 0.78)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	_root.draw_style_box(sb, box)
	var cy := box.position.y + r + 12.0
	var x0 := box.position.x + gap + r
	var step := r * 2.0 + gap
	var dim := Color(0.62, 0.7, 0.76)
	var green := Color(0.45, 1.0, 0.65)
	var amber := Color(1.0, 0.72, 0.25)
	var red := Color(1.0, 0.32, 0.26)
	# 1) HIZ
	var kmh := vessel.airspeed() * 3.6
	var c := Vector2(x0, cy)
	_dial_face(c, r)
	_dial_ticks(c, r, 14, 2)
	_dial_needle(c, r, clampf(kmh / 1400.0, 0.0, 1.0), Color.WHITE)
	_text_c(c + Vector2(0, -r * 0.36), "HIZ", 10, dim, _font_bold)
	_readout_bg(c, r)
	_text_c(c + Vector2(0, r * 0.42), "%d" % kmh, 20, Color.WHITE, _font_bold)
	_text_c(c + Vector2(0, r * 0.66), "km/sa · M%.2f" % vessel.mach(), 9, dim)
	# 2) İRTİFA (ibre: her tur 1000 m)
	var alt := vessel.altitude()
	c.x += step
	_dial_face(c, r)
	_dial_ticks(c, r, 10, 5, true)
	_dial_needle(c, r, fposmod(alt, 1000.0) / 1000.0, Color.WHITE, true)
	_text_c(c + Vector2(0, -r * 0.36), "İRTİFA", 10, dim, _font_bold)
	var alt_txt := ("%.1f km" % (alt / 1000.0)) if alt >= 10000.0 else ("%d m" % alt)
	_readout_bg(c, r)
	_text_c(c + Vector2(0, r * 0.42), alt_txt, 18, Color.WHITE, _font_bold)
	var vs := vessel.vertical_speed()
	var vs_col := green if vs >= -2.0 else (amber if vs > -30.0 else red)
	_text_c(c + Vector2(0, r * 0.66), "%s %+d m/s" % ["▲" if vs >= 0.0 else "▼", roundi(vs)], 10, vs_col, _font_bold)
	# 3) GAZ (art yakıcı bölgesi turuncu)
	var thr := clampf(vessel.ctrl_throttle, 0.0, 1.0)
	c.x += step
	_dial_face(c, r)
	_dial_zone(c, r, EngineModule.AFTERBURNER_THRESHOLD, 1.0, Color(1.0, 0.5, 0.15, 0.85))
	_dial_ticks(c, r, 10, 5)
	var ab := false
	var n2 := 0.0
	for e in vessel.engines():
		n2 = maxf(n2, e.n2)
		ab = ab or e.afterburner > 0.3
	_dial_arc_fill(c, r - 9.0, thr, Color(1.0, 0.55, 0.2) if ab else green)
	_dial_needle(c, r, thr, Color.WHITE)
	_text_c(c + Vector2(0, -r * 0.36), "GAZ", 10, dim, _font_bold)
	_readout_bg(c, r)
	_text_c(c + Vector2(0, r * 0.42), "%d%%" % (thr * 100.0), 20, Color(1.0, 0.6, 0.25) if ab else Color.WHITE, _font_bold)
	_text_c(c + Vector2(0, r * 0.66), "AB" if ab else "N2 %d" % (n2 * 100.0), 10, Color(1.0, 0.6, 0.25) if ab else dim, _font_bold)
	# 4) G (pilot sınırına göre bölgeler, yapı sınırı işareti)
	var tol: float = player.g_tolerance() if player else 8.0
	var g := vessel.g_force
	var gmin := -3.0
	var gmax := 12.0
	var f := func(x: float) -> float: return clampf((x - gmin) / (gmax - gmin), 0.0, 1.0)
	c.x += step
	_dial_face(c, r)
	_dial_zone(c, r, f.call(-1.0), f.call(tol * 0.75), Color(green, 0.55))
	_dial_zone(c, r, f.call(tol * 0.75), f.call(tol), Color(amber, 0.75))
	_dial_zone(c, r, f.call(tol), 1.0, Color(red, 0.8))
	_dial_zone(c, r, 0.0, f.call(-1.0), Color(red, 0.6))
	_dial_ticks(c, r, 15, 5)
	var struct_g := maxf(absf(g), 1.0) / maxf(vessel.max_stress, 0.05)
	if vessel.max_stress > 0.05 and struct_g < gmax:
		var a := _dial_angle(f.call(struct_g))
		var dir := Vector2(cos(a), sin(a))
		_root.draw_line(c + dir * (r - 2), c + dir * (r + 7), Color(1, 1, 1), 3.0)
	var strain := player.g_strain if player else 0.0
	var gcol := green if g < tol * 0.75 else (amber if g < tol else red)
	if strain > 0.5:
		gcol = red
	_dial_needle(c, r, f.call(g), gcol)
	_text_c(c + Vector2(0, -r * 0.36), "G", 11, dim, _font_bold)
	_readout_bg(c, r)
	_text_c(c + Vector2(0, r * 0.42), "%+.1f" % g, 20, gcol, _font_bold)
	# pilot zorlanma çubuğu
	var bar := Rect2(c.x - r * 0.5, c.y + r * 0.58, r, 5)
	_root.draw_rect(bar, Color(1, 1, 1, 0.1))
	_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(strain, 0.0, 1.0), bar.size.y)), red if strain > 0.6 else amber)
	# alt satır
	var ly := box.end.y - 14.0
	var info := "YÖN %03d°   ·   α %+.1f°   ·   yer %d m   ·   pilot sınırı %.1f G" % [vessel.heading_deg(), vessel.aoa_deg(), vessel.radar_altitude(), tol]
	_text(Vector2(box.position.x + 16, ly), info, 11, dim, _font_bold)


## Kadran açısı: 0 → sol alt (135°), 1 → sağ alt (405°); tam=true ise tam tur (yukarıdan).
func _dial_angle(t: float, full := false) -> float:
	if full:
		return -PI * 0.5 + t * TAU
	return deg_to_rad(135.0 + 270.0 * t)


## Dijital okumanın arkasına koyu zemin (ibre üstünden geçse de okunur).
func _readout_bg(c: Vector2, r: float) -> void:
	var rr := Rect2(c + Vector2(-r * 0.62, r * 0.14), Vector2(r * 1.24, r * 0.6))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.82)
	sb.set_corner_radius_all(5)
	_root.draw_style_box(sb, rr)


func _dial_face(c: Vector2, r: float) -> void:
	_root.draw_circle(c, r, Color(0.01, 0.015, 0.02, 0.85))
	_root.draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.18), 1.5, true)


func _dial_ticks(c: Vector2, r: float, n: int, major_every: int, full := false) -> void:
	for i in n + (0 if full else 1):
		var t := float(i) / n
		var a := _dial_angle(t, full)
		var d := Vector2(cos(a), sin(a))
		var major := i % major_every == 0
		_root.draw_line(c + d * (r - (9.0 if major else 5.0)), c + d * (r - 2.0), Color(1, 1, 1, 0.7 if major else 0.35), 1.5 if major else 1.0)


func _dial_zone(c: Vector2, r: float, t0: float, t1: float, col: Color) -> void:
	if t1 <= t0:
		return
	_root.draw_arc(c, r - 3.5, _dial_angle(t0), _dial_angle(t1), 24, col, 4.0, true)


func _dial_arc_fill(c: Vector2, r: float, t: float, col: Color) -> void:
	if t <= 0.001:
		return
	_root.draw_arc(c, r, _dial_angle(0.0), _dial_angle(t), 32, Color(col, 0.6), 3.0, true)


func _dial_needle(c: Vector2, r: float, t: float, col: Color, full := false) -> void:
	var a := _dial_angle(t, full)
	var d := Vector2(cos(a), sin(a))
	_root.draw_line(c - d * 6.0, c + d * (r - 8.0), Color(0, 0, 0, 0.5), 4.0, true)
	_root.draw_line(c - d * 6.0, c + d * (r - 8.0), col, 2.5, true)
	_root.draw_circle(c, 4.0, col)


# ---------------------------------------------------------------- telsiz kutusu (sağ üst)

var radio: Radio
var autoland_status := ""
var _radio_log: Array = []      # [konuşan, metin, zaman]
var _clock := 0.0


func radio_message(sender: String, text: String) -> void:
	_radio_log.append([sender, text, _clock])
	if _radio_log.size() > 3:
		_radio_log.pop_front()


## Telsiz mesajları: konuşan adı renkli, konuşurken sinyal çubukları oynar, 10 sn sonra solar.
func _radio_box(s: Vector2) -> void:
	var live := radio != null and radio.speaking
	var items := []
	for m in _radio_log:
		var age: float = _clock - float(m[2])
		if age < 10.0:
			items.append([m[0], m[1], clampf((10.0 - age) / 2.0, 0.0, 1.0)])
	if items.is_empty() and not live:
		return
	var w := 430.0
	var line_h := 19.0
	var lines := []
	for it in items:
		var wrapped := _wrap(String(it[1]), 58)
		lines.append([it[0], wrapped, it[2]])
	var h := 34.0
	for l in lines:
		h += line_h * (1 + (l[1] as Array).size()) + 4.0
	var r := Rect2(s.x - w - 18, 76, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.03, 0.82)
	sb.border_color = Color(0.45, 1.0, 0.65, 0.5 if live else 0.2)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(8)
	_root.draw_style_box(sb, r)
	_text(r.position + Vector2(12, 21), "📻 TELSİZ", 12, Color(0.45, 1.0, 0.65), _font_bold)
	# sinyal çubukları
	for i in 5:
		var bh := 4.0 + i * 2.5
		var on := live and randf() < 0.8 - i * 0.1
		_root.draw_rect(Rect2(r.position.x + 100 + i * 6, r.position.y + 22 - bh, 4, bh), Color(0.45, 1.0, 0.65, 0.9 if on else 0.18))
	var y := r.position.y + 34.0
	var colors := {"KULE": Color(0.55, 0.85, 1.0), "ŞAHİN GÖZÜ": Color(1.0, 0.82, 0.35)}
	for l in lines:
		var a: float = l[2]
		var col: Color = colors.get(String(l[0]), Color(0.75, 1.0, 0.75))
		if String(l[0]).ends_with("KULESİ"):
			col = Color(0.55, 0.85, 1.0)
		y += line_h
		_text(Vector2(r.position.x + 12, y), String(l[0]) + ":", 12, Color(col, a), _font_bold)
		for txt in l[1]:
			y += line_h
			_text(Vector2(r.position.x + 20, y), String(txt), 13, Color(0.92, 0.94, 0.95, a))
		y += 4.0


func _wrap(text: String, n: int) -> Array:
	var out := []
	var cur := ""
	for word in text.split(" "):
		if (cur + " " + word).length() > n and not cur.is_empty():
			out.append(cur)
			cur = word
		else:
			cur = word if cur.is_empty() else cur + " " + word
	if not cur.is_empty():
		out.append(cur)
	return out


# ---------------------------------------------------------------- PFD (alt orta, her zaman)

const PFD_SKY := Color(0.16, 0.42, 0.78)
const PFD_GROUND := Color(0.45, 0.3, 0.16)
const PFD_W := 640.0
const PFD_H := 176.0


## Cam kokpit birincil uçuş ekranı: gaz | hız şeridi | yapay ufuk | irtifa şeridi + VS | G,
## altta pusula. Gerçek uçaklardaki PFD düzeni.
func _pfd(s: Vector2) -> void:
	var box := Rect2((s.x - PFD_W) * 0.5, s.y - PFD_H - 10, PFD_W, PFD_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.02, 0.03, 0.86)
	sb.border_color = Color(0.45, 1.0, 0.65, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	_root.draw_style_box(sb, box)
	var cx := box.get_center().x
	var cy := box.position.y + 74.0
	_pfd_throttle(Rect2(box.position.x + 16, box.position.y + 14, 34, 120))
	_pfd_speed_tape(Rect2(box.position.x + 64, box.position.y + 14, 104, 124))
	_pfd_attitude(Vector2(cx, cy), 62.0)
	_pfd_ils(Vector2(cx, cy), 62.0)
	_pfd_alt_tape(Rect2(box.end.x - 178, box.position.y + 14, 104, 124))
	_pfd_g_bar(Rect2(box.end.x - 50, box.position.y + 14, 34, 120))
	_pfd_compass(Rect2(cx - 150, box.end.y - 28, 300, 20))
	# açık hava freni / fren paraşütü: PFD üstünde sarı etiket
	var tags := PackedStringArray()
	for m in vessel.modules:
		if m is AirbrakeModule and m.deploy > 0.1 and not "HAVA FRENİ" in tags:
			tags.append("HAVA FRENİ")
		elif m is ChuteModule and m.state == 1 and not "PARAŞÜT" in tags:
			tags.append("PARAŞÜT")
	if vessel.parking_brake:
		tags.append("PARK FRENİ")
	if not tags.is_empty():
		_text_c(Vector2(box.position.x + 116, box.position.y - 8), "  ·  ".join(tags), 13, Color(1.0, 0.75, 0.25), _font_bold)


func _pfd_attitude(c: Vector2, r: float) -> void:
	var pitch := vessel.pitch_deg()
	var roll := deg_to_rad(vessel.roll_deg())
	var ppd := 2.4
	var n := Vector2(sin(-roll), cos(-roll))
	var along := Vector2(n.y, -n.x)
	var off := c + n * (pitch * ppd)
	_root.draw_circle(c, r, PFD_SKY)
	var pts := PackedVector2Array()
	var steps := 96
	var prev_in := false
	var prev_p := Vector2.ZERO
	for i in steps + 1:
		var a := TAU * float(i) / steps
		var p := c + Vector2(cos(a), sin(a)) * r
		var inside := (p - off).dot(n) > 0.0
		if i > 0 and inside != prev_in:
			var d0 := (prev_p - off).dot(n)
			var d1 := (p - off).dot(n)
			pts.append(prev_p.lerp(p, d0 / (d0 - d1)))
		if inside and i < steps:
			pts.append(p)
		prev_in = inside
		prev_p = p
	if pts.size() >= 3:
		_root.draw_colored_polygon(pts, PFD_GROUND)
	for deg in range(-40, 41, 5):
		var center := off - n * (deg * ppd)
		if center.distance_to(c) > r - 8.0:
			continue
		if deg == 0:
			var hits := _circle_clip(center - along * r * 1.3, center + along * r * 1.3, c, r)
			if hits.size() == 2:
				_root.draw_line(hits[0], hits[1], Color.WHITE, 2.0, true)
			continue
		var half := 24.0 if deg % 10 == 0 else 11.0
		_root.draw_line(center - along * half, center + along * half, Color(1, 1, 1, 0.85), 1.5, true)
		if deg % 10 == 0:
			_root.draw_string(_font, center + along * (half + 3) + Vector2(0, 4), str(absi(deg)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))
	for b in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(-90.0 + b)
		var d := Vector2(cos(a), sin(a))
		var l := 9.0 if b % 30 == 0 else 5.0
		_root.draw_line(c + d * r, c + d * (r - l), Color(1, 1, 1, 0.8), 1.5)
	var ra := deg_to_rad(-90.0) - roll
	var rd := Vector2(cos(ra), sin(ra))
	var rp := c + rd * (r - 11.0)
	var rn := rd.orthogonal()
	var yel := Color(1.0, 0.85, 0.2)
	_root.draw_colored_polygon(PackedVector2Array([rp, rp - rd * 9 + rn * 6, rp - rd * 9 - rn * 6]), yel)
	_root.draw_arc(c, r, 0, TAU, 64, Color(0, 0, 0, 0.9), 3.0, true)
	_root.draw_arc(c, r + 1.5, 0, TAU, 64, Color(1, 1, 1, 0.25), 1.0, true)
	for side in [-1.0, 1.0]:
		var a0 := c + Vector2(side * 34, 0)
		var a1 := c + Vector2(side * 12, 0)
		_root.draw_line(a0, a1, Color.BLACK, 6.0)
		_root.draw_line(a0, a1, yel, 4.0)
		_root.draw_line(a1, a1 + Vector2(0, 6), yel, 4.0)
	_root.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), yel)


func _circle_clip(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return []
	var sq := sqrt(disc)
	return [a + d * clampf((-qb - sq) / (2.0 * qa), 0.0, 1.0), a + d * clampf((-qb + sq) / (2.0 * qa), 0.0, 1.0)]


## Kayan şerit: değerin çevresindeki çentikler + ortada kutulu okuma.
func _pfd_tape(r: Rect2, value: float, span: float, minor: float, major: float, ticks_right: bool, label: String, sub: String, sub_col: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.1, 0.9)
	bg.set_corner_radius_all(6)
	_root.draw_style_box(bg, r)
	var cy := r.get_center().y
	var half := r.size.y * 0.5
	var v := floorf((value - span) / minor) * minor
	while v <= value + span:
		var y := cy - (v - value) / span * half
		if y > r.position.y + 4 and y < r.end.y - 4:
			var is_major := absf(fposmod(v + 0.001, major)) < 0.01
			var tl := 10.0 if is_major else 5.0
			var x0 := r.end.x - tl if ticks_right else r.position.x
			_root.draw_line(Vector2(x0, y), Vector2(x0 + tl, y), Color(1, 1, 1, 0.75 if is_major else 0.4), 1.5)
			if is_major and absf(y - cy) > 16.0:
				var t := "%d" % roundi(v)
				var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				var tx := r.end.x - 14.0 - tw if ticks_right else r.position.x + 14.0
				_root.draw_string(_font, Vector2(tx, y + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))
		v += minor
	var br := Rect2(r.position.x + 4, cy - 15, r.size.x - 8.0, 30)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.95)
	box.border_color = Color(1, 1, 1, 0.85)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	_root.draw_style_box(box, br)
	var txt := "%d" % roundi(value)
	var w := _font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_root.draw_string(_font_bold, Vector2(br.get_center().x - w * 0.5, cy + 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	_text_c(Vector2(r.get_center().x, r.position.y - 3.0), label, 9, Color(0.6, 0.68, 0.74), _font_bold)
	_text_c(Vector2(r.get_center().x, r.end.y + 14.0), sub, 11, sub_col, _font_bold)


func _pfd_speed_tape(r: Rect2) -> void:
	_pfd_tape(r, vessel.airspeed() * 3.6, 120.0, 10.0, 50.0, true, "HIZ km/sa", "M %.2f" % vessel.mach(), Color(0.45, 1.0, 0.65))


func _pfd_alt_tape(r: Rect2) -> void:
	var vs := vessel.vertical_speed()
	var vs_col := Color(0.45, 1.0, 0.65) if vs >= -2.0 else (Color(1.0, 0.72, 0.25) if vs > -30.0 else Color(1.0, 0.32, 0.26))
	_pfd_tape(r, vessel.altitude(), 300.0, 20.0, 100.0, false, "İRTİFA m", "%s %+d m/s" % ["▲" if vs >= 0.0 else "▼", roundi(vs)], vs_col)
	var x := r.end.x + 7.0
	var cy := r.get_center().y
	var k := clampf(vs / 30.0, -1.0, 1.0)
	_root.draw_line(Vector2(x, cy), Vector2(x, cy - k * (r.size.y * 0.45)), vs_col, 3.0)
	_root.draw_line(Vector2(x - 3, cy), Vector2(x + 3, cy), Color(1, 1, 1, 0.5), 1.0)
	var radar := vessel.radar_altitude()
	if radar < 1500.0:
		_text_c(Vector2(r.get_center().x, r.position.y + 14.0), "yer %d" % radar, 10, Color(1.0, 0.85, 0.4), _font_bold)


func _pfd_throttle(r: Rect2) -> void:
	var thr := clampf(vessel.ctrl_throttle, 0.0, 1.0)
	var ab := false
	var n2 := 0.0
	for e in vessel.engines():
		ab = ab or e.afterburner > 0.3
		n2 = maxf(n2, e.n2)
	var bar := Rect2(r.position.x + 9, r.position.y + 6, 16, r.size.y - 8)
	_root.draw_rect(bar, Color(1, 1, 1, 0.08))
	var ab_y := bar.end.y - bar.size.y * EngineModule.AFTERBURNER_THRESHOLD
	_root.draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, ab_y - bar.position.y), Color(1.0, 0.5, 0.15, 0.25))
	var col := Color(1.0, 0.55, 0.2) if thr >= EngineModule.AFTERBURNER_THRESHOLD else Color(0.45, 1.0, 0.65)
	_root.draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * thr, bar.size.x, bar.size.y * thr), col)
	_text_c(Vector2(r.get_center().x, r.position.y - 3), "GAZ", 9, Color(0.6, 0.68, 0.74), _font_bold)
	_text_c(Vector2(r.get_center().x, r.end.y + 14), "AB" if ab else "%d%%" % (thr * 100.0), 12, col, _font_bold)
	_text_c(Vector2(r.get_center().x, r.end.y + 27), "N2 %d" % (n2 * 100.0), 9, Color(0.6, 0.68, 0.74))


func _pfd_g_bar(r: Rect2) -> void:
	var tol: float = player.g_tolerance() if player else 8.0
	var g := vessel.g_force
	var gmin := -3.0
	var gmax := 12.0
	var bar := Rect2(r.position.x + 9, r.position.y + 6, 16, r.size.y - 8)
	var span := gmax - gmin
	_root.draw_rect(bar, Color(1, 1, 1, 0.06))
	var zones := [[gmin, -1.0, Color(1.0, 0.32, 0.26, 0.5)], [-1.0, tol * 0.75, Color(0.45, 1.0, 0.65, 0.28)],
		[tol * 0.75, tol, Color(1.0, 0.72, 0.25, 0.45)], [tol, gmax, Color(1.0, 0.32, 0.26, 0.5)]]
	for z in zones:
		var y0: float = bar.end.y - bar.size.y * clampf((float(z[1]) - gmin) / span, 0.0, 1.0)
		var y1: float = bar.end.y - bar.size.y * clampf((float(z[0]) - gmin) / span, 0.0, 1.0)
		_root.draw_rect(Rect2(bar.position.x, y0, bar.size.x, y1 - y0), z[2])
	var gy: float = bar.end.y - bar.size.y * clampf((g - gmin) / span, 0.0, 1.0)
	var gcol := Color(0.45, 1.0, 0.65) if g < tol * 0.75 else (Color(1.0, 0.72, 0.25) if g < tol else Color(1.0, 0.32, 0.26))
	_root.draw_colored_polygon(PackedVector2Array([Vector2(bar.position.x - 7, gy - 5), Vector2(bar.position.x - 1, gy), Vector2(bar.position.x - 7, gy + 5)]), gcol)
	_root.draw_line(Vector2(bar.position.x, gy), Vector2(bar.end.x, gy), Color.WHITE, 2.0)
	if vessel.max_stress > 0.05:
		var sg := maxf(absf(g), 1.0) / vessel.max_stress
		if sg < gmax:
			var sy: float = bar.end.y - bar.size.y * clampf((sg - gmin) / span, 0.0, 1.0)
			_root.draw_line(Vector2(bar.position.x - 3, sy), Vector2(bar.end.x + 3, sy), Color(1, 1, 1, 0.9), 1.0)
	_text_c(Vector2(r.get_center().x, r.position.y - 3), "G", 10, Color(0.6, 0.68, 0.74), _font_bold)
	_text_c(Vector2(r.get_center().x, r.end.y + 14), "%+.1f" % g, 12, gcol, _font_bold)
	var strain: float = player.g_strain if player else 0.0
	if strain > 0.05:
		_root.draw_rect(Rect2(r.position.x + 4, r.end.y + 21, (r.size.x - 8) * clampf(strain, 0.0, 1.0), 3), Color(1.0, 0.32, 0.26))


func _pfd_compass(r: Rect2) -> void:
	var hdg := vessel.heading_deg()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.1, 0.9)
	bg.set_corner_radius_all(6)
	_root.draw_style_box(bg, r)
	var cx := r.get_center().x
	var span := 50.0
	var d := int(floor((hdg - span) / 5.0)) * 5
	while d <= hdg + span:
		var x := cx + (d - hdg) / span * r.size.x * 0.5
		if x > r.position.x + 6 and x < r.end.x - 6:
			var dd := posmod(d, 360)
			_root.draw_line(Vector2(x, r.end.y - (7.0 if dd % 10 == 0 else 3.0)), Vector2(x, r.end.y - 2), Color(1, 1, 1, 0.6), 1.0)
			if dd % 30 == 0 and absf(x - cx) > 26.0:
				var lbl: String = CARDINALS.get(dd, "%02d" % (dd / 10))
				var w := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				_root.draw_string(_font, Vector2(x - w * 0.5, r.position.y + 11), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.75))
		d += 5
	var txt := "%03d°" % (roundi(hdg) % 360)
	var tw := _font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12
	var br := Rect2(cx - tw * 0.5, r.position.y, tw, 17)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.95)
	box.border_color = Color(1, 1, 1, 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	_root.draw_style_box(box, br)
	_text_c(Vector2(cx, r.position.y + 13), txt, 12, Color.WHITE, _font_bold)


## ILS iğneleri yapay ufkun üstünde: macenta dikey = yön, yatay = süzülüş. İğneye doğru uç.
func _pfd_ils(c: Vector2, r: float) -> void:
	if vessel.radar_altitude() < 3.0:
		return
	var ils := Ils.info(vessel)
	if ils.is_empty():
		return
	var mag := Color(1.0, 0.35, 1.0)
	var lx := c.x - clampf(float(ils["loc"]) / 2.5, -1.0, 1.0) * r * 0.75
	var gy := c.y + clampf(float(ils["gs"]) / 0.7, -1.0, 1.0) * r * 0.75
	_root.draw_line(Vector2(lx, c.y - r * 0.7), Vector2(lx, c.y + r * 0.7), Color(0, 0, 0, 0.6), 4.0)
	_root.draw_line(Vector2(lx, c.y - r * 0.7), Vector2(lx, c.y + r * 0.7), mag, 2.0)
	_root.draw_line(Vector2(c.x - r * 0.7, gy), Vector2(c.x + r * 0.7, gy), Color(0, 0, 0, 0.6), 4.0)
	_root.draw_line(Vector2(c.x - r * 0.7, gy), Vector2(c.x + r * 0.7, gy), mag, 2.0)
	# ölçek noktaları
	for k in [-2, -1, 1, 2]:
		_root.draw_circle(Vector2(c.x + k * r * 0.375, c.y + r * 0.86), 2.0, Color(1, 1, 1, 0.7))
		_root.draw_circle(Vector2(c.x + r * 0.86, c.y + k * r * 0.375), 2.0, Color(1, 1, 1, 0.7))
	_text_c(Vector2(c.x, c.y - r - 6.0), "ILS %s  ·  %.1f km" % [ils["name"], float(ils["dist"]) / 1000.0], 11, mag, _font_bold)


## Kokpit HUD'unda ILS: ekran ortasında yön / süzülüş iğneleri (yeşil HUD rengi).
func _hud_ils(c: Vector2) -> void:
	if vessel.radar_altitude() < 3.0:
		return
	var ils := Ils.info(vessel)
	if ils.is_empty():
		return
	var r := 70.0
	var lx := c.x - clampf(float(ils["loc"]) / 2.5, -1.0, 1.0) * r
	var gy := c.y + clampf(float(ils["gs"]) / 0.7, -1.0, 1.0) * r
	_root.draw_line(Vector2(lx, c.y - r), Vector2(lx, c.y + r), Color(HUD_COLOR, 0.8), 1.5)
	_root.draw_line(Vector2(c.x - r, gy), Vector2(c.x + r, gy), Color(HUD_COLOR, 0.8), 1.5)
	_text_c(Vector2(c.x, c.y + r + 18.0), "ILS %s  %.1f km" % [ils["name"], float(ils["dist"]) / 1000.0], 13, HUD_COLOR, _font_bold)
