extends Node
## --breakcheck: 6 sn boyunca parça sayısını, en yüklü parçayı ve hava freni kuvvetini yazar.
var main: Node
var _t := 0.0

func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	if fmod(_t, 0.5) < delta:
		var worst := ""
		var ws := 0.0
		for p in v.parts:
			if p.stress > ws:
				ws = p.stress
				worst = p.title
		var ab := 0.0
		for m in v.get_modules_of(AirbrakeModule):
			ab = m.deploy
		var dmg := PackedStringArray()
		for p in v.parts:
			if p.hp < p.max_hp * 0.999:
				dmg.append("%s %d%%" % [p.title, p.health_ratio() * 100.0])
		print("t=%.1f parça=%d hız=%d en_yüklü=%s %.2f hava_freni=%.2f kokpit=%s hasarlı=%s" % [_t, v.parts.size(), v.airspeed() * 3.6, worst, ws, ab, v.cockpit() != null, dmg])
	if Game.args.has("killwing") and absf(_t - 1.0) < delta * 0.6:
		for p in v.parts.duplicate():
			for m in p.modules:
				if m is WingModule and not m is ControlSurfaceModule and p in v.parts:
					v.destroy_part(p)
		print("KANATLAR KOPTU parça=%d kokpit=%s kamera_hedefi_uçak=%s" % [v.parts.size(), v.cockpit() != null, main.camera.target == v])
	if Game.args.has("killwing") and absf(_t - 2.5) < delta * 0.6:
		main.eject()
		print("FIRLATMA pilot=%s kamera_eva=%s" % [is_instance_valid(main.pilot), main.camera.is_eva()])
	if _t > 6.0:
		get_tree().quit()
