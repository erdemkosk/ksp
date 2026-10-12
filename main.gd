extends Node3D
## Uçuş sahnesi: ortam, arazi, deniz, havaalanı, uçak, kamera, HUD.
##
## Komut satırı (godot ... -- <argümanlar>):
##   --autotest             otomatik pilotla kalkış testi, telemetri yazdırır ve çıkar
##   --screenshot=yol.png --shot-time=6   belirtilen saniyede ekran görüntüsü alıp çıkar
##   --air                  havada başla
##   --debug                aerodinamik debug açık başla
##   --camera=0|1|2         takip / kokpit / serbest
##   --weather=0..4         açık / parçalı / kapalı / fırtına / sis
##   --time=0..2            sabah / öğle / gün batımı
##   --nohelp               yardım kartı kapalı başla
##   --yaw=derece           kamera yörünge açısı (ekran görüntüleri için)
##   --eva                  1 sn sonra pilot dışarı çıkar
##   --alt=metre            havada başlama irtifası
##   --x=metre              havada başlarken doğuya uzaklık (ör. denizin üstü)
##   --hour=saat            başlangıç saati (havaalanı meridyeni)

const CRAFT_PATH := "res://crafts/kartal_1.json"
const RUNWAY_START := Vector3(0, TerrainGen.AIRFIELD_ELEV + 2.2 * PartLibrary.WORLD_SCALE + 0.1, 1100)
const AIR_START_ALTITUDE := 1500.0
const AIR_START_SPEED := 180.0

var world: Node3D
var terrain: Terrain
var vessel: Vessel
var camera: FlightCamera
var player: PlayerController
var hud: Hud
var aero_debug: AeroDebug
var sky: SkyController
var interaction: CockpitInteraction
var pilot: PilotCharacter          ## EVA'daki pilot (yoksa null)
var audio: AudioManager

var _time := 0.0
var mission: MissionManager
var radio: Radio
const BOARD_DISTANCE := 3.5
const EVA_MAX_SPEED := 3.0


