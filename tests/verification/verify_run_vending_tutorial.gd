extends Node
## 隔离验收：正式 Dungeon + 真实 ServiceStation3D；本文件不登记到统一套件。

const DUNGEON := preload("res://scenes/Dungeon3D.tscn")
const TUTORIAL_ID := "nar_tutorial_run_vending_01"

var _host: Dungeon3D
var _controller: Node
var _room: DungeonRoom3D
var _merchant: ServiceStation3D
var _upgrade: ServiceStation3D
var _checks: Array[String] = []
var _failures: Array[String] = []
var _money := 0
var _capture_dir := ""
var _inventory_before: Array[Dictionary] = []
var _stock_before: Dictionary = {}
var _b_captured := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var defaults := DUNGEON.instantiate() as Dungeon3D
	_check(not defaults.enable_run_vending_tutorial_in_test, "test_mode 下贩卖机教学默认关闭")
	defaults.free()
	_host = DUNGEON.instantiate() as Dungeon3D
	_host.test_mode = true
	_host.enable_run_vending_tutorial_in_test = true
	_host.run_seed_override = 20261118
	add_child(_host)
	if not await _wait(func() -> bool:
		return _host.is_node_ready() and is_instance_valid(_host.player) and not (_host.get("_room_by_id") as Dictionary).is_empty()
	, "正式 Dungeon ready"):
		_finish()
		return
	_controller = _host.get("_run_vending_tutorial") as Node
	_room = (_host.get("_room_by_id") as Dictionary).get(str(_host.get("_current_room_id"))) as DungeonRoom3D
	_check(is_instance_valid(_controller), "显式 opt-in 安装独立 controller")
	_check(is_instance_valid(_room), "当前 host/room 可用")
	if _room == null:
		_finish()
		return
	_money = GameManager.currency
	_inventory_before = _host.get_inventory_module().get_slots_snapshot()
	_stock_before = (_host.build_runtime_save_snapshot().get("merchant_stock", {}) as Dictionary).duplicate(true)
	_check(BaseManager.get_narrative_history(TUTORIAL_ID).is_empty(), "隔离档初始无教学历史；不手工写入或清除历史")
	_capture_dir = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	_spawn_real_stations()
	await get_tree().process_frame
	await _capture("01_stations")
	_check_negative_objects()
	_check_positive_merchant()
	await _capture("02_merchant_positive")
	await _interrupt_and_retry_once()
	await _capture("03_after_interrupt")
	await _skip_close_and_retry()
	await _complete_without_purchase()
	if DisplayServer.get_name() != "headless":
		_check(_b_captured, "真实 B 双侧立绘截图已落盘")
	_check(GameManager.currency == _money, "教学全过程不改本局金币")
	_check(_host.get_inventory_module().get_slots_snapshot() == _inventory_before, "教学全过程不改背包库存")
	_check((_host.build_runtime_save_snapshot().get("merchant_stock", {}) as Dictionary) == _stock_before, "教学全过程不改商人货架库存")
	_check(_host.call("get_run_vending_tutorial_station_snapshot").get("station") == _merchant, "完成后仍只查询真实当前商人服务点")
	_finish()


func _spawn_real_stations() -> void:
	_merchant = ServiceStation3D.new()
	_merchant.name = "RealMerchantStation"
	_merchant.configure("merchant", "局内自动贩卖机", Color(0.3, 0.9, 0.7))
	_room.add_child(_merchant)
	_merchant.position = Vector3(1.5, 0.0, 0.0)
	_upgrade = ServiceStation3D.new()
	_upgrade.name = "RealUpgradeStation"
	_upgrade.configure("upgrade", "改造台", Color(0.5, 0.7, 1.0))
	_room.add_child(_upgrade)
	_upgrade.position = Vector3(0.0, 0.0, 4.0)
	# 真实 Area3D 的 body_entered 由物理帧异步维护；反例先清空本夹具手动注入的接近态，
	# 避免 Dungeon 初始玩家位置或旧房间信号污染“未靠近”断言。
	_merchant.call("_on_body_exited", _host.player)
	_upgrade.call("_on_body_exited", _host.player)


