class_name RewardSpec
extends RefCounted
## RewardSpec — 奖励规格的解析与校验（REWARD-SERVICE 的输入契约）。
##
## 一份 Spec = 「发什么」的唯一可编辑声明。四个 kind 覆盖全部投放：
##   item      物品表 · 按 item_id 直取
##   pool      物品表 · 按池键反向聚集（掷骰规则由掉落池登记表决定）
##   monster   怪物表 · 按 monster_id 取该怪的掉落规格（递归深度硬限 1）
##   currency  货币表 · 按公式算量
##
## 只读依赖：`ItemRegistry`（物品表）、`MonsterInjector`（怪物表）、`RewardPoolRegistry`（池登记）。
## 不得 import 任何 `world3d`。设计依据：`docs/v0.1/04_技术施工_战斗与局内成长.md` §22.3。

const KIND_ITEM := "item"
const KIND_POOL := "pool"
const KIND_MONSTER := "monster"
const KIND_CURRENCY := "currency"
const KINDS := [KIND_ITEM, KIND_POOL, KIND_MONSTER, KIND_CURRENCY]

## 三个调度触发点。`clear` 清房、`search` 搜索容器、`kill` 击杀。
const TRIGGER_CLEAR := "clear"
const TRIGGER_SEARCH := "search"
const TRIGGER_KILL := "kill"
const TRIGGERS := [TRIGGER_CLEAR, TRIGGER_SEARCH, TRIGGER_KILL]

## fallback 长度上限；fallback 内不得再套 fallback（防无限回退）。
const MAX_FALLBACK := 2
## monster kind 的递归深度硬限，防环。
const MAX_MONSTER_DEPTH := 1

## 货币 ID 登记。当前全项目只有魂一种；BaseData.extraction_points 是它的持久化字段。
## 尚无独立货币表，故这里是唯一口径，不得在别处另写一份字符串。
const CURRENCIES := {
	"extraction_points": { "name": "魂", "persist_field": "extraction_points" },
}

## 命名规格运行时登记处（spec_id → spec）。关卡设计源装载时install，测试可注入替身。
static var _named_specs: Dictionary = {}

const _MONSTER_INJECTOR := preload("res://src/map/MonsterInjector.gd")
const _POOLS := preload("res://src/rewards/RewardPoolRegistry.gd")


# ---------------------------------------------------------------------------
# 命名规格登记
# ---------------------------------------------------------------------------

static func clear_named() -> void:
	_named_specs.clear()


static func has_named(spec_id: String) -> bool:
	return _named_specs.has(spec_id)


static func get_named(spec_id: String) -> Dictionary:
	if not _named_specs.has(spec_id):
		return {}
	var raw: Dictionary = _named_specs[spec_id]
	return raw.duplicate(true)


## 登记一份命名规格。spec_id 为空、或 spec 非法时返回 false 并不写入。
static func register_named(spec_id: String, spec: Dictionary) -> bool:
	if spec_id.is_empty() or spec.is_empty():
		return false
	var probe := spec.duplicate(true)
	probe["spec_id"] = spec_id
	if not validate_spec(probe, "named:%s" % [spec_id]).get("ok", false):
		return false
	_named_specs[spec_id] = probe
	return true


static func named_spec_ids() -> Array[String]:
	var out: Array[String] = []
	for key in _named_specs.keys():
		out.append(str(key))
	out.sort()
	return out


# ---------------------------------------------------------------------------
# 恒定资产表只读口径
# ---------------------------------------------------------------------------

static func is_known_monster(monster_id: String) -> bool:
	return _MONSTER_INJECTOR.BASE_ENEMY_TYPES.has(monster_id)


static func known_monster_ids() -> Array[String]:
	var out: Array[String] = []
	for key in _MONSTER_INJECTOR.BASE_ENEMY_TYPES.keys():
		out.append(str(key))
	out.sort()
	return out


