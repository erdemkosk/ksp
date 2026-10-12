extends Node
## Floating origin: odak noktası orijinden uzaklaşınca tüm dünyayı geri kaydırır.
## 32-bit float hassasiyet kaybını (titreme) önler. Küre gezegende üç eksende kaydırır;
## gezegen merkezi (Planet) 64-bit olarak birlikte güncellenir.

signal shifted(shift: Vector3)

const THRESHOLD := 1000.0

## Toplam kaydırma (64-bit). Gerçek konum = yerel konum + offset.
var offset_x := 0.0
var offset_y := 0.0
var offset_z := 0.0
var world_root: Node3D


func check(focus: Vector3) -> void:
	if world_root == null:
		return
	if focus.length() < THRESHOLD:
		return
	_shift_world(focus)


## Dünyayı başlangıç konumuna geri getirir (pistte yeniden doğma için).
func reset_world() -> void:
	if offset_x == 0.0 and offset_y == 0.0 and offset_z == 0.0:
		return
	_shift_world(Vector3(-offset_x, -offset_y, -offset_z))
	offset_x = 0.0
	offset_y = 0.0
	offset_z = 0.0
	Planet.reset()
	shifted.emit(Vector3.ZERO)


func _shift_world(shift: Vector3) -> void:
	for child in world_root.get_children():
		if child is Node3D and not child.is_in_group("origin_fixed"):
			child.global_position -= shift
			child.reset_physics_interpolation()
	offset_x += shift.x
	offset_y += shift.y
	offset_z += shift.z
	Planet.shift(shift)
	shifted.emit(shift)
