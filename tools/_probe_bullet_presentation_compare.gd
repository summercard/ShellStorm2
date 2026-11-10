extends Node
## 临时渲染探针：敌方子弹「3D 弹体（默认）」vs「公告板图标 70%」同屏对照（2026-11-10）。
##
## 为什么要它：2026-11-10 业主回退到 3D 弹体，同时要求公告板保留、图标缩到 70%。
## headless 只能断言尺寸与朝向，断不出「到底哪个更像弹丸」—— 必须一张同屏图。
##
## 布局：左列三发 = 默认（不传 `billboard`，走 3D 弹体）；右列三发 = 显式 `billboard = true`。
## 两列弹色一一对应（红 / 紫 / 橙），距离与高度相同，便于逐颗比对。
##
## 运行（必须真渲染，不能 --headless）：
##   godot --path . --resolution 1280x720 --scene res://tools/_probe_bullet_presentation_compare.tscn

const PLAYER := preload("res://scenes/Player3D.tscn")
const OUT_DIR := "res://outputs/bullet_presentation_20261110"
const SHOT_FRAMES := 24
## 敌弹视觉倍率：与远征03 的 `monster_rules.projectile.visual_scale` 同口径。
const ENEMY_VISUAL_SCALE := 1.6


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

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 0.2, 30.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.1, 0)
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)

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

	var colors := [Color("ff5c4d"), Color("c46bff"), Color("ffb03a")]
	# 左列（3D 弹体）/ 右列（公告板 70%）：同为三发，弹色与纵深一一对应。
	var columns := [
		{"x": -1.7, "billboard": false, "label": "3D"},
		{"x": 1.1, "billboard": true, "label": "BILLBOARD70"},
	]
	for column in columns:
		for i in range(colors.size()):
			var projectile := Projectile3D.new()
			stage.add_child(projectile)
			var config := {
				"direction": Vector3(0, 0, -1), "speed": 6.0, "damage": 5, "hostile": true,
				"target_group": "player_3d", "projectile_collision_mask": 1,
				"color": colors[i], "visual_scale": ENEMY_VISUAL_SCALE, "shooter": player,
			}
			if bool(column["billboard"]):
				config["billboard"] = true
			projectile.activate(
				config,
				player.global_position
				+ Vector3(
					float(column["x"]) + float(i) * 0.55,
					0.75,
					-3.2 - float(i) * 1.4
				)
			)
			projectile.set_physics_process(false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for i in range(SHOT_FRAMES):
		await get_tree().process_frame
	await _save("compare_3d_vs_billboard70.png")
	get_tree().quit(0)


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, file_name]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	print("SHOT=", path, " err=", error, " size=", image.get_size())