func _check_negative_objects() -> void:
	# 先把玩家真实移出两台机器的交互体积，再验证“未靠近”反例。
	_host.player.global_position = _room.global_position + Vector3(12.0, 0.0, 12.0)
	_merchant.call("_on_body_exited", _host.player)
	_upgrade.call("_on_body_exited", _host.player)
	var snapshot := _host.call("get_run_vending_tutorial_station_snapshot") as Dictionary
	_check(snapshot.is_empty(), "未靠近真实 merchant 时不触发")
	_host.player.global_position = _upgrade.global_position
	_upgrade.call("_on_body_entered", _host.player)
	_check((_host.call("get_run_vending_tutorial_station_snapshot") as Dictionary).is_empty(), "upgrade 服务点不冒充 merchant")
	_upgrade.call("_on_body_exited", _host.player)


func _check_positive_merchant() -> void:
	_host.player.global_position = _merchant.global_position
	_merchant.call("_on_body_entered", _host.player)
	var snapshot := _host.call("get_run_vending_tutorial_station_snapshot") as Dictionary
	_check(snapshot.get("station") == _merchant, "当前 room 入树的真实 merchant 为正例")
	_check(bool(snapshot.get("player_in_range", false)), "正例使用 station.get_snapshot.player_in_range")
	_check(str(snapshot.get("room_id", "")) == str(_host.get("_current_room_id")), "正例属于当前 host/room")


func _interrupt_and_retry_once() -> void:
	if not await _wait(func() -> bool: return NarrativeDirector.active_id() == TUTORIAL_ID, "真实 merchant 接近后起播"):
		return
	var before := _controller.call("get_snapshot") as Dictionary
	NarrativeDirector.abort("qa_vending_interrupt")
	await get_tree().process_frame
	var after := _controller.call("get_snapshot") as Dictionary
	_check(not BaseManager.has_narrative_completed(TUTORIAL_ID), "中断不写 narrative_history")
	_check(not bool(after.get("locked", false)), "中断释放独立教学锁")
	_check(int(after.get("generation", 0)) > int(before.get("generation", 0)), "中断使 controller 代际失效")
	_check(await _wait(func() -> bool: return NarrativeDirector.active_id() == TUTORIAL_ID, "仍在范围内中断后可重试"), "中断后只重试一次起播")
	_check(int((_controller.call("get_snapshot") as Dictionary).get("request_count", 0)) == 2, "同一真实证据只产生一次重试")


func _skip_close_and_retry() -> void:
	for action in ["skip", "close"]:
		if not await _wait(func() -> bool: return NarrativeDirector.active_id() == TUTORIAL_ID and DialogueUI.is_active(), action + " 前真实对白起播"):
			return
		var before := _controller.call("get_snapshot") as Dictionary
		var revision := BaseManager.data.save_revision
		DialogueUI.call(action)
		if not await _wait(func() -> bool: return NarrativeDirector.active_id().is_empty(), action + " 终止而非继续视作已读"):
			return
		if not await _wait(func() -> bool: return not bool((_controller.call("get_snapshot") as Dictionary).get("locked", true)), action + " 释放教学锁"):
			return
		_check(BaseManager.get_narrative_history(TUTORIAL_ID).is_empty(), action + " 不写 narrative_history")
		_check(BaseManager.data.save_revision == revision, action + " 不保存完成记录")
		_check(int((_controller.call("get_snapshot") as Dictionary).get("generation", 0)) > int(before.get("generation", 0)), action + " 使旧代际失效")
		if not await _wait(func() -> bool: return NarrativeDirector.active_id() == TUTORIAL_ID and DialogueUI.is_active(), action + " 后真实 merchant 可重试"):
			return
		_check(int((_controller.call("get_snapshot") as Dictionary).get("request_count", 0)) == int(before.get("request_count", 0)) + 1, action + " 后只重试一次起播")


