extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://run_settlement_transaction_probe.json"


func _ready() -> void:
	_cleanup()
	var failures: Array[String] = []
	_verify_success_failure_and_idempotency(failures)
	_verify_death_failure_retry_and_reload(failures)
	_cleanup()
	if failures.is_empty():
		print("RUN_SETTLEMENT_TRANSACTION_OK: success and death settle in one atomic, retryable and reload-safe commit")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_success_failure_and_idempotency(failures: Array[String]) -> void:
	var manager := _new_manager()
	manager.data.active_run_snapshot = {"valid": true, "checkpoint_id": "run_success_probe"}
	manager.force_save_failure_for_test = true
	var failed := manager.commit_run_settlement({
		"transaction_id": "txn_run_success",
		"success": true,
		"kills": 4,
		"extraction_points": 37,
		"extraction_loot": [{"id": "item_health_potion", "count": 2}],
	}) as Dictionary
	if bool(failed.get("success", false)):
		failures.append("成功撤离在强制写盘失败时错误报告成功")
	if manager.data.total_runs != 0 or manager.data.extraction_points != 0:
		failures.append("成功撤离写盘失败后统计或魂没有回滚")
	if not manager.data.extraction_loot.is_empty() or manager.data.active_run_snapshot.is_empty():
		failures.append("成功撤离写盘失败后战利品或行动检查点没有回滚")
	if "txn_run_success" in manager.data.completed_transaction_ids:
		failures.append("失败的成功撤离事务被错误写入幂等日志")

	manager.force_save_failure_for_test = false
	var committed := manager.commit_run_settlement({
		"transaction_id": "txn_run_success",
		"success": true,
		"kills": 4,
		"extraction_points": 37,
		"extraction_loot": [{"id": "item_health_potion", "count": 2}],
	}) as Dictionary
	if not bool(committed.get("success", false)):
		failures.append("成功撤离事务无法在故障解除后重试提交")
	if manager.data.total_runs != 1 or manager.data.successful_extractions != 1:
		failures.append("成功撤离事务没有一次性更新行动统计")
	if manager.data.total_kills != 4 or manager.data.extraction_points != 37:
		failures.append("成功撤离事务没有一次性更新击杀与魂")
	if manager.data.extraction_loot.size() != 1 or not manager.data.active_run_snapshot.is_empty():
		failures.append("成功撤离事务没有一次性写入战利品并结束行动")
	var revision_after_commit: int = manager.data.save_revision
	var duplicate := manager.commit_run_settlement({
		"transaction_id": "txn_run_success", "success": true,
		"kills": 99, "extraction_points": 999,
		"extraction_loot": [{"id": "item_battery_l", "count": 5}],
	}) as Dictionary
	if not bool(duplicate.get("success", false)) or not bool(duplicate.get("duplicate", false)):
		failures.append("相同成功撤离事务没有作为幂等重试返回")
	if manager.data.save_revision != revision_after_commit or manager.data.total_runs != 1:
		failures.append("相同成功撤离事务重复写盘或重复累计统计")
	manager.free()


func _verify_death_failure_retry_and_reload(failures: Array[String]) -> void:
	var manager := _new_manager()
	manager.load_base()
	manager.data.active_run_snapshot = {"valid": true, "checkpoint_id": "run_death_probe"}
	var insured_item := ItemRegistry.get_instance().get_item("item_battery_l")
	insured_item["item_instance_id"] = "insured_battery_probe"
	var request := {
		"transaction_id": "txn_run_death",
		"success": false,
		"kills": 2,
		"insurance_saved": [{
			"item": insured_item, "count": 3, "insurance_slot": 1,
		}],
	}
	manager.force_save_failure_for_test = true
	if bool(manager.commit_run_settlement(request).get("success", false)):
		failures.append("死亡结算在强制写盘失败时错误报告成功")
	if manager.data.total_runs != 1 or not manager.data.pending_insurance_slots.is_empty():
		failures.append("死亡结算写盘失败后统计或保险中转没有回滚")
	if manager.data.active_run_snapshot.is_empty():
		failures.append("死亡结算写盘失败后提前清除了可恢复行动")

	manager.force_save_failure_for_test = false
	if not bool(manager.commit_run_settlement(request).get("success", false)):
		failures.append("死亡结算无法在故障解除后重试提交")
	if manager.data.total_runs != 2 or manager.data.successful_extractions != 1:
		failures.append("死亡结算没有只增加一次失败行动统计")
	if manager.data.pending_insurance_slots.size() != 1 or not manager.data.active_run_snapshot.is_empty():
		failures.append("死亡结算没有原子写入保险中转并结束行动")
	manager.free()

	var reloaded := _new_manager()
	reloaded.load_base()
	var revision_before_duplicate: int = reloaded.data.save_revision
	var duplicate := reloaded.commit_run_settlement(request) as Dictionary
	if not bool(duplicate.get("success", false)) or not bool(duplicate.get("duplicate", false)):
		failures.append("重载后重复死亡结算没有命中持久幂等日志")
	if reloaded.data.save_revision != revision_before_duplicate or reloaded.data.total_runs != 2:
		failures.append("重载后重复死亡结算再次修改了存档")
	if reloaded.data.pending_insurance_slots.size() != 1:
		failures.append("重载后重复死亡结算复制了保险返还物")
	reloaded.free()


func _new_manager() -> Node:
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	return manager


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
