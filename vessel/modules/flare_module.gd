class_name FlareModule
extends PartModule
## Karşı tedbir fişekliği: ısı tuzağı (flare, O) ve/veya chaff (Ş) hazneleri.
## Flare IR füzeyi, chaff radar füzesini ve takip radarını şaşırtır.
## Otomatik program (Vessel.cm_auto): sana kilitli füze 4 km'ye girince doğru tedbiri kendiliğinden
## atar (IR füzeye flare, radar füzesine chaff).

const AUTO_RANGE := 4000.0

var count := 30            ## flare
var chaff := 0             ## chaff
var _cooldown := 0.0
var _chaff_cooldown := 0.0
var _auto_t := 0.0


func setup(p: Dictionary) -> void:
	count = int(p.get("count", count))
	chaff = int(p.get("chaff", chaff))


func physics_tick(delta: float) -> void:
	_cooldown -= delta
	_chaff_cooldown -= delta
	_auto_t -= delta
	if not vessel.cm_auto or _auto_t > 0.0 or not vessel.has_power():
		return
	var inc := vessel.incoming_missile()
	if inc == null or inc.global_position.distance_to(vessel.com_global()) > AUTO_RANGE:
		return
	_auto_t = 0.8
	if inc.is_radar():
		vessel.drop_chaff()
	else:
		vessel.drop_flares()


## Bir salvo flare atmayı dener (0.35 sn aralık). Atıldıysa true.
func fire() -> bool:
	if count <= 0 or _cooldown > 0.0 or not vessel.has_power():
		return false
	count -= 2
	_cooldown = 0.35
	Flare.drop(vessel, 2)
	return true


## Bir chaff paketi atmayı dener (0.5 sn aralık). Atıldıysa true.
func fire_chaff() -> bool:
	if chaff <= 0 or _chaff_cooldown > 0.0 or not vessel.has_power():
		return false
	chaff -= 1
	_chaff_cooldown = 0.5
	Chaff.drop(vessel)
	return true
