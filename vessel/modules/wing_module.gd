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

# Biçimden doğan davranış (ilk fizik karesinde parça tanımının kanat görselinden okunur):
var sweep := 0.0          ## hücum kenarı ok açısı (radyan; eksi = ters ok)
var thickness := 0.08     ## kalınlık / veter
var taper := 0.5          ## uç veteri / kök veteri
var is_delta := false     ## delta: vorteks kaldırması, yüksek hücum açısı, dönüşte enerji kaybı
var mach_dd := 0.8        ## sürükleme ıraksama Mach'ı (Korn): üstünde şok, Mach tuck, titreşim
var span_total := 4.0     ## yer etkisi için kanat açıklığı (iki yan)
## Titreşim (buffet) 0..1: stall yaklaşırken ve şok bölgesinde; kamera ve ses kullanır.
var buffet := 0.0
var _shape_ready := false
var _phase := 0.0
var _t := 0.0
var _ground_h := 999.0
var _ground_k := 0


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


func physics_tick(delta: float) -> void:
	if not _shape_ready:
		_read_shape()
	_t += delta
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
		buffet = 0.0
		return

	var flow := -v / speed
	var mach := speed / Atmosphere.SPEED_OF_SOUND
	var horizontal := absf((vessel.global_basis.inverse() * normal).y) > 0.6
	# transonik şok: sürükleme ıraksama Mach'ının üstünde (kalın düz kanatta erken, ok kanatta geç);
	# ses hızını epey geçince şok kanadın arkasına oturur ve etki azalır
	var shock := smoothstep(mach_dd - 0.03, mach_dd + 0.08, mach) * (1.0 - smoothstep(1.15, 1.4, mach))
	# öndeki kanatların aşağı akışı: hücum açısı ε = Σ f·2·CL/(π·AR) kadar azalır
	downwash = 0.0
	for link in upstream:
		var u: WingModule = link[0]
		if is_instance_valid(u) and u.part in vessel.parts:
			downwash += float(link[1]) * 2.0 * u.last_cl * u.induced_k * 0.8
	downwash = clampf(downwash, -0.2, 0.2)
	# şok bölgesinde kontrol yüzeyi etkisini yitirir (akış ayrılır)
	var aoa := wrapf(atan2(-v.dot(normal), v.dot(chord)) + deflection * (1.0 - 0.5 * shock) - downwash, -PI, PI)
	last_aoa = aoa

	var cl := lift_coefficient(aoa)
	var blend := _stall_blend(aoa)
	stalled = blend > 0.3
	var a_abs := absf(aoa)
	# delta: hücum kenarı girdabı ek kaldırma verir (Polhamus) — stall geç gelir ama bu kaldırma
	# normal kuvvettir: geriye eğik, sürüklemesi büyük (dönüşte enerji hızla tükenir)
	var cl_vortex := 0.0
	if is_delta:
		cl_vortex = 2.0 * pow(sin(aoa), 2.0) * cos(aoa) * signf(aoa) * (1.0 - smoothstep(deg_to_rad(35.0), deg_to_rad(55.0), a_abs))
		cl += cl_vortex
	# stall yaklaşırken akış düzensizleşir: kaldırma titrer, iki kanatta farklı (kanat sallanması;
	# ok kanatta güçlü, deltada zayıf). Asimetri vrile girişi tetikleyebilir.
	var near := smoothstep(stall_angle - deg_to_rad(3.0), stall_angle, a_abs) * (1.0 - smoothstep(stall_angle + deg_to_rad(8.0), stall_angle + deg_to_rad(20.0), a_abs))
	var rock := 0.06 if is_delta else (0.24 if sweep > deg_to_rad(25.0) else 0.14)
	var wobble := sin(_t * 6.3 + _phase) * 0.6 + sin(_t * 2.1 + _phase * 2.3) * 0.4
	cl *= 1.0 - rock * near * wobble
	# ok kanatta yandan kayma yatış etkisi verir: rüzgara bakan kanadın etkin ok açısı küçülür,
	# kaldırması artar (dihedral etkisi; küçük dikey kuyrukla Hollanda yatışına yol açar)
	if horizontal and absf(sweep) > deg_to_rad(5.0):
		var vl := vessel.global_basis.inverse() * vessel.air_velocity_at(vessel.com_global())
		var beta := atan2(vl.x, maxf(-vl.z, 1.0))
		var side := signf(part.position.x - vessel.com_local.x)
		var c0 := cos(sweep)
		cl *= clampf(pow(cos(sweep - side * beta), 2.0) / maxf(c0 * c0, 0.05), 0.7, 1.3)
	# yer etkisi: kanat açıklığından alçakta indüklenen direnç azalır, kaldırma biraz artar
	var ge := 1.0
	if horizontal:
		_ground_k -= 1
		if _ground_k <= 0:
			_ground_k = 4
			_ground_h = vessel.radar_altitude() + (pos - vessel.com_global()).dot(vessel.up())
		var r := 16.0 * maxf(_ground_h, 0.1) / maxf(span_total, 1.0)
		ge = r * r / (1.0 + r * r)
		cl *= 1.0 + 0.12 * (1.0 - ge)
	last_cl = cl
	var cd := cd0 * Atmosphere.wave_drag(speed / Atmosphere.SPEED_OF_SOUND) \
		+ induced_k * tip_factor * ge * cl * cl * (1.0 - blend) \
		+ blend * 1.6 * pow(sin(aoa), 2.0) \
		+ absf(cl_vortex * tan(minf(a_abs, 1.2))) \
		+ 0.05 * shock * (0.5 + thickness * 6.0)
	# kontrol yüzeyi sapınca (aşağı sapan kanatçık daha çok) sürükleme artar: ters sapma
	if deflection != 0.0:
		cd += 0.25 * pow(sin(deflection), 2.0) + 0.15 * maxf(sin(deflection), 0.0)
	# basınç merkezinin kayması: ok kanatta stall uçtan başlar → kaldırma öne kayar (burun kalkar);
	# şokta basınç merkezi geriye kayar → burun düşer (Mach tuck)
	var tip_stall := smoothstep(stall_angle - deg_to_rad(4.0), stall_angle + deg_to_rad(3.0), a_abs) if (sweep > deg_to_rad(25.0) and not is_delta) else 0.0
	var chord_len := part.size.z
	pos += chord * (tip_stall * 0.22 * part.size.x * 0.5 * tan(sweep) - shock * 0.18 * chord_len)
	buffet = clampf(near * (rock * 4.0) + shock * (0.35 + thickness * 5.0) * smoothstep(0.1, 0.4, absf(cl)), 0.0, 1.0)

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


