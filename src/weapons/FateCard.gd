extends RefCounted
class_name FateCard

# FateCard.gd — 命运卡片数据对象
# 命运卡片系统的基础数据结构
# 一张卡 = 类型 + 品质 + 标签 + 效果 + 可选视觉改造。
# 它从不进入 SceneTree；使用 RefCounted 避免每次生成卡池都遗留孤立 Node。

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

enum Scope {
	WEAPON,
	CHARACTER,
	WORLD,
}

const STABLE_ID_BY_NAME := {
	"变大了": "fate_scale_node",
	"超频": "fate_overclock",
	"穿甲强化": "fate_armor_pierce",
	"子弹背枪": "fate_bullet_carry_gun",
	"枪上加枪": "fate_gun_on_gun",
	"配件寄生": "fate_attachment_parasite",
	"活过来": "fate_living_bullet",
	"落地炮台": "fate_turret_on_land",
	"回家看看": "fate_home_on_land",
	"子弹折返": "fate_bullet_return",
	"连锁闪电": "fate_chain_lightning",
	"弹跳弹": "fate_bounce_bullet",
	"弹幕模式": "fate_barrage_copy",
	"火焰子弹": "fate_fuse_fire",
	"冰霜子弹": "fate_fuse_frost",
	"剧毒子弹": "fate_fuse_poison",
	"管不住了": "fate_out_of_control",
	"火力暴食": "fate_gluttony",
	"换弹爆炸": "fate_explode_reload",
	"每第七发": "fate_every_seventh",
	"致命一击": "fate_crit_kill",
	"巨大化": "fate_huge_scale",
	"敌增援": "fate_reinforce",
	"命运标记": "fate_mark_enemy",
	"幸运发现": "fate_lucky_chest",
	"额外掉落": "fate_extra_loot",
	"诅咒降临": "fate_curse_map",
	"亡者祝福": "fate_bless_dead",
	"月相增生": "fate_moon_vitality",
	"月影疾行": "fate_moon_stride",
	"新月回转": "fate_moon_dash",
	"银月护体": "fate_moon_guard",
	"月刃共鸣": "fate_moon_power",
	"潮汐疗愈": "fate_moon_room_heal",
	"猎月回响": "fate_moon_elite_heal",
	"静夜屏障": "fate_moon_first_hit",
	"残月不灭": "fate_moon_last_stand",
	"月华装填": "fate_moon_ammo",
	"晨曦宝库": "fate_sun_quality",
	"丰收日": "fate_sun_extra_loot",
	"日冕增援": "fate_sun_reinforce",
	"曙光测绘": "fate_sun_reveal",
	"太阳钥印": "fate_sun_key",
	"黄金潮汐": "fate_sun_currency",
	"天火灼地": "fate_sun_scorch",
	"烈日试炼": "fate_sun_trial",
	"长昼赏金": "fate_sun_bounty",
	"日落捷径": "fate_sun_extraction",
}

const CHARACTER_SCOPE_IDS := [
	"fate_mark_enemy", "fate_bless_dead",
	"fate_moon_vitality", "fate_moon_stride", "fate_moon_dash", "fate_moon_guard",
	"fate_moon_power", "fate_moon_room_heal", "fate_moon_elite_heal",
	"fate_moon_first_hit", "fate_moon_last_stand", "fate_moon_ammo",
]
const WORLD_SCOPE_IDS := [
	"fate_reinforce", "fate_lucky_chest", "fate_extra_loot", "fate_curse_map",
	"fate_sun_quality", "fate_sun_extra_loot", "fate_sun_reinforce",
	"fate_sun_reveal", "fate_sun_key", "fate_sun_currency", "fate_sun_scorch",
	"fate_sun_trial", "fate_sun_bounty", "fate_sun_extraction",
]

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

	# 变种类（扩展）
	MUTATE_TO_CHAIN,           # 连锁闪电
	MUTATE_TO_TURRET_ON_LAND,  # 落地炮台
	MUTATE_TO_HOME_ON_LAND,    # 落地后返航（回家看看）

	# 诅咒类
	OUT_OF_CONTROL,           # 子弹上的枪乱射（管不住了）
	SIZE_GROWTH,             # 子弹越打越大（火力暴食）
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
	APPLY_SCOPED_MODIFIER,    # 角色/月亮与世界/太阳的通用局内规则
}

## 元数据
var card_id: String = ""
var stable_card_id: String = ""
var card_name: String = ""
var description: String = ""          # 完整说明（可选，UI可显示简化版）
var short_description: String = ""     # 简化版单行说明（用于UI显示）
var icon_emoji: String = ""           # 物品图标emoji（用于UI显示）

## 类型与品质
var card_type: CardType = CardType.ENHANCE
var card_rarity: CardRarity = CardRarity.COMMON
var scope: Scope = Scope.WEAPON

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
	card_name = p_name
	card_type = p_type
	card_rarity = p_rarity
	stable_card_id = str(STABLE_ID_BY_NAME.get(p_name, ""))
	card_id = stable_card_id if not stable_card_id.is_empty() else _generate_id()
	if stable_card_id in CHARACTER_SCOPE_IDS:
		scope = Scope.CHARACTER
	elif stable_card_id in WORLD_SCOPE_IDS:
		scope = Scope.WORLD
	else:
		scope = Scope.WEAPON

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


static func scope_name(value: Scope) -> String:
	match value:
		Scope.WEAPON: return "WEAPON"
		Scope.CHARACTER: return "CHARACTER"
		Scope.WORLD: return "WORLD"
	return "UNKNOWN"


static func scope_special_name(value: Scope) -> String:
	match value:
		Scope.WORLD: return "太阳命运"
		Scope.CHARACTER: return "月亮命运"
		Scope.WEAPON: return "星星命运"
	return "未知命运"


static func scope_symbol(value: Scope) -> String:
	match value:
		Scope.WORLD: return "☀"
		Scope.CHARACTER: return "☾"
		Scope.WEAPON: return "★"
	return "?"


static func scope_display_name(value: Scope) -> String:
	return "%s %s" % [scope_symbol(value), scope_special_name(value)]


static func scope_target_text(value: Scope) -> String:
	match value:
		Scope.WORLD: return "世界规则 · 不占武器槽"
		Scope.CHARACTER: return "本局角色 · 不占武器槽"
		Scope.WEAPON: return "当前枪械 · 永久占用1格"
	return "目标未知"


static func scope_color(value: Scope) -> Color:
	match value:
		Scope.WORLD: return Color("F6B94A")
		Scope.CHARACTER: return Color("9FC7FF")
		Scope.WEAPON: return Color("C99BFF")
	return Color.WHITE


func get_stable_card_id() -> String:
	return stable_card_id if not stable_card_id.is_empty() else card_id


func occupies_weapon_slot() -> bool:
	return scope == Scope.WEAPON

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
		"stable_card_id": get_stable_card_id(),
		"scope": scope_name(scope),
		"name": card_name,
		"type": type_name(card_type),
		"rarity": rarity_name(card_rarity),
		"tags": tags,
		"effect": effect,
		"visual": visual,
	}

func _to_string() -> String:
	return "[FateCard:%s %s(%s)]" % [card_id, card_name, rarity_name(card_rarity)]
