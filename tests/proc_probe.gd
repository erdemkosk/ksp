extends Node
## --procprobe: _process / _physics_process yapan düğümleri betik türüne göre gruplar; her grubu
## sırayla kapatıp açarak (A/B/A/B, kaymayı götürür) işlem+fizik süresindeki farkı ölçer.
## --procai: yalnız oyuncu dışındaki uçakların düğümleri. Yalnız ölçüm içindir.

var main: Node


func _ready() -> void:
	await get_tree().create_timer(float(Game.args.get("procwait", "10"))).timeout
	var groups := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n == self or not (n.is_processing() or n.is_physics_processing()):
			continue
		if Game.args.has("procai") and not _in_ai(n):
			continue
		var s: Script = n.get_script()
		var key: String = s.resource_path.get_file() if s else n.get_class()
		if not groups.has(key):
			groups[key] = []
		groups[key].append(n)
	var res := []
	for k in groups:
		var on := 0.0
		var off := 0.0
		for rep in 4:
			on += await _measure(1.2)
			_toggle(groups[k], false)
			off += await _measure(1.2)
			_toggle(groups[k], true)
		res.append([(on - off) / 4.0, k, (groups[k] as Array).size()])
	res.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("PROC (işlem+fizik ms farkı, grup kapatılınca)")
	for r in res.slice(0, 20):
		print("  %-30s x%-3d %.2f ms" % [r[1], r[2], r[0]])
	get_tree().quit()


func _toggle(nodes: Array, on: bool) -> void:
	for n: Node in nodes:
		if not is_instance_valid(n):
			continue
		if not on:
			n.set_meta("pp", [n.is_processing(), n.is_physics_processing()])
			n.set_process(false)
			n.set_physics_process(false)
		elif n.has_meta("pp"):
			var pp: Array = n.get_meta("pp")
			n.set_process(pp[0])
			n.set_physics_process(pp[1])


func _in_ai(n: Node) -> bool:
	var p: Node = n
	while p:
		if p is Vessel:
			return p != main.vessel
		p = p.get_parent()
	return false


func _measure(sec: float) -> float:
	await get_tree().process_frame
	await get_tree().process_frame
	var sum := 0.0
	var n := 0
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
		sum += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		n += 1
	return sum / maxf(n, 1)
