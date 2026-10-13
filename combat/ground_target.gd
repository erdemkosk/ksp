class_name GroundTarget
extends StaticBody3D
## Basit yer hedefi (zırhlı araç). Canı biter: patlar, yanık kabuğa döner, duman tüter.
## Alarm: vurulan, yakınına bomba/füze düşen ya da üstünden alçak geçilen birim aynı takımdan
## ALERT_RADIUS içindeki birimleri uyarır; her birim kendi tepkisini verir (_on_alert).

const LAYER := 8
const ALERT_RADIUS := 1500.0
const THREAT_RADIUS := 900.0        ## bu kadar yakındaki alçak uçak / bomba / füze alarm verir
const LOW_PASS_AGL := 500.0

## Alarm süresi (s); son tehditten bu kadar sonra sakinleşirler (testler kısaltabilir).
static var alert_time := 45.0
## Paylaşılan tehdit listesi [konum, takım] (birkaç karede bir, tek tarama)
static var _threats: Array = []
static var _threat_frame := -100

var hp := 600.0
var destroyed := false
## Görev sayacına girer mi (konvoy aracı evet, refakat uçaksavarı hayır)
var objective := true
var unit_name := "Zırhlı araç"
## Ateş eden birimlerin hedef seçimi için
var team := "düşman"
var _hull: Node3D
var _turret: Node3D
## Kalan alarm süresi (s); > 0 iken birim tetikte
var alert_t := 0.0
var _threat_rel := Vector3.ZERO     ## son tehdidin bize göre konumu (kayan orijinden etkilenmez)
var _scan_t := randf() * 0.5
var _alarm_frame := -100


static func create(pos: Vector3, yaw: float) -> GroundTarget:
	var t := GroundTarget.new()
	t.collision_layer = LAYER
	t.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.2, 6.5)
	cs.shape = box
	cs.position = Vector3(0, 1.1, 0)
	t.add_child(cs)
	t._hull = _mesh(t, Vector3(3.4, 1.3, 6.5), Vector3(0, 0.85, 0), Color(0.33, 0.36, 0.26))
	t._turret = _mesh(t, Vector3(2.2, 0.8, 2.6), Vector3(0, 1.9, -0.3), Color(0.3, 0.33, 0.24))
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.12
	cyl.height = 3.8
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(-90, 0, 0)
	barrel.position = Vector3(0, 0, -2.6)
	barrel.material_override = t._hull.material_override
	t._turret.add_child(barrel)
	for side in [-1.0, 1.0]:
		_mesh(t, Vector3(0.7, 0.9, 6.7), Vector3(side * 1.55, 0.45, 0), Color(0.12, 0.12, 0.11))
	t.position = pos
	t.rotation.y = yaw
	return t


