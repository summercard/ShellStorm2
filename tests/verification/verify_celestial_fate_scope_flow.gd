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
		if fate_label == null or not fate_label.text.contains("月亮命运 10张") or not fate_label.text.contains("太阳命运 10张"):
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
