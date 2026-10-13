class_name GenMission
extends RefCounted
## Üretilmiş görevin (MissionGen kartı, Game.mission_card) uçuştaki kurulumu ve takibi.
## MissionManager "gen" görevinde setup() ve check() çağırır; birim yerleştirme, düşman uçağı,
## tanker, sonuç gibi işler MissionManager yardımcılarıyla yapılır.
## Kartın tohumu her şeyi belirler: brifingde gösterilen birim konumları uçuşta da aynıdır.
## Görev içi olaylar (card.events): hedef yer değiştirir, pusu, düşen dost pilot, tanker iptali.

const DEFEND_RADIUS := 3000.0
const BASE_RADIUS := 3000.0

var mm: MissionManager
var card := {}
var tpl := ""
var notes := []
var _air_t := 0.0
var _airborne := false
var _start_xz := Vector2.INF
var _pending: Array = []          # henüz doğmamış avcı grupları (kart: fighters)
var _events: Array = []           # [{…olay, done}]
var _alerted := false
var _objs: Array[GroundTarget] = []
var _hp0 := 0.0
var _bombers: Array[Vessel] = []
var _transport: Vessel
var _heli: Helicopter
var _site_root: Node3D
## Bölge işaretinin anlık dünya konumu (kayan orijin yüzünden saklanmaz, her seferinde okunur)
var _site_w: Vector3:
	get:
		return _site_root.global_position if is_instance_valid(_site_root) else Vector3.ZERO
var _points: Array = []
var _point_i := 0
var _inside := 0
var _phase := 0
var _wait := 0.0
var _rtb := false
var _side := {}                   # düşen pilot olayı: {marker, heli, hunters, idx, state}


func _init(m: MissionManager) -> void:
	mm = m


## Uçuşta kullanılacak kart: Game.mission_card; test argümanıyla (--genflighttest) boşsa üretilir.
static func card_now() -> Dictionary:
	var pc: Dictionary = Game.pending_op.get("card", {})
	if not pc.is_empty():
		return pc   # hangarda hazırlanan harekât (brifing, uçuştan önce)
	if Game.mission_card.is_empty() and (Game.args.has("genflighttest") or Game.args.has("gentemplate")):
		var tpl := String(Game.args.get("gentemplate", "kopru"))
		var rid := String(Game.args.get("genregion", ""))
		if rid == "":
			for r: Dictionary in Front.REGIONS:
				if tpl in MissionGen.POOLS.get(r["id"], []):
					rid = r["id"]
					break
		if Game.args.has("genday"):
			Career.day = int(Game.args["genday"])
		Game.mission_card = MissionGen.make_card({"mission": "gen", "region": rid, "template": tpl, "slot": int(Game.args.get("genslot", "0"))})
		if Game.args.has("genrunway"):
			Game.mission_card["runway_m"] = float(Game.args["genrunway"])
		Game.mission_region = rid
	return Game.mission_card


# ------------------------------------------------------------------ kurulum

func setup() -> void:
	card = card_now()
	tpl = String(card.get("template", ""))
	if not Game.args.has("weather"):
		Weather.set_dynamic(false)
		Weather.set_preset(int(card.get("weather", 0)), true)
	if not Game.args.has("hour"):
		Weather.clock = float(card.get("hour", 12.0))
	mm._clear_static_targets()
	_short_runway()
	if Game.args.has("genair"):
		_test_air_start()
	for u: Dictionary in card.get("units", []):
		_spawn_unit(u)
	for e: Dictionary in card.get("events", []):
		var ev: Dictionary = e.duplicate()
		ev["done"] = false
		_events.append(ev)
	for f: Dictionary in card.get("fighters", []):
		_pending.append(f.duplicate())
	if card.get("tanker", false):
		var tx: Vector2 = card["tanker_xz"]
		mm._spawn_tanker(Vector3(tx.x, 3200.0, tx.y))
	_spawn_due("start")
	match tpl:
		"kopru":
			mm.objectives = [mm._obj("%s (hasar %%0)" % String(card["units"][0].get("name", "Hedef"))), mm._obj("Hayatta kal")]
		"sam":
			mm.objectives = [mm._obj("SAM sistemleri (0/%d)" % _objs.size()), mm._obj("Hayatta kal")]
		"gemi":
			mm.objectives = [mm._obj("Gemiler (0/%d)" % _objs.size()), mm._obj("Hayatta kal")]
		"derin":
			mm.objectives = [mm._obj("Mühimmat depoları (0/%d)" % _objs.size()), mm._obj("Üsse dön (3 km)")]
		"konvoy":
			mm.objectives = [mm._obj("Konvoy (0/%d)" % _objs.size()), mm._obj("Hedefe varmalarına izin verme")]
		"onleme":
			mm.objectives = [mm._obj("Bombardımanlar (0/%d)" % int(card.get("bombers", 2))), mm._obj("Hedefi koru (3 km)")]
		"eskort":
			_spawn_transport()
			mm.objectives = [mm._obj("Herkül'ü koru"), mm._obj("Varış noktası")]
		"kurtarma":
			var s: Vector2 = card["site"]
			_site_root = _marker(s, true, 0.0)
			mm.objectives = [mm._obj("Düşen pilotun yanına git"), mm._obj("Arama timini durdur (0/%d)" % _objs.size()), mm._obj("Helikopter pilotu alsın")]
		"yuk":
			var s: Vector2 = card["site"]
			_site_root = _marker(s, false, float(card.get("zone_m", 150.0)))
			mm.objectives = [mm._obj("Sandıklar bölgede (0/%d)" % int(card.get("crates", 3)))]
			if mm.main.vessel.cargo_left() < int(card.get("crates", 3)):
				mm._pending_fail = "Uçakta %d sandık kargo yok (kargo bölmesi tak)" % int(card.get("crates", 3))
			else:
				mm.main.vessel.selected_weapon = Vessel.WEAPON_CARGO
		"kesif":
			_points = (card.get("points", []) as Array).duplicate()
			mm.objectives = []
			for i in _points.size():
				mm.objectives.append(mm._obj("Keşif noktası %s (<%d m AGL)" % [["A", "B", "C", "D"][i], int(card.get("agl_max", 600.0))]))
			mm.objectives.append(mm._obj("Fotoğrafları üsse getir"))
	if Game.args.has("genflighttest"):
		print("GENFLIGHT setup %s %s  objs=%d  units=%d  fighters=%d  events=%s  enemies=%d" % [card.get("id", ""), tpl, _objs.size(),
			(card.get("units", []) as Array).size(), _pending.size(), ",".join(_events.map(func(e: Dictionary) -> String: return e["kind"])), mm._enemies.size()])


