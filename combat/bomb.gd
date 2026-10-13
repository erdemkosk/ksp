class_name Bomb
extends Node3D
## Bomba: yerçekimi + hava direnci ile düşer, burnu hız yönüne döner, çarpınca büyük alan
## hasarıyla patlar. HUD'daki CCIP aynı fizikle hesaplanır (simulate_impact).
## Türler (kind):
##   normal  — 250 kg güdümsüz.
##   lgb     — lazer güdümlü (laser != null): podun işaretlediği nokta görünürken kanatçıklarıyla
##             oraya döner (oransal güdüm, en çok GUIDE_ACCEL); biraz süzülür.
##   glide   — süzülen bomba: açılır kanatlar (süzülme oranı ~7), GPS hedefine yönelir; 8 km
##             irtifadan 25–30 km gider.
##   cluster — misket: hedefin ~300 m üstünde açılır, 40 bombacığı geniş bir alana saçar.
##   bomblet — misketin bombacığı (küçük patlama).
##   heavy   — 1000 kg: çok büyük patlama yarıçapı.

const DRAG := 0.00018        ## v² katsayısı (deniz seviyesi)
const BLAST_RADIUS := 34.0
const BLAST_DAMAGE := 1600.0
const ARM_TIME := 0.6
const GUIDE_ACCEL := 32.0    ## m/s² (~3 G)
const SEEKER_CONE := deg_to_rad(35.0)
const BLAST := {"normal": [34.0, 1600.0], "lgb": [34.0, 1600.0], "glide": [38.0, 2000.0],
	"cluster": [20.0, 300.0], "bomblet": [11.0, 300.0], "heavy": [70.0, 4800.0]}

## Son bombanın düştüğü yer (testler için).
static var last_impact := Vector3.ZERO

var velocity := Vector3.ZERO
var shooter: Vessel
var kind := "normal"
var laser: TargetingPodModule     ## işaretleyici pod (LGB); null = güdümsüz
var gps := Vector3.INF            ## süzülen bomba hedefi (dünya; kayan orijinle kaydırılır)
var _age := 0.0
var _prev_los := Vector3.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var k := {"heavy": 1.6, "bomblet": 0.25, "cluster": 1.2, "glide": 1.25}.get(kind, 1.0) as float
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.lathe([Vector2(-1.1, 0.0), Vector2(-0.8, 0.16), Vector2(0.5, 0.17), Vector2(1.0, 0.07)], 16 if kind != "bomblet" else 6)
	body.scale = Vector3.ONE * k
	body.material_override = VesselBuilder.material("paint", Color(0.36, 0.38, 0.33) if kind in ["cluster", "bomblet"] else Color(0.33, 0.37, 0.28))
	add_child(body)
	for i in 4:
		var fin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.36, 0.3) * k
		fin.mesh = bm
		fin.position = Vector3(0, 0, 0.95 * k)
		fin.rotation_degrees = Vector3(0, 0, 45 + i * 90)
		fin.material_override = body.material_override
		add_child(fin)
	if kind == "glide":
		# açılır kanatlar
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(2.8, 0.03, 0.4)
		wing.mesh = wm
		wing.position = Vector3(0, 0.18, -0.1)
		wing.material_override = body.material_override
		add_child(wing)
	FloatingOrigin.shifted.connect(func(s: Vector3) -> void:
		if gps != Vector3.INF:
			gps -= s)


## Yerin (arazi ya da deniz) deniz seviyesinden yüksekliği; çarpışma yaması dışında da çalışır.
static func ground_alt(pos: Vector3) -> float:
	return maxf(TerrainGen.height(Planet.surface_dir(pos)), 0.0)


static func step(pos: Vector3, vel: Vector3, dt: float, drag := DRAG) -> Vector3:
	var rho := Atmosphere.density(Planet.altitude(pos)) / 1.225
	return vel + (Planet.gravity_at(pos) - vel * vel.length() * drag * rho) * dt


## Bugün bırakılsaydı nereye düşerdi? (HUD CCIP). Dünya uzayında çarpma noktası ya da null.
static func simulate_impact(space: PhysicsDirectSpaceState3D, pos: Vector3, vel: Vector3, max_time := 40.0) -> Variant:
	var dt := 0.1
	var t := 0.0
	while t < max_time:
		var nv := step(pos, vel, dt)
		var np := pos + (vel + nv) * 0.5 * dt   # yamuk kuralı: büyük adımda da doğru
		var q := PhysicsRayQueryParameters3D.create(pos, np, 1 | 8)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return hit["position"]
		if Planet.altitude(np) < ground_alt(np):
			return np
		pos = np
		vel = nv
		t += dt
		dt = minf(dt * 1.06, 0.25)
	return null


