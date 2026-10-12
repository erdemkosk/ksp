class_name Radio
extends Node
## Telsiz konuşmaları: kule (kalkış/iniş izni), radar uçağı "Şahin Gözü" (temas bildirimi),
## kendi çağrılarımız (füze atışı, düşürme). Konuşma işletim sisteminin sesi ile okunur;
## başta "cızz" açılış, arkada parazit, sonda kapanış cızırtısı. Türkçe ses varsa Türkçe,
## yoksa İngilizce okur. Ekranda altyazı olarak da görünür (Hud mesajı).

var main: Node
var enabled := true

var _queue: Array = []            # [tr, en]
var _voice := ""
var _turkish := false
var _busy := 0.0
var _static: AudioStreamPlayer
var speaking := false

# durum bayrakları (her biri bir kez)
var _cleared_takeoff := false
var _airborne := false
var _cleared_landing := false
var _welcomed := false
var _had_contact := false
var _t_ground := 0.0
var _tower := "Kule"


func _ready() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) or Game.args.has("autotest") or Game.args.has("missiontest"):
		enabled = false
		return
	var en := ""
	for v in DisplayServer.tts_get_voices():
		var lang: String = v.get("language", "")
		if lang.begins_with("tr") and _voice.is_empty():
			_voice = v["id"]
			_turkish = true
		elif lang.begins_with("en") and en.is_empty():
			# uyarı sesinden (kadın) farklı olsun: erkek ses tercih
			var name: String = v.get("name", "")
			if "David" in name or "Mark" in name or "Guy" in name or "Male" in name:
				en = v["id"]
	if _voice.is_empty():
		for v in DisplayServer.tts_get_voices():
			if (v.get("language", "") as String).begins_with("en"):
				en = v["id"] if en.is_empty() else en
		_voice = en
	enabled = not _voice.is_empty()
	_static = AudioStreamPlayer.new()
	_static.stream = Sfx.looped("radio_static.ogg")
	_static.bus = Sfx.BUS_UI
	_static.volume_db = -22.0
	add_child(_static)


## Bir telsiz mesajı sıraya koy.
## sender: konuşan (KULE, ŞAHİN GÖZÜ, kendi çağrı adımız) — telsiz kutusunda başta yazar.
func say(tr: String, en: String, sender := "") -> void:
	if enabled and bool(Game.settings.get("radio", true)) and _queue.size() < 4:
		_queue.append([tr, en, sender if not sender.is_empty() else _tower.to_upper()])


func callsign() -> String:
	var v: Vessel = main.vessel
	return v.craft_name if is_instance_valid(v) else "Kartal-1"


func _process(delta: float) -> void:
	if not enabled:
		return
	_busy -= delta
	if speaking:
		if not DisplayServer.tts_is_speaking() and _busy <= 0.0:
			speaking = false
			_static.stop()
			Sfx.play_ui("radio_close.ogg", -8.0)
			_busy = 0.8
		return
	if _queue.is_empty() or _busy > 0.0 or DisplayServer.tts_is_speaking():
		return
	var m: Array = _queue.pop_front()
	Sfx.play_ui("radio_open.ogg", -8.0)
	_static.play()
	var text: String = m[0] if _turkish else m[1]
	DisplayServer.tts_speak(text, _voice, 75, 1.0, 1.05)
	if main and main.hud:
		main.hud.radio_message(String(m[2]), String(m[0]))
	speaking = true
	_busy = 0.6


