extends RefCounted
## Read-only level scope; application/payment remain owned by Engine/Bridge.
const DATA_PATH := "res://data/fate/level_pools.json"
static var _policies: Dictionary = {}

static func policy(level_id: String) -> Dictionary:
	if _policies.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary and int(parsed.get("schema_version", 0)) == 1:
			_policies = parsed.get("policies", {})
	return (_policies.get(level_id, {}) as Dictionary).duplicate(true)

static func allows(level_id: String, stable_id: String) -> bool:
	var rules := policy(level_id)
	# A missing configured level must fail closed, not leak the global pool.
	if level_id == "expedition_01" and rules.is_empty():
		return false
	return rules.is_empty() or stable_id in (rules.get("card_ids", []) as Array)

static func filter_pool(pool: Array[FateCard], level_id: String) -> Array[FateCard]:
	var result: Array[FateCard] = []
	for card in pool:
		if card != null and allows(level_id, card.get_stable_card_id()):
			result.append(card)
	return result

static func orient(card: FateCard, roll: float, level_id: String) -> void:
	if bool(policy(level_id).get("upright_only", false)):
		card.set_orientation(FateCard.Orientation.UPRIGHT, roll)
	else:
		card.roll_orientation(roll)
