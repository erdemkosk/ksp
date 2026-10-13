class_name NavalGroup
## Düşman deniz grupları: önder gemi rota noktalarını dolaşır, refakatler düzen tutar (Warship
## leader/slot). Kıyı haritanın doğusunda (x ≳ 9 km); düşman cephesinin önündeki derin deniz
## kuzeydoğuda. Serbest uçuşta (kariyer bölgesi düşmandaysa) kalıcı bir filo orada seyreder.

## Kalıcı filo / Filo Baskını: kuzeydoğu açıkları (üsten ~30 km)
const FLEET_XZ := Vector2(16000, -25500)
const FLEET_ROUTE: Array[Vector2] = [Vector2(13500, -28500), Vector2(18500, -26500), Vector2(17500, -21500), Vector2(13000, -23000)]
## Fırkateyn Avı: Dereköy açıkları
const HUNT_XZ := Vector2(15000, -16000)
const HUNT_ROUTE: Array[Vector2] = [Vector2(15000, -16000), Vector2(18000, -12000), Vector2(14000, -9000), Vector2(12500, -14000)]
## Deniz Devriyesi: akıncılar kuzeydoğudan Güney Sahili'ne iner
const RAID_XZ := Vector2(17000, -15000)
const RAID_GOAL := Vector2(12000, 3000)

const REGION := "dogudeniz"


## Grubu kur. kind: "carrier" (uçak gemisi + muhrip + korvet), "destroyers" (iki fırkateyn),
## "raiders" (üç korvet), "patrol" (fırkateyn + korvet). Döner: gemiler (önder ilk).
static func spawn(world: Node3D, kind: String, route: Array[Vector2], start := Vector2.INF) -> Array[Warship]:
	var out: Array[Warship] = []
	var lead: Warship
	var slots: Array[Vector2] = []
	match kind:
		"carrier":
			lead = Carrier.create_carrier()
			out.append(lead)
			out.append(Frigate.create_frigate("Düşman muhribi"))
			out.append(Warship.create_ship("Düşman korveti"))
			slots = [Vector2(-700.0, -700.0), Vector2(750.0, 550.0)]
		"destroyers":
			lead = Frigate.create_frigate("Düşman fırkateyni 1")
			out.append(lead)
			out.append(Frigate.create_frigate("Düşman fırkateyni 2"))
			slots = [Vector2(650.0, 600.0)]
		"raiders":
			lead = Warship.create_ship("Akıncı korvet 1")
			out.append(lead)
			out.append(Warship.create_ship("Akıncı korvet 2"))
			out.append(Warship.create_ship("Akıncı korvet 3"))
			slots = [Vector2(-500.0, 450.0), Vector2(500.0, 450.0)]
			lead.speed = 12.0
		_:
			lead = Frigate.create_frigate("Düşman fırkateyni")
			out.append(lead)
			out.append(Warship.create_ship("Düşman korveti"))
			slots = [Vector2(600.0, 500.0)]
	lead.route = route
	var p0: Vector2 = route[0] if start == Vector2.INF else start
	var p1: Vector2 = route[1 % route.size()]
	if p1.distance_to(p0) < 1.0:
		p1 = p0 + Vector2(0, -1000)
	var d := p1 - p0
	var hdg := atan2(-d.x, -d.y)
	var fwd := Vector2(-sin(hdg), -cos(hdg))
	var right := Vector2(cos(hdg), -sin(hdg))
	_place(world, lead, p0, hdg)
	lead._wp = 1 % route.size()
	for i in range(1, out.size()):
		var s := out[i]
		s.leader = lead
		s.slot = slots[i - 1]
		s.speed = maxf(s.speed, lead.speed * 1.4)
		s.route = route        # önder batarsa rotayı kendisi sürdürür
		s._wp = lead._wp
		_place(world, s, p0 + right * s.slot.x - fwd * s.slot.y, hdg)
	return out


static func _place(world: Node3D, s: Warship, xz: Vector2, hdg: float) -> void:
	world.add_child(s)
	s.heading = hdg
	var pos := MissionManager.world_point(xz.x, xz.y, 0.5)
	s.global_transform = Transform3D(Basis(Planet.up_at(pos), hdg) * Planet.local_basis(pos), pos)


## Serbest uçuş: düşman cephesinin önündeki denizde kalıcı filo. Kariyerde doğu denizi bizdeyse
## filo yok, çekişmeliyse yalnız fırkateyn + korvet devriyesi.
static func spawn_patrol(world: Node3D) -> Array[Warship]:
	var kind := "carrier"
	if not Career.sandbox() and not Front.region(REGION).is_empty():
		match Front.owner(REGION):
			Front.DOST:
				return []
			Front.CEKISME:
				kind = "patrol"
	return spawn(world, kind, FLEET_ROUTE, FLEET_XZ)
