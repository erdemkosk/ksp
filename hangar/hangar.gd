extends Node3D
## Hangar: parçalardan uçak tasarlama (KSP'deki uçak yapım binası gibi).
##
## Solda parça paleti → bir parça seç → yarı saydam hayaleti fareyi izler:
##   gövde parçaları (kokpit, tank, motor, burun) uçtan uca eksen boyunca eklenir,
##   kanat/kontrol yüzeyleri yan yüzeye (yatay) ya da üst yüzeye (dikey kuyruk) takılır,
##   iniş takımı ve silahlar alta asılır. Simetri açıkken karşı tarafa ayna kopya eklenir.
## Sol tık: yerleştir / takılı parçayı tutup taşı · Sağ tık ya da Del: sil · X: simetri
## R: döndür · Shift+tekerlek ya da [ ]: büyüt/küçült · Ctrl+Z / Ctrl+Y: geri al / yinele
## Ctrl+S: kaydet · F: kamerayı uçağa ortala · Esc: iptal
## Sağda: kütle, itki/ağırlık, kanat alanı, maliyet, ağırlık merkezi (sarı) ve kaldırma
## merkezi (mavi) işaretleri, kararlılık ve uyarılar. Kaydet / Yükle / PİSTE ÇIK.

const CATEGORY_ORDER := ["kokpit", "gövde", "sensör", "motor", "hava alığı", "kanat", "kontrol", "fren", "iniş takımı", "silah", "savunma", "harici"]
const AXIAL := ["kokpit", "gövde", "sensör", "motor"]
const CRAFT_HEIGHT := 3.4
const USER_DIR := "user://crafts/"
const DEFAULT_CRAFT := "res://crafts/kartal_1.json"
const SNAP := 0.05
const CENTER_SNAP := 0.35
const ANGLE_STEPS := [5.0, 15.0, 30.0, 45.0, 90.0]

var craft := {"name": "Yeni Uçak", "parts": [], "units": PartLibrary.WORLD_SCALE}
var symmetry := true

var _craft_root: Node3D
var _preview: Vessel
var _part_entry := {}            # Part -> craft.parts indeksi
var _selected := ""              # paletteki seçili parça kimliği
var _user_rot := Vector3.ZERO     # W/S, A/D, Q/E ile eklenen dönüş (derece, parçanın kendi eksenlerinde)
var _angle_step := 15.0
var _ghost: Node3D
var _ghost_mirror: Node3D
var _ghost_mat: StandardMaterial3D
var _placement := {}             # {pos, rot, ok}
var _scale := 1.0                # seçili parçanın ölçeği
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _hover_part: Part
var _hover_mat: StandardMaterial3D
var _hover_label: Label
var _place_label: Label
var _help_panel: Control
var _rmb_pos := Vector2.ZERO
var _rmb_click := false
var _nodes: Array[Dictionary] = []      # boştaki bağlantı noktaları {pos, dir, part}
var _node_markers: Array[MeshInstance3D] = []
var _node_mat: StandardMaterial3D
var _part_panel: UiWindow
var _panel_index := -1                  # açık paneldeki kaydın indeksi
var _search: LineEdit
var _cards := {}                 # id -> kart (Button)
var _cat_boxes := {}             # kategori -> [başlık, ızgara]
var _com_marker: MeshInstance3D
var _col_marker: MeshInstance3D
# parça ağacı ve araçlar (KSP: 1 yerleştir · 2 kaydır · 3 döndür · 4 kök)
var _part_copy := {}             # Part -> kaydın kaçıncı simetri kopyası
var _held: Array = []            # elde taşınan grup (kök + alt ağaç kayıtları); boşsa tek parça
var _held_root_xf := Transform3D.IDENTITY   # grubun kökünün tutulmadan önceki dönüşümü
var _held_restore: Dictionary = {}          # tutmadan önceki tasarım (Esc ile geri koy)
var _ghost_nodes := {}           # "üye:kopya" -> hayalet düğüm
var _sym_mode := "mirror"        # "mirror" ya da "radial"
var _radial := 4                 # radyal simetride kopya sayısı
var _tool := 1
var _gizmo: HangarGizmo
var _giz_uid := -1               # tutamaçların bağlı olduğu kayıt
var _giz_copy := 0
var _drag_axis := -1
var _drag_from := Vector2.ZERO
var _drag_base: Dictionary = {}  # sürükleme başında tasarım
var _drag_val := 0.0
var _tool_btns: Array[Button] = []

var _cam: Camera3D
var _yaw := deg_to_rad(-35.0)
var _pitch := deg_to_rad(18.0)
var _dist := 22.0
var _target := Vector3(0, 2.0, -2.0)

var _theme: Theme
var _name_edit: LineEdit
var _stats: Label
var _warn: RichTextLabel
var _dash: DesignDashboard          ## görsel tasarım panosu (hangar/design_dashboard.gd)
var _sym_check: CheckButton
var _load_popup: PopupPanel
var _load_list: VBoxContainer
var _status: Label
var _time := 0.0
var _mcheck: MissionCheck        ## görev kartı + canlı kontrol listesi (görev hazırlığında)


func _ready() -> void:
	# uçuş/test argümanlarıyla açıldıysa doğrudan uçuşa geç
	if not Game.args.is_empty() and not Game.args.has("hangar"):
		get_tree().change_scene_to_file.call_deferred("res://main.tscn")
		return
	TerrainGen.init()
	FloatingOrigin.world_root = self
	FloatingOrigin.offset_x = 0.0
	FloatingOrigin.offset_y = 0.0
	FloatingOrigin.offset_z = 0.0
	Planet.reset()

	_build_environment()
	_craft_root = Node3D.new()
	_craft_root.name = "Craft"
	_craft_root.position = Vector3(0, CRAFT_HEIGHT, 0)
	add_child(_craft_root)
	_build_markers()
	_gizmo = HangarGizmo.new()
	_gizmo.name = "Gizmo"
	_craft_root.add_child(_gizmo)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.1
	_cam.far = 500.0
	add_child(_cam)

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.35)
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hover_mat.albedo_color = Color(0.25, 0.6, 1.0, 0.35)

	if Game.args.has("opprep"):   # test: "Göreve çık" ile gelinmiş gibi aç
		Game.pending_op = {"mission": String(Game.args["opprep"]) if Game.args["opprep"] is String else "kara", "region": "sahil", "combat": true}
		if Game.args.has("cardtest"):   # örnek görev kartı (görev üreticisi sözleşmesi)
			Game.pending_op["card"] = MissionCheck.sample_card()
	Game.rehearsal = false          # provadan dönüldü: hazırlık (pending_op) sürer
	_build_ui()
	var life := HangarLife.new()     # teknisyenler, alet arabası, merdiven; F12 fotoğraf
	life.name = "HangarLife"
	life.hangar = self
	add_child(life)
	if not Game.flight_craft.is_empty():
		craft = Game.flight_craft.duplicate(true)
	else:
		craft = VesselBuilder.load_craft(String(Game.args.get("craft", DEFAULT_CRAFT)))
	_name_edit.text = craft.get("name", "Yeni Uçak")
	_rebuild()
	if Game.hangar_action == "missions":
		_open_missions.call_deferred()
	elif Game.hangar_action == "crew":
		_open_crew.call_deferred()
	elif Game.hangar_action == "new":
		_new_craft.call_deferred()
	Game.hangar_action = ""
	if Game.args.has("ctltest"):
		_ctl_test.call_deferred()
	elif Game.args.has("hovertest"):
		_hover_test.call_deferred()
	elif Game.args.has("hangartreetest"):
		_tree_test.call_deferred()
	elif Game.args.has("hangartest"):
		_self_test.call_deferred()
	elif Game.args.has("briefing"):
		(func() -> void: Briefing.open(self, String(Game.args["briefing"]), _name_edit.text, func() -> void: pass)).call_deferred()
	elif Game.args.has("medaltest"):   # madalya/rütbe testi (bellekte), sonra kadro paneli
		add_child.call_deferred(preload("res://tests/medal_test.gd").new())
	elif Game.args.has("hangarcrew"):
		_open_crew.call_deferred()
	elif Game.args.has("hangarmissions"):
		_open_missions.call_deferred()
	elif Game.args.has("debriefdemo"):   # ekran görüntüsü: örnek görev kartıyla uçuş raporu + tasarım değerlendirmesi
		(func() -> void:
			await get_tree().create_timer(0.5).timeout
			DesignDebrief.demo(self, _preview)).call_deferred()
	elif Game.args.has("hangardemo"):
		_demo.call_deferred()
	elif Game.args.has("hangarload"):   # ekran görüntüsü: yükleme listesi (hizmet geçmişi)
		_open_load.call_deferred()
	elif Game.args.has("prodemo"):   # ekran görüntüsü: seri üretim penceresi
		(func() -> void: ProductionDialog.open(self)).call_deferred()
	elif Game.args.has("protopalette"):   # ekran görüntüsü: paletteki prototip rozetleri (aramayla)
		(func() -> void:
			_search.text = String(Game.args["protopalette"])
			_filter_palette(_search.text)).call_deferred()
	elif Game.args.has("tweakdemo"):   # ekran görüntüsü: verilen parçanın sağ tık penceresi
		(func() -> void:
			await get_tree().create_timer(0.6).timeout
			for p in _preview.parts:
				if p.part_id == String(Game.args["tweakdemo"]):
					_fake_mouse = Vector2(900, 200)
					_open_part_panel(p)
					break).call_deferred()


## --hangardemo: ekran görüntüsü için elde parça + açık parça penceresi.
func _demo() -> void:
	await get_tree().create_timer(0.5).timeout
	for p in _preview.parts:
		if p.part_id == String(Game.args.get("demopart", "wing_main")):
			var sp := _cam.unproject_position(_craft_root.global_transform * p.position)
			_fake_mouse = sp
			await get_tree().process_frame
			_open_part_panel(p)
			break
	_select(String(Game.args["hangardemo"]))
	var mode := String(Game.args.get("demo-at", "node"))
	if mode == "node" and not _nodes.is_empty():
		var wp: Vector3 = _craft_root.global_transform * (_nodes[0]["pos"] as Vector3)
		_fake_mouse = _cam.unproject_position(wp) + Vector2(25, 10)
	else:
		_fake_mouse = Vector2(1000, 200)


## --hangartreetest: parça ağacı, grup taşıma, radyal simetri, tutamaçla kaydırma ve kök değiştirme.
func _tree_test() -> void:
	await get_tree().process_frame
	var parts: Array = craft["parts"]
	var no_tree := 0
	for e: Dictionary in parts:
		if not e.has("uid") or not e.has("parent"):
			no_tree += 1
	var root_name := ""
	for e: Dictionary in parts:
		if int(e.get("parent", 0)) < 0:
			root_name += String(e["part"]) + " "
	print("TREE kayıt=%d ağaçsız=%d kök=%s" % [parts.size(), no_tree, root_name])
	# en çok alt ağacı olan gövde parçasını tut, 1 m geri koy
	var best := -1
	var best_n := 0
	for i in parts.size():
		var n := CraftTree.subtree(craft, i).size()
		if i > 0 and n > best_n and n < parts.size():
			best_n = n
			best = i
	var e0: Dictionary = parts[best]
	var best_uid := int(e0["uid"])
	var p0 := VesselBuilder._vec(e0["pos"])
	var kids_before := {}
	for i in CraftTree.subtree(craft, best):
		kids_before[int(parts[i]["uid"])] = [VesselBuilder._vec(parts[i]["pos"]), parts[i].get("mirror", false)]
	var n_parts := _preview.parts.size()
	_grab(best, false)
	print("TREE tutulan=%s grup=%d" % [e0["part"], _held.size()])
	_placement = {"pos": p0 + Vector3(0, 0, 1.0), "rot": VesselBuilder._vec(e0.get("rot", [0, 0, 0])), "ok": true, "parent": null}
	_try_place(false)
	var ok := true
	for uid in kids_before:
		var i := CraftTree.index_of(craft, uid)
		var e: Dictionary = craft["parts"][i]
		var d := VesselBuilder._vec(e["pos"]) - (kids_before[uid][0] as Vector3)
		if not d.is_equal_approx(Vector3(0, 0, 1.0)) or e.get("mirror", false) != kids_before[uid][1]:
			ok = false
			print("TREE  hata: %s kayma=%s ayna=%s" % [e["part"], d, e.get("mirror", false)])
	print("TREE grup 1 m geri taşındı, ayna korundu: %s  parça sayısı %d → %d" % [ok, n_parts, _preview.parts.size()])
	# radyal ×4: gövdenin yanına küçük kanat
	symmetry = true
	_sym_mode = "radial"
	_radial = 4
	var body: Part = null
	for p in _preview.parts:
		if p.def.get("category", "") == "gövde" and absf(p.position.x) < 0.1:
			body = p
	_select("wing_small")
	_placement = {"pos": body.position + Vector3(1.6, 0, 0), "rot": Vector3.ZERO, "ok": true, "parent": body}
	var before := _preview.parts.size()
	_try_place(false)
	var last: Dictionary = craft["parts"][-1]
	print("TREE radyal: kayıt radial=%s axis=%s  parça %d → %d (4 bekleniyor)" % [last.get("radial"), last.get("axis"), before, _preview.parts.size()])
	# tutamaç: aynalı bir kaydın SOL (ayna) kopyasını +X'e (merkeze doğru) 0.5 m kaydır → sağ taraf -X'e
	var mi := -1
	for i in (craft["parts"] as Array).size():
		if craft["parts"][i].get("mirror", false):
			mi = i
			break
	var mpos := VesselBuilder._vec(craft["parts"][mi]["pos"])
	_tool = 2
	_giz_uid = int(craft["parts"][mi]["uid"])
	_giz_copy = 1
	_place_gizmo()
	_drag_base = craft.duplicate(true)
	_drag_axis = 0
	var s0 := _cam.unproject_position(_gizmo.global_position)
	var s1 := _cam.unproject_position(_gizmo.global_position + Vector3.RIGHT * _gizmo.size_k)
	_drag_from = s0
	_drag_update(s0 + (s1 - s0) * (0.5 / _gizmo.size_k), false)
	_end_drag()
	var mi2 := CraftTree.index_of(craft, _giz_uid)
	print("TREE tutamaç: ayna kopyası +X 0.5 → asıl kayıt x %.2f → %.2f (−0.5 bekleniyor)" % [mpos.x, VesselBuilder._vec(craft["parts"][mi2]["pos"]).x])
	# kök değiştir: kuyruktaki son gövde parçası kök olunca tutulan grup ön tarafı da kapsar
	best = CraftTree.index_of(craft, best_uid)
	_make_root(best)
	print("TREE kök değişti: %s kökün alt ağacı = %d / %d" % [craft["parts"][best]["part"], CraftTree.subtree(craft, best).size(), (craft["parts"] as Array).size()])
	if Game.args.has("shotdir"):
		# tutamaçların görüntüsü (sağ ana kanat üstünde)
		_focus_camera()
		_giz_copy = 0
		for t in [2, 3]:
			_tool = t
			_place_gizmo()
			for i in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(String(Game.args["shotdir"]) + "/gizmo_%d.png" % t)
	get_tree().quit()


## --ctltest: kumanda testi (↓ basılı → yüzeyler sapar, bırakınca döner) ve kontrol yüzeyi paneli.
func _ctl_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var report := func(tag: String) -> void:
		var s := PackedStringArray()
		for m in _preview.modules:
			if m is ControlSurfaceModule:
				s.append("%s %+.0f°" % [m.part.part_id, rad_to_deg(m.deflection)])
		print("CTL %s: %s" % [tag, ", ".join(s)])
	for key in [KEY_DOWN, KEY_RIGHT]:
		var e := InputEventKey.new()
		e.keycode = key
		e.physical_keycode = key
		e.pressed = true
		Input.parse_input_event(e)
		await get_tree().create_timer(0.6).timeout
		report.call("%s basılı" % OS.get_keycode_string(key))
		e = e.duplicate()
		e.pressed = false
		Input.parse_input_event(e)
		await get_tree().create_timer(0.8).timeout
		report.call("bırakıldı")
	# bir elevonun panelini aç (yetki / eksen / dene)
	for p in _preview.parts:
		if p.part_id == "elevon" or p.part_id == "stabilator":
			_open_part_panel(p)
			break
	if Game.args.has("shotdir"):
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(Game.args["shotdir"]) + "/ctl_panel.png")
	get_tree().quit()


## --hovertest: paletten gerçek tıkla parça seç, fareyi sahnenin ortasına götür; hayalet çıkıyor mu,
## imlecin altında hangi arayüz kontrolü var (görünmez bir kontrol yerleştirmeyi engelliyor mu).
func _hover_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var card: Button = null
	for k in _cards:
		var b: Button = _cards[k]
		if b.is_visible_in_tree() and b.get_global_rect().end.y < 700.0 and Career.is_unlocked(k):
			card = b
			break
	var cpos := card.get_global_rect().get_center()
	var mv0 := InputEventMouseMotion.new()
	mv0.position = cpos
	mv0.global_position = cpos
	Input.parse_input_event(mv0)
	for i in 3:
		await get_tree().process_frame
	var h0 := get_viewport().gui_get_hovered_control()
	print("HOVER kart=%s rect=%s görünür=%s kilitli=%s devre_dışı=%s  kartın üstündeki=%s" % [card.get_path(), card.get_global_rect(),
		card.is_visible_in_tree(), false, card.disabled, h0.get_path() if h0 else "yok"])
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = cpos
		e.global_position = cpos
		Input.parse_input_event(e)
		await get_tree().process_frame
	if Game.args.has("shotdir"):
		var mvc := InputEventMouseMotion.new()
		mvc.position = cpos + Vector2(20, 10)
		mvc.global_position = mvc.position
		Input.parse_input_event(mvc)
		Input.warp_mouse(cpos + Vector2(20, 10))
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(Game.args["shotdir"]) + "/hover_card.png")
	var vs := get_viewport().get_visible_rect().size
	for spot in [vs * 0.5, vs * Vector2(0.45, 0.4), vs * Vector2(0.3, 0.75)]:
		var mv := InputEventMouseMotion.new()
		mv.position = spot
		mv.global_position = spot
		Input.parse_input_event(mv)
		Input.warp_mouse(spot)
		for i in 3:
			await get_tree().process_frame
		var hov := get_viewport().gui_get_hovered_control()
		print("HOVER seçili=%s nokta=%s üstteki=%s (%s) yerleşim=%s hayalet=%s" % [_selected, spot,
			hov.get_path() if hov else "yok", hov.get_class() if hov else "", not _placement.is_empty(),
			is_instance_valid(_ghost) and _ghost.visible])
	# takılması gereken parça, boş köşe: imlecin ucunda yüzmeli
	_select("wing_main")
	var corner := vs * Vector2(0.25, 0.2)
	var mv2 := InputEventMouseMotion.new()
	mv2.position = corner
	mv2.global_position = corner
	Input.parse_input_event(mv2)
	Input.warp_mouse(corner)
	for i in 3:
		await get_tree().process_frame
	var gpos := _cam.unproject_position(_ghost.global_position) if is_instance_valid(_ghost) else Vector2.ZERO
	print("HOVER kanat boşlukta: yerleşim=%s hayalet görünür=%s hayaletin ekran konumu=%s imleç=%s" % [
		not _placement.is_empty(), is_instance_valid(_ghost) and _ghost.visible, gpos, corner])
	get_tree().quit()


## --hangartest: sıfırdan, fare yerleştirmesini taklit ederek uçak kurar.
func _self_test() -> void:
	_new_craft()
	await get_tree().process_frame
	var steps := [
		["cockpit_mk1", null, Vector3.ZERO],
		["tank_long", "cockpit_mk1", Vector3(0, 0, 1)],
		["jet_engine", "tank_long", Vector3(0, 0, 1)],
		["radar_nose", "cockpit_mk1", Vector3(0, 0, -1)],
		["wing_main", "tank_long", Vector3(1, 0, 0), 1.25],
		["stabilator", "jet_engine", Vector3(1, 0, 0)],
		["wing_small", "jet_engine", Vector3(0, 1, 0)],
		["gear_main", "tank_long", Vector3(0.9, -1, 0)],
		["gear_nose", "cockpit_mk1", Vector3(0, -1, 0)],
	]
	for s in steps:
		_select(s[0], s[3] if s.size() > 3 else 1.0)
		var mouse := Vector2.ZERO
		if s[1] != null:
			var target: Part = null
			for p in _preview.parts:
				if p.part_id == s[1]:
					target = p
			var dir: Vector3 = s[2]
			var local: Vector3 = target.position + dir * (target.size * 0.5 + Vector3.ONE * 0.3)
			_cam.global_position = _craft_root.global_transform * (local + dir.normalized() * 8.0)
			_cam.look_at(_craft_root.global_transform * target.position, Vector3.UP if absf(dir.y) < 0.9 else Vector3.FORWARD)
			await get_tree().physics_frame
			await get_tree().physics_frame
			mouse = _cam.unproject_position(_craft_root.global_transform * (target.position + dir * 0.3))
		_placement = _compute_placement(mouse)
		print("TEST %s → %s" % [s[0], _placement])
		_try_place(false)
		await get_tree().process_frame
	print("TEST parça sayısı: %d  uyarı: %s" % [_preview.parts.size(), _warn.get_parsed_text().replace("\n", " | ")])
	if Game.args.has("autotest"):
		Game.args.erase("screenshot")
		_launch()