static func is_known_currency(currency_id: String) -> bool:
	return CURRENCIES.has(currency_id)


static func known_currency_ids() -> Array[String]:
	var out: Array[String] = []
	for key in CURRENCIES.keys():
		out.append(str(key))
	out.sort()
	return out


# ---------------------------------------------------------------------------
# 引用归一化：房间/关卡 reward_plan 的一个槽位 → 具体 spec
# ---------------------------------------------------------------------------

## 把一个槽位引用归一化成具体 spec。
##
## 支持三种写法（设计源侧越写越省）：
##   1. `{"spec_id": "exp01_room_03_clear"}`   → 取登记表里的命名规格
##   2. `{"entries": [...]}`（可带 fallback）   → 内联规格
##   3. `{"pool_id": "loot_floor_1_2"}`         → 单条池 entry 的简写（可带 draws / chance）
##
## 返回 `{ ok, spec, errors }`。未登记的 spec_id 一律拒绝，**不回退**别的规格。
static func normalize_ref(ref: Dictionary, path: String) -> Dictionary:
	var errors: Array[Dictionary] = []

	if ref.is_empty():
		return { "ok": false, "spec": {}, "errors": [_err("INVALID_SPEC_REF", path, "空引用")] }

	if ref.has("spec_id"):
		var spec_id := str(ref["spec_id"])
		if spec_id.is_empty():
			return { "ok": false, "spec": {}, "errors": [_err("INVALID_SPEC_REF", path, "spec_id 为空")] }
		if not has_named(spec_id):
			return {
				"ok": false, "spec": {},
				"errors": [_err("UNKNOWN_SPEC", "%s.spec_id" % [path], "未登记命名规格 '%s'" % [spec_id])],
			}
		var named := get_named(spec_id)
		return { "ok": true, "spec": named, "errors": errors }

	if ref.has("entries") or ref.has("fallback"):
		var inline := ref.duplicate(true)
		if not inline.has("spec_id"):
			inline["spec_id"] = "inline:%s" % [path]
		var check := validate_spec(inline, path)
		return { "ok": bool(check["ok"]), "spec": inline if check["ok"] else {}, "errors": check["errors"] }

	if ref.has("pool_id"):
		var entry := { "kind": KIND_POOL, "pool_id": str(ref["pool_id"]) }
		if ref.has("draws"):
			entry["draws"] = ref["draws"]
		if ref.has("chance"):
			entry["chance"] = ref["chance"]
		var single := { "spec_id": "inline:%s" % [path], "entries": [entry] }
		var single_check := validate_spec(single, path)
		return {
			"ok": bool(single_check["ok"]),
			"spec": single if single_check["ok"] else {},
			"errors": single_check["errors"],
		}

	return {
		"ok": false, "spec": {},
		"errors": [_err("INVALID_SPEC_REF", path, "既无 spec_id / entries 也无 pool_id")],
	}


# ---------------------------------------------------------------------------
# 规格校验
# ---------------------------------------------------------------------------

