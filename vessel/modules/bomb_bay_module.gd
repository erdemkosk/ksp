class_name BombBayModule
extends PartModule
## İç bomba bölmesi: gövdenin içinde 250 kg'lık bombalar. Silah "BOMBA BÖLMESİ" seçiliyken
## tetiğe basınca kapaklar açılır (~1.2 sn), açılınca tetik basılı kaldıkça bombalar sırayla
## (seri / "stick") düşer. Tetik bırakılınca 3 sn sonra kapaklar kapanır.
## Açık kapaklar sürükleme ekler ve radar kesit alanını büyütür (Vessel.rcs).

const BOMB_MASS := 250.0
const INTERVAL := 0.28
const DOOR_RATE := 0.85          ## kapak açılma hızı (1/sn)

var capacity := 8
var bombs := 8
var doors := 0.0                 ## 0 kapalı .. 1 açık
var _want_open := false
var _idle := 0.0
var _next := 0.0
var _door_l: Node3D
var _door_r: Node3D


func setup(p: Dictionary) -> void:
	capacity = int(p.get("bombs", capacity))
	bombs = capacity


func on_attached() -> void:
	_door_l = part.get_node_or_null("Visual/DoorL")
	_door_r = part.get_node_or_null("Visual/DoorR")


func extra_mass() -> float:
	return bombs * BOMB_MASS


func physics_tick(delta: float) -> void:
	var selected := vessel.selected_weapon == Vessel.WEAPON_BAY and vessel.master_arm and vessel.has_power()
	if selected and vessel.ctrl_fire and bombs > 0:
		_want_open = true
		_idle = 0.0
	else:
		_idle += delta
		if _idle > 3.0:
			_want_open = false
	doors = move_toward(doors, 1.0 if _want_open else 0.0, DOOR_RATE * delta)
	if _door_l:
		_door_l.rotation.z = -doors * 1.4
	if _door_r:
		_door_r.rotation.z = doors * 1.4
	# açık kapak sürüklemesi (yaklaşık 1.5 m² küt yüzey)
	if doors > 0.01:
		var v := vessel.air_velocity_at(part.global_position)
		vessel.add_force_at(-v * v.length() * 0.5 * vessel.air_density() * 1.5 * doors, part.global_position)
	_next -= delta
	if selected and vessel.ctrl_fire and doors >= 0.98 and bombs > 0 and _next <= 0.0:
		_next = INTERVAL
		_drop()


func _drop() -> void:
	bombs -= 1
	var b := Bomb.new()
	b.velocity = vessel.linear_velocity
	b.shooter = vessel
	vessel.get_parent().add_child(b)
	var slot := float(bombs % 4) - 1.5
	b.global_position = part.global_transform * Vector3(0, -0.6, slot * 0.6)
	b.look_at(b.global_position + vessel.forward(), vessel.up())
	Sfx.play_at("hydraulic_thunk.ogg", part.global_position, -6.0, 1.2, 800.0)
	vessel.recalc_mass()
