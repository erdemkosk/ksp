class_name MissileModule
extends PartModule
## Füze rayı: bir IR füze taşır. Arayıcı başlık (uçağın burnu yönündeki koni) en güçlü ısı
## kaynağına kilitlenir. Kilit olmadan da ateşlenebilir (kör atış): füze uçuşta önündeki
## koniyi tarar, bir ısı kaynağı bulursa ona kilitlenir, bulamazsa boşa gider. Füze ağırlığı fırlatılınca düşer.

const MISSILE_MASS := 85.0
const SEEK_CONE := deg_to_rad(18.0)
const SEEK_RANGE := 7000.0
const DESIGNATED_CONE := deg_to_rad(35.0)   ## radarla seçilen hedef için arayıcı daha geniş bakar

var loaded := true
var target: Vessel          ## arayıcının şu an izlediği hedef
var _visual: Node3D
var _fired_this_press := false


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual/Missile")


func extra_mass() -> float:
	return MISSILE_MASS if loaded else 0.0


func physics_tick(_delta: float) -> void:
	var active := loaded and vessel.master_arm and vessel.selected_weapon == 1 and vessel.has_power()
	target = _seek() if active else null
	if not vessel.ctrl_fire:
		_fired_this_press = false
		return
	# tetik başına tek füze: araçtaki ilk dolu ray ateşler
	if active and not _fired_this_press and _is_first_ready():
		_launch()
		for m in vessel.modules:
			if m is MissileModule:
				m._fired_this_press = true


func _is_first_ready() -> bool:
	for m in vessel.modules:
		if m is MissileModule and m.loaded:
			return m == self
	return false


## Burun konisindeki en güçlü ısı kaynağı (uzaklığın karesiyle zayıflar).
func _seek() -> Vessel:
	var d := vessel.designated
	if is_instance_valid(d) and not d.parts.is_empty() and d.team != vessel.team:
		var dto: Vector3 = d.heat_position() - vessel.com_global()
		if dto.length() < SEEK_RANGE and dto.length() > 50.0 and vessel.forward().angle_to(dto) < DESIGNATED_CONE:
			return d
	var best: Vessel = null
	var best_score := 0.0
	var fwd := vessel.forward()
	var origin := vessel.com_global()
	for node in vessel.get_parent().get_children():
		if node is Vessel and node != vessel and node.team != vessel.team and not node.parts.is_empty():
			var to: Vector3 = node.heat_position() - origin
			var dist := to.length()
			if dist > SEEK_RANGE or dist < 50.0 or fwd.angle_to(to) > SEEK_CONE:
				continue
			var score: float = node.heat_signature() / (dist * dist) * 1e6
			if score > best_score and score > 0.02:
				best = node
				best_score = score
	return best


func _launch() -> void:
	loaded = false
	if _visual:
		_visual.visible = false
	var m := Missile.new()
	m.velocity = vessel.linear_velocity + vessel.forward() * 25.0 - vessel.global_basis.y * 6.0
	m.target = target
	m.shooter = vessel
	vessel.get_parent().add_child(m)
	m.global_position = part.global_transform * Vector3(0, -0.35, 0)
	m.look_at(m.global_position + vessel.forward(), vessel.up())
	Sfx.play_at("missile_launch.ogg", part.global_position, 2.0, randf_range(0.95, 1.05), 5000.0)
	vessel.weapon_fired.emit(1)
	vessel.recalc_mass()
