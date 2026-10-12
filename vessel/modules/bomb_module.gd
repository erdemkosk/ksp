class_name BombModule
extends PartModule
## Bomba askısı: bir adet güdümsüz 250 kg bomba taşır. BOMBA seçiliyken tetik bırakır
## (tetik başına bir bomba). HUD, bombanın düşeceği yeri (CCIP) gösterir.

const BOMB_MASS := 250.0

var loaded := true
var _visual: Node3D
var _released_this_press := false


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual/Bomb")


func extra_mass() -> float:
	return BOMB_MASS if loaded else 0.0


func physics_tick(_delta: float) -> void:
	if not vessel.ctrl_fire:
		_released_this_press = false
		return
	var active := loaded and vessel.master_arm and vessel.selected_weapon == Vessel.WEAPON_BOMB and vessel.has_power()
	if active and not _released_this_press and _is_first_ready():
		release()
		for m in vessel.modules:
			if m is BombModule:
				m._released_this_press = true


func _is_first_ready() -> bool:
	for m in vessel.modules:
		if m is BombModule and m.loaded:
			return m == self
	return false


func release() -> void:
	loaded = false
	if _visual:
		_visual.visible = false
	var b := Bomb.new()
	b.velocity = vessel.linear_velocity   # HUD CCIP aynı başlangıçla hesaplar
	b.shooter = vessel
	vessel.get_parent().add_child(b)
	b.global_position = part.global_transform * Vector3(0, -0.4, 0)
	b.look_at(b.global_position + vessel.forward(), vessel.up())
	Sfx.play_at("hydraulic_thunk.ogg", part.global_position, -4.0, 1.4, 800.0)
	vessel.recalc_mass()
