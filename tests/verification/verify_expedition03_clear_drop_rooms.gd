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
