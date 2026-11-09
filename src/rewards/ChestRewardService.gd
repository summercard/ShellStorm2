class_name ChestRewardService
extends RefCounted
## 宝箱奖励的唯一纯解析器。
##
## 输入宝箱配置、局种子和稳定的房间/宝箱 ID，输出标准 item grants。
## 本类不创建节点、不发放奖励、不推进 Dungeon 主 RNG；每个奖励分支都通过
## RewardService.resolve() 使用独立的 `seed + room_id + chest_id + salt` 流。

const _REWARD_SERVICE := preload("res://src/rewards/RewardService.gd")
const _SPEC := preload("res://src/rewards/RewardSpec.gd")
const _WEAPON_BULLET_DROP := preload("res://src/weapons/WeaponBulletDrop.gd")

const TIER_NORMAL := "normal"
const TIER_ADVANCED := "advanced"
const FATE_ITEM_ID := "item_fate_card_drop"
const FATE_CHANCE := 0.30
const DEFAULT_POOL_ID := "loot_floor_1_2"


## 解析一只宝箱。返回 `{ok, grants, errors}`。
## `chest_tier` 显式优先；旧配置没有档位时，rare/epic 品质兼容升级为 advanced。
static func resolve(
	chest_config: Dictionary,
	run_seed: int,
	room_id: String,
	floor_level: int = 1
) -> Dictionary:
	var result := {
		"ok": false,
		"grants": [] as Array[Dictionary],
		"errors": [] as Array[Dictionary],
	}
	var errors: Array[Dictionary] = []
	if room_id.is_empty():
		errors.append(_error("INVALID_ROOM_ID", "room_id 不能为空"))
		result["errors"] = errors
		return result
	if chest_config.is_empty():
		errors.append(_error("INVALID_CHEST_CONFIG", "chest_config 为空"))
		result["errors"] = errors
		return result

	var chest_id := str(chest_config.get("id", ""))
	if chest_id.is_empty():
		errors.append(_error("INVALID_CHEST_ID", "chest_config.id 不能为空"))
		result["errors"] = errors
		return result

	var tier := _tier_for(chest_config)
	if tier.is_empty():
		errors.append(_error("INVALID_CHEST_TIER", "chest_tier 必须是 normal 或 advanced"))
		result["errors"] = errors
		return result

	var pool_id := str(chest_config.get("reward_pool_id", DEFAULT_POOL_ID))
	var floor := maxi(1, floor_level)
	var grants: Array[Dictionary] = []
	var branch_reports: Array = []

	var fate_report := _resolve_fate(
		chest_config, run_seed, room_id, chest_id, tier, floor
	)
	branch_reports.append(fate_report)
	if not bool(fate_report.get("ok", false)):
		errors.append_array(fate_report.get("errors", []))
	else:
		grants.append_array(fate_report.get("grants", []))

	if tier == TIER_NORMAL:
		var consumable_candidates := _candidates(
			pool_id, floor, "consumable", false
		)
		if consumable_candidates.is_empty():
			errors.append(_error("EMPTY_CONSUMABLE_POOL", "没有可用消耗品"))
		else:
			var consumable_count := _stable_count(
				2, 3, run_seed, room_id, chest_id, "normal_consumables_count"
			)
			var consumable_report := _resolve_fixed_items(
				consumable_candidates, consumable_count, run_seed, room_id, chest_id, "normal_consumables", floor
			)
			branch_reports.append(consumable_report)
			if not bool(consumable_report.get("ok", false)):
				errors.append_array(consumable_report.get("errors", []))
			else:
				grants.append_array(consumable_report.get("grants", []))
	else:
		var other_candidates := _candidates(
			pool_id, floor, "", true
		)
		if other_candidates.is_empty():
			errors.append(_error("EMPTY_OTHER_POOL", "没有可用的非枪物品"))
		else:
			var other_count := _stable_count(
				5, 8, run_seed, room_id, chest_id, "advanced_other_count"
			)
			var other_report := _resolve_fixed_items(
				other_candidates, other_count, run_seed, room_id, chest_id, "advanced_other", floor
			)
			branch_reports.append(other_report)
			if not bool(other_report.get("ok", false)):
				errors.append_array(other_report.get("errors", []))
			else:
				grants.append_array(other_report.get("grants", []))

		var gun_candidates := _gun_candidates(pool_id, floor)
		if gun_candidates.is_empty():
			errors.append(_error("EMPTY_GUN_POOL", "没有可用的非近战枪械"))
		else:
			var gun_report := _resolve_fixed_items(
				gun_candidates, 1, run_seed, room_id, chest_id, "advanced_gun", floor
			)
			branch_reports.append(gun_report)
			if not bool(gun_report.get("ok", false)):
				errors.append_array(gun_report.get("errors", []))
			else:
				grants.append_array(gun_report.get("grants", []))

	# 关卡保底（2026-11-09）：由 `clear_drops.room_guarantees` 在配置宝箱时写进 `guaranteed_items`。
	# 与上面的档位分支**互相独立**：不是「替换掉落」，而是「额外保证」。
	# 用**无类型** Array 接：`RewardService.resolve()` 返回的 grants 是普通 Array，
	# 强转 `Array[Dictionary]` 在「无保底条目」的空数组上会失败并中断解析。
	var guaranteed_grants: Array = []
	var guaranteed_report := _resolve_guaranteed_items(
		chest_config, run_seed, room_id, chest_id, floor
	)
	branch_reports.append(guaranteed_report)
	if not bool(guaranteed_report.get("ok", false)):
		errors.append_array(guaranteed_report.get("errors", []))
	else:
		guaranteed_grants = guaranteed_report.get("grants", []) as Array

	result["ok"] = errors.is_empty()
	# ⚠ 顺序：先 `_unit_grants` 把普通奖励拍成单件，**之后**再接保底。
	# 保底条目自带数量（如 100 发弹药），绝不能过 `_unit_grants`（那会把 100 拍成 1）。
	var stabilized := _stabilize_grants(_unit_grants(grants), room_id, chest_id)
	for grant in guaranteed_grants:
		stabilized.append(grant)
	result["grants"] = stabilized
	result["errors"] = errors
	result["tier"] = tier
	result["quality"] = str(chest_config.get("quality", "common"))
	result["branch_reports"] = branch_reports
	return result


