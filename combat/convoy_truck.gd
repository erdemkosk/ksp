class_name ConvoyTruck
extends GroundTarget
## Yolda ilerleyen konvoy aracı (kamyon ya da zırhlı araç). Yol, başlangıç çerçevesindeki
## (doğu, güney) noktalarıdır; konum her karede araziye oturtulur (kayan orijinden etkilenmez).
## Yolun sonuna varan araç döner ve geri gider. Vurulunca durur, yanar.
## Saldırı (araç vurulur, yakına bomba düşer, alçak geçiş): konvoy dağılır. Her araç yoldan
## çıkar, hızlanır, yakındaki ormana / köye / kasabaya (yoksa yolun tehditten uzak yanına) sürer
## ve orada saklanır. Alarm geçince yola döner, kaldığı yerden devam eder.
## Refakat aracı (escort; varsayılan: zırhlılar) alarmda makineli tüfekle karşılık verir.

const DASH := 17.0              ## dağılırken hız (m/s)
const MG_RANGE := 1400.0

## Sahnedeki konvoy araçları (birbirinden kaçınma, saklanma yeri paylaşımı)
static var all: Array[ConvoyTruck] = []

var path: Array[Vector2] = []
var speed := 11.0
var offset := 0.0             ## yol boyunca mesafe (m), konvoyda araç arası aralık için
var escort := false
var state := "road"           ## road, scatter, hide, regroup
var _seg := 0
var _t := 0.0
var _dir := 1
var _wheels: Array[Node3D] = []
var _xz := Vector2.ZERO       ## yüzey konumu (başlangıç çerçevesi doğu/güney)
var _heading := 0.0           ## 0 = kuzey (-z)
var _v := 0.0                 ## anlık hız
var _dash := DASH
var _dest := Vector2.ZERO
var _drive_t := 0.0
var _leave_seg := 0
var _leave_t := 0.0
var _leave_dir := 1
var _leave_xz := Vector2.ZERO
var _tilt := Vector2.ZERO     ## (yunuslama, yatış): arazi eğimi
var _gun: GunMount
var _los := false
var _los_t := 0.0


## `armed`: makineli tüfekli refakat aracı mı (null: zırhlıysa evet).
static func create_truck(road: Array[Vector2], start_dist: float, armored: bool, armed: Variant = null) -> ConvoyTruck:
	var t := ConvoyTruck.new()
	t.path = road
	t.hp = 500.0 if armored else 260.0
	t.unit_name = "Zırhlı araç" if armored else "Kamyon"
	t.escort = armored if armed == null else bool(armed)
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.6, 7.0)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	t.add_child(cs)
	var olive := Color(0.31, 0.34, 0.24)
	var mount := Vector3(0, 2.1, -2.4)
	if armored:
		t._hull = _mesh(t, Vector3(2.6, 1.3, 6.4), Vector3(0, 1.0, 0), olive)
		mount = Vector3(0, 1.65, 0.4)
	else:
		t._hull = _mesh(t, Vector3(2.4, 1.6, 2.0), Vector3(0, 1.3, -2.4), olive)              # kabin
		_mesh(t, Vector3(2.5, 2.0, 4.4), Vector3(0, 1.6, 0.9), Color(0.36, 0.38, 0.3))           # branda
	if armored or t.escort:
		# taret: yatay döner, makineli tüfek yükselir
		var yaw := Node3D.new()
		yaw.position = mount
		t.add_child(yaw)
		_mesh(yaw, Vector3(1.4, 0.6, 1.6) if armored else Vector3(0.9, 0.35, 0.9), Vector3(0, 0.3, 0), olive.darkened(0.1))
		t._turret = yaw
		if t.escort:
			t._gun = _make_mg(t, yaw)
	for z in [-2.4, 0.2, 2.4]:
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 0.4
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(side * 1.25, 0.5, z)
			w.material_override = SamSite._mat(Color(0.08, 0.08, 0.08))
			t.add_child(w)
			t._wheels.append(w)
	t.offset = start_dist
	return t


## 12.7 mm makineli tüfek (hafif uçaksavar): hızlı döner, kısa menzil, hafif mermi.
static func _make_mg(t: ConvoyTruck, yaw: Node3D) -> GunMount:
	var pitch := Node3D.new()
	pitch.position = Vector3(0, 0.5, -0.4)
	yaw.add_child(pitch)
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.06
	cyl.height = 1.7
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(-90, 0, 0)
	barrel.position = Vector3(0, 0, -0.85)
	barrel.material_override = SamSite._mat(Color(0.1, 0.1, 0.1))
	pitch.add_child(barrel)
	var muzzles: Array[Vector3] = [Vector3(0, 0, -1.8)]
	var g := GunMount.new(t, yaw, pitch, muzzles)
	g.muzzle_speed = 880.0
	g.damage = 7.0
	g.interval = 0.08
	g.spread = deg_to_rad(0.8)
	g.max_range = MG_RANGE
	g.yaw_rate = deg_to_rad(90.0)
	g.pitch_rate = deg_to_rad(60.0)
	g.min_pitch = deg_to_rad(-8.0)
	g.max_pitch = deg_to_rad(70.0)
	g.rest_pitch = 0.0
	g.burst_len = Vector2(0.6, 1.4)
	g.pause_len = Vector2(1.0, 2.2)
	g.fire_cone = deg_to_rad(4.0)
	g.aim_error = deg_to_rad(0.6)
	g.sound_pitch = 0.95
	g.sound_db = 0.0
	g.sound_range = 2500.0
	g.add_flash(0.25)
	return g


