class_name Wingman
extends AIPilot
## Oyuncunun kanat adamı ("Kanat 2"): AIPilot'un tüm çatışma/savunma/yer güvenliği
## davranışını kullanır; lider bir AIPilot değil oyuncunun uçağıdır (WingFlight.main.vessel).
## Telsiz emirleri (F2 → Kanat adamı):
##   KORU     — kolda uçar; oyuncuya yaklaşan/kuyruğuna giren düşmana saldırır (varsayılan)
##   SALDIR   — oyuncunun seçtiği/kilitlendiği hedefe saldırır; hedef düşünce KORU'ya döner
##   SERBEST  — kendi sensörleriyle bulduğu en yakın düşmanı avlar
##   KOL      — yalnız kol uçuşu (saldırmaz; kendine gelen tehdide karşı savunur)
##   ÜS       — en yakın havaalanına döner (WingFlight oraya varınca uçağı indirir)
## Pistte başlarsa lider havalanınca kalkış koşusu yapar (_takeoff), sonra AIPilot devralır.

enum Order { COVER, ATTACK, FREE, FORM, RTB }
const ORDER_NAMES := ["KORU", "SALDIR", "SERBEST", "KOL", "ÜSSE"]
## Kol yeri: liderin sağ arkası (yan, geri, yukarı — metre)
const SLOT := Vector3(220.0, 15.0, 110.0)

var lead: Vessel
var order := Order.COVER
var order_target: Vessel
## Pistte bekliyor / kalkış koşusunda
var on_runway := false
var _rolling := false
var _runway_heading := 0.0
var _thr_i := 0.0


func _ready() -> void:
	super()
	if on_runway:
		_runway_heading = vessel.heading_deg()


func set_order(o: Order, tgt: Vessel = null) -> void:
	order = o
	order_target = tgt
	_scan_t = 0.0


func _lead_ok() -> bool:
	return is_instance_valid(lead) and not lead.parts.is_empty() and lead.has_pilot()


func _lead_grounded() -> bool:
	return lead.radar_altitude() < 40.0 and lead.airspeed() < 70.0


func _physics_process(delta: float) -> void:
	if on_runway:
		_takeoff(delta)
		return
	super(delta)


# ------------------------------------------------------------------ kalkış

## Lider havalanana dek pistte bekle; sonra tam gaz, 75 m/s'de burnu kaldır, 60 m'de takım yukarı.
func _takeoff(_delta: float) -> void:
	if not is_instance_valid(vessel) or vessel.parts.is_empty() or not vessel.has_pilot():
		return
	var w := vessel.local_angular_velocity()
	if not _rolling:
		vessel.parking_brake = true
		vessel.ctrl_throttle = 0.0
		if _lead_ok() and (lead.radar_altitude() > 15.0 or lead.ground_speed() > 55.0):
			_rolling = true
			dbg = "kalkış koşusu"
		return
	vessel.parking_brake = false
	vessel.ctrl_brakes = false
	vessel.ctrl_throttle = 1.0
	var alt := vessel.radar_altitude()
	var on_ground := alt < 3.5
	var pitch := 12.0 if vessel.airspeed() > 75.0 else 0.0
	if alt > 60.0:
		vessel.gear_down = false
	vessel.ctrl_pitch = clampf((pitch - vessel.pitch_deg()) * 0.08 - w.x * 1.5, -1.0, 1.0)
	vessel.ctrl_roll = clampf(-vessel.roll_deg() * 0.04 + w.z * 1.0, -1.0, 1.0)
	var herr := wrapf(_runway_heading - vessel.heading_deg(), -180.0, 180.0)
	vessel.ctrl_yaw = clampf(herr * 0.1, -1.0, 1.0) if on_ground else clampf(w.y * 2.0, -1.0, 1.0)
	_mode = "kalkış"
	dbg = "kalkış hız=%d irt=%d" % [vessel.airspeed(), alt]
	if alt > 250.0:
		on_runway = false
		vessel.gear_down = false
		state = State.FORM


