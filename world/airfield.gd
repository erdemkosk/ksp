class_name Airfield
## Pist, taksi yolu, apron, hangarlar, kule ve yakıt tankları.
## Arazi bu bölgede TerrainGen.AIRFIELD_ELEV yüksekliğinde düzdür.

const RUNWAY_LENGTH := 2400.0
const RUNWAY_WIDTH := 45.0
const WHITE := Color(0.92, 0.92, 0.9)
const ASPHALT := Color(0.17, 0.17, 0.18)
const CONCRETE := Color(0.42, 0.42, 0.41)


static var _rl := RUNWAY_LENGTH
static var _rw := RUNWAY_WIDTH


## index: TerrainGen.AIRFIELDS sırası (0 ana üs, 1 kuzey havaalanı).
static func build(index := 0) -> Node3D:
	var cfg: Dictionary = TerrainGen.AIRFIELDS[index]
	_rl = cfg["runway"]
	_rw = RUNWAY_WIDTH if index == 0 else 35.0
	var main_base := index == 0
	var root := Node3D.new()
	root.name = "Airfield%d" % index
	root.transform = TerrainGen.airfield_transform(index)
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# Pist (çarpışmayı arazi sağlar, bunlar görsel)
	_box(root, Vector3(_rw + 10, 0.08, _rl + 60), Vector3(0, 0.0, 0), Color(0.3, 0.3, 0.29))
	_box(root, Vector3(_rw, 0.1, _rl), Vector3(0, 0.01, 0), ASPHALT, 0.8)
	var z := -_rl * 0.5 + 90.0
	while z < _rl * 0.5 - 90.0:
		_box(root, Vector3(0.9, 0.02, 30.0), Vector3(0, 0.07, z), WHITE)
		z += 60.0
	for side in [-1.0, 1.0]:
		for x in [-_rw * 0.5 + 0.8, _rw * 0.5 - 0.8]:
			_box(root, Vector3(0.6, 0.02, _rl - 10.0), Vector3(x, 0.07, 0), WHITE)
		for i in 8:
			var x := -_rw * 0.5 + 5.0 + i * 5.0
			if absf(x) < 3.0:
				continue
			_box(root, Vector3(1.8, 0.02, 30.0), Vector3(x, 0.07, side * (_rl * 0.5 - 30.0)), WHITE)
		for i in 2:
			for x in [-6.0, 6.0]:
				_box(root, Vector3(3.0, 0.02, 22.0), Vector3(x, 0.07, side * (_rl * 0.5 - 300.0 - i * 150.0)), WHITE)


	RunwayLights.build(root, _rl, _rw)
	var sock := AirfieldProps.Windsock.new()
	sock.position = Vector3(-_rw * 0.5 - 45.0, 0, -_rl * 0.5 + 350.0)
	root.add_child(sock)
	var sock2 := AirfieldProps.Windsock.new()
	sock2.position = Vector3(-_rw * 0.5 - 45.0, 0, _rl * 0.5 - 350.0)
	root.add_child(sock2)
	var beacon := AirfieldProps.Beacon.new()
	beacon.position = Vector3(220, 32.3, 120)
	root.add_child(beacon)

	# Taksi yolu ve apron
	_box(root, Vector3(18, 0.08, _rl * 0.75), Vector3(110, 0.01, 0), ASPHALT)
	for zz in [-_rl * 0.33, 0.0, _rl * 0.33]:
		_box(root, Vector3(110, 0.08, 18), Vector3(55, 0.01, zz), ASPHALT)
	_box(root, Vector3(170, 0.1, 360), Vector3(215, 0.02, 380), CONCRETE, 0.9)

	# Hangarlar (kemerli çatı)
	for i in (3 if main_base else 1):
		_hangar(root, Vector3(330, 0, 260 + i * 95))
	# Kule
	_box(root, Vector3(9, 26, 9), Vector3(220, 13, 120), Color(0.85, 0.85, 0.82), 0.8, true)
	_box(root, Vector3(13, 5, 13), Vector3(220, 28.5, 120), Color(0.1, 0.16, 0.22), 0.1, true)
	_box(root, Vector3(14, 0.6, 14), Vector3(220, 31.3, 120), Color(0.3, 0.3, 0.32), 0.8, true)
	if not Game.args.has("nolife"):
		root.add_child(WorldLife.parked(index))
	# Yakıt tankları
	for i in 3:
		var tank := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 9.0
		cyl.bottom_radius = 9.0
		cyl.height = 11.0
		tank.mesh = cyl
		tank.material_override = _mat(Color(0.82, 0.83, 0.8), 0.5)
		tank.position = Vector3(300 + i * 24, 5.5, -200)
		root.add_child(tank)
	return root


static func _hangar(root: Node3D, pos: Vector3) -> void:
	var w := 46.0
	var d := 70.0
	_box(root, Vector3(w, 12, d), pos + Vector3(0, 6, 0), Color(0.6, 0.62, 0.64), 0.7, true)
	var roof := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = w * 0.5
	cyl.bottom_radius = w * 0.5
	cyl.height = d
	cyl.radial_segments = 32
	roof.mesh = cyl
	roof.rotation_degrees = Vector3(90, 0, 0)  # silindir ekseni hangar boyunca
	roof.scale = Vector3(1, 1, 0.35)           # kemeri basıklaştır
	roof.position = pos + Vector3(0, 12, 0)
	roof.material_override = _mat(Color(0.5, 0.53, 0.56), 0.5)
	root.add_child(roof)
	# kapı
	_box(root, Vector3(0.3, 10, d * 0.8), pos + Vector3(-w * 0.5 - 0.1, 5, 0), Color(0.3, 0.32, 0.35), 0.6)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, roughness := 0.9, solid := false) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, roughness)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.add_child(mi)
		parent.add_child(body)
	else:
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


static var _mats := {}


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]
