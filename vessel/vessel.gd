class_name Vessel
extends RigidBody3D
## Parçalardan oluşan araç. Tek bir RigidBody: parça başına joint yok.
## Kütle, ağırlık merkezi ve atalet parçalardan hesaplanır.
## Eksenler: -Z ileri, +Y yukarı, +X sağ.
##
## Hasar: çarpışmada temas eden parçaya darbe hızına göre hasar verilir. Canı biten parça
## kopar; ona yalnızca onun üzerinden bağlı parçalar da (komşuluk grafiğine göre) onunla
## birlikte ayrı bir enkaz olarak düşer. Kalan uçağın kütlesi/aerodinamiği anında değişir.

const GRAVITY := 9.81
const IMPACT_SAFE := 7.0          ## bu dik çarpma hızının altında hasar yok (m/s)
const SPAWN_GRACE := 1.5          ## doğduktan sonra hasarsız süre (s)

## Kokpitteki "dışarı çık" kolu çekildi.
signal request_eva
signal part_destroyed(part: Part)
## Kokpit yok oldu (pilot kaybedildi)
signal cockpit_lost
## Silah ateşlendi (1: füze, 2: bomba) — telsiz çağrıları için
signal weapon_fired(kind: int)
## Sistem mesajı (otomatik marş adımları vb.)
signal system_message(text: String)

var craft_name := ""
var parts: Array[Part] = []
var modules: Array[PartModule] = []

# Kontrol girdileri: oyuncu veya yapay zeka yazar.
var ctrl_pitch := 0.0      ## +1 burun yukarı
var ctrl_yaw := 0.0        ## +1 burun sağa
var ctrl_roll := 0.0       ## +1 sağa yatış
var ctrl_throttle := 0.0   ## 0..1
var ctrl_brakes := false
var gear_down := true      ## komut; takımların gerçek konumu LandingGearModule.deploy
var parking_brake := false
## Elektrik ve marş sistemleri
var battery_on := true
var jfs_on := false            ## marş türbini (Jet Fuel Starter)
var jfs_spool := 0.0           ## 0..1
var master_arm := false
var cockpit_light := false
var engine_on: bool:           ## en az bir motor çalışıyor mu (okuma)
	get:
		return engines_running()
var lights_on := false
var sas := true
## Hidrolik sistem: kumanda yüzeylerini hareket ettirir. Sızıntıyla kapasite düşer; motorlar
## dururken yalnız yedek (RAT) basıncı kalır. 0..1
var hydraulics := 1.0
var hydraulic_leak := false
## Kısmi arızalar (HUD uyarı satırları): anahtar -> metin
var failures := {}

var com_local := Vector3.ZERO
var g_force := 1.0
## Yerçekimi hariç hissedilen ivme (m/s², dünya çerçevesi), yumuşatılmış
var proper_accel := Vector3.ZERO
## Herhangi bir parçanın en yüksek yük oranı (1 = dayanım sınırı)
var max_stress := 0.0
var autopilot_active := false
## Takım: aynı takımdakiler birbirini hedeflemez
var team := "oyuncu"
## Radarda seçilen hedef (tık / F4): füze arayıcısı önce buna kilitlenir.
var designated: Vessel
## Seçili silah: 0 = top, 1 = ısı güdümlü füze
var selected_weapon := 0
const WEAPON_GUN := 0
const WEAPON_MISSILE := 1
const WEAPON_BOMB := 2
const WEAPON_CARGO := 3
const WEAPON_RADAR := 4
const WEAPON_LGB := 5
## Silah kartlarının ve V ile dönüşün sırası
const WEAPON_ORDER := [WEAPON_GUN, WEAPON_MISSILE, WEAPON_RADAR, WEAPON_BOMB, WEAPON_LGB, WEAPON_CARGO]
## Radar yayını (kapalıyken düşman RWR'ı seni görmez; IRST pasif çalışmaya devam eder)
var radar_on := true
## Karşı tedbir otomatik programı (füze 4 km'ye girince flare / chaff kendiliğinden)
var cm_auto := false
## Ateş tetiği (oyuncu/AI yazar)
var ctrl_fire := false
## Kokpitteki otopilot düğmesi
signal autopilot_toggle