static func _mesh(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	parent.add_child(mi)
	return mi


func take_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	_on_hit(amount)
	# ateş altındayız: komşuları uyar (mermi yağmurunda her isabette değil)
	if Engine.get_physics_frames() - _alarm_frame > 20:
		_alarm_frame = Engine.get_physics_frames()
		raise_alarm(_guess_threat(), true)
	if hp <= 0.0:
		destroyed = true
		var up := Planet.up_at(global_position)
		Effects.explosion(FloatingOrigin.world_root, global_position + up * 1.5, up, 2.5)
		Sfx.explosion(global_position, 2.0)
		_burn(self)
		if _turret:
			_turret.position += Vector3(randf_range(-1, 1), 0.8, randf_range(-1, 1))
			_turret.rotation_degrees = Vector3(randf_range(-25, 25), randf_range(0, 360), randf_range(-25, 25))
		_on_destroyed()
		if team == "düşman":
			Crew.note_target_destroyed(self)   # madalya sayacı (Kara Kartalı / Gemi Avcısı)
		var smoke := Effects.smoke_column()
		add_child(smoke)
		smoke.position = Vector3(0, 2, 0)


## Alt sınıflar için: yok olunca ek davranış (helikopter düşer, kamyon durur…).
func _on_destroyed() -> void:
	pass


## Alt sınıflar için: isabet aldı (uçaksavar susar, helikopter kaçar…).
func _on_hit(_amount: float) -> void:
	pass


## Alt sınıflar için: alarm geldi. `first`: sakinken ilk alarm; `hit`: biri vuruldu.
func _on_alert(_first: bool, _hit: bool) -> void:
	pass


func alerted() -> bool:
	return alert_t > 0.0 and not destroyed


## Son bilinen tehdit konumu (alarm yoksa null).
func threat_point() -> Variant:
	return global_position + _threat_rel if alerted() else null


## Alarm geldiğinde (ilk kez) çağrılır — düşman üssü avcı kaldırır vb.
var alerted_cb: Callable


## Bu birime alarm ver.
func alarm(threat: Vector3, hit := false) -> void:
	if destroyed:
		return
	var first := alert_t <= 0.0
	alert_t = alert_time
	_threat_rel = threat - global_position
	_on_alert(first, hit)
	if first and alerted_cb.is_valid():
		alerted_cb.call()


## Yarıçap içindeki aynı takımdan tüm birimleri (kendisi dahil) uyar.
func raise_alarm(threat: Vector3, hit := false, radius := ALERT_RADIUS) -> void:
	var p := get_parent()
	if p == null:
		return
	for n in p.get_children():
		if n is GroundTarget and n.team == team and not n.destroyed and n.global_position.distance_to(global_position) < radius:
			n.alarm(threat, hit)


## Ateş edeni bilmiyoruz: en yakın düşman uçağı, yoksa tepemiz.
func _guess_threat() -> Vector3:
	var v: Vessel = nearest_enemy_vessel(6000.0) if get_parent() else null
	return v.com_global() if v else global_position + Planet.up_at(global_position) * 300.0


## Alt sınıfların _physics_process'i çağırır: alarm süresi + yakın tehdit taraması (2 Hz).
func _alert_tick(delta: float) -> void:
	alert_t = maxf(alert_t - delta, 0.0)
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.5
	_refresh_threats(get_parent())
	for th: Array in _threats:
		if th[1] != team and (th[0] as Vector3).distance_to(global_position) < THREAT_RADIUS:
			raise_alarm(th[0])
			return


## Alçak uçan uçaklar, düşen bombalar, uçan füzeler (15 karede bir; tüm birimler paylaşır).
static func _refresh_threats(world: Node) -> void:
	var f := Engine.get_physics_frames()
	if f - _threat_frame < 15 or world == null:
		return
	_threat_frame = f
	_threats.clear()
	for n in world.get_children():
		if n is Vessel:
			if not n.parts.is_empty() and n.has_pilot() and n.radar_altitude() < LOW_PASS_AGL:
				_threats.append([n.com_global(), n.team])
		elif n is Bomb:
			_threats.append([n.global_position, n.shooter.team if is_instance_valid(n.shooter) else ""])
	for m in Missile.active:
		if is_instance_valid(m) and is_instance_valid(m.shooter):
			_threats.append([m.global_position, m.shooter.team])


## Dünya konumunun yüzey koordinatı (başlangıç çerçevesi: x doğu, y güney).
static func surface_xz(p: Vector3) -> Vector2:
	var d := (p - Planet.center()).normalized()
	return Vector2(d.x, d.z) / maxf(d.y, 0.01) * Planet.RADIUS


## Tüm görselleri yanık kabuk rengine çevir.
static func _burn(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = c.material_override.duplicate()
			m.albedo_color = Color(0.07, 0.065, 0.06)
			m.emission_enabled = false
			c.material_override = m
		_burn(c)


## En yakın düşman uçağı (oyuncu ya da dost), menzil içinde.
func nearest_enemy_vessel(max_range: float) -> Vessel:
	var best: Vessel = null
	var bd := max_range
	for n in get_parent().get_children():
		if n is Vessel and n.team != team and not n.parts.is_empty() and n.has_pilot():
			var d: float = n.com_global().distance_to(global_position)
			if d < bd:
				bd = d
				best = n
	return best


## Arada arazi var mı (radar / görüş hattı).
func line_of_sight(to: Vector3) -> bool:
	# arazi çarpışması yalnız odak çevresinde var: hattı arazi yüksekliğiyle örnekle
	var from := global_position + Planet.up_at(global_position) * 4.0
	for i in range(1, 20):
		var p := from.lerp(to, i / 20.0)
		if Planet.altitude(p) < TerrainGen.height(Planet.surface_dir(p)) + 2.0:
			return false
	return true
