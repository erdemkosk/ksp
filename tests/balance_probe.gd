extends Node
## --balance: uçağın kütle merkezi, kanat alanı merkezi ve takım konumlarını yazar (z+ = geri).

var main: Node


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var v: Vessel = main.vessel
	var com := v.center_of_mass
	var wa := 0.0
	var wz := 0.0
	var tail := 0.0
	for p in v.parts:
		if Game.args.has("sizes"):
			var vis := p.get_node_or_null("Visual") as Node3D
			print("  %s z=%.2f vis_scale=%s" % [p.part_id, p.position.z, vis.scale if vis else Vector3.ZERO])
	for p in v.parts:
		for m in p.modules:
			if m is WingModule:
				var a: float = m.area
				var horiz := absf(p.global_basis.y.dot(v.global_basis.y)) > 0.5
				if horiz:
					wa += a
					wz += a * p.position.z
					if p.position.z > com.z + 6.0:
						tail += a
			elif m is LandingGearModule:
				print("  takım %s z=%.2f" % [p.part_id, p.position.z])
	print("BALANCE kütle %.0f kg  CoM z=%.2f y=%.2f  kanat merkezi z=%.2f (alan %.1f, kuyruk %.1f)" % [v.mass, com.z, com.y, wz / maxf(wa, 0.01), wa, tail])
	get_tree().quit()
