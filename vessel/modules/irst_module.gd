class_name IrstModule
extends PartModule
## Kızılötesi arama-izleme (IRST): burnun önündeki koni içinde ısı kaynaklarını pasif olarak
## bulur. Yayın yapmaz, düşman RWR'ında görünmez. Menzil hedefin ısısına bağlıdır (art yakıcılı
## motor çok uzaktan, rölantideki pervaneli uçak yakından görülür); arazi görüşü keser.
## Mesafe ölçemez (lazer yok): kontaklar HUD'da tahmini mesafeyle gösterilir.
## Seçilen IRST hedefi IR füze arayıcısının önceliğidir; radar füzesi için radar gerekir.

var range_m := 14000.0
var cone := deg_to_rad(55.0)
var contacts: Array[Vessel] = []

var _scan_timer := 0.0


func setup(p: Dictionary) -> void:
	range_m = p.get("range", range_m)
	cone = deg_to_rad(p.get("cone_deg", 55.0))


func physics_tick(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 0.3
	contacts.clear()
	if not vessel.has_power() or part.health_ratio() < 0.3:
		return
	var origin := part.global_position
	var fwd := vessel.forward()
	for node in vessel.get_parent().get_children():
		if node is Vessel and node != vessel and not node.parts.is_empty():
			var heat: float = node.heat_signature()
			if heat < 0.05:
				continue
			var to: Vector3 = node.heat_position() - origin
			var dist := to.length()
			# ısı ~ 1/r²: menzil ısının kareköküyle ölçeklenir (0.75 = tipik seyir)
			var reach := range_m * clampf(sqrt(heat / 0.75), 0.35, 1.6)
			if dist < reach and fwd.angle_to(to) < cone and Missile.terrain_clear(origin, node.heat_position()):
				contacts.append(node)
