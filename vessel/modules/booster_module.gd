class_name BoosterModule
extends PartModule
## Katı yakıtlı kalkış roketi (JATO): eylem panelinden bir kez ateşlenir, kısılamaz,
## yakıtı bitene kadar tam itki verir (parçanın -Z yönünde). Hava alığı ve marş istemez.
## Bitince ölü ağırlık ve sürükleme olarak kalır.

var thrust_max := 30000.0
var burn_time := 10.0
var capacity := 120.0      ## katı yakıt (kg)
var propellant := 120.0
var lit := false
var thrust := 0.0

var _outer: GeometryInstance3D
var _core: GeometryInstance3D


func setup(p: Dictionary) -> void:
	thrust_max = p.get("thrust", thrust_max)
	burn_time = p.get("burn_time", burn_time)
	capacity = p.get("propellant", capacity)
	propellant = capacity


func on_attached() -> void:
	_outer = part.get_node_or_null("Visual/Exhaust")
	_core = part.get_node_or_null("Visual/ExhaustCore")


## Ateşle (yalnız bir kez). Başarılıysa true.
func ignite() -> bool:
	if lit or propellant <= 0.0 or part.submerged > 0.5:
		return false
	lit = true
	return true


func burning() -> bool:
	return lit and propellant > 0.0


func physics_tick(delta: float) -> void:
	thrust = 0.0
	if not burning():
		return
	propellant = maxf(propellant - capacity / burn_time * delta, 0.0)
	thrust = thrust_max * lerpf(0.5, 1.0, part.health_ratio())
	var dir := -part.global_basis.z
	vessel.add_force_at(dir * thrust, part.global_position)
	part.aero_load += dir * thrust


func extra_mass() -> float:
	return propellant


func _process(_delta: float) -> void:
	if part == null:
		return
	var on := burning()
	for g in [_outer, _core]:
		if g:
			g.visible = on
			if on:
				g.set_instance_shader_parameter("power", 1.0)
				g.set_instance_shader_parameter("afterburner", 0.6)
