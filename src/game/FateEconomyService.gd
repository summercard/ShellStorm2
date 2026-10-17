extends RefCounted
## 远征命运卡经济纯服务。
## 只接受运行时已经解析出的编成、货币规则和实际击杀收入；不读取钱包决定价格，
## 不读取未来收益解锁稀有度。每次门后报价在生成时冻结，直到该门后事务关闭。

const SCHEMA_VERSION := 3
const PRICE_FLOOR_RATIO := 0.85
const PRICE_CEILING_RATIO := 1.15
## 门后报价基准 = **刚清完那间内容房的参考收益**（不是整关平均、不是钱包）。
## 分享系数：普通卡 0.85 门收益 ⇒ 清完一间房基本只够买一张；任意三张合计 ≥ 2.55 门收益，
## 所以「一间房的收入买三张」永远不成立。高稀有度要攒 1~3 间房才买得起，构成消费抉择。
const RARITY_PRICE_SHARES: Array[float] = [0.85, 1.30, 1.85, 2.60, 3.50]
## 最低报价：防止无收益门（安全屋出门）出现白拿三张。
const MIN_CARD_PRICE := 40
const RARITY_UNLOCK_INCOME_RATIOS: Array[float] = [0.0, 0.12, 0.30, 0.55, 0.80]
const MONSTER_VARIANTS := preload("res://src/enemy3d/MonsterVariants.gd")
const REWARD_SERVICE := preload("res://src/rewards/RewardService.gd")
## 仅限制报价上限，不改星币七现行效果或生命周期。
const CARD_PRICE_CAPS := {"fate_sun_bounty": 100}

var _configured := false
var _door_count := 1
var _floor := 1
var _currency_rules: Dictionary = {}
var _strong_variant_chance := 0.0
var _reference_counts: Dictionary = {}
var _reference_income_min := 0.0
var _reference_income_expected := 0.0
var _reference_income_max := 0.0
## 按房间顺序保存的**单间参考收益**。门后报价只读其中一间，避免用整关平均
## 把首门（房间小、收益低）的卡价压低成"三张全买得起"。
var _segment_income_min: Array[float] = []
var _segment_income_expected: Array[float] = []
var _segment_income_max: Array[float] = []
var _actual_kill_income := 0
var _actual_kill_events := 0


func configure_from_runtime(
	rooms: Array, box_catalog: Dictionary, currency_rules: Dictionary, floor: int, door_count: int,
	strong_variant_chance: float = 0.0
) -> Dictionary:
	_configured = false
	_door_count = maxi(1, door_count)
	_floor = maxi(1, floor)
	_currency_rules = currency_rules.duplicate(true) if currency_rules != null else {}
	_strong_variant_chance = clampf(strong_variant_chance, 0.0, 1.0)
	_reference_counts.clear()
	_reference_income_min = 0.0
	_reference_income_expected = 0.0
	_reference_income_max = 0.0
	_segment_income_min.clear()
	_segment_income_expected.clear()
	_segment_income_max.clear()
	for room_value in rooms:
		if not room_value is Dictionary:
			continue
		var room: Dictionary = room_value as Dictionary
		var room_min := _reference_income_min
		var room_expected := _reference_income_expected
		var room_max := _reference_income_max
		var placements: Array = room.get("spawn_placements", []) as Array
		if not placements.is_empty():
			var selected_indexes := _selected_box_indexes(room.get("encounter", {}) as Dictionary, placements.size())
			for placement_index in selected_indexes:
				var placement_value: Variant = placements[placement_index]
				if placement_value is Dictionary:
					_add_box_reference(placement_value as Dictionary, box_catalog)
		else:
			_add_encounter_reference(room.get("encounter", {}) as Dictionary)
		# 单间收益 = 累计差分，保证与整关总额完全同源，不另建一套估算。
		_segment_income_min.append(maxf(0.0, _reference_income_min - room_min))
		_segment_income_expected.append(maxf(0.0, _reference_income_expected - room_expected))
		_segment_income_max.append(maxf(0.0, _reference_income_max - room_max))
	_configured = true
	return get_snapshot()


func is_configured() -> bool:
	return _configured


func actual_kill_income() -> int:
	return _actual_kill_income


func record_actual_kill_income(amount: int) -> void:
	var safe_amount := maxi(0, amount)
	if safe_amount <= 0:
		return
	_actual_kill_income += safe_amount
	_actual_kill_events += 1


func max_unlocked_rarity() -> int:
	if not _configured or _reference_income_expected <= 0.0:
		return 0
	var unlocked := 0
	for rarity in range(RARITY_UNLOCK_INCOME_RATIOS.size()):
		var threshold := int(ceil(_reference_income_expected * RARITY_UNLOCK_INCOME_RATIOS[rarity]))
		if _actual_kill_income >= threshold:
			unlocked = rarity
	return unlocked


