class_name Atmosphere
## Basit atmosfer modeli.

const SEA_LEVEL_DENSITY := 1.225
const SCALE_HEIGHT := 8500.0
const SPEED_OF_SOUND := 340.0


static func density(altitude: float) -> float:
	return SEA_LEVEL_DENSITY * exp(-maxf(altitude, 0.0) / SCALE_HEIGHT)


## Ses hızı civarında sürükleme artışı (transonik duvar).
static func wave_drag(mach: float) -> float:
	if mach < 0.8:
		return 1.0
	var peak := smoothstep(0.8, 1.05, mach) * 4.0
	var after := smoothstep(1.2, 2.0, mach) * 1.5
	return 1.0 + peak - after
