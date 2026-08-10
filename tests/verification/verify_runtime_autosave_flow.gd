extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://runtime_autosave_probe.json"


class RuntimeProvider extends Node:
	var inventory := InventoryModule.new(12)
	var snapshot_serial := 0

	func build_runtime_save_snapshot() -> Dictionary:
		return {
			"valid": true,
			"schema": "runtime_player_state_v1",
			"checkpoint_id": "runtime_player_state_v1",
			"layout_id": "runtime_player_state_v1",
			"snapshot_serial": snapshot_serial,
			"inventory_capacity": inventory.get_capacity(),
			"inventory_slots": inventory.get_slots_snapshot(),
		}


func _ready() -> void:
	_cleanup()
	var failures: Array[String] = []
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	add_child(manager)
	manager.data = BaseData.new()
	var provider := RuntimeProvider.new()
	add_child(provider)
	manager.register_runtime_checkpoint_provider(provider)

	provider.inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 1)
	provider.snapshot_serial = 1
	manager.queue_runtime_checkpoint("first_change", 0.06)
	provider.inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 1)
	provider.snapshot_serial = 2
	manager.queue_runtime_checkpoint("second_change", 0.06)
	await get_tree().create_timer(0.12).timeout
	if manager.data.save_revision != 1:
		failures.append("合并窗口内两次变化没有合并成一次磁盘提交")
	var stored := manager.get_active_run_checkpoint()
	if int(stored.get("snapshot_serial", 0)) != 2:
		failures.append("合并写入没有保存窗口内最后一份状态")

	provider.inventory.add_item(ItemRegistry.get_instance().get_item("item_battery_s"), 1)
	provider.snapshot_serial = 3
	if not manager.flush_runtime_checkpoint("room_transition"):
		failures.append("房门关键节点没有同步提交")
	if manager.data.save_revision != 2:
		failures.append("关键节点同步提交的 revision 不正确")

	var restored := MANAGER_SCRIPT.new()
	restored.save_path = TEST_PATH
	restored.load_base()
	var reloaded := restored.get_active_run_checkpoint()
	if int(reloaded.get("snapshot_serial", 0)) != 3:
		failures.append("模拟重启后没有恢复最后一次关键节点快照")
	var slots := reloaded.get("inventory_slots", []) as Array
	var occupied := 0
	for entry in slots:
		if entry is Dictionary and not (entry as Dictionary).is_empty():
			occupied += 1
	if occupied != 2:
		failures.append("重启快照没有保留背包的精确格位/堆叠")

	var insurance := InsuranceModule.new(2)
	insurance.insure_item_direct(ItemRegistry.get_instance().get_item("weapon_pistol"))
	var insurance_copy := InsuranceModule.new(2)
	insurance_copy.restore_slots_snapshot(insurance.get_slots_snapshot())
	if insurance_copy.get_used_slots() != 1:
		failures.append("保险格完整快照不能恢复")

	manager.unregister_runtime_checkpoint_provider(provider, false)
	manager.queue_free()
	provider.queue_free()
	restored.free()
	_cleanup()
	await get_tree().process_frame
	if failures.is_empty():
		print("RUNTIME_AUTOSAVE_OK: coalesced changes, forced room checkpoint, restart and insurance restore pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
