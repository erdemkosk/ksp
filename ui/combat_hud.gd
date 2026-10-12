class_name CombatHud
extends Control
## Savaş göstergeleri:
##  • Radar hedef kutuları (her dış/kokpit görünümde): mesafe, yaklaşma hızı, ekran dışıysa kenar oku
##  • Kokpit HUD nişangahları (MASTER ARM açıkken):
##      TOP   — mermi düşüşü ve hedef hareketini hesaplayan önleme nişangahı (pipper + öngörü elması)
##      FÜZE  — arayıcı halkası; kilitlenince hedefe atlar, "KİLİT" ve atış menzili
##      BOMBA — CCIP: bomba şimdi bırakılırsa düşeceği nokta + düşüş çizgisi
##  • Silah durumu paneli, radar ekranı (sol altta uçuş panelinin yanında)
##  • Füze yaklaşma uyarısı (yön oku + bip), arayıcı hırıltısı ve kilit tonu sesleri

const HUD_COLOR := Color(0.4, 1.0, 0.6)
const ENEMY := Color(1.0, 0.35, 0.3)
const FRIEND := Color(0.4, 0.8, 1.0)
const SHADOW := Color(0, 0, 0, 0.55)

var vessel: Vessel
var camera: FlightCamera

var _font: SystemFont
var _bold: SystemFont
var _growl: AudioStreamPlayer
var _lock: AudioStreamPlayer
var _beep_timer := 0.0
var _blink := 0.0
var _ccip: Variant = null
var _ccip_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	_growl = _loop("seeker_growl.ogg")
	_lock = _loop("lock_tone.ogg")


