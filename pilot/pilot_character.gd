class_name PilotCharacter
extends CharacterBody3D
## Uçak dışındaki pilot (EVA). WASD yürü, Shift koş, Ctrl yavaş yürü, Space zıpla; fare: bakış.
## Hareket yönü kameranın yatay açısına göredir. Küre gezegende "yukarı" yereldir.
## Fırlatma koltuğuyla atılırsa (eject) önce serbest düşer, 1.3 sn sonra paraşüt açılır;
## Kumandalı (ram-air) paraşüt: A/D döner (kanat yatar), W hızlanır, S frenler — yere yakın S
## basılı: yumuşak iniş (flare). Yere ~12 m/s üstünde çarpan pilot ölür.

signal landed(impact_speed: float)
## Yürürken yüksekten düşüp öldü (paraşütle inişte `landed` yeterli)
signal died(impact_speed: float)

const FATAL_IMPACT := 12.0    ## m/s: bundan sert yere çarpan pilot ölür (ragdoll)

const WALK := 2.9
const RUN := 6.8
const SNEAK := 1.3
const JUMP := 4.4
const ACCEL := 4.5         ## hız / sn oranı (hıza göre ölçeklenir)
const DECEL := 7.0
const TURN_RATE := 9.0     ## rad/s

var pilot_name := "Pilot"
var model: PilotModel
## Kamera yatay açısı (yerel çerçevede, FlightCamera yazar)
var cam_yaw := 0.0
var enabled := true

var _phase := 0.0
var _facing := 0.0
var airborne := false        ## fırlatıldı, henüz yere değmedi
var chute_open := false
var _air_t := 0.0
var _chute_open_k := 0.0
var _amount := 0.0
var _run := 0.0
var _turn_lean := 0.0
var _squash := 0.0
var _breath := 0.0
var _was_floor := true
var _off_floor := 0.0
var ragdoll: PilotRagdoll         ## öldüyse cansız beden (karakter onu izler)
var impact_velocity := Vector3.ZERO


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	cs.shape = capsule
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	model = PilotModel.new()
	model.pilot_name = pilot_name
	add_child(model)
	global_basis = Planet.local_basis(global_position)


func face(yaw: float) -> void:
	_facing = yaw
	cam_yaw = yaw