var _mass_timer := 0.0
var _prev_velocity := Vector3.ZERO
var _age := 0.0
var _pending_damage := {}      # Part -> hasar (fizik geri çağrısında toplanır)
var _collider_part := {}       # CollisionShape3D -> Part
var _neighbors := {}           # Part -> Array[Part]


func _ready() -> void:
	can_sleep = false
	gravity_scale = 0.0   # yerçekimini gezegen merkezine doğru kendimiz uyguluyoruz
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 16
	collision_layer = 2
	collision_mask = 1 | 2
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.3
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	for part in parts:
		part.vessel = self
		for module in part.modules:
			module.vessel = self
			modules.append(module)
		for cs in part.colliders:
			_collider_part[cs] = part
	_build_neighbors()
	var lights := VesselLights.new()
	lights.name = "Lights"
	add_child(lights)
	lights.setup(self)
	var sounds := VesselAudio.new()
	sounds.name = "Audio"
	add_child(sounds)
	sounds.setup(self)
	var aero := AeroFx.new()
	aero.name = "AeroFx"
	aero.vessel = self
	add_child(aero)
	recalc_mass()
	for module in modules:
		module.on_attached()
	AeroLinks.rebuild(self)
	_prev_velocity = linear_velocity


func _physics_process(delta: float) -> void:
	_age += delta
	update_hydraulics(delta)
	_update_fuel_dump(delta)
	if parts.is_empty():
		freeze = true   # tüm parçalar koptu: boş gövde artık bir şey değil
		return
	_mass_timer -= delta
	if _mass_timer <= 0.0:
		_mass_timer = 0.25
		recalc_mass()
	# Küre gezegen: yerçekimi merkeze doğru, irtifayla azalır
	apply_central_force(Planet.gravity_at(com_global()) * mass)
	_update_systems(delta)
	for part in parts:
		part.aero_load = Vector3.ZERO
	for module in modules:
		module.physics_tick(delta)
	for part in parts:
		Hydro.apply(self, part, delta)
	var accel := (linear_velocity - _prev_velocity) / delta
	_prev_velocity = linear_velocity
	var proper := accel - Planet.gravity_at(com_global())
	proper_accel = proper_accel.lerp(proper, 0.25)   # tek karelik temas sıçramalarını yumuşat
	g_force = lerpf(g_force, proper.dot(global_basis.y) / GRAVITY, 0.2)
	_structural_loads(delta)
	_apply_pending_damage()


## Yapısal yük: her parçanın bağlantısına binen kuvvet = parçaya etkiyen dış kuvvetler
## (kaldırma, sürükleme, itki) − parçanın kendi ataleti (kütle × hissedilen ivme).
## Dayanımı aşan parça hasar alır; %60 aşarsa anında kopar.
func _structural_loads(delta: float) -> void:
	max_stress = 0.0
	if _age < SPAWN_GRACE:
		return
	for part in parts:
		var load := (part.aero_load - proper_accel * part.get_mass()).length()
		var ratio := load / maxf(part.strength, 1.0)
		part.stress = lerpf(part.stress, ratio, 0.3)
		max_stress = maxf(max_stress, part.stress)
		if part.stress > 1.6:
			_pending_damage[part] = part.max_hp * 10.0
		elif part.stress > 1.0:
			_pending_damage[part] = _pending_damage.get(part, 0.0) + part.max_hp * (part.stress - 1.0) * 6.0 * delta


## Fizik motorunun temas listesi: dik çarpma hızına göre hasar topla.
## (Burada sahne ağacı değiştirilemez; hasar _physics_process'te uygulanır.)
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _age < SPAWN_GRACE:
		return
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		var vn := absf(state.get_contact_local_velocity_at_position(i).dot(n))
		if vn < IMPACT_SAFE:
			continue
		var owner_id := shape_find_owner(state.get_contact_local_shape(i))
		var part: Part = _collider_part.get(shape_owner_get_owner(owner_id))
		if part:
			var dmg := pow(vn - IMPACT_SAFE, 2.0) * 5.0
			_pending_damage[part] = maxf(_pending_damage.get(part, 0.0), dmg)


func damage_part(part: Part, amount: float) -> void:
	if part in parts and amount > 0.0:
		_pending_damage[part] = _pending_damage.get(part, 0.0) + amount


