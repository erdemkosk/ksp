class_name PassengerModule
extends PartModule
## Yolcu kabini: `seats` koltuk. Görevler yolcu bindirir (kişi başı 80 kg).
## Yolcular sert manevradan rahatsız olur: konfor görevi (yolcu turu) bunu ölçer.

const PERSON_MASS := 80.0

var seats := 6
var passengers := 0


func setup(p: Dictionary) -> void:
	seats = int(p.get("seats", seats))


func extra_mass() -> float:
	return passengers * PERSON_MASS
