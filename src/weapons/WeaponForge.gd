class_name WeaponForge
extends RefCounted
## 武器改造台（炼金抽卡）—— 纯规则层，唯一真源。
##
## 盘面是 6×6 = 36 格；玩家把武器与弹药模块投进去，换出一把品质与弹种重新掷骰的新枪。
## 本文件只做四件事：**判定能不能炼 / 算品质概率 / 掷骰 / 构建产出物品字典**。
## 不碰场景、不碰 UI、不写背包 —— 事务由 `WorkbenchPanel` 负责。
##
## ## 三条配方（判定自上而下，命中即停）
##   R1 重铸 `remelt`    ：1 把武器 + ≥1 个弹药模块 → 1 把，同枪身蓝本
##   R2 融合 `fusion`    ：≥2 把武器            → 1 把，取伤害最高者为蓝本 + 随机附带配件
##   R3 合成 `synthesis` ：0 武器 + 熔炼值 ≥6   → floor(V/6) 把（≤3），枪身随机
##
## ## 为什么 R1 必须有燃料
## 若允许「1 把枪单独重铸」，玩家能拿同一把枪反复掷品质而只承担"枪还是枪"的风险 ——
## 品质池没有下降档，这是纯套利。把成本钉在消耗品上，赌局才成立。
##
## ## 品质与弹种的常量一律不许在这里复制
## 品质规格（伤害倍率 / 命运槽加成 / 颜色 / 基础权重）唯一真源是 `WeaponDropGrade`；
## 弹种池唯一真源是 `WeaponBulletDrop`。这里只做**加权与掷骰**，不重新定义任何档位。
## 复制常量会让"改一处、另一处忘了改"，而这类漂移在数值上不可见、只在体验上崩。

## ————————————————————————————————
## 盘面
## ————————————————————————————————
## 5×5：业主 2026-10-18 要求盘面"尽可能四方形"，并明确先按 5×5 做。
## 面板 `WorkbenchPanel` 的常量必须与这里逐值一致（验收钉住）。
const TRAY_COLUMNS := 5
const TRAY_ROWS := 5
const TRAY_CAPACITY := TRAY_COLUMNS * TRAY_ROWS

## ————————————————————————————————
## 配方参数
## ————————————————————————————————
## 武器数硬上限：36 格理论上能塞 18 把手枪，但 >6 之后加成已无意义，
## 且会让「投越多越赚」变成唯一解。
const MAX_BLUEPRINT_WEAPONS := 6

## R3 的熔炼门槛与单次产出上限。
const MELT_THRESHOLD := 6
const MAX_MELT_OUTPUT := 3

## 熔炼值：按物品 `rarity` 计。只用于 R3 计数。
## 与 `WeaponDropGrade` 的 rarity 分级同源（common→legendary 五档）。
const MELT_VALUES: Dictionary = {
	"common": 1,
	"uncommon": 2,
	"rare": 3,
	"epic": 4,
	"legendary": 6,
}
const DEFAULT_MELT_VALUE := 1

## ————————————————————————————————
## 品质权重
## ————————————————————————————————
## 每多投 1 把武器，各档权重乘这个系数（蓝降、紫金升）。
const WEAPON_WEIGHT_STEP: Dictionary = {
	WeaponDropGrade.GRADE_BLUE: 0.55,
	WeaponDropGrade.GRADE_PURPLE: 1.35,
	WeaponDropGrade.GRADE_GOLD: 1.75,
}

## 每 1 点**稀有度分**对权重的倾斜（绝对值，非比例）。蓝是负的。
##
## 系数比"按熔炼值倾斜"陡得多：熔炼值只是数量门槛，稀有度分才是品质驱动。
## 实测梯度（n=1，R 为稀有度分）：
##   R=0  → 蓝 70.0%  紫 25.0%  金 5.0%
##   R=3  → 蓝 64.9%  紫 28.0%  金 7.0%      （1 件 rare）
##   R=10 → 蓝 53.4%  紫 35.0%  金 11.6%     （约 2 件 epic + 1 件 rare）
##   R=20 → 蓝 37.7%  紫 44.3%  金 17.9%
##   R=40 → 蓝 8.9%   紫 61.6%  金 29.5%     （需要堆大量稀有材料）
const RARITY_WEIGHT_TILT: Dictionary = {
	WeaponDropGrade.GRADE_BLUE: -0.015,
	WeaponDropGrade.GRADE_PURPLE: 0.011,
	WeaponDropGrade.GRADE_GOLD: 0.007,
}

