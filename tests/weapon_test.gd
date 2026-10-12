extends Node
## Silah testi: oyuncuyu düşmanın arkasına koyar; önce IR füze (kilit + fırlatma), sonra top.
## Düşmanın kalan parçalarını ve kopan parçaları yazdırır.

var main: Node
var _t := 0.0
var _next := 0.0


func _ready() -> void:
	await get_tree().physics_frame
	var e: Vessel = main.enemy
	var v: Vessel = main.vessel
	v.global_transform = Transform3D(e.global_basis, e.global_position - e.forward() * 700.0 + e.up() * 20.0)
	v.linear_velocity = e.linear_velocity * 1.05
	v.reset_physics_interpolation()
	v.set_hot()
	v.master_arm = true
	v.selected_weapon = 1
	e.part_destroyed.connect(func(p: Part) -> void: print("  DÜŞMAN PARÇASI KOPTU: %s (t=%.1f)" % [p.title, _t]))


func _physics_process(delta: float) -> void:
	var v: Vessel = main.vessel
	var e: Vessel = main.enemy
	_t += delta
	if not is_instance_valid(e):
		return
	# hedefi burnun önünde tut (basit takip)
	var to := e.com_global() - v.com_global()
	var local := v.global_basis.inverse() * to.normalized()
	v.ctrl_pitch = clampf(local.y * 4.0, -1.0, 1.0)
	v.ctrl_roll = clampf(-local.x * 3.0, -1.0, 1.0)
	v.ctrl_throttle = 0.85
	var lock := false
	for m in v.modules:
		if m is MissileModule and m.target:
			lock = true
	if _t > 6.0:
		v.selected_weapon = 0
	v.ctrl_fire = (_t > 2.0 and _t < 2.2) or (lock and _t < 6.0 and v.missiles_left() == 2) or (_t > 7.0 and _t < 11.0)
	if _t >= _next:
		_next += 0.5
		print("t=%4.1f mesafe=%5.0f kilit=%s füze=%d mermi=%d düşman_parça=%d mermi_uçuşta=%d" % [
			_t, to.length(), lock, v.missiles_left(), v.gun_ammo(), e.parts.size(), ProjectileManager.instance._pos.size()])
	if _t > 14.0:
		print("SİLAH TESTİ BİTTİ")
		get_tree().quit()
