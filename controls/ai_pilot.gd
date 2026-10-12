class_name AIPilot
extends Node
## Düşman pilot yapay zekası. Durumlar:
##   DEVRİYE  — otopilotla irtifa/hız tutup iki yön arasında tur atar
##   ÇATIŞMA  — en yakın düşmana önleme takibi (uzakta saf takip, yakında öncülü takip);
##              burun hedefe dönünce füze kilidi alır ve atar, yakında topla vurur
##   SAVUNMA  — kendine kilitli füze yaklaşınca füzeye dik (beam) sert dönüş, gazı keser,
##              flare atar; sonra çatışmaya döner
## Her durumda: yere yaklaşırsa önce kurtarır, G sınırını aşmaz (kendi kanadını koparmasın).
## `skill` (0..1): görme menzili, nişan hatası, tepki, G sınırı, flare zamanlaması.

enum State { PATROL, ENGAGE, DEFEND }
const STATE_NAMES := ["DEVRİYE", "ÇATIŞMA", "SAVUNMA"]

var vessel: Vessel
var skill := 0.6
var altitude := 2000.0
var speed := 200.0
var leg_time := 45.0
## false: hiç saldırmaz (hedef uçağı, eğitim)
var aggressive := true

var state := State.PATROL
var target: Vessel

var _ap := Autopilot.new()
var _t := 0.0
var _missile_cd := 4.0
var _flare_cd := 0.0
var _fire_hold := 0.0
var _aim_noise := Vector3.ZERO
var _noise_t := 0.0
var _scan_t := 0.0
var _stale := 0.0
var _yoyo := 0.0
var dbg := ""
var _pitch_i := 0.0
var _yaw_i := 0.0


func _ready() -> void:
	_ap.level = true
	_ap.hold_altitude = true
	_ap.hold_heading = true
	_ap.hold_speed = true
	_ap.target_altitude = altitude
	_ap.target_speed = speed
	if is_instance_valid(vessel):
		_ap.target_heading = vessel.heading_deg()
		vessel.master_arm = true


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel) or vessel.parts.is_empty() or vessel.cockpit() == null or not vessel.has_pilot():
		if is_instance_valid(vessel):
			vessel.ctrl_fire = false
		return
	_t += delta
	_missile_cd -= delta
	_flare_cd -= delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5
		target = _find_target() if aggressive else null

	var incoming := vessel.incoming_missile()
	var threat_d := incoming.global_position.distance_to(vessel.com_global()) if incoming else INF
	if incoming and threat_d < lerpf(2500.0, 5000.0, skill):
		state = State.DEFEND
	elif is_instance_valid(target):
		state = State.ENGAGE
	else:
		state = State.PATROL

	vessel.ctrl_fire = false
	match state:
		State.PATROL:
			_patrol(delta)
		State.ENGAGE:
			_engage(delta)
		State.DEFEND:
			_defend(incoming, threat_d)


# ------------------------------------------------------------------ durumlar

func _patrol(_delta: float) -> void:
	if _t > leg_time:
		_t = 0.0
		_ap.target_heading = fposmod(_ap.target_heading + 180.0, 360.0)
	var out := _ap.compute(vessel)
	var w := vessel.local_angular_velocity()
	var pitch: float = out["pitch"] if out["pitch"] != null else 0.0
	var roll: float = out["roll"] if out["roll"] != null else 0.0
	var safe := _ground_escape()
	if safe != Vector3.ZERO:
		_fly(safe, 6.0)
		vessel.ctrl_throttle = 1.0
		return
	vessel.ctrl_pitch = pitch
	vessel.ctrl_roll = roll
	vessel.ctrl_yaw = clampf(w.y * 2.0, -1.0, 1.0)
	vessel.ctrl_throttle = out["throttle"] if out["throttle"] != null else 0.7


