class_name Carrier
extends Warship
## Uçak gemisi (270 m): düz uçuş güvertesi, açılı iniş pisti, sancakta ada üst yapısı, güvertede
## park etmiş avcılar. Arama radarı 45 km, kısa menzilli SAM (9 km, 8 füze), üç CIWS.
## Oyuncuyu radarla LAUNCH_RANGE içinde görürse ya da alarm alırsa baş katapulttan avcı kaldırır:
## her LAUNCH_EVERY saniyede bir, havada en çok `max_airborne`, toplam `air_wing` uçak.
## Batırmak zor (çok sayıda gemi savar füzesi / ağır bomba) — ödülü de büyük.

signal launched(v: Vessel)

const LAUNCH_RANGE := 28000.0
const LAUNCH_EVERY := 35.0
const DECK_Y := 13.2
const CRAFTS := ["res://crafts/kartal_1.json", "res://crafts/sahin_b.json"]

var air_wing := 6
var max_airborne := 2
var fighter_skill := 0.55
var scrambling := false
var flights: Array[Vessel] = []
var _parked: Array[Node3D] = []
var _launch_t := 4.0


static func create_carrier(title := "Düşman uçak gemisi") -> Carrier:
	var t := Carrier.new()
	t.unit_name = title
	t.hp = 12000.0
	t.missiles = 8
	t.radar_range = 45000.0
	t.sam_range = 9000.0
	t.reload = 6.0
	t.speed = 8.0
	t.turn_rate = 0.035
	t.sink_time = 45.0
	t.sink_depth = 32.0
	t.armor = 0.08
	t.tag = "CV"
	t._collision(Vector3(40.0, 26.0, 272.0), Vector3(0, 6.0, -2.0))
	var grey := Color(0.44, 0.47, 0.5)
	var deck := Color(0.24, 0.25, 0.26)
	# gövde: dar alt gövde + geniş uçuş güvertesi, sivri baş
	t._hull = _mesh(t, Vector3(30.0, 16.0, 226.0), Vector3(0, 4.0, 4.0), grey)
	var bow := _mesh(t, Vector3(21.2, 16.0, 21.2), Vector3(0, 4.0, -109.0), grey)
	bow.rotation_degrees = Vector3(0, 45, 0)
	_mesh(t, Vector3(30.4, 0.6, 236.0), Vector3(0, -2.6, 0.0), Color(0.45, 0.12, 0.1))   # su hattı
	_mesh(t, Vector3(38.0, 1.4, 252.0), Vector3(0, DECK_Y - 0.7, -4.0), deck)            # uçuş güvertesi
	var bow_deck := _mesh(t, Vector3(26.9, 1.4, 26.9), Vector3(0, DECK_Y - 0.7, -128.0), deck)
	bow_deck.rotation_degrees = Vector3(0, 45, 0)
	bow_deck.scale = Vector3(1.0, 1.0, 0.55)
	# açılı iniş pisti (iskele çıkıntısı) ve güverte çizgileri
	var angled := _mesh(t, Vector3(14.0, 1.4, 120.0), Vector3(-20.0, DECK_Y - 0.7, 40.0), deck)
	angled.rotation_degrees = Vector3(0, -9, 0)
	var line_c := Color(0.85, 0.85, 0.8)
	var al := _mesh(t, Vector3(0.6, 0.1, 200.0), Vector3(-9.0, DECK_Y + 0.05, 30.0), line_c)
	al.rotation_degrees = Vector3(0, -9, 0)
	for side in [-1.0, 1.0]:
		var ed := _mesh(t, Vector3(0.4, 0.1, 190.0), Vector3(-9.0 + side * 11.0, DECK_Y + 0.05, 30.0), line_c)
		ed.rotation_degrees = Vector3(0, -9, 0)
	for k in 10:
		_mesh(t, Vector3(0.5, 0.1, 6.0), Vector3(-3.0, DECK_Y + 0.05, -125.0 + k * 11.0), Color(0.95, 0.8, 0.2))  # katapult hattı
	_mesh(t, Vector3(8.0, 0.1, 0.6), Vector3(-3.0, DECK_Y + 0.05, -128.0), Color(0.95, 0.8, 0.2))
	# ada: sancakta, iki kat + köprü camı + baca + direk/radar
	_mesh(t, Vector3(9.0, 12.0, 34.0), Vector3(15.0, DECK_Y + 6.0, 22.0), grey.lightened(0.06))
	_mesh(t, Vector3(8.0, 5.0, 20.0), Vector3(15.0, DECK_Y + 14.5, 18.0), grey.lightened(0.1))
	_mesh(t, Vector3(8.2, 1.4, 1.0), Vector3(15.0, DECK_Y + 15.5, 7.8), Color(0.12, 0.15, 0.18))
	_mesh(t, Vector3(6.0, 6.0, 8.0), Vector3(15.0, DECK_Y + 15.0, 32.0), Color(0.24, 0.25, 0.26))   # baca
	t._add_mast(Vector3(15.0, DECK_Y + 17.0, 20.0), 9.0, 7.5)
	# park etmiş avcılar (sancak kıç ve baş tarafı)
	for i in 6:
		var p := _deck_plane()
		var aft := i < 4
		p.position = Vector3(10.0 if aft else 12.0, DECK_Y, 70.0 + i * 16.0 if aft else -70.0 - (i - 4) * 18.0)
		p.rotation_degrees = Vector3(0, 35.0 if aft else -40.0, 0)
		t.add_child(p)
		t._parked.append(p)
	# savunma: kısa menzilli SAM (kıç sancak sponsonu) + üç CIWS
	t._add_launcher(Vector3(17.0, DECK_Y + 0.1, 112.0), 8)
	t._add_ciws(Vector3(17.5, DECK_Y + 0.5, -98.0))
	t._add_ciws(Vector3(-18.5, DECK_Y + 0.5, 100.0))
	t._add_ciws(Vector3(15.0, DECK_Y + 17.2, 30.0))
	return t


