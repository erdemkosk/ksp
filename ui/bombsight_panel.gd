class_name BombsightPanel
extends Control
## Bombacı kamerası (Ğ): uçağın altından aşağı bakan dar açılı kamera — sağ altta kare ekran.
## Üstünde: nişan artısı, bombanın şimdi bırakılsa düşeceği yer (CCIP, sarı elmas), yer
## hedefleri (kırmızı), GPS hedefi (altın artı) ve CCIP'in hedefe uzaklığı / bırakmaya kalan süre.
## Tekerlek: yakınlaştır.

const SIDE := 360.0
const ZOOMS := [32.0, 18.0, 9.0]

var main: Node
var open := false
var _vp: SubViewport
var _cam: Camera3D
var _img: TextureRect
var _overlay: Control
var _zoom := 1
var _ccip: Variant = null
var _ccip_t := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = Vector2(SIDE, SIDE)
	visible = false
	_vp = SubViewport.new()
	_vp.size = Vector2i(480, 480)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = ZOOMS[_zoom]
	_cam.far = 30000.0
	_vp.add_child(_cam)
	_img = TextureRect.new()
	_img.texture = _vp.get_texture()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_font = UiTheme.get_theme().default_font
	(func() -> void: _vp.world_3d = get_viewport().world_3d).call_deferred()


func toggle() -> void:
	open = not open
	visible = open
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("bombsight"):
		toggle()
		get_viewport().set_input_as_handled()
	elif open and event is InputEventMouseButton and event.pressed and Rect2(global_position, size).has_point(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = mini(_zoom + 1, ZOOMS.size() - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxi(_zoom - 1, 0)
		_cam.fov = ZOOMS[_zoom]


func _process(delta: float) -> void:
	if not open or not is_instance_valid(main) or not is_instance_valid(main.vessel):
		return
	var vs := get_viewport_rect().size
	position = Vector2(vs.x - SIDE - 20.0, vs.y - SIDE - 220.0)
	var v: Vessel = main.vessel
	var up := Planet.up_at(v.com_global())
	var pos := v.com_global() - v.up() * 2.0
	var fwd := v.forward() - up * v.forward().dot(up)
	if fwd.length() < 0.1:
		fwd = v.global_basis.z
	_cam.global_position = pos
	_cam.look_at(pos - up * 100.0, fwd.normalized())
	_ccip_t -= delta
	if _ccip_t <= 0.0:
		_ccip_t = 0.1
		_ccip = Bomb.simulate_impact(v.get_world_3d().direct_space_state, v.com_global() - v.up() * 0.8, v.linear_velocity, 60.0)
	_overlay.queue_redraw()


func _to_panel(world: Vector3) -> Variant:
	if _cam.is_position_behind(world):
		return null
	var p := _cam.unproject_position(world) / Vector2(_vp.size) * size
	return p if Rect2(Vector2.ZERO, size).has_point(p) else null


func _draw_overlay() -> void:
	var s := size
	var green := Color(0.4, 1.0, 0.6)
	var gold := Color(1.0, 0.85, 0.2)
	var red := Color(1.0, 0.35, 0.3)
	_overlay.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.35), false, 2.0)
	var c := s * 0.5
	_overlay.draw_line(c - Vector2(30, 0), c - Vector2(8, 0), green, 1.5)
	_overlay.draw_line(c + Vector2(8, 0), c + Vector2(30, 0), green, 1.5)
	_overlay.draw_line(c - Vector2(0, 30), c - Vector2(0, 8), green, 1.5)
	_overlay.draw_line(c + Vector2(0, 8), c + Vector2(0, 30), green, 1.5)
	var v: Vessel = main.vessel
	if not is_instance_valid(v):
		return
	# yer hedefleri
	for n in v.get_parent().get_children():
		if n is GroundTarget and not n.destroyed and not n.has_meta("hidden"):
			var gp: Variant = _to_panel(n.global_position)
			if gp != null:
				_overlay.draw_rect(Rect2(gp - Vector2(5, 5), Vector2(10, 10)), red, false, 1.5)
	var gps := v.strike_world()
	if gps != Vector3.INF:
		var sp: Variant = _to_panel(gps)
		if sp != null:
			_overlay.draw_line(sp - Vector2(10, 0), sp + Vector2(10, 0), gold, 2.0)
			_overlay.draw_line(sp - Vector2(0, 10), sp + Vector2(0, 10), gold, 2.0)
	var info := "CCIP —"
	if _ccip != null:
		var ip: Variant = _to_panel(_ccip)
		if ip != null:
			var d := 9.0
			_overlay.draw_polyline(PackedVector2Array([ip + Vector2(0, -d), ip + Vector2(d, 0), ip + Vector2(0, d), ip + Vector2(-d, 0), ip + Vector2(0, -d)]), gold, 2.0)
		# en yakın hedefe uzaklık ve bırakmaya kalan süre (yatay hızla)
		var best := INF
		var goal: Variant = null
		for n in v.get_parent().get_children():
			if n is GroundTarget and not n.destroyed and not n.has_meta("hidden"):
				var dd: float = n.global_position.distance_to(_ccip)
				if dd < best:
					best = dd
					goal = n.global_position
		if gps != Vector3.INF and gps.distance_to(_ccip) < best:
			best = gps.distance_to(_ccip)
			goal = gps
		if goal != null:
			var up := Planet.up_at(v.com_global())
			var hv := v.linear_velocity - up * v.linear_velocity.dot(up)
			var to: Vector3 = (goal as Vector3) - (_ccip as Vector3)
			var ahead := to.dot(hv.normalized()) if hv.length() > 1.0 else 0.0
			var tt := ahead / maxf(hv.length(), 1.0)
			info = "HEDEF %d m  ·  bırakmaya %s" % [best, ("%.1f sn" % tt) if tt > 0.0 else "GEÇTİ"]
			if best < 40.0:
				info = "BIRAK!  (%d m)" % best
	_overlay.draw_rect(Rect2(0, s.y - 26, s.x, 26), Color(0, 0, 0, 0.6))
	_overlay.draw_string(_font, Vector2(8, s.y - 8), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gold)
	_overlay.draw_string(_font, Vector2(8, 18), "BOMBACI KAMERASI (Ğ)  ·  x%d" % [_zoom + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, green)
