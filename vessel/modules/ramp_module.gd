class_name RampModule
extends PartModule
## Arka yük rampası: kapalı başlar (kapı gövde altına oturur). Parça penceresinden (sağ tık)
## "Rampayı aç / kapat": kapı ön kenarındaki menteşeden aşağı iner, içerideki koyu kargo
## bölmesi görünür. Açıkken hava direnci artar (yavaşlatır, burnu hafif kaldırır).

const OPEN_DEG := 26.0
const RATE := 0.3                          ## 1 / sn — tam açılma ~3.3 sn
const HINGE := Vector3(0.0, -0.648, -1.2)  ## Visual uzayında (parça tanımının birimleri)

var open := false
var deploy := 0.0
var drag_area := 1.6
var _door: Node3D
var _base := Transform3D.IDENTITY


func setup(p: Dictionary) -> void:
	drag_area = p.get("drag_area", drag_area)


func on_attached() -> void:
	_door = part.get_node_or_null("Visual/Ramp")
	if _door:
		_base = _door.transform


func toggle() -> void:
	open = not open
	Sfx.play_at("gear_motor.ogg", part.global_position, -4.0, 0.8, 900.0)
	vessel.system_message.emit("Rampa açılıyor" if open else "Rampa kapanıyor")


func physics_tick(delta: float) -> void:
	var target := 1.0 if open else 0.0
	if deploy != target:
		deploy = move_toward(deploy, target, RATE * delta)
		if deploy == target:
			Sfx.play_at("hydraulic_thunk.ogg", part.global_position, -4.0, 0.9, 800.0)
		_update_visual()
	if deploy > 0.01:
		var v := vessel.air_velocity_at(part.global_position)
		var speed := v.length()
		if speed > 1.0:
			var q := 0.5 * vessel.air_density() * speed * speed
			var f := -v / speed * q * drag_area * deploy
			var at := part.global_transform * Vector3(0.0, -0.6, 0.6)
			vessel.add_force_at(f, at)
			part.aero_load += f


## Kapıyı menteşe çevresinde döndür (arka ucu aşağı).
func _update_visual() -> void:
	if _door == null:
		return
	var a := deg_to_rad(OPEN_DEG) * smoothstep(0.0, 1.0, deploy)
	_door.transform = Transform3D(Basis(Vector3.RIGHT, a), HINGE) * Transform3D(Basis.IDENTITY, -HINGE) * _base