# ------------------------------------------------------------------ ortam

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.ssr_enabled = true            # cilalı zeminde uçağın yansıması
	env.ssr_max_steps = 48
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# güneş açık kapıdan (-z) içeri vurur: zeminde uzun bir ışık lekesi
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 200, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	# uçağa tavandan bakan spotlar (sıcak/soğuk)
	for sp in [[Vector3(-13, 19, 12), Color(1.0, 0.9, 0.78), true], [Vector3(14, 19, -6), Color(0.85, 0.92, 1.0), false]]:
		var spot := SpotLight3D.new()
		spot.position = sp[0]
		spot.light_color = sp[1]
		spot.light_energy = 9.0
		spot.spot_range = 45.0
		spot.spot_angle = 28.0
		spot.shadow_enabled = sp[2]
		add_child(spot)
		spot.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	for x in [-14.0, 14.0]:
		for z in [-12.0, 10.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, 16.0, z)
			l.omni_range = 40.0
			l.light_energy = 3.2
			l.light_color = Color(1.0, 0.96, 0.9)
			add_child(l)

	# zemin (cilalı epoksi: hafif yansır), işaret çizgileri, duvarlar, tavan lambaları
	_box(Vector3(70, 0.2, 70), Vector3(0, -0.1, 0), Color(0.36, 0.37, 0.38), 0.3)
	for i in range(1, 12):
		var k := -35.0 + i * 5.83
		_box(Vector3(70, 0.01, 0.04), Vector3(0, 0.002, k), Color(0.24, 0.25, 0.26), 0.9)
		_box(Vector3(0.04, 0.01, 70), Vector3(k, 0.002, 0), Color(0.24, 0.25, 0.26), 0.9)
	for i in 9:
		var z := -24.0 + i * 6.0
		_box(Vector3(0.25, 0.02, 3.0), Vector3(0, 0.01, z), Color(0.95, 0.75, 0.1), 0.6)
	_box(Vector3(30, 0.02, 0.3), Vector3(0, 0.01, -27), Color(0.95, 0.75, 0.1), 0.6)
	_box(Vector3(30, 0.02, 0.3), Vector3(0, 0.01, 27), Color(0.95, 0.75, 0.1), 0.6)
	# arka duvar (-z): ortada 30 × 14 m açık kapı
	_box(Vector3(20, 22, 0.5), Vector3(-25, 11, -35), Color(0.32, 0.35, 0.38), 0.7)
	_box(Vector3(20, 22, 0.5), Vector3(25, 11, -35), Color(0.32, 0.35, 0.38), 0.7)
	_box(Vector3(30, 8, 0.5), Vector3(0, 18, -35), Color(0.32, 0.35, 0.38), 0.7)
	_box(Vector3(0.5, 22, 70), Vector3(-35, 11, 0), Color(0.36, 0.38, 0.4), 0.7)
	_box(Vector3(0.5, 22, 70), Vector3(35, 11, 0), Color(0.36, 0.38, 0.4), 0.7)
	_box(Vector3(70, 22, 0.5), Vector3(0, 11, 35), Color(0.25, 0.27, 0.29), 0.6)   # kapı
	for i in 6:
		_box(Vector3(68, 0.3, 0.6), Vector3(0, 6 + i * 2.4, 34.6), Color(0.18, 0.19, 0.2), 0.5)
	_box(Vector3(70, 0.5, 70), Vector3(0, 22, 0), Color(0.2, 0.21, 0.22), 0.8)
	for x in [-14.0, 0.0, 14.0]:
		for z in [-20.0, 0.0, 20.0]:
			var lamp := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(6, 0.15, 1.2)
			lamp.mesh = m
			var mat := StandardMaterial3D.new()
			mat.emission_enabled = true
			mat.emission = Color(1, 0.97, 0.9)
			mat.emission_energy_multiplier = 3.0
			lamp.material_override = mat
			lamp.position = Vector3(x, 21.7, z)
			add_child(lamp)
	_build_outside()
	_build_structure()
	_build_props()


## Kapının dışı: güneşli apron, çimen, uzak tepeler ve gökyüzü (ışıksız düzlemler).
func _build_outside() -> void:
	_box(Vector3(120, 0.2, 70), Vector3(0, -0.12, -70), Color(0.55, 0.55, 0.53), 0.9)          # apron
	_box(Vector3(160, 0.2, 60), Vector3(0, -0.14, -130), Color(0.33, 0.42, 0.22), 1.0)          # çimen
	_box(Vector3(0.4, 0.02, 60), Vector3(0, 0.0, -66), Color(0.95, 0.75, 0.1), 0.6)             # taksi çizgisi
	_backdrop(Vector3(400, 0.1, 160), Vector3(0, 70, -180), Color(0.58, 0.72, 0.9), Vector3(90, 0, 0))   # gök
	_backdrop(Vector3(400, 0.1, 30), Vector3(0, 6, -175), Color(0.36, 0.45, 0.42), Vector3(90, 0, 0))    # tepeler
	# yarı açık sürgülü kapı kanatları (duvarın dışında)
	for sx in [-1.0, 1.0]:
		_box(Vector3(9, 14, 0.4), Vector3(sx * 19.5, 7, -35.6), Color(0.27, 0.3, 0.33), 0.6)
		for k in 5:
			_box(Vector3(9, 0.15, 0.1), Vector3(sx * 19.5, 1.5 + k * 2.8, -35.85), Color(0.2, 0.22, 0.24), 0.5)
	_box(Vector3(32, 0.4, 0.6), Vector3(0, 14.2, -35.2), Color(0.85, 0.7, 0.1), 0.6)          # kapı rayı


## Çelik iskelet: duvar kolonları, çatı makasları, köprülü vinç.
func _build_structure() -> void:
	var steel := Color(0.26, 0.3, 0.36)
	for i in 8:
		var k := -30.0 + i * 8.57
		_box(Vector3(0.7, 22, 0.9), Vector3(34.4, 11, k), steel, 0.5)
		_box(Vector3(0.7, 22, 0.9), Vector3(-34.4, 11, k), steel, 0.5)
		_box(Vector3(70, 0.9, 0.5), Vector3(0, 20.8, k), steel, 0.5)            # makas alt başlığı
		for j in 6:
			var x := -30.0 + j * 12.0
			_box(Vector3(0.18, 2.4, 0.18), Vector3(x, 20.0, k), steel, 0.5, Vector3(0, 0, 35 if j % 2 else -35))
	# yan duvarlarda sarı-siyah tampon şeridi
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.9, 70), Vector3(sx * 34.7, 0.45, 0), Color(0.9, 0.72, 0.08), 0.6)
	# köprülü vinç: yan raylar, sarı köprü, araba ve sarkan kanca
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.6, 0.8, 70), Vector3(sx * 33.5, 17.0, 0), steel, 0.5)
	_box(Vector3(67, 1.2, 1.0), Vector3(0, 17.6, -14), Color(0.92, 0.7, 0.08), 0.55)
	_box(Vector3(2.0, 1.0, 2.0), Vector3(-8, 16.6, -14), Color(0.3, 0.3, 0.32), 0.5)
	_cyl(0.03, 8.0, Vector3(-8, 12.0, -14), Color(0.15, 0.15, 0.15), 0.4)
	_box(Vector3(0.6, 0.5, 0.3), Vector3(-8, 7.8, -14), Color(0.9, 0.2, 0.1), 0.5)
	# duvarda tabela
	var plate := Label3D.new()
	plate.text = "HANGAR 1"
	plate.font_size = 220
	plate.pixel_size = 0.01
	plate.modulate = Color(0.92, 0.94, 0.96)
	plate.outline_size = 0
	plate.shaded = true
	plate.position = Vector3(34.0, 13.0, 8.6)
	plate.rotation_degrees = Vector3(0, -90, 0)
	add_child(plate)


## Kenarlardaki teçhizat (uçağın kurulduğu orta alandan uzak).
func _build_props() -> void:
	var red := Color(0.72, 0.1, 0.08)
	# takım dolapları (çekmece çizgili) ve tezgâh: +x duvarı
	for z in [-14.0, -11.4]:
		_box(Vector3(1.3, 1.1, 2.4), Vector3(32.8, 0.55, z), red, 0.4)
		for k in 4:
			_box(Vector3(0.02, 0.03, 2.2), Vector3(32.14, 0.25 + k * 0.24, z), Color(0.12, 0.12, 0.12), 0.5)
		_box(Vector3(1.0, 0.9, 2.2), Vector3(32.9, 1.55, z), red.darkened(0.15), 0.4)
	_box(Vector3(1.4, 0.08, 5.0), Vector3(32.6, 0.95, -0.5), Color(0.45, 0.32, 0.2), 0.8)
	for dz in [-2.3, 2.3]:
		for dx in [-0.55, 0.55]:
			_box(Vector3(0.08, 0.92, 0.08), Vector3(32.6 + dx, 0.46, -0.5 + dz), Color(0.2, 0.2, 0.22), 0.5)
	_box(Vector3(0.05, 1.6, 4.6), Vector3(34.0, 1.9, -0.5), Color(0.55, 0.57, 0.58), 0.6)      # alet panosu
	# gaz tüpleri
	for i in 5:
		_cyl(0.16, 1.5, Vector3(33.4 - (i % 2) * 0.4, 0.75, 6.0 + i * 0.38), [Color(0.2, 0.45, 0.25), Color(0.6, 0.62, 0.65)][i % 2], 0.35, 0.4)
	# yangın tüpleri (duvar dibinde)
	for z in [-24.0, 12.0, 26.0]:
		_cyl(0.13, 0.6, Vector3(34.3, 0.3, z), Color(0.85, 0.08, 0.05), 0.35)
	# varil yığını: -x köşesi
	for i in 7:
		var p := Vector3(-31.5 + (i % 4) * 0.72, 0.45, -28.0 + floorf(i / 4.0) * 0.75)
		_cyl(0.32, 0.9, p, Color(0.12, 0.28, 0.55), 0.5, 0.2)
	# çekici (tug): sarı gövde, kabin, tekerlekler
	var tug := Vector3(-24.0, 0.0, 16.0)
	_box(Vector3(2.2, 0.8, 3.4), tug + Vector3(0, 0.75, 0), Color(0.9, 0.68, 0.08), 0.5)
	_box(Vector3(1.6, 0.9, 1.2), tug + Vector3(0, 1.6, 0.9), Color(0.85, 0.63, 0.07), 0.5)
	_box(Vector3(1.5, 0.7, 0.05), tug + Vector3(0, 1.65, 0.28), Color(0.15, 0.2, 0.25), 0.1)
	for dx in [-1.05, 1.05]:
		for dz in [-1.1, 1.1]:
			_cyl(0.4, 0.35, tug + Vector3(dx, 0.4, dz), Color(0.06, 0.06, 0.06), 0.9, 0.0, Vector3(0, 0, 90))
	_box(Vector3(0.15, 0.15, 2.6), tug + Vector3(0, 0.5, -2.9), Color(0.25, 0.25, 0.27), 0.5)   # çeki demiri
	# bakım merdiveni (sarı): -x tarafında
	var st := Vector3(-16.0, 0.0, -6.0)
	for sx in [-0.45, 0.45]:
		_box(Vector3(0.08, 3.4, 0.08), st + Vector3(sx, 1.7, -0.9), Color(0.9, 0.7, 0.08), 0.5, Vector3(-22, 0, 0))
	for k in 7:
		_box(Vector3(0.9, 0.05, 0.3), st + Vector3(0, 0.35 + k * 0.42, -0.25 - k * 0.17), Color(0.5, 0.5, 0.52), 0.5)
	_box(Vector3(1.0, 0.06, 1.0), st + Vector3(0, 3.2, -1.7), Color(0.5, 0.5, 0.52), 0.5)
	for dx in [-0.45, 0.45]:
		for dz in [0.0, -2.2]:
			_box(Vector3(0.08, 3.2, 0.08), st + Vector3(dx, 1.6, dz), Color(0.9, 0.7, 0.08), 0.5)
	# tekerlekli takoz ve emniyet konileri
	for p in [Vector3(-8, 0, 22), Vector3(9, 0, 23), Vector3(-26, 0, -12)]:
		_cone(p)