func _apply_pending_damage() -> void:
	if _pending_damage.is_empty():
		return
	var pending := _pending_damage
	_pending_damage = {}
	for part: Part in pending:
		if not part in parts:
			continue
		part.hp -= pending[part]
		if part.hp <= 0.0:
			destroy_part(part)
		else:
			DamageFx.for_part(part).refresh()
			for m in part.modules:
				m.on_damaged(pending[part])
			_hydraulic_hit(part, pending[part])


## Parçayı yok et: patlama efekti, ondan kopan alt grupları enkaz olarak ayır.
func destroy_part(part: Part) -> void:
	if not part in parts:
		return
	var fx_size := clampf(part.get_mass() / 400.0, 0.6, 3.0)
	if part.submerged > 0.0:
		Effects.splash(get_parent(), part.global_position, up(), fx_size * 1.5)
		Sfx.splash(part.global_position, fx_size * 1.5)
	else:
		Effects.explosion(get_parent(), part.global_position, up(), fx_size)
		Sfx.explosion(part.global_position, fx_size)
	var was_cockpit := part == cockpit_part()
	var remaining: Array[Part] = []
	for p in parts:
		if p != part:
			remaining.append(p)
	# kök: kokpit (yoksa en ağır parça); köke bağlı kalanlar uçakta kalır
	var root: Part = cockpit_part() if not was_cockpit else null
	if root == null:
		for p in remaining:
			if root == null or p.get_mass() > root.get_mass():
				root = p
	var kept: Array[Part] = []
	if root:
		kept = _component(root, remaining)
	var loose: Array[Part] = []
	for p in remaining:
		if not p in kept:
			loose.append(p)
	_spawn_debris([part])
	while not loose.is_empty():
		var group := _component(loose[0], loose)
		_spawn_debris(group)
		for p in group:
			loose.erase(p)
	part_destroyed.emit(part)
	recalc_mass()
	AeroLinks.rebuild(self)
	if was_cockpit:
		cockpit_lost.emit()


func _component(start: Part, pool: Array[Part]) -> Array[Part]:
	var out: Array[Part] = [start]
	var stack: Array[Part] = [start]
	while not stack.is_empty():
		var p: Part = stack.pop_back()
		for q: Part in _neighbors.get(p, []):
			if q in pool and not q in out:
				out.append(q)
				stack.append(q)
	return out


func _spawn_debris(group: Array[Part]) -> void:
	var d := Debris.new()
	d.transform = transform
	get_parent().add_child(d)
	# kopan parça uçağın içinden ayrılır: aralarında çarpışma olmasın (zincirleme hasar yapmasın)
	d.add_collision_exception_with(self)
	add_collision_exception_with(d)
	# kopma yüzleri: kalan komşularla birleşim yerine yırtık metal kapak + kıvılcım + duman
	for part in group:
		for q: Part in _neighbors.get(part, []):
			if q in parts and not q in group:
				DamageFx.tear(part, q)
	var total := 0.0
	var moment := Vector3.ZERO
	for part in group:
		parts.erase(part)
		for m in part.modules:
			modules.erase(m)
			if m is EngineModule:
				m.thrust = 0.0
			m.vessel = null
		for cs in part.colliders:
			_collider_part.erase(cs)
			cs.reparent(d, true)
		part.reparent(d, true)
		d.parts.append(part)
		total += part.get_mass()
		moment += part.position * part.get_mass()
	d.mass = maxf(total, 10.0)
	d.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	d.center_of_mass = moment / maxf(total, 1.0)
	var com := global_transform * d.center_of_mass
	d.linear_velocity = velocity_at(com)
	d.angular_velocity = angular_velocity + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	d.reset_physics_interpolation()


## İki parça kutuları değiyorsa komşudur (kopma hesabı bu grafiğe göre yapılır).
func _build_neighbors() -> void:
	for a in parts:
		_neighbors[a] = []
	for i in parts.size():
		var a := parts[i]
		var ba := a.local_aabb()
		for j in range(i + 1, parts.size()):
			var b := parts[j]
			if ba.intersects(b.local_aabb()):
				_neighbors[a].append(b)
				_neighbors[b].append(a)

