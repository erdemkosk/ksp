class_name PlayerController
extends Node
## Klavye girdisini Vessel kontrollerine çevirir. Sadece pilot kokpitteyken çalışır.
## SAS açıkken, girdi yokken dönüşleri söndürür. Alt + W/S: yunuslama trimi.
## Otopilot açık eksenleri yönetir; pilot o eksene dokunursa kontrol pilota geçer.

## Pilotun uçuş yeteneği kumanda tepkisini ve SAS hassasiyetini belirler (Crew).
var input_response := 4.0
var sas_gain := 2.0

## G bayılması: yüksek G'de kan beyinden çekilir (gri/siyah perde), aşırısında pilot
## bayılır ve kumandaları bırakır. Negatif G'de kırmızı perde. Eşik G dayanımına bağlı.
var g_strain := 0.0
var red_strain := 0.0
var blackout := false
var _xp_acc := 0.0
## G sınırlayıcı (fly-by-wire): kumanda, pilotun dayanabileceği G'yi aşacak kadar çekilemez.
## Ölçülen G sınıra yaklaşınca yunuslama komutu kısılır; ayarlardan kapatılabilir.
var g_limiter := true
var _g_per_q := 6.0e-4      ## öğrenilen: (G-1) / (kumanda × dinamik basınç); güvenli taraftan başlar
var _auth := 1.0
var _auth_neg := 1.0
var _prev_wx := 0.0
var _wdot := 0.0

var vessel: Vessel
var enabled := true
var throttle := 0.0
var pitch_trim := 0.0
var autopilot := Autopilot.new()

## Fareyle uçuş (War Thunder tarzı): fare dünyada bir nişan yönü belirler, uçak oraya
## kendisi döner. Klavye/gamepad ile eksene dokununca o an elle kumandaya geçer.
## Y: fare / klavye modu. Alt basılıyken imleç serbest (panel ve kokpit düğmeleri için).
var mouse_flight := true
var aim_dir := Vector3.ZERO
var camera: FlightCamera
var mouse_sensitivity := 0.0025
var _fly := FlyTo.new()
var _manual_t := 0.0

