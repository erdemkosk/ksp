extends Node
## Madalya / rütbe testi (yalnız bellekte; --medaltest kayıtları korur). Hangarda çalışır:
## godot --path . -- --hangar --medaltest [--screenshot=x.png --shot-time=2]
## Test pilotu çeşitli olaylarla uçurulur, kazanılanlar yazdırılır, sonra kadro paneli açılır
## (ekran görüntüsü yoksa çıkar).


func _ready() -> void:
	var crew := Crew
	var weather := Weather
	if not crew._testing():
		push_error("medaltest: --medaltest ile çalıştır")
		return
	# eski kayıt (yeni alanlar yok): varsayılanlar + sessiz madalya/rütbe
	var old := {"name": "Eski Pilot", "ucus": 3, "nisan": 2, "dayanim": 2, "xp": 900, "level": 4, "flights": 12, "kills": 6, "status": "hazır"}
	crew._ensure(old)
	print("ESKİ KAYIT: rütbe=%s madalyalar=%s km=%s ships=%s" % [Medals.rank_name(old), old["medals"], old["km"], old["ships"]])
	# test pilotu
	Game.test_flight = false
	var p: Dictionary = crew._new_pilot(1)
	p["name"] = "Test Pilot"
	crew.pilots.append(p)
	crew.selected = crew.pilots.size() - 1
	print("YENİ: %s %s  madalya=%d" % [Medals.rank_name(p), p["name"], p["medals"].size()])
	var ship := Warship.new()
	var truck := GroundTarget.new()
	for f in 12:
		match f:
			0:
				crew.add_kill()
				crew.note_landing(-1.0)
			1:
				crew.note_target_destroyed(ship)
				crew.note("ejections")
			2:
				for i in 10:
					crew.note_target_destroyed(truck)
				weather.clock = 23.0
				crew.note_mission(true, "kurtarma", Vector3(0, 6.0e6, 0))
				weather.clock = 12.5
			3:
				weather.preset = Weather.Preset.STORM
				crew.note_landing(-2.5)
				weather.preset = Weather.Preset.CLEAR
				crew.note_air(4000.0, 260.0, 9.4)   # ~1040 km, 9.4 G
			4:
				for i in 4:
					crew.add_kill()
				crew.note("damaged_returns")
		for i in 9:
			crew.note_landing(-1.0)
		crew.note_mission(true, "kara", Vector3(0, 6.0e6, 0))
		crew.award(300 + f * 120)
		print("--- uçuş %d" % (f + 1))
		for l in crew.end_flight(false):
			print("   ", l)
	print("SONUÇ: %s  seviye %d  uçuş %d  madalya %d/%d  km=%.0f  maxG=%.1f" % [Medals.rank_name(p), p["level"], p["flights"], p["medals"].size(), Medals.LIST.size(), p["km"], p["max_g"]])
	for m in Medals.LIST:
		print("   %s %-16s %s" % ["[X]" if Medals.has(p, m["id"]) else "[ ]", m["name"], Medals.progress(p, m)])
	ship.free()
	truck.free()
	crew.pilots.append(old)
	var h := get_parent()
	if Game.args.has("screenshot") and h.has_method("_open_crew"):
		if not Game.args.has("medalreport"):
			h._open_crew()
		if Game.args.has("medalreport"):   # rapor görünümü (ağaç duraklatılmaz ki ekran görüntüsü alınsın)
			FlightReport.open(h, "UÇUŞ RAPORU", PackedStringArray(["Test Pilot +420 XP", "MADALYA: Gemi Avcısı — Bir düşman savaş gemisi batır.", "MADALYA: As Pilot — 5 düşman uçağı düşür.", "TERFİ: Test Pilot Binbaşı oldu!"]), true)
			await get_tree().process_frame
			get_tree().paused = false
		if Game.args.has("medaldetail"):
			await get_tree().process_frame
			MedalView.open_detail(h._crew_list, p)
	else:
		get_tree().quit()