func _ready() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	FloatingOrigin.world_root = world

	terrain = Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	world.add_child(Airfield.build(0))
	world.add_child(Airfield.build(1))
	world.add_child(Towns.build())
	world.add_child(AirfieldProps.SkidMarks.new())
	if not Game.args.has("nolife"):
		world.add_child(WorldLife.build())
	var projectiles := ProjectileManager.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)
	_spawn_ground_targets()

	sky = SkyController.new()
	sky.terrain = terrain
	add_child(sky)

	camera = FlightCamera.new()
	var clouds := VolumetricClouds.new()
	camera.add_child(clouds)
	sky.clouds = clouds
	world.add_child(camera)
	if Game.args.has("camera"):
		camera.mode = int(Game.args["camera"]) as FlightCamera.Mode
	if Game.args.has("look"):
		var lk: PackedStringArray = str(Game.args["look"]).split(",")
		camera.head_yaw = deg_to_rad(float(lk[0]))
		camera.head_pitch = deg_to_rad(float(lk[1]))
	if Game.args.has("yaw"):
		camera.orbit_yaw = deg_to_rad(float(Game.args["yaw"]))
	if Game.args.has("airbrake"):
		(func() -> void:
			for m in vessel.get_modules_of(AirbrakeModule):
				m.hold = true).call_deferred()
	if Game.args.has("camdist"):
		camera.distance = float(Game.args["camdist"])
	if Game.args.has("camel"):
		camera.orbit_elevation = deg_to_rad(float(Game.args["camel"]))

	player = PlayerController.new()
	player.camera = camera
	add_child(player)
	interaction = CockpitInteraction.new()
	interaction.camera = camera
	add_child(interaction)
	hud = Hud.new()
	hud.player = player
	hud.camera = camera
	hud.interaction = interaction
	add_child(hud)
	flight_map = FlightMap.new()
	flight_map.main = self
	add_child(flight_map)
	if Game.args.has("map"):
		flight_map.toggle.call_deferred()
	pod_panel = TargetingPodPanel.new()
	pod_panel.main = self
	hud.add_child(pod_panel)
	if Game.args.has("pod"):
		(func() -> void:
			pod_panel.toggle()
			var pm := pod_panel.pod()
			if pm:
				pm.mode = int(Game.args.get("podmode", "0"))
				pm.zoom = int(Game.args.get("podzoom", "1"))
				pm.el = deg_to_rad(-25.0)).call_deferred()
	action_bar = ActionBar.new()
	action_bar.main = self
	hud.add_child(action_bar)
	var pause := PauseMenu.new()
	pause.main = self
	add_child(pause)
	radio = Radio.new()
	hud.radio = radio
	radio.main = self
	add_child(radio)
	audio = AudioManager.new()
	audio.camera = camera
	audio.player = player
	add_child(audio)
	sky.lightning.connect(audio.thunder)
	aero_debug = AeroDebug.new()
	aero_debug.enabled = Game.args.has("debug")
	add_child(aero_debug)

	if Game.args.has("mission"):
		Game.mission = String(Game.args["mission"])
	var mdef := MissionManager.get_def(Game.mission)
	if not Game.resume.is_empty():
		Crew.selected = int(Game.resume.get("pilot", Crew.selected))
		Game.mission = ""
		mdef = {}
		Game.flight_craft = Game.resume.get("craft", {})
		FloatingOrigin.reset_world()
		_spawn(Transform3D(Basis(), RUNWAY_START), Vector3.ZERO)
		FlightSave.apply(self, Game.resume)
		_time = float(Game.resume.get("time", 0.0))
		Game.resume = {}
		hud.show_message("Kayıttan devam ediliyor", 3.0)
	elif not mdef.is_empty():
		match "air_args" if Game.args.has("air") else String(mdef.get("start", "runway")):
			"air_args":
				spawn_in_air()
			"air":
				spawn_in_air(float(mdef.get("alt", AIR_START_ALTITUDE)), 0.0, float(mdef.get("z", 0.0)))
			"runway_hot":
				spawn_on_runway()
				vessel.set_hot()
				vessel.parking_brake = false
			_:
				spawn_on_runway()
		mission = MissionManager.new()
		mission.main = self
		add_child(mission)
		mission.setup()
		if Game.args.has("aiplayer"):
			player.enabled = false
			var pai := AIPilot.new()
			pai.vessel = vessel
			pai.skill = float(Game.args.get("skill", "0.9"))
			vessel.add_child(pai)
	elif Game.args.has("air"):
		spawn_in_air()
	else:
		spawn_on_runway()
	terrain.generate_now()

	if Game.args.has("autotest"):
		player.enabled = false
		var test := preload("res://tests/autotest.gd").new()
		test.main = self
		add_child(test)
	if Game.args.has("crashtest"):
		player.enabled = false
		var ct := preload("res://tests/crash_test.gd").new()
		ct.main = self
		add_child(ct)
	if Game.args.has("starttest") or Game.args.has("gtest"):
		player.enabled = false
		var st := preload("res://tests/systems_test.gd").new()
		st.main = self
		st.mode = "start" if Game.args.has("starttest") else "gtest"
		add_child(st)
	if Game.args.has("weapontest"):
		player.enabled = false
		var wt := preload("res://tests/weapon_test.gd").new()
		wt.main = self
		add_child.call_deferred(wt)
	if Game.args.has("autolandtest"):
		var alt_ := preload("res://tests/autoland_test.gd").new()
		alt_.main = self
		add_child.call_deferred(alt_)
	if Game.args.has("partsprobe"):
		var pp := preload("res://tests/parts_probe.gd").new()
		pp.main = self
		add_child.call_deferred(pp)
	if Game.args.has("ejecttest"):
		var ejt := preload("res://tests/eject_test.gd").new()
		ejt.main = self
		add_child.call_deferred(ejt)
	if Game.args.has("savetest"):
		var svt := preload("res://tests/save_test.gd").new()
		svt.main = self
		add_child.call_deferred(svt)
	if Game.args.has("loaltest"):
		var lt := preload("res://tests/loal_test.gd").new()
		lt.main = self
		add_child.call_deferred(lt)
	if Game.args.has("missionendtest"):
		var met := preload("res://tests/mission_end_test.gd").new()
		met.main = self
		add_child.call_deferred(met)
	if Game.args.has("breakcheck"):
		var bc := preload("res://tests/break_check.gd").new()
		bc.main = self
		add_child.call_deferred(bc)
	if Game.args.has("riverprobe"):
		var rp := preload("res://tests/river_probe.gd").new()
		rp.main = self
		add_child.call_deferred(rp)
	if Game.args.has("aeroprobe"):
		var ap := preload("res://tests/aero_probe.gd").new()
		ap.main = self
		add_child.call_deferred(ap)
	if Game.args.has("walktest"):
		var wkt := preload("res://tests/walk_test.gd").new()
		wkt.main = self
		add_child.call_deferred(wkt)
	if Game.args.has("pulltest"):
		var ptt := preload("res://tests/pull_test.gd").new()
		ptt.main = self
		add_child.call_deferred(ptt)
	if Game.args.has("pulldemo"):
		player.enabled = false
		var pd := preload("res://tests/pull_demo.gd").new()
		pd.main = self
		add_child.call_deferred(pd)
	if Game.args.has("damagedemo"):
		var dd := preload("res://tests/damage_demo.gd").new()
		dd.main = self
		add_child.call_deferred(dd)
	if Game.args.has("mousetest"):
		var mt := preload("res://tests/mouse_test.gd").new()
		mt.main = self
		add_child.call_deferred(mt)
	if Game.args.has("droptest"):
		player.enabled = false
		var drt := preload("res://tests/drop_test.gd").new()
		drt.main = self
		add_child.call_deferred(drt)
	if Game.args.has("bombtest"):
		player.enabled = false
		var bt := preload("res://tests/bomb_test.gd").new()
		bt.main = self
		add_child.call_deferred(bt)
	if Game.args.has("guntest"):
		player.enabled = false
		var gt := preload("res://tests/gun_test.gd").new()
		gt.main = self
		add_child.call_deferred(gt)
	if Game.args.has("dogfight"):
		player.enabled = false
		var dt := preload("res://tests/dogfight_test.gd").new()
		dt.main = self
		add_child.call_deferred(dt)
	if Game.args.has("eva"):
		get_tree().create_timer(1.0).timeout.connect(try_eva)
	# serbest uçuşta düşman yok (F7 ile çağrılabilir); eski testler --drone ile pasif hedef ister
	if mdef.is_empty() and Game.resume.is_empty() and not Game.args.has("nolife") and not Crew._testing():
		_spawn_civil_traffic()
	if mdef.is_empty() and (Game.args.has("drone") or Game.args.has("weapontest") or Game.args.has("dogfight") or Game.args.has("guntest")):
		spawn_enemy()


