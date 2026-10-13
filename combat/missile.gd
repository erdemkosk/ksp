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
##   Doppler hızı ~0, yer yankısına karışır) ve chaff kilidi koparabilir. Hedef bir füze de
##   olabilir (SAM'ın seyir füzesini vurması): o zaman doğrudan izler.
## guidance = "arm": radar avcısı (HARM). Radar yayınına kilitlenir (SAM, erken uyarı radarı,
##   gemi, radarı açık uçak). Yayın kesilirse son bilinen konuma gider.
## guidance = "cruise": seyir füzesi. Haritadan seçilen noktaya (GPS) yerden ~60 m yükseklikte
##   arazi takip ederek uçar, hedefe yaklaşınca yükselip dalar. SAM'lar onu vurabilir.
## guidance = "ship": gemi savar. Denizin ~15 m üstünde uçar, hedef bölgeye yaklaşınca kendi
##   radarını açıp en yakın savaş gemisine kilitlenir.

const IR := {"burn": 2.6, "thrust": 260.0, "max_g": 35.0, "cone": 30.0, "fuse": 9.0, "blast_r": 15.0,
	"blast_dmg": 420.0, "life": 22.0, "drag": 0.0009, "r": 0.07, "len": 2.8}
const RADAR := {"burn": 5.0, "thrust": 175.0, "max_g": 30.0, "cone": 45.0, "fuse": 12.0, "blast_r": 18.0,
	"blast_dmg": 380.0, "life": 50.0, "drag": 0.0006, "r": 0.09, "len": 3.6}
const LONG := {"burn": 8.0, "thrust": 150.0, "max_g": 22.0, "cone": 45.0, "fuse": 20.0, "blast_r": 25.0,
	"blast_dmg": 450.0, "life": 110.0, "drag": 0.0004, "r": 0.2, "len": 6.5}
const ARM := {"burn": 4.5, "thrust": 170.0, "max_g": 22.0, "cone": 60.0, "fuse": 18.0, "blast_r": 22.0,
	"blast_dmg": 1100.0, "life": 80.0, "drag": 0.0006, "r": 0.12, "len": 4.1}
const CRUISE := {"burn": 2.5, "thrust": 60.0, "max_g": 6.0, "cone": 30.0, "fuse": 14.0, "blast_r": 40.0,
	"blast_dmg": 2600.0, "life": 700.0, "drag": 0.00025, "r": 0.28, "len": 5.2, "cruise": 240.0, "agl": 60.0}
const SHIP := {"burn": 2.0, "thrust": 90.0, "max_g": 12.0, "cone": 40.0, "fuse": 10.0, "blast_r": 20.0,
	"blast_dmg": 2400.0, "life": 400.0, "drag": 0.00025, "r": 0.18, "len": 4.6, "cruise": 260.0, "agl": 15.0}
const NAV_GAIN := 4.0
const ACTIVE_RANGE := 7000.0
const NOTCH_SPEED := 35.0           ## m/s: hedefin görüş hattındaki hızı bundan küçükse çentikte
const SEEKER_CONE := deg_to_rad(30.0)   ## IR arayıcı (MissileModule ve yapay zeka da kullanır)

var velocity := Vector3.ZERO
## Füze de hedef olabilir (SAM önleme füzesi): Vessel ile aynı arayüz
var linear_velocity: Vector3:
	get:
		return velocity
var target: Node3D           ## Vessel, Flare, Warship ya da önlenecek Missile
var victim: Vessel           ## fırlatıldığında kilitli olunan uçak (füze uyarısı için)
var guidance := "ir"
var launcher: Node           ## radar: hedefi aydınlatan (Vessel ya da SamSite)
var can_go_active := true    ## radar: son evrede kendi radarını açabilir mi
var seeker_active := false   ## radar / gemi savar: kendi radarı açık
var long_range := false      ## uzun menzilli SAM füzesi (büyük, uzun yanma)
var team := ""               ## atanın takımı (shooter yoksa: SAM)
var strike_point := Vector3.INF   ## seyir / gemi savar: hedef nokta (dünya; kayan orijinle kaydırılır)