var _pitch := 0.0
var _yaw := 0.0
var _roll := 0.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel):
		return
	if not enabled:
		return
	if not vessel.has_pilot():
		vessel.ctrl_pitch = 0.0
		vessel.ctrl_yaw = 0.0
		vessel.ctrl_roll = 0.0
		vessel.ctrl_brakes = false
		return

	_update_g_loc(delta)
	var pitch_input := Input.get_axis("pitch_down", "pitch_up")
	if Input.is_key_pressed(KEY_ALT):
		pitch_trim = clampf(pitch_trim + pitch_input * 0.25 * delta, -0.5, 0.5)
		pitch_input = 0.0
	# ağır / büyük uçakta çubuk (ve boynuz lövye) daha ağır hareket eder: tam sapmaya geç ulaşır
	var resp := input_response * ControlSurfaceModule.response_factor(vessel.mass)
	_pitch = move_toward(_pitch, pitch_input, resp * delta)
	_yaw = move_toward(_yaw, Input.get_axis("yaw_left", "yaw_right"), resp * delta)
	_roll = move_toward(_roll, Input.get_axis("roll_left", "roll_right"), resp * delta)

	var manual_throttle := false
	if Input.is_action_pressed("throttle_up"):
		throttle += 0.5 * delta
		manual_throttle = true
	if Input.is_action_pressed("throttle_down"):
		throttle -= 0.5 * delta
		manual_throttle = true
	if Input.is_action_just_pressed("throttle_full"):
		throttle = 1.0
		manual_throttle = true
	if Input.is_action_just_pressed("throttle_cut"):
		throttle = 0.0
		manual_throttle = true
	throttle = clampf(throttle, 0.0, 1.0)
	if manual_throttle:
		autopilot.hold_speed = false

	if Input.is_action_just_pressed("gear_toggle"):
		vessel.gear_down = not vessel.gear_down
	if Input.is_action_just_pressed("sas_toggle"):
		Sfx.click()
		vessel.sas = not vessel.sas
	if Input.is_action_just_pressed("engine_toggle"):
		Sfx.click()
		if vessel.engines_running():
			vessel.shutdown_engines()
		else:
			vessel.auto_start()
	if Input.is_action_just_pressed("lights_toggle"):
		Sfx.click()
		vessel.lights_on = not vessel.lights_on
	if Input.is_action_just_pressed("parking_brake"):
		Sfx.click()
		vessel.parking_brake = not vessel.parking_brake
	if Input.is_action_just_pressed("canopy_toggle") and vessel.cockpit():
		vessel.cockpit().canopy_open = not vessel.cockpit().canopy_open

	var pitch := _pitch
	var yaw := _yaw
	var roll := _roll
	var fcs := _fcs()
	var mouse_active := _mouse_flight_active()
	var manual := absf(_pitch) > 0.05 or absf(_roll) > 0.05 or absf(_yaw) > 0.05
	if mouse_active:
		if aim_dir == Vector3.ZERO or manual:
			aim_dir = vessel.forward()   # elle kumandada nişan burnu izler
			_manual_t = 0.4
		_manual_t -= delta
		if _manual_t <= 0.0:
			var out := _fly.compute(vessel, aim_dir, g_tolerance() - 0.5, delta)   # pilotu bayıltmaz
			pitch = out["pitch"]
			roll = out["roll"]
			yaw = out["yaw"]
	if camera:
		camera.mouse_aim = aim_dir if mouse_active else Vector3.ZERO
	if blackout:
		# bilinçsiz pilot kumandayı bırakır
		pitch = 0.0
		yaw = 0.0
		roll = 0.0
		_pitch = 0.0
		_roll = 0.0
		_yaw = 0.0
	if vessel.sas:
		# Gövde açısal hızı: +x burun yukarı, +y burun sola, -z sağa yatış
		# (mekanik kumandada SAS basit bir dengeleyici: yarı güçte)
		var w := vessel.local_angular_velocity()
		var g_sas := sas_gain * (0.5 if fcs == "mech" else 1.0)
		if absf(pitch) < 0.05:
			pitch = clampf(-w.x * g_sas, -1.0, 1.0)
		if absf(yaw) < 0.05:
			yaw = clampf(w.y * g_sas, -1.0, 1.0)
		if absf(roll) < 0.05:
			roll = clampf(w.z * g_sas, -1.0, 1.0)

	if autopilot.any_active():
		var ap := autopilot.compute(vessel)
		if ap["pitch"] != null and absf(_pitch) < 0.05:
			pitch = ap["pitch"]
		if ap["roll"] != null and absf(_roll) < 0.05:
			roll = ap["roll"]
		if ap["throttle"] != null:
			throttle = move_toward(throttle, ap["throttle"], 0.3 * delta)

	# kumanda kuralı kokpite göre (bkz. _fcs): FBW sınırlar, hidrolik sönümler, mekanik ham kumanda
	match fcs:
		"fbw":
			vessel.ctrl_pitch = _limit_aoa(_limit_g(clampf(_damp_pitch(pitch, delta) + pitch_trim, -1.0, 1.0), delta))
		"hydro":
			vessel.ctrl_pitch = clampf(_damp_pitch(pitch, delta) + pitch_trim, -1.0, 1.0)
		_:
			var k := _stick_force()
			vessel.ctrl_pitch = clampf(pitch * k + pitch_trim, -1.0, 1.0)
			yaw *= k
			roll *= k
	if fcs != "fbw":
		_warnings(delta)
	vessel.ctrl_yaw = yaw
	vessel.ctrl_roll = roll
	vessel.ctrl_throttle = throttle
	vessel.ctrl_brakes = Input.is_action_pressed("brakes")
	vessel.ctrl_fire = Input.is_action_pressed("fire")
	if Input.is_action_just_pressed("weapon_cycle"):
		vessel.cycle_weapon()
		Sfx.click()
	if Input.is_action_pressed("flare"):
		vessel.drop_flares()
	if Input.is_action_pressed("chaff"):
		vessel.drop_chaff()
	if Input.is_action_just_pressed("cm_auto"):
		vessel.cm_auto = not vessel.cm_auto
		vessel.system_message.emit("KARŞI TEDBİR PROGRAMI %s" % ("OTOMATİK" if vessel.cm_auto else "ELLE"))
	vessel.autopilot_active = autopilot.any_active()


## Kokpitteki OTOPİLOT düğmesi / U tuşu: açıksa kapat, kapalıysa mevcut irtifa ve yönü tut.
func toggle_autopilot() -> void:
	if autopilot.any_active():
		autopilot.disengage()
	elif is_instance_valid(vessel):
		autopilot.capture(vessel)
		autopilot.level = true
		autopilot.hold_altitude = true
		autopilot.hold_heading = true