func _physics_process(delta: float) -> void:
	if not enabled or main == null:
		return
	var v: Vessel = main.vessel
	if not is_instance_valid(v) or not v.has_pilot():
		return
	var cs := callsign()
	var grounded := false
	for m in v.modules:
		if m is LandingGearModule and m.grounded:
			grounded = true
	var near_base: bool = _dist_base(v) < 8000.0
	# kalkış izni: motor çalışıyor, pistte duruyor
	if grounded and v.engines_running() and v.ground_speed() < 3.0 and not _cleared_takeoff and near_base:
		_t_ground += delta
		if _t_ground > 2.5:
			_cleared_takeoff = true
			var w := Weather.wind_at(v.global_position)
			var wdir := int(fposmod(rad_to_deg(atan2(-w.x, w.z)), 360.0) / 10.0) * 10
			var kt := int(w.length() * 1.94)
			say("%s, %s. Pist üç altı, rüzgar %d derece %d knot. Kalkışa izin verildi." % [cs, _tower.to_lower(), wdir, kt],
				"%s, tower. Runway three six, wind %d at %d knots. Cleared for takeoff." % [cs, wdir, kt])
	# kalkış görüldü
	if not grounded and v.radar_altitude() > 150.0 and not _airborne:
		_airborne = true
		_cleared_landing = false
		_welcomed = false
		if near_base:
			say("%s, kalkışınız görüldü. Frekansta kalın, iyi uçuşlar." % cs,
				"%s, airborne. Stay on frequency, have a good flight." % cs)
	# iniş izni: üsse yaklaşma, takım açık, alçak ve yavaş
	if _airborne and not _cleared_landing and near_base and v.gear_down and v.radar_altitude() < 1200.0 and v.airspeed() < 120.0:
		_cleared_landing = true
		say("%s, %s. Pist üç altı, inişe izin verildi." % [cs, _tower.to_lower()], "%s, tower. Runway three six, cleared to land." % cs)
	# iniş sonrası
	if _airborne and grounded and v.ground_speed() < 15.0 and near_base and not _welcomed:
		_welcomed = true
		_airborne = false
		_cleared_takeoff = true
		say("%s, hoş geldiniz. Pisti boşaltın, apronu takip edin." % cs, "%s, welcome back. Vacate the runway, taxi to the apron." % cs)
	# radar teması (yeni)
	var radar := v.radar()
	if radar and v.has_power():
		var enemy: Vessel = null
		for c in radar.contacts:
			if is_instance_valid(c) and c.team != v.team:
				enemy = c
		if enemy and not _had_contact:
			var to := enemy.com_global() - v.com_global()
			var fr := Planet.local_basis(v.global_position)
			var brg := int(fposmod(rad_to_deg(atan2(to.dot(fr.x), -to.dot(fr.z))), 360.0))
			say("%s, Şahin Gözü. Düşman teması, kerteriz %03d, %d kilometre." % [cs, brg, int(to.length() / 1000.0)],
				"%s, Hawkeye. Bandit, bearing %03d, %d kilometers." % [cs, brg, int(to.length() / 1000.0)], "ŞAHİN GÖZÜ")
		_had_contact = enemy != null


## En yakın havaalanına yatay mesafe; _tower o havaalanının adı olur.
func _dist_base(v: Vessel) -> float:
	var best := INF
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var xz: Vector2 = a["xz"]
		var base := MissionManager.world_point(xz.x, xz.y, float(a["elev"]))
		var d := v.com_global() - base
		var up := Planet.up_at(base)
		var hd := (d - up * d.dot(up)).length()
		if hd < best:
			best = hd
			_tower = "Kule" if a["name"] == "Ana Üs" else "%s kulesi" % a["name"]
	return best


func on_kill() -> void:
	say("Hedef düştü, tebrikler %s." % callsign(), "Hawkeye: splash one, good kill %s." % callsign(), "ŞAHİN GÖZÜ")


func on_missile() -> void:
	say("%s, füze atıldı!" % callsign(), "%s, Fox two!" % callsign(), callsign().to_upper())


# ------------------------------------------------------------------ pilot istekleri (F2 telsiz menüsü)

## En yakın havaalanı: [indeks, yatay mesafe m, kerteriz derece]
func nearest_airfield(v: Vessel) -> Array:
	var best := [0, INF, 0]
	var fr := Planet.local_basis(v.global_position)
	for i in TerrainGen.AIRFIELDS.size():
		var a: Dictionary = TerrainGen.AIRFIELDS[i]
		var xz: Vector2 = a["xz"]
		var base := MissionManager.world_point(xz.x, xz.y, float(a["elev"]))
		var d := base - v.com_global()
		var hd := (d - fr.y * d.dot(fr.y))
		if hd.length() < float(best[1]):
			best = [i, hd.length(), int(fposmod(rad_to_deg(atan2(d.dot(fr.x), -d.dot(fr.z))), 360.0))]
	return best


