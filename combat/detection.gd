class_name Detection
## Radar algılama modeli — oyuncu, düşman avcıları, SAM'lar, erken uyarı radarı ve AWACS aynı
## kuralları kullanır:
##   • Menzil hedefin radar kesit alanıyla (RCS) büyür: R ∝ RCS^¼ (radar denklemi). Büyük uçak,
##     dış yükler (füze, bomba, tank, pod) ve açık bomba kapakları RCS'yi artırır.
##   • Arazi görüş hattını keser (tepenin arkası, vadi).
##   • Yer yankısı: alçaktaki hedef yer yansımalarına karışır. Aşağı bakan hava radarı yerden
##     ~500 m altındaki hedefi kısa menzilde görür; yer radarı ufka yakın alçak hedefi daha da zor.
##   • Çentik: radara dik uçan (Doppler hızı ~0) alçak hedef kaybolur.
##   • ECM karıştırması menzili kısaltır (yakında radar gürültüyü yener).
## Erken uyarı radarı ve AWACS gördüklerini takımlarına "veri bağı" ile bildirir (report);
## yapay zekâ avcıları bu listeden de hedef bulur (known).

const VISUAL_RANGE := 2500.0       ## göz ile görme (radarsız da)
const REPORT_TTL := 8.0            ## veri bağı bilgisinin geçerlilik süresi (sn)

## takım -> {Vessel: son görülme zamanı (sn)}
static var _reports := {}


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Radar (from, RCS=1 hedef için menzil range_m) hedefi görüyor mu?
static func radar_sees(from: Vector3, range_m: float, t: Vessel, ground_based := false) -> bool:
	if not is_instance_valid(t) or t.parts.is_empty():
		return false
	var tp := t.com_global()
	var d := from.distance_to(tp)
	if d > range_m * 1.6:
		return false
	var reach := range_m * sqrt(sqrt(t.rcs()))
	if t.jamming():
		reach = maxf(reach * EcmModule.JAM_RANGE_FACTOR, EcmModule.BURN_THROUGH)
	reach *= clutter_factor(from, t, ground_based)
	if d > reach:
		return false
	if t.radar_altitude() < 400.0 and Missile.in_notch(from, t):
		return false
	return Missile.terrain_clear(from, tp)


## Yer yankısı çarpanı (0.2..1): hedef alçakta ve radar ona aşağıdan/yandan değil yukarıdan
## bakıyorsa ya da radar yerdeyse ve hedef ufka yakınsa düşer.
static func clutter_factor(from: Vector3, t: Vessel, ground_based: bool) -> float:
	var agl := t.radar_altitude()
	if ground_based:
		return lerpf(0.25, 1.0, smoothstep(30.0, 300.0, agl))
	var los := (t.com_global() - from).normalized()
	if los.dot(Planet.up_at(from)) > -0.03:
		return 1.0          # yukarı / yatay bakıyor: arkada gökyüzü var
	return lerpf(0.3, 1.0, smoothstep(40.0, 500.0, agl))


## Veri bağı: gözcünün gördüğü hedef takımına bildirilir.
static func report(team: String, t: Vessel) -> void:
	if not _reports.has(team):
		_reports[team] = {}
	_reports[team][t] = now()


## Takımın veri bağıyla bildiği (son REPORT_TTL saniyede görülmüş) uçaklar.
static func known(team: String) -> Array[Vessel]:
	var out: Array[Vessel] = []
	if not _reports.has(team):
		return out
	var tnow := now()
	var stale: Array = []
	for t in _reports[team]:
		if not is_instance_valid(t) or (t as Vessel).parts.is_empty() or tnow - float(_reports[team][t]) > REPORT_TTL:
			stale.append(t)
		else:
			out.append(t)
	for t in stale:
		_reports[team].erase(t)
	return out


## Bu uçak şu an herhangi bir düşman sensörünce görülüyor mu (HUD "GÖRÜNÜYORSUN" ışığı).
static func is_seen(v: Vessel) -> bool:
	var me := v.com_global()
	for n in v.get_parent().get_children():
		if n is Vessel and n != v and not n.parts.is_empty() and n.team != v.team and n.team != "sivil":
			var r: RadarModule = n.radar()
			if r and v in r.contacts:
				return true
			if n.com_global().distance_to(me) < VISUAL_RANGE:
				return true
	for site in SamSite.sites:
		if not site.destroyed and site.team != v.team and site.sees(v):
			return true
	for st in RadarStation.stations:
		if not st.destroyed and st.team != v.team and st.sees(v):
			return true
	for sh in Warship.ships:
		if is_instance_valid(sh) and sh.team != v.team and sh.global_position.distance_to(me) < sh.radar_range * 1.6 and sh.sees(v):
			return true
	for team in _reports:
		if team != v.team and _reports[team].has(v) and now() - float(_reports[team][v]) < 2.0:
			return true
	return false
