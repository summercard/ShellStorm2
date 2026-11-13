extends Node3D
## 远征03 清房掉落的**房间边界**：无怪房永远不掉箱。
##
## 业主 2026-11-09 报障：走进通道房（`connector_10x30`）地上摆着一只宝箱。
## 根因不是宝箱房配置，而是清房掉落（`clear_drops.content_room.chest_chance = 1.0`）
## 把「无怪房」也算成了内容房：无怪房进房即 `cleared = true`，
## `_mark_room_cleared()` 的 `was_cleared = false` 分支照常 deferred 一次
## `_ensure_room_clear_drop()`，于是每间通道 / 商店 / Boss 前厅都白送一只箱子。
##
## 这条用例守两件事，缺一条都会退化成「全绿但玩家仍看到箱子」：
##   A 无怪房（走廊 / 商店 / 前厅）：跑一遍清房入口，名下**一只箱子都不许有**；
##   B 战斗房：清房仍必须掉箱（防止把整条清房掉落一起关掉，用「没有箱子」换绿）。
##
## 判据用 `authored_layout_peaceful`（无怪房的唯一事实所有者），**不用房型名**：
## 走廊运行时 `room_type` 是空串、商店是 `MERCHANT`、前厅是 `UPGRADE` ——
## 按房型排除必漏，这正是本次故障的形态。

const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED := 77003244
## 宝箱房恒 2 间（设计 §8）：两间 `REWARD` 各 1 只高级箱。少于 2 说明用例扫错了层。
const EXPECTED_REWARD_ROOMS := 2

var _checks := 0
var _failures := 0
var _tower: TowerDescent3D


class EntrySnapshotProbe extends Node:
	var tower: TowerDescent3D
	var captures: Array[Dictionary] = []

	func build_runtime_save_snapshot() -> Dictionary:
		var snapshot := tower.build_runtime_save_snapshot()
		captures.append({"room": snapshot.get("current_room_id"), "frame": Engine.get_process_frames()})
		return snapshot


func _ready() -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	await _run()
	print("EXP03_CLEAR_DROP checks=%d failures=%d" % [_checks, _failures])
	if _failures == 0:
		print("EXP03_CLEAR_DROP_OK")
	get_tree().quit(0 if _failures == 0 else 1)


func _run() -> void:
	_tower = LEVEL.instantiate() as TowerDescent3D
	_tower.set("test_mode", true)
	_tower.set("run_seed_override", SEED)
	add_child(_tower)
	await _settle(20)
	_tower.set_process(false)
	if "--entry-only" in OS.get_cmdline_user_args():
		await _verify_entry_idempotency()
		_tower.call("_unregister_runtime_persistence", false)
		_tower.queue_free()
		await _settle(2)
		return

	var service: RefCounted = _tower.get("_clear_drop_service") as RefCounted
	if service == null or not bool(service.call("is_configured")):
		_fail("清房掉落服务未配置（clear_drops 段没生效，本用例无法验证）")
		return

	var rooms := _tower.get("_room_by_id") as Dictionary
	_check(not rooms.is_empty(), "关卡没有房间表")

	var peaceful_checked := 0
	var declared_rooms: Array[String] = []
	var combat_checked := 0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		# 先逼出细节树：宝箱由 `_build_detail()` 建，不建就永远「场上没有箱子」——
		# 那是假绿（本工程在挂载门禁上踩过同形状的坑）。
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()

	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		# —— 设计期声明了宝箱的房（REWARD）：箱子必须真的建出来 ——
		if not room.chest_placements.is_empty():
			declared_rooms.append(room.room_id)
			var declared_built := room.get_treasure_chests().size()
			_check(
				declared_built == room.chest_placements.size(),
				"%s 声明 %d 只宝箱，实际建出 %d 只"
				% [room.room_id, room.chest_placements.size(), declared_built]
			)
			continue

		# —— A 无怪房：跑一遍清房入口，不许掉箱 ——
		if room.authored_layout_peaceful:
			peaceful_checked += 1
			room.cleared = true
			_tower.set("_current_room_id", room.room_id)
			_tower.call("_ensure_room_clear_drop", room)
			await _settle(2)
			var spawned := room.find_chest_by_id("drop_%s" % room.room_id)
			_check(
				spawned == null,
				"无怪房 %s（room_type=%s）被清房掉落塞了宝箱" % [room.room_id, room.room_type]
			)
			_check(
				room.get_treasure_chests().is_empty(),
				"无怪房 %s 场上仍有 %d 只宝箱" % [room.room_id, room.get_treasure_chests().size()]
			)
			continue

		# —— B 战斗房：清房仍必须按掷骰结果掉箱 ——
		if combat_checked >= 3:
			continue
		if room.room_type == "BOSS":
			continue
		combat_checked += 1
		room.cleared = true
		_tower.set("_current_room_id", room.room_id)
		_tower.call("_ensure_room_clear_drop", room)
		await _settle(2)
		var expected: Dictionary = service.call(
			"roll_room_drop", room.room_id, "content", _tower.run_seed
		)
		var chest := room.find_chest_by_id("drop_%s" % room.room_id)
		if str(expected.get("kind", "")) == "chest":
			_check(chest != null, "战斗房 %s 掷骰为宝箱，场上却没有" % room.room_id)
		else:
			_check(chest == null, "战斗房 %s 掷骰不是宝箱，场上却建了一只" % room.room_id)

	_check(peaceful_checked > 0, "没有扫到任何无怪房（用例空转，判据可能写错）")
	_check(combat_checked > 0, "没有扫到任何战斗房（B 段空转）")
	_check(
		declared_rooms.size() == EXPECTED_REWARD_ROOMS,
		"宝箱房数量应为 %d，实际 %d：%s"
		% [EXPECTED_REWARD_ROOMS, declared_rooms.size(), str(declared_rooms)]
	)