func recalc_mass() -> void:
	var total := 0.0
	var moment := Vector3.ZERO
	for part in parts:
		var m := part.get_mass()
		total += m
		moment += part.position * m
	if total <= 0.0:
		return
	com_local = moment / total
	var inertia_sum := Vector3.ZERO
	for part in parts:
		var m := part.get_mass()
		var r := part.position - com_local
		var s := (part.basis * part.size).abs()
		inertia_sum.x += m * (r.y * r.y + r.z * r.z + (s.y * s.y + s.z * s.z) / 12.0)
		inertia_sum.y += m * (r.x * r.x + r.z * r.z + (s.x * s.x + s.z * s.z) / 12.0)
		inertia_sum.z += m * (r.x * r.x + r.y * r.y + (s.x * s.x + s.y * s.y) / 12.0)
	mass = total
	center_of_mass = com_local
	inertia = inertia_sum


# --- Fizik yardımcıları ---

func com_global() -> Vector3:
	return global_transform * com_local


func velocity_at(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - com_global())


## Havaya göre hız (rüzgar ve türbülans dahil). Aerodinamik bunu kullanır.
func air_velocity_at(point: Vector3) -> Vector3:
	return velocity_at(point) - Weather.wind_at(point)


func add_force_at(force: Vector3, point: Vector3) -> void:
	apply_force(force, point - global_position)


func air_density() -> float:
	return Atmosphere.density(altitude())


# --- Uçuş verileri ---

func altitude() -> float:
	return Planet.altitude(com_global())


## Hava hızı (rüzgara göre), göstergelerde bu kullanılır.
func airspeed() -> float:
	return air_velocity_at(com_global()).length()


func ground_speed() -> float:
	return linear_velocity.length()


## Zeminden (veya denizden) yükseklik.
func radar_altitude() -> float:
	var p := com_global()
	var ground := TerrainGen.height(Planet.surface_dir(p))
	return altitude() - maxf(ground, 0.0)


## Yerel ufuk çerçevesi (x doğu, y yukarı, z güney).
func local_frame() -> Basis:
	return Planet.local_basis(com_global())


func cockpit_part() -> Part:
	for part in parts:
		for module in part.modules:
			if module is CockpitModule:
				return part
	return null


func mach() -> float:
	return airspeed() / Atmosphere.SPEED_OF_SOUND


func forward() -> Vector3:
	return -global_basis.z


func up() -> Vector3:
	return Planet.up_at(com_global())


func pitch_deg() -> float:
	return rad_to_deg(asin(clampf(forward().dot(up()), -1.0, 1.0)))


func roll_deg() -> float:
	var u := up()
	return rad_to_deg(atan2(-global_basis.x.dot(u), global_basis.y.dot(u)))


func heading_deg() -> float:
	var f := forward()
	var b := local_frame()
	return fposmod(rad_to_deg(atan2(f.dot(b.x), -f.dot(b.z))), 360.0)


## Dikey hız (yerel yukarıya göre).
func vertical_speed() -> float:
	return linear_velocity.dot(up())


func aoa_deg() -> float:
	var v := global_basis.inverse() * air_velocity_at(com_global())
	if v.length() < 1.0:
		return 0.0
	return rad_to_deg(atan2(-v.y, -v.z))


func local_angular_velocity() -> Vector3:
	return global_basis.inverse() * angular_velocity


# --- Modüller ---

func get_modules_of(type: Script) -> Array:
	var out := []
	for module in modules:
		if is_instance_of(module, type):
			out.append(module)
	return out


func fuel_amount() -> float:
	var total := 0.0
	for module in modules:
		if module is FuelTankModule:
			total += module.fuel
	return total


func fuel_capacity() -> float:
	var total := 0.0
	for module in modules:
		if module is FuelTankModule:
			total += module.capacity
	return total


## Yakıt boşaltma (acil iniş için ağırlık atma): kanat uçlarından buhar, yedek yakıtta durur.
var fuel_dumping := false
var _dump_trails: Array[PuffTrail] = []
const DUMP_RESERVE := 0.12        ## kapasitenin bu kadarı tankta kalır


