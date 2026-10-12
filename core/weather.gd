extends Node
## Hava durumu ve zaman (autoload: Weather).
## Görsel ayarlar SkyController'da uygulanır; rüzgar/türbülans aerodinamiğe girer.
## Hava ayarı değişince değerler birkaç saniyede yumuşakça geçiş yapar.
##
## Zaman: `clock` havaalanı meridyenindeki güneş saatidir (0..24) ve sürekli akar.
## Güneş gezegen eksenine göre döner; doğuya uçtukça yerel saat ilerler.

signal changed

enum Preset { CLEAR, SCATTERED, OVERCAST, STORM, FOG }

const PRESETS := {
	Preset.CLEAR: {"name": "Açık", "clouds": 0.12, "dark": 0.0, "fog": 0.00003, "rain": 0.0,
		"wind": 3.0, "gust": 0.5, "turb": 0.05, "sun": 1.0, "wet": 0.0, "waves": 0.6,
		"cloud_base": 1800.0, "cloud_top": 3200.0, "cloud_cov": 0.22, "cloud_density": 0.025},
	Preset.SCATTERED: {"name": "Parçalı Bulutlu", "clouds": 0.42, "dark": 0.08, "fog": 0.00005, "rain": 0.0,
		"wind": 7.0, "gust": 2.0, "turb": 0.25, "sun": 0.95, "wet": 0.0, "waves": 1.0,
		"cloud_base": 1500.0, "cloud_top": 3800.0, "cloud_cov": 0.45, "cloud_density": 0.035},
	Preset.OVERCAST: {"name": "Kapalı", "clouds": 0.88, "dark": 0.5, "fog": 0.0001, "rain": 0.0,
		"wind": 10.0, "gust": 3.0, "turb": 0.45, "sun": 0.4, "wet": 0.15, "waves": 1.4,
		"cloud_base": 900.0, "cloud_top": 2600.0, "cloud_cov": 0.85, "cloud_density": 0.045},
	Preset.STORM: {"name": "Fırtına", "clouds": 1.0, "dark": 0.85, "fog": 0.00022, "rain": 1.0,
		"wind": 17.0, "gust": 7.0, "turb": 1.0, "sun": 0.15, "wet": 1.0, "waves": 2.2,
		"cloud_base": 700.0, "cloud_top": 7000.0, "cloud_cov": 0.95, "cloud_density": 0.06},
	Preset.FOG: {"name": "Sisli", "clouds": 0.7, "dark": 0.3, "fog": 0.0011, "rain": 0.0,
		"wind": 1.5, "gust": 0.3, "turb": 0.05, "sun": 0.45, "wet": 0.35, "waves": 0.4,
		"cloud_base": 150.0, "cloud_top": 900.0, "cloud_cov": 0.8, "cloud_density": 0.03},
}

## F6 ile atlanan saatler
const TIMES := [
	{"name": "Sabah", "hour": 7.0},
	{"name": "Öğle", "hour": 12.5},
	{"name": "Gün Batımı", "hour": 18.25},
	{"name": "Gece", "hour": 23.5},
]
const TIME_SCALES := [1.0, 10.0, 100.0, 1000.0]
const DAY_LENGTH := 7200.0    ## gezegenin bir günü, gerçek saniye (1x hızda)
const BLEND_RATE := 0.4       ## 1/s

var preset: Preset = Preset.SCATTERED
## Havaalanı meridyeninde güneş saati
var clock := 12.5
var time_scale_index := 0
## Rüzgarın estiği yön (radyan, 0 = kuzey)
var wind_heading := deg_to_rad(240.0)

## Anlık (geçişli) değerler
var current := {}

