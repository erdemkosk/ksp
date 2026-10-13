class_name WingmanMenu
extends RefCounted
## Telsiz (F2) → "Kanat adamı…" alt menüsü: kanat adamına emirler. ActionBar öğeleri üretir.

const LABEL := "Kanat adamı…"


## Ana telsiz menüsüne eklenecek giriş (kanat adamı uçmuyorsa boş).
static func entry(bar: ActionBar) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wf := WingFlight.active
	if wf != null and is_instance_valid(wf) and wf.flying():
		out.append(bar._item(LABEL, "K2 · " + Wingman.ORDER_NAMES[wf.ai.order], ActionBar.ACC, func() -> void: bar.wing_mode = true))
	return out


static func items(bar: ActionBar) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wf := WingFlight.active
	var cur := -1
	if wf != null and is_instance_valid(wf) and wf.flying():
		cur = wf.ai.order
	var add := func(label: String, o: Wingman.Order, col: Color) -> void:
		out.append(bar._item(label, "●" if cur == o else "", col, func() -> void:
			if WingFlight.active and is_instance_valid(WingFlight.active):
				WingFlight.active.command(o)))
	add.call("Hedefime saldır", Wingman.Order.ATTACK, ActionBar.RED)
	add.call("Beni koru", Wingman.Order.COVER, ActionBar.ACC)
	add.call("Dağıl / serbest avlan", Wingman.Order.FREE, ActionBar.AMBER)
	add.call("Formasyona dön", Wingman.Order.FORM, ActionBar.ACC)
	add.call("Üsse dön", Wingman.Order.RTB, ActionBar.DIM)
	out.append(bar._item("◀ Geri", "F2", ActionBar.DIM, func() -> void: bar.wing_mode = false))
	return out


## Hangar kadro paneli: "Kanat adamı olarak götür" düğmesi (tekrar basınca bırakır).
static func crew_button(idx: int, refresh: Callable) -> Button:
	var b := Button.new()
	var on := Crew.wingman == idx
	b.text = "  ✓ KANAT ADAMI  " if on else "  Kanat adamı olarak götür  "
	b.tooltip_text = "Bu pilot senin uçağının aynısıyla kolunda uçar (görev ve serbest uçuş).\nTelsiz: F2 → Kanat adamı…"
	if on:
		b.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		Crew.wingman = -1 if Crew.wingman == idx else idx
		Crew.save()
		refresh.call())
	return b
