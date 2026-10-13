class_name AmbientAir
extends Node
## Ortam hava trafiği (taktik katman): cephe hattı boyunca dost ve düşman devriye çiftleri, aralarında
## kendiliğinden çıkan it dalaşları (oyuncu katılabilir) ve ara sıra dost bölgeye yönelen düşman
## taarruz paketi (kuleden "ÖNLEME" çağrısı, önleyene prim; kariyerde bağlı baskın boşa çıkar).
##
## Ucuz tutmak için gruplar iki hâlde yaşar:
##   sanal  — yalnız (x, z) konumu ve rota; 1 Hz ilerler, sanal düşmanla karşılaşırsa zarla çatışır
##   gerçek — oyuncuya LIVE_RANGE'ten yakınken fizikli uçak + AIPilot (en çok MAX_LIVE uçak)
## Uzaklaşan gerçek grup tekrar sanala döner (uçaklar silinir). Konumlar yüzey koordinatında
## (x doğu, z güney) tutulur; kayan orijinden etkilenmez.
##
## Görev sırasında görevin kendi düşmanlarına karışmaz: yalnız izin veren görevlerde, görev
## bölgesinden uzak rotalarda, düşman ortam uçakları ancak ortam rakibi / oyuncu yakınken saldırgan.
## Testlerde yalnız --ambient / --ambienttest ile açılır; --noambient kapatır.

const MAX_LIVE := 4             ## aynı anda gerçek yapay zekâ uçağı (her biri ~1–1.5 ms işlemci)
const LIVE_RANGE := 24000.0
const VIRTUAL_RANGE := 30000.0
const MIN_SPAWN_DIST := 10000.0
## Görev bölgesinden uzak dur (light kip)
const AVOID_R := 11000.0
const FIGHTER := "res://crafts/kartal_1.json"
const BOMBER := "res://crafts/sahin_b.json"
const LIFE := 1100.0
const CALLSIGNS := ["Kılıç", "Şimşek", "Yıldırım", "Pars", "Börü", "Tufan"]
## Görev → ortam kipi. full: her şey; light: devriyeler görevden uzakta, taarruz paketi yalnız
## kariyerde açık baskın varken; friendly: yalnız dost devriye. Listede olmayan görev: ortam yok.
const MISSION_MODE := {
	"kesif": "light", "kara": "light", "sam": "light", "heli": "light", "devriye": "light",
	"filo": "light", "firkateyn": "light",
	"egitim": "friendly", "yolcu": "friendly", "kargo": "friendly", "kurtarma": "friendly", "ikmal": "friendly",
	"nakliye": "friendly",
}

var main: Node
var mode := "full"
var _groups: Array[Dictionary] = []
var _tick := 0.0
var _clock := 0.0
var _respawn := 30.0
var _strike_t := 120.0
var _strikes := 0
var _wrecks: Array = []           # [Vessel, ölüm zamanı]
var _avoid: Array[Vector2] = []
var _seq := 0
var _test := false


## main._ready sonunda: kip uygunsa yöneticiyi ekle. Döndürür: yönetici (ya da null).
static func attach(m: Node, mission_id: String) -> AmbientAir:
	var md := mode_for(mission_id)
	if md == "none":
		return null
	var a := AmbientAir.new()
	a.name = "AmbientAir"
	a.main = m
	a.mode = md
	m.add_child(a)
	return a


static func mode_for(mission_id: String) -> String:
	if Game.args.has("noambient") or Game.args.has("nolife"):
		return "none"
	if Crew._testing() and not (Game.args.has("ambient") or Game.args.has("ambienttest")):
		return "none"
	if mission_id == "":
		return "full"
	return String(MISSION_MODE.get(mission_id, "none"))


func _ready() -> void:
	_test = Game.args.has("ambienttest")
	if mode != "full" and Game.mission_region != "":
		var r := Front.region(Game.mission_region)
		if not r.is_empty():
			_avoid.append(r["xz"])
	_strike_t = 25.0 if _test else randf_range(100.0, 160.0)
	# başlangıçta birer dost ve düşman devriye
	_spawn_patrol("oyuncu")
	if mode != "friendly":
		_spawn_patrol("düşman")
	if _test:
		print("AMBIENT start mode=%s groups=%d" % [mode, _groups.size()])


