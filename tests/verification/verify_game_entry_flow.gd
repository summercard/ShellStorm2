extends Node

const ENTRY_FLOW_SCRIPT := preload("res://src/core/GameEntryFlow.gd")


func _ready() -> void:
	var failures: Array[String] = []
	_verify_entry_intent_lifecycle(failures)
	_verify_tower_entry_gate(failures)
	if failures.is_empty():
		print("GAME_ENTRY_FLOW_OK: startup page is exclusive to cold/explicit entry; death return stays on the 99F gameplay path")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_entry_intent_lifecycle(failures: Array[String]) -> void:
	var flow := ENTRY_FLOW_SCRIPT.new()
	var cold_start := flow.consume_main_scene_entry()
	if not bool(cold_start.get("show_main_entry", false)) or str(cold_start.get("reason", "")) != flow.REASON_COLD_START:
		failures.append("进程首次进入没有唯一解析为冷启动主页")
	var unrequested_reload := flow.consume_main_scene_entry()
	if bool(unrequested_reload.get("show_main_entry", true)):
		failures.append("未登记的局内场景重载错误重新打开了启动页")
	flow.request_gameplay_entry(flow.REASON_DEATH_RETURN_99F, flow.SPAWN_BASE_99F)
	var death_return := flow.consume_main_scene_entry()
	if bool(death_return.get("show_main_entry", true)):
		failures.append("死亡返回被错误分流到启动页")
	if str(death_return.get("spawn_target", "")) != flow.SPAWN_BASE_99F:
		failures.append("死亡返回没有保留99F基地出生契约")
	flow.request_main_entry(flow.REASON_EXPLICIT_MAIN_ENTRY)
	var explicit_main := flow.consume_main_scene_entry()
	if not bool(explicit_main.get("show_main_entry", false)):
		failures.append("显式返回开始界面没有打开主页")
	var cancelled_id := flow.request_main_entry(flow.REASON_EXPLICIT_MAIN_ENTRY)
	if not flow.cancel_request(cancelled_id) or not flow.peek_pending_entry().is_empty():
		failures.append("场景切换失败时无法撤销未消费的主页请求")
	flow.free()


func _verify_tower_entry_gate(failures: Array[String]) -> void:
	var tower := TowerDescent3D.new()
	tower.return_scene_path = GameDesignConfig.MAIN_SCENE
	var death_request_id := int(tower.call("_request_return_entry_context", false))
	var routed_death := GameEntryFlow.consume_main_scene_entry()
	if death_request_id <= 0 or str(routed_death.get("reason", "")) != GameEntryFlow.REASON_DEATH_RETURN_99F:
		failures.append("Dungeon3D死亡结算没有登记99F玩法返回意图")
	if bool(routed_death.get("show_main_entry", true)):
		failures.append("Dungeon3D死亡结算的实际返回意图仍会显示启动页")
	tower.set("_entry_context", {
		"kind": GameEntryFlow.KIND_GAMEPLAY,
		"reason": GameEntryFlow.REASON_DEATH_RETURN_99F,
		"spawn_target": GameEntryFlow.SPAWN_BASE_99F,
		"show_main_entry": false,
	})
	if bool(tower.call("_entry_context_requests_main_entry")):
		failures.append("TowerDescent3D仍会为死亡返回安装启动页")
	if bool(tower.call("_should_start_on_rooftop_for_entry")):
		failures.append("死亡返回99F仍可被新手逻辑改送到100F天台")
	tower.set("_entry_context", {
		"kind": GameEntryFlow.KIND_MAIN_ENTRY,
		"reason": GameEntryFlow.REASON_EXPLICIT_MAIN_ENTRY,
		"spawn_target": GameEntryFlow.SPAWN_SAVED_PROGRESS,
		"show_main_entry": true,
	})
	if not bool(tower.call("_entry_context_requests_main_entry")):
		failures.append("TowerDescent3D没有接受显式返回开始界面的请求")
	tower.free()
