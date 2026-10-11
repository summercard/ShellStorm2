class_name ExpeditionDepartureService
extends RefCounted
## 基地选关与天台直达入口共用的出发事务。
static func prepare(provider: Node, source := ExpeditionEntryContext.BASE) -> Dictionary:
	if not BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure"):
		return {"success": false, "message": "保存失败，请重试"}
	var previous := BaseManager.get_active_run_checkpoint()
	BaseManager.unregister_runtime_checkpoint_provider(provider, false)
	var carried := previous.duplicate(true)
	carried[Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY] = true
	carried[ExpeditionEntryContext.SOURCE_KEY] = ExpeditionEntryContext.normalize(source)
	carried.erase(ExpeditionEntryContext.RETURN_KEY)
	if not BaseManager.set_active_run_checkpoint(carried, "mission_operations_departure_carry"):
		BaseManager.register_runtime_checkpoint_provider(provider)
		return {"success": false, "message": "出发交接失败，请重试"}
	return {"success": true, "previous": previous, "provider": provider}

static func rollback(ticket: Dictionary) -> void:
	BaseManager.set_active_run_checkpoint(ticket.get("previous", {}), "mission_operations_departure_rollback")
	var provider := ticket.get("provider") as Node
	if is_instance_valid(provider):
		BaseManager.register_runtime_checkpoint_provider(provider)
	GameDesignConfig.pending_expedition_level_id = ""
