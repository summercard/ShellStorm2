extends Node
class_name FateCardPresets

# FateCardPresets.gd — 命运卡片预设工厂
# 提供游戏内置的命运卡片预设，快速生成卡片实例

## 命运卡片质量常量（对应卡牌稀有度）
const RARITY_COMMON := FateCard.CardRarity.COMMON
const RARITY_RARE := FateCard.CardRarity.RARE
const RARITY_EPIC := FateCard.CardRarity.EPIC
const RARITY_LEGENDARY := FateCard.CardRarity.LEGENDARY
const RARITY_MYSTIC := FateCard.CardRarity.MYSTIC

## ========== 组合类（COMBINE）==========


## 子弹背枪：选择子弹上挂枪身，子弹飞行时会携带枪并自动射击
static func bullet_carry_gun() -> FateCard:
	var card := FateCard.new("子弹背枪", FateCard.CardType.COMBINE, RARITY_EPIC)
	card.tags = ["Fate.Combine", "Fate.AddChildNode", "bullet_mountable"]
	card.description = "选择一个子弹和一个枪身，该子弹将携带枪身并自动射击"
	card.effect = {
		"action": FateCard.EffectAction.ATTACH_GUN_TO_BULLET,
		"damage_scale": 0.45,
		"fire_rate_scale": 0.6,
		"max_attached_gun": 1,
	}
	card.visual = {
		"action": "AddVisualChild",
		"scale": 0.45,
		"mount_point": "Top",
	}
	return card


## 枪上加枪：枪身挂枪身，主枪开火时副枪也跟随射击
static func gun_on_gun() -> FateCard:
	var card := FateCard.new("枪上加枪", FateCard.CardType.COMBINE, RARITY_LEGENDARY)
	card.tags = ["Fate.Combine", "Fate.AddChildNode"]
	card.description = "选择一个枪身，将其挂到当前枪身上，副枪跟随射击"
	card.effect = {
		"action": FateCard.EffectAction.ATTACH_GUN_TO_GUN,
		"damage_scale": 0.5,
		"fire_rate_scale": 0.6,
		"follow_probability": 1.0,
	}
	return card


## 配件寄生：配件寄生到子弹上，命中时触发效果
static func attachment_parasite() -> FateCard:
	var card := FateCard.new("配件寄生", FateCard.CardType.COMBINE, RARITY_EPIC)
	card.tags = ["Fate.Combine", "Fate.AddChildNode", "attachment"]
	card.description = "选择一个配件使其寄生到子弹上，命中时触发配件效果"
	card.effect = {
		"action": FateCard.EffectAction.ATTACH_TO_MOUNT,
		"target_slot": "MUZZLE",
		"trigger_on_hit": true,
	}
	return card


## ========== 强化类（ENHANCE）==========


## 变大了：当前子弹变大并提升命中伤害。
static func scale_up() -> FateCard:
	var card := FateCard.new("变大了", FateCard.CardType.ENHANCE, RARITY_COMMON)
	card.tags = ["Fate.Enhance", "Fate.ScaleNode"]
	card.target_rules = [{"select": "BULLET"}]
	card.description = "当前子弹体型与碰撞范围增加，伤害 +3，弹速降低"
	card.effect = {
		"action": FateCard.EffectAction.SCALE_NODE,
		"scale": 1.5,
		"damage_bonus": 3,
		"speed_multiplier": 0.7,
	}
	card.visual = {
		"action": "ScaleUp",
		"scale": 1.5,
	}
	return card


## 超频：当前枪身射速大幅提升。
static func overclock() -> FateCard:
	var card := FateCard.new("超频", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.tags = ["Fate.Enhance", "Fate.MultiplyFireRate"]
	card.target_rules = [{"select": "GUN_BODY"}]
	card.description = "当前枪身射速提升 80%"
	card.effect = {
		"action": FateCard.EffectAction.MULTIPLY_FIRE_RATE,
		"multiplier": 1.8,
		"overheat_penalty": 1.5,
	}
	return card


## 穿甲强化：提升当前子弹的即时命中伤害。
static func armor_pierce() -> FateCard:
	var card := FateCard.new("穿甲强化", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.tags = ["Fate.Enhance", "Fate.AddDamage"]
	card.target_rules = [{"select": "BULLET"}]
	card.description = "当前子弹伤害 +5"
	card.effect = {
		"action": FateCard.EffectAction.ADD_DAMAGE,
		"damage_bonus": 5,
		"pierce_level": 2,
	}
	return card


## ========== 变种类（MUTATE）==========


## 活过来：子弹变成活体，轻微追踪敌人
static func living_bullet() -> FateCard:
	var card := FateCard.new("活过来", FateCard.CardType.MUTATE, RARITY_EPIC)
	card.tags = ["Fate.Mutate", "Fate.MutateToHoming"]
	card.target_rules = [{"select": "BULLET"}]
	card.description = "选择一个子弹，变成活体子弹，会轻微追踪敌人"
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_HOMING,
		"homing_strength": 0.3,
		"speed_penalty": 0.2,
	}
	card.visual = {
		"action": "AddEyes",
		"eye_count": 2,
	}
	return card


## 不想飞：子弹落地变成炮台
static func turret_on_land() -> FateCard:
	var card := FateCard.new("不想飞", FateCard.CardType.MUTATE, RARITY_RARE)
	card.tags = ["Fate.Mutate", "Fate.Turret"]
	card.description = "子弹落地后变成小炮台，继续攻击周围敌人"
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_LIVING,
		"spawn_turret_on_land": true,
		"turret_duration": 5.0,
	}
	return card


