extends Node
## Kargo bırakma testi: görevin yön işaretine uçar, sandık iniş noktası bölge merkezine
## en yakın olduğunda bırakır (görev sonucu MissionManager yazdırır).

var main: Node
var _t := 0.0
var _ap := Autopilot.new()
var _prev := INF


func _ready() -> void:
	await get_tree().physics_frame
	var v: Vessel = main.vessel
	_ap.level = true
	_ap.hold_altitude = true
	_ap.hold_heading = true
	_ap.hold_speed = true
	_ap.target_altitude = v.altitude()
	_ap.target_speed = 120.0


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	var m: MissionManager = main.mission
	if m == null or m.nav_point == null:
		return
	var target: Vector3 = m.nav_point
	var fr := Planet.local_basis(v.global_position)
	var to := target - v.com_global()
	_ap.target_heading = fposmod(rad_to_deg(atan2(to.dot(fr.x), -to.dot(fr.z))), 360.0)
	var imp: Variant = CargoCrate.simulate_impact(v.com_global() - v.up() * 1.5, v.linear_velocity)
	if imp != null:
		var vel_h := (v.linear_velocity - fr.y * v.linear_velocity.dot(fr.y)).normalized()
		var right := vel_h.cross(fr.y)
		var lat := (target - (imp as Vector3)).dot(right)
		var dist_imp := to.length()
		if dist_imp < 5000.0:
			var trk := fposmod(rad_to_deg(atan2(vel_h.dot(fr.x), -vel_h.dot(fr.z))), 360.0)
			_ap.target_heading = fposmod(trk + clampf(lat * 0.1, -15.0, 15.0), 360.0)
	var out := _ap.compute(v)
	v.ctrl_pitch = out["pitch"] if out["pitch"] != null else 0.0
	v.ctrl_roll = out["roll"] if out["roll"] != null else 0.0
	v.ctrl_throttle = out["throttle"] if out["throttle"] != null else 0.6
	var cd := (imp as Vector3).distance_to(target) if imp != null else INF
	v.ctrl_fire = cd > _prev and _prev < 60.0 and v.cargo_left() > 0 and fmod(_t, 2.0) < 1.0
	if v.ctrl_fire:
		print("t=%.1f SANDIK BIRAKILDI, öngörülen sapma %.0f m" % [_t, _prev])
		_prev = INF
	else:
		_prev = cd
	if fmod(_t, 10.0) < delta:
		print("t=%.0f hedefe %.0f m  öngörü sapma %.0f m  kalan sandık %d" % [_t, to.length(), cd, v.cargo_left()])
	if _t > 400.0:
		get_tree().quit()
