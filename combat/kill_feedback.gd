class_name KillFeedback
extends Node
## Oyuncunun vuruş hissi (main ekler; Damage.on_hit'i dinler):
##   • isabet işareti: vurulan noktanın etrafında 0.25 sn beyaz çarpı + kısa "tık"
##   • düşürme: kırmızı büyük çarpı, ekranın üstünde "DÜŞÜRÜLDÜ" şeridi ve sayaç, kısa ağır çekim
##   • düşen uçak alev + kara duman iziyle düşer; yere çarpınca büyük patlama, enkaz yerinde
##     iki dakika yanar ve tüter
##   • yer hedefi imhası: "HEDEF İMHA" şeridi
## "Kim vurdu" bilgisini Damage._notify hedefe damgalar (meta hit_by); düşürme, düşmanın
## pilotu / kokpiti gidince bu damgadan oyuncuya yazılır.

const MARK_TIME := 0.28
const BANNER_TIME := 2.4
const WRECK_TIME := 120.0

var main: Node
var kills := 0
var _layer: CanvasLayer
var _draw: Control
var _marks: Array[Dictionary] = []      ## {pos, t, kill}
var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
var _banner_col := Color(1.0, 0.3, 0.25)
var _falling: Array[Dictionary] = []    ## {v, trail}
var _scan_t := 0.0
var _tick_cd := 0.0
var _font: SystemFont


func _ready() -> void:
	Damage.on_hit = _on_hit
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_draw = Control.new()
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_layer.add_child(_draw)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_font.font_weight = 800


func _exit_tree() -> void:
	if Damage.on_hit == Callable(self, "_on_hit"):
		Damage.on_hit = Callable()


func _player() -> Vessel:
	return main.get("vessel") as Vessel if is_instance_valid(main) else null


func _on_hit(target: Node, pos: Vector3, shooter: Object) -> void:
	if shooter != _player() or target == shooter:
		return
	_marks.append({"pos": pos, "t": MARK_TIME, "kill": false})
	if _tick_cd <= 0.0:
		_tick_cd = 0.06
		Sfx.play_ui("switch_4.ogg", -9.0, randf_range(1.9, 2.2))


func _process(delta: float) -> void:
	_tick_cd -= delta
	_draw.size = _draw.get_viewport().get_visible_rect().size
	var real := delta / maxf(Engine.time_scale, 0.01)   # ağır çekimde işaretler normal hızda söner
	for m in _marks:
		m["t"] = float(m["t"]) - real
	_marks = _marks.filter(func(m: Dictionary) -> bool: return float(m["t"]) > 0.0)
	_banner_t -= real
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan()
	_update_falling()
	_draw.queue_redraw()


## Oyuncunun vurduğu ve artık uçamayan (pilotsuz / kokpitsiz / parçasız) düşmanları ve yok
## olan yer hedeflerini bul.
func _scan() -> void:
	var me := _player()
	if me == null or FloatingOrigin.world_root == null:
		return
	for n in FloatingOrigin.world_root.get_children():
		if n == me or n.has_meta("downed") or not n.has_meta("hit_by") or n.get_meta("hit_by") != me:
			continue
		if n is Vessel:
			var v: Vessel = n
			if v.parts.is_empty() or v.cockpit_part() == null or not v.has_pilot():
				_downed(v)
		elif n is GroundTarget and n.destroyed:
			n.set_meta("downed", true)
			_show_banner("HEDEF İMHA", _target_name(n), Color(1.0, 0.7, 0.25))
			_marks.append({"pos": (n as Node3D).global_position, "t": MARK_TIME * 3.0, "kill": true})


func _target_name(n: Node) -> String:
	var s := String(n.get("title")) if n.get("title") != null else ""
	return s if s != "" and s != "<null>" else String(n.name)


func _downed(v: Vessel) -> void:
	v.set_meta("downed", true)
	kills += 1
	_show_banner("DÜŞÜRÜLDÜ", "%s  ·  bu uçuşta %d" % [v.craft_name, kills], Color(1.0, 0.3, 0.25))
	_marks.append({"pos": v.com_global(), "t": MARK_TIME * 4.0, "kill": true})
	Sfx.play_ui("lock_tone.ogg", -8.0, 0.75)
	_slowmo()
	# alevler içinde düşüş: en büyük kalan parçaya yanma izi
	var trail: Node3D = null
	var big: Part = null
	for p in v.parts:
		if big == null or p.get_mass() > big.get_mass():
			big = p
	if big:
		trail = Effects.burning_trail()
		big.add_child(trail)
	var ids: Array = []
	for p in v.parts:
		ids.append(p.part_id)
	_falling.append({"v": v, "trail": trail, "ids": ids})


func _show_banner(title: String, sub: String, col: Color) -> void:
	_banner = title
	_banner_sub = sub
	_banner_col = col
	_banner_t = BANNER_TIME


