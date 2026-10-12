class_name DamageFx
extends Node3D
## Parça hasarının görünür izleri (parçanın çocuğu; parça koparsa enkazla birlikte gider):
##   • is / yanık: sağlık düştükçe parçanın üstüne koyulaşan lekeli kararma
##   • duman: %50 altında koyu duman izi
##   • yangın: motor %40 / dolu yakıt tankı %30 altında alev, ışık; yangın parçayı yakmaya devam eder
##   • yakıt sızıntısı: delik tanktan beyaz buhar izi, yakıt azalır

static var _scorch := []            # 3 kademe kaplama malzemesi

var part: Part
var _level := -1
var _smoke: PuffTrail
var _fire: PuffTrail
var _leak: PuffTrail
var _light: OmniLight3D


static func for_part(p: Part) -> DamageFx:
	for c in p.get_children():
		if c is DamageFx:
			return c
	var fx := DamageFx.new()
	fx.part = p
	p.add_child(fx)
	return fx


static func _scorch_mat(level: int) -> Material:
	if _scorch.is_empty():
		var noise := FastNoiseLite.new()
		noise.frequency = 0.04
		noise.fractal_octaves = 4
		for i in 3:
			var tex := NoiseTexture2D.new()
			tex.width = 256
			tex.height = 256
			tex.seamless = true
			tex.noise = noise
			var g := Gradient.new()
			var cut: float = [0.62, 0.48, 0.32][i]
			g.set_color(0, Color(0.02, 0.018, 0.015, 0.0))
			g.set_offset(0, cut)
			g.set_color(1, Color(0.02, 0.018, 0.015, 0.92))
			g.set_offset(1, cut + 0.12)
			tex.color_ramp = g
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = tex
			m.roughness = 0.95
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.6
			m.render_priority = 1
			_scorch.append(m)
	return _scorch[level]


## Sağlık değişince çağrılır.
func refresh() -> void:
	var h := part.health_ratio()
	var level := -1
	if h < 0.25:
		level = 2
	elif h < 0.5:
		level = 1
	elif h < 0.8:
		level = 0
	if level != _level:
		_level = level
		part.damage_overlay = _scorch_mat(level) if level >= 0 else null
		_set_overlay(part.damage_overlay)
	if h < 0.5 and _smoke == null:
		_smoke = PuffTrail.create(self, Vector3.ZERO, "smoke")
	var engine := _has(EngineModule)
	var tank := _tank()
	var burning := (engine and h < 0.4) or (tank != null and tank.fuel > 30.0 and h < 0.3)
	if burning and _fire == null:
		_fire = PuffTrail.create(self, Vector3.ZERO, "fire")
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.omni_range = 14.0
		add_child(_light)
	if tank != null and h < 0.6 and tank.fuel > 0.0 and _leak == null:
		_leak = PuffTrail.create(self, Vector3.ZERO, "leak")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(part):
		return
	if _light:
		_light.light_energy = randf_range(2.0, 4.5)
	var v := part.vessel
	# yangın parçayı yakar (sonunda patlar)
	if _fire and is_instance_valid(v) and part in v.parts:
		v.damage_part(part, 4.0 * delta)
	# sızıntı: delikten yakıt akar
	if _leak:
		var tank := _tank()
		if tank and tank.fuel > 0.0:
			tank.fuel = maxf(tank.fuel - (1.0 - part.health_ratio()) * 6.0 * delta, 0.0)
		else:
			_leak.emitting = false


func _has(t: Variant) -> bool:
	for m in part.modules:
		if is_instance_of(m, t):
			return true
	return false


func _tank() -> FuelTankModule:
	for m in part.modules:
		if m is FuelTankModule:
			return m
	return null


func _set_overlay(mat: Material) -> void:
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GPUParticles3D or n is CockpitSwitch:
			continue
		stack.append_array(n.get_children())
		if n is MeshInstance3D and not (n.material_override is ShaderMaterial and not n.material_override.has_meta("paint")):
			n.material_overlay = mat

