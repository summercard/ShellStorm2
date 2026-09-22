class_name RewardPoolRegistry
extends RefCounted
## 掉落池登记处 — REWARD-SERVICE 的「池是否存在」唯一权威。
##
## 分工（不要混淆）：
##   · 池里**有哪些物品** = `ItemRegistry` 的 `floor_loot_weights` 键（物品表是物品的权威）。
##   · 池**是否存在、给谁用、怎么掷骰** = 本文件。
## 两者交叉校验：物品表出现的每个池键必须在此登记；登记的 active 池必须至少有一个成员（死池即红）。
##
## 只读依赖：`ItemRegistry`。不得 import 任何 `world3d`，不得读写场景节点。
## 设计依据：`docs/v0.1/04_技术施工_战斗与局内成长.md` §22.5。

const STATUS_ACTIVE := "active"
const STATUS_DEPRECATED := "deprecated"

const ROLL_WEIGHTED := "weighted"
const ROLL_INDEPENDENT := "independent"
const ROLL_ALL := "all"
const ROLL_MODES := [ROLL_WEIGHTED, ROLL_INDEPENDENT, ROLL_ALL]

const USAGE_MONSTER := "monster"
const USAGE_SEARCH := "search"
const USAGE_REWARD := "reward"
const USAGE_BOSS := "boss"
const USAGE_ELITE := "elite"

const TIER_SHALLOW := "shallow"
const TIER_MEDIUM := "medium"
const TIER_DEEP := "deep"
const TIER_ABYSS := "abyss"
const TIER_ANY := "any"

## 未登记的独立池权重上限默认值：与 04 §21 单件规则一致，显式提高才生效。
const DEFAULT_MAX_DROPS := 1

## 掷骰字段冲突码（04 §22.8）。**唯一口径**：`RewardSpec` / `RewardService` 必须引用这里的常量，
## 不得在别处重写字符串字面量 —— 2026-09-22 曾因两边各写一份、改一侧忘一侧导致校验静默失效。
const CONFLICT_NONE := ""
const CONFLICT_MIXED_ROLL_FIELDS := "MIXED_ROLL_FIELDS"
const CONFLICT_INVALID_CHANCE := "INVALID_CHANCE"