func _loop(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.looped(name)
	p.bus = Sfx.BUS_UI
	p.volume_db = -12.0
	add_child(p)
	return p


# ------------------------------------------------------------------ hedef seçimi

## Sol tık hedef kutusuna (imleç serbestken) ya da F4: radar temasını seç. Seçili hedef
## füze arayıcısının önceliğidir; aynı hedefe tekrar tık seçimi kaldırır.
func _unhandled_input(event: InputEvent) -> void:
	if not _ok() or not vessel.has_pilot() or (vessel.radar() == null and vessel.irst() == null):
		return
	if event.is_action_pressed("target_cycle"):
		cycle_target()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		for t in vessel.sensor_contacts():
			if not is_instance_valid(t) or t.parts.is_empty():
				continue
			var sp: Variant = _proj(t.com_global())
			if sp == null:
				continue
			var half := clampf(9000.0 / maxf(t.com_global().distance_to(vessel.com_global()), 1.0), 12.0, 44.0) + 8.0
			if (event.position - (sp as Vector2)).abs().x < half and (event.position - (sp as Vector2)).abs().y < half:
				designate(t)
				get_viewport().set_input_as_handled()
				return


func designate(t: Vessel) -> void:
	vessel.designated = null if vessel.designated == t else t
	Sfx.play_ui("lock_tone.ogg" if vessel.designated else "switch_2.ogg", -10.0, 1.6)


## Sıradaki temas: burna en yakın açıdan başlayarak döner.
func cycle_target() -> void:
	var list: Array = []
	for t in vessel.sensor_contacts():
		if is_instance_valid(t) and not t.parts.is_empty() and t.team != vessel.team:
			list.append(t)
	if list.is_empty():
		vessel.designated = null
		return
	var fwd := vessel.forward()
	list.sort_custom(func(a: Vessel, b: Vessel) -> bool:
		return fwd.angle_to(a.com_global() - vessel.com_global()) < fwd.angle_to(b.com_global() - vessel.com_global()))
	var i := list.find(vessel.designated)
	vessel.designated = list[(i + 1) % list.size()]
	Sfx.play_ui("lock_tone.ogg", -10.0, 1.6)


func _ok() -> bool:
	return is_instance_valid(vessel) and vessel.is_inside_tree() and is_instance_valid(camera) and not camera.is_eva()


func _process(delta: float) -> void:
	_blink += delta
	_update_audio(delta)
	_ccip_timer -= delta
	var bomb_sel := _ok() and ((vessel.selected_weapon == Vessel.WEAPON_BOMB and vessel.bombs_left() > 0) \
		or (vessel.selected_weapon == Vessel.WEAPON_LGB and vessel.bombs_left(true) > 0))
	if bomb_sel and _ccip_timer <= 0.0:
		_ccip_timer = 0.05
		_ccip = Bomb.simulate_impact(vessel.get_world_3d().direct_space_state, vessel.com_global() - vessel.up() * 0.8, vessel.linear_velocity)
	elif _ok() and vessel.selected_weapon == Vessel.WEAPON_CARGO and vessel.cargo_left() > 0 and _ccip_timer <= 0.0:
		_ccip_timer = 0.1
		_ccip = CargoCrate.simulate_impact(vessel.com_global() - vessel.up() * 1.5, vessel.linear_velocity)
	queue_redraw()


# ------------------------------------------------------------------ ses

func locked_target() -> Vessel:
	for m in vessel.modules:
		if m is MissileModule and m.loaded and is_instance_valid(m.target):
			return m.target
	return null


func _update_audio(delta: float) -> void:
	var armed := _ok() and vessel.has_pilot() and vessel.master_arm and vessel.has_power()
	var missile_mode := armed and vessel.selected_weapon == Vessel.WEAPON_MISSILE and vessel.missiles_left() > 0
	var radar_mode := armed and vessel.selected_weapon == Vessel.WEAPON_RADAR and vessel.radar_missiles_left() > 0
	var locked := (missile_mode or radar_mode) and locked_target() != null
	_set_playing(_growl, missile_mode and not locked)
	_set_playing(_lock, locked)
	_update_rwr(delta)
	# füze yaklaşma uyarısı: yaklaştıkça hızlanan bip
	var inc := vessel.incoming_missile() if _ok() else null
	if inc:
		_beep_timer -= delta
		if _beep_timer <= 0.0:
			var d := inc.global_position.distance_to(vessel.com_global())
			_beep_timer = clampf(d / 6000.0, 0.08, 0.5)
			Sfx.play_ui("caution_beep.ogg", -4.0, 1.7)


func _set_playing(p: AudioStreamPlayer, on: bool) -> void:
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


# ------------------------------------------------------------------ çizim

func _draw() -> void:
	if not _ok():
		return
	var s := size
	var cockpit := camera.mode == FlightCamera.Mode.COCKPIT
	var powered := vessel.has_power()
	_target_boxes()
	if cockpit and powered and vessel.master_arm and vessel.has_pilot():
		match vessel.selected_weapon:
			Vessel.WEAPON_GUN:
				if vessel.gun_ammo() > 0:
					_gun_sight()
			Vessel.WEAPON_MISSILE:
				if vessel.missiles_left() > 0:
					_missile_sight()
			Vessel.WEAPON_RADAR:
				if vessel.radar_missiles_left() > 0:
					_radar_missile_sight()
			Vessel.WEAPON_BOMB:
				if vessel.bombs_left() > 0:
					_bomb_sight()
			Vessel.WEAPON_LGB:
				if vessel.bombs_left(true) > 0:
					_lgb_sight()
	if vessel.selected_weapon == Vessel.WEAPON_CARGO and vessel.cargo_left() > 0:
		_cargo_sight()
	_own_missiles(s)
	_missile_warning(s)
	if powered and _has_rwr():
		_draw_rwr(s)


func _proj(world: Vector3) -> Variant:
	if camera.is_position_behind(world):
		return null
	var p := camera.unproject_position(world)
	if size.x > 10.0 and Rect2(Vector2.ZERO, size).grow(-4).has_point(p):
		return p
	return null


## Ekran dışı/arkadaki nokta için ekran kenarındaki yön (merkezden).
func _edge_dir(world: Vector3) -> Vector2:
	var local := camera.global_basis.inverse() * (world - camera.global_position)
	var d := Vector2(local.x, -local.y)
	return d.normalized() if d.length() > 0.001 else Vector2.UP


func _enemies() -> Array[Vessel]:
	var out: Array[Vessel] = []
	for n in vessel.get_parent().get_children():
		if n is Vessel and n != vessel and not n.parts.is_empty() and n.team != vessel.team:
			out.append(n)
	return out


func _target_boxes() -> void:
	if (vessel.radar() == null and vessel.irst() == null) or not vessel.has_power():
		return
	var locked := locked_target()
	var c := size * 0.5
	for t in vessel.sensor_contacts():
		if not is_instance_valid(t) or t.parts.is_empty():
			continue
		var col := FRIEND if t.team == vessel.team else (Color(0.72, 0.75, 0.78) if t.team == "sivil" else ENEMY)
		# yalnız IRST'nin gördüğü temas: turuncu, mesafe yok (pasif sensör, açı izi)
		if vessel.ir_only(t):
			var ip: Variant = _proj(t.heat_position())
			if ip != null:
				_ring(ip, 16.0, Color(1.0, 0.6, 0.2))
				_text_c(ip + Vector2(0, -24), "IR", 13, Color(1.0, 0.6, 0.2), _bold)
				if t == vessel.designated:
					_ring(ip, 22.0, Color(0.45, 0.85, 1.0))
					_text_c(ip + Vector2(0, 36), "SEÇİLİ", 12, Color(0.45, 0.85, 1.0), _bold)
			continue
		var tp := t.com_global()
		var to := tp - vessel.com_global()
		var dist := to.length()
		var closing := (vessel.linear_velocity - t.linear_velocity).dot(to / maxf(dist, 1.0))
		var sp: Variant = _proj(tp)
		if sp == null:
			# ekran dışı: kenarda ok
			var dir := _edge_dir(tp)
			var r := minf(c.x, c.y) - 60.0
			var p := c + dir * r
			var n := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + dir * 16, p + n * 9, p - n * 9]), col)
			_text_c(p - dir * 18 + Vector2(0, 5), "%.1f km" % (dist / 1000.0), 13, col)
			continue
		var half := clampf(9000.0 / maxf(dist, 1.0), 12.0, 44.0)
		var r2 := Rect2(sp - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(Rect2(r2.position + Vector2(1, 1), r2.size), SHADOW, false, 2.0)
		draw_rect(r2, col, false, 2.0)
		var label := "%s  %.1f km" % [t.craft_name, dist / 1000.0] if dist >= 1000.0 else "%s  %d m" % [t.craft_name, dist]
		_text_c(sp + Vector2(0, -half - 8), label, 13, col)
		_text_c(sp + Vector2(0, half + 18), "%+d km/sa" % (closing * 3.6), 12, col)
		if t == vessel.designated:
			var k := half + 5.0
			var sel := Color(0.45, 0.85, 1.0)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var cp: Vector2 = sp + Vector2(sx * k, sy * k)
					draw_line(cp, cp - Vector2(sx * 10, 0), sel, 3.0)
					draw_line(cp, cp - Vector2(0, sy * 10), sel, 3.0)
			_text_c(sp + Vector2(0, half + 34), "SEÇİLİ", 12, sel, _bold)
		if t == locked and fmod(_blink, 0.5) < 0.35:
			var d := half + 8.0
			draw_polyline(PackedVector2Array([sp + Vector2(0, -d), sp + Vector2(d, 0), sp + Vector2(0, d), sp + Vector2(-d, 0), sp + Vector2(0, -d)]), Color(1, 0.95, 0.4), 2.5, true)


# --- nişangahlar

func _gun_sight() -> void:
	var gun: GunModule = null
	for m in vessel.modules:
		if m is GunModule and m.ammo > 0:
			gun = m
			break
	if gun == null:
		return
	var mv := gun.muzzle_velocity
	var muzzle := gun.part.global_transform * gun.muzzle_local()
	var f := -gun.part.global_basis.z
	var v := vessel.linear_velocity
	var g := Planet.gravity_at(muzzle)
	# önündeki en yakın düşman (topun radarla menzil ölçmesi)
	var target: Vessel = null
	var best := 2500.0
	for e in _enemies():
		var to := e.com_global() - muzzle
		var d := to.length()
		if d < best and f.angle_to(to) < deg_to_rad(30.0):
			best = d
			target = e
	var dist := best if target else 800.0
	var t := dist / maxf(mv, 100.0)

	t = dist / (mv * (1.0 - 0.00035 * dist * 0.5))   # sürüklemeyle yavaşlamayı kaba hesaba kat
	var bullet_rel := muzzle + f * mv * t + 0.5 * g * t * t   # uçağa göre (kendi hızımız iki tarafta da var)
	var pip: Variant = _proj(bullet_rel)
	if pip != null:
		_ring(pip, 22.0, HUD_COLOR)
		draw_circle(pip, 2.5, HUD_COLOR)
		# menzil yayı (2500 m'ye göre dolu)
		if target:
			draw_arc(pip, 28.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(dist / 2500.0, 0.0, 1.0), 32, HUD_COLOR, 2.0, true)
	if target:
		var future := target.com_global() + (target.linear_velocity - v) * t
		var fp: Variant = _proj(future)
		if fp != null:
			_diamond(fp, 7.0, ENEMY)
			if pip != null and (fp as Vector2).distance_to(pip) < 22.0:
				_text_c(pip + Vector2(0, -34), "ATEŞ", 16, Color(1, 0.95, 0.4), _bold)
	_text_c(Vector2(size.x * 0.5, size.y * 0.48 + 190), "TOP  %d" % vessel.gun_ammo(), 16, HUD_COLOR, _bold)


func _missile_sight() -> void:
	var c := size * 0.5
	var nose := camera.global_position + vessel.forward() * 1000.0
	var np: Variant = _proj(nose)
	var locked := locked_target()
	var r := tan(MissileModule.SEEK_CONE) / tan(deg_to_rad(camera.fov) * 0.5) * size.y * 0.5
	if locked:
		var lp: Variant = _proj(locked.heat_position())
		if lp != null:
			_ring(lp, 26.0, Color(1, 0.95, 0.4))
		var d := locked.com_global().distance_to(vessel.com_global())
		var in_range := d > 600.0 and d < MissileModule.SEEK_RANGE * 0.85
		_text_c(Vector2(c.x, size.y * 0.48 + 170), "KİLİT  %.1f km" % (d / 1000.0), 18, Color(1, 0.95, 0.4), _bold)
		if in_range and fmod(_blink, 0.6) < 0.4:
			_text_c(Vector2(c.x, size.y * 0.48 + 194), "ATIŞ MENZİLİNDE", 15, Color(1, 0.95, 0.4), _bold)
	elif np != null:
		_ring(np, r, HUD_COLOR)
		_text_c(Vector2(c.x, size.y * 0.48 + 170), "ARAYICI — kilitsiz atış serbest", 15, HUD_COLOR)
	_text_c(Vector2(c.x, size.y * 0.48 + 214), "IR FÜZE  ×%d" % vessel.missiles_left(), 16, HUD_COLOR, _bold)


func _bomb_sight() -> void:
	var c := size * 0.5
	var vel := vessel.linear_velocity
	var fpm: Variant = _proj(camera.global_position + vel.normalized() * 1000.0) if vel.length() > 15.0 else null
	if _ccip == null:
		_text_c(Vector2(c.x, size.y * 0.48 + 170), "CCIP —", 15, HUD_COLOR)
	else:
		var impact: Vector3 = _ccip
		var ip: Variant = _proj(impact)
		var d := vessel.com_global().distance_to(impact)
		if ip != null:
			if fpm != null:
				draw_line(fpm, ip, HUD_COLOR, 1.5, true)
			_ring(ip, 14.0, HUD_COLOR)
			draw_circle(ip, 2.5, HUD_COLOR)
			# bomba yarıçapı içinde yer hedefi var mı?
			for n in vessel.get_parent().get_children():
				if n is GroundTarget and not n.destroyed and n.global_position.distance_to(impact) < Bomb.BLAST_RADIUS * 0.7:
					_text_c(ip + Vector2(0, -26), "BIRAK", 16, Color(1, 0.95, 0.4), _bold)
					break
		else:
			# düşüş noktası görüş alanının altında: aşağı ok
			var p := Vector2(c.x, size.y - 150)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, 14), p + Vector2(-10, -4), p + Vector2(10, -4)]), HUD_COLOR)
		_text_c(Vector2(c.x, size.y * 0.48 + 170), "CCIP  %.1f km" % (d / 1000.0), 15, HUD_COLOR)
	# yer hedeflerini işaretle (hedefleme podu)
	for n in vessel.get_parent().get_children():
		if n is GroundTarget and not n.destroyed:
			var gp: Variant = _proj(n.global_position)
			if gp != null and n.global_position.distance_to(vessel.com_global()) < 12000.0:
				_diamond(gp, 6.0, ENEMY)
	_text_c(Vector2(c.x, size.y * 0.48 + 194), "BOMBA  ×%d" % vessel.bombs_left(), 16, HUD_COLOR, _bold)