func _box(size: Vector3, pos: Vector3, color: Color, roughness: float, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _std_mat(color, roughness)
	mi.position = pos
	mi.rotation_degrees = rot
	add_child(mi)


func _cyl(r: float, h: float, pos: Vector3, color: Color, roughness: float, metallic := 0.0, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 20
	mi.mesh = m
	var mat := _std_mat(color, roughness)
	mat.metallic = metallic
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	add_child(mi)


## Işıktan etkilenmeyen düzlem (dış manzara).
func _backdrop(size: Vector3, pos: Vector3, color: Color, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees = rot
	add_child(mi)


func _cone(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.04
	m.bottom_radius = 0.2
	m.height = 0.7
	mi.mesh = m
	mi.material_override = _std_mat(Color(1.0, 0.4, 0.05), 0.6)
	mi.position = p + Vector3(0, 0.35, 0)
	add_child(mi)
	_box(Vector3(0.42, 0.06, 0.42), p + Vector3(0, 0.03, 0), Color(0.1, 0.1, 0.1), 0.8)
	_cyl(0.105, 0.1, p + Vector3(0, 0.45, 0), Color(0.95, 0.95, 0.95), 0.6)   # yansıtıcı bant


const HELP_KEYS := [
	["ARAÇLAR", ""],
	["1 · 2 · 3 · 4", "yerleştir · kaydır (oklar) · döndür (halkalar) · kök seç"],
	["Kaydır / döndür", "parçaya tıkla, tutamacı sürükle (Shift: serbest) — takılı olanlar da gelir"],
	["YERLEŞTİRME", ""],
	["Sol tık", "parçayı yerleştir · takılı parçayı ona takılı her şeyle tut"],
	["Ctrl + sol tık", "parçayı takılı olanlarla kopyala"],
	["Shift + sol tık", "yerleştir, seçim (grup) elde kalsın"],
	["Esc · sağ tık", "elden bırak (taşınan grup yerine döner)"],
	["Sağ tık", "parça penceresi (bilgi, boyut, ayarlar, taşı, kopyala, kök yap, sil)"],
	["Del", "fare altındaki parçayı takılı olanlarla sil"],
	["X · V", "simetri aç / kapat · tür: ayna → radyal ×2 ×3 ×4 ×6 ×8"],
	["Yön tuşları · PgUp/PgDn", "fare altındaki parçayı ince kaydır (Shift: 25 cm)"],
	["DÖNDÜRME VE BOYUT", ""],
	["W/S · A/D · Q/E", "burun · sapma · yatış ekseninde döndür"],
	["C · Boşluk", "açı adımını değiştir · dönüşü sıfırla"],
	["Shift + tekerlek · [ ]", "gövde, motor, kanat boyutu (0.5×–2×)"],
	["KAMERA VE DOSYA", ""],
	["Sağ sürükle · orta sürükle", "kamerayı döndür · kaydır"],
	["Tekerlek · F", "yakınlaş · uçağı ortala"],
	["Ctrl+Z · Ctrl+Y", "geri al · yinele"],
	["Ctrl+S", "kaydet"],
	["F12", "fotoğraf (arayüz gizlenir, user://photos)"],
	["Rüzgâr tüneli (üst çubuk)", "akış, stall, yük haritası, kaldırma eğrisi"],
]


## F1: tüm hangar kısayolları (sabit alt yazı yerine).
func _build_help(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(Color(0.05, 0.07, 0.09, 0.95), 10))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "HANGAR KISAYOLLARI"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	for row in HELP_KEYS:
		var k := Label.new()
		k.text = row[0]
		var section: bool = row[1] == ""
		k.add_theme_font_size_override("font_size", 12 if section else 14)
		k.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68) if section else Color(1.0, 0.85, 0.45))
		grid.add_child(k)
		var v := Label.new()
		v.text = row[1]
		v.add_theme_font_size_override("font_size", 14)
		v.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		grid.add_child(v)
	var close := Label.new()
	close.text = "F1 ile kapat"
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
	box.add_child(close)
	_help_panel = panel


func _std_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _build_markers() -> void:
	_com_marker = _marker(Color(1.0, 0.85, 0.1))
	_col_marker = _marker(Color(0.2, 0.6, 1.0))


func _marker(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.7
	mi.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_craft_root.add_child(mi)
	return mi


# ------------------------------------------------------------------ uçak önizlemesi

func _rebuild() -> void:
	_close_part_panel()
	_sync_paint_ui()
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_part_entry.clear()
	_part_copy.clear()
	var parts: Array = craft.get("parts", [])
	if not parts.is_empty():
		_preview = VesselBuilder.build(craft)
		_preview.freeze = true
		_craft_root.add_child(_preview)
		_preview.set_physics_process(false)
		_preview.set_cold()
		# parça → kayıt eşlemesi (simetri kopyaları — ayna ya da radyal — kaydın hemen ardından gelir)
		var k := 0
		for i in parts.size():
			var entry: Dictionary = parts[i]
			var copies := VesselBuilder.entry_copies(entry).size()
			for c in copies:
				if k < _preview.parts.size():
					_part_entry[_preview.parts[k]] = i
					_part_copy[_preview.parts[k]] = c
				k += 1
		CraftTree.ensure(craft, _preview, _part_entry)   # eski tasarım: ağacı temastan çıkar
		if _drag_axis < 0:
			_rest_on_floor()     # sürüklerken uçak yerinden oynamasın
	_refresh_nodes()
	_update_stats()
	_place_gizmo()


# ------------------------------------------------------------------ parça penceresi (sağ tık)

func _close_part_panel() -> void:
	if is_instance_valid(_part_panel):
		_part_panel.queue_free()
	_part_panel = null
	_panel_index = -1


func _open_part_panel(part: Part) -> void:
	if not _part_entry.has(part):
		return
	_close_part_panel()
	var idx: int = _part_entry[part]
	var entry: Dictionary = craft["parts"][idx]
	var sc: float = entry.get("scale", 1.0)
	var def: Dictionary = part.def      # kurulmuş tanım: ölçek, esneme ve kanat biçimi dahil
	_panel_index = idx
	var w := UiWindow.create(String(def.get("title", "")).to_upper(), _theme)
	w.custom_minimum_size.x = 260
	var info := Label.new()
	info.text = _part_tooltip(def).split("\n", true, 1)[1] if _part_tooltip(def).contains("\n") else ""
	if entry.get("mirror", false):
		info.text += "\nSimetrik çift (karşı tarafta ayna kopyası var)"
	info.add_theme_font_size_override("font_size", 13)
	w.body.add_child(info)
	if def.get("category", "") in VesselBuilder.SCALABLE:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "Boyut"
		l.custom_minimum_size.x = 60
		row.add_child(l)
		var minus := Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		row.add_child(minus)
		var val := Label.new()
		val.text = "×%.2f" % sc
		val.custom_minimum_size.x = 70
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.focus_mode = Control.FOCUS_NONE
		row.add_child(plus)
		minus.pressed.connect(func() -> void: _rescale_entry(idx, -1))
		plus.pressed.connect(func() -> void: _rescale_entry(idx, 1))
		w.body.add_child(row)
	if def.get("procedural", "") == "wing":
		_wing_editor(w.body, idx, entry)
	if def.get("category", "") in VesselBuilder.STRETCHABLE:
		_stretch_editor(w.body, idx, entry)
	_tweak_editor(w.body, idx, entry, part)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var n_sub := CraftTree.subtree(craft, idx).size()
	if n_sub > 1:
		var sub := Label.new()
		sub.text = "Bu parçaya %d parça takılı: taşı / kopyala / sil hepsini birlikte yapar" % (n_sub - 1)
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
		w.body.add_child(sub)
	for spec in [["Taşı", func() -> void: _grab(idx, false)],
			["Kopyala", func() -> void: _grab(idx, true)],
			["Kök yap", func() -> void: _make_root(idx)],
			["Sil", func() -> void:
				_close_part_panel()
				_delete_entry(idx)]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	w.body.add_child(buttons)
	w.closed.connect(_close_part_panel)
	_hover_label.get_parent().add_child(w)
	var vp := get_viewport().get_visible_rect().size
	w.position = (_mouse() + Vector2(24, -30)).clamp(Vector2(310, 64), vp - Vector2(290, 230))
	_part_panel = w
	Sfx.click()


## Parçaya özel ayarlar (KSP tweakable gibi): yakıt doluluğu, motor itki sınırı ve art yakıcı,
## kontrol yüzeyi sapma açısı. Kayda (craft parts girdisi) yazılır, uçuşta VesselBuilder uygular.
func _tweak_editor(parent: Control, idx: int, entry: Dictionary, part: Part) -> void:
	for m in part.modules:
		if m is FuelTankModule and m.capacity > 0.0:
			_section_label(parent, "YAKIT")
			var cap: float = m.capacity
			_slider(parent, "Doluluk", 0.0, 100.0, 5.0, float(entry.get("fuel", 1.0)) * 100.0, "%%%d", func(x: float) -> void:
				_commit_entry(idx, func(e: Dictionary) -> void:
					if x >= 99.5:
						e.erase("fuel")
					else:
						e["fuel"] = x / 100.0))
			var l := Label.new()
			l.text = "%d / %d kg — az yakıt: hafif ve çevik, ama kısa menzil" % [cap * float(entry.get("fuel", 1.0)), cap]
			l.add_theme_font_size_override("font_size", 11)
			l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
			parent.add_child(l)
		elif m is EngineModule:
			_section_label(parent, "MOTOR")
			_slider(parent, "İtki sınırı", 10.0, 100.0, 5.0, float(entry.get("thrust_limit", 1.0)) * 100.0, "%%%d", func(x: float) -> void:
				_commit_entry(idx, func(e: Dictionary) -> void:
					if x >= 99.5:
						e.erase("thrust_limit")
					else:
						e["thrust_limit"] = x / 100.0))
			if not (m.prop or m.rocket or bool(part.def.get("modules", [{}])[0].get("no_ab", false))):
				var ab := CheckBox.new()
				ab.text = "Art yakıcı (AB) kullanılsın"
				ab.focus_mode = Control.FOCUS_NONE
				ab.button_pressed = not entry.get("no_ab", false)
				ab.toggled.connect(func(on: bool) -> void:
					_commit_entry(idx, func(e: Dictionary) -> void:
						if on:
							e.erase("no_ab")
						else:
							e["no_ab"] = true))
				parent.add_child(ab)
		elif m is ControlSurfaceModule:
			_section_label(parent, "KONTROL YÜZEYİ")
			var base_deg := rad_to_deg(m.max_deflection)
			_slider(parent, "Sapma", 5.0, 35.0, 1.0, float(entry.get("deflect", base_deg)), "±%d°", func(x: float) -> void:
				_commit_entry(idx, func(e: Dictionary) -> void:
					e["deflect"] = x))
			# KSP gibi yetki: ne kadar tepki versin (eksi = ters çalışır)
			_slider(parent, "Yetki", -150.0, 150.0, 10.0, float(entry.get("auth", 1.0)) * 100.0, "%+d%%", func(x: float) -> void:
				_commit_entry(idx, func(e: Dictionary) -> void:
					if absf(x - 100.0) < 1.0:
						e.erase("auth")
					else:
						e["auth"] = x / 100.0))
			# hangi eksene çalışsın (kendiliğinden konumundan bulunur; burada kapatılabilir)
			var axes: Array = entry.get("axes", [1.0, 1.0, 1.0])
			var row := HBoxContainer.new()
			for spec in [["Yunuslama", 0], ["Yatış", 2], ["Sapma", 1]]:
				var ax_i: int = spec[1]
				var cb := CheckBox.new()
				cb.text = spec[0]
				cb.focus_mode = Control.FOCUS_NONE
				cb.button_pressed = float(axes[ax_i]) > 0.5
				cb.disabled = absf(m.axis_weights[ax_i]) < 0.01 and float(axes[ax_i]) > 0.5   # bu eksene zaten etkisi yok
				cb.tooltip_text = "Bu yüzey %s komutuna çalışsın" % String(spec[0]).to_lower()
				cb.toggled.connect(func(on: bool) -> void:
					_commit_entry(idx, func(e: Dictionary) -> void:
						var a: Array = (e.get("axes", [1.0, 1.0, 1.0]) as Array).duplicate()
						a[ax_i] = 1.0 if on else 0.0
						if a == [1.0, 1.0, 1.0]:
							e.erase("axes")
						else:
							e["axes"] = a))
				row.add_child(cb)
			parent.add_child(row)
			var test := Button.new()
			test.text = "Hareketi dene"
			test.focus_mode = Control.FOCUS_NONE
			test.tooltip_text = "Yüzey iki yöne tam sapar ve yerine döner. Bütün uçak için: ok tuşları (yunus / yatış), , . (sapma)"
			test.pressed.connect(func() -> void: _sweep_surface(m))
			parent.add_child(test)
			var hint := Label.new()
			hint.text = "Bütün uçağı dene: ↑↓ yunuslama · ←→ yatış · , . sapma"
			hint.add_theme_font_size_override("font_size", 11)
			hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
			parent.add_child(hint)

## Tek yüzeyi dene: +tam → −tam → 0 (yerine döner), gerçek dönüş hızıyla.
func _sweep_surface(m: ControlSurfaceModule) -> void:
	if not is_instance_valid(m):
		return
	Sfx.play_ui("hydraulic_thunk.ogg", -10.0, 1.4)
	for target in [1.0, -1.0, 0.0]:
		var goal: float = target * m.max_deflection * signf(m.authority if m.authority != 0.0 else 1.0)
		while is_instance_valid(m) and absf(m.deflection - goal) > 0.001:
			var dt := get_process_delta_time()
			m.deflection = move_toward(m.deflection, goal, m.rate * dt)
			var vis := m.part.get_node_or_null("Visual") as Node3D
			if vis:
				vis.rotation.x = m.deflection
			await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout


var _ctl_active := false


## Hangar kumanda testi: ok tuşları / , . basılıyken önizlemedeki bütün kontrol yüzeyleri o
## komuta göre sapar, bırakınca yerine döner (hangi yüzeyin hangi eksene çalıştığı görünür).
func _update_control_test(delta: float) -> void:
	if not is_instance_valid(_preview):
		return
	var typing := (_name_edit and _name_edit.has_focus()) or (_search and _search.has_focus())
	var pitch := 0.0
	var roll := 0.0
	var yaw := 0.0
	if not typing:
		pitch = (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_key_pressed(KEY_UP) else 0.0)
		roll = (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0)
		yaw = (1.0 if Input.is_key_pressed(KEY_PERIOD) else 0.0) - (1.0 if Input.is_key_pressed(KEY_COMMA) else 0.0)
	var any := pitch != 0.0 or roll != 0.0 or yaw != 0.0
	if not any and not _ctl_active:
		return
	var desired := Vector3(pitch, -yaw, -roll)
	var moving := false
	for m in _preview.modules:
		if m is ControlSurfaceModule:
			m.preview_tick(desired, delta)
			moving = moving or absf(m.deflection) > 0.001
	_ctl_active = any or moving


# ------------------------------------------------------------------ biçim düzenleyicileri

## Kaydı değiştir, uçağı yeniden kur ve aynı parçanın penceresini tekrar aç.
func _commit_entry(idx: int, change: Callable) -> void:
	if idx < 0 or idx >= (craft["parts"] as Array).size():
		return
	_push_undo()
	change.call(craft["parts"][idx])
	Sfx.play_ui("switch_2.ogg", -12.0, 1.1)
	_rebuild()
	for p in _part_entry:
		if _part_entry[p] == idx:
			_open_part_panel(p)
			return


## Etiketli kaydırıcı. Sürüklerken yalnız değer yazısı değişir; bırakınca (ya da tıklama /
## tekerlekten 0.35 sn sonra) on_commit(değer) çağrılır.
func _slider(parent: Control, title: String, lo: float, hi: float, step: float, value: float, fmt: String, on_commit: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 92
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 120
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v := Label.new()
	v.text = fmt % value
	v.custom_minimum_size.x = 52
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 12)
	row.add_child(v)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.35
	row.add_child(timer)
	var state := {"drag": false}
	s.drag_started.connect(func() -> void: state["drag"] = true)
	s.drag_ended.connect(func(_changed: bool) -> void:
		state["drag"] = false
		on_commit.call_deferred(s.value))
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		if not state["drag"]:
			timer.start())
	timer.timeout.connect(func() -> void: on_commit.call_deferred(s.value))
	parent.add_child(row)


func _section_label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	parent.add_child(l)


## Ayarlanabilir kanat: hazır biçimler + açıklık, veterler, ok açıları, kırılma, kalınlık, dihedral.
## Açıklık değişince kök yerinde kalır (kanat gövdeden kopmaz).
func _wing_editor(parent: Control, idx: int, entry: Dictionary) -> void:
	var p: Dictionary = (entry.get("wing", PartLibrary.WING_PRESETS["Trapez"]) as Dictionary).duplicate()
	_section_label(parent, "KANAT BİÇİMİ")
	var grid := GridContainer.new()
	grid.columns = 4
	for shape_name in PartLibrary.WING_PRESETS:
		var b := Button.new()
		b.text = shape_name
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func() -> void: _set_wing(idx, (PartLibrary.WING_PRESETS[shape_name] as Dictionary).duplicate()))
		grid.add_child(b)
	parent.add_child(grid)
	var specs := [
		["Açıklık", "span", 1.0, 12.0, 0.1, "%.1f m"],
		["Kök veteri", "root", 0.4, 9.0, 0.1, "%.1f m"],
		["Uç veteri", "tip", 0.05, 6.0, 0.05, "%.2f m"],
		["Ok açısı", "sweep", -40.0, 70.0, 1.0, "%+.0f°"],
		["Kırılma", "crank", 0.0, 0.8, 0.05, "%.2f"],
		["İç ok açısı", "crank_sweep", 0.0, 80.0, 1.0, "%.0f°"],
		["Kalınlık", "thick", 0.03, 0.15, 0.005, "%.3f"],
	]
	for sp in specs:
		var key: String = sp[1]
		_slider(parent, sp[0], sp[2], sp[3], sp[4], float(p.get(key, 0.0)), sp[5], func(x: float) -> void:
			var np := p.duplicate()
			np[key] = x
			_set_wing(idx, np))
	# dihedral: yatay kanatta Z dönüşü
	var rot := VesselBuilder._vec(entry.get("rot", [0, 0, 0]))
	if absf(rot.z) < 45.0:
		_slider(parent, "Dihedral", -20.0, 20.0, 1.0, rot.z, "%+.0f°", func(x: float) -> void:
			_commit_entry(idx, func(e: Dictionary) -> void:
				var r := VesselBuilder._vec(e.get("rot", [0, 0, 0]))
				e["rot"] = [r.x, r.y, x]))
	var info := Label.new()
	var d := PartLibrary.custom_wing_def(p)
	var wm: Dictionary = d["modules"][0]
	info.text = "Alan %.1f m²  ·  en-boy %.1f  ·  stall %d°  ·  %d kg" % [wm["area"], wm["aspect_ratio"], wm["stall_deg"], d["mass"]]
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	parent.add_child(info)


## Yeni kanat biçimi: açıklık değişince parçayı kaydırarak kökü yerinde tut.
func _set_wing(idx: int, np: Dictionary) -> void:
	_commit_entry(idx, func(e: Dictionary) -> void:
		var sc := float(e.get("scale", 1.0))
		var old_w: float = (VesselBuilder.entry_def(e["part"], e, sc)["size"] as Vector3).x
		e["wing"] = np
		var new_w: float = (VesselBuilder.entry_def(e["part"], e, sc)["size"] as Vector3).x
		var dir := Basis.from_euler(VesselBuilder._vec(e.get("rot", [0, 0, 0])) * (PI / 180.0)) * Vector3.RIGHT
		if e.get("flip", false):
			dir = -dir
		var pos := VesselBuilder._vec(e["pos"]) + dir * (new_w - old_w) * 0.5
		e["pos"] = [pos.x, pos.y, pos.z])


## Gövde esnemesi: uzunluk, genişlik, yükseklik ve hazır kesitler. Uzayınca arkadaki parçalar
## geriye, genişleyince yandakiler dışarı itilir (uçak bütün kalır, ön uç yerinde).
func _stretch_editor(parent: Control, idx: int, entry: Dictionary) -> void:
	var st := VesselBuilder._vec(entry.get("stretch", [1, 1, 1]))
	_section_label(parent, "GÖVDE BİÇİMİ")
	var row := HBoxContainer.new()
	for spec in [["Yuvarlak", Vector2(1.0, 1.0)], ["Oval", Vector2(1.25, 0.8)], ["Yassı", Vector2(1.7, 0.55)], ["Dar-uzun", Vector2(0.8, 0.8)]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var xy: Vector2 = spec[1]
		b.pressed.connect(func() -> void: _set_stretch(idx, Vector3(xy.x, xy.y, st.z)))
		row.add_child(b)
	parent.add_child(row)
	_slider(parent, "Uzunluk", 0.4, 3.0, 0.05, st.z, "×%.2f", func(x: float) -> void: _set_stretch(idx, Vector3(st.x, st.y, x)))
	_slider(parent, "Genişlik", 0.4, 3.0, 0.05, st.x, "×%.2f", func(x: float) -> void: _set_stretch(idx, Vector3(x, st.y, st.z)))
	_slider(parent, "Yükseklik", 0.4, 3.0, 0.05, st.y, "×%.2f", func(x: float) -> void: _set_stretch(idx, Vector3(st.x, x, st.z)))


func _set_stretch(idx: int, ns: Vector3) -> void:
	var parts: Array = craft["parts"]
	var e: Dictionary = parts[idx]
	var sc := float(e.get("scale", 1.0))
	var old_size: Vector3 = VesselBuilder.entry_def(e["part"], e, sc)["size"]
	var probe := e.duplicate(true)
	probe["stretch"] = [ns.x, ns.y, ns.z]
	var new_size: Vector3 = VesselBuilder.entry_def(e["part"], probe, sc)["size"]
	var p0 := VesselBuilder._vec(e["pos"])
	var front := p0.z - old_size.z * 0.5
	var back := p0.z + old_size.z * 0.5
	var dz := new_size.z - old_size.z
	var dw := (new_size.x - old_size.x) * 0.5
	var on_axis := absf(p0.x) < 0.3
	_commit_entry(idx, func(en: Dictionary) -> void:
		if ns.is_equal_approx(Vector3.ONE):
			en.erase("stretch")
		else:
			en["stretch"] = [ns.x, ns.y, ns.z]
		if not on_axis:
			return
		en["pos"] = [p0.x, p0.y, p0.z + dz * 0.5]
		for i in parts.size():
			if i == idx:
				continue
			var o: Dictionary = parts[i]
			var q := VesselBuilder._vec(o.get("pos", [0, 0, 0]))
			if q.z > p0.z + 0.01:
				q.z += dz      # arkadakiler geriye
			if absf(q.x) > 0.3 and q.z > front - 0.2 and q.z < back + 0.2:
				q.x += signf(q.x) * dw     # yandakiler (kanat kökü, alık) dışarı
			o["pos"] = [q.x, q.y, q.z])


func _rescale_entry(idx: int, dir: int) -> void:
	var entry: Dictionary = craft["parts"][idx]
	var i := SCALES.find(float(entry.get("scale", 1.0)))
	if i < 0:
		i = SCALES.find(1.0)
	var ns: float = SCALES[clampi(i + dir, 0, SCALES.size() - 1)]
	_push_undo()
	if is_equal_approx(ns, 1.0):
		entry.erase("scale")
	else:
		entry["scale"] = ns
	Sfx.play_ui("switch_2.ogg", -10.0, 0.8 + ns * 0.3)
	_rebuild()
	for p in _part_entry:
		if _part_entry[p] == idx:
			_open_part_panel(p)
			return


func _pick_up_entry(idx: int) -> void:
	_grab(idx, false)


## Parçayı ve ona takılı her şeyi (alt ağaç) ele al (KSP gibi). copy: tasarımda bırak, kopyasını
## al. Tutulan grup Esc / sağ tıkla yerine döner; yerleştirince yeni yerine taşınır.
func _grab(idx: int, copy: bool) -> void:
	_close_part_panel()
	var parts: Array = craft["parts"]
	if idx < 0 or idx >= parts.size():
		return
	var ids := CraftTree.subtree(craft, idx)
	var restore := craft.duplicate(true)
	var group: Array = []
	if copy:
		for i in ids:
			group.append((parts[i] as Dictionary).duplicate(true))
		CraftTree.renumber(craft, group)
	else:
		_push_undo()
		group = CraftTree.take(craft, ids)
	var root: Dictionary = group[0]
	var sym := CraftTree.sym_of(root)
	if sym.has("mirror"):
		symmetry = true
		_sym_mode = "mirror"
	elif sym.has("radial"):
		symmetry = true
		_sym_mode = "radial"
		_radial = int(sym["radial"])
	_sync_sym_ui()
	Sfx.play_ui("switch_2.ogg", -6.0, 1.2)
	_giz_uid = -1
	if not copy:
		_rebuild()
	_select(root["part"], float(root.get("scale", 1.0)))
	_held = group
	_held_root_xf = VesselBuilder.entry_xform(root)
	_held_restore = {} if copy else restore
	_clear_ghosts()
	_ghost = _ghost_for(0, 0, false)
	if group.size() > 1:
		_flash("%d parça birlikte %s (takılı olanlarla)" % [group.size(), "kopyalandı" if copy else "taşınıyor"])


## Tutulan grubu bırak: taşınıyorsa yerine geri koy.
func _cancel_hold() -> void:
	if not _held_restore.is_empty():
		craft = _held_restore
		_held_restore = {}
		if not _undo.is_empty():
			_undo.pop_back()
		_rebuild()
	_select("")


## Parçayı ve ona takılı her şeyi sil.
func _delete_entry(idx: int) -> void:
	if idx < 0 or idx >= (craft["parts"] as Array).size():
		return
	var ids := CraftTree.subtree(craft, idx)
	_push_undo()
	CraftTree.take(craft, ids)
	_hover_part = null
	_giz_uid = -1
	Sfx.play_ui("switch_3.ogg", -6.0, 0.8)
	if ids.size() > 1:
		_flash("%d parça silindi (takılı olanlarla)" % ids.size())
	_rebuild()


const TOOL_NAMES := ["", "Yerleştir", "Kaydır", "Döndür", "Kök"]
const TOOL_HINTS := ["",
	"Sol tık: tut / yerleştir (takılı olanlarla) · Ctrl+sol: kopyala · Sağ tık: pencere",
	"Parçaya tıkla → okları sürükle: eksende kaydır (adım 5 cm, Shift serbest) · takılı olanlar da gelir",
	"Parçaya tıkla → halkaları sürükle: eksen çevresinde döndür (açı adımı C, Shift 1°)",
	"Parçaya tıkla: uçağın kökü olur (tutunca ona takılı her şey gelir)"]


var _blink_mat: StandardMaterial3D


## Uyarıya tıklanınca ilgili parçalar kırmızı yanıp söner (3 kez).
func _blink(kind: String) -> void:
	if not is_instance_valid(_preview):
		return
	if _blink_mat == null:
		_blink_mat = StandardMaterial3D.new()
		_blink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blink_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_blink_mat.no_depth_test = true
		_blink_mat.albedo_color = Color(1.0, 0.25, 0.15, 0.6)
	var hits := _parts_of(kind)
	if hits.is_empty():
		_flash("Uçakta bu türden parça yok — paletten ekle")
		return
	Sfx.play_ui("switch_2.ogg", -10.0, 1.5)
	for i in 6:
		for p in hits:
			if is_instance_valid(p):
				_set_overlay(p, _blink_mat if i % 2 == 0 else null)
		await get_tree().create_timer(0.2).timeout


## Uyarı türüne (_update_stats `kind`) uyan parçalar.
func _parts_of(kind: String) -> Array[Part]:
	var hits: Array[Part] = []
	if not is_instance_valid(_preview):
		return hits
	for p in _preview.parts:
		var match_it := false
		for m in p.modules:
			match kind:
				"engine": match_it = match_it or m is EngineModule
				"intake": match_it = match_it or m is IntakeModule or m is EngineModule
				"fuel": match_it = match_it or m is FuelTankModule
				"wing": match_it = match_it or (m is WingModule and not m is ControlSurfaceModule)
				"control": match_it = match_it or m is ControlSurfaceModule
				"gear": match_it = match_it or m is LandingGearModule
				"cockpit": match_it = match_it or m is CockpitModule
				"radar": match_it = match_it or m is RadarModule or m is MissileModule
				"pod": match_it = match_it or m is TargetingPodModule or m is BombModule
		if match_it:
			hits.append(p)
	return hits


var _markers: Array[Label3D] = []


## Sorunlu parçaların üstünde yüzen ⚠ işaretleri (yazı okumadan görülsün). Parça yoksa (ör. kokpit
## eksik) işaret uçağın ağırlık merkezinin üstünde durur.
func _warn_markers(kinds: PackedStringArray) -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()
	if not is_instance_valid(_preview):
		return
	# her uyarı türüne TEK işaret: ilgili parçaların ortasının üstünde (altı tane ⚠ gürültü olur)
	var spots: Array[Vector3] = []
	for kind in kinds:
		var hits := _parts_of(kind)
		var s := _preview.com_local + Vector3.UP * 2.5
		if not hits.is_empty():
			var sum := Vector3.ZERO
			var top := -INF
			for p in hits:
				sum += p.position
				top = maxf(top, p.position.y + p.size.y * 0.5)
			s = sum / hits.size()
			s.y = top + 1.0
		for o in spots:
			if o.distance_to(s) < 1.2:
				s.y = o.y + 1.3     # üst üste binmesin
		spots.append(s)
	for s in spots:
		var l := Label3D.new()
		l.text = "⚠"
		l.font_size = 96
		l.pixel_size = 0.008
		l.modulate = Color(1.0, 0.55, 0.2)
		l.outline_size = 18
		l.outline_modulate = Color(0.1, 0.02, 0.0, 0.9)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = s
		_preview.add_child(l)
		_markers.append(l)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "position:y", s.y + 0.3, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(l, "position:y", s.y, 0.6).set_trans(Tween.TRANS_SINE)


var _tunnel: WindTunnel


## Rüzgâr tüneli aç / kapa (hangar/wind_tunnel.gd): akış, stall, yük haritası, CL eğrisi.
func _toggle_tunnel() -> void:
	if _tunnel == null:
		_tunnel = WindTunnel.new()
		_tunnel.name = "WindTunnel"
		_tunnel.hangar = self
		_tunnel.ui_root = _hover_label.get_parent() as Control
		add_child(_tunnel)
	if _tunnel.is_open():
		_tunnel.close()
	else:
		_cancel_hold()
		_close_part_panel()
		_tunnel.open()
	Sfx.click()


## Alt ortada araç çubuğu (KSP'deki gibi): 1 yerleştir · 2 kaydır · 3 döndür · 4 kök.
func _build_toolbar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -40
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	for t in range(1, 5):
		var b := Button.new()
		b.text = "%d  %s" % [t, TOOL_NAMES[t]]
		b.toggle_mode = true
		b.button_pressed = t == _tool
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = TOOL_HINTS[t]
		b.add_theme_font_size_override("font_size", 13)
		var tt := t
		b.pressed.connect(func() -> void:
			b.set_pressed_no_signal(true)
			_set_tool(tt))
		row.add_child(b)
		_tool_btns.append(b)
	root.add_child(panel)


## Araç: 1 yerleştir · 2 kaydır · 3 döndür · 4 kök.
func _set_tool(t: int) -> void:
	if t == _tool:
		return
	if not _selected.is_empty():
		_cancel_hold()
	_tool = t
	_drag_axis = -1
	for i in _tool_btns.size():
		_tool_btns[i].set_pressed_no_signal(i + 1 == t)
	Sfx.play_ui("switch_2.ogg", -12.0, 1.0 + t * 0.08)
	_flash("%s — %s" % [TOOL_NAMES[t], TOOL_HINTS[t]])
	_place_gizmo()


## Kaydır / döndür aracında tıklama: tutamaca basıldıysa sürükleme başlar, parçaya basıldıysa
## tutamaçlar o parçaya (tıklanan simetri kopyasına) taşınır, boşluğa basıldıysa kalkar.
func _tool_click(mouse: Vector2) -> void:
	if _gizmo.visible:
		var axis := _gizmo.pick(_cam, mouse)
		if axis >= 0:
			_drag_axis = axis
			_drag_from = mouse
			_drag_val = 0.0
			_drag_base = craft.duplicate(true)
			_push_undo()
			return
	var part := _part_under_mouse()
	if part != null and _part_entry.has(part):
		_giz_uid = int(craft["parts"][_part_entry[part]].get("uid", -1))
		_giz_copy = int(_part_copy.get(part, 0))
		Sfx.play_ui("switch_2.ogg", -14.0, 1.3)
	else:
		_giz_uid = -1
	_place_gizmo()


## Tutamaçları hedef parçanın üstüne koy (araç 2 / 3 ve hedef varsa).
func _place_gizmo() -> void:
	if _gizmo == null:
		return
	var idx := CraftTree.index_of(craft, _giz_uid) if _giz_uid >= 0 else -1
	var target: Part = null
	if idx >= 0 and (_tool == 2 or _tool == 3):
		for p in _part_entry:
			if _part_entry[p] == idx and int(_part_copy.get(p, 0)) == _giz_copy:
				target = p
	if target == null:
		_gizmo.set_mode(HangarGizmo.Mode.NONE)
		return
	_gizmo.position = target.position
	_gizmo.set_mode(HangarGizmo.Mode.MOVE if _tool == 2 else HangarGizmo.Mode.ROTATE)


## Sürükleme: başlangıç tasarımından, toplam kaydırma / dönüş kadar değiştirilmiş tasarım kurulur
## (adım değişince). Tıklanan kopyadaki hareket asıl kayda çevrilir (aynada X ters, radyalde döner).
func _drag_update(mouse: Vector2, free: bool) -> void:
	var val: float
	if _tool == 2:
		val = snappedf(_gizmo.drag_move(_cam, _drag_axis, _drag_from, mouse), 0.001 if free else SNAP)
	else:
		var step := deg_to_rad(1.0 if free else _angle_step)
		val = snappedf(_gizmo.drag_angle(_cam, _drag_axis, _drag_from, mouse), step)
	if is_equal_approx(val, _drag_val):
		return
	_drag_val = val
	craft = _drag_base.duplicate(true)
	var idx := CraftTree.index_of(craft, _giz_uid)
	if idx < 0:
		return
	var axis: Vector3 = HangarGizmo.AXES[_drag_axis]
	var pivot := _gizmo.position
	var d_copy: Transform3D
	if _tool == 2:
		d_copy = Transform3D(Basis.IDENTITY, axis * val)
	else:
		d_copy = Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(axis, val), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	var ops := VesselBuilder.copy_ops(craft["parts"][idx])
	var op: Dictionary = ops[_giz_copy] if _giz_copy < ops.size() else ops[0]
	var s: Transform3D = op["xf"]
	var d := s * d_copy * s if op["mirror"] else s.affine_inverse() * d_copy * s
	var ids := CraftTree.subtree(craft, idx)
	var group := CraftTree.take(craft, ids)
	var moved := CraftTree.transform_group(craft, group, d, CraftTree.sym_of(group[0]))
	(craft["parts"] as Array).append_array(moved)
	_rebuild()
	_flash(("%+.2f m" % val) if _tool == 2 else ("%+d°" % roundi(rad_to_deg(val))))


func _end_drag() -> void:
	_drag_axis = -1
	_drag_base = {}
	if is_equal_approx(_drag_val, 0.0) and not _undo.is_empty():
		_undo.pop_back()     # hiç oynamadı: geri alma noktası gereksiz
	_rebuild()               # zemine yeniden otur


## Kök değiştir (KSP 4. araç): uçağın ağacı bu parçadan başlar.
func _make_root(idx: int) -> void:
	_close_part_panel()
	if idx < 0 or idx >= (craft["parts"] as Array).size():
		return
	_push_undo()
	CraftTree.reroot(craft, idx)
	Sfx.play_ui("switch_2.ogg", -8.0, 0.9)
	_flash("Kök: %s — tutunca artık bu parçaya takılanlar gelir" % PartLibrary.get_def(String(craft["parts"][idx]["part"])).get("title", ""))


## Uçağı tekerlekleri (yoksa gövdesi) zemine değecek şekilde indir.
func _rest_on_floor() -> void:
	var low := INF
	var stack: Array[Node] = [_preview]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.is_visible_in_tree() and n.mesh != null:
			var aabb: AABB = n.get_aabb()
			var xf: Transform3D = _craft_root.global_transform.affine_inverse() * n.global_transform
			for i in 8:
				low = minf(low, (xf * aabb.get_endpoint(i)).y)
	if low < INF:
		_craft_root.position.y = maxf(-low, 0.3)


# ------------------------------------------------------------------ kare döngüsü

func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_load_popup) and _load_popup.visible and is_instance_valid(_pv_root):
		_pv_root.rotate_y(delta * 0.35)    # önizleme yavaşça döner
	if not Game.args.has("hangartest"):
		_update_camera()
	_update_ghost()
	_update_hover()
	_update_control_test(delta)
	if _gizmo and _gizmo.visible:
		if _drag_axis < 0:
			_gizmo.hover = _gizmo.pick(_cam, _mouse())
		_gizmo.fit(_cam)
	if Game.args.has("screenshot") and _time >= float(Game.args.get("shot-time", "3")):
		_take_screenshot(Game.args["screenshot"])


func _update_camera() -> void:
	var offset := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_pitch) * Vector3(0, 0, _dist)
	_cam.global_position = _target + offset
	_cam.look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		# sürüklemeden bırakılan sağ tık = tıklama
		if _rmb_click:
			_rmb_click = false
			if not _selected.is_empty():
				_cancel_hold()
			else:
				var part := _part_under_mouse()
				if part != null:
					_open_part_panel(part)
				else:
					_close_part_panel()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _drag_axis >= 0:
		_end_drag()
		return
	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if _drag_axis >= 0:
			_drag_update(event.position, event.shift_pressed)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if event.position.distance_to(_rmb_pos) > 5.0:
				_rmb_click = false
			if not _rmb_click:
				_yaw -= rel.x * 0.005
				_pitch = clampf(_pitch + rel.y * 0.005, -0.2, 1.4)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var b := _cam.global_basis
			_target += (-b.x * rel.x + b.y * rel.y) * _dist * 0.0015
	elif event is InputEventMouseButton and event.pressed:
		var scaling: bool = event.shift_pressed and not _selected.is_empty()
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if scaling:
					_change_scale(1)
				else:
					_dist = maxf(_dist * 0.9, 5.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if scaling:
					_change_scale(-1)
				else:
					_dist = minf(_dist * 1.1, 90.0)
			MOUSE_BUTTON_LEFT:
				if _tunnel != null and _tunnel.is_open():
					return      # rüzgâr tünelinde tasarım değişmez (kamera serbest)
				if not _selected.is_empty():
					_try_place(event.shift_pressed)
				elif _tool == 2 or _tool == 3:
					_tool_click(event.position)
				elif _tool == 4:
					var part := _part_under_mouse()
					if part != null and _part_entry.has(part):
						_make_root(_part_entry[part])
				else:
					_try_pick_up(event.ctrl_pressed)   # Ctrl: kopyala
			MOUSE_BUTTON_RIGHT:
				_rmb_pos = event.position
				_rmb_click = true
	elif event is InputEventKey and event.pressed:
		if _name_edit.has_focus() or _search.has_focus() or (_paint_num and _paint_num.has_focus()):
			return
		if event.ctrl_pressed:
			match event.physical_keycode:
				KEY_Z:
					_undo_step(_undo, _redo)
				KEY_Y:
					_undo_step(_redo, _undo)
				KEY_S:
					_save()
			return
		# ince kaydırma: fare altındaki takılı parça, yön tuşları / PgUp-PgDn (Shift: 25 cm)
		if _selected.is_empty() and event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN]:
			_nudge(event.physical_keycode, 0.25 if event.shift_pressed else 0.05)
			return
		if event.echo:
			return
		match event.physical_keycode:
			KEY_F1:
				_help_panel.visible = not _help_panel.visible
			KEY_X:
				symmetry = not symmetry
				_sync_sym_ui()
				_flash("Simetri: " + _sym_label())
			KEY_V:
				_cycle_sym()
			KEY_1, KEY_2, KEY_3, KEY_4:
				_set_tool(event.physical_keycode - KEY_0)
			# KSP gibi: W/S burun (X), A/D sapma (Y), Q/E yatış (Z); Shift ters
			KEY_W:
				_rotate_user(0, -1.0)
			KEY_S:
				_rotate_user(0, 1.0)
			KEY_A:
				_rotate_user(1, 1.0)
			KEY_D:
				_rotate_user(1, -1.0)
			KEY_Q:
				_rotate_user(2, 1.0)
			KEY_E, KEY_R:
				_rotate_user(2, -1.0 if not event.shift_pressed else 1.0)
			KEY_SPACE:
				_user_rot = Vector3.ZERO
			KEY_C:
				var i := ANGLE_STEPS.find(_angle_step)
				_angle_step = ANGLE_STEPS[(i + 1) % ANGLE_STEPS.size()]
				_flash("Açı adımı: %d°" % _angle_step)
			KEY_BRACKETRIGHT, KEY_EQUAL, KEY_KP_ADD:
				_change_scale(1)
			KEY_BRACKETLEFT, KEY_MINUS, KEY_KP_SUBTRACT:
				_change_scale(-1)
			KEY_DELETE, KEY_BACKSPACE:
				_try_delete()
			KEY_F:
				_focus_camera()
			KEY_ESCAPE:
				if _selected.is_empty() and _giz_uid >= 0:
					_giz_uid = -1
					_place_gizmo()
				else:
					_cancel_hold()


const SCALES := [0.5, 0.625, 0.75, 0.875, 1.0, 1.25, 1.5, 1.75, 2.0]


func _change_scale(dir: int) -> void:
	if _selected.is_empty():
		return
	if not PartLibrary.get_def(_selected).get("category", "") in VesselBuilder.SCALABLE:
		_flash("Bu parça ölçeklenemez")
		return
	var i := SCALES.find(_scale)
	if i < 0:
		i = SCALES.find(1.0)
	_scale = SCALES[clampi(i + dir, 0, SCALES.size() - 1)]
	Sfx.play_ui("switch_2.ogg", -10.0, 0.8 + _scale * 0.3)


func _focus_camera() -> void:
	if is_instance_valid(_preview) and not _preview.parts.is_empty():
		_target = _craft_root.global_transform * _preview.com_local
		var ext := 0.0
		for p in _preview.parts:
			ext = maxf(ext, p.position.length() + p.size.length() * 0.5)
		_dist = clampf(ext * 2.4, 6.0, 90.0)


# ------------------------------------------------------------------ geri al / üzerine gelme

func _push_undo() -> void:
	_undo.append(craft.duplicate(true))
	if _undo.size() > 60:
		_undo.pop_front()
	_redo.clear()


func _undo_step(from: Array[Dictionary], to: Array[Dictionary]) -> void:
	if from.is_empty():
		return
	to.append(craft.duplicate(true))
	craft = from.pop_back()
	_name_edit.text = craft.get("name", "")
	Sfx.play_ui("switch_3.ogg", -8.0, 1.1)
	_rebuild()


func _part_under_mouse() -> Part:
	if not is_instance_valid(_preview) or get_viewport().gui_get_hovered_control() != null:
		return null
	var mouse := _mouse()
	var from := _cam.project_ray_origin(mouse)
	return _preview.pick_part(from, from + _cam.project_ray_normal(mouse) * 200.0)


func _update_hover() -> void:
	var part: Part = _part_under_mouse() if _selected.is_empty() else null
	if part != _hover_part:
		_set_overlay(_hover_part, null)
		_set_overlay(part, _hover_mat)
		_hover_part = part
	if part != null:
		var idx: int = _part_entry.get(part, -1)
		var sc: float = (craft["parts"][idx] as Dictionary).get("scale", 1.0) if idx >= 0 else 1.0
		_hover_label.text = "%s%s\n%d kg · %d HP\nSol tık: tut (takılı olanlarla) · Ctrl: kopyala · Sağ tık: pencere · Del: sil" % [
			part.title, "  ×%.2f" % sc if not is_equal_approx(sc, 1.0) else "", part.get_mass(), part.max_hp]
		_hover_label.position = _mouse() + Vector2(18, 14)
		_hover_label.visible = true
	else:
		_hover_label.visible = false
	if not _selected.is_empty():
		var def := PartLibrary.get_def(_selected)
		var on_center: bool = not _placement.is_empty() and absf((_placement["pos"] as Vector3).x) < 0.01
		_place_label.text = "%s  ·  ölçek ×%.2f  ·  dönüş X%+d° Y%+d° Z%+d°  (adım %d°, C)  ·  simetri %s%s" % [
			def.get("title", _selected), _scale, _user_rot.x, _user_rot.y, _user_rot.z, _angle_step,
			_sym_label() + ("  ·  %d parça birlikte" % _held.size() if _held.size() > 1 else ""), "  ·  ORTA ÇİZGİ (tek)" if on_center and _placement.get("ok", false) else ""]
		_place_label.visible = true
	else:
		_place_label.visible = false


func _set_overlay(part: Part, mat: Material) -> void:
	if not is_instance_valid(part):
		return
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			n.material_overlay = mat


# ------------------------------------------------------------------ yerleştirme

func _select(id: String, scale := 1.0, roll := 0.0) -> void:
	# taşınmakta olan grup bırakılıyorsa yerine geri konur (paletten başka parça seçmek gibi)
	if not _held_restore.is_empty():
		craft = _held_restore
		_held_restore = {}
		if not _undo.is_empty():
			_undo.pop_back()
		_rebuild()
	_held = []
	_selected = id
	_user_rot = Vector3(0, 0, roll)
	_scale = scale
	_set_overlay(_hover_part, null)
	_hover_part = null
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == id)
	_clear_ghosts()
	if not id.is_empty():
		_close_part_panel()
		_ghost = _ghost_for(0, 0, false)
	_refresh_nodes()


