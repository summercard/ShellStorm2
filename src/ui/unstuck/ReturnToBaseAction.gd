class_name ReturnToBaseAction
extends RefCounted
## 暂停菜单脱困动作的唯一策略门。世界根节点负责给出战局状态并执行
## 回城；按钮绝不直接改玩家坐标，避免绕过原有楼层/存档/房间链路。

const CONTEXT_METHOD := "get_return_to_base_context"
const CAN_REQUEST_METHOD := "can_return_player_to_base_center"
const REQUEST_METHOD := "return_player_to_base_center_from_pause"


static func get_availability(game_root: Node) -> Dictionary:
	if game_root == null:
		return _result(false, "未连接当前游戏场景")
	var context := {}
	if game_root.has_method(CONTEXT_METHOD):
		var value: Variant = game_root.call(CONTEXT_METHOD)
		if value is Dictionary:
			context = (value as Dictionary).duplicate(true)
	if bool(context.get("in_active_run", false)) or bool(context.get("combat_active", false)):
		return _result(false, "战局中不可使用")
	if bool(context.get("transition_active", false)):
		return _result(false, "场景切换中不可使用")
	if game_root.has_method(CAN_REQUEST_METHOD):
		if not bool(game_root.call(CAN_REQUEST_METHOD)):
			return _result(false, str(context.get("unavailable_reason", "当前位置不可回到基地中心")))
	elif not bool(context.get("base_center_available", false)):
		return _result(false, "当前场景尚未提供基地出生点")
	if not game_root.has_method(REQUEST_METHOD):
		return _result(false, "当前场景尚未连接脱困动作")
	return _result(true, "返回99层基地中心")


static func request(game_root: Node) -> Dictionary:
	var availability := get_availability(game_root)
	if not bool(availability.get("available", false)):
		return availability
	var result: Variant = game_root.call(REQUEST_METHOD)
	if result is Dictionary:
		var response := (result as Dictionary).duplicate(true)
		if not response.has("success"):
			response["success"] = true
		return response
	return {
		"available": true,
		"success": bool(result),
		"reason": "已返回基地中心" if bool(result) else "返回基地中心失败",
	}


static func _result(available: bool, reason: String) -> Dictionary:
	return {"available": available, "success": false, "reason": reason}
