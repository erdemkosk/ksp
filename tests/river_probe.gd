extends Node
## --riverprobe: oluşan nehirleri ve yol kesişimlerini yazar; --map: kaba yükseklik haritası.
var main: Node

func _ready() -> void:
	if Game.args.has("hmap"):
		var z := -34000
		while z <= 10000:
			var line := "%6d " % z
			var x := -34000
			while x <= 14000:
				var h := TerrainGen.height(Vector3(x, 600000, z).normalized())
				line += "~" if h < 0.0 else ("." if h < 60.0 else ("-" if h < 200.0 else ("+" if h < 500.0 else "^")))
				x += 2000
			print(line)
			z += 2000
	var t0 := Time.get_ticks_msec()
	print("NEHİR sayısı=%d" % TerrainGen.rivers.size())
	for r in TerrainGen.rivers:
		var pts: PackedVector2Array = r["pts"]
		var lv: PackedFloat32Array = r["level"]
		var length := 0.0
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
		print("  kaynak=%s ağız=%s uzunluk=%.1f km seviye %.0f→%.0f m" % [pts[0], pts[pts.size() - 1], length / 1000.0, lv[0], lv[lv.size() - 1]])
	print("  köprüler=%s" % [Towns.bridges()])
	for i in 20000:
		TerrainGen.height(Vector3(randf_range(-20000, 0), 600000, randf_range(-20000, 0)).normalized())
	print("  20000 yükseklik örneği: %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()