## 校验一份 spec（含 entries 与 fallback 的逐条校验）。
## 返回 `{ ok, errors: [{code, path, detail}] }`。errors 非空即整份规格被拒。
static func validate_spec(spec: Dictionary, path: String = "spec") -> Dictionary:
	var errors: Array[Dictionary] = []

	if spec.is_empty():
		return { "ok": false, "errors": [_err("INVALID_ENTRY", path, "spec 为空")] }

	var spec_id := str(spec.get("spec_id", ""))
	if spec_id.is_empty():
		errors.append(_err("INVALID_ENTRY", "%s.spec_id" % [path], "spec_id 缺失或为空"))

	var entries = spec.get("entries", null)
	if entries == null:
		errors.append(_err("INVALID_ENTRY", "%s.entries" % [path], "entries 缺失"))
	elif not (entries is Array):
		errors.append(_err("INVALID_ENTRY", "%s.entries" % [path], "entries 不是数组"))
	else:
		var index := 0
		for entry in entries:
			errors.append_array(_validate_entry(entry, "%s.entries[%d]" % [path, index]))
			index += 1

	if spec.has("fallback"):
		var fallback = spec["fallback"]
		if not (fallback is Array):
			errors.append(_err("INVALID_ENTRY", "%s.fallback" % [path], "fallback 不是数组"))
		else:
			var fb: Array = fallback
			if fb.size() > MAX_FALLBACK:
				errors.append(_err(
					"INVALID_ENTRY", "%s.fallback" % [path],
					"fallback 长度 %d 超过上限 %d" % [fb.size(), MAX_FALLBACK]
				))
			var index := 0
			for entry in fb:
				if entry is Dictionary and (entry as Dictionary).has("fallback"):
					errors.append(_err(
						"INVALID_ENTRY", "%s.fallback[%d]" % [path, index],
						"fallback 内不得再套 fallback"
					))
				else:
					errors.append_array(_validate_entry(entry, "%s.fallback[%d]" % [path, index]))
				index += 1

	return { "ok": errors.is_empty(), "errors": errors }


