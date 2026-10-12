class_name Missile
extends Node3D
## Güdümlü füze. Kendi basit fiziğiyle uçar: roket motoru, yerçekimi, sürükleme.
## Güdüm: oransal güdüm (proportional navigation) — görüş hattının dönme hızıyla orantılı
## yanal ivme. Yakınlık tapası hedefe yaklaşınca patlatır (alan hasarı).
##
## guidance = "ir": arayıcı başlık koni içindeki en güçlü ısı kaynağını izler; hedef koniden
##   çıkarsa kilit kopar, fişek kandırabilir.
## guidance = "radar": fırlatan (uçak radarı ya da SAM) hedefi izlediği sürece yarı aktif güdüm.
##   İz koparsa son bilinen konuma doğru uçar. ACTIVE_RANGE içinde kendi radarını açar ve
##   bağımsızlaşır (SAM füzesi hep fırlatana bağlıdır). Arazi maskesi, çentik (füzeye dik uçuş:
##   Doppler hızı ~0, yer yankısına karışır) ve chaff kilidi koparabilir.

const IR := {"burn": 2.6, "thrust": 260.0, "max_g": 35.0, "cone": 30.0, "fuse": 9.0, "blast_r": 15.0,
	"blast_dmg": 420.0, "life": 22.0, "drag": 0.0009}
const RADAR := {"burn": 5.0, "thrust": 175.0, "max_g": 30.0, "cone": 45.0, "fuse": 12.0, "blast_r": 18.0,
	"blast_dmg": 380.0, "life": 50.0, "drag": 0.0006}
const NAV_GAIN := 4.0
const ACTIVE_RANGE := 7000.0
const NOTCH_SPEED := 35.0           ## m/s: hedefin görüş hattındaki hızı bundan küçükse çentikte
const SEEKER_CONE := deg_to_rad(30.0)   ## IR arayıcı (MissileModule ve yapay zeka da kullanır)

var velocity := Vector3.ZERO
var target: Node3D           ## Vessel ya da Flare (ikisi de heat_position/heat_signature/linear_velocity sunar)
var victim: Vessel           ## fırlatıldığında kilitli olunan uçak (füze uyarısı için)
var guidance := "ir"
var launcher: Node           ## radar: hedefi aydınlatan (Vessel ya da SamSite)
var can_go_active := true    ## radar: son evrede kendi radarını açabilir mi
var seeker_active := false   ## radar: kendi radarı açık (fırlatandan bağımsız)

## Uçuştaki füzeler (füze yaklaşma uyarısı, RWR ve yapay zeka kaçınması için).
static var active: Array[Missile] = []
var shooter: Vessel

var _p: Dictionary = IR
var _age := 0.0
var _prev_los := Vector3.ZERO
var _decoy_timer := 0.0
var _scan_timer := 0.0
var _track_timer := 0.0
var _last_pos := Vector3.ZERO     ## radar: hedefin son bilinen konumu / hızı (iz koparsa tahmin)
var _last_vel := Vector3.ZERO
var _has_last := false
var _trail: PuffTrail
var _motor: AudioStreamPlayer3D
var _flame: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var radar := guidance == "radar"
	_p = RADAR if radar else IR
	var r := 0.09 if radar else 0.07
	var length := 3.6 if radar else 2.8
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.lathe([Vector2(-length * 0.5, 0.0), Vector2(-length * 0.5 + 0.12, r * 0.6),
		Vector2(-length * 0.5 + 0.38, r), Vector2(length * 0.5, r)], 16)
	body.material_override = VesselBuilder.material("paint", Color(0.85, 0.86, 0.84))
	add_child(body)
	for roll in [45.0, 135.0]:
		var fin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 7.0, 0.01, 0.3)
		fin.mesh = bm
		fin.position = Vector3(0, 0, length * 0.5 - 0.2)
		fin.rotation_degrees = Vector3(0, 0, roll)
		fin.material_override = body.material_override
		add_child(fin)
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = r * 1.3
	cone.bottom_radius = 0.0
	cone.height = 1.6
	_flame.mesh = cone
	_flame.rotation_degrees = Vector3(-90, 0, 0)
	_flame.position = Vector3(0, 0, length * 0.5 + 0.8)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.7, 0.3) * 3.0
	_flame.material_override = fm
	add_child(_flame)
	_trail = PuffTrail.create(self, Vector3(0, 0, length * 0.5 + 0.1), "missile")
	_motor = AudioStreamPlayer3D.new()
	_motor.stream = Sfx.looped("missile_motor.ogg")
	_motor.unit_size = 20.0
	_motor.max_distance = 4000.0
	_motor.bus = Sfx.world_bus()
	_motor.autoplay = true
	add_child(_motor)
	FloatingOrigin.shifted.connect(_on_shift)
	active.append(self)
	if target is Vessel:
		victim = target
		_remember(target)


func _exit_tree() -> void:
	active.erase(self)


func is_radar() -> bool:
	return guidance == "radar"