func _bomber_total() -> int:
	return _bombers.size()


## Kısa pist: uçak kalkış ucundan ileri alınır, kuzey ucuna yalnız runway_m kalır.
func _short_runway() -> void:
	var v: Vessel = mm.main.vessel
	var rw := float(card.get("runway_m", MissionGen.FULL_RUNWAY))
	if not is_instance_valid(v) or v.radar_altitude() > 10.0:
		return
	if rw < MissionGen.FULL_RUNWAY - 50.0:
		var z := MissionGen.RUNWAY_END_Z + rw
		var cur := v.global_position
		var pos := MissionManager.world_point(0.0, z, Planet.altitude(cur))
		v.global_transform = Transform3D(Planet.local_basis(pos), pos)
		v.linear_velocity = Vector3.ZERO
		mm.main.terrain.collision.rebuild_now(mm.main.terrain.to_local(pos))
		mm._message("Kısa pist: %d m kullanılabilir (krater onarımı)" % int(rw), 6.0)
	_start_xz = GroundTarget.surface_xz(v.global_position)


## Test: hedefe 9 km kala, 1500 m'de havada başla.
func _test_air_start() -> void:
	var t: Vector2 = card["target_xz"]
	var dir := t.normalized() if t.length() > 1.0 else Vector2(0, -1)
	var p := t - dir * 9000.0
	if tpl == "onleme":
		p = (card["defend_xz"] as Vector2).lerp(t, 0.3)
	elif tpl == "eskort":
		p = Vector2(0, 2500)
	var alt := MissionManager.ground_height(p.x, p.y) + (1500.0 if tpl != "kesif" else 400.0)
	var pos := MissionManager.world_point(p.x, p.y, alt)
	var frame := Planet.local_basis(pos)
	var hdg := atan2(dir.x, -dir.y)
	var basis := Basis(frame.y, -hdg) * frame
	var v: Vessel = mm.main.vessel
	v.global_transform = Transform3D(basis, pos)
	v.linear_velocity = -basis.z * 180.0
	v.set_gear_instant(false)
	v.set_hot()
	_start_xz = Vector2.INF


func _spawn_unit(u: Dictionary) -> void:
	var xz: Vector2 = u["xz"]
	var obj := bool(u.get("obj", false))
	match String(u["type"]):
		"sam":
			_place(SamSite.create_sam(Vector3.ZERO, 0.0), xz, obj)
		"lrsam":
			var lr := SamSite.create_long_range()
			_place(lr[0], xz, obj)
			_place(lr[1], xz + Vector2(70, 30), obj)
			_place(lr[2], xz + Vector2(-55, 40), obj)
		"aaa":
			_place(AaaGun.create_aaa(Vector3.ZERO, 0.0), xz, obj)
		"manpads":
			_place(Manpads.create_team(), xz, obj)
		"radar":
			var st := RadarStation.create_station()
			_place(st, xz, obj)
			st.spotted.connect(func(_v: Vessel) -> void: _on_alert())
		"depot":
			var d := mm._depot(String(u.get("name", "Mühimmat deposu")), float(u.get("hp", 1500.0)))
			_place(d, xz, obj)
		"bridge":
			_place_bridge(u)
		"ship":
			var sh := Warship.create_ship("Düşman korveti")
			sh.heading = float(u.get("heading", 0.0))
			_place(sh, xz, obj)
		"frigate":
			var fr := Frigate.create_frigate()
			fr.heading = float(u.get("heading", 0.0))
			_place(fr, xz, obj)
		"convoy":
			var road: Array[Vector2] = []
			for p: Vector2 in card.get("path", []):
				road.append(p)
			var n := int(u.get("n", 5))
			var arm := int(u.get("armored", 2))
			var esc := int(u.get("escort", 1))
			for i in n:
				var t := ConvoyTruck.create_truck(road, 40.0 + (n - 1 - i) * 34.0, i < arm, i < esc)
				_place(t, Vector2.ZERO, true)
		"hunters":
			var road2: Array[Vector2] = [xz, u["to"]]
			for i in int(u.get("n", 2)):
				var t := ConvoyTruck.create_truck(road2, 10.0 + i * 30.0, i % 2 == 0, true)
				t.speed = 9.0
				_place(t, Vector2.ZERO, obj)


func _place(u: GroundTarget, xz: Vector2, obj: bool) -> void:
	u.objective = obj
	mm._add_unit(u, xz)
	if obj:
		u.set_meta("gen_obj", true)
		_objs.append(u)
		_hp0 += u.hp
	u.alerted_cb = _on_alert