## 蓝权重地板：加权再狠也不能把蓝打到 0，否则「炼不炼」就没有悬念了。
const BLUE_WEIGHT_FLOOR := 0.05

## ————————————————————————————————
## 配方与拒绝码
## ————————————————————————————————
const RECIPE_NONE := ""
const RECIPE_REMELT := "remelt"
const RECIPE_FUSION := "fusion"
const RECIPE_SYNTHESIS := "synthesis"

const REJECT_EMPTY_TRAY := "empty_tray"
const REJECT_SINGLE_WEAPON_WITHOUT_FUEL := "single_weapon_without_fuel"
const REJECT_INSUFFICIENT_FUEL := "insufficient_fuel"
const REJECT_INSUFFICIENT_MELT := "insufficient_melt"
const REJECT_BACKPACK_FULL := "backpack_full"
const REJECT_INSUFFICIENT_CURRENCY := "insufficient_currency"
const REJECT_NO_BLUEPRINT := "no_blueprint"
const REJECT_NO_OUTPUT := "no_output"

## R1 的燃料门槛（熔炼值）。**所有物品都能当材料**，但"能当"不等于"一件就够"。
##
## 定成 3 而不是 1：若一件 common 消耗品（1 点）就能重铸，玩家会拿垃圾把
## 一把枪反复掷品质，而品质池没有下降档 ⇒ 纯套利。3 点意味着
## 「3 个 common」或「1 个 rare」或「1 个 uncommon + 1 个 common」——
## 门槛不高，但足以让每次重铸真的付出东西。
const FUEL_THRESHOLD := 3

## R2 的随机配件数：n=2 → 1 个，n≥3 → 2 个。
const FUSION_ATTACHMENTS := {2: 1, 3: 2}

## ————————————————————————————————
## 稀有度分（"材料的稀有度会提升稀有度"）
## ————————————————————————————————
## 与 `MELT_VALUES` 是**两张不同的表**，别合并：
##   · `MELT_VALUES` 算「熔炼值」—— 决定 R1 燃料门槛与 R3 产出数量，平滑（1/2/3/4/6）。
##   · `RARITY_POINTS` 算「稀有度分」—— 决定品质概率，陡峭（0/1/2/4/7），
##     且 **common 恒为 0**。
##
## common 在稀有度分里必须是 0：否则拿一堆白装堆满 36 格就能把金概率顶上去，
## 而白装是战局里最不缺的东西 —— 那等于给了一条零成本的搏金通道。
## 熔炼值那边 common 仍是 1，因为"凑够 6 点"是数量门槛，不是品质门槛。
const RARITY_POINTS: Dictionary = {
	"common": 0,
	"uncommon": 1,
	"rare": 2,
	"epic": 4,
	"legendary": 7,
}

## 已带掉落品质的物品，品质本身也折算稀有度分（紫 +1 / 金 +2）。
##
## 理由：一把金品质步枪当材料，显然比同名蓝品质的更值钱。
## 不加这一项，玩家会发现"把金枪熔了和熔蓝枪一个结果"，那是反直觉的。
const GRADE_RARITY_BONUS: Dictionary = {
	WeaponDropGrade.GRADE_BLUE: 0,
	WeaponDropGrade.GRADE_PURPLE: 1,
	WeaponDropGrade.GRADE_GOLD: 2,
}