## Güvertede park etmiş avcı (yalnız görsel).
static func _deck_plane() -> Node3D:
	var n := Node3D.new()
	var paint := Color(0.36, 0.4, 0.44)
	_mesh(n, Vector3(1.7, 1.6, 15.0), Vector3(0, 2.0, 0), paint)                      # gövde
	_mesh(n, Vector3(0.9, 0.7, 2.4), Vector3(0, 3.0, -4.0), Color(0.12, 0.15, 0.2))   # kanopi
	_mesh(n, Vector3(5.0, 0.25, 4.0), Vector3(0, 1.8, 1.0), paint.darkened(0.1))     # katlı kanat
	for side in [-1.0, 1.0]:
		var w := _mesh(n, Vector3(0.25, 3.0, 3.0), Vector3(side * 2.6, 3.2, 1.0), paint.darkened(0.1))
		w.rotation_degrees = Vector3(0, 0, side * -12.0)
		var fin := _mesh(n, Vector3(0.2, 2.6, 2.2), Vector3(side * 0.9, 3.8, 6.0), paint.darkened(0.15))
		fin.rotation_degrees = Vector3(-15, 0, side * 12.0)
	_mesh(n, Vector3(5.0, 0.2, 2.0), Vector3(0, 2.2, 6.4), paint.darkened(0.1))     # yatay kuyruk
	for p in [Vector3(0, 0.6, -5.0), Vector3(-1.4, 0.6, 1.5), Vector3(1.4, 0.6, 1.5)]:
		_mesh(n, Vector3(0.3, 1.2, 0.5), p, Color(0.1, 0.1, 0.1))
	return n


func airborne() -> int:
	var n := 0
	for f in flights:
		if is_instance_valid(f) and not f.parts.is_empty() and f.has_pilot():
			n += 1
	return n


func _weapons(delta: float, v: Vessel, seen: bool, dist: float) -> void:
	_launch_t -= delta
	if not scrambling and ((seen and dist < LAUNCH_RANGE) or alerted()):
		scrambling = true
		_launch_t = minf(_launch_t, 6.0)
		if v:
			v.system_message.emit("DÜŞMAN UÇAK GEMİSİ AVCI KALDIRIYOR!")
	if scrambling and _launch_t <= 0.0 and air_wing > 0 and airborne() < max_airborne:
		_launch_t = LAUNCH_EVERY
		_launch()


## Baş katapulttan avcı kaldır: güverte ucunun önünde, tırmanış hızında, gemi yönünde.
func _launch() -> void:
	air_wing -= 1
	if not _parked.is_empty():
		_parked.pop_back().visible = false
	var up := Planet.up_at(global_position)
	var fwd := -global_basis.z
	var pos := to_global(Vector3(-3.0, DECK_Y + 45.0, -170.0))
	var craft := VesselBuilder.load_craft(CRAFTS[flights.size() % CRAFTS.size()])
	craft["paint"] = {"scheme": "gece", "number": "G-%d" % (10 + randi() % 80)}
	var e := VesselBuilder.build(craft)
	e.name = "CarrierFighter%d" % flights.size()
	e.craft_name = "Gemi avcısı %d" % (flights.size() + 1)
	e.team = team
	var b := Basis.looking_at(fwd, up)
	e.transform = Transform3D(b, pos)
	e.linear_velocity = fwd * 150.0 + up * 8.0
	get_parent().add_child(e)
	e.global_transform = Transform3D(b, pos)
	e.set_gear_instant(false)
	e.set_hot()
	e.lights_on = true
	var ai := AIPilot.new()
	ai.vessel = e
	ai.skill = fighter_skill
	ai.aggressive = true
	ai.altitude = 1800.0
	ai.speed = 215.0
	ai.leg_time = 60.0
	e.add_child(ai)
	flights.append(e)
	Sfx.play_at("missile_launch.ogg", pos, 4.0, 0.5, 6000.0)
	launched.emit(e)
	if Game.args.has("navaltest"):
		print("NAVAL: %s avcı kaldırdı (%s), havada %d, kalan %d" % [unit_name, e.craft_name, airborne(), air_wing])


func _on_destroyed() -> void:
	super._on_destroyed()
	air_wing = 0
	for p in _parked:
		p.visible = false
	# ikinci duman sütunu: ada
	var smoke := Effects.smoke_column()
	add_child(smoke)
	smoke.position = Vector3(15.0, DECK_Y + 10.0, 20.0)
