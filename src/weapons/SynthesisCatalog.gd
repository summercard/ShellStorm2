class_name SynthesisCatalog
extends RefCounted
## 合成目录（定向合成，R0）—— 纯规则层。
##
## 设计真源：[07.3 玩法系统｜合成目录与兴趣曲线](../../docs/v0.1/07.3_玩法系统_合成目录与兴趣曲线.md)。
##
## 它解决的问题是「**方向**」不是「随机」：
## `WeaponForge` 的三条配方（R1 重铸 / R2 融合 / R3 盲盒）都只能掷骰出枪身，
## 玩家"就差一把霰弹枪"时没有任何可控路径。本表把道具（钥匙）与武器（产物）
## 逐条连起来，投够钥匙就产出指定的那把枪。
##
## ## 边界
## - 本文件只管**配方表 + 命中判定 + 优先级**，不碰场景、不碰 UI、不写背包。
## - 金币费用是**固定价**（不是按投入估值算）：合成配方的投入物是固定的，
##   按估值算会让"同样两条碎片，因为顺手多丢了几件垃圾而涨价"。
## - 材料消耗由 `WorkbenchPanel` 的事务统一处理（清空盘面），这里不负责扣物。

## 曲线段常量。段号 = 工坊蓝图 Tier，验收钉住两者相等。
const TIER_0 := 0
const TIER_1 := 1
const TIER_2 := 2
const TIER_3 := 3

## 合成配方的固定金币价与品质加成是两条独立参数：
## - `coin_cost` 锁在产物商价的 36% 左右（让"比直接买便宜六成"成为可学习的认知）
## - `quality_bonus` 用 0/2/4/7，刻意与 `RARITY_POINTS` 同量级，
##   好解释成「合成这把枪本身相当于白送 1 件 rare / legendary 材料」
##
## `preload_bullet` 非空时产物固定装该弹种（但 `bullet_module_locked = false`，可拆换）。
## `preload_attachments` 是产物预装的随机配件数，从该枪身实际支持的槽位里抽。
const RECIPES: Array = [
	{
		"recipe_id": "SYN-PISTOL",
		"curve_tier": TIER_0,
		"product_id": "weapon_pistol",
		"key_item_id": "bp_pistol",
		"key_count": 2,
		"fuel_min": 6,
		"coin_cost": 25,
		"quality_bonus": 0,
		"preload_bullet": "",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-SHOTGUN",
		"curve_tier": TIER_0,
		"product_id": "weapon_shotgun",
		"key_item_id": "bp_shotgun",
		"key_count": 2,
		"fuel_min": 6,
		"coin_cost": 40,
		"quality_bonus": 0,
		"preload_bullet": "",
		"preload_attachments": 0,
	},
	# 近战链第一级：钥匙是**武器本身**（近战没有碎片物品），所以 key_count 恒为 1。
	{
		"recipe_id": "SYN-GREATBLADE",
		"curve_tier": TIER_0,
		"product_id": "weapon_greatblade",
		"key_item_id": "weapon_baseball_bat",
		"key_count": 1,
		"fuel_min": 6,
		"coin_cost": 60,
		"quality_bonus": 0,
		"preload_bullet": "",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-RIFLE",
		"curve_tier": TIER_1,
		"product_id": "weapon_rifle",
		"key_item_id": "bp_rifle",
		"key_count": 3,
		"fuel_min": 9,
		"coin_cost": 55,
		"quality_bonus": 2,
		"preload_bullet": "mod_bullet_piercing",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-MG",
		"curve_tier": TIER_1,
		"product_id": "weapon_machinegun",
		"key_item_id": "bp_machinegun",
		"key_count": 3,
		"fuel_min": 9,
		"coin_cost": 65,
		"quality_bonus": 2,
		"preload_bullet": "mod_bullet_standard",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-WARAXE",
		"curve_tier": TIER_1,
		"product_id": "weapon_waraxe",
		"key_item_id": "weapon_greatblade",
		"key_count": 1,
		"fuel_min": 10,
		"coin_cost": 90,
		"quality_bonus": 2,
		"preload_bullet": "",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-SNIPER",
		"curve_tier": TIER_2,
		"product_id": "weapon_sniper",
		"key_item_id": "bp_sniper",
		"key_count": 4,
		"fuel_min": 12,
		"coin_cost": 80,
		"quality_bonus": 4,
		"preload_bullet": "mod_bullet_piercing",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-LAUNCHER",
		"curve_tier": TIER_2,
		"product_id": "weapon_launcher",
		"key_item_id": "bp_launcher",
		"key_count": 4,
		"fuel_min": 12,
		"coin_cost": 90,
		"quality_bonus": 4,
		"preload_bullet": "mod_bullet_explosive",
		"preload_attachments": 0,
	},
	{
		"recipe_id": "SYN-CHARGE",
		"curve_tier": TIER_3,
		"product_id": "weapon_charge",
		"key_item_id": "bp_charge",
		"key_count": 5,
		"fuel_min": 15,
		"coin_cost": 125,
		"quality_bonus": 7,
		"preload_bullet": "",
		"preload_attachments": 1,
	},
]

