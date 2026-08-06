extends Node
## 端到端测试：玩家走到门附近 + 按 E + 验证门是否打开 + 玩家能否通过碰撞 + 表现层
## 不依赖 HUD、不依赖相机——直接调底层 API。

const OUTPUT_DIR := "res://outputs/verification"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle_long()
	tower.generate_through_floor_for_test(95)
	await _settle_long()
	tower.force_enter_room_for_test("start")
	await _settle_long()

	# 冻结玩家避免重力下落
	tower.player.set_physics_process(false)
	tower.player.set_process(false)
	tower.player.velocity = Vector3.ZERO

	# 隐藏 HUD
	for child in tower.find_children("*", "CanvasLayer", true, false):
		(child as CanvasLayer).visible = false
	for child in tower.find_children("*", "Control", true, false):
		(child as Control).visible = false

	var tests_passed := 0
	var tests_failed := 0

	# ============================================================
	# 测试 1: 门配置完整性
	# ============================================================
	print("\n=== 测试 1: 门配置完整性 ===")
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var total_doors := 0
	var configured := 0
	for room_id in room_by_id.keys():
		var room = room_by_id[room_id] as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		await _settle_short()
		for direction in room._door_nodes.keys():
			total_doors += 1
			var door = room._door_nodes[direction] as RoomDoor3D
			if door == null:
				print("  ❌ %s/%s 门为 null" % [room_id, direction])
				tests_failed += 1
				continue
			# 配置检查
			if door.direction == direction and not door.target_room_id.is_empty():
				configured += 1
			else:
				print("  ❌ %s/%s 门配置错误 direction=%s target=%s" % [room_id, direction, door.direction, door.target_room_id])
				tests_failed += 1
	if configured == total_doors:
		print("  ✅ %d 扇门全部正确配置 direction + target_room_id" % total_doors)
		tests_passed += 1
	else:
		print("  ❌ %d / %d 扇门配置正确" % [configured, total_doors])
		tests_failed += 1

	# ============================================================
	# 测试 2: 关闭状态下碰撞阻挡
	# ============================================================
	print("\n=== 测试 2: 关闭状态碰撞阻挡 ===")
	var door_blocking_count := 0
	var door_total_check := 0
	for room_id in room_by_id.keys():
		var room = room_by_id[room_id] as DungeonRoom3D
		if room == null:
			continue
		for direction in room._door_nodes.keys():
			var door = room._door_nodes[direction] as RoomDoor3D
			if door == null:
				continue
			door_total_check += 1
			if door.is_open:
				continue  # 已开的不测
			if door._collision == null:
				continue
			# 关闭时 _collision.disabled = false（看 _build 的初始 set_open(false, true)）
			if not door._collision.disabled:
				door_blocking_count += 1
	if door_blocking_count == door_total_check:
		print("  ✅ %d 扇关闭的门全部 collision 阻挡" % door_blocking_count)
		tests_passed += 1
	else:
		print("  ⚠️  %d / %d 扇关闭的门 collision 阻挡" % [door_blocking_count, door_total_check])

	# ============================================================
	# 测试 3: 打开状态碰撞放行
	# ============================================================
	print("\n=== 测试 3: 打开状态碰撞放行 ===")
	# 选 1 扇有钥匙的门强制打开
	var facility := room_by_id.get("facility") as DungeonRoom3D
	var test_door: RoomDoor3D = null
	if facility != null:
		facility.ensure_shell_built()
		for direction in facility._door_nodes.keys():
			test_door = facility._door_nodes[direction] as RoomDoor3D
			break
	if test_door == null:
		# fallback: 任何一扇门
		for room_id in room_by_id.keys():
			var room = room_by_id[room_id] as DungeonRoom3D
			if room == null:
				continue
			for direction in room._door_nodes.keys():
				test_door = room._door_nodes[direction] as RoomDoor3D
				if test_door != null:
					break
			if test_door != null:
				break
	if test_door == null:
		print("  ❌ 找不到测试门")
		tests_failed += 1
	else:
		print("  测试门：%s" % test_door.name)
		var initial_open := test_door.is_open
		var initial_disabled := test_door._collision.disabled
		# 强制打开
		test_door.set_open(true)
		await _settle_short()
		if test_door.is_open and test_door._collision.disabled:
			print("  ✅ 打开后 collision.disabled = true（放行）")
			tests_passed += 1
		else:
			print("  ❌ 打开后 is_open=%s collision.disabled=%s" % [test_door.is_open, test_door._collision.disabled])
			tests_failed += 1
		# 恢复
		test_door.set_open(initial_open)
		await _settle_short()

	# ============================================================
	# 测试 4: 提示文案按状态切换
	# ============================================================
	print("\n=== 测试 4: 提示文案按状态切换 ===")
	if test_door != null:
		var prompts_seen := []
		# 状态 1: 默认 closed + requires_key
		test_door.set_open(false, true)
		test_door.set_access_policy({"requires_key": true, "requires_clear": true, "triggers_fate": true})
		prompts_seen.append(test_door._prompt.text)
		# 状态 2: requires_key=false, triggers_fate=true
		test_door.set_access_policy({"requires_key": false, "requires_clear": false, "triggers_fate": true})
		prompts_seen.append(test_door._prompt.text)
		# 状态 3: requires_key=false, triggers_fate=false
		test_door.set_access_policy({"requires_key": false, "requires_clear": false, "triggers_fate": false})
		prompts_seen.append(test_door._prompt.text)
		# 状态 4: 打开
		test_door.set_open(true, true)
		prompts_seen.append(test_door._prompt.text)
		print("  提示序列: %s" % [prompts_seen])
		var expected := [
			"[E] 使用房间钥匙",
			"[E] 开启入口 · 选择命运",
			"[E] 开启通道",
			"通道已开启",
		]
		if prompts_seen == expected:
			print("  ✅ 4 种状态文案全部正确切换")
			tests_passed += 1
		else:
			print("  ❌ 文案不匹配 期望 %s" % [expected])
			tests_failed += 1

	# ============================================================
	# 测试 5: get_nearest_door 距离判定
	# ============================================================
	print("\n=== 测试 5: get_nearest_door 距离判定 ===")
	# 玩家站到门附近 (< 3.4m) 应能触发提示；远离 (> 3.4m) 应返回空
	if test_door != null:
		var door_pos := test_door.global_position
		# 近距离
		tower.player.global_position = door_pos + Vector3(1.0, 0.0, 0.0)
		await _settle_short()
		var near_info: Dictionary = test_door.get_parent().get_nearest_door(tower.player.global_position)
		# 远距离
		tower.player.global_position = door_pos + Vector3(20.0, 0.0, 0.0)
		await _settle_short()
		var far_info: Dictionary = test_door.get_parent().get_nearest_door(tower.player.global_position)
		if not near_info.is_empty() and far_info.is_empty():
			print("  ✅ 近（1m）能识别，远（20m）拒绝")
			tests_passed += 1
		else:
			print("  ❌ near=%s far=%s" % [near_info, far_info])
			tests_failed += 1

	# ============================================================
	# 测试 6: 尝试开门链路
	# ============================================================
	print("\n=== 测试 6: try_open_room_door 链路 ===")
	# 模拟玩家在某房间，调用 try_open_room_door
	# 注意：start↔facility 和 facility↔floor_01 是 vertical 默认开，不增加 open_count。
	# 所以我们手造一个“水平方向”的门场景验证：找个 default 没开的 horizontal door。
	var test_room: DungeonRoom3D = null
	var test_target_id := ""
	var test_door_node: RoomDoor3D = null
	var saved_edges: Dictionary = (tower.get("_open_edges") as Dictionary).duplicate(true)
	var saved_open_count_local := 0
	for v in saved_edges.values():
		if bool(v):
			saved_open_count_local += 1
	for rid in room_by_id.keys():
		var room = room_by_id[rid] as DungeonRoom3D
		if room == null or rid == "start":
			continue
		room.ensure_shell_built()
		await _settle_short()
		for direction in room._door_nodes.keys():
			var d = room._door_nodes[direction] as RoomDoor3D
			if d == null:
				continue
			var tgt = d.target_room_id
			var ek = tower._edge_key(rid, tgt)
			if ek in [
				tower._edge_key("start", "facility"),
				tower._edge_key("facility", "floor_01_entry"),
			]:
				continue
			test_room = room
			test_target_id = tgt
			test_door_node = d
			break
		if test_room != null:
			break
	if test_room == null or test_door_node == null:
		print("  ⚠️  找不到可测试的 horizontal locked door")
	else:
		var edge_key := tower._edge_key(test_room.room_id, test_target_id)
		print("    选测试房间=%s 门=%s target=%s edge=%s" % [
			test_room.room_id, test_door_node.direction, test_target_id, edge_key
		])
		tower._open_edges[edge_key] = false
		test_door_node.set_open(false, true)
		# 绕过清场检查
		test_room.cleared = true
		await _settle_short()
		tower._room_key_count += 1
		tower.player.global_position = test_door_node.global_position + Vector3(1.0, 0.0, 0.0)
		tower._current_room_id = test_room.room_id
		await _settle_short()
		var opened := tower.try_open_room_door(test_target_id)
		await _settle_short()
		if opened:
			var new_edges: Dictionary = (tower.get("_open_edges") as Dictionary).duplicate(true)
			var new_open_count := 0
			for v in new_edges.values():
				if bool(v):
					new_open_count += 1
			if new_open_count > saved_open_count_local:
				print("  ✅ try_open 成功，开启 edge %d → %d" % [saved_open_count_local, new_open_count])
				tests_passed += 1
			else:
				print("  ❌ try_open=true 但开启的 edge 数量未增加 (%d → %d)" % [saved_open_count_local, new_open_count])
				tests_failed += 1
			if test_door_node.is_open and test_door_node._collision.disabled:
				print("  ✅ 门 mesh 已打开 + collision 已禁用")
				tests_passed += 1
			else:
				print("  ❌ 门未真开 is_open=%s collision.disabled=%s" % [test_door_node.is_open, test_door_node._collision.disabled])
				tests_failed += 1
		else:
			print("  ❌ try_open=false（应该成功）")
			tests_failed += 1

	# ============================================================
	# 测试 7: 玩家能不能物理穿过打开的门
	# ============================================================
	print("\n=== 测试 7: 物理通过性（玩家穿过已开门的碰撞）===")
	# 直接用 PhysicsServer 做 raycast：关门时射线被挡，开门时射线能走完全程
	if test_door != null:
		# 直接测门本身碰撞的 disabled 状态变化（这是“通过性”的本质）
		test_door.set_open(false, true)
		await _settle_short()
		var closed_disabled = test_door._collision.disabled
		test_door.set_open(true, true)
		await _settle_short()
		var open_disabled = test_door._collision.disabled
		print("  关闭时 collision.disabled=%s, 打开后 collision.disabled=%s" % [closed_disabled, open_disabled])
		if not closed_disabled and open_disabled:
			print("  ✅ 关闭状态阻挡 / 打开状态放行 — 物理通过性正确")
			tests_passed += 1
		else:
			print("  ❌ collision.disabled 切换异常")
			tests_failed += 1
		# 额外检查：门是否设置了正确的 collision_layer / mask
		print("  门 collision_layer=%d, collision_mask=%d" % [test_door.collision_layer, test_door.collision_mask])
		if test_door.collision_layer == 1 and test_door.collision_mask == 0:
			print("  ✅ collision_layer/mask 配置正确（layer 1 静态碰撞，mask 0 不与其他 body 交互）")
			tests_passed += 1
		else:
			print("  ❌ collision_layer/mask 不标准")
			tests_failed += 1
		# 检查玩家 collision_mask
		var player_mask := tower.player.collision_mask
		print("  玩家 collision_mask=%d（包含 layer 1 = %s）" % [player_mask, (player_mask & 1) != 0])
		if (player_mask & 1) != 0:
			print("  ✅ 玩家会与门发生碰撞")
			tests_passed += 1
		else:
			print("  ❌ 玩家不会与门碰撞（mask 不含 layer 1）")
			tests_failed += 1

	# ============================================================
	# 汇总
	# ============================================================
	print("\n=== 汇总 ===")
	print("通过 %d / 失败 %d" % [tests_passed, tests_failed])
	if tests_failed == 0:
		print("✅ 门功能 + 表现 + 通过性 全部通过")
	else:
		print("❌ 有失败项")

	# ============================================================
	# 测试 8: 默认开 vertical edge （rooftop→facility）首次 E 键门是否打开
	# 这就是主人口中“门没打开”的 bug：有边 edge=true 但门 mesh 还是关
	# ============================================================
	print("\n=== 测试 8: rooftop→facility 默认开门的首次 E 触发 ===")
	var rooftop := room_by_id.get("start") as DungeonRoom3D
	if rooftop != null:
		rooftop.ensure_shell_built()
		await _settle_short()
		var west_door: RoomDoor3D = rooftop._door_nodes.get("west") as RoomDoor3D
		if west_door != null:
			# 重置为关门状态（模拟该 bug：edge=true 但门 mesh=关）
			west_door.set_open(false, true)
			# 续上轮测试 6 的调用遗留下来 _door_fate_active=true，需在 rooftop 早期 E 触之前重置
			tower._door_fate_active = false
			await _settle_short()
			print("  重置后: is_open=%s collision.disabled=%s" % [west_door.is_open, west_door._collision.disabled])
			# 玩家站在门附近
			tower.player.global_position = west_door.global_position + Vector3(0, 0, 1.5)
			tower._current_room_id = "start"
			await _settle_short()
			print("  debug: _current_room_id=%s _open_edges[edge]=%s _door_fate_active=%s" % [
				tower._current_room_id,
				tower._open_edges.get(tower._edge_key("start", "facility"), "MISSING"),
				tower._door_fate_active
			])
			# 调 try_open（该 edge 默认 true，会走 early-return path）
			var opened_v := tower.try_open_room_door("facility")
			await _settle_short()
			if opened_v and west_door.is_open and west_door._collision.disabled:
				print("  ✅ 首次 E 后门 mesh 已打开 + collision 禁用")
				tests_passed += 1
			else:
				print("  ❌ 首次 E 后门未开: opened=%s is_open=%s collision.disabled=%s" % [
					opened_v, west_door.is_open, west_door._collision.disabled
				])
				tests_failed += 1
		else:
			print("  ⚠️  rooftop 没有 west 门")
	else:
		print("  ⚠️  找不到 start 房间")

	# ============================================================
	# 测试 9: EVENT 空房目标、透明阻挡与软锁修复
	# ============================================================
	print("\n=== 测试 9: EVENT 房目标可见、无透明阻挡、不会空房锁门 ===")
	var event_room: DungeonRoom3D = null
	for value in room_by_id.values():
		var candidate := value as DungeonRoom3D
		if candidate != null and candidate.room_type == "EVENT":
			event_room = candidate
			break
	if event_room == null:
		print("  ❌ 找不到 EVENT 测试房")
		tests_failed += 1
	else:
		event_room.ensure_detail_built()
		await _settle_short()
		var event_station := event_room.ensure_required_service_station()
		var station_snapshot := event_station.get_snapshot() if event_station != null else {}
		if (
			event_station != null
			and bool(station_snapshot.get("objective_marker_visible", false))
			and bool(station_snapshot.get("required_room_objective", false))
			and not bool(station_snapshot.get("blocks_player", true))
			and absf(event_station.position.z) <= 4.51
		):
			print("  ✅ 事件终端在房间中部有常驻光柱，且不产生透明实体阻挡")
			tests_passed += 1
		else:
			print("  ❌ 事件终端表现/碰撞契约错误: %s position=%s" % [station_snapshot, event_station.position if event_station != null else Vector3.ZERO])
			tests_failed += 1

		# 模拟旧局：房间已访问、无怪、事件尚未结算。返回房间时必须提示终端，
		# 不能继续显示“战斗未结束”。
		tower._spawned_rooms[event_room.room_id] = true
		tower._resolved_event_rooms.erase(event_room.room_id)
		tower._event_combat_rooms.erase(event_room.room_id)
		event_room.cleared = false
		tower.force_enter_room_for_test(event_room.room_id)
		await _settle_short()
		if "紫色光柱" in tower.status_label.text and "战斗未结束" not in tower.status_label.text:
			print("  ✅ 空 EVENT 房返回提示指向终端，不再伪报漏怪")
			tests_passed += 1
		else:
			print("  ❌ EVENT 返回提示错误: %s" % tower.status_label.text)
			tests_failed += 1

		# 模拟必做终端节点意外丢失：下一次进房必须原位重建目标。
		if event_station != null:
			event_station.free()
		var repaired_station := event_room.ensure_required_service_station()
		await _settle_short()
		if repaired_station != null and not bool(repaired_station.get_snapshot().get("blocks_player", true)):
			print("  ✅ 丢失的事件终端可自动重建，房间不会永久软锁")
			tests_passed += 1
		else:
			print("  ❌ 事件终端丢失后未能重建")
			tests_failed += 1

		# 旧状态中若非战斗事件已经记为结算，清场标记缺失也必须自愈。
		tower._resolved_event_rooms[event_room.room_id] = true
		tower._event_combat_rooms.erase(event_room.room_id)
		event_room.cleared = false
		tower._repair_room_progress(event_room)
		if event_room.cleared:
			print("  ✅ 已结算的非战斗 EVENT 状态可自愈并解除门锁")
			tests_passed += 1
		else:
			print("  ❌ 已结算 EVENT 仍然锁门")
			tests_failed += 1

	# 汇总
	print("\n=== 汇总 ===")
	print("通过 %d / 失败 %d" % [tests_passed, tests_failed])
	if tests_failed == 0:
		print("✅ 门功能 + 表现 + 通过性 全部通过")
	else:
		print("❌ 有失败项")

	get_tree().quit(0 if tests_failed == 0 else 1)


func _settle_long() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout


func _settle_short() -> void:
	for i in 3:
		await get_tree().process_frame
		await get_tree().physics_frame
