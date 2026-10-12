class_name Drogue
extends Node3D
## Tanker uçağının arkasından sarkan ikmal hortumu ve sepeti (hortum-sepet yöntemi).
## Tankerin kuyruğundan geriye ve aşağı uzanır, hafifçe salınır. Sepet ışıkları: sarı = hazır,
## yeşil = yakıt akıyor. Probun bağlantısı RefuelProbeModule'de.

const HOSE_LENGTH := 24.0

static var active: Array[Drogue] = []

var tanker: Vessel
var connected: Vessel
var flowing := false

var _hose: MeshInstance3D
var _basket: Node3D
var _lamp_mat: StandardMaterial3D
var _t := 0.0
var _anchor_local := Vector3.ZERO    ## hortumun tankerdeki çıkış noktası (tanker uzayı)
var _prev_basket := Vector3.ZERO
var _vel := Vector3.ZERO


static func attach(to: Vessel) -> Drogue:
	var d := Drogue.new()
	d.tanker = to
	var rear := 0.0
	for p in to.parts:
		rear = maxf(rear, p.position.z + p.size.z * 0.5)
	d._anchor_local = Vector3(0, -0.9, rear - 1.0)
	to.get_parent().add_child(d)
	return d


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	active.append(self)
	_hose = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 1.0
	cyl.radial_segments = 10
	_hose.mesh = cyl
	_hose.material_override = VesselBuilder.material("dark")
	add_child(_hose)
	# sepet: dışa açılan koni (paraşüt gibi), iç halka ve uç ışıkları
	_basket = Node3D.new()
	add_child(_basket)
	var cone := MeshInstance3D.new()
	cone.mesh = MeshFactory.lathe([Vector2(-0.35, 0.18), Vector2(0.1, 0.35), Vector2(0.55, 0.62)], 24)
	cone.material_override = VesselBuilder.material("paint", Color(0.9, 0.9, 0.88))
	_basket.add_child(cone)
	var ring := MeshInstance3D.new()
	ring.mesh = MeshFactory.lathe([Vector2(-0.45, 0.16), Vector2(-0.3, 0.2)], 16)
	ring.material_override = VesselBuilder.material("metal")
	_basket.add_child(ring)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.albedo_color = Color(1.0, 0.8, 0.2) * 2.0
	for i in 6:
		var a := i * TAU / 6.0
		var lamp := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.04
		s.height = 0.08
		lamp.mesh = s
		lamp.material_override = _lamp_mat
		lamp.position = Vector3(cos(a) * 0.62, sin(a) * 0.62, 0.55)
		_basket.add_child(lamp)
	FloatingOrigin.shifted.connect(func(s: Vector3) -> void: _prev_basket -= s)
	_update(0.0)


func _exit_tree() -> void:
	active.erase(self)


## Sepetin ağzının (probun gireceği nokta) dünya konumu.
func basket_position() -> Vector3:
	return _basket.global_position + _basket.global_basis.z * -0.35


func velocity() -> Vector3:
	return _vel


func _physics_process(delta: float) -> void:
	if not is_instance_valid(tanker) or tanker.parts.is_empty():
		queue_free()
		return
	_t += delta
	_update(delta)


func _update(delta: float) -> void:
	var xf := tanker.global_transform
	var anchor := xf * _anchor_local
	# sepet: tankerin arkasında, biraz aşağıda; türbülansla hafif salınır
	var sway := Vector3(sin(_t * 0.7) * 0.6 + sin(_t * 1.9) * 0.15, sin(_t * 0.9 + 1.0) * 0.35, 0.0)
	var local := _anchor_local + Vector3(0, -HOSE_LENGTH * 0.18, HOSE_LENGTH * 0.98) + sway
	var basket := xf * local
	if delta > 0.0:
		_vel = (basket - _prev_basket) / delta if _prev_basket != Vector3.ZERO else tanker.linear_velocity
	_prev_basket = basket
	var back := (basket - anchor)
	_basket.global_position = basket
	_basket.global_basis = Basis.looking_at(-back.normalized(), xf.basis.y)
	# hortum: çıkıştan sepete
	_hose.global_position = (anchor + basket) * 0.5
	var dir := back.normalized()
	var side := dir.cross(xf.basis.y).normalized()
	_hose.global_basis = Basis(side, dir, side.cross(dir)).scaled_local(Vector3(1, back.length(), 1))
	_lamp_mat.albedo_color = (Color(0.3, 1.0, 0.4) if flowing else Color(1.0, 0.8, 0.2)) * 2.0
	flowing = false
