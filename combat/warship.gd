class_name Warship
extends GroundTarget
## Savaş gemisi (korvet): denizde yavaşça seyreder, kıyıya yaklaşırsa döner. Arama radarı
## (30 km, RWR'da G), baş tarafta radar güdümlü SAM rampası (12 km, 6 füze, gemi radarı
## izledikçe güdülür) ve iki yakın savunma topu (CIWS, 2 km). Gemi savar füzesi ve bombayla
## batırılır (top mermisi zırhta az iş görür); batınca yan yatıp suya gömülür. Radarı radar
## avcısı füzenin hedefidir. Fırkateyn (Frigate) ve uçak gemisi (Carrier) bundan türer.
## Filo: `leader` + `slot` ile önderin yanında düzen tutar; `route` verilirse rota noktalarını
## sırayla dolaşır. Yakında düşman yokken sensörler 2 Hz'de bakar (uzaktaki gemi ucuz).

const RADAR_RANGE := 30000.0
const SAM_RANGE := 12000.0
const SPEED := 7.0
const LOCK_TIME := 4.0
const RELOAD := 10.0
const CIWS_RANGE := 2400.0

static var ships: Array[Warship] = []

var missiles := 6
var heading := 0.0                 ## yerel çerçevede (rad); 0 = kuzey (-z)
var radar_range := RADAR_RANGE
var sam_range := SAM_RANGE
var speed := SPEED
var turn_rate := 0.06              ## rad/s
var reload := RELOAD
var tag := "G"                     ## HUD / RWR simgesi
var armor := 0.15                  ## küçük isabetlerin (top mermisi) hasar çarpanı
var hull_size := Vector3(11.0, 9.0, 72.0)    ## patlama mesafesi için gövde kutusu
var hull_center := Vector3(0, 3.0, 0)
var sink_time := 20.0
var sink_depth := 10.0
var leader: Warship                ## filo önderi (yoksa kendi rotası)
var slot := Vector2.ZERO           ## önderin çerçevesinde yuva (x sancak, y kıç; metre)
var route: Array[Vector2] = []     ## rota noktaları (yüzey xz); boşsa düz seyir
var launchers: Array[Node3D] = []
var _mast: Node3D
var _launcher: Node3D
var _guns: Array[GunMount] = []
var _target: Vessel
var _lock_t := 0.0
var _cool := 3.0
var _turn_t := 0.0
var _land_t := 0.0
var _land_ahead := false
var _sink := 0.0
var _idle_t := randf() * 0.5
var _wp := 0
var _li := 0


static func create_ship(title := "Düşman korveti") -> Warship:
	var t := Warship.new()
	t.unit_name = title
	t.hp = 2600.0
	t._collision(t.hull_size, t.hull_center)
	var grey := Color(0.48, 0.5, 0.52)
	# gövde: sivri baş, düz kıç (lathe yerine kutular + baş kaması)
	t._hull = _mesh(t, Vector3(10.0, 5.0, 56.0), Vector3(0, 1.0, 6.0), grey)
	var bow := _mesh(t, Vector3(7.1, 5.0, 7.1), Vector3(0, 1.0, -22.0), grey)
	bow.rotation_degrees = Vector3(0, 45, 0)
	_mesh(t, Vector3(10.2, 0.4, 66.0), Vector3(0, -1.4, 2.0), Color(0.45, 0.12, 0.1))   # su hattı (kırmızı)
	_mesh(t, Vector3(9.6, 0.3, 54.0), Vector3(0, 3.6, 7.0), Color(0.36, 0.38, 0.4))     # güverte
	# üst yapı ve köprü
	_mesh(t, Vector3(7.5, 5.0, 16.0), Vector3(0, 6.0, 4.0), grey.lightened(0.05))
	_mesh(t, Vector3(7.8, 1.2, 3.0), Vector3(0, 8.2, -3.0), Color(0.12, 0.15, 0.18))     # köprü camı
	_mesh(t, Vector3(3.0, 3.0, 4.0), Vector3(0, 9.2, 10.0), Color(0.25, 0.26, 0.27))     # baca
	# direk ve dönen radar
	t._add_mast(Vector3(0, 8.5, 2.0), 8.0, 5.0)
	# baş SAM rampası (dikey tüpler)
	t._add_launcher(Vector3(0, 4.4, -12.0), 6)
	# yakın savunma topları (CIWS): iki yanda
	for side in [-1.0, 1.0]:
		t._add_ciws(Vector3(side * 3.2, 9.0, 12.0))
	return t


# ------------------------------------------------------------------ yapım yardımcıları

func _collision(size: Vector3, center: Vector3) -> void:
	hull_size = size
	hull_center = center
	collision_layer = LAYER
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	add_child(cs)


