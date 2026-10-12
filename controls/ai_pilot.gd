class_name AIPilot
extends Node
## Düşman pilot yapay zekası. Durumlar:
##   DEVRİYE  — otopilotla irtifa/hız tutup iki yön arasında tur atar
##   ÇATIŞMA  — uzakta önleme (hedefin varacağı yere), yakında öncülü takip (top),
##              aşma tehlikesinde gecikmeli takip (lag) + yüksek yo-yo, hedef kaçarsa alçak yo-yo.
##              Füzeyi yalnız atış zarfında atar (arkadan uzak, kafa kafaya kısa menzil).
##   SAVUNMA  — kendine kilitli füze: IR'ye karşı gaz kes + dik dön + flare; radara karşı çentik
##              (beam) + alçal + chaff (uzaktaysa soğuk yöne kaç); son anda füzeye dik en sert çekiş
##   KAÇINMA  — kuyruğunda düşman: kırma dönüşü, rastgele jink, makas; kanat adamı varsa
##              düşmanı ona doğru sürükler; enerjisi biterse dalışla ayrılır
##   KOL      — kanat adamı liderin yanında gevşek kolda uçar
##   ENERJİ   — hız çok düştü: yükü boşalt, dalışla hız topla, sonra çatışmaya dön
## Kanat çifti (pair): ortak hedef; yakın olan saldırır, uzaktaki yandan kıskaca alır; düşman
## birini kovalarsa diğeri yardıma gelir, kovalanan onu arkadaşına sürükler.
## Enerji: hız + irtifa izlenir; köşe hızının altında G azalır, yavaşken dalış, hızlıyken tırmanış.
## Her durumda yer önce gelir: öngörülü arazi kaçınma ve dalış sınırı, G/AoA sınırı.
## `skill` (0..1, LEVELS: acemi/tecrübeli/as): tepki süresi, G toleransı, nişan, füze zarfı,
## flare zamanlaması, enerji bilinci.

enum State { PATROL, ENGAGE, DEFEND, EVADE, FORM, EXTEND }
const STATE_NAMES := ["DEVRİYE", "ÇATIŞMA", "SAVUNMA", "KAÇINMA", "KOL", "ENERJİ"]
## Hazır beceri düzeyleri (görevler adla seçebilir: AIPilot.level("as"))
const LEVELS := {"acemi": 0.25, "tecrübeli": 0.55, "as": 0.9}

var vessel: Vessel
var skill := 0.6
var altitude := 2000.0
var speed := 200.0
var leg_time := 45.0
## false: hiç saldırmaz (hedef uçağı, eğitim)
var aggressive := true
## Kanat çifti: kanat adamının lideri / liderin kanat adamı (pair() bağlar)
var leader: AIPilot
var wingman: AIPilot

var state := State.PATROL
var target: Vessel
## Kuyruğumuzdaki düşman (top tehdidi)
var threat: Vessel
var dbg := ""
## Toplam top tetiği süresi (istatistik, testler)
var gun_time := 0.0

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
var _pitch_i := 0.0
var _yaw_i := 0.0
# algılama gecikmesi (tepki süresi)
var _msl_t := 0.0
var _six_t := 0.0
# enerji
var _spd := 0.0
var _energy := 0.0
var _ps := 0.0
# savunma manevraları
var _jink_t := 0.0
var _jink_ang := 0.0
var _break_side := 1.0
var _mode := ""
# arazi öngörüsü (10 Hz)
var _terrain_t := 0.0
var _terrain_ahead := false
# öğrenilen "çekiş başına G" katsayısı: G ≈ 1 + kazanç·çekiş·v² (başlangıç tahmini)
var _g_gain := 1.6e-4
var _escaping := false


## Uçağın yapay zeka pilotu (yoksa null).
static func of(v: Variant) -> AIPilot:
	if not is_instance_valid(v):
		return null
	for c in v.get_children():
		if c is AIPilot:
			return c
	return null


## İki uçağı lider + kanat adamı olarak bağlar.
static func pair(lead: Vessel, wing: Vessel) -> void:
	var a := of(lead)
	var b := of(wing)
	if a and b:
		a.wingman = b
		b.leader = a


## Beceri adı ("acemi", "tecrübeli", "as") ya da sayı ("0.7") → 0..1.
static func level(lvl: String) -> float:
	if LEVELS.has(lvl):
		return LEVELS[lvl]
	return clampf(float(lvl), 0.0, 1.0) if lvl.is_valid_float() else 0.6