func dump_rate() -> float:
	return maxf(15.0, fuel_capacity() / 80.0)   # kg/s: dolu tank ~1.5 dakikada boşalır


func can_dump_fuel() -> bool:
	return fuel_amount() > fuel_capacity() * DUMP_RESERVE + 1.0


func set_fuel_dump(on: bool) -> void:
	if on and not can_dump_fuel():
		system_message.emit("Yakıt boşaltılamaz: yedek seviyede")
		return
	fuel_dumping = on
	system_message.emit("YAKIT BOŞALTILIYOR" if on else "Yakıt boşaltma durdu")
	if on and _dump_trails.is_empty():
		# en dıştaki kanat parçalarının uçlarından
		for side in [-1.0, 1.0]:
			var best: Part = null
			for p in parts:
				if signf(p.position.x) != side or not _is_main_wing(p):
					continue
				if best == null or absf(p.position.x) + p.size.x * 0.5 > absf(best.position.x) + best.size.x * 0.5:
					best = p
			if best:
				_dump_trails.append(PuffTrail.create(best, Vector3(side * best.size.x * 0.42, 0, best.size.z * 0.3), "dump"))
		if _dump_trails.is_empty():
			_dump_trails.append(PuffTrail.create(self, Vector3(0, -0.3, 4.0), "dump"))
	for t in _dump_trails:
		if is_instance_valid(t):
			t.emitting = on


func _is_main_wing(p: Part) -> bool:
	var wing := false
	for m in p.modules:
		if m is ControlSurfaceModule:
			return false
		if m is WingModule:
			wing = true
	return wing


func _update_fuel_dump(delta: float) -> void:
	if not fuel_dumping:
		return
	var keep := fuel_capacity() * DUMP_RESERVE
	var amount := minf(dump_rate() * delta, fuel_amount() - keep)
	if amount <= 0.0:
		set_fuel_dump(false)
		system_message.emit("Yakıt boşaltma bitti — yedek yakıt kaldı")
		return
	draw_fuel(amount)


## Tanklardan orantılı yakıt çeker; çekilebilen miktarı döner.
func draw_fuel(amount: float) -> float:
	var available := fuel_amount()
	if available <= 0.0 or amount <= 0.0:
		return 0.0
	var take := minf(amount, available)
	var ratio := take / available
	for module in modules:
		if module is FuelTankModule:
			module.fuel -= module.fuel * ratio
	return take


func total_thrust() -> float:
	var total := 0.0
	for module in modules:
		if module is EngineModule:
			total += module.thrust
	return total


func cockpit() -> CockpitModule:
	for module in modules:
		if module is CockpitModule:
			return module
	return null


func has_pilot() -> bool:
	var c := cockpit()
	return c != null and c.occupied


## İniş takımlarının ortalama açılma oranı (0 kapalı, 1 açık).
func gear_deploy() -> float:
	var total := 0.0
	var n := 0
	for module in modules:
		if module is LandingGearModule:
			total += module.deploy
			n += 1
	return total / n if n > 0 else 0.0


## Takımları animasyonsuz ayarla (doğma anı için).
func set_gear_instant(down: bool) -> void:
	gear_down = down
	for module in modules:
		if module is LandingGearModule:
			module.deploy = 1.0 if down else 0.0


# --- Elektrik / marş ---

## Motorların hava ihtiyacının ne kadarı karşılanıyor (0..1). J-70 (70 kN) ~0.5 m² alık ister.
func intake_ratio() -> float:
	var need := 0.0
	for e in engines():
		need += e.intake_need()
	if need <= 0.0:
		return 1.0
	var have := 0.0
	for m in modules:
		if m is IntakeModule:
			have += m.effective_area()
	return clampf(have / need, 0.0, 1.0)


func engines() -> Array:
	return get_modules_of(EngineModule)


func engines_running() -> bool:
	for e in engines():
		if e.is_running():
			return true
	return false


## Batarya ya da çalışan motorun jeneratörü.
func has_power() -> bool:
	return battery_on or engines_running()


func jfs_ready() -> bool:
	return jfs_spool > 0.9


