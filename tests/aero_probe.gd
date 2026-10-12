extends Node
## --aeroprobe: 6 sn düz uçuştan sonra kanatların aşağı akışını ve gövde yüzlerini yazar.

var main: Node
var _t := 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 6.0:
		return
	var v: Vessel = main.vessel
	if Game.args.has("picktest"):
		var ok := 0
		var bad := PackedStringArray()
		for p in v.parts:
			var up := v.global_basis.y
			var c := p.global_position
			var got := v.pick_part(c + up * 30.0, c - up * 30.0)
			var side := v.pick_part(c + v.global_basis.x * signf(p.position.x + 0.001) * 30.0, c)
			if got == p or side == p:
				ok += 1
			else:
				bad.append("%s→%s" % [p.title, got.title if got else "-"])
		print("PICKTEST doğru=%d/%d yanlış=%s" % [ok, v.parts.size(), bad])
		get_tree().quit()
		return
	print("AERO hız=%d aoa=%.1f yunus=%.1f dikey=%.1f" % [v.airspeed() * 3.6, v.aoa_deg(), v.pitch_deg(), v.vertical_speed()])
	for m in v.modules:
		if m is WingModule and not m.upstream.is_empty():
			print("  %s z=%.1f bağlantı=%d aşağı akış=%.2f°  CL=%.2f" % [m.part.title, m.part.position.z, m.upstream.size(), rad_to_deg(m.downwash), m.last_cl])
		elif m is BodyDragModule and (m.front_open or m.rear_open):
			print("  gövde %s ön_açık=%s(%s) arka_açık=%s(%s)" % [m.part.title, m.front_open, "yuvarlak" if m.front_round else "KÜT", m.rear_open, "sivri" if m.rear_tapered else "KÜT"])
	for p in v.parts:
		var py := p.get_node_or_null("Pylon")
		if py:
			print("  PYLON %s yerel=%s ölçek=%s" % [p.title, v.to_local(py.global_position), py.scale])
	for p in v.parts:
		var f := p.get_node_or_null("RootFillet")
		if f:
			var lp: Vector3 = v.to_local(f.global_position)
			print("  FILLET %s yerel=%s ölçek=%s" % [p.title, lp, f.scale])
	get_tree().quit()
