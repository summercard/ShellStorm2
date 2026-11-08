extends Node
## 12只唯一精英的跨局档案事实源：预约、成长、逃脱、死亡与夺械转译。
## 静态身份、投放与表现配置由 EliteContentCatalog 独立持有。

signal roster_changed(elite_id: String, record: Dictionary)
signal elite_reserved(elite_id: String, encounter_id: String)
signal elite_settled(elite_id: String, outcome: String, record: Dictionary)

const ROSTER_VERSION := 2
const MAX_XP_EVENT_IDS := 128
const VALID_STATES := [
	"Newborn", "Escaped", "Equipped", "Growing", "RevengeHunter",
	"RegionalBoss", "QuasiBoss", "Killed", "Defeated",
]

const DEFINITIONS := EliteContentCatalog.DEFINITIONS

var _definitions_by_id: Dictionary = {}
var _reservations_by_encounter: Dictionary = {}


func _ready() -> void:
	add_to_group("elite_archive")
	for definition in DEFINITIONS:
		_definitions_by_id[str(definition["elite_id"])] = definition.duplicate(true)
	_ensure_roster()
	_clear_stale_reservations()


func get_definition(elite_id: String) -> Dictionary:
	return (_definitions_by_id.get(elite_id, {}) as Dictionary).duplicate(true)


func get_all_elites() -> Array[Dictionary]:
	_ensure_roster()
	var result: Array[Dictionary] = []
	for definition in DEFINITIONS:
		var elite_id := str(definition["elite_id"])
		var merged := definition.duplicate(true)
		merged.merge(_get_record(elite_id), true)
		result.append(merged)
	return result


func get_record(elite_id: String) -> Dictionary:
	if not _definitions_by_id.has(elite_id):
		return {}
	var merged := get_definition(elite_id)
	merged.merge(_get_record(elite_id), true)
	return merged


func get_encountered_elites() -> Array[Dictionary]:
	var encountered: Array[Dictionary] = []
	for record in get_all_elites():
		if (
			int(record.get("encounter_count", 0)) > 0
			or int(record.get("escape_count", 0)) > 0
			or int(record.get("death_count", 0)) > 0
		):
			encountered.append(record)
	return encountered


func get_bounty_currency(elite_id: String) -> int:
	var definition := get_definition(elite_id)
	var record := _get_record(elite_id)
	return _bounty_currency(
		definition.get("growth_profile", {}) as Dictionary,
		clampi(int(record.get("bounty_reward_level", 0)), 0, 5)
	)


func select_and_reserve(seed_value: int, floor_number: int, encounter_id: String) -> Dictionary:
	_ensure_roster()
	if encounter_id.is_empty():
		return {"success": false, "reason": "missing_encounter_id"}
	if _reservations_by_encounter.has(encounter_id):
		return get_record(str(_reservations_by_encounter[encounter_id]))
	var eligible: Array[String] = []
	for definition in EliteContentCatalog.get_deployable_for_floor(floor_number, seed_value):
		var elite_id := str(definition["elite_id"])
		var record := _get_record(elite_id)
		if str(record.get("state", "Newborn")) == "Killed":
			continue
		var reserved_encounter := str(record.get("reserved_encounter_id", ""))
		if reserved_encounter.is_empty():
			eligible.append(elite_id)
	if eligible.is_empty():
		return {"success": false, "reason": "roster_exhausted_or_reserved"}
	eligible.sort()
	var mixed_seed := seed_value ^ hash(encounter_id) ^ (floor_number * 104729)
	var index := posmod(mixed_seed, eligible.size())
	var elite_id := eligible[index]
	if not reserve(elite_id, encounter_id, floor_number):
		return {"success": false, "reason": "reservation_failed"}
	return get_record(elite_id)


