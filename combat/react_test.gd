class_name ReactTest
extends Node
## Yer birimi tepki testi (--reacttest). Kayıtlara dokunmaz, sonunda oyundan çıkar.
##   --mission=kara : bir kamyonu vurur (konvoy dağılır), uçağı uçaksavarın yanından düz geçirir
##                    (öncül nişan/seri), uçaksavarı vurur (susar), uçağı uzaklaştırır (konvoy
##                    toparlanıp yola döner). Durumları zamanla yazdırır.
##   --mission=heli : helikopteri vurur, kaçınmayı (alçalma, maske noktası, fişek) yazdırır.

static var _started := false

var _t := 0.0
var _print_t := 0.0
var _main: Node
var _phase := 0
var _aaa_shots0 := 0


static func ensure(from: Node) -> void:
	if _started:
		return
	_started = true
	# test kipi: kadro/kariyer kaydı yazılmaz (Crew._testing missiontest'i tanır)
	Game.args["missiontest"] = true
	from.get_tree().root.add_child.call_deferred(ReactTest.new())


func _ready() -> void:
	_main = get_tree().current_scene
	GroundTarget.alert_time = 20.0
	print("REACT: test başladı, görev=", Game.mission)


func _units(cls: Variant) -> Array:
	var out := []
	for n in _main.world.get_children():
		if is_instance_of(n, cls):
			out.append(n)
	return out


func _physics_process(delta: float) -> void:
	_t += delta
	_print_t -= delta
	if Game.mission == "heli":
		_heli_test()
	else:
		_convoy_test(delta)


func _convoy_test(_delta: float) -> void:
	var trucks := _units(ConvoyTruck)
	var guns := _units(AaaGun)
	if trucks.is_empty() or guns.is_empty():
		return
	var aaa: AaaGun = guns[0]
	var v: Vessel = _main.vessel
	# uçak: 3-40 sn uçaksavarın 900 m yanından 700 m yükseklikte düz geçer, sonra uzaklaşır
	if is_instance_valid(v):
		var a := GroundTarget.surface_xz(aaa.global_position)
		var xz: Vector2
		var alt: float
		if _t < 40.0:
			xz = a + Vector2(-2600.0 + (_t - 3.0) * 120.0, 900.0)
			alt = MissionManager.ground_height(xz.x, xz.y) + 700.0
		else:
			xz = a + Vector2(9000.0, 9000.0)
			alt = 6000.0
		var p := MissionManager.world_point(xz.x, xz.y, alt)
		var p2 := MissionManager.world_point(xz.x + 1.0, xz.y, alt)
		v.global_position = p - (v.com_global() - v.global_position)
		v.linear_velocity = (p2 - p).normalized() * (120.0 if _t < 40.0 else 0.0)
		v.angular_velocity = Vector3.ZERO
	if _phase == 0 and _t > 3.0:
		_phase = 1
		print("REACT t=%.1f: kamyon vuruluyor (%s)" % [_t, trucks[1].unit_name])
		trucks[1].take_damage(40.0)
	if _phase == 1 and _t > 16.0:
		_phase = 2
		_aaa_shots0 = aaa.shots()
		aaa.take_damage(80.0)
		print("REACT t=%.1f: uçaksavar vuruldu, sessiz=%s mermi=%d" % [_t, aaa.quiet(), _aaa_shots0])
	if _phase == 2 and _t > 19.0:
		_phase = 3
		print("REACT t=%.1f: sessizken atılan mermi=%d (sessiz=%s)" % [_t, aaa.shots() - _aaa_shots0, aaa.quiet()])
	if _print_t <= 0.0:
		_print_t = 3.0
		var line := "REACT t=%5.1f |" % _t
		for tr: ConvoyTruck in trucks:
			var off := tr._xz.distance_to(tr._leave_xz) if tr.state != "road" else 0.0
			line += " %s%s/%.0fm/%.0f" % [tr.state, "*" if tr.destroyed else "", off, tr._v]
		line += " | AAA:"
		for g: AaaGun in guns:
			line += " %d%s%s" % [g.shots(), "(q)" if g.quiet() else "", "(a)" if g.alerted() else ""]
		var esc := 0
		for tr: ConvoyTruck in trucks:
			esc += tr.shots()
		line += " | refakat=%d isabet=%d" % [esc, Damage.vessel_hits]
		print(line)
	if _t > 95.0:
		var on_road := 0
		for tr: ConvoyTruck in trucks:
			if tr.state == "road" or tr.destroyed:
				on_road += 1
		print("REACT SONUÇ: yolda %d/%d, uçaksavar mermi %d" % [on_road, trucks.size(), aaa.shots()])
		get_tree().quit()


func _heli_test() -> void:
	var helis := _units(Helicopter)
	if helis.is_empty():
		return
	var h: Helicopter = helis[0]
	if _phase == 0 and _t > 3.0:
		_phase = 1
		print("REACT t=%.1f: helikopter vuruluyor" % _t)
		h.take_damage(30.0)
	if _print_t <= 0.0:
		_print_t = 1.0
		for x: Helicopter in helis:
			var agl := Planet.altitude(x.global_position) - x._ground(x.global_position)
			print("REACT t=%5.1f heli %s kaçış=%s agl=%.0f hız=%.0f fişek=%d alarm=%s" % [_t, x.name, x.evading(), agl, x.velocity.length(), x.flares_left(), x.alerted()])
	if _t > 20.0:
		get_tree().quit()
