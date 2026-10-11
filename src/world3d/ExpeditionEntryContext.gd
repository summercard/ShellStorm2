class_name ExpeditionEntryContext
extends RefCounted
## 只保存白名单入口 ID，场景和固定安全落点由正式入口声明。
const BASE := "base_99f"
const TOWER03 := "tower03_rooftop"
const SOURCE_KEY := "expedition_entry_source"
const RETURN_KEY := "expedition_return_source"
const TOWER03_SPAWN := Vector3(-22.0, 0.08, -167.3)

static func normalize(source: String) -> String:
	return TOWER03 if source == TOWER03 else BASE

static func return_marker(source: String) -> Dictionary:
	if normalize(source) != TOWER03:
		return {}
	return RunPersistenceService.finalize_runtime_snapshot({
		"scope": "base", "runtime_map_id": "", "current_room_id": "start",
		"current_floor_index": 0, RETURN_KEY: TOWER03,
	})

static func is_on_tower03(position: Vector3) -> bool:
	return position.x > -46.5 and position.x < 22.5 and position.z > -195.5 and position.z < -152.0 and position.y > -0.5 and position.y < 12.0
