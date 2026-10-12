class_name CargoModule
extends PartModule
## Kargo bölmesi: paraşütlü yardım sandıkları. KARGO seçiliyken tetik (Space) bir sandık
## bırakır. Sandık 1.5 sn sonra paraşüt açar ve yavaşça iner; HUD bırakma noktasını gösterir.

const CRATE_MASS := 300.0

var crates := 4


func setup(p: Dictionary) -> void:
	crates = int(p.get("crates", crates))


func extra_mass() -> float:
	return crates * CRATE_MASS


var _released_this_press := false


func physics_tick(_delta: float) -> void:
	if not vessel.ctrl_fire:
		_released_this_press = false
		return
	if crates > 0 and vessel.selected_weapon == Vessel.WEAPON_CARGO and not _released_this_press and _is_first_ready():
		release()
		for m in vessel.modules:
			if m is CargoModule:
				m._released_this_press = true


func _is_first_ready() -> bool:
	for m in vessel.modules:
		if m is CargoModule and m.crates > 0:
			return m == self
	return false


func release() -> void:
	crates -= 1
	var c := CargoCrate.new()
	c.velocity = vessel.linear_velocity
	vessel.get_parent().add_child(c)
	c.global_position = part.global_transform * Vector3(0, -part.size.y * 0.5 - 0.8, part.size.z * 0.3)
	Sfx.play_at("hydraulic_thunk.ogg", part.global_position, -2.0, 0.8, 800.0)
	vessel.recalc_mass()
