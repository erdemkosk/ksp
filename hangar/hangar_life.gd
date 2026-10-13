class_name HangarLife
extends Node3D
## Canlı hangar: uçağın çevresinde yürüyen, durup uçağa bakan teknisyenler; alet arabası ve iş
## merdiveni (uçağın boyuna göre yerleşir). F12: fotoğraf — arayüz gizlenir, user://photos/'a PNG.
## Tasarıma ve kayda dokunmaz.

const TECHS := 3
const WALK_SPEED := 1.3

var hangar: Node                       ## hangar.gd (_preview, _craft_root, _flash)
var _techs: Array[Dictionary] = []     ## {model, pos, target, wait, phase, facing}
var _center := Vector3.ZERO
var _radius := 9.0
var _fit_t := 0.0
var _cart: Node3D
var _ladder: Node3D


func _ready() -> void:
	for i in TECHS:
		var m := PilotModel.new()
		m.name = "Tech%d" % i
		m.pilot_name = "Teknisyen"
		add_child(m)
		var a := TAU * i / TECHS + randf_range(-0.4, 0.4)
		var p := Vector3(cos(a), 0.0, sin(a)) * _radius
		_techs.append({"model": m, "pos": p, "target": p, "wait": randf_range(0.5, 4.0), "phase": randf() * TAU, "facing": 0.0, "angle": a})
	_cart = _build_cart()
	add_child(_cart)
	_ladder = _build_ladder()
	add_child(_ladder)


func _process(delta: float) -> void:
	_fit_t -= delta
	if _fit_t <= 0.0:
		_fit_t = 1.0
		_fit()
	for t in _techs:
		_step(t, delta)


## Uçağın zemindeki izi: merkez (ağırlık merkezinin altı) ve çevresinde yürünecek halka.
func _fit() -> void:
	var v: Vessel = hangar.get("_preview")
	var root: Node3D = hangar.get("_craft_root")
	if not is_instance_valid(v) or v.parts.is_empty() or root == null:
		return
	var ext := 2.0
	for p in v.parts:
		ext = maxf(ext, Vector2(p.position.x, p.position.z - v.com_local.z).length() + p.size.length() * 0.5)
	var c := root.global_transform * v.com_local
	_center = Vector3(c.x, 0.0, c.z)
	_radius = clampf(ext * 0.75 + 2.5, 5.0, 40.0)
	# alet arabası sağ arkada, merdiven sol önde (kokpite yakın)
	_cart.position = _center + Vector3(_radius * 0.55, 0.0, _radius * 0.35)
	_cart.rotation.y = 0.6
	_ladder.position = _center + Vector3(-_radius * 0.45, 0.0, -_radius * 0.3)
	_ladder.rotation.y = -0.4


func _step(t: Dictionary, delta: float) -> void:
	var m: PilotModel = t["model"]
	var pos: Vector3 = t["pos"]
	var wait: float = t["wait"]
	if wait > 0.0:
		# durup uçağa bakar
		t["wait"] = wait - delta
		# merkeze (uçağa) dön: yön -pos, model ileri -Z → açı atan2(pos.x, pos.z)
		t["facing"] = lerp_angle(float(t["facing"]), atan2(pos.x, pos.z), 1.0 - exp(-3.0 * delta))
		m.pose_standing()
		if float(t["wait"]) <= 0.0:
			# yeni durak: halkada 40–120° ötede
			var a: float = float(t["angle"]) + randf_range(0.7, 2.1) * (1.0 if randf() < 0.6 else -1.0)
			t["angle"] = a
			t["target"] = Vector3(cos(a), 0.0, sin(a)) * _radius * randf_range(0.85, 1.05)
	else:
		var target: Vector3 = t["target"]
		var d := target - pos
		if d.length() < 0.2:
			t["wait"] = randf_range(2.0, 6.0)
		else:
			# halka üzerinde yürü (uçağın içinden geçmesin): hedefe yaklaşırken halkaya geri çekil
			var step := d.normalized() * WALK_SPEED * delta
			var np := pos + step
			var r := Vector2(np.x, np.z).length()
			if r < _radius * 0.8:
				np = np * (_radius * 0.8 / maxf(r, 0.01))
			t["pos"] = np
			t["facing"] = lerp_angle(float(t["facing"]), atan2(-d.x, -d.z), 1.0 - exp(-6.0 * delta))
			t["phase"] = float(t["phase"]) + WALK_SPEED * delta * 2.4
			m.pose_walk(float(t["phase"]), 1.0, false, 0.0, 0.0, 0.0, sin(float(t["phase"]) * 0.3))
	m.position = _center + (t["pos"] as Vector3)
	m.rotation.y = float(t["facing"])


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, metal := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	m.metallic = metal
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


