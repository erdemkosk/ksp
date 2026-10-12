class_name Helicopter
extends GroundTarget
## Helikopter (kinematik uçuş: hedefe hızlanır, yavaşlar, burnu hıza göre eğilir).
## Görevler:
##   "attack"  — düşman saldırı helikopteri: bir noktanın çevresinde alçak devriye, yakına
##               gelen uçağa (1.8 km) döner ve topla ateş eder.
##   "rescue"  — kurtarma: hedefe (paraşütle inen pilot) uçar, yanına iner, pilot binince kalkar.
## Kaçınma (saldırı helikopteri): vurulunca, yakınındaki birim vurulunca ya da üstüne füze /
## bomba gelince birkaç saniye kaçar: ağaç boyuna alçalır, tehditle arasına tepe koyan (arazi
## maskesi) bir noktaya, yana yalpalayarak hızla gider, ısı fişeği atar; sonra saldırıya döner.
## Her durumda arazi izlenir (önündeki tepeye çarpmaz).
## Vurulunca dönerek düşer ve yere çarpınca patlar.

signal landed_near_target
signal departed

var mode := "attack"
var max_speed := 65.0
var cruise_agl := 120.0
var home_xz := Vector2.ZERO          ## devriye merkezi (başlangıç çerçevesi doğu/güney)
var rescue_target: Node3D
var state := "fly"                   ## fly, descend, landed, takeoff, leave, falling, wreck
var velocity := Vector3.ZERO

var _rotor: Node3D
var _tail_rotor: Node3D
var _gun: Node3D
var _yaw := 0.0
var _tilt := Vector2.ZERO
var _patrol_a := 0.0
var _gun_cd := 2.0
var _burst := 0.0
var _shot_t := 0.0
var _landed_t := 0.0
var _audio: AudioStreamPlayer3D
var _spin := 0.0
var _evade_t := 0.0                  ## kalan kaçınma süresi
var _evade_xz := Vector2.ZERO        ## kaçış noktası (yüzey koordinatı)
var _jink_t := 0.0
var _jink := 1.0
var _flares := 16
var _flare_cd := 0.0
var _missile_t := 0.0

const EVADE_AGL := 22.0


