extends Node

const SERVICE := preload("res://src/game/FateEconomyService.gd")
const BOXES := preload("res://src/map/SpawnBoxCatalog.gd")
const EXPEDITION := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED := 515151
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_check_pure_economy()
	await _check_formal_expedition()
	for failure in failures:
		push_error(failure)
	print("FATE_ECONOMY_SERVICE_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_pure_economy() -> void:
	var rules := {
		"per_tier": {"elite": {"base": 50, "per_floor": 20}, "boss": {"base": 200, "per_floor": 20}},
		"per_kind": {
			"melee_chaser": {"base": 4, "per_floor": 1},
			"ranged_caster": {"base": 7, "per_floor": 1},
			"melee_chaser_strong": {"base": 4, "per_floor": 1},
			"ranged_caster_strong": {"base": 7, "per_floor": 1},
			"fat_zombie03_strong": {"base": 20, "per_floor": 4},
		}, "default": {"base": 4, "per_floor": 1},
	}
	var boxes := {
		"normalized": {"spawns": [{"type": "melee_chaser", "count_min": 2, "count_max": 2}, {"type": "elite", "count_min": 1, "count_max": 1}]},
		"raw": {"spawns": [{"type": "ranged_caster", "count": {"min": 1, "max": 3}}, {"type": "boss", "count": 1}]},
		"unused": {"spawns": [{"type": "boss", "count": 99}]},
	}
	var placements := [{"box": "normalized", "count_multiplier": 2, "count_bonus": 1}, {"box": "raw"}, {"box": "unused"}]
	var stages := {"stages": [{"boxes": [0, 0]}, {"boxes": [1]}]}
	var rooms := [{"spawn_placements": placements, "encounter": stages}, {"encounter": {"stages": [{"monsters": [{"type": "strong_random", "count": 3}]}]}}]
	var service = SERVICE.new()
	service.configure_from_runtime(rooms, boxes, rules, 1, 10)
	var income: Dictionary = service.get_snapshot()["reference_income"]
	# 两次盒0：2×(5只小怪×5+1精英×70)=190；盒1=228/236/244；随机强化3只=15/37/72。
	_expect(income == {"min": 433, "expected": 463, "max": 506}, "混合编成手算433/463/506不匹配：%s" % income)
	_expect(service._selected_box_indexes(stages, 3) == [0, 0, 1], "重复调用盒被去重")
	_expect(service._selected_box_indexes({"stages": [{"boxes": []}]}, 3).is_empty(), "显式空波次错误回退所有盒")
	var normalized = SERVICE.new()
	var raw = SERVICE.new()
	normalized.configure_from_runtime([{"spawn_placements": [{"box": "x"}]}], {"x": BOXES.load_box("box_wall_arc")}, rules, 1, 1)
	raw.configure_from_runtime([{"spawn_placements": [{"box": "x"}]}], {"x": {"spawns": [{"type": "ranged_caster", "count": {"min": 1, "max": 2}}]}}, rules, 1, 1)
	_expect(raw.get_snapshot()["reference_income"] == normalized.get_snapshot()["reference_income"], "raw与normalized区间不一致")
	# 星币七只截断不抬价：封顶后必须等于 min(原报价, 100)，旧 bug 是把低报价抬到 100。
	var raw_bounds: Dictionary = service.price_bounds_for_rarity(0)
	var capped_bounds: Dictionary = service.price_bounds_for_card(0, "fate_sun_bounty")
	_expect(int(capped_bounds["quote"]) == mini(int(raw_bounds["quote"]), 100), "星币七报价未按min(原报价,100)截断（或被抬到100）：原%d 封顶后%d" % [raw_bounds["quote"], capped_bounds["quote"]])
	for offer in range(20):
		for rarity in range(5):
			# 报价按门序号取基准房收益，上下界必须与该门一致，否则冻结价会越界。
			var bounds: Dictionary = service.price_bounds_for_rarity(rarity, offer)
			var span := maxi(1, int((int(bounds["max"]) - int(bounds["min"])) / 10.0) + 1)
			var original_quote := int(bounds["min"]) + absi(hash("%d|%d|%d|%s" % [SEED, offer, rarity, "fate_sun_bounty"])) % span * 10
			_expect(service.frozen_quote_for_card(rarity, offer, "fate_sun_bounty", SEED) == mini(original_quote, 100), "星币七未按min(原报价,100)截断")
	_check_boundaries(service)
	var zero = SERVICE.new()
	zero.configure_from_runtime([], {}, rules, 1, 10)
	zero.record_actual_kill_income(10000)
	_expect(zero.max_unlocked_rarity() == 0, "零参考收益解锁贵卡")
	print("FATE_HANDCALC min=%d expected=%d max=%d" % [income["min"], income["expected"], income["max"]])


func _check_boundaries(service: RefCounted) -> void:
	var thresholds: Array = service.get_snapshot()["rarity_unlock_thresholds"]
	for rarity in range(1, 5):
		var threshold := int(thresholds[rarity])
		service.import_snapshot({"schema_version": 2, "actual_kill_income": threshold - 1, "actual_kill_events": 0})
		_expect(service.max_unlocked_rarity() == rarity - 1, "稀有度%d边界下提前解锁" % rarity)
		service.record_actual_kill_income(1)
		_expect(service.max_unlocked_rarity() == rarity, "稀有度%d边界未解锁" % rarity)
	service.import_snapshot({"schema_version": 2, "actual_kill_income": 0, "actual_kill_events": 0})
	_expect(service.max_unlocked_rarity() == 0, "零实际收入提前解锁")


func _check_one_card_per_door(formal: Dictionary) -> void:
	var segments: Array = formal["segment_income_expected"]
	var table: Array = formal["door_price_table"]
	_expect(table.size() == int(formal["door_count"]), "逐门价表没有覆盖全部构筑门")
	var spent := 0
	var first_purchase_slot := -1
	var floor_price := int(formal.get("min_card_price", 40))
	for row: Dictionary in table:
		var door := int(row["door"])
		var segment_index := int(row["segment_index"])
		var segment_income := int(row["segment_income"])
		var base := int(row["base"])
		var prices: Array = row["prices"]
		var cheapest := int(prices[0])
		var cumulative := 0
		# 第 door 门打开时已清完的房间 = 序号 0..door-1（第 1 门只有安全屋，无收益）。
		for cursor in range(mini(door, segments.size())):
			cumulative += int(round(float(segments[cursor])))
		print("FATE_DOOR_PRICE door=%d segment_index=%d segment=%d base=%d cumulative=%d common=%d rare=%d epic=%d legend=%d mystic=%d" % [
			door, segment_index, segment_income, base, cumulative,
			int(prices[0]), int(prices[1]), int(prices[2]), int(prices[3]), int(prices[4]),
		])
		if segment_income <= 0:
			continue
		# 一间房的参考收益：买得下一张普通卡，但**买不下三张**。
		_expect(cheapest <= maxi(base, floor_price), "第%d门普通卡贵过该门基准（%d>%d）" % [door, cheapest, base])
		_expect(cheapest * 3 > segment_income, "第%d门同一间房收益就能买三张（%d×3<=%d）" % [door, cheapest, segment_income])
		_expect(int(prices[2]) > segment_income, "第%d门史诗卡不高于一间房收益（%d<=%d）" % [door, prices[2], segment_income])
		# 按「有钱就买最便宜一张」模拟整条主路，检查保底与"不能三张"。
		var wallet := cumulative - spent
		var affordable := 0
		for price in prices:
			if int(price) <= wallet:
				affordable += 1
		_expect(affordable >= 1 or wallet <= 0, "第%d门连一张普通卡都买不起（钱包%d，最低%d）" % [door, wallet, cheapest])
		_expect(affordable < 3, "第%d门同一间房收益可买三张（钱包%d）" % [door, wallet])
		if first_purchase_slot < 0 and affordable >= 1:
			first_purchase_slot = affordable
		if wallet >= cheapest:
			spent += cheapest
	_expect(first_purchase_slot == 1, "首次买得起的门不是只够一张（%d）" % first_purchase_slot)
	print("FATE_ONE_CARD_PER_DOOR first_slot=%d spent=%d" % [first_purchase_slot, spent])


func _spawn_expedition(snapshot: Dictionary = {}) -> TowerDescent3D:
	var dungeon := EXPEDITION.instantiate() as TowerDescent3D
	dungeon.test_mode = true
	dungeon.run_seed_override = SEED
	if not snapshot.is_empty():
		dungeon.set("_runtime_restore_snapshot", snapshot)
	add_child(dungeon)
	for frame in range(8):
		await get_tree().process_frame
	dungeon.player.set_physics_process(false)
	dungeon.player.set_process(false)
	return dungeon


func _check_formal_expedition() -> void:
	var dungeon: TowerDescent3D = await _spawn_expedition()
	var economy: RefCounted = dungeon.get("_fate_economy")
	var formal: Dictionary = economy.get_snapshot()
	var income: Dictionary = formal["reference_income"]
	_expect(dungeon.get_runtime_map_id() == "expedition_01" and bool(formal["configured"]), "正式远征未配置经济")
	_expect(int(income["min"]) > 0 and int(income["min"]) <= int(income["expected"]) and int(income["expected"]) <= int(income["max"]), "正式Y边界非法")
	_expect(int(formal["floor"]) == dungeon.visual_theme.difficulty_rank, "参考floor与运行怪物/奖励floor不一致")
	_expect(int(formal["door_count"]) == 10, "构筑门分母不是10个内容房")
	print("FATE_FORMAL_Y seed=%d floor=%d doors=%d min=%d expected=%d max=%d" % [SEED, formal["floor"], formal["door_count"], income["min"], income["expected"], income["max"]])
	for row: Dictionary in formal["price_bounds"]:
		print("FATE_FORMAL_PRICE rarity=%d min=%d centre=%d max=%d threshold=%d" % [row["rarity"], row["min"], row["quote"], row["max"], formal["rarity_unlock_thresholds"][int(row["rarity"])]])
	_check_one_card_per_door(formal)
	_check_boundaries(economy)
	var stages := {"stages": [{"boxes": [0, 0]}, {"boxes": [1]}]}
	var production: Array = dungeon.call("_resolve_encounter_stages", stages, 3)
	var flattened: Array = []
	for stage: Array in production:
		flattened.append_array(stage)
	_expect(economy._selected_box_indexes(stages, 3) == flattened, "经济重复盒语义与生产不一致")
	var main_rng: RandomNumberGenerator = dungeon.get("_rng")
	var rng_before := main_rng.state
	# 01新局仅正位；历史逆位快照兼容由verify_fate_level01_pool覆盖。
	var sample_offer_id := 0
	var signatures: Dictionary = {}
	var reversed_count := 0
	for offer_id in range(40):
		dungeon.set("_fate_door_offer_id", offer_id)
		var cards: Array[FateCard] = dungeon.call("_gate_expedition_fate_offer")
		_expect(cards.size() == 2, "01白名单普通交集应为两张，不得越界补第三张")
		var ids: Array[String] = []
		for card in cards:
			_expect(card.card_rarity == FateCard.CardRarity.COMMON, "零击杀池混入贵卡")
			_expect(card.get_stable_card_id() not in ids, "正式池三卡重复")
			ids.append(card.get_stable_card_id())
			if card.is_reversed():
				reversed_count += 1
		signatures["|".join(ids)] = true
	_expect(reversed_count == 0, "01不得生成逆位")
	_expect(signatures.size() > 1, "前期随机抽牌退化为固定排列")
	_expect(main_rng.state == rng_before, "抽牌污染主随机流")
	print("FATE_FORMAL_RANDOM offers=40 identity_sets=%d reversed=%d slots=80" % [signatures.size(), reversed_count])
	dungeon.set("_fate_door_offer_id", sample_offer_id)
	dungeon.call("_show_door_fate_choices")
	var zero_offer: Dictionary = dungeon.call("_export_door_fate_snapshot")
	dungeon.call("_close_door_fate_overlay")
	_expect(dungeon.try_open_room_door("room_01"), "正式入口门未开启")
	dungeon.force_enter_room_for_test("room_01")
	dungeon.player.global_position = ((dungeon.get("_room_by_id") as Dictionary)["room_01"] as DungeonRoom3D).global_position + Vector3.UP * 0.1
	for frame in range(3):
		await get_tree().process_frame
	var room: DungeonRoom3D = (dungeon.get("_room_by_id") as Dictionary).get("room_01")
	var enemies: Array = (dungeon.get("_enemy_nodes_by_room") as Dictionary).get("room_01", []).duplicate()
	_expect(not enemies.is_empty(), "正式room_01没有真实敌人")
	var reward_coordinator: RefCounted = dungeon.get("_reward_coordinator")
	var expected_actual := 0
	var kills_before := int(dungeon.get("_kills"))
	for enemy: Enemy3D in enemies:
		if not is_instance_valid(enemy) or enemy.ai_state == "dead":
			continue
		var data := enemy.get_enemy_data()
		_expect(int(data.get("floor", 1)) == int(formal["floor"]), "真实怪物floor未对齐")
		var report: Dictionary = reward_coordinator.resolve_kill(room.reward_plan, data, "%s:%s" % [room.room_id, enemy.get_persistent_id()])
		for grant: Dictionary in report["grants"]:
			if str(grant.get("kind", "")) == "currency":
				expected_actual += int(grant.get("amount", 0))
		enemy.take_damage(1000000)
	_expect(economy.actual_kill_income() == expected_actual and expected_actual > 0, "真实死亡信号→_on_enemy_killed未记录grants金币")
	_expect(int(dungeon.get("_kills")) > kills_before and int(economy.get_snapshot()["actual_kill_events"]) > 0, "实际击杀记账没有事件")
	print("FATE_FORMAL_KILL actual=%d resolved_grants=%d kills=%d" % [economy.actual_kill_income(), expected_actual, int(dungeon.get("_kills")) - kills_before])
	# room_01的混编盒含1秒延迟怪，必须等实到后继续走同一死亡信号链，不能伪造cleared。
	await get_tree().create_timer(1.5).timeout
	var delayed: Array = (dungeon.get("_enemy_nodes_by_room") as Dictionary).get("room_01", []).duplicate()
	for enemy: Enemy3D in delayed:
		if not is_instance_valid(enemy) or enemy.ai_state == "dead":
			continue
		var report: Dictionary = reward_coordinator.resolve_kill(room.reward_plan, enemy.get_enemy_data(), "%s:%s" % [room.room_id, enemy.get_persistent_id()])
		for grant: Dictionary in report["grants"]:
			if str(grant.get("kind", "")) == "currency":
				expected_actual += int(grant.get("amount", 0))
		enemy.take_damage(1000000)
	_expect(economy.actual_kill_income() == expected_actual, "延迟怪击杀收入未记入")
	print("FATE_FORMAL_KILL_TOTAL actual=%d resolved_grants=%d cleared=%s alive=%d" % [economy.actual_kill_income(), expected_actual, room.cleared, int((dungeon.get("_alive_by_room") as Dictionary).get("room_01", -1))])
	await get_tree().create_timer(1.2).timeout
	await _collect_room_currency(dungeon, room)
	_expect(GameManager.currency > 0, "真实击杀金币球未拾取到钱包")
	dungeon.player.global_position = room.global_position + Vector3.UP * 0.1
	dungeon.force_enter_room_for_test(room.room_id)
	dungeon.set("_room_key_count", 10)
	_expect(dungeon.try_open_room_door("room_02"), "真实清房后第二门未开启")
	await get_tree().process_frame
	_expect(bool(dungeon.get("_door_fate_active")), "正式第二门未显示报价")
	var earned_offer: Dictionary = dungeon.call("_export_door_fate_snapshot")
	_expect(earned_offer["offer_id"] == sample_offer_id + 2, "门序号未顺序推进")
	print("FATE_FORMAL_OFFER phase=early actual=%d wallet=%d cards=%s" % [economy.actual_kill_income(), GameManager.currency, JSON.stringify(earned_offer["cards"])])
	var quotes: Dictionary = dungeon.get("_fate_door_quote").duplicate(true)
	GameManager.add_currency(500)
	dungeon.call("_refresh_door_fate_prices")
	_expect((dungeon.get("_fate_door_quote") as Dictionary) == quotes, "钱包增加后冻结价变化")
	var current_choices: Array = dungeon.get("_door_fate_choices")
	for reverse_index in range(current_choices.size() - 1, -1, -1):
		var card: FateCard = current_choices[reverse_index]
		_expect(int(dungeon.call("_fate_price", card)) == int(quotes[card.get_stable_card_id()]), "查询顺序改变报价")
	var selected := -1
	var choices: Array = dungeon.get("_door_fate_choices")
	for index in range(choices.size()):
		var card := choices[index] as FateCard
		if FateCardGameBridge.requires_source_selection(card):
			continue
		var before := GameManager.currency
		var price: int = dungeon.call("_fate_price", card)
		await dungeon.call("_purchase_fate_card", index)
		if (dungeon.get("_door_fate_purchased") as Array)[index]:
			_expect(before - GameManager.currency == price, "正式购卡扣费不等于冻结价")
			selected = index
			print("FATE_FORMAL_PURCHASE index=%d id=%s price=%d before=%d after=%d" % [index, card.get_stable_card_id(), price, before, GameManager.currency])
			break
		_expect(before == GameManager.currency, "应用失败未原额退款")
	_expect(selected >= 0, "正式报价没有一张完成真实购买")
	_expect((dungeon.get("_fate_door_quote") as Dictionary) == quotes, "扣款后其它报价变化")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(dungeon.build_runtime_save_snapshot()))
	var door_before: Dictionary = (snapshot["fate_run_state"] as Dictionary)["door"]
	var reversed_saved := false
	for card_row: Dictionary in door_before["cards"]:
		if str(card_row["orientation"]) == "REVERSED":
			reversed_saved = true
	_expect(not reversed_saved, "01新局快照不得出现逆位")
	dungeon.queue_free()
	for frame in range(3):
		await get_tree().process_frame
	dungeon = await _spawn_expedition(snapshot)
	dungeon.call("_restore_runtime_save_snapshot", snapshot)
	# UI重建前也要按已购数据拒绝，不能依赖按钮metadata。
	if selected >= 0:
		_expect(str(dungeon.call("_fate_card_block_reason", selected)) == "purchased", "恢复UI前已购卡可重买")
	for frame in range(8):
		await get_tree().process_frame
	var door_after: Dictionary = JSON.parse_string(JSON.stringify(dungeon.call("_export_door_fate_snapshot")))
	_expect(bool(dungeon.get("_door_fate_active")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") != null, "销毁重建后active报价未恢复")
	_expect(door_before == door_after, "候选/正逆/roll/报价/已购/门序号恢复不同：before=%s after=%s" % [door_before, door_after])
	_expect((dungeon.get("_fate_economy") as RefCounted).actual_kill_income() == expected_actual, "实际击杀收入恢复不一致")
	if selected >= 0:
		var before := GameManager.currency
		await dungeon.call("_purchase_fate_card", selected)
		_expect(GameManager.currency == before, "恢复后重复购买再次扣费")
	print("FATE_FORMAL_RESUME same=%s offer_id=%d purchased_index=%d" % [door_before == door_after, int(door_after.get("offer_id", 0)), selected])
	var resumed_choices: Array = dungeon.get("_door_fate_choices")
	# 新经济：单门三张价格 ≈ 2.5~3 间房的收益，"存够钱"必须按本门冻结报价真给够，
	# 不能再沿用旧的 500 金币（旧价 20/30/20 时代够用，新价下两张都买不起）。
	var outstanding := 0
	for index in range(resumed_choices.size()):
		if (dungeon.get("_door_fate_purchased") as Array)[index]:
			continue
		outstanding += int(dungeon.call("_fate_price", resumed_choices[index]))
	if GameManager.currency < outstanding:
		GameManager.add_currency(outstanding - GameManager.currency + 10)
	for index in range(resumed_choices.size()):
		if (dungeon.get("_door_fate_purchased") as Array)[index]:
			continue
		var before := GameManager.currency
		var price: int = dungeon.call("_fate_price", resumed_choices[index])
		await dungeon.call("_purchase_fate_card", index)
		_expect((dungeon.get("_door_fate_purchased") as Array)[index], "存钱后未能购买本门剩余卡")
		_expect(before - GameManager.currency == price, "同门全买扣费不守恒")
	_expect((dungeon.get("_door_fate_purchased") as Array).count(true) == resumed_choices.size(), "后续购买被强制限张数")
	print("FATE_FORMAL_ALL_BOUGHT count=%d wallet=%d" % [resumed_choices.size(), GameManager.currency])
	dungeon.call("_close_door_fate_overlay")
	var closed_offer_id := int(dungeon.get("_fate_door_offer_id"))
	var closed: Dictionary = dungeon.build_runtime_save_snapshot()
	_expect(int(closed["fate_run_state"]["door"]["offer_id"]) == closed_offer_id, "关闭报价后丢失门序号")
	# 下面两段只注入测试赏金到真实奖励grants通道，明确不冒充整关自然游玩收入。
	await _quote_phase_with_reward_fixture(dungeon, "middle", int(income["expected"]) / 2)
	await _quote_phase_with_reward_fixture(dungeon, "late", int(ceil(float(income["expected"]) * 0.85)))
	var repeat: Dictionary = zero_offer
	dungeon.queue_free()
	for frame in range(3):
		await get_tree().process_frame
	dungeon = await _spawn_expedition()
	dungeon.set("_fate_door_offer_id", sample_offer_id)
	dungeon.call("_show_door_fate_choices")
	_expect((dungeon.call("_export_door_fate_snapshot") as Dictionary) == repeat, "同种子重启第一次候选/正逆/报价不同")
	dungeon.call("_close_door_fate_overlay")
	dungeon.queue_free()
	for frame in range(3):
		await get_tree().process_frame
	print("FATE_FORMAL_PATH_COMPLETED")


func _collect_room_currency(dungeon: TowerDescent3D, room: DungeonRoom3D) -> void:
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if not value is GroundLootPickup3D or not room.is_ancestor_of(value):
			continue
		var pickup := value as GroundLootPickup3D
		if not bool(pickup.item_data.get("is_currency", false)):
			continue
		dungeon.player.global_position = pickup.global_position
		dungeon.call("_on_ground_loot_requested", pickup, pickup.item_data)
	await get_tree().process_frame


func _quote_phase_with_reward_fixture(dungeon: TowerDescent3D, phase: String, target_income: int) -> void:
	var economy: RefCounted = dungeon.get("_fate_economy")
	var room: DungeonRoom3D = (dungeon.get("_room_by_id") as Dictionary)["room_01"]
	var injector: RefCounted = dungeon.get("_monster_injector")
	var config: Dictionary = injector.generate_box_enemy("melee_chaser", dungeon.visual_theme.difficulty_rank, 0)
	config["elite_bounty_currency"] = maxi(0, target_income - economy.actual_kill_income())
	config["persistent_id"] = "economy_reward_fixture_%s" % phase
	var configs: Array[Dictionary] = [config]
	var spawned: int = dungeon.call("_spawn_enemy_batch", room, configs, true, false, [room.global_position + Vector3.UP * 0.1])
	_expect(spawned == 1, "测试赏金敌人未由正式批次生成")
	for enemy: Enemy3D in (dungeon.get("_enemy_nodes_by_room") as Dictionary).get(room.room_id, []):
		if enemy.get_persistent_id() == config["persistent_id"]:
			enemy.take_damage(1000000)
			break
	await get_tree().process_frame
	_expect(economy.actual_kill_income() >= target_income, "测试赏金未通过真实击杀grants记入actual")
	dungeon.call("_show_door_fate_choices")
	var state: Dictionary = dungeon.call("_export_door_fate_snapshot")
	print("FATE_FORMAL_OFFER phase=%s source=kill_grants_bounty_fixture actual=%d max_rarity=%d cards=%s" % [phase, economy.actual_kill_income(), economy.max_unlocked_rarity(), JSON.stringify(state["cards"])])
	var high_seen := false
	var saved_id := int(dungeon.get("_fate_door_offer_id"))
	for probe_id in range(saved_id, saved_id + 40):
		dungeon.set("_fate_door_offer_id", probe_id)
		var probe_cards: Array[FateCard] = dungeon.call("_gate_expedition_fate_offer")
		for card in probe_cards:
			_expect(int(card.card_rarity) <= economy.max_unlocked_rarity(), "正式阶段抽入未解锁贵卡")
			if int(card.card_rarity) >= 3:
				high_seen = true
	dungeon.set("_fate_door_offer_id", saved_id)
	_expect(high_seen == (phase == "late"), "中期禁贵卡/后期可见贵卡不成立")
	print("FATE_FORMAL_HIGH_POOL phase=%s high_rarity_seen=%s samples=40" % [phase, high_seen])
	for card: FateCard in dungeon.get("_door_fate_choices"):
		var price: int = dungeon.call("_fate_price", card)
		var bounds: Dictionary = dungeon.call("_fate_price_bounds", card)
		_expect(price >= int(bounds["min"]) and price <= int(bounds["max"]), "正式%s报价越界" % phase)
		_expect(int(card.card_rarity) <= economy.max_unlocked_rarity(), "未解锁贵卡入池")
	dungeon.call("_close_door_fate_overlay")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
