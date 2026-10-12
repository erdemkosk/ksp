class_name VolumetricClouds
extends MeshInstance3D
## Hacimsel bulut katmanı. Kameranın çocuğu olan tam ekran dörtgen; SkyController
## her karede güneş, gök rengi ve hava durumu değerlerini günceller.

var material: ShaderMaterial
var _wind := Vector3.ZERO


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mesh = quad
	material = ShaderMaterial.new()
	material.shader = preload("res://world/clouds.gdshader")
	material.set_shader_parameter("shape_tex", _noise3d(64, FastNoiseLite.TYPE_CELLULAR, 0.06, 3, 5))
	material.set_shader_parameter("detail_tex", _noise3d(32, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.12, 3, 9))
	material.set_shader_parameter("planet_radius", Planet.RADIUS)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = Vector3(0, 0, -1.0)


## Rüzgarla bulutların sürüklenmesi (yerel çerçevede biriken ofset).
func advance(delta: float, wind: Vector3) -> void:
	_wind -= wind * delta
	material.set_shader_parameter("wind_offset", _wind)
	material.set_shader_parameter("planet_center", Planet.center())


static func _noise3d(size: int, type: int, freq: float, octaves: int, seed: int) -> NoiseTexture3D:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = seed
	if type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var tex := NoiseTexture3D.new()
	tex.width = size
	tex.height = size
	tex.depth = size
	tex.seamless = true
	tex.noise = n
	return tex
