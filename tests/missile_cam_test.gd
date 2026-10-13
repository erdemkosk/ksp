extends Node
## --missilecamtest: füze atıp Space'i basılı tutar (füze kamerası), ekran görüntüsü için.

var main: Node


func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var v: Vessel = main.vessel
	v.master_arm = true
	v.selected_weapon = Vessel.WEAPON_MISSILE
	Input.action_press("fire")
	await get_tree().create_timer(4.0).timeout
	print("MISSILECAM aktif=%s" % is_instance_valid(main.camera.missile_cam))
