extends Node
## 复现：99F 基地「远征情报室」传送进远征关卡时，玩家携带物是否被交接。
##
## 真实事件链（RogueMapSelectMenu._enter_level）：
##   1. BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure")
##      ⇒ 在塔楼场景里写一条 scope=base / runtime_map_id="" 的快照（含背包与主副枪）
##   2. GameEntryFlow 登记入口意图，切 ExpeditionLoadingScreen → ExpeditionLevel01_3D
## 本探针直接构造第 1 步的产物，再真实加载远征场景，观察第 2 步的恢复结果。
##
## Case A：base 快照原样（runtime_map_id=""）—— 这就是真机业主走的路。
## Case B：把快照 runtime_map_id 伪造成 "expedition_01"（对照组），
##         用来判定「是地图 ID 匹配把携带物挡在门外」，还是携带物本身装不回去。

const TEST_PATH := "user://probe_departure_carry.json"
const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const LOADOUT_WEAPON_ID := "weapon_rifle"
const LOADOUT_ITEM_ID := "item_health_potion"
const LOADOUT_ITEM_COUNT := 3

var _probe_completed := false


func _ready() -> void:
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH

	await _run_case("", "A_real_base_snapshot")
	await _run_case("expedition_01", "B_forced_map_match")

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	_probe_completed = true
	call_deferred("_report")


func _run_case(map_id: String, label: String) -> void:
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true
	BaseManager.clear_active_run_checkpoint("probe_reset")

	var weapon: Dictionary = BaseShopService.ensure_item_instance(
		(ItemRegistry.get_instance().get_item(LOADOUT_WEAPON_ID) as Dictionary).duplicate(true)
	)
	var potion: Dictionary = BaseShopService.ensure_item_instance(
		(ItemRegistry.get_instance().get_item(LOADOUT_ITEM_ID) as Dictionary).duplicate(true)
	)
	var expected_weapon_id := str(weapon.get("weapon_instance_id", ""))
	var expected_instance_id := str(weapon.get("item_instance_id", ""))

	var snapshot := _build_base_snapshot(map_id, potion, weapon)
	if not BaseManager.set_active_run_checkpoint(snapshot, "probe_departure"):
		print("[%s] SETUP_FAILED: 无法写入基地快照" % label)
		return
	var written := BaseManager.get_active_run_checkpoint()
	print(
		"[%s] SNAPSHOT scope=%s map=%s weapon_id=%s potion_count=%d" % [
			label,
			str(written.get("scope", "")),
			str(written.get("runtime_map_id", "")),
			expected_weapon_id,
			LOADOUT_ITEM_COUNT,
		]
	)

	GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
		GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	add_child(tower)
	for _frame in 8:
		await get_tree().process_frame

	var backpack := tower.get_inventory_module()
	var potion_count := -1
	var ammo_count := -1
	if backpack != null:
		potion_count = backpack.get_item_count(LOADOUT_ITEM_ID)
		ammo_count = backpack.get_item_count("item_ammo_pack")
	var slot0 := tower.player.get_equipped_weapon_item_for_slot(0)
	print(
		"[%s] RESULT map_id=%s carried_potion=%d guaranteed_ammo=%d slot0_item=%s slot0_instance=%s expected_instance=%s slot0_weapon_id=%s expected_weapon_id=%s" % [
			label,
			tower.get_runtime_map_id(),
			potion_count,
			ammo_count,
			str(slot0.get("id", "")),
			str(slot0.get("item_instance_id", "")),
			expected_instance_id,
			str(slot0.get("weapon_instance_id", "")),
			expected_weapon_id,
		]
	)

	tower.queue_free()
	await get_tree().process_frame


func _build_base_snapshot(map_id: String, potion: Dictionary, weapon: Dictionary) -> Dictionary:
	var slots: Array[Dictionary] = []
	slots.append({"item": potion.duplicate(true), "count": LOADOUT_ITEM_COUNT})
	for _index in range(11):
		slots.append({})
	var insurance: Array[Dictionary] = [{}, {}]
	var snapshot := {
		"valid": true,
		"schema": "runtime_player_state_v2",
		"checkpoint_id": "checkpoint:probe:base",
		"layout_id": "runtime_player_state_v2",
		"scope": "base",
		"run_seed": 20260926,
		"run_id": "run:probe:base",
		"current_room_id": "facility",
		"current_floor_index": 1,
		"player_position": [],
		"player_rotation_y": 0.0,
		"player_hp": 100,
		"inventory_capacity": 12,
		"inventory_slots": slots,
		"insurance_capacity": 2,
		"insurance_slots": insurance,
		"equipped_weapon_items": [weapon.duplicate(true), {}],
		"active_weapon_slot": 0,
		"equipped_backpack_item": {},
		"flashlight_module_id": "basic",
		"flashlight_charge_ratio": 1.0,
		"quick_item_slots": [{}, {}],
		"quick_item_ids": ["", ""],
		"room_key_count": 1,
		"run_value": 0,
		"kills": 0,
		"run_currency": 0,
		"edge_states": {},
		"runtime_map_id": map_id,
		"world_state": {
			"schema": "tower_world_state_v1",
			"committed_floor_indices": [],
			"floor_layout_ids": {},
			"room_progress": {},
		},
	}
	return RunPersistenceService.finalize_runtime_snapshot(snapshot)


func _report() -> void:
	if not _probe_completed:
		print("PROBE_DEPARTURE_CARRY_INTERRUPTED")
		get_tree().quit(1)
		return
	print("PROBE_DEPARTURE_CARRY_DONE")
	get_tree().quit(0)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
