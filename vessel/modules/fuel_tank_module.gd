class_name FuelTankModule
extends PartModule

var capacity := 0.0
var fuel := 0.0


func setup(p: Dictionary) -> void:
	capacity = p.get("capacity", 0.0)
	fuel = p.get("fuel", capacity)


func extra_mass() -> float:
	return fuel
