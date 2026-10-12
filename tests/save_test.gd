extends Node
## --savetest: 3 sn uç, kaydet, konumu yaz, sahneyi kayıttan yeniden yükle; 1 sn sonra
## konum/hız farkını yaz. (--savetest=2 aşaması yeniden yüklemede otomatik)

var main: Node
var _t := 0.0
var _phase := 1


func _ready() -> void:
	_phase = 2 if str(Game.args.get("savetest", "")) == "2" else 1


func _abs(p: Vector3) -> Vector3:
	return p + Vector3(FloatingOrigin.offset_x, FloatingOrigin.offset_y, FloatingOrigin.offset_z)


func _physics_process(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	if _phase == 1 and _t > 3.0:
		main.vessel.parts[3].hp *= 0.5
		print("KAYIT  abs=%s hız=%.1f yakıt=%.0f irt=%.0f" % [_abs(v.global_position), v.airspeed(), v.fuel_amount(), v.altitude()])
		print("kaydedildi=%s" % FlightSave.save(main))
		Game.args["savetest"] = "2"
		main.quick_load()
		_phase = 0
	elif _phase == 2 and _t > 0.05 and _t < 0.1:
		print("YÜKLE  abs=%s hız=%.1f yakıt=%.0f irt=%.0f hp3=%.0f" % [_abs(v.global_position), v.airspeed(), v.fuel_amount(), v.altitude(), v.parts[3].hp])
	elif _phase == 2 and _t > 2.0:
		print("SAVETEST bitti irt=%.0f hız=%.1f" % [v.altitude(), v.airspeed()])
		get_tree().quit()