## Lazer güdümlü bomba: podun işaretlediği nokta, güdümsüz düşüş noktası (CCIP) ve bırakma
## bölgesi. Bomba kanatçıklarıyla düşüş noktasından işarete doğru yaklaşık irtifanın %90'ı
## kadar sapabilir (süzülme payı).
func _lgb_sight() -> void:
	var c := size * 0.5
	var y0 := size.y * 0.48 + 170
	var col := Color(1, 0.95, 0.4)
	var pod := vessel.targeting_pod()
	var spot: Variant = pod.target_point() if pod else null
	if _ccip != null:
		var ip: Variant = _proj(_ccip)
		if ip != null:
			_ring(ip, 10.0, Color(HUD_COLOR, 0.6))
	if spot == null:
		_text_c(Vector2(c.x, y0), "LAZER YOK — hedefleme podunu hedefe kilitle (F8)" if pod else "HEDEFLEME PODU YOK — güdümsüz düşer", 15, HUD_COLOR)
	else:
		var sp: Variant = _proj(spot)
		if sp != null:
			_diamond(sp, 12.0, col)
			_text_c(sp + Vector2(0, -20), "L", 14, col, _bold)
		var me := vessel.com_global()
		var up := Planet.up_at(me)
		var to: Vector3 = (spot as Vector3) - me
		var horiz := (to - up * to.dot(up)).length()
		var h_above := maxf(-to.dot(up), 0.0)
		var in_zone := false
		if _ccip != null:
			var miss: Vector3 = (spot as Vector3) - (_ccip as Vector3)
			in_zone = (miss - up * miss.dot(up)).length() < maxf(500.0, h_above * 0.9)
		_text_c(Vector2(c.x, y0), "LAZER İŞARETİ  %.1f km  ·  hedef %d m altta" % [horiz / 1000.0, roundi(h_above)], 16, col, _bold)
		if in_zone and fmod(_blink, 0.6) < 0.4:
			_text_c(Vector2(c.x, y0 + 24), "BIRAKMA BÖLGESİ — BIRAK", 16, col, _bold)
		elif not in_zone:
			_text_c(Vector2(c.x, y0 + 24), "bölge dışı — yaklaş ya da yüksel", 14, HUD_COLOR)
	_text_c(Vector2(c.x, y0 + 46), "LAZER BOMBA  ×%d" % vessel.bombs_left(true), 16, HUD_COLOR, _bold)