static func create_heli(kind: String) -> Helicopter:
	var t := Helicopter.new()
	t.mode = kind
	t.hp = 350.0
	t.unit_name = "Saldırı helikopteri" if kind == "attack" else "Kurtarma helikopteri"
	t.team = "düşman" if kind == "attack" else "oyuncu"
	t.objective = kind == "attack"
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.6, 11.0)
	cs.shape = box
	cs.position = Vector3(0, 1.6, 1.5)
	t.add_child(cs)
	var body_col := Color(0.25, 0.3, 0.2) if kind == "attack" else Color(0.95, 0.45, 0.1)
	var trim := Color(0.18, 0.2, 0.16) if kind == "attack" else Color(0.95, 0.95, 0.93)
	# gövde: önden arkaya damla
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.lathe([Vector2(-3.0, 0.0), Vector2(-2.6, 0.75), Vector2(-1.6, 1.15), Vector2(0.6, 1.2),
		Vector2(2.0, 0.9), Vector2(3.0, 0.45)], 20, 1.05)
	body.position = Vector3(0, 1.5, 0)
	body.material_override = SamSite._mat(body_col)
	t.add_child(body)
	t._hull = body
	# cam burun
	var glass := MeshInstance3D.new()
	glass.mesh = MeshFactory.lathe([Vector2(-3.05, 0.0), Vector2(-2.7, 0.6), Vector2(-1.9, 0.95), Vector2(-1.2, 0.98)], 16, 1.0, 20.0, 160.0)
	glass.position = Vector3(0, 1.6, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.15, 0.22, 0.28)
	gm.metallic = 0.6
	gm.roughness = 0.1
	glass.material_override = gm
	t.add_child(glass)
	# kuyruk
	var boom := MeshInstance3D.new()
	boom.mesh = MeshFactory.lathe([Vector2(0.0, 0.42), Vector2(6.5, 0.18)], 10)
	boom.position = Vector3(0, 1.9, 2.6)
	boom.material_override = SamSite._mat(body_col)
	t.add_child(boom)
	_mesh(t, Vector3(0.12, 1.5, 1.0), Vector3(0, 2.6, 8.7), trim)                 # dikey kuyruk
	_mesh(t, Vector3(1.8, 0.08, 0.6), Vector3(0, 2.0, 8.0), trim)                 # yatay kuyruk
	# kızaklar
	for side in [-1.0, 1.0]:
		_mesh(t, Vector3(0.12, 0.12, 4.2), Vector3(side * 1.1, 0.06, -0.3), Color(0.12, 0.12, 0.12))
		for z in [-1.4, 0.8]:
			_mesh(t, Vector3(0.08, 0.6, 0.08), Vector3(side * 1.0, 0.4, z), Color(0.12, 0.12, 0.12))
	# ana rotor
	t._rotor = Node3D.new()
	t._rotor.position = Vector3(0, 3.0, -0.2)
	t.add_child(t._rotor)
	_mesh(t._rotor, Vector3(0.4, 0.5, 0.4), Vector3(0, -0.2, 0), Color(0.15, 0.15, 0.15))
	for i in 4:
		var blade := Node3D.new()
		blade.rotation.y = i * PI * 0.5
		t._rotor.add_child(blade)
		_mesh(blade, Vector3(0.38, 0.05, 6.2), Vector3(0, 0, -3.2), Color(0.12, 0.12, 0.12))
	# kuyruk rotoru
	t._tail_rotor = Node3D.new()
	t._tail_rotor.position = Vector3(0.25, 2.7, 9.0)
	t.add_child(t._tail_rotor)
	for i in 2:
		var b := Node3D.new()
		b.rotation.x = i * PI * 0.5
		t._tail_rotor.add_child(b)
		_mesh(b, Vector3(0.04, 1.6, 0.18), Vector3.ZERO, Color(0.12, 0.12, 0.12))
	if kind == "attack":
		t._gun = Node3D.new()
		t._gun.position = Vector3(0, 0.55, -2.4)
		t.add_child(t._gun)
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.07
		cyl.height = 1.4
		barrel.mesh = cyl
		barrel.rotation_degrees = Vector3(-90, 0, 0)
		barrel.position = Vector3(0, 0, -0.7)
		barrel.material_override = SamSite._mat(Color(0.1, 0.1, 0.1))
		t._gun.add_child(barrel)
		for side in [-1.0, 1.0]:
			_mesh(t, Vector3(1.4, 0.1, 0.5), Vector3(side * 1.4, 1.3, -0.3), body_col)       # kanatçık
			var pod := MeshInstance3D.new()
			pod.mesh = MeshFactory.lathe([Vector2(-0.9, 0.0), Vector2(-0.7, 0.22), Vector2(0.8, 0.22)], 10)
			pod.position = Vector3(side * 1.9, 1.1, -0.3)
			pod.material_override = SamSite._mat(Color(0.2, 0.22, 0.18))
			t.add_child(pod)
	else:
		var lbl := Label3D.new()
		lbl.text = "KURTARMA"
		lbl.font_size = 64
		lbl.pixel_size = 0.006
		lbl.modulate = Color(0.1, 0.1, 0.1)
		lbl.outline_size = 0
		lbl.position = Vector3(1.24, 1.6, 0.6)
		lbl.rotation_degrees = Vector3(0, 90, 0)
		t.add_child(lbl)
	return t


func _ready() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = Sfx.looped("prop_loop.ogg")
	_audio.pitch_scale = 0.45
	_audio.unit_size = 40.0
	_audio.max_distance = 5000.0
	_audio.volume_db = 4.0
	_audio.bus = Sfx.world_bus()
	_audio.autoplay = true
	add_child(_audio)
	_yaw = 0.0
	if Game.args.has("reacttest"):
		ReactTest.ensure(self)