func _clear_ghosts() -> void:
	for k in _ghost_nodes:
		if is_instance_valid(_ghost_nodes[k]):
			_ghost_nodes[k].queue_free()
	_ghost_nodes.clear()
	_ghost = null
	_ghost_mirror = null


## Hayalet düğümü: üye m (0 = kök, >0 tutulan grubun diğer parçaları), simetri kopyası c.
func _ghost_for(m: int, c: int, mirrored: bool) -> Node3D:
	var key := "%d:%d" % [m, c]
	if _ghost_nodes.has(key) and is_instance_valid(_ghost_nodes[key]):
		return _ghost_nodes[key]
	var def: Dictionary
	var flip := mirrored
	if m == 0:
		if _held.is_empty():
			def = PartLibrary.get_def(_selected)
		else:
			var root: Dictionary = (_held[0] as Dictionary).duplicate()
			root.erase("scale")      # kökün ölçeği hayalet dönüşümünde (Shift+tekerlek)
			def = VesselBuilder.entry_def(String(root["part"]), root, 1.0)
			flip = flip != bool(root.get("flip", false))
	else:
		var e: Dictionary = _held[m]
		def = VesselBuilder.entry_def(String(e["part"]), e, float(e.get("scale", 1.0)))
		flip = flip != bool(e.get("flip", false))
	var node := _make_ghost_def(def, flip, String(def.get("title", "")))
	_craft_root.add_child(node)
	_ghost_nodes[key] = node
	return node


## Gövde parçası elde iken boştaki uç bağlantı noktalarını yeşil toplarla göster (KSP gibi).
func _refresh_nodes() -> void:
	for m in _node_markers:
		m.queue_free()
	_node_markers.clear()
	_nodes.clear()
	if _selected.is_empty() or not is_instance_valid(_preview):
		return
	var sel_def := PartLibrary.get_def(_selected)
	var pylon_mode := _pylon_load(sel_def)
	if not _is_axial(sel_def) and not pylon_mode:
		return
	if _node_mat == null:
		_node_mat = StandardMaterial3D.new()
		_node_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_node_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_node_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.8)
		_node_mat.no_depth_test = true
		_node_mat.render_priority = 5
	if pylon_mode:
		# silah / dış yük elde: boştaki askı noktalarının alt ucunda yeşil top
		for p in _preview.parts:
			if not p.def.get("pylon", false):
				continue
			var pos := p.position - p.basis.y.normalized() * p.size.y * 0.5
			if _pylon_occupied(p, pos):
				continue
			_add_node(pos, -p.basis.y.normalized(), p)
		return
	var axial: Array[Part] = []
	for p in _preview.parts:
		if _is_axial(p.def):
			axial.append(p)
	for p in axial:
		for s in [-1.0, 1.0]:
			var dir: Vector3 = p.basis.z.normalized() * s
			var centers: Array[Vector3] = [p.position + dir * p.size.z * 0.5]
			# ikiz motor adaptörü: arka yüzde yan yana iki yuva
			if s > 0.0 and p.def.has("rear_nodes"):
				centers.clear()
				for fx in p.def["rear_nodes"]:
					centers.append(p.position + dir * p.size.z * 0.5 + p.basis.x.normalized() * float(fx) * p.size.x)
			for pos in centers:
				var occupied := false
				for q in axial:
					if q != p and q.local_aabb(0.0).has_point(pos + dir * 0.3):
						occupied = true
						break
				if not occupied:
					_add_node(pos, dir, p)


