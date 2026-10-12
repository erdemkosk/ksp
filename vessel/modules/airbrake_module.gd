class_name AirbrakeModule
extends PartModule
## Hava freni: fren (B) basılıyken panel açılır (~1 sn), hava direnci büyür.
## Görselde "Panel" adlı parça menteşesinden 60° kalkar.

const OPEN_DEG := -60.0

var area := 1.2
var cd := 1.25
var deploy := 0.0
var hold := false          ## eylem panelinden sürekli açık
var _was_open := false
var _panel: Node3D
var _panel_rot := Vector3.ZERO


func setup(p: Dictionary) -> void:
	area = p.get("area", area)
	cd = p.get("cd", cd)


func on_attached() -> void:
	_panel = part.get_node_or_null("Visual/Panel")
	if _panel:
		_panel_rot = _panel.rotation_degrees


func physics_tick(delta: float) -> void:
	var want := 1.0 if ((vessel.ctrl_brakes and not vessel.parking_brake) or hold) and vessel.has_power() else 0.0
	if (want > 0.5) != _was_open:
		_was_open = want > 0.5
		Sfx.play_at("hydraulic_thunk.ogg", part.global_position, -10.0, 1.3 if _was_open else 1.1, 800.0)
	# yüksek hızda hava kuvveti kapağı kısmen geri iter ("blowback"): açılma dinamik basınçla sınırlı
	var q := 0.5 * vessel.air_density() * pow(vessel.airspeed(), 2.0)
	want = minf(want, clampf(22000.0 / maxf(q, 1.0), 0.35, 1.0))
	deploy = move_toward(deploy, want, delta * 1.2)
	if _panel:
		_panel.rotation_degrees = _panel_rot + Vector3(OPEN_DEG * deploy, 0, 0)
	if deploy <= 0.001:
		return
	var pos := part.global_position
	var v := vessel.air_velocity_at(pos)
	var f := -v * v.length() * 0.5 * vessel.air_density() * cd * area * deploy
	vessel.add_force_at(f, pos)
	part.aero_load += f
