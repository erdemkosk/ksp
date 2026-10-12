extends Node
## --walktest: pilot iner, önce yürür sonra koşar ve zıplar; hızları yazar. --run: hep koş.

var main: Node
var _t := 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > 1.2 and not is_instance_valid(main.pilot):
		main.try_eva()
	var p: PilotCharacter = main.pilot
	if not is_instance_valid(p):
		return
	Input.action_press("yaw_left" if Game.args.has("side") else "pitch_down")
	if Game.args.has("close"):
		main.camera.eva_distance = 2.6
		main.camera.orbit_elevation = 0.05
	if _t > 3.0 or Game.args.has("run"):
		Input.action_press("throttle_up")
	if absf(_t - 5.0) < delta:
		Input.action_press("jump")
	elif _t > 5.1:
		Input.action_release("jump")
	if fmod(_t, 0.5) < delta:
		print("t=%.1f hız=%.2f yerde=%s amt=%.2f run=%.2f squash=%.2f off=%.2f" % [_t, p.velocity.length(), p.is_on_floor(), p._amount, p._run, p._squash, p._off_floor])
	if _t > 7.0 and not Game.args.has("screenshot"):
		get_tree().quit()