## Köprü hedefi: gerçek köprü güvertesini kaplayan beton kutu (canı istenen patlayıcıya göre).
func _place_bridge(u: Dictionary) -> void:
	var xz: Vector2 = u["xz"]
	var t := RadarStation.make_truck(String(u.get("name", "Köprü")), float(u.get("hp", 6000.0)))
	for c in t.get_children():
		c.queue_free()
	var length := float(u.get("width", 40.0)) + 40.0
	t._hull = GroundTarget._mesh(t, Vector3(11.6, 1.6, length), Vector3(0, -0.5, 0), Color(0.6, 0.58, 0.54))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 3.0, length)
	cs.shape = box
	t.add_child(cs)
	t.objective = true
	t.set_meta("gen_obj", true)
	mm.main.world.add_child(t)
	var pos := MissionManager.world_point(xz.x, xz.y, float(u.get("level", 0.0)) + 5.0)
	var frame := Planet.local_basis(pos)
	var dir: Vector2 = u.get("dir", Vector2(0, -1))
	t.global_transform = Transform3D(Basis(frame.y, -atan2(dir.x, -dir.y)) * frame, pos)
	t.alerted_cb = _on_alert
	_objs.append(t)
	_hp0 += t.hp


## Bölge işareti: duman, ışık; kurtarmada düşen pilot figürü, yük bırakmada halka (radius).
func _marker(xz: Vector2, person: bool, radius: float) -> Node3D:
	var h := MissionManager.ground_height(xz.x, xz.y)
	var pos := MissionManager.world_point(xz.x, xz.y, h)
	var root := Node3D.new()
	mm.main.world.add_child(root)
	root.global_transform = Transform3D(Planet.local_basis(pos), pos)
	root.add_child(Effects.smoke_column())
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.omni_range = 60.0
	light.light_energy = 4.0
	light.position = Vector3(0, 3, 0)
	root.add_child(light)
	if person:
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.8
		body.mesh = cap
		body.name = "Pilot"
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.5, 0.1)
		body.material_override = m
		body.position = Vector3(4, 0.9, 6)
		root.add_child(body)
	if radius > 0.0:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = radius - 3.0
		t.outer_radius = radius + 3.0
		t.rings = 96
		ring.mesh = t
		var m2 := StandardMaterial3D.new()
		m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m2.albedo_color = Color(1.0, 0.5, 0.1)
		ring.material_override = m2
		ring.position = Vector3(0, 2.0, 0)
		root.add_child(ring)
	return root


## Dost uçak (nakliye): görev boyunca varış noktasına düz uçar.
func _spawn_friendly(path: String, xz: Vector2, alt: float, to: Vector2, speed: float, title: String) -> Vessel:
	var pos := MissionManager.world_point(xz.x, xz.y, alt)
	var frame := Planet.local_basis(pos)
	var d := to - xz
	var basis := Basis(frame.y, -atan2(d.x, -d.y)) * frame
	var craft := VesselBuilder.load_craft(path)
	craft["paint"] = {"scheme": "kırmızı-beyaz", "number": "N-07"}
	var t := VesselBuilder.build(craft)
	t.name = "Transport"
	t.craft_name = title
	t.team = mm.main.vessel.team
	t.transform = Transform3D(basis, pos)
	t.linear_velocity = -basis.z * speed
	mm.main.world.add_child(t)
	t.set_gear_instant(false)
	t.set_hot()
	t.lights_on = true
	var ai := AIPilot.new()
	ai.vessel = t
	ai.aggressive = false
	ai.altitude = alt
	ai.speed = speed
	ai.leg_time = 99999.0
	t.add_child(ai)
	return t


func _spawn_transport() -> void:
	var v: Vessel = mm.main.vessel
	var p := GroundTarget.surface_xz(v.global_position) + Vector2(260, 120)
	_transport = _spawn_friendly(MissionGen.HERKUL, p, float(card.get("escort_alt", 2000.0)), card["target_xz"], 120.0, "Herkül (nakliye)")


static func _hd(a: Vector3, b: Vector3) -> float:
	var d := a - b
	var up := Planet.up_at(b)
	return (d - up * d.dot(up)).length()


