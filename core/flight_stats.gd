class_name FlightStats
extends Node
## Uçuş kaydı: uçuş boyunca uçağın sınırlarını izler, uçuş sonu raporuna "tasarım notları" yazar —
## en yüksek G, en çok zorlanan parça, stall süresi, kompresör stall'ları, en yüksek hız / irtifa,
## yakıt tüketimi. Oyuncu "uçağım neden …" sorusunun cevabını burada görür.

var vessel: Vessel
var max_g := 1.0
var min_g := 1.0
var max_mach := 0.0
var max_kmh := 0.0
var max_alt := 0.0
var stall_time := 0.0
var buffet_time := 0.0
var cstalls := 0
var airborne_time := 0.0
var worst_part := ""
var worst_stress := 0.0
var fuel_start := -1.0
var _was_cstall := {}


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel) or not vessel.is_inside_tree() or vessel.parts.is_empty():
		return
	if fuel_start < 0.0:
		fuel_start = vessel.fuel_amount()
	var airborne := vessel.radar_altitude() > 5.0
	if not airborne:
		return
	airborne_time += delta
	max_g = maxf(max_g, vessel.g_force)
	min_g = minf(min_g, vessel.g_force)
	max_mach = maxf(max_mach, vessel.mach())
	max_kmh = maxf(max_kmh, vessel.airspeed() * 3.6)
	max_alt = maxf(max_alt, vessel.altitude())
	var stalled := false
	for m in vessel.modules:
		if m is WingModule and m.stalled and absf(m.part.basis.y.y) > 0.6:
			stalled = true
		elif m is EngineModule:
			var key: String = "cstall%d" % m.part.get_instance_id()
			var now: bool = vessel.failures.has(key)
			if now and not _was_cstall.get(key, false):
				cstalls += 1
			_was_cstall[key] = now
	if stalled:
		stall_time += delta
	if vessel.wing_buffet() > 0.3:
		buffet_time += delta
	for p in vessel.parts:
		if p.stress > worst_stress:
			worst_stress = p.stress
			worst_part = p.title


## Rapor satırları (uçuş sonu ekranı).
func report() -> PackedStringArray:
	var out := PackedStringArray()
	if airborne_time < 5.0:
		return out
	out.append("UÇUŞ KAYDI: en yüksek %+.1f G / %+.1f G · %d km/sa (M%.2f) · %d m" % [max_g, min_g, max_kmh, max_mach, max_alt])
	if is_instance_valid(vessel) and fuel_start > 0.0:
		var used := fuel_start - vessel.fuel_amount()
		out.append("Yakıt: %d kg harcandı (%%%d)" % [used, used / fuel_start * 100.0])
	if worst_part != "":
		var note := "  — dayanım sınırına çok yakın, güçlendir ya da büyüt" if worst_stress > 0.8 else ""
		out.append("En çok zorlanan parça: %s (%%%d yük)%s" % [worst_part, worst_stress * 100.0, note])
	if stall_time > 1.0:
		out.append("Kanat stall'da %.0f sn kaldı — kaldırma merkezi / kanat alanı / kalkış hızı kontrol edilmeli" % stall_time)
	if buffet_time > 3.0:
		out.append("Kanatlar %.0f sn titredi (stall öncesi ya da ses hızına yakın şok)" % buffet_time)
	if cstalls > 0:
		out.append("Kompresör stall: %d kez — yüksek hücum açısında tam güç, alık yerleşimine bak" % cstalls)
	return out