## Arayıcı konisindeki fişekler: hedeften daha parlak görünen bir fişek arayıcıyı kandırabilir.
## Her 0.15 sn'de bir şans; fişek ne kadar sıcak ve hedefe göre ne kadar yakınsa şans o kadar yüksek.
func _check_decoys(pos: Vector3, fwd: Vector3) -> void:
	if not target is Vessel:
		return
	var t_heat: float = target.heat_signature() / maxf(pos.distance_squared_to(target.heat_position()), 1.0)
	for f in Flare.active:
		var to := f.global_position - pos
		if fwd.angle_to(to) > SEEKER_CONE:
			continue
		var f_heat := f.heat / maxf(to.length_squared(), 1.0)
		var ratio := f_heat / maxf(t_heat, 1e-9)
		if ratio > 0.6 and randf() < clampf(0.12 + 0.1 * ratio, 0.0, 0.55):
			target = f
			return


## Kilitsiz atılan ya da kilidi kopan füze: önündeki koniyi tarar, en sıcak düşmana kilitlenir.
func _acquire(pos: Vector3, fwd: Vector3) -> void:
	var best_score := 0.0
	for node in get_parent().get_children():
		if node is Vessel and node != shooter and not node.parts.is_empty() and (shooter == null or not is_instance_valid(shooter) or node.team != shooter.team):
			var to: Vector3 = node.heat_position() - pos
			var d := to.length()
			if d > MissileModule.SEEK_RANGE or fwd.angle_to(to) > SEEKER_CONE:
				continue
			var score: float = node.heat_signature() / (d * d) * 1e6
			if score > best_score and score > 0.02:
				best_score = score
				target = node
	if target is Vessel and victim == null:
		victim = target
		_prev_los = Vector3.ZERO


func _on_shift(s: Vector3) -> void:
	_prev_los = Vector3.ZERO
	_last_pos -= s


# ------------------------------------------------------------------ radar güdümü

func _remember(t: Node3D) -> void:
	_last_pos = t.com_global()
	_last_vel = t.linear_velocity
	_has_last = true


## Fırlatan hâlâ hedefi izliyor mu (yarı aktif evre).
func _launcher_tracks() -> bool:
	if not is_instance_valid(launcher) or not is_instance_valid(target):
		return false
	if launcher is SamSite:
		return not launcher.destroyed and launcher.tracking() == target
	if launcher is Vessel:
		var r: RadarModule = launcher.radar()
		return r != null and launcher.has_power() and not launcher.parts.is_empty() and target in r.contacts
	return false


## Hedefin Doppler hızı yer yankısına karışıyor mu (çentik). Alçakta ve yüksekte farklı:
## hedef yerin üstündeyken (arkasında arazi) daha kolay saklanır.
static func in_notch(seeker_pos: Vector3, t: Vessel) -> bool:
	var los := (t.com_global() - seeker_pos).normalized()
	var radial := absf(t.linear_velocity.dot(los))
	var looking_down := los.dot(Planet.up_at(seeker_pos)) < 0.05
	return t.linear_velocity.length() > 60.0 and radial < NOTCH_SPEED and (looking_down or t.radar_altitude() < 3000.0)


## İki nokta arasında arazi var mı (ucuz örnekleme; çarpışma yalnız odak çevresinde var).
static func terrain_clear(a: Vector3, b: Vector3) -> bool:
	for i in range(1, 16):
		var p := a.lerp(b, i / 16.0)
		if Planet.altitude(p) < TerrainGen.height(Planet.surface_dir(p)) + 5.0:
			return false
	return true


## Radar iz kontrolü (0.15 sn'de bir): kilidi düşüren her şey burada.
func _radar_track(pos: Vector3, fwd: Vector3) -> void:
	if not is_instance_valid(target):
		target = null
	# yarı aktif evrede fırlatan izi yeniden yakalarsa veri bağı geri gelir
	if target == null and not seeker_active and is_instance_valid(victim):
		target = victim
		if not _launcher_tracks():
			target = null
	if target is Vessel:
		var t: Vessel = target
		var keep := t.is_inside_tree() and not t.parts.is_empty()
		if keep and not seeker_active:
			keep = _launcher_tracks()      # veri bağı: fırlatanın radarı izliyorsa koni gerekmez
			# takip radarı da chaff'a kayabilir (yarı aktif evre)
			if keep and randf() < Chaff.near(t.com_global()) * 0.08:
				keep = false
		elif keep:
			keep = fwd.angle_to(t.com_global() - pos) < deg_to_rad(_p["cone"]) and terrain_clear(pos, t.com_global())
			if keep and in_notch(pos, t) and randf() < 0.22:
				keep = false
			# ECM: uzaktayken arayıcı gürültüde hedefi kaybedebilir
			if keep and t.jamming() and pos.distance_to(t.com_global()) > EcmModule.BURN_THROUGH and randf() < 0.06:
				keep = false
			# chaff: hedefin yakınındaki taze bulut arayıcıyı kendine çekebilir
			if keep and randf() < Chaff.near(t.com_global()) * 0.14:
				keep = false
		if keep:
			_remember(t)
			# yaklaşınca kendi radarını aç: artık fırlatana gerek yok
			if not seeker_active and can_go_active and pos.distance_to(t.com_global()) < ACTIVE_RANGE:
				seeker_active = true
		else:
			target = null
			_prev_los = Vector3.ZERO
	if target == null and can_go_active and _has_last:
		if not seeker_active and pos.distance_to(_last_pos) < ACTIVE_RANGE:
			seeker_active = true      # "PITBULL": kendi radarı açıldı, son bilinen bölgede ara
		if seeker_active:
			_radar_acquire(pos, fwd)


