class_name CockpitModule
extends PartModule
## Kokpit: pilot(lar), kanopi/kapı, kumandalar, tıklanabilir anahtarlar ve canlı ekranlar.
## Konumlar parçanın yerel uzayında (gövde ekseni z, üst +y, ön -z).
##
## İki düzen (parça tanımında modül parametresi "layout"):
##   "fighter" — tek kişilik savaş kokpiti: göz panelden ~0.65 m, HUD camı, orta lövye,
##               sol konsolda gaz kolu, arkadan menteşeli balon kanopi
##   "civil"   — yan yana iki koltuk: iki boynuz lövye (yoke), ortada gaz kolu, 4 ekranlı
##               geniş panel, yandan (martı kanadı gibi) açılan kapı, sağda yardımcı pilot

const PILOT_NAMES := ["Ayaz Kartal", "Deniz Şahin", "Bora Yıldırım", "Ece Doğan", "Kaan Atmaca", "Selin Ateş"]

const LAYOUTS := {
	"fighter": {
		"seats": [Vector3(0, 0.32, 0.18)], "recline": 12.0,
		"pedals": [Vector3(-0.13, 0.14, -0.58), Vector3(0.13, 0.14, -0.58)],
		"panel_z": -0.38, "mfds": [Vector3(-0.215, 0.755, -0.403), Vector3(0.215, 0.755, -0.403)], "mfd_size": 0.17,
		"canopy": "bubble", "hinge": Vector3(0, 0.62, 1.2), "open_deg": 55.0,
		"exit": Vector3(-1.7, 0.2, 0.2), "drop": 0.0,
	},
	"civil": {
		"seats": [Vector3(-0.3, 0.32, 0.12), Vector3(0.3, 0.32, 0.12)], "recline": 8.0,
		"pedals": [Vector3(-0.13, 0.14, -0.6), Vector3(0.13, 0.14, -0.6)],
		"panel_z": -0.42, "mfds": [Vector3(-0.47, 0.745, -0.44), Vector3(-0.18, 0.745, -0.44), Vector3(0.18, 0.745, -0.44), Vector3(0.47, 0.745, -0.44)], "mfd_size": 0.16,
		"canopy": "gull", "hinge": Vector3(-0.6, 0.66, -0.2), "open_deg": 70.0,
		"exit": Vector3(-1.8, 0.2, 0.0), "drop": -0.1,
	},
}

var pilot_name := ""
var occupied := true
var canopy_open := false
var pilot: PilotModel
var copilot: PilotModel
var switches: Array[CockpitSwitch] = []
var layout := "fighter"

var _L: Dictionary
var _canopy_t := 0.0
var _canopy: Node3D
var _in: Node3D
var _exit := Vector3.ZERO
var _stick: Node3D
var _stick_grip: Node3D
var _yokes: Array[Node3D] = []
var _yoke_grips: Array[Node3D] = []
var _throttle: Node3D
var _throttle_knob: Node3D
var _caution_lamp: MeshInstance3D
var _gear_lamps: Array[MeshInstance3D] = []
var _flood: OmniLight3D
var _mfd_quads: Array[MeshInstance3D] = []


func setup(p: Dictionary) -> void:
	pilot_name = p.get("pilot", "")
	layout = p.get("layout", "fighter")
	if pilot_name.is_empty():
		pilot_name = PILOT_NAMES[randi() % PILOT_NAMES.size()]


func on_attached() -> void:
	_L = LAYOUTS.get(layout, LAYOUTS["fighter"])
	# iç düzen (koltuk, panel, kumandalar, pilot, cam) gövdenin içine indirilir: kanopi alçak kalır
	_in = Node3D.new()
	_in.name = "Interior"
	_in.position = Vector3(0, float(_L.get("drop", 0.0)), 0)
	part.add_child(_in)
	_build_canopy()
	if layout == "civil":
		_build_civil_controls()
		_build_civil_switches()
	else:
		_build_controls()
		_build_switches()
	_build_mfds()
	_build_details()
	pilot = PilotModel.new()
	pilot.name = "Pilot"
	pilot.pilot_name = pilot_name
	_in.add_child(pilot)
	if layout == "civil":
		copilot = PilotModel.new()
		copilot.name = "Copilot"
		copilot.pilot_name = "Yardımcı pilot"
		_in.add_child(copilot)
		_make_visible_in_cockpit.call_deferred(copilot)


## Yardımcı pilotun kafası kokpit kamerasında da görünsün (kendi kafamız gizli kalır).
func _make_visible_in_cockpit(m: PilotModel) -> void:
	var stack: Array[Node] = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is VisualInstance3D:
			n.layers = 1