func _update_systems(delta: float) -> void:
	if jfs_on and not has_power():
		jfs_on = false
	jfs_spool = move_toward(jfs_spool, 1.0 if jfs_on else 0.0, delta * (0.35 if jfs_on else 0.25))
	# motor(lar) rölantiye oturunca JFS kendiliğinden devreden çıkar
	if jfs_on and not engines().is_empty():
		var all_running := true
		for e in engines():
			if not e.is_running():
				all_running = false
		if all_running:
			jfs_on = false


func start_engines() -> bool:
	var ok := false
	for e in engines():
		ok = e.start() or ok
	return ok


func shutdown_engines() -> void:
	for e in engines():
		e.shutdown()


## Soğuk ve karanlık: her şey kapalı (pistte doğarken).
func set_cold() -> void:
	battery_on = false
	jfs_on = false
	jfs_spool = 0.0
	for e in engines():
		e.state = EngineModule.State.OFF
		e.n2 = 0.0


## Sıcak: motor rölantide (havada doğarken, testler).
func set_hot() -> void:
	battery_on = true
	for e in engines():
		e.state = EngineModule.State.RUNNING
		e.n2 = EngineModule.IDLE_N2


## Otomatik marş: batarya → JFS → motor → rölanti. (I tuşu)
func auto_start() -> void:
	if engines_running():
		return
	if not battery_on:
		battery_on = true
		Sfx.click()
		system_message.emit("Batarya açık")
		await get_tree().create_timer(0.8).timeout
	if not jfs_on:
		jfs_on = true
		Sfx.click()
		system_message.emit("JFS çalıştırılıyor…")
	while is_inside_tree() and not jfs_ready():
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.5).timeout
	Sfx.click()
	if start_engines():
		system_message.emit("Motor marşta — ateşleme bekleniyor")
		while is_inside_tree() and not engines_running():
			await get_tree().physics_frame
			if engines().is_empty() or engines()[0].state == EngineModule.State.OFF:
				system_message.emit("Marş başarısız")
				return
		system_message.emit("Motor rölantide")
	else:
		system_message.emit("Marş başarısız (yakıt/güç?)")


# --- Savaş ---

## Işın isabetindeki şekil indeksinden parçayı bul.
## Fare ışını (dünya uzayı, from→to) ile parça seçimi: çarpışma şekilleri + çarpışma şekli
## olmayan parçaların (iniş takımı) görsel mesh kutuları. Hangar ve parça pencereleri için.
## Işının değdiği parça: görsel üçgenlere göre (çarpışma şekilleri kaba ve birbirine taşar —
## kanada tıklayınca gövde seçilmesin). Önce kutu (AABB) elemesi, sonra üçgen kesişimi.
static var _faces_cache := {}


func pick_part(from: Vector3, to: Vector3) -> Part:
	var best: Part = null
	var best_d := INF
	for p in parts:
		for n in p.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var mo := mi.material_override
			if mo is ShaderMaterial and not mo.has_meta("paint") and mo != VesselBuilder.cockpit_panel_material():
				continue        # alev, ısı dalgası, cam gibi saydam efektler
			var inv := mi.global_transform.affine_inverse()
			var lf: Vector3 = inv * from
			var lt: Vector3 = inv * to
			if mi.get_aabb().grow(0.02).intersects_segment(lf, lt) == null:
				continue
			var faces: PackedVector3Array = _faces_cache.get(mi.mesh, PackedVector3Array())
			if faces.is_empty():
				faces = mi.mesh.get_faces()
				_faces_cache[mi.mesh] = faces
			var dir := lt - lf
			var i := 0
			while i + 2 < faces.size():
				var hit: Variant = Geometry3D.segment_intersects_triangle(lf, lt, faces[i], faces[i + 1], faces[i + 2])
				if hit != null:
					var d := from.distance_to(mi.global_transform * (hit as Vector3))
					if d < best_d:
						best_d = d
						best = p
				i += 3
	return best


func part_for_shape(shape_idx: int) -> Part:
	if shape_idx < 0:
		return null
	var owner_id := shape_find_owner(shape_idx)
	if owner_id < 0:
		return null
	return _collider_part.get(shape_owner_get_owner(owner_id))


## Isı izi (0..~1.5): çalışan motorların gücü, afterburner çok parlatır.
func heat_signature() -> float:
	var h := 0.0
	for e in engines():
		if e.is_running():
			h += (0.25 + 0.5 * e.throttle + 0.8 * e.afterburner) * (0.45 if e.prop else 1.0)
	return h


