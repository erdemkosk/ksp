extends Node
## Hasar görselleri demosu: parçaları farklı oranlarda hasarlandırır (ekran görüntüsü için).

var main: Node


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var v: Vessel = main.vessel
	for p in v.parts:
		var f := 0.0
		match p.part_id:
			"jet_engine": f = float(Game.args.get("engdmg", "0.7"))
			"tank_long": f = 0.5          # sızıntı + duman
			"wing_main": f = 0.35         # is
			"cockpit_mk1": f = 0.15
		if f > 0.0:
			v.damage_part(p, p.max_hp * f)