## Pilot yeteneklerini uygula (her doğuşta main çağırır).
func apply_pilot() -> void:
	mouse_flight = bool(Game.settings.get("mouse_aim", false))
	mouse_sensitivity = 0.0025 * float(Game.settings.get("mouse_sens", 1.0))
	if camera:
		camera.cockpit_fov = float(Game.settings.get("fov", 78.0))
	g_limiter = bool(Game.settings.get("g_limit", true))
	var fly := Crew.skill("ucus")
	input_response = 3.0 + 0.5 * fly
	sas_gain = 1.5 + 0.2 * fly
	g_strain = 0.0
	red_strain = 0.0
	blackout = false


func _update_g_loc(delta: float) -> void:
	var g := vessel.g_force
	var tol := g_tolerance()
	var onset := tol * 0.75
	if g > tol:
		# sınırın üstü: birkaç saniyede bayılma (tol+1 G'de ~4 sn)
		g_strain += ((g - tol) * 0.18 + 0.06) * delta
	elif g > onset:
		# gri bölge: görüş daralır ama sınırın altında asla bayılmaz
		g_strain = minf(g_strain + (g - onset) / (tol - onset) * 0.05 * delta, 0.8)
	else:
		g_strain -= delta * (0.25 if g > 2.0 else 0.45)
	g_strain = clampf(g_strain, 0.0, 1.3)
	var neg := -(2.5 + 0.3 * Crew.skill("dayanim"))
	if g < neg:
		red_strain += ((neg - g) * 0.15 + 0.05) * delta
	else:
		red_strain -= delta * 0.4
	red_strain = clampf(red_strain, 0.0, 1.2)
	if not blackout and (g_strain >= 1.0 or red_strain >= 1.0):
		blackout = true
		vessel.system_message.emit("PİLOT BAYILDI (G-LOC)!")
	elif blackout and g_strain < 0.35 and red_strain < 0.35:
		blackout = false
		vessel.system_message.emit("Pilot kendine geldi")
	# yüksek G tecrübesi
	if g > 5.0:
		_xp_acc += delta
		if _xp_acc >= 2.0:
			_xp_acc = 0.0
			Crew.award(1, "dayanim")


## Fareyle uçuş şu an etkin mi (uçuşta, EVA değil, Alt basılı değil, pilot bilinçli)?
func _mouse_flight_active() -> bool:
	return mouse_flight and camera != null and not camera.is_eva() and not blackout \
		and camera.mode != FlightCamera.Mode.ORBIT and vessel.has_pilot()


func _process(_delta: float) -> void:
	# fare yakalama: fareyle uçuşta yakalı, Alt basılıyken serbest (paneller, kokpit düğmeleri)
	if not enabled or not is_instance_valid(vessel):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# yürürken (EVA) fare her zaman bakış içindir; uçuşta yalnız fareyle uçuş açıkken
	var free_cursor := Input.is_key_pressed(KEY_ALT) or not DisplayServer.window_is_focused() or FlightMap.showing
	# paraşütle inerken fare serbest: üstteki zaman hızlandırma vb. tıklanabilsin (bakış: sağ sürükle)
	var parachuting: bool = camera != null and camera.is_eva() and is_instance_valid(camera.pilot) and camera.pilot.airborne
	var want_captured := not free_cursor and not parachuting and camera != null and (camera.is_eva() \
		or (mouse_flight and camera.mode != FlightCamera.Mode.ORBIT and vessel.has_pilot()))
	var mode := Input.MOUSE_MODE_CAPTURED if want_captured else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _unhandled_input(event: InputEvent) -> void:
	# N: paneller (savaş paneli, kumanda paneli, pencere çubuğu) aç / kapa — imleç serbest kalır
	if event.is_action_pressed("panel_toggle"):
		Hud.panels_open = not Hud.panels_open
		return
	# TAB ya da Y: fareyle uçuş aç / kapa (varsayılan klavye)
	if event.is_action_pressed("cursor_toggle") or event.is_action_pressed("mouse_flight"):
		mouse_flight = not mouse_flight
		aim_dir = Vector3.ZERO
		if is_instance_valid(vessel):
			vessel.system_message.emit("Kumanda: %s" % ("FARE (nişana uçar) — Alt: imleç" if mouse_flight else "KLAVYE / GAMEPAD"))
		return
	# füze kamerasında fare etrafa bakmak içindir, uçağı yönlendirmez
	if event is InputEventMouseMotion and camera and camera.missile_view():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and is_instance_valid(vessel):
		if aim_dir == Vector3.ZERO:
			aim_dir = vessel.forward()
		var rel: Vector2 = event.relative
		var up := Planet.up_at(vessel.global_position)
		var right := aim_dir.cross(up).normalized()
		var s := mouse_sensitivity * (camera.fov / 70.0 if camera else 1.0)
		var d := aim_dir.rotated(up, -rel.x * s)
		var pitched := d.rotated(right, -rel.y * s)
		# dik yukarı / aşağı takılmasın
		if absf(pitched.dot(up)) < 0.985:
			d = pitched
		aim_dir = d.normalized()


