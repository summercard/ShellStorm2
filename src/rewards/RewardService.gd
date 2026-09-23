class_name RewardService
extends RefCounted
## RewardService — 「规格 → 实体」的**唯一**解析器（REWARD-SERVICE 的事实所有者）。
##
## 纯逻辑：`RefCounted`，输入 `(spec, context)`，输出奖励实体数组与报告。
## **不需要 Godot 场景**即可测；不得反向读 `Dungeon3D` / 场景节点 / `RoomGraphRuntime`；
## 不得 import 任何 `world3d`。调度点只负责「选 Spec + 选 Sink + 给位置」，不再含数值。
##
## 两种掷骰模型（池级声明，同一解析器内单一分叉）：
##   weighted    池内归一加权抽签：抽 `draws` 次，每次按 `w_i/Σw` 选 1 件。必出，件数恒等于 draws。
##   independent 逐件独立判定：每件各掷 1 次，互不影响。可空手、可多件、件数受 `max_drops` 钳位。
##   all         奖励型全给（等价 independent 且 p_i ≡ 1）。
##
## ⚠️ 反直觉点：`independent` 池「至少掉一件」= `1 − Π(1−p_i)`，**不等于** `Σp_i`。
##    `p=(0.2, 0.5)` 时是 60%（不是 70%），两件都掉 10%，空手 40%。作者按加法心算会系统性高估。
##    折算值由 `RewardSpec.fold_chances()` 给出，编辑器直接显示，禁止作者手算。
##
## 设计依据：`docs/v0.1/04_技术施工_战斗与局内成长.md` §22。

const _SPEC := preload("res://src/rewards/RewardSpec.gd")
const _POOLS := preload("res://src/rewards/RewardPoolRegistry.gd")
const _WEAPON_INSTANCE := preload("res://src/weapons/WeaponInstance.gd")

## 默认可为空的怪物掉落规格提供者：(monster_id, tier, floor_level, floor) -> spec Dictionary。
## 缺省走 `MonsterInjector.drop_spec_for`（怪物表的结构化投影）。
static var _monster_spec_provider: Callable = Callable()


## 注入怪物掉落规格提供者（测试替身用）。传空 Callable 恢复缺省。
static func set_monster_spec_provider(provider: Callable) -> void:
	_monster_spec_provider = provider


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------

## 解析一份 spec。返回 `{ ok, spec_id, grants[], rejected[], truncated, used_fallback, errors[] }`。
##
## ⚠️ `ok` 的语义是**「规格结构通过校验」**，不是「拿到了奖励」：
##   · 结构非法（entries 缺失、chance 越界、未知 ID…）⇒ `ok=false`，`errors` 有内容，`grants` 空。
##   · 结构合法但某条被拒（空池、权重全 0、超上限冲突…）⇒ `ok=true`，`rejected` 有内容，`grants` 可能为空。
##   调用方若要判"有没有出东西"，看 `grants`；要判"哪条被拒"，看 `rejected`。
##   二者不可合并成一个布尔 —— 04 §22.8 明确「未知 ID 拒绝，空池才算失败下限、允许回退」，
##   这条纪律只有在 `ok` 与 `rejected` 分离时才表达得出来。
##
## context：
##   seed:int        必给（同 seed + 同 spec 必须逐位一致；绝不用全局 randf）
##   floor:int       默认 1
##   depth:int       默认 0
##   multipliers:{}  multiplier_ref 取值表，默认 1.0
##   salt:String     同一 seed 下把不同调度点的流分开（可选）
static func resolve(spec: Dictionary, context: Dictionary = {}) -> Dictionary:
	var spec_id := str(spec.get("spec_id", ""))
	var report := {
		"ok": false,
		"spec_id": spec_id,
		"grants": [] as Array[Dictionary],
		"rejected": [] as Array[Dictionary],
		"truncated": false,
		"used_fallback": false,
		"errors": [] as Array[Dictionary],
	}

	var check := _SPEC.validate_spec(spec, "spec:%s" % [spec_id])
	if not check.get("ok", false):
		report["errors"] = check["errors"]
		return report
	report["ok"] = true

	var ctx := _normalize_context(context)
	var rng := _make_rng(ctx, spec_id)
	var state := {
		"ctx": ctx,
		"rng": rng,
		"grants": [] as Array[Dictionary],
		"rejected": [] as Array[Dictionary],
		"truncated": false,
	}

	_resolve_entries(spec.get("entries", []), state, "entries", 0)

	if (state["grants"] as Array).is_empty() and spec.has("fallback"):
		# 空池才允许回退；未知 ID 已在 validate 阶段被拒，两者分道。
		report["used_fallback"] = true
		_resolve_entries(spec.get("fallback", []), state, "fallback", 0)

	report["grants"] = _sort_grants(state["grants"])
	report["rejected"] = state["rejected"]
	report["truncated"] = bool(state["truncated"])
	return report


