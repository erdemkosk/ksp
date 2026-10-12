extends Node
## Çarpışma testi: havada başlar, burnu aşağı ve sağa yatırıp yere/suya dalar.
## Kopan parçaları, enkaz sayısını ve uçağın durumunu yazdırır.
## Kullanım: --air --alt=120 --crashtest   (suya çarpma için ayrıca --x=40000)

const DURATION := 14.0

var main: Node
var _t := 0.0
var _next_log := 0.0


func _ready() -> void:
	main.vessel.part_destroyed.connect(func(p: Part) -> void:
		print("  KOPTU: %s (t=%.2f)" % [p.title, _t]))
	main.vessel.cockpit_lost.connect(func() -> void: print("  KOKPİT KAYBEDİLDİ (t=%.2f)" % _t))


func _physics_process(delta: float) -> void:
	var v: Vessel = main.vessel
	_t += delta
	v.ctrl_throttle = 0.8
	v.ctrl_pitch = -0.6 if _t > 0.5 else 0.0
	v.ctrl_roll = 0.4 if _t > 0.5 else 0.0
	if _t >= _next_log:
		_next_log += 0.5
		var debris := 0
		for c in main.world.get_children():
			if c is Debris:
				debris += 1
		var sub := 0.0
		for p in v.parts:
			sub = maxf(sub, p.submerged)
		print("t=%4.1f irt=%7.1f hız=%6.1f parça=%2d enkaz=%d kütle=%5.0f batma=%.2f" % [
			_t, v.altitude(), v.linear_velocity.length(), v.parts.size(), debris, v.mass, sub])
	if _t >= DURATION:
		print("ÇARPIŞMA TESTİ BİTTİ")
		get_tree().quit()
