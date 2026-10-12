extends SceneTree
## Arazi yoklama: aday noktaların yüksekliği ve düzlüğü (ikinci havaalanı yeri seçmek için).
func _init() -> void:
	TerrainGen.init()
	var best := []
	for x in range(-40000, 40001, 2000):
		for z in range(-40000, -9999, 2000):
			var d := Vector3(x, TerrainGen.RADIUS, z).normalized()
			if TerrainGen.land_mask(d) < 0.1:
				continue
			var h := TerrainGen.height(d)
			var diff := 0.0
			for o in [Vector2(0, 1100), Vector2(0, -1100), Vector2(400, 0), Vector2(-400, 0), Vector2(300, 700), Vector2(-300, -700)]:
				var d2 := Vector3(x + o.x, TerrainGen.RADIUS, z + o.y).normalized()
				diff = maxf(diff, absf(TerrainGen.height(d2) - h))
			best.append([diff, x, z, h])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in 12:
		print("x=%d z=%d yük=%.0f fark=%.1f" % [best[i][1], best[i][2], best[i][3], best[i][0]])
	quit()
