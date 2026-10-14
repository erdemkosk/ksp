extends Node
## --air --transtest : her hazır uçakta kaç gövde geçiş kaportası (VesselBuilder._add_transitions)
## oluştuğunu ve hangi parçalarda olduğunu yazar.
var main: Node


func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	for f in DirAccess.get_files_at("res://crafts"):
		if not f.ends_with(".json"):
			continue
		var v := VesselBuilder.build(VesselBuilder.load_craft("res://crafts/" + f))
		var names := PackedStringArray()
		for p in v.parts:
			for c in p.get_children():
				if String(c.name).begins_with("Transition"):
					names.append(p.part_id)
		print("TRP %-16s geçiş=%d  %s" % [f.get_basename(), names.size(), ", ".join(names)])
		v.free()
	get_tree().quit()