## 曲线段元数据。`density` = 本段每多少次给一条新配方，是曲线唯一可验收的骨架。
## 验收钉住 density 严格递增（1/2/3/5）—— 间隔恒定会让玩家在第 5 次就摸清套路。
const CURVE_TIERS: Array = [
	{
		"tier": TIER_0,
		"code": "L0",
		"name": "Hook",
		"density": 1,
		"emotion": 72,
		"first_experience": "材料变成了枪",
	},
	{
		"tier": TIER_1,
		"code": "L1",
		"name": "Promise",
		"density": 2,
		"emotion": 75,
		"first_experience": "能指定弹种",
	},
	{
		"tier": TIER_2,
		"code": "L2",
		"name": "Payoff",
		"density": 3,
		"emotion": 88,
		"first_experience": "能造出 rare 枪",
	},
	{
		"tier": TIER_3,
		"code": "L3",
		"name": "Chase",
		"density": 5,
		"emotion": 95,
		"first_experience": "能造出 epic 枪",
	},
]

## ————————————————————————————————
## 硬保底
## ————————————————————————————————
## 只作用于 `bp_charge`。它的期望获取是 8–12 局 —— 那是**平均值**，
## 而平均值不解决"运气极差"：按 `boss_floor_2 ×4` 的权重，存在连续多局颗粒无收的可能。
## 终局目标的**卡死**比"长"更伤人 —— 长是期待，卡死是绝望。
##
## 为什么不给所有配方都加：其余八条的期望都在 1–6 局内，最长的一条也够不上卡死的量级。
## 全加会把曲线变成"可计划的进度条"，随机张力就没了。
## **保底是兜住运气的下限，不是消灭运气。**
const PITY_THRESHOLD := 3
const PITY_KEYS: Array[String] = ["bp_charge"]


## 本次是否该触发保底（调用方在**结算掉落前**问）。
static func pity_should_grant(state: Dictionary) -> bool:
	return int(state.get("misses", 0)) >= PITY_THRESHOLD


## 记一次"通关了目标层但没见到保底钥匙"。
static func pity_record_miss(state: Dictionary) -> void:
	state["misses"] = int(state.get("misses", 0)) + 1


## 记一次掉落。**只有拿到保底钥匙本身才清零** ——
## 如果"随便掉点什么"也能清零，保底可以被绕开。
static func pity_record_drop(state: Dictionary, item_id: String) -> void:
	if item_id in PITY_KEYS:
		state["misses"] = 0


## 一次行动结算的完整保底判定（**纯逻辑**：不写档、不碰背包）。
##
## `state` 是存档里的 `synthesis_pity` 整块（形如 `{"bp_charge": {"misses": 2}}`），
## 本函数**就地修改**它，调用方负责把这一块随存档落盘。
## `loot_ids` 是本次带出的物品 id 列表（每件一条，堆叠算多次）。
## `boss_cleared` 是本次是否击败过首领 —— 这是"这一局算不算一次机会"的判据。
##
## 三条分支的顺序不能换：
##   1. **本局拿到了** → 清零。哪怕这局没打首领，运气好拿到了也该清零。
##   2. **没拿到且打了首领** → 达阈值就补发，否则记一次 miss。
##   3. **没拿到且没打首领** → **什么都不做**。
##
## 第 3 条是保底唯一的防刷门：如果"进图 → 直接撤离"也能记 miss，
## 玩家二十秒跑一次就能把计数刷满，保底就从"运气下限"退化成"可刷的进度条"。
##
## 返回 `{"key", "granted", "cleared", "misses", "threshold"}`。
## `granted` 非空 = 调用方**必须**把这个物品真发给玩家（数量恒为 1）。
static func resolve_settlement(
	state: Dictionary, loot_ids: Array, boss_cleared: bool
) -> Dictionary:
	if PITY_KEYS.is_empty():
		return {"key": "", "granted": "", "cleared": false, "misses": 0, "threshold": PITY_THRESHOLD}
	var key := str(PITY_KEYS[0])
	var bucket := _pity_bucket(state, key)
	var granted := ""
	var cleared := false
	if loot_ids.has(key):
		bucket["misses"] = 0
		cleared = true
	elif boss_cleared:
		if pity_should_grant(bucket):
			granted = key
			bucket["misses"] = 0
		else:
			pity_record_miss(bucket)
	state[key] = bucket
	return {
		"key": key,
		"granted": granted,
		"cleared": cleared,
		"misses": int(bucket.get("misses", 0)),
		"threshold": PITY_THRESHOLD,
	}


