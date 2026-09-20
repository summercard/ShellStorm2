extends Node3D
const ENEMY = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.12, 0.15, 0.19)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.8
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(2.5, 1.8, -4.0)
	add_child(camera)
	camera.look_at(Vector3(0, 0.75, 0))
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.3
	var e = ENEMY.instantiate()
	add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	await get_tree().process_frame
	e.avatar.sync_presentation("telegraph", 0.20, 0.0, 0.38, 0.34)
	await RenderingServer.frame_post_draw
	var path := "I:/工作项目/shellstrom2/outputs/little_zombie_godot.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("ZOMBIE_RENDER_OK ", path)
	e.free()
	get_tree().quit()