func physics_tick(delta: float) -> void:
	_canopy_t = move_toward(_canopy_t, 1.0 if canopy_open else 0.0, delta * 0.7)
	var a := deg_to_rad(float(_L["open_deg"])) * smoothstep(0.0, 1.0, _canopy_t)
	if _canopy == null:
		pass                            # fırlatmada atıldı
	elif _L["canopy"] == "gull":
		_canopy.rotation.z = a          # sol kenardan yukarı açılır
	else:
		_canopy.rotation.x = a          # arkadan menteşeli


func _process(_delta: float) -> void:
	if part == null or vessel == null:
		return
	var seats: Array = _L["seats"]
	var pedals: Array = _L["pedals"]
	var recline: float = _L["recline"]
	if layout == "civil":
		for y in _yokes:
			y.position.z = y.get_meta("z0") + vessel.ctrl_pitch * 0.06
			y.rotation.z = deg_to_rad(-vessel.ctrl_roll * 40.0)
		_throttle.rotation.x = deg_to_rad(lerpf(30.0, -30.0, vessel.ctrl_throttle))
		pilot.visible = occupied
		var s0: Vector3 = seats[0]
		if occupied:
			pilot.pose_seated(s0, recline, _in.to_local(_yoke_grips[0].global_position),
				_in.to_local(_throttle_knob.global_position),
				s0 + Vector3(-0.13, -0.18, -0.72), s0 + Vector3(0.13, -0.18, -0.72))
		var s1: Vector3 = seats[1]
		copilot.pose_seated(s1, recline, s1 + Vector3(-0.12, 0.08, -0.32), s1 + Vector3(0.12, 0.08, -0.32),
			s1 + Vector3(-0.13, -0.18, -0.7), s1 + Vector3(0.13, -0.18, -0.7))
	else:
		_stick.rotation = Vector3(deg_to_rad(vessel.ctrl_pitch * 14.0), 0, deg_to_rad(-vessel.ctrl_roll * 14.0))
		_throttle.rotation.x = deg_to_rad(lerpf(25.0, -25.0, vessel.ctrl_throttle))
		pilot.visible = occupied
		if occupied:
			pilot.pose_seated(seats[0], recline,
				_in.to_local(_throttle_knob.global_position), _in.to_local(_stick_grip.global_position),
				pedals[0], pedals[1])
	if occupied:
		_auto_head(_delta)
	_update_lamps()


func is_canopy_fully_open() -> bool:
	return _canopy_t >= 0.99


## Pilotun kokpit dışına iniş noktası (dünya koordinatı).
func exit_point() -> Vector3:
	return part.global_transform * _exit


# ------------------------------------------------------------------ kanopi / kapı

## Fırlatma: kanopi patlayıcı cıvatalarla atılır, hava akışında uçup düşer.
func jettison_canopy() -> void:
	if _canopy == null or FloatingOrigin.world_root == null:
		return
	var deb := Debris.new()
	deb.mass = 45.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.5, 1.6)
	cs.shape = bs
	deb.add_child(cs)
	FloatingOrigin.world_root.add_child(deb)
	deb.global_transform = _canopy.global_transform
	_canopy.reparent(deb)
	deb.linear_velocity = vessel.linear_velocity + vessel.up() * 22.0 - vessel.forward() * 4.0
	deb.angular_velocity = vessel.global_basis.x * randf_range(3.0, 6.0)
	deb.add_collision_exception_with(vessel)
	_canopy = null
	Sfx.play_at("explosion_small.ogg", part.global_position, -4.0, 1.6, 1500.0)


