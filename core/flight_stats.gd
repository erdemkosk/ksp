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
# pilot yorumları için
var player: PlayerController      ## main yazar (bayılma, G yükü)
var blackouts := 0
var gray_time := 0.0              ## G perdesi (gri bölge) süresi
var gear_overspeed := false
var start_parts := -1
var max_aoa := 0.0
var _was_out := false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vessel) or not vessel.is_inside_tree() or vessel.parts.is_empty():
		return
	if fuel_start < 0.0:
		fuel_start = vessel.fuel_amount()
	if start_parts < 0:
		start_parts = vessel.parts.size()
	var airborne := vessel.radar_altitude() > 5.0
	if not airborne:
		return
	airborne_time += delta
	max_aoa = maxf(max_aoa, vessel.aoa_deg() if vessel.airspeed() > 40.0 else 0.0)
	if is_instance_valid(player):
		if player.blackout and not _was_out:
			blackouts += 1
		_was_out = player.blackout
		if player.g_strain > 0.3:
			gray_time += delta
	for k: String in vessel.failures:
		if k.begins_with("gear"):
			gear_overspeed = true
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


## Pilotun ağzından 1–3 yorum ("PİLOT|ad|söz"): uçuş verisinden, en dikkat çekenler önce.
## Rapor ekranı bunları alıntı kartı olarak çizer. Aynı durum için birkaç farklı söyleyiş var.
func pilot_notes(pilot_name: String, kills := 0) -> PackedStringArray:
	var out := PackedStringArray()
	if airborne_time < 8.0 or pilot_name == "":
		return out
	var cands: Array = []   # [öncelik, söz]
	var lost := start_parts - (vessel.parts.size() if is_instance_valid(vessel) else 0)
	if blackouts > 0:
		cands.append([10, _pick(["Gözüm karardı, kendime geldiğimde yer gökyüzündeydi. O çubuk bu kadar sert olmamalı.",
			"%d kez bayıldım. Uçak benden çok G çekiyor — sınırlayıcı ister." % blackouts])])
	elif gray_time > 6.0:
		cands.append([6, _pick(["Dönüşlerde hep gri perde vardı. Bu uçak pilotu yoruyor.",
			"G yükü hep sınırdaydı; uzun bir it dalaşında dayanamam."])])
	if lost > 0:
		cands.append([9, _pick(["%d parça eksik döndük. Yapıyı güçlendirmezseniz bir dahaki sefere dönemeyiz." % lost,
			"Havada parça koptu, sesini duydum. Bu uçağa yeniden binmem için onu sağlamlaştırın."])])
	elif worst_stress > 0.9:
		cands.append([7, _pick(["%s her sert dönüşte inledi. Bir gün gidecek." % worst_part,
			"Gıcırtılar yüzünden tam gaz açamadım — %s dayanmıyor." % worst_part])])
	if gear_overspeed:
		cands.append([7, _pick(["Takımı hızlı açtım, kapaklar titredi. Takım hız sınırı uyarısını daha belirgin yapın.",
			"İnişte takım rüzgâra dayanamadı, hızı düşürmeden açmamak lazımmış."])])
	if stall_time > 3.0:
		cands.append([6, _pick(["Yavaşta kanat birden bırakıyor, hiç uyarı vermiyor.",
			"Stall'a girince toparlamak zor. Kanat alanı ya da kuyruk büyümeli."])])
	if cstalls > 0:
		cands.append([5, _pick(["Motor yüksek açıda iki kez öksürdü. Alıkları kontrol edin.",
			"Kompresör patladı — sert manevrada tam gaz verince alık havasız kalıyor."])])
	if buffet_time > 8.0:
		cands.append([4, "Kanatlar sürekli titriyordu; ses hızına yakın uçmak rahat değil."])
	if is_instance_valid(vessel) and fuel_start > 0.0 and vessel.fuel_amount() < fuel_start * 0.08:
		cands.append([8, _pick(["Yakıt ışığı yanarken indim. Biraz daha uzak bir hedef olsaydı göle inerdik.",
			"Menzil yetmiyor, tank ekleyin."])])
	if kills >= 2:
		cands.append([5, _pick(["%d düşman! Bu uçakla dalaşa girmekten korkmuyorum artık." % kills,
			"Bu uçak avcı ruhlu — %d düşürdük ve hâlâ cephanem vardı." % kills])])
	elif kills == 1:
		cands.append([3, "Bir tane düşürdük. Nişan kolay, uçak sözümü dinliyor."])
	if max_mach > 1.05:
		cands.append([2, "Ses duvarını geçtik, kokpitte bir an her şey sustu. Harika bir his."])
	if cands.is_empty():
		cands.append([1, _pick(["Sorunsuz bir uçuştu. Bu uçağa güveniyorum.",
			"Uçak dengeli, eller serbest düz gidiyor. Böyle devam.",
			"Kumandalar yumuşak, uçak ne istersem yapıyor."])])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in mini(cands.size(), 3):
		out.append("PİLOT|%s|%s" % [pilot_name, cands[i][1]])
	return out


func _pick(options: Array) -> String:
	return options[randi() % options.size()]


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
