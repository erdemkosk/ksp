class_name CockpitSwitch
extends Area3D
## Kokpitte fareyle tıklanabilen kumanda.
##   toggle  — kollu anahtar (açık/kapalı)
##   button  — ışıklı basmalı düğme: basınca gömülür, aktifken içi yanar
##   guarded — kırmızı kapaklı anahtar: ilk tık kapağı açar, ikinci tık anahtarı çalıştırır;
##             anahtar kapalıyken kapak birkaç saniye sonra kendiliğinden kapanır
##   handle / gear / eject — özel kollar
## Durumu `getter`dan okur, tıklanınca `action`ı çağırır.

const LAYER := 1 << 7   ## sadece kokpit etkileşim ışını bu katmanı tarar
const COVER_OPEN_DEG := -110.0

var label := ""
var kind := "toggle"
var getter: Callable
var action: Callable
## Kolun açık/kapalı açıları (yerel X ekseninde, derece)
var on_angle := -35.0
var off_angle := 35.0

var _lever: Node3D
var _cap: Node3D
var _lamp: MeshInstance3D
var _lamp_on: Material
var _lamp_off: Material
var _cover: Node3D
var _cover_open := false
var _cover_t := 0.0
var _cover_idle := 0.0
var _highlight: MeshInstance3D
var _angle := 0.0
var _press := 0.0


static func create(text: String, size: Vector3, state_getter: Callable, on_click: Callable) -> CockpitSwitch:
	var s := CockpitSwitch.new()
	s.label = text
	s.getter = state_getter
	s.action = on_click
	s.collision_layer = LAYER
	s.collision_mask = 0
	s.monitoring = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	s.add_child(cs)

	var hl := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = size * 1.15
	hl.mesh = hm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 1.0, 0.7, 0.18)
	mat.no_depth_test = true
	hl.material_override = mat
	hl.visible = false
	hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(hl)
	s._highlight = hl
	return s


## Kolu (dönen görsel) bağlar.
func set_lever(node: Node3D) -> void:
	_lever = node
	add_child(node)


## Basmalı düğmenin kapağı ve ışığı.
func set_button(cap: Node3D, lamp: MeshInstance3D, lit: Material, dark: Material) -> void:
	_cap = cap
	_lamp = lamp
	_lamp_on = lit
	_lamp_off = dark
	add_child(cap)


## Kapaklı anahtarın menteşeli kapağı.
func set_cover(cover: Node3D) -> void:
	_cover = cover
	add_child(cover)


func is_on() -> bool:
	return _owner_ok() and getter.is_valid() and bool(getter.call())


## Anahtarın sahibi kokpit modülü hâlâ bir uçağa bağlı mı (parça koptuysa / pilot öldüyse değil).
func _owner_ok() -> bool:
	if not getter.is_valid():
		return false
	var o: Object = getter.get_object()
	if o is PartModule:
		return is_instance_valid((o as PartModule).vessel)
	return true


func activate() -> void:
	if not _owner_ok():
		return
	_cover_idle = 0.0
	if _cover and not _cover_open:
		_cover_open = true
		Sfx.play_ui("switch_4.ogg", -8.0, 0.7)   # kapak menteşesi
		return
	Sfx.click()
	_press = 1.0
	if action.is_valid():
		action.call()


func set_highlight(on: bool) -> void:
	_highlight.visible = on


func tooltip() -> String:
	if _cover and not _cover_open:
		return "%s  ·  korumalı — kapağı açmak için tıkla" % label
	if kind == "button":
		return "%s  ·  %s" % [label, "AKTİF" if is_on() else "bas"]
	return "%s  ·  %s" % [label, "AÇIK" if is_on() else "KAPALI"]


func _process(delta: float) -> void:
	# yalnız kamera yakındayken (kokpit / yakın dış görünüm): yapay zekâ uçaklarının onlarca anahtarı boşuna çalışmasın
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_squared_to(global_position) > 1600.0:
		return
	var on := is_on()
	if _lever:
		var target := deg_to_rad(on_angle if on else off_angle)
		_angle = move_toward(_angle, target, delta * 8.0)
		_lever.rotation.x = _angle
	if _cap:
		_press = move_toward(_press, 0.0, delta * 6.0)
		_cap.position.y = -0.006 * _press
	if _lamp:
		_lamp.material_override = _lamp_on if on else _lamp_off
	if _cover:
		if _cover_open and not on:
			_cover_idle += delta
			if _cover_idle > 4.0:
				_cover_open = false
		_cover_t = move_toward(_cover_t, 1.0 if _cover_open else 0.0, delta * 5.0)
		_cover.rotation.x = deg_to_rad(COVER_OPEN_DEG) * smoothstep(0.0, 1.0, _cover_t)