## 池登记表。键 = 池ID（稳定键，小写蛇形，发布后不因中文名改变）。
## 字段：name 中文名 / usage 用途 / tier 适用层级 / roll Roll 模式 /
##       cap 抽次上限（weighted=draws，independent/all=max_drops）/
##       status 状态 / migration_target 弃用迁移目标 / note 备注。
##
## 全部 21 个键的现状分类（2026-09-22 实测）：
##   · 有消费点 14 个：loot_common、loot_floor_1_2/3_4/5、loot_abyss、
##     elite_floor_1/2、boss_floor_1/2、scavenge_floor_1..5
##   · 死池 7 个：combat_floor_1..5（23/23/19/13/11 件物品声明，零消费点）、
##     spawn_starter（16 件）、blueprint_attachment_unlock（1 件）
##
## 可达性口径（2026-09-22 实测）：Dungeon3D 里 `floor = maxi(1, visual_theme.difficulty_rank)`，
## 而 `difficulty_rank` **在所有场景/资源里都没被赋值** ⇒ 默认 1。因此：
##   · 默认难度下 `boss_floor_%d` 只取到 boss_floor_1，`scavenge_floor_%d` 只取到 scavenge_floor_1；
##   · `loot_floor_1_2/3_4/5`、`loot_abyss` 由 `_get_loot_table(floor_level)` 决定，均可达；
##   · 一旦有人把 difficulty_rank 提到 3+，`boss_floor_%d` 会拼出**未登记池名** ⇒
##     RewardService 会拒绝并报 `UNKNOWN_POOL`（旧路径则是静默返回空表）。
##     这是登记表要暴露的问题，不是本次引入的；修法（加登记行 vs 钳位）属数据裁决。
const POOLS := {
	"loot_common": {
		"name": "通用掉落池",
		"usage": USAGE_MONSTER, "tier": TIER_ANY,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "怪物无楼层归口时的兜底池；LootModule.generate_enemy_loot 的默认值",
	},
	"loot_floor_1_2": {
		"name": "浅层掉落池（1-2层）",
		"usage": USAGE_MONSTER, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector._get_loot_table(SHALLOW)",
	},
	"loot_floor_3_4": {
		"name": "中层掉落池（3-4层）",
		"usage": USAGE_MONSTER, "tier": TIER_MEDIUM,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector._get_loot_table(MEDIUM)",
	},
	"loot_floor_5": {
		"name": "深层掉落池（5层）",
		"usage": USAGE_MONSTER, "tier": TIER_DEEP,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector._get_loot_table(DEEP)",
	},
	"loot_abyss": {
		"name": "深渊掉落池",
		"usage": USAGE_MONSTER, "tier": TIER_ABYSS,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector._get_loot_table(ABYSS)；成员最多（32 件）",
	},
	"elite_floor_1": {
		"name": "精英池·浅层",
		"usage": USAGE_ELITE, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector 精英分支：floor<=2 取此池",
	},
	"elite_floor_2": {
		"name": "精英池·中层",
		"usage": USAGE_ELITE, "tier": TIER_MEDIUM,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector 精英分支：floor>2 取此池",
	},
	"boss_floor_1": {
		"name": "首领池·第1档",
		"usage": USAGE_BOSS, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "MonsterInjector._generate_boss：loot_table = boss_floor_%d % floor",
	},
	"boss_floor_2": {
		"name": "首领池·第2档",
		"usage": USAGE_BOSS, "tier": TIER_MEDIUM,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "同上；floor>=3 时 boss_floor_%d 会拼出未登记池名，见 report() 的 latent 段",
	},
	"scavenge_floor_1": {
		"name": "搜索池·第1档",
		"usage": USAGE_SEARCH, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "LootModule.generate_container_loot：scavenge_floor_%d % min(5, floor)",
	},
	"scavenge_floor_2": {
		"name": "搜索池·第2档",
		"usage": USAGE_SEARCH, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "同上",
	},
	"scavenge_floor_3": {
		"name": "搜索池·第3档",
		"usage": USAGE_SEARCH, "tier": TIER_MEDIUM,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "同上",
	},
	"scavenge_floor_4": {
		"name": "搜索池·第4档",
		"usage": USAGE_SEARCH, "tier": TIER_DEEP,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "同上",
	},
	"scavenge_floor_5": {
		"name": "搜索池·第5档",
		"usage": USAGE_SEARCH, "tier": TIER_ABYSS,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_ACTIVE, "migration_target": "",
		"note": "同上；floor>=5 全部归到这一档",
	},
	"combat_floor_1": {
		"decision_pending": true,
		"name": "[死池]战斗池·第1档",
		"usage": USAGE_MONSTER, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "loot_floor_1_2",
		"note": "23 件物品声明权重，全仓零消费点。待裁决：接线或从物品表删除（04 §22.5）",
	},
	"combat_floor_2": {
		"decision_pending": true,
		"name": "[死池]战斗池·第2档",
		"usage": USAGE_MONSTER, "tier": TIER_SHALLOW,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "loot_floor_1_2",
		"note": "23 件物品声明权重，全仓零消费点。待裁决",
	},
	"combat_floor_3": {
		"decision_pending": true,
		"name": "[死池]战斗池·第3档",
		"usage": USAGE_MONSTER, "tier": TIER_MEDIUM,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "loot_floor_3_4",
		"note": "19 件物品声明权重，全仓零消费点。待裁决",
	},
	"combat_floor_4": {
		"decision_pending": true,
		"name": "[死池]战斗池·第4档",
		"usage": USAGE_MONSTER, "tier": TIER_DEEP,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "loot_floor_3_4",
		"note": "13 件物品声明权重，全仓零消费点。待裁决",
	},
	"combat_floor_5": {
		"decision_pending": true,
		"name": "[死池]战斗池·第5档",
		"usage": USAGE_MONSTER, "tier": TIER_DEEP,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "loot_floor_5",
		"note": "11 件物品声明权重，全仓零消费点。待裁决",
	},
	"spawn_starter": {
		"decision_pending": true,
		"name": "[死池]开局保底池",
		"usage": USAGE_REWARD, "tier": TIER_ANY,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "建议:接线到开局保底发放，或从物品表删除",
		"note": "16 件物品声明权重，全仓零消费点。无消费点 = 开局保底走的是 _grant_guaranteed_loadout_ammo 硬编码，待接线",
	},
	"blueprint_attachment_unlock": {
		"decision_pending": true,
		"name": "[死池]配件蓝图解锁池",
		"usage": USAGE_REWARD, "tier": TIER_ANY,
		"roll": ROLL_WEIGHTED, "cap": 1,
		"status": STATUS_DEPRECATED, "migration_target": "建议:接工坊配件解锁链，或从物品表删除",
		"note": "1 件物品声明权重，全仓零消费点。待裁决：接工坊解锁链或从物品表删除",
	},
}


