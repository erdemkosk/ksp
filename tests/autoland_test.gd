extends Node
## Otomatik iniş testi: havada başla, otomatik inişi başlat, aşamaları ve sonucu yazdır.
var main: Node
var _t := 0.0
func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	main.start_autoland()
	main.autoland.finished.connect(func(ok: bool) -> void:
		var af: Dictionary = TerrainGen.AIRFIELDS[int(Game.args.get("af", "0"))]
		var c := MissionManager.world_point(af["xz"].x, af["xz"].y, float(af["elev"]))
		var fr := Planet.local_basis(c)
		var d: Vector3 = main.vessel.com_global() - c
		print("OTOMATİK İNİŞ SONUÇ: %s  t=%.0f  hız=%.1f  pist merkezine göre x=%.0f z=%.0f (pist |x|<22, |z|<1200)" % [ok, _t, main.vessel.ground_speed(), d.dot(fr.x), d.dot(fr.z)])
		get_tree().quit())
func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	if fmod(_t, 10.0) < delta and is_instance_valid(main.autoland):
		print("t=%3d %s irt=%4d yer=%4d hız=%3d dikey=%+5.1f yunus=%+.1f" % [_t, main.autoland.status(), v.altitude(), v.radar_altitude(), v.airspeed(), v.vertical_speed(), v.pitch_deg()])
	if _t > 500.0:
		print("ZAMAN AŞIMI")
		get_tree().quit()
