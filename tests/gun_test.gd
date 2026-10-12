extends Node
## Top isabet testi: hedef aynı hızla önümüzde; burun hedefe kilitli, 1.5 sn ateş.

var main: Node
var _t := 0.0
var _hits0 := 0
var _dist := 500.0


func _ready() -> void:
	await get_tree().physics_frame
	var e: Vessel = main.enemy
	var v: Vessel = main.vessel
	for c in e.get_children():
		if c is AIPilot:
			c.queue_free()
	_dist = float(Game.args.get("dist", "500"))
	e.global_transform = Transform3D(v.global_basis, v.global_position + v.forward() * _dist)
	e.linear_velocity = v.linear_velocity
	e.reset_physics_interpolation()
	v.set_hot()
	v.master_arm = true
	v.selected_weapon = 0
	_hits0 = Damage.vessel_hits


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	var e: Vessel = main.enemy
	# ikisini de hızla birlikte taşı, burnu hedefe çevir (kinematik)
	var to := e.com_global() - v.com_global()
	var up := Planet.up_at(v.global_position)
	var t := to.length() / 900.0
	var aim := to - Planet.gravity_at(v.global_position) * 0.5 * t * t
	v.global_basis = Basis.looking_at(aim.normalized(), up)
	v.angular_velocity = Vector3.ZERO
	e.angular_velocity = Vector3.ZERO
	e.linear_velocity = v.linear_velocity
	e.global_basis = v.global_basis
	v.ctrl_fire = _t > 0.5 and _t < 2.0
	if _t > 4.0:
		print("TOP TESTİ mesafe=%d  isabet=%d  atılan=%d  düşman_parça=%d" % [_dist, Damage.vessel_hits - _hits0, 500 - v.gun_ammo(), e.parts.size()])
		get_tree().quit()
