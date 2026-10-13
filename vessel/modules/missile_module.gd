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
##
## Radar avcısı (guidance = "arm"): burna en yakın yayın yapan radar (SAM, erken uyarı, gemi,
## radarı açık uçak), 80 km'ye kadar. Yayın yoksa atış olmaz.
## Seyir füzesi (guidance = "cruise"): haritadan seçilen GPS hedefine (M, sol tık). Hedef yoksa atış olmaz.
## Gemi savar (guidance = "ship"): burna en yakın düşman gemisi (70 km) ya da GPS hedefi;
## ikisi de yoksa burun yönünde 40 km'ye atılır, orada kendi arar.

const MISSILE_MASS := 85.0
const RADAR_MISSILE_MASS := 150.0
const MASSES := {"ir": 85.0, "radar": 150.0, "arm": 360.0, "cruise": 1200.0, "ship": 650.0}
const SEEK_CONE := deg_to_rad(18.0)
const SEEK_RANGE := 7000.0
const DESIGNATED_CONE := deg_to_rad(35.0)   ## radarla seçilen hedef için arayıcı daha geniş bakar
const RADAR_RANGE := 16000.0                ## radar füzesinin azami atış menzili
const RADAR_MIN_RANGE := 1000.0
const RADAR_BORESIGHT := deg_to_rad(20.0)    ## seçili hedef yoksa burna bu kadar yakın temas
const ARM_RANGE := 80000.0
const ARM_CONE := deg_to_rad(45.0)
const CRUISE_RANGE := 110000.0
const SHIP_RANGE := 70000.0

var loaded := true
var guidance := "ir"
var radar_guided := false   ## guidance == "radar" (eski kodla uyum)
var target: Vessel          ## arayıcının (IR) ya da radarın (RF) şu an izlediği hedef
var aim_node: Node3D        ## ARM: yayın kaynağı · gemi savar: hedef gemi
var _visual: Node3D
var _fired_this_press := false


func setup(p: Dictionary) -> void:
	guidance = String(p.get("guidance", "ir"))
	radar_guided = guidance == "radar"


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual/Missile")


func extra_mass() -> float:
	return float(MASSES.get(guidance, MISSILE_MASS)) if loaded else 0.0


func weapon_kind() -> int:
	match guidance:
		"radar":
			return Vessel.WEAPON_RADAR
		"arm":
			return Vessel.WEAPON_ARM
		"cruise":
			return Vessel.WEAPON_CRUISE
		"ship":
			return Vessel.WEAPON_SHIP
	return Vessel.WEAPON_MISSILE


func physics_tick(_delta: float) -> void:
	var active := loaded and vessel.master_arm and vessel.selected_weapon == weapon_kind() and vessel.has_power()
	target = null
	aim_node = null
	if active:
		match guidance:
			"radar":
				target = _radar_lock()
			"arm":
				aim_node = _arm_lock()
			"ship":
				aim_node = _ship_lock()
			"cruise":
				pass
			_:
				target = _seek()
	if not vessel.ctrl_fire:
		_fired_this_press = false
		return
	# tetik başına tek füze: araçtaki ilk dolu ray ateşler
	if active and not _fired_this_press and _is_first_ready():
		var why := _blocked()
		if why != "":
			Sfx.play_ui("switch_2.ogg", -8.0, 0.6)   # kilit / hedef yok: atış yok
			vessel.system_message.emit(why)
		else:
			_launch()
		for m in vessel.modules:
			if m is MissileModule and m.guidance == guidance:
				m._fired_this_press = true


## Atışa engel varsa nedeni (yoksa boş).
func _blocked() -> String:
	match guidance:
		"radar":
			return "" if target else "RADAR İZİ YOK — F4 ile hedef seç"
		"arm":
			return "" if aim_node else "RADAR YAYINI YOK — burnu SAM / radara çevir"
		"cruise":
			if vessel.strike_xz == Vector2.INF:
				return "GPS HEDEF YOK — haritada (M) sol tıkla"
			if vessel.strike_world().distance_to(vessel.com_global()) > CRUISE_RANGE:
				return "HEDEF MENZİL DIŞI (110 km)"
	return ""


func _is_first_ready() -> bool:
	for m in vessel.modules:
		if m is MissileModule and m.loaded and m.guidance == guidance:
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


## ARM: burna en yakın (koni içinde, menzilde, görüş hattında) yayın kaynağı.
func _arm_lock() -> Node3D:
	var origin := vessel.com_global()
	var best: Node3D = null
	var best_a := ARM_CONE
	for e in Missile.emitters(vessel.get_parent(), vessel.team):
		if e == vessel:
			continue
		var p := Missile._emitter_pos(e)
		var to := p - origin
		var a := vessel.forward().angle_to(to)
		if a < best_a and to.length() < ARM_RANGE and Missile.terrain_clear(origin, p):
			best_a = a
			best = e
	return best


## Gemi savar: burna en yakın düşman gemisi.
func _ship_lock() -> Node3D:
	var origin := vessel.com_global()
	var best: Node3D = null
	var best_a := deg_to_rad(60.0)
	for sh in Warship.ships:
		if not is_instance_valid(sh) or sh.destroyed or sh.team == vessel.team:
			continue
		var to := sh.global_position - origin
		var a := vessel.forward().angle_to(to)
		if a < best_a and to.length() < SHIP_RANGE:
			best_a = a
			best = sh
	return best


func _launch() -> void:
	loaded = false
	if _visual:
		_visual.visible = false
	var m := Missile.new()
	m.guidance = guidance
	match guidance:
		"radar":
			m.launcher = vessel
			m.target = target
		"arm":
			m.target = aim_node
		"cruise":
			m.strike_point = vessel.strike_world()
		"ship":
			if aim_node:
				m.strike_point = aim_node.global_position
				m.target = aim_node
			elif vessel.strike_xz != Vector2.INF:
				m.strike_point = vessel.strike_world()
			else:
				m.strike_point = vessel.com_global() + vessel.forward() * 40000.0
		_:
			m.target = target
	m.velocity = vessel.linear_velocity + vessel.forward() * 25.0 - vessel.global_basis.y * 6.0
	m.shooter = vessel
	vessel.get_parent().add_child(m)
	m.global_position = part.global_transform * Vector3(0, -0.35, 0)
	m.look_at(m.global_position + vessel.forward(), vessel.up())
	var heavy := guidance in ["arm", "cruise", "ship"]
	Sfx.play_at("missile_launch.ogg", part.global_position, 3.0 if heavy else 2.0, randf_range(0.95, 1.05) * (0.75 if heavy else (0.85 if radar_guided else 1.0)), 6000.0)
	vessel.weapon_fired.emit(weapon_kind())
	vessel.recalc_mass()
