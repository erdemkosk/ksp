class_name AeroLinks
## Parçalar arası aerodinamik etkileşim (uçak kurulurken ve parça koptukça yeniden hesaplanır):
##   • Aşağı akış (downwash): kaldırma üreten bir kanat arkasındaki yüzeylere aşağı doğru akış
##     bırakır; arkadaki yüzeyin hücum açısı ε = 2·CL/(π·AR) kadar azalır (yanal örtüşme ve
##     yükseklik farkıyla zayıflar). Kuyruk ana kanadın arkasında daha az etkili, tandem kanatlar
##     bedava kaldırma alamaz.
##   • Gövde ön/arka yüzleri: önünde başka gövde olan parça rüzgardan korunur; açıkta kalan
##     küt bir burun düz levha gibi, sivri koni ise düşük dirençle karşılar. Açıkta kalan küt
##     arka uç (kuyruk konisi yok) taban direnci üretir.


static func rebuild(v: Vessel) -> void:
	var wings: Array = []
	var bodies: Array = []
	for m in v.modules:
		if m is WingModule:
			wings.append(m)
		elif m is BodyDragModule:
			bodies.append(m)
	# --- aşağı akış bağlantıları
	for w: WingModule in wings:
		w.upstream.clear()
		if not _horizontal(w.part):
			continue
		var pw := w.part.position
		var span_w := w.part.size.x * 0.5
		for u: WingModule in wings:
			if u == w or not _horizontal(u.part) or u is ControlSurfaceModule:
				continue
			var pu := u.part.position
			var ahead := pw.z - pu.z            # -Z ileri: arkadaki yüzeyin z'si büyük
			if ahead < 0.6 or ahead > 25.0:
				continue
			# yanal örtüşme: arkadaki yüzeyin açıklığı öndekinin izine ne kadar giriyor
			var span_u := u.part.size.x * 0.5
			var lo := maxf(pw.x - span_w, pu.x - span_u)
			var hi := minf(pw.x + span_w, pu.x + span_u)
			var overlap := clampf((hi - lo) / maxf(span_w * 2.0, 0.1), 0.0, 1.0)
			if overlap <= 0.05:
				continue
			# yükseklik farkı: iz kanat açıklığının yarısı kadar dikeyde etkili
			var dy := absf(pw.y - pu.y)
			var vert := clampf(1.0 - dy / maxf(span_u * 0.6, 0.5), 0.0, 1.0)
			# hemen arkadaki (kontrol yüzeyi gibi kanadın kendi parçası) tam etki almaz
			var dist := clampf((ahead - 0.6) / 2.0, 0.3, 1.0)
			var f := overlap * vert * dist
			if f > 0.03:
				w.upstream.append([u, f])
	# --- gövde ön/arka yüzleri
	for b: BodyDragModule in bodies:
		b.front_open = true
		b.rear_open = true
		var pb := b.part.position
		var rb := maxf(b.part.size.x, b.part.size.y) * 0.5
		var hb := b.part.size.z * 0.5
		if not _axial(b.part):
			continue
		for o: BodyDragModule in bodies:
			if o == b or not _axial(o.part):
				continue
			var po := o.part.position
			var ro := maxf(o.part.size.x, o.part.size.y) * 0.5
			if Vector2(po.x - pb.x, po.y - pb.y).length() > maxf(rb, ro) * 0.5:
				continue
			var gap_front := (pb.z - hb) - (po.z + o.part.size.z * 0.5)
			var gap_rear := (po.z - o.part.size.z * 0.5) - (pb.z + hb)
			# komşu yüz en az bu parçanın yarıçapının %70'ini kaplıyorsa korunur
			if ro >= rb * 0.7:
				if absf(gap_front) < 0.4:
					b.front_open = false
				if absf(gap_rear) < 0.4:
					b.rear_open = false


static func _horizontal(p: Part) -> bool:
	return absf(p.basis.y.normalized().y) > 0.6


static func _axial(p: Part) -> bool:
	return absf(p.basis.z.normalized().z) > 0.9
