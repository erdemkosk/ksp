class_name AutoLand
extends Node
## Otomatik iniş ("pilot indirsin"): en yakın havaalanına gider, pist ekseninde 3° süzülüşle
## alçalır, burun kaldırıp teker koyar, frenleyip durur. Hız uçağın stall hızına göre seçilir.
## Aşamalar: YAKLAŞMA → SON YAKLAŞMA → TEKER KOYMA → FREN → BİTTİ

signal finished(success: bool)

enum Phase { NAV, FINAL, FLARE, ROLLOUT, DONE }
const PHASE_NAMES := ["Yaklaşma noktasına", "Son yaklaşma", "Teker koyma", "Frenleme", "Durdu"]
const GLIDE := deg_to_rad(3.0)

var vessel: Vessel
var phase := Phase.NAV
var airfield := 0

var _fly := FlyTo.new()
var _center := Vector3.ZERO
var _land_dir := Vector3.ZERO     # iniş yönü (pist boyunca)
var _side := Vector3.ZERO
var _up := Vector3.ZERO
var _thr := Vector3.ZERO          # teker koyma noktası
var _elev := 0.0
var _vs_stall := 60.0
var _timeout := 0.0
var _outer := false
var dbg := ""


func _ready() -> void:
	_pick_runway()
	FloatingOrigin.shifted.connect(func(sft: Vector3) -> void:
		_center -= sft
		_thr -= sft)
	var area := 0.0
	for m in vessel.modules:
		if m is WingModule:
			area += m.area
	_vs_stall = sqrt(2.0 * vessel.mass * 9.81 / (1.225 * maxf(area, 1.0) * 1.2))


## Pist ekseni dünyada: kayan orijin yalnız öteler, yönler başlangıç çerçevesindekiyle aynı.
func _runway_frame(i: int) -> void:
	var a: Dictionary = TerrainGen.AIRFIELDS[i]
	var xz: Vector2 = a["xz"]
	var xf := TerrainGen.airfield_transform(i)
	_elev = float(a["elev"])
	_center = MissionManager.world_point(xz.x, xz.y, _elev)
	_up = Planet.up_at(_center)
	var z := xf.basis.z.normalized()
	# yaklaşma yönü: uçak pistin hangi ucuna yakınsa oradan
	var rel := vessel.com_global() - _center
	_land_dir = -z if rel.dot(z) > 0.0 else z
	_side = _land_dir.cross(_up).normalized()
	var half := float(a["runway"]) * 0.5
	_thr = _center - _land_dir * (half - 280.0)


func _pick_runway() -> void:
	var best := INF
	for i in TerrainGen.AIRFIELDS.size():
		var xz: Vector2 = TerrainGen.AIRFIELDS[i]["xz"]
		var d := vessel.com_global().distance_to(MissionManager.world_point(xz.x, xz.y, 0.0))
		if d < best:
			best = d
			airfield = i
	_runway_frame(airfield)


