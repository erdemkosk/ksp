extends Node
## --nodeprobe: bir uçağın düğüm sayısını parçaya ve türe göre döker (performans).
var main: Node

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var v: Vessel = main.vessel
	var by_part := {}
	var by_type := {}
	var procs := 0
	var stack: Array[Node] = [v]
	var total := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		total += 1
		by_type[n.get_class()] = by_type.get(n.get_class(), 0) + 1
		if n.is_processing() or n.is_physics_processing():
			procs += 1
		var p: Node = n
		while p and not p is Part and p != v:
			p = p.get_parent()
		if p is Part:
			by_part[(p as Part).part_id] = by_part.get((p as Part).part_id, 0) + 1
	print("NODES toplam %d, işleyen %d" % [total, procs])
	for k in by_part:
		if by_part[k] > 30:
			print("  parça %s: %d" % [k, by_part[k]])
	for k in by_type:
		if by_type[k] > 40:
			print("  tür %s: %d" % [k, by_type[k]])
	get_tree().quit()