func _physics_process(delta: float) -> void:
	_clock += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	var me := _player_xz()
	if me == Vector2.INF:
		return
	for g in _groups.duplicate():
		if g["live"].is_empty():
			_update_virtual(g, me)
		else:
			_update_live(g, me)
	_virtual_fights(me)
	_manage_live(me)
	_clean_wrecks()
	# yeni gruplar
	_respawn -= 1.0
	if _respawn <= 0.0:
		_respawn = randf_range(50.0, 90.0)
		var want := 1 if mode != "full" else 2
		if _count("oyuncu", "patrol") < want:
			_spawn_patrol("oyuncu")
		if mode != "friendly" and _count("düşman", "patrol") < want:
			_spawn_patrol("düşman")
	_strike_t -= 1.0
	if _strike_t <= 0.0:
		_strike_t = randf_range(240.0, 420.0)
		_try_strike(me)
	# --ambienttest --ambientkill: gerçek taarruz paketini oyuncu düşürmüş say (önleme zincirini dener)
	if _test and Game.args.has("ambientkill"):
		for g in _groups:
			if g["kind"] == "strike" and not (g["live"] as Array).is_empty():
				g["pk"] = 1
				for v in g["live"]:
					v.queue_free()
	if _test and int(_clock) % 5 == 0:
		_print_status(me)
	if _test and _clock > float(Game.args.get("ambient-time", "75")):
		print("AMBIENT done groups=%d live=%d" % [_groups.size(), _live_count()])
		get_tree().quit()


# ------------------------------------------------------------------ cephe geometrisi

func _owner(id: String) -> int:
	if Front.status() != "running":
		return int(Front.region(id)["start"])
	return Front.owner(id)


## Cephe hattı kenarları: [dost/çekişmeli bölge, komşu düşman bölge], görev bölgesinden uzak olanlar.
func _edges() -> Array:
	var out := []
	for r: Dictionary in Front.REGIONS:
		var f: String = r["id"]
		if _owner(f) == Front.DUSMAN:
			continue
		for e: String in Front.NEIGHBORS[f]:
			if _owner(e) != Front.DUSMAN:
				continue
			var mid: Vector2 = (r["xz"] as Vector2).lerp(Front.region(e)["xz"], 0.5)
			if _avoided(mid, AVOID_R + 2000.0):
				continue
			out.append([f, e])
	return out


func _avoided(xz: Vector2, r := AVOID_R) -> bool:
	for a in _avoid:
		if xz.distance_to(a) < r:
			return true
	return false


## Kenarın kendi tarafında yarış pisti biçimli devriye rotası.
func _patrol_route(own: Vector2, other: Vector2, enemy := false) -> Array[Vector2]:
	var d := (other - own).normalized()
	var side := Vector2(-d.y, d.x) * 3000.0
	var p1 := own.lerp(other, 0.3)
	var p2 := own.lerp(other, 0.58)
	var out: Array[Vector2] = []
	for p: Vector2 in [p1 + side, p2 + side, p2 - side, p1 - side]:
		# düşman devriye dost meydanların 9 km yakınına girmez (pistte bekleyen oyuncuya dalmasın)
		if not _avoided(p) and not (enemy and _near_friendly_field(p, 9000.0)):
			out.append(p)
	return out


# ------------------------------------------------------------------ gruplar