func _physics_process(delta: float) -> void:
	_age += delta
	var pos := global_position
	velocity = step(pos, velocity, delta, DRAG * (0.25 if kind == "glide" else 1.0))
	if laser != null:
		_guide(pos, delta)
	elif kind == "glide" and gps != Vector3.INF:
		_glide(pos, delta)
	# misket: hedefin ~300 m üstünde (yerden) açılır
	if kind == "cluster" and _age > 1.5 and Planet.altitude(pos) - ground_alt(pos) < 300.0:
		_scatter(pos)
		return
	var new_pos := pos + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(pos, new_pos, 1 | 2 | 8)
	if is_instance_valid(shooter) and _age < 2.0:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() or Planet.altitude(new_pos) < ground_alt(new_pos):
		global_position = hit["position"] if not hit.is_empty() else new_pos
		last_impact = global_position
		if Game.args.has("bombtest"):
			var nd := INF
			for n in get_parent().get_children():
				if n is GroundTarget:
					nd = minf(nd, n.global_position.distance_to(global_position))
			print("BOMBA ÇARPTI: en yakın tanka %.1f m (yaş %.1f)" % [nd, _age])
		if _age > ARM_TIME or kind == "bomblet":
			var bl: Array = BLAST.get(kind, BLAST["normal"])
			Damage.explosion(global_position, bl[0], bl[1], null)
			if kind == "heavy":
				Effects.explosion(FloatingOrigin.world_root, global_position, Planet.up_at(global_position), 5.0)
		queue_free()
		return
	global_position = new_pos
	if velocity.length() > 1.0:
		look_at(new_pos + velocity, Planet.up_at(new_pos))
	if _age > 180.0:
		queue_free()


## Misket açılır: 40 bombacık, hıza ek olarak her yöne (çoğu yatay) saçılır.
func _scatter(pos: Vector3) -> void:
	var up := Planet.up_at(pos)
	Effects.explosion(FloatingOrigin.world_root, pos, up, 0.8)
	for i in 40:
		var b := Bomb.new()
		b.kind = "bomblet"
		b.shooter = shooter
		var r := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.2), randf_range(-1, 1))
		b.velocity = velocity * 0.85 + r * randf_range(15.0, 55.0)
		get_parent().add_child(b)
		b.global_position = pos + r
	queue_free()


## Süzülen bomba: kanat kaldırması (en çok ~1.3 G) ve GPS hedefine yönelme.
func _glide(pos: Vector3, delta: float) -> void:
	var speed := velocity.length()
	if speed < 1.0 or _age < 0.8:
		return
	var fwd := velocity / speed
	var los := gps - pos
	var los_dir := los.normalized()
	var up := Planet.up_at(pos)
	# kaldırma: yerçekiminin dik bileşenini karşıla (süzül), hızla orantılı sınır
	var lift_dir := up - fwd * up.dot(fwd)
	var accel := lift_dir.normalized() * 9.81 * 0.95 if lift_dir.length() > 0.01 else Vector3.ZERO
	if _prev_los != Vector3.ZERO:
		var los_rate := (los_dir - _prev_los) / delta
		var cmd := los_rate * 3.0 * maxf(speed, 80.0) + (los_dir - fwd) * speed * 0.15
		cmd -= fwd * cmd.dot(fwd)
		accel += cmd
	_prev_los = los_dir
	var lim := 9.81 * clampf(speed / 120.0, 0.3, 1.6)
	velocity += accel.limit_length(lim) * delta


## Lazer işareti (podun takip noktası) arayıcı konisindeyse ona doğru yanal ivme.
func _guide(pos: Vector3, delta: float) -> void:
	var spot: Variant = null
	if is_instance_valid(laser) and is_instance_valid(laser.vessel) and laser.part in laser.vessel.parts and laser.vessel.has_power():
		spot = laser.target_point()
	var speed := velocity.length()
	if spot == null or speed < 1.0 or _age < 0.5:
		_prev_los = Vector3.ZERO
		return
	var los: Vector3 = (spot as Vector3) - pos
	var fwd := velocity / speed
	if fwd.angle_to(los) > SEEKER_CONE:
		_prev_los = Vector3.ZERO
		return
	var los_dir := los.normalized()
	# kanatçık kaldırması: yerçekiminin bir kısmını karşılar (süzülme)
	var up := Planet.up_at(pos)
	var lift := up - fwd * up.dot(fwd)
	var accel := lift * 9.81 * 0.45
	if _prev_los != Vector3.ZERO:
		var los_rate := (los_dir - _prev_los) / delta
		var cmd := los_rate * 3.5 * maxf(speed, 80.0)
		# yerçekimi düşüşünü telafi (bomba hedefin üstünden geçmesin)
		cmd -= Planet.gravity_at(pos) * 0.6
		cmd -= fwd * cmd.dot(fwd)
		accel += cmd
	_prev_los = los_dir
	velocity += accel.limit_length(GUIDE_ACCEL) * delta
