class_name ChuteModule
extends PartModule
## Fren paraşütü: yerdeyken (tekerler yerde, > 20 m/s) fren basılınca açılır, uçağı hızla
## yavaşlatır. Tek kullanımlık: 8 m/s altında ya da 110 m/s üstünde (yırtılır) bırakılır.
## Eylem panelinden (1-9) istenen an açılabilir ya da kesilebilir.

var area := 18.0
var cd := 1.3
var state := 0          ## 0 paket, 1 açık, 2 bırakıldı
var _open := 0.0
var _canopy: MeshInstance3D


func setup(p: Dictionary) -> void:
	area = p.get("area", area)


func on_attached() -> void:
	_canopy = MeshInstance3D.new()
	_canopy.mesh = MeshFactory.lathe([Vector2(0.0, 0.0), Vector2(1.5, 2.2), Vector2(2.3, 2.5), Vector2(2.6, 2.3)], 20)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.5, 0.15)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	_canopy.material_override = m
	_canopy.visible = false
	part.add_child(_canopy)


func deploy() -> void:
	if state != 0:
		return
	state = 1
	Sfx.play_at("canopy_motor.ogg", part.global_position, -2.0, 1.6, 1500.0)
	vessel.system_message.emit("Fren paraşütü açıldı")


func release() -> void:
	if state == 1:
		state = 2
		vessel.system_message.emit("Paraşüt kesildi")


func _grounded() -> bool:
	for m in vessel.modules:
		if m is LandingGearModule and m.grounded:
			return true
	return false


func physics_tick(delta: float) -> void:
	var v := vessel.air_velocity_at(part.global_position)
	var speed := v.length()
	if state == 0 and vessel.ctrl_brakes and speed > 20.0 and _grounded():
		deploy()
	if state == 1 and (speed < 8.0 or speed > 110.0):
		state = 2
		vessel.system_message.emit("Paraşüt bırakıldı" if speed < 8.0 else "Paraşüt yırtıldı!")
	_open = move_toward(_open, 1.0 if state == 1 else 0.0, delta * 2.5)
	_canopy.visible = _open > 0.01
	if _open <= 0.01:
		return
	# kubbe hızın tersine, 8 m arkada, şişerek açılır
	var back := -v.normalized() if speed > 1.0 else part.global_basis.z
	_canopy.global_position = part.global_position + back * (2.0 + 8.0 * _open)
	# kubbenin ağzı (+z) uçağa baksın
	_canopy.global_basis = Basis.looking_at(back, Planet.up_at(part.global_position)).scaled(Vector3.ONE * maxf(_open, 0.05))
	var f := -v * speed * 0.5 * vessel.air_density() * cd * area * _open
	vessel.add_force_at(f, part.global_position)
	part.aero_load += f
