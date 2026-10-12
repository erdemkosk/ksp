class_name FlareModule
extends PartModule
## Karşı tedbir fişekliği: O tuşu (ya da yapay zeka) her basışta bir çift ısı tuzağı atar.

var count := 30
var _cooldown := 0.0


func setup(p: Dictionary) -> void:
	count = int(p.get("count", count))


func physics_tick(delta: float) -> void:
	_cooldown -= delta


## Bir salvo atmayı dener (0.35 sn aralık). Atıldıysa true.
func fire() -> bool:
	if count <= 0 or _cooldown > 0.0 or not vessel.has_power():
		return false
	count -= 2
	_cooldown = 0.35
	Flare.drop(vessel, 2)
	return true
