extends Node
## Gezegen (autoload: Planet). Küre geometrisi, yerel "yukarı/kuzey/doğu", yerçekimi,
## irtifa ve güneşin konumu.
##
## Başlangıç çerçevesinde havaalanı orijinde ve yerel yukarı +Y, kuzey -Z, doğu +X.
## Gezegen merkezi floating origin kaydıkça hareket eder; hassasiyet için 64-bit tutulur.

const RADIUS := TerrainGen.RADIUS
const SURFACE_GRAVITY := 9.81
const ATMOSPHERE_HEIGHT := 70000.0
const AIRFIELD_LATITUDE := 25.0

## Kutup ekseni (kuzey). Yön olduğu için kaydırmadan etkilenmez.
var axis := Vector3(0, sin(deg_to_rad(AIRFIELD_LATITUDE)), -cos(deg_to_rad(AIRFIELD_LATITUDE)))

# Merkez (floating koordinat, 64-bit bileşenler)
var _cx := 0.0
var _cy := -RADIUS
var _cz := 0.0


## Merkezin yaklaşık konumu (32-bit; yön hesapları için yeterli).
func center() -> Vector3:
	return Vector3(_cx, _cy, _cz)


## Bir noktanın merkeze göre konumu (64-bit hesaplanır, sonuç küçük değilse 32-bit'e iner).
func relative(p: Vector3) -> Vector3:
	return Vector3(p.x - _cx, p.y - _cy, p.z - _cz)


## Floating origin kaydırınca çağrılır.
func shift(s: Vector3) -> void:
	_cx -= s.x
	_cy -= s.y
	_cz -= s.z


func reset() -> void:
	_cx = 0.0
	_cy = -RADIUS
	_cz = 0.0


func up_at(p: Vector3) -> Vector3:
	return relative(p).normalized()


func altitude(p: Vector3) -> float:
	var dx := p.x - _cx
	var dy := p.y - _cy
	var dz := p.z - _cz
	return sqrt(dx * dx + dy * dy + dz * dz) - RADIUS


func gravity_at(p: Vector3) -> Vector3:
	var r := RADIUS / (RADIUS + maxf(altitude(p), -1000.0))
	return -up_at(p) * SURFACE_GRAVITY * r * r


## Yerel kuzey (yüzeye teğet). Kutupta tanımsız olduğu için sabit bir yöne düşer.
func north_at(p: Vector3) -> Vector3:
	var up := up_at(p)
	var n := axis - up * axis.dot(up)
	return n.normalized() if n.length() > 1e-5 else Vector3.FORWARD


func east_at(p: Vector3) -> Vector3:
	return north_at(p).cross(up_at(p)).normalized()


## Yerel çerçeve: x = doğu, y = yukarı, z = güney (Godot'ta -Z ileri = kuzey).
func local_basis(p: Vector3) -> Basis:
	var up := up_at(p)
	var north := north_at(p)
	return Basis(north.cross(up).normalized(), up, -north)


## Gezegen yüzeyindeki birim yön (merkezden), floating koordinattan.
func surface_dir(p: Vector3) -> Vector3:
	return relative(p).normalized()


func latitude_deg(p: Vector3) -> float:
	return rad_to_deg(asin(clampf(surface_dir(p).dot(axis), -1.0, 1.0)))


## Boylam: havaalanı meridyeni 0, doğu pozitif.
func longitude_deg(p: Vector3) -> float:
	var d := surface_dir(p)
	var ref := _meridian_ref()
	var east_ref := axis.cross(ref)
	return rad_to_deg(atan2(d.dot(east_ref), d.dot(ref)))


## Havaalanı meridyenindeki ekvator yönü.
func _meridian_ref() -> Vector3:
	var up0 := Vector3.UP
	return (up0 - axis * up0.dot(axis)).normalized()


## Güneşe doğru birim yön. hour: havaalanı meridyeninde yerel güneş saati (0..24).
func sun_direction(hour: float) -> Vector3:
	var angle := (hour - 12.0) / 24.0 * TAU
	# Sabah güneş doğuda (+X tarafı) olmalı → eksen etrafında negatif dönüş
	return _meridian_ref().rotated(axis, -angle)


## Bir noktanın yerel güneş yüksekliği (derece).
func sun_elevation_at(p: Vector3, sun_dir: Vector3) -> float:
	return rad_to_deg(asin(clampf(up_at(p).dot(sun_dir), -1.0, 1.0)))
