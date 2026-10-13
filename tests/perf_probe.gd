extends Node
## --perfprobe: uçuşta kare sürelerini ölçer: ortalama, p95/p99, takılmalar (>40 ms) ve o andaki
## sayaçlar (nesne, çizim çağrısı, fizik/işlem süresi). --perfprobe=SN süreyi verir (varsayılan 40).

var main: Node
var _t := 0.0
var _last := 0
var _ms: Array[float] = []
var _spikes: Array = []
var _dur := 40.0
var _shift_f := -10


func _ready() -> void:
	var a: Variant = Game.args.get("perfprobe", true)
	if a is String and String(a).is_valid_float():
		_dur = float(a)
	_last = Time.get_ticks_usec()
	FloatingOrigin.shifted.connect(func(_s: Vector3) -> void: _shift_f = Engine.get_process_frames())


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	_t += delta
	if _t < 4.0:      # yükleme ısınması
		return
	_ms.append(ms)
	if ms > 40.0:
		var tag := " [KAYDIRMA]" if Engine.get_process_frames() - _shift_f <= 2 else ""
		_spikes.append(tag + "  %.1f sn: %.0f ms  (işlem %.1f, fizik %.1f, nesne %d, çizim %d, ilkel %dk)" % [_t, ms,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0])
	if _t >= _dur + 4.0:
		var s := _ms.duplicate()
		s.sort()
		var avg := 0.0
		for x in s:
			avg += x
		avg /= s.size()
		print("PERF kare %d · ort %.1f ms (%.0f fps) · p95 %.1f · p99 %.1f · en kötü %.0f · takılma(>40ms) %d" % [s.size(), avg, 1000.0 / avg,
			s[int(s.size() * 0.95)], s[int(s.size() * 0.99)], s[-1], _spikes.size()])
		print("PERF işlem %.1f ms · fizik %.1f ms · nesne %d · çizim %d · fizik adımı/sn %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Engine.physics_ticks_per_second])
		for l in _spikes.slice(0, 15):
			print(l)
		get_tree().quit()
