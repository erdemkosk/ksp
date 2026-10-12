class_name RefuelProbeModule
extends PartModule
## Havada ikmal probu. Probun ucu bir tankerin sepetine (Drogue) CONTACT_RADIUS içinde ve
## yavaş yaklaşarak girince bağlanır; bağlıyken tanklara saniyede FLOW kg yakıt akar.
## Sepetten BREAK_RADIUS'tan fazla uzaklaşınca ya da çok sert çarpınca bağlantı kopar.

const CONTACT_RADIUS := 1.6
const BREAK_RADIUS := 4.0
const MAX_CLOSING := 6.0          ## m/s: bundan hızlı giren prob sepetten seker
const FLOW := 55.0                ## kg/s

var drogue: Drogue                ## bağlı sepet (yoksa null)
var received := 0.0               ## bu uçuşta alınan toplam yakıt (kg)
var _bounce := 0.0


## Probun ucu (dünya).
func tip() -> Vector3:
	return part.global_transform * Vector3(0, 0, -part.size.z * 0.5)


func physics_tick(delta: float) -> void:
	_bounce -= delta
	var t := tip()
	if is_instance_valid(drogue):
		var d := t.distance_to(drogue.basket_position())
		if d > BREAK_RADIUS or not drogue.is_inside_tree() or not is_instance_valid(drogue.tanker):
			_disconnect("İKMAL: bağlantı koptu")
			return
		var room := vessel.fuel_capacity() - vessel.fuel_amount()
		if room <= 1.0:
			_disconnect("İKMAL: tanklar dolu — ayrıl")
			return
		var amount := minf(FLOW * delta, room)
		_add_fuel(amount)
		received += amount
		drogue.flowing = true
		return
	if _bounce > 0.0:
		return
	for dr in Drogue.active:
		var bp := dr.basket_position()
		if t.distance_to(bp) > CONTACT_RADIUS:
			continue
		var closing := (vessel.linear_velocity - dr.velocity()).dot((bp - t).normalized())
		if closing > MAX_CLOSING:
			_bounce = 1.5
			vessel.system_message.emit("İKMAL: çok hızlı girdin — sepet sekti")
			Sfx.play_at("hydraulic_thunk.ogg", bp, -2.0, 1.6, 300.0)
			return
		drogue = dr
		dr.connected = vessel
		vessel.system_message.emit("İKMAL: BAĞLANDI — yakıt akıyor, pozisyonu koru")
		Sfx.play_at("hydraulic_thunk.ogg", bp, 0.0, 1.0, 300.0)
		return


func connected() -> bool:
	return is_instance_valid(drogue)


func _disconnect(msg: String) -> void:
	if is_instance_valid(drogue):
		drogue.connected = null
		drogue.flowing = false
	drogue = null
	_bounce = 1.0
	vessel.system_message.emit(msg)


## Yakıtı boş yeri olan tanklara sırayla doldur.
func _add_fuel(amount: float) -> void:
	for m in vessel.modules:
		if amount <= 0.0:
			break
		if m is FuelTankModule:
			var put := minf(amount, m.capacity - m.fuel)
			if put > 0.0:
				m.fuel += put
				amount -= put