func _build_canopy() -> void:
	# Cam, gövdedeki açıklığa (dünya ölçeğiyle büyür) ve pilotun kafasına (sabit insan boyu)
	# göre hesaplanır: tabanı açıklığın kenarlarını örter, tepesi kaskın ~10 cm üstünde kalır.
	var s := float(part.def.get("_scale", 1.0))
	var drop := float(_L.get("drop", 0.0))
	var civil: bool = _L["canopy"] == "gull"
	var shell_r := 0.65 * s
	var edge := deg_to_rad(30.0 if civil else 48.0)
	var edge_y := shell_r * sin(edge)
	var edge_x := shell_r * cos(edge)
	var top := (1.27 if civil else 1.25) + drop
	# yarım küre cam: tabanı gövde açıklığının kenarında (alt yarı yok; açılınca altında koyu cam görünmez)
	var c := edge_y - 0.02
	var h := maxf(top - c, 0.2)
	var w := edge_x * 1.04
	var z0 := (-0.95 if civil else -0.75) * s
	var z1 := (0.85 if civil else 1.0) * s
	var zc := (z0 + z1) * 0.5
	var half_l := (z1 - z0) * 0.5 * 1.05
	# camın merkezi parça uzayında; kanopi düğümü iç düzen (drop) altında
	var center := Vector3(0, c - drop, zc)
	_canopy = Node3D.new()
	_canopy.name = "CanopyHinge"
	_canopy.position = Vector3(-w * 0.95, c - drop, zc) if civil else Vector3(0, c - drop, zc + half_l * 0.9)
	_in.add_child(_canopy)
	_exit = Vector3((_L["exit"] as Vector3).x * s, (_L["exit"] as Vector3).y, (_L["exit"] as Vector3).z)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://vessel/canopy_glass.gdshader")
	var glass := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.is_hemisphere = true
	sphere.height = 0.5
	sphere.radial_segments = 48
	sphere.rings = 24
	glass.mesh = sphere
	glass.material_override = mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.scale = Vector3(w * 2.0, h * 2.0, half_l * 2.0)
	glass.position = center - _canopy.position
	if civil:
		# geniş, basık sivil kabin camı; çerçeve: tavan kirişi ve ön dikme
		mat.set_shader_parameter("bow_front", -0.43)
		mat.set_shader_parameter("bow_back", 0.44)
		mat.set_shader_parameter("frame_width", 0.008)
	else:
		mat.set_shader_parameter("bow_front", -0.25)
		# ön çerçeve (yay) — kanopi ile birlikte açılır
		var bow := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.44
		tor.outer_radius = 0.48
		tor.rings = 32
		tor.ring_segments = 6
		bow.mesh = tor
		bow.material_override = VesselBuilder.material("paint_dark")
		bow.rotation_degrees = Vector3(90, 0, 0)
		bow.scale = Vector3(w / 0.46, 1.0, h / 0.46)
		bow.position = center + Vector3(0, 0, -half_l * 0.5) - _canopy.position
		bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_canopy.add_child(bow)
	_canopy.add_child(glass)


# ------------------------------------------------------------------ savaş kokpiti

func _build_controls() -> void:
	# orta lövye
	_stick = Node3D.new()
	_stick.position = Vector3(0, 0.12, -0.12)
	_in.add_child(_stick)
	_add_mesh(_stick, _cyl(0.014, 0.3), Vector3(0, 0.15, 0), "dark")
	_add_mesh(_stick, _cyl(0.05, 0.03), Vector3(0, 0.0, 0), "rubber")   # körük
	_stick_grip = Node3D.new()
	_stick_grip.position = Vector3(0, 0.31, 0)
	_stick.add_child(_stick_grip)
	_add_mesh(_stick_grip, _cyl(0.025, 0.1), Vector3.ZERO, "dark")
	_add_mesh(_stick_grip, _box(Vector3(0.015, 0.015, 0.015)), Vector3(0, 0.055, -0.015), "red")
	_add_mesh(_stick_grip, _box(Vector3(0.012, 0.03, 0.012)), Vector3(0, 0.0, -0.03), "metal")   # tetik
	# gaz kolu (sol konsol, arka)
	_throttle = Node3D.new()
	_throttle.position = Vector3(-0.34, 0.5, 0.24)
	_in.add_child(_throttle)
	_add_mesh(_throttle, _cyl(0.012, 0.12), Vector3(0, 0.06, 0), "metal")
	_throttle_knob = Node3D.new()
	_throttle_knob.position = Vector3(0, 0.13, 0)
	_throttle.add_child(_throttle_knob)
	_add_mesh(_throttle_knob, _box(Vector3(0.05, 0.045, 0.08)), Vector3.ZERO, "dark")
	_add_mesh(_throttle_knob, _box(Vector3(0.012, 0.012, 0.012)), Vector3(0.026, 0.012, -0.02), "red")