## 调度入口：按覆盖链选规格再解析。
##
## 覆盖链（唯一优先级，越左越优先）：
##   房间 reward_plan  >  关卡 reward_plan  >  怪物表 drop 规格  >  全局默认公式
##
## request：
##   trigger:"clear"|"search"|"kill"
##   room_reward_plan / level_reward_plan :  该触发的槽位引用（可选）
##   monster_id / monster_tier / floor_level : trigger=kill 时用于取怪物表规格
##   default_pool_id :  全局兜底池（可选）
##   context :  透传给 resolve
static func resolve_dispatch(request: Dictionary) -> Dictionary:
	var trigger := str(request.get("trigger", ""))
	if not _SPEC.TRIGGERS.has(trigger):
		return {
			"ok": false, "spec_id": "", "grants": [] as Array[Dictionary],
			"rejected": [] as Array[Dictionary], "truncated": false, "used_fallback": false,
			"errors": [{"code": "INVALID_TRIGGER", "path": "request.trigger", "detail": "trigger '%s' 不在 %s 内" % [trigger, str(_SPEC.TRIGGERS)]}],
		}

	var context: Dictionary = request.get("context", {}).duplicate(true)
	var picked := _pick_ref(request, trigger)
	var source := str(picked.get("source", ""))

	# 房间 > 关卡：命中即用，未登记 spec_id 一律拒绝，不回退到别级。
	if source == "room" or source == "level":
		var ref: Dictionary = picked.get("ref", {})
		var normalized := _SPEC.normalize_ref(ref, "reward_plan.%s.%s" % [source, trigger])
		if not normalized.get("ok", false):
			return {
				"ok": false, "spec_id": "", "grants": [] as Array[Dictionary],
				"rejected": [] as Array[Dictionary], "truncated": false, "used_fallback": false,
				"errors": normalized["errors"],
			}
		context["salt"] = "%s:%s" % [source, trigger]
		return resolve(normalized["spec"], context)

	# 怪物表规格（仅 kill 有意义；search/clear 无怪物上下文时跳过）
	if source == "monster":
		var monster_spec := _monster_spec_for(request, context)
		if monster_spec.is_empty():
			return _empty_report("monster")
		context["salt"] = "monster:%s" % [str(request.get("monster_id", ""))]
		return resolve(monster_spec, context)

	# 全局默认公式
	var default_pool := str(request.get("default_pool_id", ""))
	if default_pool.is_empty():
		return _empty_report("default")
	context["salt"] = "default"
	return resolve({
		"spec_id": "default:%s" % [default_pool],
		"entries": [{ "kind": _SPEC.KIND_POOL, "pool_id": default_pool }],
	}, context)


# ---------------------------------------------------------------------------
# 覆盖链
# ---------------------------------------------------------------------------

static func _pick_ref(request: Dictionary, trigger: String) -> Dictionary:
	var room_plan: Dictionary = request.get("room_reward_plan", {})
	if room_plan.has(trigger):
		return { "source": "room", "ref": room_plan[trigger] }
	var level_plan: Dictionary = request.get("level_reward_plan", {})
	if level_plan.has(trigger):
		return { "source": "level", "ref": level_plan[trigger] }
	if trigger == _SPEC.TRIGGER_KILL and not str(request.get("monster_id", "")).is_empty():
		return { "source": "monster", "ref": {} }
	return { "source": "default", "ref": {} }


static func _monster_spec_for(request: Dictionary, context: Dictionary) -> Dictionary:
	var monster_id := str(request.get("monster_id", ""))
	if monster_id.is_empty():
		return {}
	var tier := str(request.get("monster_tier", "normal"))
	var floor_level := int(request.get("floor_level", 0))
	var floor := int(context.get("floor", 1))
	if _monster_spec_provider.is_valid():
		var injected = _monster_spec_provider.call(monster_id, tier, floor_level, floor)
		if injected is Dictionary:
			return injected
	var injector := preload("res://src/map/MonsterInjector.gd")
	return injector.drop_spec_for(monster_id, tier, floor_level, floor)


static func _empty_report(spec_id: String) -> Dictionary:
	return {
		"ok": true, "spec_id": spec_id, "grants": [] as Array[Dictionary],
		"rejected": [] as Array[Dictionary], "truncated": false, "used_fallback": false,
		"errors": [] as Array[Dictionary],
	}


