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
		"panel_z": -0.38, "mfds": [Vector2(-0.205, 0.055), Vector2(0.205, 0.055)], "mfd_size": 0.17,
		"canopy": "bubble", "hinge": Vector3(0, 0.62, 1.2), "open_deg": 55.0,
		"exit": Vector3(-1.7, 0.2, 0.2), "drop": 0.0,
	},
	"civil": {
		"seats": [Vector3(-0.3, 0.32, 0.12), Vector3(0.3, 0.32, 0.12)], "recline": 8.0,
		"pedals": [Vector3(-0.13, 0.14, -0.6), Vector3(0.13, 0.14, -0.6)],
		"panel_z": -0.42, "mfds": [Vector2(-0.47, 0.05), Vector2(-0.18, 0.05), Vector2(0.18, 0.05), Vector2(0.47, 0.05)], "mfd_size": 0.16,
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
## Savaş kanopisinin biçimi: "" standart, "bubble" çerçevesiz uzun balon (tam görüş),
## "framed" çok çerçeveli klasik, "low" alçak ve uzun (gövdeye gömük görünüm)
var canopy_style := ""
## "airliner": burun kokpiti — açılır kanopi yok (cam gövdenin parçası), giriş kapıdan.
## Fırlatma koltuğu olmayan kokpit (yolcu uçağı): ⌫ / FIRLAT çalışmaz.
var no_eject := false
var _drop_override: Variant = null

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
var _gear_lamps: Array[MeshInstance3D] = []
var _flood: OmniLight3D
## Gösterge paneli yüzeyi: yerel (x, u, z) — x sağ, u panel boyunca yukarı, z pilota doğru.
var _panel: Node3D
var _mfds: Array[MfdDisplay] = []
var _mfd_vps: Array[SubViewport] = []
var _mfd_timer := 0.0
var _pedals: Array[Node3D] = []      ## [sol, sağ] (sivilde ardından yardımcı pilotun çifti)
var _needles := {}                   ## ad -> Node3D (analog ibreler)
var _adi: Node3D
var _annunciators: Array[Dictionary] = []
var _lamp_off: Material
var _active := false                 ## kokpit kamerası bu uçakta ya da kamera yakın
var _cv := Vector3.ZERO              ## yumuşatılmış kumanda: (yunuslama, yatış, sapma)
var _ct := 0.0                       ## yumuşatılmış gaz


func setup(p: Dictionary) -> void:
	pilot_name = p.get("pilot", "")
	layout = p.get("layout", "fighter")
	canopy_style = p.get("canopy_style", "")
	no_eject = p.get("no_eject", false)
	_drop_override = p.get("drop", null)
	if pilot_name.is_empty():
		pilot_name = PILOT_NAMES[randi() % PILOT_NAMES.size()]


func on_attached() -> void:
	_L = LAYOUTS.get(layout, LAYOUTS["fighter"]).duplicate()
	if _drop_override != null:
		_L["drop"] = float(_drop_override)
	# iç düzen (koltuk, panel, kumandalar, pilot, cam) gövdenin içine indirilir: kanopi alçak kalır
	_in = Node3D.new()
	_in.name = "Interior"
	_in.position = Vector3(0, float(_L.get("drop", 0.0)), 0)
	part.add_child(_in)
	# gösterge paneli ön yüzü (part_library'deki panel kutusu: merkez (0, 0.69, pz-0.035), -15°, 5 cm kalın)
	_panel = Node3D.new()
	_panel.name = "PanelFace"
	_panel.position = Vector3(0, 0.69, float(_L["panel_z"]) - 0.035) + Basis(Vector3.RIGHT, deg_to_rad(-15.0)) * Vector3(0, 0, 0.025)
	_panel.rotation_degrees = Vector3(-15, 0, 0)
	_in.add_child(_panel)
	_lamp_off = VesselBuilder.material("dark", Color(0.13, 0.12, 0.1))
	_build_canopy()
	_build_pedals()
	if layout == "civil":
		_build_civil_controls()
		_build_civil_switches()
	else:
		_build_controls()
		_build_switches()
	_build_mfds()
	_build_gauges()
	_build_details()
	_build_scale_fill()
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


func _process(delta: float) -> void:
	if part == null or vessel == null:
		return
	var seats: Array = _L["seats"]
	var recline: float = _L["recline"]
	# kumandalar oyuncunun girdisini izler (klavyede ani sıçramasın diye hafif yumuşatılmış)
	var k := 1.0 - exp(-14.0 * delta)
	_cv = _cv.lerp(Vector3(vessel.ctrl_pitch, vessel.ctrl_roll, vessel.ctrl_yaw), k)
	_ct = lerpf(_ct, vessel.ctrl_throttle, k)
	for i in _pedals.size():
		var pd := _pedals[i]
		pd.position.z = float(pd.get_meta("z0")) + (_cv.z if i % 2 == 0 else -_cv.z) * 0.04
	if layout == "civil":
		for y in _yokes:
			y.position.z = y.get_meta("z0") + _cv.x * 0.06
			y.rotation.z = deg_to_rad(-_cv.y * 40.0)
		_throttle.rotation.x = deg_to_rad(lerpf(30.0, -30.0, _ct))
		pilot.visible = occupied
		var s0: Vector3 = seats[0]
		if occupied:
			pilot.pose_seated(s0, recline, _in.to_local(_yoke_grips[0].global_position),
				_in.to_local(_throttle_knob.global_position), _pedals[0].position, _pedals[1].position)
		var s1: Vector3 = seats[1]
		copilot.pose_seated(s1, recline, s1 + Vector3(-0.12, 0.08, -0.32), s1 + Vector3(0.12, 0.08, -0.32),
			_pedals[2].position, _pedals[3].position)
	else:
		_stick.rotation = Vector3(deg_to_rad(_cv.x * 14.0), 0, deg_to_rad(-_cv.y * 14.0))
		_throttle.rotation.x = deg_to_rad(lerpf(25.0, -25.0, _ct))
		pilot.visible = occupied
		if occupied:
			pilot.pose_seated(seats[0], recline,
				_in.to_local(_throttle_knob.global_position), _in.to_local(_stick_grip.global_position),
				_pedals[0].position, _pedals[1].position)
	if occupied:
		_auto_head(delta)
	_active = _is_viewed()
	if _active:
		_update_lamps()
		_update_gauges()
		_mfd_timer -= delta
		if _mfd_timer <= 0.0:
			_mfd_timer = 1.0 / 12.0
			for i in _mfds.size():
				_mfds[i].refresh()
				_mfd_vps[i].render_target_update_mode = SubViewport.UPDATE_ONCE


## Kokpit içi ancak kokpit kamerasında ya da kamera yakındayken canlı tutulur (ekranlar,
## ibreler, lambalar): uzaktaki yapay zekâ uçakları için boşuna çizim yapılmaz.
func _is_viewed() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var fc := cam as FlightCamera
	if fc and fc.target == vessel and fc.mode == FlightCamera.Mode.COCKPIT:
		return true
	return cam.global_position.distance_squared_to(part.global_position) < 18.0 * 18.0


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


## Pilot fırlatma koltuğuyla atlayabilir mi (yolcu uçağı kokpitinde yok).
func can_eject() -> bool:
	return not no_eject


func _build_canopy() -> void:
	if canopy_style == "airliner":
		# burun kokpiti: cam gövdenin parçası (part_library), açılır kanopi yok; çıkış sol kapıdan
		var s0 := float(part.def.get("_scale", 1.0))
		_exit = Vector3(-1.8 * s0, 0.2, 0.9 * s0)
		_canopy = null
		return
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
	match canopy_style:
		"bubble":
			top += 0.08      # kaskın üstünde bol boşluk: her yön görünür
		"low":
			top -= 0.04
	# yarım küre cam: tabanı gövde açıklığının kenarında (alt yarı yok; açılınca altında koyu cam görünmez)
	var c := edge_y - 0.02
	var h := maxf(top - c, 0.2)
	var w := edge_x * (0.94 if canopy_style == "low" else 1.04)
	var z0 := (-0.95 if civil else -0.75) * s
	var z1 := (0.85 if civil else 1.0) * s
	var zc := (z0 + z1) * 0.5
	var half_l := (z1 - z0) * 0.5 * (1.25 if canopy_style in ["bubble", "low"] else 1.05)
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
	elif canopy_style == "bubble":
		# tek parça balon: çerçeve yalnız arkada, önde yay yok
		mat.set_shader_parameter("bow_front", -2.0)
		mat.set_shader_parameter("bow_back", 0.46)
		mat.set_shader_parameter("tint", Color(0.7, 0.62, 0.42))
	elif canopy_style == "framed":
		# klasik: dört yay ve tepede boylamasına kiriş (shader çizgileri + kanopiyle açılan yaylar)
		mat.set_shader_parameter("bow_front", -0.32)
		mat.set_shader_parameter("bow_back", 0.12)
		mat.set_shader_parameter("frame_width", 0.016)
		for zf in [-0.32, -0.1, 0.12, 0.34]:
			var fb := MeshInstance3D.new()
			var ft := TorusMesh.new()
			ft.inner_radius = 0.46
			ft.outer_radius = 0.49
			ft.rings = 32
			ft.ring_segments = 6
			fb.mesh = ft
			fb.material_override = VesselBuilder.material("paint_dark")
			fb.rotation_degrees = Vector3(90, 0, 0)
			fb.scale = Vector3(w / 0.475, 1.0, h / 0.475)
			fb.position = center + Vector3(0, 0, zf * half_l * 2.0) - _canopy.position
			fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_canopy.add_child(fb)
		var spine := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.03, 0.02, half_l * 2.0 * 0.95)
		spine.mesh = sb
		spine.material_override = VesselBuilder.material("paint_dark")
		spine.position = center + Vector3(0, h - 0.005, 0) - _canopy.position
		_canopy.add_child(spine)
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
	# taban kutusu ve körük (körük lövyeyle eğilir)
	_add_mesh(_in, _box(Vector3(0.12, 0.05, 0.12)), Vector3(0, 0.095, -0.12), "dark")
	var boot := _add_mesh(_stick, _cyl(0.05, 0.05), Vector3(0, 0.02, 0), "rubber")
	(boot.mesh as CylinderMesh).top_radius = 0.022
	_add_mesh(_stick, _cyl(0.013, 0.26), Vector3(0, 0.15, 0), "dark")
	_add_mesh(_stick, _cyl(0.017, 0.02), Vector3(0, 0.26, 0), "metal")    # bilezik
	_stick_grip = Node3D.new()
	_stick_grip.position = Vector3(0, 0.31, 0)
	_stick.add_child(_stick_grip)
	# kabza: hafif öne eğik, üstte şapka anahtarı ve kırmızı bomba tuşu, önde tetik
	var grip := _add_mesh(_stick_grip, _cyl(0.024, 0.11), Vector3(0, 0, 0.004), "dark", Vector3(-12, 0, 0))
	(grip.mesh as CylinderMesh).bottom_radius = 0.02
	_add_mesh(_stick_grip, _box(Vector3(0.05, 0.03, 0.06)), Vector3(0, 0.058, -0.006), "dark", Vector3(-12, 0, 0))
	_add_mesh(_stick_grip, _cyl(0.007, 0.012), Vector3(-0.008, 0.078, 0.004), "metal")      # şapka
	_add_mesh(_stick_grip, _box(Vector3(0.012, 0.008, 0.012)), Vector3(0.012, 0.076, -0.01), "red")
	_add_mesh(_stick_grip, _box(Vector3(0.01, 0.006, 0.01)), Vector3(0.016, 0.07, 0.016), "button")
	_add_mesh(_stick_grip, _box(Vector3(0.012, 0.034, 0.012)), Vector3(0, 0.015, -0.03), "metal", Vector3(15, 0, 0))   # tetik
	_add_mesh(_stick_grip, _box(Vector3(0.008, 0.02, 0.016)), Vector3(-0.022, 0.02, 0.0), "button")   # serçe parmak kolu
	# gaz kolu (sol konsol, arka): yarıklı kızak, AB kademesi işareti
	_add_mesh(_in, _box(Vector3(0.012, 0.004, 0.2)), Vector3(-0.34, 0.502, 0.22), "black")
	_add_mesh(_in, _box(Vector3(0.03, 0.003, 0.006)), Vector3(-0.31, 0.502, 0.175), "yellow")
	for i in 5:
		_add_mesh(_in, _box(Vector3(0.012, 0.003, 0.003)), Vector3(-0.312, 0.502, 0.28 - i * 0.025), "white")
	_throttle = Node3D.new()
	_throttle.position = Vector3(-0.34, 0.5, 0.24)
	_in.add_child(_throttle)
	_add_mesh(_throttle, _cyl(0.012, 0.12), Vector3(0, 0.06, 0), "metal")
	_throttle_knob = Node3D.new()
	_throttle_knob.position = Vector3(0, 0.13, 0)
	_throttle.add_child(_throttle_knob)
	_add_mesh(_throttle_knob, _box(Vector3(0.05, 0.045, 0.08)), Vector3.ZERO, "dark")
	_add_mesh(_throttle_knob, _box(Vector3(0.03, 0.03, 0.06)), Vector3(0.018, 0.02, 0.0), "dark", Vector3(0, 0, -20))
	_add_mesh(_throttle_knob, _box(Vector3(0.012, 0.012, 0.012)), Vector3(0.026, 0.012, -0.02), "red")
	_add_mesh(_throttle_knob, _cyl(0.006, 0.01), Vector3(0.03, 0.03, 0.01), "metal")     # telsiz düğmesi
	_add_mesh(_throttle_knob, _box(Vector3(0.01, 0.008, 0.016)), Vector3(-0.026, 0.0, -0.02), "button")


