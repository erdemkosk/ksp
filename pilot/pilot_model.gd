class_name PilotModel
extends Node3D
## Prosedürel savaş pilotu modeli: zeytin yeşili uçuş tulumu, G-elbisesi, emniyet kemerleri,
## can yeleği, vizörlü uçuş kaskı, oksijen maskesi ve hortumu, eldiven ve botlar.
## Kollar ve bacaklar iki kemikli IK ile hedeflere uzanır; aynı sistem hem koltukta
## oturma hem yürüme pozunu üretir.
## Model uzayı: +Y yukarı, -Z ileri (yüz yönü). Ayakta dururken orijin ayakların arası.

const HEAD_LAYER := 2  ## kokpit kamerası bu katmanı görmez (kendi kafamızın içi)

const SUIT := Color(0.36, 0.38, 0.28)
const G_SUIT := Color(0.27, 0.29, 0.21)
const VEST := Color(0.5, 0.47, 0.3)
const HARNESS := Color(0.11, 0.11, 0.1)
const SKIN := Color(0.86, 0.68, 0.55)
const HELMET := Color(0.8, 0.81, 0.8)
const GLOVE := Color(0.22, 0.16, 0.11)
const BOOT := Color(0.06, 0.06, 0.06)
const MASK := Color(0.32, 0.34, 0.3)

const THIGH := 0.42
const SHIN := 0.42
const UPPER_ARM := 0.3
const FOREARM := 0.27
const TORSO := 0.52
const NECK := 0.07
const HIP_WIDTH := 0.1
const SHOULDER_WIDTH := 0.19
const HEAD_HEIGHT := 0.12   ## boyun üstünden kafa merkezine

var pilot_name := "Pilot"
## Kafanın çevrilmesi (kokpitte etrafa bakarken)
var head_yaw := 0.0
var head_pitch := 0.0

var _torso: Node3D
var _head: Node3D
var _eye: Node3D
var _segments := {}   # ad -> Node3D (mesh -Y yönünde sarkar)
var _hands := {}
var _feet := {}
static var _mats := {}


func _ready() -> void:
	_build()
	pose_standing()


## Kamera için göz noktası (kafa ile döner).
func eye() -> Node3D:
	return _eye


# ------------------------------------------------------------------ pozlar

## Ayakta durma / yürüme / koşma. phase: adım fazı (radyan), amount: 0..1 yürüme şiddeti,
## run: 0..1 koşu, lean: dönüşte yana yatma (rad), squash: iniş esnemesi (+) / zıplama (-),
## breath: -1..1 nefes (dururken omuzlar hafif iner kalkar).
func pose_walk(phase: float, amount: float, airborne := false, run := 0.0, lean := 0.0, squash := 0.0, breath := 0.0) -> void:
	var idle := 1.0 - clampf(amount, 0.0, 1.0)
	# kalça orta duruşta (ayak gövde altındayken) en yüksek, adımlar açıkken en alçak
	var drop := absf(sin(phase)) * lerpf(0.03, 0.05, run) * amount
	var crouch := maxf(squash, 0.0) * 0.18
	var pelvis := Vector3(0, THIGH + SHIN + 0.08 - drop - 0.025 * run - crouch + breath * 0.004 * idle, 0)
	var fwd_lean := deg_to_rad(3.0 * amount + 13.0 * run + maxf(squash, 0.0) * 18.0)
	var twist := sin(phase) * lerpf(0.1, 0.18, run) * amount
	var torso_basis := Basis(Vector3.BACK, lean) * Basis(Vector3.RIGHT, -fwd_lean) * Basis(Vector3.UP, twist)
	_set_torso(pelvis, torso_basis)
	var stride := lerpf(0.28, 0.44, run) * amount
	for side: float in [-1.0, 1.0]:
		var s := sin(phase + (0.0 if side < 0 else PI))
		var hip := pelvis + Vector3(side * HIP_WIDTH, -0.03, 0)
		# arkadaki bacak kalkarak öne gelir (salınım fazı)
		var lift := maxf(cos(phase + (0.0 if side < 0 else PI)), 0.0) * lerpf(0.08, 0.2, run) * amount
		var foot := Vector3(side * HIP_WIDTH * 1.05, 0.07 + lift, -s * stride)
		if airborne:
			foot = hip + Vector3(side * 0.07, -0.58 - (0.0 if squash < 0.0 else 0.1), -0.12 + side * 0.08)
		_leg(side, hip, foot, Vector3(0, 0.2, -1))
		var shoulder := _shoulder(side)
		# kollar bacaklara ters sallanır; koşuda dirsekler bükülür, eller göğüse yakın
		var hand := shoulder + torso_basis * Vector3(side * lerpf(0.07, 0.04, run), lerpf(-0.54, -0.32, run) + breath * 0.004 * idle, s * lerpf(0.24, 0.34, run) * amount - run * 0.08)
		if airborne:
			hand = shoulder + torso_basis * Vector3(side * 0.3, -0.22, -0.12)
		_arm(side, shoulder, hand, Vector3(side * 0.4, -0.2, 0.9))
	head_pitch = deg_to_rad(4.0 * run)
	_update_head()