## ————————————————————————————————
## 金币费用
## ————————————————————————————————
## 公式：`cost = max(min_cost, ceil(投入估值 × rate))`
##
## **为什么按投入估值而不是固定价**：固定价会让"拿 350 的蓄力炮"和"拿 45 的球棒"
## 付一样的钱，等于鼓励拿最便宜的垃圾反复熔。按估值计费，贵的东西熔炼也贵，
## 玩家不会因为"熔一把贵枪才花 20"而把它当消耗品刷。
##
## **费率为什么 R3 最高**：R2 本身要牺牲一把枪（实物成本已经很重），R3 只烧弹药模块，
## 如果不加价，「捡 6 个标准弹 → 换一把枪」会变成比 R1/R2 更划算的稳定套利。
const COIN_RATE: Dictionary = {
	RECIPE_REMELT: 0.30,
	RECIPE_FUSION: 0.40,
	RECIPE_SYNTHESIS: 0.50,
}
const COIN_MIN: Dictionary = {
	RECIPE_REMELT: 20,
	RECIPE_FUSION: 40,
	RECIPE_SYNTHESIS: 40,
}

## 近战没有弹药槽。
const MELEE_TAG := "melee"
const MELEE_SUBTYPE := "melee_weapon"

## attachment item_id -> AssemblyNode.SlotType，探测一次后缓存。
static var _attachment_slot_cache: Dictionary = {}


## ————————————————————————————————
## 物品判定
## ————————————————————————————————

## 该物品能不能投进炼金盘。
##
## **所有非空物品都能当材料**（2026-10-18 业主裁决：所有东西都能当材料）。
## 武器是**蓝本**，其余都是**材料**：弹药模块、配件、消耗品、装备、蓝图碎片……
## 一律按 `rarity` 折算熔炼值与稀有度分。
##
## 只有空字典返回 false —— 那是"这一格没有物品"，不是"这件物品不被接受"。
static func accepts(item: Dictionary) -> bool:
	return not item.is_empty()


## 这件物品是不是武器（= 可当蓝本）。
static func is_blueprint_weapon(item: Dictionary) -> bool:
	return str(item.get("type", "")) == "weapon"


## 这件物品是不是弹药模块（= 可当燃料，且参与弹种抽取）。
static func is_bullet_module(item: Dictionary) -> bool:
	return (
		str(item.get("type", "")) == "module"
		and str(item.get("subtype", "")) == "bullet"
	)


## 单件物品的熔炼值（含堆叠数量）。
##
## 未知 rarity 回落 `DEFAULT_MELT_VALUE`：宁可少算，也不能让一件没登记的
## 新物品凭空值 6 点、把 R3 门槛打穿。
static func melt_value_of(item: Dictionary) -> int:
	var count := maxi(1, int(item.get("count", 1)))
	return _unit_melt_value(item) * count


static func _unit_melt_value(item: Dictionary) -> int:
	var rarity := str(item.get("rarity", "common"))
	return int(MELT_VALUES.get(rarity, DEFAULT_MELT_VALUE))


## 单件物品的稀有度分（含堆叠数量）。品质概率的唯一驱动项。
##
## = `RARITY_POINTS[rarity] + GRADE_RARITY_BONUS[drop_grade]`，再乘堆叠数量。
## 未知 rarity 回落 0：宁可少算，也不能让一件没登记的物品凭空顶高金概率。
static func rarity_points_of(item: Dictionary) -> int:
	if item.is_empty():
		return 0
	var count := maxi(1, int(item.get("count", 1)))
	return _unit_rarity_points(item) * count


static func _unit_rarity_points(item: Dictionary) -> int:
	var rarity := str(item.get("rarity", "common"))
	var points := int(RARITY_POINTS.get(rarity, 0))
	var grade := str(item.get("drop_grade", ""))
	if WeaponDropGrade.is_valid(grade):
		points += int(GRADE_RARITY_BONUS.get(grade, 0))
	return points


static func is_melee(item: Dictionary) -> bool:
	if str(item.get("subtype", "")) == MELEE_SUBTYPE:
		return true
	for tag in item.get("tags", []):
		if str(tag) == MELEE_TAG:
			return true
	return false


## ————————————————————————————————
## 投入解析
## ————————————————————————————————

