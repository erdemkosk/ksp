class_name BombModule
extends PartModule
## Bomba askısı: bir bomba taşır. Tetik başına bir bomba bırakır. Türler ("kind"):
##   normal  — 250 kg güdümsüz (BOMBA): HUD, düşeceği yeri (CCIP) gösterir.
##   lgb     — lazer güdümlü (guided): hedefleme podunun işaretine süzülür; kilit sürmeli.
##   glide   — süzülen bomba: açılır kanatlarla haritadaki GPS hedefine 20–30 km'den süzülür.
##   cluster — misket: hedefin ~300 m üstünde açılır, geniş alana 40 bombacık saçar.
##   heavy   — 1000 kg: büyük patlama yarıçapı (pist, sığınak, gemi).

const BOMB_MASS := 250.0
const MASSES := {"normal": 250.0, "lgb": 250.0, "glide": 480.0, "cluster": 430.0, "heavy": 1000.0}

var loaded := true
var guided := false          ## kind == "lgb" (eski kodla uyum)
var kind := "normal"
var _visual: Node3D
var _released_this_press := false


func setup(p: Dictionary) -> void:
	kind = String(p.get("kind", "lgb" if bool(p.get("guided", false)) else "normal"))
	guided = kind == "lgb"


func on_attached() -> void:
	_visual = part.get_node_or_null("Visual/Bomb")


func extra_mass() -> float:
	return float(MASSES.get(kind, BOMB_MASS)) if loaded else 0.0


func weapon_kind() -> int:
	match kind:
		"lgb":
			return Vessel.WEAPON_LGB
		"glide":
			return Vessel.WEAPON_GLIDE
		"cluster":
			return Vessel.WEAPON_CLUSTER
		"heavy":
			return Vessel.WEAPON_HEAVY
	return Vessel.WEAPON_BOMB


func physics_tick(_delta: float) -> void:
	if not vessel.ctrl_fire:
		_released_this_press = false
		return
	var active := loaded and vessel.master_arm and vessel.selected_weapon == weapon_kind() and vessel.has_power()
	if active and not _released_this_press and _is_first_ready():
		if kind == "glide" and vessel.strike_xz == Vector2.INF:
			Sfx.play_ui("switch_2.ogg", -8.0, 0.6)
			vessel.system_message.emit("GPS HEDEF YOK — haritada (M) sol tıkla")
		else:
			release()
		for m in vessel.modules:
			if m is BombModule and m.kind == kind:
				m._released_this_press = true


func _is_first_ready() -> bool:
	for m in vessel.modules:
		if m is BombModule and m.loaded and m.kind == kind:
			return m == self
	return false


func release() -> void:
	loaded = false
	if _visual:
		_visual.visible = false
	var b := Bomb.new()
	b.velocity = vessel.linear_velocity   # HUD CCIP aynı başlangıçla hesaplar
	b.shooter = vessel
	b.kind = kind
	match kind:
		"lgb":
			b.laser = vessel.targeting_pod()
		"glide":
			b.gps = vessel.strike_world()
	vessel.get_parent().add_child(b)
	b.global_position = part.global_transform * Vector3(0, -0.4, 0)
	b.look_at(b.global_position + vessel.forward(), vessel.up())
	Sfx.play_at("hydraulic_thunk.ogg", part.global_position, -4.0, 1.4 if kind != "heavy" else 0.9, 800.0)
	vessel.recalc_mass()
