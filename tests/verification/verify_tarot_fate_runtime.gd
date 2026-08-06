extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var cards := FateCardPresets.playable_presets()
	_check(cards.size() == 48, "expected 48 executable tarot cards, got %d" % cards.size(), failures)
	var stable_ids := {}
	for card in cards:
		var stable_id := card.get_stable_card_id()
		_check(not stable_ids.has(stable_id), "duplicate stable id: %s" % stable_id, failures)
		stable_ids[stable_id] = true
		var definition := TarotFateCatalog.get_definition(stable_id)
		_check(not definition.is_empty(), "missing tarot definition: %s" % stable_id, failures)
		_check(card.card_name == str(definition.get("name", "")), "runtime still shows legacy name: %s" % card.legacy_card_name, failures)
		_check(card.card_name != card.legacy_card_name, "tarot name did not replace legacy name: %s" % stable_id, failures)
		var tarot_name := card.card_name
		var scope := card.scope
		card.set_orientation(FateCard.Orientation.UPRIGHT, 0.25)
		var upright_description := card.description
		var upright_effect := card.effect.duplicate(true)
		var upright_tree := WeaponPresets.build_rifle()
		var upright_result := FateCardEngine.apply_card(card, upright_tree)
		_check(upright_result.success, "%s upright failed: %s" % [tarot_name, upright_result.message], failures)
		_free_tree_nodes(upright_tree.get_root())
		upright_tree.free()
		card.set_orientation(FateCard.Orientation.REVERSED, 0.75)
		_check(card.card_name == tarot_name and card.scope == scope, "%s reversed changed identity or owner" % tarot_name, failures)
		_check(card.description != upright_description, "%s reversed description is unchanged" % tarot_name, failures)
		_check(card.effect != upright_effect, "%s reversed effect snapshot is unchanged" % tarot_name, failures)
		_check(str(card.effect.get("orientation", "")) == "REVERSED", "%s reversed effect lacks orientation" % tarot_name, failures)
		var reversed_tree := WeaponPresets.build_rifle()
		var reversed_result := FateCardEngine.apply_card(card, reversed_tree)
		_check(reversed_result.success, "%s reversed failed: %s" % [tarot_name, reversed_result.message], failures)
		_free_tree_nodes(reversed_tree.get_root())
		reversed_tree.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var reversed_count := 0
	var sample_card := FateCardPresets.overclock()
	for _sample in 100000:
		if sample_card.roll_orientation(rng.randf()) == FateCard.Orientation.REVERSED:
			reversed_count += 1
	var reversed_ratio := float(reversed_count) / 100000.0
	_check(reversed_ratio >= 0.495 and reversed_ratio <= 0.505, "orientation distribution %.4f is outside 49.5%%-50.5%%" % reversed_ratio, failures)

	rng.seed = 91234
	var offer := FateCardPresets.draw_offer(3, rng)
	_check(offer.size() == 3, "draw_offer did not return three cards", failures)
	var offer_ids := {}
	for card in offer:
		offer_ids[card.get_stable_card_id()] = true
		_check(card.orientation_name() in ["正位", "逆位"], "offer card has no readable orientation", failures)
	_check(offer_ids.size() == 3, "draw_offer contains duplicate card ids", failures)

	if failures.is_empty():
		print("TAROT_FATE_RUNTIME_OK: 48 tarot names, upright/reversed effects, stable IDs and 50/50 orientation passed")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _free_tree_nodes(node: AssemblyNode) -> void:
	if node == null:
		return
	for slot_type in node.slots:
		var child: AssemblyNode = node.slots[slot_type]
		_free_tree_nodes(child)
	node.free()


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
