extends Node
class_name FateCardPresets

# FateCardPresets.gd — 命运卡片预设工厂
# 提供游戏内置的命运卡片预设，快速生成卡片实例

## 命运卡片品质常量
const RARITY_COMMON := FateCard.CardRarity.COMMON
const RARITY_RARE := FateCard.CardRarity.RARE
const RARITY_EPIC := FateCard.CardRarity.EPIC
const RARITY_LEGENDARY := FateCard.CardRarity.LEGENDARY
const RARITY_MYSTIC := FateCard.CardRarity.MYSTIC

## ========== 组合类（COMBINE）==========

## 子弹背枪：子弹携带枪身，边飞边射
static func bullet_carry_gun() -> FateCard:
	var card := FateCard.new("子弹背枪", FateCard.CardType.COMBINE, RARITY_EPIC)
	card.icon_emoji = "🔫"
	card.short_description = "子弹飞出去时自动开枪"
	card.description = "选择一个子弹和一个枪身，该子弹将携带枪身并自动射击"
	card.tags = ["Fate.Combine", "Fate.AddChildNode", "bullet_mountable"]
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


## 枪上加枪：副枪跟随主枪一起射击
static func gun_on_gun() -> FateCard:
	var card := FateCard.new("枪上加枪", FateCard.CardType.COMBINE, RARITY_LEGENDARY)
	card.icon_emoji = "🔗"
	card.short_description = "副枪跟随主枪一起开火"
	card.description = "选择一个枪身，将其挂到当前枪身上，副枪跟随射击"
	card.tags = ["Fate.Combine", "Fate.AddChildNode"]
	card.effect = {
		"action": FateCard.EffectAction.ATTACH_GUN_TO_GUN,
		"damage_scale": 0.5,
		"fire_rate_scale": 0.6,
		"follow_probability": 1.0,
	}
	return card


## 配件寄生：配件寄生到子弹上，命中触发效果
static func attachment_parasite() -> FateCard:
	var card := FateCard.new("配件寄生", FateCard.CardType.COMBINE, RARITY_EPIC)
	card.icon_emoji = "🦠"
	card.short_description = "配件附在子弹上，命中时触发效果"
	card.description = "选择一个配件使其寄生到子弹上，命中时触发配件效果"
	card.tags = ["Fate.Combine", "Fate.AddChildNode", "attachment"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.ATTACH_TO_MOUNT,
		"target_slot": "MUZZLE",
		"trigger_on_hit": true,
	}
	return card


## ========== 强化类（ENHANCE）==========

## 变大了：节点放大，伤害提升，速度降低
static func scale_up() -> FateCard:
	var card := FateCard.new("变大了", FateCard.CardType.ENHANCE, RARITY_COMMON)
	card.icon_emoji = "📦"
	card.short_description = "体型与碰撞范围增加"
	card.description = "选择一个节点，体型与碰撞范围增加，伤害提升 30%，速度降低 20%"
	card.tags = ["Fate.Enhance", "Fate.ScaleNode"]
	card.effect = {
		"action": FateCard.EffectAction.SCALE_NODE,
		"scale": 1.4,
		"damage_scale": 1.3,
		"speed_scale": 0.8,
	}
	card.visual = {
		"action": "scale_up",
		"scale": 1.4,
	}
	return card


