class_name FlightSave
## Uçuş ortası kayıt (F9) ve devam (ana menü → Devam et / F10).
## Saklanan: uçak tasarımı, mutlak konum (kayan orijinden bağımsız, 64-bit), duruş, hızlar,
## parça sağlıkları, yakıt / mühimmat, takım, gaz, motor durumu, hava ve saat, pilot, görev.
## Kopan parçalar yüklemede yeniden kopar (enkaz bırakmadan).

const PATH := "user://flight_save.json"


static func _path() -> String:
	return "user://flight_save_test.json" if Crew._testing() else PATH


static func exists() -> bool:
	return FileAccess.file_exists(_path())


static func info() -> String:
	if not exists():
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if typeof(d) != TYPE_DICTIONARY:
		return ""
	return "%s · %s · %d m" % [d.get("craft", {}).get("name", "Uçak"), d.get("when", ""), int(d.get("alt", 0))]


static func save(main: Node) -> bool:
	var v: Vessel = main.vessel
	if not is_instance_valid(v) or v.parts.is_empty() or not v.has_pilot():
		return false
	var p := v.global_position
	var parts := []
	for part in v.parts:
		var st := {"bi": int(part.get_meta("bi", -1)), "hp": part.hp}
		for m in part.modules:
			if m is FuelTankModule:
				st["fuel"] = m.fuel
			elif m is GunModule:
				st["ammo"] = m.ammo
			elif m is FlareModule:
				st["flares"] = m.count
			elif m is MissileModule or m is BombModule:
				st["loaded"] = m.loaded
		parts.append(st)
	var q := v.global_basis.get_rotation_quaternion()
	var d := {
		"version": 1,
		"when": Time.get_datetime_string_from_system(false, true),
		"craft": main.spawned_craft,
		"pos": [p.x + FloatingOrigin.offset_x, p.y + FloatingOrigin.offset_y, p.z + FloatingOrigin.offset_z],
		"rot": [q.x, q.y, q.z, q.w],
		"vel": _v(v.linear_velocity), "ang": _v(v.angular_velocity),
		"alt": v.altitude(),
		"parts": parts,
		"gear": v.gear_down, "throttle": main.player.throttle, "running": v.engines_running(),
		"sas": v.sas, "lights": v.lights_on, "arm": v.master_arm,
		"weather": Weather.preset, "clock": Weather.clock,
		"pilot": Crew.selected, "mission": Game.mission, "time": main._time,
	}
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	return true


static func load_data() -> Dictionary:
	if not exists():
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	return d if typeof(d) == TYPE_DICTIONARY else {}


## main._spawn tamamlandıktan sonra çağrılır: durumu geri yükler.
static func apply(main: Node, d: Dictionary) -> void:
	var v: Vessel = main.vessel
	var pa: Array = d.get("pos", [0, 0, 0])
	var pos := Vector3(float(pa[0]) - FloatingOrigin.offset_x, float(pa[1]) - FloatingOrigin.offset_y, float(pa[2]) - FloatingOrigin.offset_z)
	var r: Array = d.get("rot", [0, 0, 0, 1])
	v.global_transform = Transform3D(Basis(Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3]))), pos)
	v.linear_velocity = _vec(d.get("vel", [0, 0, 0]))
	v.angular_velocity = _vec(d.get("ang", [0, 0, 0]))
	v.reset_physics_interpolation()
	# parça durumları; kayıtta olmayanlar kopmuştu
	var by_bi := {}
	for st: Dictionary in d.get("parts", []):
		by_bi[int(st.get("bi", -1))] = st
	var lost: Array[Part] = []
	for part in v.parts:
		var bi := int(part.get_meta("bi", -1))
		if not by_bi.has(bi):
			lost.append(part)
			continue
		var st: Dictionary = by_bi[bi]
		part.hp = float(st.get("hp", part.hp))
		for m in part.modules:
			if m is FuelTankModule and st.has("fuel"):
				m.fuel = float(st["fuel"])
			elif m is GunModule and st.has("ammo"):
				m.ammo = int(st["ammo"])
			elif m is FlareModule and st.has("flares"):
				m.count = int(st["flares"])
			elif (m is MissileModule or m is BombModule) and st.has("loaded"):
				m.loaded = bool(st["loaded"])
				if not m.loaded and m.part.get_node_or_null("Visual/Missile"):
					m.part.get_node("Visual/Missile").visible = false
	for part in lost:
		if part in v.parts and part != v.cockpit_part():
			v.destroy_part(part)
	# kopan parçaların enkazı kayıtta zaten düşmüştü: yeni enkaz bırakma
	for n in FloatingOrigin.world_root.get_children():
		if n is Debris:
			n.queue_free()
	v.recalc_mass()
	if bool(d.get("running", false)):
		v.set_hot()
	v.set_gear_instant(bool(d.get("gear", true)))
	v.sas = bool(d.get("sas", true))
	v.lights_on = bool(d.get("lights", false))
	v.master_arm = bool(d.get("arm", false))
	main.player.throttle = float(d.get("throttle", 0.0))
	v.parking_brake = false
	Weather.set_preset(int(d.get("weather", Weather.preset)), true)
	Weather.clock = float(d.get("clock", Weather.clock))
	for part in v.parts:
		var fx := DamageFx.for_part(part) if part.hp < part.max_hp * 0.8 else null
		if fx:
			fx.refresh()


static func _v(x: Vector3) -> Array:
	return [x.x, x.y, x.z]


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
