extends Node
class_name FateCard

# FateCard.gd — 命运卡片节点
# 命运卡片系统的基础数据结构
# 一张卡 = 类型 + 品质 + 标签 + 效果 + 可选视觉改造

## 卡片类型枚举
enum CardType {
	COMBINE,   # 组合卡：把两个节点连接起来
	ENHANCE,   # 强化卡：提升数值或触发频率
	MUTATE,    # 变种卡：改变模块行为
	COPY,      # 复制卡：复制节点或效果
	FUSE,      # 融合卡：两个模块合成新模块
	CURSE,     # 诅咒卡：强力但带副作用
	RULE,      # 规则卡：改变触发规则
	VISUAL,    # 视觉卡：改变表现，少量改变属性
}

## 卡片品质枚举
enum CardRarity {
	COMMON,    # 白色：简单强化，稳定安全
	RARE,      # 蓝色：改变某个行为，收益明显
	EPIC,      # 紫色：产生组合关系，构筑核心
	LEGENDARY, # 金色：改变武器树结构，强力稀有
	MYSTIC,    # 红色：诅咒或失控型效果，极强但危险
}

## 效果动作枚举（Effect.action 的可能值）
enum EffectAction {
	# 组合类
	ATTACH_GUN_TO_BULLET,     # 子弹上挂枪（子弹背枪）
	ATTACH_BULLET_TO_GUN,     # 枪身上挂子弹
	ATTACH_TO_MOUNT,          # 挂载槽挂载任意节点
	ATTACH_GUN_TO_GUN,        # 枪上加枪（主枪开火时副枪也开火）

	# 强化类
	SCALE_NODE,               # 缩放节点（变大了）
	MULTIPLY_FIRE_RATE,       # 射速倍率（超频）
	ADD_DAMAGE,               # 增加伤害
	ADD_SPREAD,               # 增加扩散
	ADD_BULLET_COUNT,         # 增加子弹数量

	# 变种类
	MUTATE_TO_HOMING,         # 变成追踪弹（活过来）
	MUTATE_TO_BOUNCE,         # 变成弹跳弹
	MUTATE_TO_LIVING,         # 变成活体子弹

	# 复制类
	COPY_NODE,                # 复制节点

	# 融合类
	FUSE_DAMAGE,              # 伤害融合
	FUSE_SPEED,               # 速度融合

	# 诅咒类
	EXPLODE_ON_RELOAD,        # 换弹爆炸
	SLUGGISH,                 # 卡壳（降低命中率）
	SLOW_ON_HIT,              # 命中后减速

	# 规则类
	EVERY_NTH_FIRE,           # 每第N发触发特殊效果
	CRIT_ON_KILL,             # 击杀必暴击

	# 视觉类
	SCALE_UP,                 # 巨大化
	ADD_EYES,                 # 加眼睛动画
	ADD_LEGS,                 # 加脚动画

	# 环境命运触发器专用（无目标节点）
	REINFORCE_WAVE,           # 触发波次外额外刷怪
	GRANT_RANDOM_CARD,        # 给予随机命运卡片
	LUCKY_CHEST,              # 下次开箱品质提升
	EXTRA_LOOT,               # 下次开箱额外掉落
	CURSE_ROOM_ENEMIES,       # 当前房间敌人伤害提升（诅咒）
	BLESS_DEAD,               # 低血量存活后获得伤害加成（祝福）
}

## 元数据
var card_id: String = ""
var card_name: String = ""
var description: String = ""

## 类型与品质
var card_type: CardType = CardType.ENHANCE
var card_rarity: CardRarity = CardRarity.COMMON

## 标签（用于规则检查）
var tags: Array[String] = []

## 目标选择规则
## selectTarget() 会根据这些规则筛选可用节点
var target_rules: Array[Dictionary] = []

## 效果定义
var effect: Dictionary = {}

## 可选视觉改造
var visual: Dictionary = {}

## 唯一计数器
static var _id_counter: int = 0

func _init(p_name: String = "", p_type: CardType = CardType.ENHANCE, p_rarity: CardRarity = CardRarity.COMMON) -> void:
	card_id = _generate_id()
	card_name = p_name
	card_type = p_type
	card_rarity = p_rarity

static func _generate_id() -> String:
	_id_counter += 1
	return "fate_card_%04d" % _id_counter

## 获取品质名称
static func rarity_name(r: CardRarity) -> String:
	match r:
		CardRarity.COMMON: return "普通"
		CardRarity.RARE: return "稀有"
		CardRarity.EPIC: return "史诗"
		CardRarity.LEGENDARY: return "传说"
		CardRarity.MYSTIC: return "禁忌"
	return "未知"

## 获取类型名称
static func type_name(t: CardType) -> String:
	match t:
		CardType.COMBINE: return "组合"
		CardType.ENHANCE: return "强化"
		CardType.MUTATE: return "变种"
		CardType.COPY: return "复制"
		CardType.FUSE: return "融合"
		CardType.CURSE: return "诅咒"
		CardType.RULE: return "规则"
		CardType.VISUAL: return "视觉"
	return "未知"

## 获取品质颜色（用于 UI）
static func rarity_color(r: CardRarity) -> Color:
	match r:
		CardRarity.COMMON: return Color.WHITE
		CardRarity.RARE: return Color("4A9EFF")      # 蓝色
		CardRarity.EPIC: return Color("A855F7")     # 紫色
		CardRarity.LEGENDARY: return Color("F59E0B") # 金色
		CardRarity.MYSTIC: return Color("EF4444")    # 红色
	return Color.WHITE

## 获取调试信息
func get_debug_info() -> Dictionary:
	return {
		"card_id": card_id,
		"name": card_name,
		"type": type_name(card_type),
		"rarity": rarity_name(card_rarity),
		"tags": tags,
		"effect": effect,
		"visual": visual,
	}

func _to_string() -> String:
	return "[FateCard:%s %s(%s)]" % [card_id, card_name, rarity_name(card_rarity)]