func _physics_process(delta: float) -> void:
	if ragdoll != null:
		# ölü: karakter (kamera ve arazi çarpışma odağı) bedeni izler
		if is_instance_valid(ragdoll):
			global_position = ragdoll.center()
		return
	var frame := Planet.local_basis(global_position)
	global_basis = frame   # gövde her zaman yerel dik
	up_direction = frame.y
	var up := frame.y
	if airborne:
		_fly_ejected(delta, frame)
		return

	var input := Input.get_vector("yaw_left", "yaw_right", "pitch_down", "pitch_up") if enabled else Vector2.ZERO
	var dir := frame * (Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0.0, input.y))
	var running := Input.is_action_pressed("throttle_up") and input.length() > 0.1
	var slow := Input.is_action_pressed("throttle_down")
	var speed := RUN if running else (SNEAK if slow else WALK)
	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	var on_floor := is_on_floor()
	# yerde hızlanma / durma ayrı: bırakınca çabuk durur, havada az kontrol
	var rate := (ACCEL if input.length() > 0.1 else DECEL) if on_floor else 1.5
	horizontal = horizontal.move_toward(dir * speed, rate * speed * delta)
	var alt := Planet.altitude(global_position)
	var in_water := alt < 0.2 and TerrainGen.height(Planet.surface_dir(global_position)) < 0.0
	if in_water:
		# yüzme: su yüzeyinde kal, yavaş ilerle
		horizontal = horizontal.limit_length(1.6)
		vertical = vertical.lerp(up * clampf(-alt * 2.0 - 0.3, -1.0, 2.5), 1.0 - exp(-4.0 * delta))
	elif on_floor:
		vertical = up * maxf(vertical.dot(up), 0.0)
		if enabled and Input.is_action_just_pressed("jump"):
			vertical = up * JUMP
			_squash = -0.4
	else:
		vertical += Planet.gravity_at(global_position) * delta
	var fall_speed := -vertical.dot(up)
	velocity = horizontal + vertical
	var pre := velocity
	move_and_slide()
	# yüksekten düşüş (uçağın üstünden, uçurumdan): ölümcül
	if (is_on_floor() or get_slide_collision_count() > 0) and _off_floor > 0.25 and fall_speed > FATAL_IMPACT:
		die(pre)
		died.emit(fall_speed)
		return
	# iniş: dizler esner (düşüş hızıyla orantılı)
	if is_on_floor() and _off_floor > 0.25 and fall_speed > 2.0:
		_squash = clampf(fall_speed / 8.0, 0.2, 1.0)
		Sfx.play_at("step_grass_%d.ogg" % (randi() % 5), global_position, 0.0, 0.8, 60.0)
	_was_floor = is_on_floor()
	_off_floor = 0.0 if is_on_floor() else _off_floor + delta
	_squash = move_toward(_squash, 0.0, delta * 3.0)

	# yön: hareket yönüne yumuşak dön; dönüş hızından yana yatma
	var local_h := frame.inverse() * horizontal
	var hs := Vector2(local_h.x, local_h.z).length()
	var prev_facing := _facing
	if hs > 0.4:
		var want := atan2(-local_h.x, -local_h.z)
		_facing = rotate_toward(_facing, want, TURN_RATE * delta)
	var turn := wrapf(_facing - prev_facing, -PI, PI) / maxf(delta, 0.001)
	_turn_lean = lerpf(_turn_lean, clampf(-turn * hs * 0.035, -0.25, 0.25), 1.0 - exp(-8.0 * delta))
	model.rotation.y = _facing
	# animasyon: adım fazı hızla, koşu oranı yumuşak geçişli
	_amount = lerpf(_amount, clampf(hs / WALK, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	_run = lerpf(_run, clampf((hs - WALK) / (RUN - WALK), 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	_breath += delta * lerpf(1.6, 4.0, _run)
	var prev_step := int(_phase / PI)
	_phase += hs * delta * lerpf(2.4, 1.75, _run)
	if int(_phase / PI) != prev_step and _off_floor < 0.15 and hs > 0.5:
		var on_pavement := TerrainGen.in_airfield(Planet.surface_dir(global_position), -150.0)
		Sfx.play_at("step_%s_%d.ogg" % ["concrete" if on_pavement else "grass", randi() % 5], global_position, -8.0 + hs * 1.2, randf_range(0.9, 1.1), 60.0)
	model.pose_walk(_phase, _amount, _off_floor > 0.15 and not in_water, _run, _turn_lean, _squash, sin(_breath))




# ------------------------------------------------------------------ fırlatma koltuğu ve paraşüt
#   0.00 sn  koltuk roketi ateşlenir (alev + duman), pilot koltukta oturur
#   1.30 sn  koltuk ayrılır ve düşer, paraşüt torbası açılır: önce ipler uzar (0.5 sn),
#            sonra kubbe şişer (0.7 sn). Kubbe her an hava akışının tersine bakar.

const CHUTE_CDA := 32.0          ## m² (≈ 7 m/s alçalma)
const SEAT_TIME := 1.3

var _seat: Node3D
var _flame: MeshInstance3D
var _smoke: PuffTrail
var _rig: Node3D                 ## kubbe + ipler (hava akışına göre döner)
var _dome: Node3D
var _lines: Array[MeshInstance3D] = []
var _hang := Basis()             ## görsel eğim (yerel çerçeveye göre)
var _extend := 0.0
var _inflate := 0.0
var _brake := 0.0                ## 0..1 iki fren ipi birden (S)
var _turn := 0.0                 ## -1..1 dönüş (A/D: tek fren ipi)
var _flare := 1.0                ## süzülürken biriken, frende kaldırmaya dönen hız payı
var _body := Basis()             ## pilotun görsel duruşu (kanadın arkasından sarkaç gibi gelir)
var _hand_l := Vector3.ZERO      ## fren ipi tutamakları (model uzayında)
var _hand_r := Vector3.ZERO
var _brake_lines: Array[MeshInstance3D] = []
var _brake_tops: Array[Vector3] = []   ## fren iplerinin kanattaki ucu (rig uzayında)


## Fırlatma: koltuk roketi pilotu uçağın tavan yönünde fırlatır. seat_basis: uçağın duruşu.
func eject(vel: Vector3, seat_basis := Basis()) -> void:
	airborne = true
	chute_open = false
	_air_t = 0.0
	velocity = vel
	var frame := Planet.local_basis(global_position)
	_hang = frame.inverse() * seat_basis.orthonormalized()
	# yön: koltuğun (uçağın) baktığı yön; duruş eğimi bu yönle birleşik tutulur
	var f := _hang * Vector3.FORWARD
	_facing = atan2(-f.x, -f.z)
	_body = _hang
	_brake = 0.0
	_turn = 0.0
	_flare = 1.0
	_build_seat()
	_smoke = PuffTrail.create(self, Vector3(0, -0.2, 0.3), "missile")
	model.pose_seated(Vector3(0, 0.42, 0), 12.0, Vector3(-0.12, 0.62, -0.22), Vector3(0.12, 0.62, -0.22),
		Vector3(-0.16, 0.08, -0.55), Vector3(0.16, 0.08, -0.55))


func _fly_ejected(delta: float, frame: Basis) -> void:
	_air_t += delta
	var up := frame.y
	var g := Planet.gravity_at(global_position)
	var rho := Atmosphere.density(Planet.altitude(global_position))
	var v := velocity
	var speed := v.length()
	if _flame:
		_flame.visible = _air_t < 0.35
		_flame.scale = Vector3(1, 1, 1) * randf_range(0.8, 1.2)
	if _smoke and _air_t > 0.5:
		_smoke.emitting = false
	if not chute_open and _air_t > SEAT_TIME:
		chute_open = true
		_drop_seat(frame)
		_build_chute()
		Sfx.play_at("canopy_motor.ogg", global_position, 0.0, 0.7, 400.0)
	var acc := g
	var input := Input.get_vector("yaw_left", "yaw_right", "pitch_down", "pitch_up") if enabled else Vector2.ZERO
	var flying := chute_open and _inflate > 0.9
	if chute_open:
		_extend = move_toward(_extend, 1.0, delta / 0.5)
		if _extend >= 1.0:
			_inflate = move_toward(_inflate, 1.0, delta / 0.7)
		_chute_open_k = 0.05 + 0.95 * smoothstep(0.0, 1.0, _inflate)
	if flying:
		# kumandalı (ram-air) paraşüt: A/D fren iplerinden birini çeker → döner ve yatar; W hızlanır
		# (daha hızlı alçalır); S iki ipi birden çeker → frenler. Süzülürken biriken hız, frenle bir
		# an kaldırmaya çevrilir (yere yakın S: yumuşak iniş — flare).
		var speed_in := maxf(-input.y, 0.0)
		_brake = move_toward(_brake, maxf(input.y, 0.0), delta * 3.0)
		_turn = move_toward(_turn, input.x, delta * 2.2)
		_facing -= _turn * 0.9 * delta
		_flare = clampf(_flare + delta * (0.35 if _brake < 0.3 else -1.4 * _brake), 0.0, 1.0)
		var glide := 7.5 + 4.0 * speed_in - 5.5 * _brake
		var sink := 5.0 + 2.0 * speed_in + 1.6 * absf(_turn) - 3.8 * _brake * _flare + 1.5 * _brake * (1.0 - _flare)
		var fwd := frame * (Basis(Vector3.UP, _facing) * Vector3.FORWARD)
		var want := fwd * glide - up * maxf(sink, 1.2)
		velocity = v.lerp(want, 1.0 - exp(-1.4 * delta))
	else:
		if chute_open:
			acc -= v * speed * 0.5 * rho * CHUTE_CDA * _chute_open_k / 95.0
		else:
			acc -= v * speed * 0.5 * rho * 0.7 / 95.0
		velocity = v + acc * delta
	if velocity.length() > 400.0:
		velocity = velocity.limit_length(400.0)
	var impact := -velocity.dot(up)
	impact_velocity = velocity
	move_and_slide()
	var alt := Planet.altitude(global_position)
	var in_water := alt < 0.3 and TerrainGen.height(Planet.surface_dir(global_position)) < 0.0
	if _air_t > 0.6 and (is_on_floor() or in_water or get_slide_collision_count() > 0):
		_land(in_water, impact)
		return
	# görsel duruş: koltuktayken uçağın açısından yavaşça dikleşir; paraşütteyken kubbe hava
	# akışının tersine bakar, pilot iplerin ucunda sallanır
	var target := Basis()
	if flying:
		# kanat dönüşe yatar; pilot iplerin ucunda biraz geriden gelir (sarkaç), frende ayaklar öne
		target = Basis(Vector3.UP, _facing) * Basis(Vector3.BACK, -_turn * 0.45)
	elif chute_open and velocity.length() > 0.5:
		var axis := frame.inverse() * (-velocity.normalized())
		if axis.dot(Vector3.UP) < -0.2:
			axis = (axis + Vector3.UP * 1.5).normalized()
		target = Basis(Quaternion(Vector3.UP, axis.normalized())) * Basis(Vector3.UP, _facing)
	else:
		target = Basis(Vector3.UP, _facing)
	_hang = _hang.slerp(target, 1.0 - exp(-(3.0 if chute_open else 1.2) * delta)).orthonormalized()
	var local_v := frame.inverse() * velocity
	if chute_open and not flying and Vector2(local_v.x, local_v.z).length() > 1.0:
		_facing = lerp_angle(_facing, atan2(-local_v.x, -local_v.z), 1.0 - exp(-1.5 * delta))
	var body_target := _hang
	if flying:
		var sway := sin(_air_t * 1.7) * 0.04
		# frende kanat yavaşlar, pilot ileri savrulur: gövde arkaya yaslanır, ayaklar öne (+X dönüşü)
		body_target = Basis(Vector3.UP, _facing) * Basis(Vector3.BACK, -_turn * 0.3 + sway) * Basis(Vector3.RIGHT, _brake * 0.22)
	_body = _body.slerp(body_target, 1.0 - exp(-(2.0 if chute_open else 6.0) * delta)).orthonormalized()
	model.basis = _body
	if _seat:
		_seat.basis = model.basis
	if _rig:
		_rig.basis = _hang
		var ext := maxf(_extend, 0.08)
		_rig.scale = Vector3(lerpf(0.12, 1.0, _inflate), ext, lerpf(0.12, 1.0, _inflate))
		# kanat şişerken hafif nefes alır
		var breath := 1.0 + 0.02 * sin(_air_t * 3.1) * _inflate
		_dome.scale = Vector3(breath, 1.0 + 0.04 * (1.0 - _inflate), breath)
	if chute_open:
		# koşum takımında oturur gibi asılı: kalçalar yüksek, bacaklar hafif öne uzanmış ve
		# sallanıyor; eller fren ipi tutamaklarında (dönüşte bir el, frende ikisi aşağı)
		var swing := sin(_air_t * 2.3) * 0.05
		var pull_l := clampf(_brake + maxf(-_turn, 0.0), 0.0, 1.0)
		var pull_r := clampf(_brake + maxf(_turn, 0.0), 0.0, 1.0)
		_hand_l = Vector3(-0.3, 1.98 - pull_l * 0.5, 0.02)
		_hand_r = Vector3(0.3, 1.98 - pull_r * 0.5, 0.02)
		# bacak 0.84 m: kalçadan ~0.82 m'de ayak → dizler hafif bükük (gerilip kilitlenmez)
		model.pose_seated(Vector3(0, 0.95, 0.04), 4.0, _hand_l, _hand_r,
			Vector3(-0.15, 0.2 + _brake * 0.06, -0.28 + swing - _brake * 0.06),
			Vector3(0.15, 0.2 + _brake * 0.06, -0.28 - swing - _brake * 0.06))
		_update_brake_lines()


func _land(in_water: bool, impact: float) -> void:
	airborne = false
	if not in_water and impact > FATAL_IMPACT:
		# ölümcül çarpma: koltuk / paraşüt bırakılır, beden ragdoll olur (main raporlar)
		if _seat:
			_drop_seat(Planet.local_basis(global_position))
		if _rig:
			_rig.queue_free()
			_rig = null
		if _smoke:
			_smoke.emitting = false
		die(impact_velocity)
		landed.emit(impact)
		return
	_squash = clampf(impact / 8.0, 0.3, 1.0)
	if _rig:
		# kubbe söner, yere yığılır, sonra kaybolur
		var rig := _rig
		_rig = null
		var tw := rig.create_tween()
		tw.tween_property(rig, "scale", Vector3(1.3, 0.05, 1.3), 1.2)
		tw.tween_callback(rig.queue_free)
	if _seat:
		_seat.queue_free()
		_seat = null
	model.basis = Basis(Vector3.UP, _facing)
	model.pose_standing()
	velocity = Vector3.ZERO
	landed.emit(0.0 if in_water else impact)


## Pilot öldü: model parçaları eklemli rijit gövdelere geçer, karakter çarpışmasız izleyici olur.
## vel: çarpmadan hemen önceki hız (bedenin bir kısmı yere geçer, kalanı yuvarlanma).
func die(vel: Vector3) -> void:
	if ragdoll != null:
		return
	enabled = false
	airborne = false
	collision_layer = 0
	collision_mask = 0
	var up := Planet.up_at(global_position)
	var along := vel - up * vel.dot(up)
	var spin := up.cross(along).normalized() * clampf(along.length() * 0.35, 1.0, 8.0) if along.length() > 0.5 \
		else Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	ragdoll = PilotRagdoll.spawn(model, along * 0.7 + up * clampf(-vel.dot(up) * 0.15, 0.0, 3.0), spin)
	Sfx.play_at("hydraulic_thunk.ogg", global_position, 2.0, 0.6, 120.0)


func _build_seat() -> void:
	_seat = Node3D.new()
	add_child(_seat)
	var dark := Color(0.12, 0.13, 0.12)
	var yel := Color(0.9, 0.75, 0.15)
	_box(_seat, Vector3(0.52, 0.12, 0.55), Vector3(0, 0.36, -0.08), dark)            # oturak
	_box(_seat, Vector3(0.55, 0.95, 0.14), Vector3(0, 0.82, 0.22), dark)             # sırt
	_box(_seat, Vector3(0.4, 0.22, 0.18), Vector3(0, 1.38, 0.24), dark)              # başlık
	_box(_seat, Vector3(0.08, 0.5, 0.06), Vector3(0, 1.08, 0.08), yel)               # çekme kolu
	_box(_seat, Vector3(0.14, 0.3, 0.14), Vector3(0, 0.15, 0.2), Color(0.3, 0.3, 0.32)) # roket
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 1.4
	_flame.mesh = cone
	_flame.position = Vector3(0, -0.7, 0.2)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.7, 0.3) * 4.0
	_flame.material_override = fm
	_seat.add_child(_flame)


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Koltuk pilottan ayrılıp kendi başına düşer (enkaz olarak).
func _drop_seat(_frame: Basis) -> void:
	if _seat == null:
		return
	var deb := Debris.new()
	deb.mass = 70.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.55, 1.2, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.7, 0)
	deb.add_child(cs)
	var root: Node = FloatingOrigin.world_root if FloatingOrigin.world_root else get_parent()
	root.add_child(deb)
	deb.global_transform = _seat.global_transform
	_seat.reparent(deb)
	deb.linear_velocity = velocity - Planet.up_at(global_position) * 3.0
	deb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	deb.add_collision_exception_with(self)
	_seat = null


## Kumandalı (ram-air) paraşüt: kavisli dikdörtgen kanat — 9 hücre (kırmızı / beyaz / lacivert),
## uçlarda yan plakalar; taşıyıcı ipler kanadın altından omuz askılarına, fren ipleri arka
## köşelerden pilotun ellerine iner (eller çektikçe ipler de iner). Kanat +Y yukarıda, -Z ileri.
const CANOPY_TOP := 7.4
const CANOPY_R := 6.2            ## kanat kavisinin yarıçapı (yandan bakınca hafif yay)
const CELL_CHORD := 2.7
const RISER_L := Vector3(-0.24, 2.15, 0.0)
const RISER_R := Vector3(0.24, 2.15, 0.0)


func _build_chute() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	_dome = Node3D.new()
	_rig.add_child(_dome)
	var cols := [Color(0.85, 0.14, 0.1), Color(0.95, 0.95, 0.93), Color(0.12, 0.2, 0.45)]
	var mats: Array[StandardMaterial3D] = []
	for c in cols:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats.append(m)
	var cells := 9
	var half := deg_to_rad(38.0)
	var cell_w := 2.0 * CANOPY_R * sin(half) / cells * 1.08
	var under: Array[Vector3] = []     # hücre altlarının ön / arka noktaları (ip bağlantıları)
	for i in cells:
		var a := lerpf(-half, half, (i + 0.5) / cells)
		var center := Vector3(CANOPY_R * sin(a), CANOPY_TOP - CANOPY_R * (1.0 - cos(a)), 0.0)
		var cell := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(cell_w, 0.38, CELL_CHORD)
		cell.mesh = bm
		cell.material_override = mats[[0, 1, 2, 1][i % 4]]
		cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# kavis boyunca yatık; hücum kenarı hafif aşağı (kanat profili gibi)
		cell.basis = Basis(Vector3.BACK, -a) * Basis(Vector3.RIGHT, deg_to_rad(-6.0))
		cell.position = center
		_dome.add_child(cell)
		# hücre ağızları: ön yüzde koyu açıklık (hava girişi)
		var mouth := MeshInstance3D.new()
		var mb := BoxMesh.new()
		mb.size = Vector3(cell_w * 0.8, 0.22, 0.02)
		mouth.mesh = mb
		mouth.material_override = VesselBuilder.material("dark")
		mouth.position = Vector3(0, -0.04, -CELL_CHORD * 0.5 - 0.005)
		cell.add_child(mouth)
		var down := cell.basis * Vector3(0, -0.19, 0)
		under.append(center + down + cell.basis * Vector3(0, 0, -CELL_CHORD * 0.35))
		under.append(center + down + cell.basis * Vector3(0, 0, CELL_CHORD * 0.25))
	# yan plakalar (stabilizatörler)
	for s in [-1.0, 1.0]:
		var a: float = half * s
		var plate := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.02, 0.9, CELL_CHORD * 0.9)
		plate.mesh = pb
		plate.material_override = mats[2]
		plate.basis = Basis(Vector3.BACK, -a)
		plate.position = Vector3(CANOPY_R * sin(a), CANOPY_TOP - CANOPY_R * (1.0 - cos(a)) - 0.45, 0.0)
		_dome.add_child(plate)
	# taşıyıcı ipler: her ikinci hücrenin altından ön / arka → kendi tarafındaki omuz askısına
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.85, 0.85, 0.8)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines.clear()
	for k in under.size():
		if (k / 2) % 2 == 1:
			continue
		var top: Vector3 = under[k]
		var riser: Vector3 = RISER_R if top.x >= 0.0 else RISER_L
		_lines.append(_line(lm, top, riser))
	# omuzdan koşuma kısa askılar
	for r in [RISER_L, RISER_R]:
		_lines.append(_line(lm, r, Vector3(r.x * 0.8, 1.55, 0.0)))
	# fren ipleri: kanadın iki arka uç köşesinden ellere (her karede güncellenir)
	_brake_lines.clear()
	_brake_tops.clear()
	_brake_tops.append(under[1])                   # sol kanat ucu arka köşe
	_brake_tops.append(under[under.size() - 1])    # sağ kanat ucu arka köşe
	var bmat := lm.duplicate() as StandardMaterial3D
	bmat.albedo_color = Color(0.95, 0.85, 0.2)
	for i in 2:
		_brake_lines.append(_line(bmat, _brake_tops[i], _brake_tops[i] + Vector3.DOWN))


func _line(mat: Material, a: Vector3, b: Vector3) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	cyl.radial_segments = 3
	line.mesh = cyl
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(line)
	_set_line(line, a, b)
	return line


func _set_line(line: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := maxf(d.length(), 0.01)
	line.position = (a + b) * 0.5
	line.basis = _basis_y(d / l) * Basis.from_scale(Vector3(1.0, l, 1.0))   # ipin kendi ekseninde uzat


## Fren iplerini ellere bağla (eller pose'ta model uzayında; ipler rig uzayında).
func _update_brake_lines() -> void:
	if _rig == null or _brake_lines.size() < 2:
		return
	var to_rig := _rig.transform.affine_inverse() * model.transform
	var hands := [_hand_l, _hand_r]
	for i in 2:
		_set_line(_brake_lines[i], _brake_tops[i], to_rig * (hands[i] as Vector3))


static func _basis_y(dir: Vector3) -> Basis:
	var x := dir.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = dir.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, dir, x.cross(dir).normalized())