func _ready() -> void:
	_ap.level = true
	_ap.hold_altitude = true
	_ap.hold_heading = true
	_ap.hold_speed = true
	_ap.target_altitude = altitude
	_ap.target_speed = speed
	_break_side = 1.0 if randf() < 0.5 else -1.0
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
	_terrain_t -= delta
	_escaping = false
	_update_energy(delta)
	if _scan_t <= 0.0:
		_scan_t = lerpf(0.8, 0.3, skill)
		target = _pick_target() if aggressive else null
		threat = _find_threat() if aggressive else null

	# tehditler ancak tepki süresi kadar sonra fark edilir
	var incoming := vessel.incoming_missile()
	var threat_d := incoming.global_position.distance_to(vessel.com_global()) if incoming else INF
	_msl_t = _msl_t + delta if incoming and threat_d < lerpf(3000.0, 6000.0, skill) else 0.0
	_six_t = _six_t + delta if is_instance_valid(threat) else 0.0

	var prev := state
	if incoming and _msl_t > _reaction() * 0.7:
		state = State.DEFEND
	elif is_instance_valid(threat) and _six_t > _reaction():
		state = State.EVADE
	elif is_instance_valid(target):
		state = State.EXTEND if _want_extend() else State.ENGAGE
	elif _mate_lead():
		state = State.FORM
	else:
		state = State.PATROL
	if state == State.PATROL and prev != State.PATROL:
		# devriyeye dönüş: bulunduğu yönden devam
		_ap.target_heading = vessel.heading_deg()
		_t = 0.0

	vessel.ctrl_fire = false
	vessel.ctrl_brakes = false
	match state:
		State.PATROL:
			_patrol(delta)
		State.ENGAGE:
			_engage(delta)
		State.DEFEND:
			_defend(incoming, threat_d)
		State.EVADE:
			_evade(delta)
		State.FORM:
			_form()
		State.EXTEND:
			_extend()
	if vessel.ctrl_fire and vessel.selected_weapon == Vessel.WEAPON_GUN:
		gun_time += delta


# ------------------------------------------------------------------ beceri / enerji

## Tehdidi fark edip tepki verme süresi (s).
func _reaction() -> float:
	return lerpf(1.1, 0.25, skill)


## Dayanabildiği en yüksek G.
func _g_max() -> float:
	return lerpf(5.5, 8.8, skill)


func _aoa_max() -> float:
	return lerpf(12.0, 15.0, skill)


func _v_low() -> float:
	return maxf(speed * 0.6, 80.0)


func _v_corner() -> float:
	return maxf(speed * 0.85, 110.0)


func _update_energy(delta: float) -> void:
	_spd = vessel.airspeed()
	var e := vessel.altitude() + _spd * _spd / (2.0 * 9.81)
	if _energy != 0.0:
		_ps = lerpf(_ps, (e - _energy) / maxf(delta, 0.001), clampf(delta * 1.5, 0.0, 1.0))
	_energy = e


## Enerjiye göre kullanılabilir G: köşe hızının altında yük azalır (hız kanamasın).
## Acemi enerjiyi daha az önemser (hız kaybeder ama AoA sınırı stall'dan korur).
func _energy_g(g: float) -> float:
	var k := clampf((_spd - _v_low()) / (_v_corner() - _v_low()), 0.0, 1.0)
	return lerpf(g, lerpf(3.0, g, k), lerpf(0.4, 1.0, skill))


## Hız çok düştü ve hedef önümüzde değil: dalışla hız topla (ENERJİ durumu).
func _want_extend() -> bool:
	var agl := vessel.radar_altitude()
	var to := target.com_global() - vessel.com_global()
	var shot := to.length() < 1800.0 and vessel.forward().angle_to(to) < deg_to_rad(30.0)
	if state == State.EXTEND:
		return _spd < _v_corner() and agl > 500.0 and not shot
	return _spd < _v_low() * 0.92 and agl > 900.0 and not shot and skill > 0.3


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
		_escaping = true
		_fly(safe, _g_max())
		vessel.ctrl_throttle = 1.0
		return
	vessel.ctrl_pitch = pitch
	vessel.ctrl_roll = roll
	vessel.ctrl_yaw = clampf(w.y * 2.0, -1.0, 1.0)
	vessel.ctrl_throttle = out["throttle"] if out["throttle"] != null else 0.7
	_mode = ""
	dbg = "devriye"