func _physics_process(delta: float) -> void:
	var up := Planet.up_at(global_position)
	_rotor.rotate_y(delta * (0.0 if state == "wreck" else (8.0 if state == "landed" else 22.0)))
	_tail_rotor.rotate_x(delta * (0.0 if state == "wreck" else 60.0))
	if state == "wreck":
		return
	if state == "falling":
		_fall(delta, up)
		return
	var goal := _goal()
	var target: Vector3 = goal[0]
	var face: Variant = goal[1]
	var to := target - global_position
	var to_h := to - up * to.dot(up)
	var dist := to_h.length()
	var evading := _evade_t > 0.0
	var top := max_speed * (1.25 if evading else 1.0)
	var want_h := to_h.normalized() * minf(top, sqrt(2.0 * 4.0 * dist)) if dist > 1.0 else Vector3.ZERO
	var want_v := clampf(to.dot(up) * 0.6, -7.0 if state != "descend" else -4.5, 8.0)
	# arazi izleme: önümüzdeki 4 sn'lik yolun en yüksek noktasının üstünde kal
	var gh := _ground(global_position)
	var agl := Planet.altitude(global_position) - gh
	if state == "fly" or state == "leave":
		var floor_h := gh
		for k in [1.5, 4.0]:
			floor_h = maxf(floor_h, _ground(global_position + velocity * k))
		var margin := 12.0 if evading else 25.0
		var below := floor_h + margin - Planet.altitude(global_position)
		if below > 0.0:
			want_v = maxf(want_v, minf(below * 0.8, 12.0))
	var want := want_h + up * want_v
	var accel := (want - velocity).limit_length(9.0 if evading else 6.0)
	velocity += accel * delta
	# araziye çarpma
	if state != "descend" and state != "landed" and agl < 15.0 and velocity.dot(up) < 0.0:
		velocity -= up * velocity.dot(up)
	if state == "landed":
		velocity = Vector3.ZERO
	global_position += velocity * delta
	if agl < 0.2 and state == "descend":
		global_position += up * (0.2 - agl)
	# duruş: yön hıza (ya da hedefe) bakar, burun ivmeyle eğilir
	var frame := Planet.local_basis(global_position)
	var hv := frame.inverse() * (velocity - up * velocity.dot(up))
	if face != null:
		var fl := frame.inverse() * ((face as Vector3) - global_position)
		_yaw = lerp_angle(_yaw, atan2(-fl.x, -fl.z), 1.0 - exp(-1.5 * delta))
	elif Vector2(hv.x, hv.z).length() > 4.0:
		_yaw = lerp_angle(_yaw, atan2(-hv.x, -hv.z), 1.0 - exp(-1.2 * delta))
	var la := Basis(Vector3.UP, -_yaw) * (frame.inverse() * accel)
	_tilt = _tilt.lerp(Vector2(clampf(la.z * 0.06, -0.3, 0.3), clampf(-la.x * 0.06, -0.3, 0.3)), 1.0 - exp(-3.0 * delta))
	global_basis = frame * Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _tilt.x) * Basis(Vector3.BACK, _tilt.y)
	_audio.pitch_scale = 0.45 if state != "landed" else 0.3
	if mode == "attack":
		_alert_tick(delta)
		_evade_logic(delta)
		_attack(delta)
	else:
		_rescue_logic(delta, agl)


