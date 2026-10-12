class_name VesselLights
extends Node
## Seyir ışıkları (Vessel.lights_on ile): sol kanat ucu kırmızı, sağ yeşil, en yüksek
## noktada yanıp sönen beyaz çakar; burun takımında iniş farı (takım açıkken).
## Işıklar parçalara takılır; parça koparsa ışığı da onunla gider.

var vessel: Vessel
var _nav: Array[Node3D] = []
var _strobe: Node3D
var _landing: SpotLight3D
var _t := 0.0


func setup(v: Vessel) -> void:
	vessel = v
	var left: Part = null
	var right: Part = null
	var top: Part = null
	var nose_gear: Part = null
	for p in v.parts:
		if p.def.get("category", "") == "kanat":
			if left == null or p.position.x < left.position.x:
				left = p
			if right == null or p.position.x > right.position.x:
				right = p
		if top == null or p.position.y + p.size.y > top.position.y + top.size.y:
			top = p
		for m in p.modules:
			if m is LandingGearModule and m.steerable:
				nose_gear = p
	if left and left.position.x < -0.5:
		_nav.append(_lamp(left, Vector3(-left.size.x * 0.5, 0, 0), Color(1.0, 0.1, 0.05)))
	if right and right.position.x > 0.5:
		_nav.append(_lamp(right, Vector3(right.size.x * 0.5, 0, 0), Color(0.1, 1.0, 0.25)))
	if top:
		_strobe = _lamp(top, (top.basis.inverse() * Vector3(0, top.size.y * 0.5 + 0.05, 0)), Color(1, 1, 1))
	if nose_gear:
		_landing = SpotLight3D.new()
		_landing.light_color = Color(1.0, 0.96, 0.88)
		_landing.light_energy = 12.0
		_landing.spot_range = 450.0
		_landing.spot_angle = 18.0
		_landing.shadow_enabled = false
		_landing.position = Vector3(0, -0.4, -0.3)
		_landing.rotation_degrees = Vector3(-6, 0, 0)
		nose_gear.add_child(_landing)


## Küçük parlayan küre + nokta ışık.
func _lamp(part: Part, local_pos: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.position = local_pos
	var bulb := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	bulb.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * 2.5
	bulb.material_override = m
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 6.0
	root.add_child(light)
	part.add_child(root)
	return root


func _process(delta: float) -> void:
	if not is_instance_valid(vessel):
		return
	_t += delta
	var on := vessel.lights_on
	for n in _nav:
		if is_instance_valid(n):
			n.visible = on
	if is_instance_valid(_strobe):
		# saniyede bir çift çakma
		var phase := fmod(_t, 1.2)
		_strobe.visible = on and (phase < 0.06 or (phase > 0.16 and phase < 0.22))
	if is_instance_valid(_landing):
		_landing.visible = on and vessel.gear_deploy() > 0.95