func _engage(delta: float) -> void:
	var me := vessel.com_global()
	var tp := target.com_global()
	var tv := target.linear_velocity
	var to := tp - me
	var dist := to.length()
	var los := to / maxf(dist, 1.0)
	var closing := (vessel.linear_velocity - tv).dot(los)
	# hedefin bize bakma açısı: 1 = tam kafa kafaya, -1 = tam arkasındayız
	var aspect := target.forward().dot(-los)
	var ata := vessel.forward().angle_to(to)
	var up := Planet.up_at(me)
	var agl := vessel.radar_altitude()

	# nişan gürültüsü (düşük beceri = titrek nişan), yavaşça değişir
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = randf_range(0.5, 1.0)
		_aim_noise = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (1.0 - skill) * 0.012

	_select_weapon(dist)
	var gun: GunModule = null
	for m in vessel.modules:
		if m is GunModule and m.ammo > 0:
			gun = m
			m.gimbal_deg = lerpf(0.4, 1.6, skill)
			m.aim_target = target

	var g := _energy_g(_g_max())
	var aim := tp
	var flank: Variant = _flank_point(tp, dist, up)
	if flank != null:
		# kıskaç: arkadaş doğrudan saldırıyor, ben yandan açılıyorum
		aim = flank
		_mode = "kıskaç"
	elif aspect > 0.5 and dist < 3500.0 and dist > 250.0 and vessel.selected_weapon == Vessel.WEAPON_GUN:
		# kafa kafaya: yana açıl, geçişten sonra dönüş için yer kalsın (iki daireli dönüş)
		var side := (to.cross(up)).normalized()
		if side.dot(vessel.linear_velocity) < 0.0:
			side = -side
		aim = tp + side * 700.0
		_mode = "kafa"
	elif dist > 2500.0:
		# önleme: hedefin buluşma anındaki yeri (usta daha ileriyi kestirir)
		var tgo := clampf(dist / maxf(closing, 80.0), 0.0, lerpf(2.0, 8.0, skill))
		aim = tp + tv * tgo
		_mode = "önle"
	else:
		var overshoot := aspect < 0.3 and dist < lerpf(450.0, 700.0, skill) and (closing > 60.0 or (ata > deg_to_rad(55.0) and closing > 10.0))
		if overshoot and skill > 0.2:
			# gecikmeli takip: hedefin gerisine, hızlıysak yukarı (yüksek yo-yo) — öne kaçma
			aim = tp - tv.normalized() * clampf(dist * 0.8, 150.0, 500.0)
			if _spd > _v_corner() * 0.95:
				aim += up * clampf(dist * 0.5, 100.0, 400.0)
			_mode = "gecikmeli"
		elif ata < deg_to_rad(40.0) and dist < 1500.0 and gun:
			# öncülü takip: top mermisinin buluşma noktası
			aim = me + gun.lead_direction(target) * dist
			_mode = "öncülü"
		else:
			aim = tp
			_mode = "saf"
			# alçak yo-yo: hedef uzaklaşıyor ve yavaşız → biraz alçalıp hız al, içeriden kes
			if closing < -10.0 and dist > 900.0 and _spd < _v_corner() and agl > 1500.0:
				aim -= up * dist * 0.25
				_mode = "alçak yo-yo"
	var dir := (aim - me).normalized() + _aim_noise
	# hızlıyız ve hedef yakında, yanımızda: hızı irtifaya çevir (dönüş yarıçapı küçülsün)
	if _spd > speed * 1.2 and dist < 2000.0 and ata > deg_to_rad(45.0) and skill > 0.4:
		dir = (dir + up * 0.5).normalized()
	# daire kilitlenmesi (iki taraf da kuyruk kovalıyor): bir süre dikeye çık (yüksek yo-yo)
	var off := vessel.forward().angle_to(to)
	_stale = _stale + delta if (dist < 1600.0 and off > deg_to_rad(25.0)) else maxf(_stale - delta * 2.0, 0.0)
	if _stale > lerpf(16.0, 8.0, skill):
		_yoyo = 5.0 if _spd > _v_low() else 0.0
		_stale = 0.0
	_yoyo -= delta
	if _yoyo > 0.0 and vessel.radar_altitude() < 6000.0:
		dir = (dir + up * 1.4).normalized()
	# çarpışmadan kaçın
	if dist < 220.0 and closing > 40.0:
		dir = (to.cross(up).normalized() + up * 0.5).normalized()
	dir = _deconflict(dir, tp, dist, up)

	# gaz: uzakta ya da yavaşken art yakıcı; arkasındayken ~450 m'de hız eşle (öne kaçmasın)
	if _mode == "gecikmeli" and closing > 40.0 and dist < 500.0:
		vessel.ctrl_throttle = 0.0
		vessel.ctrl_brakes = skill > 0.4 and _spd > _v_corner()
	elif dist > 1500.0 or _spd < _v_corner():
		vessel.ctrl_throttle = 1.0
	elif aspect < -0.5:
		var want_closing := clampf((dist - 450.0) * 0.25, -40.0, 120.0)
		vessel.ctrl_throttle = clampf(0.62 + (want_closing - closing) * 0.03, 0.0, 1.0)
	else:
		vessel.ctrl_throttle = 0.9
	if _steer(dir, g):
		return

	# ateş
	var lead_dir := gun.lead_direction(target) if gun else los
	var err := vessel.forward().angle_to(lead_dir)
	dbg = "%s err=%.0f asp=%+.2f kap=%+d hız=%d Ps=%+d" % [_mode, rad_to_deg(err), aspect, closing, _spd, _ps]
	if vessel.selected_weapon == Vessel.WEAPON_MISSILE or vessel.selected_weapon == Vessel.WEAPON_RADAR:
		_missile_shot(delta, dist, aspect)
	elif gun and dist < lerpf(800.0, 1100.0, skill) and err < deg_to_rad(gun.gimbal_deg) + atan2(lerpf(9.0, 6.0, skill), dist) and not _mate_in_line(dist):
		vessel.ctrl_fire = true