func _wind_text(v: Vessel) -> Array:
	var w := Weather.wind_at(v.global_position)
	var wdir := int(fposmod(rad_to_deg(atan2(-w.x, w.z)), 360.0) / 10.0) * 10
	return [wdir, int(w.length() * 1.94)]


## kind: takeoff, landing, vector, weather, mayday
func request(kind: String) -> void:
	var v: Vessel = main.vessel if main else null
	if not is_instance_valid(v):
		return
	var cs := callsign()
	var me := cs.to_upper()
	var near := nearest_airfield(v)
	var af: Dictionary = TerrainGen.AIRFIELDS[near[0]]
	var tower := "Kule" if af["name"] == "Ana Üs" else "%s kulesi" % af["name"]
	var km := float(near[1]) / 1000.0
	var w := _wind_text(v)
	var grounded := v.radar_altitude() < 5.0
	match kind:
		"takeoff":
			say("%s, kalkış izni istiyorum." % tower, "%s, request takeoff." % tower, me)
			if not grounded:
				say("%s, zaten havadasınız." % cs, "%s, you are already airborne." % cs, tower.to_upper())
			elif km > 3.0:
				say("%s, sizi pistte görmüyoruz. Kendi sorumluluğunuzda kalkın." % cs, "%s, not on a runway, depart at your own discretion." % cs, tower.to_upper())
			else:
				_cleared_takeoff = true
				say("%s, pist üç altı, rüzgar %d derece %d knot. Kalkışa izin verildi." % [cs, w[0], w[1]],
					"%s, runway three six, wind %d at %d knots, cleared for takeoff." % [cs, w[0], w[1]], tower.to_upper())
		"landing":
			say("%s, %d kilometre mesafedeyim, iniş istiyorum." % [tower, roundi(km)], "%s, %d kilometers out, request landing." % [tower, roundi(km)], me)
			if grounded:
				say("%s, yerdesiniz." % cs, "%s, you are on the ground." % cs, tower.to_upper())
			else:
				_cleared_landing = true
				var elev := int(af["elev"])
				say("%s, %s, kerteriz %03d, %d kilometre. Pist üç altı, rüzgar %d derece %d knot, meydan rakımı %d metre. Takım aşağı, inişe izin verildi." % [cs, tower.to_lower(), near[2], roundi(km), w[0], w[1], elev],
					"%s, steer %03d, %d kilometers. Runway three six, wind %d at %d, cleared to land." % [cs, near[2], roundi(km), w[0], w[1]], tower.to_upper())
		"vector":
			say("%s, en yakın meydana yön istiyorum." % tower, "%s, request vectors to nearest field." % tower, me)
			say("%s, %s kerteriz %03d, %d kilometre." % [cs, af["name"], near[2], roundi(km)],
				"%s, %s bearing %03d, %d kilometers." % [cs, af["name"], near[2], roundi(km)], tower.to_upper())
		"weather":
			say("%s, meydan hava durumu?" % tower, "%s, request weather." % tower, me)
			say("%s, %s, rüzgar %d derece %d knot, yerel saat %s." % [cs, Weather.preset_name().to_lower(), w[0], w[1], Weather.format_hour(Weather.local_hour(v.global_position))],
				"%s, %s, wind %d at %d knots." % [cs, Weather.preset_name(), w[0], w[1]], tower.to_upper())
		"mayday":
			say("Mayday, mayday, mayday, %s. Acil durum!" % cs, "Mayday mayday mayday, %s, declaring emergency." % cs, me)
			say("%s, acil durum anlaşıldı. %s kerteriz %03d, %d kilometre, tüm pistler size açık. Kurtarma ekibi hazırda." % [cs, af["name"], near[2], roundi(km)],
				"%s, roger mayday. %s bearing %03d, %d kilometers, all runways yours." % [cs, af["name"], near[2], roundi(km)], tower.to_upper())
