extends Node
## --loaltest: düşman 3 km önde ama 40° yanda (arayıcı konisi dışında) → kilitsiz füze atılır.
## Füzenin uçuşta hedef bulup bulmadığı yazılır. --straight: düşman tam önde.

var main: Node
var _t := 0.0
var _fired := false
var _m: Missile


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	if _t > 0.5 and not is_instance_valid(main.enemy):
		main.spawn_enemy(false)
		var e: Vessel = main.enemy
		var off := 0.0 if Game.args.has("straight") else deg_to_rad(40.0)
		var dir := v.forward().rotated(v.up(), off)
		e.global_transform = Transform3D(v.global_basis, v.global_position + dir * 3000.0)
		e.linear_velocity = v.linear_velocity
		e.reset_physics_interpolation()
	if _t > 1.5 and not _fired:
		v.master_arm = true
		v.selected_weapon = Vessel.WEAPON_MISSILE
		main.player.enabled = false
		v.ctrl_fire = true
		if v.missiles_left() < 2:
			_fired = true
			v.ctrl_fire = false
			_m = Missile.active[0] if not Missile.active.is_empty() else null
			print("LOAL atıldı, kilit=%s" % [_m.target != null if _m else "füze yok"])
	if _fired and is_instance_valid(_m) and fmod(_t, 0.5) < delta:
		print("t=%.1f hedef=%s" % [_t, _m.target.name if is_instance_valid(_m.target) else "-"])
	if _t > 14.0:
		print("LOALTEST bitti, düşman parça=%d" % (main.enemy.parts.size() if is_instance_valid(main.enemy) else -1))
		get_tree().quit()