## Uçuştaki füzeler (füze yaklaşma uyarısı, RWR ve yapay zeka kaçınması için).
static var active: Array[Missile] = []
var shooter: Vessel

var _p: Dictionary = IR
var _age := 0.0
var _prev_los := Vector3.ZERO
var _decoy_timer := 0.0
var _scan_timer := 0.0
var _track_timer := 0.0
var _last_pos := Vector3.ZERO     ## radar / ARM: hedefin son bilinen konumu / hızı (iz koparsa tahmin)
var _last_vel := Vector3.ZERO
var _has_last := false
var _trail: PuffTrail
var _motor: AudioStreamPlayer3D
var _flame: MeshInstance3D
var _popped := false              ## seyir füzesi: son dalış için yükseldi


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	match guidance:
		"radar":
			_p = LONG if long_range else RADAR
		"arm":
			_p = ARM
		"cruise":
			_p = CRUISE
		"ship":
			_p = SHIP
		_:
			_p = IR
	if team == "" and is_instance_valid(shooter):
		team = shooter.team
	var r: float = _p["r"]
	var length: float = _p["len"]
	var col := Color(0.88, 0.89, 0.87)
	if guidance in ["cruise", "ship"]:
		col = Color(0.42, 0.45, 0.4)
	add_child(build_model(length, r, guidance != "ir", col))
	if guidance == "cruise":
		# açılır kanatlar (seyir füzesi)
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(2.6, 0.03, 0.35)
		wing.mesh = wm
		wing.position = Vector3(0, 0, 0.2)
		wing.material_override = VesselBuilder.material("paint", col)
		add_child(wing)
	# roket alevi: motorlardaki alev shader'ı (dış alev + sıcak çekirdek) ve egzoz ışığı
	var nz := length * 0.5 + 0.06
	_flame = _flame_mesh("flame", [Vector2(0, r * 0.7), Vector2(r * 3.0, r * 1.15), Vector2(r * 14.0, r * 0.8), Vector2(r * 26.0, 0.0)], nz)
	_flame_core = _flame_mesh("flame_core", [Vector2(0, r * 0.55), Vector2(r * 3.0, r * 0.5), Vector2(r * 9.0, 0.0)], nz)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.3)
	_glow.light_energy = 2.5
	_glow.omni_range = 14.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 0, nz + r * 4.0)
	add_child(_glow)
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
	elif guidance == "arm" and is_instance_valid(target):
		_last_pos = _emitter_pos(target)
		_has_last = true


func _exit_tree() -> void:
	active.erase(self)


var _flame_core: MeshInstance3D
var _glow: OmniLight3D