func _spawn_patrol(team: String) -> bool:
	var me := _player_xz()
	var edges := _edges()
	edges.shuffle()
	for e: Array in edges:
		var own: Vector2 = Front.region(e[0] if team == "oyuncu" else e[1])["xz"]
		var other: Vector2 = Front.region(e[1] if team == "oyuncu" else e[0])["xz"]
		var route := _patrol_route(own, other, team != "oyuncu")
		if route.size() < 2:
			continue
		# giriş noktası: oyuncudan yeterince uzak (kendi gerimizden uçarak gelir)
		var back := own + (own - other).normalized() * 6000.0
		var start := Vector2.INF
		for p: Vector2 in [route[0], own, back]:
			if me == Vector2.INF or p.distance_to(me) >= MIN_SPAWN_DIST:
				start = p
				break
		if start == Vector2.INF:
			continue
		_seq += 1
		var friend := team == "oyuncu"
		var cs: String = CALLSIGNS[_seq % CALLSIGNS.size()] if friend else "Düşman devriye %d" % _seq
		_groups.append({"team": team, "kind": "patrol", "name": cs, "xz": start, "alt": randf_range(2400.0, 3600.0),
			"speed": 200.0, "route": route, "wp": 0, "n": 2, "live": [], "skill": randf_range(0.45, 0.65) if friend else randf_range(0.35, 0.6),
			"born": _clock, "fight": false, "called": false, "pk": 0})
		if _test:
			print("AMBIENT spawn %s %s at %s route %s" % [team, cs, start, e])
		return true
	return false


## Taarruz paketi: iki bombardıman düşman bölgesinden dost hedefe.
func _try_strike(me: Vector2) -> void:
	if mode == "friendly" or _count("düşman", "strike") > 0:
		return
	var raid := FrontAI.pending_raid()
	var target := ""
	if mode == "light":
		if raid.is_empty() or _strikes > 0:
			return
		target = raid["region"]
	elif not raid.is_empty():
		target = raid["region"]
	else:
		var opts := []
		for r: Dictionary in Front.REGIONS:
			if _owner(r["id"]) == Front.DOST:
				opts.append(r["id"])
		if opts.is_empty():
			return
		target = "anaus" if "anaus" in opts and randf() < 0.5 else String(opts.pick_random())
	var src := FrontAI._raid_source(target)
	if src == "":
		src = "kuzeyhava"
	var txz: Vector2 = Front.region(target)["xz"]
	var sxz: Vector2 = Front.region(src)["xz"]
	# kaynak çok yakınsa geriden gelsin (önlemeye zaman kalsın)
	if sxz.distance_to(txz) < 22000.0:
		sxz = txz + (sxz - txz).normalized() * 22000.0
	_strikes += 1
	_seq += 1
	var route: Array[Vector2] = [txz]
	var g := {"team": "düşman", "kind": "strike", "name": "Taarruz paketi", "xz": sxz, "alt": 4000.0, "speed": 190.0,
		"route": route, "wp": 0, "n": 2, "live": [], "skill": 0.45, "born": _clock, "fight": false, "called": false,
		"pk": 0, "target": target, "home": sxz, "struck": false}
	_groups.append(g)
	var tname := String(Front.region(target)["name"])
	var dist := int(sxz.distance_to(me) / 1000.0)
	_say("KULE", "Tüm birlikler, ÖNLEME! İki düşman bombardıman %s yönüne ilerliyor. Kerteriz %03d, %d kilometre, irtifa dört bin. Önleyene prim var." % [tname, _bearing(me, sxz), dist],
		"All units, scramble! Two enemy bombers inbound %s. Bearing %03d, %d kilometers, angels twelve." % [tname, _bearing(me, sxz), dist])
	if main.hud:
		main.hud.show_message("ÖNLEME: düşman taarruz paketi → %s  (kerteriz %03d, %d km)" % [tname, _bearing(me, sxz), dist], 6.0)


func _count(team: String, kind: String) -> int:
	var n := 0
	for g in _groups:
		if g["team"] == team and g["kind"] == kind:
			n += 1
	return n


func _live_count() -> int:
	var n := 0
	for g in _groups:
		n += (g["live"] as Array).size()
	return n


## Sanal grup: rotada ilerler; ömrü dolunca (uzaktaysa) üssüne döner = silinir.
func _update_virtual(g: Dictionary, me: Vector2) -> void:
	if _clock - float(g["born"]) > LIFE and (g["xz"] as Vector2).distance_to(me) > LIVE_RANGE:
		_groups.erase(g)
		return
	if g["fight"]:
		return
	var tgt: Vector2 = g["route"][g["wp"]]
	var d: Vector2 = tgt - g["xz"]
	var step := float(g["speed"]) * 1.0
	if d.length() <= step:
		g["xz"] = tgt
		_next_wp(g)
	else:
		g["xz"] = (g["xz"] as Vector2) + d.normalized() * step