## Etkin radar arayıcı: konideki, son bilinen konuma en yakın düşmanı yakalar.
func _radar_acquire(pos: Vector3, fwd: Vector3) -> void:
	var best: Vessel = null
	var best_d := 2500.0
	for node in get_parent().get_children():
		if node is Vessel and node != shooter and not node.parts.is_empty() and (shooter == null or not is_instance_valid(shooter) or node.team != shooter.team):
			var tp: Vector3 = node.com_global()
			if fwd.angle_to(tp - pos) > deg_to_rad(_p["cone"]) or pos.distance_to(tp) > ACTIVE_RANGE * 1.2:
				continue
			var d := tp.distance_to(_last_pos)
			if d < best_d and not in_notch(pos, node) and terrain_clear(pos, tp):
				best_d = d
				best = node
	if best:
		target = best
		victim = best
		_prev_los = Vector3.ZERO
		_remember(best)


# ------------------------------------------------------------------ uçuş

func _physics_process(delta: float) -> void:
	_age += delta
	var pos := global_position
	var accel := Planet.gravity_at(pos)
	var speed := velocity.length()
	var fwd := velocity.normalized() if speed > 1.0 else -global_basis.z

	if _age < _p["burn"]:
		accel += fwd * float(_p["thrust"])
	else:
		_flame.visible = false
		_motor.volume_db = move_toward(_motor.volume_db, -60.0, delta * 30.0)
	var rho := Atmosphere.density(Planet.altitude(pos))
	accel -= velocity * speed * float(_p["drag"]) * rho / 1.225

	# Arayıcı ve güdüm (ilk 0.25 sn serbest uçuş: uçaktan güvenle ayrılsın)
	var aim: Variant = null
	if is_radar():
		_track_timer -= delta
		if _track_timer <= 0.0 and _age > 0.25:
			_track_timer = 0.15
			_radar_track(pos, fwd)
		if is_instance_valid(target) and target.is_inside_tree():
			aim = target.com_global()
		elif _has_last:
			# iz yok: son bilinen konumun tahmini (hedef aynı hızla gitmiş say)
			_last_pos += _last_vel * delta
			aim = _last_pos
	else:
		_scan_timer -= delta
		if not is_instance_valid(target) and _age > 0.25 and _scan_timer <= 0.0:
			_scan_timer = 0.2
			_acquire(pos, fwd)
		_decoy_timer -= delta
		if _decoy_timer <= 0.0 and is_instance_valid(target) and _age > 0.25:
			_decoy_timer = 0.15
			_check_decoys(pos, fwd)
		if is_instance_valid(target) and target.is_inside_tree():
			if fwd.angle_to(target.heat_position() - pos) > SEEKER_CONE * 1.6 or target.heat_signature() < 0.02:
				target = null   # hedef arayıcı konisinden çıktı / soğudu: kilit koptu
			else:
				aim = target.heat_position()
	if aim != null and _age > 0.25:
		var los: Vector3 = aim - pos
		var dist := los.length()
		var los_dir := los / maxf(dist, 0.01)
		if _prev_los != Vector3.ZERO:
			var los_rate := (los_dir - _prev_los) / delta
			var tvel: Vector3 = target.linear_velocity if is_instance_valid(target) else _last_vel
			var closing: float = (velocity - tvel).dot(los_dir)
			var cmd := los_rate * NAV_GAIN * maxf(closing, 100.0)
			cmd -= fwd * cmd.dot(fwd)
			accel += cmd.limit_length(float(_p["max_g"]) * 9.81)
		_prev_los = los_dir
		if dist < float(_p["fuse"]) and is_instance_valid(target):
			_detonate()
			return

	velocity += accel * delta
	var new_pos := pos + velocity * delta
	# çarpma (zemin, araç)
	var q := PhysicsRayQueryParameters3D.create(pos, new_pos, 1 | 2 | 8)
	if is_instance_valid(shooter) and _age < 1.0:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		_detonate()
		return
	global_position = new_pos
	if velocity.length() > 1.0:
		look_at(new_pos + velocity, Planet.up_at(new_pos))
	if _age > float(_p["life"]) or Planet.altitude(new_pos) < 0.0:
		_detonate()


func _detonate() -> void:
	Damage.explosion(global_position, float(_p["blast_r"]), float(_p["blast_dmg"]), null)
	# duman izi bir süre havada kalsın
	_trail.emitting = false
	queue_free()