## 关卡保底条目解析（2026-11-09）。`chest_config.guaranteed_items` 是**已定好物与数量**的列表，
## 由 `ClearDropService` 在配置宝箱时按本局种子算好（含「两个候选房随机挑一间」「两把枪随机挑一把」）。
##
## 本函数只负责翻译成标准 grants，不做任何掷骰 —— 「抽哪一间 / 抽哪把枪」的确定性必须在
## 上游一次算清，否则同一只箱子读档重开时可能换内容。
static func _resolve_guaranteed_items(
	chest_config: Dictionary,
	run_seed: int,
	room_id: String,
	chest_id: String,
	floor_level: int
) -> Dictionary:
	var items := chest_config.get("guaranteed_items", []) as Array
	if items.is_empty():
		return {"ok": true, "grants": []}
	var entries: Array = []
	for raw in items:
		var guaranteed := raw as Dictionary
		var item_id := str(guaranteed.get("item_id", ""))
		if item_id.is_empty():
			continue
		var entry := {
			"kind": _SPEC.KIND_ITEM,
			"item_id": item_id,
			"count": maxi(1, int(guaranteed.get("count", 1))),
			"merge_same_item": false,
		}
		# 保底枪的品质是**定值**（例如远征01 要求最低品质 = 蓝），不参与随机品质分布。
		var grade := str(guaranteed.get("grade", ""))
		if not grade.is_empty():
			entry["forced_grade"] = grade
		entries.append(entry)
	if entries.is_empty():
		return {"ok": true, "grants": []}
	return _REWARD_SERVICE.resolve({
		"spec_id": "chest:%s:%s:guaranteed" % [room_id, chest_id],
		"entries": entries,
	}, {
		"seed": run_seed,
		"floor": maxi(1, floor_level),
		"salt": _salt(room_id, chest_id, "guaranteed"),
	})


static func _tier_for(config: Dictionary) -> String:
	var explicit := str(config.get("chest_tier", "")).to_lower()
	if explicit == TIER_NORMAL or explicit == TIER_ADVANCED:
		return explicit
	var quality := str(config.get("quality", "")).to_lower()
	if quality == "rare" or quality == "epic":
		return TIER_ADVANCED
	if not quality.is_empty():
		return TIER_NORMAL
	return TIER_NORMAL


static func _resolve_fate(
	config: Dictionary,
	run_seed: int,
	room_id: String,
	chest_id: String,
	tier: String,
	floor_level: int
) -> Dictionary:
	var chance := FATE_CHANCE if tier == TIER_NORMAL else 1.0
	var spec := {
		"spec_id": "chest:%s:%s:fate" % [room_id, chest_id],
		"entries": [{
			"kind": _SPEC.KIND_ITEM,
			"item_id": FATE_ITEM_ID,
			"count": 1,
			"chance": chance,
			"merge_same_item": false,
		}],
	}
	var report := _REWARD_SERVICE.resolve(spec, {
		"seed": run_seed,
		"floor": maxi(1, floor_level),
		"salt": _salt(room_id, chest_id, "fate"),
	})
	if not bool(report.get("ok", false)):
		return report
	var fate_id := "chest:%s:%s:fate" % [room_id, chest_id]
	for grant_value in report.get("grants", []):
		var grant := grant_value as Dictionary
		grant["fate_pickup_id"] = fate_id
		grant["fate_source"] = "treasure_chest"
		grant["source_room_id"] = room_id
		grant["source_chest_id"] = chest_id
		var item := grant.get("item", {}) as Dictionary
		item["fate_pickup_id"] = fate_id
		item["fate_source"] = "treasure_chest"
		item["source_room_id"] = room_id
		item["source_chest_id"] = chest_id
		grant["item"] = item
	return report


