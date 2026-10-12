class_name EngineModule
extends PartModule
## Jet motoru: parçanın -Z yönünde itki, yakıt tüketir, irtifayla güç kaybeder.
## Gaz %95'in üstünde afterburner devreye girer: daha fazla itki, çok daha fazla yakıt,
## uzun şok elmaslı alev. Alev ortamı aydınlatır, arkasında sıcak hava dalgalanır.

const AFTERBURNER_THRESHOLD := 0.95
const AFTERBURNER_THRUST := 1.45
const AFTERBURNER_FUEL := 3.0

var max_thrust := 60000.0
var fuel_rate := 1.5    ## tam gazda (afterburner'sız) kg/s
var spool_rate := 0.6   ## gaz değişim hızı (1/s)

var throttle := 0.0     ## motorun gerçek (gecikmeli) gaz seviyesi
var afterburner := 0.0  ## 0..1, yumuşak geçişli
var thrust := 0.0
var flameout := false
var _sputter := 0.0
## Hava alığı karşılama oranı (0..1), HUD ve hangar için
var intake := 1.0
## Pervaneli motor: art yakıcı yok, itki hızla düşer (pervane verimi), ısı izi düşük
var prop := false
## Art yakıcısız (turbofan) ve roket motoru (hava alığı istemez, irtifada güç kaybetmez)
var no_ab := false
var rocket := false
var prop_vmax := 150.0
## Ramjet: sıkıştırıcısı yok, koç basıncıyla çalışır — yavaşken itki ~0, Mach 2–3.5'te en güçlü
var ramjet := false
## Darbeli jet: bu Mach'ın üstünde itki hızla düşer (0 = sınır yok)
var pulse_mach := 0.0
## İtki yönlendirme (TVC): lüle ±gimbal radyan döner, yunuslama/sapma komutuna tork katar
var gimbal := 0.0
var gimbal_cmd := Vector2.ZERO   ## x: lüle yerel X çevresinde, y: yerel Y çevresinde (-1..1)
var _nozzle: Node3D
var _prop_node: Node3D
var _prop_angle := 0.0
var _prop_disc: Node3D

## Motor durumu. Çalıştırmak için güç + JFS (marş türbini) gerekir.
enum State { OFF, CRANKING, RUNNING }
const IDLE_N2 := 0.25
var state := State.RUNNING
## Çekirdek devri 0..1 (rölanti 0.25). Ses ve görsel bunu kullanır.
var n2 := IDLE_N2

var _outer: GeometryInstance3D
var _core: GeometryInstance3D
var _haze: GeometryInstance3D
var _light: OmniLight3D


func setup(p: Dictionary) -> void:
	max_thrust = p.get("max_thrust", max_thrust)
	fuel_rate = p.get("fuel_rate", fuel_rate)
	spool_rate = p.get("spool_rate", spool_rate)
	prop = p.get("prop", false)
	no_ab = p.get("no_ab", false)
	rocket = p.get("rocket", false)
	prop_vmax = p.get("prop_vmax", prop_vmax)
	ramjet = p.get("ramjet", false)
	pulse_mach = p.get("pulse_mach", 0.0)
	gimbal = deg_to_rad(p.get("gimbal_deg", 0.0))
	if ramjet or pulse_mach > 0.0:
		no_ab = true


func on_attached() -> void:
	_outer = part.get_node_or_null("Visual/Exhaust")
	_prop_node = part.get_node_or_null("Visual/Prop")
	_prop_disc = part.get_node_or_null("Visual/PropDisc")
	_core = part.get_node_or_null("Visual/ExhaustCore")
	_haze = part.get_node_or_null("Visual/HeatHaze")
	_nozzle = part.get_node_or_null("Visual/Nozzle")
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.25)
	_light.omni_range = 18.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, 2.6)
	part.add_child(_light)
	if prop:
		_light.visible = false


## Marşı başlat (güç, JFS ve yakıt varsa). Başarılıysa true.
func start() -> bool:
	if state != State.OFF or not vessel.has_power() or not vessel.jfs_ready() or vessel.fuel_amount() <= 0.0:
		return false
	state = State.CRANKING
	return true


func shutdown() -> void:
	state = State.OFF


func is_running() -> bool:
	return state == State.RUNNING