## Kanat çifti ayrımı: ikimiz aynı hedefin yakınındaysak hedefe uzak olan yana ve yukarı
## kayar (aynı noktaya dalıp çarpışmasınlar); çok yakınsak doğrudan uzaklaş.
func _deconflict(dir: Vector3, tp: Vector3, dist: float, up: Vector3) -> Vector3:
	var mate := _mate()
	if mate == null:
		return dir
	var me := vessel.com_global()
	var mp := mate.vessel.com_global()
	var sep := me - mp
	if sep.length() < 250.0:
		_mode += " ayrıl"
		return (dir + sep.normalized() * 1.5 + up * 0.3).normalized()
	if mate.target == target and dist < 2200.0 and mp.distance_to(tp) < dist and sep.length() < 900.0:
		# örtme (cover): önde saldıran arkadaşın yanında, biraz yukarıda kal
		var side := (tp - mp).cross(up).normalized()
		if side.dot(sep) < 0.0:
			side = -side
		_mode += " ört"
		return ((tp + side * 400.0 + up * 250.0 - me).normalized() + dir).normalized()
	return dir


## Arkadaş ateş hattında mı (dost ateşi yok).
func _mate_in_line(dist: float) -> bool:
	var mate := _mate()
	if mate == null:
		return false
	var to := mate.vessel.com_global() - vessel.com_global()
	return to.length() < dist + 300.0 and vessel.forward().angle_to(to) < deg_to_rad(6.0)


## Kanat çifti kıskacı: ikimiz de aynı hedefe saldırırken hedefe uzak olan yandan açılır.
## Hedef arkadaşı kovalıyorsa kıskaç yok: doğrudan yardıma (null).
func _flank_point(tp: Vector3, dist: float, up: Vector3) -> Variant:
	var mate := _mate()
	if mate == null or mate.target != target or dist < 2200.0 or skill < 0.3:
		return null
	var mp := mate.vessel.com_global()
	if _chasing(target, mate.vessel):
		_mode = "yardım"
		return null
	if mate.state != State.ENGAGE or mp.distance_to(tp) > dist:
		return null
	var axis := tp - mp
	var side := axis.cross(up).normalized()
	if side.dot(vessel.com_global() - tp) < 0.0:
		side = -side
	return tp + side * minf(dist * 0.6, 2500.0)


func _select_weapon(dist: float) -> void:
	var radar := vessel.radar()
	var has_rf := vessel.radar_missiles_left() > 0 and radar != null and target in radar.contacts
	if has_rf and dist > 3000.0 and dist < MissileModule.RADAR_RANGE * lerpf(0.6, 0.85, skill):
		vessel.selected_weapon = Vessel.WEAPON_RADAR
		vessel.designated = target
	elif vessel.missiles_left() > 0 and dist > 800.0 and dist < MissileModule.SEEK_RANGE:
		vessel.selected_weapon = Vessel.WEAPON_MISSILE
		vessel.designated = target
	elif vessel.gun_ammo() > 0:
		vessel.selected_weapon = Vessel.WEAPON_GUN


