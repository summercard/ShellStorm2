class_name RevivalPolicy
extends RefCounted

## v0.1 空策略：只冻结“无复活来源”时的查询与失败语义，不提前决定次数、成本或复活点。
const REASON_NO_SOURCE := "no_revival_source"


func query(_context: Dictionary = {}) -> Dictionary:
	return {
		"available": false,
		"reason": REASON_NO_SOURCE,
		"source_id": "",
		"reservation_id": "",
	}


func reserve(context: Dictionary = {}) -> Dictionary:
	var decision := query(context)
	return {
		"success": false,
		"reason": decision["reason"],
		"source_id": decision["source_id"],
		"reservation_id": decision["reservation_id"],
	}
