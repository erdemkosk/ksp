class_name WingModule
extends PartModule
## Kaldırma yüzeyi. Parçanın yerel eksenleri: X = açıklık, Y = yüzey normali, -Z = hücum kenarı.
## Her karede kendi noktasındaki hava hızından kaldırma/sürükleme hesaplar ve o noktaya uygular.

var area := 1.0
var lift_slope := 5.5
var stall_angle := deg_to_rad(15.0)
var cd0 := 0.012
var induced_k := 0.08
## Kuvvetin uygulandığı nokta (parça uzayı): ayarlanabilir kanatta ortalama veterin çeyreği.
## Hazır kanatlarda sıfır (parça merkezi).
var ac_offset := Vector3.ZERO
## Uç plakası etkisi (winglet / kanat ucu rayı, AeroLinks): indüklenen direnç çarpanı
var tip_factor := 1.0
## Kontrol yüzeylerinde hücum açısına eklenen sapma (radyan).
var deflection := 0.0
## Önündeki kanatlar ve iz etkisi (AeroLinks): [[WingModule, katsayı], ...]
var upstream: Array = []
var last_cl := 0.0
## Bu karede öndekilerden gelen aşağı akış açısı (debug için)
var downwash := 0.0

# Debug / HUD için son değerler
var last_lift := Vector3.ZERO
var last_drag := Vector3.ZERO
var last_aoa := 0.0
var stalled := false


func setup(p: Dictionary) -> void:
	area = p.get("area", area)
	lift_slope = p.get("lift_slope", lift_slope)
	stall_angle = deg_to_rad(p.get("stall_deg", 15.0))
	cd0 = p.get("cd0", cd0)
	var aspect: float = p.get("aspect_ratio", 4.0)
	induced_k = 1.0 / (PI * 0.8 * aspect)
	ac_offset = p.get("ac_offset", Vector3.ZERO)


## Aerodinamik merkez (uçak uzayı) — hangarda kaldırma merkezi hesabı için.
func ac_local() -> Vector3:
	return part.transform * ac_offset


func physics_tick(_delta: float) -> void:
	var b := part.global_basis
	var span := b.x
	var normal := b.y
	var chord := -b.z
	var pos := part.global_position if ac_offset == Vector3.ZERO else part.global_transform * ac_offset

	var v := vessel.air_velocity_at(pos)
	v -= span * v.dot(span)  # açıklık yönündeki akış kaldırma üretmez
	var speed := v.length()
	if speed < 0.5:
		last_lift = Vector3.ZERO
		last_drag = Vector3.ZERO
		stalled = false
		return

	var flow := -v / speed
	# öndeki kanatların aşağı akışı: hücum açısı ε = Σ f·2·CL/(π·AR) kadar azalır
	downwash = 0.0
	for link in upstream:
		var u: WingModule = link[0]
		if is_instance_valid(u) and u.part in vessel.parts:
			downwash += float(link[1]) * 2.0 * u.last_cl * u.induced_k * 0.8
	downwash = clampf(downwash, -0.2, 0.2)
	var aoa := wrapf(atan2(-v.dot(normal), v.dot(chord)) + deflection - downwash, -PI, PI)
	last_aoa = aoa

	var cl := lift_coefficient(aoa)
	last_cl = cl
	var blend := _stall_blend(aoa)
	stalled = blend > 0.3
	var cd := cd0 * Atmosphere.wave_drag(speed / Atmosphere.SPEED_OF_SOUND) \
		+ induced_k * tip_factor * cl * cl * (1.0 - blend) \
		+ blend * 1.6 * pow(sin(aoa), 2.0)

	var lift_dir := normal - flow * normal.dot(flow)
	lift_dir = lift_dir.normalized() if lift_dir.length_squared() > 1e-6 else Vector3.ZERO

	var q := 0.5 * vessel.air_density() * speed * speed * (1.0 - part.submerged)
	# kısmi hasar: delik açılmış yüzey daha az kaldırır, daha çok sürükler
	var h := part.health_ratio()
	if h < 0.999:
		cl *= lerpf(0.4, 1.0, h)
		cd += (1.0 - h) * 0.08
	last_lift = lift_dir * cl * q * area
	last_drag = flow * cd * q * area
	vessel.add_force_at(last_lift + last_drag, pos)
	part.aero_load += last_lift + last_drag


## Doğrusal bölge + stall sonrası düz levha modeline geçiş.
func on_damaged(_amount: float) -> void:
	if part.health_ratio() < 0.5 and not vessel.failures.has(_fkey()):
		vessel.failures[_fkey()] = "%s HASARLI — kaldırma %d%%" % [part.title.to_upper(), lerpf(40.0, 100.0, part.health_ratio())]


func _fkey() -> String:
	return "wing%d" % part.get_instance_id()


func lift_coefficient(aoa: float) -> float:
	var max_cl := lift_slope * stall_angle
	var linear := clampf(lift_slope * aoa, -max_cl, max_cl)
	var plate := 0.9 * sin(2.0 * aoa)
	return lerpf(linear, plate, _stall_blend(aoa))


func _stall_blend(aoa: float) -> float:
	return smoothstep(stall_angle, stall_angle + deg_to_rad(12.0), absf(aoa))