func status() -> String:
	return "%s — %s" % [String(TerrainGen.AIRFIELDS[airfield]["name"]), PHASE_NAMES[phase]]


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel) or vessel.parts.is_empty() or vessel.cockpit() == null:
		finished.emit(false)
		queue_free()
		return
	_timeout += delta
	var pos := vessel.com_global()
	var speed := vessel.airspeed()
	var grounded := false
	for m in vessel.modules:
		if m is LandingGearModule and m.grounded:
			grounded = true
	# pist eşiğine olan pist-boyu mesafe (önünde pozitif) ve yanal sapma
	var s := (_thr - pos).dot(_land_dir)
	var lat := (pos - _thr).dot(_side)
	var agl := (pos - _center).dot(_up) - 0.0
	var v_app := clampf(_vs_stall * 1.5, 72.0, 125.0)
	var v_nav := clampf(_vs_stall * 2.2, 120.0, 170.0)
	vessel.ctrl_brakes = false
	vessel.parking_brake = false
	match phase:
		Phase.NAV:
			var faf := _thr - _land_dir * 9000.0 + _up * (9000.0 * tan(GLIDE) + 15.0)
			# eksene dışarıdan, piste dönük gir: yaklaşma noktasının içindeysek önce 13 km'lik dış kapıya
			if s < 9500.0 or vessel.forward().dot(_land_dir) < 0.0 and s < 12500.0:
				_outer = true
			if _outer and s > 12500.0:
				_outer = false
			var gate := _thr - _land_dir * 13500.0 + _up * (13500.0 * tan(GLIDE) + 15.0) + _side * signf(lat if absf(lat) > 1.0 else 1.0) * 2500.0
			var to := (gate if _outer else faf) - pos
			# arazi emniyeti: altındaki ve 2 km önündeki arazinin en az 300 m üstünde kal
			var ahead := pos + vessel.linear_velocity.normalized() * 2000.0
			var gh := maxf(TerrainGen.height(Planet.surface_dir(pos)), TerrainGen.height(Planet.surface_dir(ahead)))
			var floor_alt := maxf(gh, 0.0) + 300.0
			if Planet.altitude(pos) < floor_alt + 150.0:
				to = (to - _up * to.dot(_up)).normalized() * 1000.0 + _up * clampf((floor_alt + 150.0 - Planet.altitude(pos)) * 2.0, 0.0, 600.0)
			# yaklaşma noktasına varınca ya da zaten eksende ve süzülüş üstündeysek son yaklaşma
			var on_axis := absf(lat) < 600.0 and s > 2500.0 and s < 16000.0 and vessel.forward().dot(_land_dir) > 0.8 and agl < s * tan(GLIDE) + 14.0 + 250.0
			if not _outer and (to.length() < 1500.0 and vessel.forward().dot(_land_dir) > 0.6 or on_axis):
				phase = Phase.FINAL
			_steer(_limit_turn(_limit_dive(to.normalized(), 12.0)), 2.5, delta)
			_speed(v_nav, 0.0, 0.09)
		Phase.FINAL:
			vessel.gear_down = true
			# eksen üstünde 1200 m ileride, süzülüş yüksekliğindeki noktaya uç
			var ahead := maxf(s - 700.0, -200.0)
			var target := _thr - _land_dir * ahead + _up * (maxf(ahead, 0.0) * tan(GLIDE) + 14.0)
			target -= _side * lat * 0.0
			_steer(_limit_turn(_limit_dive((target - pos).normalized(), 6.0)), 2.5, delta)
			# süzülüş yolunun altındaysak güç ekle, üstündeysek azalt
			var path_h := maxf(s, 0.0) * tan(GLIDE) + 14.0
			_speed(v_app, clampf((path_h - agl) * 0.02, -0.3, 0.8), 0.035)
			if grounded:
				phase = Phase.ROLLOUT
			if agl < 20.0 and s < 3000.0:
				phase = Phase.FLARE
			if absf(lat) > 900.0 or s < -800.0:
				phase = Phase.NAV   # pas geç, yeniden dene
		Phase.FLARE:
			# alçalma hızını -1.2 m/s'ye indir, gaz rölanti
			var vs := vessel.vertical_speed()
			var k := clampf(0.035 + (-1.2 - vs) * 0.02, -0.06, 0.16)
			_steer((_land_dir + _up * k).normalized(), 2.0, delta)
			vessel.ctrl_throttle = 0.0
			if grounded:
				phase = Phase.ROLLOUT
		Phase.ROLLOUT:
			vessel.ctrl_throttle = 0.0
			vessel.ctrl_pitch = 0.0
			vessel.ctrl_roll = 0.0
			vessel.ctrl_brakes = speed > 3.0
			var hdg_err := vessel.forward().cross(_land_dir).dot(_up)
			vessel.ctrl_yaw = clampf(-lat * 0.04 - hdg_err * 3.0, -1.0, 1.0)
			if vessel.ground_speed() < 1.5:
				phase = Phase.DONE
				vessel.parking_brake = true
				vessel.ctrl_brakes = false
				finished.emit(true)
				queue_free()
	if _timeout > 600.0:
		finished.emit(false)
		queue_free()


func _steer(dir: Vector3, g_limit: float, delta: float) -> void:
	var out := _fly.compute(vessel, dir, g_limit, delta)
	vessel.ctrl_pitch = out["pitch"]
	vessel.ctrl_roll = out["roll"]
	vessel.ctrl_yaw = out["yaw"]


func _speed(target: float, extra := 0.0, k := 0.06) -> void:
	vessel.ctrl_throttle = clampf(0.55 + (target - vessel.airspeed()) * k + extra, 0.0, 1.0)


## Yön en fazla `deg` derece aşağı bakabilir: yüksekten dalış yerine kontrollü alçalma.
func _limit_dive(dir: Vector3, deg: float) -> Vector3:
	var down := -dir.dot(_up)
	var max_down := sin(deg_to_rad(deg))
	if down <= max_down:
		return dir
	var h := (dir - _up * dir.dot(_up)).normalized()
	return (h * cos(deg_to_rad(deg)) - _up * max_down).normalized()


## Hedef burnun 70°'den fazla yanındaysa yön kademeli döndürülür (sırtüstü dalış olmasın).
func _limit_turn(dir: Vector3) -> Vector3:
	var f := vessel.forward()
	var fh := (f - _up * f.dot(_up)).normalized()
	var dh := (dir - _up * dir.dot(_up))
	if dh.length() < 0.01:
		return dir
	dh = dh.normalized()
	var ang := fh.signed_angle_to(dh, _up)
	var lim := deg_to_rad(70.0)
	if absf(ang) <= lim:
		return dir
	var nh := fh.rotated(_up, signf(ang) * lim)
	return (nh * sqrt(maxf(1.0 - pow(dir.dot(_up), 2.0), 0.0)) + _up * dir.dot(_up)).normalized()
