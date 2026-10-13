class_name SamSite
extends GroundTarget
## Yerden havaya füze (SAM) rampası: dönen arama radarı + 4 tüplü fırlatıcı.
## Uçak menzile (9 km) girip arazinin üstünde görünür olunca (yerden 120 m+) radar kilitlenir,
## birkaç saniye sonra füze atar. Füzeler radar komutlu: rampa radarı izi tuttukça güdülür.
## Alçak uçuş / arazi maskesi izi koparır (füze kör kalır), füzeye dik uçuş (çentik) ve chaff
## füzenin kilidini düşürebilir. Uçağın RWR'ı aramayı, kilidi ve atışı gösterir.

## Sahnedeki etkin rampalar (RWR tarar).
static var sites: Array[SamSite] = []

const RANGE := 9000.0
const MIN_AGL := 120.0
const LOCK_TIME := 3.5
const RELOAD := 13.0

## Sistem değerleri (uzun menzilli SAM farklı kurar)
var range_m := RANGE
var min_agl := MIN_AGL
var lock_time := LOCK_TIME
var reload := RELOAD
var long_range := false
## Uzun menzilli sistem: ayrı arama ve takip radarı araçları. Arama radarı yoksa yalnız takip
## radarının kendi kısa menzilinde arar; takip radarı yoksa kilitlenemez (füze atamaz).
var search_unit: GroundTarget
var track_unit: GroundTarget

var missiles := 4
var _radar: Node3D
var _launcher: Node3D
var _lock_t := 0.0
var _cool := 4.0
var _target: Vessel
var _warned := false


static func create_sam(pos: Vector3, yaw: float) -> SamSite:
	var t := SamSite.new()
	t.hp = 450.0
	t.unit_name = "SAM rampası"
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 3.0, 8.0)
	cs.shape = box
	cs.position = Vector3(0, 1.5, 0)
	t.add_child(cs)
	var olive := Color(0.3, 0.33, 0.24)
	t._hull = _mesh(t, Vector3(3.0, 1.4, 8.0), Vector3(0, 1.0, 0), olive)
	_mesh(t, Vector3(2.8, 1.5, 2.2), Vector3(0, 2.2, -2.8), olive.darkened(0.1))      # kabin
	for side in [-1.0, 1.0]:
		for k in 4:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.55
			cyl.height = 0.5
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(side * 1.5, 0.55, -3.0 + k * 2.0)
			w.material_override = _mat(Color(0.1, 0.1, 0.1))
			t.add_child(w)
	# fırlatıcı: 4 tüp, 45° yukarı bakar, dönebilir
	t._launcher = Node3D.new()
	t._launcher.position = Vector3(0, 2.0, 1.4)
	t.add_child(t._launcher)
	for i in 4:
		var tube := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.28
		cyl.height = 5.0
		tube.mesh = cyl
		tube.position = Vector3((i % 2 - 0.5) * 0.62, 0.6 + (i / 2) * 0.62, 0)
		tube.rotation_degrees = Vector3(-45, 0, 0)
		tube.material_override = _mat(Color(0.36, 0.4, 0.3))
		t._launcher.add_child(tube)
	t._turret = t._launcher
	# radar anteni
	t._radar = Node3D.new()
	t._radar.position = Vector3(0, 3.4, -2.8)
	t.add_child(t._radar)
	var dish := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 1.0, 0.12)
	dish.mesh = bm
	dish.position = Vector3(0, 0.5, 0)
	dish.material_override = _mat(Color(0.75, 0.75, 0.7))
	t._radar.add_child(dish)
	t.position = pos
	t.rotation.y = yaw
	return t


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _enter_tree() -> void:
	sites.append(self)


func _exit_tree() -> void:
	sites.erase(self)


## Radarın kilitli izlediği uçak (yoksa null).
func tracking() -> Vessel:
	return null if destroyed or not is_instance_valid(_target) else _target


## Kilit ilerlemesi 0..1 (RWR: arama → kilit).
func lock_progress() -> float:
	return clampf(_lock_t / LOCK_TIME, 0.0, 1.0)


## Radar yayın yapıyor mu (radar avcısı füze ve RWR için).
func emitting() -> bool:
	if destroyed:
		return false
	if long_range:
		return _alive(search_unit) or _alive(track_unit)
	return true


## Yayın kaynağının konumu (radar avcısı füzenin hedefi): arama radarı, yoksa takip radarı.
func emitter_position() -> Vector3:
	if long_range:
		if _alive(track_unit) and _target:
			return track_unit.global_position + Planet.up_at(track_unit.global_position) * 3.0
		if _alive(search_unit):
			return search_unit.global_position + Planet.up_at(search_unit.global_position) * 4.0
		if _alive(track_unit):
			return track_unit.global_position + Planet.up_at(track_unit.global_position) * 3.0
	return _radar.global_position


static func _alive(u: GroundTarget) -> bool:
	return is_instance_valid(u) and not u.destroyed