# ---------------------------------------------------------------------------
# 数据驱动覆盖层
# ---------------------------------------------------------------------------

## 池定义的运行时覆盖层。缺省为空 ⇒ 不影响正式运行。
## 用途：① 掉落池表（xlsx）装载时把登记行装进来；② 测试替身注入临时池。
static var _overlay: Dictionary = {}


## 注入/覆盖一个池定义（字段同 POOLS 行；可另带成员级覆盖）：
##   `member_chances: {item_id: p}`  independent/all 池的逐件概率
##   `member_weights: {item_id: w}`  weighted 池的逐件权重（按池视角覆盖物品表）
## 两者都只对**已存在的成员**生效 —— 成员资格仍由物品表的 `floor_loot_weights` 键决定，
## 覆盖层不能凭空造出池成员。
static func install_overlay(pool_id: String, info: Dictionary) -> void:
	if pool_id.is_empty():
		return
	_overlay[pool_id] = info.duplicate(true)


static func clear_overlays() -> void:
	_overlay.clear()


static func overlay_ids() -> Array[String]:
	var out: Array[String] = []
	for key in _overlay.keys():
		out.append(str(key))
	out.sort()
	return out


static func _raw(pool_id: String) -> Dictionary:
	if _overlay.has(pool_id):
		return _overlay[pool_id] as Dictionary
	if POOLS.has(pool_id):
		return POOLS[pool_id] as Dictionary
	return {}


## 池是否已登记（不论状态）。
static func has_pool(pool_id: String) -> bool:
	return _overlay.has(pool_id) or POOLS.has(pool_id)


## 取池登记条目；未登记返回空字典。
static func get_pool(pool_id: String) -> Dictionary:
	return _raw(pool_id).duplicate(true)


## 池是否已登记且 active。
static func is_active(pool_id: String) -> bool:
	var info := _raw(pool_id)
	return not info.is_empty() and str(info.get("status", "")) == STATUS_ACTIVE


## 全部已登记池ID（不含覆盖层未在 POOLS 中的键则一并计入），已排序。
static func pool_ids() -> Array[String]:
	var seen: Dictionary = {}
	for key in POOLS.keys():
		seen[str(key)] = true
	for key in _overlay.keys():
		seen[str(key)] = true
	var out: Array[String] = []
	for key in seen.keys():
		out.append(str(key))
	out.sort()
	return out


## 池的 Roll 模式；未登记返回空串。
static func roll_mode(pool_id: String) -> String:
	var info := _raw(pool_id)
	if info.is_empty():
		return ""
	return str(info.get("roll", ROLL_WEIGHTED))


## 池的抽次上限。未登记或非法返回 DEFAULT_MAX_DROPS。
static func cap(pool_id: String) -> int:
	var info := _raw(pool_id)
	if info.is_empty():
		return DEFAULT_MAX_DROPS
	return maxi(0, int(info.get("cap", DEFAULT_MAX_DROPS)))


## 池登记行是否**显式声明**了抽次上限。
##
## 与 `cap()` 的区别是关键：`cap()` 会在缺省时补 `DEFAULT_MAX_DROPS`，
## 无法区分「作者写了 1」与「作者没写」。04 §22.8 的 `MISSING_MAX_DROPS`
## 要求「`independent` 池必须显式钳位、不许静默」⇒ 判据只能看有没有这个键。
static func has_declared_cap(pool_id: String) -> bool:
	var info := _raw(pool_id)
	return not info.is_empty() and info.has("cap")


