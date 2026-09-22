class_name BlueprintUpgradeService
extends RefCounted
## 枪械工坊蓝图升级的纯规则边界；不写存档，不访问 UI。

const MAX_TIER := 3
const COSTS := {
	"gunbody": [80, 200, 500],
	"bullet": [60, 150, 400],
	"attachment": [50, 120, 350],
}


static func cost_for(category_id: String, current_tier: int) -> int:
	if not COSTS.has(category_id) or current_tier < 0 or current_tier >= MAX_TIER:
		return -1
	return int((COSTS[category_id] as Array)[current_tier])


static func plan(category_id: String, current_tier: int, expected_tier: int, points: int) -> Dictionary:
	if not COSTS.has(category_id):
		return {"success": false, "code": "invalid_category"}
	if current_tier != expected_tier:
		return {"success": false, "code": "stale_tier", "current_tier": current_tier}
	if current_tier >= MAX_TIER:
		return {"success": false, "code": "max_tier", "current_tier": current_tier}
	var cost := cost_for(category_id, current_tier)
	if points < cost:
		return {
			"success": false, "code": "insufficient_currency",
			"cost": cost, "points": points, "current_tier": current_tier,
		}
	return {
		"success": true,
		"category_id": category_id,
		"old_tier": current_tier,
		"new_tier": current_tier + 1,
		"cost": cost,
		"old_points": points,
		"new_points": points - cost,
	}
