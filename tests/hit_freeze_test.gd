extends Node
## --hitfreezetest: düşmana füze isabeti anındaki takılmayı ölçer. Düşmanın yanında iki kez
## (ilk isabet = ilk shader derlemesi) füze patlaması tetikler; her adımın süresini ve sonraki
## karelerin sürelerini yazar.

var main: Node
var _frames := -1
var _t_last := 0
var _round := 0


func _ready() -> void:
	await get_tree().create_timer(1.5).timeout
	main.spawn_enemy(false)
	await get_tree().create_timer(1.0).timeout
	_hit()


func _hit() -> void:
	var e: Vessel = main.enemy
	if not is_instance_valid(e):
		print("HITFREEZE düşman yok")
		get_tree().quit()
		return
	_round += 1
	var gp := e.com_global() + Vector3(3, 0, 0)
	var t0 := Time.get_ticks_usec()
	if not Game.args.has("nodmg"):
		Damage.explosion(gp, 25.0, 900.0, null)
	var t1 := Time.get_ticks_usec()
	if not Game.args.has("nofx"):
		Effects.explosion(FloatingOrigin.world_root, gp, Planet.up_at(gp), 3.0)
	var t2 := Time.get_ticks_usec()
	if not Game.args.has("nosfx"):
		Sfx.explosion(gp, 2.5)
	var t3 := Time.get_ticks_usec()
	print("HITFREEZE tur %d: Damage.explosion %.1f ms, Effects %.1f ms, Sfx %.1f ms, parça kaldı %d" % [_round, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, e.parts.size()])
	_frames = 0
	_t_last = Time.get_ticks_usec()


func _process(_d: float) -> void:
	if _frames < 0:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _t_last) / 1000.0
	_t_last = now
	_frames += 1
	if ms > 25.0 or _frames <= 3:
		print("  kare %d: %.1f ms  (process %.1f, physics %.1f, nesne %d, çizim çağrısı %d)" % [_frames, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _frames >= 40:
		_frames = -1
		if _round < 2:
			await get_tree().create_timer(1.0).timeout
			main.spawn_enemy(false)
			await get_tree().create_timer(1.0).timeout
			_hit()
		else:
			get_tree().quit()
