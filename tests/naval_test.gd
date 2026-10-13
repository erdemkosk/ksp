extends Node
## Deniz grubu testi (--navaltest, --air ile). Kayıtlara dokunmaz (Crew._testing), sonunda çıkar.
## Uçak gemisi grubu kurulur; oyuncunun uçağı 0-70 sn grubun çevresinde 5 km yarıçaplı daire
## çizer (1500 m): SAM, baş topu, CIWS ve avcı kaldırma yazdırılır. 70 sn'den sonra gemiler
## mermi (zırh) ve gemi savar füzesi eşdeğeri patlamalarla vurulur, batış izlenir.

var main: Node
var _t := 0.0
var _print_t := 0.0
var _ships: Array[Warship] = []
var _hits0 := 0
var _hp0 := 0.0
var _armor_done := false
var _blast_t := 0.0


func _ready() -> void:
	main = get_tree().current_scene
	main.player.enabled = false
	if Game.mission != "":
		# görev kipi (--mission=filo|firkateyn|devriye --missiontest): görev gemilerini sırayla batır
		_ships.assign(Warship.ships.duplicate())
		print("NAVAL: görev %s, %d gemi" % [Game.mission, _ships.size()])
		return
	_ships = NavalGroup.spawn(main.world, "carrier", NavalGroup.FLEET_ROUTE, NavalGroup.FLEET_XZ)
	_hits0 = Damage.vessel_hits
	print("NAVAL: test başladı, %d gemi" % _ships.size())


func _physics_process(delta: float) -> void:
	_t += delta
	_print_t -= delta
	if Game.mission != "":
		_mission_tick(delta)
		return
	var cv := _ships[0] as Carrier
	var dd := _ships[1] as Frigate
	var v: Vessel = main.vessel
	if _t < 70.0 and is_instance_valid(v) and not v.parts.is_empty():
		# daire: muhribin çevresinde 5 km, 1500 m
		var c := GroundTarget.surface_xz(dd.global_position)
		var a := _t * 0.04
		var xz := c + Vector2(cos(a), sin(a)) * 5000.0
		var xz2 := c + Vector2(cos(a + 0.001), sin(a + 0.001)) * 5000.0
		var p := MissionManager.world_point(xz.x, xz.y, 1500.0)
		var p2 := MissionManager.world_point(xz2.x, xz2.y, 1500.0)
		v.global_position = p - (v.com_global() - v.global_position)
		v.global_basis = Basis.looking_at((p2 - p).normalized(), Planet.up_at(p))
		v.linear_velocity = (p2 - p).normalized() * 200.0
		v.angular_velocity = Vector3.ZERO
	elif _t >= 70.0 and is_instance_valid(v) and not v.parts.is_empty():
		# uzaklaş: grubun 60 km dışına (avcılar peşinden gelebilir)
		var p := MissionManager.world_point(-20000.0, 10000.0, 3000.0)
		v.global_position = p
		v.linear_velocity = Vector3.ZERO
	if _t > 72.0 and not _armor_done:
		_armor_done = true
		_hp0 = dd.hp
		for i in 100:
			dd.take_damage(28.0)
		print("NAVAL: zırh: muhribe 100 top mermisi (28) → hp %.0f → %.0f (%.1f/mermi)" % [_hp0, dd.hp, (_hp0 - dd.hp) / 100.0])
	if _t > 75.0:
		_blast_t -= delta
		if _blast_t <= 0.0:
			_blast_t = 3.0
			# gemi savar füzesi eşdeğeri: gövdenin baş tarafına (merkezden uzak) isabet
			for s in _ships:
				if not s.destroyed:
					var hit := s.to_global(Vector3(0, s.hull_size.y * 0.5, -s.hull_size.z * 0.4))
					var hp := s.hp
					Damage.explosion(hit, 20.0, 2400.0, null)
					print("NAVAL: t=%.0f %s gemi savar isabeti: hp %.0f → %.0f (gövdeye %.1f m)" % [_t, s.unit_name, hp, s.hp, s.blast_distance(hit)])
					break
	if _print_t <= 0.0:
		_print_t = 5.0
		var ciws := 0
		for s in _ships:
			for g in s._guns:
				ciws += g.shots
		var vd := v.com_global().distance_to(dd.global_position) / 1000.0 if is_instance_valid(v) else -1.0
		var line := "NAVAL t=%5.1f | uçak %s parça=%d can=%.0f mesafe=%.1fkm isabet=%d flak=%d | CIWS mermi=%d | topatış=%d | CV havada=%d kalan=%d |" % [
			_t, "sağ" if is_instance_valid(v) and v.has_pilot() else "YOK", v.parts.size() if is_instance_valid(v) else 0, _part_hp(v), vd,
			Damage.vessel_hits - _hits0, FlakShell.bursts, ciws, dd.gun_shots, cv.airborne(), cv.air_wing]
		for s in _ships:
			var off := s.global_position.distance_to(cv.global_position)
			line += " %s hp=%.0f füze=%d %s%.0fm" % [s.tag, s.hp, s.missiles, "BATIK " if s.destroyed else "", off]
		print(line)
		for f in cv.flights:
			if is_instance_valid(f) and not f.parts.is_empty():
				print("NAVAL   avcı %s irtifa=%.0f hız=%.0f" % [f.craft_name, Planet.altitude(f.com_global()), f.linear_velocity.length()])
	var all_sunk := true
	for s in _ships:
		all_sunk = all_sunk and s.destroyed
	if _t > 150.0 or (all_sunk and _t > 100.0):
		print("NAVAL SONUÇ: batık=%s, avcı kaldırma=%d, topatış=%d, flak=%d, uçak isabet=%d" % [all_sunk, cv.flights.size(), dd.gun_shots, FlakShell.bursts, Damage.vessel_hits - _hits0])
		get_tree().quit()


func _part_hp(v: Vessel) -> float:
	var s := 0.0
	if is_instance_valid(v):
		for p in v.parts:
			s += p.hp
	return s


func _mission_tick(delta: float) -> void:
	_blast_t -= delta
	if _t < 5.0 or _blast_t > 0.0:
		return
	_blast_t = 2.0
	var mm: MissionManager = main.mission
	for s in _ships:
		if not s.destroyed:
			Damage.explosion(s.to_global(Vector3(0, s.hull_size.y * 0.5, -s.hull_size.z * 0.3)), 20.0, 2400.0, null)
			break
	print("NAVAL t=%.0f görev=%s %s | düşman uçak=%d" % [_t, mm.state, mm.objectives[0]["text"], mm._enemies.size()])
	if _t > 120.0:
		get_tree().quit()
