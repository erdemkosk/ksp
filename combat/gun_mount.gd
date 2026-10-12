class_name GunMount
extends RefCounted
## Yer birimlerinin döner silah yuvası (uçaksavar, refakat aracının makineli tüfeği).
## Dönüş hızı sınırlı taret (yatay + yükseliş açısı sınırları), mermi sürüklemesini ve hedefin
## ivmesini hesaba katan öncül nişan, nişan oturunca kısa seriler (seri başına küçük nişancı
## hatası), izli mermi ve namlu alevi. Mermileri ProjectileManager uçurur.

var unit: GroundTarget
var yaw_node: Node3D                 ## gövdeye göre y ekseninde döner
var pitch_node: Node3D               ## yaw_node çocuğu; x ekseninde yükselir, namlular -z yönünde
var muzzles: Array[Vector3] = []     ## pitch_node yerelinde namlu ağızları (sırayla ateşler)
var muzzle_speed := 950.0
var damage := 22.0
var interval := 0.09
var spread := deg_to_rad(0.5)
var max_range := 2600.0
var yaw_rate := deg_to_rad(55.0)
var pitch_rate := deg_to_rad(40.0)
var min_pitch := deg_to_rad(-5.0)
var max_pitch := deg_to_rad(85.0)
var rest_pitch := deg_to_rad(10.0)
var burst_len := Vector2(1.0, 2.0)
var pause_len := Vector2(1.5, 3.0)
var fire_cone := deg_to_rad(3.0)     ## nişan hatası bundan küçükse ateş
var aim_error := deg_to_rad(0.35)    ## seri başına nişancı hatası (standart sapma)
var tracer_every := 3
var sound := "gun_stop.ogg"
var sound_pitch := 0.6
var sound_db := 2.0
var sound_range := 4000.0
var sound_every := 2
var shots := 0                       ## toplam atılan mermi (testler için)

var _burst := 0.0
var _cool := 0.0
var _shot_t := 0.0
var _bias := Vector2.ZERO
var _track: Vessel
var _prev_vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _flash: MeshInstance3D
var _flash_t := 0.0


func _init(u: GroundTarget, yaw: Node3D, pitch: Node3D, muzzle_pts: Array[Vector3]) -> void:
	unit = u
	yaw_node = yaw
	pitch_node = pitch
	muzzles = muzzle_pts


## Namlu alevi: ateş anında kısa yanan parlak top (ucuz: tek mesh, ışık yok).
func add_flash(size: float) -> void:
	_flash = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	s.radial_segments = 8
	s.rings = 4
	_flash.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.35) * 4.0
	_flash.material_override = m
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := Vector3.ZERO
	for p in muzzles:
		c += p
	_flash.position = c / maxf(muzzles.size(), 1.0)
	_flash.visible = false
	pitch_node.add_child(_flash)


## Mermi `d` metreye kaç saniyede varır (v² sürüklemesi: dv/dt = -k v²).
func flight_time(d: float) -> float:
	var k := ProjectileManager.DRAG_K
	return (exp(k * d) - 1.0) / (k * muzzle_speed)


## Öncül nişan noktası: mermi uçuş süresi kadar ileri (hız + kestirilen ivme), düşüş telafili.
func lead_point(v: Vessel, delta: float) -> Vector3:
	var vel := v.linear_velocity
	if v != _track:
		_track = v
		_acc = Vector3.ZERO
	elif delta > 0.0:
		_acc = _acc.lerp((vel - _prev_vel) / delta, 1.0 - exp(-2.0 * delta)).limit_length(90.0)
	_prev_vel = vel
	var muzzle := pitch_node.global_position
	var p0 := v.com_global()
	var tp := p0
	var t := flight_time(muzzle.distance_to(tp))
	for i in 3:
		tp = p0 + vel * t + _acc * (0.5 * t * t)
		t = flight_time(muzzle.distance_to(tp))
	return tp - Planet.gravity_at(tp) * 0.5 * t * t


## Tareti dönüş hızı sınırıyla noktaya çevir. Döner: namlu ile nokta arasındaki açı.
func slew_to(p: Vector3, delta: float) -> float:
	var parent := yaw_node.get_parent() as Node3D
	var local := parent.to_local(p) - yaw_node.transform * pitch_node.position
	var want_yaw := atan2(-local.x, -local.z)
	var want_pitch := clampf(atan2(local.y, Vector2(local.x, local.z).length()), min_pitch, max_pitch)
	var dy := wrapf(want_yaw - yaw_node.rotation.y, -PI, PI)
	yaw_node.rotation.y += clampf(dy, -yaw_rate * delta, yaw_rate * delta)
	pitch_node.rotation.x = move_toward(pitch_node.rotation.x, want_pitch, pitch_rate * delta)
	return (-pitch_node.global_basis.z).angle_to(p - pitch_node.global_position)


## Ateşi kes; varsa tehdit yönüne bak, yoksa namluyu dinlenme açısına indir.
func rest(delta: float, look: Variant = null, pitch := INF) -> void:
	_burst = 0.0
	_tick(delta)
	if look != null:
		slew_to(look as Vector3, delta)
	pitch_node.rotation.x = move_toward(pitch_node.rotation.x, rest_pitch if pitch == INF else pitch, pitch_rate * delta * 0.5)


## Hedefi izle; `may_fire` ve nişan uygunsa seri at. Döner: bu karede ateş ediyor mu.
func engage(v: Vessel, delta: float, may_fire: bool) -> bool:
	_tick(delta)
	var tp := lead_point(v, delta)
	var from := pitch_node.global_position
	var d := from.distance_to(tp)
	var up := Planet.up_at(tp)
	var side := (tp - from).cross(up).normalized()
	tp += (side * _bias.x + up * _bias.y) * d
	var err := slew_to(tp, delta)
	var in_env := d < max_range and flight_time(d) < ProjectileManager.LIFETIME * 0.9
	if not may_fire or not in_env or err > fire_cone * (2.0 if _burst > 0.0 else 1.0):
		_burst = 0.0
		return false
	if _burst <= 0.0 and _cool <= 0.0:
		_burst = randf_range(burst_len.x, burst_len.y)
		_cool = _burst + randf_range(pause_len.x, pause_len.y)
		_bias = Vector2(randfn(0.0, 1.0), randfn(0.0, 1.0)) * aim_error
		_shot_t = 0.0
	if _burst <= 0.0:
		return false
	_burst -= delta
	_shot_t -= delta
	while _shot_t <= 0.0:
		_shot_t += interval
		_shoot()
	return true


func firing() -> bool:
	return _burst > 0.0


func _tick(delta: float) -> void:
	_cool -= delta
	if _flash:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0


func _shoot() -> void:
	if ProjectileManager.instance == null or muzzles.is_empty():
		return
	shots += 1
	var b := pitch_node.global_basis.orthonormalized()
	var dir := (-b.z).rotated(b.x, randfn(0.0, spread)).rotated(b.y, randfn(0.0, spread))
	var p := pitch_node.global_transform * muzzles[shots % muzzles.size()]
	ProjectileManager.instance.spawn(p, dir * muzzle_speed, damage, shots % tracer_every == 0, unit)
	if _flash:
		_flash_t = 0.04
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * randf_range(0.7, 1.2)
	if shots % sound_every == 0:
		Sfx.play_at(sound, p, sound_db, sound_pitch * randf_range(0.92, 1.08), sound_range)
