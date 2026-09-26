extends Node
## 基地 → 远征出发的携带物与状态交接验收。
##
## 背景（2026-09-26 实测 bug）：基地落盘产物是**塔楼身份**的快照
## （`scope=base` + 空 `runtime_map_id`），而远征场景是 `expedition_01`。
## 三条既有恢复通道的判据全都要求地图 ID 相同 ⇒ 这一跳被整条丢弃：
## 玩家带着 99F 基地的背包与主副枪出发，进远征却只剩白送武器 + 保底备弹。
## 修法见 `Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY`。
##
## 本场景三段断言：
##   1. 带出发标记的基地快照 ⇒ 背包 / 主副枪 / 装备背包 / 快捷栏 / 保险格 /
##      HP / 手电电量 / 魂 / 房间钥匙全部装回；
##   2. 同一次入场里**远征出生点契约不被改写**（仍是安全房中心朝前门方向偏 4m，
##      不是房间中心）—— 出发交接刻意不恢复坐标；
##   3. 反向对照：去掉标记 ⇒ 一律不得装回（证明标记是唯一开关，不是碰巧被别的分支捞到）。
## `_probe_completed` 是防假绿哨兵：中途脚本错误会静默中断并留下空失败表。

const TEST_PATH := "user://expedition_departure_carry_verify.json"
const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"

const CARRY_WEAPON_ID := "weapon_rifle"
const CARRY_POTION_ID := "item_health_potion"
const CARRY_POTION_COUNT := 3
const CARRY_INSURED_COUNT := 2
const CARRY_QUICK_ITEM_ID := "item_battery_s"
const CARRY_BACKPACK_ID := "equipment_backpack_2"
const CARRY_HP := 42
const CARRY_FLASHLIGHT_CHARGE := 0.37
const CARRY_CURRENCY := 777
const CARRY_KEYS := 4
## 远征出生点：安全房中心朝前门方向偏 4m（`_expedition_entry_spawn_offset()`）。
const ENTRY_SPAWN_OFFSET_M := 4.0

var _probe_completed := false


func _ready() -> void:
	var failures: Array[String] = []
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true

	await _verify_marker_survives_scene_unload(failures)
	await _verify_marked_departure(failures)
	await _verify_unmarked_control(failures)
	await _verify_tower_still_takes_base_branch(failures)

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	_probe_completed = true
	call_deferred("_report_and_quit", failures.duplicate())


## 真机链路段：`RogueMapSelectMenu._enter_level()` 的序列必须让出发标记**活过塔楼场景卸载**。
##
## ⚠️ 这是 2026-09-26 真机报障暴露的验收盲区：只「构造快照 → 加载目的地图」跳过了
## "卸载塔楼"这一步，而 `Dungeon3D._exit_tree()` 调的是
## `unregister_runtime_checkpoint_provider(self, true)` —— `flush_before_unregister=true`
## 会再抓一次当前状态写盘，用一条**不带标记**的快照整体覆盖刚打的标记
## ⇒ 目的地图仍认不出它，玩家照样回到保底装备。修法是落盘后、写标记前先摘提供者，
## 本段就是盯着这一步。
func _verify_marker_survives_scene_unload(failures: Array[String]) -> void:
	_reset_base_data()
	var tower = await _spawn_tower()
	if tower == null:
		failures.append("塔楼场景装配失败，真机链路段无法判定")
		return
	var backpack: InventoryModule = tower.get_inventory_module()
	if backpack == null:
		failures.append("塔楼场景没有创建主背包模块")
		tower.queue_free()
		return
	var weapon: Dictionary = BaseShopService.ensure_item_instance(_item(CARRY_WEAPON_ID))
	var potion: Dictionary = BaseShopService.ensure_item_instance(_item(CARRY_POTION_ID))
	tower.player.equip_weapon_item_to_slot(weapon, 0)
	backpack.add_item(potion, CARRY_POTION_COUNT)
	await get_tree().process_frame

	# 复刻 `_enter_level()`：落盘 → 摘运行时提供者 → 打出发标记。
	if not BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure"):
		failures.append("真机链路段无法落盘基地状态")
		tower.queue_free()
		return
	BaseManager.unregister_runtime_checkpoint_provider(tower, false)
	var departure := BaseManager.get_active_run_checkpoint()
	departure[Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY] = true
	if not BaseManager.set_active_run_checkpoint(
		departure, "mission_operations_departure_carry"
	):
		failures.append("真机链路段无法写入出发标记")
		tower.queue_free()
		return

	# 卸载塔楼场景 = `change_scene_to_file()` 的那一步。
	tower.queue_free()
	for _frame in 4:
		await get_tree().process_frame
	var after_unload := BaseManager.get_active_run_checkpoint()
	if not bool(after_unload.get(Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY, false)):
		failures.append(
			"塔楼场景卸载后出发标记被抹掉（_exit_tree 的 flush_before_unregister 覆盖），真机仍会回到保底装备"
		)

	var expedition = await _spawn_expedition()
	if expedition == null:
		failures.append("远征场景装配失败，真机链路段无法判定")
		return
	var ex_backpack: InventoryModule = expedition.get_inventory_module()
	if ex_backpack == null or ex_backpack.get_item_count(CARRY_POTION_ID) != CARRY_POTION_COUNT:
		failures.append("真机链路：远征入场没有拿到基地整备的背包物品")
	if str(expedition.player.get_equipped_weapon_item_for_slot(0).get("id", "")) != CARRY_WEAPON_ID:
		failures.append("真机链路：远征入场没有拿到基地整备的主武器")

	expedition.queue_free()
	await get_tree().process_frame
	print("DEPARTURE_CARRY_STAGE_OK marker_survives_unload")


