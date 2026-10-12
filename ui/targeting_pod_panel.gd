class_name TargetingPodPanel
extends Control
## Hedefleme podu paneli (F8 aç/kapa). Podun gözünden canlı görüntü ve nişan sembolleri.
## Kumanda: Numpad 8/2/4/6 kaydır · +/- yakınlaştır · 5 kilit · 0 mod · . sıfırla.
## İmleç serbestken: görüntüde sürükle = kaydır, tekerlek = yakınlaştır, tık = oraya kilitlen.
## Açıkken savaş paneli kenara katlanır; kapanınca geri gelir. Ana ekranda podun baktığı
## nokta elmas işaretle gösterilir.

const W := 452.0
const IMG := Vector2(432, 300)
const GREEN := Color(0.55, 1.0, 0.65)
const AMBER := Color(1.0, 0.75, 0.25)

var main: Node
var open := false

var _vp: SubViewport
var _cam: Camera3D
var _img: TextureRect
var _mat: ShaderMaterial
var _overlay: Control
var _marker: Control
var _font := SystemFont.new()
var _bold := SystemFont.new()
var _drag := false
var _t := 0.0
var _combat_was_collapsed := false


func _ready() -> void:
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(IMG.x), int(IMG.y))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.world_3d = get_viewport().world_3d
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.near = 0.5
	_cam.far = 60000.0
	_cam.current = true
	_vp.add_child(_cam)
	_img = TextureRect.new()
	_img.texture = _vp.get_texture()
	_img.position = Vector2(10, 34)
	_img.size = IMG
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://ui/pod_view.gdshader")
	_img.material = _mat
	add_child(_img)
	_overlay = Control.new()
	_overlay.position = _img.position
	_overlay.size = IMG
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.clip_contents = true
	_overlay.draw.connect(_draw_symbology)
	add_child(_overlay)
	# ana ekranda podun baktığı nokta
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.top_level = true
	add_child(_marker)
	size = Vector2(W, 34 + IMG.y + 70)


func pod() -> TargetingPodModule:
	if main == null or not is_instance_valid(main.vessel):
		return null
	for m in main.vessel.modules:
		if m is TargetingPodModule:
			return m
	return null


func toggle() -> void:
	open = not open
	var cp: CombatPanel = main.hud.combat_panel if main and main.hud else null
	if cp:
		if open:
			_combat_was_collapsed = cp.collapsed
			cp.collapsed = true
		else:
			cp.collapsed = _combat_was_collapsed
	Sfx.click()