## Radar füzesi: seçili/izlenen hedef, atış menzili çubuğu (DLZ), kalan füze.
func _radar_missile_sight() -> void:
	var c := size * 0.5
	var t := locked_target()
	var y0 := size.y * 0.48 + 170
	var col := Color(1, 0.95, 0.4)
	# DLZ: sağda dikey çubuk, 0..20 km; geçerli atış bölgesi (1–16 km) kalın, hedef mesafesi ok
	var bar := Rect2(c.x + 250, c.y - 110, 6, 220)
	var max_km := 20.0
	var y_of := func(km: float) -> float: return bar.end.y - bar.size.y * clampf(km / max_km, 0.0, 1.0)
	draw_line(Vector2(bar.position.x, bar.position.y), Vector2(bar.position.x, bar.end.y), HUD_COLOR, 1.5)
	var lo: float = y_of.call(MissileModule.RADAR_MIN_RANGE / 1000.0)
	var hi: float = y_of.call(MissileModule.RADAR_RANGE / 1000.0)
	draw_line(Vector2(bar.position.x + 3, lo), Vector2(bar.position.x + 3, hi), HUD_COLOR, 5.0)
	for km in [5, 10, 15, 20]:
		var y: float = y_of.call(float(km))
		draw_line(Vector2(bar.position.x - 6, y), Vector2(bar.position.x, y), HUD_COLOR, 1.5)
		_text(Vector2(bar.position.x + 12, y + 5), str(km), 12, HUD_COLOR)
	if t:
		var d := t.com_global().distance_to(vessel.com_global())
		var y: float = y_of.call(d / 1000.0)
		var p := Vector2(bar.position.x - 8, y)
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(-12, -7), p + Vector2(-12, 7)]), col)
		var tp: Variant = _proj(t.com_global())
		if tp != null:
			_ring(tp, 30.0, col)
		_text_c(Vector2(c.x, y0), "RADAR İZİ  %.1f km" % (d / 1000.0), 18, col, _bold)
		if d < MissileModule.RADAR_RANGE * 0.8 and fmod(_blink, 0.6) < 0.4:
			_text_c(Vector2(c.x, y0 + 24), "ATIŞ MENZİLİNDE", 15, col, _bold)
	else:
		_text_c(Vector2(c.x, y0), "İZ YOK — F4 / tık ile radar hedefi seç", 15, HUD_COLOR)
	_text_c(Vector2(c.x, y0 + 44), "RADAR FÜZE  ×%d" % vessel.radar_missiles_left(), 16, HUD_COLOR, _bold)