func _build_switches() -> void:
	var v := vessel
	var pz: float = _L["panel_z"]
	# --- Ön panel (pilota bakan) ---
	_add_switch("İNİŞ TAKIMI", Vector3(-0.29, 0.66, pz + 0.01), Vector3(75, 0, 0), "gear",
		func() -> bool: return v.gear_down, func() -> void: v.gear_down = not v.gear_down)
	_add_switch("KANOPİ", Vector3(0.29, 0.66, pz + 0.01), Vector3(75, 0, 0), "button",
		func() -> bool: return canopy_open, func() -> void: canopy_open = not canopy_open)
	_add_switch("MASTER ARM", Vector3(-0.29, 0.56, pz + 0.035), Vector3(75, 0, 0), "guarded",
		func() -> bool: return v.master_arm, func() -> void: v.master_arm = not v.master_arm)
	# --- Sol konsol: motor ve elektrik (önden arkaya) ---
	var x := -0.36
	var y := 0.5
	_add_switch("BATARYA", Vector3(x, y, -0.24), Vector3.ZERO, "toggle",
		func() -> bool: return v.battery_on, func() -> void: v.battery_on = not v.battery_on)
	_add_switch("JFS", Vector3(x, y, -0.16), Vector3.ZERO, "button",
		func() -> bool: return v.jfs_on, func() -> void: v.jfs_on = not v.jfs_on and v.has_power())
	_add_switch("MOTOR ÇALIŞTIR", Vector3(x, y, -0.08), Vector3.ZERO, "button",
		func() -> bool: return _engine_starting(), func() -> void: v.start_engines())
	_add_switch("YAKIT KES", Vector3(x, y, 0.0), Vector3.ZERO, "guarded",
		func() -> bool: return not v.engines_running(), func() -> void: v.shutdown_engines())
	_add_switch("PARK FRENİ", Vector3(x, y, 0.08), Vector3.ZERO, "handle",
		func() -> bool: return v.parking_brake, func() -> void: v.parking_brake = not v.parking_brake)
	# --- Sağ konsol: ışıklar ve otomatik sistemler ---
	x = 0.36
	_add_switch("KOKPİT IŞIĞI", Vector3(x, y, -0.24), Vector3.ZERO, "button",
		func() -> bool: return v.cockpit_light, func() -> void: v.cockpit_light = not v.cockpit_light)
	_add_switch("SAS", Vector3(x, y, -0.16), Vector3.ZERO, "toggle",
		func() -> bool: return v.sas, func() -> void: v.sas = not v.sas)
	_add_switch("OTOPİLOT", Vector3(x, y, -0.08), Vector3.ZERO, "button",
		func() -> bool: return v.autopilot_active, func() -> void: v.autopilot_toggle.emit())
	_add_switch("SEYİR IŞIKLARI", Vector3(x, y, 0.0), Vector3.ZERO, "toggle",
		func() -> bool: return v.lights_on, func() -> void: v.lights_on = not v.lights_on)
	_add_switch("DIŞARI ÇIK", Vector3(0.42, 0.6, 0.42), Vector3(0, 0, -30), "eject",
		func() -> bool: return not occupied, func() -> void: v.request_eva.emit())


# ------------------------------------------------------------------ sivil kokpit

func _build_civil_controls() -> void:
	var seats: Array = _L["seats"]
	var pz: float = _L["panel_z"]
	for s: Vector3 in seats:
		# boynuz lövye: panelden çıkan kolon + U biçimli direksiyon
		_add_mesh(_in, _cyl(0.018, 0.2), Vector3(s.x, 0.6, pz + 0.08), "metal", Vector3(90, 0, 0))
		var yoke := Node3D.new()
		yoke.position = Vector3(s.x, 0.6, pz + 0.19)
		yoke.set_meta("z0", yoke.position.z)
		_in.add_child(yoke)
		_add_mesh(yoke, _box(Vector3(0.26, 0.03, 0.03)), Vector3.ZERO, "dark")
		for sx in [-0.13, 0.13]:
			_add_mesh(yoke, _box(Vector3(0.03, 0.11, 0.035)), Vector3(sx, 0.045, 0), "dark")
		_add_mesh(yoke, _box(Vector3(0.05, 0.03, 0.01)), Vector3(0, 0.0, 0.018), "metal")
		var grip := Node3D.new()
		grip.position = Vector3(-0.13, 0.06, 0)
		yoke.add_child(grip)
		_yokes.append(yoke)
		_yoke_grips.append(grip)
	# orta gaz kolu kutusu
	_add_mesh(_in, _box(Vector3(0.16, 0.14, 0.34)), Vector3(0, 0.47, -0.2), "interior")
	_throttle = Node3D.new()
	_throttle.position = Vector3(-0.03, 0.54, -0.2)
	_in.add_child(_throttle)
	_add_mesh(_throttle, _cyl(0.01, 0.12), Vector3(0, 0.06, 0), "metal")
	_throttle_knob = Node3D.new()
	_throttle_knob.position = Vector3(0, 0.13, 0)
	_throttle.add_child(_throttle_knob)
	_add_mesh(_throttle_knob, _box(Vector3(0.06, 0.03, 0.03)), Vector3.ZERO, "dark")
	var prop_lever := _add_mesh(_in, _cyl(0.01, 0.1), Vector3(0.04, 0.59, -0.2), "metal")
	_add_mesh(prop_lever, _box(Vector3(0.03, 0.03, 0.03)), Vector3(0, 0.05, 0), "lamp_amber")


