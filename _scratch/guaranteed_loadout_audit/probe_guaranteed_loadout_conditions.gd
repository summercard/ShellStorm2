extends Node
## 审计：保底武器与保底备弹到底在什么条件下出现。
##
## 业主口径（2026-09-26）：
##   ① 保底武器 + 保底弹药只属于「死亡」与「主动退出战局（撤离失败）」；
##   ② 撤离成功（含信号塔撤离）必须完整带回所有东西，不得出现保底物品。
##
## 本探针在真实路径（test_mode=false）下取三个事实：
##   A. 场景装配（= 每次加载塔楼场景）时玩家身上有什么 —— 说明保底的**实际发放条件**；
##   B. 人为装上"自己的枪 + 背包物品"之后的状态（对照组）；
##   C. 塔楼 98F 首门反向撤退（主动弃局，场景内）之后玩家身上有什么 —— 说明弃局路径给不给保底。
## 远征「退出战局」与塔楼 98F 反向撤退共用同一份清空实现（`_discard_run_carry_for_retreat`），
## 差异只在落点：前者 `change_scene_to_file` 重载塔楼场景，后者留在场景内。

const TEST_PATH := "user://guaranteed_loadout_audit.json"
const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const AMMO_ID := "item_ammo_pack"
const POTION_ID := "item_health_potion"
const AUDIT_WEAPON_ID := "weapon_rifle"

var _probe_completed := false


func _ready() -> void:
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true
	BaseManager.clear_active_run_checkpoint("audit_reset")

	await _run()

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	_probe_completed = true
	call_deferred("_report")


func _run() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	add_child(tower)
	for _frame in 8:
		await get_tree().process_frame

	var backpack: InventoryModule = tower.get_inventory_module()
	var slot0: Dictionary = tower.player.get_equipped_weapon_item_for_slot(0)
	print(
		"[A 场景装配即发] 保底发数常量=%d | slot0=%s | 背包弹药=%d | 背包药水=%d" % [
			tower.get_guaranteed_loadout_ammo_rounds(),
			str(slot0.get("id", "<空>")),
			backpack.get_item_count(AMMO_ID),
			backpack.get_item_count(POTION_ID),
		]
	)

	var weapon: Dictionary = BaseShopService.ensure_item_instance(
		(ItemRegistry.get_instance().get_item(AUDIT_WEAPON_ID) as Dictionary).duplicate(true)
	)
	var potion: Dictionary = BaseShopService.ensure_item_instance(
		(ItemRegistry.get_instance().get_item(POTION_ID) as Dictionary).duplicate(true)
	)
	tower.player.equip_weapon_item_to_slot(weapon, 0)
	backpack.add_item(potion, 3)
	await get_tree().process_frame
	var before_slot0: Dictionary = tower.player.get_equipped_weapon_item_for_slot(0)
	print(
		"[B 弃局前] slot0=%s | 背包弹药=%d | 背包药水=%d | 占用=%d" % [
			str(before_slot0.get("id", "<空>")),
			backpack.get_item_count(AMMO_ID),
			backpack.get_item_count(POTION_ID),
			backpack.get_used_slots(),
		]
	)

	tower.confirm_initial_loop_retreat_for_test()
	for _frame in 4:
		await get_tree().process_frame
	var after_slot0: Dictionary = tower.player.get_equipped_weapon_item_for_slot(0)
	print(
		"[C 弃局后] slot0=%s | 背包弹药=%d | 背包药水=%d | 占用=%d" % [
			str(after_slot0.get("id", "<空>")),
			backpack.get_item_count(AMMO_ID),
			backpack.get_item_count(POTION_ID),
			backpack.get_used_slots(),
		]
	)

	tower.queue_free()
	await get_tree().process_frame


func _report() -> void:
	if not _probe_completed:
		print("GUARANTEED_LOADOUT_AUDIT_INTERRUPTED")
		get_tree().quit(1)
		return
	print("GUARANTEED_LOADOUT_AUDIT_DONE")
	get_tree().quit(0)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