func _next_wp(g: Dictionary) -> void:
	if g["kind"] == "strike":
		if not g["struck"]:
			g["struck"] = true
			_on_struck(g)
			var back: Array[Vector2] = [g["home"]]
			g["route"] = back
			g["wp"] = 0
		else:
			_despawn(g)
		return
	g["wp"] = (int(g["wp"]) + 1) % (g["route"] as Array).size()


## Gerçek grup: ölüleri say (oyuncuya düşürme), lideri rotaya yönelt, uzaklaşınca sanala dön.
func _update_live(g: Dictionary, me: Vector2) -> void:
	var live: Array = g["live"]
	var alive: Array = []
	for v in live:
		if _dead(v):
			g["n"] = int(g["n"]) - 1
			_wrecks.append([v, _clock])
			_on_down(g, v)
		else:
			alive.append(v)
	g["live"] = alive
	if alive.is_empty():
		_group_gone(g)
		return
	var lead: Vessel = alive[0]
	g["xz"] = _xz_of(lead.global_position)
	g["alt"] = clampf(_alt_of(lead.global_position), 1500.0, 5000.0)
	var ai := AIPilot.of(lead)
	if ai:
		# lider öldüyse kanat adamı lider olur
		ai.leader = null
		var tgt: Vector2 = g["route"][g["wp"]]
		if (g["xz"] as Vector2).distance_to(tgt) < (2500.0 if g["kind"] == "strike" else 2000.0):
			_next_wp(g)
			if not _groups.has(g):
				return
			tgt = g["route"][g["wp"]]
		if ai.state == AIPilot.State.PATROL:
			ai._ap.target_heading = _bearing(g["xz"], tgt)
	var engaged := false
	for v: Vessel in alive:
		var a := AIPilot.of(v)
		if a == null:
			continue
		if g["kind"] == "patrol":
			a.aggressive = _foe_near(g, v.global_position)
			# yerdeki (pistteki) oyuncuya dalmasın: yakına gelen düşman çatışmayı bırakır
			if g["team"] == "düşman" and is_instance_valid(main.vessel) and main.vessel.radar_altitude() < 150.0 \
					and main.vessel.global_position.distance_to(v.global_position) < 9000.0:
				a.aggressive = false
		if a.state == AIPilot.State.ENGAGE or a.state == AIPilot.State.DEFEND or a.state == AIPilot.State.EVADE:
			engaged = true
	# dost devriye çatışmaya girdi: oyuncuyu çağır
	if engaged and g["team"] == "oyuncu" and not g["called"]:
		g["called"] = true
		var dist := (g["xz"] as Vector2).distance_to(me)
		if dist > 3000.0:
			_say("ŞAHİN GÖZÜ", "%s uçuşu düşmanla çatışmada. Kerteriz %03d, %d kilometre. Yardıma gidebilirsen git." % [g["name"], _bearing(me, g["xz"]), int(dist / 1000.0)],
				"%s flight engaged with bandits. Bearing %03d, %d kilometers. Assist if able." % [g["name"], _bearing(me, g["xz"]), int(dist / 1000.0)])
	if not engaged and (g["xz"] as Vector2).distance_to(me) > VIRTUAL_RANGE:
		_virtualize(g)


## Ortam uçağı yalnız yakındaki ortam rakibine saldırır; düşmanlar havadaki oyuncuya da (pistte
## bekleyene değil). Görevin kendi düşmanlarını aramaya gitmezler.
func _foe_near(g: Dictionary, p: Vector3) -> bool:
	for o in _groups:
		if o["team"] == g["team"]:
			continue
		for v in o["live"]:
			if is_instance_valid(v) and v.global_position.distance_to(p) < 15000.0:
				return true
	if g["team"] == "düşman" and is_instance_valid(main.vessel) and main.vessel.radar_altitude() > 150.0 and main.vessel.global_position.distance_to(p) < 15000.0:
		return true
	return false


