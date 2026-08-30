extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 8052026
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame

	var weapon_before := dungeon.player.get_weapon_presentation_snapshot()
	var used_before := int(weapon_before.get("fate_slot_used", 0))
	var new_cards: Array[FateCard] = [
		FateCardPresets.moon_vitality(), FateCardPresets.moon_stride(),
		FateCardPresets.moon_dash(), FateCardPresets.moon_guard(),
		FateCardPresets.moon_power(), FateCardPresets.moon_room_heal(),
		FateCardPresets.moon_elite_heal(), FateCardPresets.moon_first_hit(),
		FateCardPresets.moon_last_stand(), FateCardPresets.moon_ammo(),
		FateCardPresets.sun_quality(), FateCardPresets.sun_extra_loot(),
		FateCardPresets.sun_reinforce(), FateCardPresets.sun_reveal(),
		FateCardPresets.sun_key(), FateCardPresets.sun_currency(),
		FateCardPresets.sun_scorch(), FateCardPresets.sun_trial(),
		FateCardPresets.sun_bounty(), FateCardPresets.sun_extraction(),
	]
	for card in new_cards:
		var result := FateCardGameBridge.apply_card(card)
		if not bool(result.get("success", false)):
			failures.append("scoped card failed: %s (%s)" % [card.card_name, result.get("message", "")])
		if not str(result.get("scope_display_name", "")).contains("命运"):
			failures.append("application result misses celestial scope name: %s" % card.card_name)

	var scope_state := FateCardGameBridge.get_scope_state_snapshot()
	if (scope_state.get("character", []) as Array).size() != 10:
		failures.append("moon cards were not all stored by the character owner")
	if (scope_state.get("world", []) as Array).size() != 10:
		failures.append("sun cards were not all stored by the world owner")
	var weapon_after := dungeon.player.get_weapon_presentation_snapshot()
	if int(weapon_after.get("fate_slot_used", 0)) != used_before:
		failures.append("moon/sun cards consumed weapon fate slots")

	var character := dungeon.player.get_character_fate_snapshot()
	if dungeon.player.max_hp != 120:
		failures.append("moon vitality did not raise max HP to 120")
	if float(character.get("move_speed_multiplier", 1.0)) <= 1.0:
		failures.append("moon stride is not executable")
	if float(character.get("dash_cooldown_multiplier", 1.0)) >= 1.0:
		failures.append("moon dash cooldown is not executable")
	if int(character.get("last_stand_charges", 0)) != 1:
		failures.append("moon last stand charge was not stored")
	if int(character.get("room_heal", 0)) != 6 or float(character.get("room_ammo_ratio", 0.0)) < 0.19:
		failures.append("room-entry moon rules were not stored")

	var world := dungeon.get_world_fate_snapshot()
	if int(world.get("next_chest_quality", 0)) != 1 or int(world.get("next_chest_extra", 0)) != 2:
		failures.append("sun chest rules were not stored")
	if int(world.get("next_room_enemy_count", 0)) != 3:
		failures.append("sun reinforcement was not stored")
	if not is_equal_approx(float(world.get("next_room_enemy_hp_multiplier", 1.0)), 0.8):
		failures.append("sun scorch was not stored")
	if not is_equal_approx(float(world.get("next_room_enemy_damage_multiplier", 1.0)), 1.25):
		failures.append("sun trial damage risk was not stored")
	if not is_equal_approx(float(world.get("next_room_currency_multiplier", 1.0)), 2.0):
		failures.append("sun trial reward was not stored")
	if int(world.get("bounty_rooms", 0)) != 3 or int(world.get("bounty_amount", 0)) != 35:
		failures.append("sun bounty was not stored")
	if not is_equal_approx(float(world.get("extraction_time_multiplier", 1.0)), 0.8):
		failures.append("sun extraction shortcut was not stored")

	# 下一箱类效果必须在真实搜索结算中被消费，而不只是留在快照里。
	var loot_before := get_tree().get_nodes_in_group("ground_loot_3d").size()
	var start_room := (dungeon.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	dungeon.call("_on_prop_searched", start_room, {"size_class": "small"})
	var chest_after := dungeon.get_world_fate_snapshot()
	if int(chest_after.get("next_chest_quality", -1)) != 0 or int(chest_after.get("next_chest_extra", -1)) != 0:
		failures.append("next-chest sun cards were not consumed by a real container search")
	if get_tree().get_nodes_in_group("ground_loot_3d").size() <= loot_before:
		failures.append("real container settlement did not produce a world pickup")

	# 开门先展示命运选择，目标房必须等选择结束后才生成并消费“下一房”效果。
	dungeon.set("_next_room_enemy_count", 0)
	dungeon.set("_next_room_enemy_hp_multiplier", 1.0)
	dungeon.set("_next_room_enemy_damage_multiplier", 1.0)
	dungeon.set("_next_room_currency_multiplier", 1.0)
	var room_by_id := dungeon.get("_room_by_id") as Dictionary
	var neighbors := dungeon.get("_room_neighbors") as Dictionary
	var spawned := dungeon.get("_spawned_rooms") as Dictionary
	var source_id := ""
	var target_id := ""
	for candidate_source in neighbors.keys():
		for candidate_target in neighbors.get(candidate_source, []):
			var target_room := room_by_id.get(str(candidate_target)) as DungeonRoom3D
			if target_room != null and target_room.room_type in GameDesignConfig.ROOM_TYPES_WITH_HOSTILES and not spawned.has(target_room.room_id):
				source_id = str(candidate_source)
				target_id = target_room.room_id
				break
		if not target_id.is_empty():
			break
	if target_id.is_empty():
		failures.append("cannot find an unstreamed hostile room for next-room fate acceptance")
	else:
		var source_room := room_by_id.get(source_id) as DungeonRoom3D
		source_room.cleared = true
		dungeon.set("_current_room_id", source_id)
		dungeon.set("_room_key_count", 99)
		if not dungeon.try_open_room_door(target_id):
			failures.append("cannot open fate-gated edge for next-room timing acceptance")
		elif (dungeon.get("_spawned_rooms") as Dictionary).has(target_id):
			failures.append("target hostile room spawned before the fate choice")
		else:
			await get_tree().process_frame
			FateCardGameBridge.apply_card(FateCardPresets.sun_reinforce())
			FateCardGameBridge.apply_card(FateCardPresets.sun_scorch())
			FateCardGameBridge.apply_card(FateCardPresets.sun_trial())
			dungeon.call("_close_door_fate_overlay")
			if not (dungeon.get("_spawned_rooms") as Dictionary).has(target_id):
				failures.append("target room did not stream after fate selection closed")
			var hp_by_room := dungeon.get("_room_enemy_hp_multipliers") as Dictionary
			var damage_by_room := dungeon.get("_room_enemy_damage_multipliers") as Dictionary
			var currency_by_room := dungeon.get("_room_currency_multipliers") as Dictionary
			if not is_equal_approx(float(hp_by_room.get(target_id, 1.0)), 0.8):
				failures.append("next-room HP fate was not consumed by the opened target room")
			if not is_equal_approx(float(damage_by_room.get(target_id, 1.0)), 1.25):
				failures.append("next-room damage fate was not consumed by the opened target room")
			if not is_equal_approx(float(currency_by_room.get(target_id, 1.0)), 2.0):
				failures.append("next-room reward fate was not consumed by the opened target room")

	var moon_face := dungeon.call("_get_fate_choice_text", FateCardPresets.moon_vitality()) as String
	var sun_face := dungeon.call("_get_fate_choice_text", FateCardPresets.sun_quality()) as String
	var star_face := dungeon.call("_get_fate_choice_text", FateCardPresets.overclock()) as String
	if not moon_face.contains("☾ 月亮命运") or not moon_face.contains("不占武器槽"):
		failures.append("moon card face lacks its special name/target")
	if not sun_face.contains("☀ 太阳命运") or not sun_face.contains("不占武器槽"):
		failures.append("sun card face lacks its special name/target")
	if not star_face.contains("★ 星星命运") or not star_face.contains("永久刻印"):
		failures.append("weapon card face lacks its special name/permanent target")

	var inventory_ui := dungeon.get("_inventory_ui") as InventoryUI
	if inventory_ui != null:
		inventory_ui.set_inventory_panel_open(true)
		await get_tree().process_frame
		var fate_label := inventory_ui.equipment_fate_label
		if fate_label == null or not fate_label.text.contains("月亮命运") or not fate_label.text.contains("太阳命运"):
			failures.append("equipment UI does not persistently expose moon/sun fate state")
	else:
		failures.append("formal dungeon has no inventory fate observation UI")

	dungeon.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("CELESTIAL_FATE_SCOPE_FLOW_OK: 20 new moon/sun cards execute, persist, avoid weapon slots, and expose named card/UI state")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