static func _heading(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return rad_to_deg(atan2(d.x, -d.y))


## Avcı / bombardıman grubunu doğur.
func _spawn_group(f: Dictionary) -> void:
	var role := String(f.get("role", "fighter"))
	var xz: Vector2 = f["xz"]
	var alt := float(f.get("alt", 3000.0))
	var to: Vector2 = f.get("to", _player_xz())
	var hdg := _heading(xz, to)
	var n := int(f.get("n", 1))
	var side := Vector2.from_angle(deg_to_rad(hdg))   # yana dizilim
	var diff := float(card.get("diff", 0.3))
	var lead: Vessel = null
	for i in n:
		var p := xz + side * (i * 450.0 - (n - 1) * 225.0) + Vector2(0, i * 120.0)
		if role == "bomber":
			var e := mm._spawn_enemy(Vector3(p.x, alt, p.y), hdg, 0.5, false, "Bombardıman %d" % (_bombers.size() + 1), MissionManager.SAHIN_B)
			var spd := float(f.get("speed", 200.0))
			for c in e.get_children():
				if c is AIPilot:
					c.leg_time = 99999.0
					c.speed = spd
					c.altitude = alt
			e.linear_velocity = e.linear_velocity.normalized() * spd
			_bombers.append(e)
		else:
			var craft := MissionGen.ECM_FIGHTER if card.get("enemy_ecm", false) else ""
			var skill := clampf(0.4 + diff * 0.3 + (0.15 if card.get("enemy_defensive", false) else 0.0), 0.2, 0.9)
			var e := mm._spawn_enemy(Vector3(p.x, alt, p.y), hdg, skill, true, "Düşman avcı" + (" (ECM)" if craft != "" else ""), craft)
			if role == "escort":
				for c in e.get_children():
					if c is AIPilot:
						c.speed = float(f.get("speed", 220.0))
			if card.get("enemy_defensive", false) and lead != null:
				AIPilot.pair(lead, e)
				lead = null
			else:
				lead = e


func _spawn_due(trigger: String) -> void:
	for f: Dictionary in _pending.duplicate():
		if String(f.get("trigger", "start")) == trigger:
			_pending.erase(f)
			_spawn_group(f)


func _on_alert() -> void:
	if _alerted or mm.state != "running":
		return
	_alerted = true
	var n := 0
	for f: Dictionary in _pending:
		if f.get("trigger", "") == "alert":
			n += int(f.get("n", 1))
	if n > 0:
		_radio("%s, düşman alarm verdi: %d avcı kalkıyor!" % [_cs(), n], "Bandits scrambling.", "AWACS")
		_spawn_due("alert")


func _player_xz() -> Vector2:
	var v: Vessel = mm.main.vessel
	return GroundTarget.surface_xz(v.com_global()) if is_instance_valid(v) else Vector2.ZERO


func _cs() -> String:
	return mm.main.radio.callsign() if mm.main.radio else "Kartal"


func _radio(tr: String, en: String, sender := "") -> void:
	if mm.main.radio:
		mm.main.radio.say(tr, en, sender)
	mm._message(tr, 5.0)


# ------------------------------------------------------------------ takip

func check(v: Vessel, delta: float) -> void:
	var agl := v.radar_altitude()
	if not _airborne and agl > 8.0 and v.airspeed() > 40.0:
		_airborne = true
		if _start_xz != Vector2.INF:
			var roll := _start_xz.distance_to(GroundTarget.surface_xz(v.global_position))
			notes.append("Kalkış koşusu ~%d m (kullanılabilir pist %d m)" % [int(roll), int(card.get("runway_m", 0.0))])
	if not _airborne and _start_xz != Vector2.INF and v.ground_speed() > 15.0:
		var z := GroundTarget.surface_xz(v.global_position).y
		if z < MissionGen.RUNWAY_END_Z - 40.0:
			notes.append("Pist yetmedi: uçak %d m'lik pistte havalanamadı" % int(card.get("runway_m", 0.0)))
			mm._finish(false, "Pist yetmedi (%d m)" % int(card.get("runway_m", 0.0)))
			return
	if _airborne:
		_air_t += delta
	if Game.args.has("genflighttest"):
		_test_hooks(v)
		if mm.state != "running":
			return
	_triggers(v)
	_side_event(v, delta)
	match tpl:
		"kopru":
			_check_kill(v, "HEDEF", true)
		"sam":
			_check_kill(v, "SAM", false, "SAM sistemleri")
		"gemi":
			_check_kill(v, "GEMİ", false, "Gemiler")
		"derin":
			_check_kill(v, "DEPO", false, "Mühimmat depoları")
		"konvoy":
			_check_convoy(v)
		"onleme":
			_check_intercept(v)
		"eskort":
			_check_escort(v)
		"kurtarma":
			_check_rescue(v, delta)
		"yuk":
			_check_drop(v)
		"kesif":
			_check_recon(v)


## Test kancaları: --genevents (olaylar 5 sn arayla), --genkill=S (S. saniyede hedefler yok olur),
## --genmax=S (süre sınırı).
func _test_hooks(v: Vessel) -> void:
	if Game.args.has("genevents"):
		for i in _events.size():
			_events[i]["trigger"] = "time"
			_events[i]["v"] = 4.0 + i * 6.0
		for f: Dictionary in _pending:
			if f.get("trigger", "") in ["clock", "time"]:
				f["v"] = 3.0
		_air_t = maxf(_air_t, mm.elapsed)
	if Game.args.has("genkill") and mm.elapsed > float(Game.args["genkill"]) and not has_meta("killed"):
		set_meta("killed", true)
		print("GENFLIGHT kill t=%.0f objs=%d bombers=%d enemies=%d events=%s" % [mm.elapsed, _objs.size(), _bombers.size(), mm._enemies.size(), _events.map(func(e: Dictionary) -> String: return "%s:%s" % [e["kind"], e["done"]])])
		for u in _objs:
			if is_instance_valid(u) and not u.destroyed:
				u.take_damage(1.0e7)
		for e in _bombers:
			if is_instance_valid(e):
				for p in e.parts.duplicate():
					e.damage_part(p, 1.0e7)
		if tpl == "yuk" or tpl == "kesif" or tpl == "eskort":
			var t: Vector2 = card["target_xz"]
			var p := MissionManager.world_point(t.x, t.y, MissionManager.ground_height(t.x, t.y) + 200.0)
			if tpl == "eskort" and is_instance_valid(_transport):
				_transport.global_position = p + Vector3(0, 1500, 0)
			else:
				v.global_position = p
		if card.get("rtb", false) or tpl == "kesif":
			v.global_position = MissionManager.world_point(500, 1500, 600.0)
	if int(mm.elapsed * 60.0) % 1200 == 0 and tpl == "kurtarma":
		print("GENFLIGHT t=%.0f phase=%d heli=%s d=%.0f pdist=%.0f" % [mm.elapsed, _phase, _heli.state if is_instance_valid(_heli) else "-", _heli.global_position.distance_to(_site_w) if is_instance_valid(_heli) else -1.0, mm._horiz_dist(v, _site_w)])
	if Game.args.has("genmax") and mm.elapsed > float(Game.args["genmax"]):
		mm._finish(false, "test süresi doldu")

func _triggers(v: Vessel) -> void:
	var t: Vector2 = card["target_xz"]
	var dist := _player_xz().distance_to(t)
	for f: Dictionary in _pending.duplicate():
		var tr := String(f.get("trigger", ""))
		if (tr == "clock" and mm.elapsed >= float(f.get("v", 0.0))) or (tr == "time" and _airborne and _air_t >= float(f.get("v", 0.0))) or (tr == "near" and dist < float(f.get("v", 10.0)) * 1000.0):
			_pending.erase(f)
			_spawn_group(f)
			_radio("%s, radar temas: %d düşman avcı yaklaşıyor." % [_cs(), int(f.get("n", 1))], "Bandits inbound.", "AWACS")
	for e: Dictionary in _events:
		if e["done"]:
			continue
		var go := false
		match String(e.get("trigger", "time")):
			"time":
				go = _airborne and _air_t >= float(e.get("v", 120.0))
			"near":
				go = dist < float(e.get("v", 12.0)) * 1000.0
		if go:
			e["done"] = true
			_fire_event(e, v)


func _fire_event(e: Dictionary, v: Vessel) -> void:
	match String(e["kind"]):
		"relocate":
			_relocate(e["delta"])
		"ambush":
			var n := int(e.get("n", 3))
			var me := _player_xz()
			var from := me + MissionGen._enemy_dir(me) * 14000.0
			_spawn_group({"role": "fighter", "xz": MissionGen._in_world(from), "alt": maxf(v.altitude() + 600.0, 2500.0), "n": n, "to": me})
			_radio("%s, dikkat! %d düşman avcı %s yönünden geliyor, pusu!" % [_cs(), n, MissionGen._compass(from - me)], "Ambush, %d bandits!" % n, "AWACS")
			notes.append("Olay: pusu (%d avcı)" % n)
		"downed":
			_start_downed(e["xz"])
		"tanker_cancel":
			if is_instance_valid(mm._tanker):
				var p := mm.main.vessel.probe() as RefuelProbeModule
				if p and p.connected():
					e["done"] = false   # bağlıyken iptal etme, sonra tekrar dene
					return
				mm._tanker.queue_free()
				_radio("%s, Deve tankeri geri çağrıldı: dönüşte ikmal yok, yakıtını hesapla!" % _cs(), "Tanker recalled, no refuel.", "KARARGÂH")
				notes.append("Olay: tanker iptal edildi")


## Hedef yer değiştirdi: sağ kalan hedef birimleri (ya da sıradaki nokta / bırakma bölgesi) taşınır.
func _relocate(delta: Vector2) -> void:
	var t: Vector2 = card["target_xz"]
	var nt := t + delta
	if tpl == "kesif":
		if _point_i < _points.size():
			_points[_point_i] = (_points[_point_i] as Vector2) + delta
			nt = _points[_point_i]
	elif tpl == "yuk":
		nt = t + delta
		if is_instance_valid(_site_root):
			var h := MissionManager.ground_height(nt.x, nt.y)
			var pos := MissionManager.world_point(nt.x, nt.y, h)
			_site_root.global_transform = Transform3D(Planet.local_basis(pos), pos)
		card["site"] = nt
	else:
		for u in _objs:
			if not is_instance_valid(u) or u.destroyed:
				continue
			var xz := GroundTarget.surface_xz(u.global_position) + delta
			if MissionGen._h(xz) < 3.0:
				continue
			var pos := MissionManager.world_point(xz.x, xz.y, MissionManager.ground_height(xz.x, xz.y) + 0.5)
			u.global_transform = Transform3D(Planet.local_basis(pos), pos)
	card["target_xz"] = nt
	Game.mission_card["target_xz"] = nt
	var what: String = {"sam": "SAM bataryası", "derin": "depolar", "kesif": "keşif noktası", "yuk": "bırakma bölgesi"}.get(tpl, "hedef")
	_radio("%s, plan değişti: %s yer değiştirdi, %d km %s. Yeni konum işaretlendi." % [_cs(), what, int(delta.length() / 1000.0), MissionGen._compass(delta)],
		"Target relocated.", "KARARGÂH")
	notes.append("Olay: hedef yer değiştirdi (%d km)" % int(delta.length() / 1000.0))


## Düşen dost pilot (yan görev): helikopter gelene kadar arama timinden koru. Başarı primi.
func _start_downed(xz: Vector2) -> void:
	var marker := _marker_free(xz)
	var from := xz + MissionGen._enemy_dir(xz) * 3200.0
	var road: Array[Vector2] = [from, xz]
	var hunters := []
	for i in 2:
		var tr := ConvoyTruck.create_truck(road, 10.0 + i * 30.0, false, true)
		tr.speed = 8.0
		tr.objective = false
		mm._add_unit(tr, Vector2.ZERO)
		hunters.append(tr)
	var heli := Helicopter.create_heli("rescue")
	heli.home_xz = Vector2.ZERO
	heli.rescue_target = marker
	mm.main.world.add_child(heli)
	var hp := MissionManager.world_point(xz.x * 0.3, xz.y * 0.3, 300.0)
	var dir := (MissionManager.world_point(xz.x, xz.y, 300.0) - hp)
	if dir.length() > 9000.0:
		hp = MissionManager.world_point(xz.x, xz.y, 300.0) - dir.normalized() * 9000.0
	heli.global_transform = Transform3D(Planet.local_basis(hp), hp)
	mm.objectives.append(mm._obj("Ek: düşen pilotu koru (helikopter yolda)"))
	_side = {"marker": marker, "heli": heli, "hunters": hunters, "idx": mm.objectives.size() - 1, "state": "wait", "t": 0.0, "xz": xz}
	heli.landed_near_target.connect(func() -> void: _side["state"] = "landed")
	heli.departed.connect(func() -> void: _side["state"] = "saved")
	_radio("%s, Mayday! Bir dost pilot %d km %s düştü, düşman arama timi yolda. Helikopter gelene kadar üstünde kal." % [
		_cs(), int(_player_xz().distance_to(xz) / 1000.0), MissionGen._compass(xz - _player_xz())], "Friendly down, cover him.", "KARARGÂH")
	notes.append("Olay: düşen dost pilot")


func _marker_free(xz: Vector2) -> Node3D:
	return _marker(xz, true, 0.0)


func _side_event(_v: Vessel, delta: float) -> void:
	if _side.is_empty() or _side["state"] in ["done", "lost"]:
		return
	var idx := int(_side["idx"])
	var heli: Helicopter = _side["heli"]
	var site: Vector3 = (_side["marker"] as Node3D).global_position
	if not is_instance_valid(heli) or heli.destroyed:
		_side_end(false, "helikopter düştü")
		return
	for tr in _side["hunters"]:
		if is_instance_valid(tr) and not tr.destroyed and tr.global_position.distance_to(site) < 250.0:
			_side_end(false, "arama timi pilota ulaştı")
			return
	match String(_side["state"]):
		"landed":
			_side["t"] = float(_side["t"]) + delta
			if float(_side["t"]) > 6.0:
				var pm := (_side["marker"] as Node3D).get_node_or_null("Pilot")
				if pm:
					pm.visible = false
				heli.lift_off()
				_side["state"] = "lifting"
		"saved":
			_side_end(true, "")
	mm.objectives[idx]["text"] = "Ek: düşen pilotu koru (%s)" % {"wait": "helikopter yolda", "landed": "pilot biniyor", "lifting": "kalkıyor"}.get(_side["state"], "")


func _side_end(ok: bool, why: String) -> void:
	var idx := int(_side["idx"])
	_side["state"] = "done" if ok else "lost"
	if ok:
		mm.objectives[idx]["done"] = true
		mm.objectives[idx]["text"] = "Ek: dost pilot kurtarıldı (+1.500 ₺)"
		if not Game.test_flight and not Career.sandbox():
			Career.money += 1500
			Career.total_earned += 1500
		_radio("%s, pilot helikopterde! Teşekkürler, prim hesabına yazıldı." % _cs(), "Survivor aboard.", "KURTARMA 1")
		notes.append("Ek görev: dost pilot kurtarıldı")
	else:
		mm.objectives[idx]["text"] = "Ek: dost pilot kaybedildi (%s)" % why
		_radio("%s, dost pilotu kaybettik: %s." % [_cs(), why], "We lost him.", "KARARGÂH")
		notes.append("Ek görev başarısız: %s" % why)


## Hedef birimlerin tamamı: yok edilince (rtb ise üsse dönünce) görev biter.
func _check_kill(v: Vessel, nav: String, hp_mode: bool, label := "") -> void:
	if _rtb:
		_check_base(v, "Üsse dön (3 km)")
		return
	var total := 0
	var dead := 0
	var hp_left := 0.0
	var nearest: Variant = null
	var nd := INF
	for u in _objs:
		if not is_instance_valid(u):
			continue
		total += 1
		if u.destroyed:
			dead += 1
		else:
			hp_left += maxf(u.hp, 0.0)
			var d: float = u.global_position.distance_to(v.com_global())
			if d < nd:
				nd = d
				nearest = u.global_position
	mm.nav_point = nearest
	mm.nav_label = nav
	if hp_mode:
		var name := String(card["units"][0].get("name", "Hedef"))
		mm.objectives[0]["text"] = "%s (hasar %%%d)" % [name, int((1.0 - hp_left / maxf(_hp0, 1.0)) * 100.0)]
	else:
		mm.objectives[0]["text"] = "%s (%d/%d)" % [label, dead, total]
	if total > 0 and dead >= total:
		mm.objectives[0]["done"] = true
		if card.get("rtb", false):
			_rtb = true
			_radio("%s, hedefler yok edildi. Üsse dön." % _cs(), "Targets destroyed, RTB.", "KARARGÂH")
		else:
			mm.objectives[1]["done"] = true
			mm._finish(true, "")


func _check_base(v: Vessel, text: String) -> void:
	mm.nav_point = MissionManager.world_point(0, 600, 300.0)
	mm.nav_label = "ANA ÜS"
	var i := mm.objectives.size() - 1
	mm.objectives[i]["text"] = text
	if mm._near_base(v, BASE_RADIUS):
		mm.objectives[i]["done"] = true
		mm._finish(true, "")


func _check_convoy(v: Vessel) -> void:
	var goal: Vector2 = card.get("goal_xz", Vector2.ZERO)
	var gw := MissionManager.world_point(goal.x, goal.y, 0.0)
	for u in _objs:
		if is_instance_valid(u) and not u.destroyed and _hd(u.global_position, gw) < 400.0:
			mm._finish(false, "Konvoy hedefine ulaştı")
			return
	var total := 0
	var dead := 0
	var nearest: Variant = null
	var nd := INF
	for u in _objs:
		if not is_instance_valid(u):
			continue
		total += 1
		if u.destroyed:
			dead += 1
		elif u.global_position.distance_to(v.com_global()) < nd:
			nd = u.global_position.distance_to(v.com_global())
			nearest = u.global_position
	mm.objectives[0]["text"] = "Konvoy (%d/%d)" % [dead, total]
	mm.nav_point = nearest
	mm.nav_label = "KONVOY"
	if total > 0 and dead >= total:
		mm.objectives[0]["done"] = true
		mm.objectives[1]["done"] = true
		mm._finish(true, "")


func _check_intercept(_v: Vessel) -> void:
	if _bombers.is_empty():
		var s: Vector2 = card["target_xz"]
		mm.nav_point = MissionManager.world_point(s.x, s.y, float(card.get("target_alt_m", 5000.0)))
		mm.nav_label = "BOMBARDIMANLAR %d sn sonra kalkıyor" % maxi(int(float(card.get("launch_s", 0.0)) - mm.elapsed), 0)
		return
	var defend: Vector2 = card.get("defend_xz", Vector2.ZERO)
	var dw := MissionManager.world_point(defend.x, defend.y, 0.0)
	var dead := 0
	var best: Vessel = null
	var bd := INF
	for e in _bombers:
		if not is_instance_valid(e) or mm._enemy_dead(e):
			dead += 1
			continue
		var d := mm._horiz_dist(e, dw)
		if d < DEFEND_RADIUS:
			mm._finish(false, "Bombardıman hedefe ulaştı")
			return
		if d < bd:
			bd = d
			best = e
	mm.objectives[0]["text"] = "Bombardımanlar (%d/%d)" % [dead, _bombers.size()]
	mm.nav_point = best.com_global() if best else null
	mm.nav_label = "BOMBARDIMAN  %.0f km hedefe" % (bd / 1000.0) if best else ""
	if not _bombers.is_empty() and dead >= _bombers.size():
		mm.objectives[0]["done"] = true
		mm.objectives[1]["done"] = true
		mm._finish(true, "")


func _check_escort(_v: Vessel) -> void:
	if not is_instance_valid(_transport) or mm._enemy_dead(_transport):
		mm._finish(false, "Nakliye uçağı düşürüldü")
		return
	var dest: Vector2 = card["target_xz"]
	var dw := MissionManager.world_point(dest.x, dest.y, 0.0)
	var d := mm._horiz_dist(_transport, dw)
	mm.objectives[1]["text"] = "Varış noktası (%.1f km)" % (d / 1000.0)
	mm.nav_point = _transport.com_global()
	mm.nav_label = "HERKÜL"
	if d < 2500.0:
		mm.objectives[0]["done"] = true
		mm.objectives[1]["done"] = true
		mm._finish(true, "Nakliye vardı")


func _check_rescue(v: Vessel, delta: float) -> void:
	var dead := 0
	for u in _objs:
		if not is_instance_valid(u) or u.destroyed:
			dead += 1
		elif u.global_position.distance_to(_site_w) < 250.0:
			mm._finish(false, "Arama timi pilota ulaştı")
			return
	mm.objectives[1]["text"] = "Arama timini durdur (%d/%d)" % [dead, _objs.size()]
	mm.objectives[1]["done"] = dead >= _objs.size()
	match _phase:
		0:
			mm.nav_point = _site_w + Planet.up_at(_site_w) * 100.0
			mm.nav_label = "PİLOT"
			if mm._horiz_dist(v, _site_w) < 4000.0 or has_meta("killed"):
				mm.objectives[0]["done"] = true
				_heli = Helicopter.create_heli("rescue")
				_heli.home_xz = Vector2.ZERO
				_heli.rescue_target = _site_root
				mm.main.world.add_child(_heli)
				var back := (MissionManager.world_point(0, 0, 300.0) - _site_w)
				var up := Planet.up_at(_site_w)
				back = (back - up * back.dot(up)).normalized()
				var hp := _site_w + back * 7000.0 + up * 250.0
				_heli.global_transform = Transform3D(Planet.local_basis(hp), hp)
				_heli.landed_near_target.connect(func() -> void: _phase = 2)
				_heli.departed.connect(func() -> void: _phase = 4)
				_radio("%s, pilotu görüyorum. Kurtarma helikopteri yolda, iki dakika. Bölgeyi temiz tut!" % _cs(), "Rescue helo inbound.", "KURTARMA 1")
				_phase = 1
		1:
			mm.nav_point = _site_w + Planet.up_at(_site_w) * 100.0
			mm.nav_label = "PİLOT"
			if not is_instance_valid(_heli) or _heli.destroyed:
				mm._finish(false, "Kurtarma helikopteri düştü")
		2:
			_wait += delta
			mm.objectives[2]["text"] = "Pilot biniyor… %d sn" % ceili(maxf(6.0 - _wait, 0.0))
			if _wait > 6.0:
				var pm := _site_root.get_node_or_null("Pilot")
				if pm:
					pm.visible = false
				_heli.lift_off()
				_phase = 3
		4:
			mm.objectives[2]["done"] = true
			mm._finish(true, "Pilot kurtarıldı")
	if _phase in [2, 3] and (not is_instance_valid(_heli) or _heli.destroyed):
		mm._finish(false, "Kurtarma helikopteri düştü")


func _check_drop(v: Vessel) -> void:
	var need := int(card.get("crates", 3))
	var radius := float(card.get("zone_m", 150.0))
	mm.nav_point = _site_w
	mm.nav_label = "BIRAKMA BÖLGESİ"
	var flying := 0
	for n in mm.main.world.get_children():
		if n is CargoCrate:
			if not n.down:
				flying += 1
			elif not n.counted:
				n.counted = true
				var hd := _hd(n.global_position, _site_w)
				if hd < radius:
					_inside += 1
					mm._message("Sandık bölgede! (%d m)" % hd, 2.5)
				else:
					mm._message("Sandık bölge dışına düştü (%d m)" % hd, 2.5)
	mm.objectives[0]["text"] = "Sandıklar bölgede (%d/%d)" % [_inside, need]
	if _inside >= need:
		mm.objectives[0]["done"] = true
		mm._finish(true, "")
	elif v.cargo_left() == 0 and flying == 0:
		mm._finish(false, "Sandıklar bitti, bölgeye yalnızca %d tanesi indi" % _inside)


func _check_recon(v: Vessel) -> void:
	var agl_max := float(card.get("agl_max", 600.0))
	if _point_i < _points.size():
		var p: Vector2 = _points[_point_i]
		var g := MissionManager.ground_height(p.x, p.y)
		mm.nav_point = MissionManager.world_point(p.x, p.y, g + minf(agl_max * 0.5, 300.0))
		mm.nav_label = "KEŞİF %s  (<%d m AGL)" % [["A", "B", "C", "D"][_point_i], int(agl_max)]
		if mm._horiz_dist(v, mm.nav_point) < 450.0 and v.radar_altitude() < agl_max:
			mm.objectives[_point_i]["done"] = true
			_point_i += 1
			Sfx.play_ui("switch_4.ogg", 0.0, 1.8)
			mm._message("Fotoğraf çekildi ✓", 2.0)
			if _point_i < _points.size():
				card["target_xz"] = _points[_point_i]
				Game.mission_card["target_xz"] = _points[_point_i]
		return
	_check_base(v, "Fotoğrafları üsse getir")


# ------------------------------------------------------------------ brifing

## Brifing haritası: [ad, xz, renk] ve hedef satırları (MissionManager.briefing("gen")).
static func briefing_info(c: Dictionary) -> Dictionary:
	var red := Color(1.0, 0.35, 0.3)
	var gold := Color(1.0, 0.82, 0.3)
	var green := Color(0.45, 1.0, 0.6)
	var pts := []
	var tp := String(c.get("template", ""))
	var names := {"sam": "SAM", "lrsam": "SAM 40 km", "aaa": "Uçaksavar", "manpads": "", "radar": "Radar", "depot": "Depo",
		"bridge": "Köprü", "ship": "Gemi", "frigate": "Fırkateyn", "convoy": "Konvoy", "hunters": "Arama timi"}
	var shown := {}
	for u: Dictionary in c.get("units", []):
		var k := String(u["type"])
		var label := String(names.get(k, ""))
		if shown.has(k) and not bool(u.get("obj", false)):
			label = ""
		shown[k] = true
		pts.append([label, u["xz"], red if u.get("obj", false) or k in ["sam", "lrsam", "radar"] else Color(1.0, 0.6, 0.45)])
	for i in (c.get("points", []) as Array).size():
		pts.append([["A", "B", "C", "D"][i], c["points"][i], gold])
	if c.has("site"):
		pts.append(["Karakol" if tp == "yuk" else "Pilot", c["site"], gold])
	if c.has("goal_xz"):
		pts.append(["Konvoyun hedefi", c["goal_xz"], gold])
	if c.has("defend_xz"):
		pts.append(["Korunacak", c["defend_xz"], green])
	for f: Dictionary in c.get("fighters", []):
		if f.get("trigger", "") in ["start", "clock"]:
			pts.append(["Bombardımanlar" if f.get("role", "") == "bomber" else "Refakat", f["xz"], red])
	if tp == "eskort":
		pts.append(["Varış", c["target_xz"], green])
	if c.get("tanker", false):
		pts.append(["Tanker", c["tanker_xz"], Color(0.6, 0.85, 1.0)])
	var obj := []
	match tp:
		"kopru":
			obj = ["%s: en az %s patlayıcıyla yık" % [String(c["units"][0].get("name", "Hedef")), MissionGen._kg(float(c["payload_kg"]))], "Ortasını vur: tek bomba yetmez"]
		"sam":
			obj = ["Bütün SAM rampalarını ve radarları yok et", "9 km içinde 120 m üstünde görünme, chaff / ECM / radar avcısı füze"]
		"konvoy":
			obj = ["Konvoyu hedefine varmadan yok et", "Refakat araçları makineli tüfekle karşılık verir"]
		"onleme":
			obj = ["Bombardımanları %d m'de, Mach %.2f — %d dk içinde düşür" % [int(c["target_alt_m"]), c["target_mach"], int(float(c["time_limit_s"]) / 60.0)], "Hedefe 3 km yaklaşmalarına izin verme"]
		"eskort":
			obj = ["Herkül'ü varış noktasına kadar koru", "Düşman avcılarını nakliyeden uzak tut"]
		"kurtarma":
			obj = ["Pilotun yanına git (4 km): helikopter çağrılır", "Arama timini pilota 250 m yaklaştırma", "Helikopter pilotu alıp kalksın"]
		"yuk":
			obj = ["%d sandığı %d m'lik bölgeye bırak (V: KARGO, Space)" % [int(c.get("crates", 3)), int(c.get("zone_m", 150.0))], "Dar vadi: yavaş ve alçak geç"]
		"kesif":
			obj = ["A, B, C noktalarının üzerinden %d m AGL altında geç" % int(c.get("agl_max", 600.0)), "Fotoğrafları üsse getir (3 km)"]
		"gemi":
			obj = ["Bütün gemileri batır", "CIWS gelen füzeyi düşürebilir: birlikte at"]
		"derin":
			obj = ["Mühimmat depolarını yok et", "Erken uyarı radarına görünme", "Üsse dön (3 km)"]
	return {"points": pts, "objectives": obj}