# ---------------------------------------------------------------------------
# 逐 entry 解析
# ---------------------------------------------------------------------------

static func _resolve_entries(entries, state: Dictionary, prefix: String, depth: int) -> void:
	if not (entries is Array):
		return
	var index := 0
	for entry in entries:
		var path := "%s[%d]" % [prefix, index]
		index += 1
		if not (entry is Dictionary):
			continue
		if depth > _SPEC.MAX_MONSTER_DEPTH:
			state["rejected"].append({"code": "SPEC_CYCLE", "path": path, "detail": "递归深度超限"})
			continue
		_resolve_entry(entry, state, path, depth)


static func _resolve_entry(entry: Dictionary, state: Dictionary, path: String, depth: int) -> void:
	var rng: RandomNumberGenerator = state["rng"]
	var ctx: Dictionary = state["ctx"]

	# 条目级概率闸：先判「这条出不出」，与池内掷骰相互独立。
	if entry.has("chance"):
		if rng.randf() > clampf(float(entry["chance"]), 0.0, 1.0):
			return

	var kind := str(entry.get("kind", ""))
	match kind:
		_SPEC.KIND_ITEM:
			_resolve_item_entry(entry, state, path)
		_SPEC.KIND_POOL:
			_resolve_pool_entry(entry, state, path)
		_SPEC.KIND_CURRENCY:
			_resolve_currency_entry(entry, state, path)
		_SPEC.KIND_MONSTER:
			_resolve_monster_entry(entry, state, path, depth, ctx)


static func _resolve_item_entry(entry: Dictionary, state: Dictionary, path: String) -> void:
	var item_id := str(entry.get("item_id", ""))
	var registry := ItemRegistry.get_instance()
	if not registry.has_item(item_id):
		state["rejected"].append({"code": "UNKNOWN_ITEM", "path": path, "detail": item_id})
		return
	var count := _eval_amount(entry.get("count", 1), state, path)
	if count <= 0:
		return
	var definition := registry.get_item(item_id)
	# 枪械 count=N 意味着 N 把不同的真实武器，不能把同一 instance_id
	# 塞进一个 count=N 的地面字典或背包堆叠。
	if str(definition.get("type", "")) == "weapon":
		for index in range(count):
			_append_grant(state, {
				"kind": _SPEC.KIND_ITEM, "item_id": item_id, "count": 1,
				"item": _WEAPON_INSTANCE.ensure_weapon_item(definition),
				"sink": str(entry.get("sink", "ground")), "pool_id": "",
				"slot": "%s:%d" % [path, index], "merged": false,
			}, false)
		return
	var item := _WEAPON_INSTANCE.ensure_weapon_item(definition)
	_append_grant(state, {
		"kind": _SPEC.KIND_ITEM,
		"item_id": item_id,
		"count": count,
		"item": item,
		"sink": str(entry.get("sink", "ground")),
		"pool_id": "",
		"slot": path,
		"merged": false,
	}, bool(entry.get("merge_same_item", false)))


static func _resolve_pool_entry(entry: Dictionary, state: Dictionary, path: String) -> void:
	var pool_id := str(entry.get("pool_id", ""))
	if not _POOLS.has_pool(pool_id):
		state["rejected"].append({"code": "UNKNOWN_POOL", "path": path, "detail": pool_id})
		return
	if not _POOLS.is_active(pool_id):
		state["rejected"].append({"code": "POOL_DEPRECATED", "path": path, "detail": pool_id})
		return

	var members := _POOLS.members(pool_id)
	if members.is_empty():
		# 空池不是失败：留给调用方决定是否走 fallback。
		state["rejected"].append({"code": "EMPTY_POOL", "path": path, "detail": pool_id})
		return

	var mode := _POOLS.roll_mode(pool_id)
	match mode:
		_POOLS.ROLL_INDEPENDENT:
			_draw_independent(entry, state, path, pool_id, members)
		_POOLS.ROLL_ALL:
			for member in members:
				_append_member(state, member, path, pool_id)
		_:
			_draw_weighted(entry, state, path, pool_id, members)