func price_for_rarity(rarity: int, door_index: int = 1) -> int:
	if not _configured:
		return 0
	return int(price_bounds_for_rarity(rarity, door_index).get("quote", 0))


func frozen_quote_for_card(rarity: int, offer_id: int, stable_card_id: String, run_seed: int = 0) -> int:
	# offer_id 就是门序号：报价只由「第几门 + 该门基准房收益 + 种子」决定，与钱包无关。
	var bounds := price_bounds_for_rarity(rarity, offer_id)
	var minimum := int(bounds.get("min", 0))
	var maximum := int(bounds.get("max", 0))
	var quote := int(bounds.get("quote", 0))
	if minimum > 0 and maximum > minimum:
		var span := maxi(1, int((maximum - minimum) / 10.0) + 1)
		var offset: int = absi(hash("%d|%d|%d|%s" % [run_seed, offer_id, rarity, stable_card_id])) % span
		quote = minimum + offset * 10
	return mini(quote, int(CARD_PRICE_CAPS[stable_card_id])) if CARD_PRICE_CAPS.has(stable_card_id) else quote


func price_bounds_for_card(rarity: int, stable_card_id: String, door_index: int = 1) -> Dictionary:
	var bounds := price_bounds_for_rarity(rarity, door_index)
	if CARD_PRICE_CAPS.has(stable_card_id):
		var cap := int(CARD_PRICE_CAPS[stable_card_id])
		var capped_min := mini(int(bounds.get("min", cap)), cap)
		var capped_max := mini(int(bounds.get("max", cap)), cap)
		var capped_quote := mini(int(bounds.get("quote", cap)), cap)
		capped_quote = clampi(capped_quote, capped_min, maxi(capped_min, capped_max))
		return {"min": capped_min, "quote": capped_quote, "max": maxi(capped_min, capped_max)}
	return bounds


## 门序号（1 基，等于 `_fate_door_offer_id`）对应的价格基准房间。
## 第 1 门是安全屋出门、尚无击杀，沿用第 1 间内容房的收益，避免出现 10 金币白拿三张。
func price_segment_index_for_door(door_index: int) -> int:
	var count := _segment_income_expected.size()
	if count <= 0:
		return -1
	if count == 1:
		return 0
	return clampi(maxi(door_index - 1, 1), 1, count - 1)


## 某一门的报价基准 = max（该门之前刚清完那间房的参考收益，至今平均每门收益）。
## 只取单间会让小房间（收益 40）把卡价压到 50，攒下来的钱又能一次买三张；
## 取两者较大值后，报价永远跟得上"已经打到第几门"，一间房仍然只够一张。
func door_price_base(door_index: int) -> float:
	var index := price_segment_index_for_door(door_index)
	if index < 0:
		return 0.0
	var segment := _segment_income_expected[index]
	var cumulative := 0.0
	for cursor in range(index + 1):
		cumulative += _segment_income_expected[cursor]
	# 分母是**累计到的房间数**（index+1），不是门序号：第 1 门是安全屋出门，
	# 尚未清房，不能用整关总额当基准，否则首门报价会被整体收益抬高。
	var average := cumulative / float(maxi(1, index + 1))
	return maxf(segment, average)


func price_bounds_for_rarity(rarity: int, door_index: int = 1) -> Dictionary:
	if not _configured:
		return {"min": 0, "quote": 0, "max": 0}
	var base := door_price_base(door_index)
	var share: float = RARITY_PRICE_SHARES[clampi(rarity, 0, RARITY_PRICE_SHARES.size() - 1)]
	var centre := maxf(float(MIN_CARD_PRICE), base * share)
	var minimum := maxi(MIN_CARD_PRICE, _round10(centre * PRICE_FLOOR_RATIO))
	var maximum := maxi(minimum, _round10(centre * PRICE_CEILING_RATIO))
	var quote := clampi(_round10(centre), minimum, maximum)
	return {"min": minimum, "quote": quote, "max": maximum}


func budget_snapshot(wallet: int) -> Dictionary:
	return {
		"wallet": maxi(0, wallet),
		"earned_kill_income": _actual_kill_income,
		"spendable_budget": maxi(0, wallet),
		"formula": "spendable_budget = current_run_wallet; rarity_unlock_income = cumulative_actual_kill_income; cheapest_quote = 0.70 x just_cleared_room_reference_income",
	}


func export_snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"configured": _configured,
		"actual_kill_income": _actual_kill_income,
		"actual_kill_events": _actual_kill_events,
	}