## 解析盘面投入。
##
## `items` 是盘面上每一格持有的物品字典（可带 `count`）。返回：
##   recipe        命中的配方（未命中为 RECIPE_NONE）
##   reason        未命中 / 拒绝时的稳定原因码
##   weapons       投入的武器（保持盘面顺序）—— 唯一可当**蓝本**的东西
##   materials     投入的全部材料（含弹药模块、配件、消耗品、装备…）
##   modules       材料里的弹药模块子集（只用于弹种抽取）
##   melt          材料熔炼值之和 —— R1 燃料门槛、R3 产出数量
##   rarity_points 材料稀有度分之和 —— **品质概率的唯一驱动项**
##   output_count  本次会产出几把
##   blueprint     R1 的蓝本武器字典（R2 为**空** —— 蓝本到掷骰时才随机定，见 `pick_blueprint`）
##   blueprint_candidates R2 的蓝本候选（= 投入的全部武器）
##   value         投入估值（`coin_cost` 的计费基数）
##
## **R2 不在这里定蓝本**：业主 2026-10-18 要求「两把随机」。
## 解析阶段还不知道随机结果，把它写死成第一把会让 UI 显示一个假结论。
static func classify(items: Array) -> Dictionary:
	var weapons: Array = []
	var materials: Array = []
	var modules: Array = []
	var melt := 0
	var rarity_points := 0
	var value := 0
	for value_variant in items:
		if not value_variant is Dictionary:
			continue
		var item := value_variant as Dictionary
		if item.is_empty():
			continue
		value += item_value(item)
		if is_blueprint_weapon(item):
			weapons.append(item)
			continue
		materials.append(item)
		melt += melt_value_of(item)
		rarity_points += rarity_points_of(item)
		if is_bullet_module(item):
			modules.append(item)

	# 多把武器时，除蓝本之外的那几把会被销毁 —— 它们的熔炼值与稀有度必须计入。
	# 必须在**收完所有武器之后**统一算：边收边算会让"第一把当蓝本不计数"
	# 的假设漏进 n=2 的情况，导致只累计到第二把。
	if weapons.size() >= 2:
		for weapon in weapons:
			melt += melt_value_of(weapon)
			rarity_points += rarity_points_of(weapon)

	var result := {
		"recipe": RECIPE_NONE,
		"reason": "",
		"weapons": weapons,
		"materials": materials,
		"modules": modules,
		"melt": melt,
		"rarity_points": rarity_points,
		"value": value,
		"output_count": 0,
		"blueprint": {},
		"blueprint_candidates": [],
		"blueprint_index": -1,
		"coin_cost": 0,
	}
	if weapons.is_empty() and materials.is_empty():
		result["reason"] = REJECT_EMPTY_TRAY
		return result

	if weapons.size() >= 2:
		result["recipe"] = RECIPE_FUSION
		result["output_count"] = 1
		result["blueprint_candidates"] = weapons.duplicate()
		result["coin_cost"] = coin_cost_for(RECIPE_FUSION, value)
		return result

	if weapons.size() == 1:
		if materials.is_empty():
			result["reason"] = REJECT_SINGLE_WEAPON_WITHOUT_FUEL
			return result
		# 燃料门槛按熔炼值算，不按"件数"：一件 legendary 抵得上一堆白装。
		if melt < FUEL_THRESHOLD:
			result["reason"] = REJECT_INSUFFICIENT_FUEL
			return result
		result["recipe"] = RECIPE_REMELT
		result["output_count"] = 1
		result["blueprint"] = weapons[0]
		result["blueprint_index"] = 0
		result["coin_cost"] = coin_cost_for(RECIPE_REMELT, value)
		return result

	# 0 武器：纯材料合成。数量看熔炼值，品质看稀有度分。
	if melt < MELT_THRESHOLD:
		result["reason"] = REJECT_INSUFFICIENT_MELT
		return result
	result["recipe"] = RECIPE_SYNTHESIS
	result["output_count"] = clampi(melt / MELT_THRESHOLD, 1, MAX_MELT_OUTPUT)
	result["coin_cost"] = coin_cost_for(RECIPE_SYNTHESIS, value)
	return result