func _build_civil_switches() -> void:
	var v := vessel
	var pz: float = _L["panel_z"]
	# panelin alt şeridi: sistemler (soldan sağa)
	var row_y := 0.535
	var specs := [
		["BATARYA", "toggle", func() -> bool: return v.battery_on, func() -> void: v.battery_on = not v.battery_on],
		["JFS", "button", func() -> bool: return v.jfs_on, func() -> void: v.jfs_on = not v.jfs_on and v.has_power()],
		["MOTOR ÇALIŞTIR", "button", func() -> bool: return _engine_starting(), func() -> void: v.start_engines()],
		["YAKIT KES", "guarded", func() -> bool: return not v.engines_running(), func() -> void: v.shutdown_engines()],
		["SEYİR IŞIKLARI", "toggle", func() -> bool: return v.lights_on, func() -> void: v.lights_on = not v.lights_on],
		["KOKPİT IŞIĞI", "button", func() -> bool: return v.cockpit_light, func() -> void: v.cockpit_light = not v.cockpit_light],
	]
	for i in specs.size():
		var s: Array = specs[i]
		_add_switch(s[0], Vector3(-0.5 + i * 0.2, row_y, pz + 0.04), Vector3(75, 0, 0), s[1], s[2], s[3])
	# orta: iniş takımı kolu panelde, park freni kutuda
	_add_switch("İNİŞ TAKIMI", Vector3(0, 0.66, pz + 0.01), Vector3(75, 0, 0), "gear",
		func() -> bool: return v.gear_down, func() -> void: v.gear_down = not v.gear_down)
	_add_switch("PARK FRENİ", Vector3(0.05, 0.545, -0.08), Vector3.ZERO, "handle",
		func() -> bool: return v.parking_brake, func() -> void: v.parking_brake = not v.parking_brake)
	# göz siperinin üstü: otomatik uçuş
	_add_switch("SAS", Vector3(-0.12, 0.885, pz - 0.1), Vector3(20, 0, 0), "toggle",
		func() -> bool: return v.sas, func() -> void: v.sas = not v.sas)
	_add_switch("OTOPİLOT", Vector3(0.12, 0.885, pz - 0.1), Vector3(20, 0, 0), "button",
		func() -> bool: return v.autopilot_active, func() -> void: v.autopilot_toggle.emit())
	# kapı
	_add_switch("KAPI", Vector3(-0.56, 0.62, -0.1), Vector3(0, 0, 30), "button",
		func() -> bool: return canopy_open, func() -> void: canopy_open = not canopy_open)
	_add_switch("DIŞARI ÇIK", Vector3(-0.56, 0.62, 0.15), Vector3(0, 0, 30), "eject",
		func() -> bool: return not occupied, func() -> void: v.request_eva.emit())


# ------------------------------------------------------------------ ortak

func _engine_starting() -> bool:
	if vessel == null:
		return false   # kokpit koptu
	for e in vessel.engines():
		if e.state == EngineModule.State.CRANKING:
			return true
	return false


func _add_switch(text: String, pos: Vector3, rot: Vector3, kind: String, getter: Callable, action: Callable) -> void:
	var size := Vector3(0.07, 0.08, 0.07) if kind != "gear" else Vector3(0.08, 0.12, 0.1)
	var s := CockpitSwitch.create(text, size, getter, action)
	s.kind = kind
	s.position = pos
	s.rotation_degrees = rot
	_in.add_child(s)
	_add_mesh(s, _box(Vector3(0.06, 0.012, 0.06)), Vector3.ZERO, "dark")  # taban plakası
	match kind:
		"button":
			var cap := Node3D.new()
			_add_mesh(cap, _box(Vector3(0.036, 0.016, 0.036)), Vector3(0, 0.012, 0), "button")
			var lamp := _add_mesh(cap, _box(Vector3(0.026, 0.004, 0.012)), Vector3(0, 0.021, -0.006), "dark")
			s.set_button(cap, lamp, VesselBuilder.material("lamp_green"), VesselBuilder.material("dark", Color(0.1, 0.13, 0.1)))
		"guarded":
			var lever := Node3D.new()
			_add_mesh(lever, _cyl(0.006, 0.04), Vector3(0, 0.02, 0), "metal")
			_add_mesh(lever, _cyl(0.009, 0.012), Vector3(0, 0.042, 0), "white")
			s.set_lever(lever)
			var cover := Node3D.new()
			cover.position = Vector3(0, 0.006, 0.025)
			_add_mesh(cover, _box(Vector3(0.05, 0.055, 0.05)), Vector3(0, 0.028, -0.025), "red")
			s.set_cover(cover)
		_:
			var lever := Node3D.new()
			match kind:
				"gear":
					_add_mesh(lever, _cyl(0.008, 0.09), Vector3(0, 0.045, 0), "metal")
					var wheel := _add_mesh(lever, _cyl(0.022, 0.018), Vector3(0, 0.095, 0), "white")
					wheel.rotation_degrees = Vector3(0, 0, 90)
					s.on_angle = 40.0
					s.off_angle = -40.0
				"handle":
					_add_mesh(lever, _box(Vector3(0.05, 0.05, 0.015)), Vector3(0, 0.03, 0), "red")
				"eject":
					_add_mesh(lever, _torus(0.03, 0.045), Vector3(0, 0.04, 0), "yellow", Vector3(90, 0, 0))
					s.on_angle = -50.0
					s.off_angle = 0.0
				_:
					_add_mesh(lever, _cyl(0.006, 0.04), Vector3(0, 0.02, 0), "metal")
					_add_mesh(lever, _cyl(0.009, 0.012), Vector3(0, 0.042, 0), "white")
			s.set_lever(lever)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 36
	lbl.outline_size = 8
	lbl.pixel_size = 0.00034
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.9, 0.95, 0.9)
	lbl.position = Vector3(0, -0.012, 0.042) if rot == Vector3.ZERO else Vector3(0, -0.05, 0.0)
	s.add_child(lbl)
	switches.append(s)