func pose_standing() -> void:
	pose_walk(0.0, 0.0)


## Koltukta oturma. Hedefler model uzayında: pelvis, eller, ayaklar.
func pose_seated(pelvis: Vector3, recline_deg: float, left_hand: Vector3, right_hand: Vector3, left_foot: Vector3, right_foot: Vector3) -> void:
	var torso_basis := Basis(Vector3.RIGHT, deg_to_rad(recline_deg))
	_set_torso(pelvis, torso_basis)
	_leg(-1.0, pelvis + Vector3(-HIP_WIDTH, 0, 0), left_foot, Vector3(-0.2, 1, -0.3))
	_leg(1.0, pelvis + Vector3(HIP_WIDTH, 0, 0), right_foot, Vector3(0.2, 1, -0.3))
	_arm(-1.0, _shoulder(-1.0), left_hand, Vector3(-0.8, -0.4, 0.5))
	_arm(1.0, _shoulder(1.0), right_hand, Vector3(0.8, -0.4, 0.5))
	_update_head()


# ------------------------------------------------------------------ iskelet

func _set_torso(pelvis: Vector3, b: Basis) -> void:
	_torso.transform = Transform3D(b, pelvis)


func _shoulder(side: float) -> Vector3:
	return _torso.transform * Vector3(side * SHOULDER_WIDTH, TORSO - 0.06, 0)


func _update_head() -> void:
	_head.transform = Transform3D(Basis(Vector3.UP, head_yaw) * Basis(Vector3.RIGHT, head_pitch),
		Vector3(0, TORSO + NECK + HEAD_HEIGHT, 0))


func _leg(side: float, hip: Vector3, foot: Vector3, hint: Vector3) -> void:
	var knee := _ik(hip, foot, THIGH, SHIN, hint)
	var key := "L" if side < 0 else "R"
	_place(_segments["thigh" + key], hip, knee)
	var shin_end := knee + (foot - knee).normalized() * SHIN
	_place(_segments["shin" + key], knee, shin_end)
	_feet[key].position = shin_end
	_feet[key].basis = Basis()


func _arm(side: float, shoulder: Vector3, hand: Vector3, hint: Vector3) -> void:
	var elbow := _ik(shoulder, hand, UPPER_ARM, FOREARM, hint)
	var key := "L" if side < 0 else "R"
	_place(_segments["upper" + key], shoulder, elbow)
	var fore_end := elbow + (hand - elbow).normalized() * FOREARM
	_place(_segments["fore" + key], elbow, fore_end)
	_hands[key].position = fore_end
	_hands[key].basis = _segments["fore" + key].basis


## İki kemikli analitik IK: orta eklemin (diz/dirsek) konumunu döner.
static func _ik(root: Vector3, target: Vector3, l1: float, l2: float, hint: Vector3) -> Vector3:
	var d := target - root
	var dist := clampf(d.length(), 0.02, l1 + l2 - 0.001)
	var dir := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := hint - dir * hint.dot(dir)
	bend = bend.normalized() if bend.length() > 0.001 else Vector3.UP
	return root + dir * a + bend * h


## Segment düğümünü `from` noktasına koyar ve -Y eksenini `to` noktasına çevirir.
static func _place(node: Node3D, from: Vector3, to: Vector3) -> void:
	var y := from - to
	if y.length() < 0.0001:
		return
	y = y.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y, z), from)