## Uçuştaki kendi radar füzelerimiz: hedefe kalan süre ve evre (veri bağı / aktif / iz kayıp).
func _own_missiles(s: Vector2) -> void:
	var y := s.y * 0.48 + 260
	for mi in Missile.active:
		if mi.shooter != vessel or not mi.is_radar():
			continue
		var text := ""
		var col := HUD_COLOR
		if is_instance_valid(mi.target):
			var to: Vector3 = mi.target.com_global() - mi.global_position
			var closing: float = maxf((mi.velocity - mi.target.linear_velocity).dot(to.normalized()), 50.0)
			if mi.seeker_active:
				text = "RF  AKTİF  %d sn" % roundi(to.length() / closing)
				col = Color(1, 0.95, 0.4)
			else:
				text = "RF  VERİ BAĞI  %d sn — hedefi radarda tut" % roundi(to.length() / closing)
		else:
			text = "RF  İZ KAYIP" if not mi.seeker_active else "RF  ARIYOR"
			col = Color(1, 0.6, 0.3)
		_text_c(Vector2(s.x * 0.5, y), text, 14, col, _bold)
		y += 18


func _missile_warning(s: Vector2) -> void:
	var inc := vessel.incoming_missile()
	if inc == null:
		return
	var c := s * 0.5
	var mp := inc.global_position
	var d := mp.distance_to(vessel.com_global())
	var dir := _edge_dir(mp)
	var p := c + dir * minf(c.x, c.y) * 0.55
	var n := dir.orthogonal()
	if fmod(_blink, 0.4) < 0.28:
		draw_colored_polygon(PackedVector2Array([p + dir * 26, p + n * 14, p - n * 14]), ENEMY)
		_text_c(p - dir * 26 + Vector2(0, 6), "FÜZE %.1f km" % (d / 1000.0), 16, ENEMY, _bold)
		if inc.is_radar():
			_text_c(Vector2(c.x, s.y * 0.2), "RADAR FÜZESİ — füzeye dik dön (çentik)%s" % ("  ·  Ş: CHAFF" if vessel.chaff_left() > 0 else ""), 18, ENEMY, _bold)
		elif vessel.flares_left() > 0:
			_text_c(Vector2(c.x, s.y * 0.2), "O: FLARE AT", 18, ENEMY, _bold)


# --- RWR (radar uyarı alıcısı)
# Uçağı tarayan / kilitlenen radarları ve kendi radarı açık füzeleri yön olarak gösterir.
# Burun yukarıda; merkeze yakın = daha tehlikeli. S: SAM, F: avcı, M: aktif radar füzesi.
# Seviye: 0 arama (yeşil), 1 kilit (sarı), 2 atış / füze (kırmızı, yanıp söner).

const RWR_R := 70.0
var _rwr: Array = []              ## [{pos, sym, level, key}]
var _rwr_scan := 0.0
var _rwr_levels := {}             ## key -> son seviye (yeni tehdit sesi için)
var _rwr_beep := 0.0
var _seen := false                ## herhangi bir düşman sensörü bizi görüyor (Detection.is_seen)