func physics_tick(delta: float) -> void:
	match state:
		State.OFF:
			n2 = move_toward(n2, 0.0, 0.07 * delta)
			throttle = 0.0
		State.CRANKING:
			# JFS çekirdeği döndürür; %12'de ateşleme, %25'te rölanti
			if not vessel.jfs_ready() and n2 < 0.12:
				state = State.OFF
			n2 = move_toward(n2, IDLE_N2, 0.035 * delta)
			throttle = 0.0
			if n2 >= IDLE_N2 - 0.005:
				state = State.RUNNING
		State.RUNNING:
			var target := IDLE_N2 + (1.0 - IDLE_N2) * vessel.ctrl_throttle
			n2 = move_toward(n2, target, spool_rate * (1.0 - IDLE_N2) * delta)
			throttle = clampf((n2 - IDLE_N2) / (1.0 - IDLE_N2), 0.0, 1.0)

	var running := state == State.RUNNING
	var ab_target := 1.0 if running and not prop and not no_ab and not rocket and vessel.ctrl_throttle > AFTERBURNER_THRESHOLD and throttle > 0.9 else 0.0
	afterburner = move_toward(afterburner, ab_target, delta * 2.5)

	var ratio := 1.0
	if running:
		# rölantide de yakıt yakar
		var need := fuel_rate * maxf(throttle, 0.08) * lerpf(1.0, AFTERBURNER_FUEL, afterburner) * delta
		# yakıt akışı üretilen itkiyle orantılı: ince havada itki ve yakıt birlikte düşer,
		# soğuk yüksek havada motor biraz daha verimli (özgül tüketim ~%10 iyileşir). Roket hariç.
		if not rocket:
			var dr := clampf(vessel.air_density() / Atmosphere.SEA_LEVEL_DENSITY, 0.02, 1.2)
			need *= pow(dr, 0.7) * lerpf(0.9, 1.0, minf(dr, 1.0))
		if ramjet:
			need *= 0.15 + 0.85 * smoothstep(0.3, 1.3, vessel.mach())   # yavaşken az yakıt, az itki
		ratio = vessel.draw_fuel(need) / need
		if part.submerged > 0.5 or ratio < 0.5:
			state = State.OFF   # su altında ya da yakıt bitince söner
	flameout = running and ratio < 0.99

	var density_ratio := vessel.air_density() / Atmosphere.SEA_LEVEL_DENSITY
	thrust = 0.0
	if running:
		# koç basıncı: Mach 1.6'ya kadar itki biraz artar, Mach 2.2 üstünde alık sınırı
		var m := vessel.mach()
		var ram := 1.0 + 0.18 * minf(m, 1.6) - maxf(m - 2.2, 0.0) * 0.8
		if rocket:
			ram = 1.0
			density_ratio = 1.0 + 0.12 * (1.0 - minf(density_ratio, 1.0))   # vakumda biraz daha güçlü
		if prop:
			# pervane: statik itki yüksek, hız arttıkça düşer
			var s := vessel.airspeed() / prop_vmax
			ram = clampf(1.0 - s * s * 0.85, 0.08, 1.0)
		var ram_floor := 0.2
		if ramjet:
			ram = ramjet_factor(m)
			ram_floor = 0.0
		elif pulse_mach > 0.0:
			ram = clampf(1.0 - pow(m / pulse_mach, 4.0) * 0.9, 0.05, 1.0)
		# hava alığı yetersizse motor boğulur
		intake = lerpf(intake, vessel.intake_ratio(), minf(delta * 5.0, 1.0))
		if rocket:
			intake = 1.0
		thrust = max_thrust * throttle * lerpf(1.0, AFTERBURNER_THRUST, afterburner) * ratio * pow(density_ratio, 0.7) * maxf(ram, ram_floor) * intake * lerpf(0.45, 1.0, part.health_ratio())   # hasarlı motor güç kaybeder
		# ağır hasarlı motor tekler: anlık itki kaybı
		if part.health_ratio() < 0.3:
			vessel.failures["eng%d" % part.get_instance_id()] = "MOTOR TEKLİYOR"
			if _sputter <= 0.0 and randf() < delta * 0.6:
				_sputter = randf_range(0.2, 0.6)
		if _sputter > 0.0:
			_sputter -= delta
			thrust *= 0.15
	var dir := -part.global_basis.z
	if gimbal > 0.0:
		var target := _gimbal_target() if running else Vector2.ZERO
		gimbal_cmd = gimbal_cmd.move_toward(target, delta * lerpf(0.6, 4.0, vessel.hydraulics))
		dir = part.global_basis * (Basis.from_euler(Vector3(gimbal_cmd.x, gimbal_cmd.y, 0.0) * gimbal) * Vector3.FORWARD)
	vessel.add_force_at(dir * thrust, part.global_position)
	part.aero_load += dir * thrust