## Direk + dönen arama radarı. base: direk dibi, h: direk boyu, w: anten genişliği.
func _add_mast(base: Vector3, h: float, w: float) -> void:
	var grey := Color(0.48, 0.5, 0.52)
	_mesh(self, Vector3(0.8, h, 0.8), base + Vector3(0, h * 0.5, 0), grey)
	_mast = Node3D.new()
	_mast.position = base + Vector3(0, h + 0.1, 0)
	add_child(_mast)
	_mesh(_mast, Vector3(w, w * 0.28, 0.3), Vector3(0, 0.4, 0), Color(0.78, 0.79, 0.78))
	_turret = _mast


## Dikey atım hücreleri (SAM). Her hücre bir füze.
func _add_launcher(pos: Vector3, cells: int) -> void:
	var l := Node3D.new()
	l.position = pos
	add_child(l)
	var cols := 3 if cells <= 6 else 4
	for i in cells:
		_mesh(l, Vector3(0.9, 1.6, 0.9), Vector3((i % cols - (cols - 1) * 0.5) * 1.1, 0.8, (i / cols) * 1.1 - 0.5), Color(0.32, 0.34, 0.35))
	launchers.append(l)
	if _launcher == null:
		_launcher = l


## Yakın savunma topu (CIWS): beyaz kubbe, tek namlu, çok hızlı atış.
func _add_ciws(pos: Vector3) -> GunMount:
	var yaw := Node3D.new()
	yaw.position = pos
	add_child(yaw)
	_mesh(yaw, Vector3(1.6, 1.8, 1.6), Vector3(0, 0.6, 0), Color(0.86, 0.87, 0.86))
	var pitch := Node3D.new()
	pitch.position = Vector3(0, 0.9, 0)
	yaw.add_child(pitch)
	var barrel := _mesh(pitch, Vector3(0.25, 0.25, 2.4), Vector3(0, 0, -1.2), Color(0.2, 0.2, 0.2))
	barrel.name = "Barrel"
	var muzzles: Array[Vector3] = [Vector3(0, 0, -2.5)]
	var g := GunMount.new(self, yaw, pitch, muzzles)
	g.muzzle_speed = 1100.0
	g.damage = 18.0
	g.interval = 0.03
	g.max_range = 2200.0
	g.yaw_rate = deg_to_rad(120.0)
	g.pitch_rate = deg_to_rad(90.0)
	g.add_flash(0.35)
	_guns.append(g)
	return g


static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	mi.mesh = c
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = SamSite._mat(color)
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ arayüz

func _enter_tree() -> void:
	ships.append(self)


func _exit_tree() -> void:
	ships.erase(self)


func emitting() -> bool:
	return not destroyed


func emitter_position() -> Vector3:
	return _mast.global_position


func tracking() -> Vessel:
	return null if destroyed or not is_instance_valid(_target) else _target


func sees(v: Vessel) -> bool:
	return not destroyed and Detection.radar_sees(emitter_position(), radar_range, v, true)


## Zırh: top mermisi gibi küçük isabetler gövdede az iş görür.
func take_damage(amount: float) -> void:
	super.take_damage(amount * (armor if amount < 100.0 else 1.0))


## Patlama noktasının gövde kutusuna uzaklığı (Damage.explosion; uzun gövdede merkez yanıltır).
func blast_distance(p: Vector3) -> float:
	var q := (to_local(p) - hull_center).abs() - hull_size * 0.5
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()


# ------------------------------------------------------------------ davranış

func _physics_process(delta: float) -> void:
	if destroyed:
		# batış: yan yatar ve suya gömülür
		_sink = minf(_sink + delta / sink_time, 1.0)
		var up := Planet.up_at(global_position)
		global_position -= up * delta * sink_depth / sink_time * (1.5 - _sink)
		rotate_object_local(Vector3.BACK, delta * 0.8 / sink_time * (1.0 - _sink))
		if _sink >= 1.0:
			set_physics_process(false)
		return
	_alert_tick(delta)
	_mast.rotate_y(delta * 2.2)
	_steam(delta)
	_cool -= delta
	_idle_t -= delta
	if _idle_t > 0.0:
		return
	var v := nearest_enemy_vessel(radar_range * 1.3)
	var m := _incoming_missile()
	if v == null and m == null and not alerted():
		# yakında kimse yok: sensörler yarım saniyede bir (uzaktaki filo ucuz)
		_idle_t = 0.5
		_target = null
		_lock_t = 0.0
		return
	_combat(delta, v, m)


