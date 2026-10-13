class_name EnemyAirbase
extends Node3D
## Düşman havaalanı (görevde kurulur): arazinin en düz yerine 1.2 km'lik pist (üç bölüm — her
## biri ayrı hedef), üç uçak hangarı, apronda park etmiş avcılar, yakıt tankları, kule, iki
## uçaksavar, bir SAM rampası, iki omuzdan SAM ekibi ve bir erken uyarı radarı.
## Alarm (birim vurulur, üstünden alçak geçilir ya da radar seni görür): pist sağlamsa (en az iki
## bölüm) her 50 sn'de iki avcı kaldırır — park halindeki her sağlam uçak bir kalkış hakkıdır.
## Pist bombalanırsa kalkış durur.

signal scrambled(v: Vessel)

const RUNWAY_LEN := 1200.0
const RUNWAY_W := 45.0
const SCRAMBLE_EVERY := 50.0

var mission: MissionManager
var center_xz := Vector2.ZERO
var heading := 0.0                      ## pist yönü (rad, yerel çerçevede; 0 = kuzey-güney)
var runway: Array[GroundTarget] = []
var parked: Array[GroundTarget] = []
var units: Array[GroundTarget] = []
var radar: RadarStation
var alarm := false
var _scramble_t := 8.0
var launched := 0