static func _draw_weighted(
	entry: Dictionary, state: Dictionary, path: String, pool_id: String, members: Array
) -> void:
	var total := 0.0
	for member in members:
		total += maxf(0.0, float((member as Dictionary).get("loot_weight", 0.0)))
	if total <= 0.0:
		state["rejected"].append({"code": "EMPTY_WEIGHT", "path": path, "detail": pool_id})
		return

	var cap := _effective_cap(entry, pool_id, state, path)
	if cap < 0:
		return

	var rng: RandomNumberGenerator = state["rng"]
	var draws := mini(_POOLS.cap(pool_id), cap)
	if entry.has("draws"):
		draws = mini(maxi(0, int(entry["draws"])), cap)

	for _i in range(draws):
		var roll := rng.randf() * total
		var cumulative := 0.0
		var picked: Dictionary = members[members.size() - 1]
		for member in members:
			cumulative += maxf(0.0, float((member as Dictionary).get("loot_weight", 0.0)))
			if roll <= cumulative:
				picked = member
				break
		_append_member(state, picked, path, pool_id)


static func _draw_independent(
	entry: Dictionary, state: Dictionary, path: String, pool_id: String, members: Array
) -> void:
	var rng: RandomNumberGenerator = state["rng"]
	for member in members:
		var p := float((member as Dictionary).get("loot_chance", -1.0))
		if p < 0.0 or p > 1.0:
			# 成员未声明 chance（-1）或越界：整池拒绝，不静默当 0。
			state["rejected"].append({
				"code": "INVALID_CHANCE", "path": path,
				"detail": "池 '%s' 成员概率越界或未声明" % [pool_id],
			})
			return

	var hits: Array = []
	for member in members:
		if rng.randf() < float((member as Dictionary).get("loot_chance", 0.0)):
			hits.append(member)

	if hits.is_empty():
		# 空手是 independent 的合法结果，不是错误。
		return

	var cap := _effective_cap(entry, pool_id, state, path)
	if cap < 0:
		return
	if cap == 0:
		return

	# 截断策略：priority —— 按权重降序取前 N（声明式，可复现；缺权重按 1.0 计）。
	hits.sort_custom(func(a, b):
		return float((a as Dictionary).get("loot_weight", 1.0)) > float((b as Dictionary).get("loot_weight", 1.0))
	)
	if hits.size() > cap:
		state["truncated"] = true
		state["rejected"].append({
			"code": "DROPS_TRUNCATED", "path": path,
			"detail": "命中 %d 件，按 priority 截断到 %d 件" % [hits.size(), cap],
		})
		hits = hits.slice(0, cap)

	for member in hits:
		_append_member(state, member, path, pool_id)


## 条目可用的件数上限。
##
## 04 §21（2026-08-07 冻结）「每次最多 1 件」默认**不变**，故上限默认恒为 1。
## 只有条目显式声明 `max_drops` 才放宽（04 §22.10 的 C2 裁决）。
## 池已声明多件、而条目没显式确认 → 报 `SINGLE_DROP_CONFLICT` 并拒绝，**不静默截断**。
## 返回 -1 表示拒绝。
static func _effective_cap(
	entry: Dictionary, pool_id: String, state: Dictionary, path: String
) -> int:
	if entry.has("max_drops"):
		return maxi(0, int(entry["max_drops"]))
	var pool_cap := _POOLS.cap(pool_id)
	if pool_cap > _POOLS.DEFAULT_MAX_DROPS:
		state["rejected"].append({
			"code": "SINGLE_DROP_CONFLICT", "path": path,
			"detail": "池 '%s' 声明上限 %d > %d，但条目未显式声明 max_drops" % [
				pool_id, pool_cap, _POOLS.DEFAULT_MAX_DROPS,
			],
		})
		return -1
	return pool_cap


static func _resolve_currency_entry(entry: Dictionary, state: Dictionary, path: String) -> void:
	var currency_id := str(entry.get("currency_id", ""))
	if not _SPEC.is_known_currency(currency_id):
		state["rejected"].append({"code": "UNKNOWN_CURRENCY", "path": path, "detail": currency_id})
		return
	var amount := _eval_amount(entry.get("amount", 0), state, path)
	if amount <= 0:
		return
	_append_grant(state, {
		"kind": _SPEC.KIND_CURRENCY,
		"currency_id": currency_id,
		"item_id": "",
		"amount": amount,
		"count": amount,
		"item": {},
		"sink": "wallet",
		"pool_id": "",
		"slot": path,
		"merged": false,
	}, false)


