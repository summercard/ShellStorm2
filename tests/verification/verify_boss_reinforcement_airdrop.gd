extends Node
## 正式Boss实体激活、真实预约/flush和物理重力落地专项。
const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
var tower: TowerDescent3D
var room: DungeonRoom3D
var checks := 0
var failures: Array[String] = []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		print("BOSS_AIRDROP_FAIL ", text)

func actors(dynamic_only := false) -> Array[Enemy3D]:
	var out: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get("boss", []):
		if is_instance_valid(value) and not value.is_queued_for_deletion() and value.ai_state != "dead":
			if not dynamic_only or bool(value.enemy_data.get("boss_reinforcement_spawned", false)):
				out.append(value)
	return out

func _ready() -> void:
	var a := OS.get_environment("APPDATA").replace("\\", "/").to_lower()
	var b := OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower()
	check(a != b and a.get_base_dir() == b.get_base_dir() and a.ends_with("/appdata") and b.ends_with("/localappdata") and (a.contains("/flow_integration/") or a.contains("/shellstorm-verification.")), "必须隔离用户目录")
	if not failures.is_empty():
		await finish()
		return
	tower = SCENE.instantiate()
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started:
			break
		await get_tree().process_frame
	check(tower._main_story_gameplay_started and tower._room_by_id.has("boss"), "正式场景未就绪")
	if not tower._main_story_gameplay_started:
		await finish()
		return
	tower.set_process(false)
	tower.player.set_physics_process(false)
	room = tower._room_by_id["boss"]
	room.ensure_shell_built()
	room.ensure_detail_built()
	tower.player.global_position = room.boss_spawn_position_world() + Vector3(7, 0.5, 0)
	tower.force_enter_room_for_test("boss")
	await get_tree().physics_frame
	await get_tree().process_frame
	var boss := tower._boss_reinforcement_boss("boss")
	check(boss != null, "未通过正式盒生成Boss实体")
	if boss == null:
		await finish()
		return
	boss.set_runtime_active(true, true)
	boss.monitor_combat.request_story_activation()
	for _frame in 70:
		boss._physics_process(0.1)
	check(boss.monitor_combat.activation_completed and bool(tower._boss_reinforcement_states.get("boss", {}).get("armed", false)), "实际激活未接入增援")
	if not boss.monitor_combat.activation_completed:
		await finish()
		return
	boss.set_physics_process(false)
	# 等待原静态随从的1.5/3秒延迟，不把它们冒充动态增援。
	await get_tree().create_timer(3.2, false).timeout
	for actor in actors():
		actor.set_physics_process(false)
	var static_count := actors().size()
	check(static_count >= 4 and actors(true).is_empty(), "静态随从/动态身份错误")
	print("BOSS_AIRDROP_STATE armed=", tower._boss_reinforcement_states.get("boss", {}), " alive=", tower._boss_reinforcement_alive("boss"), " current=", tower._current_room_id)
	var probe_requested: Array[Vector3] = []
	for marker: Marker3D in room.boss_reinforcement_spawn_markers():
		probe_requested.append(room.to_global(Vector3(marker.position.x, 0.0, marker.position.z)))
	var narrative_landings := room.resolve_narrative_floor_positions(probe_requested, [], 3.0)
	var enemy_landings: Array = []
	for point in probe_requested:
		enemy_landings.append(room.resolve_enemy_spawn_position(point))
	print("BOSS_AIRDROP_LANDINGS narrative=", narrative_landings, " enemy=", enemy_landings)
	tower._tick_boss_reinforcements(11.9)
	check(tower._reserved_spawn_count("boss") == 0 and actors(true).is_empty(), "12秒前提前投放")
	tower._tick_boss_reinforcements(0.1)
	print("BOSS_AIRDROP_PLAN ", room.boss_reinforcement_plan, " markers=", room.boss_reinforcement_spawn_markers().size())
	check(tower._reserved_spawn_count("boss") == 3 and actors(true).is_empty(), "首轮没有真实预约3只")
	var requests := tower._reserved_room_spawns.get("boss", []) as Array
	if requests.is_empty():
		await finish()
		return
	var request := requests[0] as Dictionary
	for config: Dictionary in request["configs"]:
		var landing: Vector3 = config["spawn_landing_anchor"]
		check(room.resolve_enemy_spawn_position(landing).is_finite() and room.resolve_enemy_spawn_position(landing).distance_to(landing) < 0.05, "预约landing无真实支撑/净距")
	for point: Array in request["positions"]:
		check(is_equal_approx(float(point[1]) - room.global_position.y, 3.0), "空投3m起点被改成地面")
	tower._flush_reserved_room_spawns("boss")
	check(actors(true).size() == 3 and tower._reserved_spawn_count("boss") == 0, "reserve→flush没有实际3实体或预约未清")
	check(not tower._room_spawn_blocked.has("boss"), "空投错误污染room_spawn_blocked")
	for actor in actors(true):
		check(is_equal_approx(actor.global_position.y - room.global_position.y, 3.0), "实际实体不是3m投放")
		check(actor._external_velocity.length() > 0.0 and actor._external_timer > 0.0, "原水平物理投放未保留")
		actor.set_physics_process(true)
	await get_tree().create_timer(1.0, false).timeout
	for actor in actors(true):
		check(actor.global_position.y < room.global_position.y + 0.3 and actor.is_on_floor(), "空投实体未实际重力落地")
		actor.set_physics_process(false)
	check(actors().size() - actors(true).size() == static_count, "动态投放改变静态随从计数")
	print("BOSS_AIRDROP_FIRST actual=3 reserved=0 height=3 landed=true static=", static_count)
	tower._tick_boss_reinforcements(8.9)
	check(actors(true).size() == 3 and tower._reserved_spawn_count("boss") == 0, "后续9秒前提前投放")
	tower._tick_boss_reinforcements(0.1)
	check(tower._reserved_spawn_count("boss") == 3, "后续9秒未预约3只")
	tower._flush_reserved_room_spawns("boss")
	check(actors(true).size() == 6 and tower._reserved_spawn_count("boss") == 0, "第二轮未达到实际6只")
	for actor in actors(true):
		actor.set_physics_process(false)
	tower._tick_boss_reinforcements(9.0)
	check(actors(true).size() == 6 and tower._reserved_spawn_count("boss") == 0, "增援突破6上限")
	# 释放动态3只，再让已到期轮次生成；故意损坏一次起点，验证失败预约退出并重试。
	for actor in actors(true).slice(0, 3):
		tower._on_enemy_killed(actor, actor.get_enemy_data())
		actor.free()
	tower._tick_boss_reinforcements(0.01)
	check(tower._reserved_spawn_count("boss") == 3, "腾出容量后未重试预约")
	var bad := (tower._reserved_room_spawns["boss"] as Array)[0] as Dictionary
	bad["positions"][0][1] = -1000.0
	tower._flush_reserved_room_spawns("boss")
	check(tower._reserved_spawn_count("boss") == 0 and actors(true).size() == 3 and not tower._room_spawn_blocked.has("boss"), "失败预约永久占容量或假生成")
	tower._tick_boss_reinforcements(0.01)
	tower._flush_reserved_room_spawns("boss")
	check(actors(true).size() == 6 and tower._reserved_spawn_count("boss") == 0, "失败后不能正常补投")
	for actor in actors(true):
		actor.set_physics_process(false)
	for actor in actors(true).slice(0, 3):
		tower._on_enemy_killed(actor, actor.get_enemy_data())
		actor.free()
	tower._tick_boss_reinforcements(9.0)
	check(tower._reserved_spawn_count("boss") == 3, "死亡窗口前预约未建立")
	boss.take_damage(boss.current_hp + 100000)
	tower._flush_reserved_room_spawns("boss")
	tower._tick_boss_reinforcements(30.0)
	check(actors(true).size() == 3 and tower._reserved_spawn_count("boss") == 0, "Boss死亡后继续投放或预约未释放")
	check(bool(tower._boss_reinforcement_states["boss"].get("stopped", false)), "Boss死亡未停止控制器")
	check(not tower._room_spawn_blocked.has("boss"), "末态留下刷怪阻塞")
	print("BOSS_AIRDROP_CAP_AND_STOP max_alive=6 failed_reservation_released=true death_stopped=true")
	await finish()

func finish() -> void:
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print("BOSS_REINFORCEMENT_AIRDROP_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