## Ramjet itki çarpanı Mach'a göre: Mach 0.35 altında yok, 1.3'te tam, 3'te ~1.9 kat, 3.6 üstü düşer.
static func ramjet_factor(m: float) -> float:
	return maxf(smoothstep(0.35, 1.3, m) * (1.0 + 0.9 * clampf((m - 1.3) / 1.7, 0.0, 1.0)) - maxf(m - 3.6, 0.0) * 1.2, 0.0)


## Lülenin istenen açısı: yunuslama / sapma (ve gerekirse yatış) komutuna en çok tork veren yön.
## Yerel X çevresinde +a dönüş itkiyi +Y'ye, yerel Y çevresinde +b dönüş -X'e eğer.
func _gimbal_target() -> Vector2:
	var desired := Vector3(vessel.ctrl_pitch, -vessel.ctrl_yaw, -vessel.ctrl_roll)
	if desired.is_zero_approx():
		return Vector2.ZERO
	var r := part.position - vessel.com_local
	var ta := r.cross(part.basis.y)
	var tb := r.cross(-part.basis.x)
	var a := clampf(desired.dot(ta.normalized()) * 1.5, -1.0, 1.0) if ta.length() > 0.05 else 0.0
	var b := clampf(desired.dot(tb.normalized()) * 1.5, -1.0, 1.0) if tb.length() > 0.05 else 0.0
	return Vector2(a, b)


## Alevin görünürlüğü: çalışırken, ya da marşta ateşleme anından sonra.
func flame_level() -> float:
	if state == State.RUNNING:
		return 0.15 + 0.85 * throttle
	if state == State.CRANKING and n2 > 0.12:
		return (n2 - 0.12) / (IDLE_N2 - 0.12) * 0.15
	return 0.0
func _process(_delta: float) -> void:
	if part == null:
		return
	if _prop_node:
		_prop_angle = fmod(_prop_angle + n2 * 45.0 * _delta, TAU)
		_prop_node.rotation.z = _prop_angle
		# hızlı dönerken kanatlar bulanık bir diske dönüşür
		var fast := n2 > 0.3
		for c in _prop_node.get_children():
			c.visible = not fast
		if _prop_disc:
			_prop_disc.visible = n2 > 0.12
			_prop_disc.scale = Vector3.ONE * (0.9 + 0.1 * n2)
	if gimbal > 0.0:
		var tilt := Vector3(gimbal_cmd.x, gimbal_cmd.y, 0.0) * gimbal
		for n in [_nozzle, _outer, _core, _haze]:
			if n:
				n.rotation = tilt
	var power := maxf(clampf(thrust / max_thrust, 0.0, 1.5), flame_level() * 0.3)
	if ramjet:
		power = maxf(power, flame_level() * 0.3 * smoothstep(0.2, 1.0, vessel.mach() if vessel else 0.0))
	var dry := clampf(power, 0.0, 1.0)
	# kuru güçte kısa, soluk alev; afterburner'da uzun turuncu alev ve şok elmasları
	if _outer:
		_outer.visible = power > 0.03
		var length := lerpf(0.15 + 0.35 * dry, 1.25, afterburner)
		var width := lerpf(0.75 + 0.15 * dry, 1.05, afterburner)
		_outer.scale = Vector3(width, width, length)
		_outer.set_instance_shader_parameter("power", lerpf(0.25 + 0.35 * dry, 1.0, afterburner))
		_outer.set_instance_shader_parameter("afterburner", afterburner)
	if _core:
		_core.visible = power > 0.03
		_core.scale = Vector3.ONE * lerpf(0.6 + 0.3 * dry, 1.0, afterburner) + Vector3(0, 0, afterburner * 0.3)
		_core.set_instance_shader_parameter("power", lerpf(0.4 + 0.4 * dry, 1.0, afterburner))
		_core.set_instance_shader_parameter("afterburner", afterburner)
	if _haze:
		_haze.visible = power > 0.05
		_haze.set_instance_shader_parameter("power", clampf(0.3 + 0.7 * dry + afterburner * 0.5, 0.0, 1.5))
	if _light:
		_light.visible = power > 0.05 and not prop
		_light.light_energy = 0.3 * dry + 3.5 * afterburner
		_light.omni_range = lerpf(8.0, 25.0, afterburner)


## Bu motorun tam güçte ihtiyaç duyduğu hava alığı alanı (m²).
func intake_need() -> float:
	return max_thrust / 70000.0 * 0.5 if is_running() and not rocket else 0.0