func _dead(v: Variant) -> bool:
	return not is_instance_valid(v) or v.parts.is_empty() or v.cockpit() == null or not v.has_pilot()


## Bir ortam uçağı düştü: oyuncu yakındaysa (ve daha yakın dost ortam uçağı yoksa) düşürme oyuncunun.
func _on_down(g: Dictionary, v: Variant) -> void:
	if g["team"] != "düşman" or not is_instance_valid(v) or not is_instance_valid(main.vessel) or not main.vessel.has_pilot():
		return
	var p: Vector3 = v.global_position
	var dp: float = main.vessel.global_position.distance_to(p)
	if dp > 6000.0:
		return
	for o in _groups:
		if o["team"] != "oyuncu":
			continue
		for f in o["live"]:
			if is_instance_valid(f) and f.global_position.distance_to(p) < dp * 0.7:
				return
	g["pk"] = int(g["pk"]) + 1
	Crew.add_kill()
	if main.radio:
		main.radio.on_kill()
	if main.hud:
		main.hud.show_message("%s düşürüldü!  +40 XP" % ("Bombardıman" if g["kind"] == "strike" else "Düşman devriye"), 3.0)
	if _test:
		print("AMBIENT player kill in ", g["name"])


## Grup tükendi.
func _group_gone(g: Dictionary) -> void:
	_groups.erase(g)
	if g["kind"] == "strike" and not g["struck"]:
		if int(g["pk"]) > 0:
			var msg := FrontAI.strike_intercepted(g["target"])
			if main.hud:
				main.hud.show_message(msg, 6.0)
			_say("KULE", "Taarruz paketi dağıtıldı. Harika iş, %s." % _callsign(), "Strike package destroyed. Good work, %s." % _callsign())
		else:
			_say("ŞAHİN GÖZÜ", "Dost devriye taarruz paketini düşürdü.", "Friendly patrol splashed the strike package.")
	if _test:
		print("AMBIENT group gone ", g["name"], " pk=", g["pk"])


## Taarruz paketi hedefe ulaştı.
func _on_struck(g: Dictionary) -> void:
	var tname := String(Front.region(g["target"])["name"])
	_say("KULE", "Bombardımanlar %s üzerinde! Hasar bildirildi." % tname, "Bombers over %s! Damage reported." % tname)
	if _test:
		print("AMBIENT strike reached ", g["target"])


func _despawn(g: Dictionary) -> void:
	for v in g["live"]:
		if is_instance_valid(v):
			v.queue_free()
	_groups.erase(g)


func _virtualize(g: Dictionary) -> void:
	var n := 0
	for v in g["live"]:
		if is_instance_valid(v):
			n += 1
			v.queue_free()
	g["n"] = n
	g["live"] = []
	if _test:
		print("AMBIENT virtualize ", g["name"])


## Sanal dost ve düşman devriyeler karşılaşınca zarla çatışır (oyuncudan uzakta).
func _virtual_fights(me: Vector2) -> void:
	var gone := []
	for a in _groups:
		if a["team"] != "oyuncu" or not (a["live"] as Array).is_empty():
			continue
		var foe: Dictionary = {}
		for b in _groups:
			if b["team"] == "düşman" and (b["live"] as Array).is_empty() and (a["xz"] as Vector2).distance_to(b["xz"]) < 5000.0:
				foe = b
				break
		a["fight"] = not foe.is_empty()
		if foe.is_empty():
			continue
		foe["fight"] = true
		if not a["called"] and (a["xz"] as Vector2).distance_to(me) < 45000.0:
			a["called"] = true
			_say("ŞAHİN GÖZÜ", "%s uçuşu düşmanla çatışmada. Kerteriz %03d, %d kilometre." % [a["name"], _bearing(me, a["xz"]), int((a["xz"] as Vector2).distance_to(me) / 1000.0)],
				"%s flight engaged. Bearing %03d, %d kilometers." % [a["name"], _bearing(me, a["xz"]), int((a["xz"] as Vector2).distance_to(me) / 1000.0)])
		for pair in [[a, foe], [foe, a]]:
			if randf() < (0.03 if pair[0]["kind"] == "strike" else 0.02) * (0.85 + 0.5 * Designs.fleet_quality() if pair[0]["team"] == "oyuncu" else 1.0):
				pair[1]["n"] = int(pair[1]["n"]) - 1
		for g in [a, foe]:
			if int(g["n"]) <= 0 and not g in gone:
				gone.append(g)
	for g in _groups:
		if g["fight"] and g["team"] == "düşman":
			var still := false
			for a in _groups:
				if a["team"] == "oyuncu" and (a["xz"] as Vector2).distance_to(g["xz"]) < 5000.0:
					still = true
			g["fight"] = still
	for g in gone:
		_groups.erase(g)
		if _test:
			print("AMBIENT virtual loss ", g["name"])


