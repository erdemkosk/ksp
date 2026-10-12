class_name SkyController
extends Node
## Ortam: gökyüzü, güneş, ay, gece, sis, yağmur, şimşek, uzay.
## Güneş gezegen eksenine göre döner (Weather.clock); gece-gündüz kameranın konumuna göre
## doğal olarak oluşur: doğuya uçarsan gün doğumuna yetişirsin.

const DAY_ZENITH := Color(0.15, 0.34, 0.70)
const DAY_HORIZON := Color(0.64, 0.76, 0.89)
const SUNSET_ZENITH := Color(0.13, 0.19, 0.42)
const SUNSET_HORIZON := Color(0.98, 0.58, 0.36)
const NIGHT_ZENITH := Color(0.004, 0.008, 0.02)
const NIGHT_HORIZON := Color(0.02, 0.035, 0.07)
const STORM_GREY := Color(0.42, 0.45, 0.48)

var terrain: Terrain
var clouds: VolumetricClouds

var _env: Environment
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _rain: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _flash := 0.0
var _next_flash := 6.0
var _prev_cam_pos := Vector3.ZERO

## Diğer sistemler için (ışıklar, köy pencereleri): 0 gündüz, 1 gece
var night := 0.0

signal lightning


func _ready() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://world/sky.gdshader")
	var cloud_noise := FastNoiseLite.new()
	cloud_noise.frequency = 0.008
	cloud_noise.fractal_octaves = 6
	var cloud_tex := NoiseTexture2D.new()
	cloud_tex.width = 1024
	cloud_tex.height = 1024
	cloud_tex.seamless = true
	cloud_tex.noise = cloud_noise
	_sky_mat.set_shader_parameter("cloud_noise", cloud_tex)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# güneş sürekli hareket ettiği için yansıma haritası her karede güncellenir (küçük tutulur)
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = Color(0.05, 0.07, 0.12)
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.glow_enabled = true
	_env.glow_intensity = 0.35
	_env.glow_bloom = 0.03
	_env.glow_hdr_threshold = 2.5
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_aerial_perspective = 0.75
	_env.fog_sky_affect = 0.0
	_env.fog_sun_scatter = 0.25
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 900.0
	_sun.directional_shadow_blend_splits = true
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 0.9)
	_moon.shadow_enabled = false
	add_child(_moon)

	_build_rain()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c: Dictionary = Weather.current
	var dark: float = c["dark"]
	var cp := cam.global_position
	var frame := Planet.local_basis(cp)
	var up := frame.y
	var alt := maxf(Planet.altitude(cp), 0.0)
	var space := smoothstep(12000.0, 60000.0, alt)

	# Güneş ve yerel yüksekliği
	var sun_dir := Weather.sun_direction()
	var sun_elev := rad_to_deg(asin(clampf(sun_dir.dot(up), -1.0, 1.0)))
	var dip := acos(clampf(Planet.RADIUS / (Planet.RADIUS + alt), -1.0, 1.0))
	var elev_eff := sun_elev + rad_to_deg(dip)   # yükseldikçe güneş daha geç batar
	night = 1.0 - smoothstep(-10.0, 3.0, elev_eff)
	var twilight := 1.0 - smoothstep(2.0, 18.0, elev_eff)   # gün doğumu/batımı renkleri

	_sun.global_basis = Basis.looking_at(-sun_dir, Planet.axis if absf(sun_dir.dot(Planet.axis)) < 0.95 else Vector3.RIGHT)
	var sun_color := Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.5, 0.25), twilight * (1.0 - space))
	var sun_visible := smoothstep(-3.0, 3.0, elev_eff)
	_sun.light_color = sun_color
	_sun.light_energy = 1.25 * lerpf(float(c["sun"]), 1.0, space) * sun_visible
	_sun.shadow_opacity = clampf(float(c["sun"]) * 1.1, 0.2, 1.0)
	_sun.visible = sun_visible > 0.001

	# Ay: güneşin neredeyse tersinde
	var moon_dir := sun_dir.rotated(Planet.axis, deg_to_rad(165.0))
	var moon_elev := moon_dir.dot(up)
	_moon.global_basis = Basis.looking_at(-moon_dir, Planet.axis)
	_moon.light_energy = 0.12 * night * smoothstep(-0.05, 0.1, moon_elev) * (1.0 - dark * 0.8)
	_moon.visible = _moon.light_energy > 0.001

	# Gök renkleri; kapalı havada griye çekilir
	var zenith := DAY_ZENITH.lerp(SUNSET_ZENITH, twilight).lerp(NIGHT_ZENITH, night)
	var horizon := DAY_HORIZON.lerp(SUNSET_HORIZON, twilight * (1.0 - night * 0.7)).lerp(NIGHT_HORIZON, night)
	zenith = zenith.lerp(STORM_GREY * 0.8 * (1.0 - night * 0.9), dark * (1.0 - space))
	horizon = horizon.lerp(STORM_GREY * (1.0 - night * 0.9), dark * 0.9 * (1.0 - space))
	_sky_mat.set_shader_parameter("zenith_color", zenith)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("sun_tint", sun_color)
	_sky_mat.set_shader_parameter("local_up", up)
	_sky_mat.set_shader_parameter("local_east", frame.x)
	_sky_mat.set_shader_parameter("local_north", -frame.z)
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", moon_dir)
	_sky_mat.set_shader_parameter("star_axis", Planet.axis)
	_sky_mat.set_shader_parameter("star_angle", Weather.clock / 24.0 * TAU)
	_sky_mat.set_shader_parameter("night", night)
	_sky_mat.set_shader_parameter("space", space)
	_sky_mat.set_shader_parameter("horizon_dip", sin(dip))
	# gökteki 2B katman artık sadece ince yüksek sirüs; asıl bulutlar hacimsel
	_sky_mat.set_shader_parameter("coverage", float(c["clouds"]) * 0.35)
	_sky_mat.set_shader_parameter("darkness", dark)
	_sky_mat.set_shader_parameter("cloud_fade", 1.0 - smoothstep(3000.0, 6000.0, alt))

	# Sis: yükseldikçe incelir, gece kararır
	var light_level := clampf(0.06 + (1.0 - night) * (0.35 + float(c["sun"]) * 0.6), 0.04, 1.0)
	_env.fog_density = float(c["fog"]) * exp(-alt / 5000.0)
	_env.fog_light_color = horizon * light_level / maxf(horizon.get_luminance(), 0.05) * 0.6
	_env.ambient_light_sky_contribution = 1.0 - night * 0.5
	_env.ambient_light_energy = lerpf(1.0, 0.7, dark)

	# Zemin ve deniz
	if terrain:
		terrain.material.set_shader_parameter("wetness", c["wet"])
		terrain.ocean_material.set_shader_parameter("waves", c["waves"])
		terrain.ocean_material.set_shader_parameter("darkness", maxf(dark, night * 0.6))
		terrain.ocean_material.set_shader_parameter("sky_zenith", zenith)
		terrain.ocean_material.set_shader_parameter("sky_horizon", horizon)
		terrain.ocean_material.set_shader_parameter("sun_dir", sun_dir)
		terrain.ocean_material.set_shader_parameter("sun_color", sun_color)
		terrain.ocean_material.set_shader_parameter("sun_strength", _sun.light_energy * (1.0 - dark * 0.9))
		TerrainProps.set_night(night)
		Towns.set_night(night)

	_update_clouds(delta, c, zenith, horizon, sun_dir, sun_color, dark)
	_update_rain(cam, delta, float(c["rain"]) * (1.0 - smoothstep(4000.0, 8000.0, alt)))
	_update_lightning(delta, float(c["rain"]))


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 12000
	_rain.lifetime = 1.2
	_rain.local_coords = true
	_rain.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	_rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(45, 30, 45)
	_rain_mat.gravity = Vector3.ZERO
	_rain_mat.direction = Vector3.DOWN
	_rain_mat.spread = 2.0
	_rain_mat.initial_velocity_min = 38.0
	_rain_mat.initial_velocity_max = 44.0
	_rain_mat.particle_flag_align_y = true
	_rain.process_material = _rain_mat
	var drop := BoxMesh.new()
	drop.size = Vector3(0.015, 0.9, 0.015)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	drop.material = mat
	_rain.draw_pass_1 = drop
	_rain.emitting = false
	add_child(_rain)


