extends Node

const DUNGEON := preload("res://scenes/Dungeon3D.tscn")
var dungeon: Dungeon3D
var room: DungeonRoom3D
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
	var result := FateCardPresets.get_by_card_id(id)
	result.set_orientation(FateCard.Orientation.REVERSED if reversed else FateCard.Orientation.UPRIGHT, 0.75 if reversed else 0.25)
	return result

func apply(id: String, reversed := false) -> Dictionary:
	var result := dungeon.apply_world_fate_card(card(id, reversed))
	check(bool(result.get("success", false)), "世界命令 " + id + str(reversed) + str(result))
	return result

func enter(target: DungeonRoom3D) -> void:
	dungeon.player.global_position = target.global_position + Vector3(0, 0.05, 0)
	dungeon._on_room_entered(target)

func prepare() -> void:
	dungeon._cancel_room_wave_intermission(room.room_id)
	for enemy in dungeon.get_node("ActiveEnemies").get_children():
		enemy.free()
	dungeon._enemy_nodes_by_room[room.room_id] = []
	dungeon._room_wave_queues[room.room_id] = []
	dungeon._reserved_room_spawns.erase(room.room_id)
	dungeon._pending_delayed_spawns.erase(room.room_id)
	dungeon._room_fate_wave_queued.erase(room.room_id)
	dungeon.reset_world_fate_state()
	room.cleared = false
	dungeon._current_room_id = room.room_id
	dungeon.player.global_position = room.global_position + Vector3(0, 0.05, 0)
	GameManager.currency = 0

func config() -> Dictionary:
	return {"enemy_type": "melee_chaser", "hp": 20, "max_hp": 20, "damage": 10, "speed": 90, "floor": 1}

func commit() -> Enemy3D:
	var batch: Array[Dictionary] = [config()]
	check(dungeon._commit_room_waves(room, [batch]), "正式波次提交")
	return dungeon._enemy_nodes_by_room[room.room_id][0] as Enemy3D

func pickups() -> Array[GroundLootPickup3D]:
	var result: Array[GroundLootPickup3D] = []
	for child in room.get_children():
		if child is GroundLootPickup3D:
			result.append(child)
	return result

func clear_pickups() -> void:
	for pickup in pickups():
		pickup.free()

func grant_item(rarity := "common") -> Dictionary:
	var item := ItemRegistry.new().get_item("item_room_key").duplicate(true)
	item["rarity"] = rarity
	return {"kind": "item", "item_id": "item_room_key", "item": item, "count": 1}