func _engage(delta: float) -> void:
	var me := vessel.com_global()
	var tp := target.com_global()
	var to := tp - me
	var dist := to.length()
	var closing := (vessel.linear_velocity - target.linear_velocity).dot(to / maxf(dist, 1.0))

	# nişan gürültüsü (düşük beceri = titrek nişan), yavaşça değişir
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = 0.8
		_aim_noise = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (1.0 - skill) * 0.006

	# silah seçimi
	var has_missile := vessel.missiles_left() > 0
	var gun_range := dist < 1100.0 and vessel.gun_ammo() > 0
	if has_missile and dist > 900.0 and dist < MissileModule.SEEK_RANGE:
		vessel.selected_weapon = Vessel.WEAPON_MISSILE
	elif vessel.gun_ammo() > 0:
		vessel.selected_weapon = Vessel.WEAPON_GUN

	# öncülü takip: top mermisi uçuş süresi kadar ileri
	var aim := tp
	# hedefin bize bakma açısı: 1 = tam kafa kafaya, -1 = tam arkasındayız
	var aspect := target.forward().dot((me - tp) / maxf(dist, 1.0))
	var up := Planet.up_at(me)
	if aspect > 0.5 and dist < 3500.0 and dist > 250.0 and vessel.selected_weapon != Vessel.WEAPON_MISSILE:
		# kafa kafaya: yana açıl, geçişten sonra dönüş için yer kalsın (iki daireli dönüş)
		var side := (to.cross(up)).normalized()
		if side.dot(vessel.linear_velocity) < 0.0:
			side = -side
		aim = tp + side * 700.0
	elif aspect < 0.3 and dist < 2500.0:
		var t_lead := dist / 950.0
		aim = tp + (target.linear_velocity - vessel.linear_velocity) * t_lead
		aim -= Planet.gravity_at(me) * 0.5 * t_lead * t_lead
	var dir := (aim - me).normalized() + _aim_noise
	# daire kilitlenmesi (iki taraf da kuyruk kovalıyor): bir süre dikeye çık (yüksek yo-yo)
	var off := vessel.forward().angle_to(to)
	_stale = _stale + delta if (dist < 1600.0 and off > deg_to_rad(25.0)) else maxf(_stale - delta * 2.0, 0.0)
	if _stale > lerpf(16.0, 8.0, skill):
		_yoyo = 5.0
		_stale = 0.0
	_yoyo -= delta
	if _yoyo > 0.0 and vessel.radar_altitude() < 6000.0:
		dir = (dir + Planet.up_at(me) * 1.4).normalized()
	var g_limit := lerpf(6.0, 9.0, skill)
	# çarpışmadan kaçın
	if dist < 220.0 and closing > 40.0:
		dir = (to.cross(up).normalized() + up * 0.5).normalized()

	var safe := _ground_escape()
	if safe != Vector3.ZERO:
		_fly(safe, g_limit)
		vessel.ctrl_throttle = 1.0
		return
	_fly(dir.normalized(), g_limit)

	# gaz: uzaktayken art yakıcı; arkasındayken ~450 m'de hız eşle (öne kaçmasın)
	if dist > 1500.0:
		vessel.ctrl_throttle = 1.0
	elif aspect < -0.5:
		var want_closing := clampf((dist - 450.0) * 0.25, -40.0, 120.0)
		vessel.ctrl_throttle = clampf(0.62 + (want_closing - closing) * 0.03, 0.0, 1.0)
	else:
		vessel.ctrl_throttle = 0.9

	# ateş: topun öncü noktasına göre (yapay zeka topu hedefe biraz yönlenebilir)
	var gun: GunModule = null
	for m in vessel.modules:
		if m is GunModule and m.ammo > 0:
			gun = m
			m.gimbal_deg = lerpf(0.5, 1.2, skill)
			m.aim_target = target
	var lead_dir := gun.lead_direction(target) if gun else (aim - me).normalized()
	var err := vessel.forward().angle_to(lead_dir)
	dbg = "err=%.1f asp=%+.2f kap=%+d gaz=%.2f" % [rad_to_deg(err), aspect, closing, vessel.ctrl_throttle]
	if vessel.selected_weapon == Vessel.WEAPON_MISSILE:
		var locked := false
		for m in vessel.modules:
			if m is MissileModule and m.loaded and m.target == target:
				locked = true
		_fire_hold -= delta
		if locked and _missile_cd <= 0.0 and dist < MissileModule.SEEK_RANGE * lerpf(0.55, 0.8, skill):
			_fire_hold = 0.1
			_missile_cd = lerpf(14.0, 7.0, skill)
		vessel.ctrl_fire = _fire_hold > 0.0
	elif gun_range and gun and err < deg_to_rad(gun.gimbal_deg) + atan2(4.0, dist):
		vessel.ctrl_fire = true


