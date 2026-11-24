class_name SynthesisCatalog
extends RefCounted
## 合成目录（定向合成，R0）—— 纯规则层。
##
## 设计真源：[07.3 玩法系统｜合成目录与兴趣曲线](../../docs/v0.1/07.3_玩法系统_合成目录与兴趣曲线.md)。
##
## R0 仅保留两条近战武器升级；R1 重铸 / R2 融合 / R3 随机合成由 WeaponForge 持有。
## 2026-11-24：九种碎片实物退役，七条依赖碎片的配方与碎片结算保底同步退役。
##
## ## 边界
## - 本文件只管**配方表 + 命中判定 + 优先级**，不碰场景、不碰 UI、不写背包。
## - 金币费用是固定价；武器和最低燃料门槛不改变。
## - 材料消耗由 `WorkbenchPanel` 的事务统一处理（清空盘面），这里不负责扣物。

## 曲线段常量。段号 = 工坊蓝图 Tier，验收钉住两者相等。
const TIER_0 := 0
const TIER_1 := 1

## 两级近战升级的原固定金币价与品质加成不变。产物无弹药槽，不预装配件。
const RECIPES: Array = [
	# key_item_id 是配方的历史字段名；投入物是武器本体，不是房间钥匙。
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
]

## 曲线段元数据。`density` = 本段每多少次给一条新配方，是曲线唯一可验收的骨架。
## 仅显示仍有配方的 L0/L1；不为已退役的碎片配方保留空章节。
const CURVE_TIERS: Array = [
	{
		"tier": TIER_0,
		"code": "L0",
		"name": "Hook",
		"density": 1,
		"emotion": 72,
		"first_experience": "棒球棍升级为工业断刃",
	},
	{
		"tier": TIER_1,
		"code": "L1",
		"name": "Promise",
		"density": 2,
		"emotion": 75,
		"first_experience": "工业断刃升级为攻城裂甲斧",
	},
]

## R0 的必要投入只能是现存武器，普通道具只计燃料。
const ALLOWED_KEY_TYPES: Array[String] = ["weapon"]


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


## 当前 R0 产物物品 ID 集合。
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


## 配方的必要投入是否为真实武器。
static func is_weapon_key(key_item_id: String) -> bool:
	var definition := ItemRegistry.get_instance().get_item(key_item_id)
	return str(definition.get("type", "")) == "weapon"


## ————————————————————————————————
## 命中判定
## ————————————————————————————————

## 找到必要武器已投入的配方，不计算燃料；多条命中时稳定取较高段。
static func find_key_complete(weapons: Array) -> Dictionary:
	var best: Dictionary = {}
	for recipe in RECIPES:
		if not _key_satisfied(recipe, weapons):
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


## 完整命中：武器与燃料同时满足。
static func find_ready(weapons: Array, melt: int) -> Dictionary:
	var recipe := find_key_complete(weapons)
	if recipe.is_empty():
		return {}
	if melt < int(recipe["fuel_min"]):
		return {}
	return recipe


## 某配方的武器投入进度（按实例数，不按堆叠计数）。
static func key_progress(recipe: Dictionary, weapons: Array) -> Dictionary:
	var key := str(recipe["key_item_id"])
	var need := int(recipe["key_count"])
	var have := 0
	for value in weapons:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == key:
			have += 1
	return {"have": have, "need": need, "complete": _key_satisfied(recipe, weapons)}


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

## 只认恰好需要的武器；额外投入第二把武器交给 R2 融合。
static func _key_satisfied(recipe: Dictionary, weapons: Array) -> bool:
	var key := str(recipe["key_item_id"])
	if not is_weapon_key(key) or weapons.size() != int(recipe["key_count"]):
		return false
	for value in weapons:
		if not value is Dictionary or str(value.get("id", "")) != key:
			return false
	return true
