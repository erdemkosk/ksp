class_name PilotRagdoll
extends Node3D
## Cansız pilot (ragdoll): PilotModel'in parçaları o anki pozlarıyla eklemli rijit gövdelere
## taşınır — gövde, kafa, üst kollar, ön kollar (+el), uyluklar, baldırlar (+bot). Eklemler
## koni-burgu (ConeTwist): boyun, omuz, dirsek, kalça, diz; her biri insan açı sınırlarına
## yakın. Gövdeler birbiriyle çarpışmaz, yalnız araziyle ve araçlarla.

const LAYER := 16
## ad: [yarıçap, uzunluk (kapsülün -Y boyunca), kütle kg]
const SEGMENTS := {
	"upper": [0.06, PilotModel.UPPER_ARM, 2.3],
	"fore": [0.052, PilotModel.FOREARM + 0.08, 1.8],
	"thigh": [0.085, PilotModel.THIGH, 8.5],
	"shin": [0.065, PilotModel.SHIN + 0.06, 4.8],
}
## eklem: [çocuk, ebeveyn, koni açısı, burgu açısı] (derece)
const JOINTS := [
	["head", "torso", 40.0, 35.0],
	["upperL", "torso", 85.0, 40.0], ["upperR", "torso", 85.0, 40.0],
	["foreL", "upperL", 70.0, 15.0], ["foreR", "upperR", 70.0, 15.0],
	["thighL", "torso", 65.0, 20.0], ["thighR", "torso", 65.0, 20.0],
	["shinL", "thighL", 70.0, 8.0], ["shinR", "thighR", 70.0, 8.0],
]

var bodies := {}


## Modelden ragdoll kur. velocity: başlangıç hızı, spin: açısal hız (yuvarlanma).
static func spawn(model: PilotModel, velocity: Vector3, spin := Vector3.ZERO) -> PilotRagdoll:
	var rd := PilotRagdoll.new()
	rd.name = "PilotRagdoll"
	var root: Node = FloatingOrigin.world_root if FloatingOrigin.world_root else model.get_tree().current_scene
	root.add_child(rd)
	rd.global_transform = Transform3D.IDENTITY
	rd._build(model, velocity, spin)
	return rd


## Kameranın izleyeceği nokta (gövde).
func center() -> Vector3:
	var t: RigidBody3D = bodies.get("torso")
	return t.global_transform * Vector3(0, 0.3, 0) if is_instance_valid(t) else global_position


func _build(model: PilotModel, velocity: Vector3, spin: Vector3) -> void:
	var nodes := model.ragdoll_nodes()
	# önce bütün dünya dönüşümlerini al (yeniden bağlarken değişmesin)
	var xf := {}
	for k in nodes:
		xf[k] = (nodes[k] as Node3D).global_transform
	var torso_xf: Transform3D = xf["torso"]
	var com := torso_xf * Vector3(0, PilotModel.TORSO * 0.5, 0)

	_body("torso", torso_xf, _capsule(0.17, PilotModel.TORSO + 0.12), Vector3(0, PilotModel.TORSO * 0.5, 0), 30.0)
	_body("head", xf["head"], _sphere(0.15), Vector3(0, 0.02, 0), 5.0)
	for key in ["L", "R"]:
		for seg in SEGMENTS:
			var spec: Array = SEGMENTS[seg]
			_body(seg + key, xf[seg + key], _capsule(spec[0], spec[1] + spec[0] * 2.0), Vector3(0, -spec[1] * 0.5, 0), spec[2])
	# görsel düğümleri gövdelere taşı (kafa torsonun çocuğu: önce o)
	var order := ["head", "torso"]
	for key in ["L", "R"]:
		order.append_array(["upper" + key, "fore" + key, "thigh" + key, "shin" + key])
	for k in order:
		(nodes[k] as Node3D).reparent(bodies[k], true)
	for key in ["L", "R"]:
		(nodes["hand" + key] as Node3D).reparent(bodies["fore" + key], true)
		(nodes["foot" + key] as Node3D).reparent(bodies["shin" + key], true)
	# eklemler
	for j: Array in JOINTS:
		var child: RigidBody3D = bodies[j[0]]
		var parent: RigidBody3D = bodies[j[1]]
		var at: Vector3
		var axis: Vector3
		if j[0] == "head":
			at = torso_xf * Vector3(0, PilotModel.TORSO + PilotModel.NECK, 0)
			axis = torso_xf.basis.y.normalized()
		else:
			at = child.global_position
			axis = -child.global_basis.y.normalized()     # kemik yönü
		_joint(child, parent, at, axis, j[2], j[3])
	# başlangıç hareketi: ortak hız + gövde merkezine göre dönme
	for k in bodies:
		var b: RigidBody3D = bodies[k]
		b.linear_velocity = velocity + spin.cross(b.global_position - com)
		b.angular_velocity = spin


func _body(key: String, at: Transform3D, shape: Shape3D, offset: Vector3, mass: float) -> void:
	var b := RigidBody3D.new()
	b.name = key
	b.mass = mass
	b.collision_layer = LAYER
	b.collision_mask = 1 | 2
	b.linear_damp = 0.05
	b.angular_damp = 1.6
	b.continuous_cd = key == "torso" or key == "head"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	b.add_child(cs)
	add_child(b)
	b.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	bodies[key] = b


func _joint(child: RigidBody3D, parent: RigidBody3D, at: Vector3, axis: Vector3, swing_deg: float, twist_deg: float) -> void:
	var j := ConeTwistJoint3D.new()
	add_child(j)
	# koni ekseni eklemin X ekseni: kemik yönüne çevir
	var x := axis.normalized()
	var ref := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := x.cross(ref).normalized()
	var y := z.cross(x).normalized()
	j.global_transform = Transform3D(Basis(x, y, z), at)
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_deg))
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_deg))
	j.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
	j.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 0.9)
	j.node_a = j.get_path_to(parent)
	j.node_b = j.get_path_to(child)


static func _capsule(r: float, h: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	return c


static func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s
