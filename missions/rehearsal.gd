class_name Rehearsal
extends Node
## Görev provası: görev kartının rotası, saati ve havası; düşman yok, risk yok (test uçuşu).
## Üsten kalkılır, hedef bölgesi (target_xz) işaret sütunu ve halkayla gösterilir, süre sayılır.
## Hedefe varış süresi, oradaki yakıt ve alçak giriş irtifası Game.last_result'a yazılır;
## uçuş sonu raporundaki tasarım değerlendirmesi bunları kullanır. Hangar'a dönünce hazırlık sürer.

const ARRIVE_R := 2500.0      ## hedef bölgesine varış yarıçapı (m)
const HOME_R := 3000.0

var main: Node
var card := {}
var elapsed := 0.0
var t_target := -1.0
var t_home := -1.0
var fuel_at_target := -1.0
var _target := Vector2.ZERO
var _base := Vector2.ZERO
var _limit := 0.0
var _agl_sum := 0.0
var _agl_n := 0
var _ui: Control
var _font: SystemFont
var _bold: SystemFont
var _beam: Node3D


## Prova açık mı (main: düşman filosu / ortam hava trafiği kurulmaz).
static func active() -> bool:
	# yalnız görevsiz test uçuşunda (gerçek görev hiçbir zaman prova olmaz)
	return (Game.rehearsal and Game.test_flight and Game.mission == "") or Game.args.has("rehearsaldemo")


## main._ready: prova ise yöneticiyi ekle.
static func attach(m: Node) -> Rehearsal:
	if not active():
		return null
	if Game.args.has("rehearsaldemo"):
		Game.test_flight = true
		if Game.mission_card.is_empty():
			Game.mission_card = MissionCheck.sample_card()
	var r := Rehearsal.new()
	r.name = "Rehearsal"
	r.main = m
	r.card = Game.mission_card
	m.add_child(r)
	return r


func _ready() -> void:
	_target = MissionCheck.target_xz(card)
	_base = MissionCheck.base_xz(card)
	if _target == Vector2.INF:   # kartta hedef yoksa kuzeye menzil kadar
		_target = _base + Vector2(0, -maxf(MissionCheck.one_way_km(card), 10.0) * 1000.0)
	_limit = float(card.get("time_limit_s", 0.0))
	# hava ve saat: kartın koşulları, sabit (dinamik hava kapalı)
	Weather.set_dynamic(false)
	var wp := MissionCheck.weather_preset(card.get("weather", ""))
	if wp >= 0:
		Weather.set_preset(wp, true)
	if card.has("hour"):
		Weather.clock = float(card["hour"])
	elif bool(card.get("night", false)):
		Weather.clock = 23.5
	# üs ana meydan değilse üssün üstünde havada başla
	if _base.length() > HOME_R:
		main.spawn_in_air(1200.0, _base.x, _base.y)
	_build_marker()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)
	_write_result()
	(func() -> void:
		if is_instance_valid(main.hud):
			main.hud.show_message("GÖREV PROVASI: %s — düşman yok, risk yok. Hedef işaretli, süre sayılıyor." % String(card.get("title", "")), 7.0)).call_deferred()


func _build_marker() -> void:
	var gh := MissionManager.ground_height(_target.x, _target.y)
	var pos := MissionManager.world_point(_target.x, _target.y, gh)
	_beam = Node3D.new()
	main.world.add_child(_beam)
	_beam.global_position = pos
	_beam.global_basis = Planet.local_basis(pos)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 18.0
	cyl.bottom_radius = 18.0
	cyl.height = 1500.0
	col.mesh = cyl
	col.material_override = mat
	col.position = Vector3(0, 750.0, 0)
	_beam.add_child(col)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = ARRIVE_R - 25.0
	t.outer_radius = ARRIVE_R
	t.rings = 128
	ring.mesh = t
	ring.material_override = mat
	ring.position = Vector3(0, 30.0, 0)
	_beam.add_child(ring)


func _physics_process(delta: float) -> void:
	var v: Vessel = main.vessel
	if not is_instance_valid(v):
		return
	elapsed += delta
	var tp := _surface_point(_target)
	var d := _horiz(v, tp)
	if t_target < 0.0:
		# giriş: hedefe son 15 km'de yerden yükseklik ortalaması (alçak giriş = radardan saklanma)
		if d < 15000.0 and v.radar_altitude() > 5.0:
			_agl_sum += v.radar_altitude()
			_agl_n += 1
		if d < ARRIVE_R:
			t_target = elapsed
			fuel_at_target = v.fuel_amount()
			print("PROVA: hedef bölgesi %.0f sn, yakıt %.0f kg" % [t_target, fuel_at_target])
			var late := _limit > 0.0 and t_target > _limit
			main.hud.show_message("Hedef bölgesi: %s%s — üsse dön" % [MissionCheck.dur(t_target), ("  (süre %s AŞILDI)" % MissionCheck.dur(_limit)) if late else ""], 6.0)
			_write_result()
	elif t_home < 0.0 and _horiz(v, _surface_point(_base)) < HOME_R and v.ground_speed() < 3.0 and v.radar_altitude() < 6.0:
		t_home = elapsed
		main.hud.show_message("Prova tamam: üsse dönüldü (%s). Uçuşu bitirip Hangar'a dön." % MissionCheck.dur(t_home), 6.0)
		_write_result()


