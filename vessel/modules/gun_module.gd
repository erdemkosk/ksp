class_name GunModule
extends PartModule
## Top: saniyede `rate` mermi, namlu çıkış hızı uçağın hızına eklenir. Her 4 mermiden biri izli.
## MASTER ARM açık, top seçili ve tetik basılıyken ateşler.

var rate := 50.0
var muzzle_velocity := 1000.0
var damage := 28.0
var ammo := 500
var spread_deg := 0.25
## Yapay zeka için: hedefin öncü noktasına en fazla bu kadar (derece) yönlenebilen top
var gimbal_deg := 0.0
var aim_target: Vessel

var _timer := 0.0
var _count := 0
var _sound: AudioStreamPlayer3D
var _flash: OmniLight3D
var _firing := false


func setup(p: Dictionary) -> void:
	rate = p.get("rate", rate)
	muzzle_velocity = p.get("muzzle_velocity", muzzle_velocity)
	damage = p.get("damage", damage)
	ammo = int(p.get("ammo", ammo))


func on_attached() -> void:
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = Sfx.looped("gun_loop.ogg")
	_sound.unit_size = 25.0
	_sound.max_distance = 4000.0
	part.add_child(_sound)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.3)
	_flash.omni_range = 8.0
	_flash.light_energy = 0.0
	_flash.position = muzzle_local()
	part.add_child(_flash)


func muzzle_local() -> Vector3:
	return Vector3(0, 0, -part.size.z * 0.5 - 0.3)


func physics_tick(delta: float) -> void:
	var want := vessel.ctrl_fire and vessel.master_arm and vessel.selected_weapon == 0 and ammo > 0 and vessel.has_power()
	_timer -= delta
	if want:
		while _timer <= 0.0 and ammo > 0:
			_timer += 1.0 / rate
			_fire_one()
	else:
		_timer = maxf(_timer, 0.0)
	if want != _firing:
		_firing = want
		if want:
			_sound.bus = Sfx.world_bus()
			_sound.play()
		else:
			_sound.stop()
			Sfx.play_at("gun_stop.ogg", part.global_position, -2.0)
	_flash.light_energy = randf_range(1.5, 3.5) if want else 0.0


func _fire_one() -> void:
	ammo -= 1
	_count += 1
	var b := part.global_basis
	var bore := -b.z
	if gimbal_deg > 0.0 and is_instance_valid(aim_target) and not aim_target.parts.is_empty():
		var want := lead_direction(aim_target)
		var ang := bore.angle_to(want)
		var lim := deg_to_rad(gimbal_deg)
		if ang > 0.0001:
			bore = bore.slerp(want, minf(lim / ang, 1.0))
	var dir := bore.rotated(b.x, deg_to_rad(randf_range(-spread_deg, spread_deg))).rotated(b.y, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var muzzle := part.global_transform * muzzle_local()
	ProjectileManager.instance.spawn(muzzle, vessel.linear_velocity + dir * muzzle_velocity, damage, _count % 4 == 0, vessel)
	# geri tepme
	vessel.add_force_at(-dir * damage * 300.0, muzzle)


## Merminin `dist` metreye (göreli) varış süresi: sürükleme yavaşlatır (a = k·V²).
static func bullet_time(dist: float, mv: float, own_speed: float) -> float:
	var a := ProjectileManager.DRAG_K * pow(mv + own_speed, 2.0)
	var disc := mv * mv - 2.0 * a * dist
	if disc <= 0.0:
		return dist / (mv * 0.5)
	return (mv - sqrt(disc)) / a


## Hedefe isabet için namlunun bakması gereken yön (dünya uzayı).
func lead_direction(target: Vessel) -> Vector3:
	var muzzle := part.global_transform * muzzle_local()
	var to := target.com_global() - muzzle
	var t := bullet_time(to.length(), muzzle_velocity, vessel.linear_velocity.length())
	var aim := to + (target.linear_velocity - vessel.linear_velocity) * t - Planet.gravity_at(muzzle) * 0.5 * t * t
	return aim.normalized()