func _process(delta: float) -> void:
	_t += delta
	var p := pod()
	var can: bool = p != null and main.vessel.has_pilot() and not main.camera.is_eva()
	if not can and open:
		toggle()
	visible = can and open
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	_marker.visible = can
	_marker.queue_redraw()
	if open and main.hud and main.hud.combat_panel:
		main.hud.combat_panel.collapsed = true       # pod açıkken savaş paneli kenarda
	if not visible:
		return
	position = Vector2(14, 64)
	# klavye kaydırma (numpad), basılı tutuldukça
	var dx := float(Input.is_physical_key_pressed(KEY_KP_6)) - float(Input.is_physical_key_pressed(KEY_KP_4))
	var dy := float(Input.is_physical_key_pressed(KEY_KP_8)) - float(Input.is_physical_key_pressed(KEY_KP_2))
	p.slew(dx, dy, delta)
	# kamera: podun gözü, bakış yönü, yakınlaştırma
	var eye := p.eye()
	var dir := p.look_dir()
	var up: Vector3 = main.vessel.global_basis.y
	if absf(dir.dot(up)) > 0.98:
		up = main.vessel.global_basis.z
	_cam.global_transform = Transform3D(Basis.looking_at(dir, up), eye)
	_cam.fov = p.fov()
	_mat.set_shader_parameter("mode", p.mode)
	_mat.set_shader_parameter("time", _t)
	_overlay.queue_redraw()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pod_toggle"):
		if pod() != null:
			toggle()
			get_viewport().set_input_as_handled()
		return
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var p := pod()
	match event.physical_keycode:
		KEY_KP_ADD:
			p.zoom = mini(p.zoom + 1, TargetingPodModule.ZOOMS.size() - 1)
		KEY_KP_SUBTRACT:
			p.zoom = maxi(p.zoom - 1, 0)
		KEY_KP_5:
			p.toggle_lock()
			Sfx.play_ui("lock_tone.ogg", -10.0, 1.8 if p.tracking else 1.2)
		KEY_KP_0:
			p.mode = (p.mode + 1) % TargetingPodModule.MODES.size()
		KEY_KP_PERIOD:
			p.tracking = false
			p.track_node = null
			p.az = 0.0
			p.el = deg_to_rad(-12.0)
		_:
			return
	Sfx.click()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var p := pod()
	if p == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var in_img := Rect2(_img.position, IMG).has_point(event.position)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and in_img:
			p.zoom = mini(p.zoom + 1, TargetingPodModule.ZOOMS.size() - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and in_img:
			p.zoom = maxi(p.zoom - 1, 0)
		elif event.button_index == MOUSE_BUTTON_LEFT and in_img:
			# tıklanan yöne bak ve kilitlen
			var local: Vector2 = (event.position - _img.position) / IMG * Vector2(_vp.size)
			var wdir := _cam.project_ray_normal(local)
			var lv: Vector3 = main.vessel.global_basis.inverse() * wdir
			p.tracking = false
			p.track_node = null
			p.az = clampf(atan2(lv.x, -lv.z), -TargetingPodModule.AZ_LIMIT, TargetingPodModule.AZ_LIMIT)
			p.el = clampf(atan2(lv.y, Vector2(lv.x, lv.z).length()), TargetingPodModule.EL_MIN, TargetingPodModule.EL_MAX)
			p.toggle_lock()
			Sfx.play_ui("lock_tone.ogg", -10.0, 1.8)
		elif event.button_index == MOUSE_BUTTON_RIGHT and in_img:
			_drag = true
		elif _buttons_hit(event.position, p):
			Sfx.click()
		accept_event()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_drag = false
	elif event is InputEventMouseMotion and _drag:
		var k := deg_to_rad(p.fov()) / IMG.x
		p.tracking = false
		p.track_node = null
		p.az = clampf(p.az + event.relative.x * k, -TargetingPodModule.AZ_LIMIT, TargetingPodModule.AZ_LIMIT)
		p.el = clampf(p.el - event.relative.y * k, TargetingPodModule.EL_MIN, TargetingPodModule.EL_MAX)
		accept_event()


## Alt şerit düğmeleri: MOD · YAKIN − · YAKIN + · KİLİT · SIFIRLA
func _button_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var y := 34 + IMG.y + 36
	var w := (W - 20 - 4 * 6) / 5.0
	for i in 5:
		out.append(Rect2(10 + i * (w + 6), y, w, 26))
	return out


func _buttons_hit(pos: Vector2, p: TargetingPodModule) -> bool:
	var r := _button_rects()
	for i in r.size():
		if r[i].has_point(pos):
			match i:
				0: p.mode = (p.mode + 1) % TargetingPodModule.MODES.size()
				1: p.zoom = maxi(p.zoom - 1, 0)
				2: p.zoom = mini(p.zoom + 1, TargetingPodModule.ZOOMS.size() - 1)
				3: p.toggle_lock()
				4:
					p.tracking = false
					p.track_node = null
					p.az = 0.0
					p.el = deg_to_rad(-12.0)
			return true
	return false


# ------------------------------------------------------------------ çizim

func _draw() -> void:
	var p := pod()
	if p == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.92)
	sb.border_color = Color(GREEN, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	draw_string(_bold, Vector2(12, 22), "HEDEFLEME PODU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GREEN)
	var right := "%s   ·   %s   ·   F8 kapat" % [TargetingPodModule.MODES[p.mode], ["GENİŞ", "ORTA", "DAR", "ÇOK DAR"][p.zoom]]
	var rw := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(_font, Vector2(W - rw - 12, 21), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.8, 0.8))
	# bilgi satırı
	var y := 34 + IMG.y + 20
	var rng := p.range_m()
	var state := "KİLİT" if p.tracking else ("SINIR!" if p.gimbal_limit else "SERBEST")
	var info := "AZ %+04d°   EL %+03d°   MENZİL %s   %s" % [roundi(rad_to_deg(p.az)), roundi(rad_to_deg(p.el)),
		("%.1f km" % (rng / 1000.0)) if rng > 0.0 else "—", state]
	draw_string(_bold, Vector2(12, y), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AMBER if p.tracking else GREEN)
	var labels := ["MOD", "YAKIN −", "YAKIN +", "KİLİT" if not p.tracking else "BIRAK", "SIFIRLA"]
	var keys := ["0", "−", "+", "5", "."]
	var rs := _button_rects()
	for i in rs.size():
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.1, 0.13, 0.15) if not (i == 3 and p.tracking) else Color(0.45, 0.32, 0.05)
		bsb.set_corner_radius_all(5)
		draw_style_box(bsb, rs[i])
		var t := "%s  [%s]" % [labels[i], keys[i]]
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, rs[i].position + Vector2((rs[i].size.x - tw) * 0.5, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.93, 0.95))


