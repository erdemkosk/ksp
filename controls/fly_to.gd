class_name FlyTo
extends RefCounted
## Uçağı dünya uzayındaki bir yöne çeviren kumanda yasası (fareyle uçuş ve yapay zeka için).
## Büyük açıda "yat ve çek": hedefi gövdenin üst eksenine getirip çeker. Küçük açıda yatarak
## döner ve dümenle ince ayar yapar. İntegral terimler 1 G için gereken sürekli çekişi öğrenir.
## G sınırını aşmaz (yapıyı ve pilotu korur).

var pitch_i := 0.0
var yaw_i := 0.0


## {pitch, roll, yaw} döndürür (-1..1).
func compute(vessel: Vessel, dir: Vector3, g_limit: float, delta: float) -> Dictionary:
	var b := vessel.global_basis
	var local := (b.inverse() * dir).normalized()
	var w := vessel.local_angular_velocity()
	var ang := acos(clampf(-local.z, -1.0, 1.0))
	var k := smoothstep(0.1, 0.25, ang)
	var coarse := atan2(local.x, local.y)
	var lateral := atan2(local.x, -local.z)
	var bank_goal := clampf(rad_to_deg(lateral) * 9.0, -70.0, 70.0)
	var fine := deg_to_rad(bank_goal - vessel.roll_deg())
	var roll := clampf(lerpf(fine, coarse, k) * 1.8 + w.z * 0.5, -1.0, 1.0)
	var vert := atan2(local.y, -local.z)
	if ang < 0.3:
		pitch_i = clampf(pitch_i + vert * delta * 2.5, -0.3, 0.6)
		yaw_i = clampf(yaw_i + lateral * delta * 1.5, -0.3, 0.3)
	else:
		pitch_i = move_toward(pitch_i, 0.0, delta * 0.3)
		yaw_i = move_toward(yaw_i, 0.0, delta)
	var pitch := vert * 3.5 - w.x * 0.6 + pitch_i
	if absf(coarse) > 1.4 and ang > 0.3:
		pitch = minf(pitch, 0.15)
	if vessel.g_force > g_limit:
		pitch -= (vessel.g_force - g_limit) * 0.35
	var yaw := lateral * 4.0 + yaw_i if ang < 0.25 else 0.0
	return {"pitch": clampf(pitch, -0.5, 1.0), "roll": roll, "yaw": clampf(yaw + w.y * 1.0, -1.0, 1.0)}
