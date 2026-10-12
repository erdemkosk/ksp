extends Node
## Otomatik kalkış testi: tam gaz, 75 m/s'de burnu kaldırır, tırmanır, düz uçuşa geçer.
## Her saniye telemetri yazdırır. Fizik ve aerodinamiği başsız (headless) doğrulamak için.

const DURATION := 70.0

var main: Node

var _t := 0.0
var _next_log := 0.0
var _airborne_at := -1.0


func _physics_process(delta: float) -> void:
	var v: Vessel = main.vessel
	if not is_instance_valid(v):
		return
	_t += delta

	var speed := v.airspeed()
	var alt := v.radar_altitude()
	var on_ground := alt < 3.5

	var target_pitch := 0.0
	if speed > 75.0:
		target_pitch = 12.0
	if alt > 600.0:
		target_pitch = 3.0
	if _t > 50.0:
		target_pitch = 0.0
	if alt > 60.0:
		v.gear_down = false
	if _airborne_at < 0.0 and not on_ground:
		_airborne_at = _t

	var w := v.local_angular_velocity()
	v.parking_brake = false
	v.ctrl_throttle = 1.0 if _t < 50.0 else 0.6
	v.ctrl_pitch = clampf((target_pitch - v.pitch_deg()) * 0.08 - w.x * 1.5, -1.0, 1.0)
	# 50. saniyeden sonra 30° yatışla sağa dönüş
	var target_roll := 30.0 if _t > 55.0 else 0.0
	v.ctrl_roll = clampf((target_roll - v.roll_deg()) * 0.04 + w.z * 1.0, -1.0, 1.0)
	var heading_err := wrapf(0.0 - v.heading_deg(), -180.0, 180.0)
	v.ctrl_yaw = clampf(heading_err * 0.1, -1.0, 1.0) if on_ground else clampf(w.y * 2.0, -1.0, 1.0)

	if _t >= _next_log:
		_next_log += 1.0
		print("t=%4.1f hız=%5.1f radar_irt=%6.1f dikey=%+5.1f yunus=%+5.1f yatış=%+6.1f yön=%5.1f hücum=%+5.1f G=%+4.1f yakıt=%5.0f kütle=%5.0f com_z=%+.2f" % [
			_t, speed, alt, v.vertical_speed(), v.pitch_deg(), v.roll_deg(), v.heading_deg(),
			v.aoa_deg(), v.g_force, v.fuel_amount(), v.mass, v.com_local.z])

	if _t >= DURATION:
		print("AUTOTEST BİTTİ  kalkış t=%.1f" % _airborne_at)
		get_tree().quit()
