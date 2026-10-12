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

## Kask şeridi rengi pilotun adından (her pilotun kaskı biraz farklı).
const STRIPES := [Color(0.75, 0.1, 0.08), Color(0.12, 0.25, 0.6), Color(0.9, 0.7, 0.1), Color(0.08, 0.08, 0.09), Color(0.9, 0.45, 0.08)]
const METAL := Color(0.62, 0.63, 0.6)
const RUBBER := Color(0.13, 0.14, 0.13)


func _build() -> void:
	_torso = Node3D.new()
	_torso.name = "Torso"
	add_child(_torso)
	# kalça (G-elbisesi) ve gövde: bel ince, göğüs geniş, omuzlar yuvarlak, önden arkaya basık
	_mesh(_torso, MeshFactory.lathe([Vector2(-0.13, 0.0), Vector2(-0.11, 0.115), Vector2(-0.03, 0.172), Vector2(0.06, 0.168), Vector2(0.13, 0.152)], 22),
		Vector3(0, 0.04, 0), G_SUIT, "fabric", Vector3(-90, 0, 0), Vector3(1.06, 0.8, 1.0))
	_mesh(_torso, MeshFactory.lathe([Vector2(0.0, 0.152), Vector2(0.1, 0.156), Vector2(0.22, 0.178), Vector2(0.34, 0.196),
		Vector2(0.44, 0.198), Vector2(0.5, 0.18), Vector2(0.555, 0.13), Vector2(0.585, 0.07), Vector2(0.595, 0.0)], 24),
		Vector3.ZERO, SUIT, "fabric", Vector3(-90, 0, 0), Vector3(1.12, 0.74, 1.0))
	# omuz ve kalça eklemleri: uzuvlarla gövde arasında boşluk kalmasın
	for sx: float in [-1.0, 1.0]:
		_mesh(_torso, _sphere(0.068), Vector3(sx * SHOULDER_WIDTH, TORSO - 0.06, 0.0), SUIT, "fabric", Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
		_mesh(_torso, _sphere(0.088), Vector3(sx * HIP_WIDTH, -0.02, 0.0), G_SUIT, "fabric")
	# G-elbisesi bel bandı ve hortum bağlantısı (sol bel)
	_mesh(_torso, MeshFactory.lathe([Vector2(0.06, 0.168), Vector2(0.08, 0.18), Vector2(0.15, 0.18), Vector2(0.17, 0.166)], 22),
		Vector3.ZERO, G_SUIT.darkened(0.1), "fabric", Vector3(-90, 0, 0), Vector3(1.08, 0.82, 1.0))
	_mesh(_torso, _cyl(0.018, 0.08), Vector3(-0.19, 0.11, -0.04), RUBBER, "rubber", Vector3(0, 0, 90))
	# fermuar (yakadan aşağı) ve yaka
	_mesh(_torso, _box(Vector3(0.012, 0.16, 0.006)), Vector3(0.0, TORSO - 0.07, -0.148), METAL, "metal", Vector3(-12, 0, 0))
	_mesh(_torso, _cone(0.066, 0.1, 0.075), Vector3(0, TORSO - 0.005, 0.0), SUIT, "fabric")
	# can yeleği: öne çıkık şişirme torbaları, cepler, telsiz kesesi
	_mesh(_torso, _capsule(0.175, TORSO * 0.6), Vector3(0, TORSO * 0.6, 0.0), VEST, "fabric", Vector3.ZERO, Vector3(1.12, 1.0, 0.86))
	for sx: float in [-1.0, 1.0]:
		_mesh(_torso, _capsule(0.05, 0.2), Vector3(sx * 0.075, TORSO * 0.63, -0.14), VEST.darkened(0.08), "fabric", Vector3(0, 0, sx * 6), Vector3(1.0, 1.0, 0.55))
		_mesh(_torso, _box(Vector3(0.07, 0.075, 0.035)), Vector3(sx * 0.12, TORSO * 0.4, -0.15), VEST.darkened(0.15), "fabric")
		_mesh(_torso, _box(Vector3(0.072, 0.02, 0.037)), Vector3(sx * 0.12, TORSO * 0.4 + 0.035, -0.152), VEST.darkened(0.25), "fabric")   # kapak
	_mesh(_torso, _box(Vector3(0.05, 0.11, 0.04)), Vector3(-0.15, TORSO * 0.62, -0.1), Color(0.15, 0.16, 0.13), "rubber", Vector3(0, 25, 0))  # telsiz
	_mesh(_torso, _cyl(0.006, 0.07), Vector3(-0.16, TORSO * 0.62 + 0.08, -0.1), Color(0.08, 0.08, 0.08), "rubber")                      # anten
	# paraşüt kemer takımı: omuz askıları, göğüs kayışı, bacak kayışları, Koch kilitleri
	for sx: float in [-1.0, 1.0]:
		_mesh(_torso, _box(Vector3(0.048, TORSO * 0.78, 0.014)), Vector3(sx * 0.095, TORSO * 0.55, -0.16), HARNESS, "", Vector3(0, 0, sx * 7))
		_mesh(_torso, _box(Vector3(0.048, 0.014, 0.32)), Vector3(sx * 0.115, TORSO - 0.02, 0.0), HARNESS, "", Vector3(sx * 4, 0, 0))
		_mesh(_torso, _box(Vector3(0.048, TORSO * 0.75, 0.014)), Vector3(sx * 0.095, TORSO * 0.55, 0.155), HARNESS, "", Vector3(0, 0, -sx * 7))
		_mesh(_torso, _cyl(0.022, 0.016), Vector3(sx * 0.1, TORSO * 0.82, -0.17), METAL, "metal", Vector3(90, 0, 0))   # Koch
		_mesh(_torso, _box(Vector3(0.05, 0.12, 0.014)), Vector3(sx * 0.11, -0.02, -0.15), HARNESS, "", Vector3(0, 0, -sx * 20))
	_mesh(_torso, _box(Vector3(0.24, 0.035, 0.014)), Vector3(0, TORSO * 0.52, -0.172), HARNESS)        # göğüs kayışı
	_mesh(_torso, _box(Vector3(0.04, 0.03, 0.012)), Vector3(0, TORSO * 0.52, -0.18), METAL, "metal")   # kayış tokası
	_mesh(_torso, _box(Vector3(0.32, 0.045, 0.31)), Vector3(0, 0.12, 0), HARNESS)                         # bel kemeri
	_mesh(_torso, _box(Vector3(0.07, 0.05, 0.02)), Vector3(0, 0.12, -0.157), METAL, "metal")              # toka
	# yamalar: isim, bayrak (sol omuz), filo (sağ omuz)
	_mesh(_torso, _box(Vector3(0.085, 0.032, 0.008)), Vector3(-0.08, TORSO * 0.8, -0.155), Color(0.16, 0.15, 0.12))
	_mesh(_torso, _box(Vector3(0.008, 0.04, 0.06)), Vector3(-SHOULDER_WIDTH - 0.06, TORSO - 0.12, 0.0), Color(0.78, 0.08, 0.08))
	_mesh(_torso, _cyl(0.03, 0.008), Vector3(SHOULDER_WIDTH + 0.06, TORSO - 0.12, 0.0), Color(0.95, 0.75, 0.15), "", Vector3(0, 0, 90))
	# boyun
	_mesh(_torso, _cyl(0.052, NECK + 0.05), Vector3(0, TORSO + NECK * 0.5, 0), SKIN, "skin")
	_build_head()
	_build_hose()

	for key in ["L", "R"]:
		var side := -1.0 if key == "L" else 1.0
		_segments["thigh" + key] = _limb(THIGH, 0.085, G_SUIT, "thigh", side)
		_segments["shin" + key] = _limb(SHIN, 0.064, G_SUIT, "shin", side)
		_segments["upper" + key] = _limb(UPPER_ARM, 0.058, SUIT, "upper", side)
		_segments["fore" + key] = _limb(FOREARM, 0.05, SUIT, "fore", side)
		_feet[key] = _build_boot()
		_hands[key] = _build_hand(side)


## Kafa ve kask: cilt, kask kabuğu, kulaklıklar, ense koruması, vizör yuvası ve altın tonlu
## vizör, pilota özel renk şeridi, oksijen maskesi (yanlarda süngü kilitleri).
func _build_head() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_torso.add_child(_head)
	var stripe: Color = STRIPES[absi(pilot_name.hash()) % STRIPES.size()]
	var parts: Array[MeshInstance3D] = []
	parts.append(_mesh(_head, _sphere(0.098), Vector3(0, -0.008, 0.0), SKIN, "skin", Vector3.ZERO, Vector3(0.88, 1.1, 1.0)))
	# kabuk: arkası ensede aşağı uzar
	parts.append(_mesh(_head, _sphere(0.14), Vector3(0, 0.032, 0.012), HELMET, "gloss", Vector3.ZERO, Vector3(0.96, 0.98, 1.08)))
	parts.append(_mesh(_head, _sphere(0.12), Vector3(0, -0.03, 0.05), HELMET.darkened(0.06), "gloss", Vector3.ZERO, Vector3(1.0, 0.9, 0.9)))
	# kulaklık çanakları
	for sx: float in [-1.0, 1.0]:
		parts.append(_mesh(_head, _cyl(0.05, 0.03), Vector3(sx * 0.128, -0.005, 0.01), HELMET.darkened(0.1), "gloss", Vector3(0, 0, 90)))
		parts.append(_mesh(_head, _cyl(0.012, 0.03), Vector3(sx * 0.115, 0.035, -0.105), METAL, "metal", Vector3(0, 0, 90)))   # vizör pimi
	# yüz açıklığı çerçevesi (lastik)
	parts.append(_mesh(_head, MeshFactory.lathe([Vector2(-0.01, 0.095), Vector2(0.012, 0.102)], 24, 1.15), Vector3(0, 0.0, -0.118), RUBBER, "rubber"))
	# renk şeridi (tepeden enseye) ve vizör yuvası
	parts.append(_mesh(_head, _sphere(0.1412), Vector3(0, 0.033, 0.012), stripe, "gloss", Vector3.ZERO, Vector3(0.22, 0.985, 1.085)))
	parts.append(_mesh(_head, _box(Vector3(0.2, 0.03, 0.06)), Vector3(0, 0.125, -0.085), HELMET.darkened(0.15), "gloss", Vector3(-30, 0, 0)))
	# vizör: kaskın önünü saran altın tonlu yansıtıcı kabuk
	parts.append(_mesh(_head, _sphere(0.147), Vector3(0, 0.03, -0.018), Color(0.32, 0.24, 0.08), "visor", Vector3.ZERO, Vector3(0.92, 0.52, 0.99)))
	# oksijen maskesi: gövde, ağız valfi, yanlarda süngü kilitleri, kask askısı
	parts.append(_mesh(_head, MeshFactory.lathe([Vector2(-0.05, 0.02), Vector2(-0.03, 0.045), Vector2(0.0, 0.062), Vector2(0.035, 0.066)], 18, 1.1),
		Vector3(0, -0.05, -0.098), MASK, "rubber", Vector3(-12, 0, 0)))
	parts.append(_mesh(_head, _cyl(0.022, 0.02), Vector3(0, -0.07, -0.152), Color(0.2, 0.21, 0.19), "rubber", Vector3(-80, 0, 0)))
	for sx: float in [-1.0, 1.0]:
		parts.append(_mesh(_head, _box(Vector3(0.012, 0.04, 0.05)), Vector3(sx * 0.072, -0.03, -0.085), METAL, "metal", Vector3(0, sx * 25, 0)))
		parts.append(_mesh(_head, _box(Vector3(0.01, 0.012, 0.09)), Vector3(sx * 0.1, -0.02, -0.04), HARNESS, "", Vector3(0, sx * 20, 0)))
	for p in parts:
		p.layers = HEAD_LAYER
	_eye = Node3D.new()
	_eye.name = "Eye"
	_eye.position = Vector3(0, 0.02, -0.075)
	_head.add_child(_eye)


## Oksijen hortumu: maskeden göğüsteki bağlantıya kıvrılan halkalı lastik hortum.
func _build_hose() -> void:
	var a := Vector3(0.0, TORSO + NECK + HEAD_HEIGHT - 0.085, -0.16)
	var ctrl := Vector3(-0.07, TORSO + 0.0, -0.24)
	var b := Vector3(-0.11, TORSO * 0.66, -0.17)
	var n := 11
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
		var seg := Node3D.new()
		_torso.add_child(seg)
		_place(seg, prev, p)
		var ring := _mesh(seg, _cyl(0.017, prev.distance_to(p) * 0.92), Vector3(0, -prev.distance_to(p) * 0.5, 0), RUBBER, "rubber")
		ring.layers = HEAD_LAYER
		prev = p
	var plug := _mesh(_torso, _cyl(0.024, 0.04), b, METAL, "metal", Vector3(70, 0, 0))
	plug.layers = HEAD_LAYER


## Uzuv: uca doğru incelen kas profili (lathe ekseni -Y'ye çevrilir). Türüne göre ayrıntı:
## uyluk (G-elbisesi şişirme torbası, cep, sağda diz tahtası), baldır (dizlik, alt cep),
## üst kol (kalem cebi solda), ön kol (eldiven bileği). Uçta eklem küresi (dirsek / diz).
func _limb(length: float, radius: float, color: Color, kind: String, side: float) -> Node3D:
	var n := Node3D.new()
	n.name = kind + ("L" if side < 0 else "R")
	add_child(n)
	var r := radius
	var prof := [Vector2(-r * 0.6, r * 0.55), Vector2(0.0, r), Vector2(length * 0.25, r * 1.06), Vector2(length * 0.5, r * 1.0),
		Vector2(length * 0.8, r * 0.84), Vector2(length, r * 0.74), Vector2(length + r * 0.3, r * 0.5)]
	_mesh(n, MeshFactory.lathe(prof, 16), Vector3.ZERO, color, "fabric", Vector3(90, 0, 0))
	# eklem: bir sonraki uzvun başını örter
	_mesh(n, _sphere(r * 0.8), Vector3(0, -length, 0), color, "fabric")
	match kind:
		"thigh":
			# G-elbisesi şişirme torbası (öne doğru kabarık) ve yan cep
			_mesh(n, _capsule(r * 0.75, length * 0.7), Vector3(0, -length * 0.45, -r * 0.35), color.darkened(0.06), "fabric", Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
			_mesh(n, _box(Vector3(0.03, length * 0.36, r * 1.5)), Vector3(side * r * 1.0, -length * 0.5, 0), color.darkened(0.14), "fabric")
			_mesh(n, _box(Vector3(0.032, 0.02, r * 1.52)), Vector3(side * r * 1.0, -length * 0.33, 0), color.darkened(0.25), "fabric")
			if side > 0.0:
				# diz tahtası: beyaz not tahtası, klips, kayışlar
				_mesh(n, _box(Vector3(0.11, 0.15, 0.012)), Vector3(0, -length * 0.62, -r * 1.05), Color(0.9, 0.9, 0.86), "", Vector3(8, 0, 0))
				_mesh(n, _box(Vector3(0.05, 0.015, 0.02)), Vector3(0, -length * 0.62 + 0.07, -r * 1.1), METAL, "metal")
				for dy in [-0.25, -0.85]:
					_mesh(n, _sphere(r * 1.03), Vector3(0, -length * absf(dy) - 0.0, 0), HARNESS, "", Vector3.ZERO, Vector3(1.0, 0.12, 1.0))
		"shin":
			_mesh(n, _sphere(r * 1.05), Vector3(0, -0.02, -r * 0.35), color.darkened(0.12), "fabric", Vector3.ZERO, Vector3(1.0, 1.2, 0.7))   # dizlik
			_mesh(n, _box(Vector3(r * 1.3, length * 0.25, 0.03)), Vector3(0, -length * 0.55, -r * 0.9), color.darkened(0.12), "fabric")
		"upper":
			if side < 0.0:
				_mesh(n, _box(Vector3(0.03, 0.09, 0.05)), Vector3(-r * 0.95, -length * 0.45, -r * 0.2), color.darkened(0.15), "fabric")
				for k in 2:
					_mesh(n, _cyl(0.005, 0.03), Vector3(-r * 0.95, -length * 0.45 + 0.055, -r * 0.3 + k * 0.016), Color(0.1, 0.1, 0.12) if k == 0 else METAL, "metal")
		"fore":
			# eldiven bileği (uca doğru genişleyen manşet)
			_mesh(n, _cone(r * 1.05, r * 0.82, 0.07), Vector3(0, -length + 0.02, 0), GLOVE, "leather")
	return n


## Eldivenli el: avuç, dört parmak (iki boğumlu, hafif kıvrık), başparmak, manşet.
func _build_hand(side: float) -> Node3D:
	var hand := Node3D.new()
	hand.name = "hand" + ("L" if side < 0 else "R")
	add_child(hand)
	_mesh(hand, _box(Vector3(0.082, 0.085, 0.032)), Vector3(0, -0.045, 0), GLOVE, "leather")
	_mesh(hand, _sphere(0.042), Vector3(0, -0.045, 0.004), GLOVE, "leather", Vector3.ZERO, Vector3(1.0, 1.05, 0.45))
	for i in 4:
		var x := lerpf(-0.03, 0.03, i / 3.0)
		var ln := [0.036, 0.042, 0.04, 0.032][i] as float
		var f := Node3D.new()
		f.position = Vector3(x, -0.088, 0)
		f.rotation_degrees = Vector3(-28, 0, 0)
		hand.add_child(f)
		_mesh(f, _capsule(0.0105, ln), Vector3(0, -ln * 0.5, 0), GLOVE, "leather")
		var tip := Node3D.new()
		tip.position = Vector3(0, -ln, 0)
		tip.rotation_degrees = Vector3(-35, 0, 0)
		f.add_child(tip)
		_mesh(tip, _capsule(0.0098, ln * 0.75), Vector3(0, -ln * 0.36, 0), GLOVE, "leather")
	var th := Node3D.new()
	th.position = Vector3(side * 0.04, -0.035, -0.008)
	th.rotation_degrees = Vector3(-20, 0, side * 40)
	hand.add_child(th)
	_mesh(th, _capsule(0.012, 0.055), Vector3(0, -0.028, 0), GLOVE, "leather")
	return hand


## Uçuş botu: yuvarlak burun, bilek konçu, bağcık şeridi, kalın taban ve topuk.
func _build_boot() -> Node3D:
	var foot := Node3D.new()
	add_child(foot)
	_mesh(foot, MeshFactory.lathe([Vector2(-0.2, 0.0), Vector2(-0.185, 0.038), Vector2(-0.12, 0.056), Vector2(0.03, 0.06), Vector2(0.075, 0.055), Vector2(0.09, 0.0)], 16, 0.82),
		Vector3(0, -0.02, -0.03), BOOT, "leather")
	_mesh(foot, _cone(0.06, 0.065, 0.16), Vector3(0, 0.05, 0.02), BOOT, "leather")           # konç
	_mesh(foot, _box(Vector3(0.045, 0.14, 0.012)), Vector3(0, 0.03, -0.045), Color(0.14, 0.13, 0.12), "", Vector3(-12, 0, 0))   # bağcık
	_mesh(foot, _box(Vector3(0.118, 0.028, 0.295)), Vector3(0, -0.072, -0.06), Color(0.035, 0.035, 0.035), "rubber")
	_mesh(foot, _box(Vector3(0.1, 0.03, 0.07)), Vector3(0, -0.06, 0.05), Color(0.035, 0.035, 0.035), "rubber")
	return foot


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, kind := "", rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.material_override = _mat(color, kind)
	parent.add_child(mi)
	return mi


static func _mat(color: Color, kind: String) -> Material:
	var key := color.to_html() + kind
	if _mats.has(key):
		return _mats[key]
	if kind == "fabric":
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://pilot/fabric.gdshader")
		sm.set_shader_parameter("base", color)
		_mats[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	match kind:
		"gloss":
			m.roughness = 0.22
			m.clearcoat_enabled = true
			m.clearcoat = 0.7
			m.clearcoat_roughness = 0.15
		"visor":
			m.roughness = 0.04
			m.metallic = 1.0
			m.metallic_specular = 0.9
		"metal":
			m.roughness = 0.3
			m.metallic = 0.9
		"rubber":
			m.roughness = 0.92
		"leather":
			m.roughness = 0.55
			m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		"skin":
			m.roughness = 0.6
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.35
	_mats[key] = m
	return m


# ------------------------------------------------------------------ ragdoll desteği

## Ragdoll için gövde parçaları (dünya dönüşümleri o anki pozdan): ad → düğüm.
## torso (kafa hariç), head, upperL/R, foreL/R, thighL/R, shinL/R, handL/R, footL/R.
func ragdoll_nodes() -> Dictionary:
	var out := {"torso": _torso, "head": _head}
	for key in ["L", "R"]:
		for seg in ["thigh", "shin", "upper", "fore"]:
			out[seg + key] = _segments[seg + key]
		out["hand" + key] = _hands[key]
		out["foot" + key] = _feet[key]
	return out


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
