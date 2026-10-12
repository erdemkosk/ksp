class_name FlightCamera
extends Camera3D
## Kamera modları (C ile değişir):
##   TAKİP   — uçağın arkasından, yönünü takip eder
##   KOKPİT  — pilotun gözünden (FPS). Sağ tık + sürükle: kafa çevir, tekerlek: zoom
##   SERBEST — uçak etrafında serbest yörünge
## EVA'da kamera yürüyen pilotu üçüncü şahıs olarak takip eder.
## Orta tık: bakışı sıfırla.

enum Mode { CHASE, COCKPIT, ORBIT }
const MODE_NAMES := ["TAKİP", "KOKPİT", "SERBEST"]

var mode := Mode.CHASE
var target: Vessel
var pilot: PilotCharacter      ## EVA'daysa dolu
var distance := 24.0
var eva_distance := 4.5
var orbit_yaw := 0.0
var orbit_elevation := deg_to_rad(12.0)
var head_yaw := 0.0
var head_pitch := 0.0
var cockpit_fov := 78.0
## Fareyle uçuşta nişan yönü (dünya); sıfırsa klasik takip kamerası
var mouse_aim := Vector3.ZERO

## His: sarsıntı (trauma 0..1, karesi kadar titrer), G ile baş kayması, hızla FOV.
var trauma := 0.0
var _shake_noise := FastNoiseLite.new()
var _shake_t := 0.0
var _prev_g := 1.0
var _g_head := Vector2.ZERO
## Kokpitte varsayılan bakış biraz aşağı (ekranlar ve burun görünsün)
const COCKPIT_LOOK_DOWN := -0.13

var _heading := 0.0


func _ready() -> void:
	far = 60000.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP


func set_target(v: Vessel) -> void:
	target = v
	pilot = null
	_heading = _desired_heading(v.global_transform, _heading)
	_update(1.0)


func set_eva(p: PilotCharacter) -> void:
	pilot = p
	orbit_yaw = _heading
	orbit_elevation = deg_to_rad(15.0)
	p.face(orbit_yaw)


func is_eva() -> bool:
	return is_instance_valid(pilot)


func mode_name() -> String:
	return "EVA" if is_eva() else MODE_NAMES[mode]


