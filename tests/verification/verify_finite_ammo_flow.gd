extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 8312026
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	if BaseManager.get_vault_capacity() < 20:
		failures.append("base vault capacity is still below twenty slots")

	var hud := dungeon.get_node("HUD/ReferenceCombatHUD") as Control
	var info_panel := hud.get_node("CurrentInfoPanel") as PanelContainer
	var weapon_panel := hud.get_node("CurrentWeaponPanel") as PanelContainer
	var quick_panel := hud.get_node("QuickItemHUD_0") as PanelContainer
	var action_panel := hud.get_node("ActionKeyStrip").get_child(0) as PanelContainer
	if info_panel.position.x > 20.0 or info_panel.position.y < 290.0:
		failures.append("current-info HUD was not moved below the left objective region")
	if weapon_panel.size.x > 255.0 or weapon_panel.size.y > 50.0:
		failures.append("weapon HUD was not reduced to approximately sixty percent")
	if quick_panel.size.x > 50.0 or quick_panel.size.y > 48.0:
		failures.append("quick-item HUD was not reduced with the weapon HUD")
	for panel in [info_panel, weapon_panel, quick_panel, action_panel]:
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null or style.bg_color.a > 0.51:
			failures.append("gameplay HUD panel background exceeds the fifty-percent alpha contract")
			break

	var inventory := dungeon.get("_inventory") as InventoryModule
	var ammo := ItemRegistry.get_instance().get_item("item_ammo_pack")
	if inventory == null or inventory.add_item(ammo, 5) != 5:
		failures.append("cannot stage five reserve rounds in the backpack")
	else:
		var weapon := dungeon.player.weapon
		var before := maxi(0, weapon.magazine_size - 8)
		weapon.current_ammo = before
		weapon.ammo_changed.emit(before, weapon.magazine_size)
		if not dungeon.player.request_reload():
			failures.append("finite reload refused despite reserve ammo")
		else:
			weapon.call("_process", weapon.reload_time + 0.01)
			if weapon.current_ammo != before + 5:
				failures.append("partial reload did not load exactly the five available rounds")
			if inventory.get_item_count("item_ammo_pack") != 0:
				failures.append("reload did not consume the exact reserve count")
		if dungeon.player.request_reload():
			failures.append("reload started with an empty reserve")

	# 主副武器各自保存弹匣。直接发出弹量事件等价于一次真实射击后的同步。
	var secondary := ItemRegistry.get_instance().get_item("weapon_shotgun")
	var equip_result := dungeon.player.equip_weapon_item_to_slot(secondary, 1)
	if not bool(equip_result.get("success", false)):
		failures.append("cannot equip secondary weapon for magazine persistence check")
	else:
		var primary_ammo := maxi(0, dungeon.player.weapon.magazine_size - 3)
		dungeon.player.weapon.current_ammo = primary_ammo
		dungeon.player.weapon.ammo_changed.emit(primary_ammo, dungeon.player.weapon.magazine_size)
		if not bool(dungeon.player.switch_weapon_slot(1).get("success", false)):
			failures.append("cannot switch to secondary weapon")
		elif not bool(dungeon.player.switch_weapon_slot(0).get("success", false)):
			failures.append("cannot switch back to primary weapon")
		elif dungeon.player.weapon.current_ammo != primary_ammo:
			failures.append("switching away and back refilled the primary magazine")

	var loot := LootModule.new()
	loot.set_seed(8312026)
	var elite_drops := loot.generate_enemy_loot({"floor": 2, "is_elite": true})
	var dropped_rounds := 0
	for item in elite_drops:
		if str(item.get("id", "")) == "item_ammo_pack":
			dropped_rounds += int(item.get("count", 0))
	if dropped_rounds < 8:
		failures.append("elite enemy did not produce its guaranteed reserve-ammo stack")

	dungeon.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("FINITE_AMMO_FLOW_OK: reserve rounds are consumed exactly, empty reload is blocked, weapon magazines persist across swaps, and enemies drop ammo")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
