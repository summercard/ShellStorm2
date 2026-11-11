extends Node
## 纯服务专项：只读内容，裸箱不入树；启动前必须隔离 APPDATA。

const CLEAR := preload("res://src/game/ClearDropService.gd")
const CHEST := preload("res://src/rewards/ChestRewardService.gd")
const REWARD := preload("res://src/rewards/RewardService.gd")
const ECONOMY := preload("res://src/game/FateEconomyService.gd")
const PLAN := "res://data/level_plans/expedition_01/level_plan.json"
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(OS.get_environment("APPDATA").contains("2026-11-11_expedition01_flow"), "必须在 Autoload 前隔离用户目录")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))["clear_drops"]
	var service := CLEAR.new()
	_check(service.configure(config)["ok"], "配置应通过")
	for seed_value in [1, 7, 2026, 42, 808]:
		var ammo := 0
		var health := 0
		var weapons := 0
		for index in range(1, 11):
			var room_id := "room_%02d" % index
			var drop: Dictionary = service.roll_room_drop(room_id, "content", seed_value)
			_check(drop == service.roll_room_drop(room_id, "content", seed_value), "计划必须可复现")
			for grant in drop.get("grants", []):
				_check(grant["item_id"] in ["item_ammo_pack", "item_health_potion"], "小包不得额外发币或新物品")
				if grant["item_id"] == "item_ammo_pack": ammo += int(grant["count"])
				else: health += int(grant["count"])
			var chest_config: Dictionary = drop["chest"]
			_check(not chest_config.has("grants") and not chest_config.has("additional_weapon"), "箱与小包必须分账")
			if index in [1, 2, 7, 9, 10]: _check(not chest_config["mimic"], "关键箱禁拟态")
			var report := CHEST.resolve(chest_config, seed_value, room_id, 1)
			_check(report["ok"], "箱奖励解析应通过")
			var fate := 0
			for grant in report["grants"]:
				var item: Dictionary = grant["item"]
				if grant["item_id"] == "item_fate_card_drop":
					fate += 1
					_check(item["source_room_id"] == room_id, "凭据来源不可漂移")
					_check(bool(item.get("fate_common_offer", false)) == (index == 2), "普通报价标记必须跟随凭据")
				if item.get("type", "") == "weapon":
					weapons += 1
					_check(item["drop_grade"] == "blue", "教学枪蓝品")
					_check(item["bullet_module_id"] == "mod_bullet_standard" and item["bullet_module_locked"], "教学枪标准弹锁定")
					var tree := WeaponInstance.from_item(item).build_runtime_tree()
					var bullet: AssemblyNode = tree.get_root().slots[AssemblyNode.SlotType.BULLET]
					_check(bullet != null and bullet.node_name == "Bullet_Standard", "真实装配弹种必须正确")
					tree.clear_assembly()
					tree.free()
			_check(fate <= 1 and (index not in [2, 7] or fate == 1), "02/07单次替代30%，不得双发")
			if index == 7:
				var extra := CHEST.resolve_additional_weapon(drop, seed_value, room_id, "clear_drop:" + room_id, 1)
				_check(extra["ok"] and extra["grants"].size() == 1, "07恰好一把追加枪")
				var item: Dictionary = extra["grants"][0]["item"]
				_check(item["drop_grade"] == "purple" and item["bullet_module_id"] == "mod_bullet_standard", "07紫步枪标准弹")
				_check((item.get("fate_upgrades", []) as Array).is_empty() and not item.get("narrative_auto_equip", false), "不得迁移卡或自动装备")
				_check(item["weapon_instance_id"] == CHEST.resolve_additional_weapon(drop, seed_value, room_id, "clear_drop:" + room_id, 1)["grants"][0]["item"]["weapon_instance_id"], "追加枪身份稳定")
		_check(ammo == 2100 and health == 5 and weapons == 1, "全程固定小包2100弹5药，加教学100弹与1枪")
	_case_box_snapshot()
	_case_economy()
	_case_overflow()
	_case_old_plan(config)
	_case_random_stream()
	_case_weapon_run_identity()
	_case_placement_economy()
	for failure in failures: push_error(failure)
	print("EXPEDITION01_REWARD_FLOW checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _case_box_snapshot() -> void:
	var box := TreasureChest3D.new()
	box.configure({"id": "frozen", "chest_tier": "normal", "source_room_id": "room_02", "fate_card_chance": 1.0, "fate_common_offer": true, "guaranteed_items": [{"item_id": "weapon_rifle", "count": 1, "grade": "blue", "bullet_module_id": "mod_bullet_standard"}]})
	var restored := TreasureChest3D.new()
	restored.from_snapshot(JSON.parse_string(JSON.stringify(box.get_save_data())))
	_check(JSON.parse_string(JSON.stringify(box.get_reward_config())) == JSON.parse_string(JSON.stringify(restored.get_reward_config())), "保存可选字段JSON往返必须一致")
	box.free()
	box = TreasureChest3D.new()
	box.configure({"id": "old_advanced", "chest_tier": "advanced"})
	_check(not box.get_reward_config().has("fate_card_chance"), "旧箱缺概率不能补30%")
	var report := CHEST.resolve(box.get_reward_config(), 1, "boss", 1)
	var fate := 0
	for grant in report["grants"]:
		if grant["item_id"] == "item_fate_card_drop": fate += 1
	_check(fate == 1, "旧高级箱仍必给命运凭据")
	var mismatch := CHEST.resolve(restored.get_reward_config(), 1, "room_07", 1)
	_check(not mismatch["ok"], "来源房不符必须拒绝，不能漂移报价来源")
	box.free()
	restored.free()

func _case_economy() -> void:
	var economy := ECONOMY.new()
	var rooms: Array = [{"id": "entry"}]
	for index in range(1, 11):
		rooms.append({"id": "room_%02d" % index, "encounter": {"stages": [{"monsters": [{"type": "melee_chaser", "count": index}]}]}})
	economy.configure_from_runtime(rooms, {}, {"default": {"base": 5, "per_floor": 0}}, 1, 10)
	_check(economy.price_index_for_room("room_02") == 2 and economy.price_index_for_room("room_07") == 7, "来源映射不依报价次数")
	_check(economy.price_index_for_room("missing") == -1, "未知来源不得借用后房价格")
	var pool: Array[FateCard] = [FateCardPresets.scale_up(), FateCardPresets.bounce_bullet()]
	var offer: Array[FateCard] = [FateCardPresets.gun_on_gun(), FateCardPresets.bullet_carry_gun(), FateCardPresets.armor_pierce()]
	var guaranteed := ECONOMY.ensure_common_offer(offer, pool, 7, "pickup")
	_check(guaranteed.size() == 3, "普通候选保底不改变槽位数")
	var seen := {}
	var common := false
	for card in guaranteed:
		_check(not seen.has(card.get_stable_card_id()), "普通保底不得重复身份")
		seen[card.get_stable_card_id()] = true
		if card.get_stable_card_id() in ["fate_scale_node", "fate_bounce_bullet"]:
			common = card.card_rarity == FateCard.CardRarity.COMMON and not card.is_reversed()
	_check(common, "正常候选至少一张普通正位教学卡")
	_check(ECONOMY.ensure_common_offer(offer, [], 7, "pickup").is_empty(), "无合法普通卡必须拒绝而不是越白名单")

func _case_overflow() -> void:
	var item := ItemRegistry.get_instance().get_item("item_ammo_pack")
	var board := InventoryModule.new(40)
	_check(board.add_item(item, 2200) == 2200, "累计2200弹不得截到999")
	var total := 0
	for slot in board.get_occupied_slots():
		_check(slot["count"] <= 999, "每栈不得超999")
		total += int(slot["count"])
	_check(total == 2200 and board.get_used_slots() == 3, "应拆成999+999+202")
	var full := InventoryModule.new(1)
	var added := full.add_item(item, 2200)
	_check(added == 999 and 2200 - added == 1201, "有限容量返回真实数量，余量留地面")

func _case_old_plan(config: Dictionary) -> void:
	var old := config.duplicate(true)
	old.erase("room_overrides")
	var service := CLEAR.new()
	service.configure(old)
	var frozen: Dictionary = JSON.parse_string(JSON.stringify(service.roll_room_drop("room_07", "content", 7)))
	service.configure(config)
	_check(frozen["grants"].is_empty() and frozen["additional_weapon"].is_empty(), "旧冻结计划不得因新配置补发")
	var no_chest := config.duplicate(true)
	no_chest["content_room"]["chest_chance"] = 0.0
	no_chest["fallback_pool"] = []
	service.configure(no_chest)
	_check(service.roll_room_drop("room_10", "content", 7)["grants"].size() == 2, "无箱也保留独立小包")

func _case_random_stream() -> void:
	var seen := {}
	var base := {"spec_id": "flow_stream", "entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 1}, {"kind": "item", "item_id": "weapon_shotgun", "count": 1}]}
	for seed_value in range(32):
		var normal := REWARD.resolve(base, {"seed": seed_value})
		var fixed := base.duplicate(true)
		fixed["entries"][0]["bullet_module_id"] = "mod_bullet_standard"
		var forced := REWARD.resolve(fixed, {"seed": seed_value})
		seen[normal["grants"][0]["item"]["bullet_module_id"]] = true
		_check(normal["grants"][1]["item"]["bullet_module_id"] == forced["grants"][1]["item"]["bullet_module_id"], "强制弹种不移动后项弹种随机流")
		_check(normal["grants"][1]["item"]["drop_grade"] == forced["grants"][1]["item"]["drop_grade"], "强制弹种不移动后项品质随机流")
	_check(seen.size() > 1, "非教学枪仍随机弹种")

func _case_weapon_run_identity() -> void:
	var drop := {"additional_weapon": {"weapon_id": "weapon_rifle", "grade": "purple", "bullet_module_id": "mod_bullet_standard"}}
	var teaching := {"id": "drop_room_02", "chest_tier": "normal", "guaranteed_items": [{"item_id": "weapon_rifle", "count": 1, "grade": "blue", "bullet_module_id": "mod_bullet_standard"}, {"item_id": "item_ammo_pack", "count": 100}]}
	var advanced := {"id": "drop_boss", "chest_tier": "advanced"}
	var seen_ids := {}
	var seen_transactions := {}
	for seed_value in range(16):
		var old_extra := CHEST.resolve_additional_weapon(drop, seed_value, "room_07", "clear_drop:room_07", 1)
		var old_teaching := CHEST.resolve(teaching, seed_value, "room_02", 1)
		var old_advanced := CHEST.resolve(advanced, seed_value, "boss", 1)
		_check(_weapon_ids(old_extra) == _weapon_ids(CHEST.resolve_additional_weapon(drop, seed_value, "room_07", "clear_drop:room_07", 1)), "兼容空run参数仍按seed稳定")
		for run_id in ["run_a", "run_b", "run:a|b"]:
			var extra := CHEST.resolve_additional_weapon(drop, seed_value, "room_07", "clear_drop:room_07", 1, run_id)
			var guaranteed := CHEST.resolve(teaching, seed_value, "room_02", 1, run_id)
			var boss := CHEST.resolve(advanced, seed_value, "boss", 1, run_id)
			_check(_weapon_ids(extra) == _weapon_ids(CHEST.resolve_additional_weapon(drop, seed_value, "room_07", "clear_drop:room_07", 1, run_id)), "追加枪同局重试身份必须不变")
			_check(_weapon_ids(guaranteed) == _weapon_ids(CHEST.resolve(teaching, seed_value, "room_02", 1, run_id)), "教学枪同局重试身份必须不变")
			_check(_reward_without_identity(extra) == _reward_without_identity(old_extra), "追加枪run身份不得改变奖励随机流")
			_check(_reward_without_identity(guaranteed) == _reward_without_identity(old_teaching), "教学枪run身份不得改变卡与消耗品随机流")
			_check(_reward_without_identity(boss) == _reward_without_identity(old_advanced), "普通箱枪身份不得改变原高级箱随机奖励")
			for report in [extra, guaranteed, boss]:
				_check(report["ok"], "run身份解析必须通过")
				for grant in report["grants"]:
					var item: Dictionary = grant["item"]
					if item.get("type", "") != "weapon": continue
					var id: String = item["weapon_instance_id"]
					var transaction: String = item["created_transaction_id"]
					_check(not seen_ids.has(id), "不同seed/run/来源的武器ID不得碰撞")
					_check(not seen_transactions.has(transaction), "不同seed/run/来源的创建事务不得碰撞")
					seen_ids[id] = true
					seen_transactions[transaction] = true
					_check(item["weapon_instance"]["weapon_instance_id"] == id and item["weapon_instance"]["created_transaction_id"] == transaction, "内外层身份与事务必须一致")
	_check(seen_ids.size() == 144, "16种子3run3来源全部分离")
	var legacy: Array = CHEST.resolve_additional_weapon(drop, 1, "room_07", "clear_drop:room_07", 1)["grants"]
	legacy[0]["item"]["weapon_instance_id"] = "chest_wpn_old_frozen"
	legacy[0]["item"]["created_transaction_id"] = "chest:old:frozen"
	legacy[0]["item"]["weapon_instance"]["weapon_instance_id"] = "chest_wpn_old_frozen"
	legacy[0]["item"]["weapon_instance"]["created_transaction_id"] = "chest:old:frozen"
	var frozen: Array = JSON.parse_string(JSON.stringify(legacy))
	var box := TreasureChest3D.new()
	box.configure({"id": "legacy", "grants": frozen})
	var restored := TreasureChest3D.new()
	restored.from_snapshot(JSON.parse_string(JSON.stringify(box.get_save_data())))
	CHEST.resolve_additional_weapon(drop, 1, "room_07", "clear_drop:room_07", 1, "new_run")
	_check(restored.get_explicit_grants() == frozen, "冻结旧grants读档必须原样保留旧ID")
	var inventory := InventoryModule.new(40)
	_check(inventory.add_item(frozen[0]["item"], 1) == 1, "旧武器应可继续入包")
	_check(inventory.get_occupied_slots()[0]["item"]["weapon_instance_id"] == "chest_wpn_old_frozen", "旧冻结武器经过现有背包不得换ID")
	box.free()
	restored.free()
	print("WEAPON_RUN_IDENTITY_OK unique_ids=%d unique_transactions=%d" % [seen_ids.size(), seen_transactions.size()])

func _weapon_ids(report: Dictionary) -> Array:
	var ids: Array = []
	for grant in report["grants"]:
		var item: Dictionary = grant["item"]
		if item.get("type", "") == "weapon": ids.append([item["weapon_instance_id"], item["created_transaction_id"]])
	return ids

func _reward_without_identity(report: Dictionary) -> Array:
	var grants: Array = report["grants"].duplicate(true)
	for grant in grants:
		var item: Dictionary = grant["item"]
		item.erase("weapon_instance_id")
		item.erase("created_transaction_id")
		var nested: Dictionary = item.get("weapon_instance", {})
		nested.erase("weapon_instance_id")
		nested.erase("created_transaction_id")
	return grants

func _case_placement_economy() -> void:
	var boxes := preload("res://src/map/SpawnBoxCatalog.gd")
	var shared := boxes.load_box("box_center_elite")
	var before := shared.duplicate(true)
	var placement := {"box": "box_center_elite", "count_multiplier": 2, "count_bonus": 2, "spawn_overrides": [{"type": "melee_chaser", "count": 1, "delay_sec": 0.5}, {"type": "melee_chaser_strong", "count": {"min": 1, "max": 2}}]}
	var effective := boxes.resolve_placement_box(placement)
	_check(effective["spawns"].size() == 2 and effective["spawns"][0]["count_min"] == 1, "实例覆盖须完整替换并normalized")
	_check(effective["spawns"][1]["count_max"] == 2, "normalized区间须保留")
	var rules := {"per_tier": {"elite": {"base": 70, "per_floor": 0}}, "per_kind": {"melee_chaser": {"base": 5, "per_floor": 0}, "melee_chaser_strong": {"base": 11, "per_floor": 0}}, "default": {"base": 5, "per_floor": 0}}
	var economy := ECONOMY.new()
	var snapshot := economy.configure_from_runtime([{"id": "override", "spawn_placements": [placement]}], {"box_center_elite": shared}, rules, 1, 1)
	_check(snapshot["ok"] and snapshot["configured"], "合法实例经济配置通过")
	_check(snapshot["reference_income"] == {"min": 42, "expected": 53, "max": 64}, "倍率与bonus仅应用一次：4M+2至4SM=42/53/64")
	_check(not snapshot["reference_counts"].has("elite"), "失效精英不得残留在覆盖收益里")
	_check(boxes.load_box("box_center_elite") == before and shared == before, "实例解析不得污染共享盒或调用方字典")
	var old := ECONOMY.new()
	var old_snapshot := old.configure_from_runtime([{"id": "old", "spawn_placements": [{"box": "box_center_elite"}]}], {}, rules, 1, 1)
	_check(old_snapshot["reference_income"] == {"min": 75, "expected": 75, "max": 75}, "无override的旧共享盒仍1E+1M")
	var invalid: Array = [
		{"box": "unknown", "spawn_overrides": [{"type": "melee_chaser", "count": 1}]},
		{"box": "box_center_elite", "spawn_overrides": []},
		{"box": "box_center_elite", "spawn_overrides": [{"type": "unknown", "count": 1}]},
		{"box": "box_center_elite", "spawn_overrides": [{"type": "melee_chaser", "count": 0}]},
		{"box": "box_center_elite", "spawn_overrides": [{"type": "melee_chaser", "count": 1.5}]},
		{"box": "box_center_elite", "spawn_overrides": [{"type": "melee_chaser", "count": 1, "unknown": 2}]},
		{"box": "box_center_elite", "spawn_overrides": [{"type": "melee_chaser", "count": 1, "delay_sec": -1}]},
		{"box": "box_center_elite", "spawn_overrides": [{"type": "melee_chaser", "count": {"min": 2, "max": 1}}]},
	]
	for bad in invalid:
		var rejected := economy.configure_from_runtime([{"id": "valid", "spawn_placements": [{"box": "box_corner_ambush"}]}, {"id": "bad", "spawn_placements": [bad]}], {"unknown": shared}, rules, 1, 1)
		_check(not rejected["ok"] and not economy.is_configured() and not rejected["errors"].is_empty(), "未知/非法实例必须显式拒绝")
		_check(rejected["reference_income"] == {"min": 0, "expected": 0, "max": 0} and rejected["reference_counts"].is_empty(), "非法配置不得泄露部分估值或回退共享")
		_check(economy.price_for_rarity(0) == 0 and economy.price_index_for_room("valid") == -1, "失败后不得沿用旧报价或来源映射")
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	var floor_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level_plans/expedition_01/floors/floor_00.json"))
	var rooms: Array = []
	var override_count := 0
	var base_min := 0
	var base_max := 0
	for source in floor_data["rooms"]:
		var room: Dictionary = source.duplicate(true)
		room["id"] = room.get("legacy_room_id", room.get("room_id", ""))
		rooms.append(room)
		for instance in room.get("spawn_placements", []):
			if instance.has("spawn_overrides"): override_count += 1
		if room["id"] not in ["room_01", "room_02"]: continue
		for instance in room["spawn_placements"]:
			var box: Dictionary = boxes.resolve_placement_box(instance)
			for spawn in box["spawns"]:
				var currency := REWARD.resolve(REWARD.currency_spec_for(spawn["type"], "normal", 1, plan["monster_rules"]["currency"]), {"seed": 0, "floor": 1})
				for grant in currency["grants"]:
					base_min += int(grant["amount"]) * int(spawn["count_min"])
					base_max += int(grant["amount"]) * int(spawn["count_max"])
	var formal := economy.configure_from_runtime(rooms, {}, plan["monster_rules"]["currency"], 1, 10, 0.0)
	_check(override_count == 4, "本关恰好四placement覆盖")
	_check(formal["ok"] and formal["configured"], "正式内容经济有效")
	_check(base_min == 78 and base_max == 86, "前两房有效清单基础拾币须为78—86")
	var price_index := economy.price_index_for_room("room_02")
	_check(is_equal_approx(float(formal["segment_income_expected"][price_index]), 52.0), "room02实际基础清单参考收益应52")
	var production := ECONOMY.new()
	var production_snapshot := production.configure_from_runtime(rooms, {}, plan["monster_rules"]["currency"], 1, 10, float(plan["monster_rules"]["strong_variant"]["chance"]))
	_check(production_snapshot["ok"], "生产概率强化参数下经济有效")
	for seed_value in range(64):
		for card_id in ["fate_scale_node", "fate_bounce_bullet"]:
			for service in [economy, production]:
				var quote: int = service.frozen_quote_for_card(0, price_index, card_id, seed_value)
				_check(quote >= 40 and quote <= 50 and quote <= base_min, "room02普通正位正常报价40—50且自然拾币足够")
	print("FATE_PLACEMENT_ECONOMY_OK overrides=%d room02_reference=52 base_currency=%d-%d normal_quote=40-50" % [override_count, base_min, base_max])

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
