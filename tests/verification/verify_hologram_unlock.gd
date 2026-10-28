extends Node
const MANAGER = preload("res://src/base/BaseManager.gd")
const FIXTURE = preload("res://tests/verification/helpers/hologram_city_fixture.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	_cleanup()
	# 本用例必须自证**没有环境干扰**：P 键调试面板会把解锁写进
	# `user://expedition_debug_unlock.json`（独立于存档，供调试直通用），
	# 而 `is_expedition_level_unlocked()` 与它取或 —— 只要那台机器上留着这份文件，
	# "新存档应该锁着"就会假红。这里只清内存里的覆盖，不动磁盘文件：
	# 进程退出即结束，不影响玩家真实的调试状态。
	BaseManager._debug_unlock_overrides_loaded = true
	BaseManager._debug_unlock_overrides.clear()
	var manager = MANAGER.new()
	manager.save_path = "user://unlock_probe.json"
	manager.data = BaseData.new()
	manager._debug_unlock_overrides_loaded = true
	manager._debug_unlock_overrides.clear()
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
	# 解锁集合也要一起清：判定是「存档集合 ∪ 旧专用布尔 ∪ 调试覆盖」，
	# 只清其中一个，上一段结算真的写进去的那一份还会让 02 继续显示为已解锁。
	BaseManager.data.expedition_unlocked_levels.erase("expedition_02")
	var locked := FIXTURE.create(self)
	# 导航内容契约（显式写期望值，不用"数量相等"糊过去）：
	#   `on_unlock` 的 02 未解锁 ⇒ 不出现；`always` 的 03 ⇒ 恒定出现。
	# 加关卡时这行必须跟着改 —— 这是刻意的摩擦，避免"配置加了一条但导航没算进去"悄悄通过。
	check(locked.menu.LEVEL_IDS == ["expedition_01", "99", "expedition_03"], "locked navigation wrong: %s" % [locked.menu.LEVEL_IDS])
	# 03 从 2026-10-28 起是**真能进**的关卡（场景、设计源、生成链路都就位，
	# `unlock_policy = always`）。所以牌面应写可进，而不是"尚未开放"。
	check(locked.menu.entry_state("expedition_03") == locked.menu.ENTRY_OPEN, "03 应可进：%s" % locked.menu.entry_state("expedition_03"))
	check(locked.menu._city.entry_hints[2].text.begins_with("点击进入"), "03 牌面未写可进：%s" % locked.menu._city.entry_hints[2].text)
	locked.menu._enter_level("expedition_02")
	check(not locked.menu._departing, "locked direct entry allowed")
	locked.host.queue_free()
	await get_tree().process_frame
	BaseManager.data.expedition_02_unlocked = true
	var unlocked := FIXTURE.create(self)
	check(unlocked.menu.LEVEL_IDS == ["expedition_01", "99", "expedition_02", "expedition_03"], "unlocked navigation wrong: %s" % [unlocked.menu.LEVEL_IDS])
	unlocked.menu._progress = 1.0
	unlocked.menu._process(0.0)
	# 契约：**进不去的入口不得出发，且必须给「尚未开放」回执**。
	#
	# 这条断言换过两次对象，每次都是因为"被测的那个关卡其实已经能进了"：
	#   远征02（2026-10-12 场景建好）⇒ 远征03（2026-10-28 场景与生成链路就位）。
	# 现在四张关卡都能进，**已经没有「已登记但缺场景」的实例**，所以改用
	# **未登记的 id** 走同一条 `coming_soon` 分支 —— `entry_state()` 对
	# 「未登记」与「场景缺失」返回同一状态，契约照样被覆盖，且不会随关卡进度失效。
	var missing_id := "expedition_99_missing"
	check(unlocked.menu.entry_state(missing_id) == unlocked.menu.ENTRY_COMING_SOON, "未登记 id 未被判为未开放")
	check(unlocked.menu._entry_hint_text(missing_id) == "尚未开放", "未登记 id 牌面文案不对：%s" % unlocked.menu._entry_hint_text(missing_id))
	unlocked.menu._enter_level(missing_id)
	check(not unlocked.menu._departing and GameDesignConfig.pending_expedition_level_id.is_empty(), "unavailable entry routed to gameplay")
	check(unlocked.menu._city.status.text.contains("尚未开放"), "unavailable entry lacks feedback")
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
