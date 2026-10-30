extends Node3D
## 小僵尸死亡可见性 —— 「绿色方块爆开、不留尸体」改动后的新契约（业主 2026-10-14）。
##
## 历史背景：改动前小僵尸死后会播 2.4s **倒地动画**并留下一具**尸体**，由 PlayerVision3D
## 按距离/遮挡管理显隐，本验收守的就是那条链。业主改为「死后不再有倒地动画，改播绿色方块
## 爆开（FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D`）、尸体一并取消」后，**尸体这条链整体消失**，
## 于是本验收改为守新契约：
##   1. 活体照旧被视野系统追踪、可见（不能因为改了死亡表现而把活体也弄没了）；
##   2. 死后**不留尸体**：节点立即回收、不再靠物理 AI 跑死亡时钟；
##   3. 死亡结算（`killed`）恰好一次；
##   4. `enemy_death_visual_3d` 必须干净（没有尸体就不该有组标记残留）。
## 反向对照 `--negative-untracked`：注入一个假的组标记 ⇒ 第 4 条必须变红
## （证明「组必须是空的」这条断言真的有辨别力，而不是恒真）。
##
## 特效侧（FX01-19 的资产契约、三段节奏、地面平铺、floor_y、端到端接线）另由
## `verify_zombie_goo_death_vfx` 专测，本文件只管「视野 / 尸体」这一面。

var failures: Array[String] = []
var killed_count := 0
var capture := false
var output_dir := ""


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func shot(name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(name + ".png"))


func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	if output_dir.is_empty():
		output_dir = OS.get_user_data_dir().path_join("melee_zombie_death_visibility")
	DirAccess.make_dir_recursive_absolute(output_dir)
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
	enemy.configure_from_enemy_data({"enemy_type": "melee_chaser", "name": "小僵尸"})
	enemy.set_physics_process(false)
	await get_tree().physics_frame
	vision._refresh_target_visibility()
	check(enemy.visible, "live enemy not visible")
	check(vision._tracked_enemy_ids.has(enemy.get_instance_id()), "live enemy not tracked before death")

	await shot("living")

	enemy.killed.connect(func(_enemy: Enemy3D, _data: Dictionary):
		killed_count += 1
		# 同步击杀订阅者可能切换房间激活；不能因此复活死亡流程。
		enemy.set_runtime_active(false, false))
	# 「倒地段」本来多长 —— 只有它确实存在时，「回收得比它快」才说明倒地动画真被去掉了
	var fall_duration := 0.0
	if enemy.avatar != null and enemy.avatar.has_formal_normal():
		fall_duration = enemy.avatar.get_formal_death_duration()
	check(fall_duration > 2.0, "control invalid: melee fall-down segment should be > 2s (got %.2f)" % fall_duration)
	enemy.take_damage(99999)
	# 死亡同帧：模型必须已收起（倒地动画做不到 —— 它要先留一具躯干在场上播 2.4s）
	if enemy.avatar != null and enemy.avatar.has_formal_normal():
		check(not enemy.avatar.visible, "death frame kept the model visible (falling-down animation still running)")
	# 反向对照注入点：改动后「尸体显影组」这条链已不存在，注入一个假组标记来验判据有辨别力
	if OS.get_cmdline_user_args().has("--negative-untracked"):
		var stale := Node3D.new()
		stale.name = "StaleCorpseStub"
		add_child(stale)
		stale.add_to_group("enemy_death_visual_3d")

	await shot("impact")
	await get_tree().create_timer(0.35).timeout
	check(not is_instance_valid(enemy), "corpse kept after death (falling-down animation must be gone)")
	check(get_tree().get_nodes_in_group("enemy_death_visual_3d").is_empty(), "corpse group leaked")
	check(killed_count == 1, "death settlement repeated")

	var negative := OS.get_cmdline_user_args().has("--negative-untracked")
	var name := "negative" if negative else "render" if capture else "logic"
	FileAccess.open(output_dir.path_join(name + ".json"), FileAccess.WRITE).store_string(
		JSON.stringify({"passed": failures.is_empty(), "failures": failures, "real_renderer": capture}, "\t")
	)
	for failure in failures:
		push_error(failure)
	print("MELEE_ZOMBIE_DEATH_VISIBILITY_", "OK" if failures.is_empty() else "FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
