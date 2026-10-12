class_name Damage
## Hasar yardımcıları: mermi isabeti ve patlama (alan hasarı).


## Araçlara isabet eden mermi sayısı (testler için).
static var vessel_hits := 0


## Işın isabeti: vurulan şey araçsa ilgili parçaya, yer hedefiyse hedefe hasar.
static func apply_hit(hit: Dictionary, damage: float, velocity: Vector3) -> void:
	var collider: Object = hit.get("collider")
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if collider is Vessel:
		var v: Vessel = collider
		vessel_hits += 1
		var part := v.part_for_shape(hit.get("shape", -1))
		if part:
			v.damage_part(part, damage)
			DamageFx.bullet_hole(part, pos, normal)
		v.apply_impulse(velocity.normalized() * damage * 0.4, pos - v.global_position)
		shake_camera(pos, 0.12, 40.0)
		var cam := (Engine.get_main_loop() as SceneTree).root.get_viewport().get_camera_3d() as FlightCamera
		if cam and cam.target == v:
			# bizim uçağımıza isabet: kabinde sert metal darbesi
			Sfx.play_ui("impact_metal_%d.ogg" % (1 + randi() % 2), -2.0, randf_range(0.7, 0.9))
			cam.add_trauma(0.15)
		Sfx.play_at("impact_metal_%d.ogg" % (1 + randi() % 2), pos, -4.0, randf_range(0.9, 1.2), 900.0)
		if randf() < 0.3:
			Sfx.play_at("ricochet_%d.ogg" % (1 + randi() % 2), pos, -2.0, randf_range(0.85, 1.15), 700.0)
		_spark(pos, normal)
	elif collider is GroundTarget:
		collider.take_damage(damage)
		Sfx.play_at("impact_metal_%d.ogg" % (1 + randi() % 2), pos, -4.0, randf_range(0.8, 1.0), 900.0)
		_spark(pos, normal)
	elif collider is RigidBody3D:
		if collider is Debris:
			# düşen enkaza isabet: en yakın parçaya delik
			var best: Part = null
			for p: Part in (collider as Debris).parts:
				if is_instance_valid(p) and (best == null or p.global_position.distance_squared_to(pos) < best.global_position.distance_squared_to(pos)):
					best = p
			if best:
				DamageFx.bullet_hole(best, pos, normal)
		collider.apply_impulse(velocity.normalized() * damage * 0.4, pos - collider.global_position)
		_spark(pos, normal)
	else:
		# zemine düşen mermi: toz
		Effects.dust(FloatingOrigin.world_root, pos, normal)


## Patlama: yarıçap içindeki tüm araç parçalarına ve yer hedeflerine mesafeyle azalan hasar.
static func explosion(pos: Vector3, radius: float, max_damage: float, source: Object = null) -> void:
	var root := FloatingOrigin.world_root
	AudioManager.near_blast(pos, radius)
	Effects.explosion(root, pos, Planet.up_at(pos), clampf(radius / 10.0, 1.0, 4.0))
	shake_camera(pos, 0.9, radius * 25.0)
	Sfx.explosion(pos, clampf(radius / 10.0, 1.0, 3.0))
	for node in root.get_children():
		if node is Vessel and node != source:
			var v: Vessel = node
			for part in v.parts.duplicate():
				var d: float = part.global_position.distance_to(pos)
				if d < radius:
					var f: float = 1.0 - d / radius
					v.damage_part(part, max_damage * f * f)
					if f > 0.25:
						DamageFx.blast_mark(part, pos, f)
			var dv := v.com_global().distance_to(pos)
			if dv < radius * 1.5:
				v.apply_central_impulse((v.com_global() - pos).normalized() * max_damage * 20.0 * (1.0 - dv / (radius * 1.5)))
		elif node is GroundTarget:
			var d: float = node.global_position.distance_to(pos)
			if d < radius:
				node.take_damage(max_damage * (1.0 - d / radius))


static func _spark(pos: Vector3, normal: Vector3) -> void:
	Effects.sparks(FloatingOrigin.world_root, pos, normal)


## Kamera sarsıntısı: oyuncunun uçağı vurulduğunda ya da yakında patlama olduğunda.
static func shake_camera(pos: Vector3, amount: float, radius: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var cam := tree.root.get_viewport().get_camera_3d() as FlightCamera
	if cam == null:
		return
	var d := cam.global_position.distance_to(pos)
	if d < radius:
		cam.add_trauma(amount * (1.0 - d / radius))
