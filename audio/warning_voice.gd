class_name WarningVoice
extends Node
## Kokpit uyarıları: her uyarının kendine özgü tonu (kodla üretilir, bkz. Synth) ve sesli
## uyarısı ("Bitching Betty" tarzı, işletim sisteminin konuşma sentezi; Windows'ta tercihen
## kadın sesi Zira). Konuşma sentezi yoksa tonlar yine çalar.
## Öncelik: aynı anda tek ton ve tek konuşma; yüksek öncelikli uyarı düşüğü keser.
## Spam yok: her uyarının tekrar süresi, yeni uyarı için 0.25 sn kararlılık şartı ve
## kaybolduktan sonra 1 sn içinde dönerse "yeni" sayılmaması.

## ad: [öncelik (küçük = önemli), konuşma, konuşma tekrarı (s), ton, ton tekrarı (s; 0 = bir kez), kesici]
const DEFS := {
	"PULL UP": [0, "Pull up. Pull up.", 2.2, "tone_pullup", 0.95, true],
	"ENGINE FIRE": [1, "Engine fire. Engine fire.", 6.0, "tone_fire", 2.5, true],
	"MISSILE": [2, "Missile. Missile.", 3.0, "tone_missile", 0.0, true],
	"OVER G": [3, "Over G. Over G.", 2.5, "tone_overg", 1.2, true],
	"STALL": [4, "Stall. Stall.", 2.0, "tone_stall", 0.55, true],
	"ALTITUDE": [5, "Altitude. Altitude.", 4.0, "tone_altitude", 4.0, false],
	"LOCK": [6, "Spike.", 8.0, "tone_lock", 0.0, false],
	"GEAR": [7, "Landing gear.", 6.0, "tone_caution", 0.0, false],
	"FUEL EMPTY": [8, "Fuel empty.", 15.0, "tone_fuel", 15.0, false],
	"BINGO": [9, "Bingo fuel.", 30.0, "tone_fuel", 0.0, false],
	"CANOPY": [10, "Canopy.", 8.0, "tone_caution", 0.0, false],
}

var vessel: Vessel
var enabled := true            ## konuşma sentezi var mı
var tones := true

var _voice := ""
var _cooldown := {}            ## konuşma tekrar sayaçları
var _tone_cd := {}
var _pending := {}             ## ad -> görülme süresi (kararlılık)
var _gone := {}                ## ad -> kaybolalı geçen süre
var _active := PackedStringArray()
var _tone: AudioStreamPlayer
var _tone_name := ""
var _speaking := ""
var _speak_t := 0.0
var _eval_t := 0.0
var forced := PackedStringArray()   ## test: evaluate yerine bu uyarılar (--audiotest)


func _ready() -> void:
	_tone = AudioStreamPlayer.new()
	_tone.bus = Sfx.BUS_UI
	_tone.volume_db = -7.0
	add_child(_tone)
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		enabled = false
		return
	var voices := DisplayServer.tts_get_voices()
	var best := ""
	for v in voices:
		var name: String = v.get("name", "")
		var lang: String = v.get("language", "")
		if not lang.begins_with("en"):
			continue
		if best.is_empty():
			best = v["id"]
		if "Zira" in name or "Female" in name or "Hazel" in name or "Susan" in name or "Aria" in name or "Jenny" in name:
			best = v["id"]
			break
	_voice = best
	enabled = not _voice.is_empty()
	for v in voices:
		if v["id"] == _voice:
			print("Sesli uyarı sesi: ", v.get("name", "?"))


## Etkin uyarılar, önem sırasına göre.
static func evaluate(v: Vessel) -> PackedStringArray:
	var list := PackedStringArray()
	if not is_instance_valid(v) or v.parts.is_empty() or not v.has_pilot():
		return list
	var speed := v.airspeed()
	var radar := v.radar_altitude()
	var vs := v.vertical_speed()
	var airborne := radar > 4.0
	var gear := v.gear_deploy()
	# arazi yaklaşması: çarpmaya kalan süre (takım açık yaklaşmada yalnız çok dik alçalışta)
	var tti := radar / maxf(-vs, 0.01) if vs < -1.0 else INF
	if airborne and speed > 40.0 and ((tti < 5.0 and radar < 900.0 and (gear < 0.5 or vs < -25.0)) \
			or (radar < 300.0 and vs < -35.0 and gear < 0.5)):
		list.append("PULL UP")
	elif airborne and speed > 40.0 and gear < 0.5 and radar < 150.0 and tti < 12.0:
		list.append("ALTITUDE")
	for m in v.modules:
		if m is EngineModule and is_instance_valid(m.part) and m.part.hp < m.part.max_hp * 0.4:
			list.append("ENGINE FIRE")
			break
	if v.incoming_missile() != null:
		list.append("MISSILE")
	if v.max_stress > 0.85:
		list.append("OVER G")
	var stalled := absf(v.aoa_deg()) > 16.0
	for m in v.modules:
		if m is WingModule and m.stalled:
			stalled = true
	if airborne and speed > 30.0 and stalled:
		list.append("STALL")
	if v.has_power() and _locked(v):
		list.append("LOCK")
	if gear < 0.99 and radar < 120.0 and vs < -2.0 and speed < 110.0 and airborne:
		list.append("GEAR")
	var fuel := v.fuel_amount()
	if v.fuel_capacity() > 0.0:
		if fuel <= 0.0:
			list.append("FUEL EMPTY")
		elif fuel / v.fuel_capacity() < 0.15:
			list.append("BINGO")
	var c := v.cockpit()
	if c and c.canopy_open and speed > 30.0:
		list.append("CANOPY")
	var sorted := Array(list)
	sorted.sort_custom(func(a: String, b: String) -> bool: return int(DEFS[a][0]) < int(DEFS[b][0]))
	return PackedStringArray(sorted)


