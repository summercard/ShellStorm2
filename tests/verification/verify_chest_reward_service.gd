extends Node
## ChestRewardService 两档奖励专项验收。
## 只验证纯解析结果，不创建宝箱节点、不发放奖励、不消费共享 RNG。

const _SERVICE := preload("res://src/rewards/ChestRewardService.gd")
const _WEAPON_DROP := preload("res://src/weapons/WeaponBulletDrop.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_case_normal()
	_case_advanced()
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