## Bölgede pist için en düz yeri ve yönü bul: [merkez xz, yön (rad), ortalama yükseklik].
static func find_site(lo: Vector2, hi: Vector2, seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var best := [lo.lerp(hi, 0.5), 0.0, 0.0]
	var best_score := INF
	for i in 260:
		var c := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var h0 := MissionManager.ground_height(c.x, c.y)
		if h0 < 8.0:
			continue
		for k in 6:
			var a := k * PI / 6.0
			var along := Vector2(sin(a), cos(a))
			var side := Vector2(along.y, -along.x)
			var dev := 0.0
			var sum := 0.0
			for s in [-0.5, -0.25, 0.0, 0.25, 0.5]:
				for w in [-1.0, 1.0]:
					var p: Vector2 = c + along * RUNWAY_LEN * s + side * (RUNWAY_W + 60.0) * w
					var h := MissionManager.ground_height(p.x, p.y)
					sum += h
					dev = maxf(dev, absf(h - h0))
			if dev < best_score:
				best_score = dev
				best = [c, a, sum / 10.0]
		if best_score < 4.0:
			break
	return best


## Üssü kur. mm: görev yöneticisi (birimleri dünyaya o ekler).
static func build(mm: MissionManager, lo: Vector2, hi: Vector2, seed_v := 77) -> EnemyAirbase:
	var b := EnemyAirbase.new()
	b.name = "EnemyAirbase"
	b.mission = mm
	var site := find_site(lo, hi, seed_v)
	b.center_xz = site[0]
	b.heading = site[1]
	mm.main.world.add_child(b)
	b._build_units()
	return b


func _local(p: Vector2) -> Vector2:
	# yerel (doğu, güney) → pist çerçevesi: x pist yanı, y pist boyu
	var along := Vector2(sin(heading), cos(heading))
	var side := Vector2(along.y, -along.x)
	return center_xz + side * p.x + along * p.y


func _place(u: GroundTarget, local: Vector2, yaw := 0.0, sink := 0.0) -> void:
	var xz := _local(local)
	mission.main.world.add_child(u)
	var h := MissionManager.ground_height(xz.x, xz.y)
	var pos := MissionManager.world_point(xz.x, xz.y, maxf(h, 0.5) - sink)
	u.global_transform = Transform3D(Planet.local_basis(pos).rotated(Planet.up_at(pos), heading + yaw), pos)
	units.append(u)
	u.alerted_cb = _on_alert


func _build_units() -> void:
	# pist: üç bölüm (her biri bombayla ayrı ayrı kesilebilir)
	for i in 3:
		var seg := RadarStation.make_truck("Pist bölümü %d" % (i + 1), 1400.0)
		for c in seg.get_children():
			c.queue_free()
		seg._hull = GroundTarget._mesh(seg, Vector3(RUNWAY_W, 1.2, RUNWAY_LEN / 3.0 - 2.0), Vector3(0, 0.2, 0), Color(0.2, 0.21, 0.22))
		for k in 8:
			GroundTarget._mesh(seg, Vector3(0.9, 0.05, 14.0), Vector3(0, 0.82, -170.0 + k * 48.0), Color(0.9, 0.9, 0.85))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(RUNWAY_W, 1.6, RUNWAY_LEN / 3.0)
		cs.shape = box
		seg.add_child(cs)
		seg.set_meta("runway", true)
		_place(seg, Vector2(0, (i - 1) * RUNWAY_LEN / 3.0), 0.0, 0.4)
		runway.append(seg)
	# hangarlar ve park etmiş uçaklar (apron pistin doğusunda)
	for i in 3:
		var hg := RadarStation.make_truck("Uçak hangarı", 1800.0)
		for c in hg.get_children():
			c.queue_free()
		hg._hull = GroundTarget._mesh(hg, Vector3(28, 9, 30), Vector3(0, 4.5, 0), Color(0.42, 0.44, 0.38))
		var roof := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 14.0
		cyl.bottom_radius = 14.0
		cyl.height = 30.0
		roof.mesh = cyl
		roof.rotation_degrees = Vector3(90, 0, 0)
		roof.scale = Vector3(1, 1, 0.45)
		roof.position = Vector3(0, 9.0, 0)
		roof.material_override = SamSite._mat(Color(0.36, 0.4, 0.33))
		hg.add_child(roof)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(28, 14, 30)
		cs.shape = box
		cs.position = Vector3(0, 7, 0)
		hg.add_child(cs)
		_place(hg, Vector2(140.0, -360.0 + i * 70.0), PI * 0.5)
	for i in 4:
		var pl := _parked_plane()
		_place(pl, Vector2(95.0, -120.0 + i * 55.0), PI * 0.5)
		parked.append(pl)
	# yakıt tankları, kule
	for i in 2:
		var ft := RadarStation.make_truck("Yakıt tankı", 500.0)
		for c in ft.get_children():
			c.queue_free()
		var t := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 7.0
		tc.bottom_radius = 7.0
		tc.height = 8.0
		t.mesh = tc
		t.position = Vector3(0, 4, 0)
		t.material_override = SamSite._mat(Color(0.7, 0.7, 0.66))
		ft.add_child(t)
		ft._hull = t
		var cs := CollisionShape3D.new()
		var cyl_s := CylinderShape3D.new()
		cyl_s.radius = 7.0
		cyl_s.height = 8.0
		cs.shape = cyl_s
		cs.position = Vector3(0, 4, 0)
		ft.add_child(cs)
		_place(ft, Vector2(230.0, 120.0 + i * 25.0))
	var tower := RadarStation.make_truck("Kontrol kulesi", 900.0)
	for c in tower.get_children():
		c.queue_free()
	tower._hull = GroundTarget._mesh(tower, Vector3(6, 16, 6), Vector3(0, 8, 0), Color(0.6, 0.6, 0.56))
	GroundTarget._mesh(tower, Vector3(9, 3.5, 9), Vector3(0, 17.5, 0), Color(0.15, 0.2, 0.24))
	var tcs := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(9, 19, 9)
	tcs.shape = tbox
	tcs.position = Vector3(0, 9.5, 0)
	tower.add_child(tcs)
	_place(tower, Vector2(110.0, 200.0))
	# savunma: iki uçaksavar, bir SAM, iki omuzdan SAM ekibi, erken uyarı radarı
	for p in [Vector2(-160, -420), Vector2(180, 380)]:
		_place(AaaGun.create_aaa(Vector3.ZERO, 0.0), p)
	_place(SamSite.create_sam(Vector3.ZERO, 0.0), Vector2(-260, 150))
	for p in [Vector2(-90, 700), Vector2(60, -720)]:
		_place(Manpads.create_team(), p)
	radar = RadarStation.create_station("Erken uyarı radarı", 60000.0)
	_place(radar, Vector2(320.0, -40.0))
	radar.spotted.connect(func(_v: Vessel) -> void: _on_alert())
	for u in units:
		u.objective = u in runway or u in parked or u.unit_name == "Uçak hangarı"


## Apronda park etmiş avcı (yer hedefi): gövde, kanat, kuyruk, kanopi.
func _parked_plane() -> GroundTarget:
	var pl := RadarStation.make_truck("Park etmiş avcı", 260.0)
	for c in pl.get_children():
		c.queue_free()
	var paint := Color(0.4, 0.43, 0.38)
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.lathe([Vector2(-7.0, 0.0), Vector2(-5.5, 0.6), Vector2(-3.0, 0.85), Vector2(5.0, 0.85), Vector2(6.5, 0.6)], 14)
	body.material_override = SamSite._mat(paint)
	body.position = Vector3(0, 1.9, 0)
	pl.add_child(body)
	pl._hull = body
	GroundTarget._mesh(pl, Vector3(10.0, 0.25, 3.5), Vector3(0, 1.6, 0.8), paint.darkened(0.1))     # kanat
	GroundTarget._mesh(pl, Vector3(4.2, 0.2, 1.8), Vector3(0, 2.0, 5.2), paint.darkened(0.1))      # yatay kuyruk
	var fin := GroundTarget._mesh(pl, Vector3(0.2, 2.6, 2.0), Vector3(0, 3.3, 5.0), paint.darkened(0.1))
	fin.rotation_degrees = Vector3(-15, 0, 0)
	GroundTarget._mesh(pl, Vector3(0.9, 0.6, 2.0), Vector3(0, 2.75, -3.4), Color(0.12, 0.15, 0.2))  # kanopi
	for p in [Vector3(0, 0.6, -4.0), Vector3(-1.3, 0.6, 1.0), Vector3(1.3, 0.6, 1.0)]:
		GroundTarget._mesh(pl, Vector3(0.3, 1.2, 0.5), p, Color(0.1, 0.1, 0.1))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 3.5, 14)
	cs.shape = box
	cs.position = Vector3(0, 1.8, 0)
	pl.add_child(cs)
	return pl


