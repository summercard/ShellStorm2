extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://workshop_transaction_probe.json"


func _ready() -> void:
	_cleanup()
	var failures: Array[String] = []
	var manager := _new_manager()
	manager.data.extraction_points = 100

	var insufficient: Dictionary = manager.upgrade_blueprint("gunbody", 0, "workshop:insufficient")
	if not bool(insufficient.get("success", false)):
		failures.append("Tier0→1 在 100 魂时不应余额不足：%s" % str(insufficient))
	if manager.data.blueprint_gunbody_tier != 1 or manager.data.extraction_points != 20:
		failures.append("升级没有原子扣除 80 魂并把枪身提升到 Tier1")

	var revision: int = int(manager.data.save_revision)
	var duplicate: Dictionary = manager.upgrade_blueprint("gunbody", 0, "workshop:insufficient")
	if not bool(duplicate.get("success", false)) or not bool(duplicate.get("duplicate", false)):
		failures.append("相同工坊事务没有命中持久幂等日志")
	if manager.data.save_revision != revision or manager.data.blueprint_gunbody_tier != 1:
		failures.append("重复工坊事务再次写盘或升级")

	var stale: Dictionary = manager.upgrade_blueprint("gunbody", 0, "workshop:stale")
	if bool(stale.get("success", false)) or str(stale.get("code", "")) != "stale_tier":
		failures.append("旧 Tier 并发请求没有稳定返回 stale_tier")

	var poor: Dictionary = manager.upgrade_blueprint("gunbody", 1, "workshop:poor")
	if bool(poor.get("success", false)) or str(poor.get("code", "")) != "insufficient_currency":
		failures.append("余额不足没有稳定返回 insufficient_currency")
	if manager.data.blueprint_gunbody_tier != 1 or manager.data.extraction_points != 20:
		failures.append("余额不足错误修改了 Tier 或余额")

	manager.data.extraction_points = 300
	manager.force_save_failure_for_test = true
	var failed: Dictionary = manager.upgrade_blueprint("gunbody", 1, "workshop:save_failure")
	if bool(failed.get("success", false)) or str(failed.get("code", "")) != "save_failed":
		failures.append("写盘失败没有稳定返回 save_failed")
	if manager.data.blueprint_gunbody_tier != 1 or manager.data.extraction_points != 300:
		failures.append("写盘失败没有同时回滚 Tier 和余额")
	if "workshop:save_failure" in manager.data.completed_transaction_ids:
		failures.append("失败事务被错误写入幂等日志")

	manager.force_save_failure_for_test = false
	var retried: Dictionary = manager.upgrade_blueprint("gunbody", 1, "workshop:save_failure")
	if not bool(retried.get("success", false)) or manager.data.blueprint_gunbody_tier != 2:
		failures.append("写盘恢复后同事务无法安全重试")
	manager.free()

	var reloaded := _new_manager()
	reloaded.load_base()
	var before_reload_retry: int = int(reloaded.data.save_revision)
	var reload_duplicate: Dictionary = reloaded.upgrade_blueprint("gunbody", 1, "workshop:save_failure")
	if not bool(reload_duplicate.get("duplicate", false)) or reloaded.data.save_revision != before_reload_retry:
		failures.append("重载后工坊事务幂等性失效")
	reloaded.free()
	_cleanup()

	if failures.is_empty():
		print("WORKSHOP_TRANSACTION_FLOW_OK: cost, atomic save, rollback, stale-tier rejection and reload idempotency pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


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
