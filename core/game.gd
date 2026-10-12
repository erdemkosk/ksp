extends Node
## Global: tuş haritası ve komut satırı argümanları.

const KEY_BINDINGS := {
	"pitch_up": [KEY_S, KEY_DOWN],
	"pitch_down": [KEY_W, KEY_UP],
	"roll_left": [KEY_Q, KEY_LEFT],
	"roll_right": [KEY_E, KEY_RIGHT],
	"yaw_left": [KEY_A],
	"yaw_right": [KEY_D],
	"throttle_up": [KEY_SHIFT],
	"throttle_down": [KEY_CTRL],
	"throttle_full": [KEY_Z],
	"throttle_cut": [KEY_X],
	"brakes": [KEY_B],
	"gear_toggle": [KEY_G],
	"sas_toggle": [KEY_T],
	"reset_runway": [KEY_R],
	"air_start": [KEY_H],
	"camera_mode": [KEY_C],
	"toggle_debug": [KEY_F3],
	"toggle_help": [KEY_F1],
	"weather_cycle": [KEY_F5],
	"time_cycle": [KEY_F6],
	"time_faster": [KEY_PERIOD],
	"time_slower": [KEY_COMMA],
	"eva": [KEY_F],
	"jump": [KEY_SPACE],
	"canopy_toggle": [KEY_K],
	"lights_toggle": [KEY_L],
	"engine_toggle": [KEY_I],
	"parking_brake": [KEY_P],
	"autopilot_toggle": [KEY_U],
	"panel_toggle": [KEY_N],
	"fire": [KEY_SPACE],
	"weapon_cycle": [KEY_V],
	"spawn_enemy": [KEY_F7],
	"hangar": [KEY_J],
	"flare": [KEY_O],
	"mouse_flight": [KEY_Y],
	"pause": [KEY_ESCAPE],
	"cursor_toggle": [KEY_TAB],
	"target_cycle": [KEY_F4],
	"pod_toggle": [KEY_F8],
	"quicksave": [KEY_F9],
	"quickload": [KEY_F10],
	"map": [KEY_M],
}

## Gamepad (Xbox düzeni): sol çubuk burun/yatış, sağ çubuk sapma/gaz, RT ateş, LT fren,
## LB flare, Y silah, X takım, B SAS, RB kamera, Start motor, Back park freni.
const JOY_BINDINGS := {
	"pitch_up": [["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"pitch_down": [["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"roll_left": [["axis", JOY_AXIS_LEFT_X, -1.0]],
	"roll_right": [["axis", JOY_AXIS_LEFT_X, 1.0]],
	"yaw_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
	"yaw_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
	"throttle_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"throttle_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],
	"fire": [["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"brakes": [["axis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"flare": [["button", JOY_BUTTON_LEFT_SHOULDER]],
	"weapon_cycle": [["button", JOY_BUTTON_Y]],
	"gear_toggle": [["button", JOY_BUTTON_X]],
	"sas_toggle": [["button", JOY_BUTTON_B]],
	"camera_mode": [["button", JOY_BUTTON_RIGHT_SHOULDER]],
	"engine_toggle": [["button", JOY_BUTTON_START]],
	"parking_brake": [["button", JOY_BUTTON_BACK]],
}

## `godot -- --autotest --screenshot=x.png` gibi argümanlar.
var args := {}

## Hangarda tasarlanıp piste çıkarılan uçak (craft sözlüğü). Boşsa varsayılan uçak.
var flight_craft := {}
## Uçuş kaydından devam: FlightSave verisi (main _ready'de uygulanır)
var resume := {}

## Oyuncu ayarları (user://settings.json)
var settings := {"mouse_aim": false, "mouse_sens": 1.0, "volume": 0.8, "fov": 78.0, "radio": true, "shake": 1.0, "g_limit": true, "sandbox": false, "panel_alpha": 0.6, "fullscreen": true}
## Hangar açılınca yapılacak iş: "missions" (görev seçimi), "crew" (kadro) ya da boş
var hangar_action := ""

## Seçili görev kimliği (MissionManager.DEFS). Boşsa serbest uçuş.
var mission := ""


func _ready() -> void:
	_register_inputs()
	_parse_args()
	load_settings()
	_apply_window()


## Tam ekran (ayar, varsayılan açık). Testler ve ekran görüntüleri pencerede kalır.
func _apply_window() -> void:
	var testing := args.has("screenshot") or DisplayServer.get_name() == "headless"
	for k in ["autotest", "hangartest", "missiontest", "dogfight", "guntest", "bombtest"]:
		testing = testing or args.has(k)
	if testing:
		return
	var fs := bool(settings.get("fullscreen", true))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		settings["fullscreen"] = not bool(settings.get("fullscreen", true))
		save_settings()
		_apply_window()


func _register_inputs() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in JOY_BINDINGS:
		for spec: Array in JOY_BINDINGS[action]:
			if spec[0] == "axis":
				var je := InputEventJoypadMotion.new()
				je.axis = spec[1]
				je.axis_value = spec[2]
				InputMap.action_add_event(action, je)
				InputMap.action_set_deadzone(action, 0.12)
			else:
				var jb := InputEventJoypadButton.new()
				jb.button_index = spec[1]
				InputMap.action_add_event(action, jb)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := arg.trim_prefix("--")
		var eq := a.find("=")
		if eq == -1:
			args[a] = true
		else:
			args[a.substr(0, eq)] = a.substr(eq + 1)


func load_settings() -> void:
	if FileAccess.file_exists("user://settings.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				settings[k] = d[k]
	apply_settings()


func save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))
	apply_settings()


func apply_settings() -> void:
	_apply_window()
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(settings["volume"]), 0.0001)))