func _has_rwr() -> bool:
	return vessel.radar() != null or not vessel.available_weapons().is_empty()


func _update_rwr(delta: float) -> void:
	_rwr_scan -= delta
	_rwr_beep -= delta
	if not _ok() or not vessel.has_power() or not _has_rwr():
		_rwr.clear()
		return
	if _rwr_scan <= 0.0:
		_rwr_scan = 0.2
		_scan_rwr()
	var top := -1
	for th in _rwr:
		top = maxi(top, th["level"])
	# kilit: yavaş çift bip; atış: füze uyarısı zaten hızlı bip çalar
	if top == 1 and _rwr_beep <= 0.0:
		_rwr_beep = 0.9
		Sfx.play_ui("caution_beep.ogg", -10.0, 1.15)


func _scan_rwr() -> void:
	var me := vessel.com_global()
	var out: Array = []
	_seen = Detection.is_seen(vessel)
	# RWR yayını pasif dinler: radarın kapsamındaysan (seni göremese bile) sembolü çıkar
	for site in SamSite.sites:
		if not site.is_inside_tree() or site.team == vessel.team or not site.emitting():
			continue
		var ep := site.emitter_position()
		if ep.distance_to(me) > site.detect_range() * 1.3 or not Missile.terrain_clear(ep, me):
			continue
		var lvl := 1 if site.tracking() == vessel else 0
		out.append({"pos": site.global_position, "sym": "S+" if site.long_range else "S", "level": lvl, "key": site.get_instance_id()})
	for st in RadarStation.stations:
		if not st.is_inside_tree() or st.team == vessel.team or not st.emitting() or st.unit_name.begins_with("SAM"):
			continue
		var ep2 := st.emitter_position()
		if ep2.distance_to(me) < st.range_m * 1.2 and Missile.terrain_clear(ep2, me):
			out.append({"pos": st.global_position, "sym": "EW", "level": 0, "key": st.get_instance_id()})
	for sh in Warship.ships:
		if is_instance_valid(sh) and not sh.destroyed and sh.team != vessel.team and sh.global_position.distance_to(me) < Warship.RADAR_RANGE * 1.2:
			out.append({"pos": sh.global_position, "sym": "G", "level": 1 if sh.tracking() == vessel else 0, "key": sh.get_instance_id()})
	for n in vessel.get_parent().get_children():
		if not n is Vessel or n == vessel or n.parts.is_empty() or n.team == vessel.team or not n.has_power():
			continue
		var r: RadarModule = n.radar()
		if r == null or not vessel in r.contacts:
			# radarı seni görmese de karıştırma yayını çok uzaktan duyulur
			if n.jamming() and n.com_global().distance_to(me) < EcmModule.EMIT_RANGE:
				out.append({"pos": n.com_global(), "sym": "J", "level": 0, "key": n.get_instance_id()})
			continue
		var lvl := 0
		for m in n.modules:
			if m is MissileModule and m.radar_guided and m.target == vessel:
				lvl = 1
		out.append({"pos": n.com_global(), "sym": "A" if n.has_meta("awacs") else "F", "level": lvl, "key": n.get_instance_id()})
	for mi in Missile.active:
		if not mi.is_radar() or mi.victim != vessel or not is_instance_valid(mi.target):
			continue
		if mi.seeker_active:
			out.append({"pos": mi.global_position, "sym": "M", "level": 2, "key": mi.get_instance_id()})
		else:
			# yarı aktif evre: fırlatanın sembolü "atış" olur
			for th in out:
				if is_instance_valid(mi.launcher) and th["key"] == mi.launcher.get_instance_id():
					th["level"] = 2
	# yeni tehdit ya da seviye artışı: kısa ton
	var seen := {}
	for th in out:
		seen[th["key"]] = th["level"]
		if th["level"] > int(_rwr_levels.get(th["key"], -1)):
			Sfx.play_ui("lock_tone.ogg" if th["level"] == 0 else "caution_beep.ogg", -12.0 if th["level"] == 0 else -6.0, 0.7 if th["level"] == 0 else 1.4)
			if th["level"] == 1:
				var who: String = {"S": "SAM", "S+": "UZUN MENZİLLİ SAM", "G": "GEMİ", "A": "AWACS"}.get(th["sym"], "AVCI RADAR")
				vessel.system_message.emit("RWR: %s KİLİDİ" % who)
	_rwr_levels = seen
	_rwr = out