func _verify_entry_idempotency() -> void:
	# 外层必须先隔离 Autoload；这里的 false 样本真实调用过房快照入口。
	if OS.get_environment("SHELLSTORM_ENTRY_ISOLATED") != "1" or not "room_entry_idempotency" in OS.get_environment("APPDATA"):
		_fail("正式过房样本未在启动前隔离")
		return
	_tower.set_physics_process(false)
	_tower.player.set_physics_process(false)
	var rooms := _tower.get("_room_by_id") as Dictionary
	var target: DungeonRoom3D
	for value in rooms.values():
		var candidate := value as DungeonRoom3D
		if candidate.room_id != "start" and candidate.authored_layout_peaceful and candidate.chest_placements.is_empty():
			target = candidate
			break
	if not _check(target != null, "有可用于真实 Area 回调的和平房"):
		return
	target.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await _settle(2)
	var events: Array[Dictionary] = []
	_tower.room_entered.connect(func(room): events.append({"room": room.room_id, "node": room.get_instance_id(), "frame": Engine.get_process_frames()}))
	var probe := EntrySnapshotProbe.new()
	probe.tower = _tower
	add_child(probe)
	BaseManager.register_runtime_checkpoint_provider(probe)
	_tower.test_mode = false
	_tower.set("_runtime_persistence_active", true)
	var bodies: Array[int] = []
	var notices: Array[int] = []
	target.player_entered.connect(func(_room): notices.append(Engine.get_process_frames()))
	var area := target.get_node("RoomTrigger") as Area3D
	var area_callback := func(body):
		if body == _tower.player:
			bodies.append(Engine.get_process_frames())
			if "--entry-natural" in OS.get_cmdline_user_args():
				_tower.call("_refresh_physical_location_authority")
			else:
				_tower.force_enter_room_for_test(target.room_id)
	area.body_entered.connect(area_callback)
	_tower.player.global_position = target.global_position + Vector3(0.0, 0.05, 0.0)
	await _settle(5)
	print("ENTRY_REAL_TRACE bodies=%s notices=%s events=%s captures=%s test_mode=%s" % [bodies, notices, events, probe.captures, _tower.test_mode])
	var baseline := "--entry-baseline" in OS.get_cmdline_user_args()
	var expected := 2 if baseline else 1
	_check(bodies.size() == 1 and notices.size() == 1, "真实 Area 进入与延迟通知各一次")
	_check(events.size() == expected and probe.captures.size() == expected, "双入口事件/快照次数符合预期 %d" % expected)
	if events.size() == 2:
		_check(events[0].frame == events[1].frame, "基线确为同 process frame 两次完整通知，不是继承叠计")
	area.body_entered.disconnect(area_callback)
	if not baseline:
		await _verify_entry_boundaries(target, events, probe)
	BaseManager.unregister_runtime_checkpoint_provider(probe, false)
	BaseManager.call("_finish_room_writes", true)
	_tower.test_mode = true
	_tower.set("_runtime_persistence_active", false)
	probe.queue_free()


