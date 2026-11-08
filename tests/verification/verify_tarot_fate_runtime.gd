extends "res://tests/verification/verify_fate_world_completion.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	dungeon = DUNGEON.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 20261008
	add_child(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	for candidate in dungeon._rooms:
		if candidate.room_type == "COMBAT":
			room = candidate
			break
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
		_prepare_owner()
		var upright_tree := BlueprintRegistry.build_weapon_tree("bp_rifle")
		var upright_result := FateCardEngine.apply_card(card, upright_tree, _source_targets(card, upright_tree))
		_check(upright_result.success, "%s upright failed: %s" % [tarot_name, upright_result.message], failures)
		upright_tree.clear_assembly(false)
		upright_tree.free()
		card.set_orientation(FateCard.Orientation.REVERSED, 0.75)
		_check(card.card_name == tarot_name and card.scope == scope, "%s reversed changed identity or owner" % tarot_name, failures)
		_check(card.description != upright_description, "%s reversed description is unchanged" % tarot_name, failures)
		_check(card.effect != upright_effect, "%s reversed effect snapshot is unchanged" % tarot_name, failures)
		_check(str(card.effect.get("orientation", "")) == "REVERSED", "%s reversed effect lacks orientation" % tarot_name, failures)
		_prepare_owner()
		var reversed_tree := BlueprintRegistry.build_weapon_tree("bp_rifle")
		var reversed_result := FateCardEngine.apply_card(card, reversed_tree, _source_targets(card, reversed_tree))
		_check(reversed_result.success, "%s reversed failed: %s" % [tarot_name, reversed_result.message], failures)
		reversed_tree.clear_assembly(false)
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

	# —— 正式入口收口（设计 §8.1）——
	# 普通容器只记统计，不能按 5/10 次自动授予奖励卡、创建 offer 或扣钱；
	# 命运卡专用掉落物主动交互才进入统一购卡事务。
	_check(
		MapFateTriggers.DEFAULT_TRIGGERS.is_empty(),
		"普通容器仍配置了自动命运卡阈值触发",
		failures
	)
	var container_trigger := MapFateTriggers.new()
	add_child(container_trigger)
	await get_tree().process_frame
	for _index in range(10):
		container_trigger.on_container_opened("treasure_chest")
	var container_auto_triggered := false
	for value in container_trigger._triggered_this_run.values():
		container_auto_triggered = container_auto_triggered or bool(value)
	_check(
		int(container_trigger._counters.get(MapFateTriggers.TriggerType.OPEN_CHEST, 0)) == 10
		and not container_auto_triggered,
		"普通容器统计未保留或意外触发命运效果",
		failures
	)
	for environment_fate in ["fate_lucky_chest", "fate_extra_loot", "fate_mark_enemy", "fate_reinforce", "fate_curse_map", "fate_bless_dead"]:
		var trigger_result: Dictionary = FateCardGameBridge.apply_fate_card_from_trigger(environment_fate)
		_check(
			not bool(trigger_result.get("success", true))
			and str(trigger_result.get("message", "")).contains("active pickup/offer"),
			"%s 仍可从环境触发桥直接生效" % environment_fate,
			failures
		)
	var cards_before := FateCardGameBridge.get_card_count()
	var pending_before := FateCardGameBridge.get_pending_character_rewards().size()
	var character_reward := FateCardGameBridge.grant_random_card_from_character()
	_check(
		not bool(character_reward.get("success", true))
		and FateCardGameBridge.get_card_count() == cards_before
		and FateCardGameBridge.get_pending_character_rewards().size() == pending_before,
		"角色二级奖励旧API仍可免费抽取或应用命运卡",
		failures
	)
	container_trigger.queue_free()
	# 抽卡路径仍是敌增援唯一真源：预设必须保留 REINFORCE_WAVE 执行动作。
	var reinforce := FateCardPresets.fate_reinforce()
	_check(
		int((reinforce.effect as Dictionary).get("action", -1)) == FateCard.EffectAction.REINFORCE_WAVE,
		"fate_reinforce 预设缺少 REINFORCE_WAVE（抽卡落地路径被破坏）",
		failures
	)

	dungeon.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("TAROT_FATE_RUNTIME_OK: 48 tarot names, upright/reversed effects, stable IDs, 50/50 orientation and draw-only combat fates passed")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _prepare_owner() -> void:
	prepare()
	EliteRosterService.reset_roster_for_test()
	room.set_meta("floor_number", EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", dungeon.run_seed))
	commit()
	dungeon.player.reset_character_fate_state()


func _source_targets(current: FateCard, tree: WeaponAssemblyTree) -> Array[AssemblyNode]:
	var bullet := tree.root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	match current.get_stable_card_id():
		"fate_attachment_parasite":
			var source := BlueprintRegistry.create_assembly_node("attach_triple_muzzle")
			_check(tree.mount(tree.root, source.get_attachment_slot_type(), source), "安装真实配件前置", failures)
			return [bullet, source]
		"fate_gun_on_gun":
			return [tree.root, tree.root]
		"fate_bullet_carry_gun":
			return [bullet, tree.root]
	return []


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