func _ready() -> void:
	all.append(self)
	if Game.args.has("reacttest"):
		ReactTest.ensure(self)
	_v = speed
	# başlangıç: yol boyunca offset metre ileri
	var d := offset
	while _seg < path.size() - 1:
		var l := path[_seg].distance_to(path[_seg + 1])
		if d < l:
			_t = d / l
			break
		d -= l
		_seg += 1
	_place(0.0)


func _exit_tree() -> void:
	all.erase(self)


func _physics_process(delta: float) -> void:
	if destroyed or path.size() < 2:
		return
	_alert_tick(delta)
	match state:
		"road":
			_drive_road(delta)
		"scatter", "regroup":
			_drive_offroad(delta)
		"hide":
			_v = 0.0
			if not alerted():
				# tehlike geçti: yola dön
				state = "regroup"
				_drive_t = 0.0
	if _gun:
		_escort_fire(delta)
	if _v > 0.1:
		for w in _wheels:
			w.rotate_object_local(Vector3.UP, _v * delta / 0.5)


func _drive_road(delta: float) -> void:
	_v = move_toward(_v, speed, 3.0 * delta)
	var l := maxf(path[_seg].distance_to(path[_seg + 1]), 1.0)
	_t += _dir * _v * delta / l
	if _t > 1.0:
		if _seg + 2 < path.size():
			_seg += 1
			_t -= 1.0
		else:
			_t = 1.0
			_dir = -1
	elif _t < 0.0:
		if _seg > 0:
			_seg -= 1
			_t += 1.0
		else:
			_t = 0.0
			_dir = 1
	_place(delta)


func _place(_delta: float) -> void:
	var xz := path[_seg].lerp(path[_seg + 1], clampf(_t, 0.0, 1.0))
	var ahead := (path[_seg + 1] - path[_seg]) * _dir
	var h := maxf(Towns.road_height(xz.x, xz.y), 0.5)
	var pos := MissionManager.world_point(xz.x, xz.y, h)
	var frame := Planet.local_basis(pos)
	var yaw := atan2(-ahead.x, -ahead.y)   # 0 = kuzey (-z), x doğu
	_xz = xz
	_heading = yaw
	_tilt = Vector2.ZERO
	global_transform = Transform3D(frame * Basis(Vector3.UP, yaw), pos)


# ------------------------------------------------------------------ dağılma

func _on_alert(_first: bool, _hit: bool) -> void:
	if state == "road" or state == "regroup":
		_scatter()


func _on_hit(_amount: float) -> void:
	# saklandığı yerde vuruldu: başka yere kaç
	if state == "hide" and hp > 0.0 and randf() < 0.6:
		_scatter()


func _scatter() -> void:
	if state == "road":
		_leave_seg = _seg
		_leave_t = _t
		_leave_dir = _dir
		_leave_xz = _xz
	state = "scatter"
	_drive_t = 0.0
	_dash = DASH * randf_range(0.85, 1.15)
	_dest = _pick_cover()


## Saklanma noktası: yakın aday noktalardan orman/köy yoğun, tehditten uzak, düz, kuru olanı.
func _pick_cover() -> Vector2:
	var fwd := Vector2(-sin(_heading), -cos(_heading))
	var right := Vector2(-fwd.y, fwd.x)
	var away := Vector2.ZERO
	var tp: Variant = threat_point()
	if tp != null:
		away = _xz - GroundTarget.surface_xz(tp as Vector3)
		away = away.normalized() if away.length() > 1.0 else Vector2.ZERO
	var side := 1.0 if randf() < 0.5 else -1.0
	if away != Vector2.ZERO and randf() < 0.75:
		side = 1.0 if away.dot(right) >= 0.0 else -1.0
	var best := _xz + right * side * 40.0
	var best_s := -INF
	for i in 12:
		var lat := side if i < 8 else -side
		var dir := (right * lat * randf_range(0.5, 1.0) + fwd * randf_range(-0.9, 0.9)).normalized()
		var c := _xz + dir * randf_range(110.0, 420.0)
		var s := _cover_score(c, away)
		if s > best_s:
			best_s = s
			best = c
	# yakında kasaba varsa evlerin arasına sığınmak cazip
	for t: Dictionary in Towns.TOWNS:
		var tc: Vector2 = t["xz"]
		var r := float(t["r"])
		if tc.distance_to(_xz) < r + 1200.0:
			var c := tc + Vector2.from_angle(randf() * TAU) * randf() * r * 0.7
			var s := _cover_score(c, away) + 1.5
			if s > best_s:
				best_s = s
				best = c
	return best