## 物品表当前**声明**过的全部池键（weight 与 chance 两侧合并），已排序。
## 这是「物品表侧的事实」，用来与登记表交叉比对。
static func declared_pool_ids() -> Array[String]:
	var registry := ItemRegistry.get_instance()
	var seen: Dictionary = {}
	for item in registry.get_all_items():
		for key in _keys_of(item, "floor_loot_weights"):
			seen[key] = true
		for key in _keys_of(item, "floor_loot_chances"):
			seen[key] = true
	var out: Array[String] = []
	for key in seen.keys():
		out.append(str(key))
	out.sort()
	return out


## 取池成员（只读投影：物品定义 + `loot_weight` + `loot_chance`）。
## `loot_chance` 未声明时为 -1.0（调用方据此报 INVALID_CHANCE，不静默当 0）。
##
## 权重来源：物品表 `floor_loot_weights[pool]`；覆盖层的 `member_weights` 可**按池视角**覆盖
## 单件权重（不改物品表）。加这个通道的理由：作者最常调的就是"这个池里某件多少概率"，
## 而同一物品在不同池里本就允许权重不同 —— 池视角覆盖是这条需求的自然落点，
## 也是"池权重全 0 必须报 EMPTY_WEIGHT"这条门禁唯一可复现的构造方式。
static func members(pool_id: String) -> Array[Dictionary]:
	var registry := ItemRegistry.get_instance()
	var raw: Array[Dictionary] = registry.get_loot_table(pool_id)
	var weight_override: Dictionary = _raw(pool_id).get("member_weights", {})
	var out: Array[Dictionary] = []
	for entry in raw:
		var item_id := str(entry.get("id", ""))
		if item_id.is_empty():
			continue
		var copy := entry.duplicate(true)
		copy["item_id"] = item_id
		if weight_override.has(item_id):
			copy["loot_weight"] = float(weight_override[item_id])
		copy["loot_chance"] = declared_chance(item_id, pool_id)
		out.append(copy)
	return out


## 某个物品对某个池声明的独立概率；未声明返回 -1.0。
##
## 取值顺序：① 池覆盖层的 `member_chances`（池内视角的数值，掉落池表装载时用）；
##           ② 物品表的 `floor_loot_chances[pool]`。两者都没有 → -1.0（调用方报 INVALID_CHANCE）。
static func declared_chance(item_id: String, pool_id: String) -> float:
	if item_id.is_empty() or pool_id.is_empty():
		return -1.0
	var info := _raw(pool_id)
	var per_member: Dictionary = info.get("member_chances", {})
	if per_member.has(item_id):
		return float(per_member[item_id])
	var item := ItemRegistry.get_instance().get_item(item_id)
	if item.is_empty():
		return -1.0
	var chances: Dictionary = item.get("floor_loot_chances", {})
	if not chances.has(pool_id):
		return -1.0
	return float(chances[pool_id])


## 池内掷骰字段是否自洽。返回错误码（空串 = 通过）。
##
## 关键数据事实：**池成员资格由物品表的 `floor_loot_weights` 键决定**，
## 所以任何池的成员天生带 `weight`。因此：
##   · `independent` 池里 weight 是**结构性的**（成员资格 + 截断优先级），不是混用；
##     概率另由 `floor_loot_chances` / 覆盖层 `member_chances` 给出。
##   · 真正的混用是**反过来**：池声明 `weighted`，却有成员声明了 `chance` —— 那个 chance 无意义，属作者错误。
##
## 返回 `CONFLICT_MIXED_ROLL_FIELDS`（weighted 池里有成员声明 chance）
##     / `CONFLICT_INVALID_CHANCE`（independent 池里有成员没声明 chance）
##     / `CONFLICT_NONE`（自洽）。
static func roll_field_conflict(pool_id: String) -> String:
	var mode := roll_mode(pool_id)
	if mode == "":
		return CONFLICT_NONE
	var members := members(pool_id)
	if members.is_empty():
		return CONFLICT_NONE
	var declared := 0
	for member in members:
		if float(member.get("loot_chance", -1.0)) >= 0.0:
			declared += 1
	if mode == ROLL_INDEPENDENT or mode == ROLL_ALL:
		if declared < members.size():
			return CONFLICT_INVALID_CHANCE
		return CONFLICT_NONE
	# weighted：池内出现 chance 声明即视为语义混用。
	if declared > 0:
		return CONFLICT_MIXED_ROLL_FIELDS
	return CONFLICT_NONE


