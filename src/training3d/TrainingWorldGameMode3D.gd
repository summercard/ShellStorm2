class_name TrainingWorldGameMode3D
extends Node
## 靶场的「世界命运宿主」。
##
## 为什么靶场需要它：14 张 WORLD 卡（以及 fate_bless_dead 这类角色卡）**全部**
## 通过 `FateCardEngine._find_room_game_mode()` 找 group `room_game_mode` 的宿主，
## 再调它的 `apply_world_fate_card()` / `trigger_extra_wave()` / `set_extra_loot_next_chest()`
## 等方法。靶场原来没有宿主 → 这些卡一律返回 `world_owner_unavailable`，
## 表现为"卡装不上去"，而不是"效果没生效"。
##
## 本宿主的分工刻意分开：
##   - **能真做的就真做**：增援直接刷一波怪；腐蚀/焦土/试炼的下一波倍率真的喂给新生成的敌人。
##   - **做不了的记下来**：宝箱品质、额外掉落、钥匙、揭示、赏金、撤离时限在靶场里没有
##     对应实体，因此记成可查询的**待结状态**，由补给箱与 HUD 兑现/展示，
##     而不是假装成功。绝不写存档。

## 请求靶场刷一波增援；由 TrainingRange3D 连接后落到刷怪台上。
signal reinforcement_requested(count: int, spawn_elite: bool)
## 每次世界命运落地后广播，供 HUD 显示。
signal world_card_applied(card_id: String, detail: String)

## 待结的宝箱状态（补给箱开启时消费）。
var chest_quality_boost := 0
var chest_extra_count := 0
var chest_max_rarity := ""
## 下一波敌人的数值倍率（生成时消费）。
var next_wave_hp_multiplier := 1.0
var next_wave_damage_multiplier := 1.0
## 无法在靶场内物理复现、但需要让测试者看见"确实生效了"的世界状态。
var curse_damage_multiplier := 1.0
var currency_multiplier := 1.0
var room_key_count := 0
var revealed_radius := 0
var bounty_total := 0
var extraction_time_multiplier := 1.0
## 低血量祝福（fate_bless_dead）。
var bless_dead: Dictionary = {}
var applied_card_ids: Array[String] = []


func _ready() -> void:
	add_to_group("room_game_mode")


## FateCardEngine 的唯一世界入口。
func apply_world_fate_card(card: FateCard) -> Dictionary:
	if card == null or card.scope != FateCard.Scope.WORLD:
		return {"success": false, "error": "invalid_world_card", "message": "当前不能应用世界命运"}
	var effect := card.effect
	var detail := ""
	match card.stable_card_id:
		"fate_reinforce":
			var wave := trigger_extra_wave(effect)
			if not bool(wave.get("success", false)):
				return wave
			detail = str(wave.get("message", ""))
		"fate_curse_map":
			apply_curse_to_current_room(
				float(effect.get("enemy_damage_multiplier", effect.get("damage_multiplier", 1.15))),
				float(effect.get("currency_multiplier", 1.0))
			)
			detail = "敌人伤害 ×%.2f，金币 ×%.2f" % [curse_damage_multiplier, currency_multiplier]
		"fate_lucky_chest", "fate_extra_loot":
			chest_quality_boost += int(effect.get("quality_boost", 0))
			chest_extra_count += int(
				effect.get("extra_count", 1 if card.stable_card_id == "fate_extra_loot" else 0)
			)
			detail = "待结：品质 +%d，额外 %d 件" % [chest_quality_boost, chest_extra_count]
		"fate_sun_quality":
			chest_quality_boost += int(effect.get("tiers", 1))
			detail = "待结：品质 +%d 档" % chest_quality_boost
		"fate_sun_extra_loot":
			chest_extra_count += maxi(0, int(effect.get("count", 1)))
			if effect.has("max_rarity"):
				chest_max_rarity = str(effect["max_rarity"]).to_lower()
			detail = "待结：额外 %d 件（上限 %s）" % [chest_extra_count, chest_max_rarity]
		"fate_sun_reinforce":
			var count := maxi(0, int(effect.get("count", 0)))
			var elite_count := maxi(0, int(effect.get("elite_count", 0)))
			trigger_extra_wave({"spawn_count": maxi(1, count + elite_count), "spawn_elite": elite_count > 0})
			detail = "增援 %d 只%s" % [maxi(1, count + elite_count), "（含精英）" if elite_count > 0 else ""]
		"fate_sun_reveal":
			revealed_radius = maxi(revealed_radius, int(effect.get("radius", 1)))
			detail = "揭示半径 %d（靶场无小地图，仅记录）" % revealed_radius
		"fate_sun_key":
			room_key_count += maxi(0, int(effect.get("count", 1)))
			detail = "钥匙 +%d（靶场无门锁，仅记录）" % room_key_count
		"fate_sun_currency":
			currency_multiplier *= maxf(0.0, float(effect.get("multiplier", 1.0)))
			detail = "金币倍率 ×%.2f（靶场无结算，仅记录）" % currency_multiplier
		"fate_sun_scorch":
			next_wave_hp_multiplier *= maxf(0.01, float(effect.get("multiplier", 1.0)))
			next_wave_damage_multiplier *= maxf(0.0, float(effect.get("damage_multiplier", 1.0)))
			detail = "下一波敌人：血 ×%.2f，伤害 ×%.2f" % [next_wave_hp_multiplier, next_wave_damage_multiplier]
		"fate_sun_trial":
			next_wave_damage_multiplier *= maxf(0.0, float(effect.get("damage_multiplier", 1.0)))
			currency_multiplier *= maxf(0.0, float(effect.get("currency_multiplier", 1.0)))
			detail = "试炼：下一波伤害 ×%.2f" % next_wave_damage_multiplier
		"fate_sun_bounty":
			bounty_total += int(effect.get("amount", 0))
			detail = "赏金累计 %d（靶场无结算，仅记录）" % bounty_total
		"fate_sun_extraction":
			extraction_time_multiplier *= maxf(0.01, float(effect.get("multiplier", 1.0)))
			detail = "撤离时限 ×%.2f（靶场无撤离点，仅记录）" % extraction_time_multiplier
		_:
			return {"success": false, "error": "unsupported_world_card", "message": "世界命运尚无执行器"}
	applied_card_ids.append(card.stable_card_id)
	world_card_applied.emit(card.stable_card_id, detail)
	return {"success": true, "message": "已应用世界命运：%s（%s）" % [card.card_name, detail]}


