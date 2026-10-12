extends Node
## --missionendtest: görev hedeflerini 3. sn'de yok eder (görev havada biter), sonuç ekranı
## açılmamalı; sonra otomatik iniş başlar, uçak durunca sonuç ekranı açılmalı.

var main: Node
var _t := 0.0
var _phase := 0


func _physics_process(delta: float) -> void:
	_t += delta
	var mm: MissionManager = main.mission
	if _phase == 0 and _t > 3.0:
		for n in main.world.get_children():
			if n is GroundTarget and n.objective:
				n.take_damage(99999.0)
		_phase = 1
	elif _phase == 1 and mm.state != "running":
		print("GÖREV BİTTİ havada: durum=%s sonuç_ekranı=%s bekliyor=%s irt=%.0f" % [mm.state, is_instance_valid(mm._result), mm._await_landing, main.vessel.radar_altitude()])
		main.start_autoland()
		_phase = 2
	elif _phase == 2 and is_instance_valid(mm._result):
		print("SONUÇ EKRANI açıldı: yerde=%s hız=%.1f t=%.0f kokpit=%s pilot=%s parça=%d irt=%.0f" % [mm._grounded(main.vessel), main.vessel.ground_speed(), _t, main.vessel.cockpit() != null, main.vessel.has_pilot(), main.vessel.parts.size(), main.vessel.radar_altitude()])
		get_tree().quit()
	if _phase == 2 and fmod(_t, 2.0) < delta:
		var v: Vessel = main.vessel
		print("t=%.0f irt=%.0f yer=%.0f hız=%.0f parça=%d dikey=%+.0f yunus=%+.0f yatış=%+.0f %s" % [_t, v.altitude(), v.radar_altitude(), v.airspeed(), v.parts.size(), v.vertical_speed(), v.pitch_deg(), v.roll_deg(), main.autoland.status() if is_instance_valid(main.autoland) else "-"])
	if _t > 400.0:
		print("MISSIONENDTEST zaman aşımı")
		get_tree().quit()
