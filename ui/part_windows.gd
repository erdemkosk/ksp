class_name PartWindows
extends Control
## KSP'deki parça pencereleri: dış kamerada bir parçaya SAĞ TIK (sürüklemeden) → o parçanın
## canlı bilgi penceresi açılır (sağlık, yapı yükü, kütle, modül durumları) ve modüle göre
## düğmeler (motor çalıştır/durdur, iniş takımı aç/kapa, ...). Aynı parçaya tekrar sağ tık kapatır.
## Fare üstüne geldiği parça hafifçe parlar; birden çok pencere açık kalabilir, sürüklenebilir.

const CLICK_SLOP := 6.0

var camera: FlightCamera
var theme_res: Theme

var _windows := {}           # Part -> {window, info, hp, stress, buttons}
var _press_pos := Vector2.ZERO
var _press_valid := false
var _hover: Part
var _hover_mat: StandardMaterial3D
var _open_mat: StandardMaterial3D
var _last_mouse := Vector2(-1, -1)
var _hover_cd := 0.0
var _label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_mat = _overlay(Color(0.35, 0.75, 1.0, 0.45))
	_open_mat = _overlay(Color(0.3, 1.0, 0.55, 0.22))
	_label = Label.new()
	_label.theme = UiTheme.get_theme()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 5)
	_label.visible = false
	add_child(_label)
	if Game.args.has("partwin"):
		demo_open.call_deferred()