func reserve(elite_id: String, encounter_id: String, floor_number: int) -> bool:
	if not _definitions_by_id.has(elite_id) or encounter_id.is_empty():
		return false
	var record := _get_record(elite_id)
	if str(record.get("state", "Newborn")) == "Killed":
		return false
	var current := str(record.get("reserved_encounter_id", ""))
	if not current.is_empty() and current != encounter_id:
		return false
	if current == encounter_id:
		return true
	record["reserved_encounter_id"] = encounter_id
	record["reservation_confirmed"] = false
	record["last_floor_number"] = floor_number
	record["last_outcome"] = "reserved"
	if not _commit_record(elite_id, record, "elite_reserve:%s" % elite_id):
		return false
	_reservations_by_encounter[encounter_id] = elite_id
	elite_reserved.emit(elite_id, encounter_id)
	return true


func confirm_reservation(elite_id: String, encounter_id: String) -> bool:
	if encounter_id.is_empty() or not _definitions_by_id.has(elite_id):
		return false
	var record := _get_record(elite_id)
	if str(record.get("reserved_encounter_id", "")) != encounter_id:
		return false
	if bool(record.get("reservation_confirmed", false)):
		return true
	record["reservation_confirmed"] = true
	record["encounter_count"] = int(record.get("encounter_count", 0)) + 1
	record["last_encounter_at_unix"] = int(Time.get_unix_time_from_system())
	record["last_outcome"] = "active"
	if _commit_record(elite_id, record, "elite_confirm:%s" % elite_id):
		roster_changed.emit(elite_id, get_record(elite_id))
		return true
	return false


func settle(elite_id: String, encounter_id: String, outcome: String, context: Dictionary = {}, runtime_snapshot: Dictionary = {}) -> bool:
	if outcome not in ["killed", "escaped", "despawned", "defeated"]:
		return false
	var record := _migrate_record(_get_record(elite_id))
	var xp_before := int(record.get("xp", 0))
	var level_before := clampi(int(record.get("level", 1)), 1, _level_cap(elite_id))
	var xp_events: Array = (record.get("xp_event_ids", []) as Array).duplicate(true)
	var xp_event_id := str(context.get("xp_event_id", ""))
	if not xp_event_id.is_empty() and xp_events.has(xp_event_id):
		return false
	if str(record.get("reserved_encounter_id", "")) != encounter_id:
		return false
	if outcome == "killed":
		record["state"] = "Killed"
		record["death_count"] = int(record.get("death_count", 0)) + 1
		record["bounty_reward_level"] = maxi(1, int(record.get("bounty_reward_level", 0)))
	elif outcome == "escaped":
		var escape_count := int(record.get("escape_count", 0)) + 1
		record["escape_count"] = escape_count
		if elite_id == "elite_arms_taker":
			# 收租人每次出现的稳定 ID 就是一次且仅一次的撤退 XP 事件。
			# 不能使用 encounter_id：同一 run 的多次 appearance 共用 encounter，
			# 会让后续撤退被幂等检查吞掉，或把 XP 归到错误的事件上。
			_apply_xp_event(record, xp_event_id if not xp_event_id.is_empty() else "%s:escape" % encounter_id, "escape")
		else:
			record["level"] = mini(12, level_before + 1)
			_capture_stolen_module(record, context.get("weapon_snapshot", {}) as Dictionary)
		record["state"] = _state_for_growth(int(record["level"]), escape_count)
		record["bounty_reward_level"] = mini(5, 1 + int(escape_count / 2))
	elif outcome == "defeated":
		record["state"] = "Defeated"
		record["defeat_count"] = int(record.get("defeat_count", 0)) + 1
		# 战败掉落与剩余库存同属结算事务；只接受 Dungeon3D 已经按原顺序
		# 计算出的完整条目，避免先写档案、后删库存造成半结算状态。
		var remaining_inventory: Variant = context.get("defeat_inventory_remaining", null)
		if remaining_inventory is Array:
			record["stolen_items"] = (remaining_inventory as Array).duplicate(true)
	else:
		record["state"] = str(record.get("state", "Newborn"))
	if elite_id == "elite_arms_taker" and bool(context.get("killed_player", false)):
		_apply_xp_event(record, "%s:player_kill" % encounter_id, "player_kill")
	if not xp_event_id.is_empty():
		xp_events = record.get("xp_event_ids", []) as Array
		if not xp_events.has(xp_event_id):
			xp_events.append(xp_event_id)
		record["xp_event_ids"] = xp_events
	record["last_level_before"] = level_before
	record["last_level_after"] = int(record.get("level", level_before))
	record["last_xp_gain"] = int(record.get("xp", 0)) - xp_before
	if context.get("roaming_encounter", null) is Dictionary:
		record["roaming_encounter"] = (context["roaming_encounter"] as Dictionary).duplicate(true)
	record["last_outcome"] = outcome
	record["last_settled_at_unix"] = int(Time.get_unix_time_from_system())
	record["reserved_encounter_id"] = ""
	record["reservation_confirmed"] = false
	var history := (record.get("history", {}) as Dictionary).duplicate(true)
	if bool(context.get("killed_player", false)):
		history["killed_player_count"] = int(history.get("killed_player_count", 0)) + 1
	history["last_context"] = _sanitize_context(context)
	record["history"] = history
	var reason := "elite_settle:%s:%s" % [elite_id, outcome]
	var committed := _commit_record(elite_id, record, reason) if runtime_snapshot.is_empty() else BaseManager.commit_elite_and_runtime_checkpoint(elite_id, record, runtime_snapshot, reason)
	if not committed:
		return false
	_reservations_by_encounter.erase(encounter_id)
	roster_changed.emit(elite_id, get_record(elite_id))
	elite_settled.emit(elite_id, outcome, get_record(elite_id))
	return true


