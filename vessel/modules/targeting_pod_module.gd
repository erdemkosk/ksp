class_name TargetingPodModule
extends PartModule
## Hedefleme podu (FLIR / TV): podun önündeki döner optik başlıktan dünyaya bakan bir kamera.
## Görüntü kendi panelinde (TargetingPodPanel) gösterilir. Başlık gövdeye göre azimut ±150°,
## yükseliş -110°..+20° döner. Kilit: bakılan noktaya (nokta takibi) ya da yakındaki araca /
## yer hedefine (alan takibi) kilitlenir; uçak dönse de başlık oraya bakmaya devam eder.
## Kilitlenen uçak radar hedefi olarak seçilir (füze arayıcısı önceliği).

const ZOOMS := [32.0, 12.0, 4.5, 1.6]      ## görüş alanı (derece)
const MODES := ["TV", "IR BEYAZ", "IR SİYAH", "GECE"]
const AZ_LIMIT := deg_to_rad(150.0)
const EL_MIN := deg_to_rad(-110.0)
const EL_MAX := deg_to_rad(20.0)
const SLEW_RATE := 0.9                      ## rad/s (yakınlaşınca yavaşlar)

var az := 0.0                ## gövdeye göre yön (rad, + sağ)
var el := deg_to_rad(-12.0)  ## gövdeye göre yükseliş (rad, - aşağı)
var zoom := 0
var mode := 0
var tracking := false
var track_point := Vector3.ZERO             ## dünya konumu (kayan orijinle kaydırılır)
var track_node: Node3D                      ## araç / yer hedefi (alan takibi)
var gimbal_limit := false                   ## başlık sınırına dayandı (kilit koptu)
var _head: Node3D


func on_attached() -> void:
	_head = part.get_node_or_null("Visual/Head")
	FloatingOrigin.shifted.connect(func(s: Vector3) -> void: track_point -= s)


func fov() -> float:
	return ZOOMS[zoom]


## Optik başlığın dünya konumu.
func eye() -> Vector3:
	return part.global_transform * Vector3(0, -0.05, -part.size.z * 0.5 + 0.1)


## Gövdeye göre bakış yönü (dünya).
func look_dir() -> Vector3:
	var b := vessel.global_basis
	var local := Basis(Vector3.UP, -az) * Basis(Vector3.RIGHT, el) * Vector3.FORWARD
	return (b * local).normalized()


## Bakış hattının araziye değdiği yer (en çok 30 km); bulamazsa null.
func ground_point() -> Variant:
	var from := eye()
	var dir := look_dir()
	var space := vessel.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + dir * 3.0, from + dir * 30000.0, 1 | 8)
	q.exclude = [vessel.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	# arazi çarpışması yalnız yakında var: yükseklik fonksiyonuyla ileri yürü
	var step := 40.0
	var d := 40.0
	while d < 30000.0:
		var p := from + dir * d
		if Planet.altitude(p) < maxf(TerrainGen.height(Planet.surface_dir(p)), 0.0):
			return p
		d += step
		step = minf(step * 1.08, 400.0)
	return null


func slew(dx: float, dy: float, delta: float) -> void:
	if absf(dx) + absf(dy) < 0.001:
		return
	if tracking:
		tracking = false
		track_node = null
	var rate := SLEW_RATE * (fov() / ZOOMS[0])
	az = clampf(az + dx * rate * delta, -AZ_LIMIT, AZ_LIMIT)
	el = clampf(el + dy * rate * delta, EL_MIN, EL_MAX)


## Kilit aç / kapat: yakında araç ya da yer hedefi varsa ona, yoksa noktaya.
func toggle_lock() -> void:
	if tracking:
		tracking = false
		track_node = null
		return
	var gp: Variant = ground_point()
	var from := eye()
	var dir := look_dir()
	# bakış hattına en yakın araç / yer hedefi (görüş alanına göre tolerans)
	var best: Node3D = null
	var best_ang := deg_to_rad(fov()) * 0.12
	for n in vessel.get_parent().get_children():
		if n == vessel:
			continue
		var tp := Vector3.INF
		if n is Vessel and not n.parts.is_empty():
			tp = n.com_global()
		elif n is GroundTarget and not n.destroyed:
			tp = n.global_position + Planet.up_at(n.global_position) * 1.5
		if tp == Vector3.INF or tp.distance_to(from) > 30000.0:
			continue
		var ang := dir.angle_to(tp - from)
		if ang < best_ang:
			best_ang = ang
			best = n
	if best:
		track_node = best
		tracking = true
		if best is Vessel and best.team != vessel.team:
			vessel.designated = best
	elif gp != null:
		track_point = gp
		track_node = null
		tracking = true


## Takip edilen nokta (dünya) ya da null.
func target_point() -> Variant:
	if not tracking:
		return null
	if is_instance_valid(track_node):
		if track_node is Vessel:
			return (track_node as Vessel).com_global()
		return track_node.global_position + Planet.up_at(track_node.global_position) * 1.5
	return track_point


func physics_tick(_delta: float) -> void:
	gimbal_limit = false
	var tp: Variant = target_point()
	if tp != null:
		if is_instance_valid(track_node) and track_node is GroundTarget and track_node.destroyed:
			track_point = target_point()
			track_node = null
		var local := vessel.global_basis.inverse() * ((tp as Vector3) - eye())
		var naz := atan2(local.x, -local.z)
		var nel := atan2(local.y, Vector2(local.x, local.z).length())
		if absf(naz) > AZ_LIMIT or nel < EL_MIN or nel > EL_MAX:
			gimbal_limit = true
			tracking = false
			track_node = null
		else:
			az = naz
			el = nel
	if _head:
		_head.rotation = Vector3(0, -az, 0)
		var ball := _head.get_node_or_null("Ball") as Node3D
		if ball:
			ball.rotation = Vector3(el, 0, 0)


## Bakılan noktaya uzaklık (lazer telemetre), metre; yoksa -1.
func range_m() -> float:
	var tp: Variant = target_point()
	if tp == null:
		tp = ground_point()
	return eye().distance_to(tp) if tp != null else -1.0
