extends Node3D
## 胖子僵尸死亡可见性 —— 「橙红方块 + 绿色冲击波自爆、不留尸体」改动后的新契约（业主 2026-10-14）。
##
## 历史背景：改动前胖子僵尸死后会播 2.6s **倒地动画**并留下一具**尸体**（含
## `BellyGroundCompression` 压地 blend shape），由 PlayerVision3D 按距离/遮挡管理显隐，
## 本验收守的就是那条链。业主第二轮明确「**同样去掉胖子僵尸的倒地动画播放**」、
## 并把自爆重做为「橙红方块 + 绿色冲击波」后，**尸体这条链整体消失**，
## 于是本验收改为守新契约：
##   1. 活体照旧被视野系统追踪、可见（不能因为改了死亡表现而把活体也弄没了）；
##   2. 死后**不留尸体**：死亡同帧模型已收起、节点 2 帧内回收、不再靠物理 AI 跑死亡时钟；
##   3. 死亡表现真的出过：借出了 FX01-17 `VFX-DEATH-BLAST-3D`，且**没有**误借 FX01-19；
##   4. 死亡结算（`killed`）恰好一次；
##   5. `enemy_death_visual_3d` 必须干净（没有尸体就不该有组标记残留）。
## 反向对照 `--negative-untracked`：注入一个假的组标记 ⇒ 第 5 条必须变红
## （证明「组必须是空的」这条断言真的有辨别力，而不是恒真）。
##
## 特效侧（FX01-17 的方块/冲击波/灯、FX01-19 的 ×2 与绿色冲击波、两者各自的 floor_y）
## 另由 `verify_death_blast_vfx` / `verify_zombie_goo_death_vfx` / `verify_hit_routing_vfx` 专测；
## 本文件只管「视野 / 尸体」这一面。

var failures: Array[String] = []
var killed_count := 0
var capture := false


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func shot(name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://outputs/fat_zombie03_death_fix/" + name + ".png")


func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	DirAccess.make_dir_recursive_absolute("res://outputs/fat_zombie03_death_fix")
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
	camera.look_at(Vector3(0, 0.8, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.7
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

	var enemy := load("res://scenes/enemies/fat_zombie03.tscn").instantiate() as Enemy3D
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().physics_frame
	vision._refresh_target_visibility()
	check(enemy.visible, "live enemy not visible")
	check(vision._tracked_enemy_ids.has(enemy.get_instance_id()), "live enemy not tracked before death")
	check(enemy.uses_no_corpse_death(), "fat zombie not in the no-corpse list (falling animation must be gone)")
	check(not enemy.uses_goo_death_burst(), "fat zombie must use its own blast, not FX01-19")
	# 「倒地段」本来多长 —— 只有它确实存在时，「回收得比它快」才说明倒地动画真被去掉了
	var fall_duration := 0.0
	if enemy.avatar != null and enemy.avatar.has_formal_normal():
		fall_duration = enemy.avatar.get_formal_death_duration()
	check(fall_duration > 2.0, "control invalid: fat zombie fall-down segment should be > 2s (got %.2f)" % fall_duration)

	var pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	var pool := pools[0] as VfxPool3D if not pools.is_empty() and pools[0] is VfxPool3D else null
	check(pool != null, "VfxPool missing; blast booking not verified")
	var blast_before := pool.active_count(VfxPool3D.FX01_DEATH_BLAST) if pool != null else 0
	var goo_before := pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH) if pool != null else 0

	enemy.killed.connect(func(_enemy: Enemy3D, _data: Dictionary):
		killed_count += 1
		# 同步击杀订阅者可能切换房间激活；不能因此复活死亡流程。
		enemy.set_runtime_active(false, false))
	enemy.take_damage(99999)
	# 死亡同帧：模型必须已收起（倒地动画做不到 —— 它要先留一具躯干在场上播 2.6s）
	if enemy.avatar != null and enemy.avatar.has_formal_normal():
		check(not enemy.avatar.visible, "death frame kept the model visible (falling-down animation still running)")
	check(not enemy.is_in_group("enemy_death_visual_3d"), "no-corpse death must not join the corpse visibility group")
	if pool != null:
		check(pool.active_count(VfxPool3D.FX01_DEATH_BLAST) == blast_before + 1,
			"death did not book FX01-17 blast (%d -> %d)"
			% [blast_before, pool.active_count(VfxPool3D.FX01_DEATH_BLAST)])
		check(pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH) == goo_before,
			"death wrongly booked FX01-19 (melee zombie death asset)")
	# 反向对照注入点：改动后「尸体显影组」这条链已不存在，注入一个假组标记来验判据有辨别力
	if OS.get_cmdline_user_args().has("--negative-untracked"):
		var stale := Node3D.new()
		stale.name = "StaleCorpseStub"
		add_child(stale)
		stale.add_to_group("enemy_death_visual_3d")

	await shot("blast")
	await get_tree().create_timer(0.35).timeout
	check(not is_instance_valid(enemy), "corpse kept after death (falling-down animation must be gone)")
	check(get_tree().get_nodes_in_group("enemy_death_visual_3d").is_empty(), "corpse group leaked")
	check(killed_count == 1, "death settlement repeated")
	if pool != null:
		pool.clear_kind(VfxPool3D.FX01_DEATH_BLAST)

	var negative := OS.get_cmdline_user_args().has("--negative-untracked")
	var name := "negative" if negative else "render" if capture else "logic"
	FileAccess.open("res://outputs/fat_zombie03_death_fix/" + name + ".json", FileAccess.WRITE).store_string(
		JSON.stringify({"passed": failures.is_empty(), "failures": failures, "real_renderer": capture}, "\t")
	)
	for failure in failures:
		push_error(failure)
	print("FAT_ZOMBIE03_DEATH_VISIBILITY_", "OK" if failures.is_empty() else "FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