## Bir radar bize kilitli mi (SAM rampası ya da radar füzesi bize ayarlı avcı)?
static func _locked(v: Vessel) -> bool:
	if v.radar() == null and v.available_weapons().is_empty():
		return false     # RWR yok
	for site in SamSite.sites:
		if is_instance_valid(site) and not site.destroyed and site.tracking() == v and site.lock_progress() > 0.3:
			return true
	if not is_instance_valid(v.get_parent()):
		return false
	for n in v.get_parent().get_children():
		if n is Vessel and n != v and n.team != v.team:
			for m in n.modules:
				if m is MissileModule and m.radar_guided and m.target == v:
					return true
	return false


func _process(delta: float) -> void:
	for k in _cooldown.keys():
		_cooldown[k] -= delta
	for k in _tone_cd.keys():
		_tone_cd[k] -= delta
	_speak_t -= delta
	if _speaking != "" and _speak_t <= 0.0 and (not enabled or not DisplayServer.tts_is_speaking()):
		_speaking = ""
	_eval_t -= delta
	if _eval_t > 0.0:
		return
	var dt := 0.1 - _eval_t
	_eval_t = 0.1
	if not is_instance_valid(vessel) or not vessel.has_pilot():
		_active = PackedStringArray()
		_pending.clear()
		if _tone.playing and _tone_name != "":
			_tone.stop()
		return
	var raw := forced if not forced.is_empty() else evaluate(vessel)
	# kararlılık: 0.25 sn sürmeyen uyarı sayılmaz (PULL UP hariç); kısa kopmalar yok sayılır
	var now := PackedStringArray()
	for w in raw:
		_pending[w] = float(_pending.get(w, 0.0)) + dt
		_gone.erase(w)
		if w == "PULL UP" or w == "MISSILE" or _pending[w] >= 0.25 or w in _active:
			now.append(w)
	for w in _pending.keys():
		if not w in raw:
			_pending.erase(w)
	for w in _active:
		if not w in raw:
			_gone[w] = float(_gone.get(w, 0.0)) + dt
			if _gone[w] < 1.0:
				now.append(w)     # 1 sn içinde dönerse kesintisiz say
			else:
				_gone.erase(w)
				_tone_cd.erase(w)
				_cooldown.erase(w)
	var ordered := Array(now)
	ordered.sort_custom(func(a: String, b: String) -> bool: return int(DEFS[a][0]) < int(DEFS[b][0]))
	_active = PackedStringArray(ordered)
	# yalnız şu an gerçekten süren uyarılar ses çıkarır (kaybolanlar sadece "yeni" sayılmaz)
	for w in ordered:
		if not _gone.has(w):
			_play_tone(w)
			_speak(w)
			return


func _play_tone(w: String) -> void:
	if not tones:
		return
	var def: Array = DEFS[w]
	# daha önemli bir uyarının tonu çalıyorsa bekle; daha önemsizini kes
	if _tone.playing and _tone_name in DEFS and int(DEFS[_tone_name][0]) < int(def[0]):
		return
	if float(_tone_cd.get(w, 0.0)) > 0.0:
		return
	if _tone_cd.has(w) and float(def[4]) <= 0.0:
		return       # bir kez çalan ton
	_tone.stream = Synth.get_stream(def[3])
	_tone_name = w
	_tone.play()
	_tone_cd[w] = float(def[4]) if float(def[4]) > 0.0 else 1e9


func _speak(w: String) -> void:
	if not enabled:
		return
	var def: Array = DEFS[w]
	if float(_cooldown.get(w, 0.0)) > 0.0:
		return
	var interrupt := false
	if _speaking != "":
		if _speaking == w or int(DEFS[_speaking][0]) <= int(def[0]) or not bool(def[5]):
			return       # sürmekte olan konuşma daha önemli: sırası gelince
		interrupt = true
	DisplayServer.tts_speak(def[1], _voice, 75, 1.0, 1.15, 0, interrupt or bool(def[5]))
	_speaking = w
	_speak_t = 0.9
	_cooldown[w] = def[2]


func active() -> PackedStringArray:
	return _active
