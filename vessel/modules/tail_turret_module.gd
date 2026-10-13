class_name TailTurretModule
extends PartModule
## Kuyruk topçusu: arkaya bakan çift namlulu taret. Topçu kendiliğinden, uçağın arka
## yarıküresinde (burundan ±110° dışı) 1.5 km içindeki düşman uçağını öncül nişanla izler ve
## kısa seriler atar. Yer birimlerininkiyle aynı nişan / mermi modeli (GunMount).

const RANGE := 1500.0

var ammo := 1200
var _gun: GunMount
var _yaw: Node3D
var _pitch: Node3D
var _scan := 0.0
var _target: Vessel


func setup(p: Dictionary) -> void:
	ammo = int(p.get("ammo", ammo))


func on_attached() -> void:
	# taret: parçanın arka ucunda; dinlenirken geriye bakar
	_yaw = Node3D.new()
	_yaw.position = Vector3(0, 0.15, part.size.z * 0.25)
	_yaw.rotation.y = PI
	part.add_child(_yaw)
	var dome := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.42
	s.height = 0.84
	dome.mesh = s
	dome.material_override = VesselBuilder.material("glass")
	_yaw.add_child(dome)
	_pitch = Node3D.new()
	_pitch.position = Vector3(0, 0.05, 0)
	_yaw.add_child(_pitch)
	for sx in [-0.12, 0.12]:
		var barrel := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.05
		c.height = 1.4
		barrel.mesh = c
		barrel.rotation_degrees = Vector3(-90, 0, 0)
		barrel.position = Vector3(sx, 0, -0.85)
		barrel.material_override = VesselBuilder.material("dark")
		_pitch.add_child(barrel)
	var muzzles: Array[Vector3] = [Vector3(-0.12, 0, -1.6), Vector3(0.12, 0, -1.6)]
	_gun = GunMount.new(vessel, _yaw, _pitch, muzzles)
	_gun.muzzle_speed = 850.0
	_gun.damage = 16.0
	_gun.interval = 0.07
	_gun.max_range = RANGE
	_gun.yaw_rate = deg_to_rad(90.0)
	_gun.pitch_rate = deg_to_rad(70.0)
	_gun.min_pitch = deg_to_rad(-40.0)
	_gun.max_pitch = deg_to_rad(70.0)
	_gun.rest_pitch = 0.0
	_gun.burst_len = Vector2(0.6, 1.4)
	_gun.pause_len = Vector2(0.6, 1.4)
	_gun.add_flash(0.25)


func physics_tick(delta: float) -> void:
	if _gun == null or not vessel.has_pilot():
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.4
		_target = _find()
	if ammo <= 0 or not is_instance_valid(_target):
		_gun.rest(delta)
		return
	var before := _gun.shots
	_gun.engage(_target, delta, true)
	ammo -= _gun.shots - before


func _find() -> Vessel:
	var me := part.global_position
	var fwd := vessel.forward()
	var best: Vessel = null
	var bd := RANGE
	for n in vessel.get_parent().get_children():
		if n is Vessel and n != vessel and n.team != vessel.team and n.team != "sivil" and not n.parts.is_empty():
			var to: Vector3 = n.com_global() - me
			var d := to.length()
			if d < bd and fwd.angle_to(to) > deg_to_rad(70.0):
				bd = d
				best = n
	return best
