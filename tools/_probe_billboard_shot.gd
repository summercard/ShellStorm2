extends Node
## 临时渲染探针：准星图标 + 敌方子弹图标的真机观感截图（2026-11-09）。
##
## 为什么需要它：headless 只能断言「基向量对不对、像素多大」，断不出「好不好看」。
## 主人要的是「准星图标」，形态得用眼睛验。
##
## 运行（必须真渲染，不能 --headless）：
##   godot --path . --resolution 1280x720 --scene res://tools/_probe_billboard_shot.tscn

const PLAYER := preload("res://scenes/Player3D.tscn")
const OUT_DIR := "res://outputs/crosshair_billboard"
## 截几张：① 常规瞄准 ② 准星贴到敌人身上（验证「图标不糊、读得清」）。
const SHOT_FRAMES := 30


func _ready() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("141d22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cfdfe6")
	environment.ambient_light_energy = 1.2
	world_environment.environment = environment
	stage.add_child(world_environment)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("2c3c44")
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)

	# 地面碰撞体：没有它玩家会一直下坠，相机跟着掉到地下 —— 截图里只剩一片灰。
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 0.2, 30.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.1, 0)
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)

	# 一面墙，用来验「准星有深度测试、不会透墙显示」。
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(8.0, 3.0, 0.3)
	wall.position = Vector3(0.0, 1.5, -9.0)
	wall.mesh = wall_mesh
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("3d525c")
	wall_mesh.material = wall_material
	stage.add_child(wall)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -34, 0)
	key.light_energy = 1.5
	stage.add_child(key)

	var player := PLAYER.instantiate() as Player3D
	stage.add_child(player)
	for i in range(30):
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.equip_weapon("bp_pistol", "mod_bullet_standard")
	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	await get_tree().process_frame
	print("PLAYER_Y=", player.global_position.y, " CAMERA=", camera.global_position)

	# 准星：摆在角色正前 5m 的瞄准平面上。
	var cursor_pos := player.global_position + Vector3(0.6, 0.75, -5.0)
	player.call("_place_aim_cursor", cursor_pos)

	# 一面挡在准星与相机之间的板子：验「准星是否被前景遮挡」。
	var blocker := MeshInstance3D.new()
	var blocker_mesh := BoxMesh.new()
	blocker_mesh.size = Vector3(2.2, 2.6, 0.16)
	var blocker_material := StandardMaterial3D.new()
	blocker_material.albedo_color = Color("7a4d4d")
	blocker_mesh.material = blocker_material
	blocker.mesh = blocker_mesh
	# 相机在角色后上方（+y +z），准星在 -z 方向 ⇒ 遮挡板放在两者之间、略偏上，
	# 只压住准星的一侧，一眼能看出「准星是否被切」。
	blocker.position = player.global_position + Vector3(0.6, 1.35, -2.7)
	blocker.rotation_degrees = Vector3(-22.0, 8.0, 0.0)
	stage.add_child(blocker)

	# 三发敌方子弹：不同弹色、不同距离，验「形状恒定、颜色可辨」。
	var colors := [Color("ff5c4d"), Color("c46bff"), Color("ffb03a")]
	for i in range(colors.size()):
		var projectile := Projectile3D.new()
		stage.add_child(projectile)
		projectile.activate({
			"direction": Vector3(0, 0, -1), "speed": 6.0, "damage": 5, "hostile": true,
			"target_group": "player_3d", "projectile_collision_mask": 1,
			"color": colors[i], "visual_scale": 1.6, "shooter": player,
		}, player.global_position + Vector3(-1.6 + float(i) * 1.5, 0.75, -3.4 - float(i) * 1.6))
		projectile.set_physics_process(false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for i in range(SHOT_FRAMES):
		await get_tree().process_frame
	await _save("crosshair_billboard_preview.png")
	get_tree().quit(0)


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, file_name]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	print("SHOT=", path, " err=", error, " size=", image.get_size())