## Radar kesit alanı çarpanı (Detection): gövde büyüklüğü (parça sayısı) + dış yükler (her
## dolu füze / bomba rayı, pod, harici tank) + açık bomba kapakları. 1 ≈ Kartal-1 temiz.
func rcs() -> float:
	var r := clampf(float(parts.size()) / 16.0, 0.35, 2.5)
	for m in modules:
		if (m is MissileModule or m is BombModule) and m.loaded:
			r += 0.05
		elif m is EcmModule or m is TargetingPodModule:
			r += 0.05
		elif m is BombBayModule:
			r += 0.45 * m.doors
	for p in parts:
		if p.def.get("category", "") == "harici":
			r += 0.05
	return r


## Isı kaynağının konumu (motor lülesi), yoksa ağırlık merkezi.
func heat_position() -> Vector3:
	for e in engines():
		return e.part.global_transform * Vector3(0, 0, 1.6)
	return com_global()


func weapons() -> Array:
	var out := []
	for m in modules:
		if m is GunModule or m is MissileModule or m is BombModule:
			out.append(m)
	return out


## Uçakta bulunan silah türleri (WEAPON_* sırasıyla).
func available_weapons() -> Array[int]:
	var out: Array[int] = []
	for m in modules:
		var kind := -1
		if m is GunModule:
			kind = WEAPON_GUN
		elif m is MissileModule:
			kind = m.weapon_kind()
		elif m is BombModule:
			kind = m.weapon_kind()
		elif m is CargoModule:
			kind = WEAPON_CARGO
		if kind >= 0 and not kind in out:
			out.append(kind)
	out.sort_custom(func(a: int, b: int) -> bool: return WEAPON_ORDER.find(a) < WEAPON_ORDER.find(b))
	return out


## Sıradaki mevcut silaha geç (V).
func cycle_weapon() -> void:
	var list := available_weapons()
	if list.is_empty():
		return
	var i := list.find(selected_weapon)
	selected_weapon = list[(i + 1) % list.size()]


## Dolu güdümsüz bomba askıları (guided=true: lazer güdümlü).
func bombs_left(guided := false) -> int:
	var n := 0
	for m in modules:
		if m is BombModule and m.loaded and m.guided == guided:
			n += 1
	return n


func targeting_pod() -> TargetingPodModule:
	for m in modules:
		if m is TargetingPodModule:
			return m
	return null


func irst() -> IrstModule:
	for m in modules:
		if m is IrstModule:
			return m
	return null


func probe() -> RefuelProbeModule:
	for m in modules:
		if m is RefuelProbeModule:
			return m
	return null


## Çalışan bir ECM podu var mı (düşman radarlarını karıştırıyor).
func jamming() -> bool:
	for m in modules:
		if m is EcmModule and m.active():
			return true
	return false


## Radar (açıksa) ve IRST temasları birlikte (hedef kutuları, hedef seçimi).
func sensor_contacts() -> Array[Vessel]:
	var out: Array[Vessel] = []
	var r := radar()
	if r:
		out.append_array(r.contacts)
	var ir := irst()
	if ir:
		for t in ir.contacts:
			if not t in out:
				out.append(t)
	return out


## Yalnız IRST'nin gördüğü (radarın görmediği) temas mı.
func ir_only(t: Vessel) -> bool:
	var r := radar()
	return not (r != null and t in r.contacts)


func cargo_left() -> int:
	var n := 0
	for m in modules:
		if m is CargoModule:
			n += m.crates
	return n


## Yolcu kabinlerindeki toplam koltuk.
func passenger_seats() -> int:
	var n := 0
	for m in modules:
		if m is PassengerModule:
			n += m.seats
	return n


## Yolcuları kabinlere dağıt (görevler). Sığmayan sayıyı döndürür.
func board_passengers(count: int) -> int:
	for m in modules:
		if m is PassengerModule:
			var k := mini(count, m.seats - m.passengers)
			m.passengers += k
			count -= k
	recalc_mass()
	return count


func passengers() -> int:
	var n := 0
	for m in modules:
		if m is PassengerModule:
			n += m.passengers
	return n