func _draw_rwr(s: Vector2) -> void:
	var c := Vector2((s.x + Hud.PFD_W) * 0.5 + RWR_R + 22.0, s.y - RWR_R - 26.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.04, 0.03, 0.78)
	bg.set_corner_radius_all(int(RWR_R + 10))
	bg.border_color = Color(1, 1, 1, 0.14)
	bg.set_border_width_all(1)
	draw_style_box(bg, Rect2(c - Vector2.ONE * (RWR_R + 10), Vector2.ONE * (RWR_R + 10) * 2.0))
	var grid := Color(0.4, 1.0, 0.6, 0.22)
	for k in [0.33, 0.66, 1.0]:
		draw_arc(c, RWR_R * k, 0.0, TAU, 48, grid, 1.0, true)
	for a in 12:
		var dir := Vector2.from_angle(a * TAU / 12.0)
		draw_line(c + dir * RWR_R * (0.92 if a % 3 else 0.85), c + dir * RWR_R, grid, 1.5)
	# kendi uçak işareti
	draw_line(c + Vector2(0, -7), c + Vector2(0, 7), HUD_COLOR, 2.0)
	draw_line(c + Vector2(-6, -1), c + Vector2(6, -1), HUD_COLOR, 2.0)
	_text_c(c + Vector2(0, -RWR_R - 14), "RWR", 11, Color(0.6, 0.75, 0.7), _bold)
	# görünürlük ışığı: herhangi bir düşman radarı / gözcü / veri bağı seni görüyor mu
	var vis := Rect2(c + Vector2(-58, -RWR_R - 46), Vector2(116, 20))
	var vcol := Color(1.0, 0.45, 0.25) if _seen else Color(0.35, 0.9, 0.5)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(vcol, 0.18 if not _seen or fmod(_blink, 0.8) < 0.5 else 0.35)
	vs.border_color = vcol
	vs.set_border_width_all(1)
	vs.set_corner_radius_all(4)
	draw_style_box(vs, vis)
	_text_c(vis.get_center() + Vector2(0, 5), "GÖRÜNÜYORSUN" if _seen else "GİZLİ", 12, vcol, _bold)
	if vessel.jamming():
		_text(c + Vector2(RWR_R - 18, -RWR_R + 2), "ECM", 11, Color(0.45, 0.85, 1.0), _bold)
	if not vessel.radar_on and vessel.radar() != null:
		_text(c + Vector2(-RWR_R - 4, -RWR_R + 2), "SESSİZ", 11, Color(1.0, 0.8, 0.35), _bold)
	if _rwr.is_empty():
		return
	var inv := vessel.global_basis.inverse()
	var top := 0
	var me := vessel.com_global()
	for th in _rwr:
		top = maxi(top, th["level"])
		var local: Vector3 = inv * (th["pos"] - me)
		var dir := Vector2(local.x, local.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.UP
		var dist := (th["pos"] as Vector3).distance_to(me)
		var rr := RWR_R * clampf(lerpf(0.3, 0.92, dist / 20000.0) - 0.12 * float(th["level"]), 0.18, 0.92)
		var p := c + dir * rr
		var lvl: int = th["level"]
		var col := [Color(0.4, 1.0, 0.6), Color(1.0, 0.85, 0.3), ENEMY][lvl] as Color
		if lvl == 2 and fmod(_blink, 0.3) > 0.18:
			continue
		_text_c(p + Vector2(0, 6), th["sym"], 17, col, _bold)
		if lvl >= 1:
			_diamond(p, 13.0, col)
		if lvl == 2:
			_ring(p, 17.0, col)
	var label := ["ARAMA", "KİLİT", "ATIŞ"][top] as String
	var lcol := [Color(0.4, 1.0, 0.6), Color(1.0, 0.85, 0.3), ENEMY][top] as Color
	_text_c(c + Vector2(0, RWR_R + 22), label, 13, lcol, _bold)


# --- paneller

func _weapon_panel(s: Vector2) -> void:
	var r := Rect2(18, s.y - 122 - 18 - 44, 360, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.72)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	var arm := vessel.master_arm
	var pill := Rect2(r.position + Vector2(8, 7), Vector2(74, 22))
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.75, 0.15, 0.1, 0.9) if arm else Color(1, 1, 1, 0.08)
	ps.set_corner_radius_all(11)
	draw_style_box(ps, pill)
	_text_c(pill.position + Vector2(37, 16), "ARM" if arm else "EMNİYET", 12, Color.WHITE if arm else Color(0.7, 0.75, 0.8), _bold)
	var items := []
	for kind in vessel.available_weapons():
		var count := [vessel.gun_ammo(), vessel.missiles_left(), vessel.bombs_left()][kind] as int
		items.append([["TOP", "FÜZE", "BOMBA"][kind], count, kind == vessel.selected_weapon])
	var x := pill.end.x + 12
	for it in items:
		var txt := "%s %d" % [it[0], it[1]]
		var col := Color(0.45, 1.0, 0.65) if it[2] else Color(0.62, 0.7, 0.76)
		_text(Vector2(x, r.position.y + 23), txt, 14 if it[2] else 13, col, _bold if it[2] else _font)
		x += _bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14
	if vessel.flares_left() > 0 or _has_flares():
		_text(Vector2(x, r.position.y + 23), "FLARE %d" % vessel.flares_left(), 13, Color(1.0, 0.8, 0.45), _font)


func _has_flares() -> bool:
	for m in vessel.modules:
		if m is FlareModule:
			return true
	return false