func commit_run_record(elite_id: String, run_state: Dictionary, snapshot: Dictionary, receipt: Dictionary = {}) -> bool:
	if not _definitions_by_id.has(elite_id):
		return false
	var record := _get_record(elite_id)
	if not run_state.is_empty():
		record["roaming_encounter"] = run_state.duplicate(true)
	if not receipt.is_empty():
		var receipt_id := str(receipt.get("receipt_id", ""))
		var receipts: Array = (record.get("rent_receipts", []) as Array).duplicate(true)
		if receipt_id.is_empty() or receipts.has(receipt_id):
			return false
		receipts.append(receipt_id)
		record["rent_receipts"] = receipts
		if elite_id == "elite_arms_taker" and str(receipt.get("kind", "")) == "escape":
			# 中间 appearance 的撤退走 commit_run_record，不走 settle；因此这里
			# 必须消费同一个 appearance 稳定 ID，保证每次出现恰好获得一次 XP。
			var escape_event_id := str(receipt.get("xp_event_id", receipt_id))
			_apply_xp_event(record, escape_event_id, "escape")
		if receipt.get("kind", "") == "item":
			var items: Array = (record.get("stolen_items", []) as Array).duplicate(true)
			var stolen_item := (receipt["item"] as Dictionary).duplicate(true)
			# 枪械必须以完整 WeaponInstance 数据进入精英档案；普通物品保持原始字典。
			if str(stolen_item.get("type", "")) == "weapon":
				stolen_item = WeaponInstance.ensure_weapon_item(stolen_item)
			var source_encounter_id := str(receipt.get("source_encounter_id", ""))
			var entry := {
				"item": stolen_item,
				"count": 1,
				"receipt_id": receipt_id,
				"source_encounter_id": source_encounter_id,
				"source_run_id": str(receipt.get("source_run_id", "")),
				"source_floor_number": int(receipt.get("source_floor_number", 0)),
			}
			items.append(entry)
			record["stolen_items"] = items
		elif receipt.get("kind", "") == "currency":
			record["stolen_currency"] = int(record.get("stolen_currency", 0)) + int(receipt["amount"])
	if not BaseManager.commit_elite_and_runtime_checkpoint(elite_id, record, snapshot, "elite_run:%s" % elite_id):
		return false
	roster_changed.emit(elite_id, get_record(elite_id))
	return true


