extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const RUNTIME_REWARD_COORDINATOR := preload("res://src/rewards/RuntimeRewardCoordinator.gd")


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
	if info_panel.position.x > 20.0 or info_panel.position.y < 290.0:
		failures.append("current-info HUD was not moved below the left objective region")
	if weapon_panel.size.x > 312.0 or weapon_panel.size.y > 59.0 or weapon_panel.size.x < 250.0 or weapon_panel.size.y < 44.0:
		failures.append("weapon HUD was not reduced to approximately sixty percent: %s" % weapon_panel.size)
	if quick_panel.size.x > 50.0 or quick_panel.size.y > 48.0:
		failures.append("quick-item HUD was not reduced with the weapon HUD")
	for panel in [info_panel, weapon_panel, quick_panel]:
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null or style.bg_color.a > 0.51:
			failures.append("gameplay HUD panel background exceeds the fifty-percent alpha contract")
			break

	var inventory := dungeon.get("_inventory") as InventoryModule
	var ammo := ItemRegistry.get_instance().get_item("item_ammo_pack")
	# 2026-11-09：出厂豌豆手枪改**弹匣无限**（开火不扣弹、换弹不吃备弹），
	# 它已经验不了「有限备弹按缺口装填」这条规则。规则的样本枪换成步枪 ——
	# **规则本身没变**，只是不能再拿无限弹匣的枪当反例。
	if not bool(dungeon.player.weapon.get("infinite_reserve_ammo")):
		failures.append("出场手枪应为无限备弹（2026-11-09 业主口径）")
	var finite_gun := ItemRegistry.get_instance().get_item("weapon_rifle")
	var equip_finite := dungeon.player.equip_weapon_item_to_slot(finite_gun, 0)
	if not bool(equip_finite.get("success", false)):
		failures.append("cannot equip rifle for the finite-reserve reload check")
	elif bool(dungeon.player.weapon.get("infinite_reserve_ammo")):
		failures.append("rifle must not be flagged as infinite ammo")
	if inventory == null or inventory.add_item(ammo, 5) != 5:
		failures.append("cannot stage five reserve rounds in the backpack")
	else:
		# 2026-11-13 回归（报障：拾取后右下角备弹不更新）：备弹是独立物品，
		# 拾取只改背包计数、**不发 `player.ammo_changed`**（弹匣当前数没变），
		# 所以 HUD 必须靠 `inventory_changed` 立刻重推。这条断言盯的就是那条连线。
		if dungeon.ammo_label == null or not dungeon.ammo_label.text.ends_with("· 5备弹"):
			failures.append(
				"picking up five reserve rounds did not refresh the weapon HUD: %s"
				% ("<null>" if dungeon.ammo_label == null else dungeon.ammo_label.text)
			)
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
			if dungeon.ammo_label == null or not dungeon.ammo_label.text.ends_with("· 0备弹"):
				failures.append(
					"weapon HUD still showed spent reserve ammo after reload: %s"
					% ("<null>" if dungeon.ammo_label == null else dungeon.ammo_label.text)
				)
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

	var rewards := RUNTIME_REWARD_COORDINATOR.new()
	rewards.configure(8312026)
	var elite_drops := rewards.resolve_kill({}, {
		"enemy_type": "melee_chaser",
		"floor": 2,
		"loot_table": "loot_floor_1_2",
		"is_elite": true,
	}, "finite_ammo_elite").get("grants", []) as Array
	var dropped_rounds := 0
	for grant in elite_drops:
		if str(grant.get("item_id", "")) == "item_ammo_pack":
			dropped_rounds += int(grant.get("count", 0))
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