func runway_ok() -> bool:
	var ok := 0
	for s in runway:
		if is_instance_valid(s) and not s.destroyed:
			ok += 1
	return ok >= 2


func aircraft_left() -> int:
	var n := 0
	for p in parked:
		if is_instance_valid(p) and not p.destroyed:
			n += 1
	return n - launched


func _on_alert(_a = null, _b = null) -> void:
	if not alarm:
		alarm = true
		_scramble_t = 6.0
		if is_instance_valid(mission) and is_instance_valid(mission.main.vessel):
			mission.main.vessel.system_message.emit("DÜŞMAN ÜSSÜ ALARMDA — avcılar kalkıyor!")


func _physics_process(delta: float) -> void:
	if not alarm or not is_instance_valid(mission):
		return
	_scramble_t -= delta
	if _scramble_t > 0.0:
		return
	_scramble_t = SCRAMBLE_EVERY
	if not runway_ok():
		return
	for i in 2:
		if aircraft_left() <= 0:
			return
		launched += 1
		# pist başından kalkıyor: düşük irtifa, tırmanma hızında
		var end := _local(Vector2((i - 0.5) * 20.0, RUNWAY_LEN * 0.5 + 150.0))
		var h := MissionManager.ground_height(end.x, end.y)
		var hdg := rad_to_deg(-heading) + 180.0
		var e := mission._spawn_enemy(Vector3(end.x, h + 120.0 + i * 40.0, end.y), hdg, 0.55, true, "Önleyici %d" % launched, MissionManager.SAHIN_B if launched % 2 == 0 else "")
		e.linear_velocity = e.linear_velocity.normalized() * 130.0
		scrambled.emit(e)
