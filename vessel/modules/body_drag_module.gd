class_name BodyDragModule
extends PartModule
## Gövde parçaları için eksen bazlı sürükleme (ön alan + yan alan).
## Yan sürükleme sayesinde dikey kuyrukla birlikte yön kararlılığı oluşur.
## Ön\/arka yüz açıkta mı (AeroLinks) ve parçanın şekli (döndürme profilinden: sivri burun,
## daralan kuyruk) önden gelen direnci belirler: küt açık burun düz levha gibi direnir,
## kuyruk konisi olmayan açık arka uç taban direnci üretir. Motorun arkası egzozla dolu sayılır.

const BLUNT_CD := 0.6       ## açıkta kalan küt ön yüz
const BASE_CD := 0.22       ## açıkta kalan küt arka yüz (taban emmesi)

var front_area := 1.0
var side_area := 1.0
var cd_front := 0.1
var cd_side := 0.8
var front_open := true
var rear_open := true
var front_round := true     ## ön uç sivri / yuvarlak (ya da hava alan motor ağzı)
var rear_tapered := true    ## arka uç daralıyor ya da egzoz


func setup(p: Dictionary) -> void:
	front_area = p.get("front_area", front_area)
	side_area = p.get("side_area", side_area)
	cd_front = p.get("cd_front", cd_front)
	cd_side = p.get("cd_side", cd_side)


func on_attached() -> void:
	# şekli tanımın döndürme gövdelerinden çıkar: uçlardaki yarıçap / en büyük yarıçap
	var front_r := INF
	var rear_r := INF
	var zmin := INF
	var zmax := -INF
	var rmax := 0.0
	for vis: Dictionary in part.def.get("visuals", []):
		if vis.get("type", "") != "lathe" or vis.has("arc_from"):
			continue
		for pt: Vector2 in vis.get("profile", []):
			rmax = maxf(rmax, pt.y)
			if pt.x < zmin - 0.001:
				zmin = pt.x
				front_r = pt.y
			elif absf(pt.x - zmin) <= 0.001:
				front_r = minf(front_r, pt.y)
			if pt.x > zmax + 0.001:
				zmax = pt.x
				rear_r = pt.y
			elif absf(pt.x - zmax) <= 0.001:
				rear_r = minf(rear_r, pt.y)
	var has_engine := false
	for m in part.modules:
		if m is EngineModule or m is IntakeModule:
			has_engine = true
	if rmax > 0.0:
		front_round = has_engine or front_r < rmax * 0.55
		rear_tapered = has_engine or rear_r < rmax * 0.6
	# ikiz motor adaptörü: arka yüz motor yuvaları (egzozla dolu)
	if part.def.has("rear_nodes"):
		rear_tapered = true
	else:
		front_round = true
		rear_tapered = true


func physics_tick(_delta: float) -> void:
	var b := part.global_basis
	var pos := part.global_position
	var v := vessel.air_velocity_at(pos)
	var vl := Vector3(v.dot(b.x), v.dot(b.y), v.dot(b.z))
	var k := -0.5 * vessel.air_density()
	var wave := Atmosphere.wave_drag(absf(vl.z) / Atmosphere.SPEED_OF_SOUND)
	# ileri giderken (-z) ön yüz rüzgara, arka yüz izdeki emmeye maruz
	var forward := vl.z < 0.0
	var lead_open := front_open if forward else rear_open
	var lead_round := front_round if forward else rear_tapered
	var trail_open := rear_open if forward else front_open
	var trail_tapered := rear_tapered if forward else front_round
	var cd := cd_front
	if lead_open and not lead_round:
		cd = maxf(cd, BLUNT_CD)
	if trail_open and not trail_tapered:
		cd += BASE_CD
	var fx := k * cd_side * side_area * vl.x * absf(vl.x)
	var fy := k * cd_side * side_area * vl.y * absf(vl.y)
	var fz := k * cd * wave * front_area * vl.z * absf(vl.z)
	var f := b.x * fx + b.y * fy + b.z * fz
	vessel.add_force_at(f, pos)
	part.aero_load += f