## PPI radar ekranı: burun yönü yukarı, koni içindeki temaslar, menzil halkaları.
func _radar_scope(s: Vector2) -> void:
	var radar := vessel.radar()
	if radar == null:
		return
	var w := 230.0
	var h := 166.0
	var r := Rect2(390, s.y - h - 18, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.04, 0.8)
	sb.border_color = Color(0.45, 1.0, 0.65, 0.25)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(10)
	draw_style_box(sb, r)
	var green := Color(0.4, 1.0, 0.55)
	_text(r.position + Vector2(10, 18), "RADAR", 11, Color(0.62, 0.7, 0.76), _bold)
	var rng := radar.range_m
	_text(r.position + Vector2(w - 70, 18), "%d km" % (rng / 1000.0), 11, Color(0.62, 0.7, 0.76), _bold)
	var origin := Vector2(r.position.x + w * 0.5, r.end.y - 10)
	var R := h - 34.0
	if not vessel.has_power():
		_text_c(origin + Vector2(0, -R * 0.5), "GÜÇ YOK", 14, Color(1, 0.5, 0.4), _bold)
		return
	var cone := radar.cone
	for k in [0.33, 0.66, 1.0]:
		draw_arc(origin, R * k, -PI * 0.5 - cone, -PI * 0.5 + cone, 24, Color(green, 0.22), 1.0, true)
	for a in [-cone, 0.0, cone]:
		draw_line(origin, origin + Vector2(sin(a), -cos(a)) * R, Color(green, 0.18), 1.0)
	# tarama çizgisi
	var sweep := sin(_blink * 1.6) * cone
	draw_line(origin, origin + Vector2(sin(sweep), -cos(sweep)) * R, Color(green, 0.45), 1.5, true)
	# temaslar: uçağın yatay düzlemine göre kerteriz
	var basis := Planet.local_basis(vessel.global_position)
	var hdg := deg_to_rad(vessel.heading_deg())
	for t in radar.contacts:
		if not is_instance_valid(t):
			continue
		var to := t.com_global() - vessel.com_global()
		var lx := to.dot(basis.x)
		var ln := -to.dot(basis.z)
		var bearing := atan2(lx, ln) - hdg
		bearing = wrapf(bearing, -PI, PI)
		var horiz := Vector2(lx, ln).length()
		var p := origin + Vector2(sin(bearing), -cos(bearing)) * R * clampf(horiz / rng, 0.0, 1.0)
		var col := FRIEND if t.team == vessel.team else (Color(0.72, 0.75, 0.78) if t.team == "sivil" else ENEMY)
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
		var dalt := t.altitude() - vessel.altitude()
		_text(p + Vector2(7, 4), "%+.1f" % (dalt / 1000.0), 10, col)
		if t == locked_target():
			draw_arc(p, 8.0, 0, TAU, 16, Color(1, 0.95, 0.4), 1.5)
	# bize gelen füzeler
	for mi in Missile.active:
		if mi.victim == vessel:
			var to := mi.global_position - vessel.com_global()
			var b := wrapf(atan2(to.dot(basis.x), -to.dot(basis.z)) - hdg, -PI, PI)
			var horiz := Vector2(to.dot(basis.x), to.dot(basis.z)).length()
			var p := origin + Vector2(sin(b), -cos(b)) * R * clampf(horiz / rng, 0.0, 1.0)
			draw_line(p - Vector2(5, 5), p + Vector2(5, 5), ENEMY, 2.0)
			draw_line(p - Vector2(5, -5), p + Vector2(5, -5), ENEMY, 2.0)
	draw_circle(origin, 3.0, green)


# --- çizim yardımcıları

func _ring(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c + Vector2(1, 1), r, 0, TAU, 40, SHADOW, 2.0)
	draw_arc(c, r, 0, TAU, 40, col, 2.0, true)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 2.0, true)


func _text(pos: Vector2, text: String, sz: int, col: Color, font: Font = null) -> void:
	var f := font if font else _font
	draw_string(f, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, SHADOW)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_c(pos: Vector2, text: String, sz: int, col: Color, font: Font = null) -> void:
	var f := font if font else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_text(pos - Vector2(w * 0.5, 0), text, sz, col, f)


## Kargo: sandık şimdi bırakılsa ineceği yer (her görünümde).
func _cargo_sight() -> void:
	if _ccip == null:
		return
	var impact: Vector3 = _ccip
	var col := Color(1.0, 0.85, 0.35)
	var ip: Variant = _proj(impact)
	var d := vessel.com_global().distance_to(impact)
	if ip != null:
		_ring(ip, 16.0, col)
		draw_line(ip - Vector2(24, 0), ip - Vector2(10, 0), col, 2.0)
		draw_line(ip + Vector2(24, 0), ip + Vector2(10, 0), col, 2.0)
		_text_c(ip + Vector2(0, -24), "KARGO  %.1f km" % (d / 1000.0), 13, col, _bold)
	else:
		_text_c(Vector2(size.x * 0.5, size.y - 190), "KARGO iniş noktası görüş dışında (%.1f km)" % (d / 1000.0), 14, col, _bold)