## Füze atışı: kilit + atış zarfı. Zarf açıya bağlı: IR arkadan uzun, kafa kafaya kısa menzil;
## radar füzesi kafa kafaya (yüksek yaklaşma) daha uzaktan. Acemi zarf dışından da atar,
## usta uçuştaki füzesinin sonucunu bekler.
func _missile_shot(delta: float, dist: float, aspect: float) -> void:
	var rf := vessel.selected_weapon == Vessel.WEAPON_RADAR
	var locked := false
	for m in vessel.modules:
		if m is MissileModule and m.loaded and m.radar_guided == rf and m.target == target:
			locked = true
	_fire_hold -= delta
	var rear := clampf((1.0 - aspect) * 0.5, 0.0, 1.0)
	var r_max: float = MissileModule.RADAR_RANGE * lerpf(0.8, 0.45, rear) if rf else MissileModule.SEEK_RANGE * lerpf(0.35, 0.75, rear)
	r_max *= lerpf(1.2, 0.95, skill)
	var r_min := MissileModule.RADAR_MIN_RANGE * 1.3 if rf else 600.0
	var in_flight := 0
	for mi in Missile.active:
		if mi.shooter == vessel and mi.victim == target:
			in_flight += 1
	var hold := in_flight > 0 and skill > 0.4 and dist > 2000.0
	if locked and _missile_cd <= 0.0 and dist < r_max and dist > r_min and not hold:
		_fire_hold = 0.1
		_missile_cd = lerpf(24.0, 14.0, skill) if rf else lerpf(12.0, 6.0, skill)
	vessel.ctrl_fire = _fire_hold > 0.0


## Kendine kilitli füze. Uzak radar füzesi: soğuk yöne kaç (sürükle, füze enerjisini harcasın);
## yakında: füzeye dik (beam/çentik), radar füzesine karşı alçal (arkada yer yankısı), IR'ye
## karşı gazı kes; zamanında flare/chaff; çarpmadan hemen önce görüş hattına dik en sert çekiş.
func _defend(m: Missile, d: float) -> void:
	var me := vessel.com_global()
	var up := Planet.up_at(me)
	var agl := vessel.radar_altitude()
	var los := (m.global_position - me) / maxf(d, 1.0)
	var closing := (m.velocity - vessel.linear_velocity).dot(-los)
	var tti := d / maxf(closing, 60.0)
	var radar := m.is_radar()
	var beam := los.cross(up).normalized()
	if beam.dot(vessel.linear_velocity) < 0.0:
		beam = -beam
	var dir: Vector3
	var g := _g_max()
	if tti < lerpf(1.0, 2.0, skill):
		# son an: kaldırma vektörünü görüş hattına dik tut, en sert çek
		var lift := vessel.global_basis.y
		lift -= los * lift.dot(los)
		if agl < 1200.0 and lift.dot(up) < 0.0:
			lift = -lift
		dir = (vessel.forward() * 0.2 + lift.normalized()).normalized()
		_mode = "son an"
	elif radar and d > Missile.ACTIVE_RANGE * 1.1 and skill > 0.4:
		# soğuk yöne kaç: füze uzun yolda enerjisini harcasın
		var cold := -los - up * los.dot(-up)
		dir = (cold.normalized() - up * (0.25 if agl > 1500.0 else 0.0)).normalized()
		_mode = "soğuk"
	else:
		var down := 0.0
		if radar:
			down = 0.35 if agl > 700.0 else 0.0
		elif agl > 1500.0:
			down = 0.2
		dir = (beam - up * down).normalized()
		_mode = "çentik" if radar else "dik"
	# ısı izini azalt (IR): art yakıcı kapalı, rölantiye yakın; çok yavaşsak kuru tam güç
	if radar:
		vessel.ctrl_throttle = 1.0
	elif _spd < _v_low():
		vessel.ctrl_throttle = 0.85
	else:
		vessel.ctrl_throttle = 0.35
	# karşı tedbir: IR'ye flare, radara chaff (aynı fişeklik)
	var window := lerpf(2.5, 4.5, skill) if not radar else 3.0
	if _flare_cd <= 0.0 and (tti < window or _mode == "son an"):
		if randf() < lerpf(0.55, 0.97, skill):
			if radar:
				vessel.drop_chaff()
			else:
				vessel.drop_flares()
		_flare_cd = lerpf(0.8, 0.35, skill) if _mode != "son an" else 0.35
	dbg = "%s tti=%.1f d=%d %s" % [_mode, tti, d, "radar" if radar else "IR"]
	_steer(dir, g)


