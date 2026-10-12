class_name Hydro
## Su fiziği: bir gövdenin (uçak/enkaz) bir parçası deniz seviyesinin altına girince
## kaldırma kuvveti, çok güçlü su direnci, giriş darbesi (hasar) ve sıçrama.

const WATER_DENSITY := 1025.0
const IMPACT_SAFE := 12.0   ## bu dikey hızın altında suya giriş hasarsız (m/s)


static func apply(body: RigidBody3D, part: Part, delta: float) -> void:
	var p := part.global_position
	var r := (part.size.x + part.size.y + part.size.z) / 6.0   # yaklaşık yarı kalınlık
	var alt := Planet.altitude(p)
	if alt > r:
		part.submerged = 0.0
		return
	if TerrainGen.height(Planet.surface_dir(p)) >= 0.0:
		part.submerged = 0.0   # orası kara, su yok
		return
	var frac := clampf((r - alt) / (2.0 * r), 0.0, 1.0)
	var up := Planet.up_at(p)
	var com := body.global_transform * body.center_of_mass
	var v := body.linear_velocity + body.angular_velocity.cross(p - com)

	# suya giriş anı: sıçrama ve darbe
	if part.submerged <= 0.01 and frac > 0.01:
		var vn := -v.dot(up)
		if vn > 3.0 or v.length() > 25.0:
			Effects.splash(FloatingOrigin.world_root, p - up * alt, up, clampf(v.length() / 25.0, 0.5, 3.5))
			Sfx.splash(p - up * alt, clampf(v.length() / 25.0, 0.5, 3.5))
		if vn > IMPACT_SAFE and body is Vessel:
			body.damage_part(part, pow(vn - IMPACT_SAFE, 2.0) * 3.0)
	part.submerged = frac
	if frac <= 0.0:
		return

	var volume := part.size.x * part.size.y * part.size.z * 0.55
	var force := up * WATER_DENSITY * Planet.SURFACE_GRAVITY * volume * frac
	var speed := v.length()
	if speed > 0.05:
		var area := (part.size.x * part.size.y + part.size.y * part.size.z + part.size.x * part.size.z) / 3.0
		var drag := 0.5 * WATER_DENSITY * 0.7 * area * frac * speed * speed
		# tek adımda hızı tersine çevirmesin (sayısal kararlılık)
		var part_share := body.mass * part.get_mass() / maxf(_total_mass(body), 1.0)
		drag = minf(drag, part_share * speed / delta * 0.5)
		force += -v / speed * drag
	body.apply_force(force, p - body.global_position)


static func _total_mass(body: RigidBody3D) -> float:
	var total := 0.0
	for part in body.get("parts"):
		total += part.get_mass()
	return total