## 全量门禁评估（只评估 `POOLS` 正式表，不含覆盖层；覆盖层是装载/替身通道）。
## 返回 { ok, unregistered[], empty_active[], missing_cap[], mixed_fields[],
##        invalid_chance[], deprecated_without_target[], summary{} }。
static func evaluate() -> Dictionary:
	var declared := declared_pool_ids()
	var registered := pool_ids()

	var unregistered: Array[String] = []
	for pool_id in declared:
		if not has_pool(pool_id):
			unregistered.append(pool_id)

	var empty_active: Array[String] = []
	var missing_cap: Array[String] = []
	var mixed_fields: Array[String] = []
	var invalid_chance: Array[String] = []
	var deprecated_without_target: Array[String] = []
	var pending_decisions: Array[String] = []

	for pool_id in registered:
		var info: Dictionary = POOLS[pool_id] if POOLS.has(pool_id) else _overlay[pool_id]
		var status := str(info.get("status", ""))
		if status == STATUS_DEPRECATED:
			if bool(info.get("decision_pending", false)):
				# 已登记、已写明迁移建议，只等一次数据裁决 —— 报告但不拦门禁。
				pending_decisions.append(pool_id)
			elif str(info.get("migration_target", "")).is_empty():
				deprecated_without_target.append(pool_id)
			continue
		if members(pool_id).is_empty():
			empty_active.append(pool_id)
			continue
		var mode := str(info.get("roll", ROLL_WEIGHTED))
		if mode == ROLL_INDEPENDENT and maxi(0, int(info.get("cap", DEFAULT_MAX_DROPS))) <= 0:
			missing_cap.append(pool_id)
		var conflict := roll_field_conflict(pool_id)
		if conflict == CONFLICT_MIXED_ROLL_FIELDS:
			mixed_fields.append(pool_id)
		elif conflict == CONFLICT_INVALID_CHANCE:
			invalid_chance.append(pool_id)

	var ok := (
		unregistered.is_empty()
		and empty_active.is_empty()
		and missing_cap.is_empty()
		and mixed_fields.is_empty()
		and invalid_chance.is_empty()
		and deprecated_without_target.is_empty()
	)

	var active_count := 0
	for pool_id in registered:
		var row: Dictionary = POOLS[pool_id] if POOLS.has(pool_id) else _overlay[pool_id]
		if str(row.get("status", "")) == STATUS_ACTIVE:
			active_count += 1

	return {
		"ok": ok,
		"unregistered": unregistered,
		"empty_active": empty_active,
		"missing_cap": missing_cap,
		"mixed_fields": mixed_fields,
		"invalid_chance": invalid_chance,
		"deprecated_without_target": deprecated_without_target,
		"pending_decisions": pending_decisions,
		"summary": {
			"declared": declared.size(),
			"registered": registered.size(),
			"active": active_count,
			"deprecated": registered.size() - active_count,
		},
	}


## 单行摘要，供门禁打印判据。字段与 `evaluate()` 的每个红项一一对应，不许有"静默的红"。
static func summary_line() -> String:
	var report := evaluate()
	var summary: Dictionary = report["summary"]
	return "REWARD_POOL_REGISTRY_OK declared=%d registered=%d active=%d deprecated=%d dead_active=%d unregistered=%d mixed=%d invalid_chance=%d missing_cap=%d deprecated_without_target=%d pending=%d" % [
		int(summary["declared"]),
		int(summary["registered"]),
		int(summary["active"]),
		int(summary["deprecated"]),
		(report["empty_active"] as Array).size(),
		(report["unregistered"] as Array).size(),
		(report["mixed_fields"] as Array).size(),
		(report["invalid_chance"] as Array).size(),
		(report["missing_cap"] as Array).size(),
		(report["deprecated_without_target"] as Array).size(),
		(report["pending_decisions"] as Array).size(),
	]


static func _keys_of(item: Dictionary, field: String) -> Array[String]:
	var out: Array[String] = []
	var table: Dictionary = item.get(field, {})
	for key in table.keys():
		out.append(str(key))
	return out