func _combat(delta: float, v: Vessel, m: Missile) -> void:
	var seen := v != null and sees(v)
	if seen:
		Detection.report(team, v)
	var dist := v.com_global().distance_to(global_position) if v else INF
	# SAM: radar izi + menzil
	if seen and dist < sam_range:
		_target = v
		_lock_t += delta * (1.0 - Chaff.near(v.com_global(), 250.0) * 0.9)
		if _lock_t > LOCK_TIME and _cool <= 0.0 and missiles > 0:
			_fire(v)
	else:
		_target = null
		_lock_t = maxf(_lock_t - delta, 0.0)
	# CIWS: yakındaki uçak ya da gelen füze
	var close: Vessel = v if dist < CIWS_RANGE and line_of_sight(v.com_global()) else null
	for g in _guns:
		if close:
			g.engage(close, delta, true)
		elif m:
			# füzeye nişan: yaklaştıkça düşürme şansı artar
			g.rest(delta, m.global_position)
			if is_instance_valid(m) and m.global_position.distance_to(global_position) < 1500.0 and randf() < delta * 0.9:
				m.shoot_down()
		else:
			g.rest(delta, threat_point())
	_weapons(delta, v, seen, dist)


## Alt sınıflar için: ek silahlar (baş topu, uçak kaldırma…). v: en yakın düşman uçağı (ya da null).
func _weapons(_delta: float, _v: Vessel, _seen: bool, _dist: float) -> void:
	pass


func _incoming_missile() -> Missile:
	for m in Missile.active:
		if is_instance_valid(m) and m.team != team and m.guidance in ["ship", "cruise", "arm"] and m.global_position.distance_to(global_position) < 3000.0:
			return m
	return null


## Seyir: önderin yanındaki yuvaya ya da rota noktasına dön; önü kara ya da sığsa yavaşça dön.
func _steam(delta: float) -> void:
	var frame := Planet.local_basis(global_position)
	var want := heading
	var spd := speed
	if is_instance_valid(leader) and not leader.destroyed:
		var lb := leader.global_basis
		var slot_p := leader.global_position + lb.x * slot.x + lb.z * slot.y
		var goal := slot_p - lb.z * 500.0          # yuvanın biraz önüne bak: yumuşak katılma
		var to := goal - global_position
		want = atan2(-to.dot(frame.x), -to.dot(frame.z))
		var ahead := (slot_p - global_position).dot(-global_basis.z)   # > 0: yuva önümüzde
		spd = clampf(leader.speed + ahead * 0.02, leader.speed * 0.5, speed * 1.6)
	elif not route.is_empty():
		var wp := MissionManager.world_point(route[_wp].x, route[_wp].y, 0.0)
		var to := wp - global_position
		to -= frame.y * to.dot(frame.y)
		if to.length() < 900.0:
			_wp = (_wp + 1) % route.size()
		want = atan2(-to.dot(frame.x), -to.dot(frame.z))
	var fwd := frame * Vector3(sin(-heading), 0, -cos(heading))
	_land_t -= delta
	if _land_t <= 0.0:
		_land_t = 1.0
		_land_ahead = TerrainGen.height(Planet.surface_dir(global_position + fwd * (600.0 + hull_size.z))) > -8.0
	_turn_t -= delta
	if _land_ahead or _turn_t > 0.0:
		if _turn_t <= 0.0:
			_turn_t = 20.0
		heading += delta * turn_rate
	else:
		heading += clampf(wrapf(want - heading, -PI, PI), -turn_rate * delta, turn_rate * delta)
	var pos := global_position + fwd * spd * delta
	var dir := (pos - Planet.center()).normalized()
	global_position = Planet.center() + dir * (Planet.RADIUS + 0.5)
	global_basis = Basis(Planet.up_at(global_position), heading) * Planet.local_basis(global_position)


func _fire(v: Vessel) -> void:
	missiles -= 1
	_cool = reload
	_lock_t = 0.0
	var up := Planet.up_at(global_position)
	var l: Node3D = launchers[_li % launchers.size()] if not launchers.is_empty() else self
	_li += 1
	var m := Missile.new()
	m.guidance = "radar"
	m.launcher = self
	m.can_go_active = false
	m.team = team
	m.velocity = up * 50.0
	m.target = v
	get_parent().add_child(m)
	m.global_position = l.global_position + up * 2.5
	m.look_at(m.global_position + up, Planet.local_basis(m.global_position).z)
	Sfx.play_at("missile_launch.ogg", m.global_position, 6.0, 0.8, 9000.0)
	v.system_message.emit("GEMİ SAM ATIŞI! — chaff (Ş), dik dön, alçal")
	if Game.args.has("navaltest"):
		print("NAVAL: %s SAM attı (kalan %d), hedef %.1f km" % [unit_name, missiles, v.com_global().distance_to(global_position) / 1000.0])


func _on_destroyed() -> void:
	missiles = 0
	var smoke := Effects.smoke_column()
	add_child(smoke)
	smoke.position = Vector3(0, hull_size.y * 0.8, hull_size.z * 0.12)
	if Game.args.has("navaltest"):
		print("NAVAL: %s BATIYOR" % unit_name)
