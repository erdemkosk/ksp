class_name MissileModule
extends PartModule
## Füze rayı: bir füze taşır. Füze ağırlığı fırlatılınca düşer.
##
## IR (varsayılan): arayıcı başlık (uçağın burnu yönündeki koni) en güçlü ısı kaynağına
## kilitlenir. Kilit olmadan da ateşlenebilir (kör atış): füze uçuşta önündeki koniyi tarar,
## bir ısı kaynağı bulursa ona kilitlenir, bulamazsa boşa gider.
##
## Radar (guidance = "radar"): uçağın radarının izlediği hedefe atılır — radarla seçili hedef
## (F4), yoksa burna en yakın radar teması. Kilit yoksa atış olmaz.

const MISSILE_MASS := 85.0
const RADAR_MISSILE_MASS := 150.0
const SEEK_CONE := deg_to_rad(18.0)
const SEEK_RANGE := 7000.0
const DESIGNATED_CONE := deg_to_rad(35.0)   ## radarla seçilen hedef için arayıcı daha geniş bakar
const RADAR_RANGE := 16000.0                ## radar füzesinin azami atış menzili
const RADAR_MIN_RANGE := 1000.0
const RADAR_BORESIGHT := deg_to_rad(20.0)    ## seçili hedef yoksa burna bu kadar yakın temas

var loaded := true
var radar_guided := false
var target: Vessel          ## arayıcının (IR) ya da radarın (RF) şu an izlediği hedef
var _visual: Node3D
var _fired_this_press := false


func setup(p: Dictionary) -> void:
	radar_guided = p.get("guidance", "ir") == "radar"


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual/Missile")


func extra_mass() -> float:
	if not loaded:
		return 0.0
	return RADAR_MISSILE_MASS if radar_guided else MISSILE_MASS


func weapon_kind() -> int:
	return Vessel.WEAPON_RADAR if radar_guided else Vessel.WEAPON_MISSILE


func physics_tick(_delta: float) -> void:
	var active := loaded and vessel.master_arm and vessel.selected_weapon == weapon_kind() and vessel.has_power()
	if not active:
		target = null
	else:
		target = _radar_lock() if radar_guided else _seek()
	if not vessel.ctrl_fire:
		_fired_this_press = false
		return
	# tetik başına tek füze: araçtaki ilk dolu ray ateşler
	if active and not _fired_this_press and _is_first_ready():
		if radar_guided and target == null:
			Sfx.play_ui("switch_2.ogg", -8.0, 0.6)   # kilit yok: atış yok
		else:
			_launch()
		for m in vessel.modules:
			if m is MissileModule and m.radar_guided == radar_guided:
				m._fired_this_press = true


func _is_first_ready() -> bool:
	for m in vessel.modules:
		if m is MissileModule and m.loaded and m.radar_guided == radar_guided:
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


## Radar izi: seçili hedef radar temasıysa o, değilse burna en yakın düşman teması.
func _radar_lock() -> Vessel:
	var radar := vessel.radar()
	if radar == null:
		return null
	var origin := vessel.com_global()
	var d := vessel.designated
	if is_instance_valid(d) and d in radar.contacts and d.team != vessel.team and _in_envelope(d.com_global().distance_to(origin)):
		return d
	var best: Vessel = null
	var best_a := RADAR_BORESIGHT
	for t in radar.contacts:
		if not is_instance_valid(t) or t.parts.is_empty() or t.team == vessel.team or t.team == "sivil":
			continue
		var to := t.com_global() - origin
		var a := vessel.forward().angle_to(to)
		if a < best_a and _in_envelope(to.length()):
			best_a = a
			best = t
	return best


func _in_envelope(dist: float) -> bool:
	return dist > RADAR_MIN_RANGE and dist < RADAR_RANGE


func _launch() -> void:
	loaded = false
	if _visual:
		_visual.visible = false
	var m := Missile.new()
	if radar_guided:
		m.guidance = "radar"
		m.launcher = vessel
	m.velocity = vessel.linear_velocity + vessel.forward() * 25.0 - vessel.global_basis.y * 6.0
	m.target = target
	m.shooter = vessel
	vessel.get_parent().add_child(m)
	m.global_position = part.global_transform * Vector3(0, -0.35, 0)
	m.look_at(m.global_position + vessel.forward(), vessel.up())
	Sfx.play_at("missile_launch.ogg", part.global_position, 2.0, randf_range(0.95, 1.05) * (0.85 if radar_guided else 1.0), 5000.0)
	vessel.weapon_fired.emit(weapon_kind())
	vessel.recalc_mass()