func _add_node(pos: Vector3, dir: Vector3, p: Part) -> void:
	_nodes.append({"pos": pos, "dir": dir, "part": p})
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	mi.mesh = sm
	mi.material_override = _node_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	_craft_root.add_child(mi)
	_node_markers.append(mi)


## Uç uca eksen boyunca takılan parça mı (yüzeye takılan sensörler hariç).
func _is_axial(def: Dictionary) -> bool:
	return def.get("category", "") in AXIAL and def.get("mount", "") == ""


## Askıya takılacak yük mü (silah, savunma podu, dış yük; askının kendisi ve uca takılanlar hariç).
func _pylon_load(def: Dictionary) -> bool:
	return def.get("category", "") in ["silah", "savunma", "harici"] and not def.get("pylon", false) and def.get("mount", "") == ""


## Askının altında zaten bir yük var mı.
func _pylon_occupied(pylon: Part, attach: Vector3) -> bool:
	for q in _preview.parts:
		if q == pylon or q.def.get("pylon", false):
			continue
		var d := q.position - attach
		if absf(d.x) < 0.25 and absf(d.z) < pylon.size.z * 0.6 and d.y < 0.05 and d.y > -1.5:
			return true
	return false


func _make_ghost(id: String, mirrored: bool) -> Node3D:
	return _make_ghost_def(PartLibrary.get_def(id), mirrored, id)


## Hayalet (yarı saydam önizleme) bir parça tanımından. Ayarlanabilir kanat / esnetilmiş gövde
## gibi kayda özel tanımlarda ağ önbelleği anahtarı görselin kendisinden üretilir.
func _make_ghost_def(def: Dictionary, mirrored: bool, id: String) -> Node3D:
	var root := Node3D.new()
	var visual := Node3D.new()
	visual.position = def.get("visual_pivot", Vector3.ZERO)
	visual.scale = Vector3.ONE * float(def.get("_scale", 1.0))
	if mirrored and def.get("mirror_visual", false):
		visual.scale.x = -visual.scale.x
	var visuals: Array = def.get("visuals", [])
	for i in visuals.size():
		var v: Dictionary = visuals[i]
		if v.has("parent") or v.get("noscale", false) or v.get("mat", "") in ["flame", "flame_core", "heat_haze"]:
			continue
		var mi := VesselBuilder._make_mesh(v, "%s:%d:%d" % [id, i, v.hash()])
		mi.material_overlay = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(mi)
	root.add_child(visual)
	root.visible = false
	return root


var _ui_root: Control
var _cursor_icon: TextureRect


## Seçili parçanın küçük resmi imlecin ucunda (imleç paneldeyken: tıklamanın işe yaradığı görülsün).
func _update_cursor_icon(show: bool) -> void:
	if not is_instance_valid(_cursor_icon):
		if not is_instance_valid(_ui_root):
			return
		_cursor_icon = TextureRect.new()
		_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_cursor_icon.size = Vector2(72, 72)
		_cursor_icon.modulate = Color(1, 1, 1, 0.9)
		_ui_root.add_child(_cursor_icon)
	_cursor_icon.visible = show and _cards.has(_selected)
	if _cursor_icon.visible:
		_cursor_icon.texture = (_cards[_selected] as Button).icon
		_cursor_icon.position = get_viewport().get_mouse_position() + Vector2(10, 10)
		_cursor_icon.move_to_front()


func _update_ghost() -> void:
	if _selected.is_empty() or not is_instance_valid(_ghost):
		_update_cursor_icon(false)
		return
	var over_ui := get_viewport().gui_get_hovered_control() != null and _fake_mouse.x < 0.0
	_update_cursor_icon(over_ui)
	_placement = {} if over_ui else _compute_placement(_mouse())
	for k in _ghost_nodes:
		_ghost_nodes[k].visible = false
	if _placement.is_empty():
		# KSP gibi: takılacak yer yokken de parça imlecin ucunda yüzer (soluk); uçağa yaklaşınca
		# yapışır ve yeşillenir. Bu hâlde tık yerleştirmez.
		if not over_ui and is_instance_valid(_cam):
			var mp := _mouse()
			var o := _cam.project_ray_origin(mp)
			var dir := _cam.project_ray_normal(mp)
			var n := -_cam.global_basis.z
			var denom := dir.dot(n)
			var dist := (_target - o).dot(n) / denom if absf(denom) > 0.01 else 10.0
			var at := o + dir * clampf(dist, 3.0, 200.0)
			var g := _ghost_for(0, 0, false)
			var local := _craft_root.global_transform.affine_inverse() * at
			g.transform = Transform3D(Basis.from_euler(_user_rot * (PI / 180.0)) * Basis.from_scale(Vector3.ONE * _effective_scale()), local)
			g.visible = true
			_ghost_mat.albedo_color = Color(0.85, 0.9, 1.0, 0.3)
		return
	var pos: Vector3 = _placement["pos"]
	var rot: Vector3 = _placement["rot"]
	var t := Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos)
	# simetri kopyaları (ayna ya da radyal): kayıtla aynı kurallar (VesselBuilder.copy_ops)
	var ops := VesselBuilder.copy_ops(_sym_entry(_placement))
	var root_xf := t * Transform3D(Basis.from_scale(Vector3.ONE * _effective_scale()), Vector3.ZERO)
	var inv_root := _held_root_xf.affine_inverse()
	for m in maxi(_held.size(), 1):
		var x := root_xf if m == 0 else t * inv_root * VesselBuilder.entry_xform(_held[m])
		for c in ops.size():
			var node := _ghost_for(m, c, ops[c]["mirror"])
			node.transform = VesselBuilder.apply_op(ops[c], x)
			node.visible = true
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.45) if _placement["ok"] else Color(1.0, 0.3, 0.25, 0.35)


## Yerleştirmenin simetrisi (kayda yazılacak alanlar): {} tek, {"mirror": true} ayna,
## {"radial": n, "axis": [x, y]} takıldığı parçanın ekseni çevresinde n kopya.
func _sym_entry(pl: Dictionary) -> Dictionary:
	if not symmetry or pl.is_empty() or not pl.get("ok", false):
		return {}
	var pos: Vector3 = pl["pos"]
	if _sym_mode == "mirror":
		return {"mirror": true} if absf(pos.x) > SNAP else {}
	var c := Vector2.ZERO
	var pp: Variant = pl.get("parent")
	if pp is Part and is_instance_valid(pp):
		c = Vector2((pp as Part).position.x, (pp as Part).position.y)
	if Vector2(pos.x, pos.y).distance_to(c) < SNAP * 2.0:
		return {}      # eksenin üstünde: tek parça
	return {"radial": _radial, "axis": [c.x, c.y]}


func _sym_label() -> String:
	if not symmetry:
		return "kapalı"
	return "ayna ×2" if _sym_mode == "mirror" else "radyal ×%d" % _radial


## V: simetri türü — ayna → radyal 2 → 3 → 4 → 6 → 8 → ayna.
func _cycle_sym() -> void:
	symmetry = true
	if _sym_mode == "mirror":
		_sym_mode = "radial"
		_radial = 2
	else:
		var order := [2, 3, 4, 6, 8]
		var i := order.find(_radial)
		if i < 0 or i == order.size() - 1:
			_sym_mode = "mirror"
		else:
			_radial = order[i + 1]
	Sfx.play_ui("switch_2.ogg", -10.0, 1.2)
	_flash("Simetri: " + _sym_label())
	_sync_sym_ui()


func _sync_sym_ui() -> void:
	if _sym_check:
		_sym_check.set_pressed_no_signal(symmetry)
		_sym_check.text = "Simetri: %s  (X · V tür)" % _sym_label()


func _effective_scale() -> float:
	var cat: String = PartLibrary.get_def(_selected).get("category", "")
	return _scale if cat in VesselBuilder.SCALABLE else 1.0


## Fare konumu için parçanın yeri ve dönüşü (uçak uzayında). ok=false ise boşlukta.
func _compute_placement(mouse: Vector2) -> Dictionary:
	var def := PartLibrary.get_def(_selected)
	var size: Vector3 = (def.get("size", Vector3.ONE) as Vector3) * _effective_scale()
	var cat: String = def.get("category", "")
	var extra := _user_rot
	if craft.get("parts", []).is_empty():
		return {"pos": Vector3.ZERO, "rot": _with_user(Vector3.ZERO), "ok": true}

	var from := _cam.project_ray_origin(mouse)
	var to := from + _cam.project_ray_normal(mouse) * 200.0
	var inv0 := _craft_root.global_transform.affine_inverse()
	# gövde parçası (ya da askıya takılacak yük): ekranda en yakın boş bağlantı noktasına yapış
	var on_pylon := _pylon_load(def)
	if (_is_axial(def) or on_pylon) and not _nodes.is_empty():
		var best: Dictionary = {}
		var best_d := 70.0
		for nd in _nodes:
			var wp: Vector3 = _craft_root.global_transform * (nd["pos"] as Vector3)
			if _cam.is_position_behind(wp):
				continue
			var d := _cam.unproject_position(wp).distance_to(mouse)
			if d >= best_d:
				continue
			# uçağın arkasında kalan (görünmeyen) noktayı seçme
			var cp := _cam.global_position
			var oq := PhysicsRayQueryParameters3D.create(cp, wp, 2)
			var oh := get_world_3d().direct_space_state.intersect_ray(oq)
			if not oh.is_empty() and cp.distance_to(oh["position"]) < cp.distance_to(wp) - 0.35:
				continue
			if d < best_d:
				best_d = d
				best = nd
		for i in _node_markers.size():
			_node_markers[i].scale = Vector3.ONE * (1.8 if _nodes[i] == best else 1.0)
		if not best.is_empty():
			var dir: Vector3 = best["dir"]
			var hp: Part = best["part"]
			var p0: Vector3 = (best["pos"] as Vector3) + dir * (size.y if on_pylon else size.z) * 0.5
			return {"pos": p0.snapped(Vector3.ONE * 0.001), "rot": _with_user(hp.rotation_degrees), "ok": true, "parent": hp}
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not is_instance_valid(_preview):
		# boşlukta: parça yine fareyi izler (kırmızı), uçağa yaklaştırınca yapışır
		var plane := Plane(-_cam.global_basis.z, _target)
		var wp: Variant = plane.intersects_ray(from, _cam.project_ray_normal(mouse))
		if wp == null:
			return {}
		return {"pos": inv0 * (wp as Vector3), "rot": _with_user(Vector3.ZERO), "ok": false}
	var inv := _craft_root.global_transform.affine_inverse()
	var p: Vector3 = inv * (hit["position"] as Vector3)
	var n: Vector3 = (inv.basis * (hit["normal"] as Vector3)).normalized()
	var hit_part := _preview.part_for_shape(hit.get("shape", -1))

	var pos := p
	var rot := Vector3.ZERO
	var hit_axial: bool = hit_part != null and _is_axial(hit_part.def)
	var mount: String = def.get("mount", "")
	if _is_axial(def) and hit_axial and absf(n.z) > 0.6:
		# eksen boyunca uç uca
		var s := signf(n.z)
		pos = hit_part.position + Vector3(0, 0, s * (hit_part.size.z * 0.5 + size.z * 0.5))
	elif mount == "tip":
		# kanat ucu: dokunulan yüzeyden dışarı (kanadın uç yüzü ±x)
		pos = p + Vector3(signf(n.x) if absf(n.x) > 0.3 else signf(p.x), 0, 0) * size.x * 0.5
	elif mount == "surface":
		pos = p + n * minf(size.x, size.y) * 0.5
	elif cat in ["kanat", "kontrol"]:
		# yüzeyin açısını al (KSP gibi): yanda yatay, üstte dikey kuyruk, arada dihedral;
		# açı, açı adımına yapışır (C ile değişir)
		var ang := rad_to_deg(atan2(n.y, n.x))
		ang = snappedf(ang, _angle_step)
		var d := Vector3(cos(deg_to_rad(ang)), sin(deg_to_rad(ang)), 0.0)
		pos = p + d * size.x * 0.5
		rot = Vector3(0, 0, ang)
	elif cat == "iniş takımı":
		pos = p
	elif cat in ["silah", "savunma", "harici"]:
		pos = p - Vector3(0, size.y * 0.5, 0)
	else:
		pos = p + n * minf(size.x, size.y) * 0.5
	pos = pos.snapped(Vector3.ONE * SNAP)
	if absf(pos.x) < CENTER_SNAP:
		pos.x = 0.0      # orta çizgiye yapış: tek parça (burun takımı, dikey kuyruk), ayna kopya yok
	if symmetry and _sym_mode == "mirror" and pos.x < -SNAP and cat in ["kanat", "kontrol"]:
		pos.x = -pos.x   # simetride kaydı hep sağ taraf olarak tut, sol taraf ayna kopya
		rot.z = 180.0 - rot.z
	rot = _with_user(rot)
	return {"pos": pos, "rot": rot, "ok": true, "parent": hit_part}


## Yerleştirme dönüşüne kullanıcının açı adımlı dönüşünü (parçanın kendi eksenlerinde) ekle.
func _with_user(rot_deg: Vector3) -> Vector3:
	if _user_rot == Vector3.ZERO:
		return rot_deg
	var b := Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_euler(_user_rot * (PI / 180.0))
	return (b.get_euler() * (180.0 / PI)).snapped(Vector3.ONE * 0.01)


func _rotate_user(axis: int, sign: float) -> void:
	if _selected.is_empty():
		return
	_user_rot[axis] = fposmod(_user_rot[axis] + sign * _angle_step + 180.0, 360.0) - 180.0
	Sfx.play_ui("switch_2.ogg", -14.0, 1.4)


func _try_place(keep_selection: bool) -> void:
	if _selected.is_empty() or _placement.is_empty() or not _placement["ok"]:
		return
	var pos: Vector3 = _placement["pos"]
	var rot: Vector3 = _placement["rot"]
	var parts: Array = craft["parts"]
	var sym := _sym_entry(_placement)
	var parent_uid := -1
	var pp: Variant = _placement.get("parent")
	if pp is Part and is_instance_valid(pp) and _part_entry.has(pp):
		parent_uid = int(parts[_part_entry[pp]].get("uid", -1))
	var group: Array
	if _held.is_empty():
		group = [{"part": _selected, "uid": CraftTree.next_uid(craft)}]
	else:
		# taşınan grup: kök yeni yerine, takılı olanlar onunla birlikte (simetri kuralları CraftTree'de)
		var t_new := Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos)
		group = CraftTree.transform_group(craft, _held.duplicate(true), t_new * _held_root_xf.affine_inverse(), sym)
	var entry: Dictionary = group[0]
	entry["pos"] = [pos.x, pos.y, pos.z]
	if rot != Vector3.ZERO:
		entry["rot"] = [rot.x, rot.y, rot.z]
	else:
		entry.erase("rot")
	CraftTree.set_sym(entry, sym)
	var sc := _effective_scale()
	if not is_equal_approx(sc, 1.0):
		entry["scale"] = sc
	else:
		entry.erase("scale")
	if parts.is_empty():
		entry["parent"] = -1
	elif parent_uid >= 0:
		entry["parent"] = parent_uid
	else:
		entry.erase("parent")    # takıldığı parça bilinmiyor: kurulumda temastan bağlanır (CraftTree.ensure)
	if _held_restore.is_empty():
		_push_undo()      # taşımada geri alma noktası tutarken kondu
	_held_restore = {}
	var first := parts.size()
	parts.append_array(group)
	Sfx.click()
	_rebuild()
	_pop(first)
	if keep_selection and not _held.is_empty():
		# Shift: aynı grubun bir kopyası elde kalsın (yeni uid'lerle)
		var again: Array = []
		for e: Dictionary in _held:
			again.append(e.duplicate(true))
		CraftTree.renumber(craft, again)
		_held = again
		return
	var need := _missing_requirement(PartLibrary.get_def(String(entry["part"])))
	if need != "":
		_flash("⚠ " + need)
	if not keep_selection:
		_select("")


## Takılı parçayı tut: kayıttan çıkar ve aynı ölçekle elde taşı.
func _try_pick_up(copy := false) -> void:
	var part := _part_under_mouse()
	if part == null or not _part_entry.has(part):
		_close_part_panel()
		return
	_grab(_part_entry[part], copy)


func _try_delete() -> void:
	var part := _hover_part if is_instance_valid(_hover_part) else _part_under_mouse()
	if part == null or not _part_entry.has(part):
		return
	_delete_entry(_part_entry[part])


# ------------------------------------------------------------------ istatistikler

func _update_stats() -> void:
	if _stats == null:
		return
	if not is_instance_valid(_preview) or _preview.parts.is_empty():
		_stats.text = "Parça yok.\nSoldan bir kokpit seçip yerleştir."
		_warn.text = ""
		_com_marker.visible = false
		_col_marker.visible = false
		if is_instance_valid(_mcheck):
			_mcheck.refresh(null)
		if is_instance_valid(_dash):
			_dash.set_data({"empty": true})
		_warn_markers([])
		return
	var v := _preview
	var dry := 0.0
	var cost := 0
	for p in v.parts:
		dry += p.dry_mass
		cost += int(p.def.get("cost", 0))
	var thrust := 0.0
	var wing_area := 0.0
	var col := Vector3.ZERO
	var col_area := 0.0
	var has_gear := false
	var guns := 0
	var intake_area := 0.0
	var missiles := 0
	var radar_missiles := 0
	for m in v.modules:
		if m is EngineModule:
			thrust += m.max_thrust
		elif m is WingModule:
			wing_area += m.area
			var n: Vector3 = m.part.basis.y
			if absf(n.y) > 0.7:
				col += m.ac_local() * m.area
				col_area += m.area
		elif m is LandingGearModule:
			has_gear = true
		elif m is IntakeModule:
			intake_area += m.area
		elif m is GunModule:
			guns += 1
		elif m is MissileModule:
			missiles += 1
			radar_missiles += 1 if m.radar_guided else 0
	var mass := v.mass
	var intake_need := thrust / 70000.0 * 0.5
	var intake_pct := intake_area / intake_need if intake_need > 0.0 else 1.0
	var static_thrust := _thrust_at(v, 0.0, 0.0, true)   # duran uçakta (ramjette 0)
	var tw := static_thrust / maxf(mass * 9.81, 1.0)
	var com := v.com_local
	_com_marker.visible = true
	_com_marker.position = com
	var margin := 0.0
	if col_area > 0.0:
		col /= col_area
		_col_marker.visible = true
		_col_marker.position = col
		margin = col.z - com.z   # pozitif: kaldırma merkezi arkada = kararlı
	else:
		_col_marker.visible = false
	var stall_speed := sqrt(2.0 * mass * 9.81 / (1.225 * maxf(wing_area, 0.1) * 1.2)) * 3.6

	_stats.text = "\n".join(PackedStringArray([
		"Parça            %d" % v.parts.size(),
		"Kütle (dolu)     %d kg" % mass,
		"Kütle (boş)      %d kg" % dry,
		"Yakıt            %d kg" % v.fuel_capacity(),
		"İtki (AB, duran) %d kN" % (static_thrust / 1000.0),
		"İtki / ağırlık   %.2f" % tw,
		"Kumanda          %s" % {"fbw": "FBW (sınırlı)", "hydro": "hidrolik", "mech": "mekanik"}.get(PlayerController.fcs_for(v.cockpit()), "—"),
		"Kanat alanı      %.1f m²" % wing_area,
		"Tahmini stall    %d km/sa" % stall_speed,
		"Kararlılık payı  %+.2f m" % margin,
		"Hava alığı       %d%%" % (intake_pct * 100.0),
		("Silah            %d top · %d füze" % [guns, missiles]) + ((" (%d radar)" % radar_missiles) if radar_missiles > 0 else ""),
		"Maliyet          %d" % cost,
	]))
	_stats.text += "

