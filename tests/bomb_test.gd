extends Node
## Bomba testi: konvoya doğru düz uçar, CCIP noktası bir tankın 12 m yakınına gelince bırakır.

var main: Node
var _t := 0.0
var _ap := Autopilot.new()
var _released := 0
var _min_ccip := INF
var _prev_cd := INF


func _ready() -> void:
	await get_tree().physics_frame
	var v: Vessel = main.vessel
	v.master_arm = true
	v.selected_weapon = Vessel.WEAPON_BOMB
	_ap.level = true
	_ap.hold_altitude = true
	_ap.hold_heading = true
	_ap.hold_speed = true
	_ap.target_altitude = v.altitude()
	_ap.target_speed = 200.0
	_ap.target_heading = v.heading_deg()


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	# en yakın sağlam tankın yönüne dön
	var best: GroundTarget = null
	var bd := INF
	for n in main.world.get_children():
		if n is GroundTarget and not n.destroyed:
			var d: float = n.global_position.distance_to(v.com_global())
			if d < bd:
				bd = d
				best = n
	if best:
		var to := best.global_position - v.com_global()
		var fr := Planet.local_basis(v.global_position)
		_ap.target_heading = fposmod(rad_to_deg(atan2(to.dot(fr.x), -to.dot(fr.z))), 360.0)
	# yakında: düşüş noktasının yanal hatasına göre ince yön düzeltmesi
	var pre: Variant = Bomb.simulate_impact(v.get_world_3d().direct_space_state, v.com_global() - v.up() * 0.8, v.linear_velocity)
	if pre != null and best and bd < 6000.0:
		var fr2 := Planet.local_basis(v.global_position)
		var vel_h := (v.linear_velocity - fr2.y * v.linear_velocity.dot(fr2.y)).normalized()
		var right := vel_h.cross(fr2.y)
		var lat := (best.global_position - (pre as Vector3)).dot(right)
		var trk := fposmod(rad_to_deg(atan2(vel_h.dot(fr2.x), -vel_h.dot(fr2.z))), 360.0)
		_ap.target_heading = fposmod(trk + clampf(lat * 0.08, -15.0, 15.0), 360.0)
	var out := _ap.compute(v)
	v.ctrl_pitch = out["pitch"] if out["pitch"] != null else 0.0
	v.ctrl_roll = out["roll"] if out["roll"] != null else 0.0
	v.ctrl_throttle = out["throttle"] if out["throttle"] != null else 0.7
	var impact: Variant = Bomb.simulate_impact(v.get_world_3d().direct_space_state, v.com_global() - v.up() * 0.8, v.linear_velocity)
	v.ctrl_fire = false
	if impact != null and best:
		_min_ccip = minf(_min_ccip, (impact as Vector3).distance_to(best.global_position))
	var cd := (impact as Vector3).distance_to(best.global_position) if impact != null and best else INF
	# en yakın noktada bırak: mesafe artmaya başladığı an (ve yarıçap içindeyken)
	var release := cd < Bomb.BLAST_RADIUS * 1.2 and cd > _prev_cd and _prev_cd < Bomb.BLAST_RADIUS * 1.2
	_prev_cd = cd
	if release and v.bombs_left() > 0:
		v.ctrl_fire = true
		_released += 1
		print("t=%.1f BOMBA BIRAKILDI  hedefe %.0f m, kalan %d" % [_t, bd, v.bombs_left() - 1])
	if fmod(_t, 5.0) < delta:
		var dead := 0
		for n in main.world.get_children():
			if n is GroundTarget and n.destroyed:
				dead += 1
		var li := Bomb.last_impact
		var near := INF
		for n in main.world.get_children():
			if n is GroundTarget:
				near = minf(near, n.global_position.distance_to(li))
		print("t=%.0f irt=%d hedefe=%.0f m ccip_min=%.0f yok edilen=%d bomba=%d  son_bomba_tanka=%.0f m" % [_t, v.altitude(), bd, _min_ccip, dead, v.bombs_left(), near])
		_min_ccip = INF
	if _t > 90.0 or (v.bombs_left() == 0 and _t > 30.0 and fmod(_t, 5.0) < delta and _released > 0 and _t > 60.0):
		get_tree().quit()
