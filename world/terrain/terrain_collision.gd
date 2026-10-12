class_name TerrainCollision
extends StaticBody3D
## Hedefin (uçak/pilot) altında hareket eden heightmap çarpışma yaması.
## Yama yerel teğet düzlemde durur (512 m'de küre eğriliği ~5 cm, ihmal edilebilir);
## yükseklikler bu düzleme göre ölçülür. İş parçacığında hesaplanır.

const SIZE := 65          ## örnek sayısı (2^n + 1, Jolt heightfield için)
const SPACING := 8.0
const RECENTER := 96.0

var target: Node3D

var _shape := HeightMapShape3D.new()
## Yama merkezinin gezegene göre konumu (64-bit) ve yerel eksenleri
var _center := PackedFloat64Array([0, 0, 0])
var _basis := Basis()
var _has_patch := false
var _task := -1
var _pending := {}


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape.map_width = SIZE
	_shape.map_depth = SIZE
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	# Yükseklikler SPACING'e bölünüp saklanır, düzgün ölçek geri çevirir.
	cs.scale = Vector3.ONE * SPACING
	add_child(cs)


func _physics_process(_delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply(_pending)
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	if _task == -1 and _distance_to(target.global_position) > RECENTER:
		var req := _request(target.global_position)
		_task = WorkerThreadPool.add_task(_compute.bind(req))


## Doğma anında olduğu gibi, beklemeden kur.
func rebuild_now(world_pos: Vector3) -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	var req := _request(world_pos)
	_compute(req)
	_apply(_pending)


## Floating origin kaydırınca yeniden yerleştir.
func reposition() -> void:
	if _has_patch:
		var c := Planet.center()
		global_transform = Transform3D(_basis, Vector3(_center[0] + c.x, _center[1] + c.y, _center[2] + c.z))


func _distance_to(world_pos: Vector3) -> float:
	if not _has_patch:
		return INF
	var r := Planet.relative(world_pos)
	return Vector3(r.x - _center[0], r.y - _center[1], r.z - _center[2]).length()


## Hedefin altındaki yüzey noktası ve yerel çerçeve (64-bit).
func _request(world_pos: Vector3) -> Dictionary:
	var r := Planet.relative(world_pos)
	var l := sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
	var d := PackedFloat64Array([r.x / l, r.y / l, r.z / l])
	var up := Vector3(d[0], d[1], d[2])
	var basis := Planet.local_basis(world_pos)
	var R := TerrainGen.RADIUS
	return {"dir": d, "basis": Basis(basis.x, up, basis.z), "center": PackedFloat64Array([d[0] * R, d[1] * R, d[2] * R])}


func _compute(req: Dictionary) -> void:
	var data := PackedFloat32Array()
	data.resize(SIZE * SIZE)
	var half := (SIZE - 1) / 2
	var c: PackedFloat64Array = req["center"]
	var b: Basis = req["basis"]
	var ex := b.x
	var ez := b.z
	var up := b.y
	var R := TerrainGen.RADIUS
	for j in SIZE:
		for i in SIZE:
			var ox := (i - half) * SPACING
			var oz := (j - half) * SPACING
			var qx := c[0] + ex.x * ox + ez.x * oz
			var qy := c[1] + ex.y * ox + ez.y * oz
			var qz := c[2] + ex.z * ox + ez.z * oz
			var l := sqrt(qx * qx + qy * qy + qz * qz)
			var dx := qx / l
			var dy := qy / l
			var dz := qz / l
			var h := TerrainGen.height(Vector3(dx, dy, dz))
			var r := R + h
			# yüzey noktasının teğet düzleme göre yüksekliği
			var sx := dx * r - c[0]
			var sy := dy * r - c[1]
			var sz := dz * r - c[2]
			data[j * SIZE + i] = (sx * up.x + sy * up.y + sz * up.z) / SPACING
	_pending = {"data": data, "center": c, "basis": b}


func _apply(p: Dictionary) -> void:
	_shape.map_data = p["data"]
	_center = p["center"]
	_basis = p["basis"]
	_has_patch = true
	reposition()
