class_name Debris
extends RigidBody3D
## Uçaktan kopan parça(lar). Kendi kütlesi, yerçekimi, hava ve su direnciyle düşer.
## Parça düğümleri ve çarpışma şekilleri araçtan buraya taşınır (görsel olarak aynen kalır).

const LIFETIME := 90.0

var parts: Array[Part] = []
var _age := 0.0


func _ready() -> void:
	gravity_scale = 0.0
	continuous_cd = true
	collision_layer = 2
	collision_mask = 1
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.4


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	var com := global_transform * center_of_mass
	apply_central_force(Planet.gravity_at(com) * mass)
	# kaba hava direnci: parça boyutlarından ön alan
	var v := linear_velocity - Weather.wind_at(com)
	var speed := v.length()
	if speed > 1.0:
		var area := 0.0
		for part in parts:
			area += part.size.x * part.size.y * 0.5 + part.size.z * 0.3
		var rho := Atmosphere.density(Planet.altitude(com))
		apply_central_force(-v / speed * 0.5 * rho * speed * speed * area * 0.6)
	for part in parts:
		Hydro.apply(self, part, delta)