## Oyuncuya yakın sanal grupları gerçek uçağa çevir (en yakın önce, toplam MAX_LIVE).
func _manage_live(me: Vector2) -> void:
	var cands := []
	for g in _groups:
		if (g["live"] as Array).is_empty() and int(g["n"]) > 0:
			var d := (g["xz"] as Vector2).distance_to(me)
			if d < LIVE_RANGE:
				cands.append([d, g])
	if cands.is_empty():
		return
	# taarruz paketi önce (önleme çağrısı yapıldı, görünmeli)
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		var sa: bool = a[1]["kind"] == "strike"
		var sb: bool = b[1]["kind"] == "strike"
		return sa if sa != sb else a[0] < b[0])
	var used := _live_count()
	for c: Array in cands:
		var g: Dictionary = c[1]
		var n := mini(int(g["n"]), 2)
		if used + n > MAX_LIVE and g["kind"] == "strike":
			used -= _free_farthest_patrol(me)
		if used + n > MAX_LIVE:
			break
		_materialize(g, n)
		used += n
		break                     # karede tek grup


## Yer açmak için en uzaktaki gerçek devriyeyi sanala çevir. Döndürür: boşalan uçak sayısı.
func _free_farthest_patrol(me: Vector2) -> int:
	var best: Dictionary = {}
	var bd := -1.0
	for g in _groups:
		if g["kind"] == "patrol" and not (g["live"] as Array).is_empty() and (g["xz"] as Vector2).distance_to(me) > bd:
			bd = (g["xz"] as Vector2).distance_to(me)
			best = g
	if best.is_empty():
		return 0
	var n: int = (best["live"] as Array).size()
	_virtualize(best)
	return n


func _materialize(g: Dictionary, n: int) -> void:
	var xz: Vector2 = g["xz"]
	var tgt: Vector2 = g["route"][g["wp"]]
	var dir := (tgt - xz).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	var right := Vector2(-dir.y, dir.x)
	var hdg := _bearing(xz, tgt)
	var friend: bool = g["team"] == "oyuncu"
	var strike: bool = g["kind"] == "strike"
	var live: Array = []
	g["live"] = live          # kurulurken tekrar seçilmesin
	for i in n:
		if i > 0:
			await get_tree().process_frame    # uçakları ayrı karelerde kur: takılma olmasın
			if not is_instance_valid(main) or not is_instance_valid(main.world):
				return
		var p: Vector2 = xz - dir * 300.0 * i + right * 320.0 * i
		var alt := maxf(float(g["alt"]) + 40.0 * i, MissionManager.ground_height(p.x, p.y) + 600.0)
		var pos := MissionManager.world_point(p.x, p.y, alt)
		var frame := Planet.local_basis(pos)
		var basis := Basis(frame.y, deg_to_rad(-hdg)) * frame
		# dost avcı devriyeler oyuncunun seri üretimdeki tasarımıyla uçar (Designs; yoksa Kartal)
		var craft: Dictionary = Designs.fleet_craft() if friend and not strike else {}
		if craft.is_empty():
			craft = VesselBuilder.load_craft(BOMBER if strike else FIGHTER)
		elif _test:
			print("AMBIENT filo tipi: ", craft.get("name", ""))
		craft["paint"] = {"scheme": "gri" if friend else ("gece" if strike else "çöl"), "number": ("K-%d" if friend else "D-%d") % (10 + randi() % 80)}
		var v := VesselBuilder.build(craft)
		v.name = "Ambient%d" % (_seq * 10 + i)
		v.craft_name = ("%s-%d" % [g["name"], i + 1]) if friend else ("Bombardıman %d" % (i + 1) if strike else "%s-%d" % [g["name"], i + 1])
		v.team = g["team"]
		v.transform = Transform3D(basis, pos)
		v.linear_velocity = -basis.z * float(g["speed"])
		main.world.add_child(v)
		v.set_gear_instant(false)
		v.set_hot()
		v.lights_on = true
		var ai := AIPilot.new()
		ai.vessel = v
		ai.skill = float(g["skill"])
		ai.aggressive = false   # _update_live rakip yakınken açar
		ai.altitude = alt
		ai.speed = float(g["speed"])
		ai.leg_time = 1.0e9
		v.add_child(ai)
		live.append(v)
	if live.size() == 2:
		AIPilot.pair(live[0], live[1])
	g["live"] = live
	g["fight"] = false
	if _test:
		print("AMBIENT materialize %s (%s) n=%d" % [g["name"], g["team"], n])