## 正向：出发标记在 ⇒ 所有权与状态全部装回，且出生点不被改写。
func _verify_marked_departure(failures: Array[String]) -> void:
	_reset_base_data()
	var fixture := _build_fixture()
	var marked := (fixture["snapshot"] as Dictionary).duplicate(true)
	marked[Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY] = true
	if not BaseManager.set_active_run_checkpoint(marked, "probe_departure_marked"):
		failures.append("探针无法写入带出发标记的基地快照")
		return

	var tower = await _spawn_expedition()
	if tower == null:
		failures.append("远征场景装配失败，正向段无法判定")
		return

	var backpack: InventoryModule = tower.get_inventory_module()
	if backpack == null:
		failures.append("远征入场没有创建主背包模块")
		tower.queue_free()
		return
	var potion_count: int = backpack.get_item_count(CARRY_POTION_ID)
	if potion_count != CARRY_POTION_COUNT:
		failures.append(
			"出发携带的背包物品没有装回：%s 为 %d，期望 %d"
			% [CARRY_POTION_ID, potion_count, CARRY_POTION_COUNT]
		)
	# 出发交接是整格覆盖，不是叠加：保底备弹必须被快照内容顶掉。
	if backpack.get_item_count("item_ammo_pack") != 0:
		failures.append("出发交接叠在了保底备弹上；背包应被快照整格覆盖")

	var slot0: Dictionary = tower.player.get_equipped_weapon_item_for_slot(0)
	if str(slot0.get("id", "")) != CARRY_WEAPON_ID:
		failures.append("主武器槽没有装回基地那把枪：%s" % str(slot0.get("id", "")))
	elif str(slot0.get("weapon_instance_id", "")) != str(fixture["weapon_instance_id"]):
		failures.append("主武器的枪械实例 ID 与基地快照不一致，等于换了另一把枪")
	if not tower.player.get_equipped_weapon_item_for_slot(1).is_empty():
		failures.append("副武器槽应为空，却装上了东西")
	if tower.player.get_active_weapon_slot() != 0:
		failures.append("出发生效的武器槽不是快照里的 0 号槽")

	if tower.player.current_hp != CARRY_HP:
		failures.append("玩家 HP 没带过来：%d，期望 %d" % [tower.player.current_hp, CARRY_HP])

	var flashlight: Node = tower.player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null:
		failures.append("找不到手电模块，无法判定电量交接")
	elif absf(float(flashlight.get_charge_ratio()) - CARRY_FLASHLIGHT_CHARGE) > 0.01:
		failures.append(
			"手电电量没带过来：%.3f，期望 %.3f"
			% [float(flashlight.get_charge_ratio()), CARRY_FLASHLIGHT_CHARGE]
		)

	if str(tower.player.get_equipped_backpack_item().get("id", "")) != CARRY_BACKPACK_ID:
		failures.append("装备背包没带过来")

	var insurance: InsuranceModule = tower.get_insurance_module()
	var insurance_slots: Array = insurance.get_slots_snapshot() if insurance != null else []
	var insured_slot: Dictionary = insurance_slots[0] if not insurance_slots.is_empty() else {}
	if insured_slot.is_empty():
		failures.append("保险格第 0 格没有装回")
	elif int(insured_slot.get("count", 0)) != CARRY_INSURED_COUNT:
		failures.append("保险格物品数量不对：%d" % int(insured_slot.get("count", 0)))

	var quick := tower._quick_inventory as InventoryModule
	var quick_slot: Dictionary = quick.get_slot(0) if quick != null else {}
	if quick_slot.is_empty():
		failures.append("快捷栏第 0 格没有装回")
	elif str((quick_slot.get("item", {}) as Dictionary).get("id", "")) != CARRY_QUICK_ITEM_ID:
		failures.append("快捷栏物品不是快照里那件")

	if GameManager.currency != CARRY_CURRENCY:
		failures.append("魂没有带过来：%d，期望 %d" % [GameManager.currency, CARRY_CURRENCY])
	if int(tower._room_key_count) != CARRY_KEYS:
		failures.append("房间钥匙数没有带过来：%d，期望 %d" % [int(tower._room_key_count), CARRY_KEYS])

	# 出生点契约：出发交接不得恢复基地坐标，否则远征刻意的 4m 偏移会被
	# `_resolve_runtime_restore_room()` 的基地房 id 兜底改写成安全房中心。
	var entry_room := tower._room_by_id.get("start") as DungeonRoom3D
	if entry_room == null:
		failures.append("远征缺少入口安全房，无法判定出生点契约")
	else:
		var offset: Vector3 = tower.player.global_position - entry_room.global_position
		var horizontal := Vector2(offset.x, offset.z).length()
		if absf(horizontal - ENTRY_SPAWN_OFFSET_M) > 0.5:
			failures.append(
				"远征出生点被出发交接改写：距安全房中心 %.2f m，期望 %.1f m"
				% [horizontal, ENTRY_SPAWN_OFFSET_M]
			)

	tower.queue_free()
	await get_tree().process_frame
	print("DEPARTURE_CARRY_STAGE_OK marked_expedition")