func import_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var snapshot: Dictionary = value as Dictionary
	if int(snapshot.get("schema_version", 0)) not in [1, 2, SCHEMA_VERSION]:
		return false
	_actual_kill_income = maxi(0, int(snapshot.get("actual_kill_income", 0)))
	_actual_kill_events = maxi(0, int(snapshot.get("actual_kill_events", 0)))
	return true


func get_snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"configured": _configured,
		"floor": _floor,
		"door_count": _door_count,
		"reference_income": {
			"min": roundi(_reference_income_min),
			"expected": roundi(_reference_income_expected),
			"max": roundi(_reference_income_max),
		},
		"reference_counts": _reference_counts.duplicate(true),
		"actual_kill_income": _actual_kill_income,
		"actual_kill_events": _actual_kill_events,
		"max_unlocked_rarity": max_unlocked_rarity(),
		"segment_income_expected": _segment_income_expected.duplicate(),
		"price_bounds": _price_bounds_snapshot(1),
		"door_price_table": _door_price_table(),
		"min_card_price": MIN_CARD_PRICE,
		"rarity_unlock_thresholds": _unlock_thresholds(),
		"budget_formula": "spendable_budget = current_run_wallet; actual_kill_income is not future income and never changes a frozen quote; cheapest_quote = 0.70 x just_cleared_room_reference_income",
	}


func _selected_box_indexes(encounter: Dictionary, placement_count: int) -> Array[int]:
	var stages: Array = encounter.get("stages", []) as Array
	var indexes: Array[int] = []
	# 与 Dungeon3D._resolve_encounter_stages 一致：每次调用都计数，跨波重复不去重。
	for stage_value in stages:
		if not stage_value is Dictionary:
			continue
		for index_value in (stage_value as Dictionary).get("boxes", []) as Array:
			var index := int(index_value)
			if index >= 0 and index < placement_count:
				indexes.append(index)
	if stages.is_empty():
		for index in range(placement_count):
			indexes.append(index)
	return indexes


func _add_box_reference(placement: Dictionary, box_catalog: Dictionary) -> void:
	var box_id := str(placement.get("box", ""))
	var box: Dictionary = box_catalog.get(box_id, {}) as Dictionary
	if box.is_empty():
		return
	var multiplier := maxi(1, int(placement.get("count_multiplier", 1)))
	var bonus := int(placement.get("count_bonus", 0))
	var bonus_used := false
	for spawn_value in box.get("spawns", []) as Array:
		if not spawn_value is Dictionary:
			continue
		var spawn: Dictionary = spawn_value as Dictionary
		var counts := _count_range(spawn)
		var type_id := str(spawn.get("type", ""))
		if type_id not in ["elite", "boss"]:
			counts[0] *= multiplier
			counts[1] *= multiplier
			if bonus > 0 and not bonus_used:
				counts[0] += bonus
				counts[1] += bonus
				bonus_used = true
		_add_type_reference(type_id, counts[0], counts[1])


func _add_encounter_reference(encounter: Dictionary) -> void:
	var stages: Array = encounter.get("stages", []) as Array
	var used_box_indexes: Dictionary = {}
	for stage_value in stages:
		if not stage_value is Dictionary:
			continue
		var stage: Dictionary = stage_value as Dictionary
		for box_index_value in stage.get("boxes", []) as Array:
			used_box_indexes[int(box_index_value)] = true
	if not used_box_indexes.is_empty():
		return
	for stage_value in stages:
		if not stage_value is Dictionary:
			continue
		var stage: Dictionary = stage_value as Dictionary
		for monster_value in stage.get("monsters", []) as Array:
			if not monster_value is Dictionary:
				continue
			var monster: Dictionary = monster_value as Dictionary
			var type_id := str(monster.get("type", ""))
			var count := maxf(0.0, float(int(monster.get("count", 0))))
			_add_type_reference(type_id, count, count)


func _add_type_reference(type_id: String, minimum: float, maximum: float) -> void:
	if type_id == "strong_random":
		_add_strong_random_reference(minimum, maximum)
		return
	_add_resolved_type_reference(type_id, minimum, maximum)


func _add_strong_random_reference(minimum: float, maximum: float) -> void:
	var incomes: Array[float] = []
	for kind in MONSTER_VARIANTS.all_variant_ids():
		incomes.append(_currency_value(str(kind), "normal", _floor))
	if incomes.is_empty():
		return
	var minimum_income := incomes[0]
	var maximum_income := incomes[0]
	var expected_income := 0.0
	for income in incomes:
		minimum_income = minf(minimum_income, income)
		maximum_income = maxf(maximum_income, income)
		expected_income += income
	expected_income /= float(incomes.size())
	var row: Dictionary = _reference_counts.get("strong_random", {
		"min": 0.0, "expected": 0.0, "max": 0.0, "tier": "normal",
	}) as Dictionary
	row["min"] = float(row.get("min", 0.0)) + minimum
	row["expected"] = float(row.get("expected", 0.0)) + (minimum + maximum) * 0.5
	row["max"] = float(row.get("max", 0.0)) + maximum
	_reference_counts["strong_random"] = row
	_reference_income_min += minimum * minimum_income
	_reference_income_expected += (minimum + maximum) * 0.5 * expected_income
	_reference_income_max += maximum * maximum_income