func _build_switches() -> void:
	var v := vessel
	# --- Ön panel (pilota bakan), MFD'lerin altındaki şerit ---
	_add_switch("İNİŞ TAKIMI", _pp(-0.25, -0.118, 0.006), Vector3(75, 0, 0), "gear",
		func() -> bool: return v.gear_down, func() -> void: v.gear_down = not v.gear_down)
	_add_switch("MASTER ARM", _pp(-0.335, -0.118, 0.006), Vector3(75, 0, 0), "guarded",
		func() -> bool: return v.master_arm, func() -> void: v.master_arm = not v.master_arm)
	_add_switch("KANOPİ", _pp(0.25, -0.118, 0.006), Vector3(75, 0, 0), "button",
		func() -> bool: return canopy_open, func() -> void: canopy_open = not canopy_open)
	_add_switch("RADAR", _pp(0.335, -0.118, 0.006), Vector3(75, 0, 0), "toggle",
		func() -> bool: return v.radar_on, func() -> void: v.radar_on = not v.radar_on)
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
		_add_switch(s[0], _pp(-0.5 + i * 0.2, -0.15, 0.006), Vector3(75, 0, 0), s[1], s[2], s[3])
	# orta: iniş takımı kolu panelde, park freni kutuda
	_add_switch("İNİŞ TAKIMI", _pp(0, -0.075, 0.006), Vector3(75, 0, 0), "gear",
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
	# konsolda anahtarın arkasında; panelde (75° eğik) anahtarın altında, yüzeyin hemen önünde
	lbl.position = Vector3(0, -0.012, 0.042) if rot == Vector3.ZERO else Vector3(0, 0.012, 0.04)
	s.add_child(lbl)
	switches.append(s)


## Hangarda büyütülmüş kokpit: iç düzen insan boyunda kalır, ama gövde kabuğu büyür. Taban,
## panel, panel altı ve göz siperi kabuğun iç duvarına kadar genişletilir (yanlarda boşluk
## ve aşağıda açık kuyu görünmesin). Ölçeksiz kokpitte bir şey yapmaz.
func _build_scale_fill() -> void:
	var s := float(part.def.get("_scale", 1.0))
	if s <= PartLibrary.WORLD_SCALE * 1.04:
		return
	var drop := float(_L.get("drop", 0.0))
	var pz: float = _L["panel_z"]
	var civil := layout == "civil"
	var r_in := 0.62 * s - 0.02
	var half := func(y_in: float) -> float:
		var y := y_in + drop
		return sqrt(maxf(r_in * r_in - y * y, 0.0))
	var z0 := (-0.95 if civil else -0.75) * s
	var z1 := (0.85 if civil else 1.0) * s
	# taban: kabuğun açıklığı boyunca, duvardan duvara
	var fw: float = half.call(0.05) * 2.0
	_add_mesh(_in, _box(Vector3(fw, 0.04, z1 - z0)), Vector3(0, 0.045, (z0 + z1) * 0.5), "dark")
	# panel arkası ve altı (panelin hemen arkasında, kenarları duvara kadar)
	var pw: float = minf(half.call(0.69) * 2.0, 3.0)
	var back := _add_mesh(_in, _box(Vector3(pw, 0.36, 0.05)), Vector3(0, 0.69, pz - 0.06), "interior", Vector3(-15, 0, 0))
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var lw: float = half.call(0.38) * 2.0
	_add_mesh(_in, _box(Vector3(lw, 0.36, 0.4)), Vector3(0, 0.36, pz - 0.23), "interior")
	# panelin önünde kabuğa kadar uzanan kapalı burun bölmesi (göz siperi hizasında üst kapak)
	var gw: float = half.call(0.86) * 2.0
	if gw > 0.2:
		var nose_len := absf(z0 - (pz - 0.3)) + 0.05
		_add_mesh(_in, _box(Vector3(gw, 0.04, nose_len)), Vector3(0, 0.86, pz - 0.3 - nose_len * 0.5 + 0.02), "dark")
	# yan duvar sırları: koltuk hizasında kabuk kenarına kadar konsol üstü
	var sill_y := 0.46
	var sw: float = half.call(sill_y)
	var inner := 0.62 if civil else 0.43
	if sw > inner + 0.03:
		for sx in [-1.0, 1.0]:
			_add_mesh(_in, _box(Vector3(sw - inner, 0.05, z1 - z0 - 0.4)), Vector3(sx * (inner + sw) * 0.5, sill_y, (z0 + z1) * 0.5 + 0.1), "interior")


## Panel yüzeyindeki (x, u, öne çıkıntı) noktanın iç düzen (_in) koordinatı.
func _pp(x: float, u: float, off := 0.0) -> Vector3:
	return _panel.transform * Vector3(x, u, off)


## Pedallar: kızak üstünde ileri-geri kayar (sapma girdisi), pilotun ayakları üstünde.
func _build_pedals() -> void:
	var pedals: Array = _L["pedals"]
	var seats: Array = _L["seats"]
	var bases: Array[Vector3] = []
	if layout == "civil":
		for s: Vector3 in seats:
			for p: Vector3 in pedals:
				bases.append(Vector3(s.x + p.x, p.y, p.z))
	else:
		for p: Vector3 in pedals:
			bases.append(p)
	for b in bases:
		_add_mesh(_in, _box(Vector3(0.035, 0.012, 0.2)), Vector3(b.x, 0.076, b.z), "black")       # kızak
		var n := Node3D.new()
		n.position = b
		n.set_meta("z0", b.z)
		_in.add_child(n)
		var plate := Node3D.new()
		plate.rotation_degrees = Vector3(-30, 0, 0)
		n.add_child(plate)
		_add_mesh(plate, _box(Vector3(0.09, 0.13, 0.025)), Vector3.ZERO, "metal")
		for k in 3:   # kaymaz şeritler
			_add_mesh(plate, _box(Vector3(0.08, 0.008, 0.006)), Vector3(0, -0.04 + k * 0.04, 0.013), "black")
		_add_mesh(n, _cyl(0.008, 0.08), Vector3(0, -0.035, -0.035), "dark", Vector3(-60, 0, 0))   # kol
		_pedals.append(n)


func _build_mfds() -> void:
	var spots: Array = _L["mfds"]
	var sz: float = _L["mfd_size"]
	var has_radar := vessel.radar() != null
	var has_weapons := not vessel.weapons().is_empty()
	var cycle: Array[int] = []
	for p in [MfdDisplay.Page.PFD, MfdDisplay.Page.ENGINE, MfdDisplay.Page.HSI, MfdDisplay.Page.RADAR, MfdDisplay.Page.STORES]:
		if (p == MfdDisplay.Page.RADAR and not has_radar) or (p == MfdDisplay.Page.STORES and not has_weapons):
			continue
		cycle.append(p)
	var defaults: Array
	if layout == "civil":
		defaults = [MfdDisplay.Page.PFD, MfdDisplay.Page.HSI, MfdDisplay.Page.ENGINE, MfdDisplay.Page.PFD]
	else:
		defaults = [MfdDisplay.Page.RADAR if has_radar else MfdDisplay.Page.ENGINE,
			MfdDisplay.Page.STORES if has_weapons and not has_radar else MfdDisplay.Page.HSI]
	var screen_shader := preload("res://vessel/mfd_screen.gdshader")
	for i in spots.size():
		var at: Vector2 = spots[i]
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var mfd := MfdDisplay.new()
		mfd.pages = cycle
		mfd.page = defaults[i % defaults.size()]
		mfd.vessel = vessel
		mfd.size = Vector2(256, 256)
		vp.add_child(mfd)
		_in.add_child(vp)
		_mfds.append(mfd)
		_mfd_vps.append(vp)
		# çerçeve: kalın kenar, dört kenarda OSB tuşları, köşelerde parlaklık düğmeleri
		var frame := Node3D.new()
		frame.position = Vector3(at.x, at.y, 0)
		_panel.add_child(frame)
		var bw := sz + 0.046
		_add_mesh(frame, _box(Vector3(bw, bw, 0.016)), Vector3(0, 0, 0.008), "dark")
		_add_mesh(frame, _box(Vector3(sz + 0.006, sz + 0.006, 0.004)), Vector3(0, 0, 0.0145), "black")
		var e := sz * 0.5 + 0.0115
		for k in 5:
			var t := -sz * 0.4 + k * sz * 0.2
			_add_mesh(frame, _box(Vector3(0.015, 0.011, 0.007)), Vector3(t, -e, 0.019), "button")
			_add_mesh(frame, _box(Vector3(0.015, 0.011, 0.007)), Vector3(t, e, 0.019), "button")
		for k in 4:
			var t := -sz * 0.3 + k * sz * 0.2
			_add_mesh(frame, _box(Vector3(0.011, 0.015, 0.007)), Vector3(-e, t, 0.019), "button")
			_add_mesh(frame, _box(Vector3(0.011, 0.015, 0.007)), Vector3(e, t, 0.019), "button")
		for cx in [-e, e]:
			_add_mesh(frame, _cyl(0.0075, 0.01), Vector3(cx, e, 0.019), "metal", Vector3(90, 0, 0))
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(sz, sz)
		quad.mesh = qm
		quad.position = Vector3(0, 0, 0.0185)
		var mat := ShaderMaterial.new()
		mat.shader = screen_shader
		mat.set_shader_parameter("screen_tex", vp.get_texture())
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(quad)
		# ekrana tıklayınca sonraki sayfa
		var side := "SOL" if at.x < 0.0 else "SAĞ"
		if spots.size() > 2:
			side = ["SOL DIŞ", "SOL İÇ", "SAĞ İÇ", "SAĞ DIŞ"][i]
		var sw := CockpitSwitch.create("%s MFD — sayfa değiştir" % side, Vector3(sz, sz, 0.01),
			func() -> bool: return false, mfd.next_page)
		sw.kind = "button"
		sw.position = Vector3(0, 0, 0.022)
		frame.add_child(sw)
		switches.append(sw)


## Analog yedek göstergeler: hava hızı, yapay ufuk küresi, irtifa; yakıt ve hidrolik.
## Kadranlar bir kez çizilen 2x2 doku atlasından, ibreler 3B.
func _build_gauges() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.add_child(GaugeFaces.new())
	_in.add_child(vp)
	var tex := vp.get_texture()
	var civil := layout == "civil"
	var r_small := 0.021 if civil else 0.023
	if civil:
		_adi_at(Vector2(0, 0.105), 0.027)
		_gauge(tex, 0, Vector2(-0.042, 0.034), r_small, "asi")
		_gauge(tex, 1, Vector2(0.042, 0.034), r_small, "alt")
		_gauge(tex, 2, Vector2(-0.325, 0.0), 0.024, "fuel")
		_gauge(tex, 3, Vector2(0.325, 0.0), 0.024, "hyd")
	else:
		_adi_at(Vector2(0, 0.046), 0.028)
		_gauge(tex, 0, Vector2(-0.052, -0.026), r_small, "asi")
		_gauge(tex, 1, Vector2(0.052, -0.026), r_small, "alt")
		_gauge(tex, 2, Vector2(-0.045, -0.152), 0.021, "fuel")
		_gauge(tex, 3, Vector2(0.045, -0.152), 0.021, "hyd")


func _gauge(tex: Texture2D, cell: int, at: Vector2, r: float, key: String) -> void:
	var g := Node3D.new()
	g.position = Vector3(at.x, at.y, 0)
	_panel.add_child(g)
	_add_mesh(g, _cyl(r + 0.006, 0.01), Vector3(0, 0, 0.004), "dark", Vector3(90, 0, 0))
	_add_mesh(g, _torus(r, r + 0.005), Vector3(0, 0, 0.011), "metal", Vector3(90, 0, 0))
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(r * 2.0, r * 2.0)
	face.mesh = qm
	face.position = Vector3(0, 0, 0.0095)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = Vector3(0.5, 0.5, 1)
	m.uv1_offset = Vector3((cell % 2) * 0.5, (cell / 2) * 0.5, 0)
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.6
	face.material_override = m
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(face)
	var needle_mat := StandardMaterial3D.new()
	needle_mat.albedo_color = Color(0.95, 0.95, 0.9)
	needle_mat.emission_enabled = true
	needle_mat.emission = Color(0.95, 0.95, 0.9)
	needle_mat.emission_energy_multiplier = 0.4
	var lengths := [0.82] if key != "alt" else [0.85, 0.55]
	for j in lengths.size():
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, 0.0105 + j * 0.001)
		g.add_child(pivot)
		var l: float = r * float(lengths[j])
		var nm := MeshInstance3D.new()
		nm.mesh = _box(Vector3(0.0024 if j == 0 else 0.0034, l, 0.001))
		nm.position = Vector3(0, l * 0.5 - r * 0.12, 0)
		nm.material_override = needle_mat
		nm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(nm)
		_needles[key + ("" if j == 0 else "2")] = pivot
	_add_mesh(g, _cyl(0.003, 0.003), Vector3(0, 0, 0.012), "black", Vector3(90, 0, 0))


