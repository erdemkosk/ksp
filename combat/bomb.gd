class_name Bomb
extends Node3D
## Bomba: yerçekimi + hava direnci ile düşer, burnu hız yönüne döner, çarpınca büyük alan
## hasarıyla patlar. HUD'daki CCIP aynı fizikle hesaplanır (simulate_impact).
## Lazer güdümlü (laser != null): podun işaretlediği nokta görünürken kanatçıklarıyla oraya
## döner (oransal güdüm, en çok GUIDE_ACCEL). Kanatçıklar biraz kaldırma da üretir: süzülerek
## güdümsüzden daha uzağa gider. İşaret kaybolursa balistik devam eder.

const DRAG := 0.00018        ## v² katsayısı (deniz seviyesi)
const BLAST_RADIUS := 34.0
const BLAST_DAMAGE := 1600.0
const ARM_TIME := 0.6
const GUIDE_ACCEL := 32.0    ## m/s² (~3 G)
const SEEKER_CONE := deg_to_rad(35.0)

## Son bombanın düştüğü yer (testler için).
static var last_impact := Vector3.ZERO

var velocity := Vector3.ZERO
var shooter: Vessel
var laser: TargetingPodModule     ## işaretleyici pod (LGB); null = güdümsüz
var _age := 0.0
var _prev_los := Vector3.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.lathe([Vector2(-1.1, 0.0), Vector2(-0.8, 0.16), Vector2(0.5, 0.17), Vector2(1.0, 0.07)], 16)
	body.material_override = VesselBuilder.material("paint", Color(0.33, 0.37, 0.28))
	add_child(body)
	for i in 4:
		var fin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.36, 0.3)
		fin.mesh = bm
		fin.position = Vector3(0, 0, 0.95)
		fin.rotation_degrees = Vector3(0, 0, 45 + i * 90)
		fin.material_override = body.material_override
		add_child(fin)


## Yerin (arazi ya da deniz) deniz seviyesinden yüksekliği; çarpışma yaması dışında da çalışır.
static func ground_alt(pos: Vector3) -> float:
	return maxf(TerrainGen.height(Planet.surface_dir(pos)), 0.0)


static func step(pos: Vector3, vel: Vector3, dt: float) -> Vector3:
	var rho := Atmosphere.density(Planet.altitude(pos)) / 1.225
	return vel + (Planet.gravity_at(pos) - vel * vel.length() * DRAG * rho) * dt


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
	velocity = step(pos, velocity, delta)
	if laser != null:
		_guide(pos, delta)
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
		if _age > ARM_TIME:
			Damage.explosion(global_position, BLAST_RADIUS, BLAST_DAMAGE, null)
		queue_free()
		return
	global_position = new_pos
	if velocity.length() > 1.0:
		look_at(new_pos + velocity, Planet.up_at(new_pos))
	if _age > 90.0:
		queue_free()


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
