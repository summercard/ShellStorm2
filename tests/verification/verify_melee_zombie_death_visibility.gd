extends Node3D
var failures: Array[String] = []
var killed_count := 0
var capture := false
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func shot(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://outputs/melee_zombie_reduction/" + name + ".png")
func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	DirAccess.make_dir_recursive_absolute("res://outputs/melee_zombie_reduction")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(4, 3, -5)
	add_child(camera)
	camera.look_at(Vector3(0, 0.55, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	camera.current = true
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(15, 0.2, 15)
	floor_shape.shape = floor_box
	ground.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = floor_box.size
	floor_mesh.mesh = mesh
	ground.add_child(floor_mesh)
	ground.position.y = -0.1
	add_child(ground)
	var player := load("res://scenes/Player3D.tscn").instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(0, 0, -4)
	add_child(player)
	player.set_physics_process(false)
	player.hide()
	camera.current = true
	var vision := player.get_node("PlayerVision3D") as PlayerVision3D
	var enemy := load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn").instantiate() as Enemy3D
	add_child(enemy)
	enemy.configure_from_enemy_data({"enemy_type":"melee_chaser", "name":"小僵尸"})
	enemy.set_physics_process(false)
	await get_tree().physics_frame
	vision._refresh_target_visibility()
	check(enemy.visible, "live enemy not visible")
	check(vision._tracked_enemy_ids.has(enemy.get_instance_id()), "live enemy not tracked before death")
	enemy.killed.connect(func(_enemy: Enemy3D, _data: Dictionary):
		killed_count += 1
		# 同步击杀订阅者可能切换房间激活；不能暂停死亡表现。
		enemy.set_runtime_active(false, false))
	enemy.take_damage(99999)
	if OS.get_cmdline_user_args().has("--negative-untracked"):
		enemy.remove_from_group("enemy_death_visual_3d")
	await get_tree().create_timer(0.35).timeout
	check(is_instance_valid(enemy) and enemy.visible, "death disappeared after AI unregister")
	check(not enemy.is_in_group("enemy_3d") and not enemy.is_in_group("damageable_3d"), "corpse still combat target")
	check(enemy.is_in_group("enemy_death_visual_3d"), "corpse visibility group missing")
	check(enemy._state_time > 0.25 and not enemy.is_physics_processing(), "death clock requires physics AI")
	check(enemy.avatar._formal_normal_root.get_presentation_snapshot().clip == "dead", "death clip not sampled")
	check(enemy.avatar._formal_normal_root.get_presentation_snapshot().sample_time > 0.25, "death animation stuck at first frame")
	await shot("falling")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(0, 1, -2)
	add_child(wall)
	await get_tree().create_timer(0.12).timeout
	check(not enemy.visible, "corpse visible through wall")
	wall.free()
	await get_tree().create_timer(0.12).timeout
	check(enemy.visible, "corpse failed to reappear when wall removed")
	await get_tree().create_timer(0.6).timeout
	await shot("impact")
	await get_tree().create_timer(0.2).timeout
	await shot("bounce")
	player.position = Vector3(0, 0, -40)
	await get_tree().create_timer(0.1).timeout
	check(not enemy.visible, "corpse visible outside vision range")
	player.position = Vector3(0, 0, -4)
	await get_tree().create_timer(0.1).timeout
	check(enemy.visible, "corpse did not reappear inside vision range")
	await get_tree().create_timer(0.55).timeout
	check(is_instance_valid(enemy) and enemy.visible, "death recycled before settling")
	await shot("settled")
	await get_tree().create_timer(0.7).timeout
	check(not is_instance_valid(enemy), "corpse not recycled at end")
	check(killed_count == 1, "death settlement repeated")
	check(get_tree().get_nodes_in_group("enemy_death_visual_3d").is_empty(), "corpse group leaked")
	var negative := OS.get_cmdline_user_args().has("--negative-untracked")
	var name := "negative" if negative else "render" if capture else "logic"
	FileAccess.open("res://outputs/melee_zombie_reduction/" + name + ".json", FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(), "failures":failures, "real_renderer":capture}, "\t"))
	for failure in failures: push_error(failure)
	print("MELEE_ZOMBIE_DEATH_VISIBILITY_", "OK" if failures.is_empty() else "FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
