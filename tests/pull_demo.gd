extends Node
## Yüksek G dönüş demosu (kanat ucu izleri ve yoğuşma için ekran görüntüsü).
var main: Node
func _physics_process(_d: float) -> void:
	var v: Vessel = main.vessel
	v.ctrl_throttle = 1.0
	v.ctrl_roll = clampf((75.0 - v.roll_deg()) * 0.04, -1.0, 1.0)
	v.ctrl_pitch = 0.75 if absf(v.roll_deg() - 75.0) < 25.0 else 0.0
