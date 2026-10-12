class_name CockpitInteraction
extends Node
## Kokpit görünümünde fareyle anahtarları bulur ve tıklatır.

const REACH := 2.5

var camera: FlightCamera
var hovered: CockpitSwitch

var _mouse := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hovered:
			hovered.activate()
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var hit: CockpitSwitch = null
	if is_instance_valid(camera) and camera.mode == FlightCamera.Mode.COCKPIT and not camera.is_eva():
		var from := camera.project_ray_origin(_mouse)
		var to := from + camera.project_ray_normal(_mouse) * REACH
		var q := PhysicsRayQueryParameters3D.create(from, to, CockpitSwitch.LAYER)
		q.collide_with_areas = true
		q.collide_with_bodies = false
		var result := camera.get_world_3d().direct_space_state.intersect_ray(q)
		if not result.is_empty():
			hit = result.collider as CockpitSwitch
	if hit != hovered:
		if is_instance_valid(hovered):
			hovered.set_highlight(false)
		hovered = hit
		if hovered:
			hovered.set_highlight(true)