func _unhandled_input(event: InputEvent) -> void:
	# yürürken fare yakalıysa bakış doğrudan fareyle (TPS gibi)
	if event is InputEventMouseMotion and is_eva() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0028 * float(Game.settings.get("mouse_sens", 1.0))
		orbit_yaw -= event.relative.x * k
		orbit_elevation = clampf(orbit_elevation + event.relative.y * k, -0.9, 1.3)
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var rel: Vector2 = event.relative
		if mode == Mode.COCKPIT and not is_eva():
			head_yaw = clampf(head_yaw - rel.x * 0.004, -2.6, 2.6)
			head_pitch = clampf(head_pitch - rel.y * 0.004, -1.2, 1.4)
		else:
			orbit_yaw -= rel.x * 0.005
			orbit_elevation = clampf(orbit_elevation + rel.y * 0.005, -1.2, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if is_eva():
					eva_distance = maxf(eva_distance * 0.9, 1.5)
				elif mode == Mode.COCKPIT:
					cockpit_fov = maxf(cockpit_fov - 4.0, 30.0)
				else:
					distance = maxf(distance * 0.9, 6.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if is_eva():
					eva_distance = minf(eva_distance * 1.1, 30.0)
				elif mode == Mode.COCKPIT:
					cockpit_fov = minf(cockpit_fov + 4.0, 100.0)
				else:
					distance = minf(distance * 1.1, 500.0)
			MOUSE_BUTTON_MIDDLE:
				head_yaw = 0.0
				head_pitch = 0.0
				if mode == Mode.CHASE:
					orbit_yaw = 0.0
	elif event.is_action_pressed("camera_mode") and not is_eva():
		var prev := mode
		mode = ((mode + 1) % Mode.size()) as Mode
		if mode == Mode.COCKPIT and not target.has_pilot():
			mode = Mode.ORBIT
		head_yaw = 0.0
		head_pitch = 0.0
		if mode == Mode.ORBIT and prev != Mode.ORBIT:
			orbit_yaw += _heading
		elif mode == Mode.CHASE:
			orbit_yaw = 0.0


func _process(delta: float) -> void:
	_update(1.0 - exp(-4.0 * delta))
	_apply_feel(delta)


func _update(blend: float) -> void:
	cull_mask = 0xFFFFF
	if is_eva():
		_update_eva()
		return
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var t := target.get_global_transform_interpolated()
	var cockpit := target.cockpit()
	if mode == Mode.COCKPIT and cockpit and cockpit.occupied and cockpit.pilot:
		cockpit.pilot.head_yaw = head_yaw
		cockpit.pilot.head_pitch = head_pitch + COCKPIT_LOOK_DOWN   # doğal bakış: burnun hafif altı
		var rel := target.global_transform.affine_inverse() * cockpit.pilot.eye().global_transform
		global_transform = (t * rel).orthonormalized()
		_set_clip(0.05)
		fov = cockpit_fov
		cull_mask = 0xFFFFF & ~PilotModel.HEAD_LAYER   # kendi kafamızın içini görmeyelim
		return
	if cockpit and cockpit.pilot:
		cockpit.pilot.head_yaw = 0.0
		cockpit.pilot.head_pitch = 0.0

	_set_clip(0.25)
	fov = 70.0
	var focus := t * target.com_local
	if mouse_aim != Vector3.ZERO and mode == Mode.CHASE:
		# fareyle uçuş: kamera nişan yönünün arkasında; uçak nişana doğru döner
		var up := Planet.up_at(focus)
		var wanted := focus - mouse_aim * distance + up * distance * 0.18
		global_position = _safe_position(focus, wanted)
		look_at(focus + mouse_aim * distance * 1.5, up)
		_heading = _desired_heading(t, _heading)
		return
	_heading = lerp_angle(_heading, _desired_heading(t, _heading), blend)
	var yaw := _heading + orbit_yaw if mode == Mode.CHASE else orbit_yaw
	var frame := Planet.local_basis(focus)
	var offset := frame * (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -orbit_elevation) * Vector3(0, 0, distance))
	global_position = _safe_position(focus, focus + offset)
	look_at(focus, frame.y)


func _update_eva() -> void:
	_set_clip(0.1)
	fov = 70.0
	pilot.cam_yaw = orbit_yaw
	var origin := pilot.get_global_transform_interpolated().origin
	var frame := Planet.local_basis(origin)
	# omuz üstü: odak biraz sağda ve göz hizasında (yakınlaşınca omuza daha yakın)
	var side := frame * (Basis(Vector3.UP, orbit_yaw) * Vector3.RIGHT)
	var focus := origin + frame.y * 1.55 + side * clampf(eva_distance * 0.09, 0.15, 0.55) if not pilot.airborne else origin + frame.y * 1.5
	var offset := frame * (Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, -orbit_elevation) * Vector3(0, 0, eva_distance))
	global_position = _safe_position(focus, focus + offset)
	look_at(focus, frame.y)


## Uçağın yerel ufuktaki yön açısı (kamera bunun arkasına yerleşir).
func _desired_heading(t: Transform3D, fallback: float) -> float:
	var frame := Planet.local_basis(t.origin)
	var f := -t.basis.z
	var fx := f.dot(frame.x)
	var fz := f.dot(frame.z)
	if Vector2(fx, fz).length() < 0.1:
		return fallback
	return atan2(-fx, -fz)


## Yakın/uzak düzlem. Uzak düzlem irtifaya göre ufuk mesafesini kapsar (uzaydan tüm
## gezegen görünür); oran ~2 milyonu geçerse Godot'nun frustum hesabı bozuluyor,
## bu yüzden gerekirse yakın düzlem de büyütülür.
func _set_clip(min_near: float) -> void:
	var alt := maxf(Planet.altitude(global_position), 0.0)
	var horizon := sqrt(2.0 * Planet.RADIUS * alt + alt * alt)
	far = clampf(horizon * 1.3 + 30000.0, 60000.0, 2500000.0)
	near = maxf(min_near, far / 1500000.0)