static func _stable_count(
	minimum: int,
	maximum: int,
	run_seed: int,
	room_id: String,
	chest_id: String,
	branch: String
) -> int:
	var span := maxi(1, maximum - minimum + 1)
	var value := absi(hash("%d|%s|%s|%s" % [run_seed, room_id, chest_id, branch]))
	return minimum + (value % span)


static func _resolve_fixed_items(
	candidates: Array[Dictionary],
	draws: int,
	run_seed: int,
	room_id: String,
	chest_id: String,
	branch: String,
	floor_level: int
) -> Dictionary:
	return _REWARD_SERVICE.resolve({
		"spec_id": "chest:%s:%s:%s" % [room_id, chest_id, branch],
		"entries": [{
			"kind": _SPEC.KIND_WEIGHTED,
			"draws": draws,
			"options": _weighted_options(candidates),
			"merge_same_item": false,
		}],
	}, {
		"seed": run_seed,
		"floor": maxi(1, floor_level),
		"salt": _salt(room_id, chest_id, branch),
	})


static func _weighted_options(candidates: Array[Dictionary]) -> Array:
	var options: Array = []
	for candidate in candidates:
		options.append({
			"weight": maxf(0.001, float(candidate.get("loot_weight", 1.0))),
			"kind": _SPEC.KIND_ITEM,
			"item_id": str(candidate.get("id", candidate.get("item_id", ""))),
			"count": 1,
			"merge_same_item": false,
		})
	return options


static func _candidates(
	pool_id: String,
	floor: int,
	type_filter: String,
	non_gun_only: bool
) -> Array[Dictionary]:
	var registry := ItemRegistry.get_instance()
	var source := registry.get_all_items()
	var out: Array[Dictionary] = []
	for raw in source:
		var item := raw as Dictionary
		if _excluded(item):
			continue
		if not type_filter.is_empty() and str(item.get("type", "")) != type_filter:
			continue
		if non_gun_only and str(item.get("type", "")) == "weapon":
			continue
		if str(item.get("type", "")) == "weapon":
			continue
		var weight := _pool_weight(item, pool_id)
		if not pool_id.is_empty() and weight <= 0.0:
			continue
		item["loot_weight"] = weight if weight > 0.0 else 1.0
		out.append(item)
	if out.is_empty() and not pool_id.is_empty():
		return _candidates("", floor, type_filter, non_gun_only)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return out


static func _gun_candidates(pool_id: String, floor: int) -> Array[Dictionary]:
	var registry := ItemRegistry.get_instance()
	var out: Array[Dictionary] = []
	for raw in registry.get_items_by_type("weapon"):
		var item := raw as Dictionary
		if _excluded(item):
			continue
		if str(item.get("subtype", "")) != "gun_body" and not (item.get("tags", []) as Array).has("gun_body"):
			continue
		if _WEAPON_BULLET_DROP.is_melee_weapon(item):
			continue
		var weight := _pool_weight(item, pool_id)
		if not pool_id.is_empty() and weight <= 0.0:
			continue
		item["loot_weight"] = weight if weight > 0.0 else 1.0
		out.append(item)
	if out.is_empty() and not pool_id.is_empty():
		return _gun_candidates("", floor)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return out


static func _pool_weight(item: Dictionary, pool_id: String) -> float:
	if pool_id.is_empty():
		return 1.0
	var weights := item.get("floor_loot_weights", {}) as Dictionary
	return maxf(0.0, float(weights.get(pool_id, 0.0)))


static func _excluded(item: Dictionary) -> bool:
	var item_id := str(item.get("id", item.get("item_id", "")))
	if item_id == FATE_ITEM_ID:
		return true
	var item_type := str(item.get("type", ""))
	if item_type == "key" or item_type == "fate_pickup":
		return true
	var tags := item.get("tags", []) as Array
	return tags.has("key") or tags.has("fate_pickup") or tags.has("world_credential_only")


static func _unit_grants(grants: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in grants:
		var grant := raw.duplicate(true)
		grant["count"] = 1
		out.append(grant)
	return out


static func _stabilize_grants(grants: Array[Dictionary], room_id: String, chest_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(grants.size()):
		var grant := grants[index].duplicate(true)
		var item := grant.get("item", {}) as Dictionary
		if str(item.get("type", "")) == "weapon":
			var item_id := str(grant.get("item_id", item.get("id", "weapon")))
			var stable_id := "chest_wpn_%08x_%02d" % [
				absi(hash("%s|%s|%s|%d" % [room_id, chest_id, item_id, index])), index,
			]
			item["weapon_instance_id"] = stable_id
			item["created_transaction_id"] = "chest:%s:%s:%d" % [room_id, chest_id, index]
			var nested := item.get("weapon_instance", {}) as Dictionary
			nested["weapon_instance_id"] = stable_id
			nested["created_transaction_id"] = item["created_transaction_id"]
			item["weapon_instance"] = nested
			grant["item"] = item
		out.append(grant)
	return out


static func _salt(room_id: String, chest_id: String, branch: String) -> String:
	return "treasure_chest|%s|%s|%s" % [room_id, chest_id, branch]


static func _error(code: String, detail: String) -> Dictionary:
	return {"code": code, "path": "chest", "detail": detail}