func flares_left() -> int:
	var n := 0
	for m in modules:
		if m is FlareModule:
			n += m.count
	return n


func chaff_left() -> int:
	var n := 0
	for m in modules:
		if m is FlareModule:
			n += m.chaff
	return n


## Chaff hazneli fişeklik var mı (panel kartı için).
func has_chaff() -> bool:
	for m in modules:
		if m is FlareModule and (m.chaff > 0 or m.part.def.get("chaff_capable", false)):
			return true
	return false


## Bir chaff paketi at (ilk dolu hazneden).
func drop_chaff() -> bool:
	for m in modules:
		if m is FlareModule and m.chaff > 0:
			return m.fire_chaff()
	return false


## Bir çift ısı tuzağı at (ilk dolu fişeklikten).
func drop_flares() -> bool:
	for m in modules:
		if m is FlareModule and m.count > 0:
			return m.fire()
	return false


## Bu uçağa kilitli, uçuştaki en yakın füze (füze yaklaşma uyarısı). Yoksa null.
func incoming_missile() -> Missile:
	var best: Missile = null
	var best_d := INF
	for mi in Missile.active:
		if mi.victim == self and is_instance_valid(mi.target):
			var d := mi.global_position.distance_to(com_global())
			if d < best_d:
				best_d = d
				best = mi
	return best


func radar() -> RadarModule:
	for m in modules:
		if m is RadarModule:
			return m
	return null


## Seçili silah türünün adı (HUD için).
func weapon_name() -> String:
	return ["TOP", "IR FÜZE", "BOMBA", "KARGO", "RADAR FÜZE", "LAZER BOMBA"][clampi(selected_weapon, 0, 5)]


func gun_ammo() -> int:
	var n := 0
	for m in modules:
		if m is GunModule:
			n += m.ammo
	return n


## Dolu IR füze rayları (radar=true: radar füzeleri).
func missiles_left(radar_guided := false) -> int:
	var n := 0
	for m in modules:
		if m is MissileModule and m.loaded and m.radar_guided == radar_guided:
			n += 1
	return n


func radar_missiles_left() -> int:
	return missiles_left(true)


# ------------------------------------------------------------------ kısmi arızalar

## Gövde isabeti hidrolik hattı delebilir (ağır hasarda daha olası).
func _hydraulic_hit(part: Part, amount: float) -> void:
	if hydraulic_leak or part.health_ratio() > 0.6:
		return
	if randf() < clampf(amount / part.max_hp, 0.05, 0.5) * 0.6:
		hydraulic_leak = true
		failures["hyd"] = "HİDROLİK SIZINTI"
		system_message.emit("HİDROLİK SIZINTI — kumanda zayıflıyor")


## Hidrolik basınç: motor çalışırken pompa, durunca yedek RAT (hızla orantılı, zayıf).
func update_hydraulics(delta: float) -> void:
	var pump := 0.0
	for e in engines():
		if e.is_running():
			pump = 1.0
	var rat := clampf((airspeed() - 50.0) / 150.0, 0.0, 1.0) * 0.45
	var cap := 1.0
	if hydraulic_leak:
		_leak_level = minf(_leak_level + delta / 40.0, 0.7)
		cap = 1.0 - _leak_level
	var target := maxf(pump, rat) * cap
	hydraulics = move_toward(hydraulics, target, delta * 0.5)
	if pump < 0.5 and has_pilot() and airspeed() > 50.0:
		failures["rat"] = "MOTOR YOK — YEDEK HİDROLİK (RAT)"
	else:
		failures.erase("rat")
	# kopan parçaların arıza satırlarını temizle
	for k: String in failures.keys():
		for pre in ["wing", "jam", "eng"]:
			if k.begins_with(pre):
				var obj := instance_from_id(int(k.substr(pre.length())))
				if not is_instance_valid(obj) or not obj in parts:
					failures.erase(k)
	if hydraulics < 0.5 and (airspeed() > 40.0 or radar_altitude() > 5.0):
		failures["hydlow"] = "HİDROLİK BASINÇ DÜŞÜK %d%%" % (hydraulics * 100.0)
	else:
		failures.erase("hydlow")


var _leak_level := 0.0