## Kamera asla arazinin, binaların ya da denizin içine girmesin:
## 1) odaktan kameraya ışın — arada engel varsa kamerayı engelin önüne çek (yay kolu)
## 2) arazi/deniz yüzeyinin en az MIN_CLEARANCE üstünde tut (çarpışma yaması dışında da)
const MIN_CLEARANCE := 1.2

func _safe_position(focus: Vector3, wanted: Vector3) -> Vector3:
	var pos := wanted
	var space := get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(focus, wanted, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pos = hit.position + (focus - wanted).normalized() * 0.5 + (hit.normal as Vector3) * 0.4
	var alt := Planet.altitude(pos)
	var ground := maxf(TerrainGen.height(Planet.surface_dir(pos)), 0.0)
	if alt < ground + MIN_CLEARANCE:
		pos += Planet.up_at(pos) * (ground + MIN_CLEARANCE - alt)
	return pos


## Dışarıdan sarsıntı ekle (patlama, çarpma).
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _apply_feel(delta: float) -> void:
	if is_eva() or not is_instance_valid(target) or not target.is_inside_tree():
		trauma = 0.0
		return
	var v := target
	var speed := v.airspeed()
	var cockpit_view := mode == Mode.COCKPIT
	# --- sarsıntı kaynakları (sürekli) ---
	var base := 0.0
	var aoa := absf(v.aoa_deg())
	if speed > 40.0 and aoa > 11.0:
		base = maxf(base, clampf((aoa - 11.0) / 8.0, 0.0, 1.0) * 0.4)           # stall öncesi titreme
	base = maxf(base, Weather.turbulence() * clampf(speed / 150.0, 0.2, 1.0) * 0.5 * (1.0 - smoothstep(1500.0, 6000.0, v.altitude())))  # türbülans
	if speed > 220.0 and v.radar_altitude() < 400.0:
		base = maxf(base, clampf((speed - 220.0) / 200.0, 0.0, 0.3))           # alçak + hızlı
	if v.ctrl_fire and v.master_arm and v.selected_weapon == Vessel.WEAPON_GUN and v.gun_ammo() > 0:
		base = maxf(base, 0.35)                                                  # top titreşimi
	if absf(v.mach() - 1.0) < 0.06:
		base = maxf(base, 0.25)                                                  # ses duvarı
	# --- ani darbeler (iniş, çarpma) ---
	var g := v.g_force
	var jolt := absf(g - _prev_g) - 0.6
	if jolt > 0.0:
		trauma = clampf(trauma + jolt * 0.07, 0.0, 1.0)
	_prev_g = g
	trauma = move_toward(trauma, 0.0, delta * 1.4)
	var amount := maxf(trauma, base)
	_shake_t += delta * (18.0 + 30.0 * amount)
	var k := amount * amount * float(Game.settings.get("shake", 1.0))
	var rx := _shake_noise.get_noise_2d(_shake_t, 0.0) * k
	var ry := _shake_noise.get_noise_2d(0.0, _shake_t) * k
	var rz := _shake_noise.get_noise_2d(_shake_t, 100.0) * k
	var scale := 0.02 if cockpit_view else 0.012
	rotate_object_local(Vector3.RIGHT, rx * scale)
	rotate_object_local(Vector3.UP, ry * scale)
	rotate_object_local(Vector3.BACK, rz * scale * 0.6)
	# --- kokpitte G ile baş kayması ---
	if cockpit_view:
		var want := Vector2(0.0, clampf((g - 1.0) * 0.0025, -0.02, 0.03))
		_g_head = _g_head.lerp(want, 1.0 - exp(-6.0 * delta))
		rotate_object_local(Vector3.RIGHT, -_g_head.y)
		translate_object_local(Vector3(0, -_g_head.y * 0.6, 0))
	# --- hız hissi: FOV genişler ---
	var extra := clampf((speed - 120.0) / 45.0, 0.0, 7.0)
	fov += extra * (0.6 if cockpit_view else 1.0)
