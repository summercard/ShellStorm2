extends Node
## E03 资源扣款事务专项。磁盘操作仅使用隔离测试路径。

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://extraction_points_spend_transaction_probe.json"


func _ready() -> void:
	_cleanup()
	var failures: Array[String] = []
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	add_child(manager)
	manager.data = BaseData.new()
	manager.data.extraction_points = 500
	if not manager.save_base("spend_probe_seed"):
		failures.append("不能建立资源扣款测试档")
	var seeded_revision := manager.data.save_revision

	if not manager.spend_extraction_points(70):
		failures.append("合法扣款被拒绝")
	if manager.data.extraction_points != 430 or manager.data.save_revision != seeded_revision + 1:
		failures.append("合法扣款没有同步更新余额和修订号")
	if _read_disk_points() != 430:
		failures.append("合法扣款没有写入磁盘")

	var committed_revision := manager.data.save_revision
	manager.force_save_failure_for_test = true
	if manager.spend_extraction_points(70):
		failures.append("强制写盘失败时扣款仍报告成功")
	if manager.data.extraction_points != 430 or manager.data.save_revision != committed_revision:
		failures.append("强制写盘失败时没有恢复内存余额或修订号")
	if _read_disk_points() != 430:
		failures.append("强制写盘失败改变了已提交磁盘余额")
	manager.force_save_failure_for_test = false

	if manager.spend_extraction_points(431):
		failures.append("余额不足时仍允许扣款")
	if manager.spend_extraction_points(0) or manager.spend_extraction_points(-1):
		failures.append("零或负数被接受为扣款")
	if manager.data.extraction_points != 430 or manager.data.save_revision != committed_revision:
		failures.append("拒绝的扣款改变了余额或产生了磁盘提交")

	var stale := MANAGER_SCRIPT.new()
	stale.save_path = TEST_PATH
	add_child(stale)
	if stale.data.extraction_points != 430:
		failures.append("第二实例没有读取已提交余额")
	manager.data.extraction_points = 620
	if not manager.save_base("spend_probe_newer_writer"):
		failures.append("不能建立较新磁盘修订")
	if stale.spend_extraction_points(70):
		failures.append("旧实例在 revision 冲突时仍报告扣款成功")
	if stale.data.extraction_points != 620 or stale.data.save_revision != manager.data.save_revision:
		failures.append("旧实例拒绝保存后覆盖了重新加载的权威余额")

	manager.queue_free()
	stale.queue_free()
	_cleanup()
	await get_tree().process_frame
	if failures.is_empty():
		print("EXTRACTION_POINTS_SPEND_TRANSACTION_OK: commit, forced failure rollback, invalid input and stale revision reload pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("EXTRACTION_POINTS_SPEND_TRANSACTION_FAIL: %s" % failure)
	get_tree().quit(1)


func _read_disk_points() -> int:
	var stored: Variant = AtomicJsonStore.load_dictionary(TEST_PATH)
	if not stored is Dictionary:
		return -1
	var unpacked := ProfileSaveService.unpack(stored as Dictionary)
	if not bool(unpacked.get("success", false)):
		return -1
	return int((unpacked.get("payload", {}) as Dictionary).get("extraction_points", -1))


func _cleanup() -> void:
	for file_path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
