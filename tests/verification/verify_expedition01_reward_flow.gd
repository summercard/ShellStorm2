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

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
