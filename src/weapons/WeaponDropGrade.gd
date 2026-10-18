class_name WeaponDropGrade
extends RefCounted
## 掉落武器的**品质**（蓝 / 紫 / 金）—— 唯一真源。
##
## 与物品自身的 `rarity`（common / uncommon / rare / epic / legendary）是**两个维度**：
##   · `rarity` = 这是哪把枪（豌豆手枪是 common，蓄力萝卜炮是 epic），写死在物品表里。
##   · `drop_grade` = 这一把枪滚出了什么品质，**每次掉落独立随机**。
## 不要拿 rarity 冒充品质：命运卡的品质提升规则（`Dungeon3D._apply_fate_item_quality`）
## 写的也是 rarity，两者混用会让"这把紫枪"和"这件紫装"的数字互相打架。
##
## 业主口径（2026-10-18）：
##   蓝 = 基础数值
##   紫 = 基础数值上伤害 +10%、命运卡格子 +2
##   金 = 基础数值上伤害 +15%、命运卡格子 +4
##
## ## 为什么必须存字段而不是算出来
## 品质是**实例属性**：同一把 `weapon_rifle`，玩家背包里可能同时躺着一把金的和一把蓝的。
## 所以品质在掉落那一刻写进物品字典、随实例走完背包 / 地面 / 保险 / 结算 / 存档。
##
## ## 伤害为什么不在掉落时乘进快照
## `assembly_snapshot` 里的 `base_stats` 会原样存档。若把 ×1.10 乘进去，读档时
## `from_item → build_runtime_tree` 会再乘一次，反复读档就复利 —— 实测这种写法
## 三进三出能把 10% 变成 33%。因此倍率只存**品质标签**，运行时由
## `WeaponAssemblyTree.get_computed_stats()` 现场乘一次（幂等）。

const GRADE_BLUE := "blue"
const GRADE_PURPLE := "purple"
const GRADE_GOLD := "gold"

## 掷骰顺序。改顺序会改变同一 seed 的落点 ⇒ 必须与文档同批改，否则「同局可复现」失效。
const ROLL_ORDER: Array[String] = [GRADE_BLUE, GRADE_PURPLE, GRADE_GOLD]

## 品质权重。总和必须为 1.0（`verify_weapon_drop_grade` 断言）。
## 70 / 25 / 5 的理由：Boss 一次 1-2 把、强化怪 25% 一把，单局枪械产出约 3 把
## ⇒ 期望每局约 0.75 把紫、0.15 把金。金色约 7 局一把，稀有但不至于见不到。
const ROLL_WEIGHTS: Dictionary = {
	GRADE_BLUE: 0.70,
	GRADE_PURPLE: 0.25,
	GRADE_GOLD: 0.05,
}

## 品质规格。`damage_mult` 是**乘法**（写 1.10 就是 +10%，不是 ×1.1 再叠基础）。
## `fate_slot_bonus` 是**加法**，叠加在物品表声明的 `fate_slot_capacity` 之上。
const GRADES: Dictionary = {
	GRADE_BLUE: {
		"display": "蓝",
		"damage_mult": 1.00,
		"fate_slot_bonus": 0,
		"color": Color(0.36, 0.72, 1.0),
	},
	GRADE_PURPLE: {
		"display": "紫",
		"damage_mult": 1.10,
		"fate_slot_bonus": 2,
		"color": Color(0.72, 0.44, 1.0),
	},
	GRADE_GOLD: {
		"display": "金",
		"damage_mult": 1.15,
		"fate_slot_bonus": 4,
		"color": Color(1.0, 0.78, 0.24),
	},
}

## 物品表没写 `fate_slot_capacity` 时的兜底。**必须与
## `WeaponInstance.DEFAULT_FATE_SLOT_CAPACITY` 同值**（8）—— 那边是运行时默认，
## 这里是「掉落时算加成」的默认；两处不一致会让蓝枪的命运槽凭空少 4 格。
const FALLBACK_FATE_SLOT_CAPACITY := 8


