extends Node
## --damagefx: hasar görselleri testi. Gerçek ışın isabetleriyle (Damage.apply_hit) gövde, motor ve
## kanatlara kurşun delikleri açar, yakına bir patlama koyar, sonra sol kanadı koparır.
## Ekran görüntüsü için: --screenshot=x.png --shot-time=2.5 --camera=2 ...

var main: Node


func _ready() -> void:
	await get_tree().create_timer(0.4).timeout
	var v: Vessel = main.vessel
	var space := v.get_world_3d().direct_space_state
	var hits := 0
	for p: Part in v.parts.duplicate():
		var n := 0
		match p.part_id:
			"tank_long": n = 6
			"jet_engine": n = 5
			"cockpit_mk1": n = 3
			"wing_main": n = 8
			"stabilator": n = 3
		for i in n:
			# parçanın üstünden / yanından ona doğru ışın (gerçek isabet noktası ve normali)
			var tgt := p.global_transform * Vector3(randf_range(-0.4, 0.4) * p.size.x, 0.0, randf_range(-0.4, 0.4) * p.size.z)
			var dir := (v.global_basis * Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.0), randf_range(-0.3, 0.3))).normalized()
			var q := PhysicsRayQueryParameters3D.create(tgt + dir * 25.0, tgt - dir * 2.0)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit.get("collider") == v:
				Damage.apply_hit(hit, float(Game.args.get("hitdmg", "12")), -dir * 900.0)
				hits += 1
	print("DAMAGEFX isabet=%d" % hits)
	await get_tree().create_timer(0.3).timeout
	# kuyruğun yanında patlama (is lekesi + şarapnel)
	var eng: Part = null
	for p in v.parts:
		if p.part_id == "jet_engine":
			eng = p
	if eng:
		Damage.explosion(eng.global_transform * Vector3(2.5, 1.0, 1.0), 6.0, 30.0)
	await get_tree().create_timer(0.3).timeout
	if Game.args.has("nobreak"):
		return
	# sol ana kanadı kopar
	var wing: Part = null
	for p in v.parts:
		if p.part_id == "wing_main" and p.position.x < 0.0:
			wing = p
	if wing:
		var before := v.parts.size()
		v.destroy_part(wing)
		var caps := 0
		for p in v.parts:
			caps += p.find_children("TornCap", "", false, false).size()
		print("DAMAGEFX kanat koptu parça %d -> %d, kalan taraftaki kapak=%d" % [before, v.parts.size(), caps])
	if Game.args.has("quitafter"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