" + _performance(v, thrust, wing_area, com)
	_stats.text += Designs.stats_block(craft)   # hizmet geçmişi, seri üretim, prototip parçalar
	# görsel pano: karakter altıgeni, denge terazisi, göstergeler, pist (DesignDashboard)
	if is_instance_valid(_dash):
		var est: Dictionary = MissionCheck.estimate(v) if thrust > 0.0 and wing_area >= 1.0 else {}
		var lim := StructLimits.estimate(v)   # deniz seviyesinde kopma hızı / G, ilk giden parça
		var zmin := INF
		var zmax := -INF
		var hp_sum := 0.0
		for p in v.parts:
			var bb := p.local_aabb(0.0)
			zmin = minf(zmin, bb.position.z)
			zmax = maxf(zmax, bb.end.z)
			hp_sum += p.max_hp
		_dash.set_data({
			"v0_kmh": float(est.get("v0", 0.0)) * 3.6, "mach": float(est.get("v0", 0.0)) / Atmosphere.SPEED_OF_SOUND,
			"climb": float(est.get("climb", 0.0)), "range_km": float(est.get("range_km", 0.0)),
			"dto": float(est.get("dto", 0.0)), "can_roll": bool(est.get("can_roll", thrust > 0.0)),
			"tw": tw, "wing_load": mass / maxf(wing_area, 0.1), "intake": intake_pct,
			"guns": guns, "missiles": missiles, "bombs": v.bombs_left(false) + v.bombs_left(true),
			"hp": hp_sum, "mass": mass, "com_z": com.z, "col_z": col.z, "has_col": col_area > 0.0,
			"dry_z": com.z + float(est.get("cg_shift", 0.0)), "z_min": zmin, "z_max": zmax,
			"vne_kmh": float(lim["vne"]) * 3.6, "g_break": float(lim["g"]),
			"vne_part": lim["vne_part"], "g_part": lim["g_part"],
		})
	# uyarılar: tıklanınca ilgili parçalar yanıp söner ([url=tür])
	var warns := PackedStringArray()
	var warn_kinds: Array[String] = []   # Array (referans): lambda içinden eklenir
	var w := func(text: String, kind: String) -> void:
		warns.append("[url=%s]• %s[/url]" % [kind, text])
		if not warn_kinds.has(kind):
			warn_kinds.append(kind)
	if v.cockpit_part() == null:
		w.call("Kokpit yok — uçak kontrol edilemez", "cockpit")
	if thrust <= 0.0:
		w.call("Motor yok", "engine")
	elif tw < 0.35:
		w.call("İtki çok düşük", "engine")
	if thrust > 0.0 and intake_pct < 0.99:
		w.call("Hava alığı yetersiz (%%%d) — motor tam güç veremez" % (intake_pct * 100.0), "intake")
	if v.fuel_capacity() <= 0.0 and thrust > 0.0:
		w.call("Yakıt yok", "fuel")
	if wing_area < 1.0:
		w.call("Kanat yok — uçamaz", "wing")
	if col_area > 0.0 and margin < 0.0:
		w.call("KARARSIZ: kaldırma merkezi ağırlık merkezinin önünde — kanadı geri al ya da ağırlığı öne", "wing")
	elif col_area > 0.0 and margin < 0.4:
		# hafif uyarı: 3B ⚠ yok (panodaki denge terazisi zaten sarı gösteriyor)
		warns.append("[url=wing]• Kararlılık payı çok az (çevik ama zor uçar)[/url]")
	if not has_gear:
		w.call("İniş takımı yok — pistten kalkamaz", "gear")
	else:
		# ana takım ağırlık merkezinin arkasında olmalı (yoksa uçak kuyruğu üstüne oturur)
		var behind := false
		for m in v.modules:
			if m is LandingGearModule and m.part.position.z > com.z + 0.1:
				behind = true
		if not behind:
			w.call("Bütün takımlar ağırlık merkezinin önünde — uçak kuyruğu üstüne oturur", "gear")
		# yerden yükseklik: tekerlekler yükte ~0.25 m sıkışır; gövde / motor / yük yere değmesin.
		# Değerse pistte sürtünür, hasar alır (hidrolik sızıntı buradan çıkıyordu)
		var wheel_low := INF
		var main_z := 0.0
		var n_main := 0
		for m in v.modules:
			if m is LandingGearModule:
				var gs := float(m.part.def.get("_scale", 1.0))
				wheel_low = minf(wheel_low, m.part.position.y - (m.rest_length + m.wheel_radius) * gs)
				if not m.steerable:
					main_z += m.part.position.z
					n_main += 1
		if wheel_low < INF:
			main_z /= maxf(n_main, 1)
			var body_low := INF
			var strike := ""
			for p in v.parts:
				if p.modules.any(func(mm: PartModule) -> bool: return mm is LandingGearModule):
					continue
				var bb := p.local_aabb(0.0)
				body_low = minf(body_low, bb.position.y)
				# kalkışta ~8° burun kalkınca ana takımın arkası alçalır. Gövde parçasında gerçek uç
				# yarıçapları (daralan kuyruk, yukarı kalkık rampa), diğerlerinde kutunun arka alt köşesi
				var pts: Array[Vector2] = []   # (z, alt y)
				var ends := VesselBuilder._body_ends(p)
				if not ends.is_empty():
					pts.append(Vector2(ends["zf"], p.position.y - float(ends["rf"])))
					pts.append(Vector2(ends["zr"], p.position.y - float(ends["rr"])))
				else:
					pts.append(Vector2(bb.end.z, bb.position.y))
				for q in pts:
					if q.x > main_z and q.y - wheel_low - (q.x - main_z) * tan(deg_to_rad(8.0)) < 0.05:
						strike = p.title
			var clearance := body_low - wheel_low
			if clearance < 0.3:
				w.call("Takımlar kısa: gövde yere %.2f m kalıyor, pistte sürtünür ve hasar alır — uzun takım seç" % maxf(clearance, 0.0), "gear")
			elif strike != "":
				w.call("Kalkışta burun kalkınca %s piste vurur — ana takımı geri al ya da uzun takım seç" % strike, "gear")
	# kumanda yetkisi: yunuslama / yatış / sapmaya bakan yüzey (ya da TVC) var mı
	var auth := Vector3.ZERO
	for m in v.modules:
		if m is ControlSurfaceModule:
			auth += m.axis_weights.abs()
		elif m is EngineModule and m.gimbal > 0.0:
			auth += Vector3(1, 1, 0)
	if v.cockpit_part() != null and wing_area >= 1.0:
		if auth.x < 0.1:
			w.call("Yunuslama kumandası yok — irtifa dümeni / elevon / stabilatör ekle", "control")
		if auth.z < 0.1:
			w.call("Yatış kumandası yok — kanada kanatçık / elevon ekle", "control")
		if auth.y < 0.1:
			w.call("Sapma kumandası yok — dikey kuyruğa dümen ekle", "control")
	if v.bombs_left(true) > 0 and v.targeting_pod() == null:
		w.call("Lazer bomba var ama hedefleme podu yok — güdümsüz düşer", "pod")
	if v.radar_missiles_left() > 0 and v.radar() == null:
		w.call("Radar füzesi var ama radar yok — atılamaz", "radar")
	_warn_count = warn_kinds.size()   # hafif uyarılar (kararlılık payı az) mührü bozmaz
	if Game.args.has("printwarn"):
		print("WARN %s: %s" % [craft.get("name", "?"), " | ".join(warns)])
	_warn.text = "\n".join(warns) if not warns.is_empty() else "Uçuşa hazır ✓"
	_warn.add_theme_color_override("default_color", Color(1.0, 0.55, 0.45) if not warns.is_empty() else Color(0.45, 1.0, 0.6))
	_warn_markers(PackedStringArray(warn_kinds))
	if is_instance_valid(_mcheck):
		_mcheck.refresh(v)


# ------------------------------------------------------------------ kaydet / yükle / uç

func _new_craft() -> void:
	if not (craft.get("parts", []) as Array).is_empty():
		_push_undo()
	craft ={"name": "Yeni Uçak", "parts": [], "units": PartLibrary.WORLD_SCALE}
	_name_edit.text = craft["name"]
	_rebuild()


func _save() -> void:
	craft["name"] = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "İsimsiz"
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := USER_DIR + (craft["name"] as String).validate_filename() + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_flash("Kaydedilemedi!")
		return
	Designs.ensure_id(craft)   # kalıcı tasarım kimliği (hizmet kaydı, seri üretim)
	f.store_string(JSON.stringify(craft, "\t"))
	f.close()
	_flash("Kaydedildi: %s" % craft["name"])
	# büro mührü: kusursuz tasarım ONAYLANDI, kusurlu ise TASLAK
	_stamp_anim("ONAYLANDI" if _warn_count == 0 else "TASLAK", Color(0.35, 0.95, 0.55) if _warn_count == 0 else Color(1.0, 0.75, 0.25))


var _warn_count := 0          ## son _update_stats'taki uyarı sayısı (mühür ve çizim)
var _blueprint_layer: CanvasLayer


## Teknik çizim aç / kapa (hangar/blueprint_view.gd). Tık ya da Esc kapatır.
func _toggle_blueprint() -> void:
	if is_instance_valid(_blueprint_layer):
		_blueprint_layer.queue_free()
		_blueprint_layer = null
		return
	_blueprint_layer = CanvasLayer.new()
	_blueprint_layer.layer = 30
	add_child(_blueprint_layer)
	var bp := BlueprintView.new()
	_blueprint_layer.add_child(bp)
	var number: String = str((craft.get("paint", {}) as Dictionary).get("number", "—"))
	bp.set_vessel(_preview, {"name": _name_edit.text.strip_edges(), "warns": _warn_count, "number": number})
	bp.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE):
			_toggle_blueprint())
	Sfx.play_ui("switch_3.ogg", -6.0, 0.8)


## Ekranın ortasına eğik lastik mühür vurulur, sonra solar.
func _stamp_anim(word: String, col: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 31
	add_child(layer)
	var l := Label.new()
	l.text = word
	l.add_theme_font_size_override("font_size", 72)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(col, 0.5))
	l.add_theme_constant_override("outline_size", 6)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New"])
	mono.font_weight = 700
	l.add_theme_font_override("font", mono)
	layer.add_child(l)
	l.reset_size()
	var vs := get_viewport().get_visible_rect().size
	l.pivot_offset = l.size * 0.5
	l.position = vs * 0.5 - l.size * 0.5
	l.rotation = -0.18
	l.scale = Vector2.ONE * 1.8
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.12)
	tw.tween_callback(func() -> void: Sfx.play_ui("hydraulic_thunk.ogg", -2.0, 1.5))
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(layer.queue_free)


const LOAD_GROUPS := ["Avcı", "Saldırı", "Destek & Nakliye", "Deneysel", "Sivil", "Benim uçaklarım", "Diğer"]


func _open_load() -> void:
	for c in _load_list.get_children():
		c.queue_free()
	# hazır uçaklar kendi "group" alanına göre, oyuncunun kaydettikleri ayrı grupta
	var groups := {}
	for dir_path in ["res://crafts/", USER_DIR]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		var names := d.get_files()
		names.sort()
		for file in names:
			if not file.ends_with(".json"):
				continue
			var data := VesselBuilder.load_craft(dir_path + file)
			if data.is_empty():
				continue
			var g: String = "Benim uçaklarım" if dir_path == USER_DIR else String(data.get("group", "Diğer"))
			if not g in LOAD_GROUPS:
				g = "Diğer"
			if not groups.has(g):
				groups[g] = []
			groups[g].append(data)
	var first: Dictionary = {}
	for g in LOAD_GROUPS:
		if not groups.has(g):
			continue
		var head := Label.new()
		head.text = g.to_upper()
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
		_load_list.add_child(head)
		for data: Dictionary in groups[g]:
			if first.is_empty():
				first = data
			var b := Button.new()
			b.text = "  %s   ·  %d parça" % [data.get("name", "?"), _entry_count(data)]
			if Designs.short_line(data) != "":
				b.text += "   ·  " + Designs.short_line(data) + ("  ·  SERİ ÜRETİMDE" if Designs.is_fleet(data) else "")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.mouse_entered.connect(func() -> void: _show_load_preview(data))
			b.pressed.connect(func() -> void:
				_push_undo()
				craft = data.duplicate(true)
				_name_edit.text = craft.get("name", "")
				_rebuild()
				if Designs.service_line(craft) != "":
					_flash("Hizmet geçmişi — " + Designs.service_line(craft))
				_load_popup.hide())
			_load_list.add_child(b)
	_load_popup.popup_centered(Vector2i(900, 540))
	if not first.is_empty():
		_show_load_preview(first)


## Ayna kopyalar dahil parça sayısı.
static func _entry_count(data: Dictionary) -> int:
	var n := 0
	for e: Dictionary in data.get("parts", []):
		n += 2 if e.get("mirror", false) else 1
	return n


# ------------------------------------------------------------------ yükleme önizlemesi

var _pv_vp: SubViewport
var _pv_root: Node3D
var _pv_cam: Camera3D
var _pv_name: Label
var _pv_desc: Label
var _pv_stats: Label
var _pv_shown: Dictionary = {}
var _pv_floor: MeshInstance3D


func _build_load_preview() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(520, 270)
	_pv_vp = SubViewport.new()
	_pv_vp.own_world_3d = true
	_pv_vp.msaa_3d = Viewport.MSAA_4X
	_pv_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(_pv_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.72)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_pv_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.8
	_pv_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.6, 0.8, 1.0)
	_pv_vp.add_child(rim)
	_pv_root = Node3D.new()
	_pv_vp.add_child(_pv_root)
	# zemin: uçağın gölgesi düşen, kenarlara doğru kararan yuvarlak hangar zemini
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.34, 0.35, 0.37)
	fm.roughness = 0.35
	fm.metallic_specular = 0.6
	floor_mi.material_override = fm
	_pv_vp.add_child(floor_mi)
	_pv_floor = floor_mi
	for i in 3:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.995 - i * 0.25
		tm.outer_radius = 1.0 - i * 0.25
		ring.mesh = tm
		ring.scale = Vector3(1, 0.3, 1)
		ring.material_override = _std_mat(Color(0.9, 0.72, 0.1), 0.6)
		floor_mi.add_child(ring)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 120.0
	_pv_cam = Camera3D.new()
	_pv_cam.fov = 30.0
	_pv_vp.add_child(_pv_cam)
	col.add_child(box)
	_pv_name = Label.new()
	_pv_name.add_theme_font_size_override("font_size", 18)
	_pv_name.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	col.add_child(_pv_name)
	_pv_desc = Label.new()
	_pv_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pv_desc.custom_minimum_size = Vector2(520, 0)
	_pv_desc.add_theme_font_size_override("font_size", 13)
	_pv_desc.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
	col.add_child(_pv_desc)
	_pv_stats = Label.new()
	_pv_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pv_stats.custom_minimum_size = Vector2(520, 0)
	_pv_stats.add_theme_font_size_override("font_size", 13)
	_pv_stats.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	col.add_child(_pv_stats)
	return col


func _clear_load_preview() -> void:
	for c in _pv_root.get_children():
		c.queue_free()
	_pv_shown = {}


## Üzerine gelinen uçağı önizlemede kur, kamerayı sığdır, özet bilgileri yaz.
func _show_load_preview(data: Dictionary) -> void:
	if data == _pv_shown:
		return
	_clear_load_preview()
	_pv_shown = data
	var v := VesselBuilder.build(data.duplicate(true))
	v.freeze = true
	_pv_root.add_child(v)
	v.set_physics_process(false)
	v.set_cold()
	# sınır kutusu (parça konum ve boyutlarından)
	var box := AABB()
	var first := true
	for p in v.parts:
		var b := p.local_aabb(0.0)
		box = b if first else box.merge(b)
		first = false
	var center := box.get_center()
	v.position = -center
	var radius := maxf(box.size.length() * 0.5, 2.0)
	# zemin uçağın altında (tekerlek ya da gövde altı), uçaktan biraz geniş
	var low := box.position.y - center.y
	for p in v.parts:
		for m in p.modules:
			if m is LandingGearModule:
				low = minf(low, p.position.y - center.y - m.rest_length - m.wheel_radius)
	_pv_floor.position = Vector3(0, low - 0.02, 0)
	_pv_floor.scale = Vector3(radius * 1.3, 1, radius * 1.3)
	_pv_root.rotation = Vector3.ZERO
	var dir := Vector3(-1.0, 0.5, -0.8).normalized()    # önden-soldan-yukarıdan (burun -z)
	_pv_cam.position = dir * radius / sin(deg_to_rad(_pv_cam.fov * 0.5)) * 0.62
	_pv_cam.look_at(Vector3.ZERO, Vector3.UP)
	_pv_name.text = String(data.get("name", "İsimsiz"))
	_pv_desc.text = String(data.get("description", ""))
	_pv_stats.text = _craft_summary(data)


## Tanımlardan özet: kütle, yakıt, itki/ağırlık, silahlar, kilitli parçalar.
static func _craft_summary(data: Dictionary) -> String:
	var mass := 0.0
	var fuel := 0.0
	var thrust := 0.0
	var loads := {}
	for e: Dictionary in data.get("parts", []):
		var def := PartLibrary.get_def(String(e.get("part", "")))
		if def.is_empty():
			continue
		var k := 2 if e.get("mirror", false) else 1
		mass += float(def.get("mass", 0.0)) * k
		for m: Dictionary in def.get("modules", []):
			match String(m.get("type", "")):
				"fuel_tank":
					fuel += float(m.get("capacity", 0.0)) * k
				"engine":
					thrust += float(m.get("max_thrust", 0.0)) * k
				"missile":
					mass += (MissileModule.RADAR_MISSILE_MASS if m.get("guidance", "") == "radar" else MissileModule.MISSILE_MASS) * k
				"bomb":
					mass += BombModule.BOMB_MASS * k
		if def.get("category", "") in ["silah", "savunma", "sensör"] or e["part"] in ["refuel_probe"]:
			var t := String(def.get("title", e["part"]))
			loads[t] = int(loads.get(t, 0)) + k
	var full := mass + fuel
	var lines := PackedStringArray()
	lines.append("Kütle %d kg (dolu)  ·  yakıt %d kg  ·  itki %d kN  ·  T/W %.2f" % [full, fuel, thrust / 1000.0, thrust / maxf(full * 9.81, 1.0)])
	if not loads.is_empty():
		var items := PackedStringArray()
		for t in loads:
			items.append("%d× %s" % [loads[t], t] if loads[t] > 1 else t)
		lines.append("Donanım: " + ", ".join(items))
	var locked := Career.locked_parts_in(data)
	if not locked.is_empty():
		lines.append("🔒 Kilitli parça var (Ar-Ge gerekir)")
	if Designs.service_line(data) != "":
		lines.append("Hizmet: " + Designs.service_line(data))
	if Designs.is_fleet(data):
		lines.append("SERİ ÜRETİMDE — filo tipi")
	return "\n".join(lines)


func _launch() -> void:
	if not is_instance_valid(_preview) or _preview.cockpit_part() == null:
		_flash("Kokpit olmadan piste çıkılamaz")
		return
	var locked := Career.locked_parts_in(craft)
	if not locked.is_empty():
		_flash("Kilitli parça var (Ar-Ge'de aç): " + ", ".join(locked))
		return
	if not Crew.can_fly(Crew.selected):
		_flash("Uçacak pilot yok — Kadro'dan hazır bir pilot seç")
		_open_crew()
		return
	if not Game.pending_op.is_empty():
		_test_flight()
		return
	if not Career.sandbox() and Game.args.is_empty():
		# kariyer: uçak hazır, cephe haritasına dön (harekât oradan seçilir)
		craft["name"] = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "İsimsiz"
		Game.flight_craft = craft.duplicate(true)
		Game.menu_screen = "career"
		FloatingOrigin.world_root = null
		get_tree().change_scene_to_file("res://menu/main_menu.tscn")
		return
	_open_missions()


# ------------------------------------------------------------------ görev hazırlığı

