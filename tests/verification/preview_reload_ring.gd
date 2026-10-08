extends Node
## 换弹环**视觉预览**：按 TowerDescent3D 的真实相机姿态渲染玩家 + 换弹环，存 PNG。
##
## 为什么单独做一个：环的「位置压住角色 / 大小是否合适 / 有没有埋进地板」这三条
## 都是**屏幕空间**的判断，headless 探针（verify_3d_reload_state_flow）只能验几何
## 数值，验不了"看起来对不对"。主人已经因为看不到画面来回改了两轮，这台探针就是
## 用来终结那条盲改回路的。
##
## 不参与自动验收，故不注册进 run_verification_suite.sh。
## 运行方式：**不带 --headless**，直接跑本场景。

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const OUTPUT_DIR := "I:/工作项目/shellstrom2/outputs/reload_ring_preview"
## 与 TowerDescent3D 的 CAMERA_* 逐字一致（玩家本地系）：
##   相机 = 玩家 + (0, CAMERA_HEIGHT_M, CAMERA_DEFAULT_TRAILING_M)
##   注视点 = 玩家 + (0, CAMERA_LOOK_HEIGHT_M, -CAMERA_LOOK_AHEAD_M)
## 数值抄自 src/world3d/TowerDescent3D.gd:157-160，改动那边这里要跟着改。
const CAMERA_LOCAL := Vector3(0.0, 10.719009, 4.037671)
const LOOK_LOCAL := Vector3(0.0, 0.45, -0.75)
## 实机视角的放大倍率 —— 1.0 就是游戏里真正的样子。
const GAME_VIEW_SCALE := 1.0
## 细看视角：同一方向、把镜头拉近到 32%，用来判「环的形状/线宽/层级」。
const DETAIL_VIEW_SCALE := 0.30
## 采样进度（换弹进度 0→1 的取点）。0.45 是主人截图里那一档。
const SAMPLES := [0.45]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var stage := _build_stage()
	add_child(stage)
	var player := PLAYER_SCENE.instantiate() as Player3D
	stage.add_child(player)
	await get_tree().process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.weapon.set_process(false)
	player.combat_enabled = true
	var locomotion := player.get("_state_machine") as StateMachine
	locomotion.stop()
	locomotion.start("idle")
	player.get_node("Camera3D").current = false
	var aim_cursor := player.get_node_or_null("AimCursor") as Node3D
	if aim_cursor != null:
		aim_cursor.visible = false
	player.aim_direction = Vector3.FORWARD
	player.aim_yaw = 0.0
	player.avatar.visual_root.rotation.y = 0.0
	player.avatar.call("_process", 0.2)

	if not player.equip_weapon("bp_pistol", "mod_bullet_standard"):
		push_error("preview: cannot equip bp_pistol")
		get_tree().quit(1)
		return
	player.weapon.set_process(false)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.current = true
	stage.add_child(camera)

	var magazine := player.weapon.magazine_size
	player.weapon.current_ammo = maxi(0, magazine - 3)
	var snapshot := player.get_reload_snapshot()
	var duration := float(snapshot.get("duration", player.weapon.reload_time))

	for sample in SAMPLES:
		if not player.is_reloading():
			player.weapon.current_ammo = maxi(0, magazine - 3)
			player.weapon.request_reload()
		# 把换弹计时器推到采样点。request_reload() 之后从 0 起算。
		player.weapon.call("_process", duration * float(sample))
		player.avatar.call("_process", 0.05)
		var tag := "p%03d" % int(float(sample) * 100.0)
		await _capture(stage, player, camera, GAME_VIEW_SCALE, "game_%s" % tag)
		await _capture(stage, player, camera, DETAIL_VIEW_SCALE, "detail_%s" % tag)

	print("RELOAD_RING_PREVIEW_OK: 已保存到 %s" % OUTPUT_DIR)
	get_tree().quit(0)


## 把相机摆到"玩家 + CAMERA_LOCAL × scale"并注视玩家，等一帧真出图后存 PNG。
func _capture(stage: Node3D, player: Player3D, camera: Camera3D, scale: float, tag: String) -> void:
	camera.position = CAMERA_LOCAL * scale
	camera.look_at(LOOK_LOCAL * scale, Vector3.UP)
	camera.fov = 65.0
	camera.make_current()
	# 朝向是按相机基每帧算的，摆完相机必须让 avatar 再跑一次 _process，
	# 否则拍到的是上一档机位下的朝向。
	player.avatar.call("_process", 0.05)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT_DIR.path_join("%s.png" % tag)
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("preview: 保存失败 %s (%s)" % [path, error_string(error)])
	else:
		print("  saved %s" % path)


## 舞台：暗色环境 + 地板 + 投影主光。投影是判"环有没有埋地"的关键参照。
func _build_stage() -> Node3D:
	var stage := Node3D.new()
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("182a34")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cfe5ec")
	environment.ambient_light_energy = 1.35
	world_environment.environment = environment
	stage.add_child(world_environment)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("304953")
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor.mesh = plane
	stage.add_child(floor)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.light_energy = 1.65
	key.shadow_enabled = true
	stage.add_child(key)
	return stage