func _overlay(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	return m


func _active() -> bool:
	return is_instance_valid(camera) and not camera.is_eva() and camera.mode != FlightCamera.Mode.COCKPIT


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_press_pos = event.position
			_press_valid = true
		elif _press_valid:
			_press_valid = false
			if event.position.distance_to(_press_pos) < CLICK_SLOP and _active():
				var part := _part_at(event.position)
				if part:
					_toggle(part)
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _press_valid:
		if event.position.distance_to(_press_pos) >= CLICK_SLOP:
			_press_valid = false


func _part_at(mouse: Vector2) -> Part:
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 3000.0
	if is_instance_valid(camera.target) and camera.target.is_inside_tree():
		var own := camera.target.pick_part(from, to)
		if own:
			return own
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider is Vessel:
		return null
	return (hit.collider as Vessel).part_for_shape(hit.shape)


func _process(delta: float) -> void:
	# üzerine gelme vurgusu: üçgen hassas seçim pahalı, yalnız fare kıpırdayınca (saniyede ≤12)
	var h: Part = _hover
	var mp := get_viewport().get_mouse_position()
	_hover_cd -= delta
	if not _active() or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or get_viewport().gui_get_hovered_control() != null:
		h = null
	elif _hover_cd <= 0.0 and mp.distance_to(_last_mouse) > 1.0:
		_hover_cd = 0.08
		_last_mouse = mp
		h = _part_at(mp)
	_label.visible = is_instance_valid(h)
	if _label.visible:
		_label.text = h.title + "  ·  sağ tık"
		_label.position = mp + Vector2(18, 10)
	if h != _hover:
		_set_overlay(_hover, null)
		_hover = h
		_set_overlay(_hover, _hover_mat)
	for part in _windows.keys():
		var d: Dictionary = _windows[part]
		if not is_instance_valid(part) or not part.is_inside_tree() or part.get_parent() is Debris:
			(d["window"] as UiWindow).queue_free()
			_windows.erase(part)
			continue
		_refresh(part, d)


func _toggle(part: Part) -> void:
	if _windows.has(part):
		_close(part)
		return
	Sfx.click()
	var side := "" if absf(part.position.x) < 0.3 else ("  (SAĞ)" if part.position.x > 0.0 else "  (SOL)")
	var w := UiWindow.create(part.title.to_upper() + side, theme_res)
	w.custom_minimum_size.x = 250
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 13)
	w.body.add_child(info)
	var hp := _bar(w.body, "Sağlık", Color(0.35, 0.9, 0.45))
	var stress := _bar(w.body, "Yapı yükü", Color(1.0, 0.7, 0.2))
	var buttons := {}
	var row := HFlowContainer.new()
	w.body.add_child(row)
	for m in part.modules:
		if m is EngineModule:
			buttons["engine"] = _button(row, "Motor", func() -> void:
				if m.is_running() or m.state == EngineModule.State.CRANKING:
					m.shutdown()
				elif not m.start():
					part.vessel.system_message.emit("Marş için batarya + JFS gerekli"))
			if not m.prop and not m.rocket:
				buttons["ab"] = _button(row, "AB", func() -> void: m.no_ab = not m.no_ab)
			_slider(w.body, "İtki sınırı", m.thrust_limit, func(x: float) -> void: m.thrust_limit = x)
		elif m is ControlSurfaceModule:
			# hangi eksene çalışsın (KSP'deki gibi): yunuslama / yatış / sapma
			for ax in [["Yunus", 0], ["Yatış", 2], ["Sapma", 1]]:
				var i: int = ax[1]
				buttons["axis%d" % i] = _button(row, ax[0], func() -> void:
					var mask: Vector3 = m.axis_mask
					mask[i] = 0.0 if mask[i] > 0.5 else 1.0
					m.axis_mask = mask)
		elif m is CockpitModule:
			buttons["canopy"] = _button(row, "Kanopi", func() -> void: m.canopy_open = not m.canopy_open)
			buttons["lights"] = _button(row, "Işıklar", func() -> void: part.vessel.lights_on = not part.vessel.lights_on)
		elif m is LandingGearModule and not buttons.has("gear"):
			buttons["gear"] = _button(row, "Takım", func() -> void:
				part.vessel.gear_down = not part.vessel.gear_down)
		elif m is EcmModule:
			buttons["ecm"] = _button(row, "ECM", func() -> void:
				m.enabled = not m.enabled)
		elif m is RadarModule:
			buttons["radar"] = _button(row, "Radar", func() -> void:
				part.vessel.radar_on = not part.vessel.radar_on)
		# KSP gibi parçaya özel işlemler
		elif m is RampModule:
			buttons["ramp"] = _button(row, "Rampa", func() -> void: m.toggle())
		elif m is CargoModule:
			buttons["cargo"] = _button(row, "Sandık bırak", func() -> void:
				if m.crates > 0:
					m.release())
			buttons["cargo_all"] = _button(row, "Yükü boşalt", func() -> void:
				_unload(part, m))
		elif m is FuelTankModule and not buttons.has("dump"):
			buttons["dump"] = _button(row, "Yakıt at", func() -> void:
				part.vessel.fuel_dumping = not part.vessel.fuel_dumping)
		elif m is ChuteModule:
			buttons["chute"] = _button(row, "Paraşüt", func() -> void:
				if m.state == 0:
					m.deploy()
				else:
					m.release())
		elif m is BombModule:
			buttons["bomb"] = _button(row, "Bırak", func() -> void:
				if m.loaded:
					m.release())
	w.closed.connect(func() -> void: _close(part))
	add_child(w)
	var mouse := get_viewport().get_mouse_position()
	# katmanın kendi boyutu 0 kalabiliyordu (pencere ekran dışında, -270,-260'ta açılıyordu): ekran boyutu
	var screen := get_viewport().get_visible_rect().size
	w.position = (mouse + Vector2(24, -40)).clamp(Vector2(8, 60), screen - Vector2(270, 260))
	_windows[part] = {"window": w, "info": info, "hp": hp, "stress": stress, "buttons": buttons}
	_set_overlay(part, _hover_mat if part == _hover else null)   # açık pencere parçayı boyamaz (yeşil iz kalıyordu)
	_refresh(part, _windows[part])

## Bölmedeki bütün sandıkları sırayla (0.35 sn arayla) bırak; rampa varsa önce açılır.
func _unload(part: Part, m: CargoModule) -> void:
	if m.crates <= 0:
		part.vessel.system_message.emit("Bölme boş")
		return
	for r in part.vessel.modules:
		if r is RampModule and not r.open:
			r.toggle()
	while is_instance_valid(part) and is_instance_valid(m) and m.crates > 0 and part.vessel != null:
		m.release()
		await get_tree().create_timer(0.35).timeout


func _close(part: Part) -> void:
	if not _windows.has(part):
		return
	(_windows[part]["window"] as UiWindow).queue_free()
	_windows.erase(part)
	if is_instance_valid(part):
		_set_overlay(part, _hover_mat if part == _hover else null)