## 按 0..1 的均匀抽样值决定品质。传 `rng.randf()`。
##
## 为什么吃抽样值而不是自己掷：掉落必须走 `RewardService` 的确定性 rng，
## 才能保证「同 run_seed + 同一击杀事件 ⇒ 同一把枪、同一品质」。
static func roll(roll_value: float) -> String:
	var value := clampf(roll_value, 0.0, 0.999999)
	var cumulative := 0.0
	for grade in ROLL_ORDER:
		cumulative += float(ROLL_WEIGHTS[grade])
		if value < cumulative:
			return grade
	return GRADE_GOLD


## 归一化：未知 / 空串一律视为蓝（蓝是「没有额外加成」的基线，不会凭空加强）。
static func normalize(raw: String) -> String:
	return raw if GRADES.has(raw) else GRADE_BLUE


static func is_valid(grade: String) -> bool:
	return GRADES.has(grade)


static func damage_multiplier(grade: String) -> float:
	return float((GRADES[normalize(grade)] as Dictionary)["damage_mult"])


static func fate_slot_bonus(grade: String) -> int:
	return int((GRADES[normalize(grade)] as Dictionary)["fate_slot_bonus"])


static func display_name(grade: String) -> String:
	return str((GRADES[normalize(grade)] as Dictionary)["display"])


static func color(grade: String) -> Color:
	return (GRADES[normalize(grade)] as Dictionary)["color"] as Color


## 把品质写进物品字典（顶层 + `weapon_instance` 嵌套层都要写）。
##
## 返回**新字典**，不改入参 —— 调用方（RewardService）拿到的是池成员 / 物品定义的副本，
## 就地改会污染同一次击杀里的其它条目。
##
## `fate_slot_capacity` 只在这里加一次：掉落即落盘，之后 `from_item` 只读不算，
## 因此反复读档不会复利。内容表若日后调整基线容量，已掉落的老实例保持自己的值
## （实例是快照，与 `rarity` 同一口径）。
static func apply_to_item(item: Dictionary, grade: String) -> Dictionary:
	if item.is_empty():
		return item
	var resolved := normalize(grade)
	var out := item.duplicate(true)
	# 幂等守卫：已带品质的物品**不再加格子**。掉落边界只调用一次，但这条守卫挡住了
	# 「有人对着背包里的枪再调一次」这种误用 —— 否则命运槽会越加越多。
	var already_graded := is_valid(str(item.get("drop_grade", "")))
	out["drop_grade"] = resolved

	var capacity := int(out.get("fate_slot_capacity", 0))
	if capacity <= 0:
		capacity = FALLBACK_FATE_SLOT_CAPACITY
	out["fate_slot_capacity"] = capacity if already_graded else capacity + fate_slot_bonus(resolved)

	var nested_value: Variant = out.get("weapon_instance", {})
	if nested_value is Dictionary:
		var nested := (nested_value as Dictionary).duplicate(true)
		nested["drop_grade"] = resolved
		nested["fate_slot_capacity"] = out["fate_slot_capacity"]
		out["weapon_instance"] = nested
	return out


## 地面名牌文字。**掉落文字上体现品质**的唯一实现（业主 2026-10-18）。
##
## 三档都标：玩家需要一眼分清「这把是蓝的」而不是「这把没标」。
## 格式 `蓝｜步枪`：竖线前是品质，竖线后是原物品名 —— 不把品质塞进 `name`，
## 否则背包、结算、存档里的物品名会被污染成一堆前缀。
static func label_for(data: Dictionary) -> String:
	var item_name := str(data.get("name", data.get("id", "物资")))
	if str(data.get("type", "")) != "weapon":
		return item_name
	if not is_valid(str(data.get("drop_grade", ""))):
		return item_name
	return "%s｜%s" % [display_name(str(data["drop_grade"])), item_name]


## 一行摘要，供验收 / 工具打印判据。
static func summary_line() -> String:
	return "WEAPON_DROP_GRADE blue=%.2f purple=%.2f gold=%.2f | purple dmg×%.2f slots+%d | gold dmg×%.2f slots+%d" % [
		float(ROLL_WEIGHTS[GRADE_BLUE]), float(ROLL_WEIGHTS[GRADE_PURPLE]), float(ROLL_WEIGHTS[GRADE_GOLD]),
		damage_multiplier(GRADE_PURPLE), fate_slot_bonus(GRADE_PURPLE),
		damage_multiplier(GRADE_GOLD), fate_slot_bonus(GRADE_GOLD),
	]
