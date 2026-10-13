class_name ProductionDialog
extends RefCounted
## Hangar "Seri üretim" penceresi: açık tasarımı kalıp + birim bedeliyle seri üretime alır.
## Üretimdeki tasarım filo tipi olur (Designs): kanat adamı ve dost devriyeler onunla uçar.
## Onaylanınca tasarım önce kaydedilir (kalıcı kimlik), sonra Designs.produce.


static func open(host: Node) -> void:
	var craft: Dictionary = host.get("craft")
	var name_edit: LineEdit = host.get("_name_edit")
	if name_edit and name_edit.text.strip_edges() != "":
		craft["name"] = name_edit.text.strip_edges()
	var d := ConfirmationDialog.new()
	d.theme = host.get("_theme")
	d.title = "Seri üretim"
	d.ok_button_text = "Seri üretime al"
	d.cancel_button_text = "Vazgeç"
	var why := Designs.flyable(craft)
	var c := Designs.production_cost(craft)
	var lines := PackedStringArray()
	lines.append(String(craft.get("name", "İsimsiz")))
	lines.append("")
	lines.append("Seri üretimdeki tasarım filonun tipi olur: kanat adamın ve cephedeki dost")
	lines.append("devriyeler bu uçakla uçar. İyi bir tasarım bütün cepheyi güçlendirir.")
	lines.append("")
	if Career.sandbox():
		lines.append("Serbest mod: ücretsiz.")
	else:
		lines.append("Kalıp (tooling): %d ₺   ·   ilk birim: %d ₺" % [int(c["tooling"]), int(c["unit"])])
		lines.append("Toplam: %d ₺   ·   Kasa: %d ₺" % [int(c["total"]), Career.money])
	var cur := Designs.fleet_name()
	if cur != "":
		lines.append("Şu anki filo tipi: %s%s" % [cur, " (bu tasarım)" if Designs.is_fleet(craft) else " — yerine geçer"])
	var s := Designs.service_line(craft)
	if s != "":
		lines.append("Hizmet: " + s)
	var protos := Designs.proto_parts_in(craft)
	if not protos.is_empty():
		lines.append("⚠ Prototip parça içeriyor (filo uçakları arıza yapmaz ama olgunlaşmaz).")
	var block := why
	if block == "" and not Career.locked_parts_in(craft).is_empty():
		block = "kilitli parça var (Ar-Ge gerekir)"
	if block == "" and Career.money < int(c["total"]):
		block = "para yetmiyor"
	if block != "":
		lines.append("")
		lines.append("✖ Seri üretime uygun değil: " + block)
	d.dialog_text = "\n".join(lines)
	d.get_ok_button().disabled = block != ""
	d.confirmed.connect(func() -> void:
		host.call("_save")                      # kalıcı kimlik (Designs.ensure_id) ve dosya
		var err := Designs.produce(host.get("craft"))
		host.call("_flash", err if err != "" else "%s seri üretimde — filo tipi oldu!" % craft.get("name", ""))
		if host.has_method("_update_stats"):
			host.call("_update_stats")
		d.queue_free())
	d.canceled.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered(Vector2i(520, 0))