## Arama menzili: uzun menzilli sistemde arama radarı ölünce takip radarının 15 km'si kalır.
func detect_range() -> float:
	if long_range and not _alive(search_unit):
		return 15000.0 if _alive(track_unit) else 0.0
	return range_m


## Radar bu uçağı görüyor mu (RCS, arazi, yer yankısı, çentik, karıştırma: Detection).
func sees(v: Vessel) -> bool:
	if destroyed or not emitting() or v.radar_altitude() < min_agl:
		return false
	return Detection.radar_sees(emitter_position(), detect_range(), v, true)


func _physics_process(delta: float) -> void:
	if destroyed:
		_target = null
		return
	_radar.rotate_y(delta * (6.0 if _target else 2.0))
	_cool -= delta
	var v := nearest_enemy_vessel(detect_range() * 1.3)
	var visible_ok := v != null and sees(v)
	if visible_ok:
		Detection.report(team, v)
	# kilit: uzun menzilli sistemde takip radarı gerekir
	if visible_ok and long_range and not _alive(track_unit):
		visible_ok = false
	if visible_ok:
		_target = v
		# chaff bulutu kilitlenmeyi geciktirir
		_lock_t += delta * (1.0 - Chaff.near(v.com_global(), 250.0) * 0.9)
		# fırlatıcı hedefe döner
		var local := to_local(v.com_global())
		_launcher.rotation.y = lerp_angle(_launcher.rotation.y, atan2(-local.x, -local.z), 1.0 - exp(-2.0 * delta))
		if not _warned:
			_warned = true
			v.system_message.emit("RADAR UYARISI: %s kilitleniyor!" % ("UZUN MENZİLLİ SAM" if long_range else "SAM"))
		if _lock_t > lock_time and _cool <= 0.0 and missiles > 0 and v.com_global().distance_to(global_position) < range_m:
			_fire(v)
	else:
		_target = null
		# uçak yoksa: gelen seyir / gemi savar füzesini önle (küçük ve alçak: kısa menzilde görür)
		var cm := _missile_threat()
		if cm and _alive_tracker():
			_m_lock += delta
			if _m_lock > lock_time * 0.6 and _cool <= 0.0 and missiles > 0:
				_m_lock = 0.0
				_fire(cm)
		else:
			_m_lock = 0.0
		_lock_t = maxf(_lock_t - delta * 2.0, 0.0)
		_warned = false


var _m_lock := 0.0


func _alive_tracker() -> bool:
	return not long_range or _alive(track_unit)


## Menzildeki (alçak uçtuğu için menzilin %30'u), görüş hattındaki düşman seyir füzesi.
func _missile_threat() -> Missile:
	var ep := emitter_position()
	var best: Missile = null
	var bd := detect_range() * 0.3
	for m in Missile.active:
		if not is_instance_valid(m) or not m.guidance in ["cruise", "ship"] or m.team == team:
			continue
		var d := m.global_position.distance_to(ep)
		if d < bd and m.radar_altitude() > 25.0 and Missile.terrain_clear(ep, m.global_position):
			bd = d
			best = m
	return best


func _fire(v: Node3D) -> void:
	missiles -= 1
	_cool = reload
	var up := Planet.up_at(global_position)
	var vp: Vector3 = v.com_global()
	var to := (vp - global_position).normalized()
	var m := Missile.new()
	m.guidance = "radar"
	m.launcher = self
	m.can_go_active = false
	m.long_range = long_range
	m.team = team
	m.velocity = (up * (0.8 if long_range else 0.7) + to * 0.3).normalized() * 45.0
	m.target = v
	get_parent().add_child(m)
	m.global_position = _launcher.global_position + up * 2.5
	m.look_at(m.global_position + m.velocity, up)
	Sfx.play_at("missile_launch.ogg", m.global_position, 6.0, 0.85, 8000.0)
	if v is Vessel:
		v.system_message.emit("SAM ATIŞI! — alçal ya da füzeye dik dön, chaff at (Ş)")


func _on_destroyed() -> void:
	missiles = 0


## Uzun menzilli SAM (S-300 tipi) bataryası: [fırlatıcı, arama radarı, takip radarı].
## 40 km, büyük füze. Görev her birimi kendi yerine koyar (_add_unit).
static func create_long_range() -> Array[GroundTarget]:
	var sam := create_sam(Vector3.ZERO, 0.0)
	sam.unit_name = "Uzun menzilli SAM"
	sam.long_range = true
	sam.range_m = 40000.0
	sam.min_agl = 60.0
	sam.lock_time = 5.0
	sam.reload = 18.0
	sam.missiles = 4
	sam.hp = 600.0
	var search := RadarStation.create_mobile("SAM arama radarı", 40000.0)
	var track := RadarStation.make_truck("SAM takip radarı", 300.0, Vector3(3.0, 3.0, 0.35))
	sam.search_unit = search
	sam.track_unit = track
	return [sam, search, track]