# ------------------------------------------------------------------ emirler → hedef seçimi

func _pick_target() -> Vessel:
	match order:
		Order.FORM, Order.RTB:
			return null
		Order.ATTACK:
			if _alive(order_target):
				return order_target
			return null
		Order.FREE:
			return _find_target()
	return _cover_target()


## Koruma: oyuncuyu kovalayan ya da ona 6 km'den yakın düşman (kovalayan öncelikli).
func _cover_target() -> Vessel:
	if not _lead_ok():
		return _find_target()
	var lp := lead.com_global()
	var best: Vessel = null
	var best_s := INF
	for n in vessel.get_parent().get_children():
		if not (n is Vessel) or n == vessel or n.team == vessel.team or n.team == "sivil" or not _alive(n):
			continue
		var d: float = n.com_global().distance_to(lp)
		var keep := n == target and d < 9000.0
		if d > 6000.0 and not keep and not _chasing(n, lead):
			continue
		var s := d * (0.3 if _chasing(n, lead) else 1.0)
		if s < best_s:
			best_s = s
			best = n
	return best


func _alive(v: Variant) -> bool:
	return is_instance_valid(v) and not v.parts.is_empty() and v.cockpit() != null and v.has_pilot()


## Kolda uçulacak lider var mı (yoksa DEVRİYE: üsse dönüş ya da liderin üstünde tur).
func _mate_lead() -> bool:
	return order != Order.RTB and _lead_ok() and not _lead_grounded()


# ------------------------------------------------------------------ kol / dönüş

func _form() -> void:
	var lp := lead.com_global()
	var lvel := lead.linear_velocity
	var me := vessel.com_global()
	var up := Planet.up_at(lp)
	var lf := lvel.normalized() if lvel.length() > 20.0 else lead.forward()
	var lfh := (lf - up * lf.dot(up)).normalized()
	var right := lfh.cross(up)
	var slot := lp + right * SLOT.x + up * SLOT.y - lfh * SLOT.z
	var err := slot - me
	var aim := slot + lvel * 3.0
	var dir := (aim - me).normalized()
	if me.distance_to(lp) < 90.0:
		dir = (dir + (me - lp).normalized()).normalized()
	var along := err.dot(lfh)
	var rel := (lvel - vessel.linear_velocity).dot(lfh)
	# integral: kalıcı geride/önde kalma hatasını siler
	_thr_i = clampf(_thr_i + along * 0.0006 * get_physics_process_delta_time(), -0.3, 0.3) if err.length() < 1500.0 else 0.0
	vessel.ctrl_throttle = 1.0 if err.length() > 2000.0 else clampf(0.6 + _thr_i + along * 0.004 + rel * 0.05, 0.05, 1.0)
	vessel.ctrl_brakes = along < -150.0 and rel < -15.0
	_mode = "kol"
	dbg = "kol hata=%d ileri=%+d" % [err.length(), along]
	_steer(dir, 4.0)


## Üsse dönüş ya da lider yerdeyse onun üstünde tur: otopilotla yön/irtifa.
func _patrol(delta: float) -> void:
	var goal := WingFlight.home_point(vessel) if order == Order.RTB or not _lead_ok() else lead.com_global()
	var me := vessel.com_global()
	var fr := Planet.local_basis(me)
	var to := goal - me
	var brg := rad_to_deg(atan2(to.dot(fr.x), -to.dot(fr.z)))
	var hd := (to - fr.y * to.dot(fr.y)).length()
	# yakındaysa çevresinde tur (hedef yönüne dik)
	_ap.target_heading = fposmod(brg + (80.0 if hd < 2500.0 else 0.0), 360.0)
	_ap.target_altitude = 1500.0
	_t = 0.0
	super(delta)
	_mode = "üsse" if order == Order.RTB else "tur"
	dbg = "%s %.1f km" % [_mode, hd / 1000.0]