static func _validate_entry(entry, path: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []

	if not (entry is Dictionary):
		return [_err("INVALID_ENTRY", path, "entry 不是字典")]

	var e: Dictionary = entry
	var kind := str(e.get("kind", ""))
	if kind.is_empty() or not KINDS.has(kind):
		return [_err("INVALID_ENTRY", "%s.kind" % [path], "kind '%s' 不在 %s 内" % [kind, str(KINDS)])]

	if e.has("chance"):
		var chance = e["chance"]
		if not (chance is float or chance is int):
			errors.append(_err("INVALID_CHANCE", "%s.chance" % [path], "chance 不是数值"))
		else:
			var value := float(chance)
			if value < 0.0 or value > 1.0:
				errors.append(_err(
					"INVALID_CHANCE", "%s.chance" % [path],
					"chance %.4f 越界（要求 0 ≤ chance ≤ 1）" % [value]
				))

	match kind:
		KIND_ITEM:
			var item_id := str(e.get("item_id", ""))
			if item_id.is_empty():
				errors.append(_err("INVALID_ENTRY", "%s.item_id" % [path], "item_id 缺失"))
			elif not ItemRegistry.get_instance().has_item(item_id):
				errors.append(_err("UNKNOWN_ITEM", "%s.item_id" % [path], "未登记物品 '%s'" % [item_id]))
			errors.append_array(_validate_count(e, path))

		KIND_POOL:
			var pool_id := str(e.get("pool_id", ""))
			if pool_id.is_empty():
				errors.append(_err("INVALID_ENTRY", "%s.pool_id" % [path], "pool_id 缺失"))
			elif not _POOLS.has_pool(pool_id):
				errors.append(_err("UNKNOWN_POOL", "%s.pool_id" % [path], "未登记掉落池 '%s'" % [pool_id]))
			elif not _POOLS.is_active(pool_id):
				errors.append(_err(
					"POOL_DEPRECATED", "%s.pool_id" % [path],
					"池 '%s' 已弃用（迁移目标 '%s'），不得被新内容引用" % [
						pool_id, str(_POOLS.get_pool(pool_id).get("migration_target", ""))
					]
				))
			else:
				var conflict := _POOLS.roll_field_conflict(pool_id)
				if conflict == _POOLS.CONFLICT_MIXED_ROLL_FIELDS:
					errors.append(_err(
						_POOLS.CONFLICT_MIXED_ROLL_FIELDS, "%s.pool_id" % [path],
						"池 '%s' 声明为 weighted 却有成员声明 chance，语义混用，整池拒绝" % [pool_id]
					))
				elif conflict == _POOLS.CONFLICT_INVALID_CHANCE:
					errors.append(_err(
						_POOLS.CONFLICT_INVALID_CHANCE, "%s.pool_id" % [path],
						"池 '%s' 声明为 independent 但成员未声明 floor_loot_chances（或覆盖层 member_chances）" % [pool_id]
					))
				if _POOLS.roll_mode(pool_id) == _POOLS.ROLL_INDEPENDENT and not _POOLS.has_declared_cap(pool_id):
					# 件数无数学上界 ⇒ 必须显式钳位；缺省补的 1 不算"声明过"。
					errors.append(_err(
						"MISSING_MAX_DROPS", "%s.pool_id" % [path],
						"independent 池 '%s' 未显式声明抽次上限（cap），不许静默截断" % [pool_id]
					))
			if e.has("draws"):
				var draws = e["draws"]
				if not (draws is int or draws is float):
					errors.append(_err("INVALID_ENTRY", "%s.draws" % [path], "draws 不是数值"))
				elif int(draws) < 0:
					errors.append(_err("INVALID_ENTRY", "%s.draws" % [path], "draws 为负"))

		KIND_MONSTER:
			var monster_id := str(e.get("monster_id", ""))
			if monster_id.is_empty():
				errors.append(_err("INVALID_ENTRY", "%s.monster_id" % [path], "monster_id 缺失"))
			elif not is_known_monster(monster_id):
				errors.append(_err(
					"UNKNOWN_MONSTER", "%s.monster_id" % [path], "未登记怪物 '%s'" % [monster_id]
				))
			if int(e.get("depth", 0)) > MAX_MONSTER_DEPTH:
				errors.append(_err(
					"SPEC_CYCLE", "%s.depth" % [path],
					"monster 递归深度超过硬限 %d" % [MAX_MONSTER_DEPTH]
				))

		KIND_CURRENCY:
			var currency_id := str(e.get("currency_id", ""))
			if currency_id.is_empty():
				errors.append(_err("INVALID_ENTRY", "%s.currency_id" % [path], "currency_id 缺失"))
			elif not is_known_currency(currency_id):
				errors.append(_err(
					"UNKNOWN_CURRENCY", "%s.currency_id" % [path], "未登记货币 '%s'" % [currency_id]
				))
			if not e.has("amount"):
				errors.append(_err("INVALID_ENTRY", "%s.amount" % [path], "amount 缺失"))
			elif not (e["amount"] is Dictionary or e["amount"] is int or e["amount"] is float):
				errors.append(_err(
					"INVALID_ENTRY", "%s.amount" % [path], "amount 既不是公式对象也不是常量"
				))

	return errors


static func _validate_count(entry: Dictionary, path: String) -> Array[Dictionary]:
	if not entry.has("count"):
		return []
	var count = entry["count"]
	# RewardService._eval_amount() supports constants, formulas and ranges.  Keep
	# the schema gate aligned with the evaluator; rejecting Dictionary here made
	# every MonsterInjector ammo range structurally invalid at runtime.
	if not (count is Dictionary or count is int or count is float):
		return [_err("INVALID_ENTRY", "%s.count" % [path], "count 既不是常量也不是公式对象")]
	return []


# ---------------------------------------------------------------------------
# 折算概率（只读，供编辑器显示，禁止作者手算）
# ---------------------------------------------------------------------------

## 由一串独立概率折算：{ any: 至少一件, none: 空手, both_all: 全部命中, expected: 期望件数 }。
## 反直觉点：`any = 1 − Π(1−p_i)` **不等于** `Σp_i`，见 04 §22.4。
static func fold_chances(chances: Array) -> Dictionary:
	var none := 1.0
	var expected := 0.0
	for raw in chances:
		var p := clampf(float(raw), 0.0, 1.0)
		none *= (1.0 - p)
		expected += p
	return {
		"any": 1.0 - none,
		"none": none,
		"expected": expected,
	}


static func _err(code: String, path: String, detail: String) -> Dictionary:
	return { "code": code, "path": path, "detail": detail }