func _run() -> void:
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("fate_completion_20261008/world"), "APPDATA启动前隔离")
	check(OS.get_environment("LOCALAPPDATA").replace("\\", "/").contains("fate_completion_20261008/world"), "LOCALAPPDATA启动前隔离")
	if not failures.is_empty():
		get_tree().quit(1)
		return
	check(load("res://src/world3d/TowerDescent3D.gd") != null, "Autoload就绪后Tower生命周期脚本可编译")
	EliteRosterService.reset_roster_for_test()
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
	check(room != null, "正式场景存在敌对房")
	if room == null:
		get_tree().quit(1)
		return
	FateCardGameBridge.apply_card_instance(card("fate_moon_room_heal"))
	FateCardGameBridge.apply_card_instance(card("fate_moon_ammo"))
	dungeon.player.current_hp = 40
	dungeon.player.weapon.current_ammo = 0
	var ammo := int(ceil(dungeon.player.weapon.magazine_size * 0.2))
	enter(room)
	check(dungeon.player.current_hp == 46, "streaming前首次进敌房真实回血")
	check(dungeon.player.weapon.current_ammo == ammo, "首次进房实际补弹")
	enter(room)
	check(dungeon.player.current_hp == 46 and dungeon.player.weapon.current_ammo == ammo, "重复入房不双算")
	FateCardGameBridge.apply_card_instance(card("fate_moon_room_heal", true))
	dungeon._mark_room_cleared(room, false)
	check(dungeon.player.current_hp == 58, "正式清房回血12")
	dungeon._mark_room_cleared(room, false)
	check(dungeon.player.current_hp == 58, "重复清房不双算")
	FateCardGameBridge.apply_card_instance(card("fate_bless_dead", true))
	dungeon.player.current_hp = 90
	dungeon._tick_bless_dead(30.01)
	check(dungeon.player.weapon.damage_multiplier > 1.07, "正式祝福计时高血触发")

	prepare()
	commit()
	apply("fate_reinforce")
	var queued_wave := int(dungeon._room_wave_totals[room.room_id])
	var first_enemy: Enemy3D = dungeon._enemy_nodes_by_room[room.room_id][0]
	first_enemy._die()
	check(dungeon._wave_spawn_pending.has(room.room_id) and dungeon._enemy_nodes_by_room[room.room_id].is_empty(), "增援不在击杀当帧补兵")
	await get_tree().create_timer(1.8).timeout
	check(int(dungeon._room_wave_numbers[room.room_id]) == 1, "增援不足两秒不出")
	await get_tree().create_timer(0.3).timeout
	check(int(dungeon._room_wave_numbers[room.room_id]) == queued_wave and dungeon._enemy_nodes_by_room[room.room_id].size() == 3, "抽卡增援两秒后整波实际生成")

	prepare()
	var baseline := commit()
	var base_hp := baseline.max_hp
	var base_damage := baseline.contact_damage
	for reversed in [false, true]:
		prepare()
		apply("fate_sun_trial", reversed)
		apply("fate_sun_scorch", reversed)
		var enemy := commit()
		check(enemy.max_hp == int(round(base_hp * (1.2 if reversed else 0.8))), "节制真实HP " + str(reversed))
		check(enemy.contact_damage == int(round(base_damage * (0.64 if reversed else 1.25))), "正义节制真实伤害 " + str(reversed))
		clear_pickups()
		dungeon._deliver_ground_rewards(room, [{"kind": "currency", "amount": 100}], room.global_position, "trial")
		check(pickups().size() == 1 and pickups()[0].item_data.count == (50 if reversed else 200), "正义实际魂球 " + str(reversed))
		apply("fate_curse_map", reversed)
		var next_batch: Array[Dictionary] = [config()]
		dungeon._spawn_enemy_batch(room, next_batch, true)
		var future := dungeon._enemy_nodes_by_room[room.room_id][-1] as Enemy3D
		check(future.contact_damage == int(round(base_damage * (0.64 * 0.9 if reversed else 1.25 * 1.15))), "诅咒未来波伤害 " + str(reversed))
		clear_pickups()
		dungeon._deliver_ground_rewards(room, [{"kind": "currency", "amount": 100}], room.global_position, "curse")
		check(pickups()[0].item_data.count == (35 if reversed else 200), "诅咒逆位魂落地 " + str(reversed))

	prepare()
	check(not dungeon.apply_world_fate_card(card("fate_sun_reinforce", true)).success, "无正式精英可投放时皇帝逆位拒绝")
	apply("fate_sun_reinforce")
	commit()
	check(dungeon._enemy_nodes_by_room[room.room_id].size() == 4, "皇帝基础波1加3")
	var total := int(dungeon._room_wave_totals[room.room_id])
	apply("fate_reinforce")
	check(int(dungeon._room_wave_totals[room.room_id]) == total + 1, "星币王牌抽后立即排波")
	check(not dungeon.apply_world_fate_card(card("fate_reinforce")).success, "重复增援明确拒绝")
	room.cleared = true
	check(not dungeon.apply_world_fate_card(card("fate_reinforce")).success, "清房抽增援明确拒绝")
	check(not dungeon.apply_world_fate_card(card("fate_curse_map")).success, "清房诅咒明确拒绝")
	for trigger in dungeon._map_fate_triggers._triggers:
		check(trigger.fate_card_id not in ["fate_reinforce", "fate_curse_map", "fate_bless_dead"], "无环境战斗卡白送")
		# 候选品质专项只隔离仍合法的开箱五次奖励，避免它改变被测单张卡。
		trigger.enabled = false

	for mode in ["authored", "boxes"]:
		prepare()
		room.enemy_spawn_plan = {"waves": [{"monsters": [{"type": "melee_chaser", "count": 1}]}]}
		var reference_waves := dungeon._authored_spawn_waves(room, 1, 0)
		if mode == "boxes":
			room.spawn_placements = [{"box": "box_room_spread", "box_center": Vector2.ZERO, "box_size": Vector2(12, 12)}]
			reference_waves = dungeon._spawn_box_waves(room, 1, 0)
		var expected := 0
		for wave in reference_waves:
			expected += (wave as Array).size()
		check(expected > 0, "正式设计源前置 " + mode)
		apply("fate_sun_reinforce")
		dungeon._spawn_room_enemies(room)
		var actual := int(dungeon._alive_by_room.get(room.room_id, 0))
		for wave in dungeon._room_wave_queues.get(room.room_id, []):
			actual += (wave as Array).size()
		check(actual == expected + 3, "皇帝覆盖设计源与盒子 " + mode + " expected=" + str(expected) + " actual=" + str(actual))
		room.spawn_placements.clear()
		room.enemy_spawn_plan.clear()

	prepare()
	room.set_meta("floor_number", EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", dungeon.run_seed))
	apply("fate_sun_reinforce", true)
	var elite_configs := dungeon._next_room_elite_configs.duplicate(true)
	commit()
	var elite: Enemy3D = dungeon._enemy_nodes_by_room[room.room_id][-1]
	check(bool(elite.get_enemy_data().get("is_elite", false)), "皇帝真实精英属性")
	FateCardGameBridge.apply_card_instance(card("fate_moon_elite_heal", true))
	var shield_before := int(dungeon.player._character_fate.shield)
	elite.transition_to("chase", "verification")
	check(int(dungeon.player._character_fate.shield) == shield_before + 20, "真实精英进战获得20盾")
	elite.transition_to("telegraph", "verification")
	check(int(dungeon.player._character_fate.shield) == shield_before + 20, "精英遭遇护盾幂等")
	dungeon._mark_room_cleared(room, false)
	check(GameManager.currency == 50, "皇帝逆位清房实际50魂")
	for elite_config in elite_configs:
		EliteRosterService.settle(str(elite_config.elite_id), str(elite_config.encounter_instance_id), "despawned")
	prepare()
	commit()
	apply("fate_reinforce", true)
	var queued: Array = dungeon._room_wave_queues[room.room_id][-1]
	check(queued.size() == 1 and bool(queued[0].is_elite), "王牌逆位队列只有一精英")
	var extra_batch: Array[Dictionary] = []
	extra_batch.assign(queued)
	dungeon._room_wave_queues[room.room_id] = []
	dungeon._spawn_enemy_batch(room, extra_batch, true)
	var extra_elite: Enemy3D = dungeon._enemy_nodes_by_room[room.room_id][-1]
	check(int(extra_elite.get_meta("fate_kill_currency", 0)) == 50, "王牌精英击杀赏金绑定来源")
	clear_pickups()
	extra_elite._die()
	await get_tree().process_frame
	var soul_total := 0
	var soul_count := 0
	for pickup in pickups():
		if str(pickup.item_data.get("type", "")) == "currency":
			soul_total += int(pickup.item_data.count)
			soul_count += 1
	check(soul_total >= 50 and soul_count == 1, "王牌击杀赏金实际合并一个魂球")
	room.remove_meta("floor_number")

	prepare()
	apply("fate_sun_bounty")
	apply("fate_sun_bounty", true)
	for index in 3:
		var key := "bounty_room_%d" % index
		var old_id := room.room_id
		room.room_id = key
		room.cleared = false
		dungeon._note_room_enemy_modifiers(room)
		dungeon._mark_room_cleared(room, false)
		check(GameManager.currency == [155, 190, 225][index], "独立赏金不串量 " + str(index))
		clear_pickups()
		dungeon._deliver_ground_rewards(room, [{"kind": "currency", "amount": 100}], room.global_position, key)
		check(pickups().size() == (1 if index == 0 else 0), "逆赏金后两房禁魂 " + str(index))
		room.room_id = old_id

	prepare()
	apply("fate_sun_currency", true)
	check(dungeon._grant_run_currency(100) == 85 and GameManager.currency == 85, "太阳逆位真实钱包85")
	clear_pickups()
	for index in 3:
		dungeon._deliver_ground_rewards(room, [grant_item()], room.global_position, "quality_%d" % index)
	check(pickups().size() == 3 and pickups()[2].item_data.rarity == "uncommon", "太阳第三实际地面物升品")
	check(pickups()[0].item_data.rarity == "common", "前两物不升品")
	var ranked := dungeon._ground_reward_candidates([grant_item("common"), grant_item("epic")])
	check(dungeon._fate_rarity_rank(ranked[1].item) > dungeon._fate_rarity_rank(ranked[0].item), "皇后按实际稀有度而非池档位排序")
	prepare()
	room.reward_plan = {"search": {"entries": [{"kind": "item", "item_id": "item_health_potion", "count": 1}]}}
	var source_rarity := dungeon._fate_rarity_rank(ItemRegistry.new().get_item("item_health_potion"))
	for spec in [["fate_lucky_chest", true, -1, 2], ["fate_extra_loot", true, 1, 1], ["fate_sun_quality", true, 2, 0]]:
		dungeon._next_chest_quality_boost = 0
		dungeon._extra_loot_next_chest_count = 0
		apply(spec[0], spec[1])
		check(dungeon._next_chest_quality_boost == spec[2] and dungeon._extra_loot_next_chest_count == spec[3], "下一箱完整升降与候选 " + spec[0])
		clear_pickups()
		dungeon._on_prop_searched(room, {"prop_id": spec[0], "size_class": "medium"})
		check(pickups().size() == 1 and pickups()[0].item_data.count == 1, "搜索始终实际单件 " + spec[0])
		check(dungeon._fate_rarity_rank(pickups()[0].item_data) == clampi(source_rarity + int(spec[2]), 0, 4), "搜索真实升降品质 " + spec[0])
	clear_pickups()
	room.reward_plan = {"search": {"entries": [{"kind": "item", "item_id": "weapon_charge", "count": 1}]}}
	apply("fate_sun_extra_loot", true)
	dungeon._on_prop_searched(room, {"prop_id": "empress", "size_class": "large"})
	check(pickups().size() == 1 and dungeon._fate_rarity_rank(pickups()[0].item_data) <= 2, "皇后真实搜索RARE上限")
	clear_pickups()
	room.reward_plan = {"search": {"entries": [
		{"kind": "item", "item_id": "item_health_potion", "count": 1},
		{"kind": "item", "item_id": "weapon_charge", "count": 1},
	]}}
	apply("fate_sun_extra_loot")
	dungeon._on_prop_searched(room, {"prop_id": "empress_best", "size_class": "large"})
	check(pickups().size() == 1 and pickups()[0].item_data.id == "weapon_charge" and pickups()[0].item_data.rarity == "epic", "皇后正位实际选择最高稀有度单件")
	var quality := {"rarity": "epic", "type": "weapon", "weapon_instance": {"rarity": "epic"}}
	dungeon._apply_fate_item_quality(quality, -1)
	check(quality.rarity == "rare" and quality.weapon_instance.rarity == "rare", "真实品质降级与枪实例一致")

	prepare()
	var keys := dungeon._room_key_count
	apply("fate_sun_key", true)
	dungeon._consume_room_key()
	check(dungeon._temporary_room_keys == 1 and dungeon._room_key_count == keys, "临时钥匙优先消耗")
	var away := dungeon._room_by_id["start"] as DungeonRoom3D
	away.set_meta("floor_number", 999)
	enter(away)
	check(dungeon._temporary_room_keys == 0, "正式跨层进房临时钥匙失效")
	apply("fate_sun_key")
	check(dungeon._room_key_count == keys + 1, "教皇正位真实永久钥匙")
	apply("fate_sun_reveal", true)
	check(not dungeon.minimap._hidden_room_types.is_empty(), "拓扑隐藏类型实际状态")
	for hidden in dungeon.minimap._hidden_room_types:
		check(dungeon.minimap.get_visible_room_type(hidden).is_empty(), "隐藏房型查询不可泄漏")

	prepare()
	var slow_enemy := commit()
	var speed := slow_enemy.move_speed
	var beacon := dungeon._create_extraction_beacon(room, "STANDARD", 30.0, false, Vector3.ZERO)
	beacon.force_start_for_test()
	apply("fate_sun_extraction", true)
	check(is_equal_approx(beacon.duration, 39.0) and is_equal_approx(beacon._remaining, 39.0), "逆世界实时剩余撤离变39秒")
	slow_enemy.global_position = beacon.global_position
	dungeon._update_fate_extraction_slow()
	check(is_equal_approx(slow_enemy.move_speed, speed * 0.5), "撤离区域真实移速减半")
	slow_enemy.global_position += Vector3(4, 0, 0)
	dungeon._update_fate_extraction_slow()
	check(is_equal_approx(slow_enemy.move_speed, speed), "离开撤离区域恢复移速")
	apply("fate_sun_extraction")
	check(is_equal_approx(beacon.duration, 31.2), "世界正逆乘法叠加")
	beacon.abort_extraction()
	dungeon.reset_world_fate_state()
	check(is_equal_approx(beacon.duration, 30.0), "结算重置撤离倍率")

	dungeon.queue_free()
	for index in 4:
		await get_tree().process_frame
	print("FATE_WORLD_CHECKS=", checks, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FATE_WORLD_COMPLETION_OK")
	get_tree().quit(0 if failures.is_empty() else 1)
