class_name AeroDebug
extends MeshInstance3D
## F3: kanat kuvvetleri (yeşil kaldırma, kırmızı sürükleme), itki (turuncu),
## ağırlık merkezi (sarı) ve hız vektörü (mavi) çizer.

const FORCE_SCALE := 1.0 / 4000.0  ## metre / Newton

var vessel: Vessel
var enabled := false

var _im := ImmediateMesh.new()


func _ready() -> void:
	mesh = _im
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	material_override = mat


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		enabled = not enabled


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if not enabled or not is_instance_valid(vessel) or not vessel.is_inside_tree():
		return
	# Fizik konumlarını interpolasyonlu görsel konuma taşı
	var to_visual := vessel.get_global_transform_interpolated() * vessel.global_transform.affine_inverse()

	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for module in vessel.modules:
		var p := to_visual * module.part.global_position
		if module is WingModule:
			_line(p, to_visual.basis * module.last_lift * FORCE_SCALE, Color.GREEN)
			_line(p, to_visual.basis * module.last_drag * FORCE_SCALE * 3.0, Color.RED)
		elif module is EngineModule:
			_line(p, to_visual.basis * (module.part.global_basis.z * module.thrust * FORCE_SCALE), Color.ORANGE)
	var com := to_visual * vessel.com_global()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(com - axis, axis * 2.0, Color.YELLOW)
	_line(com, vessel.linear_velocity * 0.1, Color.CYAN)
	_im.surface_end()


func _line(from: Vector3, vec: Vector3, color: Color) -> void:
	_im.surface_set_color(color)
	_im.surface_add_vertex(from)
	_im.surface_add_vertex(from + vec)