func _adi_at(at: Vector2, r: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(at.x, at.y, 0)
	_panel.add_child(g)
	_add_mesh(g, _torus(r - 0.001, r + 0.009), Vector3(0, 0, 0.004), "dark", Vector3(90, 0, 0))
	_add_mesh(g, _torus(r - 0.001, r + 0.004), Vector3(0, 0, 0.008), "metal", Vector3(90, 0, 0))
	# küre panelin içine gömülü, ön kubbesi görünür; uçak sembolü ve yatış işareti önünde sabit
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	ball.mesh = sm
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://vessel/adi_ball.gdshader")
	ball.material_override = bm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adi = Node3D.new()
	_adi.position = _pp(at.x, at.y, -r * 0.3)
	_in.add_child(_adi)
	_adi.add_child(ball)
	var sym := VesselBuilder.material("lamp_amber")
	for sx in [-1.0, 1.0]:
		var w := _add_mesh(g, _box(Vector3(r * 0.55, 0.0025, 0.002)), Vector3(sx * r * 0.42, 0, r * 0.74), "dark")
		w.material_override = sym
	var dot := _add_mesh(g, _box(Vector3(0.003, 0.003, 0.002)), Vector3(0, 0, r * 0.74), "dark")
	dot.material_override = sym
	var tick := _add_mesh(g, _box(Vector3(0.002, 0.006, 0.002)), Vector3(0, r + 0.002, 0.011), "white")
	tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_gauges() -> void:
	if _needles.has("asi"):
		(_needles["asi"] as Node3D).rotation.z = -deg_to_rad(GaugeFaces.needle_asi(vessel.airspeed() * 3.6))
	if _needles.has("alt"):
		var alt := maxf(vessel.altitude(), 0.0)
		(_needles["alt"] as Node3D).rotation.z = -fposmod(alt, 1000.0) / 1000.0 * TAU
		(_needles["alt2"] as Node3D).rotation.z = -fposmod(alt, 10000.0) / 10000.0 * TAU
	var powered := vessel.has_power()
	if _needles.has("fuel"):
		var f := vessel.fuel_amount() / maxf(vessel.fuel_capacity(), 1.0) if powered else 0.0
		(_needles["fuel"] as Node3D).rotation.z = -deg_to_rad(GaugeFaces.needle_sweep240(f))
	if _needles.has("hyd"):
		(_needles["hyd"] as Node3D).rotation.z = -deg_to_rad(GaugeFaces.needle_sweep240(vessel.hydraulics))
	if _adi:
		# küre ufka göre: üst kutbu yerel yukarı, -z yatay ileri yönü
		var up := vessel.up()
		var f := vessel.forward()
		var fh := f - up * f.dot(up)
		if fh.length_squared() < 1e-6:
			fh = -vessel.global_basis.y if f.dot(up) > 0.0 else vessel.global_basis.y
		var h := Basis.looking_at(fh.normalized(), up)
		_adi.basis = _in.global_basis.orthonormalized().inverse() * h


## Uyarı lambası (annunciator): sönükken yazısı soluk, yanınca renkli zemin üstünde koyu yazı.
func _add_annunciator(at: Vector2, size: Vector2, text: String, key: String, lit: String) -> void:
	var m := _add_mesh(_panel, _box(Vector3(size.x, size.y, 0.005)), Vector3(at.x, at.y, 0.0075), "dark")
	m.material_override = _lamp_off
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 28
	lbl.outline_size = 0
	lbl.pixel_size = 0.0002 if size.x < 0.045 else 0.00024
	lbl.position = Vector3(at.x, at.y, 0.0103)
	lbl.modulate = Color(0.36, 0.36, 0.33)
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lbl.line_spacing = -6.0
	_panel.add_child(lbl)
	_annunciators.append({"mesh": m, "label": lbl, "key": key, "lit": VesselBuilder.material(lit), "on": false})


func _build_annunciators() -> void:
	var items := [
		["YAKIT", "fuel", "lamp_amber"], ["HİD", "hyd", "lamp_amber"], ["MOTOR", "eng", "lamp_amber"], ["TAKIM", "gear", "lamp_red"],
		["STALL", "stall", "lamp_red"], ["FÜZE", "msl", "lamp_red"], ["KANOPİ", "canopy", "lamp_amber"], ["OTOPLT", "ap", "lamp_green"],
	]
	if layout == "civil":
		for side in [-1.0, 1.0]:
			var cx: float = side * 0.325
			_add_annunciator(Vector2(cx, 0.134), Vector2(0.074, 0.024), "ANA İKAZ" if side < 0 else "UYARI",
				"caution" if side < 0 else "warning", "lamp_amber" if side < 0 else "lamp_red")
			for j in 4:
				var it: Array = items[j + (0 if side < 0 else 4)]
				_add_annunciator(Vector2(cx - 0.019 + (j % 2) * 0.038, 0.1 - (j / 2) * 0.022), Vector2(0.035, 0.018), it[0], it[1], it[2])
	else:
		_add_mesh(_panel, _box(Vector3(0.196, 0.05, 0.006)), Vector3(0, -0.098, 0.003), "black")
		for j in items.size():
			var it: Array = items[j]
			_add_annunciator(Vector2(-0.069 + (j % 4) * 0.046, -0.087 - (j / 4) * 0.022), Vector2(0.042, 0.018), it[0], it[1], it[2])
		_add_annunciator(Vector2(-0.343, 0.13), Vector2(0.044, 0.036), "ANA\nİKAZ", "caution", "lamp_amber")
		_add_annunciator(Vector2(0.343, 0.13), Vector2(0.044, 0.036), "UYARI", "warning", "lamp_red")


## Kokpit detayları: savaşta HUD camı ve UFC; ikisinde de uyarı ve takım lambaları,
## yedek göstergeler, kırmızı gece ışığı.
func _build_details() -> void:
	var pz: float = _L["panel_z"]
	if layout == "fighter":
		# HUD: göz siperi üstünde projektör kutusu, iki yan dikme, eğik birleştirici cam
		var hud_frame := Node3D.new()
		hud_frame.position = Vector3(0, 0.915, pz - 0.12)
		_in.add_child(hud_frame)
		_add_mesh(hud_frame, _box(Vector3(0.17, 0.035, 0.11)), Vector3(0, 0.017, -0.02), "dark")
		_add_mesh(hud_frame, _box(Vector3(0.13, 0.004, 0.07)), Vector3(0, 0.036, -0.02), "hud_glass")
		for sx in [-0.098, 0.098]:
			_add_mesh(hud_frame, _box(Vector3(0.012, 0.16, 0.016)), Vector3(sx, 0.1, -0.005), "dark", Vector3(-12, 0, 0))
			_add_mesh(hud_frame, _cyl(0.006, 0.02), Vector3(sx, 0.17, -0.02), "metal", Vector3(0, 0, 90))
		_add_mesh(hud_frame, _box(Vector3(0.208, 0.012, 0.014)), Vector3(0, 0.178, -0.022), "dark")
		var combiner := _add_mesh(hud_frame, _box(Vector3(0.184, 0.14, 0.004)), Vector3(0, 0.105, -0.008), "dark", Vector3(-12, 0, 0))
		var cm := StandardMaterial3D.new()
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.albedo_color = Color(0.5, 0.9, 0.6, 0.07)
		cm.metallic = 0.5
		cm.roughness = 0.02
		combiner.material_override = cm
		var ufc := Node3D.new()
		ufc.position = Vector3(0, 0.135, 0.0)
		_panel.add_child(ufc)
		_add_mesh(ufc, _box(Vector3(0.19, 0.084, 0.02)), Vector3(0, 0, 0.01), "dark")
		_add_mesh(ufc, _box(Vector3(0.14, 0.022, 0.004)), Vector3(0, 0.025, 0.021), "screen_amber")
		for row in 2:
			for col in 5:
				_add_mesh(ufc, _box(Vector3(0.022, 0.016, 0.008)), Vector3(-0.056 + col * 0.028, -0.008 - row * 0.021, 0.022), "button")
		# koltuk: fırlatma kolu ve omuz kemerleri
		_add_mesh(_in, _torus(0.025, 0.04), Vector3(0, 0.27, -0.02), "yellow", Vector3(90, 0, 0))
		for sx in [-0.12, 0.12]:
			_add_mesh(_in, _box(Vector3(0.05, 0.5, 0.01)), Vector3(sx, 0.7, 0.45), "dark", Vector3(12, 0, 0))
		_add_mesh(_in, _box(Vector3(0.1, 0.05, 0.22)), Vector3(-0.34, 0.475, 0.22), "dark")   # gaz kolu gövdesi
	else:
		# pusula (göz siperinin üstü)
		var comp := _add_mesh(_in, _box(Vector3(0.07, 0.05, 0.05)), Vector3(0, 0.92, pz - 0.1), "dark")
		var card := _add_mesh(comp, _cyl(0.018, 0.03), Vector3(0, 0.0, 0.02), "white", Vector3(0, 0, 90))
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_annunciators()
	# iniş takımı lambaları (takım kolunun yanında, dikey)
	var gx := -0.178 if layout == "fighter" else 0.052
	var gu := -0.093 if layout == "fighter" else -0.05
	for i in 3:
		var lamp := _add_mesh(_panel, _cyl(0.0085, 0.008), Vector3(gx, gu - i * 0.024, 0.004), "dark", Vector3(90, 0, 0))
		_gear_lamps.append(lamp)
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
	var powered := vessel.has_power()
	_flood.visible = powered and vessel.cockpit_light
	var cam := get_viewport().get_camera_3d() as FlightCamera
	if cam and cam.target == vessel:
		VesselBuilder.cockpit_panel_material().set_shader_parameter("panel_light", 1.0 if powered and vessel.cockpit_light else 0.0)
	var warnings := Hud.active_warnings(vessel) if powered else PackedStringArray()
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.35
	for a in _annunciators:
		var on := powered and _annunciator_on(a["key"], warnings, blink)
		if on != a["on"]:
			a["on"] = on
			(a["mesh"] as MeshInstance3D).material_override = a["lit"] if on else _lamp_off
			(a["label"] as Label3D).modulate = Color(0.12, 0.07, 0.02) if on else Color(0.36, 0.36, 0.33)
	var gear_mat := "dark"
	if powered:
		var deploy := vessel.gear_deploy()
		if deploy >= 0.99:
			gear_mat = "lamp_green"
		elif deploy > 0.01:
			gear_mat = "lamp_red"
	for lamp in _gear_lamps:
		lamp.material_override = VesselBuilder.material(gear_mat)


func _annunciator_on(key: String, w: PackedStringArray, blink: bool) -> bool:
	match key:
		"fuel": return w.has("YAKIT AZ") or w.has("YAKIT BİTTİ")
		"hyd": return vessel.hydraulics < 0.5
		"eng": return not vessel.engines_running()
		"gear": return w.has("İNİŞ TAKIMI")
		"stall": return w.has("STALL")
		"msl": return w.has("FÜZE")
		"canopy": return canopy_open
		"ap": return vessel.autopilot_active
		"caution": return blink and not w.is_empty()
		"warning": return blink and (w.has("FÜZE") or w.has("PULL UP") or w.has("OVER G") or w.has("STALL"))
	return false


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
		"black":
			mi.material_override = VesselBuilder.material("dark", Color(0.015, 0.015, 0.015))
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
		# fırlatma kolu: sarı-siyah çizgili halka
		for i in 6:
			var seg := _add_mesh(_in, _box(Vector3(0.022, 0.012, 0.012)), Vector3(cos(i * TAU / 6.0) * 0.032, 0.27 + sin(i * TAU / 6.0) * 0.032, -0.03), "dark" if i % 2 == 0 else "yellow")
			seg.rotation.z = i * TAU / 6.0
	else:
		# tavan paneli: iki koltuğun arasında, başların üstünde-arkasında (ileri görüşü kapatmaz);
		# kapı (cam) ile birlikte açılır
		# burun kokpitinde (açılır kapı yok) tavana sabit, gövdenin içinde kalacak kadar alçak
		var ov := _add_mesh(_canopy, _box(Vector3(0.36, 0.03, 0.34)), Vector3(0, 1.225, 0.2) - _canopy.position, "interior", Vector3(-6, 0, 0)) \
			if _canopy != null else _add_mesh(_in, _box(Vector3(0.36, 0.03, 0.34)), Vector3(0, 1.1, 0.3), "interior", Vector3(-6, 0, 0))
		for row in 2:
			for k in 6:
				_add_mesh(ov, _cyl(0.005, 0.03), Vector3(-0.125 + k * 0.05, -0.025, -0.08 + row * 0.12), "metal", Vector3(180, 0, 0))
			var lbl := MeshInstance3D.new()
			lbl.mesh = _box(Vector3(0.3, 0.002, 0.01))
			lbl.material_override = label_mat
			lbl.position = Vector3(0, -0.017, -0.12 + row * 0.12)
			ov.add_child(lbl)
		for k in 3:
			_add_mesh(ov, _cyl(0.012, 0.015), Vector3(-0.1 + k * 0.1, -0.022, 0.13), "dark")


## Biniş / iniş yolu (dünya konumları): [yan duvar üstü, koltuk]. Pilot dışarıdan yan
## duvara tırmanır, oradan koltuğa kayar (iniş tersi).
func boarding_points() -> Array:
	var s := float(part.def.get("_scale", 1.0))
	var seat: Vector3 = (_L["seats"] as Array)[0]
	var side := signf(_exit.x) if absf(_exit.x) > 0.01 else -1.0
	var sill := part.global_transform * Vector3(side * 0.62 * s, 0.6 * s + 0.25, seat.z)
	var top := _in.to_global(seat + Vector3(0, 0.25, 0))
	return [sill, top]