## Engine 直接调用（不经 apply_world_fate_card）时的入口之一。
func trigger_extra_wave(effect: Dictionary = {}) -> Dictionary:
	var count := maxi(1, int(effect.get("spawn_count", 3)))
	reinforcement_requested.emit(count, bool(effect.get("spawn_elite", false)))
	return {"success": true, "message": "命运增援：刷出 %d 只" % count}


func set_next_chest_quality_boost(boost: int) -> void:
	chest_quality_boost += boost


func set_extra_loot_next_chest(enabled: bool) -> void:
	chest_extra_count = maxi(chest_extra_count, 1 if enabled else 0)


func apply_curse_to_current_room(damage_multiplier: float, currency_multiplier_value := 1.0) -> Dictionary:
	curse_damage_multiplier *= maxf(0.0, damage_multiplier)
	currency_multiplier *= maxf(0.0, currency_multiplier_value)
	next_wave_damage_multiplier *= maxf(0.0, damage_multiplier)
	return {"success": true, "message": "诅咒：敌人伤害 ×%.2f" % curse_damage_multiplier}


func apply_bless_dead(hp_threshold: float, survive_duration: float, damage_bonus: float) -> void:
	bless_dead = {
		"hp_threshold": hp_threshold,
		"survive_duration": survive_duration,
		"damage_bonus": damage_bonus,
	}


## 补给箱开启时消费：把待结的宝箱状态一次性取走并清零。
func consume_chest_pending() -> Dictionary:
	var pending := {
		"quality_boost": chest_quality_boost,
		"extra_count": chest_extra_count,
		"max_rarity": chest_max_rarity,
	}
	chest_quality_boost = 0
	chest_extra_count = 0
	chest_max_rarity = ""
	return pending


## 刷怪前消费：下一波敌人要吃到的数值倍率，取走即还原。
func consume_wave_multipliers() -> Dictionary:
	var multipliers := {
		"hp_multiplier": next_wave_hp_multiplier,
		"damage_multiplier": next_wave_damage_multiplier,
	}
	next_wave_hp_multiplier = 1.0
	next_wave_damage_multiplier = 1.0
	return multipliers


func get_snapshot() -> Dictionary:
	return {
		"chest_quality_boost": chest_quality_boost,
		"chest_extra_count": chest_extra_count,
		"next_wave_hp_multiplier": next_wave_hp_multiplier,
		"next_wave_damage_multiplier": next_wave_damage_multiplier,
		"curse_damage_multiplier": curse_damage_multiplier,
		"currency_multiplier": currency_multiplier,
		"room_key_count": room_key_count,
		"revealed_radius": revealed_radius,
		"bounty_total": bounty_total,
		"extraction_time_multiplier": extraction_time_multiplier,
		"bless_dead": bless_dead.duplicate(true),
		"applied_world_cards": applied_card_ids.duplicate(),
		"is_3d": true,
	}