func _bar(parent: Control, title: String, color: Color) -> ProgressBar:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	parent.add_child(l)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(230, 12)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)
	parent.add_child(b)
	return b


## Yüzde kaydırıcı (%10–100): başlık + değer etiketi.
func _slider(parent: Control, title: String, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	l.custom_minimum_size.x = 120
	var s := HSlider.new()
	s.min_value = 0.1
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size.x = 110
	s.focus_mode = Control.FOCUS_NONE
	l.text = "%s  %%%d" % [title, value * 100.0]
	s.value_changed.connect(func(x: float) -> void:
		l.text = "%s  %%%d" % [title, x * 100.0]
		cb.call(x))
	row.add_child(l)
	row.add_child(s)
	parent.add_child(row)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		Sfx.click()
		cb.call())
	parent.add_child(b)
	return b


func _refresh(part: Part, d: Dictionary) -> void:
	var v := part.vessel
	var lines := PackedStringArray()
	lines.append("Kütle  %d kg" % part.get_mass())
	lines.append("Hasar  %d / %d HP" % [part.hp, part.max_hp])
	lines.append("Yük    %d kN / %d kN" % [part.aero_load.length() / 1000.0, part.strength / 1000.0])
	if part.submerged > 0.01:
		lines.append("Suda   %%%d" % (part.submerged * 100.0))
	for m in part.modules:
		if m is EngineModule:
			var st: String = ["KAPALI", "MARŞ", "ÇALIŞIYOR"][m.state]
			if m.flameout:
				st = "SÖNDÜ (yakıt yok)"
			lines.append("Motor  %s · N2 %%%d" % [st, m.n2 * 100.0])
			lines.append("İtki   %d kN%s" % [m.thrust / 1000.0, "  · AB" if m.afterburner > 0.05 else ""])
			var b: Button = d["buttons"].get("engine")
			if b:
				b.text = "Motoru durdur" if m.state != EngineModule.State.OFF else "Motoru çalıştır"
			var ab: Button = d["buttons"].get("ab")
			if ab:
				ab.text = "Art yakıcı: KİLİTLİ" if m.no_ab else "Art yakıcı: serbest"
		elif m is FuelTankModule:
			lines.append("Yakıt  %d / %d kg%s" % [m.fuel, m.capacity, "  · ATILIYOR" if v.fuel_dumping else ""])
			var db: Button = d["buttons"].get("dump")
			if db:
				db.text = "Yakıt atmayı durdur" if v.fuel_dumping else "Yakıt at"
		elif m is RampModule:
			var rs: String = "AÇIK" if m.deploy >= 0.99 else ("KAPALI" if m.deploy <= 0.01 else "hareket ediyor %%%d" % (m.deploy * 100.0))
			lines.append("Rampa  %s" % rs)
			var rb2: Button = d["buttons"].get("ramp")
			if rb2:
				rb2.text = "Rampayı kapat" if m.open else "Rampayı aç"
		elif m is CargoModule:
			lines.append("Kargo  %d sandık (%d kg)" % [m.crates, m.extra_mass()])
			for k in ["cargo", "cargo_all"]:
				var cb: Button = d["buttons"].get(k)
				if cb:
					cb.disabled = m.crates <= 0
		elif m is ChuteModule:
			lines.append("Paraşüt  %s" % ["paketli", "AÇIK", "kesildi"][m.state])
			var pb: Button = d["buttons"].get("chute")
			if pb:
				pb.text = ["Paraşütü aç", "Paraşütü kes", "Paraşüt kullanıldı"][m.state]
				pb.disabled = m.state == 2
		elif m is ControlSurfaceModule:
			lines.append("Kanatçık  %+.1f°" % rad_to_deg(m.deflection))
			for ax in [["Yunus", 0], ["Yatış", 2], ["Sapma", 1]]:
				var axb: Button = d["buttons"].get("axis%d" % ax[1])
				if axb:
					axb.text = ("✓ " if m.axis_mask[ax[1]] > 0.5 else "✗ ") + String(ax[0])
		elif m is WingModule:
			lines.append("Kaldırma  %.1f kN%s" % [m.last_lift.length() / 1000.0, "  · STALL" if m.stalled else ""])
			lines.append("Hücum açısı  %+.1f°" % rad_to_deg(m.last_aoa))
		elif m is LandingGearModule:
			var gs: String = "AÇIK" if m.deploy >= 0.99 else ("KAPALI" if m.deploy <= 0.01 else "hareket ediyor %%%d" % (m.deploy * 100.0))
			lines.append("Takım  %s%s" % [gs, " · yerde" if m.grounded else ""])
			var gb: Button = d["buttons"].get("gear")
			if gb:
				gb.text = "Takımı topla" if v.gear_down else "Takımı indir"
		elif m is GunModule:
			lines.append("Top    %d mermi" % m.ammo)
		elif m is MissileModule:
			var tgt: String = "  · hedef: " + m.target.craft_name if m.loaded and is_instance_valid(m.target) else ""
			lines.append("%s   %s%s" % ["Radar füze" if m.radar_guided else "IR füze", "HAZIR" if m.loaded else "ATILDI", tgt])
		elif m is RadarModule:
			lines.append("Radar  %d km · %d temas%s%s" % [m.range_m / 1000.0, m.contacts.size(), "" if v.has_power() else " · GÜÇ YOK", "" if v.radar_on else " · SESSİZ"])
			var rb: Button = d["buttons"].get("radar")
			if rb:
				rb.text = "Radarı kapat (sessiz)" if v.radar_on else "Radarı aç"
		elif m is EcmModule:
			lines.append("ECM    %s" % ("KARIŞTIRIYOR" if m.active() else ("KAPALI" if not m.enabled else "GÜÇ YOK / HASARLI")))
			var eb: Button = d["buttons"].get("ecm")
			if eb:
				eb.text = "ECM kapat" if m.enabled else "ECM aç"
		elif m is IrstModule:
			lines.append("IRST   %d km · %d ısı teması" % [m.range_m / 1000.0, m.contacts.size()])
		elif m is RefuelProbeModule:
			lines.append("Prob   %s · alınan %d kg" % ["BAĞLI" if m.connected() else "hazır", m.received])
		elif m is BombModule:
			lines.append("%s   %s" % ["Lazer bomba" if m.guided else "Bomba", "TAKILI" if m.loaded else "BIRAKILDI"])
			var bb: Button = d["buttons"].get("bomb")
			if bb:
				bb.disabled = not m.loaded
		elif m is CockpitModule:
			lines.append("Pilot  %s" % ("içeride" if v.has_pilot() else "yok"))
			var cb2: Button = d["buttons"].get("canopy")
			if cb2:
				cb2.text = "Kanopiyi kapat" if m.canopy_open else "Kanopiyi aç"
			var lb: Button = d["buttons"].get("lights")
			if lb:
				lb.text = "Işıkları kapat" if v.lights_on else "Işıkları aç"
	(d["info"] as Label).text = "\n".join(lines)
	(d["hp"] as ProgressBar).value = 100.0 * part.health_ratio()
	(d["stress"] as ProgressBar).value = 100.0 * clampf(part.stress, 0.0, 1.0)


func _set_overlay(part: Part, mat: Material) -> void:
	if not is_instance_valid(part):
		return
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is GPUParticles3D or n is PuffTrail:
			continue
		if n is MeshInstance3D and not n.get_parent() is CockpitSwitch:
			# saydam efektler (alev, ısı dalgası, cam) vurgulanmaz: motorun arkasında yeşil koni çıkıyordu
			var mo: Material = n.material_override
			if mo is ShaderMaterial and not mo.has_meta("paint"):
				continue
			if mo is StandardMaterial3D and (mo.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mo.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
				continue
			n.material_overlay = mat if mat else part.damage_overlay


## --partwin: test/ekran görüntüsü için motor ve kanat pencerelerini aç.
func demo_open() -> void:
	await get_tree().create_timer(1.5).timeout
	var v := camera.target
	for p in v.parts:
		if p.part_id in ["jet_engine", "wing_main"] and not _windows.has(p):
			_toggle(p)
			_windows[p]["window"].position = Vector2(420 + _windows.size() * 280, 300)