## Kırmızı alet arabası: iki çekmeceli gövde, üstünde alet tablası, dört tekerlek.
func _build_cart() -> Node3D:
	var n := Node3D.new()
	var red := Color(0.7, 0.1, 0.08)
	_box(n, Vector3(0.9, 0.7, 0.5), Vector3(0, 0.5, 0), red)
	_box(n, Vector3(0.86, 0.02, 0.46), Vector3(0, 0.66, 0.0), Color(0.15, 0.15, 0.16))
	for y in [0.42, 0.6]:
		_box(n, Vector3(0.8, 0.12, 0.02), Vector3(0, y, 0.255), red.darkened(0.25))
		_box(n, Vector3(0.3, 0.02, 0.03), Vector3(0, y, 0.27), Color(0.75, 0.75, 0.75), 0.9)
	_box(n, Vector3(0.94, 0.04, 0.54), Vector3(0, 0.87, 0), Color(0.2, 0.2, 0.22), 0.6)
	_box(n, Vector3(0.25, 0.06, 0.08), Vector3(-0.2, 0.92, 0.05), Color(0.8, 0.6, 0.1))
	_box(n, Vector3(0.05, 0.05, 0.3), Vector3(0.25, 0.92, -0.05), Color(0.6, 0.6, 0.62), 0.9)
	for sx in [-0.38, 0.38]:
		for sz in [-0.18, 0.18]:
			_box(n, Vector3(0.06, 0.1, 0.1), Vector3(sx, 0.05, sz), Color(0.08, 0.08, 0.08))
	return n


## Sarı iş merdiveni: iki ayak, beş basamak, üstte platform ve korkuluk.
func _build_ladder() -> Node3D:
	var n := Node3D.new()
	var yel := Color(0.85, 0.7, 0.1)
	for sx in [-0.3, 0.3]:
		_box(n, Vector3(0.06, 1.6, 0.06), Vector3(sx, 0.8, 0.3), yel)
		_box(n, Vector3(0.06, 1.8, 0.06), Vector3(sx, 0.9, -0.5), yel)
		_box(n, Vector3(0.04, 0.8, 0.04), Vector3(sx, 2.0, -0.5), yel)
	for i in 5:
		var y := 0.3 + i * 0.3
		_box(n, Vector3(0.6, 0.04, 0.18), Vector3(0, y, 0.3 - i * 0.16), Color(0.3, 0.3, 0.32), 0.7)
	_box(n, Vector3(0.66, 0.05, 0.45), Vector3(0, 1.62, -0.45), Color(0.3, 0.3, 0.32), 0.7)
	_box(n, Vector3(0.66, 0.04, 0.04), Vector3(0, 2.38, -0.5), yel)
	return n


# ------------------------------------------------------------------ fotoğraf

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F12:
		_photo()
		get_viewport().set_input_as_handled()


## Arayüz katmanlarını gizle, bir kare bekle, PNG kaydet, geri göster.
func _photo() -> void:
	var layers: Array[CanvasLayer] = []
	for c in hangar.get_children():
		var cl := c as CanvasLayer
		if cl != null and cl.visible:
			layers.append(cl)
			cl.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://photos")
	var path := "user://photos/hangar_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	get_viewport().get_texture().get_image().save_png(path)
	for c in layers:
		c.visible = true
	Sfx.play_ui("switch_2.ogg", -6.0, 1.6)
	hangar.call("_flash", "Fotoğraf kaydedildi: " + ProjectSettings.globalize_path(path))
