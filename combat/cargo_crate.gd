class_name CargoCrate
extends Node3D
## Paraşütlü yardım sandığı. Serbest düşüş 1.5 sn, sonra paraşüt açılır (~7 m/s iniş).
## Yere inince `down` olur; kargo görevi düşen sandıkları bölgeye göre sayar.

const CHUTE_TIME := 1.5
const DRAG_FREE := 0.0004
const DRAG_CHUTE := 0.2

var velocity := Vector3.ZERO
var _age := 0.0
var _chute: MeshInstance3D
var down := false
var counted := false   ## görev bu sandığı saydı mı


static func drag_at(age: float) -> float:
	return DRAG_FREE if age < CHUTE_TIME else lerpf(DRAG_FREE, DRAG_CHUTE, clampf((age - CHUTE_TIME) / 1.2, 0.0, 1.0))


static func step(pos: Vector3, vel: Vector3, age: float, dt: float) -> Vector3:
	var rho := Atmosphere.density(Planet.altitude(pos)) / 1.225
	return vel + (Planet.gravity_at(pos) - vel * vel.length() * drag_at(age) * rho) * dt


## Sandık şimdi bırakılsa nereye iner (HUD için).
static func simulate_impact(pos: Vector3, vel: Vector3) -> Variant:
	var t := 0.0
	var dt := 0.1
	while t < 240.0:
		var nv := step(pos, vel, t, dt)
		var np := pos + (vel + nv) * 0.5 * dt
		if Planet.altitude(np) < Bomb.ground_alt(np):
			return np
		pos = np
		vel = nv
		t += dt
		dt = 0.1 if t < 4.0 else 0.5
	return null


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 1.0, 1.4)
	box.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.36, 0.22)
	m.roughness = 0.9
	box.material_override = m
	add_child(box)
	_chute = MeshInstance3D.new()
	_chute.mesh = MeshFactory.lathe([Vector2(0.0, 0.0), Vector2(1.2, 2.6), Vector2(2.0, 3.0), Vector2(2.3, 2.8)], 18)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1.0, 1.0, 1.0)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chute.material_override = cm
	_chute.visible = false
	add_child(_chute)



func _physics_process(delta: float) -> void:
	if down:
		return
	_age += delta
	var pos := global_position
	var nv := step(pos, velocity, _age, delta)
	var np := pos + (velocity + nv) * 0.5 * delta
	velocity = nv
	if Planet.altitude(np) < Bomb.ground_alt(np):
		down = true
		global_position = np
		global_basis = Planet.local_basis(np)
		_chute.visible = false
		var smoke := Effects.smoke_column()
		add_child(smoke)
		get_tree().create_timer(120.0).timeout.connect(queue_free)
		return
	global_position = np
	if _age > CHUTE_TIME:
		_chute.visible = true
		var up := -velocity.normalized() if velocity.length() > 1.0 else Planet.up_at(np)
		# kubbe yukarıda: +z ekseni (ağız) aşağı, sandığa baksın
		_chute.global_basis = Basis.looking_at(up, Planet.east_at(np)).scaled(Vector3.ONE * clampf((_age - CHUTE_TIME) / 1.0, 0.1, 1.0))
		_chute.global_position = np + up * 6.0
