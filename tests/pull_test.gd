extends Node
## --pulltest: yüksek hızda S (burun yukarı) tuşuna 8 sn basılı tutar; G, zorlanma ve bayılmayı yazar.
## --nolimit ile G sınırlayıcı kapalı.

var main: Node
var _t := 0.0
var _max_g := 0.0
var _fainted := false


func _ready() -> void:
	if Game.args.has("boomcheck"):
		var s := Sfx.sonic_boom_stream()
		var peak := 0
		for i in range(0, s.data.size(), 2):
			peak = maxi(peak, absi(s.data.decode_s16(i)))
		print("BOOM sure=%.2f peak=%d" % [s.data.size() / 2.0 / s.mix_rate, peak])
	main.player.g_limiter = not Game.args.has("nolimit")
	main.player.throttle = 1.0
	main.vessel.linear_velocity = main.vessel.forward() * float(Game.args.get("v", "210"))


func _physics_process(delta: float) -> void:
	_t += delta
	var p: PlayerController = main.player
	if _t > 1.0 and _t < 9.0:
		Input.action_press("pitch_up")
	elif _t >= 9.0:
		Input.action_release("pitch_up")
	_max_g = maxf(_max_g, main.vessel.g_force)
	_fainted = _fainted or p.blackout
	if fmod(_t, float(Game.args.get("every", "0.5"))) < delta:
		print("t=%.1f v=%d G=%.1f strain=%.2f auth=%.2f blk=%s" % [_t, main.vessel.airspeed() * 3.6, main.vessel.g_force, p.g_strain, p._auth, p.blackout])
	if _t > 10.0:
		print("PULLTEST maxG=%.1f tol=%.1f bayildi=%s" % [_max_g, p.g_tolerance(), _fainted])
		get_tree().quit()