## 单件物品的估值（含堆叠数量）。取物品表的 `price`，缺失按 0 计。
##
## 不用 `base_sell_price`：卖价只是估值的一半，用它当基数会让熔炼费低到
## "贵枪随便熔"，失去按价值分档的意义。
static func item_value(item: Dictionary) -> int:
	if item.is_empty():
		return 0
	var price := maxi(0, int(item.get("price", 0)))
	if price <= 0:
		# 调用方传进来的往往是实例字典，`price` 可能已被剥离；回查物品表。
		var definition := ItemRegistry.get_instance().get_item(str(item.get("id", "")))
		price = maxi(0, int(definition.get("price", 0)))
	return price * maxi(1, int(item.get("count", 1)))


## 金币费用：`max(min_cost, ceil(投入估值 × rate))`。参数见 `COIN_RATE` / `COIN_MIN`。
static func coin_cost_for(recipe: String, value: int) -> int:
	if not COIN_RATE.has(recipe):
		return 0
	var minimum := int(COIN_MIN.get(recipe, 0))
	var fee := int(ceil(float(maxi(0, value)) * float(COIN_RATE[recipe])))
	return maxi(minimum, fee)


## 从多把武器里**随机**挑蓝本（业主要求：两把随机）。
##
## 与旧版「取伤害最高」的区别：旧规则可解释但不符合"更随机"的设计意图 ——
## 玩家投两把枪，就该真的不知道出来的是哪把。随机结果由调用方的 rng 决定，
## 因此同 seed 可复现，验收能钉住分布。
static func pick_blueprint(weapons: Array, rng: RandomNumberGenerator) -> Dictionary:
	if weapons.is_empty():
		return {"index": -1, "item": {}}
	if rng == null:
		return {"index": 0, "item": weapons[0]}
	var index := rng.randi_range(0, weapons.size() - 1)
	return {"index": index, "item": weapons[index]}


static func _weapon_damage(item: Dictionary) -> float:
	var instance := WeaponInstance.from_item(item)
	if instance == null:
		return 0.0
	var tree := instance.build_runtime_tree()
	if tree == null:
		return 0.0
	var stats := tree.get_computed_stats()
	var damage := float(stats.get("damage", 0))
	tree.free()
	return damage


## ————————————————————————————————
## 品质概率
## ————————————————————————————————

## 归一化后的品质概率。**稀有度分 R 是唯一驱动项**（2026-10-18 业主裁决）。
##
## 公式（三条配方通用）：
##   n = 投入武器数（蓝本数），**R = 材料稀有度分之和**
##   m_blue   = 0.70 × 0.55^(n-1)      n=0 时幂为 0，即停在基础池
##   m_purple = 0.25 × 1.35^(n-1)
##   m_gold   = 0.05 × 1.75^(n-1)
##   w_blue   = max(0.05, m_blue - 0.015×R)
##   w_purple = m_purple + 0.011×R
##   w_gold   = m_gold   + 0.007×R
##
## **R3 也吃 R**（旧稿曾规定"R3 不搏金"）。那条在材料只有弹药模块时成立，
## 现在所有物品都能当材料 —— 若 R3 不吃稀有度，"投 6 个白装"和"投 6 件传说"
## 会得到同样的概率，玩家没有任何理由投好东西。改为：R3 的**数量**看熔炼值、
## **品质**看稀有度分，两条轴各管一件事。
##
## common 的稀有度分恒为 0（见 `RARITY_POINTS`），所以"堆白装"这条零成本路径
## 依然被堵住 —— 白装能凑数量，但拉不动品质。
static func grade_probabilities(weapon_count: int, rarity_points: int) -> Dictionary:
	var base := WeaponDropGrade.ROLL_WEIGHTS
	var n := clampi(weapon_count, 0, MAX_BLUEPRINT_WEAPONS)
	# n=0 时幂取 0，乘法系数退化为 1.0 —— 三条配方共用一条式子，不用分叉。
	var step_exp := maxi(0, n - 1)
	var points := float(maxi(0, rarity_points))
	var weights: Dictionary = {}
	var total := 0.0
	for grade in WeaponDropGrade.ROLL_ORDER:
		var step := float(WEAPON_WEIGHT_STEP[grade])
		var tilt := float(RARITY_WEIGHT_TILT[grade])
		var raw := float(base[grade]) * pow(step, step_exp) + tilt * points
		if grade == WeaponDropGrade.GRADE_BLUE:
			raw = maxf(BLUE_WEIGHT_FLOOR, raw)
		weights[grade] = raw
		total += raw
	if total <= 0.0:
		# 理论不可达（蓝有地板、紫金恒正），兜底返回基础池而不是空字典。
		for grade in WeaponDropGrade.ROLL_ORDER:
			weights[grade] = float(base[grade])
		total = 0.0
		for grade in WeaponDropGrade.ROLL_ORDER:
			total += float(weights[grade])
	for grade in weights.keys():
		weights[grade] = float(weights[grade]) / total
	return weights


