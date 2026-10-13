class_name FlakShell
extends Node3D
## Gemi baş topunun uçaksavar mermisi: balistik uçar (yerçekimi + hafif sürükleme), yakınlık
## tapası hedefe en çok yaklaştığı anda (ya da zaman tapası dolunca) patlar; parça tesiri
## Damage.explosion ile. Dünya kökünün çocuğu: kayan orijinle birlikte kayar.

const DRAG_K := 0.00008            ## 76 mm mermi: 20 mm'den çok daha az sürüklenir (1/m)
const BURST_R := 45.0
const BURST_DMG := 260.0
const PROX := 18.0                 ## yakınlık tapası (m)

static var bursts := 0             ## testler için

var velocity := Vector3.ZERO
var target: Vessel
var fuse_t := 8.0
var _age := 0.0
var _prev_d := INF


## Mermi `d` metreye kaç saniyede varır (v² sürüklemesi).
static func flight_time(d: float, v0: float) -> float:
	return (exp(DRAG_K * d) - 1.0) / (DRAG_K * v0)


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 6
	s.rings = 3
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.7, 0.3) * 3.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	_age += delta
	var pos := global_position
	velocity += Planet.gravity_at(pos) * delta
	velocity -= velocity * velocity.length() * DRAG_K * delta
	global_position = pos + velocity * delta
	if is_instance_valid(target) and not target.parts.is_empty():
		var d := target.com_global().distance_to(global_position)
		if d < PROX or (d < 100.0 and d > _prev_d):
			_burst()
			return
		_prev_d = d
	if _age >= fuse_t:
		_burst()
	elif Planet.altitude(global_position) < 0.0:
		queue_free()


func _burst() -> void:
	bursts += 1
	if Game.args.has("navaltest") and is_instance_valid(target) and bursts % 4 == 0:
		var rel := global_position - target.com_global()
		print("NAVAL: flak patladı, hedefe %.0f m (dikey %.0f, ileri %.0f) yaş %.1f" % [rel.length(), rel.dot(Planet.up_at(global_position)), rel.dot(target.linear_velocity.normalized()), _age])
	Damage.explosion(global_position, BURST_R, BURST_DMG, null)
	queue_free()