## Kısa ağır çekim (zaman hızlandırma açıksa dokunma; testlerde kapalı).
func _slowmo() -> void:
	if not is_equal_approx(Engine.time_scale, 1.0) or Crew._testing():
		return
	Engine.time_scale = 0.35
	get_tree().create_timer(0.45, true, false, true).timeout.connect(func() -> void:
		if is_equal_approx(Engine.time_scale, 0.35):
			Engine.time_scale = 1.0)


## Düşenler yere değince: büyük patlama, yanma izi söner, yerde iki dakika tüten enkaz.
func _update_falling() -> void:
	var keep: Array[Dictionary] = []
	for f in _falling:
		var v: Vessel = f["v"]
		if not is_instance_valid(v) or v.parts.is_empty():
			continue
		var ground := v.radar_altitude()
		if ground > 4.0 and not (v.linear_velocity.length() < 12.0 and ground < 15.0):
			keep.append(f)
			continue
		var pos := v.com_global()
		var up := Planet.up_at(pos)
		Effects.explosion(FloatingOrigin.world_root, pos, up, 3.0)
		Sfx.explosion(pos, 2.5)
		var trail: Node3D = f["trail"]
		if is_instance_valid(trail):
			for c in trail.get_children():
				(c as GPUParticles3D).emitting = false
		_wreck(pos - up * maxf(ground, 0.0), up)
		# enkaz yerde: teknisyenler inceler, bilinmeyen bir parçanın Ar-Ge bedeli düşer
		var msg := Career.salvage_from(f.get("ids", []))
		if msg != "" and main.get("hud"):
			main.hud.show_message(msg, 4.0)
			_show_banner("ENKAZ İNCELENDİ", msg.trim_prefix("ENKAZ İNCELEMESİ: "), Color(0.45, 0.85, 1.0))
	_falling = keep


func _wreck(pos: Vector3, up: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Wreck"
	FloatingOrigin.world_root.add_child(root)
	root.global_position = pos
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	root.global_basis = Basis(x, up, x.cross(up).normalized())
	# yanık leke: yere yatık koyu disk
	var scorch := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 9.0
	cm.bottom_radius = 9.0
	cm.height = 0.05
	scorch.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.045, 0.04, 0.85)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 1.0
	scorch.material_override = sm
	scorch.position = Vector3(0, 0.15, 0)
	root.add_child(scorch)
	var smoke := Effects.smoke_column()
	smoke.scale = Vector3.ONE * 1.6
	root.add_child(smoke)
	var fire := Effects.burning_trail()
	fire.position = Vector3(0, 1.0, 0)
	fire.rotation_degrees = Vector3(-90, 0, 0)   # iz yönü (+z) yukarı: alev yukarı yalar
	root.add_child(fire)
	get_tree().create_timer(WRECK_TIME).timeout.connect(func() -> void:
		if is_instance_valid(root):
			smoke.emitting = false
			for c in fire.get_children():
				(c as GPUParticles3D).emitting = false
			get_tree().create_timer(10.0).timeout.connect(root.queue_free))


# ------------------------------------------------------------------ çizim

func _on_draw() -> void:
	var cam := _draw.get_viewport().get_camera_3d()
	if cam:
		for m in _marks:
			var p: Vector3 = m["pos"]
			if cam.is_position_behind(p):
				continue
			var sp := cam.unproject_position(p)
			var kill: bool = m["kill"]
			var a := clampf(float(m["t"]) / MARK_TIME, 0.0, 1.0)
			var col := Color(1.0, 0.25, 0.2, a) if kill else Color(1, 1, 1, a)
			var gap := 14.0 if kill else 7.0
			var ln := 16.0 if kill else 8.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var dn: Vector2 = d.normalized()
				_draw.draw_line(sp + dn * gap + Vector2(1, 1), sp + dn * (gap + ln) + Vector2(1, 1), Color(0, 0, 0, a * 0.6), 3.0 if kill else 2.0)
				_draw.draw_line(sp + dn * gap, sp + dn * (gap + ln), col, 3.0 if kill else 2.0)
	if _banner_t > 0.0:
		var a := clampf(_banner_t / 0.4, 0.0, 1.0) * clampf((BANNER_TIME - _banner_t) / 0.12 + 0.3, 0.0, 1.0)
		var vs := _draw.size
		var y := vs.y * 0.2
		var tw := _font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		var band := Rect2(Vector2(vs.x * 0.5 - tw * 0.5 - 40, y - 40), Vector2(tw + 80, 74))
		_draw.draw_rect(band, Color(0, 0, 0, 0.45 * a))
		_draw.draw_rect(Rect2(band.position, Vector2(band.size.x, 3)), Color(_banner_col, a))
		_draw.draw_rect(Rect2(band.position + Vector2(0, band.size.y - 3), Vector2(band.size.x, 3)), Color(_banner_col, a))
		_draw.draw_string(_font, Vector2(vs.x * 0.5 - tw * 0.5, y + 6), _banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(_banner_col, a))
		var sw := _font.get_string_size(_banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_draw.draw_string(_font, Vector2(vs.x * 0.5 - sw * 0.5, y + 27), _banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9 * a))