## 按 0..1 抽样值掷品质。传 `rng.randf()`。
##
## 吃抽样值而不是自己掷：调用方可以传确定性 rng，验收才能复现。
static func roll_grade_value(value: float, weapon_count: int, rarity_points: int) -> String:
	var probabilities := grade_probabilities(weapon_count, rarity_points)
	var target := clampf(value, 0.0, 0.999999)
	var cumulative := 0.0
	for grade in WeaponDropGrade.ROLL_ORDER:
		cumulative += float(probabilities.get(grade, 0.0))
		if target < cumulative:
			return grade
	return WeaponDropGrade.ROLL_ORDER[WeaponDropGrade.ROLL_ORDER.size() - 1]


static func roll_grade(rng: RandomNumberGenerator, weapon_count: int, rarity_points: int) -> String:
	return roll_grade_value(rng.randf(), weapon_count, rarity_points)


## ————————————————————————————————
## 掷弹种 / 掷配件
## ————————————————————————————————

## 从候选里**按数量加权**抽一个弹种。
##
## 候选来源是两层叠加（业主 2026-10-18「从枪的属性和子弹模块中随机」）：
##   ① 投入的弹药模块 —— 按堆叠数量计票；
##   ② 投入武器**自带的绑定弹种** —— 每把枪各计 1 票。
##
## ② 是 R2 的关键：两把枪即使一个模块都不投，产出弹种也从这两把枪的弹道里随机挑，
## 而不是永远掉回标准弹。投得越多、票数越集中，结果越可预测 —— 这正是"抽卡"的分量。
##
## 候选全空时才回落 `WeaponBulletDrop.roll`（野生池），保证产出永远有弹可用。
static func roll_bullet(
	modules: Array, rng: RandomNumberGenerator, bound_bullets: Array = []
) -> String:
	var candidates: Array[String] = []
	var weights: Array[int] = []
	var total := 0
	for value in modules:
		if not value is Dictionary:
			continue
		var item := value as Dictionary
		var bullet_id := str(item.get("id", ""))
		if not WeaponBulletDrop.is_valid(bullet_id):
			continue
		var count := maxi(1, int(item.get("count", 1)))
		candidates.append(bullet_id)
		weights.append(count)
		total += count
	for value in bound_bullets:
		var bullet_id := str(value)
		if not WeaponBulletDrop.is_valid(bullet_id):
			continue
		candidates.append(bullet_id)
		weights.append(1)
		total += 1
	if total <= 0:
		return WeaponBulletDrop.roll(rng.randf())
	var target := rng.randf() * float(total)
	var cumulative := 0
	for index in range(candidates.size()):
		cumulative += weights[index]
		if target < float(cumulative):
			return candidates[index]
	return candidates[candidates.size() - 1]