func _cover_score(c: Vector2, away: Vector2) -> float:
	var d := Vector3(c.x, Planet.RADIUS, c.y).normalized()
	var h := TerrainGen.height(d)
	if h < 2.5:
		return -INF                       # su
	var rv := TerrainGen.river_at(c.x, c.y)
	if not rv.is_empty() and float(rv["dist"]) < float(rv["width"]) * 0.5 + 20.0:
		return -INF
	var slope := absf(MissionManager.ground_height(c.x + 8.0, c.y) - h) + absf(MissionManager.ground_height(c.x, c.y + 8.0) - h)
	if slope > 6.0:
		return -INF
	var s := TerrainGen.forest(d) * 2.0 + TerrainGen.village(d) - slope * 0.1 + randf() * 0.4
	if away != Vector2.ZERO:
		s += away.dot((c - _xz).normalized()) * 0.6
	for o in all:
		if o != self and o.state != "road" and o._dest.distance_to(c) < 45.0:
			s -= 1.5                      # başka araç orayı seçti: dağıl
	return s


func _drive_offroad(delta: float) -> void:
	_drive_t += delta
	var goal := _dest if state == "scatter" else _leave_xz
	var to := goal - _xz
	var dist := to.length()
	var want := atan2(-to.x, -to.y)
	var dy := wrapf(want - _heading, -PI, PI)
	# varış (yerinde dönemeyen araç hedefin etrafında dolanmasın: açı ve süre sınırı)
	if dist < (12.0 if state == "scatter" else 5.0) or (dist < 25.0 and absf(dy) > 1.3) or _drive_t > 90.0:
		if state == "scatter":
			state = "hide"
			_v = 0.0
		else:
			state = "road"
			_seg = _leave_seg
			_t = _leave_t
			_dir = _leave_dir
			_v = 4.0
			_place(delta)
			return
	else:
		var turn := clampf(_v / 10.0, 0.25, 1.2)
		_heading = wrapf(_heading + clampf(dy, -turn * delta, turn * delta), -PI, PI)
		var target_v := _dash if state == "scatter" else speed
		target_v = minf(target_v, sqrt(2.0 * 2.0 * dist) + 1.0)
		if absf(dy) > 0.9:
			target_v = minf(target_v, 6.0)
		_v = move_toward(_v, target_v, (3.5 if _v < target_v else 6.0) * delta)
		_xz += Vector2(-sin(_heading), -cos(_heading)) * _v * delta
		# diğer araçlara çarpma
		for o in all:
			if o != self:
				var dd := _xz - o._xz
				var l := dd.length()
				if l < 9.0 and l > 0.01:
					_xz += dd / l * minf(9.0 - l, 4.0 * delta)
	_place_ground(delta)


## Arazide: yükseklik + eğim (önde/sağda örnek), yön _heading.
func _place_ground(delta: float) -> void:
	var h := maxf(MissionManager.ground_height(_xz.x, _xz.y), 0.5)
	if _xz.distance_to(_leave_xz) < 8.0:
		h = maxf(Towns.road_height(_xz.x, _xz.y), 0.5)
	var fwd := Vector2(-sin(_heading), -cos(_heading))
	var right := Vector2(-fwd.y, fwd.x)
	var hf := MissionManager.ground_height(_xz.x + fwd.x * 3.0, _xz.y + fwd.y * 3.0)
	var hr := MissionManager.ground_height(_xz.x + right.x * 1.5, _xz.y + right.y * 1.5)
	var want := Vector2(clampf(atan2(hf - h, 3.0), -0.5, 0.5), clampf(atan2(hr - h, 1.5), -0.5, 0.5))
	_tilt = _tilt.lerp(want, 1.0 - exp(-6.0 * delta))
	var pos := MissionManager.world_point(_xz.x, _xz.y, h)
	var frame := Planet.local_basis(pos)
	global_transform = Transform3D(frame * Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, _tilt.x) * Basis(Vector3.BACK, _tilt.y), pos)


# ------------------------------------------------------------------ refakat ateşi

func _escort_fire(delta: float) -> void:
	if not alerted():
		_gun.rest(delta)
		return
	var v := nearest_enemy_vessel(MG_RANGE * 1.3)
	_los_t -= delta
	if v and _los_t <= 0.0:
		_los_t = 0.3
		_los = line_of_sight(v.com_global())
	if v == null or not _los:
		_gun.rest(delta, threat_point())
		return
	_gun.engage(v, delta, true)


## Testler için: refakat aracının attığı mermi (silahsızsa 0).
func shots() -> int:
	return _gun.shots if _gun else 0