func _process(_delta: float) -> void:
	if _ui:
		_ui.queue_redraw()


func _surface_point(xz: Vector2) -> Vector3:
	return MissionManager.world_point(xz.x, xz.y, MissionManager.ground_height(xz.x, xz.y))


func _horiz(v: Vessel, p: Vector3) -> float:
	var d := v.com_global() - p
	var up := Planet.up_at(p)
	return (d - up * d.dot(up)).length()


## Sonuç (tasarım değerlendirmesi): eksikleri main uçuş sonunda tamamlar (DesignDebrief.fill_result).
func _write_result() -> void:
	var r := Game.last_result
	r["card"] = card
	r["rehearsal"] = true
	r["time_s"] = elapsed
	r["success"] = t_target >= 0.0 and (_limit <= 0.0 or t_target <= _limit)
	if t_target >= 0.0:
		r["time_to_target_s"] = t_target
		r["fuel_at_target_kg"] = fuel_at_target
	if _agl_n > 0:
		r["ingress_agl_avg"] = _agl_sum / _agl_n
	if t_home >= 0.0:
		r["time_home_s"] = t_home
	r["kills"] = 0
	r["targets_destroyed"] = 0
	r["detected_by"] = []
	Game.last_result = r


func _exit_tree() -> void:
	_write_result()


func _draw_ui() -> void:
	var v: Vessel = main.vessel
	var cam: Camera3D = main.camera
	var x := 330.0 if Hud.panels_open else 18.0
	var y := 68.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.7)
	sb.border_color = Color(1.0, 0.65, 0.2, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(8)
	_ui.draw_style_box(sb, Rect2(x, y, 330, 96))
	var over := _limit > 0.0 and (t_target if t_target >= 0.0 else elapsed) > _limit
	var tl := ("  /  %s" % _clock(_limit)) if _limit > 0.0 else ""
	_text(Vector2(x + 12, y + 20), "PROVA · %s" % String(card.get("title", "")), 13, Color(1.0, 0.72, 0.3), _bold)
	_text(Vector2(x + 12, y + 46), "%s%s" % [_clock(elapsed), tl], 22, Color(1.0, 0.45, 0.4) if over else Color(0.92, 0.94, 0.96), _bold)
	var line := ""
	var nav := _surface_point(_target)
	var label := "HEDEF"
	if t_target >= 0.0:
		nav = _surface_point(_base)
		label = "ÜS"
		line = "hedefe %s%s  ·  üsse dön" % [MissionCheck.dur(t_target), " (geç)" if _limit > 0.0 and t_target > _limit else ""]
		if t_home >= 0.0:
			line = "hedef %s  ·  dönüş %s  ✓" % [MissionCheck.dur(t_target), MissionCheck.dur(t_home)]
	if is_instance_valid(v):
		var dk := _horiz(v, nav) / 1000.0
		if line == "":
			line = "hedef bölgesi %.1f km" % dk
		else:
			line += "  %.1f km" % dk
		_text(Vector2(x + 12, y + 72), line, 13, Color(0.85, 0.88, 0.92), _font)
		_text(Vector2(x + 12, y + 90), "yakıt %d kg  ·  düşman yok, risk yok" % v.fuel_amount(), 12, Color(0.7, 0.75, 0.8), _font)
	# yön işareti
	if not is_instance_valid(cam):
		return
	var p := nav + Planet.up_at(nav) * 200.0
	var d := p.distance_to(cam.global_position)
	var txt := "%s  %s" % [label, ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % d)]
	var col := Color(1.0, 0.65, 0.2)
	var size := _ui.size
	if not cam.is_position_behind(p):
		var sp := cam.unproject_position(p)
		if Rect2(Vector2.ZERO, size).grow(-30).has_point(sp):
			var r := 11.0
			_ui.draw_polyline(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0), sp + Vector2(0, -r)]), col, 2.0, true)
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			_text(sp + Vector2(-w * 0.5, -18), txt, 13, col, _bold)
			return
	var local := cam.global_basis.inverse() * (p - cam.global_position)
	var dir := Vector2(local.x, -local.y).normalized()
	var c := size * 0.5
	var pos := c + dir * (minf(c.x, c.y) - 90.0)
	var n := dir.orthogonal()
	_ui.draw_colored_polygon(PackedVector2Array([pos + dir * 18, pos + n * 10, pos - n * 10]), col)
	var w2 := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(pos - dir * 26 + Vector2(-w2 * 0.5, 5), txt, 13, col, _bold)


func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _text(pos: Vector2, text: String, sz: int, col: Color, font: Font) -> void:
	_ui.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.6))
	_ui.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
