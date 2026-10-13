class_name Frigate
extends Warship
## Fırkateyn / muhrip: korvetten büyük (130 m). Arama radarı 40 km, iki dikey atım bloğunda
## 16 radar güdümlü SAM (16 km), iki CIWS ve baş tarafta 76 mm uçaksavar topu: 6.5 km içindeki
## uçağa öncül nişanla yakınlık tapalı mermi atar (FlakShell). Batırmak için 2-3 gemi savar
## füzesi ya da birkaç ağır bomba gerekir.

const GUN_RANGE := 6500.0
const GUN_SPEED := 850.0
const GUN_EVERY := 1.4
const GUN_ERROR := deg_to_rad(0.25)

var main_gun: GunMount
var gun_shots := 0
var _gun_cd := 2.0
var _prev_vel := Vector3.ZERO
var _acc := Vector3.ZERO


static func create_frigate(title := "Düşman fırkateyni") -> Frigate:
	var t := Frigate.new()
	t.unit_name = title
	t.hp = 5200.0
	t.missiles = 16
	t.radar_range = 40000.0
	t.sam_range = 16000.0
	t.reload = 7.0
	t.speed = 9.0
	t.sink_time = 28.0
	t.sink_depth = 16.0
	t.tag = "DD"
	t._collision(Vector3(15.0, 13.0, 132.0), Vector3(0, 4.0, 0))
	var grey := Color(0.46, 0.49, 0.52)
	t._hull = _mesh(t, Vector3(14.0, 7.0, 104.0), Vector3(0, 1.5, 9.0), grey)
	var bow := _mesh(t, Vector3(9.9, 7.0, 9.9), Vector3(0, 1.5, -43.0), grey)
	bow.rotation_degrees = Vector3(0, 45, 0)
	_mesh(t, Vector3(10.0, 1.6, 14.0), Vector3(0, 5.6, -34.0), grey)        # baş kasarası
	_mesh(t, Vector3(14.2, 0.5, 120.0), Vector3(0, -1.6, 3.0), Color(0.45, 0.12, 0.1))    # su hattı
	_mesh(t, Vector3(13.4, 0.3, 100.0), Vector3(0, 5.1, 10.0), Color(0.34, 0.36, 0.38))   # güverte
	# üst yapı: köprü bloğu, helikopter hangarı, bacalar
	_mesh(t, Vector3(11.0, 7.0, 30.0), Vector3(0, 8.5, -2.0), grey.lightened(0.06))
	_mesh(t, Vector3(9.0, 3.0, 10.0), Vector3(0, 13.5, -10.0), grey.lightened(0.08))
	_mesh(t, Vector3(9.2, 1.2, 1.0), Vector3(0, 14.2, -15.1), Color(0.12, 0.15, 0.18))    # köprü camı
	_mesh(t, Vector3(12.0, 5.5, 18.0), Vector3(0, 7.8, 30.0), grey.lightened(0.04))       # hangar
	_mesh(t, Vector3(13.0, 0.2, 14.0), Vector3(0, 5.35, 47.0), Color(0.25, 0.27, 0.28))   # helikopter pisti
	for z in [8.0, 18.0]:
		_mesh(t, Vector3(4.0, 5.0, 5.0), Vector3(0, 14.0, z), Color(0.24, 0.25, 0.26))     # bacalar
	t._add_mast(Vector3(0, 15.0, -4.0), 11.0, 7.0)
	# dikey atım blokları: köprü önü ve hangar önü
	t._add_launcher(Vector3(0, 5.3, -22.0), 8)
	t._add_launcher(Vector3(0, 5.3, 19.0), 8)
	# CIWS: köprü üstü ve hangar üstü
	t._add_ciws(Vector3(0, 15.0, -14.0))
	t._add_ciws(Vector3(0, 10.6, 36.0))
	# baş topu: taret + uzun namlu
	var yaw := Node3D.new()
	yaw.position = Vector3(0, 6.4, -33.0)
	t.add_child(yaw)
	var tur := _mesh(yaw, Vector3(3.6, 2.2, 4.6), Vector3(0, 1.1, 0.3), grey.lightened(0.1))
	tur.name = "Turret"
	var pitch := Node3D.new()
	pitch.position = Vector3(0, 1.4, -1.6)
	yaw.add_child(pitch)
	_cyl(pitch, 0.16, 6.0, Vector3(0, 0, -3.0), Vector3(90, 0, 0), Color(0.3, 0.31, 0.32))
	var muzzles: Array[Vector3] = [Vector3(0, 0, -6.2)]
	var g := GunMount.new(t, yaw, pitch, muzzles)
	g.yaw_rate = deg_to_rad(40.0)
	g.pitch_rate = deg_to_rad(30.0)
	g.max_pitch = deg_to_rad(80.0)
	g.add_flash(0.8)
	t.main_gun = g
	return t


func _weapons(delta: float, v: Vessel, seen: bool, dist: float) -> void:
	_gun_cd -= delta
	if v == null or dist > GUN_RANGE or not (seen or dist < Detection.VISUAL_RANGE) or not line_of_sight(v.com_global()):
		main_gun.rest(delta, threat_point())
		return
	# öncül nişan: mermi uçuş süresi kadar ileri (hız + kestirilen ivme), düşüş telafili
	_acc = _acc.lerp((v.linear_velocity - _prev_vel) / maxf(delta, 0.001), 1.0 - exp(-1.5 * delta)).limit_length(60.0)
	_prev_vel = v.linear_velocity
	var muzzle := main_gun.pitch_node.global_position
	var p0 := v.com_global()
	var tp := p0
	var t := FlakShell.flight_time(muzzle.distance_to(tp), GUN_SPEED)
	for i in 3:
		tp = p0 + v.linear_velocity * t + _acc * (0.5 * t * t)
		t = FlakShell.flight_time(muzzle.distance_to(tp), GUN_SPEED)
	tp -= Planet.gravity_at(tp) * 0.5 * t * t
	var err := main_gun.slew_to(tp, delta)
	main_gun._tick(delta)
	if err < deg_to_rad(0.3) and _gun_cd <= 0.0:
		_gun_cd = GUN_EVERY
		_shoot(v, t)


func _shoot(v: Vessel, t: float) -> void:
	gun_shots += 1
	var b := main_gun.pitch_node.global_basis.orthonormalized()
	var dir := (-b.z).rotated(b.x, randfn(0.0, GUN_ERROR)).rotated(b.y, randfn(0.0, GUN_ERROR))
	var s := FlakShell.new()
	s.velocity = dir * GUN_SPEED
	s.target = v
	s.fuse_t = t + 0.6
	get_parent().add_child(s)
	s.global_position = main_gun.pitch_node.global_transform * main_gun.muzzles[0]
	main_gun._flash_t = 0.08
	Sfx.play_at("gun_stop.ogg", s.global_position, 8.0, 0.35, 7000.0)
	if gun_shots == 1:
		v.system_message.emit("GEMİ TOPU ATEŞ EDİYOR — 6 km dışına çık ya da alçal")
	if Game.args.has("navaltest") and gun_shots % 5 == 1:
		print("NAVAL: %s baş topu atış #%d, hedef %.1f km" % [unit_name, gun_shots, v.com_global().distance_to(global_position) / 1000.0])