## Hedef nokta ve (varsa) bakılacak nokta.
func _goal() -> Array:
	if mode == "rescue":
		if not is_instance_valid(rescue_target):
			return [global_position + Planet.up_at(global_position) * 50.0, null]
		var tp := rescue_target.global_position
		var up := Planet.up_at(tp)
		match state:
			"fly":
				# hedefin 30 m yanında, 60 m yukarıda
				var side := (global_position - tp)
				side = (side - up * side.dot(up)).normalized() * 30.0
				return [tp + side + up * 60.0, null]
			"descend":
				var side := (global_position - tp)
				side = (side - up * side.dot(up)).normalized() * 30.0
				var p := tp + side
				return [p + up * (_ground(p) - Planet.altitude(p)), tp]
			"landed":
				return [global_position, tp]
			"takeoff", "leave":
				var home := MissionManager.world_point(home_xz.x, home_xz.y, 400.0)
				return [home if state == "leave" else global_position + up * 80.0, null]
	# kaçınma: maske noktasına alçaktan, yana yalpalayarak
	if _evade_t > 0.0:
		var p := MissionManager.world_point(_evade_xz.x, _evade_xz.y, 0.0)
		var up := Planet.up_at(p)
		var to := p - global_position
		to -= up * to.dot(up)
		if to.length() > 150.0:
			p += to.normalized().cross(up) * 120.0 * _jink
		return [p + up * (_ground(p) + EVADE_AGL - Planet.altitude(p)), null]
	# saldırı: devriye halkası ya da hedef uçak
	var v := nearest_enemy_vessel(2200.0)
	if v and v.radar_altitude() < 1500.0:
		var vp := v.com_global()
		var up := Planet.up_at(vp)
		var stand := global_position - vp
		stand = (stand - up * stand.dot(up)).normalized() * 900.0
		var p := vp + stand
		return [p + up * (_ground(p) + cruise_agl - Planet.altitude(p)), vp]
	_patrol_a += 0.0025
	var c := home_xz + Vector2(cos(_patrol_a), sin(_patrol_a)) * 1500.0
	return [MissionManager.world_point(c.x, c.y, MissionManager.ground_height(c.x, c.y) + cruise_agl), null]


func _ground(p: Vector3) -> float:
	return maxf(TerrainGen.height(Planet.surface_dir(p)), 0.0)


func _attack(delta: float) -> void:
	_gun_cd -= delta
	var v := nearest_enemy_vessel(1800.0)
	if v == null:
		return
	var to := v.com_global() - _gun.global_position
	var fwd := -global_basis.z
	if fwd.angle_to(to) > deg_to_rad(25.0) or not line_of_sight(v.com_global()):
		return
	_gun.look_at(v.com_global() + v.linear_velocity * (to.length() / 900.0), Planet.up_at(global_position))
	if _burst <= 0.0 and _gun_cd <= 0.0:
		_burst = 1.2
		_gun_cd = 3.5
	if _burst > 0.0:
		_burst -= delta
		_shot_t -= delta
		while _shot_t <= 0.0:
			_shot_t += 0.1
			if ProjectileManager.instance:
				var dir := (-_gun.global_basis.z).rotated(global_basis.y, randf_range(-0.012, 0.012))
				ProjectileManager.instance.spawn(_gun.global_position - _gun.global_basis.z * 1.5, velocity + dir * 900.0, 14.0, randi() % 3 == 0, self)
				Sfx.play_at("gun_stop.ogg", _gun.global_position, 0.0, 0.9, 2500.0)


## Kaçınma zamanlayıcıları + üstüne gelen füze kontrolü (0.3 sn'de bir).
func _evade_logic(delta: float) -> void:
	_evade_t -= delta
	_flare_cd -= delta
	_jink_t -= delta
	if _jink_t <= 0.0:
		_jink_t = randf_range(2.0, 3.5)
		_jink = -_jink
	_missile_t -= delta
	if _missile_t > 0.0:
		return
	_missile_t = 0.3
	for m in Missile.active:
		if not is_instance_valid(m) or not is_instance_valid(m.shooter) or m.shooter.team == team:
			continue
		var to := global_position - m.global_position
		if to.length() < 2500.0 and m.velocity.dot(to) > 0.0:
			if _evade_t < 2.0:
				_start_evade(m.global_position)
			if _flare_cd <= 0.0:
				_drop_flares()
			return


func _on_hit(_amount: float) -> void:
	if mode == "attack" and state == "fly":
		_start_evade(_guess_threat())
		if _flare_cd <= 0.0:
			_drop_flares()


func _on_alert(_first: bool, hit: bool) -> void:
	# yalnız biri vurulunca kaç (alçak geçişte saldırıya devam)
	if hit and _evade_t <= 0.0:
		var tp: Variant = threat_point()
		if tp != null:
			_start_evade(tp as Vector3)