## Kuyruğumuzdaki düşmandan top savunması.
func _evade(delta: float) -> void:
	var me := vessel.com_global()
	var up := Planet.up_at(me)
	var bp := threat.com_global()
	var to_b := bp - me
	var d := to_b.length()
	var b_dir := to_b / maxf(d, 1.0)
	var b_ata := threat.forward().angle_to(-to_b)
	var vel_dir := vessel.linear_velocity.normalized() if vessel.linear_velocity.length() > 10.0 else vessel.forward()
	var closing := (threat.linear_velocity - vessel.linear_velocity).dot(-b_dir)
	var behind := vessel.forward().dot(b_dir)
	var agl := vessel.radar_altitude()
	# saldırgana doğru, hız eksenine dik yön (kırma dönüşü onun tarafına)
	var perp := to_b - vel_dir * to_b.dot(vel_dir)
	if perp.length() < d * 0.15:
		perp = vessel.global_basis.x * _break_side + up * 0.3
	perp = perp.normalized()
	var mate := _mate()
	var g := _g_max()
	var dir: Vector3
	if d < 450.0 and closing > 25.0 and behind > -0.6:
		# makas: saldırgan üstümüze biniyor — ona doğru dön, yavaşla, öne kaçsın
		_mode = "makas"
		dir = (perp + vel_dir * 0.1).normalized()
		vessel.ctrl_throttle = 0.0 if _spd > _v_low() else 0.8
		vessel.ctrl_brakes = _spd > _v_low() * 1.1
	elif d < lerpf(700.0, 1100.0, skill) and b_ata < deg_to_rad(14.0):
		# jink: nişan çözümünü bozmak için rastgele düzlem değiştir
		_mode = "jink"
		_jink_t -= delta
		if _jink_t <= 0.0:
			_jink_t = randf_range(0.5, 1.2) * lerpf(1.6, 1.0, skill)
			_jink_ang = randf_range(deg_to_rad(60.0), deg_to_rad(150.0)) * (1.0 if randf() < 0.5 else -1.0)
		dir = (perp.rotated(vel_dir, _jink_ang) + vel_dir * 0.1).normalized()
		vessel.ctrl_throttle = 1.0
	elif mate and mate.state != State.PATROL and d > 1100.0 and _spd > _v_low() and skill > 0.35:
		# sürükle: saldırganı kanat arkadaşının önüne getir (o arkadan vursun)
		_mode = "sürükle"
		var to_m := mate.vessel.com_global() - me
		to_m -= up * to_m.dot(up)
		dir = (to_m.normalized() + perp * 0.35 * sin(_t * 1.3)).normalized()
		vessel.ctrl_throttle = 1.0
	elif _spd < _v_low() and agl > 2500.0 and d > 900.0:
		# enerji bitti: dalışla ayrıl
		_mode = "dalış"
		var h := vel_dir - up * vel_dir.dot(up)
		dir = (h.normalized() - up * 0.8).normalized()
		vessel.ctrl_throttle = 1.0
	else:
		# kırma dönüşü: saldırgana doğru en sert dönüş (açı farkı büyüsün)
		_mode = "kır"
		dir = (perp + vel_dir * 0.15).normalized()
		vessel.ctrl_throttle = 1.0
	# ateş fırsatı (makasta öne geçtiyse)
	if is_instance_valid(target) and target == threat and vessel.gun_ammo() > 0 and d < 900.0:
		vessel.selected_weapon = Vessel.WEAPON_GUN
		if vessel.forward().angle_to(to_b) < deg_to_rad(2.0):
			vessel.ctrl_fire = true
	dbg = "%s d=%d açı=%.0f kap=%+d hız=%d" % [_mode, d, rad_to_deg(b_ata), closing, _spd]
	_steer(dir, g)


## Kanat adamı: liderin sağ arkasında gevşek kol (350 m yan, 150 m geri, 40 m yukarı).
func _form() -> void:
	var lv := leader.vessel
	var lp := lv.com_global()
	var lvel := lv.linear_velocity
	var me := vessel.com_global()
	var up := Planet.up_at(lp)
	var lf := lvel.normalized() if lvel.length() > 20.0 else lv.forward()
	var lfh := (lf - up * lf.dot(up)).normalized()
	var right := lfh.cross(up)
	var slot := lp + right * 350.0 - lfh * 150.0 + up * 40.0
	var err := slot - me
	var aim := slot + lvel * 3.0
	var dir := (aim - me).normalized()
	if me.distance_to(lp) < 120.0:
		dir = (dir + (me - lp).normalized()).normalized()
	var along := err.dot(lfh)
	var rel := (lvel - vessel.linear_velocity).dot(lfh)
	vessel.ctrl_throttle = 1.0 if err.length() > 2000.0 else clampf(0.6 + along * 0.004 + rel * 0.05, 0.1, 1.0)
	_mode = "kol"
	dbg = "kol hata=%d ileri=%+d" % [err.length(), along]
	_steer(dir, 4.0)


