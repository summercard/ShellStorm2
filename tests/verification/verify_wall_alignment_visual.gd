extends Node
## 验证 v0.1 改动后：四面外墙缺口是否落在 5m 网格上、墙体和地砖是否 1:1 对齐。
## 直接控制 player.camera：禁用 tower 覆盖、玩家不可见、相机自由摆位。

const OUTPUT_DIR := "res://outputs/verification"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle_long()
	tower.force_enter_room_for_test("start")
	await _settle_long()

	# 关闭所有 UI（HUD/小地图/控件）
	for child in tower.find_children("*", "CanvasLayer", true, false):
		(child as CanvasLayer).visible = false
	for child in tower.find_children("*", "Control", true, false):
		(child as Control).visible = false

	# 完全冻结塔楼逻辑（避免 _apply_indoor_camera_pose 覆盖相机）
	tower.set_physics_process(false)
	tower.set_process(false)
	tower.set_process_input(false)
	tower.set_process_unhandled_input(false)

	# 冻结玩家（避免重力下落 + 不被玩家 process 影响）
	tower.player.set_physics_process(false)
	tower.player.set_process(false)
	tower.player.velocity = Vector3.ZERO
	tower.player.visible = false

	# 控制 player.camera 直接摆位
	var cam := tower.player.camera
	cam.fov = 50.0
	cam.near = 0.3
	cam.far = 600.0

	const COMBAT_Y := -18.0
	const FLOOR_TOP := COMBAT_Y + 0.3

	# 1. 北墙缺口：正对北墙，相机高 5m，距离 10m 远
	_take(cam, "north_hole",
		Vector3(-2.5, FLOOR_TOP + 6.0, -135.0),
		Vector3(-2.5, FLOOR_TOP + 1.0, -125.0),
		40.0)
	# 2. 南墙缺口
	_take(cam, "south_hole",
		Vector3(17.5, FLOOR_TOP + 6.0, 135.0),
		Vector3(17.5, FLOOR_TOP + 1.0, 125.0),
		40.0)
	# 3. 西墙缺口
	_take(cam, "west_hole",
		Vector3(-135.0, FLOOR_TOP + 6.0, 12.5),
		Vector3(-125.0, FLOOR_TOP + 1.0, 12.5),
		40.0)
	# 4. 东墙缺口
	_take(cam, "east_hole",
		Vector3(135.0, FLOOR_TOP + 6.0, -2.5),
		Vector3(125.0, FLOOR_TOP + 1.0, -2.5),
		40.0)

	# 5. 战斗层斜俯视
	cam.fov = 45.0
	cam.global_position = Vector3(0.0, COMBAT_Y + 180.0, 0.0)
	cam.rotation_degrees = Vector3(-65.0, 0.0, 0.0)
	await _wait_render()
	_save("oblique_combat")

	# 6. 战斗层正俯视
	cam.fov = 40.0
	cam.global_position = Vector3(0.0, COMBAT_Y + 250.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _wait_render()
	_save("topdown_combat")

	print("截图完成 → %s" % OUTPUT_DIR)
	get_tree().quit()


func _take(cam: Camera3D, label: String, pos: Vector3, look_at: Vector3, fov_deg := 50.0) -> void:
	cam.fov = fov_deg
	cam.global_position = pos
	cam.look_at(look_at, Vector3.UP)
	await _wait_render()
	_save(label)


func _save(label: String) -> void:
	var path := "%s/wall_alignment_%s.png" % [OUTPUT_DIR, label]
	var image := get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(path)
		print("已存 %s  size=%s" % [path, image.get_size()])
	else:
		print("截图失败 %s" % path)


func _wait_render() -> void:
	# 强制 viewport 重渲染 + 等待 GPU 帧绘完
	RenderingServer.force_draw()
	for i in 4:
		await RenderingServer.frame_post_draw
		RenderingServer.force_draw()


func _settle_long() -> void:
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout