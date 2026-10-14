class_name LandingGearModule
extends PartModule
## Raycast süspansiyonlu iniş takımı: yay-sönümleyici, yanal sürtünme, fren, burun tekeri dümeni.

var rest_length := 1.2
var wheel_radius := 0.35
var spring := 100000.0
var damper := 12000.0
var steerable := false
var max_steer := deg_to_rad(35.0)
var side_friction := 0.9
var brake_friction := 0.6
var rolling_resistance := 0.02
## Açıkken hava direnci (m² × Cd). Toplanınca sıfıra iner.
var drag_area := 0.4

var grounded := false
var compression := 0.0
## 0 = toplanmış, 1 = tam açık. Animasyonla değişir (~2.5 sn).
var deploy := 1.0
const DEPLOY_RATE := 0.4
const FOLD_DEG := 88.0

## Açık takım hız sınırı (m/s; gerçekte VLE): üstünde takım zorlanır, hasar alır, sürerse kopar.
## Açılıp kapanırken (kapaklar açık, dikme yolda) sınır %15 daha düşük. Ağır takımlar daha hassas.
var max_speed := 160.0
var _over_warned := false
var _over_t := 0.0

var _visual: Node3D
var _strut: Node3D
var _wheel: Node3D


func setup(p: Dictionary) -> void:
	rest_length = p.get("rest_length", rest_length)
	wheel_radius = p.get("wheel_radius", wheel_radius)
	spring = p.get("spring", spring)
	damper = p.get("damper", damper)
	steerable = p.get("steerable", steerable)
	max_steer = deg_to_rad(p.get("max_steer_deg", 35.0))
	drag_area = p.get("drag_area", 0.25 if steerable else 0.4)
	max_speed = p.get("max_speed", max_speed)


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual")
	_strut = part.get_node_or_null("Visual/Strut")
	_wheel = part.get_node_or_null("Visual/Wheel")


func physics_tick(delta: float) -> void:
	# yerdeyken takım toplanmaz (gerçek uçaklardaki tekerlek-yük kilidi): pistte yanlışlıkla G'ye
	# basınca uçak göbeğine oturuyordu
	if not vessel.gear_down and grounded:
		vessel.gear_down = true
		if Time.get_ticks_msec() - int(vessel.get_meta("wow_msg", 0)) > 2000:
			vessel.set_meta("wow_msg", Time.get_ticks_msec())
			vessel.system_message.emit("Yerdeyken takım toplanmaz — havalanınca topla")
	deploy = move_toward(deploy, 1.0 if vessel.gear_down else 0.0, DEPLOY_RATE * delta)
	grounded = false
	compression = 0.0
	_apply_drag()
	_overspeed(delta)
	if deploy > 0.97:
		_simulate()
	_update_visual()


## Bu takımın şu anki hız sınırı (m/s): hareket halindeyken daha düşük.
func speed_limit() -> float:
	return max_speed * (0.85 if deploy < 0.99 else 1.0)


## Hız sınırı üstünde açık / açılan takım: uyarı, sınırı aştıkça hızlanan hasar → kopar.
func _overspeed(delta: float) -> void:
	var key := "gear%d" % part.get_instance_id()
	var lim := speed_limit()
	var spd := vessel.airspeed()
	if deploy <= 0.05 or spd <= lim:
		if vessel.failures.has(key):
			vessel.failures.erase(key)
		if spd < lim * 0.9:
			_over_warned = false
		_over_t = maxf(_over_t - delta, 0.0)
		return
	var over := (spd - lim) / lim
	vessel.failures[key] = "TAKIM HIZ SINIRI — TOPLA"
	if not _over_warned:
		_over_warned = true
		vessel.system_message.emit("TAKIM HIZ SINIRI! %d km/sa üstü: takımı topla (G) ya da yavaşla" % (lim * 3.6))
		Sfx.play_at("impact_metal_2.ogg", part.global_position, -4.0, 0.7, 600.0)
	# toplamaya fırsat: ilk 3 sn yalnız uyarı (titreşim sesi), sonra hasar başlar;
	# %10 aşımda ~10 sn, %40 aşımda ~3 sn daha dayanır
	_over_t += delta
	if _over_t > 3.0:
		vessel.damage_part(part, part.max_hp * (0.04 + over * 0.6) * delta)


func _simulate() -> void:
	var up := vessel.global_basis.y
	var origin := part.global_position
	var max_len := rest_length + wheel_radius
	var query := PhysicsRayQueryParameters3D.create(origin, origin - up * max_len, 1, [vessel.get_rid()])
	var hit := vessel.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	grounded = true
	var contact: Vector3 = hit.position
	var n: Vector3 = hit.normal
	compression = max_len - origin.distance_to(contact)

	var v := vessel.velocity_at(contact)
	var sink_speed := -v.dot(n)
	var normal_force := maxf(spring * compression + damper * sink_speed, 0.0)
	# dikme dibe vurduysa sert iniş: takım hasar alır (6 m/s üstü batış hızı)
	if compression > rest_length * 0.9 and sink_speed > 6.0:
		vessel.damage_part(part, pow(sink_speed - 6.0, 2.0) * 25.0)
	var force := n * normal_force

	var fwd := vessel.forward()
	fwd = (fwd - n * fwd.dot(n)).normalized()
	if steerable:
		var fade := clampf(1.0 - v.length() / 60.0, 0.15, 1.0)
		fwd = fwd.rotated(n, -vessel.ctrl_yaw * max_steer * fade)
	var side := fwd.cross(n)

	var v_side := v.dot(side)
	var v_fwd := v.dot(fwd)
	var side_limit := side_friction * normal_force
	force += side * clampf(-v_side * normal_force * 4.0, -side_limit, side_limit)
	if vessel.ctrl_brakes or vessel.parking_brake:
		var brake_limit := brake_friction * normal_force
		force += fwd * clampf(-v_fwd * normal_force * 4.0, -brake_limit, brake_limit)
	else:
		var roll_limit := rolling_resistance * normal_force
		force += fwd * clampf(-v_fwd * normal_force * 2.0, -roll_limit, roll_limit)

	vessel.add_force_at(force, contact)


func _update_visual() -> void:
	if _visual == null:
		return
	# Katlanma: ana takımlar gövdeye doğru (Z ekseni), burun takımı öne doğru (X ekseni) döner
	var fold := deg_to_rad(FOLD_DEG) * (1.0 - smoothstep(0.0, 1.0, deploy))
	if absf(part.position.x) > 0.1:
		_visual.rotation = Vector3(0, 0, -signf(part.position.x) * fold)
	else:
		_visual.rotation = Vector3(fold, 0, 0)
	_visual.visible = deploy > 0.02
	var extension := clampf(rest_length - compression, 0.05, rest_length)
	# görsel düğüm dünya ölçeğiyle büyütülmüş: uzunlukları onun uzayına çevir
	var vs := absf(_visual.scale.y) if _visual else 1.0
	if _wheel:
		_wheel.position.y = -extension / vs
	if _strut:
		_strut.position.y = -extension * 0.5 / vs
		_strut.scale.y = extension / rest_length


## Açık takımın hava direnci: dikme ve tekerlek akışa maruz kalır.
func _apply_drag() -> void:
	if deploy <= 0.01:
		return
	var pos := part.global_position - vessel.global_basis.y * rest_length * 0.5 * deploy
	var v := vessel.air_velocity_at(pos)
	var speed := v.length()
	if speed < 1.0:
		return
	var q := 0.5 * vessel.air_density() * speed * speed
	var f := -v / speed * q * drag_area * deploy
	vessel.add_force_at(f, pos)
	part.aero_load += f