func _defend(missile: Missile, d: float) -> void:
	var me := vessel.com_global()
	var los := (missile.global_position - me).normalized()
	var up := Planet.up_at(me)
	# füzeye dik yatay yön (mevcut hız yönüne yakın olan taraf)
	var beam := los.cross(up).normalized()
	if beam.dot(vessel.linear_velocity) < 0.0:
		beam = -beam
	var dir := beam - up * (0.25 if vessel.radar_altitude() > 1500.0 else -0.1)
	var safe := _ground_escape()
	_fly(safe if safe != Vector3.ZERO else dir.normalized(), lerpf(7.0, 9.0, skill))
	# ısı izini azalt: art yakıcı kapalı
	vessel.ctrl_throttle = 0.55
	# flare: füze yaklaştıkça
	if d < lerpf(1800.0, 3200.0, skill) and _flare_cd <= 0.0:
		if randf() < lerpf(0.5, 0.95, skill):
			vessel.drop_flares()
		_flare_cd = lerpf(0.8, 0.4, skill)


# ------------------------------------------------------------------ yardımcılar

func _find_target() -> Vessel:
	var best: Vessel = null
	var best_d := lerpf(9000.0, 16000.0, skill)
	for n in vessel.get_parent().get_children():
		if n is Vessel and n != vessel and n.team != vessel.team and not n.parts.is_empty() and n.has_pilot():
			var d: float = n.com_global().distance_to(vessel.com_global())
			if d < best_d:
				best_d = d
				best = n
	return best


## Yer tehlikesi varsa kaçış yönü (yukarı + ileri), yoksa sıfır.
func _ground_escape() -> Vector3:
	var agl := vessel.radar_altitude()
	var vs := vessel.vertical_speed()
	var margin := 350.0 + maxf(-vs, 0.0) * 5.0
	if agl > margin:
		return Vector3.ZERO
	var up := Planet.up_at(vessel.com_global())
	var fwd := vessel.linear_velocity.normalized() if vessel.linear_velocity.length() > 10.0 else vessel.forward()
	var hf := (fwd - up * fwd.dot(up)).normalized()
	return (hf + up * 1.2).normalized()


## Burnu `dir` yönüne çevir: hedefi kaldırma düzlemine yatır ve çek (point-and-pull).
func _fly(dir: Vector3, g_limit: float) -> void:
	var b := vessel.global_basis
	var local := (b.inverse() * dir).normalized()
	var w := vessel.local_angular_velocity()
	var ang := acos(clampf(-local.z, -1.0, 1.0))
	# yatış: büyük açıda hedefi gövdenin "yukarı" eksenine getir (yat ve çek);
	# küçük açıda yatarak dön (yanal hata kadar yatış açısı) — ince nişan
	var k := smoothstep(0.1, 0.25, ang)
	var coarse := atan2(local.x, local.y)
	var lateral := atan2(local.x, -local.z)
	var bank_goal := clampf(rad_to_deg(lateral) * 9.0, -70.0, 70.0)
	var fine := deg_to_rad(bank_goal - vessel.roll_deg())
	vessel.ctrl_roll = clampf(lerpf(fine, coarse, k) * 1.8 + w.z * 0.5, -1.0, 1.0)
	# yunuslama: hedefin dikey açısı kadar çek; ters yatış hatası büyükse çekme
	var vert := atan2(local.y, -local.z)
	# integral: 1 G tutmak için gereken sürekli çekişi öğrenir (kalıcı nişan hatasını siler)
	var dt := get_physics_process_delta_time()
	if ang < 0.3:
		_pitch_i = clampf(_pitch_i + vert * dt * 2.5, -0.3, 0.6)
		_yaw_i = clampf(_yaw_i + lateral * dt * 1.5, -0.3, 0.3)
	else:
		_pitch_i = move_toward(_pitch_i, 0.0, dt * 0.3)
		_yaw_i = move_toward(_yaw_i, 0.0, dt)
	var pitch := vert * 3.5 - w.x * 0.6 + _pitch_i
	if absf(atan2(local.x, local.y)) > 1.4 and ang > 0.3:
		pitch = minf(pitch, 0.15)
	if vessel.g_force > g_limit:
		pitch -= (vessel.g_force - g_limit) * 0.35
	vessel.ctrl_pitch = clampf(pitch, -0.5, 1.0)
	# sapma: son nişan için dümen
	var yaw := lateral * 4.0 + _yaw_i if ang < 0.25 else 0.0
	vessel.ctrl_yaw = clampf(yaw + w.y * 1.0, -1.0, 1.0)