## 反向对照：同一份快照去掉出发标记 ⇒ 一条也不许装回。
func _verify_unmarked_control(failures: Array[String]) -> void:
	_reset_base_data()
	var fixture := _build_fixture()
	var unmarked := (fixture["snapshot"] as Dictionary).duplicate(true)
	unmarked.erase(Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY)
	if not BaseManager.set_active_run_checkpoint(unmarked, "probe_departure_unmarked"):
		failures.append("探针无法写入去掉标记的基地快照")
		return

	var tower = await _spawn_expedition()
	if tower == null:
		failures.append("远征场景装配失败，反向段无法判定")
		return

	var backpack: InventoryModule = tower.get_inventory_module()
	if backpack != null and backpack.get_item_count(CARRY_POTION_ID) != 0:
		failures.append("去掉出发标记后仍然装回了背包物品，标记不是唯一开关")
	var slot0: Dictionary = tower.player.get_equipped_weapon_item_for_slot(0)
	if str(slot0.get("weapon_instance_id", "")) == str(fixture["weapon_instance_id"]):
		failures.append("去掉出发标记后仍然装回了基地那把枪，标记不是唯一开关")

	tower.queue_free()
	await get_tree().process_frame
	print("DEPARTURE_CARRY_STAGE_OK unmarked_control")


## 回归段：同一份**带出发标记**的基地快照在塔楼场景里仍必须走 base 分支。
##
## 这是"分支顺序"契约的哨兵：departure 分支一旦排到 base 分支前面，塔楼自己的
## 基地重登就会丢掉世界恢复（98F 已提交楼层、房间地面物）—— 而 base 分支必须
## 连世界带所有权一起恢复。判据用「base 分支的快照槽非空」直接命中分支本身，
## 而不是间接看背包（后者在两条分支下都会满）。
func _verify_tower_still_takes_base_branch(failures: Array[String]) -> void:
	_reset_base_data()
	var fixture := _build_fixture()
	var marked := (fixture["snapshot"] as Dictionary).duplicate(true)
	marked[Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY] = true
	if not BaseManager.set_active_run_checkpoint(marked, "probe_tower_marked"):
		failures.append("探针无法写入塔楼段快照")
		return

	var tower = await _spawn_tower()
	if tower == null:
		failures.append("塔楼场景装配失败，回归段无法判定")
		return

	if (tower._runtime_base_restore_snapshot as Dictionary).is_empty():
		failures.append(
			"带出发标记的基地快照在塔楼侧没有进 base 分支（世界恢复会丢）；"
			+ "departure 分支必须排在 base 分支之后"
		)
	if not (tower._runtime_departure_carry_snapshot as Dictionary).is_empty():
		failures.append("塔楼场景误用了出发交接通道")
	var backpack: InventoryModule = tower.get_inventory_module()
	if backpack == null or backpack.get_item_count(CARRY_POTION_ID) != CARRY_POTION_COUNT:
		failures.append("塔楼基地重登没有装回携带物")
	if str(tower._current_room_id) != "facility":
		failures.append(
			"塔楼基地重登没有落回 99F 基地：当前房间 %s" % str(tower._current_room_id)
		)

	tower.queue_free()
	await get_tree().process_frame
	print("DEPARTURE_CARRY_STAGE_OK tower_base_branch")


