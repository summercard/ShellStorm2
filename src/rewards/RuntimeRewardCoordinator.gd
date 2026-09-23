class_name RuntimeRewardCoordinator
extends RefCounted
## 运行时奖励调度边界：场景只提供触发事实，本类负责覆盖链与确定性 seed。
## 不持有场景节点，不生成表现，不写背包/钱包。

const SERVICE := preload("res://src/rewards/RewardService.gd")

var _run_seed := 1


func configure(run_seed: int) -> void:
	_run_seed = run_seed


func resolve_search(
	room_reward_plan: Dictionary,
	pool_id: String,
	floor: int,
	event_id: String
) -> Dictionary:
	return _resolve_dispatch({
		"trigger": "search",
		"room_reward_plan": room_reward_plan,
		"default_pool_id": pool_id,
		"context": _context(event_id, floor),
	})


func resolve_clear(room_reward_plan: Dictionary, floor: int, event_id: String) -> Dictionary:
	return _resolve_dispatch({
		"trigger": "clear",
		"room_reward_plan": room_reward_plan,
		"context": _context(event_id, floor),
	})


func resolve_kill(
	room_reward_plan: Dictionary,
	enemy_data: Dictionary,
	event_id: String
) -> Dictionary:
	var floor := maxi(1, int(enemy_data.get("floor", 1)))
	var tier := (
		"boss" if bool(enemy_data.get("is_boss", false))
		else "elite" if bool(enemy_data.get("is_elite", false))
		else "normal"
	)
	var report := _resolve_dispatch({
		"trigger": "kill",
		"room_reward_plan": room_reward_plan,
		"monster_id": str(enemy_data.get("enemy_type", "melee_chaser")),
		"monster_tier": tier,
		"floor_level": _floor_level_from_loot_table(str(enemy_data.get("loot_table", ""))),
		"context": _context(event_id, floor),
	})
	var bounty := maxi(0, int(enemy_data.get("elite_bounty_currency", 0)))
	if bounty > 0:
		var bounty_report := SERVICE.resolve({
			"spec_id": "elite_bounty:%s" % event_id,
			"entries": [{
				"kind": "currency",
				"currency_id": "extraction_points",
				"amount": bounty,
			}],
		}, _context("%s:bounty" % event_id, floor))
		(report["grants"] as Array).append_array(bounty_report.get("grants", []))
		(report["errors"] as Array).append_array(bounty_report.get("errors", []))
		report["ok"] = bool(report.get("ok", false)) and bool(bounty_report.get("ok", false))
	# Runtime presentation keeps the current one-physical-pickup contract.  A
	# monster spec can independently hit both its main pool and the ammo rider;
	# ammo wins that collision so elite/boss guaranteed reserve ammo remains
	# true. Base currency and elite bounty collapse into one ground orb.
	_collapse_kill_ground_grants(report)
	return report


func _collapse_kill_ground_grants(report: Dictionary) -> void:
	var grants := report.get("grants", []) as Array
	var currency_grants: Array = []
	var physical_grants: Array = []
	for value in grants:
		var grant := value as Dictionary
		if str(grant.get("kind", "")) == "currency":
			currency_grants.append(grant)
		else:
			physical_grants.append(grant)
	var collapsed: Array = []
	if not physical_grants.is_empty():
		var chosen := physical_grants[0] as Dictionary
		for value in physical_grants:
			var candidate := value as Dictionary
			if str(candidate.get("item_id", "")) == "item_ammo_pack":
				chosen = candidate
				break
		collapsed.append(chosen)
	if not currency_grants.is_empty():
		var merged_currency := (currency_grants[0] as Dictionary).duplicate(true)
		var total_currency := 0
		for value in currency_grants:
			total_currency += maxi(0, int((value as Dictionary).get("amount", 0)))
		merged_currency["amount"] = total_currency
		collapsed.append(merged_currency)
	report["grants"] = collapsed


func resolve_fixed_item(item_id: String, count: int, event_id: String, floor := 1) -> Dictionary:
	var resolution := SERVICE.resolve({
		"spec_id": "fixed:%s" % event_id,
		"entries": [{"kind": "item", "item_id": item_id, "count": count}],
	}, _context(event_id, floor))
	return _report(resolution)


func _resolve_dispatch(request: Dictionary) -> Dictionary:
	return _report(SERVICE.resolve_dispatch(request))


func _report(resolution: Dictionary) -> Dictionary:
	return {
		"ok": bool(resolution.get("ok", false)),
		"spec_id": str(resolution.get("spec_id", "")),
		"grants": (resolution.get("grants", []) as Array).duplicate(true),
		"rejected": (resolution.get("rejected", []) as Array).duplicate(true),
		"errors": (resolution.get("errors", []) as Array).duplicate(true),
		"truncated": bool(resolution.get("truncated", false)),
		"used_fallback": bool(resolution.get("used_fallback", false)),
	}


func _context(event_id: String, floor: int) -> Dictionary:
	return {
		"seed": hash("%d|%s" % [_run_seed, event_id]),
		"floor": maxi(1, floor),
		"depth": maxi(0, floor - 1),
	}


func _floor_level_from_loot_table(pool_id: String) -> int:
	match pool_id:
		"loot_floor_3_4": return RoomData.FloorLevel.MEDIUM
		"loot_floor_5": return RoomData.FloorLevel.DEEP
		"loot_abyss": return RoomData.FloorLevel.ABYSS
	return RoomData.FloorLevel.SHALLOW