static func _resolve_monster_entry(
	entry: Dictionary, state: Dictionary, path: String, depth: int, ctx: Dictionary
) -> void:
	if depth >= _SPEC.MAX_MONSTER_DEPTH:
		state["rejected"].append({"code": "SPEC_CYCLE", "path": path, "detail": "monster 嵌套超限"})
		return
	var monster_id := str(entry.get("monster_id", ""))
	if not _SPEC.is_known_monster(monster_id):
		state["rejected"].append({"code": "UNKNOWN_MONSTER", "path": path, "detail": monster_id})
		return
	var spec := _monster_spec_for(
		{
			"monster_id": monster_id,
			"monster_tier": str(ctx.get("monster_tier", "normal")),
			"floor_level": int(ctx.get("floor_level", 0)),
		},
		ctx
	)
	if spec.is_empty():
		return
	# 用同一 rng 继续解析，保证同 seed 可复现；深度 +1 由 _resolve_entries 的硬限拦住。
	_resolve_entries(spec.get("entries", []), state, "monster:%s" % [monster_id], depth + 1)


# ---------------------------------------------------------------------------
# 数值与折算
# ---------------------------------------------------------------------------

## `count` / `amount` 求值：常量 / 公式对象 / 区间对象。
##   常量      : 3
##   公式      : {"base":2,"per_floor":1,"per_depth":0,"multiplier_ref":"world_currency"}
##               → round((base + per_floor×floor + per_depth×depth) × multiplier)
##   区间      : {"min":3,"max":8}  → rng.randi_range(min, max)
static func _eval_amount(raw, state: Dictionary, _path: String) -> int:
	if raw is int or raw is float:
		return maxi(0, int(round(float(raw))))
	if not (raw is Dictionary):
		return 0
	var spec: Dictionary = raw
	if spec.has("min") or spec.has("max"):
		var lo := int(spec.get("min", 1))
		var hi := int(spec.get("max", lo))
		if hi < lo:
			hi = lo
		var rng: RandomNumberGenerator = state["rng"]
		return maxi(0, rng.randi_range(lo, hi))
	var ctx: Dictionary = state["ctx"]
	var base := float(spec.get("base", 0))
	var per_floor := float(spec.get("per_floor", 0))
	var per_depth := float(spec.get("per_depth", 0))
	var multiplier := 1.0
	var multiplier_ref := str(spec.get("multiplier_ref", ""))
	if not multiplier_ref.is_empty():
		var table: Dictionary = ctx.get("multipliers", {})
		multiplier = float(table.get(multiplier_ref, 1.0))
	var value := (base + per_floor * float(ctx.get("floor", 1)) + per_depth * float(ctx.get("depth", 0))) * multiplier
	return maxi(0, int(round(value)))


static func _append_member(state: Dictionary, member: Dictionary, path: String, pool_id: String) -> void:
	var item: Dictionary = member.duplicate(true)
	item.erase("loot_weight")
	item.erase("loot_chance")
	# 地面掉落以单件为最小单位；堆叠只发生在拾取进入背包之后（04 §21）。
	_append_grant(state, {
		"kind": _SPEC.KIND_ITEM,
		"item_id": str(item.get("id", "")),
		"count": 1,
		"item": _WEAPON_INSTANCE.ensure_weapon_item(item),
		"sink": "ground",
		"pool_id": pool_id,
		"slot": path,
		"merged": false,
	}, true)


static func _append_grant(state: Dictionary, grant: Dictionary, merge_same_item: bool) -> void:
	var grants: Array = state["grants"]
	if merge_same_item and str(grant.get("kind", "")) == _SPEC.KIND_ITEM:
		var item_id := str(grant.get("item_id", ""))
		for existing in grants:
			var e: Dictionary = existing
			if str(e.get("kind", "")) == _SPEC.KIND_ITEM and str(e.get("item_id", "")) == item_id:
				# 旧口径：同 id 命中时用后者的数量**覆盖**（不是相加），
				# 因为弹药附加项在池已抽出同物时以「整包数量」为准（LootModule 既有行为）。
				e["count"] = int(grant.get("count", 1))
				e["merged"] = true
				e["item"] = grant.get("item", e.get("item", {}))
				return
	grants.append(grant)


static func _sort_grants(grants: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for grant in grants:
		out.append(grant as Dictionary)
	return out


# ---------------------------------------------------------------------------
# 确定性随机
# ---------------------------------------------------------------------------

static func _normalize_context(context: Dictionary) -> Dictionary:
	var ctx := context.duplicate(true)
	if not ctx.has("floor"):
		ctx["floor"] = 1
	if not ctx.has("depth"):
		ctx["depth"] = 0
	if not ctx.has("multipliers"):
		ctx["multipliers"] = {}
	if not ctx.has("seed"):
		ctx["seed"] = 0
	return ctx


static func _make_rng(ctx: Dictionary, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var combined := "%d|%s|%s" % [int(ctx.get("seed", 0)), str(ctx.get("salt", "")), salt]
	rng.seed = hash(combined)
	return rng
