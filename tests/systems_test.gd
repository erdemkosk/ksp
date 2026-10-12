extends Node
## Sistem testleri:
##   --starttest : pistte soğuk başlar, otomatik marşı çalıştırır, N2/JFS/durumu yazdırır
##   --gtest     : havada yüksek hızda lövyeyi sonuna kadar çeker; G, yük ve kopan parçalar

var main: Node
var mode := ""
var _t := 0.0
var _next_log := 0.0


func _ready() -> void:
	var v: Vessel = main.vessel
	v.part_destroyed.connect(func(p: Part) -> void: print("  KOPTU: %s (t=%.2f, G=%.1f)" % [p.title, _t, v.g_force]))
	v.system_message.connect(func(t: String) -> void: print("  MESAJ: %s (t=%.1f)" % [t, _t]))
	if mode == "start":
		v.auto_start()
	else:
		v.linear_velocity = v.forward() * float(Game.args.get("speed", "300"))


func _physics_process(delta: float) -> void:
	var v: Vessel = main.vessel
	_t += delta
	if mode == "gtest":
		v.sas = false
		v.ctrl_throttle = 1.0
		v.ctrl_pitch = 1.0 if _t > 1.0 else 0.0
	if _t >= _next_log:
		_next_log += 0.5
		if mode == "start":
			var e: EngineModule = v.engines()[0]
			print("t=%4.1f bat=%s jfs=%.2f durum=%d N2=%.2f güç=%s itki=%5.1f kN" % [
				_t, v.battery_on, v.jfs_spool, e.state, e.n2, v.has_power(), v.total_thrust() / 1000.0])
		else:
			var worst: Part = null
			for p in v.parts:
				if worst == null or p.stress > worst.stress:
					worst = p
			print("t=%4.1f hız=%5.1f G=%+5.1f yük=%.2f (%s) parça=%d" % [
				_t, v.airspeed(), v.g_force, v.max_stress, worst.title if worst else "-", v.parts.size()])
	if _t >= (22.0 if mode == "start" else 6.0):
		print("TEST BİTTİ")
		get_tree().quit()
