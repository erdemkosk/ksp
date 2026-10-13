extends Node
## Tasarım testleri (kayıt yazılmaz: Crew._testing):
##   --servicetest   sahte uçuşlarla hizmet kaydı ve prototip olgunlaşması
##   --fleettest     filo tipini seç (--fleetcraft=atmaca), kanat adamı ve dost devriyeyi denetle
## main._ready WingFlight.setup'tan önce ekler.

var main: Node
var _t := 0.0
var _done := false


func _ready() -> void:
	if Game.args.has("servicetest"):
		Designs.run_service_test()
		get_tree().quit()
		return
	if Game.args.has("fleettest"):
		var path := "res://crafts/%s.json" % String(Game.args.get("fleetcraft", "atmaca"))
		var c := VesselBuilder.load_craft(path)
		c["name"] = String(c.get("name", "Filo")) + " (filo)"
		Career.money = 10000000
		for e: Dictionary in c.get("parts", []):
			Career.unlocked[String(e.get("part", ""))] = true
		var err := Designs.produce(c)
		print("FLEET produce '%s' err='%s' fleet=%s quality=%.2f" % [c["name"], err, Designs.fleet_name(), Designs.fleet_quality()])
		Game.args["wingman"] = true
		Game.args["ambient"] = true
		Game.args["ambienttest"] = true


func _physics_process(delta: float) -> void:
	if Game.args.has("prototest"):
		_proto_step(delta)
		return
	if _done or not Game.args.has("fleettest"):
		return
	_t += delta
	if _t < 4.0:
		return
	_done = true
	var fleet := Designs.fleet_craft()
	var want := VesselBuilder.build(fleet.duplicate(true))
	var n := want.parts.size()
	want.free()
	var wf: WingFlight = WingFlight.active
	if wf and is_instance_valid(wf.ship):
		print("FLEET wingman parts=%d fleet_parts=%d lead_parts=%d meta=%s  %s" % [wf.ship.parts.size(), n, main.vessel.parts.size(),
			wf.get_meta("design_name", "-"), "OK" if wf.ship.parts.size() == n else "FARKLI"])
	else:
		print("FLEET wingman yok")
	var amb: AmbientAir = main.get_node_or_null("AmbientAir")
	if amb == null:
		print("FLEET ambient yok")
		get_tree().quit()
		return
	for g: Dictionary in amb._groups:
		if g["team"] == "oyuncu" and g["kind"] == "patrol" and (g["live"] as Array).is_empty():
			await amb._materialize(g, 1)
			var v: Vessel = (g["live"] as Array)[0] if not (g["live"] as Array).is_empty() else null
			print("FLEET ambient %s parts=%d fleet_parts=%d %s" % [g["name"], v.parts.size() if v else -1, n, "OK" if v and v.parts.size() == n else "FARKLI"])
			break
	print("FLEET FrontAI blunt şansı %%%d" % roundi(15.0 * Designs.fleet_quality()))
	get_tree().quit()


## --prototest (--mission=it --aiplayer [--protorate=200] [--duration=150]): prototip arızalarını
## yazdır; 60. sn'den itibaren takımı topla/aç (sıkışma ve kurtarma), sonda özet.
var _gear_t := 60.0

func _proto_step(delta: float) -> void:
	_t += delta
	var v: Vessel = main.vessel
	if not is_instance_valid(v):
		return
	if Game.args.has("protofire"):
		# serbest uçuş: oyuncu kumandası kapalı, 3 sn'de bir IR füze tetiği (0.3 sn basılı)
		main.player.enabled = false
		v.master_arm = true
		v.selected_weapon = Vessel.WEAPON_MISSILE
		var ph := fmod(_t, 3.0)
		var was := v.ctrl_fire
		v.ctrl_fire = _t > 50.0 and ph < 0.3
		if v.ctrl_fire and not was:
			print("PROTO t=%.0f tetik, kalan füze=%d" % [_t, v.missiles_left()])
	if _t > _gear_t and _t < 120.0 and not Game.args.has("protofire"):
		_gear_t += 4.0
		v.gear_down = not v.gear_down
		print("PROTO t=%.0f takım komutu %s  deploy=%.2f" % [_t, "AÇ" if v.gear_down else "TOPLA", v.gear_deploy()])
	if fmod(_t, 10.0) < delta:
		var eng := PackedStringArray()
		for e in v.engines():
			eng.append("%s n2=%.2f lim=%.2f" % [EngineModule.State.keys()[e.state], e.n2, e.thrust_limit])
		print("PROTO t=%.0f alt=%d hız=%d radar=%s motor=[%s] arızalar=%s" % [_t, v.radar_altitude(), v.airspeed(), v.radar_on, ", ".join(eng), v.failures.values()])
	if _t > float(Game.args.get("duration", "150")):
		print("PROTO özet: arızalar=%s  rapor: %s" % [Designs.flight_failures, " | ".join(Designs.note_flight(main.spawned_craft, main, false))])
		get_tree().quit()