## Pilotun sürekli dayanabildiği G (G dayanımı yeteneğine bağlı): 1★ 7.4 G … 5★ 9.8 G.
func g_tolerance() -> float:
	return 6.8 + 0.6 * Crew.skill("dayanim")


## Pozitif ve negatif G sınırı: aşılırsa o yöndeki kumanda kazancı hızla düşer, G sınırın
## epey altına inince yavaşça geri gelir. Burun yukarı +, aşağı - komut.
func _limit_g(pitch: float, delta: float) -> float:
	if not g_limiter:
		return pitch
	# Kazanç planlaması (gerçek FBW gibi): uçağın kumanda başına ürettiği G, dinamik basınçla
	# orantılı kabul edilir ve uçuşta yavaşça öğrenilir. Tam çubuk ≈ pilotun G sınırı olacak
	# şekilde kumanda yetkisi yumuşakça ayarlanır — açıp kapamaz, kumanda akıcı kalır.
	var g := vessel.g_force
	var gmax := g_tolerance() - 0.4
	if _g_cap > 0.0:
		gmax = minf(gmax, _g_cap)   # kokpitin yapısal sınırı (ör. yolcu uçağı 2.5 G)
	var gmin := -(2.2 + 0.3 * Crew.skill("dayanim"))
	var q := maxf(0.5 * vessel.air_density() * vessel.airspeed() * vessel.airspeed(), 500.0)
	var eff := vessel.ctrl_pitch
	if absf(eff) > 0.25 and q > 3000.0:
		var sample := clampf((g - 1.0) / (eff * q), _g_per_q * 0.5, _g_per_q * 2.0)
		_g_per_q = clampf(_g_per_q + (sample - _g_per_q) * minf(delta / 0.6, 1.0), 2e-5, 3e-3)
	var want := clampf((gmax - 1.0) / (_g_per_q * q), 0.08, 1.0)
	var want_neg := clampf((1.0 - gmin) / (_g_per_q * q), 0.08, 1.0)
	# sınır aşılıyorsa yetki daha da kısılır (yumuşak)
	if g > gmax:
		want *= clampf(1.0 - (g - gmax) * 0.25, 0.3, 1.0)
	if g < gmin:
		want_neg *= clampf(1.0 - (gmin - g) * 0.3, 0.3, 1.0)
	# kısarken hızlı, açarken yavaş (aşırı G kaçmasın, kumanda yine akıcı)
	_auth = lerpf(_auth, want, 1.0 - exp(-delta / (0.07 if want < _auth else 0.35)))
	_auth_neg = lerpf(_auth_neg, want_neg, 1.0 - exp(-delta / (0.07 if want_neg < _auth_neg else 0.35)))
	return pitch * (_auth if pitch > 0.0 else _auth_neg)


## Yunuslama sönümleyici: çubuk çekilince uçağın burnu ileri geri sallanmasın (kısa periyot
## salınımı). Açısal ivmeye karşı koyar; sabit dönüş hızını azaltmaz. Kazanç dinamik basınçla
## ölçeklenir (hızlıyken kumanda yüzeyleri daha etkili).
func _damp_pitch(pitch: float, delta: float) -> float:
	var wx := vessel.local_angular_velocity().x
	var acc := (wx - _prev_wx) / maxf(delta, 0.001)
	_prev_wx = wx
	_wdot = lerpf(_wdot, acc, 1.0 - exp(-delta / 0.05))
	if blackout or absf(pitch) < 0.05:
		return pitch
	var q := 0.5 * vessel.air_density() * vessel.airspeed() * vessel.airspeed()
	var kd := clampf(4000.0 / maxf(q, 1.0), 0.04, 0.35)
	return pitch - clampf(_wdot * kd, -0.5, 0.5)


# ------------------------------------------------------------------ kumanda sistemi (kokpite göre)

const FCS_NAMES := {
	"fbw": "FLY-BY-WIRE — G ve hücum açısı sınırlı",
	"hydro": "HİDROLİK — sönümlü, sınırlayıcı yok",
	"mech": "MEKANİK — kablolu, hızlanınca çubuk ağırlaşır",
}
## Mekanik kumandada çubuğun "tam çekilebildiği" dinamik basınç (Pa, deniz seviyesinde ~75 m/s).
const MECH_Q := 3500.0