# ------------------------------------------------------------------ model

func _build() -> void:
	_torso = Node3D.new()
	add_child(_torso)
	# kalça ve gövde: döndürme profili (bel ince, göğüs geniş, omuzlar yuvarlak), önden arkaya basık
	_mesh(_torso, MeshFactory.lathe([Vector2(-0.12, 0.0), Vector2(-0.1, 0.12), Vector2(-0.02, 0.17), Vector2(0.06, 0.165), Vector2(0.12, 0.15)], 18),
		Vector3(0, 0.04, 0), G_SUIT, "", Vector3(-90, 0, 0), Vector3(1.05, 0.78, 1.0))
	_mesh(_torso, MeshFactory.lathe([Vector2(0.0, 0.15), Vector2(0.12, 0.155), Vector2(0.28, 0.185), Vector2(0.42, 0.195),
		Vector2(0.5, 0.17), Vector2(0.56, 0.11), Vector2(0.59, 0.06)], 20), Vector3.ZERO, SUIT, "", Vector3(-90, 0, 0), Vector3(1.12, 0.74, 1.0))
	# can yeleği / kemer takımı
	_mesh(_torso, _capsule(0.18, TORSO * 0.62), Vector3(0, TORSO * 0.62, -0.005), VEST, "", Vector3.ZERO, Vector3(1.1, 1, 0.82))
	for sx: float in [-1.0, 1.0]:
		_mesh(_torso, _box(Vector3(0.045, TORSO * 0.75, 0.012)), Vector3(sx * 0.09, TORSO * 0.55, -0.145), HARNESS, "", Vector3(0, 0, sx * 8))
		_mesh(_torso, _box(Vector3(0.045, 0.012, 0.3)), Vector3(sx * 0.11, TORSO - 0.03, 0.0), HARNESS)
		_mesh(_torso, _box(Vector3(0.06, 0.07, 0.03)), Vector3(sx * 0.11, TORSO * 0.42, -0.15), G_SUIT)   # cepler
	_mesh(_torso, _box(Vector3(0.3, 0.045, 0.3)), Vector3(0, 0.12, 0), HARNESS)                           # bel kemeri
	_mesh(_torso, _box(Vector3(0.07, 0.05, 0.02)), Vector3(0, 0.12, -0.15), Color(0.6, 0.6, 0.58), "metal") # toka
	_mesh(_torso, _box(Vector3(0.08, 0.035, 0.01)), Vector3(-0.08, TORSO * 0.78, -0.15), Color(0.15, 0.15, 0.12))  # isim
	_mesh(_torso, _box(Vector3(0.05, 0.035, 0.01)), Vector3(0.1, TORSO * 0.78, -0.15), Color(0.75, 0.1, 0.1))     # bayrak
	# boyun
	_mesh(_torso, _cyl(0.055, NECK + 0.04), Vector3(0, TORSO + NECK * 0.5, 0), SKIN)
	_mesh(_torso, _cone(0.07, 0.11, 0.09), Vector3(0, TORSO - 0.01, 0), SUIT)   # tulum yakası

	_head = Node3D.new()
	_torso.add_child(_head)
	var head_parts: Array[MeshInstance3D] = []
	head_parts.append(_mesh(_head, _sphere(0.1), Vector3(0, -0.005, 0.0), SKIN, "", Vector3.ZERO, Vector3(0.9, 1.1, 1.0)))
	# kask
	head_parts.append(_mesh(_head, _sphere(0.142), Vector3(0, 0.03, 0.012), HELMET, "gloss", Vector3.ZERO, Vector3(0.95, 0.98, 1.08)))
	head_parts.append(_mesh(_head, _box(Vector3(0.05, 0.02, 0.2)), Vector3(0, 0.17, 0.0), HELMET.darkened(0.2), "gloss"))
	# vizör (koyu, yansıtıcı)
	head_parts.append(_mesh(_head, _sphere(0.145), Vector3(0, 0.035, -0.012), Color(0.04, 0.05, 0.07), "visor", Vector3.ZERO, Vector3(0.9, 0.5, 0.98)))
	# oksijen maskesi ve hortum
	head_parts.append(_mesh(_head, _cone(0.028, 0.062, 0.09), Vector3(0, -0.045, -0.105), MASK, "", Vector3(-80, 0, 0)))
	head_parts.append(_mesh(_head, _box(Vector3(0.16, 0.012, 0.012)), Vector3(0, -0.03, -0.06), HARNESS))
	for p in head_parts:
		p.layers = HEAD_LAYER
	var hose := _mesh(_torso, _capsule(0.016, 0.28), Vector3(-0.06, TORSO + 0.02, -0.17), Color(0.2, 0.22, 0.18), "", Vector3(-25, 0, 18))
	hose.layers = HEAD_LAYER
	_eye = Node3D.new()
	_eye.name = "Eye"
	_eye.position = Vector3(0, 0.02, -0.075)
	_head.add_child(_eye)

	for key in ["L", "R"]:
		_segments["thigh" + key] = _limb(THIGH, 0.08, G_SUIT, true)
		_segments["shin" + key] = _limb(SHIN, 0.062, G_SUIT, true)
		_segments["upper" + key] = _limb(UPPER_ARM, 0.058, SUIT, false)
		_segments["fore" + key] = _limb(FOREARM, 0.05, SUIT, false)
		var foot := Node3D.new()
		add_child(foot)
		# bot: yuvarlak burun, ayrı topuk ve kalın taban
		_mesh(foot, MeshFactory.lathe([Vector2(-0.2, 0.0), Vector2(-0.18, 0.04), Vector2(-0.1, 0.055), Vector2(0.05, 0.058), Vector2(0.08, 0.05), Vector2(0.09, 0.0)], 14, 0.85),
			Vector3(0, -0.02, -0.03), BOOT)
		_mesh(foot, _box(Vector3(0.11, 0.06, 0.12)), Vector3(0, 0.02, 0.03), BOOT)
		_mesh(foot, _box(Vector3(0.115, 0.025, 0.29)), Vector3(0, -0.07, -0.06), Color(0.03, 0.03, 0.03))
		_feet[key] = foot
		var hand := Node3D.new()
		add_child(hand)
		_mesh(hand, _sphere(0.05), Vector3(0, -0.04, 0), GLOVE, "", Vector3.ZERO, Vector3(0.85, 1.25, 0.6))
		_mesh(hand, _capsule(0.016, 0.07), Vector3(0.035 if key == "R" else -0.035, -0.035, -0.015), GLOVE, "", Vector3(0, 0, 35 if key == "R" else -35))   # başparmak
		_mesh(hand, _cyl(0.054, 0.05), Vector3(0, 0.0, 0), GLOVE)
		_hands[key] = hand