func _build_mfds() -> void:
	var spots: Array = _L["mfds"]
	var sz: float = _L["mfd_size"]
	for i in spots.size():
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var mfd := MfdDisplay.new()
		mfd.page = MfdDisplay.Page.PFD if i % 2 == 0 else MfdDisplay.Page.ENGINE
		mfd.vessel = vessel
		mfd.size = Vector2(256, 256)
		vp.add_child(mfd)
		_in.add_child(vp)
		# ekran çerçevesi + çevresindeki tuşlar
		var bezel := _add_mesh(_in, _box(Vector3(sz + 0.04, sz + 0.04, 0.02)), (spots[i] as Vector3) + Vector3(0, 0, -0.012), "dark", Vector3(-15, 0, 0))
		for k in 5:
			_add_mesh(bezel, _box(Vector3(0.016, 0.012, 0.008)), Vector3(-sz * 0.4 + k * sz * 0.2, -sz * 0.5 - 0.012, 0.012), "button")
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(sz, sz)
		quad.mesh = qm
		quad.position = spots[i]
		quad.rotation_degrees = Vector3(-15, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = vp.get_texture()
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_in.add_child(quad)
		_mfd_quads.append(quad)


## Kokpit detayları: savaşta HUD camı ve UFC; ikisinde de uyarı ve takım lambaları,
## yedek göstergeler, kırmızı gece ışığı.
func _build_details() -> void:
	var pz: float = _L["panel_z"]
	if layout == "fighter":
		var hud_frame := Node3D.new()
		hud_frame.position = Vector3(0, 0.915, pz - 0.12)
		_in.add_child(hud_frame)
		for sx in [-0.095, 0.095]:
			_add_mesh(hud_frame, _box(Vector3(0.012, 0.15, 0.012)), Vector3(sx, 0.075, 0), "dark")
		_add_mesh(hud_frame, _box(Vector3(0.2, 0.012, 0.012)), Vector3(0, 0.15, 0), "dark")
		var combiner := _add_mesh(hud_frame, _box(Vector3(0.18, 0.14, 0.004)), Vector3(0, 0.075, 0), "dark", Vector3(-12, 0, 0))
		var cm := StandardMaterial3D.new()
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.albedo_color = Color(0.5, 0.9, 0.6, 0.07)
		cm.metallic = 0.5
		cm.roughness = 0.02
		combiner.material_override = cm
		var ufc := Node3D.new()
		ufc.position = Vector3(0, 0.83, pz - 0.035)
		ufc.rotation_degrees = Vector3(-15, 0, 0)
		_in.add_child(ufc)
		_add_mesh(ufc, _box(Vector3(0.2, 0.09, 0.02)), Vector3.ZERO, "dark")
		_add_mesh(ufc, _box(Vector3(0.14, 0.022, 0.004)), Vector3(0, 0.028, 0.011), "screen_amber")
		for row in 2:
			for col in 5:
				_add_mesh(ufc, _box(Vector3(0.022, 0.016, 0.008)), Vector3(-0.056 + col * 0.028, -0.006 - row * 0.022, 0.012), "button")
		# koltuk: fırlatma kolu ve omuz kemerleri
		_add_mesh(_in, _torus(0.025, 0.04), Vector3(0, 0.27, -0.02), "yellow", Vector3(90, 0, 0))
		for sx in [-0.12, 0.12]:
			_add_mesh(_in, _box(Vector3(0.05, 0.5, 0.01)), Vector3(sx, 0.7, 0.45), "dark", Vector3(12, 0, 0))
		_add_mesh(_in, _box(Vector3(0.1, 0.05, 0.22)), Vector3(-0.34, 0.475, 0.22), "dark")   # gaz kolu gövdesi
	else:
		# pusula ve hava hızı / irtifa saatleri (göz siperinin üstü ve panel kenarları)
		_add_mesh(_in, _box(Vector3(0.07, 0.05, 0.05)), Vector3(0, 0.92, pz - 0.1), "dark")
		for sx in [-0.62, 0.62]:
			var dial := _add_mesh(_in, _cyl(0.035, 0.01), Vector3(sx, 0.7, pz + 0.02), "dark", Vector3(75, 0, 0))
			_add_mesh(dial, _cyl(0.03, 0.002), Vector3(0, 0.006, 0), "white")
	_caution_lamp = _add_mesh(_in, _box(Vector3(0.05, 0.03, 0.012)), Vector3(-0.2, 0.82, pz - 0.025), "dark", Vector3(-15, 0, 0))
	for i in 3:
		var lamp := _add_mesh(_in, _cyl(0.009, 0.01), Vector3(-0.355 + i * 0.024, 0.61, pz + 0.01), "dark", Vector3(75, 0, 0))
		_gear_lamps.append(lamp)
	if layout == "fighter":
		for i in 2:
			var dial := _add_mesh(_in, _cyl(0.028, 0.008), Vector3(-0.035 + i * 0.07, 0.56, pz + 0.03), "dark", Vector3(75, 0, 0))
			_add_mesh(dial, _cyl(0.024, 0.002), Vector3(0, 0.005, 0), "white")
	_flood = OmniLight3D.new()
	_flood.light_color = Color(1.0, 0.25, 0.15)
	_flood.light_energy = 0.35
	_flood.omni_range = 1.4
	_flood.shadow_enabled = false
	_flood.position = Vector3(0, 1.0, 0.0)
	_flood.visible = false
	_in.add_child(_flood)
	_build_extra_details()


func _update_lamps() -> void:
	if _caution_lamp == null:
		return
	var powered := vessel.has_power()
	_flood.visible = powered and vessel.cockpit_light
	var cam := get_viewport().get_camera_3d() as FlightCamera
	if cam and cam.target == vessel:
		VesselBuilder.cockpit_panel_material().set_shader_parameter("panel_light", 1.0 if powered and vessel.cockpit_light else 0.0)
	for q in _mfd_quads:
		q.visible = powered
	if not powered:
		_caution_lamp.material_override = VesselBuilder.material("dark")
		for lamp in _gear_lamps:
			lamp.material_override = VesselBuilder.material("dark")
		return
	var warnings := Hud.active_warnings(vessel)
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.35
	_caution_lamp.material_override = VesselBuilder.material("lamp_amber" if not warnings.is_empty() and blink else "dark")
	var deploy := vessel.gear_deploy()
	var gear_mat := "dark"
	if deploy >= 0.99:
		gear_mat = "lamp_green"
	elif deploy > 0.01:
		gear_mat = "lamp_red"
	for lamp in _gear_lamps:
		lamp.material_override = VesselBuilder.material(gear_mat)


# ------------------------------------------------------------------ mesh yardımcıları

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	match mat:
		"red":
			mi.material_override = VesselBuilder.material("dark", Color(0.75, 0.1, 0.08))
		"yellow":
			mi.material_override = VesselBuilder.material("dark", Color(0.95, 0.75, 0.1))
		"white":
			mi.material_override = VesselBuilder.material("dark", Color(0.9, 0.9, 0.88))
		_:
			mi.material_override = VesselBuilder.material(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	return t


## Dış kameradan bakınca pilot canlı görünsün: başını en yakın radar temasına, yoksa dönüş
## yönüne çevirir (kokpit kamerasında başı oyuncu yönetir).
func _auto_head(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() as FlightCamera
	if cam and cam.target == vessel and cam.mode == FlightCamera.Mode.COCKPIT and not cam.is_eva():
		return
	var want := Vector2(-vessel.ctrl_roll * 0.6, vessel.ctrl_pitch * 0.25)
	var radar := vessel.radar()
	if radar:
		var best: Vessel = null
		var bd := 4000.0
		for c in radar.contacts:
			if is_instance_valid(c) and c.team != vessel.team:
				var d: float = c.com_global().distance_to(vessel.com_global())
				if d < bd:
					bd = d
					best = c
		if best:
			var local := part.global_basis.inverse() * (best.com_global() - part.global_position)
			want = Vector2(clampf(atan2(-local.x, -local.z), -2.2, 2.2), clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.6, 1.2))
	pilot.head_yaw = lerp_angle(pilot.head_yaw, want.x, 1.0 - exp(-3.0 * delta))
	pilot.head_pitch = lerpf(pilot.head_pitch, want.y, 1.0 - exp(-3.0 * delta))


## İnce detaylar: konsol anahtar sıraları ve ışıklı etiketler, dikiz aynaları, çizgili fırlatma
## kolu (avcı); tavan paneli ve güneşlikler (sivil).
func _build_extra_details() -> void:
	var label_mat := StandardMaterial3D.new()
	label_mat.albedo_color = Color(0.85, 0.9, 0.85)
	label_mat.emission_enabled = true
	label_mat.emission = Color(0.6, 1.0, 0.7)
	label_mat.emission_energy_multiplier = 0.25
	if layout == "fighter":
		for sx: float in [-0.36, 0.36]:
			var top_y := 0.46 + 0.035
			for row in 6:
				var z := -0.3 + row * 0.1
				# ışıklı etiket şeridi ve 3-4 küçük anahtar
				var lbl := MeshInstance3D.new()
				lbl.mesh = _box(Vector3(0.1, 0.002, 0.008))
				lbl.material_override = label_mat
				lbl.position = Vector3(sx, top_y + 0.001, z - 0.03)
				_in.add_child(lbl)
				for k in 3 + row % 2:
					var sw := _add_mesh(_in, _cyl(0.0045, 0.025), Vector3(sx - 0.04 + k * 0.027, top_y + 0.012, z), "metal", Vector3(-20 if (row + k) % 2 == 0 else 20, 0, 0))
					sw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if row % 3 == 1:
					_add_mesh(_in, _cyl(0.014, 0.012), Vector3(sx + 0.035, top_y + 0.006, z + 0.02), "dark")   # döner düğme
		# dikiz aynaları (kanopi yayında, kanopiyle birlikte açılır)
		var mirror_mat := StandardMaterial3D.new()
		mirror_mat.albedo_color = Color(0.85, 0.88, 0.9)
		mirror_mat.metallic = 1.0
		mirror_mat.roughness = 0.03
		var bow_z := -0.25
		for sx: float in [-0.2, 0.0, 0.2]:
			var m := MeshInstance3D.new()
			m.mesh = _box(Vector3(0.1, 0.035, 0.006))
			m.material_override = mirror_mat
			m.position = _canopy.to_local(_in.to_global(Vector3(sx, 1.12 - absf(sx) * 0.35, bow_z)))
			m.rotation_degrees = Vector3(-8, -sx * 60.0, 0)
			_canopy.add_child(m)
		# fırlatma kolu: sarı-siyah çizgili halka
		for i in 6:
			var seg := _add_mesh(_in, _box(Vector3(0.022, 0.012, 0.012)), Vector3(cos(i * TAU / 6.0) * 0.032, 0.27 + sin(i * TAU / 6.0) * 0.032, -0.03), "dark" if i % 2 == 0 else "yellow")
			seg.rotation.z = i * TAU / 6.0
	else:
		# tavan paneli: anahtar sırası ve ışıklı etiketler
		var ov := _add_mesh(_in, _box(Vector3(0.5, 0.03, 0.32)), Vector3(0, 1.12, -0.12), "interior", Vector3(12, 0, 0))
		for k in 7:
			_add_mesh(ov, _cyl(0.005, 0.03), Vector3(-0.18 + k * 0.06, -0.025, 0.05), "metal", Vector3(180, 0, 0))
		var lbl := MeshInstance3D.new()
		lbl.mesh = _box(Vector3(0.42, 0.002, 0.01))
		lbl.material_override = label_mat
		lbl.position = Vector3(0, -0.017, -0.02)
		ov.add_child(lbl)
		# güneşlikler
		for sx: float in [-0.3, 0.3]:
			_add_mesh(_in, _box(Vector3(0.34, 0.012, 0.16)), Vector3(sx, 1.08, -0.38), "seat", Vector3(-25, 0, 0))


## Biniş / iniş yolu (dünya konumları): [yan duvar üstü, koltuk]. Pilot dışarıdan yan
## duvara tırmanır, oradan koltuğa kayar (iniş tersi).
func boarding_points() -> Array:
	var s := float(part.def.get("_scale", 1.0))
	var seat: Vector3 = (_L["seats"] as Array)[0]
	var side := signf(_exit.x) if absf(_exit.x) > 0.01 else -1.0
	var sill := part.global_transform * Vector3(side * 0.62 * s, 0.6 * s + 0.25, seat.z)
	var top := _in.to_global(seat + Vector3(0, 0.25, 0))
	return [sill, top]