func _update_rain(cam: Camera3D, delta: float, rain: float) -> void:
	var cam_vel := (cam.global_position - _prev_cam_pos) / maxf(delta, 0.001)
	_prev_cam_pos = cam.global_position
	if cam_vel.length() > 400.0:  # ışınlanma (floating origin / yeniden doğma)
		cam_vel = Vector3.ZERO
	_rain.emitting = rain > 0.05
	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	if not _rain.emitting:
		return
	# Yerel koordinatta: yağmurun kameraya göre hızı = rüzgar + düşüş - kamera hızı
	var up := Planet.up_at(cam.global_position)
	var rel := Weather.wind_at(cam.global_position) - up * 40.0 - cam_vel
	rel = rel.limit_length(160.0)
	_rain_mat.direction = rel.normalized()
	_rain_mat.initial_velocity_min = rel.length() * 0.95
	_rain_mat.initial_velocity_max = rel.length() * 1.05
	_rain.global_position = cam.global_position - rel.normalized() * 25.0


func _update_lightning(delta: float, rain: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		_sun.visible = true
		_sun.light_energy += 4.0 * clampf(_flash / 0.12, 0.0, 1.0)
		_sun.light_color = _sun.light_color.lerp(Color(0.8, 0.85, 1.0), 0.7)
	if rain < 0.6:
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = randf_range(4.0, 14.0)
		_flash = 0.12
		lightning.emit()


func _update_clouds(delta: float, c: Dictionary, zenith: Color, horizon: Color, sun_dir: Vector3, sun_color: Color, dark: float) -> void:
	if clouds == null:
		return
	var m := clouds.material
	m.set_shader_parameter("cloud_base", c["cloud_base"])
	m.set_shader_parameter("cloud_top", c["cloud_top"])
	m.set_shader_parameter("coverage", c["cloud_cov"])
	m.set_shader_parameter("density", c["cloud_density"])
	m.set_shader_parameter("darkness", dark)
	# gece bulutları ayla, soğuk mavi-gri tonla aydınlanır
	var moon_dir := sun_dir.rotated(Planet.axis, deg_to_rad(165.0))
	m.set_shader_parameter("sun_dir", sun_dir if night < 0.5 else moon_dir)
	m.set_shader_parameter("sun_color", sun_color.lerp(Color(0.55, 0.62, 0.8), night))
	m.set_shader_parameter("sun_strength", _sun.light_energy + _moon.light_energy * 0.5)
	m.set_shader_parameter("sky_zenith", zenith)
	m.set_shader_parameter("sky_horizon", horizon)
	var cam := get_viewport().get_camera_3d()
	clouds.advance(delta, Weather.wind_at(cam.global_position) if cam else Vector3.ZERO)