func _limb(length: float, radius: float, color: Color, pocket: bool) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	# uca doğru incelen, iki ucu yuvarlak uzuv (lathe ekseni -Y'ye çevrilir)
	var r := radius
	var prof := [Vector2(-r * 0.9, 0.0), Vector2(-r * 0.6, r * 0.75), Vector2(0.0, r), Vector2(length * 0.35, r * 1.02),
		Vector2(length * 0.8, r * 0.82), Vector2(length, r * 0.72), Vector2(length + r * 0.5, r * 0.5), Vector2(length + r * 0.75, 0.0)]
	_mesh(n, MeshFactory.lathe(prof, 14), Vector3.ZERO, color, "", Vector3(90, 0, 0))
	if pocket:
		_mesh(n, _box(Vector3(radius * 1.6, length * 0.35, 0.03)), Vector3(radius * 0.9, -length * 0.45, 0), color.darkened(0.15))
	return n


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, kind := "", rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.material_override = _mat(color, kind)
	parent.add_child(mi)
	return mi


static func _mat(color: Color, kind: String) -> StandardMaterial3D:
	var key := color.to_html() + kind
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	match kind:
		"gloss":
			m.roughness = 0.25
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
		"visor":
			m.roughness = 0.05
			m.metallic = 0.9
		"metal":
			m.roughness = 0.3
			m.metallic = 0.9
	_mats[key] = m
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 16
	c.rings = 6
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	return c


static func _cone(r_top: float, r_bottom: float, h: float) -> CylinderMesh:
	var c := _cyl(r_bottom, h)
	c.top_radius = r_top
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