## 某把保底钥匙的当前 miss 计数（UI 的「保底 2/3」）。
static func pity_progress(state: Dictionary, key: String) -> int:
	var raw: Variant = state.get(key, null)
	if raw is Dictionary:
		return maxi(0, int((raw as Dictionary).get("misses", 0)))
	return 0


## 取（或建）某个钥匙的计数桶。**返回的是 state 内的同一个字典**，
## 改它就是改 state，不需要回写。
static func _pity_bucket(state: Dictionary, key: String) -> Dictionary:
	var raw: Variant = state.get(key, null)
	if raw is Dictionary:
		return raw as Dictionary
	var fresh: Dictionary = {"misses": 0}
	state[key] = fresh
	return fresh


## 钥匙只允许这两类（验收钉住）。判据是「**没有其他用途**」：
## 药水要喝、电池要装、弹种模块与配件要装枪 —— 拿它们当钥匙，玩家会在
## "用掉还是留着"之间纠结。蓝图碎片与近战武器没有这个冲突。
const ALLOWED_KEY_TYPES: Array[String] = ["blueprint", "weapon"]


## ————————————————————————————————
## 查询
## ————————————————————————————————

static func all_recipes() -> Array:
	return RECIPES


static func recipe_by_id(recipe_id: String) -> Dictionary:
	for recipe in RECIPES:
		if str(recipe["recipe_id"]) == recipe_id:
			return recipe
	return {}


## 某一段（= 工坊 tier）的配方列表，用于合成目录按段分组渲染。
static func recipes_of_tier(tier: int) -> Array:
	var out: Array = []
	for recipe in RECIPES:
		if int(recipe["curve_tier"]) == tier:
			out.append(recipe)
	return out


static func curve_tier_info(tier: int) -> Dictionary:
	for entry in CURVE_TIERS:
		if int(entry["tier"]) == tier:
			return entry
	return {}


## 产物物品 ID 集合（验收用：必须等于「十把非初始武器 − 棒球棍」）。
static func product_ids() -> Array[String]:
	var out: Array[String] = []
	for recipe in RECIPES:
		var product := str(recipe["product_id"])
		if not product in out:
			out.append(product)
	return out


## 钥匙物品 ID 集合。
static func key_ids() -> Array[String]:
	var out: Array[String] = []
	for recipe in RECIPES:
		var key := str(recipe["key_item_id"])
		if not key in out:
			out.append(key)
	return out


## 这把钥匙是不是「武器当钥匙」（近战链），而不是碎片。
static func is_weapon_key(key_item_id: String) -> bool:
	var definition := ItemRegistry.get_instance().get_item(key_item_id)
	return str(definition.get("type", "")) == "weapon"


## ————————————————————————————————
## 命中判定
## ————————————————————————————————

## 找到**钥匙数量已够**的配方（不看燃料是否够）。
##
## 多条命中取 `curve_tier` 最高：多投不能降级。玩家往盘里多放了一批稀有货，
## 产出必须更好；若取最低 tier，等于惩罚"多投"，玩家会学会"精确投料"，
## 而这套系统要的是"攒够了就丢进去"。
## tier 相同时按 `recipe_id` 字典序取第一个，保证确定性。
static func find_key_complete(weapons: Array, materials: Array) -> Dictionary:
	var best: Dictionary = {}
	for recipe in RECIPES:
		if not _key_satisfied(recipe, weapons, materials):
			continue
		if best.is_empty():
			best = recipe
			continue
		var tier := int(recipe["curve_tier"])
		var best_tier := int(best["curve_tier"])
		if tier > best_tier:
			best = recipe
		elif tier == best_tier and str(recipe["recipe_id"]) < str(best["recipe_id"]):
			best = recipe
	return best


## 完整命中：钥匙够 **且** 燃料够。
static func find_ready(weapons: Array, materials: Array, melt: int) -> Dictionary:
	var recipe := find_key_complete(weapons, materials)
	if recipe.is_empty():
		return {}
	if melt < int(recipe["fuel_min"]):
		return {}
	return recipe


