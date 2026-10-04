extends Node3D
const ENEMY := preload("res://scenes/enemies/fat_zombie03.tscn")
const PLAYER := preload("res://scenes/Player3D.tscn")
var enemy: Enemy3D
var camera: Camera3D
var player: Player3D
var label: Label
var capture := false
func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.10, 0.13, 0.16)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	collider.shape = box
	floor_body.add_child(collider)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = box.size
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.21, 0.24, 0.26)
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	floor_body.position.y = -0.1
	add_child(floor_body)
	player = PLAYER.instantiate() as Player3D
	player.position = Vector3(0, 0, -4)
	player.start_with_weapon = true
	add_child(player)
	camera = Camera3D.new()
	camera.position = Vector3(5, 8, -7)
	add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 22)
	ui.add_child(label)
	spawn()
	if capture:
		player.hide()
		player.set_physics_process(false)
		enemy.set_physics_process(false)
		enemy.set_process(false)
		enemy.avatar._formal_normal_root.set_process(false)
		label.text = "Fat zombie 03 | 2.2 m | 13 animations | shared Enemy3D FSM"
		await take_gallery()
		get_tree().quit()

func spawn() -> void:
	if is_instance_valid(enemy): enemy.free()
	enemy = ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.configure_from_enemy_data(MonsterInjector.new().generate_box_enemy("fat_zombie03", 1, 0))
	enemy.notify_attacked_by(player)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R: spawn()
		elif event.keycode == KEY_K and is_instance_valid(enemy): enemy.take_damage(99999)

func _process(_delta: float) -> void:
	if not capture:
		label.text = "Fat zombie 03 | WASD move / mouse fire | R respawn | K death\n" + ("HP %d / %d | %s" % [enemy.current_hp, enemy.max_hp, enemy.ai_state] if is_instance_valid(enemy) else "Dead; press R")

func take_gallery() -> void:
	var output := "res://outputs/fat_zombie03_integration"
	DirAccess.make_dir_recursive_absolute(output)
	camera.size = 5
	for item in [["idle", "idle", 0.0], ["run_top", "chase", 0.4], ["clap", "attack", 0.0], ["dead_contact", "dead", 2.2]]:
		camera.position = Vector3(0, 7, -0.1) if item[0] == "run_top" else Vector3(4, 2.8, -5)
		camera.look_at(Vector3(0, 0.85, 0))
		var visual = enemy.avatar._formal_normal_root
		visual._locomotion_phase = 0.4
		visual.sync_state(item[1], item[2], 0.6, 1.2, 1.3)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(output + "/" + item[0] + ".png")
		assert(error == OK)
	print("FAT_ZOMBIE03_RENDER_OK real_renderer=", RenderingServer.get_current_rendering_method())