func _draw_symbology() -> void:
	var p := pod()
	if p == null:
		return
	var s := IMG
	var c := s * 0.5
	var col := Color(1, 1, 1, 0.9) if p.mode != 3 else Color(0.8, 1.0, 0.8, 0.9)
	# ısı kaynakları (IR modlarda): motorlar, araçlar, yanan hedefler parlak lekeler
	if p.mode == 1 or p.mode == 2:
		var hot := Color(1, 1, 1, 0.85) if p.mode == 1 else Color(0, 0, 0, 0.85)
		for n in main.vessel.get_parent().get_children():
			var hp := Vector3.INF
			var heat := 0.0
			if n is Vessel and not n.parts.is_empty():
				hp = n.heat_position()
				heat = 1.0
			elif n is GroundTarget:
				hp = n.global_position + Planet.up_at(n.global_position) * 1.2
				heat = 0.8 if n.destroyed else 0.5
			elif n is PilotCharacter:
				hp = n.global_position + Planet.up_at(n.global_position) * 1.0
				heat = 0.4
			if hp == Vector3.INF or _cam.is_position_behind(hp):
				continue
			var sp := _cam.unproject_position(hp) / Vector2(_vp.size) * s
			var d := _cam.global_position.distance_to(hp)
			var r := clampf(900.0 / maxf(d, 1.0) * (32.0 / p.fov()), 2.0, 40.0) * heat
			_overlay.draw_circle(sp, r, hot)
	# artı imleç ve köşe parantezleri
	var g := 14.0
	_overlay.draw_line(c - Vector2(60, 0), c - Vector2(g, 0), col, 1.5)
	_overlay.draw_line(c + Vector2(g, 0), c + Vector2(60, 0), col, 1.5)
	_overlay.draw_line(c - Vector2(0, 45), c - Vector2(0, g), col, 1.5)
	_overlay.draw_line(c + Vector2(0, g), c + Vector2(0, 45), col, 1.5)
	if p.tracking:
		var b := 22.0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var cp := c + Vector2(sx * b, sy * b)
				_overlay.draw_line(cp, cp - Vector2(sx * 8, 0), AMBER, 2.0)
				_overlay.draw_line(cp, cp - Vector2(0, sy * 8), AMBER, 2.0)
	# yön ölçeği (alt) ve kuzey oku (sağ üst)
	var az_x := c.x + p.az / TargetingPodModule.AZ_LIMIT * (s.x * 0.45)
	_overlay.draw_line(Vector2(s.x * 0.05, s.y - 14), Vector2(s.x * 0.95, s.y - 14), Color(col, 0.5), 1.0)
	_overlay.draw_colored_polygon(PackedVector2Array([Vector2(az_x, s.y - 18), Vector2(az_x - 5, s.y - 8), Vector2(az_x + 5, s.y - 8)]), col)
	var el_y := lerpf(s.y * 0.9, s.y * 0.1, (p.el - TargetingPodModule.EL_MIN) / (TargetingPodModule.EL_MAX - TargetingPodModule.EL_MIN))
	_overlay.draw_line(Vector2(14, s.y * 0.1), Vector2(14, s.y * 0.9), Color(col, 0.5), 1.0)
	_overlay.draw_colored_polygon(PackedVector2Array([Vector2(10, el_y - 5), Vector2(20, el_y), Vector2(10, el_y + 5)]), col)
	var fr := Planet.local_basis(_cam.global_position)
	var f := -_cam.global_basis.z
	var hdg := atan2(f.dot(fr.x), -f.dot(fr.z))
	var nc := Vector2(s.x - 26, 26)
	var nd := Vector2(sin(-hdg), -cos(-hdg))
	_overlay.draw_arc(nc, 13, 0, TAU, 20, Color(col, 0.5), 1.0)
	_overlay.draw_line(nc, nc + nd * 11, col, 2.0)
	_overlay.draw_string(_bold, nc + nd * 20 - Vector2(4, -4), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	# takip edilen nesnenin adı
	if p.tracking and is_instance_valid(p.track_node):
		var nm := ""
		if p.track_node is Vessel:
			nm = (p.track_node as Vessel).craft_name
		elif p.track_node is GroundTarget:
			nm = (p.track_node as GroundTarget).unit_name + (" (YOK EDİLDİ)" if p.track_node.destroyed else "")
		_overlay.draw_string(_bold, Vector2(12, 20), "TAKİP: " + nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, AMBER)


func _draw_marker() -> void:
	var p := pod()
	if p == null or main.camera == null:
		return
	var tp: Variant = p.target_point()
	if tp == null:
		tp = p.ground_point()
	if tp == null or main.camera.is_position_behind(tp):
		return
	var sp: Vector2 = main.camera.unproject_position(tp)
	var col := AMBER if p.tracking else Color(GREEN, 0.8)
	var r := 9.0
	_marker.draw_polyline(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0), sp + Vector2(0, -r)]), col, 2.0, true)
	_marker.draw_string(_bold, sp + Vector2(12, 4), "POD" + (" KİLİT" if p.tracking else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