## 「差一点」提示：钥匙没凑够、但差得不多的那条配方。
##
## 只用于**软提示**（「步枪蓝图碎片还差 2 个（1/3）· 本次将按随机合成处理」），
## 不阻止熔炼 —— 钥匙不够时盘面仍然可以走 R1/R2/R3，拒绝等于剥夺玩家
## "我就是要烧掉这批货"的自由。
##
## 只报"还差 ≤ 2 个"的：差得太多时提示没有意义，只会变成噪音。
static func nearest_key_short(weapons: Array, materials: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := 99
	for recipe in RECIPES:
		if is_weapon_key(str(recipe["key_item_id"])):
			# 武器链的"差一点"没有意义（要么正好 1 把、要么完全不是这把枪）。
			continue
		var need := int(recipe["key_count"])
		var have := count_of(materials, str(recipe["key_item_id"]))
		if have <= 0:
			continue
		var gap := need - have
		if gap <= 0 or gap > 2 or gap >= best_gap:
			continue
		best_gap = gap
		best = recipe.duplicate()
		best["key_have"] = have
		best["key_need"] = need
	return best


## 盘面里某物品的实际件数（按 `count` 累加，不是条目数）。
static func count_of(items: Array, item_id: String) -> int:
	var total := 0
	for value in items:
		if not value is Dictionary:
			continue
		var item := value as Dictionary
		if str(item.get("id", "")) != item_id:
			continue
		total += maxi(1, int(item.get("count", 1)))
	return total


## 某配方的钥匙进度（UI 的「有 / 需」）。
static func key_progress(recipe: Dictionary, weapons: Array, materials: Array) -> Dictionary:
	var key := str(recipe["key_item_id"])
	var need := int(recipe["key_count"])
	var have := 0
	if is_weapon_key(key):
		# 武器按"把"数，不按 count（每把武器都是独立实例，count 恒为 1）。
		for value in weapons:
			if value is Dictionary and str((value as Dictionary).get("id", "")) == key:
				have += 1
	else:
		have = count_of(materials, key)
	return {"have": have, "need": need, "complete": have >= need}


## 产物对应的枪身蓝图 ID（`weapon_rifle` → `bp_rifle`）。
##
## 走 `ItemRegistry.assembly_id` 反查，不维护第二张映射表 ——
## 两张表迟早漂移，而漂移的表现是"合成出来的枪在背包里变成另一个物品"。
static func assembly_id_for_product(product_id: String) -> String:
	var definition := ItemRegistry.get_instance().get_item(product_id)
	return str(definition.get("assembly_id", ""))


## 一条配方的完整描述（给 UI 与验收打印用）。
static func describe(recipe: Dictionary) -> String:
	var product := ItemRegistry.get_instance().get_item(str(recipe["product_id"]))
	return "%s | %s → %s ×%d | fuel≥%d coin=%d bonus=%d" % [
		str(recipe["recipe_id"]),
		str(recipe["key_item_id"]),
		str(product.get("name", recipe["product_id"])),
		int(recipe["key_count"]),
		int(recipe["fuel_min"]),
		int(recipe["coin_cost"]),
		int(recipe["quality_bonus"]),
	]


## 一行规格摘要，供验收与工具打印判据。
static func summary_line() -> String:
	var tiers: Array[String] = []
	for entry in CURVE_TIERS:
		tiers.append("%s density=%d" % [str(entry["code"]), int(entry["density"])])
	return "SYNTHESIS_CATALOG recipes=%d products=%d keys=%d | %s" % [
		RECIPES.size(), product_ids().size(), key_ids().size(), " ".join(tiers),
	]


# ————————————————————————————————
# 内部
# ————————————————————————————————

## 钥匙数量是否已够。**不看燃料** —— 燃料由调用方另外判，因为"钥匙够但燃料不够"
## 要返回一个专属拒绝码（`synthesis_fuel_short`），不能静默降级成盲盒。
static func _key_satisfied(recipe: Dictionary, weapons: Array, materials: Array) -> bool:
	var key := str(recipe["key_item_id"])
	var need := int(recipe["key_count"])
	if is_weapon_key(key):
		# 武器链：盘上必须**正好**是 need 把、且全部是这把钥匙。
		# 多于 need 会有歧义（剩下那把要不要烧？），交给 R2 融合处理更清楚。
		if weapons.size() != need:
			return false
		for value in weapons:
			if not value is Dictionary:
				return false
			if str((value as Dictionary).get("id", "")) != key:
				return false
		return true
	# 材料链：盘上必须**没有武器**（有武器就该走 R1/R2，那是玩家的明确意图）。
	if not weapons.is_empty():
		return false
	return count_of(materials, key) >= need