## 回家看看：子弹飞出后返回玩家
static func bullet_return() -> FateCard:
	var card := FateCard.new("回家看看", FateCard.CardType.MUTATE, RARITY_EPIC)
	card.tags = ["Fate.Mutate", "Fate.Return"]
	card.target_rules = [{"select": "BULLET"}]
	card.description = "子弹飞出后返回玩家，返回途中继续造成伤害"
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_HOMING,
		"return_to_player": true,
		"return_damage_multiplier": 0.6,
	}
	return card


## ========== 诅咒类（CURSE）==========


## 管不住了：子弹上的枪自动射击但不准
static func out_of_control() -> FateCard:
	var card := FateCard.new("管不住了", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.tags = ["Fate.Curse", "Fate.UncontrolledFire"]
	card.description = "所有挂载在子弹上的枪自动射击，但子弹不一定瞄准敌人"
	card.effect = {
		"action": FateCard.EffectAction.ATTACH_TO_MOUNT,
		"auto_fire": true,
		"aim_randomness": 0.5,
		"damage_scale": 0.8,
	}
	return card


## 火力暴食：子弹命中越大，但降移速
static func gluttony() -> FateCard:
	var card := FateCard.new("火力暴食", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.tags = ["Fate.Curse", "Fate.SizeGrowth"]
	card.description = "子弹每命中一次就变大，但也会降低玩家移速"
	card.effect = {
		"action": FateCard.EffectAction.SCALE_NODE,
		"growth_per_hit": 0.2,
		"speed_penalty": 0.05,
		"max_scale": 3.0,
	}
	return card


## ========== 规则类（RULE）==========


## 每第七发：每第七发子弹携带一把枪
static func every_seventh() -> FateCard:
	var card := FateCard.new("每第七发", FateCard.CardType.RULE, RARITY_EPIC)
	card.tags = ["Fate.Rule", "Fate.EveryNthFire"]
	card.description = "每第七发子弹自动携带一把枪"
	card.effect = {
		"action": FateCard.EffectAction.EVERY_NTH_FIRE,
		"nth": 7,
		"attach_gun": true,
		"damage_scale": 0.4,
	}
	return card


## 击杀必暴击
static func crit_on_kill() -> FateCard:
	var card := FateCard.new("致命一击", FateCard.CardType.RULE, RARITY_LEGENDARY)
	card.tags = ["Fate.Rule", "Fate.CritOnKill"]
	card.description = "击杀敌人后下一次射击必定暴击"
	card.effect = {
		"action": FateCard.EffectAction.CRIT_ON_KILL,
		"crit_damage_multiplier": 2.5,
	}
	return card


## ========== 快捷方法==========


## 获取所有预设卡片的列表
static func all_presets() -> Array[FateCard]:
	return [
		bullet_carry_gun(),
		gun_on_gun(),
		attachment_parasite(),
		scale_up(),
		overclock(),
		armor_pierce(),
		living_bullet(),
		turret_on_land(),
		bullet_return(),
		out_of_control(),
		gluttony(),
		every_seventh(),
		crit_on_kill(),
		fate_lucky_chest(),
		fate_extra_loot(),
	]


## 玩家可获得的卡池只投放已接入实战反馈、能够立即感知的卡片。
static func playable_presets() -> Array[FateCard]:
	return [
		scale_up(),
		overclock(),
		armor_pierce(),
		bullet_carry_gun(),
		gun_on_gun(),
		living_bullet(),    # 活过来：子弹变活体，自动追踪敌人（MUTATE_TO_HOMING）
		turret_on_land(),   # 不想飞：子弹落地后变成小炮台继续攻击（MUTATE_TO_LIVING）
		bullet_return(),   # 回家看看：子弹飞出后返回玩家，返回途中造成伤害（MUTATE_TO_HOMING + return_to_player）
		crit_on_kill(),    # 致命一击：击杀后下一次射击必定暴击（RULE + CRIT_ON_KILL）
		every_seventh(),   # 每第七发：每第七发子弹额外发射一把挂载枪（EVERY_NTH_FIRE）
	]


## 开门命运与工作台/局前展示共享可玩牌池，避免抽到尚未完成的概念效果。
static func door_reward_presets() -> Array[FateCard]:
	return playable_presets()


## 按品质获取预设卡片
static func by_rarity(rarity: FateCard.CardRarity) -> Array[FateCard]:
	var result: Array[FateCard] = []
	for card in all_presets():
		if card.card_rarity == rarity:
			result.append(card)
	return result


## 按类型获取预设卡片
static func by_type(card_type: FateCard.CardType) -> Array[FateCard]:
	var result: Array[FateCard] = []
	for card in all_presets():
		if card.card_type == card_type:
			result.append(card)
	return result


## ========== 环境命运触发器专用卡片（由 MapFateTriggers 调用）==========


## 敌增援：连续击杀N个敌人后，波次外额外刷怪
## 注意：这是一种规则型效果，不依赖目标节点选择
static func fate_reinforce() -> FateCard:
	var card := FateCard.new("敌增援", FateCard.CardType.RULE, RARITY_RARE)
	card.tags = ["Fate.Rule", "Fate.Reinforce", "Fate.MapTrigger"]
	card.description = "连续击杀敌人后，波次外额外刷出一批增援怪物"
	card.effect = {
		"action": FateCard.EffectAction.REINFORCE_WAVE,
	}
	return card


## 命运标记：击杀第N个敌人后，获得一张随机命运卡片
static func fate_mark_enemy() -> FateCard:
	var card := FateCard.new("命运标记", FateCard.CardType.RULE, RARITY_EPIC)
	card.tags = ["Fate.Rule", "Fate.MapTrigger"]
	card.description = "击杀足够多的敌人后，获得一张随机命运卡片"
	card.effect = {
		"action": FateCard.EffectAction.GRANT_RANDOM_CARD,
	}
	return card


## 幸运发现：第N个箱子开启后，箱子物品品质提升
static func fate_lucky_chest() -> FateCard:
	var card := FateCard.new("幸运发现", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.tags = ["Fate.Enhance", "Fate.MapTrigger"]
	card.description = "下一个箱子的物品品质提升一个等级（蓝+以上）"
	card.effect = {
		"action": FateCard.EffectAction.LUCKY_CHEST,
		"quality_boost": 1,
	}
	return card


## 额外掉落：开箱获得额外物品
static func fate_extra_loot() -> FateCard:
	var card := FateCard.new("额外掉落", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.tags = ["Fate.Enhance", "Fate.MapTrigger"]
	card.description = "下一个箱子开启时额外掉落一件物品"
	card.effect = {
		"action": FateCard.EffectAction.EXTRA_LOOT,
	}
	return card


## 诅咒降临：本房间内怪物伤害+15%
static func fate_curse_map() -> FateCard:
	var card := FateCard.new("诅咒降临", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.tags = ["Fate.Curse", "Fate.MapTrigger"]
	card.description = "本房间内所有怪物伤害提升15%，持续到当前房间清理完成"
	card.effect = {
		"action": FateCard.EffectAction.CURSE_ROOM_ENEMIES,
		"damage_multiplier": 1.15,
	}
	return card


## 亡者祝福：HP低于30%后存活30秒，获得30秒伤害加成
static func fate_bless_dead() -> FateCard:
	var card := FateCard.new("亡者祝福", FateCard.CardType.ENHANCE, RARITY_EPIC)
	card.tags = ["Fate.Enhance", "Fate.MapTrigger"]
	card.description = "HP低于30%后存活30秒，获得30秒内伤害+10%"
	card.effect = {
		"action": FateCard.EffectAction.BLESS_DEAD,
		"hp_threshold": 0.3,
		"survive_duration": 30.0,
		"damage_bonus": 0.1,
	}
	return card


## 根据 card_id 字符串查找并生成对应的预设卡片实例（用于环境命运触发器）
static func get_by_card_id(card_id: String) -> FateCard:
	match card_id:
		"fate_reinforce":
			return fate_reinforce()
		"fate_mark_enemy":
			return fate_mark_enemy()
		"fate_lucky_chest":
			return fate_lucky_chest()
		"fate_extra_loot":
			return fate_extra_loot()
		"fate_curse_map":
			return fate_curse_map()
		"fate_bless_dead":
			return fate_bless_dead()
		# 兜底：返回一张通用的随机卡片
		_:
			var all := all_presets()
			if not all.is_empty():
				return all[randi() % all.size()]
			return scale_up()  # 兜底默认返回"变大了"