## "Göreve çık" ile gelindi: üstte görev şeridi; PİSTE düğmesi test uçuşu olur, yanına
## "TAMAM — GÖREVE BAŞLA" eklenir, menü düğmesi hazırlığı iptal eder.
func _build_op_bar(root: Control, bar: HBoxContainer, launch: Button, menu_btn: Button) -> void:
	var op: Dictionary = Game.pending_op
	var def := MissionManager.get_def(String(op.get("mission", "")))
	launch.text = "  TEST UÇUŞU  "
	launch.tooltip_text = "Risksiz deneme uçuşu: para, kayıp, tecrübe yok. Uçuş bitince (Hangar) buraya dönülür."
	launch.add_theme_stylebox_override("normal", _flat(Color(0.18, 0.32, 0.5), 6))
	launch.add_theme_stylebox_override("hover", _flat(Color(0.24, 0.42, 0.62), 6))
	var go := Button.new()
	go.text = "  TAMAM ▶  "
	go.tooltip_text = "Brifinge geç ve göreve başla"
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_stylebox_override("normal", _flat(Color(0.12, 0.5, 0.28), 6))
	go.add_theme_stylebox_override("hover", _flat(Color(0.16, 0.62, 0.35), 6))
	go.add_theme_font_size_override("font_size", 17)
	go.pressed.connect(_confirm_op)
	# görev provası: kartın rotası, saati ve havası; düşmansız, risksiz
	var card := MissionCheck.card_for(op)
	if not card.is_empty():
		var reh := Button.new()
		reh.text = " PROVA "
		reh.focus_mode = Control.FOCUS_NONE
		reh.tooltip_text = "GÖREV PROVASI: aynı rota, saat ve hava; düşman yok, risk yok. Hedef işaretli, süre sayılır. Bitince (Hangar) buraya dönülür."
		reh.add_theme_stylebox_override("normal", _flat(Color(0.42, 0.32, 0.1), 6))
		reh.add_theme_stylebox_override("hover", _flat(Color(0.55, 0.42, 0.14), 6))
		reh.pressed.connect(_rehearsal)
		bar.add_child(reh)
	bar.add_child(go)
	menu_btn.text = "◀ Görevi bırak"
	# görev şeridi (üst çubuğun altında, ortada)
	var strip := PanelContainer.new()
	strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	strip.offset_top = 60
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sb := _flat(Color(0.05, 0.1, 0.07, 0.9), 8)
	sb.border_color = Color(0.45, 1.0, 0.65, 0.5)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = "GÖREV HAZIRLIĞI:  %s   ·   uçağı hazırla, istersen test uçuşu yap, sonra TAMAM" % String(def.get("title", op.get("mission", "")))
	l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	l.add_theme_font_size_override("font_size", 15)
	strip.add_child(l)
	root.add_child(strip)
	# görev kartı + canlı kontrol listesi (sağ panelin solunda)
	if not card.is_empty():
		l.text = "GÖREV HAZIRLIĞI:  %s   ·   kartı karşıla, provada dene, sonra TAMAM" % String(card.get("title", def.get("title", "")))
		_mcheck = MissionCheck.create(card)
		_mcheck.anchor_left = 1.0
		_mcheck.anchor_right = 1.0
		_mcheck.offset_left = -660
		_mcheck.offset_right = -310
		_mcheck.offset_top = 104
		root.add_child(_mcheck)


func _craft_ready() -> bool:
	if not is_instance_valid(_preview) or _preview.cockpit_part() == null:
		_flash("Kokpit olmadan uçulamaz")
		return false
	var locked := Career.locked_parts_in(craft)
	if not locked.is_empty():
		_flash("Kilitli parça var (Ar-Ge'de aç): " + ", ".join(locked))
		return false
	if not Crew.can_fly(Crew.selected):
		_flash("Uçacak pilot yok — Kadro'dan hazır bir pilot seç ya da al")
		_open_crew()
		return false
	craft["name"] = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "İsimsiz"
	Game.flight_craft = craft.duplicate(true)
	return true


## Test uçuşu: görevsiz, risksiz serbest uçuş; hazırlık (pending_op) korunur, Hangar ile dönülür.
func _test_flight() -> void:
	if not _craft_ready():
		return
	Game.mode = "career"
	Game.test_flight = true
	Game.mission_card = {}
	Game.mission = ""
	Game.mission_region = ""
	Game.free_start = "runway"
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://main.tscn")


## Tamam: kontrol listesinde ✗ varsa önce uyarı; sonra brifing ve gerçek görev (hazırlık biter).
func _confirm_op() -> void:
	if not _craft_ready():
		return
	var fails := _mcheck.failures() if is_instance_valid(_mcheck) else PackedStringArray()
	if fails.is_empty():
		_start_op()
		return
	var dlg := ConfirmationDialog.new()
	dlg.theme = _theme
	dlg.title = "Tasarım görevi karşılamıyor"
	dlg.dialog_text = "Kontrol listesinde eksikler var:\n\n✗ " + "\n✗ ".join(fails) + "\n\nYine de göreve başlansın mı?"
	dlg.ok_button_text = "Yine de başla"
	dlg.cancel_button_text = "Tasarıma dön"
	dlg.confirmed.connect(_start_op)
	dlg.visibility_changed.connect(func() -> void:
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


## Görev kartını ve tasarımın tahmini performansını uçuşa taşı (uçuş sonu değerlendirmesi için).
func _carry_card() -> void:
	Game.last_result = {}
	Game.mission_card = {}
	if is_instance_valid(_mcheck) and not _mcheck.card.is_empty():
		Game.mission_card = _mcheck.card.duplicate(true)
		Game.mission_card["design"] = _mcheck.est.duplicate(true)
		Game.mission_card["check"] = _mcheck.result.duplicate(true)


## Görev provası: kartın rotası/saati/havası, düşmansız; test uçuşu gibi risksiz, hazırlık sürer.
func _rehearsal() -> void:
	if not _craft_ready():
		return
	_carry_card()
	Game.mode = "career"
	Game.test_flight = true
	Game.rehearsal = true
	Game.mission = ""
	Game.mission_region = ""
	Game.free_start = "runway"
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://main.tscn")


func _start_op() -> void:
	var op: Dictionary = Game.pending_op
	var id := String(op.get("mission", ""))
	Briefing.open(self, id, String(craft.get("name", "")), func() -> void:
		_carry_card()
		Game.rehearsal = false
		Game.pending_op = {}
		Game.mode = "career"
		Game.test_flight = false
		Game.mission = id
		Game.mission_region = String(op.get("region", ""))
		Game.free_start = "runway"
		Game.menu_screen = "career"
		FloatingOrigin.world_root = null
		get_tree().change_scene_to_file("res://main.tscn"))

func _start_flight(mission_id: String) -> void:
	Game.mission = mission_id
	craft["name"] = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "İsimsiz"
	Game.flight_craft = craft.duplicate(true)
	FloatingOrigin.world_root = null
	get_tree().change_scene_to_file("res://main.tscn")


func _flash(text: String) -> void:
	_status.text = text
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if _status.text == text:
			_status.text = "")


# ------------------------------------------------------------------ arayüz

func _build_ui() -> void:
	_theme = UiTheme.get_theme()
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	_ui_root = root
	layer.add_child(root)

	# üst çubuk
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 54
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	top.add_child(bar)
	var menu_btn := Button.new()
	menu_btn.text = "◀ Menü" if Career.sandbox() else "◀ Cephe"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func() -> void:
		Game.pending_op = {}       # görev hazırlığı varsa bırakılır
		Game.test_flight = false
		Game.rehearsal = false
		if not (craft.get("parts", []) as Array).is_empty() and _preview and _preview.cockpit_part() != null:
			craft["name"] = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "İsimsiz"
			Game.flight_craft = craft.duplicate(true)
		FloatingOrigin.world_root = null
		get_tree().change_scene_to_file("res://menu/main_menu.tscn"))
	bar.add_child(menu_btn)
	var title := Label.new()
	title.text = "HANGAR"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	bar.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 190
	_name_edit.placeholder_text = "Uçak adı"
	bar.add_child(_name_edit)
	# kısa etiket + açıklama ipucu: üst çubuk 1600 px'te de sığsın
	for spec in [["Yeni", _new_craft, ""], ["Yükle", _open_load, ""], ["Kaydet", _save, ""],
			["Üretim", func() -> void: ProductionDialog.open(self), "Seri üretim"],
			["Tünel", _toggle_tunnel, "Rüzgâr tüneli: akış, stall, yük haritası"],
			["Çizim", _toggle_blueprint, "Teknik çizim: üç görünüş, ölçüler, onay mührü"]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		bar.add_child(b)
	_pilot_btn = Button.new()
	_pilot_btn.focus_mode = Control.FOCUS_NONE
	_pilot_btn.pressed.connect(_open_crew)
	bar.add_child(_pilot_btn)
	_refresh_pilot_btn()
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	bar.add_child(_money_label)
	Career.changed.connect(_refresh_money)
	_refresh_money()
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.clip_text = true                     # uzun mesaj çubuğu genişletmesin
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	bar.add_child(_status)
	var launch := Button.new()
	launch.text = "  PİSTE ÇIK  ▶  " if Career.sandbox() else "  CEPHEYE DÖN  ▶  "
	launch.focus_mode = Control.FOCUS_NONE
	launch.add_theme_stylebox_override("normal", _flat(Color(0.12, 0.5, 0.28), 6))
	launch.add_theme_stylebox_override("hover", _flat(Color(0.16, 0.62, 0.35), 6))
	launch.add_theme_font_size_override("font_size", 17)
	launch.pressed.connect(_launch)
	bar.add_child(launch)
	if not Game.pending_op.is_empty():
		_build_op_bar(root, bar, launch, menu_btn)

	# sol: parça paleti
	var left := PanelContainer.new()
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_top = 64
	left.offset_bottom = -54
	left.offset_left = 10
	left.offset_right = 300
	root.add_child(left)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	left.add_child(pv)
	_search = LineEdit.new()
	_search.placeholder_text = "🔍  Parça ara…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_filter_palette)
	pv.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var by_cat := {}
	for id in PartLibrary.ids():
		var def := PartLibrary.get_def(id)
		var cat: String = def.get("category", "diğer")
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(id)
	var cats: Array = CATEGORY_ORDER.duplicate()
	for cat in by_cat:
		if not cat in cats:
			cats.append(cat)
	for cat: String in cats:
		if not by_cat.has(cat):
			continue
		var header := Label.new()
		header.text = cat.to_upper()
		header.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
		header.add_theme_font_size_override("font_size", 13)
		list.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		list.add_child(grid)
		_cat_boxes[cat] = [header, grid]
		for id: String in by_cat[cat]:
			var def := PartLibrary.get_def(id)
			var b := Button.new()
			b.text = "%s\n%d kg" % [def.get("title", id), def.get("mass", 0.0)]
			b.icon = _make_thumbnail(id)
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_constant_override("icon_max_width", 120)
			b.custom_minimum_size = Vector2(126, 142)
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = _part_tooltip(def)
			b.pressed.connect(func() -> void:
				if not Career.is_unlocked(id):
					b.set_pressed_no_signal(false)
					_ask_unlock(id)
					return
				_select("" if _selected == id else id))
			grid.add_child(b)
			_cards[id] = b
	_refresh_locks()

	# sağ: bilgi paneli
	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -308
	right.offset_right = -8
	right.offset_top = 64
	right.anchor_bottom = 1.0
	right.offset_bottom = -12
	root.add_child(right)
	# pano + uyarılar + boya küçük ekranda sığmayabilir: dikey kaydırma
	var info_scroll := ScrollContainer.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(info_scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(info)
	var it := Label.new()
	it.text = "UÇAK BİLGİSİ"
	it.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	info.add_child(it)
	_dash = DesignDashboard.new()
	info.add_child(_dash)
	# rakamlar isteyene: "Ayrıntılar" altında katlı
	var more := Button.new()
	more.text = "Ayrıntılar ▸"
	more.flat = true
	more.toggle_mode = true
	more.focus_mode = Control.FOCUS_NONE
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	more.add_theme_font_size_override("font_size", 13)
	more.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	info.add_child(more)
	_stats = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Bahnschrift"])
	_stats.add_theme_font_override("font", mono)
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.visible = false
	info.add_child(_stats)
	more.toggled.connect(func(on: bool) -> void:
		_stats.visible = on
		more.text = "Ayrıntılar ▾" if on else "Ayrıntılar ▸")
	var legend := Label.new()
	legend.text = "● sarı: ağırlık merkezi   ● mavi: kaldırma merkezi"
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", Color(0.7, 0.76, 0.82))
	info.add_child(legend)
	_warn = RichTextLabel.new()
	_warn.bbcode_enabled = true
	_warn.fit_content = true
	_warn.scroll_active = false
	_warn.meta_underlined = false
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	_warn.custom_minimum_size.x = 270
	_warn.tooltip_text = "Uyarıya tıkla: ilgili parçalar yanıp söner"
	_warn.meta_clicked.connect(func(meta: Variant) -> void: _blink(String(meta)))
	info.add_child(_warn)
	_sym_check = CheckButton.new()
	_sym_check.text = "Simetri  (X)"
	_sym_check.button_pressed = symmetry
	_sym_check.focus_mode = Control.FOCUS_NONE
	_sym_check.toggled.connect(func(on: bool) -> void:
		symmetry = on
		_sync_sym_ui())
	info.add_child(_sym_check)
	_build_paint_ui(info)

	# alt ipucu: yalnız temel tuşlar; tam liste F1 penceresinde
	var hint := Label.new()
	hint.text = "1-4: araç  ·  Sol tık: tut / yerleştir (takılı olanlarla)  ·  Sağ tık: pencere  ·  X / V: simetri  ·  F1: tüm kısayollar"
	hint.add_theme_font_size_override("font_size", 14)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	_build_help(root)
	_build_toolbar(root)
	_sync_sym_ui()

	# yerleştirme bilgisi (seçili parça, ölçek, dönüş)
	_place_label = Label.new()
	_place_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_place_label.offset_top = 64
	_place_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pls := _flat(Color(0.05, 0.25, 0.14, 0.9), 6)
	pls.content_margin_left = 16
	pls.content_margin_right = 16
	_place_label.add_theme_stylebox_override("normal", pls)
	_place_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_label.visible = false
	root.add_child(_place_label)

	# fare altındaki parça bilgisi
	_hover_label = Label.new()
	var hls := _flat(Color(0.03, 0.05, 0.07, 0.92), 6)
	hls.border_color = Color(0.3, 0.6, 1.0, 0.6)
	hls.set_border_width_all(1)
	_hover_label.add_theme_stylebox_override("normal", hls)
	_hover_label.add_theme_font_size_override("font_size", 13)
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.visible = false
	root.add_child(_hover_label)

	# yükleme penceresi: solda gruplu liste, sağda üzerine gelinen uçağın dönen 3B önizlemesi
	_load_popup = PopupPanel.new()
	_load_popup.theme = _theme
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 14)
	var lv := VBoxContainer.new()
	var lt := Label.new()
	lt.text = "UÇAK YÜKLE"
	lt.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	lv.add_child(lt)
	var ls := ScrollContainer.new()
	ls.custom_minimum_size = Vector2(330, 470)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_load_list = VBoxContainer.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_load_list)
	lv.add_child(ls)
	lh.add_child(lv)
	lh.add_child(_build_load_preview())
	_load_popup.add_child(lh)
	_load_popup.popup_hide.connect(func() -> void: _clear_load_preview())
	layer.add_child(_load_popup)


## Parçanın küçük 3B resmi: kendi dünyası olan bir SubViewport'ta bir kez çizilir.
func _make_thumbnail(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(240, 150)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.72)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 2.0
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.8, 1.0)
	vp.add_child(rim)

	var model := _make_ghost(id, false)
	model.visible = true
	_set_overlay_node(model, null)
	vp.add_child(model)
	# modeli ortala ve sığdır
	var box := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var xf: Transform3D = _relative_xf(model, n)
			var b: AABB = xf * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.2)
	var cam := Camera3D.new()
	cam.fov = 30.0
	var dir := Vector3(-0.9, 0.55, -1.0).normalized()   # önden-soldan-yukarıdan
	if PartLibrary.get_def(id).get("category", "") in ["kanat", "kontrol"]:
		dir = Vector3(0.2, 1.0, 0.35).normalized()       # kanatlar: yukarıdan
	cam.position = center + dir * radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.72
	cam.near = 0.05
	cam.far = radius * 20.0
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, center, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD)
	return vp.get_texture()


func _relative_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _set_overlay_node(root: Node, mat: Material) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			n.material_overlay = mat


## Füze türüne göre açıklama ve gereksinim satırları (hangar ipucu).
static func _missile_info(guidance: String) -> PackedStringArray:
	match guidance:
		"radar":
			return PackedStringArray(["Radar güdümlü füze · 1–16 km", "⚠ GEREKLİ: Radar (radar burnu / radar parçası) — F4 ile hedef seç, radar yoksa atılamaz"])
		"arm":
			return PackedStringArray(["Radar avcısı (HARM) · 80 km'ye kadar", "Hedef: yayın yapan radar (SAM, gemi, radarı açık uçak) — ek parça gerekmez"])
		"cruise":
			return PackedStringArray(["Seyir füzesi · 110 km, GPS", "⚠ GEREKLİ: uçuşta haritadan GPS hedefi (M, sol tık)"])
		"ship":
			return PackedStringArray(["Gemi savar füze · 70 km", "Hedef: en yakın düşman gemisi ya da GPS hedefi (M)"])
	return PackedStringArray(["Isı güdümlü (IR) füze · ~7 km", "Ek parça gerekmez — kilitsiz de atılabilir"])


## Parçanın uçakta ister'i (radar / pod) karşılanmıyorsa açıklama; karşılanıyorsa "".
func _missing_requirement(def: Dictionary) -> String:
	if not is_instance_valid(_preview):
		return ""
	for m: Dictionary in def.get("modules", []):
		if m.get("type", "") == "missile" and m.get("guidance", "ir") == "radar" and _preview.radar() == null:
			return "%s RADAR ister — uçağa radar burnu ekle, yoksa atılamaz" % def.get("title", "")
		if m.get("type", "") == "bomb" and (m.get("kind", "") == "lgb" or m.get("guided", false)) and _preview.targeting_pod() == null:
			return "%s HEDEFLEME PODU ister — yoksa güdümsüz düşer" % def.get("title", "")
	return ""

func _part_tooltip(def: Dictionary) -> String:
	var lines := PackedStringArray([def.get("title", ""), "%d kg · %d ₺ · %d HP" % [def.get("mass", 0), def.get("cost", 0), def.get("hp", 0)]])
	for m: Dictionary in def.get("modules", []):
		match m["type"]:
			"engine":
				lines.append("İtki %d kN (AB %d kN)" % [m.get("max_thrust", 0) / 1000.0, m.get("max_thrust", 0) * EngineModule.AFTERBURNER_THRUST / 1000.0])
				var fr := float(m.get("fuel_rate", 0.0))
				lines.append(("Tüketim %.1f kg/s tam gazda" % fr) + ("" if m.get("prop", false) or m.get("rocket", false) or m.get("no_ab", false) else "  ·  AB'de %.1f kg/s" % (fr * EngineModule.AFTERBURNER_FUEL)))
			"fuel_tank":
				lines.append("Yakıt %d kg" % m.get("capacity", 0))
			"wing":
				lines.append("Kanat alanı %.1f m²" % m.get("area", 0))
			"control_surface":
				lines.append("Kontrol yüzeyi %.1f m², ±%d°" % [m.get("area", 0), m.get("max_deflection_deg", 20)])
			"radar":
				lines.append("Radar menzili %d km" % (m.get("range", 0) / 1000.0))
			"gun":
				lines.append("Top, %d mermi" % m.get("ammo", 0))
			"missile":
				lines.append_array(_missile_info(String(m.get("guidance", "ir"))))
			"landing_gear":
				lines.append("İniş takımı (açılır/kapanır)")
			"intake":
				lines.append("Hava alığı %.2f m² (J-70 için 0.5 gerekir)" % m.get("area", 0))
			"airbrake":
				lines.append("Hava freni: B basılıyken açılır")
			"chute":
				lines.append("Fren paraşütü: yerde B ile açılır, tek kullanım")
			"flare":
				lines.append("%d ısı tuzağı (O)" % m.get("count", 0))
			"bomb":
				var kind := String(m.get("kind", "lgb" if m.get("guided", false) else "normal"))
				lines.append("Lazer güdümlü bomba" if kind == "lgb" else "Bomba (%s)" % kind)
				if kind == "lgb":
					lines.append("⚠ GEREKLİ: Hedefleme podu (yoksa güdümsüz düşer)")
	if def.get("category", "") in VesselBuilder.SCALABLE:
		lines.append("Boyutlandırılabilir (Shift+tekerlek)")
	var proto := Designs.tooltip_line(def)
	if proto != "":
		lines.append(proto)
	return "\n".join(lines)


func _filter_palette(text: String) -> void:
	var q := text.strip_edges().to_lower()
	for cat in _cat_boxes:
		var any := false
		for id: String in _cards:
			var def := PartLibrary.get_def(id)
			if def.get("category", "") != cat:
				continue
			var show := q.is_empty() or (def.get("title", id) as String).to_lower().contains(q) or (cat as String).contains(q)
			_cards[id].visible = show
			any = any or show
		_cat_boxes[cat][0].visible = any
		_cat_boxes[cat][1].visible = any


