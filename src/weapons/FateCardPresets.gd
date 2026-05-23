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

## 变大了：节点变大，伤害提升，速度降低
static func scale_up() -> FateCard:
	var card := FateCard.new("变大了", FateCard.CardType.ENHANCE, RARITY_COMMON)
	card.tags = ["Fate.Enhance", "Fate.ScaleNode"]
	card.description = "选择一个节点，体型与碰撞范围增加，伤害提升，速度降低"
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

## 超频：射速大幅提升，但过热更快
static func overclock() -> FateCard:
	var card := FateCard.new("超频", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.tags = ["Fate.Enhance", "Fate.MultiplyFireRate"]
	card.description = "选择一个枪身，射速提升 80%，但过热惩罚增加"
	card.effect = {
		"action": FateCard.EffectAction.MULTIPLY_FIRE_RATE,
		"multiplier": 1.8,
		"overheat_penalty": 1.5,
	}
	return card

## 穿甲强化：增加穿透效果
static func armor_pierce() -> FateCard:
	var card := FateCard.new("穿甲强化", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.tags = ["Fate.Enhance", "Fate.AddDamage"]
	card.description = "选择一个子弹，增加伤害和穿透能力"
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
	]

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