## 取一把枪**自带的绑定弹种**。取不到返回空串（近战、无弹种、字段被剥离都算）。
##
## 快路径读字段（顶层 → `weapon_instance` 嵌套层）：盘面上的枪通常两者都有。
## 慢路径才建实例读 `presentation_snapshot().bullet_module` —— 那条路会搭一次装配树，
## 只在字段全缺时兜底，避免每次刷新盘面都为两把枪各建一棵树。
static func weapon_bound_bullet(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var bullet_id := str(item.get("bullet_module_id", ""))
	if bullet_id.is_empty():
		var nested: Variant = item.get("weapon_instance", {})
		if nested is Dictionary:
			bullet_id = str((nested as Dictionary).get("bullet_module_id", ""))
	if WeaponBulletDrop.is_valid(bullet_id):
		return bullet_id
	var instance := WeaponInstance.from_item(item)
	if instance == null:
		return ""
	var snapshot := instance.get_presentation_snapshot()
	var module: Variant = snapshot.get("bullet_module", {})
	if not module is Dictionary:
		return ""
	var resolved := str((module as Dictionary).get("item_id", ""))
	return resolved if WeaponBulletDrop.is_valid(resolved) else ""


## 收集一组武器的绑定弹种（过滤空值与重复）。
static func collect_bound_bullets(weapons: Array) -> Array[String]:
	var out: Array[String] = []
	for value in weapons:
		if not value is Dictionary:
			continue
		var bullet_id := weapon_bound_bullet(value as Dictionary)
		if bullet_id.is_empty() or bullet_id in out:
			continue
		out.append(bullet_id)
	return out


## R2 的随机附带配件：随机挑 `count` 个互不占同一槽的配件。
##
## 只从「该枪身实际支持的槽位」与「工坊已解锁配件池」的交集里挑 ——
## 否则会给手枪装上枪托，`mount` 校验失败后产出就少一件，玩家看不出原因。
static func roll_attachments(
	gun_assembly_id: String, blueprint_tier: int, count: int, rng: RandomNumberGenerator
) -> Array[String]:
	var out: Array[String] = []
	if count <= 0 or gun_assembly_id.is_empty():
		return out
	var gun := BlueprintRegistry.create_assembly_node(gun_assembly_id)
	if gun == null:
		return out

	# 兼容性判据走枪身节点自己被 `apply_runtime_contract` 补上的 `supports_<slot>` 标签，
	# 不读注册表常量 —— 那是 autoload 上的 const，跨模块读会让脚本编译期依赖单例。
	var candidates: Array[String] = []
	var slot_of: Dictionary = {}
	for entry in BlueprintRegistry.get_available_attachments(blueprint_tier):
		var attachment_id := str(entry.get("item_id", ""))
		var slot_type := _attachment_slot_type(attachment_id)
		if slot_type < 0 or not gun.supports_attachment_slot(slot_type):
			continue
		candidates.append(attachment_id)
		slot_of[attachment_id] = slot_type
	gun.free()

	# Fisher-Yates（自实现，避免依赖 Array.shuffle 的全局 rng）
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temp
	var used_slots: Dictionary = {}
	for attachment_id in candidates:
		if out.size() >= count:
			break
		var slot_type := int(slot_of[attachment_id])
		if used_slots.has(slot_type):
			continue
		used_slots[slot_type] = true
		out.append(attachment_id)
	return out


static func _attachment_slot_type(attachment_id: String) -> int:
	if _attachment_slot_cache.has(attachment_id):
		return int(_attachment_slot_cache[attachment_id])
	var node := BlueprintRegistry.create_assembly_node(attachment_id)
	var slot_type := -1
	if node != null:
		slot_type = node.get_attachment_slot_type()
		node.free()
	_attachment_slot_cache[attachment_id] = slot_type
	return slot_type


## ————————————————————————————————
## 产出构建
## ————————————————————————————————

## 由枪身蓝图 ID 反查背包用的武器物品 ID（`bp_rifle` → `weapon_rifle`）。
##
## 走 `ItemRegistry.assembly_id` 反查，不维护第二张映射表 ——
## 两张表迟早会漂移，而漂移的表现是"炼出来的枪在背包里变成另一个物品"。
static func weapon_item_id_for_assembly(assembly_id: String) -> String:
	if assembly_id.is_empty():
		return ""
	for item in ItemRegistry.get_instance().get_items_by_type("weapon"):
		if str(item.get("assembly_id", "")) == assembly_id:
			return str(item.get("id", ""))
	return ""


## 构建一件产出物品字典（纯数据，不写背包、不入场景）。
##
## `context`：
##   assembly_id  枪身蓝图 ID（`bp_rifle`）
##   grade        品质（blue/purple/gold）
##   bullet_id    弹种 ID（近战传空）
##   attachments  附带配件 ID 数组（可空）
## 返回 `WeaponInstance.to_item_dictionary()` 的结果；无法构建时返回空字典。
static func build_output(context: Dictionary) -> Dictionary:
	var assembly_id := str(context.get("assembly_id", ""))
	var content_id := weapon_item_id_for_assembly(assembly_id)
	if content_id.is_empty():
		push_warning("[WeaponForge] 没有物品对应枪身蓝图 %s" % assembly_id)
		return {}
	var definition := ItemRegistry.get_instance().get_item(content_id)
	if definition.is_empty():
		return {}
	var item := definition.duplicate(true)
	# 品质必须在建实例之前写：`apply_to_item` 负责命运槽加成，且带幂等守卫。
	item = WeaponDropGrade.apply_to_item(item, str(context.get("grade", WeaponDropGrade.GRADE_BLUE)))

	var root := BlueprintRegistry.create_assembly_node(assembly_id)
	if root == null:
		return {}
	var melee := is_melee(item) or MELEE_TAG in root.tags
	var tree := WeaponAssemblyTree.new(root)

	var bullet_id := str(context.get("bullet_id", ""))
	if not melee and not bullet_id.is_empty():
		var bullet := BlueprintRegistry.create_assembly_node(bullet_id)
		if bullet != null:
			if not tree.mount(root, AssemblyNode.SlotType.BULLET, bullet):
				bullet.free()
		item["bullet_module_id"] = bullet_id
	item["bullet_module_locked"] = false

	for value in context.get("attachments", []) as Array:
		var attachment_id := str(value)
		if attachment_id.is_empty():
			continue
		var attachment := BlueprintRegistry.create_assembly_node(attachment_id)
		if attachment == null:
			continue
		var slot_type := attachment.get_attachment_slot_type()
		if slot_type < 0 or not tree.mount(root, slot_type, attachment):
			attachment.free()

	var instance := WeaponInstance.from_item(item, tree)
	tree.free()
	if instance == null:
		return {}
	return instance.to_item_dictionary()


## 一行规格摘要，供验收与工具打印判据。
static func summary_line() -> String:
	var base := WeaponDropGrade.ROLL_WEIGHTS
	return "WEAPON_FORGE tray=%dx%d melt_threshold=%d fuel_threshold=%d max_weapons=%d max_output=%d | base blue=%.2f purple=%.2f gold=%.2f | steps blue=%.2f purple=%.2f gold=%.2f | rarity tilt blue=%.3f purple=%.3f gold=%.3f | rarity common=%d uncommon=%d rare=%d epic=%d legendary=%d" % [
		TRAY_COLUMNS, TRAY_ROWS, MELT_THRESHOLD, FUEL_THRESHOLD,
		MAX_BLUEPRINT_WEAPONS, MAX_MELT_OUTPUT,
		float(base[WeaponDropGrade.GRADE_BLUE]),
		float(base[WeaponDropGrade.GRADE_PURPLE]),
		float(base[WeaponDropGrade.GRADE_GOLD]),
		float(WEAPON_WEIGHT_STEP[WeaponDropGrade.GRADE_BLUE]),
		float(WEAPON_WEIGHT_STEP[WeaponDropGrade.GRADE_PURPLE]),
		float(WEAPON_WEIGHT_STEP[WeaponDropGrade.GRADE_GOLD]),
		float(RARITY_WEIGHT_TILT[WeaponDropGrade.GRADE_BLUE]),
		float(RARITY_WEIGHT_TILT[WeaponDropGrade.GRADE_PURPLE]),
		float(RARITY_WEIGHT_TILT[WeaponDropGrade.GRADE_GOLD]),
		int(RARITY_POINTS["common"]),
		int(RARITY_POINTS["uncommon"]),
		int(RARITY_POINTS["rare"]),
		int(RARITY_POINTS["epic"]),
		int(RARITY_POINTS["legendary"]),
	]
