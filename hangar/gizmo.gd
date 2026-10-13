class_name HangarGizmo
extends Node3D
## Hangar tutamaçları (KSP'nin 2 / 3 araçları): seçili parçanın üstünde
##   • KAYDIR: X (kırmızı), Y (yeşil), Z (mavi) okları — sürükleyince o eksende kayar
##   • DÖNDÜR: üç halka — sürükleyince o eksen çevresinde döner
## Uçak uzayında durur (hangar uçağı döndürmez: eksenler uçağın eksenleri). Ekranda hep aynı
## boyda görünsün diye kameraya uzaklıkla ölçeklenir. Seçim ekran uzayında yapılır (fizik yok).

enum Mode { NONE, MOVE, ROTATE }
const COLORS := [Color(1.0, 0.3, 0.25), Color(0.35, 1.0, 0.4), Color(0.3, 0.55, 1.0)]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const ARROW_LEN := 1.0
const RING_R := 0.85

var mode := Mode.NONE
var hover := -1
var size_k := 1.0
var _arrows: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	for i in 3:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = COLORS[i]
		m.no_depth_test = true
		m.render_priority = 20
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats.append(m)
		# ok: gövde + uç (CylinderMesh +Y ekseninde)
		var arrow := Node3D.new()
		var shaft := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.025
		sm.bottom_radius = 0.025
		sm.height = ARROW_LEN * 0.8
		shaft.mesh = sm
		shaft.position = Vector3(0, ARROW_LEN * 0.4, 0)
		var tip := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.0
		tm.bottom_radius = 0.075
		tm.height = ARROW_LEN * 0.22
		tip.mesh = tm
		tip.position = Vector3(0, ARROW_LEN * 0.89, 0)
		for mi in [shaft, tip]:
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arrow.add_child(mi)
		# +Y → eksen
		arrow.basis = _basis_from_y(AXES[i])
		add_child(arrow)
		_arrows.append(arrow)
		# halka (TorusMesh XZ düzleminde, ekseni Y) → eksene dik düzlem
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = RING_R - 0.025
		tor.outer_radius = RING_R + 0.025
		tor.rings = 48
		tor.ring_segments = 6
		ring.mesh = tor
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.basis = _basis_from_y(AXES[i])
		add_child(ring)
		_rings.append(ring)
	set_mode(Mode.NONE)


static func _basis_from_y(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := Vector3.UP.cross(y) if absf(y.y) < 0.99 else Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func set_mode(m: int) -> void:
	mode = m
	visible = m != Mode.NONE
	for a in _arrows:
		a.visible = m == Mode.MOVE
	for r in _rings:
		r.visible = m == Mode.ROTATE


## Ekranda sabit boy: kameraya uzaklığın ~%9'u.
func fit(cam: Camera3D) -> void:
	size_k = maxf(cam.global_position.distance_to(global_position) * 0.09, 0.4)
	scale = Vector3.ONE * size_k
	for i in 3:
		var hot := i == hover
		_mats[i].albedo_color = COLORS[i].lightened(0.45) if hot else COLORS[i]


## Fare altındaki tutamaç ekseni (-1 yok).
func pick(cam: Camera3D, mouse: Vector2) -> int:
	if mode == Mode.NONE:
		return -1
	var o := global_position
	var best := -1
	var best_d := 14.0 if mode == Mode.MOVE else 10.0
	for i in 3:
		var a: Vector3 = AXES[i]
		var d := INF
		if mode == Mode.MOVE:
			var p1 := o + a * ARROW_LEN * size_k
			if cam.is_position_behind(o) or cam.is_position_behind(p1):
				continue
			d = _seg_dist(mouse, cam.unproject_position(o), cam.unproject_position(p1))
		else:
			var b := _basis_from_y(a)
			var prev := Vector2.INF
			for k in 49:
				var t := TAU * k / 48.0
				var wp := o + (b.x * cos(t) + b.z * sin(t)) * RING_R * size_k
				if cam.is_position_behind(wp):
					prev = Vector2.INF
					continue
				var sp := cam.unproject_position(wp)
				if prev != Vector2.INF:
					d = minf(d, _seg_dist(mouse, prev, sp))
				prev = sp
		if d < best_d:
			best_d = d
			best = i
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Ok sürüklemesi: farenin ekranda eksen yönündeki ilerlemesi → metre (uçak uzayında).
func drag_move(cam: Camera3D, axis: int, from_mouse: Vector2, mouse: Vector2) -> float:
	var o := global_position
	var s0 := cam.unproject_position(o)
	var ax: Vector3 = AXES[axis]
	var s1 := cam.unproject_position(o + ax * size_k)
	var dir := s1 - s0                      # 1 * size_k metre = bu kadar piksel
	if dir.length_squared() < 4.0:
		return 0.0
	return (mouse - from_mouse).dot(dir) / dir.length_squared() * size_k


## Halka sürüklemesi: merkez çevresinde farenin açısı → radyan (eksenin sağ el kuralına göre).
func drag_angle(cam: Camera3D, axis: int, from_mouse: Vector2, mouse: Vector2) -> float:
	var c := cam.unproject_position(global_position)
	var a0 := (from_mouse - c).angle()
	var a1 := (mouse - c).angle()
	var da := wrapf(a1 - a0, -PI, PI)
	# ekranda y aşağı: saat yönü pozitif açı. Eksen kameraya bakıyorsa sağ el kuralı saat yönü tersi.
	var ax: Vector3 = AXES[axis]
	var toward: bool = ax.dot(cam.global_position - global_position) > 0.0
	return -da if toward else da