## 消费精英自己的物品库存。消费事实与运行时 checkpoint 共用一个原子提交，
## 调用方可以先在实体上应用治疗，失败时再按返回值恢复实体状态。
func consume_elite_item(
	elite_id: String,
	encounter_id: String,
	item_id: String,
	count: int = 1,
	transaction_id: String = "",
	runtime_snapshot: Dictionary = {}
) -> Dictionary:
	if not _definitions_by_id.has(elite_id) or item_id.is_empty() or count <= 0:
		return {"success": false, "reason": "invalid_item_transaction"}
	var record := _migrate_record(_get_record(elite_id))
	var transactions: Array = (record.get("item_consumption_transaction_ids", []) as Array).duplicate(true)
	if not transaction_id.is_empty() and transactions.has(transaction_id):
		return {"success": true, "already_committed": true, "transaction_id": transaction_id}
	var whitelist: Array = get_definition(elite_id).get("growth_profile", {}).get("item_use_whitelist", []) as Array
	if not whitelist.is_empty() and item_id not in whitelist:
		return {"success": false, "reason": "item_not_allowed"}
	if not encounter_id.is_empty() and str(record.get("reserved_encounter_id", "")) != encounter_id:
		return {"success": false, "reason": "encounter_mismatch"}
	var remaining := count
	var items: Array = (record.get("stolen_items", []) as Array).duplicate(true)
	var consumed := 0
	for index in items.size():
		if remaining <= 0:
			break
		var raw_entry: Variant = items[index]
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var item := entry.get("item", {}) as Dictionary
		if str(item.get("id", "")) != item_id:
			continue
		var available := maxi(0, int(entry.get("count", 0)))
		if available <= 0:
			continue
		var take := mini(available, remaining)
		entry["count"] = available - take
		if int(entry["count"]) <= 0:
			items.remove_at(index)
			index -= 1
		consumed += take
		remaining -= take
	if consumed < count:
		return {"success": false, "reason": "insufficient_item", "available": consumed}
	record["stolen_items"] = items
	if not transaction_id.is_empty():
		transactions.append(transaction_id)
		while transactions.size() > MAX_XP_EVENT_IDS:
			transactions.pop_front()
		record["item_consumption_transaction_ids"] = transactions
	record["last_item_consumed_id"] = item_id
	record["last_item_consumed_count"] = count
	record["last_item_consumption_transaction_id"] = transaction_id
	var reason := "elite_item:%s:%s" % [elite_id, item_id]
	var committed := false
	if runtime_snapshot.is_empty():
		committed = _commit_record(elite_id, record, reason)
	else:
		committed = BaseManager.commit_elite_and_runtime_checkpoint(elite_id, record, runtime_snapshot, reason)
	if not committed:
		return {"success": false, "reason": "save_failed", "transaction_id": transaction_id}
	roster_changed.emit(elite_id, get_record(elite_id))
	return {
		"success": true,
		"already_committed": false,
		"consumed": consumed,
		"item_id": item_id,
		"transaction_id": transaction_id,
	}


