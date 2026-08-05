extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var cards: Array[FateCard] = FateCardPresets.playable_presets()
	if cards.size() != 48:
		failures.append("expected 48 playable cards, got %d" % cards.size())
	var scope_counts := {FateCard.Scope.WEAPON: 0, FateCard.Scope.CHARACTER: 0, FateCard.Scope.WORLD: 0}
	var stable_ids: Dictionary = {}
	for card in cards:
		scope_counts[card.scope] = int(scope_counts.get(card.scope, 0)) + 1
		if stable_ids.has(card.get_stable_card_id()):
			failures.append("duplicate stable id: %s" % card.get_stable_card_id())
		stable_ids[card.get_stable_card_id()] = true
		if FateCard.scope_display_name(card.scope) not in ["★ 星星命运", "☾ 月亮命运", "☀ 太阳命运"]:
			failures.append("missing celestial scope name: %s" % card.card_name)
		var tree: WeaponAssemblyTree = WeaponPresets.build_rifle()
		var result: FateCardEngine.ApplyResult = FateCardEngine.apply_card(card, tree)
		if not result.success:
			failures.append("%s: %s" % [card.card_name, result.message])
		_free_tree_nodes(tree.get_root())
		tree.free()
	if int(scope_counts[FateCard.Scope.WEAPON]) != 22:
		failures.append("expected 22 weapon cards")
	if int(scope_counts[FateCard.Scope.CHARACTER]) != 12:
		failures.append("expected 12 character cards")
	if int(scope_counts[FateCard.Scope.WORLD]) != 14:
		failures.append("expected 14 world cards")
	for required_id in [
		"fate_moon_vitality", "fate_moon_stride", "fate_moon_dash", "fate_moon_guard",
		"fate_moon_power", "fate_moon_room_heal", "fate_moon_elite_heal",
		"fate_moon_first_hit", "fate_moon_last_stand", "fate_moon_ammo",
		"fate_sun_quality", "fate_sun_extra_loot", "fate_sun_reinforce", "fate_sun_reveal",
		"fate_sun_key", "fate_sun_currency", "fate_sun_scorch", "fate_sun_trial",
		"fate_sun_bounty", "fate_sun_extraction",
	]:
		if not stable_ids.has(required_id):
			failures.append("new card missing from playable pool: %s" % required_id)
	if failures.is_empty():
		print("[verify_fate_card_pool] PASS %d playable cards" % cards.size())
		quit(0)
	else:
		for failure in failures:
			push_error("[verify_fate_card_pool] " + failure)
		quit(1)


func _free_tree_nodes(node: AssemblyNode) -> void:
	if node == null:
		return
	for slot_type in node.slots:
		var child: AssemblyNode = node.slots[slot_type]
		_free_tree_nodes(child)
	node.free()