func _start_evade(threat: Vector3) -> void:
	if mode != "attack" or state != "fly" or destroyed:
		return
	_evade_t = randf_range(7.0, 11.0)
	_evade_xz = _pick_mask_point(threat)


## Tehdide görünmeyen (arada tepe olan) yakın nokta; yoksa tehdit hattına dik bir nokta.
func _pick_mask_point(threat: Vector3) -> Vector2:
	var here := GroundTarget.surface_xz(global_position)
	var away := here - GroundTarget.surface_xz(threat)
	away = away.normalized() if away.length() > 1.0 else Vector2.from_angle(randf() * TAU)
	var perp := Vector2(-away.y, away.x) * (1.0 if randf() < 0.5 else -1.0)
	var best := here + (perp * 0.8 + away * 0.6).normalized() * 600.0
	var best_s := -INF
	var a0 := randf() * TAU
	for i in 8:
		var dir := Vector2.from_angle(a0 + i * TAU / 8.0)
		var c := here + dir * randf_range(450.0, 800.0)
		var h := MissionManager.ground_height(c.x, c.y)
		var p := MissionManager.world_point(c.x, c.y, h + EVADE_AGL)
		var s := absf(dir.dot(perp)) + dir.dot(away) * 0.5 + randf() * 0.3
		if not Missile.terrain_clear(threat, p):
			s += 2.0                      # arazi maskesi
		if s > best_s:
			best_s = s
			best = c
	return best


func _drop_flares() -> void:
	if _flares <= 0:
		return
	_flare_cd = 1.2
	var up := Planet.up_at(global_position)
	for i in 2:
		_flares -= 1
		var f := Flare.new()
		var side := global_basis.x * (1.0 if i % 2 == 0 else -1.0)
		f.linear_velocity = velocity + side * randf_range(10.0, 18.0) - up * 6.0
		get_parent().add_child(f)
		f.global_position = global_position + up * 1.2 + side * 1.5
	Sfx.play_at("switch_4.ogg", global_position, 2.0, 0.55, 1500.0)


## Testler için: kaçıyor mu / kalan fişek.
func evading() -> bool:
	return _evade_t > 0.0


func flares_left() -> int:
	return _flares


func _rescue_logic(delta: float, agl: float) -> void:
	if not is_instance_valid(rescue_target):
		return
	var tp := rescue_target.global_position
	var up := Planet.up_at(tp)
	var d := global_position - tp
	var hd := (d - up * d.dot(up)).length()
	match state:
		"fly":
			if hd < 60.0 and velocity.length() < 12.0:
				state = "descend"
		"descend":
			if agl < 0.6:
				state = "landed"
				_landed_t = 0.0
				landed_near_target.emit()
		"landed":
			_landed_t += delta
		"takeoff":
			if agl > 60.0:
				state = "leave"
				departed.emit()


## Pilot bindi: kalk ve üsse dön.
func lift_off() -> void:
	state = "takeoff"


func _on_destroyed() -> void:
	state = "falling"
	collision_layer = 0
	_spin = randf_range(2.0, 4.0) * (1.0 if randf() < 0.5 else -1.0)
	var smoke := PuffTrail.create(self, Vector3(0, 2.5, 1.0), "smoke")
	smoke.rate = 25.0


func _fall(delta: float, up: Vector3) -> void:
	velocity += Planet.gravity_at(global_position) * delta
	velocity *= exp(-0.2 * delta)
	global_position += velocity * delta
	rotate(up, _spin * delta)
	var agl := Planet.altitude(global_position) - _ground(global_position)
	if agl < 0.5:
		state = "wreck"
		global_position += up * (0.5 - agl)
		Effects.explosion(FloatingOrigin.world_root, global_position + up * 2.0, up, 3.0)
		Sfx.explosion(global_position, 2.5)
		_audio.stop()
		var smoke := Effects.smoke_column()
		add_child(smoke)
		smoke.position = Vector3(0, 2, 0)
		global_basis = Planet.local_basis(global_position) * Basis(Vector3.UP, _yaw) * Basis(Vector3.BACK, 0.4)
