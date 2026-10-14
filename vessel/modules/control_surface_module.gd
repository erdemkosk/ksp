class_name ControlSurfaceModule
extends WingModule
## Hareketli kontrol yüzeyi. Hangi eksene (pitch/yaw/roll) hizmet edeceğini
## ağırlık merkezine göre konumundan kendisi çıkarır (KSP'deki gibi).

var max_deflection := deg_to_rad(20.0)
var rate := deg_to_rad(90.0)
## Gövde torku eksenlerine ağırlıklar: x = pitch, y = yaw, z = roll.
var axis_weights := Vector3.ZERO
## Hangarda kapatılan eksenler 0 (x = pitch, y = yaw, z = roll).
var axis_mask := Vector3.ONE
## Yetki (KSP "authority limiter"): komut bununla çarpılır; 0.5 = yarım tepki, eksi = ters çalışır.
var authority := 1.0

var _visual: Node3D
## Ağır hasarda yüzey o anki açısında sıkışabilir.
var jammed := false


func setup(p: Dictionary) -> void:
	super.setup(p)
	max_deflection = deg_to_rad(p.get("max_deflection_deg", 20.0))


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual")
	_compute_weights()
	# büyük / ağır uçakta yüzeyler (ve hidrolikleri) daha yavaş döner: 12 t avcı 90°/sn,
	# 45 t yolcu uçağı ~47°/sn — ağır uçak kumandaya geç cevap verir
	rate = deg_to_rad(90.0) * response_factor(vessel.mass)


## Uçağın kütlesine göre kumanda tepkisi çarpanı (1 = hafif avcı; ağır uçakta küçülür).
## PlayerController da çubuk hareket hızı için kullanır.
static func response_factor(mass: float) -> float:
	return clampf(sqrt(12000.0 / maxf(mass, 1.0)), 0.4, 1.0)


func physics_tick(delta: float) -> void:
	_compute_weights()  # yakıt azaldıkça ağırlık merkezi kayar
	# İstenen tork (gövde ekseninde): burun yukarı = +X, sağa sapma = -Y, sağa yatış = -Z
	var desired := Vector3(vessel.ctrl_pitch, -vessel.ctrl_yaw, -vessel.ctrl_roll)
	var command := clampf(axis_weights.dot(desired) * authority, -1.0, 1.0)
	# hidrolik basınç: hız ve sapma payı basınçla düşer
	var hyd := vessel.hydraulics
	if not jammed:
		deflection = move_toward(deflection, command * max_deflection * lerpf(0.35, 1.0, hyd), rate * lerpf(0.15, 1.0, hyd) * delta)
	if _visual:
		_visual.rotation.x = deflection
	super.physics_tick(delta)


## Hangar kumanda testi: fizik çalışmadan yüzeyi istenen komuta (yunus, -sapma, -yatış) göre
## gerçek hızında döndürür. Komut sıfırlanınca yüzey yerine (0°) döner.
func preview_tick(desired: Vector3, delta: float) -> void:
	if _visual == null:
		_visual = part.get_node_or_null("Visual")
	_compute_weights()
	var command := clampf(axis_weights.dot(desired) * authority, -1.0, 1.0)
	deflection = move_toward(deflection, command * max_deflection, rate * delta)
	if _visual:
		_visual.rotation.x = deflection


func on_damaged(amount: float) -> void:
	super.on_damaged(amount)
	if not jammed and part.health_ratio() < 0.55 and randf() < 0.45:
		jammed = true
		vessel.failures["jam%d" % part.get_instance_id()] = "%s SIKIŞTI (%+d°)" % [part.title.to_upper(), rad_to_deg(deflection)]
		vessel.system_message.emit("%s sıkıştı!" % part.title)


## Yüzey kaldırmasını artırırsa oluşacak torkun yönü = r × n.
func _compute_weights() -> void:
	var r := part.position - vessel.com_local
	var n := part.basis.y
	var t := r.cross(n)
	var m := maxf(absf(t.x), maxf(absf(t.y), absf(t.z)))
	if m < 0.001:
		axis_weights = Vector3.ZERO
		return
	axis_weights = t / m
	for i in 3:
		if absf(axis_weights[i]) < 0.15:
			axis_weights[i] = 0.0
	axis_weights *= axis_mask
