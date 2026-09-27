extends Node
## 复现：真机链路里「出发交接标记」会不会被塔楼场景卸载时的那次 flush 抹掉。
##
## `RogueMapSelectMenu._enter_level()` 的真实序列：
##   ① `flush_runtime_checkpoint("mission_operations_teleport_departure")`
##   ② 打出发标记 + `set_active_run_checkpoint(..., "mission_operations_departure_carry")`
##   ③ `change_scene_to_file(ExpeditionLoadingScreen)` ⇒ 塔楼场景 `_exit_tree()`
##      ⇒ `unregister_runtime_checkpoint_provider(self, true)`
##      ⇒ **flush_before_unregister=true ⇒ 再抓一次当前状态写盘（不带标记）**
## 本探针按 ①②③ 顺序实测：③ 之后快照里还剩不剩标记，以及远征入场拿不拿得到携带物。

const TEST_PATH := "user://probe_departure_marker.json"
const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const CARRY_POTION_ID := "item_health_potion"
const CARRY_POTION_COUNT := 3
const CARRY_WEAPON_ID := "weapon_rifle"

var _probe_completed := false


func _ready() -> void:
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true
	BaseManager.clear_active_run_checkpoint("probe_reset")

	await _run()

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	_probe_completed = true
	call_deferred("_report")


func _run() -> void:
	# ---- 阶段 1：真实塔楼场景，做一次"局外整备" ----
	var tower = await _spawn(TOWER_SCENE)
	if tower == null:
		print("[FATAL] 塔楼场景装配失败")
		return
	var weapon: Dictionary = BaseShopService.ensure_item_instance(
		(ItemRegistry.get_instance().get_item(CARRY_WEAPON_ID) as Dictionary).duplicate(true)
	)
	var potion: Dictionary = BaseShopService.ensure_item_instance(
		(ItemRegistry.get_instance().get_item(CARRY_POTION_ID) as Dictionary).duplicate(true)
	)
	tower.player.equip_weapon_item_to_slot(weapon, 0)
	var backpack: InventoryModule = tower.get_inventory_module()
	backpack.add_item(potion, CARRY_POTION_COUNT)
	await get_tree().process_frame
	print(
		"[0 整备完成] slot0=%s potion=%d" % [
			str(tower.player.get_equipped_weapon_item_for_slot(0).get("id", "<空>")),
			backpack.get_item_count(CARRY_POTION_ID),
		]
	)

	# ---- 阶段 2：复刻 `_enter_level` 的 ① + ②（含"落盘后先摘提供者"这一步）----
	if not BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure"):
		print("[FATAL] 传送前落盘失败")
		return
	# 真机里这一步是 `RogueMapSelectMenu` 对 `get_parent()`（= 打开菜单的塔楼场景根，
	# 也就是运行时检查点提供者）调用 unregister；探针里塔楼就在手边，直接用引用。
	BaseManager.unregister_runtime_checkpoint_provider(tower, false)
	var departure := BaseManager.get_active_run_checkpoint()
	departure[Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY] = true
	if not BaseManager.set_active_run_checkpoint(departure, "mission_operations_departure_carry"):
		print("[FATAL] 出发标记写入失败")
		return
	var staged := BaseManager.get_active_run_checkpoint()
	print(
		"[1 打标记后] marker=%s scope=%s map=%s potion_in_snapshot=%d" % [
			str(staged.get(Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY, false)),
			str(staged.get("scope", "")),
			str(staged.get("runtime_map_id", "")),
			_count_snapshot_item(staged, CARRY_POTION_ID),
		]
	)

	# ---- 阶段 3：释放塔楼场景 = `change_scene_to_file` 卸载当前场景 ----
	tower.queue_free()
	for _frame in 4:
		await get_tree().process_frame
	var after_unload := BaseManager.get_active_run_checkpoint()
	print(
		"[2 卸载后] marker=%s potion_in_snapshot=%d" % [
			str(after_unload.get(Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY, false)),
			_count_snapshot_item(after_unload, CARRY_POTION_ID),
		]
	)

	# ---- 阶段 4：加载远征场景，看玩家身上拿到什么 ----
	GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
		GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	var expedition = await _spawn(EXPEDITION_SCENE)
	if expedition == null:
		print("[FATAL] 远征场景装配失败")
		return
	var ex_backpack: InventoryModule = expedition.get_inventory_module()
	print(
		"[3 远征入场] potion=%d ammo=%d slot0=%s（期望 potion=%d / slot0=%s）" % [
			ex_backpack.get_item_count(CARRY_POTION_ID),
			ex_backpack.get_item_count("item_ammo_pack"),
			str(expedition.player.get_equipped_weapon_item_for_slot(0).get("id", "<空>")),
			CARRY_POTION_COUNT,
			CARRY_WEAPON_ID,
		]
	)
	expedition.queue_free()
	await get_tree().process_frame


func _spawn(scene_path: String):
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		return null
	add_child(tower)
	for _frame in 8:
		await get_tree().process_frame
	return tower


func _count_snapshot_item(snapshot: Dictionary, item_id: String) -> int:
	var slots: Variant = snapshot.get("inventory_slots", [])
	if not slots is Array:
		return -1
	for entry_value in (slots as Array):
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var item := entry.get("item", {}) as Dictionary
		if str(item.get("id", "")) == item_id:
			return int(entry.get("count", 0))
	return 0


func _report() -> void:
	if not _probe_completed:
		print("DEPARTURE_MARKER_PROBE_INTERRUPTED")
		get_tree().quit(1)
		return
	print("DEPARTURE_MARKER_PROBE_DONE")
	get_tree().quit(0)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
