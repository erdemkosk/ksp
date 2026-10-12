class_name ConvoyTruck
extends GroundTarget
## Yolda ilerleyen konvoy aracı (kamyon ya da zırhlı araç). Yol, başlangıç çerçevesindeki
## (doğu, güney) noktalarıdır; konum her karede araziye oturtulur (kayan orijinden etkilenmez).
## Vurulunca durur, yanar. Yolun sonuna varan araç döner ve geri gider.

var path: Array[Vector2] = []
var speed := 11.0
var offset := 0.0             ## yol boyunca mesafe (m), konvoyda araç arası aralık için
var _seg := 0
var _t := 0.0
var _dir := 1
var _wheels: Array[Node3D] = []


static func create_truck(road: Array[Vector2], start_dist: float, armored: bool) -> ConvoyTruck:
	var t := ConvoyTruck.new()
	t.path = road
	t.hp = 500.0 if armored else 260.0
	t.unit_name = "Zırhlı araç" if armored else "Kamyon"
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.6, 7.0)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	t.add_child(cs)
	var olive := Color(0.31, 0.34, 0.24)
	if armored:
		t._hull = _mesh(t, Vector3(2.6, 1.3, 6.4), Vector3(0, 1.0, 0), olive)
		t._turret = _mesh(t, Vector3(1.4, 0.6, 1.6), Vector3(0, 1.95, 0.4), olive.darkened(0.1))
	else:
		t._hull = _mesh(t, Vector3(2.4, 1.6, 2.0), Vector3(0, 1.3, -2.4), olive)              # kabin
		_mesh(t, Vector3(2.5, 2.0, 4.4), Vector3(0, 1.6, 0.9), Color(0.36, 0.38, 0.3))           # branda
	for z in [-2.4, 0.2, 2.4]:
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 0.4
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(side * 1.25, 0.5, z)
			w.material_override = SamSite._mat(Color(0.08, 0.08, 0.08))
			t.add_child(w)
			t._wheels.append(w)
	t.offset = start_dist
	return t


func _ready() -> void:
	# başlangıç: yol boyunca offset metre ileri
	var d := offset
	while _seg < path.size() - 1:
		var l := path[_seg].distance_to(path[_seg + 1])
		if d < l:
			_t = d / l
			break
		d -= l
		_seg += 1
	_place(0.0)


func _physics_process(delta: float) -> void:
	if destroyed or path.size() < 2:
		return
	var l := maxf(path[_seg].distance_to(path[_seg + 1]), 1.0)
	_t += _dir * speed * delta / l
	if _t > 1.0:
		if _seg + 2 < path.size():
			_seg += 1
			_t -= 1.0
		else:
			_t = 1.0
			_dir = -1
	elif _t < 0.0:
		if _seg > 0:
			_seg -= 1
			_t += 1.0
		else:
			_t = 0.0
			_dir = 1
	_place(delta)
	for w in _wheels:
		w.rotate_object_local(Vector3.UP, speed * delta / 0.5)


func _place(_delta: float) -> void:
	var xz := path[_seg].lerp(path[_seg + 1], clampf(_t, 0.0, 1.0))
	var ahead := (path[_seg + 1] - path[_seg]) * _dir
	var h := maxf(Towns.road_height(xz.x, xz.y), 0.5)
	var pos := MissionManager.world_point(xz.x, xz.y, h)
	var frame := Planet.local_basis(pos)
	var yaw := atan2(-ahead.x, -ahead.y)   # 0 = kuzey (-z), x doğu
	global_transform = Transform3D(frame * Basis(Vector3.UP, yaw), pos)