func _make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	t.default_font = font
	t.default_font_size = 15
	var panel := _flat(Color(0.04, 0.06, 0.08, 0.88), 8)
	panel.border_color = Color(1, 1, 1, 0.1)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	var btn := _flat(Color(0.09, 0.12, 0.15, 0.95), 6)
	btn.border_color = Color(1, 1, 1, 0.12)
	btn.set_border_width_all(1)
	var hover := btn.duplicate()
	hover.bg_color = Color(0.14, 0.2, 0.24)
	var pressed := btn.duplicate()
	pressed.bg_color = Color(0.12, 0.42, 0.28)
	pressed.border_color = Color(0.45, 1.0, 0.65, 0.7)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_color", "Label", Color(0.9, 0.93, 0.95))
	return t


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _take_screenshot(path: String) -> void:
	Game.args.erase("screenshot")
	if Game.args.has("shot-blueprint"):
		_toggle_blueprint()
		await RenderingServer.frame_post_draw
	# isteğe bağlı kamera: --shot-yaw=90 --shot-pitch=5 (derece), --shot-dist=30
	if Game.args.has("shot-yaw"):
		_yaw = deg_to_rad(float(Game.args["shot-yaw"]))
		_pitch = deg_to_rad(float(Game.args.get("shot-pitch", "5")))
		if Game.args.has("shot-dist"):
			_dist = float(Game.args["shot-dist"])
		# --shot-at=parça_id: kamera o parçaya odaklanır
		if Game.args.has("shot-at") and is_instance_valid(_preview):
			for p in _preview.parts:
				if p.part_id == String(Game.args["shot-at"]):
					_target = _craft_root.global_transform * p.position
					break
		_update_camera()
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Ekran görüntüsü: ", path)
	get_tree().quit()


var _fake_mouse := Vector2(-1, -1)   ## yalnızca --hangardemo ekran görüntüsü için


func _mouse() -> Vector2:
	return _fake_mouse if _fake_mouse.x >= 0.0 else get_viewport().get_mouse_position()




# ------------------------------------------------------------------ görev seçimi

var _mission_popup: PopupPanel


func _open_missions() -> void:
	if _mission_popup != null:
		_mission_popup.queue_free()
		_mission_popup = null
	if _mission_popup == null:
		_mission_popup = PopupPanel.new()
		_mission_popup.theme = _theme
		add_child(_mission_popup)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		_mission_popup.add_child(box)
		var t := Label.new()
		t.text = "NEREYE UÇUYORUZ?"
		t.add_theme_font_size_override("font_size", 20)
		t.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
		box.add_child(t)
		var free := _mission_row("Serbest Uçuş", "Pistte soğuk başla, dünyayı özgürce gez: iki havaalanı, kasabalar. Düşman yok (istersen F7 ile saldırgan avcı çağır).", 0, "")
		box.add_child(free)
		box.add_child(HSeparator.new())
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(640, 420)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		for d: Dictionary in MissionManager.DEFS:
			list.add_child(_mission_row(d["title"], d["brief"], int(d["level"]), d["id"]))
	_mission_popup.popup_centered(Vector2i(680, 560))


func _mission_row(title: String, brief: String, level: int, id: String) -> Control:
	var panel := PanelContainer.new()
	var sb := _flat(Color(0.07, 0.1, 0.13, 0.95), 8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := Label.new()
	head.text = title + ("   " + "★".repeat(level) + "☆".repeat(3 - level) if level > 0 else "")
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45) if level > 0 else Color(0.45, 1.0, 0.65))
	col.add_child(head)
	var b := Label.new()
	b.text = brief
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 470
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.78, 0.83, 0.88))
	col.add_child(b)
	if level > 0 and not Career.sandbox():
		var done := int(Career.completed.get(id, 0))
		var rw := Label.new()
		rw.text = "Ödül %s ₺%s" % [_thousands(Career.mission_reward(level) if done == 0 else Career.mission_reward(level) / 2), ("   ·   tamamlandı ×%d" % done) if done > 0 else "   ·   ilk kez"]
		rw.add_theme_font_size_override("font_size", 13)
		rw.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if done == 0 else Color(0.6, 0.85, 0.65))
		col.add_child(rw)
	var go := Button.new()
	go.text = "  BAŞLA ▶  "
	go.focus_mode = Control.FOCUS_NONE
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.add_theme_stylebox_override("normal", _flat(Color(0.12, 0.5, 0.28), 6))
	go.add_theme_stylebox_override("hover", _flat(Color(0.16, 0.62, 0.35), 6))
	if level > 0 and not Career.mission_open(level):
		go.disabled = true
		go.text = "  🔒 %d görev daha  " % (int(Career.MISSIONS_FOR_LEVEL[level]) - Career.missions_done())
		panel.modulate = Color(1, 1, 1, 0.6)
	go.pressed.connect(func() -> void:
		if id.is_empty():
			_start_flight(id)
		else:
			_mission_popup.hide()
			Briefing.open(self, id, _name_edit.text, _start_flight.bind(id)))
	row.add_child(go)
	return panel


# ------------------------------------------------------------------ ince kaydırma / takma animasyonu

var _nudge_index := -1


func _nudge(key: int, step: float) -> void:
	var part := _hover_part if is_instance_valid(_hover_part) else null
	var idx: int = _part_entry.get(part, _nudge_index) if part else _nudge_index
	if idx < 0 or idx >= (craft["parts"] as Array).size():
		_flash("Kaydırmak için fareyi bir parçanın üstüne getir")
		return
	var d := Vector3.ZERO
	match key:
		KEY_UP: d.z = -step
		KEY_DOWN: d.z = step
		KEY_LEFT: d.x = -step
		KEY_RIGHT: d.x = step
		KEY_PAGEUP: d.y = step
		KEY_PAGEDOWN: d.y = -step
	var entry: Dictionary = craft["parts"][idx]
	if _undo.is_empty() or _nudge_index != idx:
		_push_undo()
	var p: Array = entry["pos"]
	entry["pos"] = [snappedf(float(p[0]) + d.x, 0.01), snappedf(float(p[1]) + d.y, 0.01), snappedf(float(p[2]) + d.z, 0.01)]
	_nudge_index = idx
	Sfx.play_ui("switch_2.ogg", -16.0, 1.6)
	_rebuild()
	_pop(idx, 1.04)


## Yeni takılan / kaydırılan parçaya küçük bir "oturma" animasyonu.
func _pop(idx: int, amount := 1.14) -> void:
	for p in _part_entry:
		if _part_entry[p] == idx and is_instance_valid(p):
			var vis: Node3D = p.get_node_or_null("Visual")
			if vis == null:
				continue
			var base := vis.scale
			vis.scale = base * amount
			var tw := create_tween()
			tw.tween_property(vis, "scale", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ kadro

var _pilot_btn: Button
var _money_label: Label
var _crew_popup: PopupPanel
var _crew_list: VBoxContainer


func _refresh_pilot_btn() -> void:
	var p := Crew.current()
	if p.is_empty():
		_pilot_btn.text = "  Pilot: —  "
		return
	_pilot_btn.text = "  👤 %s %s  ·  Sv %d%s  " % [Medals.rank_short(p), p["name"], p["level"], "" if p["status"] == "hazır" else "  (KAYIP)"]
	if Crew.wingman_index() >= 0:
		_pilot_btn.text += "+ K2 %s  " % Crew.pilots[Crew.wingman_index()]["name"]


func _open_crew() -> void:
	if _crew_popup == null:
		_crew_popup = PopupPanel.new()
		_crew_popup.theme = _theme
		add_child(_crew_popup)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		_crew_popup.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var t := Label.new()
		t.text = "KADRO"
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_font_size_override("font_size", 20)
		t.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
		head.add_child(t)
		var hire := Button.new()
		hire.text = "  + Yeni pilot al (%s)  " % ("ücretsiz" if HIRE_COST == 0 else "%d ₺" % HIRE_COST)
		hire.focus_mode = Control.FOCUS_NONE
		hire.pressed.connect(func() -> void:
			if not Career.sandbox() and Career.money < HIRE_COST:
				_flash("Pilot almak için %d ₺ gerekli" % HIRE_COST)
			elif not Crew.hire():
				_flash("Kadro dolu (en fazla %d pilot)" % Crew.MAX_PILOTS)
			elif not Career.sandbox():
				Career.money -= HIRE_COST
				Career.save()
				Career.changed.emit()
			_fill_crew())
		head.add_child(hire)
		var info := Label.new()
		info.text = "Uçuş: kumanda tepkisi ve SAS  ·  Nişancılık: top saçılması  ·  G dayanımı: bayılma eşiği.\nGörev, düşürülen uçak, yumuşak iniş ve yüksek G'de tecrübe kazanılır; seviye atlayınca en çok kullanılan yetenek artar."
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color(0.7, 0.76, 0.82))
		box.add_child(info)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(660, 420)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		_crew_list = VBoxContainer.new()
		_crew_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_crew_list.add_theme_constant_override("separation", 8)
		scroll.add_child(_crew_list)
	_fill_crew()
	_crew_popup.popup_centered(Vector2i(700, 560))


func _fill_crew() -> void:
	for c in _crew_list.get_children():
		c.queue_free()
	for i in Crew.pilots.size():
		var p: Dictionary = Crew.pilots[i]
		var alive: bool = p["status"] == "hazır"
		var panel := PanelContainer.new()
		var sb := _flat(Color(0.05, 0.16, 0.1, 0.95) if i == Crew.selected else Color(0.07, 0.1, 0.13, 0.95), 8)
		sb.set_content_margin_all(10)
		if i == Crew.selected:
			sb.border_color = Color(0.45, 1.0, 0.65, 0.7)
			sb.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		panel.add_child(row)
		row.add_child(MedalView.rank_badge(int(p.get("rank", 0))))   # rütbe apoleti
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var name := Label.new()
		name.text = "%s %s   Seviye %d%s" % [Medals.rank_name(p), p["name"], p["level"], "" if alive else ("   — YARALI" if p["status"] == "yaralı" else "   — KAYIP")]
		name.add_theme_font_size_override("font_size", 16)
		name.add_theme_color_override("font_color", Color.WHITE if alive else Color(0.9, 0.4, 0.35))
		col.add_child(name)
		var skills := Label.new()
		var parts := PackedStringArray()
		for k in Crew.SKILLS:
			parts.append("%s %s" % [Crew.SKILL_NAMES[k], "★".repeat(int(p[k])) + "☆".repeat(5 - int(p[k]))])
		skills.text = "   ".join(parts)
		skills.add_theme_font_size_override("font_size", 13)
		skills.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		col.add_child(skills)
		var xp_row := HBoxContainer.new()
		col.add_child(xp_row)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 10)
		bar.show_percentage = false
		var prev := Crew.xp_for(int(p["level"]) - 1) if int(p["level"]) > 1 else 0
		bar.min_value = prev
		bar.max_value = Crew.xp_for(int(p["level"]))
		bar.value = int(p["xp"])
		xp_row.add_child(bar)
		var xl := Label.new()
		xl.text = "  %d / %d XP   ·   %d uçuş   ·   %d düşürme" % [p["xp"], Crew.xp_for(int(p["level"])), p["flights"], p["kills"]]
		xl.add_theme_font_size_override("font_size", 12)
		xl.add_theme_color_override("font_color", Color(0.7, 0.76, 0.82))
		xp_row.add_child(xl)
		col.add_child(MedalView.medal_row(p))   # madalya kurdeleleri + ayrıntı
		var idx := i
		if alive and i != Crew.selected:
			var pick := Button.new()
			pick.text = "  SEÇ  "
			pick.focus_mode = Control.FOCUS_NONE
			pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pick.pressed.connect(func() -> void:
				Crew.selected = idx
				Crew.save()
				_refresh_pilot_btn()
				_fill_crew())
			row.add_child(pick)
		elif i == Crew.selected and alive:
			var l := Label.new()
			l.text = "SEÇİLİ  "
			l.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(l)
		if alive and i != Crew.selected:
			row.add_child(WingmanMenu.crew_button(idx, func() -> void:
				_refresh_pilot_btn()
				_fill_crew()))
		if not alive:
			var rm := Button.new()
			rm.text = "  Kadrodan çıkar  "
			rm.focus_mode = Control.FOCUS_NONE
			rm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rm.pressed.connect(func() -> void:
				Crew.fire_pilot(idx)
				_refresh_pilot_btn()
				_fill_crew())
			row.add_child(rm)
		_crew_list.add_child(panel)
	_refresh_pilot_btn()


# ------------------------------------------------------------------ boya

var _paint_opt: OptionButton
var _paint_num: LineEdit
var _paint_color: ColorPickerButton


func _build_paint_ui(parent: Control) -> void:
	parent.add_child(HSeparator.new())
	var t := Label.new()
	t.text = "BOYA"
	t.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	parent.add_child(t)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_paint_opt = OptionButton.new()
	_paint_opt.focus_mode = Control.FOCUS_NONE
	_paint_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in VesselBuilder.PAINT_SCHEMES:
		_paint_opt.add_item(String(k))
	_paint_opt.item_selected.connect(func(_i: int) -> void: _apply_paint())
	row.add_child(_paint_opt)
	_paint_color = ColorPickerButton.new()
	_paint_color.custom_minimum_size = Vector2(36, 28)
	_paint_color.edit_alpha = false
	_paint_color.tooltip_text = "Ana renk (şemanın birinci rengi)"
	_paint_color.popup_closed.connect(_apply_paint.bind(true))
	row.add_child(_paint_color)
	var row2 := HBoxContainer.new()
	parent.add_child(row2)
	var l := Label.new()
	l.text = "Kuyruk no"
	row2.add_child(l)
	_paint_num = LineEdit.new()
	_paint_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_num.max_length = 8
	_paint_num.text_submitted.connect(func(_s: String) -> void:
		_apply_paint()
		_paint_num.release_focus())
	_paint_num.focus_exited.connect(_apply_paint)
	row2.add_child(_paint_num)


## Uçağın boyasını arayüze yansıt (uçak yüklenince).
func _sync_paint_ui() -> void:
	if _paint_opt == null:
		return
	var p: Dictionary = craft.get("paint", {})
	var scheme: String = p.get("scheme", "gri")
	var keys := VesselBuilder.PAINT_SCHEMES.keys()
	_paint_opt.select(maxi(keys.find(scheme), 0))
	_paint_num.text = str(p.get("number", ""))
	var s: Array = VesselBuilder.PAINT_SCHEMES.get(scheme, VesselBuilder.PAINT_SCHEMES["gri"])
	_paint_color.color = Color.html(p["color1"]) if p.has("color1") else s[1]


func _apply_paint(custom_color := false) -> void:
	var keys := VesselBuilder.PAINT_SCHEMES.keys()
	var scheme: String = keys[_paint_opt.selected]
	var p := {"scheme": scheme, "number": _paint_num.text.strip_edges()}
	var old: Dictionary = craft.get("paint", {})
	if custom_color:
		p["color1"] = _paint_color.color.to_html(false)
	elif old.get("scheme", "") == scheme and old.has("color1"):
		p["color1"] = old["color1"]
	if p == old:
		return
	_push_undo()
	craft["paint"] = p
	if not custom_color:
		var s: Array = VesselBuilder.PAINT_SCHEMES[scheme]
		_paint_color.color = Color.html(p["color1"]) if p.has("color1") else s[1]
	_rebuild()


# ------------------------------------------------------------------ kariyer: para ve Ar-Ge

const HIRE_COST := 0          # şimdilik ücretsiz (eski: 4000 ₺)
var _unlock_dialog: ConfirmationDialog
var _unlock_id := ""


func _refresh_money() -> void:
	if _money_label == null:
		return
	_money_label.text = "SERBEST MOD" if Career.sandbox() else "₺ %s" % _thousands(Career.money)
	_refresh_locks()


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Kilitli parça kartları soluk ve kilit simgeli; üstünde Ar-Ge bedeli yazar.
func _refresh_locks() -> void:
	for id: String in _cards:
		var b: Button = _cards[id]
		var def := PartLibrary.get_def(id)
		if Career.is_unlocked(id):
			b.text = "%s\n%d kg" % [def.get("title", id), def.get("mass", 0.0)]
			b.modulate = Color.WHITE
			# prototip parça rozeti (Designs): turuncu yazı
			var badge := Designs.badge(id)
			if badge != "":
				b.text = "%s\n%s" % [def.get("title", id), badge]
				b.add_theme_color_override("font_color", Color(1.0, 0.68, 0.3))
			else:
				b.remove_theme_color_override("font_color")
		else:
			b.text = "🔒 %s\nAr-Ge %s ₺" % [def.get("title", id), _thousands(Career.unlock_price(id))]
			b.modulate = Color(0.75, 0.75, 0.75, 0.75) if Career.can_unlock(id) else Color(0.55, 0.55, 0.55, 0.6)


func _ask_unlock(id: String) -> void:
	var def := PartLibrary.get_def(id)
	var price := Career.unlock_price(id)
	if _unlock_dialog == null:
		_unlock_dialog = ConfirmationDialog.new()
		_unlock_dialog.theme = _theme
		_unlock_dialog.title = "Ar-Ge"
		_unlock_dialog.ok_button_text = "Aç"
		_unlock_dialog.cancel_button_text = "Vazgeç"
		_unlock_dialog.confirmed.connect(func() -> void:
			if Career.unlock(_unlock_id):
				_flash("%s açıldı!" % PartLibrary.get_def(_unlock_id).get("title", _unlock_id))
				Sfx.play_ui("lock_tone.ogg", -6.0, 1.4)
				_select(_unlock_id)
			else:
				_flash("Yetersiz para"))
		add_child(_unlock_dialog)
	_unlock_id = id
	var enough := Career.money >= price
	_unlock_dialog.dialog_text = "%s\n\n%s\n\nAr-Ge bedeli: %s ₺\nParan: %s ₺%s" % [def.get("title", id), _part_tooltip(def),
		_thousands(price), _thousands(Career.money), "" if enough else "\n\nYETERSİZ PARA — görev yaparak kazan."]
	var gate := Campaign.part_lock_reason(id)   # perde kapısı (Campaign)
	if gate != "":
		_unlock_dialog.dialog_text += "\n\n" + gate
	_unlock_dialog.get_ok_button().disabled = not enough or gate != ""
	_unlock_dialog.popup_centered(Vector2i(420, 0))


# ------------------------------------------------------------------ performans tahmini

## Kaba performans tahmini (MissionCheck.estimate: sürükleme alanı, itki eğrileri, azami hız,
## kalkış hızı/mesafesi, tırmanma, dayanım/menzil, yakıt bitince ağırlık merkezinin kayması).
## Görev kartı kontrol listesi de aynı tahmini kullanır.
func _performance(v: Vessel, thrust_dry: float, wing_area: float, _com_full: Vector3) -> String:
	if thrust_dry <= 0.0 or wing_area < 1.0:
		return "PERFORMANS: motor ve kanat gerekli"
	var e := MissionCheck.estimate(v)
	var v0: float = e["v0"]
	var v8: float = e["v8"]
	var dto: float = e["dto"]
	var shift: float = e["cg_shift"]
	var lines := PackedStringArray([
		"PERFORMANS (tahmini)",
		"Kalkış hızı      %d km/sa" % (float(e["vto"]) * 3.6),
		"Kalkış mesafesi  %d m" % dto,
		"Azami hız (0 m)  %d km/sa  M%.2f" % [v0 * 3.6, v0 / Atmosphere.SPEED_OF_SOUND],
		"Azami hız (8 km) %d km/sa  M%.2f" % [v8 * 3.6, v8 / 308.0],
		"Tırmanma         %d m/s" % float(e["climb"]),
		"Dayanım          %d dk" % float(e["endurance_min"]),
		"Menzil           %d km" % float(e["range_km"]),
		"Yakıt bitince AM %s %.2f m" % ["geri" if shift > 0.0 else "ileri", absf(shift)],
	])
	if not e["can_roll"]:
		lines.append("⚠ KALKAMAZ: düşük hızda itki yok (ramjet / zayıf motor) — ek motor ya da JATO tak")
	elif dto > 2400.0:
		lines.append("⚠ Pist (2400 m) yetmeyebilir")
	if float(e["jato"]) > 0.0:
		lines.append("JATO: +%d kN, %d sn (eylem paneli 7)" % [float(e["jato"]) / 1000.0, float(e["jato_time"])])
	if e["ramjet"]:
		lines.append("Ramjet: Mach 1.3+'ta tam güç, Mach 3'te ~1.9 kat")
	if e["tvc"]:
		lines.append("İtki yönlendirme: lüle ±15°, yavaşta da kumanda")
	if absf(shift) > 0.6:
		lines.append("⚠ Yakıt azaldıkça denge çok değişir")
	return "\n".join(lines)


## Uçağın toplam itkisi (N): MissionCheck.thrust_at (EngineModule ile aynı hız/irtifa eğrileri).
func _thrust_at(v: Vessel, s: float, alt: float, ab: bool) -> float:
	return MissionCheck.thrust_at(v, s, alt, ab)
