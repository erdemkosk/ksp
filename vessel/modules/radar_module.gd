class_name RadarModule
extends PartModule
## Arama radarı: burnun önündeki koni içinde menzildeki uçakları bulur.
## Algılama, hedefin radar kesit alanına (büyüklüğüne) bağlıdır: büyük uçak daha uzaktan görülür.
## Güç yoksa çalışmaz. Kontaklar HUD hedef kutuları ve kokpit radar ekranı için kullanılır.

var range_m := 18000.0
var cone := deg_to_rad(60.0)
var contacts: Array[Vessel] = []

var _scan_timer := 0.0


func setup(p: Dictionary) -> void:
	range_m = p.get("range", range_m)
	cone = deg_to_rad(p.get("cone_deg", 60.0))


func physics_tick(delta: float) -> void:
	_spin_dome(delta)
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 0.25
	contacts.clear()
	if not vessel.has_power() or not vessel.radar_on:
		return
	var origin := part.global_position
	var fwd := -part.global_basis.z
	for node in vessel.get_parent().get_children():
		if node is Vessel and node != vessel and not node.parts.is_empty():
			var to: Vector3 = node.com_global() - origin
			# RCS, arazi maskesi, yer yankısı (aşağı bakış), çentik ve karıştırma: Detection
			if fwd.angle_to(to) < cone and Detection.radar_sees(origin, range_m, node):
				contacts.append(node)
				if vessel.team != "oyuncu":
					Detection.report(vessel.team, node)


## Dönen radar diski (AWACS "Dome"): yalnız radar yayındayken ve güç varken döner (~10 sn'de
## bir tur); kapatınca yavaşça durur.
var _dome: Node3D
var _dome_rate := 0.0

func _spin_dome(delta: float) -> void:
	if has_meta("no_dome"):
		return
	if _dome == null:
		_dome = part.find_child("Dome", true, false) as Node3D
		if _dome == null:
			set_meta("no_dome", true)
			return
	var on := vessel.has_power() and vessel.radar_on
	_dome_rate = move_toward(_dome_rate, 0.63 if on else 0.0, delta * 0.25)
	if _dome_rate > 0.0:
		_dome.rotate_y(_dome_rate * delta)