## 只返回下一次非当前遭遇可挂载的完整枪械实例；当前遭遇刚夺取的枪械
## 通过 source_encounter_id 排除，因此本关不会出现「刚收走就立即挂上」的视觉与玩法穿透。
func get_equipped_weapons_for_encounter(
	elite_id: String,
	encounter_id: String,
	max_weapons: int = 2
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var record := get_record(elite_id)
	var stolen_items: Variant = record.get("stolen_items", [])
	if not stolen_items is Array:
		return result
	for raw_entry in stolen_items as Array:
		if result.size() >= maxi(0, max_weapons):
			break
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var item := entry.get("item", {}) as Dictionary
		if str(item.get("type", "")) != "weapon" or int(entry.get("count", 0)) <= 0:
			continue
		var source_encounter := str(entry.get("source_encounter_id", ""))
		if not encounter_id.is_empty() and not source_encounter.is_empty() and source_encounter == encounter_id:
			continue
		var normalized := WeaponInstance.ensure_weapon_item(item)
		if not normalized.is_empty():
			result.append(normalized)
	return result


func apply_archive_to_enemy_config(config: Dictionary, elite_snapshot: Dictionary) -> Dictionary:
	if elite_snapshot.is_empty() or bool(elite_snapshot.get("success", true)) == false:
		return config
	var result := config.duplicate(true)
	var elite_id := str(elite_snapshot.get("elite_id", ""))
	var level := clampi(int(elite_snapshot.get("level", 1)), 1, 12)
	var growth_profile := (elite_snapshot.get("growth_profile", {}) as Dictionary).duplicate(true)
	var bounty_tier := clampi(int(elite_snapshot.get("bounty_reward_level", 0)), 0, 5)
	result["is_elite"] = true
	result["elite_id"] = str(elite_snapshot.get("elite_id", ""))
	result["elite_behavior_id"] = str(elite_snapshot.get("behavior_id", ""))
	result["elite_level"] = level
	result["encounter_instance_id"] = str(elite_snapshot.get("reserved_encounter_id", ""))
	result["enemy_type"] = str(elite_snapshot.get("base_enemy_id", result.get("enemy_type", "melee_chaser")))
	result["name"] = str(elite_snapshot.get("name", result.get("name", "唯一精英")))
	result["modifier_id_en"] = str(elite_snapshot.get("modifier_id", "Elite.Huge"))
	result["elite_growth_hp_mult"] = 1.0 + float(level - 1) * float(growth_profile.get("hp_per_level", 0.08))
	result["elite_growth_damage_mult"] = 1.0 + float(level - 1) * float(growth_profile.get("damage_per_level", 0.045))
	result["elite_growth_profile"] = growth_profile
	result["elite_translation_id"] = str(elite_snapshot.get("translation", ""))
	result["stolen_modules"] = (elite_snapshot.get("stolen_modules", []) as Array).duplicate(true)
	result["elite_archive_state"] = str(elite_snapshot.get("state", "Newborn"))
	result["elite_escape_count"] = int(elite_snapshot.get("escape_count", 0))
	result["elite_bounty_tier"] = bounty_tier
	result["elite_bounty_currency"] = _bounty_currency(growth_profile, bounty_tier)
	result["presentation_asset_id"] = str(elite_snapshot.get("presentation_asset_id", ""))
	result["presentation_scene"] = str(elite_snapshot.get("presentation_scene", ""))
	result["elite_health_bar_profile"] = (elite_snapshot.get("health_bar_profile", {}) as Dictionary).duplicate(true)
	result["elite_deployment_status"] = str(elite_snapshot.get("deployment_status", EliteContentCatalog.DESIGN_ONLY))
	result["elite_eligible_floor_numbers"] = (elite_snapshot.get("eligible_floor_numbers", []) as Array).duplicate()
	var encounter_id := str(result.get("encounter_instance_id", ""))
	if elite_id == "elite_arms_taker" and bool(growth_profile.get("weapon_equip_next_encounter", false)):
		result["elite_equipped_weapons"] = get_equipped_weapons_for_encounter(elite_id, encounter_id, 2)
	else:
		result["elite_equipped_weapons"] = []
	result["elite_same_faction_as_normal_enemies"] = bool(growth_profile.get("same_faction_as_normal_enemies", false))
	result["elite_can_attack_normal_enemies"] = bool(growth_profile.get("can_attack_normal_enemies", false))
	return result


func reset_roster_for_test() -> void:
	if BaseManager == null:
		return
	BaseManager.replace_elite_archive_records_for_test({})
	_reservations_by_encounter.clear()
	_ensure_roster()


func _ensure_roster() -> void:
	if BaseManager == null:
		return
	var defaults := {}
	for definition in DEFINITIONS:
		var elite_id := str(definition["elite_id"])
		defaults[elite_id] = _default_record(elite_id)
	BaseManager.ensure_elite_archive_records(defaults)


func _default_record(elite_id: String) -> Dictionary:
	var definition := get_definition(elite_id)
	return {
		"elite_id": elite_id, "archive_version": ROSTER_VERSION,
		"level": 1, "state": "Newborn",
		"modifiers": [str(definition.get("modifier_id", ""))], "stolen_modules": [],
		"encounter_count": 0, "escape_count": 0, "death_count": 0,
		"bounty_reward_level": 0, "reserved_encounter_id": "",
		"reservation_confirmed": false, "last_floor_number": 0,
		"last_outcome": "unseen", "last_encounter_at_unix": 0,
		"last_settled_at_unix": 0, "history": {"killed_player_count": 0},
	}


func _get_record(elite_id: String) -> Dictionary:
	_ensure_roster()
	if BaseManager == null:
		return _default_record(elite_id)
	return _migrate_record(BaseManager.get_elite_archive_record(elite_id, _default_record(elite_id)))


func _level_cap(elite_id: String) -> int:
	var profile := get_definition(elite_id).get("growth_profile", {}) as Dictionary
	return maxi(1, int(profile.get("level_cap", 12)))


func _level_for_xp(elite_id: String, xp: int) -> int:
	var profile := get_definition(elite_id).get("growth_profile", {}) as Dictionary
	var thresholds := profile.get("xp_thresholds", [0]) as Array
	var level := 1
	for index in mini(thresholds.size(), _level_cap(elite_id)):
		if xp >= int(thresholds[index]):
			level = index + 1
	return level


func _migrate_record(source: Dictionary) -> Dictionary:
	var result := _default_record(str(source.get("elite_id", "")))
	result.merge(source, true)
	var elite_id := str(result.get("elite_id", ""))
	if elite_id == "elite_arms_taker" and int(source.get("archive_version", 1)) < 2:
		var thresholds := get_definition(elite_id).get("growth_profile", {}).get("xp_thresholds", [0]) as Array
		var legacy_level := clampi(int(source.get("level", 1)), 1, thresholds.size())
		result["xp"] = maxi(int(source.get("xp", 0)), int(thresholds[legacy_level - 1]))
		result["xp_migrated_from_level"] = legacy_level
	result["archive_version"] = ROSTER_VERSION
	if elite_id == "elite_arms_taker":
		result["level"] = _level_for_xp(elite_id, int(result.get("xp", 0)))
	return result


func _apply_xp_event(record: Dictionary, event_id: String, reason: String) -> bool:
	if event_id.is_empty() or str(record.get("elite_id", "")) != "elite_arms_taker":
		return false
	var ids := (record.get("xp_event_ids", []) as Array).duplicate()
	if ids.has(event_id):
		return false
	var profile := get_definition(str(record["elite_id"])).get("growth_profile", {}) as Dictionary
	var reward := maxi(0, int((profile.get("xp_rewards", {}) as Dictionary).get(reason, 0)))
	if reward <= 0:
		return false
	var before := int(record.get("level", 1))
	record["xp"] = int(record.get("xp", 0)) + reward
	record["level"] = _level_for_xp(str(record["elite_id"]), int(record["xp"]))
	ids.append(event_id)
	while ids.size() > MAX_XP_EVENT_IDS:
		ids.pop_front()
	record["xp_event_ids"] = ids
	record["last_xp_event_id"] = event_id
	record["last_xp_reason"] = reason
	record["last_xp_gain"] = reward
	record["last_level_before"] = before
	record["last_level_after"] = record["level"]
	if int(record["level"]) > before:
		record["last_level_up_reason"] = reason
	return true


## All XP writes use the archive transaction boundary; failed saves never advance XP.
func award_xp(elite_id: String, event_id: String, reason: String) -> bool:
	if not _definitions_by_id.has(elite_id):
		return false
	var record := _get_record(elite_id)
	if (record.get("xp_event_ids", []) as Array).has(event_id):
		return true
	if not _apply_xp_event(record, event_id, reason):
		return false
	if not _commit_record(elite_id, record, "elite_xp:%s:%s" % [elite_id, reason]):
		return false
	roster_changed.emit(elite_id, get_record(elite_id))
	return true


func _commit_record(elite_id: String, record: Dictionary, reason: String) -> bool:
	return BaseManager != null and BaseManager.commit_elite_archive_record(elite_id, record, reason)


func _clear_stale_reservations() -> void:
	if BaseManager == null:
		return
	var active_checkpoint := BaseManager.get_active_run_checkpoint()
	var active_run_id := str(active_checkpoint.get("run_id", active_checkpoint.get("checkpoint_id", "")))
	var changed := false
	var records := BaseManager.get_elite_archive_records_snapshot()
	for definition in DEFINITIONS:
		var elite_id := str(definition["elite_id"])
		var record := (records.get(elite_id, _default_record(elite_id)) as Dictionary).duplicate(true)
		var encounter_id := str(record.get("reserved_encounter_id", ""))
		if encounter_id.is_empty():
			continue
		if not active_run_id.is_empty() and encounter_id.begins_with(active_run_id + ":"):
			_reservations_by_encounter[encounter_id] = elite_id
			continue
		record["reserved_encounter_id"] = ""
		record["reservation_confirmed"] = false
		record["last_outcome"] = "stale_reservation_released"
		records[elite_id] = record
		changed = true
	if changed:
		BaseManager.commit_elite_archive_records(records, "elite_stale_reservation_cleanup")


func _state_for_growth(level: int, escape_count: int) -> String:
	if level >= 10: return "QuasiBoss"
	if level >= 8: return "RegionalBoss"
	if escape_count >= 4: return "RevengeHunter"
	if level >= 4: return "Growing"
	return "Escaped"


func _capture_stolen_module(record: Dictionary, weapon_snapshot: Dictionary) -> void:
	if weapon_snapshot.is_empty():
		return
	var content_id := str(weapon_snapshot.get(
		"content_id",
		weapon_snapshot.get("weapon_id", weapon_snapshot.get("gun_id", ""))
	))
	if content_id.is_empty():
		return
	if content_id.begins_with("bp_"):
		content_id = content_id.replace("bp_", "weapon_")
	var safe_traits: Array[String] = []
	for value in weapon_snapshot.get("bullet_tags", []) as Array:
		var bullet_trait := str(value)
		if bullet_trait in ["explosive", "piercing", "bounce", "homing"] and bullet_trait not in safe_traits:
			safe_traits.append(bullet_trait)
	var fire_rate := maxf(0.0, float(weapon_snapshot.get("fire_rate", 0.0)))
	var module := {
		"module_id": content_id,
		"source_kind": str(weapon_snapshot.get("source_kind", weapon_snapshot.get("weapon_kind", "gun_body"))),
		"content_version": int(weapon_snapshot.get("content_version", 1)),
		"translated_skill_id": str(get_definition(str(record.get("elite_id", ""))).get("translation", "")),
		"shot_count_budget": clampi(int(weapon_snapshot.get("projectile_count", 1)), 1, 3),
		"fire_rate_band": "fast" if fire_rate >= 5.0 else "standard" if fire_rate >= 2.0 else "slow",
		"bullet_traits": safe_traits,
	}
	var modules := (record.get("stolen_modules", []) as Array).duplicate(true)
	for existing in modules:
		if existing is Dictionary and str((existing as Dictionary).get("module_id", "")) == content_id:
			return
	modules.append(module)
	while modules.size() > 3:
		modules.pop_front()
	record["stolen_modules"] = modules
	if str(record.get("state", "")) not in ["RegionalBoss", "QuasiBoss"]:
		record["state"] = "Equipped"


func _bounty_currency(growth_profile: Dictionary, bounty_tier: int) -> int:
	if bounty_tier <= 0:
		return 0
	var rewards := growth_profile.get("bounty_currency_by_tier", []) as Array
	if rewards.is_empty():
		return bounty_tier * 40
	return maxi(0, int(rewards[mini(bounty_tier, rewards.size()) - 1]))


func _sanitize_context(context: Dictionary) -> Dictionary:
	return {
		"floor_number": int(context.get("floor_number", 0)),
		"room_id": str(context.get("room_id", "")),
		"killed_player": bool(context.get("killed_player", false)),
	}