## Füze modeli: raydaki füzeyle aynı (PartLibrary._missile_visuals) — fırlatınca görünüm değişmez.
static func build_model(length: float, r: float, radar: bool, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var vis := PartLibrary._missile_visuals(length, r, radar, color)
	for i in vis.size():
		var v: Dictionary = (vis[i] as Dictionary).duplicate()
		if v.get("name", "") == "Missile":
			v["pos"] = Vector3.ZERO     # rayda gövdenin altına asılı; uçuşta merkezde
		var mi := VesselBuilder._make_mesh(v, "missile:%.2f:%.3f:%s:%s:%d" % [length, r, radar, color.to_html(), i])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var parent: Node = root.find_child(String(v["parent"]), true, false) if v.has("parent") else root
		(parent if parent else root).add_child(mi)
	return root


func _flame_mesh(mat: String, profile: Array, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.lathe(profile, 16)
	mi.material_override = VesselBuilder.material(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, z)
	mi.set_instance_shader_parameter("power", 1.0)
	mi.set_instance_shader_parameter("afterburner", 0.75)
	add_child(mi)
	return mi


func is_radar() -> bool:
	return guidance == "radar"


## Füze de hedef olabilir (SAM, seyir füzesini vurur).
func com_global() -> Vector3:
	return global_position


func radar_altitude() -> float:
	return Planet.altitude(global_position) - maxf(TerrainGen.height(Planet.surface_dir(global_position)), 0.0)


## Önleme füzesi ya da top vurdu: küçük patlama, düşer.
func shoot_down() -> void:
	var up := Planet.up_at(global_position)
	Effects.explosion(FloatingOrigin.world_root, global_position, up, 1.2)
	Sfx.explosion(global_position, 0.8)
	_trail.emitting = false
	queue_free()


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
		if node is Vessel and node != shooter and not node.parts.is_empty() and node.team != team:
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
	if strike_point != Vector3.INF:
		strike_point -= s


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
	if launcher is Warship:
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
	# füze önleme: hedef füze, doğrudan izlenir
	if target is Missile:
		_remember(target)
		return
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
		if node is Vessel and node != shooter and not node.parts.is_empty() and node.team != team:
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


# ------------------------------------------------------------------ radar avcısı (ARM)

## Takımı `not_team` olmayan, şu an yayın yapan radarlar: [düğüm, ...].
static func emitters(world: Node, not_team: String) -> Array:
	var out: Array = []
	for s in SamSite.sites:
		if s.team != not_team and s.emitting():
			out.append(s)
	for st in RadarStation.stations:
		if st.team != not_team and st.emitting() and not st.unit_name.begins_with("SAM"):
			out.append(st)
	for sh in Warship.ships:
		if is_instance_valid(sh) and sh.team != not_team and not sh.destroyed:
			out.append(sh)
	if world:
		for n in world.get_children():
			if n is Vessel and n.team != not_team and n.team != "sivil" and not n.parts.is_empty() and n.radar_on and n.radar() != null and n.has_power():
				out.append(n)
	return out


static func _emitter_pos(e: Node) -> Vector3:
	if e is Vessel:
		return e.com_global()
	if e.has_method("emitter_position"):
		return e.emitter_position()
	return (e as Node3D).global_position


static func _emits(e: Node) -> bool:
	if not is_instance_valid(e):
		return false
	if e is Vessel:
		return not e.parts.is_empty() and e.radar_on and e.radar() != null and e.has_power()
	if e.has_method("emitting"):
		return e.emitting()
	return not e.destroyed


func _arm_aim(pos: Vector3, fwd: Vector3) -> Variant:
	if _emits(target):
		_last_pos = _emitter_pos(target)
		_has_last = true
		_last_vel = target.linear_velocity if target is Vessel else Vector3.ZERO
		return _last_pos
	# yayın kesildi: son bilinen yere; yolda başka yayın yakalarsa ona geç
	_scan_timer -= get_physics_process_delta_time()
	if _scan_timer <= 0.0:
		_scan_timer = 0.5
		var best: Node = null
		var best_a := deg_to_rad(_p["cone"]) * 0.5
		for e in emitters(get_parent(), team):
			var a := fwd.angle_to(_emitter_pos(e) - pos)
			if a < best_a:
				best_a = a
				best = e
		if best:
			target = best
	return _last_pos if _has_last else null


# ------------------------------------------------------------------ seyir / gemi savar

func _cruise_aim(pos: Vector3, fwd: Vector3) -> Variant:
	if strike_point == Vector3.INF:
		return null
	var up := Planet.up_at(pos)
	var goal := strike_point
	# gemi savar: hedef bölgede kendi radarını açar, en yakın düşman gemisine kilitlenir
	if guidance == "ship":
		if is_instance_valid(target) and target is Warship and not target.destroyed:
			goal = target.global_position + Planet.up_at(target.global_position) * 3.0
		elif pos.distance_to(strike_point) < 14000.0:
			seeker_active = true
			_scan_timer -= get_physics_process_delta_time()
			if _scan_timer <= 0.0:
				_scan_timer = 0.4
				var best: Warship = null
				var bd := 15000.0
				for sh in Warship.ships:
					if is_instance_valid(sh) and not sh.destroyed and sh.team != team and fwd.angle_to(sh.global_position - pos) < deg_to_rad(_p["cone"]):
						var d := sh.global_position.distance_to(pos)
						if d < bd:
							bd = d
							best = sh
				if best:
					target = best
	var to := goal - pos
	var horiz := to - up * to.dot(up)
	var hd := horiz.length()
	if guidance == "cruise" and hd < 2500.0:
		# son evre: kısa yükselme, sonra hedefe dalış
		if not _popped and hd > 1200.0:
			return pos + horiz.normalized() * 400.0 + up * 220.0
		_popped = true
		return goal
	if guidance == "ship" and hd < 1500.0:
		return goal
	# seyir: arazi / deniz takibi (önündeki ~5 sn'nin en yükseği + agl)
	var ground := 0.0
	var t := 0.0
	var hv := velocity - up * velocity.dot(up)
	while t <= 5.0:
		ground = maxf(ground, TerrainGen.height(Planet.surface_dir(pos + hv * t)))
		t += 1.0
	var want_alt := ground + float(_p["agl"])
	var alt := Planet.altitude(pos)
	return pos + horiz.normalized() * 700.0 + up * clampf(want_alt - alt, -120.0, 200.0)


# ------------------------------------------------------------------ uçuş

func _physics_process(delta: float) -> void:
	_age += delta
	var pos := global_position
	var accel := Planet.gravity_at(pos)
	var speed := velocity.length()
	var fwd := velocity.normalized() if speed > 1.0 else -global_basis.z
	var air_breather := guidance in ["cruise", "ship"]

	if _age < _p["burn"]:
		accel += fwd * float(_p["thrust"])
		# alev titrer; yanmanın son yarım saniyesinde söner
		var f := clampf((float(_p["burn"]) - _age) / 0.5, 0.0, 1.0) * randf_range(0.9, 1.1)
		_flame.scale = Vector3(1.0, 1.0, f)
		_flame_core.scale = Vector3(1.0, 1.0, f)
		_glow.light_energy = 2.5 * f
	elif air_breather:
		# turbojet: seyir hızını tut, kanat / gövde kaldırması yerçekimini karşılar
		accel += fwd * clampf((float(_p["cruise"]) - speed) * 0.8, -5.0, 25.0)
		accel -= Planet.gravity_at(pos) * 0.95
		_flame.scale = Vector3.ONE * 0.4
		_flame_core.visible = false
		_glow.visible = false
	else:
		_flame.visible = false
		_flame_core.visible = false
		_glow.visible = false
		_motor.volume_db = move_toward(_motor.volume_db, -60.0, delta * 30.0)
	var rho := Atmosphere.density(Planet.altitude(pos))
	accel -= velocity * speed * float(_p["drag"]) * rho / 1.225

	# Arayıcı ve güdüm (ilk 0.25 sn serbest uçuş: uçaktan güvenle ayrılsın)
	var aim: Variant = null
	match guidance:
		"radar":
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
		"arm":
			aim = _arm_aim(pos, fwd)
		"cruise", "ship":
			if _age > 1.0:
				aim = _cruise_aim(pos, fwd)
		_:
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
			var tvel: Vector3 = target.linear_velocity if is_instance_valid(target) and "linear_velocity" in target else _last_vel
			var closing: float = (velocity - tvel).dot(los_dir)
			var cmd := los_rate * NAV_GAIN * maxf(closing, 100.0)
			# seyir: hedef noktaya doğru yönelme (PN tek başına yavaş döner)
			if air_breather:
				cmd += (los_dir - fwd) * speed * 0.6
			cmd -= fwd * cmd.dot(fwd)
			accel += cmd.limit_length(float(_p["max_g"]) * 9.81)
		_prev_los = los_dir
		var armed_target := is_instance_valid(target) or guidance in ["arm", "cruise", "ship"]
		if dist < float(_p["fuse"]) and armed_target:
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
	if _age > float(_p["life"]) or Planet.altitude(new_pos) < 0.0 or (air_breather and radar_altitude() < 0.5):
		_detonate()


func _detonate() -> void:
	var gp := global_position
	Damage.explosion(gp, float(_p["blast_r"]), float(_p["blast_dmg"]), null)
	# patlama yakınındaki seyir / gemi savar füzeleri de düşer (önleme)
	for m in active.duplicate():
		if m != self and is_instance_valid(m) and m.guidance in ["cruise", "ship"] and m.global_position.distance_to(gp) < float(_p["blast_r"]) * 1.5:
			m.shoot_down()
	if guidance in ["cruise", "ship"]:
		Effects.explosion(FloatingOrigin.world_root, gp, Planet.up_at(gp), 3.0)
		Sfx.explosion(gp, 2.5)
	# duman izi bir süre havada kalsın
	_trail.emitting = false
	queue_free()
