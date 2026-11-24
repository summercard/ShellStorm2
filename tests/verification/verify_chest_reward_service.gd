extends Node
## ChestRewardService 两档奖励专项验收。
## 只验证纯解析结果，不创建宝箱节点、不发放奖励、不消费共享 RNG。

const _SERVICE := preload("res://src/rewards/ChestRewardService.gd")
const _WEAPON_DROP := preload("res://src/weapons/WeaponBulletDrop.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_case_normal()
	_case_advanced()
	_case_legacy_guarantees()
	_case_legacy_fixed_chest_snapshot()
	_case_legacy_reward_delivery()
	_case_stable_streams()
	_case_main_rng_is_untouched()
	if _failures.is_empty():
		print("CHEST_REWARD_SERVICE_OK: normal/advanced tiers, filters, fate metadata, deterministic streams and RNG isolation pass")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _case_normal() -> void:
	var config := {
		"id": "chest_normal_01",
		"chest_tier": "normal",
		"quality": "common",
		"reward_pool_id": "loot_floor_1_2",
	}
	var saw_fate := false
	var saw_no_fate := false
	for seed_value in range(1, 256):
		var report := _SERVICE.resolve(config, seed_value, "room_normal", 1)
		_expect(bool(report.get("ok", false)), "普通箱解析失败：%s" % str(report.get("errors", [])))
		if not bool(report.get("ok", false)):
			continue
		var fate_count := 0
		var physical_count := 0
		for value in report.get("grants", []):
			var grant := value as Dictionary
			_expect(int(grant.get("count", 0)) == 1, "普通箱每件奖励 count 必须为 1")
			var item_id := str(grant.get("item_id", ""))
			if item_id == "item_fate_card_drop":
				fate_count += 1
				_expect(str(grant.get("fate_pickup_id", "")) == "chest:room_normal:chest_normal_01:fate", "命运卡掉落物缺少稳定 fate_pickup_id")
				_expect(str(grant.get("fate_source", "")) == "treasure_chest", "命运卡掉落物来源不正确")
				_expect(str(grant.get("source_room_id", "")) == "room_normal", "命运卡掉落物缺少 source_room_id")
				_expect(str(grant.get("source_chest_id", "")) == "chest_normal_01", "命运卡掉落物缺少 source_chest_id")
			else:
				physical_count += 1
				var item := ItemRegistry.get_instance().get_item(item_id)
				_expect(str(item.get("type", "")) == "consumable", "普通箱非命运卡奖励必须是消耗品：%s" % item_id)
				_expect(not _excluded(item), "普通箱消耗品不应是钥匙或命运卡：%s" % item_id)
		_expect(physical_count >= 2 and physical_count <= 3, "普通箱应额外产出 2—3 件消耗品，实际 %d" % physical_count)
		_expect(fate_count <= 1, "普通箱命运卡掉落物最多 1 件")
		if fate_count == 1:
			saw_fate = true
		else:
			saw_no_fate = true
	_expect(saw_fate, "普通箱 30%% 分支在样本中从未命中")
	_expect(saw_no_fate, "普通箱 30%% 分支在样本中从未落空")


func _case_advanced() -> void:
	var config := {
		"id": "chest_advanced_01",
		"chest_tier": "advanced",
		"quality": "rare",
		"reward_pool_id": "loot_floor_1_2",
	}
	var report := _SERVICE.resolve(config, 20261107, "room_boss", 1)
	_expect(bool(report.get("ok", false)), "高级箱解析失败：%s" % str(report.get("errors", [])))
	if not bool(report.get("ok", false)):
		return
	var fate_count := 0
	var gun_count := 0
	var other_count := 0
	for value in report.get("grants", []):
		var grant := value as Dictionary
		var item_id := str(grant.get("item_id", ""))
		_expect(int(grant.get("count", 0)) == 1, "高级箱每件奖励 count 必须为 1")
		var item := ItemRegistry.get_instance().get_item(item_id)
		if item_id == "item_fate_card_drop":
			fate_count += 1
			_expect(str(grant.get("fate_pickup_id", "")) == "chest:room_boss:chest_advanced_01:fate", "高级箱命运卡掉落物 ID 不稳定")
		elif str(item.get("type", "")) == "weapon":
			gun_count += 1
			_expect(not _WEAPON_DROP.is_melee_weapon(item), "高级箱枪械不得为近战武器：%s" % item_id)
		else:
			other_count += 1
			_expect(not _excluded(item), "高级箱其他物品不应是钥匙或命运卡：%s" % item_id)
			_expect(str(item.get("type", "")) != "weapon", "高级箱其他物品不得是枪械：%s" % item_id)
	_expect(fate_count == 1, "高级箱必须固定 1 枚命运卡掉落物，实际 %d" % fate_count)
	_expect(gun_count == 1, "高级箱必须固定 1 把非近战枪，实际 %d" % gun_count)
	_expect(other_count >= 5 and other_count <= 8, "高级箱应额外产出 5—8 件非枪物品，实际 %d" % other_count)


func _case_legacy_guarantees() -> void:
	var config := {"id": "legacy_fixed_box", "chest_tier": "advanced", "reward_pool_id": "loot_floor_1_2",
		"guaranteed_items": [{"item_id": "weapon_rifle", "grade": "blue"}, {"item_id": "item_ammo_pack", "count": 100}]}
	var current := _SERVICE.resolve(config, 24, "legacy_room", 1, "legacy_run")
	var legacy := config.duplicate(true)
	legacy["guaranteed_items"].insert(0, {"item_id": "item_room_key"})
	legacy["guaranteed_items"].insert(2, {"item_id": "bp_rifle"})
	var restored := _SERVICE.resolve(legacy, 24, "legacy_room", 1, "legacy_run")
	_expect(restored.get("ok", false) and restored.get("grants") == current.get("grants"),
		"旧箱保底中的退役项不得改变合法奖励、叠量与枪械身份")
	var old_addition := _SERVICE.resolve_additional_weapon({"additional_weapon": {"weapon_id": "bp_rifle"}}, 24, "legacy_room", "legacy_fixed_box", 1)
	_expect(old_addition.get("ok", false) and old_addition.get("grants", []).is_empty(), "退役实物不能从旧额外奖励发出")


func _case_legacy_fixed_chest_snapshot() -> void:
	var old_config := {"id": "retired_only", "grants": [
		{"kind": "item", "item_id": "item_room_key", "item": {"id": "item_room_key"}, "count": 1},
		{"kind": "item", "item_id": "bp_rifle", "item": {"id": "bp_rifle", "type": "blueprint"}, "count": 1},
	]}
	var old_save := {"world_state": {"segment_runtime_state": {"r": {
		"treasure_chests": {"retired_only": {"spawned": true, "config": old_config}},
	}}}}
	var filtered := RunPersistenceService.without_retired_item_records(old_save)
	var config: Dictionary = filtered["world_state"]["segment_runtime_state"]["r"]["treasure_chests"]["retired_only"]["config"]
	_expect(config["grants"].is_empty() and config.get("explicit_reward_mode", false), "迁移后的旧固定箱不能降级成随机箱")
	var chest := TreasureChest3D.new()
	chest.configure(config)
	_expect(chest.has_explicit_grants() and chest.get_explicit_grants().is_empty(), "旧固定箱中所有内容退役也不能重新抽取")
	var restored := TreasureChest3D.new()
	restored.from_snapshot(chest.get_save_data())
	_expect(restored.has_explicit_grants() and restored.get_explicit_grants().is_empty(), "再次读档时仍保留空固定箱类型")
	chest.free()
	restored.free()


func _case_legacy_reward_delivery() -> void:
	var clear_drop := preload("res://src/game/ClearDropService.gd").new()
	var sink := preload("res://src/rewards/RewardSink.gd")
	var old_key := {"item_id": "item_room_key", "count": 1, "weight": 1000.0}
	var old_fragment := {"item_id": "bp_rifle", "count": 1, "weight": 1000.0}
	var medicine := {"item_id": "item_health_potion", "count": 2, "weight": 1.0}
	var config := {"schema": "shellstorm2.battle.clear_drops", "content_room": {"chest_chance": 0.0},
		"chest": {"id": "legacy_chest"}, "fallback_pool": [old_key, medicine, old_fragment],
		"room_overrides": {"room": {"grants": [old_key, medicine], "additional_weapon": {"weapon_id": "bp_rifle"}}},
		"room_guarantees": [{"id": "old_guarantee", "candidate_rooms": ["room"],
			"items": [old_fragment, medicine], "weapon_choices": ["bp_rifle", "weapon_rifle"]}]}
	_expect(clear_drop.configure(config)["ok"], "退役条目不应破坏旧清房配置")
	var drop := clear_drop.roll_room_drop("room", "content", 24)
	_expect(drop.get("item", {}).get("item_id") == "item_health_potion" and drop.get("grants") == [medicine]
		and drop.get("additional_weapon", {}).is_empty(), "清房兜底、固定包和额外奖励均不得选中退役实物")
	var guaranteed := clear_drop.guaranteed_items_for_room("room", 24)
	_expect(guaranteed.size() == 2 and guaranteed[0].get("item_id") == "weapon_rifle"
		and guaranteed[1].get("item_id") == "item_health_potion", "保底须保留合法枪与消耗品")
	var old_grant := {"kind": "item", "item_id": "bp_rifle", "count": 1, "item": {"id": "bp_rifle", "type": "blueprint"}}
	var registry := ItemRegistry.get_instance()
	var valid_grant := {"kind": "item", "item_id": "item_health_potion", "count": 2, "item": registry.get_item("item_health_potion")}
	var landed: Array = []
	var delivery := sink.apply_ground([old_grant, valid_grant], func(items: Array) -> int:
		landed.append_array(items)
		return items.size()
	)
	_expect(delivery["granted"] == [valid_grant] and delivery["rejected"] == [old_grant], "退役项不能阻塞或冒领后续合法奖励")
	_expect(landed.size() == 1 and landed[0].get("id") == "item_health_potion" and landed[0].get("count") == 2,
		"冻结发放须只落地合法物并保留数量")


func _case_stable_streams() -> void:
	var config := {"id": "stable_chest", "chest_tier": "advanced", "reward_pool_id": "loot_floor_1_2"}
	var first := _SERVICE.resolve(config, 404, "room_stable", 1)
	var second := _SERVICE.resolve(config, 404, "room_stable", 1)
	_expect(_signature(first.get("grants", [])) == _signature(second.get("grants", [])), "相同 seed + room_id + chest_id 必须得到相同奖励")
	var changed := false
	for index in range(1, 12):
		var different_config := config.duplicate(true)
		different_config["id"] = "stable_chest_other_%d" % index
		var different := _SERVICE.resolve(different_config, 404, "room_stable", 1)
		if _signature(first.get("grants", [])) != _signature(different.get("grants", [])):
			changed = true
			break
	_expect(changed, "不同 chest_id 的样本必须体现独立奖励流")


func _case_main_rng_is_untouched() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	var first := rng.randf()
	_SERVICE.resolve({"id": "rng_chest", "chest_tier": "advanced"}, 987654, "rng_room", 1)
	var second := rng.randf()
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 987654
	_expect(is_equal_approx(first, expected_rng.randf()), "测试前主 RNG 读数异常")
	_expect(is_equal_approx(second, expected_rng.randf()), "ChestRewardService 不得消费调用方主 RNG")


func _signature(grants: Array) -> String:
	var parts: Array[String] = []
	for value in grants:
		var grant := value as Dictionary
		var item := grant.get("item", {}) as Dictionary
		parts.append("%s|%d|%s|%s" % [
			str(grant.get("item_id", "")),
			int(grant.get("count", 0)),
			str(item.get("weapon_instance_id", "")),
			str(grant.get("fate_pickup_id", "")),
		])
	return ";".join(parts)


func _excluded(item: Dictionary) -> bool:
	var tags := item.get("tags", []) as Array
	return str(item.get("type", "")) in ["key", "fate_pickup"] \
		or tags.has("key") or tags.has("fate_pickup") or tags.has("world_credential_only")


func _expect(condition: bool, detail: String) -> void:
	if not condition:
		_failures.append(detail)
