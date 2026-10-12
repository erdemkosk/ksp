extends Node
## Her parçayı tek başına kurup dünyaya ekle (görsel, çarpışma, modüller hata vermesin).
var main: Node
func _ready() -> void:
	await get_tree().physics_frame
	var n := 0
	for id in PartLibrary.ids():
		var v := VesselBuilder.build({"name": "t", "parts": [{"part": id, "pos": [0, 0, 0]}]})
		v.freeze = true
		main.world.add_child(v)
		v.global_position = main.vessel.global_position + Vector3(0, 200 + n * 10, 0)
		n += v.parts.size()
	await get_tree().create_timer(1.0).timeout
	print("PARÇA SAYISI: %d, kurulan: %d" % [PartLibrary.ids().size(), n])
	get_tree().quit()