## Enerji topla: yükü boşalt (yaklaşık 0.5 G), hafif dalış, art yakıcı.
func _extend() -> void:
	var up := Planet.up_at(vessel.com_global())
	var v := vessel.linear_velocity.normalized() if vessel.linear_velocity.length() > 10.0 else vessel.forward()
	var h := v - up * v.dot(up)
	var down := 0.35 if vessel.radar_altitude() > 1200.0 else 0.0
	vessel.ctrl_throttle = 1.0
	_mode = "enerji"
	dbg = "enerji hız=%d Ps=%+d" % [_spd, _ps]
	_steer((h.normalized() - up * down).normalized(), 2.5)


# ------------------------------------------------------------------ yardımcılar

## Kanat çiftindeki arkadaş (canlı ve uçuyorsa), yoksa null.
func _mate() -> AIPilot:
	var m := leader if leader != null else wingman
	if not is_instance_valid(m) or not is_instance_valid(m.vessel) or m.vessel.parts.is_empty() or not m.vessel.has_pilot():
		return null
	return m


## Kanat adamıyım ve liderim uçuyor.
func _mate_lead() -> bool:
	return leader != null and _mate() == leader


## `a` uçağı `b`yi kovalıyor mu (burnu ona dönük, yakın).
func _chasing(a: Vessel, b: Vessel) -> bool:
	var to := b.com_global() - a.com_global()
	return to.length() < 3000.0 and a.forward().angle_to(to) < deg_to_rad(40.0)


## Hedef seçimi: en yakın düşman; arkadaşın hedefi yakınsa ona odaklan (ortak hedef).
func _pick_target() -> Vessel:
	var own := _find_target()
	var mate := _mate()
	if mate == null or not is_instance_valid(mate.target) or mate.target.parts.is_empty():
		return own
	var mt: Vessel = mate.target
	if own == null:
		return mt
	var me := vessel.com_global()
	return mt if mt.com_global().distance_to(me) < own.com_global().distance_to(me) * 1.5 else own


## Hedef yalnız sensörle bulunur (Detection): kendi radarının temasları, göz (2.5 km),
## veri bağı (erken uyarı radarı, AWACS, SAM ve diğer avcıların gördükleri) ve karıştırma
## yayını (home-on-jam). Alçaktan, araziye saklanarak gelen uçak fark edilmeyebilir.
## Zaten izlenen hedef görsel menzilin iki katına kadar bırakılmaz.
func _find_target() -> Vessel:
	var me := vessel.com_global()
	var r := vessel.radar()
	var known := Detection.known(vessel.team)
	var best: Vessel = null
	var best_d := lerpf(9000.0, 16000.0, skill) * 2.0
	for n in vessel.get_parent().get_children():
		if n is Vessel and n != vessel and n.team != vessel.team and n.team != "sivil" and not n.parts.is_empty() and n.has_pilot():
			var d: float = n.com_global().distance_to(me)
			var sensed: bool = d < Detection.VISUAL_RANGE \
				or (r != null and n in r.contacts) \
				or n in known \
				or (n.jamming() and d < EcmModule.EMIT_RANGE * 0.5) \
				or (n == target and d < Detection.VISUAL_RANGE * 2.0)
			if not sensed:
				continue
			if n.jamming():
				d *= 0.45
			if d < best_d:
				best_d = d
				best = n
	return best


## Kuyruğumuzda, burnu bize dönük, top/kısa füze menzilindeki düşman (yoksa null).
## Zaten tehdit varsa çıkış eşiği daha geniş (titreşmesin).
func _find_threat() -> Vessel:
	var me := vessel.com_global()
	var cone := deg_to_rad(45.0 if is_instance_valid(threat) else 30.0)
	var rng := 2200.0 if is_instance_valid(threat) else 1800.0
	var best: Vessel = null
	var best_d := rng
	for n in vessel.get_parent().get_children():
		if n is Vessel and n != vessel and n.team != vessel.team and n.team != "sivil" and not n.parts.is_empty() and n.has_pilot():
			var to: Vector3 = me - n.com_global()
			var d := to.length()
			# kafa kafaya geçiş tehdit değil: o bizim önümüzdeyse saldırı sürer
			if d < best_d and n.forward().angle_to(to) < cone and vessel.forward().dot(-to / maxf(d, 1.0)) < 0.3:
				best_d = d
				best = n
	return best


## Son güvenlik katmanı: yer tehlikesi varsa kaçış (true döner), yoksa dalış sınırıyla uç.
func _steer(dir: Vector3, g: float) -> bool:
	var safe := _ground_escape()
	if safe != Vector3.ZERO:
		_escaping = true
		_fly(safe, _g_max())
		vessel.ctrl_throttle = 1.0
		vessel.ctrl_brakes = false
		dbg = "YER! " + _mode
		return true
	_fly(_limit_dive(dir.normalized()), g)
	return false