var _fcs_kind := ""
var _fcs_vessel: Vessel
var _stall_deg := 16.0
var _aoa_lim := 14.0
var _warn_t := 0.0
var _over_msg := false
var _g_cap := 0.0          ## kokpit tanımındaki "g_limit": FBW bu G'den fazlasını çekmez


## Kumanda sistemi: kokpit tanımında "fcs" verilmişse o; yoksa sivil (küçük uçak) kokpit
## mekanik, çerçeveli klasik savaş kokpiti hidrolik, diğerleri FBW. Kokpit tanımındaki
## "g_limit" FBW'nin G sınırını düşürür (yolcu uçağı: FBW, 2.5 G).
func _fcs() -> String:
	if _fcs_vessel != vessel:
		_fcs_vessel = vessel
		var c := vessel.cockpit()
		var kind := fcs_for(c)
		_fcs_kind = kind
		_g_cap = float(c.part.def.get("g_limit", 0.0)) if c else 0.0
		_stall_deg = _main_wing_stall()
		_aoa_lim = _stall_deg * 0.9
		vessel.system_message.emit("Kumanda sistemi: " + FCS_NAMES.get(kind, kind))
	return _fcs_kind


## Kokpitin kumanda sistemi ("fbw" / "hydro" / "mech"); hangar da gösterir.
static func fcs_for(c: CockpitModule) -> String:
	if c == null:
		return "fbw"
	var d: String = c.part.def.get("fcs", "")
	if d != "":
		return d
	if c.canopy_style == "framed":
		return "hydro"
	if c.layout == "civil":
		return "mech"
	return "fbw"


## Ana kanadın (en geniş yatay kanat) stall açısı, derece.
func _main_wing_stall() -> float:
	var best := 0.0
	var deg := 16.0
	for m in vessel.modules:
		if m is WingModule and not m is ControlSurfaceModule and absf(m.part.basis.y.y) > 0.6 and m.area > best:
			best = m.area
			deg = rad_to_deg(m.stall_angle)
	return deg


## FBW hücum açısı sınırı: stall açısının %90'ında çubuk daha fazla çekmez (burnu indirir),
## negatifte -10°. Kalkış koşusunda (yavaşken) ve sınırlayıcı kapalıysa devre dışı.
func _limit_aoa(pitch: float) -> float:
	if not g_limiter or blackout or vessel.airspeed() < 35.0:
		return pitch
	var aoa := vessel.aoa_deg()
	if pitch > 0.0:
		pitch = minf(pitch, clampf((_aoa_lim - aoa) / 5.0, -0.5, 1.0))
	elif pitch < 0.0:
		pitch = maxf(pitch, clampf((-10.0 - aoa) / 4.0, -1.0, 0.5))
	return pitch


## Mekanik kumanda: hava yükü çubuğu ağırlaştırır — hızlıyken kumanda yüzeyi tam sapamaz
## (aynı G için daha çok çekmek gerekir), yavaşta tam sapar ama yüzeyler etkisizleşir.
func _stick_force() -> float:
	# çubuk kuvveti ~ q × sapma: pilotun kuvveti sabit → çekilebilen sapma ~ 1/q, yani hızlıyken
	# çekilebilen G kabaca sabit kalır (yine de sert çekilirse gövde zorlanır)
	var q := 0.5 * vessel.air_density() * vessel.airspeed() * vessel.airspeed()
	return clampf(MECH_Q / maxf(q, 1.0), 0.22, 1.0)


## Sınırlayıcısız kumandada ikazlar: stall'a 2.5° kala hızlı bip (stall ikazı; asıl stall'da
## WarningVoice konuşur), pilotun G sınırına yaklaşınca kalın bip ve bir kez "AŞIRI YÜK" mesajı.
func _warnings(delta: float) -> void:
	_warn_t -= delta
	if _warn_t > 0.0 or blackout or vessel.airspeed() < 30.0:
		return
	var over := vessel.g_force > g_tolerance() - 0.3   # yapısal yük ikazı WarningVoice "OVER G"de
	if absf(vessel.aoa_deg()) > _stall_deg - 2.5 and vessel.radar_altitude() > 3.0:
		Sfx.play_ui("caution_beep.ogg", -10.0, 1.7)
		_warn_t = 0.3
	elif over:
		Sfx.play_ui("caution_beep.ogg", -8.0, 0.8)
		_warn_t = 0.5
		if not _over_msg:
			_over_msg = true
			vessel.system_message.emit("AŞIRI YÜK — çubuğu bırak!")
	if not over and vessel.g_force < g_tolerance() - 1.5:
		_over_msg = false
