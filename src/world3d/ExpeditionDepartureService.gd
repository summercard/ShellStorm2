class_name ExpeditionDepartureService
extends RefCounted
## 基地选关与天台直达入口共用的出发事务。
##
## ⚠️ 2026-11-12 修：99F 基地（`BaseWorld3D`，extends Node3D）**不是** `Dungeon3D`，
## 既不注册运行快照提供者、也没有 `build_runtime_save_snapshot()`。
## 旧实现无条件要求 `flush_runtime_checkpoint()` 成功，于是基地里点任何远征入口都会
## 走 `_departure_failed("保存失败，请重试")` —— 玩家永远出不了 99F，入场仪式更无从播放。
## 现在把「有提供者却写盘失败」和「本来就没有运行快照可抓」分开：
##   - 有提供者（塔楼/关卡内）：仍必须 flush 成功，否则视为真失败；
##   - 无提供者（基地本体）：直接沿用当前已落盘的快照；若连快照都没有（新档直接站在基地），
##     不伪造一条 schema 不完整的快照，目的地默认来源即 BASE，仪式照常播放。
static func prepare(provider: Node, source := ExpeditionEntryContext.BASE) -> Dictionary:
	var has_provider := BaseManager.has_runtime_checkpoint_provider()
	if has_provider and not BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure"):
		return {"success": false, "message": "保存失败，请重试"}
	var previous := BaseManager.get_active_run_checkpoint()
	BaseManager.unregister_runtime_checkpoint_provider(provider, false)
	if previous.is_empty():
		return {"success": true, "previous": previous, "provider": provider, "carried": false}
	var carried := previous.duplicate(true)
	carried[Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY] = true
	carried[ExpeditionEntryContext.SOURCE_KEY] = ExpeditionEntryContext.normalize(source)
	carried.erase(ExpeditionEntryContext.RETURN_KEY)
	if not BaseManager.set_active_run_checkpoint(carried, "mission_operations_departure_carry"):
		BaseManager.register_runtime_checkpoint_provider(provider)
		return {"success": false, "message": "出发交接失败，请重试"}
	return {"success": true, "previous": previous, "provider": provider, "carried": true}

static func rollback(ticket: Dictionary) -> void:
	var previous := ticket.get("previous", {}) as Dictionary
	if previous.is_empty():
		BaseManager.clear_active_run_checkpoint("mission_operations_departure_rollback")
	else:
		BaseManager.set_active_run_checkpoint(previous, "mission_operations_departure_rollback")
	var provider := ticket.get("provider") as Node
	if is_instance_valid(provider):
		BaseManager.register_runtime_checkpoint_provider(provider)
	GameDesignConfig.pending_expedition_level_id = ""