## 超频：射速大幅提升，但累计受伤加重
static func overclock() -> FateCard:
	var card := FateCard.new("超频", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.icon_emoji = "⚡"
	card.short_description = "射速提升 80%"
	card.description = "选择一个枪身，射速提升 80%，但每次射击后累计受击伤害倍率（overheat_penalty=1.5：射击越多，受伤越痛）"
	card.tags = ["Fate.Enhance", "Fate.MultiplyFireRate"]
	card.effect = {
		"action": FateCard.EffectAction.MULTIPLY_FIRE_RATE,
		"fire_rate_scale": 1.8,
		"overheat_penalty": 1.5,
	}
	return card


## 穿甲强化：增加穿透和伤害
static func armor_pierce() -> FateCard:
	var card := FateCard.new("穿甲强化", FateCard.CardType.ENHANCE, RARITY_RARE)
	card.icon_emoji = "🎯"
	card.short_description = "伤害提升 50%，无视护盾"
	card.description = "选择一个节点，伤害提升 50%，无视护盾减伤效果"
	card.tags = ["Fate.Enhance", "Fate.AddDamage"]
	card.effect = {
		"action": FateCard.EffectAction.ADD_DAMAGE,
		"damage_scale": 1.5,
		"pierce_shield": true,
	}
	return card


## ========== 变种类（MUTATE）==========

## 活过来：子弹变成追踪弹
static func living_bullet() -> FateCard:
	var card := FateCard.new("活过来", FateCard.CardType.MUTATE, RARITY_RARE)
	card.icon_emoji = "👁"
	card.short_description = "子弹会追踪最近的敌人"
	card.description = "选择一个子弹，使其变成追踪弹，自动飞向最近的敌人"
	card.tags = ["Fate.Mutate", "Fate.HomingBullet"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_HOMING,
		"homing_strength": 0.6,
		"turn_rate": 3.0,
	}
	card.visual = {
		"action": "AddEyes",
	}
	return card


## 落地炮台：子弹落地生成自动炮台
static func turret_on_land() -> FateCard:
	var card := FateCard.new("落地炮台", FateCard.CardType.MUTATE, RARITY_EPIC)
	card.icon_emoji = "🏰"
	card.short_description = "子弹落地后自动炮击"
	card.description = "选择一个子弹，子弹落地后生成一座自动炮台，持续射击附近的敌人"
	card.tags = ["Fate.Mutate", "Fate.CreateTurret"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_TURRET_ON_LAND,
		"turret_duration": 8.0,
		"turret_fire_rate": 2.0,
		"turret_damage": 0.3,
	}
	return card


## 回家看看：子弹飞出后返回玩家，返回途中继续造成伤害
static func home_on_land() -> FateCard:
	var card := FateCard.new("回家看看", FateCard.CardType.MUTATE, RARITY_RARE)
	card.icon_emoji = "🏠"
	card.short_description = "子弹飞出去后返回玩家"
	card.description = "选择一个子弹，子弹飞出后返回玩家方向，返回途中继续造成 60% 伤害，持续 5 秒"
	card.tags = ["Fate.Mutate", "Fate.HomeOnLand"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_HOME_ON_LAND,
		"home_lifetime": 5.0,
		"return_damage_multiplier": 0.6,
	}
	card.visual = {
		"action": "AddLegs",
		"leg_count": 4,
	}
	return card


## 子弹折返：子弹打中目标后反弹
static func bullet_return() -> FateCard:
	var card := FateCard.new("子弹折返", FateCard.CardType.MUTATE, RARITY_RARE)
	card.icon_emoji = "↩️"
	card.short_description = "子弹命中后折返并再命中一次"
	card.description = "选择一个子弹，命中目标后折返回玩家方向，再次尝试命中敌人"
	card.tags = ["Fate.Mutate", "Fate.BounceBack"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_BOUNCE,
		"bounce_count": 1,
		"damage_scale_on_bounce": 0.7,
	}
	return card


## 连锁闪电：命中后在敌人间跳跃
static func chain_lightning() -> FateCard:
	var card := FateCard.new("连锁闪电", FateCard.CardType.MUTATE, RARITY_EPIC)
	card.icon_emoji = "⚡"
	card.short_description = "命中后在敌人间跳跃，最多3次"
	card.description = "选择一个子弹，命中后在敌人间跳跃，每次跳跃伤害递减 30%"
	card.tags = ["Fate.Mutate", "Fate.ChainLightning"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_CHAIN,
		"chain_count": 3,
		"chain_range": 150.0,
		"chain_damage_scale": 0.7,
	}
	return card


## 弹跳弹：子弹在场景边界反弹
static func bounce_bullet() -> FateCard:
	var card := FateCard.new("弹跳弹", FateCard.CardType.MUTATE, RARITY_COMMON)
	card.icon_emoji = "🏓"
	card.short_description = "子弹在边界间弹跳3次"
	card.description = "选择一个子弹，使其在墙壁和障碍物间弹跳，最多弹跳3次"
	card.tags = ["Fate.Mutate", "Fate.Bounce"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.MUTATE_TO_BOUNCE,
		"bounce_count": 3,
		"bounce_walls": true,
		"damage_scale": 0.85,
	}
	return card


## ========== 复制类（COPY）==========

## 弹幕模式：每次射击发射两波子弹
static func barrage_copy() -> FateCard:
	var card := FateCard.new("弹幕模式", FateCard.CardType.COPY, RARITY_RARE)
	card.icon_emoji = "🎆"
	card.short_description = "每次射击分两波发射"
	card.description = "选择一个枪身，每次射击分两波发射，第二波子弹延迟 0.1 秒"
	card.tags = ["Fate.Copy", "Fate.DuplicateFire"]
	card.target_rules = [{"select": "GUNBODY"}]
	card.effect = {
		"action": FateCard.EffectAction.COPY_NODE,
		"copy_fire_delay": 0.1,
		"second_wave_damage_scale": 0.6,
	}
	return card


## ========== 融合类（FUSE）==========

## 火焰子弹：子弹命中后附加火焰持续伤害
static func fuse_fire() -> FateCard:
	var card := FateCard.new("火焰子弹", FateCard.CardType.FUSE, RARITY_RARE)
	card.icon_emoji = "🔥"
	card.short_description = "命中附加火焰DOT"
	card.description = "选择一个子弹，融合火焰属性，命中后在目标身上附加火焰持续伤害（每秒8%伤害，持续3秒）"
	card.tags = ["Fate.Fuse", "Fate.DamageOverTime", "Fate.Fire"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.FUSE_DAMAGE,
		"damage_type": "fire",
		"dot_damage_per_sec": 0.08,
		"dot_duration": 3.0,
	}
	card.visual = {
		"action": "AddFireTrail",
	}
	return card


## 冰霜子弹：命中后冰冻目标0.5秒
static func fuse_frost() -> FateCard:
	var card := FateCard.new("冰霜子弹", FateCard.CardType.FUSE, RARITY_RARE)
	card.icon_emoji = "❄️"
	card.short_description = "命中后冰冻目标0.5秒"
	card.description = "选择一个子弹，融合冰霜属性，命中后冰冻目标 0.5 秒（精英怪减半）"
	card.tags = ["Fate.Fuse", "Fate.Freeze", "Fate.Ice"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.FUSE_DAMAGE,
		"damage_type": "ice",
		"freeze_duration": 0.5,
		"freeze_duration_elite": 0.25,
	}
	card.visual = {
		"action": "AddIceTrail",
	}
	return card


## 剧毒子弹：命中后附加毒素，叠加层数
static func fuse_poison() -> FateCard:
	var card := FateCard.new("剧毒子弹", FateCard.CardType.FUSE, RARITY_EPIC)
	card.icon_emoji = "☠️"
	card.short_description = "命中附加毒素，最多叠加5层"
	card.description = "选择一个子弹，融合毒素属性，命中后附加毒素，每层每秒造成 5% 伤害，最多叠加 5 层"
	card.tags = ["Fate.Fuse", "Fate.DamageOverTime", "Fate.Poison", "Fate.Stackable"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.FUSE_DAMAGE,
		"damage_type": "poison",
		"dot_damage_per_stack": 0.05,
		"max_stacks": 5,
		"dot_tick_rate": 1.0,
	}
	return card


## ========== 诅咒类（CURSE）==========

## 管不住了：子弹上的枪乱射
static func out_of_control() -> FateCard:
	var card := FateCard.new("管不住了", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.icon_emoji = "😱"
	card.short_description = "子弹上的枪随机乱射"
	card.description = "选择一个子弹，携带的枪会随机乱射，射击方向完全随机，伤害提升 30%"
	card.tags = ["Fate.Curse", "Fate.AddChildNode", "unstable"]
	card.target_rules = [{"select": "BULLET", "require_gun": true}]
	card.effect = {
		"action": FateCard.EffectAction.OUT_OF_CONTROL,
		"damage_scale": 1.3,
		"spread_angle": 360.0,
		"fire_rate_scale": 2.0,
	}
	return card


## 火力暴食：子弹越打越大
static func gluttony() -> FateCard:
	var card := FateCard.new("火力暴食", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.icon_emoji = "🌙"
	card.short_description = "每次命中子弹变大，伤害变高"
	card.description = "选择一个子弹，每次命中敌人后子弹伤害和体积增加 15%，最大可叠加 5 次"
	card.tags = ["Fate.Curse", "Fate.ScaleNode", "stacking"]
	card.target_rules = [{"select": "BULLET"}]
	card.effect = {
		"action": FateCard.EffectAction.SIZE_GROWTH,
		"damage_per_hit": 0.15,
		"scale_per_hit": 0.12,
		"max_stacks": 5,
	}
	return card


## 换弹爆炸：换弹时对周围造成伤害
static func explode_on_reload() -> FateCard:
	var card := FateCard.new("换弹爆炸", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.icon_emoji = "💥"
	card.short_description = "换弹时对周围造成爆炸伤害"
	card.description = "选择一个枪身，换弹时对周围 150 范围内的敌人造成 80% 伤害的爆炸，但换弹时间增加 0.5 秒"
	card.tags = ["Fate.Curse", "Fate.ExplodeOnReload"]
	card.target_rules = [{"select": "GUNBODY"}]
	card.effect = {
		"action": FateCard.EffectAction.EXPLODE_ON_RELOAD,
		"explosion_damage": 0.8,
		"explosion_radius": 150.0,
		"reload_penalty": 0.5,
	}
	return card


## ========== 规则类（RULE）==========

## 每第七发：第7发触发额外效果
static func every_seventh() -> FateCard:
	var card := FateCard.new("每第七发", FateCard.CardType.RULE, RARITY_RARE)
	card.icon_emoji = "7️⃣"
	card.short_description = "第7发子弹触发额外效果"
	card.description = "选择一个枪身，第 7 发子弹伤害翻倍并引发小爆炸"
	card.tags = ["Fate.Rule", "Fate.EveryNthFire"]
	card.target_rules = [{"select": "GUNBODY"}]
	card.effect = {
		"action": FateCard.EffectAction.EVERY_NTH_FIRE,
		"nth": 7,
		"damage_multiplier": 2.0,
		"bonus_effect": "small_explosion",
	}
	return card


## 致命一击：击杀后下次射击必暴击
static func crit_on_kill() -> FateCard:
	var card := FateCard.new("致命一击", FateCard.CardType.RULE, RARITY_RARE)
	card.icon_emoji = "💥"
	card.short_description = "击杀后下次射击必定暴击"
	card.description = "选择一个枪身，击杀敌人后下一次射击必暴击，暴击伤害 × 2.5"
	card.tags = ["Fate.Rule", "Fate.CritOnKill"]
	card.target_rules = [{"select": "GUNBODY"}]
	card.effect = {
		"action": FateCard.EffectAction.CRIT_ON_KILL,
		"crit_damage_multiplier": 2.5,
		"stacks": 1,
	}
	return card


## ========== 视觉类（VISUAL）==========

## 巨大化：所有相关节点放大 2 倍
static func huge_scale() -> FateCard:
	var card := FateCard.new("巨大化", FateCard.CardType.VISUAL, RARITY_COMMON)
	card.icon_emoji = "🦖"
	card.short_description = "节点整体放大 2 倍"
	card.description = "选择一个节点，该节点及其所有子节点放大 2 倍，伤害提升 50%，速度降低 40%"
	card.tags = ["Fate.Visual", "Fate.ScaleNode"]
	card.effect = {
		"action": FateCard.EffectAction.SCALE_UP,
		"scale": 2.0,
		"damage_scale": 1.5,
		"speed_scale": 0.6,
	}
	card.visual = {
		"action": "scale_up",
		"scale": 2.0,
		"add_eyes": true,
	}
	return card


## ========== 环境命运触发器（MAP_TRIGGER）==========

## 敌增援：连续击杀后额外刷怪
static func fate_reinforce() -> FateCard:
	var card := FateCard.new("敌增援", FateCard.CardType.RULE, RARITY_EPIC)
	card.icon_emoji = "👹"
	card.short_description = "连续击杀后额外刷新一波怪物"
	card.description = "连续击杀 5 个敌人后，在房间随机位置额外刷新一波怪物"
	card.tags = ["Fate.MapTrigger", "Fate.ReinforceWave"]
	card.effect = {
		"action": FateCard.EffectAction.REINFORCE_WAVE,
		"kill_threshold": 5,
		"spawn_count": 3,
	}
	return card


## 命运标记：击杀敌人后获得随机命卡
static func fate_mark_enemy() -> FateCard:
	var card := FateCard.new("命运标记", FateCard.CardType.RULE, RARITY_LEGENDARY)
	card.icon_emoji = "🎴"
	card.short_description = "击杀第10个敌人获得随机命卡"
	card.description = "每击杀 10 个敌人，有 50% 概率获得一张随机命运卡片"
	card.tags = ["Fate.MapTrigger", "Fate.GrantRandomCard"]
	card.effect = {
		"action": FateCard.EffectAction.GRANT_RANDOM_CARD,
		"kill_threshold": 10,
		"grant_probability": 0.5,
	}
	return card


## 幸运发现：下一箱品质提升
static func fate_lucky_chest() -> FateCard:
	var card := FateCard.new("幸运发现", FateCard.CardType.RULE, RARITY_RARE)
	card.icon_emoji = "🍀"
	card.short_description = "下一箱物品品质+1"
	card.description = "下一个开启的箱子物品品质提升 1 级（白色→蓝色→紫色→金色）"
	card.tags = ["Fate.MapTrigger", "Fate.LuckyChest"]
	card.effect = {
		"action": FateCard.EffectAction.LUCKY_CHEST,
		"upgrade_tiers": 1,
	}
	return card


## 额外掉落：下一箱额外获得一件
static func fate_extra_loot() -> FateCard:
	var card := FateCard.new("额外掉落", FateCard.CardType.RULE, RARITY_RARE)
	card.icon_emoji = "📤"
	card.short_description = "下一箱额外掉落一件物品"
	card.description = "下一个开启的箱子额外掉落一件随机物品"
	card.tags = ["Fate.MapTrigger", "Fate.ExtraLoot"]
	card.effect = {
		"action": FateCard.EffectAction.EXTRA_LOOT,
		"extra_count": 1,
	}
	return card


## 诅咒降临：房间内敌人伤害 +15%
static func fate_curse_map() -> FateCard:
	var card := FateCard.new("诅咒降临", FateCard.CardType.CURSE, RARITY_MYSTIC)
	card.icon_emoji = "💀"
	card.short_description = "本房间敌人伤害+15%"
	card.description = "当前房间内所有敌人伤害提升 15%，击杀后诅咒消失"
	card.tags = ["Fate.MapTrigger", "Fate.CurseRoomEnemies"]
	card.effect = {
		"action": FateCard.EffectAction.CURSE_ROOM_ENEMIES,
		"damage_bonus": 0.15,
		"clear_on_kill": true,
	}
	return card


## 亡者祝福：低血量存活后伤害 +10%
static func fate_bless_dead() -> FateCard:
	var card := FateCard.new("亡者祝福", FateCard.CardType.RULE, RARITY_EPIC)
	card.icon_emoji = "✨"
	card.short_description = "HP<30%存活30秒→伤害+10%"
	card.description = "当 HP 低于 30% 时存活 30 秒，获得伤害 +10% 的祝福（可叠加）"
	card.tags = ["Fate.MapTrigger", "Fate.BlessDead"]
	card.effect = {
		"action": FateCard.EffectAction.BLESS_DEAD,
		"hp_threshold": 0.3,
		"survive_duration": 30.0,
		"damage_bonus": 0.1,
		"max_stacks": 3,
	}
	return card


## ========== 月亮命运：角色本局规则（不占武器槽）==========

static func _scoped_modifier_card(
	card_name: String,
	card_type: FateCard.CardType,
	rarity: FateCard.CardRarity,
	icon: String,
	short_text: String,
	full_text: String,
	modifier: String,
	params: Dictionary
) -> FateCard:
	var card := FateCard.new(card_name, card_type, rarity)
	card.icon_emoji = icon
	card.short_description = short_text
	card.description = full_text
	card.tags = ["Fate.ScopedModifier", "Fate.%s" % FateCard.scope_name(card.scope)]
	card.effect = {
		"action": FateCard.EffectAction.APPLY_SCOPED_MODIFIER,
		"modifier": modifier,
	}
	card.effect.merge(params, true)
	return card


static func moon_vitality() -> FateCard:
	return _scoped_modifier_card("月相增生", FateCard.CardType.ENHANCE, RARITY_RARE, "🌕", "生命上限+20", "最大生命提升 20，并立即恢复 20 生命", "max_hp", {"amount": 20})


static func moon_stride() -> FateCard:
	return _scoped_modifier_card("月影疾行", FateCard.CardType.ENHANCE, RARITY_RARE, "🌙", "移速+12%", "本局角色移动速度提升 12%", "move_speed", {"multiplier": 1.12})


static func moon_dash() -> FateCard:
	return _scoped_modifier_card("新月回转", FateCard.CardType.RULE, RARITY_EPIC, "🌘", "冲刺冷却-20%", "本局冲刺冷却时间缩短 20%", "dash_cooldown", {"multiplier": 0.80})


static func moon_guard() -> FateCard:
	return _scoped_modifier_card("银月护体", FateCard.CardType.ENHANCE, RARITY_EPIC, "🛡", "受伤-12%", "本局角色受到的伤害降低 12%", "damage_taken", {"multiplier": 0.88})


static func moon_power() -> FateCard:
	return _scoped_modifier_card("月刃共鸣", FateCard.CardType.ENHANCE, RARITY_EPIC, "🌒", "枪伤+12%", "本局角色造成的枪械伤害提升 12%", "weapon_damage", {"multiplier": 1.12})


static func moon_room_heal() -> FateCard:
	return _scoped_modifier_card("潮汐疗愈", FateCard.CardType.RULE, RARITY_RARE, "🌊", "进新房回血6", "首次进入房间时恢复 6 生命", "room_heal", {"amount": 6})


static func moon_elite_heal() -> FateCard:
	return _scoped_modifier_card("猎月回响", FateCard.CardType.RULE, RARITY_EPIC, "🏹", "杀精英回血20", "击杀精英或首领时恢复 20 生命", "elite_heal", {"amount": 20})


static func moon_first_hit() -> FateCard:
	return _scoped_modifier_card("静夜屏障", FateCard.CardType.RULE, RARITY_LEGENDARY, "🌌", "首次受伤减半", "每个房间第一次受到的伤害降低 50%", "first_hit_guard", {"multiplier": 0.50})


static func moon_last_stand() -> FateCard:
	return _scoped_modifier_card("残月不灭", FateCard.CardType.RULE, RARITY_LEGENDARY, "🌗", "致命伤保留1血", "致命伤改为保留 1 生命；每张牌提供 1 次", "last_stand", {"charges": 1})


static func moon_ammo() -> FateCard:
	return _scoped_modifier_card("月华装填", FateCard.CardType.RULE, RARITY_RARE, "🌔", "进新房补弹20%", "首次进入房间时补充弹匣容量的 20%", "room_ammo", {"ratio": 0.20})


## ========== 太阳命运：世界/房间规则（不占武器槽）==========

static func sun_quality() -> FateCard:
	return _scoped_modifier_card("晨曦宝库", FateCard.CardType.RULE, RARITY_RARE, "🌅", "下箱品质+1", "下一个开启容器的物品品质提升 1 级", "next_chest_quality", {"tiers": 1})


static func sun_extra_loot() -> FateCard:
	return _scoped_modifier_card("丰收日", FateCard.CardType.RULE, RARITY_EPIC, "🌾", "下箱额外2件", "下一个开启容器额外掉落 2 件物品", "next_chest_extra", {"count": 2})


static func sun_reinforce() -> FateCard:
	return _scoped_modifier_card("日冕增援", FateCard.CardType.RULE, RARITY_EPIC, "☀", "下房敌人+3", "下一个敌对房间额外出现 3 名敌人", "next_room_enemy_count", {"count": 3})


static func sun_reveal() -> FateCard:
	return _scoped_modifier_card("曙光测绘", FateCard.CardType.RULE, RARITY_RARE, "🗺", "揭示周围2层", "立即揭示当前房间周围 2 层相邻房间", "reveal_rooms", {"radius": 2})


static func sun_key() -> FateCard:
	return _scoped_modifier_card("太阳钥印", FateCard.CardType.ENHANCE, RARITY_RARE, "🔑", "获得房间钥匙", "立即获得 1 把普通房间钥匙", "grant_room_key", {"count": 1})


static func sun_currency() -> FateCard:
	return _scoped_modifier_card("黄金潮汐", FateCard.CardType.ENHANCE, RARITY_EPIC, "🪙", "魂获取+30%", "本局之后获得的魂数量提升 30%", "currency_gain", {"multiplier": 1.30})


static func sun_scorch() -> FateCard:
	return _scoped_modifier_card("天火灼地", FateCard.CardType.RULE, RARITY_EPIC, "🔥", "下房敌血-20%", "下一个敌对房间的敌人最大生命降低 20%", "next_room_enemy_hp", {"multiplier": 0.80})


static func sun_trial() -> FateCard:
	return _scoped_modifier_card("烈日试炼", FateCard.CardType.CURSE, RARITY_LEGENDARY, "🌞", "强敌双倍魂", "下一个敌对房间敌人伤害提升 25%，其魂掉落翻倍", "next_room_trial", {"damage_multiplier": 1.25, "currency_multiplier": 2.0})


static func sun_bounty() -> FateCard:
	return _scoped_modifier_card("长昼赏金", FateCard.CardType.RULE, RARITY_EPIC, "🏆", "三房各奖35魂", "接下来 3 个敌对房间肃清时各获得 35 魂", "room_clear_bounty", {"rooms": 3, "amount": 35})


static func sun_extraction() -> FateCard:
	return _scoped_modifier_card("日落捷径", FateCard.CardType.RULE, RARITY_LEGENDARY, "🌇", "撤离时间-20%", "本局所有撤离同步时间缩短 20%", "extraction_time", {"multiplier": 0.80})


## ========== 总汇 ==========

## 所有预设卡片（含不可直接获得的 MAP_TRIGGER 类）
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
		chain_lightning(),
		bounce_bullet(),
		home_on_land(),
		barrage_copy(),
		fuse_fire(),
		fuse_frost(),
		fuse_poison(),
		out_of_control(),
		gluttony(),
		explode_on_reload(),
		every_seventh(),
		crit_on_kill(),
		huge_scale(),
		fate_reinforce(),
		fate_mark_enemy(),
		fate_lucky_chest(),
		fate_extra_loot(),
		fate_curse_map(),
		fate_bless_dead(),
		moon_vitality(), moon_stride(), moon_dash(), moon_guard(), moon_power(),
		moon_room_heal(), moon_elite_heal(), moon_first_hit(), moon_last_stand(), moon_ammo(),
		sun_quality(), sun_extra_loot(), sun_reinforce(), sun_reveal(), sun_key(),
		sun_currency(), sun_scorch(), sun_trial(), sun_bounty(), sun_extraction(),
	]


## 玩家可获得的卡池（门命运/三选一/工作台共用）
## 包含 MAP_TRIGGER 类命运卡（环境命运触发器，由 MapFateTriggers.gd 管理）
static func playable_presets() -> Array[FateCard]:
	return [
		scale_up(),           # 📦 变大了
		overclock(),          # ⚡ 超频
		armor_pierce(),      # 🎯 穿甲强化
		bullet_carry_gun(), # 🔫 子弹背枪
		gun_on_gun(),       # 🔗 枪上加枪
		attachment_parasite(), # 🦠 配件寄生（命中触发配件效果）
		living_bullet(),    # 👁 活过来
		turret_on_land(),   # 🏰 落地炮台
		home_on_land(),    # 🏠 回家看看
		bullet_return(),    # ↩️ 子弹折返
		chain_lightning(),  # ⚡ 连锁闪电
		bounce_bullet(),    # 🏓 弹跳弹
		barrage_copy(),     # 🎆 弹幕模式
		fuse_fire(),        # 🔥 火焰子弹
		fuse_frost(),      # ❄️ 冰霜子弹
		fuse_poison(),      # ☠️ 剧毒子弹
		out_of_control(),   # 😱 管不住了（诅咒·乱射）
		gluttony(),         # 🌙 火力暴食（诅咒·渐大）
		explode_on_reload(), # 💥 换弹爆炸（诅咒）
		every_seventh(),    # 7️⃣ 每第七发
		crit_on_kill(),     # 💥 致命一击
		huge_scale(),       # 🦖 巨大化
		fate_reinforce(),   # 👹 敌增援（连续击杀→额外刷怪）
		fate_mark_enemy(),  # 🎴 命运标记（击杀获得随机命卡）
		fate_lucky_chest(), # 🍀 幸运发现（下一箱品质提升）
		fate_extra_loot(),  # 📤 额外掉落（下一箱额外一件）
		fate_curse_map(),   # 💀 诅咒降临（房间敌人伤害+15%）
		fate_bless_dead(),  # ✨ 亡者祝福（低血存活伤害+10%）
		moon_vitality(), moon_stride(), moon_dash(), moon_guard(), moon_power(),
		moon_room_heal(), moon_elite_heal(), moon_first_hit(), moon_last_stand(), moon_ammo(),
		sun_quality(), sun_extra_loot(), sun_reinforce(), sun_reveal(), sun_key(),
		sun_currency(), sun_scorch(), sun_trial(), sun_bounty(), sun_extraction(),
	]


## 开门命运与工作台/局前展示共享可玩牌池
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


## 通过卡牌ID获取预设（用于存档/比对）
static func get_by_card_id(card_id: String) -> FateCard:
	for card in all_presets():
		if card.card_id == card_id:
			return card
	return null