func _verify_entry_boundaries(target: DungeonRoom3D, events: Array[Dictionary], probe: EntrySnapshotProbe) -> void:
	# 真实 Area 样本已单独取证；以下受控显式调用不混入流送重新启用 Area 的通知。
	for value in (_tower.get("_room_by_id") as Dictionary).values():
		var room := value as DungeonRoom3D
		room.player_entered.disconnect(_tower._on_room_entered)
	await _settle(2)
	events.clear()
	probe.captures.clear()
	var start := (_tower.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	# 真实楼梯锁判据：拒绝不能认领，解锁后同帧重试必须成功。
	var connector := Node3D.new()
	connector.set_meta("from_room_id", "start")
	connector.set_meta("to_room_id", target.room_id)
	_tower.add_child(connector)
	var edge := "entry_guard_probe"
	(_tower.get("_corridor_by_edge") as Dictionary)[edge] = connector
	(_tower.get("_open_edges") as Dictionary)[edge] = true
	(_tower.get("_vertical_arrival_open") as Dictionary)[edge] = false
	_tower.set("_current_room_id", "start")
	_tower.call("_on_room_entered", target)
	_check(events.is_empty() and probe.captures.is_empty(), "锁楼梯拒绝没有事件或检查点")
	(_tower.get("_vertical_arrival_open") as Dictionary)[edge] = true
	_tower.call("_on_room_entered", target)
	_tower.call("_on_room_entered", target)
	(_tower.get("_corridor_by_edge") as Dictionary).erase(edge)
	(_tower.get("_open_edges") as Dictionary).erase(edge)
	(_tower.get("_vertical_arrival_open") as Dictionary).erase(edge)
	connector.queue_free()
	_check(events.size() == 1 and probe.captures.size() == 1, "同帧同对象只发一次事件和检查点")
	_tower.call("_on_room_entered", start)
	_tower.call("_on_room_entered", target)
	_check(events.size() == 3 and probe.captures.size() == 3, "同帧 A→B→A 三次合法入房")
	var replacement := DungeonRoom3D.new()
	replacement.room_id = target.room_id
	replacement.room_type = target.room_type
	replacement.size_class = target.size_class
	replacement.authored_layout_peaceful = true
	# 不建第二套几何；基类入口仍必须认同 ID 的新对象。
	_tower.get_node("GeneratedRooms").add_child(replacement)
	_tower.call("_on_room_entered", replacement)
	_check(events.size() == 4 and probe.captures.size() == 4, "同 ID 新 room node 不被吞")
	_tower.call("_on_room_entered", target)
	var previous_frame := Engine.get_process_frames()
	while Engine.get_process_frames() == previous_frame:
		await get_tree().process_frame
	var before := events.size()
	_tower.call("_on_room_entered", target)
	_check(events.size() == before + 1, "下一帧同房显式重试仍进入完整修复链")
	replacement.queue_free()
	await _verify_reward_repair()


func _verify_reward_repair() -> void:
	var plans := _tower.get("_clear_drop_plans") as Dictionary
	var rooms := _tower.get("_room_by_id") as Dictionary
	var room: DungeonRoom3D
	for value in rooms.values():
		var candidate := value as DungeonRoom3D
		var plan := plans.get(candidate.room_id, {}) as Dictionary
		if not candidate.authored_layout_peaceful and candidate.room_type != "BOSS" and candidate.chest_placements.is_empty() and str(plan.get("kind", "")) == "chest":
			room = candidate
			break
	if not _check(room != null, "有正式清房宝箱计划用于同房修复"):
		return
	room.cleared = true
	(_tower.get("_spawned_rooms") as Dictionary)[room.room_id] = true
	var plan := (plans[room.room_id] as Dictionary).duplicate(true)
	plans.erase(room.room_id)
	_tower.call("_on_room_entered", room)
	var count := room.get_treasure_chests().size()
	plans[room.room_id] = plan
	_tower.call("_on_room_entered", room)
	_check(room.get_treasure_chests().size() == count, "同帧重复通知不二次交付奖励")
	var frame := Engine.get_process_frames()
	while Engine.get_process_frames() == frame:
		await get_tree().process_frame
	_tower.call("_on_room_entered", room)
	_check(room.get_treasure_chests().size() == count + 1, "下一帧显式同房重试补齐缺失清房箱")
	var delivery := (_tower.get("_clear_drop_delivery") as Dictionary).duplicate(true)
	_tower.call("_on_room_entered", room)
	await _settle(2)
	_tower.call("_on_room_entered", room)
	_check(room.get_treasure_chests().size() == count + 1 and delivery == _tower.get("_clear_drop_delivery"), "同帧及跨帧修复不重复掉箱/掉落账")


func _settle(frames := 3) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
		await get_tree().physics_frame


func _check(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("EXP03_CLEAR_DROP_FAIL " + message)
	return ok


func _fail(message: String) -> void:
	_checks += 1
	_failures += 1
	printerr("EXP03_CLEAR_DROP_FAIL " + message)
