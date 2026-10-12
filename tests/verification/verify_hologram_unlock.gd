extends Node
const MANAGER = preload("res://src/base/BaseManager.gd")
const FIXTURE = preload("res://tests/verification/helpers/hologram_city_fixture.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	_cleanup()
	var manager = MANAGER.new()
	manager.save_path = "user://unlock_probe.json"
	manager.data = BaseData.new()
	check(not manager.is_expedition_level_unlocked("expedition_02"), "new save unlocked")
	check(not BaseData.from_dict({"successful_extractions": 10}).expedition_02_unlocked, "legacy ambiguous progress unlocked")
	for entry in [{"id":"death", "success":false, "level":"expedition_01"}, {"id":"test99", "success":true, "level":"99"}, {"id":"tower", "success":true, "level":""}]:
		var result: Dictionary = manager.commit_run_settlement({"transaction_id":entry.id, "success":entry.success, "expedition_level_id":entry.level})
		check(result.success and not manager.is_expedition_level_unlocked("expedition_02"), "unrelated settlement unlocked")
	var request := {"transaction_id":"clear01", "success":true, "expedition_level_id":"expedition_01"}
	manager.force_save_failure_for_test = true
	check(not manager.commit_run_settlement(request).success, "save failure accepted")
	check(not manager.is_expedition_level_unlocked("expedition_02"), "failed save leaked unlock")
	manager.force_save_failure_for_test = false
	check(manager.commit_run_settlement(request).success, "retry failed")
	check(manager.is_expedition_level_unlocked("expedition_02"), "01 clear did not unlock")
	var revision: int = manager.data.save_revision
	check(manager.commit_run_settlement(request).duplicate and manager.data.save_revision == revision, "duplicate changed save")
	manager.load_base()
	check(manager.is_expedition_level_unlocked("expedition_02"), "reload lost unlock")
	BaseManager.data.expedition_02_unlocked = false
	var locked := FIXTURE.create(self)
	check(locked.menu.LEVEL_IDS == ["expedition_01", "99"], "locked navigation includes02")
	locked.menu._enter_level("expedition_02")
	check(not locked.menu._departing, "locked direct entry allowed")
	locked.host.queue_free()
	await get_tree().process_frame
	BaseManager.data.expedition_02_unlocked = true
	var unlocked := FIXTURE.create(self)
	check(unlocked.menu.LEVEL_IDS == ["expedition_01", "99", "expedition_02"], "unlocked navigation missing02")
	unlocked.menu._progress = 1.0
	unlocked.menu._process(0.0)
	unlocked.menu._enter_level("expedition_02")
	check(not unlocked.menu._departing and GameDesignConfig.pending_expedition_level_id.is_empty(), "missing scene routed to gameplay")
	check(unlocked.menu._city.status.text.contains("尚未开放") and unlocked.menu._city.entry_hints[2].text == "尚未开放", "missing scene lacks feedback")
	unlocked.host.queue_free()
	manager.free()
	_cleanup()
	await get_tree().process_frame
	for failure in failures: printerr("FAIL: " + failure)
	print("HOLOGRAM_UNLOCK_OK" if failures.is_empty() else "HOLOGRAM_UNLOCK_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = "user://unlock_probe.json" + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
