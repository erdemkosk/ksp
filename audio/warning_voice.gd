class_name WarningVoice
extends Node
## Kokpit sesli uyarıları ("Bitching Betty" tarzı). Gerçek kayıtlar telifli olduğu için
## işletim sisteminin konuşma sentezi kullanılır (Windows'ta tercihen kadın sesi Zira).
## Yeni bir uyarı başlayınca ana uyarı bip sesi çalar; kritik uyarılar tekrarlanır.

const PHRASES := {
	"PULL UP": ["Pull up. Pull up.", 2.2],
	"OVER G": ["Over G. Over G.", 2.5],
	"STALL": ["Stall. Stall.", 2.0],
	"YAKIT AZ": ["Bingo fuel.", 20.0],
	"YAKIT BİTTİ": ["Fuel empty.", 15.0],
	"İNİŞ TAKIMI": ["Landing gear.", 6.0],
	"KANOPİ AÇIK": ["Canopy.", 8.0],
	"FÜZE": ["Missile. Missile.", 3.0],
}

var vessel: Vessel
var enabled := true

var _voice := ""
var _cooldown := {}
var _active := PackedStringArray()


func _ready() -> void:
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


func _process(delta: float) -> void:
	for k in _cooldown.keys():
		_cooldown[k] -= delta
	if not enabled or not is_instance_valid(vessel) or not vessel.has_pilot():
		_active = PackedStringArray()
		return
	var warnings := Hud.active_warnings(vessel)
	for w in warnings:
		if not PHRASES.has(w):
			continue
		var is_new := not w in _active
		if is_new:
			Sfx.play_ui("caution_beep.ogg", -6.0)
		if _cooldown.get(w, 0.0) <= 0.0:
			var entry: Array = PHRASES[w]
			# kritik uyarılar sıraya girmesin: önceki konuşmayı kes
			DisplayServer.tts_speak(entry[0], _voice, 70, 1.0, 1.15, 0, w == "PULL UP" or w == "STALL" or w == "OVER G" or w == "FÜZE")
			_cooldown[w] = entry[1]
	_active = warnings
