extends Node

const PLAYER := preload("res://scenes/Player3D.tscn")
const OUTPUT := "res://outputs/019f8417-e7f4-7bc3-aded-c62dfd1d1462/bunny_v004_weapon_grip.png"


func _ready() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1c3039")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9dce4")
	environment.ambient_light_energy = 1.3
	world_environment.environment = environment
	stage.add_child(world_environment)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.0, 5.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("34505a")
	floor_material.roughness = 0.86
	plane.material = floor_material
	floor.mesh = plane
	stage.add_child(floor)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -32, 0)
	key.light_energy = 1.5
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.4, 3.4, -3.8)
	fill.omni_range = 9.0
	fill.light_energy = 5.0
	stage.add_child(fill)

	var sidearm_player := PLAYER.instantiate() as Player3D
	sidearm_player.position.x = -1.28
	stage.add_child(sidearm_player)
	var rifle_player := PLAYER.instantiate() as Player3D
	rifle_player.position.x = 1.28
	stage.add_child(rifle_player)
	await get_tree().process_frame
	await get_tree().process_frame
	for player in [sidearm_player, rifle_player]:
		player.set_process(false)
		player.set_physics_process(false)
		player.avatar.set_process(false)
		player.aim_direction = Vector3(0, 0, -1)
		player.aim_yaw = 0.0
		player.avatar.visual_root.rotation.y = 0.0
		player.get_node("Camera3D").current = false
		player.get_node("AimCursor").visible = false
	if not rifle_player.equip_weapon("bp_rifle", "mod_bullet_standard"):
		push_error("Cannot equip rifle for Bunny v004 two-hand preview")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	for _index in range(3):
		sidearm_player.avatar.call("_process", 0.10)
		rifle_player.avatar.call("_process", 0.10)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.55, -7.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.02, -0.20), Vector3.UP)
	camera.fov = 34.0
	camera.current = true
	stage.add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	for node in get_tree().root.find_children("*", "Control", true, false):
		(node as Control).visible = false
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUTPUT) != OK:
		push_error("Cannot save Bunny v004 weapon grip preview")
		get_tree().quit(1)
		return
	print("BUNNY_V004_WEAPON_GRIP_VISUAL_OK: right-side one-hand pistol and two-hand rifle comparison saved")
	get_tree().quit(0)