func _check_and_capture_b() -> void:
	if not await _wait(func() -> bool: return NarrativeDirector.active_id() == TUTORIAL_ID and DialogueUI.is_active(), "B 对白真实起播"):
		return
	_check(DialogueUI.current_line_index() == 0, "B 从绿苔首句起播")
	DialogueUI.reveal_all()
	DialogueUI.advance()
	if not await _wait(func() -> bool:
		var snapshot := DialogueUI.get_presentation_snapshot()
		var left: Dictionary = snapshot.get("left", {})
		var right: Dictionary = snapshot.get("right", {})
		return bool(left.get("visible", false)) and bool(right.get("visible", false)) and not bool(left.get("entering", true)) and not bool(right.get("entering", true))
	, "B 双侧立绘同时完成入场"):
		return
	var presentation := DialogueUI.get_presentation_snapshot()
	var left: Dictionary = presentation.get("left", {})
	var right: Dictionary = presentation.get("right", {})
	_check(NarrativeDirector.active_id() == TUTORIAL_ID and DialogueUI.is_active(), "B 证据属于真实教学在播会话")
	_check(str(presentation.get("mode", "")) == "B" and bool(presentation.get("portraits_enabled", false)), "真实教学使用 B 而非旧 A 模式")
	_check(str(left.get("speaker_id", "")) == "npc_base99_green" and str(left.get("mode", "")) == "hologram", "B 左侧为 npc_base99_green hologram")
	_check(str(right.get("speaker_id", "")) == "player" and str(presentation.get("active_speaker", "")) == "player", "B 右侧为当前说话的 player，左侧绿苔仍保留")
	_check(BaseManager.get_narrative_history(TUTORIAL_ID).is_empty(), "B 双侧展示中尚未读完，不提前记历史")
	_check(bool(left.get("visible", false)) and bool(right.get("visible", false)), "B 左右立绘同一快照同时可见")
	_check(int(left.get("mesh_count", 0)) > 0 and int(right.get("mesh_count", 0)) > 0 and bool(left.get("rendering", false)) and bool(right.get("rendering", false)), "B 双侧有真实网格且正在渲染")
	_check(int(presentation.get("viewport_count", 0)) == 2, "B 双侧使用两个真实 SubViewport")
	var left_rect: Rect2 = left.get("rect", Rect2())
	var right_rect: Rect2 = right.get("rect", Rect2())
	var screen := get_viewport().get_visible_rect()
	_check(left_rect.has_area() and right_rect.has_area() and screen.encloses(left_rect) and screen.encloses(right_rect) and left_rect.end.x < right_rect.position.x, "B 双侧完整位于画面内且左右不重叠")
	DialogueUI.reveal_all()
	_b_captured = await _capture("04_vending_B_both_visible")


func _complete_without_purchase() -> void:
	await _check_and_capture_b()
	var revision := BaseManager.data.save_revision
	var deadline := Time.get_ticks_msec() + 18000
	while NarrativeDirector.active_id() == TUTORIAL_ID and Time.get_ticks_msec() < deadline:
		if DialogueUI.is_active():
			DialogueUI.reveal_all()
			DialogueUI.advance()
		await get_tree().process_frame
	_check(await _wait(func() -> bool: return NarrativeDirector.active_id().is_empty(), "对白完整收口"), "对白完整结束")
	_check(BaseManager.has_narrative_completed(TUTORIAL_ID), "完整结束只写一次 history")
	_check(int(BaseManager.get_narrative_history(TUTORIAL_ID).get("completed_count", 0)) == 1, "只有真实完整读完累计一次完成")
	_check(BaseManager.data.save_revision == revision + 1, "完整读完只保存一次")
	var disk := ProfileSaveService.read_profile(BaseManager.save_path)
	var payload: Dictionary = disk.get("payload", {})
	var history: Dictionary = payload.get("narrative_history", {})
	var record: Dictionary = history.get(TUTORIAL_ID, {})
	_check(bool(disk.get("success", false)) and int(record.get("completed_count", 0)) == 1, "校验回读隔离存档中真实落盘的一次完成")
	var saved_revision := BaseManager.data.save_revision
	var saved_history := BaseManager.get_narrative_history(TUTORIAL_ID)
	await get_tree().create_timer(0.8).timeout
	var completed := _controller.call("get_snapshot") as Dictionary
	_check(int(completed.get("request_count", 0)) == 4, "中断、skip、close 各重试一次，完成后不再次触发")
	_check(NarrativeDirector.active_id().is_empty() and BaseManager.data.save_revision == saved_revision and BaseManager.get_narrative_history(TUTORIAL_ID) == saved_history, "完成后跨过重试窗口不重播、不重复保存 history")
	_check(not bool(completed.get("locked", false)), "完成后释放独立教学锁")


func _wait(predicate: Callable, label: String, seconds := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	_check(false, label)
	return false


func _check(value: bool, label: String) -> void:
	_checks.append(label)
	if not value:
		_failures.append(label)


func _capture(label: String) -> bool:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_capture_dir.path_join(label + ".png")) != OK:
		_failures.append("真实贩卖机截图落盘：" + label)
		return false
	return true


func _finish() -> void:
	print("RUN_VENDING_TUTORIAL_RESULT ", JSON.stringify({
		"passed": _failures.is_empty(),
		"checks": _checks.size(),
		"failures": _failures,
		"history": BaseManager.has_narrative_completed(TUTORIAL_ID),
		"b_both_visible_captured": _b_captured,
		"money_unchanged": GameManager.currency == _money,
	}))
	get_tree().quit(0 if _failures.is_empty() else 2)