## Düşen uçak enkazları: 2 dk sonra oyuncudan uzaksa silinir.
func _clean_wrecks() -> void:
	for w in _wrecks.duplicate():
		if not is_instance_valid(w[0]):
			_wrecks.erase(w)
		elif _clock - float(w[1]) > 120.0 and (not is_instance_valid(main.vessel) or main.vessel.global_position.distance_to(w[0].global_position) > 4000.0):
			w[0].queue_free()
			_wrecks.erase(w)


# ------------------------------------------------------------------ yardımcılar

func _player_xz() -> Vector2:
	var v: Node3D = main.vessel if is_instance_valid(main.vessel) else (main.pilot if is_instance_valid(main.pilot) else null)
	return _xz_of(v.global_position) if v else Vector2.INF


static func _xz_of(p: Vector3) -> Vector2:
	var d := (p - Planet.center()).normalized()
	return Vector2(d.x, d.z) / maxf(d.y, 0.01) * Planet.RADIUS


static func _alt_of(p: Vector3) -> float:
	return (p - Planet.center()).length() - Planet.RADIUS


## a'dan b'ye kerteriz (derece, 0 = kuzey / -z).
static func _bearing(a: Vector2, b: Vector2) -> int:
	var d := b - a
	return int(fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0))


func _callsign() -> String:
	return main.radio.callsign() if main.radio else "pilot"


func _say(sender: String, tr: String, en: String) -> void:
	if _test:
		print("AMBIENT RADIO [%s] %s" % [sender, tr])
	var r: Radio = main.radio
	if r and r.enabled:
		r.say(tr, en, sender)
	elif main.hud:
		main.hud.radio_message(sender, tr)


func _print_status(me: Vector2) -> void:
	var parts := PackedStringArray()
	for g in _groups:
		var st := "live" if not (g["live"] as Array).is_empty() else ("fight" if g["fight"] else "virt")
		var ai_st := ""
		if not (g["live"] as Array).is_empty():
			var a := AIPilot.of(g["live"][0])
			ai_st = "/" + AIPilot.STATE_NAMES[a.state] if a else ""
		parts.append("%s[%s n=%d %s%s %.0fkm]" % [g["name"], g["team"], int(g["n"]), st, ai_st, (g["xz"] as Vector2).distance_to(me) / 1000.0])
	print("AMBIENT t=%d live=%d phys=%.1fms  %s" % [int(_clock), _live_count(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "  ".join(parts)])


## Dost (sahibi düşman olmayan) bir havaalanına yakın mı.
func _near_friendly_field(p: Vector2, r: float) -> bool:
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var xz: Vector2 = a["xz"]
		var rid := "anaus" if a["name"] == "Ana Üs" else "kuzeyhava"
		if _owner(rid) != Front.DUSMAN and p.distance_to(xz) < r:
			return true
	return false
