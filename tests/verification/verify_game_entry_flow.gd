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
	_verify_runtime_restore_entry_routing(flow, failures)
	flow.request_main_entry(flow.REASON_EXPLICIT_MAIN_ENTRY)
	var explicit_main := flow.consume_main_scene_entry()
	if not bool(explicit_main.get("show_main_entry", false)):
		failures.append("显式返回开始界面没有打开主页")
	var cancelled_id := flow.request_main_entry(flow.REASON_EXPLICIT_MAIN_ENTRY)
	if not flow.cancel_request(cancelled_id) or not flow.peek_pending_entry().is_empty():
		failures.append("场景切换失败时无法撤销未消费的主页请求")
	flow.free()


func _verify_runtime_restore_entry_routing(flow: Node, failures: Array[String]) -> void:
	_assert_runtime_restore_case(
		flow,
		{
			"request_id": 77,
			"kind": GameEntryFlow.KIND_GAMEPLAY,
			"reason": GameEntryFlow.REASON_SCENE_REENTRY,
			"spawn_target": GameEntryFlow.SPAWN_BASE_99F,
			"show_main_entry": false,
		},
		GameEntryFlow.KIND_GAMEPLAY,
		false,
		"局内恢复",
		failures
	)
	_assert_runtime_restore_case(
		flow,
		{
			"request_id": 88,
			"kind": GameEntryFlow.KIND_MAIN_ENTRY,
			"reason": GameEntryFlow.REASON_COLD_START,
			"spawn_target": GameEntryFlow.SPAWN_BASE_99F,
			"show_main_entry": true,
		},
		GameEntryFlow.KIND_MAIN_ENTRY,
		true,
		"冷启动主页",
		failures
	)
	_assert_runtime_restore_case(
		flow,
		{
			"request_id": 89,
			"kind": GameEntryFlow.KIND_MAIN_ENTRY,
			"reason": GameEntryFlow.REASON_EXPLICIT_MAIN_ENTRY,
			"spawn_target": GameEntryFlow.SPAWN_BASE_99F,
			"show_main_entry": true,
		},
		GameEntryFlow.KIND_MAIN_ENTRY,
		true,
		"显式主页",
		failures
	)
	_assert_runtime_restore_case(
		flow,
		{
			"kind": GameEntryFlow.KIND_MAIN_ENTRY,
			"reason": GameEntryFlow.REASON_EXPLICIT_MAIN_ENTRY,
			"spawn_target": GameEntryFlow.SPAWN_BASE_99F,
			"show_main_entry": false,
		},
		GameEntryFlow.KIND_GAMEPLAY,
		false,
		"隐藏主页的 main_entry",
		failures
	)
	_assert_runtime_restore_case(
		flow,
		{
			"kind": GameEntryFlow.KIND_GAMEPLAY,
			"reason": GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
			"spawn_target": GameEntryFlow.SPAWN_SAVED_PROGRESS,
			"show_main_entry": false,
		},
		GameEntryFlow.KIND_GAMEPLAY,
		false,
		"基地远征出发",
		failures
	)
	_assert_runtime_restore_case(
		flow,
		{
			"kind": GameEntryFlow.KIND_GAMEPLAY,
			"reason": GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
			"spawn_target": GameEntryFlow.SPAWN_BASE_99F,
			"show_main_entry": true,
		},
		GameEntryFlow.KIND_GAMEPLAY,
		false,
		"显示标志错误的 gameplay",
		failures
	)
	_assert_runtime_restore_case(
		flow,
		{},
		GameEntryFlow.KIND_GAMEPLAY,
		false,
		"空 source context",
		failures
	)


func _assert_runtime_restore_case(
	flow: Node,
	source: Dictionary,
	expected_kind: String,
	expected_show_main_entry: bool,
	label: String,
	failures: Array[String],
) -> void:
	var source_before := source.duplicate(true)
	var request_id: int = int(flow.request_runtime_restore_entry(source))
	var restored: Dictionary = flow.consume_main_scene_entry()
	if source != source_before:
		failures.append("%s helper 修改了 source context" % label)
	if request_id <= 0:
		failures.append("%s helper 没有返回有效 request_id" % label)
	if str(restored.get("kind", "")) != expected_kind:
		failures.append("%s 没有转发为预期入口 kind" % label)
	if bool(restored.get("show_main_entry", not expected_show_main_entry)) != expected_show_main_entry:
		failures.append("%s 的 show_main_entry 不符合预期" % label)
	if str(restored.get("reason", "")) != GameEntryFlow.REASON_RUNTIME_RESTORE:
		failures.append("%s reason 不是 runtime_restore" % label)
	if str(restored.get("spawn_target", "")) != GameEntryFlow.SPAWN_SAVED_PROGRESS:
		failures.append("%s spawn 不是 saved_progress" % label)

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
	# 独立副本返回正式 BaseWorld3D 时也必须沿用99F基地出生契约。
	tower.return_scene_path = GameDesignConfig.BASE_SCENE_3D
	var rogue_return_request_id := int(tower.call("_request_return_entry_context", true))
	var rogue_return := GameEntryFlow.consume_main_scene_entry()
	if rogue_return_request_id <= 0 or str(rogue_return.get("reason", "")) != GameEntryFlow.REASON_SUCCESSFUL_RETURN_99F:
		failures.append("独立副本返回正式基地没有登记成功撤离入口意图")
	if str(rogue_return.get("spawn_target", "")) != GameEntryFlow.SPAWN_BASE_99F:
		failures.append("独立副本返回正式基地没有保留99F出生契约")
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
