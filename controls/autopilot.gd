class_name Autopilot
extends RefCounted
## Basit otopilot: kanat düzleme, irtifa tutma, yön tutma, hız tutma.
## Her biri ayrı açılıp kapanır; pilot o eksene elle dokunursa o eksen pilotta kalır.

var level := false          ## kanatları düzle
var hold_altitude := false
var hold_heading := false
var hold_speed := false
var target_altitude := 1000.0
var target_heading := 0.0     ## derece
var target_speed := 200.0     ## m/s


func any_active() -> bool:
	return level or hold_altitude or hold_heading or hold_speed


func disengage() -> void:
	level = false
	hold_altitude = false
	hold_heading = false
	hold_speed = false


## Hedefleri mevcut uçuş durumuna eşitler (bir mod açılınca çağrılır).
func capture(v: Vessel) -> void:
	target_altitude = roundf(v.altitude() / 50.0) * 50.0
	target_heading = roundf(v.heading_deg())
	target_speed = roundf(v.airspeed() / 5.0) * 5.0


## {pitch, roll, throttle} için null = otopilot o ekseni kontrol etmiyor.
func compute(v: Vessel) -> Dictionary:
	var out := {"pitch": null, "roll": null, "throttle": null}
	var w := v.local_angular_velocity()
	var desired_roll := 0.0
	if hold_heading:
		var err := wrapf(target_heading - v.heading_deg(), -180.0, 180.0)
		desired_roll = clampf(err * 1.5, -35.0, 35.0)
	if level or hold_heading:
		out["roll"] = clampf((desired_roll - v.roll_deg()) * 0.035 + w.z * 0.8, -1.0, 1.0)
	if hold_altitude:
		var alt_err := target_altitude - v.altitude()
		var desired_vs := clampf(alt_err * 0.15, -40.0, 40.0)
		var vs_err := desired_vs - v.vertical_speed()
		var desired_pitch := clampf(vs_err * 0.4 + rad_to_deg(asin(clampf(desired_vs / maxf(v.airspeed(), 30.0), -1, 1))), -15.0, 20.0)
		# yatışta burnu tutmak için ek çekiş
		desired_pitch += absf(v.roll_deg()) * 0.08
		out["pitch"] = clampf((desired_pitch - v.pitch_deg()) * 0.06 - w.x * 1.2, -1.0, 1.0)
	if hold_speed:
		var s_err := target_speed - v.airspeed()
		out["throttle"] = clampf(0.55 + s_err * 0.05, 0.0, 1.0)
	return out