## Yere doğru isteği sınırla: alçalma hızı yere kalan yüksekliği ~7 sn'den önce tüketmesin.
func _limit_dive(dir: Vector3) -> Vector3:
	var up := Planet.up_at(vessel.com_global())
	var max_down := clampf(maxf(vessel.radar_altitude() - 300.0, 0.0) / 7.0 / maxf(_spd, 60.0), 0.0, 1.0)
	if -dir.dot(up) <= max_down:
		return dir
	var h := dir - up * dir.dot(up)
	if h.length() < 0.05:
		h = vessel.forward() - up * vessel.forward().dot(up)
	return h.normalized() * sqrt(1.0 - max_down * max_down) - up * max_down


## Yer tehlikesi varsa kaçış yönü (yukarı + ileri), yoksa sıfır. Hem alttaki yer hem de
## hız yönünde 2-8 sn ilerideki arazi (sırt, dağ yamacı) denetlenir.
func _ground_escape() -> Vector3:
	var p := vessel.com_global()
	var agl := vessel.radar_altitude()
	var vs := vessel.vertical_speed()
	var danger := agl < 350.0 + maxf(-vs, 0.0) * 5.0
	if _terrain_t <= 0.0:
		_terrain_t = 0.1
		_terrain_ahead = false
		if agl < 3000.0:
			for t: float in [2.0, 4.0, 6.0, 8.0]:
				var q := p + vessel.linear_velocity * t
				var clear := Planet.altitude(q) - maxf(TerrainGen.height(Planet.surface_dir(q)), 0.0)
				if clear < 120.0 + t * 15.0:
					_terrain_ahead = true
					break
	if not danger and not _terrain_ahead:
		return Vector3.ZERO
	var up := Planet.up_at(p)
	var fwd := vessel.linear_velocity.normalized() if vessel.linear_velocity.length() > 10.0 else vessel.forward()
	var hf := (fwd - up * fwd.dot(up)).normalized()
	# tırmanış açısı hıza göre: yavaşken dik çekiş hızı bitirir (stall); yer çok yakınsa yine de çek
	var k := clampf((_spd - _v_low() * 0.8) / maxf(_v_corner() - _v_low() * 0.8, 1.0), 0.0, 1.0)
	var climb := lerpf(0.35, 1.2, k)
	if agl < 150.0 + maxf(-vs, 0.0) * 3.0:
		climb = maxf(climb, 0.8)
	return (hf + up * climb).normalized()


## Burnu `dir` yönüne çevir: hedefi kaldırma düzlemine yatır ve çek (point-and-pull).
## G, hücum açısı (stall) ve yapı zorlanması sınırlı.
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
	# ileri besleme G sınırı: yüksek hızda tam çekiş kanadı koparır. Çekiş başına G
	# (dinamik basınçla, ~v²) uçuşta öğrenilir; komut sınıra göre kırpılır.
	var v2 := maxf(_spd * _spd, 400.0)
	var cmd := vessel.ctrl_pitch
	var dg := vessel.g_force - 1.0
	if absf(cmd) > 0.25 and absf(dg) > 1.0 and signf(cmd) == signf(dg):
		# artışa hızlı, azalışa yavaş uyum (temkinli); saçma örnekleri kırp
		var r := clampf(dg / (cmd * v2), 0.6e-4, 3.0e-4)
		_g_gain = lerpf(_g_gain, r, clampf(dt * (2.0 if r > _g_gain else 0.4), 0.0, 1.0))
	var p_max := maxf((g_limit - 1.0) * 0.9 / (_g_gain * v2), 0.45 if _escaping else 0.15)
	pitch = clampf(pitch, -minf(3.5 / (_g_gain * v2), 0.5), p_max)
	# stall koruması: hücum açısı sınırı, yapı zorlanması
	var aoa := vessel.aoa_deg()
	if aoa > _aoa_max():
		pitch -= (aoa - _aoa_max()) * 0.12
	if vessel.max_stress > 0.75:
		pitch -= (vessel.max_stress - 0.75) * 2.0
	# hız sınırlı komut (yüksek hızda yunuslama salınımı olmasın)
	vessel.ctrl_pitch = move_toward(vessel.ctrl_pitch, clampf(pitch, -0.5, 1.0), dt * 3.0)
	# sapma: son nişan için dümen
	var yaw := lateral * 4.0 + _yaw_i if ang < 0.25 else 0.0
	vessel.ctrl_yaw = clampf(yaw + w.y * 1.0, -1.0, 1.0)