func _spawn_tower():
	GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_COLD_START,
		GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	var scene := load(TOWER_SCENE) as PackedScene
	if scene == null:
		return null
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		return null
	add_child(tower)
	for _frame in 8:
		await get_tree().process_frame
	return tower


func _spawn_expedition():
	GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
		GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		return null
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		return null
	add_child(tower)
	for _frame in 8:
		await get_tree().process_frame
	return tower


## 每段开始前清掉上一段写的检查点。刻意**不重建 `BaseData`** —— 重建会把内存
## revision 归零，而磁盘 revision 只单调递增，下一次保存会被 `save_base()` 判成
## 陈旧写入并打 ERROR 日志（套件会把意外引擎错误判红）。
func _reset_base_data() -> void:
	BaseManager.clear_active_run_checkpoint("probe_reset")


func _item(item_id: String) -> Dictionary:
	return (ItemRegistry.get_instance().get_item(item_id) as Dictionary).duplicate(true)


## 一份"99F 基地落盘产物"的等价快照：身份是塔楼（scope=base / 空 map id），
## 携带物与状态按设计输入填满。刻意**不带**出发标记，由各段自己决定是否打上。
func _build_fixture() -> Dictionary:
	var potion := BaseShopService.ensure_item_instance(_item(CARRY_POTION_ID))
	var insured := BaseShopService.ensure_item_instance(_item(CARRY_POTION_ID))
	var quick := BaseShopService.ensure_item_instance(_item(CARRY_QUICK_ITEM_ID))
	var backpack := BaseShopService.ensure_item_instance(_item(CARRY_BACKPACK_ID))
	var weapon := BaseShopService.ensure_item_instance(_item(CARRY_WEAPON_ID))

	var inventory_slots: Array[Dictionary] = []
	inventory_slots.append({"item": potion, "count": CARRY_POTION_COUNT})
	for _index in range(11):
		inventory_slots.append({})
	var insurance_slots: Array[Dictionary] = [
		{"item": insured, "count": CARRY_INSURED_COUNT}, {},
	]
	var quick_slots: Array[Dictionary] = [
		{"item": quick, "count": 1}, {},
	]
	var snapshot := {
		"valid": true,
		"schema": "runtime_player_state_v2",
		"checkpoint_id": "checkpoint:probe:departure",
		"layout_id": "runtime_player_state_v2",
		"scope": "base",
		"run_seed": 20260926,
		"run_id": "run:probe:departure",
		"current_room_id": "facility",
		"current_floor_index": 1,
		"player_position": [3.0, 0.05, -7.0],
		"player_rotation_y": 0.0,
		"player_hp": CARRY_HP,
		"inventory_capacity": 12,
		"inventory_slots": inventory_slots,
		"insurance_capacity": 2,
		"insurance_slots": insurance_slots,
		"equipped_weapon_items": [weapon, {}],
		"active_weapon_slot": 0,
		"equipped_backpack_item": backpack,
		"flashlight_module_id": "basic",
		"flashlight_charge_ratio": CARRY_FLASHLIGHT_CHARGE,
		"quick_item_slots": quick_slots,
		"quick_item_ids": ["", ""],
		"room_key_count": CARRY_KEYS,
		"run_value": 0,
		"kills": 0,
		"run_currency": CARRY_CURRENCY,
		"edge_states": {},
		"runtime_map_id": "",
		"world_state": {
			"schema": "tower_world_state_v1",
			"committed_floor_indices": [],
			"floor_layout_ids": {},
			"room_progress": {},
		},
	}
	return {
		"snapshot": RunPersistenceService.finalize_runtime_snapshot(snapshot),
		"weapon_instance_id": str(weapon.get("weapon_instance_id", "")),
		"item_instance_id": str(weapon.get("item_instance_id", "")),
	}


func _report_and_quit(failures: Array[String]) -> void:
	var output := failures.duplicate()
	if not _probe_completed:
		output.append("验收流程中途中断（脚本错误或提前返回），结果不可信")
	if output.is_empty():
		print(
			"EXPEDITION_DEPARTURE_CARRY_OK: 真机链路（含塔楼场景卸载后标记仍存活）把 99F 基地的"
			+ "背包/主副枪/装备背包/快捷栏/保险格/HP/手电/魂/钥匙全部带进远征；出生点契约未被改写；"
			+ "去掉标记后一条也不装回；塔楼侧仍走 base 分支"
		)
		get_tree().quit(0)
		return
	for failure in output:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