var _gust := Vector3.ZERO          # yerel çerçevede
var _gust_target := Vector3.ZERO
var _gust_timer := 0.0
var _turb_noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	_turb_noise.frequency = 0.012
	_turb_noise.fractal_octaves = 3
	current = PRESETS[preset].duplicate()
	if Game.args.has("weather"):
		set_preset(int(Game.args["weather"]), true)
	if Game.args.has("time"):
		set_time(int(Game.args["time"]))
	if Game.args.has("hour"):
		clock = float(Game.args["hour"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weather_cycle"):
		set_preset((preset + 1) % Preset.size())
	elif event.is_action_pressed("time_cycle"):
		_next_time_preset()


func set_preset(p: int, instant := false) -> void:
	preset = p as Preset
	if instant:
		current = PRESETS[preset].duplicate()
	changed.emit()


func set_time(index: int) -> void:
	clock = TIMES[clamp(index, 0, TIMES.size() - 1)]["hour"]
	changed.emit()


func _next_time_preset() -> void:
	for i in TIMES.size():
		if TIMES[i]["hour"] > clock + 0.25:
			set_time(i)
			return
	set_time(0)


func time_scale() -> float:
	return TIME_SCALES[time_scale_index]


func preset_name() -> String:
	return PRESETS[preset]["name"]


## Verilen konumdaki yerel güneş saati (boylama göre).
func local_hour(p: Vector3) -> float:
	return fposmod(clock + Planet.longitude_deg(p) / 15.0, 24.0)


static func format_hour(h: float) -> String:
	var hh := int(h) % 24
	var mm := int((h - floor(h)) * 60.0)
	return "%02d:%02d" % [hh, mm]


## Güneşe doğru birim yön (dünya çerçevesinde).
func sun_direction() -> Vector3:
	return Planet.sun_direction(clock)


## Hava değerleri hâlâ hedefe doğru ilerliyor mu.
func is_blending() -> bool:
	var target: Dictionary = PRESETS[preset]
	for k in target:
		if k != "name" and absf(current[k] - target[k]) > 0.0005 * maxf(absf(target[k]), 0.001):
			return true
	return false


func _process(delta: float) -> void:
	_time += delta
	clock = fposmod(clock + delta * time_scale() * 24.0 / DAY_LENGTH, 24.0)
	var k := 1.0 - exp(-BLEND_RATE * delta)
	var target: Dictionary = PRESETS[preset]
	for key in target:
		if key != "name":
			current[key] = lerpf(current[key], target[key], k)

	# Ani rüzgarlar: rastgele hedefe yumuşakça yaklaşan bir vektör (yerel çerçevede)
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		_gust_timer = randf_range(1.5, 5.0)
		var g: float = current["gust"]
		_gust_target = Vector3(randf_range(-g, g), randf_range(-g, g) * 0.3, randf_range(-g, g))
	_gust = _gust.lerp(_gust_target, 1.0 - exp(-0.8 * delta))


## Bir noktadaki rüzgar hızı (m/s, dünya çerçevesinde). Konuma bağlı türbülans uçağın
## farklı parçalarına farklı rüzgar verir ve gerçekçi sarsıntı oluşturur.
func wind_at(pos: Vector3) -> Vector3:
	var frame := Planet.local_basis(pos)
	var alt := Planet.altitude(pos)
	var base := Vector3(sin(wind_heading), 0.0, -cos(wind_heading)) * float(current["wind"])
	var height_factor := (0.55 + 0.45 * smoothstep(0.0, 800.0, alt)) * (1.0 - smoothstep(20000.0, 40000.0, alt))
	var w := (base + _gust) * height_factor
	var turb: float = current["turb"]
	if turb > 0.01:
		var s := _time * 15.0
		var a := 7.0 * turb * (1.0 - smoothstep(1500.0, 6000.0, alt))
		w += Vector3(
			_turb_noise.get_noise_3d(pos.x, pos.y, pos.z + s),
			_turb_noise.get_noise_3d(pos.x + 500.0, pos.y, pos.z - s) * 0.7,
			_turb_noise.get_noise_3d(pos.x, pos.y + 500.0, pos.z + s)) * a
	return frame * w


## Türbülans şiddeti 0..1 (kamera sarsıntısı için).
func turbulence() -> float:
	return float(current.get("turb", 0.0))