func _physics_process(delta: float) -> void:
	_time += delta
	if not has_flown and is_instance_valid(vessel) and vessel.has_pilot() and vessel.radar_altitude() > 30.0:
		has_flown = true
	_track_crew(delta)
	_check_autoland_cancel()
	if not is_instance_valid(autoland):
		hud.autoland_status = ""
	if is_instance_valid(pilot):
		FloatingOrigin.check(pilot.global_position)
		if _near_rescue_heli(9.0) and not _rescued:
			_board_heli()
		hud.can_board = _near_cockpit()
	elif is_instance_valid(vessel):
		FloatingOrigin.check(vessel.global_position)
	if Game.args.has("screenshot") and _time >= float(Game.args.get("shot-time", "6")):
		_take_screenshot(Game.args["screenshot"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_runway"):
		spawn_on_runway()
	elif event.is_action_pressed("air_start"):
		spawn_in_air()
	elif event.is_action_pressed("eva"):
		if _near_rescue_heli():
			_board_heli()
			return
		if is_instance_valid(pilot):
			try_board()
		else:
			try_eva()
	elif event.is_action_pressed("spawn_enemy"):
		spawn_enemy(true)
		hud.show_message("Düşman avcı kuzeyde, 2 km irtifada — saldırıyor!", 3.0)
	elif event.is_action_pressed("hangar"):
		go_to_hangar()
	elif event.is_action_pressed("quicksave"):
		quick_save()
	elif event.is_action_pressed("quickload"):
		quick_load()


## Hangara dön (J). Dünya kaydırması ve gezegen merkezi sıfırlanır.
func go_to_hangar() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	close_flight(false)
	FloatingOrigin.reset_world()
	FloatingOrigin.world_root = null
	Planet.reset()
	get_tree().change_scene_to_file("res://hangar/hangar.tscn")


func spawn_on_runway() -> void:
	FloatingOrigin.reset_world()
	_spawn(Transform3D(Basis(), RUNWAY_START), Vector3.ZERO)
	vessel.set_gear_instant(true)
	# soğuk ve karanlık başla (I: otomatik marş). Testlerde ve --hot ile sıcak.
	if Game.args.has("hot") or Game.args.has("autotest") or Game.args.has("crashtest"):
		vessel.set_hot()
	else:
		vessel.set_cold()
		hud.show_message("Soğuk başlangıç — BATARYA, JFS, MOTOR ÇALIŞTIR  (ya da I: otomatik)", 7.0)
	vessel.parking_brake = true
	player.throttle = 0.0
	player.pitch_trim = 0.0


func spawn_in_air(alt := -1.0, east := 0.0, south := 0.0) -> void:
	if alt < 0.0:
		alt = float(Game.args.get("alt", AIR_START_ALTITUDE))
		east = float(Game.args.get("x", 0.0))
		south = float(Game.args.get("z", 0.0))
	# gezegen yüzeyine göre: doğuya `east`, güneye `south` metre, `alt` metre yükseklikte
	var dir := Vector3(east, Planet.RADIUS, south).normalized()
	var pos := Planet.center() + dir * (Planet.RADIUS + alt)
	var frame := Planet.local_basis(pos)
	_spawn(Transform3D(frame, pos), frame * Vector3(0, 0, -AIR_START_SPEED))
	vessel.set_gear_instant(false)
	vessel.set_hot()
	player.throttle = 0.7


func _spawn(xform: Transform3D, velocity: Vector3) -> void:
	_remove_pilot()
	if is_instance_valid(vessel):
		world.remove_child(vessel)
		vessel.queue_free()
	# hangarda tasarlanan uçak varsa onu kullan
	var data: Dictionary = Game.flight_craft if not Game.flight_craft.is_empty() else VesselBuilder.load_craft(String(Game.args.get("craft", CRAFT_PATH)))
	vessel = VesselBuilder.build(data)
	spawned_craft = data
	for i in vessel.parts.size():
		vessel.parts[i].set_meta("bi", i)
	craft_cost = Career.craft_cost(data)
	# kadrodaki seçili pilot ve yetenekleri
	var pinfo := Crew.current()
	for p in vessel.parts:
		for m in p.modules:
			if m is CockpitModule and not pinfo.is_empty():
				m.pilot_name = pinfo["name"]
			elif m is GunModule:
				m.spread_deg *= 1.45 - 0.15 * Crew.skill("nisan")
	player.apply_pilot()
	vessel.transform = xform
	vessel.linear_velocity = velocity
	vessel.request_eva.connect(try_eva)
	vessel.part_destroyed.connect(func(p: Part) -> void: hud.show_message("%s koptu!" % p.title, 2.5))
	vessel.cockpit_lost.connect(_on_cockpit_lost)
	vessel.lights_on = Game.args.has("lights")
	vessel.autopilot_toggle.connect(player.toggle_autopilot)
	vessel.system_message.connect(func(t: String) -> void: hud.show_message(t, 2.5))
	vessel.weapon_fired.connect(func(k: int) -> void:
		if k == 1 and radio:
			radio.on_missile())
	world.add_child(vessel)
	player.autopilot.disengage()
	_focus_vessel()
	terrain.collision.rebuild_now(terrain.to_local(vessel.global_position))


func _focus_vessel() -> void:
	terrain.collision.target = vessel
	camera.set_target(vessel)
	player.vessel = vessel
	hud.vessel = vessel
	aero_debug.vessel = vessel
	audio.vessel = vessel


# ------------------------------------------------------------------ EVA

func try_eva() -> void:
	var cockpit := vessel.cockpit() if is_instance_valid(vessel) else null
	if cockpit == null or not cockpit.occupied:
		return
	if vessel.ground_speed() > EVA_MAX_SPEED or vessel.radar_altitude() > 6.0:
		hud.show_message("Dışarı çıkmak için uçak yerde ve durmuş olmalı")
		return
	cockpit.canopy_open = true
	cockpit.occupied = false
	vessel.parking_brake = true
	player.throttle = 0.0
	player.autopilot.disengage()
	vessel.ctrl_throttle = 0.0

	pilot = PilotCharacter.new()
	pilot.pilot_name = cockpit.pilot_name
	world.add_child(pilot)
	pilot.global_position = cockpit.exit_point()
	pilot.reset_physics_interpolation()
	_animate_board(cockpit, false)
	camera.set_eva(pilot)
	terrain.collision.target = pilot
	terrain.collision.rebuild_now(terrain.to_local(pilot.global_position))
	hud.show_message("%s uçaktan indi" % cockpit.pilot_name)


func try_board() -> void:
	if not _near_cockpit():
		hud.show_message("Uçağa binmek için kokpitin yanına git")
		return
	var cockpit := vessel.cockpit()
	if _boarding:
		return
	_animate_board(cockpit, true)


func _finish_board() -> void:
	_boarding = false
	var cockpit := vessel.cockpit()
	if cockpit == null:
		return
	cockpit.occupied = true
	cockpit.canopy_open = false
	_remove_pilot()
	_focus_vessel()
	camera.mode = FlightCamera.Mode.COCKPIT
	hud.show_message("%s kokpitte" % cockpit.pilot_name)


func _near_cockpit() -> bool:
	if not is_instance_valid(pilot) or not is_instance_valid(vessel):
		return false
	var cockpit := vessel.cockpit()
	if cockpit == null or cockpit.occupied:
		return false
	return pilot.global_position.distance_to(cockpit.part.global_position) < BOARD_DISTANCE + 1.5


func _remove_pilot() -> void:
	if is_instance_valid(pilot):
		pilot.queue_free()
	pilot = null
	hud.can_board = false


func _take_screenshot(path: String) -> void:
	Game.args.erase("screenshot")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Ekran görüntüsü: ", path)
	get_tree().quit()


func _on_cockpit_lost() -> void:
	_lose_aircraft()
	if _ejected:
		hud.show_message("Uçak parçalandı — pilot paraşütle kurtuldu", 4.0)
		return
	camera.mode = FlightCamera.Mode.CHASE
	var name: String = Crew.current().get("name", "Pilot")
	close_flight(true)
	hud.show_message("Kokpit parçalandı — %s kayıp.  J: hangar (yeni pilot seç)" % name, 9.0)


# ------------------------------------------------------------------ hedefler

var enemy: Vessel


## Havaalanının kuzeyinde 2 km irtifada tur atan düşman Kartal. Başta pasif hedef;
## F7 saldırgan bir avcı çıkarır (füze, top, flare kullanır).
func spawn_enemy(aggressive := false) -> void:
	if is_instance_valid(enemy):
		enemy.queue_free()
	var dir := Vector3(1500.0, Planet.RADIUS, -9000.0).normalized()
	var pos := Planet.center() + dir * (Planet.RADIUS + 2000.0)
	var frame := Planet.local_basis(pos)
	var heading := Basis(frame.y, deg_to_rad(-90.0)) * frame   # doğuya doğru
	var ecraft := VesselBuilder.load_craft(CRAFT_PATH)
	ecraft["paint"] = {"scheme": "çöl", "number": "D-%d" % (10 + randi() % 80)}
	enemy = VesselBuilder.build(ecraft)
	enemy.name = "Enemy"
	enemy.craft_name = "Düşman Kartal"
	enemy.team = "düşman"
	enemy.transform = Transform3D(heading, pos)
	enemy.linear_velocity = -heading.z * 200.0
	world.add_child(enemy)
	enemy.set_gear_instant(false)
	enemy.set_hot()
	enemy.lights_on = true
	var ai := AIPilot.new()
	ai.vessel = enemy
	ai.aggressive = aggressive or Game.args.has("dogfight")
	enemy.add_child(ai)


## Pistin kuzeyinde, araziye oturtulmuş bir zırhlı araç konvoyu.
func _spawn_ground_targets() -> void:
	for i in 6:
		var x := 220.0 + i * 28.0
		var z := -2600.0 - (i % 2) * 18.0
		var dir := Vector3(x, Planet.RADIUS, z).normalized()
		var h := maxf(TerrainGen.height(dir), 0.5)
		var pos := Planet.center() + dir * (Planet.RADIUS + h)
		var t := GroundTarget.create(pos, randf() * TAU)
		world.add_child(t)
		t.global_basis = Planet.local_basis(pos).rotated(Planet.up_at(pos), randf() * TAU)


# ------------------------------------------------------------------ kadro / tecrübe

var _flight_closed := false
var crew_lines := PackedStringArray()
var craft_cost := 0
var spawned_craft := {}
var money_lost := 0
var _ejected := false
## En az bir kez havalandı mı (üstteki "bitir" düğmesi ancak uçuştan sonra çıkar)
var has_flown := false
var _pilot_safe := false
var action_bar: ActionBar
var pod_panel: TargetingPodPanel
var flight_map: FlightMap
var _air_time := 0.0
var _was_air := false
var _last_vs := 0.0
var _enemy_alive := false


## Uçuşu kapat: kazanılan XP pilota işlenir (bir kez).
func close_flight(killed: bool) -> void:
	if _flight_closed:
		return
	_flight_closed = true
	crew_lines = Crew.end_flight(killed)
	for line in crew_lines:
		print("KADRO: ", line)
		hud.show_message(line, 4.0)


func _track_crew(delta: float) -> void:
	if not is_instance_valid(vessel) or not vessel.has_pilot():
		return
	var grounded := false
	for m in vessel.modules:
		if m is LandingGearModule and m.grounded:
			grounded = true
	if not grounded:
		_last_vs = vessel.vertical_speed()
		if vessel.radar_altitude() > 30.0:
			_air_time += delta
			if _air_time > 15.0:
				_was_air = true
	elif _was_air:
		_was_air = false
		_air_time = 0.0
		if _last_vs > -1.5:
			Crew.award(30, "ucus")
			hud.show_message("Yumuşak iniş! %.1f m/s  +30 XP" % _last_vs, 3.0)
		elif _last_vs > -3.5:
			Crew.award(15, "ucus")
			hud.show_message("İniş %.1f m/s  +15 XP" % _last_vs, 3.0)
		else:
			hud.show_message("Sert iniş! %.1f m/s" % _last_vs, 3.0)
	# serbest uçuşta düşman düşürme
	if mission == null:
		var alive := is_instance_valid(enemy) and not enemy.parts.is_empty() and enemy.cockpit() != null and enemy.has_pilot()
		if _enemy_alive and not alive:
			Crew.add_kill()
			hud.show_message("Düşman düşürüldü!  +40 XP", 3.0)
			radio.on_kill()
		_enemy_alive = alive


# ------------------------------------------------------------------ otomatik iniş

var autoland: AutoLand


## "Pilot indirsin": en yakın havaalanına otomatik iniş. Elle kumandaya dokununca iptal.
func start_autoland() -> void:
	if is_instance_valid(autoland) or not is_instance_valid(vessel) or not vessel.has_pilot():
		return
	if vessel.radar_altitude() < 5.0 and vessel.ground_speed() < 5.0:
		hud.show_message("Uçak zaten yerde", 2.0)
		return
	player.enabled = false
	player.autopilot.disengage()
	autoland = AutoLand.new()
	autoland.vessel = vessel
	add_child(autoland)
	autoland.finished.connect(_on_autoland_done)
	var af := String(TerrainGen.AIRFIELDS[autoland.airfield]["name"])
	if radio:
		radio.say("%s, %s'na otomatik iniş için yaklaşıyorum." % [radio.callsign(), af], "%s, inbound %s for landing." % [radio.callsign(), af], radio.callsign().to_upper())
	hud.show_message("OTOMATİK İNİŞ: %s  (iptal: kumandaya dokun)" % af, 4.0)


func cancel_autoland() -> void:
	if is_instance_valid(autoland):
		autoland.queue_free()
		autoland = null
		player.enabled = true
		player.throttle = vessel.ctrl_throttle
		hud.show_message("Otomatik iniş iptal — kumanda sende", 2.5)


func _on_autoland_done(ok: bool) -> void:
	autoland = null
	player.enabled = true
	player.throttle = 0.0
	if ok:
		Crew.award(25, "ucus")
		hud.show_message("Pilot uçağı indirdi  +25 XP", 3.5)
		if radio:
			radio.say("%s, hoş geldiniz. Pisti boşaltın." % radio.callsign(), "%s, welcome back." % radio.callsign())
	else:
		hud.show_message("Otomatik iniş başarısız", 3.0)


func _check_autoland_cancel() -> void:
	if not is_instance_valid(autoland) or Game.args.has("autolandtest"):
		return
	if absf(Input.get_axis("pitch_down", "pitch_up")) > 0.5 or absf(Input.get_axis("roll_left", "roll_right")) > 0.5:
		cancel_autoland()
	hud.autoland_status = autoland.status() if is_instance_valid(autoland) else ""


# ------------------------------------------------------------------ fırlatma koltuğu / uçuş sonu

## Fırlatma: kanopi atılır, koltuk roketi pilotu ~40 m/s ile uçağın tavanından fırlatır,
## 1.3 sn sonra paraşüt açılır. Kamera pilotu izler; uçak pilotsuz devam eder (düşer).
func eject() -> void:
	var cockpit := vessel.cockpit() if is_instance_valid(vessel) else null
	if cockpit == null or not cockpit.occupied or is_instance_valid(pilot):
		return
	if is_instance_valid(autoland):
		autoland.queue_free()
		autoland = null
		player.enabled = true
	var up := vessel.up()
	var start := cockpit.part.global_position + up * 1.6
	cockpit.occupied = false
	cockpit.jettison_canopy()
	_lose_aircraft()
	player.autopilot.disengage()
	_ejected = true
	pilot = PilotCharacter.new()
	pilot.pilot_name = cockpit.pilot_name
	world.add_child(pilot)
	pilot.global_position = start
	pilot.reset_physics_interpolation()
	pilot.add_collision_exception_with(vessel)
	pilot.eject(vessel.linear_velocity + up * 40.0, vessel.global_basis)
	pilot.landed.connect(_on_pilot_landed)
	camera.set_eva(pilot)
	camera.eva_distance = 16.0
	terrain.collision.target = pilot
	terrain.collision.rebuild_now(terrain.to_local(pilot.global_position))
	Sfx.play_at("missile_launch.ogg", start, 4.0, 0.8, 3000.0)
	camera.add_trauma(0.9)
	hud.show_message("FIRLATMA!  %s paraşütle iniyor — A/D W/S: yönlendir" % cockpit.pilot_name, 5.0)
	if radio:
		radio.say("Mayday, %s fırlatıyor!" % radio.callsign(), "Mayday, %s ejecting!" % radio.callsign(), radio.callsign().to_upper())
		radio.say("%s, fırlatma görüldü, kurtarma ekibi yola çıktı." % radio.callsign(), "%s, ejection observed, rescue launched." % radio.callsign())
	if mission and mission.state == "running":
		mission.state = "fail"
		mission.fail_reason = "pilot uçağı terk etti"


func _on_pilot_landed(impact: float) -> void:
	terrain.collision.rebuild_now(terrain.to_local(pilot.global_position))
	camera.eva_distance = 7.5
	if impact > 12.0:
		hud.show_message("%s yere çok sert çarptı (%.0f m/s) — kayıp." % [pilot.pilot_name, impact], 8.0)
		pilot.enabled = false
		close_flight(true)
		_show_report.call_deferred("PİLOT KAYIP", PackedStringArray(["%s paraşüt açılmadan yere çarptı." % pilot.pilot_name, "Fırlatma çok alçakta ya da ters uçarken yapıldı."]), false)
		return
	_pilot_safe = true
	Crew.award(20, "dayanim")
	hud.show_message("%s güvenle yere indi. Kurtarma helikopteri geliyor  ·  1: uçuşu hemen bitir" % pilot.pilot_name, 6.0)
	_send_rescue()
	if radio:
		radio.say("%s, sizi görüyoruz, kurtarma helikopteri yolda. Yerinizde kalın." % radio.callsign(), "%s, we have your position, rescue helo inbound." % radio.callsign())


## Uçuş bitirilebilir mi: uçak yerde durmuş (pilot içinde) ya da pilot paraşütle inmiş/yerde.
func can_end_flight() -> bool:
	if is_instance_valid(pilot):
		return not pilot.airborne
	if not is_instance_valid(vessel) or not vessel.has_pilot():
		return false
	return vessel.radar_altitude() < 6.0 and vessel.ground_speed() < 2.0


func end_flight() -> void:
	if not can_end_flight():
		hud.show_message("Uçuşu bitirmek için uçak yerde durmalı", 2.5)
		return
	var info := PackedStringArray()
	info.append("%s  ·  %s" % [vessel.craft_name if is_instance_valid(vessel) else "", Crew.current().get("name", "")])
	info.append("Uçuş süresi %d:%02d" % [int(_time) / 60, int(_time) % 60])
	if mission and not mission.def.is_empty():
		info.append("Görev: %s — %s" % [mission.def.get("title", ""), "BAŞARILI" if mission.state == "success" else ("başarısız, " + mission.fail_reason if mission.state == "fail" else "yarıda bırakıldı")])
	if _rescued:
		info.append("Pilot fırlatma koltuğuyla kurtuldu ve kurtarma helikopteriyle üsse getirildi.")
	elif _ejected:
		info.append("Pilot fırlatma koltuğuyla kurtuldu, uçak kaybedildi.")
	else:
		var near: Array = radio.nearest_airfield(vessel) if radio else [0, INF, 0]
		if float(near[1]) < 2500.0:
			Crew.award(10, "ucus")
			info.append("Uçak %s'nda park halinde. Güvenli dönüş +10 XP" % String(TerrainGen.AIRFIELDS[near[0]]["name"]))
		else:
			info.append("Uçak meydan dışında, araziye indi.")
	if money_lost > 1:
		info.append("Uçak kaybı (sigorta payı): -%d ₺" % money_lost)
	if mission and mission.money_gain > 0:
		info.append("Görev ödülü: +%d ₺" % mission.money_gain)
	if not Career.sandbox():
		info.append("Kasa: %d ₺" % Career.money)
	close_flight(false)
	info.append_array(crew_lines)
	_show_report("UÇUŞ RAPORU", info, true)


func _show_report(title: String, info: PackedStringArray, ok: bool) -> void:
	FlightReport.open(self, title, info, ok)


## Uçak kaybı: kariyerde sigorta payı (parça bedelinin yarısı) bir kez düşülür.
func _lose_aircraft() -> void:
	if money_lost > 0 or craft_cost <= 0:
		return
	money_lost = maxi(Career.aircraft_lost(craft_cost), 1)
	if money_lost > 1:
		hud.show_message("Uçak kaybı: -%d ₺ (sigorta payı)" % money_lost, 4.0)


# ------------------------------------------------------------------ uçuş kaydı

func quick_save() -> void:
	if is_instance_valid(pilot) or not is_instance_valid(vessel) or not vessel.has_pilot():
		hud.show_message("Kayıt için pilot uçakta olmalı", 2.5)
		return
	if FlightSave.save(self):
		hud.show_message("Uçuş kaydedildi (F10 ya da ana menü → Devam et)" + ("  ·  görev ilerlemesi kaydedilmez" if mission and not mission.def.is_empty() else ""), 3.0)
		Sfx.play_ui("switch_3.ogg", -4.0, 1.2)
	else:
		hud.show_message("Kayıt başarısız", 2.5)


func quick_load() -> void:
	var d := FlightSave.load_data()
	if d.is_empty():
		hud.show_message("Kayıt yok (F9 ile kaydet)", 2.5)
		return
	Game.resume = d
	close_flight(false)
	FloatingOrigin.reset_world()
	FloatingOrigin.world_root = null
	Planet.reset()
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ kurtarma helikopteri

var rescue_heli: Helicopter
var _rescued := false


## Paraşütle inen pilota en yakın meydan yönünden, 3.5 km öteden bir kurtarma helikopteri gelir.
func _send_rescue() -> void:
	if is_instance_valid(rescue_heli) or not is_instance_valid(pilot):
		return
	var near: Array = radio.nearest_airfield(vessel) if radio and is_instance_valid(vessel) else [0, 0.0, 0]
	var af: Dictionary = TerrainGen.AIRFIELDS[near[0]]
	var xz: Vector2 = af["xz"]
	var base := MissionManager.world_point(xz.x, xz.y, 0.0)
	var pp := pilot.global_position
	var up := Planet.up_at(pp)
	var dir := base - pp
	dir = (dir - up * dir.dot(up))
	dir = dir.normalized() if dir.length() > 10.0 else Planet.local_basis(pp).x
	rescue_heli = Helicopter.create_heli("rescue")
	rescue_heli.home_xz = xz
	rescue_heli.rescue_target = pilot
	world.add_child(rescue_heli)
	var start := pp + dir * 3500.0 + up * 160.0
	rescue_heli.global_transform = Transform3D(Planet.local_basis(start), start)
	rescue_heli.landed_near_target.connect(func() -> void:
		hud.show_message("Kurtarma helikopteri indi — yanına yürü (F ile bin)", 5.0))
	rescue_heli.departed.connect(func() -> void:
		get_tree().create_timer(5.0).timeout.connect(end_flight))
	if radio:
		radio.say("%s, kurtarma helikopteri sizi gördü, iki dakikaya yanınızda." % radio.callsign(),
			"%s, rescue helo has you in sight." % radio.callsign(), "KURTARMA 1")


func _near_rescue_heli(dist := 14.0) -> bool:
	return is_instance_valid(rescue_heli) and is_instance_valid(pilot) and not pilot.airborne \
		and rescue_heli.state == "landed" and pilot.global_position.distance_to(rescue_heli.global_position) < dist


func _board_heli() -> void:
	if _rescued:
		return
	_rescued = true
	pilot.set_physics_process(false)
	pilot.collision_layer = 0
	pilot.collision_mask = 0
	pilot.reparent(rescue_heli)
	pilot.position = Vector3(0, 0.9, -0.6)
	pilot.rotation = Vector3.ZERO
	pilot.model.pose_seated(Vector3(0, 0.42, 0), 10.0, Vector3(-0.15, 0.6, -0.3), Vector3(0.15, 0.6, -0.3),
		Vector3(-0.15, 0.05, -0.55), Vector3(0.15, 0.05, -0.55))
	camera.eva_distance = 22.0
	rescue_heli.lift_off()
	Crew.award(15, "ucus")
	hud.show_message("%s helikopterde — üsse dönülüyor" % pilot.pilot_name, 4.0)
	if radio:
		radio.say("Kurtarma 1, pilot alındı, üsse dönüyoruz.", "Rescue one, survivor aboard, RTB.", "KURTARMA 1")


## Serbest uçuşta iki meydan arasında dolaşan sivil uçak (radarda gri).
func _spawn_civil_traffic() -> void:
	var craft := VesselBuilder.load_craft("res://crafts/kirlangic.json")
	craft["paint"] = {"scheme": "sivil", "number": "TC-JHN"}
	var c := VesselBuilder.build(craft)
	c.name = "Civil"
	c.craft_name = "Sivil uçak TC-JHN"
	c.team = "sivil"
	var pos := MissionManager.world_point(-9000.0, -6000.0, 900.0)
	var frame := Planet.local_basis(pos)
	var basis := Basis(frame.y, deg_to_rad(-300.0)) * frame
	c.transform = Transform3D(basis, pos)
	c.linear_velocity = -basis.z * 75.0
	world.add_child(c)
	c.set_gear_instant(false)
	c.set_hot()
	c.lights_on = true
	var ai := AIPilot.new()
	ai.vessel = c
	ai.aggressive = false
	ai.altitude = 900.0
	ai.speed = 75.0
	ai.leg_time = 120.0
	ai.skill = 0.5
	c.add_child(ai)


# ------------------------------------------------------------------ biniş / iniş animasyonu

var _boarding := false


## Pilot kokpite tırmanır (board) ya da kokpitten iner. Konumlar her karede uçağa göre
## hesaplanır (kayan orijin kaydırması animasyonu bozmaz).
func _animate_board(cockpit: CockpitModule, board: bool) -> void:
	if not is_instance_valid(pilot):
		return
	_boarding = true
	pilot.enabled = false
	pilot.set_physics_process(false)
	cockpit.canopy_open = true
	var ground_local := vessel.to_local(pilot.global_position if board else cockpit.exit_point())
	var dur := 1.8
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(pilot) or not is_instance_valid(vessel):
			return
		var pts: Array = cockpit.boarding_points()
		var g := vessel.to_global(ground_local)
		var path := [g, pts[0], pts[1]] if board else [pts[1], pts[0], g]
		var k := t * 2.0
		var p: Vector3 = (path[0] as Vector3).lerp(path[1], clampf(k, 0.0, 1.0)) if k < 1.0 else (path[1] as Vector3).lerp(path[2], clampf(k - 1.0, 0.0, 1.0))
		pilot.global_position = p
		# yüz kokpite dönük, tırmanırken bacaklar adım atar
		var fr := Planet.local_basis(p)
		var to_c: Vector3 = fr.inverse() * ((pts[1] as Vector3) - p)
		if Vector2(to_c.x, to_c.z).length() > 0.05:
			pilot.model.rotation.y = atan2(-to_c.x, -to_c.z) if board else atan2(to_c.x, to_c.z)
		pilot.model.pose_walk(t * 14.0, 0.9, false, 0.0, 0.0, 0.25 + 0.2 * sin(t * PI))
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if board:
		tw.tween_callback(_finish_board)
	else:
		tw.tween_callback(func() -> void:
			_boarding = false
			if is_instance_valid(pilot):
				pilot.set_physics_process(true)
				pilot.enabled = true
				pilot.velocity = Vector3.ZERO)
