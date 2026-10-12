class_name IntakeModule
extends PartModule
## Hava alığı: motorların ihtiyaç duyduğu havayı sağlar. Uçaktaki toplam alık alanı,
## çalışan motorların toplam ihtiyacından azsa itki oranla düşer (Vessel.intake_ratio).
## Yüksek hücum/yan kayma açısında ve suya batınca alık verimi düşer.

var area := 0.5


func setup(p: Dictionary) -> void:
	area = p.get("area", area)


## Bu alığın şu anki etkin alanı (m²).
func effective_area() -> float:
	var v := vessel.air_velocity_at(part.global_position)
	var eff := 1.0
	if v.length() > 20.0:
		# alık ağzı ileri bakar: akış açısı büyüdükçe verim düşer (35°'de ~%55)
		var ang := (-part.global_basis.z).angle_to(v)   # v: parçanın havaya göre hızı (ileri)
		eff = clampf(1.0 - maxf(ang - deg_to_rad(12.0), 0.0) * 1.15, 0.25, 1.0)
	return area * eff * (1.0 - part.submerged)