func _add_resolved_type_reference(type_id: String, minimum: float, maximum: float) -> void:
	var tier := "boss" if type_id == "boss" else "elite" if type_id == "elite" else "normal"
	var minimum_income := _currency_value(type_id, tier, _floor)
	var maximum_income := minimum_income
	var expected_income := minimum_income
	var variant_id := MONSTER_VARIANTS.variant_of(type_id)
	if tier == "normal" and not variant_id.is_empty() and _strong_variant_chance > 0.0:
		var variant_income := _currency_value(variant_id, tier, _floor)
		expected_income = lerpf(minimum_income, variant_income, _strong_variant_chance)
		maximum_income = maxf(minimum_income, variant_income)
		minimum_income = minf(minimum_income, variant_income)
	var row: Dictionary = _reference_counts.get(type_id, {
		"min": 0.0, "expected": 0.0, "max": 0.0, "tier": tier,
	}) as Dictionary
	row["min"] = float(row.get("min", 0.0)) + minimum
	row["expected"] = float(row.get("expected", 0.0)) + (minimum + maximum) * 0.5
	row["max"] = float(row.get("max", 0.0)) + maximum
	_reference_counts[type_id] = row
	_reference_income_min += minimum * minimum_income
	_reference_income_expected += (minimum + maximum) * 0.5 * expected_income
	_reference_income_max += maximum * maximum_income


func _currency_value(monster_id: String, tier: String, floor: int) -> float:
	# 复用正式货币通道（包括变种 default 与公式兜底），不猜测强化怪继承原怪币值。
	var spec := REWARD_SERVICE.currency_spec_for(monster_id, tier, floor, _currency_rules)
	if spec.is_empty():
		return 0.0
	var report := REWARD_SERVICE.resolve(spec, {"seed": 0, "floor": floor})
	var income := 0
	for grant_value in report.get("grants", []) as Array:
		var grant := grant_value as Dictionary
		if str(grant.get("kind", "")) == "currency":
			income += int(grant.get("amount", 0))
	return float(income)


func _unlock_thresholds() -> Array[int]:
	var thresholds: Array[int] = []
	for ratio in RARITY_UNLOCK_INCOME_RATIOS:
		thresholds.append(int(ceil(_reference_income_expected * ratio)))
	return thresholds


func _price_bounds_snapshot(door_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rarity in range(RARITY_PRICE_SHARES.size()):
		var bounds := price_bounds_for_rarity(rarity, door_index)
		result.append({
			"rarity": rarity,
			"min": int(bounds["min"]),
			"quote": int(bounds["quote"]),
			"max": int(bounds["max"]),
		})
	return result


## 逐门价表：`door=1..N` 的基准房收益与五档报价，用于设计核对与验收打印。
func _door_price_table() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _configured:
		return result
	for door in range(1, _door_count + 1):
		var segment_index := price_segment_index_for_door(door)
		var row: Dictionary = {
			"door": door,
			"segment_index": segment_index,
			"segment_income": roundi(0.0 if segment_index < 0 else _segment_income_expected[segment_index]),
			"base": roundi(door_price_base(door)),
			"prices": [],
		}
		var prices: Array[int] = []
		for rarity in range(RARITY_PRICE_SHARES.size()):
			prices.append(int(price_bounds_for_rarity(rarity, door)["quote"]))
		row["prices"] = prices
		result.append(row)
	return result


func _count_range(value: Variant) -> Array[float]:
	if value is Dictionary:
		var source: Dictionary = value as Dictionary
		if source.has("count_min") or source.has("count_max"):
			var normalized_min := float(source.get("count_min", 0))
			var normalized_max := float(source.get("count_max", normalized_min))
			return [maxf(0.0, normalized_min), maxf(0.0, normalized_max)]
		if source.has("count"):
			return _count_range(source["count"])
		var raw_min := float(source.get("min", 0))
		var raw_max := float(source.get("max", raw_min))
		return [maxf(0.0, raw_min), maxf(0.0, raw_max)]
	var fixed := maxf(0.0, float(value))
	return [fixed, fixed]


func _round10(value: float) -> int:
	return maxi(10, int(round(value / 10.0) * 10.0))