## Kanadın biçimi parça tanımındaki görselden: hazır kanat ("wing": açıklık, kök/uç veteri, hücum
## kenarı kayması, kalınlık) ya da ayarlanabilir kanat ("wing_sections"). Ölçek açıları değiştirmez.
func _read_shape() -> void:
	_shape_ready = true
	_phase = float(part.get_instance_id() % 1000) * 0.731
	for vis: Dictionary in part.def.get("visuals", []):
		match vis.get("type", ""):
			"wing":
				var sp := maxf(float(vis.get("span", 1.0)), 0.01)
				sweep = atan2(float(vis.get("sweep", 0.0)), sp)
				thickness = float(vis.get("thick", 0.08))
				taper = float(vis.get("tip", 1.0)) / maxf(float(vis.get("root", 1.0)), 0.01)
			"wing_sections":
				var secs: Array = vis.get("secs", [])
				if secs.size() >= 2:
					var a: Vector3 = secs[0]
					var e: Vector3 = secs[-1]
					sweep = atan2(e.y - a.y, maxf(e.x - a.x, 0.01))
					taper = e.z / maxf(a.z, 0.01)
				thickness = float(vis.get("thick", 0.06))
			_:
				continue
		break
	is_delta = sweep > deg_to_rad(40.0) and taper < 0.35
	# Korn denklemi (çeyrek veter ok açısı ≈ hücum kenarınınkinin %80'i, tasarım CL 0.3)
	var c := cos(absf(sweep) * 0.8)
	mach_dd = clampf(0.87 / c - thickness / (c * c) - 0.03 / (c * c * c), 0.6, 1.1)
	# yer etkisi açıklığı: gövdeden uca iki yan (yan kanatlarda), tek parça kanatta kendi açıklığı
	span_total = maxf(2.0 * (absf(part.position.x) + part.size.x * 0.5), part.size.x)


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
