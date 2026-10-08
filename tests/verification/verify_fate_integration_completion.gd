extends "res://tests/verification/verify_fate_world_completion.gd"

var scope_events := 0
var ui_result: Dictionary = {}

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("fate_completion_20261008/integration"), "启动前隔离APPDATA")
	check(OS.get_environment("LOCALAPPDATA").replace("\\", "/").contains("fate_completion_20261008/integration"), "启动前隔离LOCALAPPDATA")
	if not failures.is_empty():
		get_tree().quit(1)
		return
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
	FateCardGameBridge.set_player(dungeon.player)
	FateCardGameBridge.scope_state_changed.connect(_scope_changed)
	for preset in FateCardPresets.playable_presets():
		for reversed in [false, true]:
			prepare()
			EliteRosterService.reset_roster_for_test()
			room.set_meta("floor_number", EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", dungeon.run_seed))
			commit()
			FateCardGameBridge.reset_run_state()
			fresh_weapon()
			var current := card(preset.get_stable_card_id(), reversed)
			if current.get_stable_card_id() == "fate_attachment_parasite":
				install("attach_triple_muzzle")
			var source: AssemblyNode = null
			if FateCardGameBridge.requires_source_selection(current):
				var candidates := FateCardGameBridge.get_source_candidates(current)
				check(not candidates.is_empty(), "真实来源候选 " + current.card_name)
				if not candidates.is_empty():
					source = candidates[0]["source"]
			var events_before := scope_events
			var result := FateCardGameBridge.apply_card_instance(current, source)
			check(bool(result.get("success", false)), "正式Bridge正逆 " + current.get_stable_card_id() + str(reversed) + str(result))
			check(FateCardGameBridge.get_card_count() == 1, "成功仅登记一次 " + current.card_name)
			check(dungeon.player.get_equipped_weapon_instance().fate_upgrades.size() == (1 if current.scope == FateCard.Scope.WEAPON else 0), "三scope槽归属 " + current.card_name)
			check(scope_events - events_before == (0 if current.scope == FateCard.Scope.WEAPON else 1), "scope成功通知一次 " + current.card_name)
			if current.scope == FateCard.Scope.WORLD:
				var bridge_state := dungeon.get_world_fate_snapshot()
				prepare()
				EliteRosterService.reset_roster_for_test()
				commit()
				var direct := FateCardEngine.apply_card(current, null)
				check(direct.success, "Engine无武器完整世界命令 " + current.card_name)
				check(bridge_state == dungeon.get_world_fate_snapshot(), "Bridge与Engine世界真实效果一致且无双算 " + current.card_name)
	prepare()
	room.cleared = true
	FateCardGameBridge.reset_run_state()
	var events_before := scope_events
	for id in ["fate_reinforce", "fate_curse_map"]:
		for reversed in [false, true]:
			var result := FateCardGameBridge.apply_card_instance(card(id, reversed))
			check(not bool(result.success), "清房真实拒绝 " + id)
			check(result.get("error", "") == "room_not_in_combat", "失败原因透传 " + id)
			check(not FateCardEngine.apply_card(card(id, reversed), null).success, "Engine不能绕过世界失败 " + id)
	check(FateCardGameBridge.get_card_count() == 0 and scope_events == events_before, "世界失败不登记不发scope")
	dungeon.show_reference_fate_overlay_for_test()
	dungeon._door_fate_choices[0] = card("fate_reinforce")
	await dungeon._on_door_fate_selected(0)
	check(dungeon._door_fate_active and dungeon._door_fate_choices[0].get_stable_card_id() == "fate_reinforce", "世界失败保留正式三选一")
	dungeon._close_door_fate_overlay()
	fresh_weapon()
	var forged := BlueprintRegistry.create_assembly_node("bp_shotgun")
	var invalid := FateCardGameBridge.apply_card_instance(card("fate_gun_on_gun"), forged)
	check(not bool(invalid.success) and dungeon.player.get_equipped_weapon_instance().fate_upgrades.is_empty(), "伪造未持有来源拒绝")
	if forged != null:
		forged.free()
	install("attach_scope")
	var static_candidates := FateCardGameBridge.get_source_candidates(card("fate_attachment_parasite"))
	check(static_candidates.size() == 1 and not bool(static_candidates[0].supported), "静态配件明确标记不支持")
	_select_button_deferred(static_candidates[0].source)
	var rejected := await FateCardGameBridge.apply_card_with_source_selection(card("fate_attachment_parasite"), self)
	check(not bool(rejected.success) and str(rejected.message).contains("静态属性"), "静态配件选择后明确拒绝")
	check(dungeon.player.get_equipped_weapon_instance().fate_upgrades.is_empty(), "静态来源失败不占槽")
	for id in ["fate_gun_on_gun", "fate_bullet_carry_gun", "fate_attachment_parasite"]:
		fresh_weapon()
		if id == "fate_attachment_parasite":
			install("attach_triple_muzzle")
		var candidate := FateCardGameBridge.get_source_candidates(card(id))[0]
		var original: Dictionary = (candidate.source as AssemblyNode).get_computed_stats().duplicate(true)
		_select_button_deferred(candidate.source)
		var applied := await FateCardGameBridge.apply_card_with_source_selection(card(id), self)
		check(bool(applied.success), "真实按钮绑定source到Bridge " + id)
		check(dungeon.player.get_equipped_weapon_instance().fate_upgrades.size() == 1, "来源UI成功仅占一槽 " + id)
		check(not original.is_empty(), "来源真实属性非空 " + id)
	fresh_weapon()
	dungeon.show_reference_fate_overlay_for_test()
	dungeon._door_fate_choices[0] = card("fate_gun_on_gun")
	_select_button_deferred(dungeon.player.get_weapon_tree().root)
	await dungeon._on_door_fate_selected(0)
	check(not dungeon._door_fate_active and dungeon.player.get_equipped_weapon_instance().fate_upgrades.size() == 1, "门后实际选牌调用统一来源入口")
	fresh_weapon()
	var workbench := preload("res://scenes/WorkbenchPanel.tscn").instantiate() as WorkbenchPanel
	add_child(workbench)
	workbench.set_player(dungeon.player)
	_select_button_deferred(dungeon.player.get_weapon_tree().root)
	await workbench._on_fate_card_selected(card("fate_bullet_carry_gun"))
	check(dungeon.player.get_equipped_weapon_instance().fate_upgrades.size() == 1, "工作台实际选牌调用统一来源入口")
	workbench.queue_free()
	fresh_weapon()
	var secondary := ItemRegistry.get_instance().get_item("weapon_shotgun")
	check(bool(dungeon.player.equip_weapon_item_to_slot(secondary, 1).success), "未激活副槽装备真实来源枪")
	var secondary_instance := dungeon.player.get_equipped_weapon_instance_for_slot(1)
	var secondary_before := secondary_instance.to_item_dictionary().duplicate(true)
	var owned_candidates := FateCardGameBridge.get_source_candidates(card("fate_gun_on_gun"))
	check(owned_candidates.size() == 2, "副槽未切出也可选，来源不重复")
	var secondary_source := owned_candidates[0].source as AssemblyNode
	check(secondary_source != dungeon.player.get_weapon_tree().root, "来源绑定非激活真实实例")
	secondary_instance.assembly_snapshot["verification_changed"] = true
	var stale := FateCardGameBridge.apply_card_instance(card("fate_gun_on_gun"), secondary_source)
	check(not bool(stale.success), "来源装配改变后拒绝陈旧选择")
	secondary_instance.assembly_snapshot.erase("verification_changed")
	var copied := FateCardGameBridge.apply_card_instance(card("fate_gun_on_gun"), secondary_source)
	check(bool(copied.success), "真实副槽来源快照可应用")
	check(secondary_instance.to_item_dictionary() == secondary_before, "快照不移动或消耗副槽来源")
	var installed := dungeon.player.get_weapon_tree().root.slots[AssemblyNode.SlotType.MOUNT] as AssemblyNode
	check(is_equal_approx(float(installed.base_stats.get("damage", 0)), float(secondary_source.get_computed_stats().get("damage", -1))), "附枪继承所选副槽实际伤害")
	fresh_weapon()
	call_deferred("_cancel_panel")
	var cancelled := await FateCardGameBridge.apply_card_with_source_selection(card("fate_gun_on_gun"), self)
	check(not bool(cancelled.success) and dungeon.player.get_equipped_weapon_instance().fate_upgrades.is_empty(), "取消来源不消耗")
	var pending := card("fate_gun_on_gun", true)
	FateCardGameBridge._pending_character_rewards.append({"card": pending, "currency_cost": 30})
	GameManager.currency = 100
	var failed_reward := FateCardGameBridge.retry_pending_character_reward()
	check(not bool(failed_reward.success) and GameManager.currency == 100, "愚者缺来源失败退魂")
	check(FateCardGameBridge._pending_character_rewards[0].card == pending, "待领保留原牌原方位")
	FateCardGameBridge._process(0.0)
	check(FateCardGameBridge._reward_button.visible, "愚者待领奖励常驻入口可见")
	call_deferred("_claim_pending")
	await FateCardGameBridge._open_pending_rewards()
	check(FateCardGameBridge.get_pending_character_rewards().is_empty() and GameManager.currency == 70, "UI领取固定奖励一次扣魂")
	check(dungeon.player.get_equipped_weapon_instance().fate_upgrades.size() == 1, "UI领取固定奖励一次刻印")
	FateCardGameBridge.scope_state_changed.disconnect(_scope_changed)
	FateCardGameBridge.reset_run_state()
	dungeon.queue_free()
	await get_tree().process_frame
	print("FATE_INTEGRATION_COMPLETION checks=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("FATE_INTEGRATION_COMPLETION_OK")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _scope_changed(_scope: String, _id: String) -> void:
	scope_events += 1

func fresh_weapon() -> void:
	var item := ItemRegistry.get_instance().get_item("weapon_rifle")
	var result := dungeon.player.equip_weapon_item(item)
	check(bool(result.success), "装备真实独立步枪")
	FateCardGameBridge.set_player(dungeon.player)

func install(id: String) -> void:
	var node := BlueprintRegistry.create_assembly_node(id)
	check(dungeon.player.get_weapon_tree().mount(dungeon.player.get_weapon_tree().root, node.get_attachment_slot_type(), node), "安装真实来源配件 " + id)

func _select_button_deferred(source: AssemblyNode) -> void:
	call_deferred("_select_button", source)

func _select_button(source: AssemblyNode) -> void:
	var panel := FateCardGameBridge.get_node("FateSourceSelectionPanel")
	for button in panel.find_children("*", "Button", true, false):
		if button.get_meta("fate_source", null) == source:
			check(true, "来源按钮绑定真实节点")
			button.pressed.emit()
			return
	check(false, "未找到绑定的来源按钮")
	panel.cancel()

func _cancel_panel() -> void:
	FateCardGameBridge.get_node("FateSourceSelectionPanel").cancel()

func _claim_pending() -> void:
	var panel := FateCardGameBridge.get_node("FateSourceSelectionPanel")
	var buttons := panel.find_children("*", "Button", true, false)
	buttons[0].pressed.emit()
	await get_tree().process_frame
	var source_panel := FateCardGameBridge.get_node("FateSourceSelectionPanel")
	for button in source_panel.find_children("*", "Button", true, false):
		if button.get_meta("fate_source", null) != null:
			button.pressed.emit()
			return
	source_panel.cancel()
