extends Node

const SCENE := preload("res://scenes/Dungeon3D.tscn")
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func card(id: String, reversed := false) -> FateCard:
	var value := FateCardPresets.get_by_card_id(id)
	value.set_orientation(FateCard.Orientation.REVERSED if reversed else FateCard.Orientation.UPRIGHT, 0.75 if reversed else 0.25)
	return value

func apply(id: String, reversed := false) -> void:
	var result := FateCardGameBridge.apply_card_instance(card(id, reversed))
	check(bool(result.get("success", false)), "正式抽卡 " + id + str(result))

func create_dungeon(real := false) -> Dungeon3D:
	var dungeon := SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = not real
	dungeon.run_seed_override = 20261008
	add_child(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	return dungeon

func seed_state(dungeon: Dungeon3D) -> void:
	var p := dungeon.player
	p.clear_all_equipped_weapons()
	var item := ItemRegistry.get_instance().get_item("weapon_pistol")
	p.equip_weapon_item_to_slot(item, 0)
	p.get_equipped_weapon_instance().fate_slot_capacity = 20
	p.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	FateCardGameBridge.set_player(p)
	apply("fate_overclock")
	apply("fate_gluttony")
	apply("fate_crit_kill")
	apply("fate_crit_kill", true)
	apply("fate_every_seventh", true)
	apply("fate_moon_vitality", true)
	apply("fate_moon_power")
	apply("fate_moon_first_hit", true)
	apply("fate_moon_ammo", true)
	apply("fate_moon_room_heal", true)
	apply("fate_moon_last_stand")
	apply("fate_bless_dead")
	apply("fate_mark_enemy", true)
	apply("fate_sun_key")
	apply("fate_sun_key", true)
	apply("fate_sun_extra_loot", true)
	apply("fate_sun_trial", true)
	apply("fate_sun_scorch", true)
	apply("fate_sun_bounty", true)
	apply("fate_sun_currency", true)
	apply("fate_sun_extraction", true)
	apply("fate_sun_reveal", true)
	p.on_fate_room_entered(dungeon._current_room_id)
	p._character_fate["first_reload_ready"] = false
	p._character_fate["room_hit_count"] = 2
	p._character_fate["last_stands"].clear()
	p._character_fate["last_stand_charges"] = 0
	p._character_fate["kill_rules"][0]["kills"] = 9
	p.current_hp = 10
	p.update_fate_survival(47.0)
	p.current_hp = 43
	p.weapon_tree.growth_stacks = 3
	p.weapon_tree.set("_overheat_shots", 7)
	p.weapon_tree.record_projectile_kill(true)
	p.weapon.set("_reload_first_shot", true)
	p.weapon.set("_fire_sequence", 6)
	p.weapon.current_ammo = 3
	FateCardGameBridge._pending_character_rewards.append({"card": card("fate_moon_stride", true), "currency_cost": 30})
	dungeon._fate_drop_quality_rules[0]["count"] = 2
	dungeon._room_fate_wave_queued["used_room"] = true
	GameManager.currency = 137

func compare(dungeon: Dungeon3D, saved: Dictionary) -> void:
	var p := dungeon.player
	check(p.current_hp == 43 and p.max_hp == 90, "HP与女祭司上限恢复，无即时回血重放")
	check(GameManager.currency == 137, "魂不重复扣除/发放")
	check(dungeon._room_key_count == int(saved["room_key_count"]), "永久钥匙不重复发放")
	check(dungeon._temporary_room_keys == 2, "临时钥匙及楼层归属恢复")
	var expected_cards := (saved["fate_run_state"]["bridge"]["cards"] as Array).size()
	var pending_now := FateCardGameBridge.get_pending_character_rewards()
	check(FateCardGameBridge.get_card_count() == expected_cards, "持卡登记数量不变 actual=%d expected=%d" % [FateCardGameBridge.get_card_count(), expected_cards])
	check(pending_now == [{"stable_card_id": "fate_moon_stride", "orientation": "逆位", "currency_cost": 30}], "愚者固定待领奖励/方位/价格不重抽 actual=%s" % [pending_now])
	check(p._character_fate["room_hit_count"] == 2 and not p._character_fate["first_reload_ready"], "月亮命中计数/首次换弹used flag")
	check(p._character_fate["last_stands"].is_empty(), "已用审判不复活")
	check(p._character_fate["kill_rules"][0]["kills"] == 9, "愚者击杀进度")
	check(p._character_fate["blessings"][0]["stacks"] == 1 and is_equal_approx(p._character_fate["blessings"][0]["elapsed"], 17.0), "祝福层数与计时")
	check(is_equal_approx(p._named_damage_multipliers["fate_bless_dead_0"], 1.1), "祝福具名伤害恢复")
	check(dungeon._extra_loot_next_chest_count == 4 and dungeon._next_chest_max_rarity == "rare", "皇后未来箱子规则")
	check(is_equal_approx(dungeon._next_room_enemy_hp_multiplier, 1.2) and is_equal_approx(dungeon._next_room_enemy_damage_multiplier, 0.64), "未来房间倍率")
	check(dungeon._fate_bounty_queues.size() == 1 and dungeon._fate_drop_quality_rules[0]["count"] == 2, "赏金队列与太阳计数")
	check(dungeon._room_fate_wave_queued.has("used_room"), "增援一次性标记")
	check(is_equal_approx(dungeon._world_currency_multiplier, 0.85) and is_equal_approx(dungeon._extraction_time_multiplier, 1.3), "未来魂和撤离倍率")
	check(p.weapon_tree.growth_stacks == 3 and p.weapon_tree.get("_overheat_shots") == 7, "运行树成长与热")
	check(p.weapon_tree.get("_crit_on_kill_stack") == 1 and p.weapon_tree.get("_crit_damage_shots") == 3, "王后两种待用奖励")
	check(p.weapon.get("_reload_first_shot") and p.weapon.get("_fire_sequence") == 6 and p.weapon.current_ammo == 3, "首发标记/第N发/余弹")
	for slot in 2:
		var source: Dictionary = saved["equipped_weapon_items"][slot]
		check(p.get_equipped_weapon_instance_id_for_slot(slot) == str(source.get("weapon_instance_id", "")), "真实装备实例归属%d" % slot)

func _run() -> void:
	for env in ["APPDATA", "LOCALAPPDATA"]:
		check(OS.get_environment(env).replace("\\", "/").contains("outputs/fate_completion_20261008/persistence"), "Autoload前隔离 " + env)
	if not failures.is_empty():
		get_tree().quit(1)
		return
	check(load("res://src/world3d/TowerDescent3D.gd") != null, "Tower快照段可编译")
	var args := OS.get_cmdline_user_args()
	var writer := "--write" in args
	var reader := "--resume" in args
	var dungeon := create_dungeon(writer or reader)
	for frame in 6:
		await get_tree().process_frame
	var saved: Dictionary
	if reader:
		saved = JSON.parse_string(FileAccess.get_file_as_string("user://fate_expected.json"))
		check(dungeon._run_id == saved["run_id"], "跨进程沿用行动ID")
		compare(dungeon, saved)
	else:
		seed_state(dungeon)
		saved = JSON.parse_string(JSON.stringify(dungeon.build_runtime_save_snapshot()))
		if writer:
			check(BaseManager.flush_runtime_checkpoint("fate_process_write"), "正式BaseManager原子写盘")
			var file := FileAccess.open("user://fate_expected.json", FileAccess.WRITE)
			file.store_string(JSON.stringify(saved))
			file.close()
		else:
			dungeon.free()
			dungeon = create_dungeon()
			await get_tree().process_frame
			dungeon._restore_runtime_save_snapshot(saved)
			compare(dungeon, saved)
			dungeon._restore_runtime_save_snapshot(saved)
			compare(dungeon, saved)
	if not writer:
		var count := FateCardGameBridge.get_card_count()
		var reward := FateCardGameBridge.retry_pending_character_reward()
		check(reward.get("success", false) and GameManager.currency == 107 and FateCardGameBridge.get_card_count() == count + 1, "恢复后领取恰好扣魂/登记一次")
		check(not FateCardGameBridge.retry_pending_character_reward().get("success", false) and GameManager.currency == 107, "已领取拒绝重复")
		FateCardGameBridge.reset_run_state()
		dungeon.reset_world_fate_state()
		check(dungeon.player.max_hp == 100 and dungeon.player.weapon_tree.growth_stacks == 0 and dungeon.player.weapon_tree.get("_overheat_shots") == 0, "reset清角色上限与武器临时状态")
		check(FateCardGameBridge.get_card_count() == 0 and FateCardGameBridge.get_pending_character_rewards().is_empty(), "reset清持卡与待领")
		check(dungeon._fate_bounty_queues.is_empty() and dungeon._world_currency_multiplier == 1.0, "reset清未来世界规则")
		var legacy := saved.duplicate(true)
		legacy.erase("fate_run_state")
		dungeon._restore_runtime_save_snapshot(legacy)
		check(dungeon.player.max_hp == 100 and FateCardGameBridge.get_card_count() == 0, "旧v2无版本键安全默认")
		check(not dungeon.player.import_fate_snapshot({"version": 1, "character": {"room_hit_count": -2}}), "负计数拒绝")
		check(not dungeon.import_world_fate_snapshot({"version": 1, "state": {"_fate_bounty_queues": ["bad"]}}), "损坏队列拒绝")
		check(not FateCardGameBridge.import_fate_snapshot({"version": 1, "cards": [{"stable_card_id": "unknown"}], "pending": []}), "未知牌拒绝")
	if writer or reader:
		BaseManager.unregister_runtime_checkpoint_provider(dungeon, false)
		dungeon._runtime_persistence_active = false
	dungeon.free()
	await get_tree().process_frame
	print("FATE_RESUME_COMPLETION_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures.size(), " mode=", args)
	get_tree().quit(0 if failures.is_empty() else 1)
