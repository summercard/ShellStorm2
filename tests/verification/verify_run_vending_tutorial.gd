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
	_capture_dir = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	_spawn_real_stations()
	await get_tree().process_frame
	await _capture("01_stations")
	_check_negative_objects()
	_check_positive_merchant()
	await _capture("02_merchant_positive")
	await _interrupt_and_retry_once()
	await _capture("03_after_interrupt")
	await _complete_without_purchase()
	_check(GameManager.currency == _money, "教学全过程不改本局金币")
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


func _complete_without_purchase() -> void:
	var deadline := Time.get_ticks_msec() + 18000
	while NarrativeDirector.active_id() == TUTORIAL_ID and Time.get_ticks_msec() < deadline:
		if DialogueUI.is_active():
			DialogueUI.reveal_all()
			DialogueUI.advance()
		await get_tree().process_frame
	_check(await _wait(func() -> bool: return NarrativeDirector.active_id().is_empty(), "对白完整收口"), "对白完整结束")
	_check(BaseManager.has_narrative_completed(TUTORIAL_ID), "完整结束只写一次 history")
	var completed := _controller.call("get_snapshot") as Dictionary
	_check(int(completed.get("request_count", 0)) == 2, "完成后不再次触发")
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


func _capture(label: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_capture_dir.path_join(label + ".png")) != OK:
		_failures.append("真实贩卖机截图落盘：" + label)


func _finish() -> void:
	print("RUN_VENDING_TUTORIAL_RESULT ", JSON.stringify({
		"passed": _failures.is_empty(),
		"checks": _checks.size(),
		"failures": _failures,
		"history": BaseManager.has_narrative_completed(TUTORIAL_ID),
		"money_unchanged": GameManager.currency == _money,
	}))
	get_tree().quit(0 if _failures.is_empty() else 2)
