extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var cards: Array[FateCard] = FateCardPresets.playable_presets()
	for card in cards:
		var tree: WeaponAssemblyTree = WeaponPresets.build_rifle()
		var result: FateCardEngine.ApplyResult = FateCardEngine.apply_card(card, tree)
		if not result.success:
			failures.append("%s: %s" % [card.card_name, result.message])
		_free_tree_nodes(tree.get_root())
		tree.free()
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
