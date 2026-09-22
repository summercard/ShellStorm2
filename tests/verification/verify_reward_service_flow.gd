extends Node
## verify_reward_service_flow — REWARD-SERVICE 的专项验收（纯逻辑，无场景）。
##
## 覆盖 04 §22.11 的 1~8 条；第 9 条（地面实体数量与颜色的真渲染）属视觉验收，
## 不在本用例内，另按 verify_requested_experience_upgrade_flow 的口径补截图。
##
## 本用例刻意**不加载任何游戏场景**：RewardService 是 RefCounted 纯逻辑，
## 必须能在无场景条件下被验证（这是 04 §22.9「独立入口」的硬要求）。
## 只读游戏数据（ItemRegistry / 怪物表 / 池登记表），不写存档、不改游戏状态。

const _POOLS := preload("res://src/rewards/RewardPoolRegistry.gd")
const _SPEC := preload("res://src/rewards/RewardSpec.gd")
const _SERVICE := preload("res://src/rewards/RewardService.gd")
const _SINK := preload("res://src/rewards/RewardSink.gd")
const _RUNTIME_COORDINATOR := preload("res://src/rewards/RuntimeRewardCoordinator.gd")

## 统计样本量。4000 次下加权频率的标准差约 sqrt(p(1-p)/N) ≈ 0.008，
## 容差取 0.03 已是 3.7σ 以上，正常随机不会误报。
const SAMPLES := 4000
const TOLERANCE := 0.03

var _failures: Array[String] = []


func _ready() -> void:
	_case_registry_gate()
	_case_reproducible()
	_case_same_source()
	_case_override_chain()
	_case_rejection_paths()
	_case_empty_vs_unknown()
	_case_weighted_distribution()
	_case_independent_math()
	_case_truncation()
	_case_field_conflict()
	_case_negative_controls()
	_case_runtime_coordinator()

	if _failures.is_empty():
		print("REWARD_SERVICE_FLOW_OK: registry gate, reproducibility, four dispatch sources, override chain, rejection paths, weighted/independent math, truncation and negative controls pass")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _case_runtime_coordinator() -> void:
	_reset()
	var coordinator := _RUNTIME_COORDINATOR.new()
	coordinator.configure(20260923)
	var first := coordinator.resolve_search({}, "scavenge_floor_1", 1, "room_a:crate_01")
	var second := coordinator.resolve_search({}, "scavenge_floor_1", 1, "room_a:crate_01")
	_expect(bool(first.get("ok", false)), "运行时协调器搜索解析应成功：%s" % str(first.get("errors", [])))
	_expect(
		_signature(first.get("grants", [])) == _signature(second.get("grants", [])),
		"运行时协调器必须按 run seed + event id 确定性解析"
	)
	var fixed := coordinator.resolve_fixed_item("item_ammo_pack", 300, "guaranteed_loadout_ammo")
	_expect(bool(fixed.get("ok", false)), "保底备弹必须走统一规格解析")
	_expect(
		int(((fixed.get("items", []) as Array)[0] as Dictionary).get("count", 0)) == 300,
		"保底备弹统一解析后应保留真实发数"
	)
	var kill := coordinator.resolve_kill({}, {
		"enemy_type": "melee_chaser", "floor": 1, "loot_table": "loot_floor_1_2",
	}, "room_a:enemy_01")
	_expect(bool(kill.get("ok", false)), "怪物击杀必须通过统一覆盖链解析：%s" % str(kill.get("errors", [])))
	_expect(
		(kill.get("items", []) as Array).any(func(item): return bool((item as Dictionary).get("is_currency", false))),
		"怪物击杀统一解析必须保留地面魂奖励"
	)
	var elite_kill := coordinator.resolve_kill({}, {
		"enemy_type": "melee_chaser", "floor": 2, "loot_table": "loot_floor_1_2",
		"is_elite": true, "elite_bounty_currency": 35,
	}, "room_a:elite_01")
	var physical_count := 0
	var currency_count := 0
	for value in elite_kill.get("items", []):
		var item := value as Dictionary
		if bool(item.get("is_currency", false)):
			currency_count += 1
		else:
			physical_count += 1
	_expect(physical_count == 1, "精英击杀必须保持一个非货币地面实体")
	_expect(currency_count == 1, "基础魂与精英悬赏必须合并为一个地面魂球")


# ---------------------------------------------------------------------------
# 用例 0：池登记门禁本身
# ---------------------------------------------------------------------------

func _case_registry_gate() -> void:
	_reset()
	var report := _POOLS.evaluate()
	_expect(bool(report["ok"]), "池登记门禁应为绿：%s" % _POOLS.summary_line())
	_expect(
		(report["unregistered"] as Array).is_empty(),
		"物品表声明的池键必须全部登记，未登记：%s" % str(report["unregistered"])
	)
	_expect(
		(report["empty_active"] as Array).is_empty(),
		"active 池不得无成员（死池）：%s" % str(report["empty_active"])
	)
	var summary: Dictionary = report["summary"]
	_expect(int(summary["active"]) + int(summary["deprecated"]) == int(summary["registered"]), "active + deprecated 必须等于 registered")
	_expect(int(summary["registered"]) >= 21, "登记池数不应少于 21 个，实测 %d" % int(summary["registered"]))
	# 死池必须写明待裁决或迁移目标，二者至少有一个（否则 deprecated_without_target 非空）。
	var silent: Array = report["deprecated_without_target"]
	_expect(silent.is_empty(), "弃用池必须写明迁移目标或标为待裁决，未写：%s" % str(silent))


# ---------------------------------------------------------------------------
# 用例 1：同 (spec, seed) 逐位一致
# ---------------------------------------------------------------------------

func _case_reproducible() -> void:
	_reset()
	var spec := _pool_spec("t_repro", "loot_common")
	var first := _SERVICE.resolve(spec, { "seed": 20260922 })
	var second := _SERVICE.resolve(spec, { "seed": 20260922 })
	_expect(bool(first["ok"]), "可复现用例的规格应被接受：%s" % str(first["errors"]))
	_expect(
		_signature(first["grants"]) == _signature(second["grants"]),
		"同一 (spec, seed) 两次解析必须逐位一致：%s vs %s" % [_signature(first["grants"]), _signature(second["grants"])]
	)

	# 同 seed 下拒绝结果也必须稳定（错误列表逐位一致）。
	var bad := { "spec_id": "t_bad", "entries": [{ "kind": "pool", "pool_id": "__no_such_pool__" }] }
	var bad_first := _SERVICE.resolve(bad, { "seed": 7 })
	var bad_second := _SERVICE.resolve(bad, { "seed": 7 })
	_expect(_error_codes(bad_first) == _error_codes(bad_second), "同 seed 下拒绝原因必须稳定")


# ---------------------------------------------------------------------------
# 用例 2：四类投放同源（"机制一样"的唯一判据）
# ---------------------------------------------------------------------------

## 判据分两层，原因是实现上刻意给每个调度点上了不同 salt（`resolve_dispatch` 里
## 把 salt 设为 "room:kill" / "level:kill" / "monster:<id>" / "default"），
## 目的是让**同一次跑**里不同调度点的随机流互不相关（否则同一房间的 clear 与 search
## 会抽出同一件东西）。因此"同源"不能写成"逐位相同"，必须写成：
##   B1 同一 context 下四路调用同一 resolve → 逐位相同（解析器只有一份）；
##   B2 四路 dispatch 各自解析到同一个 spec_id / 同一个池，且大样本分布对拍一致。
func _case_same_source() -> void:
	_reset()
	var spec := _pool_spec("t_same", "loot_common")
	_expect(_SPEC.register_named("t_same", spec), "命名规格 t_same 应登记成功")
	# 怪物表替身：任何怪都返回同一份 spec。
	_SERVICE.set_monster_spec_provider(func(_m, _t, _l, _f): return _SPEC.get_named("t_same"))

	var context := { "seed": 4242, "salt": "aligned" }

	# B1：四个调度点最终都落到同一个 resolve，产出必须逐位相同。
	var resolved: Array[String] = []
	for _i in range(4):
		resolved.append(_signature(_SERVICE.resolve(spec, context)["grants"]))
	for index in range(1, resolved.size()):
		_expect(
			resolved[index] == resolved[0],
			"同一 context 下第 %d 次解析结果应与第 1 次一致（解析器只有一份）：%s vs %s" % [index + 1, resolved[index], resolved[0]]
		)

	# B2：四路 dispatch 必须解析到同一 spec_id / 同一池。
	var routes := {
		"room": { "trigger": "kill", "room_reward_plan": { "kill": { "spec_id": "t_same" } }, "context": context },
		"level": { "trigger": "kill", "level_reward_plan": { "kill": { "spec_id": "t_same" } }, "context": context },
		"monster": { "trigger": "kill", "monster_id": "normal_melee", "context": context },
		"default": { "trigger": "kill", "default_pool_id": "loot_common", "context": context },
	}
	var signatures := {}
	var frequencies := {}
	for route_name in routes.keys():
		var request: Dictionary = routes[route_name]
		var resolution := _SERVICE.resolve_dispatch(request)
		_expect(bool(resolution["ok"]), "调度点 %s 应解析成功：%s" % [route_name, str(resolution["errors"])])
		var pools := _grant_pools(resolution["grants"])
		frequencies[route_name] = _sample_frequencies(request, SAMPLES)
		if route_name != "default":
			# room / level / monster 三路都指向 t_same；default 走 default:<pool> 的等价单条池规格。
			_expect(
				str(resolution["spec_id"]) == "t_same",
				"调度点 %s 应解析到 t_same，实际 %s" % [route_name, str(resolution["spec_id"])]
			)
		_expect(
			pools == ["loot_common"],
			"调度点 %s 应产出 loot_common 池成员，实际池=%s" % [route_name, str(pools)]
		)
		# 四路都必须是非空的同一批候选（否则"同源"无从谈起）。
		signatures[route_name] = _candidate_ids(resolution["grants"])
	_expect(signatures.size() == 4, "四个调度点都应产出结果，实际 %d 路" % signatures.size())

	# 分布对拍：四路频率两两在容差内（不同 salt 只改随机流，不改分布）。
	var names: Array = frequencies.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var drift := _max_frequency_drift(frequencies[names[i]], frequencies[names[j]])
			_expect(
				drift <= TOLERANCE * 2.0,
				"调度点 %s 与 %s 的产出分布应一致，最大偏差 %.4f" % [str(names[i]), str(names[j]), drift]
			)
	_SERVICE.set_monster_spec_provider(Callable())


# ---------------------------------------------------------------------------
# 用例 3：覆盖链（房间 > 关卡 > 怪物表 > 全局默认）
# ---------------------------------------------------------------------------

func _case_override_chain() -> void:
	_reset()
	_expect(_SPEC.register_named("t_room", _pool_spec("t_room", "loot_common")), "t_room 登记")
	_expect(_SPEC.register_named("t_level", _pool_spec("t_level", "loot_floor_1_2")), "t_level 登记")
	_expect(_SPEC.register_named("t_monster", _pool_spec("t_monster", "loot_floor_5")), "t_monster 登记")
	_SERVICE.set_monster_spec_provider(func(_m, _t, _l, _f): return _SPEC.get_named("t_monster"))
	var context := { "seed": 99 }

	# ① 房间覆盖关卡
	var r1 := _SERVICE.resolve_dispatch({
		"trigger": "kill",
		"room_reward_plan": { "kill": { "spec_id": "t_room" } },
		"level_reward_plan": { "kill": { "spec_id": "t_level" } },
		"monster_id": "normal_melee",
		"context": context,
	})
	_expect(str(r1["spec_id"]) == "t_room", "房间级应覆盖关卡级，实际取到 %s" % str(r1["spec_id"]))

	# ② 关卡覆盖怪物表
	var r2 := _SERVICE.resolve_dispatch({
		"trigger": "kill",
		"level_reward_plan": { "kill": { "spec_id": "t_level" } },
		"monster_id": "normal_melee",
		"context": context,
	})
	_expect(str(r2["spec_id"]) == "t_level", "关卡级应覆盖怪物表，实际取到 %s" % str(r2["spec_id"]))

	# ③ 怪物表覆盖全局默认
	var r3 := _SERVICE.resolve_dispatch({
		"trigger": "kill",
		"monster_id": "normal_melee",
		"default_pool_id": "scavenge_floor_1",
		"context": context,
	})
	_expect(str(r3["spec_id"]) == "t_monster", "怪物表应覆盖全局默认，实际取到 %s" % str(r3["spec_id"]))

	# ④ 全局默认（无房间/关卡/怪物上下文）
	var r4 := _SERVICE.resolve_dispatch({ "trigger": "search", "default_pool_id": "scavenge_floor_1", "context": context })
	_expect(str(r4["spec_id"]) == "default:scavenge_floor_1", "无覆盖时应落到全局默认，实际 %s" % str(r4["spec_id"]))
	_expect(_grant_pools(r4["grants"]) == ["scavenge_floor_1"], "全局默认应产出 scavenge_floor_1 的成员")

	# ⑤ 触发点必须落在 clear/search/kill 三值内
	var bad := _SERVICE.resolve_dispatch({ "trigger": "level_up", "default_pool_id": "loot_common" })
	_expect(_error_codes(bad).has("INVALID_TRIGGER"), "非法 trigger 应报 INVALID_TRIGGER，实际 %s" % str(_error_codes(bad)))
	_SERVICE.set_monster_spec_provider(Callable())


# ---------------------------------------------------------------------------
# 用例 4：拒绝路径（四个 UNKNOWN_* + INVALID_ENTRY + SPEC_CYCLE）
# ---------------------------------------------------------------------------

func _case_rejection_paths() -> void:
	_reset()
	var before_pools := _POOLS.pool_ids()
	var before_specs := _SPEC.named_spec_ids()

	var cases := [
		["UNKNOWN_ITEM", { "kind": "item", "item_id": "__no_such_item__", "count": 1 }],
		["UNKNOWN_POOL", { "kind": "pool", "pool_id": "__no_such_pool__" }],
		["UNKNOWN_MONSTER", { "kind": "monster", "monster_id": "__no_such_monster__" }],
		["UNKNOWN_CURRENCY", { "kind": "currency", "currency_id": "__no_such_currency__", "amount": 1 }],
		["INVALID_CHANCE", { "kind": "item", "item_id": _first_item_id(), "count": 1, "chance": 1.5 }],
	]
	for entry_case in cases:
		var code := str(entry_case[0])
		var spec := { "spec_id": "t_reject_%s" % [code], "entries": [entry_case[1]] }
		var report := _SERVICE.resolve(spec, { "seed": 1 })
		var codes := _error_codes(report)
		_expect(not bool(report["ok"]), "%s 用例应被拒绝，实际 ok=true" % code)
		_expect(codes.has(code), "%s 用例应报 %s，实际 %s" % [code, code, str(codes)])
		_expect((report["grants"] as Array).is_empty(), "%s 被拒后不得产出任何实体" % code)

	# SPEC_CYCLE：monster 递归深度硬限 1
	var cyclic := {
		"spec_id": "t_cycle",
		"entries": [{ "kind": "monster", "monster_id": _first_monster_id(), "depth": 2 }],
	}
	_expect(_error_codes(_SERVICE.resolve(cyclic, { "seed": 1 })).has("SPEC_CYCLE"), "monster 递归深度超限应报 SPEC_CYCLE")

	# INVALID_ENTRY：entries 缺失
	var missing := _SERVICE.resolve({ "spec_id": "t_missing_entries" }, { "seed": 1 })
	_expect(_error_codes(missing).has("INVALID_ENTRY"), "entries 缺失应报 INVALID_ENTRY")

	# 单层 monster 引用必须合法（硬限是 1，不是 0）
	var single_monster := {
		"spec_id": "t_single_monster",
		"entries": [{ "kind": "monster", "monster_id": _first_monster_id() }],
	}
	var single_codes := _error_codes(_SERVICE.resolve(single_monster, { "seed": 1 }))
	_expect(not single_codes.has("SPEC_CYCLE"), "单层 monster 引用合法，不应报 SPEC_CYCLE：%s" % str(single_codes))
	_expect(not single_codes.has("UNKNOWN_MONSTER"), "怪物表里的 ID 必须可解析：%s" % str(single_codes))

	# 拒绝后状态无变化：登记表与命名规格不得被污染。
	_expect(_POOLS.pool_ids() == before_pools, "拒绝路径不得增删池登记")
	_expect(_SPEC.named_spec_ids() == before_specs, "拒绝路径不得增删命名规格")


# ---------------------------------------------------------------------------
# 用例 5：空池 vs 未知池 —— 分道
# ---------------------------------------------------------------------------

func _case_empty_vs_unknown() -> void:
	_reset()
	# 构造一个 active 但无成员的池：成员资格由物品表决定，故这个池键不在物品表里 ⇒ 成员恒为 0。
	_POOLS.install_overlay("__t_empty_pool__", {
		"name": "测试空池", "usage": "monster", "tier": "any",
		"roll": "weighted", "cap": 1, "status": "active", "migration_target": "",
	})
	_expect(_POOLS.is_active("__t_empty_pool__"), "覆盖层注入的池应被登记表承认")
	_expect(_POOLS.members("__t_empty_pool__").is_empty(), "该测试池必须无成员（成员资格看物品表）")

	# ① 空池 → 走 fallback，且 used_fallback=true
	var with_fallback := {
		"spec_id": "t_empty_fallback",
		"entries": [{ "kind": "pool", "pool_id": "__t_empty_pool__" }],
		"fallback": [{ "kind": "pool", "pool_id": "loot_common" }],
	}
	var r1 := _SERVICE.resolve(with_fallback, { "seed": 5 })
	_expect(bool(r1["ok"]), "空池规格本身合法，应 ok=true：%s" % str(r1["errors"]))
	_expect(bool(r1["used_fallback"]), "空池应触发 fallback")
	_expect(not (r1["grants"] as Array).is_empty(), "fallback 应产出实体")
	_expect(_error_codes(r1).has("EMPTY_POOL"), "空池应记 EMPTY_POOL（不算失败）")

	# ② 未知池 → 整份拒绝，且**不得**回退（与空池分道）
	var unknown_with_fallback := {
		"spec_id": "t_unknown_fallback",
		"entries": [{ "kind": "pool", "pool_id": "__no_such_pool__" }],
		"fallback": [{ "kind": "pool", "pool_id": "loot_common" }],
	}
	var r2 := _SERVICE.resolve(unknown_with_fallback, { "seed": 5 })
	_expect(not bool(r2["ok"]), "未知池应拒绝整份规格")
	_expect(not bool(r2["used_fallback"]), "未知池不得回退 —— 未知 ID 与空池必须分道")
	_expect((r2["grants"] as Array).is_empty(), "未知池被拒后不得产出实体")

	_POOLS.clear_overlays()


# ---------------------------------------------------------------------------
# 用例 6：weighted 分布对账
# ---------------------------------------------------------------------------

func _case_weighted_distribution() -> void:
	_reset()
	var pool_id := "loot_common"
	var spec := _pool_spec("t_weighted", pool_id)
	var members := _POOLS.members(pool_id)
	var total := 0.0
	for member in members:
		total += float(member.get("loot_weight", 0.0))
	_expect(total > 0.0, "测试池 %s 权重和应大于 0" % pool_id)

	var observed := _sample_frequencies({ "trigger": "kill", "default_pool_id": pool_id, "context": {} }, SAMPLES)
	var drawn := 0
	for key in observed.keys():
		drawn += int(observed[key])
	_expect(drawn == SAMPLES, "weighted 池每次必出 1 件，总抽取数应等于样本数 %d，实际 %d" % [SAMPLES, drawn])

	for member in members:
		var item_id := str(member.get("id", ""))
		var expected := float(member.get("loot_weight", 0.0)) / total
		var actual := float(observed.get(item_id, 0)) / float(SAMPLES)
		_expect(
			absf(actual - expected) <= TOLERANCE,
			"池 %s 成员 %s 频率应贴近 w/Σw=%.4f，实测 %.4f" % [pool_id, item_id, expected, actual]
		)


# ---------------------------------------------------------------------------
# 用例 7：independent 数学（含反直觉哨兵）
# ---------------------------------------------------------------------------

func _case_independent_math() -> void:
	_reset()
	# 把 loot_common 覆盖成 independent：所有成员显式声明概率，cap 显式声明。
	var pool_id := "loot_common"
	var chances := {}
	var member_ids: Array[String] = []
	for member in _POOLS.members(pool_id):
		member_ids.append(str(member.get("id", "")))
	# 前两件是业主给的那组反例（0.2 / 0.5），其余给小概率，避免截断干扰。
	for index in range(member_ids.size()):
		if index == 0:
			chances[member_ids[index]] = 0.2
		elif index == 1:
			chances[member_ids[index]] = 0.5
		else:
			chances[member_ids[index]] = 0.05
	_install_independent_pool(pool_id, chances, member_ids.size())

	var spec := {
		"spec_id": "t_independent",
		"entries": [{ "kind": "pool", "pool_id": pool_id, "max_drops": member_ids.size() }],
	}
	var report := _SERVICE.resolve(spec, { "seed": 1 })
	_expect(bool(report["ok"]), "独立池规格应合法：%s" % str(report["errors"]))
	_expect(
		(report["rejected"] as Array).is_empty(),
		"显式声明 max_drops 后不应有任何条目被拒，实际 %s" % str(report["rejected"])
	)

	var fold := _SPEC.fold_chances([0.2, 0.5])
	_expect(
		absf(float(fold["any"]) - 0.6) < 0.0001,
		"反直觉哨兵：p=(0.2,0.5) 的「至少一件」应为 1-0.8*0.5=0.6，实际 %.4f" % float(fold["any"])
	)
	_expect(
		float(fold["any"]) < 0.7 - 0.0001,
		"反直觉哨兵必须成立：1-Π(1-p)=%.4f 严格小于 Σp=0.7" % float(fold["any"])
	)
	_expect(absf(float(fold["none"]) - 0.4) < 0.0001, "空手率应为 0.4，实际 %.4f" % float(fold["none"]))

	# 大样本：逐件频率 → p_i；空手率 → Π(1-p_i)；期望件数 → Σp_i。
	var empty := 0
	var total_drops := 0
	var hits := {}
	for index in range(SAMPLES):
		var result := _SERVICE.resolve(spec, { "seed": 90000 + index })
		var grants: Array = result["grants"]
		if grants.is_empty():
			empty += 1
			continue
		total_drops += grants.size()
		for grant in grants:
			var item_id := str((grant as Dictionary).get("item_id", ""))
			hits[item_id] = int(hits.get(item_id, 0)) + 1

	for item_id in chances.keys():
		var expected_p := float(chances[item_id])
		var actual_p := float(hits.get(item_id, 0)) / float(SAMPLES)
		_expect(
			absf(actual_p - expected_p) <= TOLERANCE,
			"独立池成员 %s 实测频率 %.4f 应贴近 p=%.4f" % [item_id, actual_p, expected_p]
		)

	var expected_empty := 1.0
	var expected_sum := 0.0
	for item_id in chances.keys():
		expected_empty *= (1.0 - float(chances[item_id]))
		expected_sum += float(chances[item_id])
	var actual_empty := float(empty) / float(SAMPLES)
	var actual_sum := float(total_drops) / float(SAMPLES)
	_expect(
		absf(actual_empty - expected_empty) <= TOLERANCE,
		"空手率实测 %.4f 应收敛到 Π(1-p)=%.4f" % [actual_empty, expected_empty]
	)
	_expect(
		absf(actual_sum - expected_sum) <= TOLERANCE * 2.0,
		"期望件数实测 %.4f 应收敛到 Σp=%.4f" % [actual_sum, expected_sum]
	)
	_POOLS.clear_overlays()


# ---------------------------------------------------------------------------
# 用例 8：截断（max_drops）可复现且如实报告
# ---------------------------------------------------------------------------

func _case_truncation() -> void:
	_reset()
	# 全 1.0 的独立池：必然全中；cap 设为 2 ⇒ 必须截断且 truncated=true。
	var pool_id := "loot_common"
	var chances := {}
	var member_ids: Array[String] = []
	for member in _POOLS.members(pool_id):
		member_ids.append(str(member.get("id", "")))
		chances[str(member.get("id", ""))] = 1.0
	_expect(member_ids.size() > 2, "用于截断用例的池成员数应大于 2，实际 %d" % member_ids.size())
	_install_independent_pool(pool_id, chances, 2)

	var spec := {
		"spec_id": "t_truncate",
		"entries": [{ "kind": "pool", "pool_id": pool_id, "max_drops": 2 }],
	}
	var first := _SERVICE.resolve(spec, { "seed": 31415 })
	_expect(bool(first["ok"]), "截断用例规格应合法：%s" % str(first["errors"]))
	_expect(bool(first["truncated"]), "命中数超过 max_drops 时应记 truncated=true")
	_expect(
		(first["grants"] as Array).size() == 2,
		"截断后件数应恰为 max_drops=2，实际 %d" % (first["grants"] as Array).size()
	)
	_expect(_error_codes(first).has("DROPS_TRUNCATED"), "截断应记 DROPS_TRUNCATED")

	var second := _SERVICE.resolve(spec, { "seed": 31415 })
	_expect(
		_signature(first["grants"]) == _signature(second["grants"]),
		"截断结果必须可复现：%s vs %s" % [_signature(first["grants"]), _signature(second["grants"])]
	)

	# 池声明多件而条目未显式确认 ⇒ SINGLE_DROP_CONFLICT 拒绝（04 §22.10，不静默截断）
	var undeclared := {
		"spec_id": "t_conflict",
		"entries": [{ "kind": "pool", "pool_id": pool_id }],
	}
	var third := _SERVICE.resolve(undeclared, { "seed": 31415 })
	var third_codes := _error_codes(third)
	_expect(
		third_codes.has("SINGLE_DROP_CONFLICT"),
		"池上限 2 而条目未声明 max_drops 应报 SINGLE_DROP_CONFLICT，实际 %s" % str(third_codes)
	)
	_expect(
		(third["grants"] as Array).is_empty(),
		"冲突时不得静默截断出 1 件，必须整条不出：实际 %d 件" % (third["grants"] as Array).size()
	)
	_POOLS.clear_overlays()


# ---------------------------------------------------------------------------
# 用例 9：Roll 字段互斥
# ---------------------------------------------------------------------------

func _case_field_conflict() -> void:
	_reset()
	# ① weighted 池里有成员声明 chance ⇒ MIXED_ROLL_FIELDS
	var weighted := _POOLS.get_pool("loot_common")
	var first_id := ""
	for member in _POOLS.members("loot_common"):
		first_id = str(member.get("id", ""))
		break
	weighted["member_chances"] = { first_id: 0.5 }
	_POOLS.install_overlay("loot_common", weighted)
	_expect(
		_POOLS.roll_field_conflict("loot_common") == _POOLS.CONFLICT_MIXED_ROLL_FIELDS,
		"weighted 池成员出现 chance 应报 MIXED_ROLL_FIELDS，实际 %s" % _POOLS.roll_field_conflict("loot_common")
	)
	var mixed := _SERVICE.resolve(_pool_spec("t_mixed", "loot_common"), { "seed": 1 })
	_expect(_error_codes(mixed).has("MIXED_ROLL_FIELDS"), "混用字段应整池拒绝，实际 %s" % str(_error_codes(mixed)))
	_POOLS.clear_overlays()

	# ② independent 池有成员没声明 chance ⇒ INVALID_CHANCE
	var independent := _POOLS.get_pool("loot_common")
	independent["roll"] = "independent"
	independent["cap"] = 1
	independent["member_chances"] = { first_id: 0.5 }  # 只声明一件，其余缺失
	_POOLS.install_overlay("loot_common", independent)
	_expect(
		_POOLS.roll_field_conflict("loot_common") == _POOLS.CONFLICT_INVALID_CHANCE,
		"independent 池成员缺 chance 应报 INVALID_CHANCE，实际 %s" % _POOLS.roll_field_conflict("loot_common")
	)
	_POOLS.clear_overlays()

	# ③ independent 池未显式声明 cap ⇒ MISSING_MAX_DROPS（缺省补的 1 不算"声明过"）
	var no_cap := _POOLS.get_pool("loot_common")
	no_cap["roll"] = "independent"
	no_cap.erase("cap")
	var all_chances := {}
	for member in _POOLS.members("loot_common"):
		all_chances[str(member.get("id", ""))] = 0.3
	no_cap["member_chances"] = all_chances
	_POOLS.install_overlay("loot_common", no_cap)
	_expect(not _POOLS.has_declared_cap("loot_common"), "覆盖层删掉 cap 后 has_declared_cap 应为 false")
	var missing_cap := _SERVICE.resolve(_pool_spec("t_missing_cap", "loot_common"), { "seed": 1 })
	_expect(
		_error_codes(missing_cap).has("MISSING_MAX_DROPS"),
		"independent 池未声明 cap 应报 MISSING_MAX_DROPS，实际 %s" % str(_error_codes(missing_cap))
	)
	_POOLS.clear_overlays()

	# ④ 弃用池不得被新内容引用
	var deprecated_reject := false
	for pool_id in _POOLS.pool_ids():
		if not _POOLS.is_active(pool_id):
			var report := _SERVICE.resolve(_pool_spec("t_deprecated", pool_id), { "seed": 1 })
			deprecated_reject = _error_codes(report).has("POOL_DEPRECATED")
			break
	_expect(deprecated_reject, "引用弃用池应报 POOL_DEPRECATED")


# ---------------------------------------------------------------------------
# 用例 10：反向对照（三组，必须精准变红后还原）
# ---------------------------------------------------------------------------

func _case_negative_controls() -> void:
	_reset()

	# ① 池权重全 0 ⇒ EMPTY_WEIGHT
	var zeroed := _POOLS.get_pool("loot_common")
	var weights := {}
	for member in _POOLS.members("loot_common"):
		weights[str(member.get("id", ""))] = 0.0
	zeroed["member_weights"] = weights
	_POOLS.install_overlay("loot_common", zeroed)
	var baseline := _SERVICE.resolve(_pool_spec("t_weight_zero", "loot_common"), { "seed": 2 })
	_expect(
		_error_codes(baseline).has("EMPTY_WEIGHT"),
		"池权重全 0 应报 EMPTY_WEIGHT，实际 %s" % str(_error_codes(baseline))
	)
	_expect((baseline["grants"] as Array).is_empty(), "权重全 0 时不得产出实体")
	_POOLS.clear_overlays()
	var restored := _SERVICE.resolve(_pool_spec("t_weight_restore", "loot_common"), { "seed": 2 })
	_expect((restored["grants"] as Array).size() == 1, "清除覆盖层后应恢复正常出 1 件")
	_expect(not _error_codes(restored).has("EMPTY_WEIGHT"), "还原后不得残留 EMPTY_WEIGHT")

	# ② spec 指向未登记池 ⇒ UNKNOWN_POOL（精准变红）
	var unknown := _SERVICE.resolve(_pool_spec("t_unknown", "__ghost_pool__"), { "seed": 2 })
	_expect(_error_codes(unknown).has("UNKNOWN_POOL"), "未登记池应报 UNKNOWN_POOL")
	var known := _SERVICE.resolve(_pool_spec("t_known", "loot_common"), { "seed": 2 })
	_expect(not _error_codes(known).has("UNKNOWN_POOL"), "换成已登记池后不得再报 UNKNOWN_POOL")

	# ③ 覆盖链顺序颠倒 ⇒ 必须表现为 room 优先（断言不是 level 优先）
	_expect(_SPEC.register_named("nc_room", _pool_spec("nc_room", "loot_common")), "nc_room 登记")
	_expect(_SPEC.register_named("nc_level", _pool_spec("nc_level", "loot_floor_5")), "nc_level 登记")
	var ordered := _SERVICE.resolve_dispatch({
		"trigger": "clear",
		"room_reward_plan": { "clear": { "spec_id": "nc_room" } },
		"level_reward_plan": { "clear": { "spec_id": "nc_level" } },
		"context": { "seed": 3 },
	})
	_expect(
		str(ordered["spec_id"]) == "nc_room",
		"覆盖链顺序若被颠倒会取到 nc_level；正确结果必须为 nc_room，实际 %s" % str(ordered["spec_id"])
	)
	# 反向：抽掉房间级后必须立刻落到关卡级（证明这一层真的在读，不是恒返回 room）
	var level_only := _SERVICE.resolve_dispatch({
		"trigger": "clear",
		"level_reward_plan": { "clear": { "spec_id": "nc_level" } },
		"context": { "seed": 3 },
	})
	_expect(
		str(level_only["spec_id"]) == "nc_level",
		"移除房间级后应落到关卡级，实际 %s" % str(level_only["spec_id"])
	)

	# ④ 未登记 spec_id 必须拒绝且不回退到别级（覆盖链的失败语义）
	var dangling := _SERVICE.resolve_dispatch({
		"trigger": "clear",
		"room_reward_plan": { "clear": { "spec_id": "__no_such_spec__" } },
		"level_reward_plan": { "clear": { "spec_id": "nc_level" } },
		"context": { "seed": 3 },
	})
	_expect(not bool(dangling["ok"]), "未登记 spec_id 应拒绝")
	_expect(
		_error_codes(dangling).has("UNKNOWN_SPEC"),
		"未登记 spec_id 应报 UNKNOWN_SPEC（不静默回退到关卡级），实际 %s" % str(_error_codes(dangling))
	)


# ---------------------------------------------------------------------------
# 断言与工具
# ---------------------------------------------------------------------------

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _reset() -> void:
	_POOLS.clear_overlays()
	_SPEC.clear_named()
	_SERVICE.set_monster_spec_provider(Callable())


func _pool_spec(spec_id: String, pool_id: String) -> Dictionary:
	return { "spec_id": spec_id, "entries": [{ "kind": "pool", "pool_id": pool_id }] }


## 覆盖 loot_common 为 independent 池；cap 必填（04 §22.8 的 MISSING_MAX_DROPS）。
func _install_independent_pool(pool_id: String, chances: Dictionary, cap: int) -> void:
	var info := _POOLS.get_pool(pool_id)
	info["roll"] = _POOLS.ROLL_INDEPENDENT
	info["cap"] = cap
	info["member_chances"] = chances
	_POOLS.install_overlay(pool_id, info)


## 按 dispatch 请求跑 n 次（每次换 seed），返回 {item_id: 出现次数}。
func _sample_frequencies(request: Dictionary, n: int) -> Dictionary:
	var counts := {}
	for index in range(n):
		var req := request.duplicate(true)
		var context: Dictionary = req.get("context", {})
		context["seed"] = 700000 + index
		req["context"] = context
		var resolution := _SERVICE.resolve_dispatch(req)
		for grant in resolution["grants"]:
			var item_id := str((grant as Dictionary).get("item_id", ""))
			counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts


func _max_frequency_drift(a: Dictionary, b: Dictionary) -> float:
	var keys := {}
	for key in a.keys():
		keys[key] = true
	for key in b.keys():
		keys[key] = true
	var worst := 0.0
	var total := float(SAMPLES)
	for key in keys.keys():
		var drift := absf(float(a.get(key, 0)) - float(b.get(key, 0))) / total
		if drift > worst:
			worst = drift
	return worst


func _signature(grants: Array) -> String:
	var parts: Array[String] = []
	for grant in grants:
		var g: Dictionary = grant
		parts.append("%s|%s|%s|%s|%d" % [
			str(g.get("kind", "")),
			str(g.get("item_id", "")),
			str(g.get("currency_id", "")),
			str(g.get("pool_id", "")),
			int(g.get("count", 0)),
		])
	return " + ".join(parts)


## 只比"出了什么"，不比数量：用于跨调度点对拍（salt 不影响分布，但可能影响抽取的具体项）。
func _candidate_ids(grants: Array) -> String:
	var ids: Array[String] = []
	for grant in grants:
		ids.append(str((grant as Dictionary).get("item_id", "")))
	ids.sort()
	return ",".join(ids)


func _grant_pools(grants: Array) -> Array[String]:
	var seen: Dictionary = {}
	for grant in grants:
		var pool_id := str((grant as Dictionary).get("pool_id", ""))
		if not pool_id.is_empty():
			seen[pool_id] = true
	var out: Array[String] = []
	for key in seen.keys():
		out.append(str(key))
	out.sort()
	return out


func _error_codes(report: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for error in report.get("errors", []):
		out.append(str((error as Dictionary).get("code", "")))
	for rejected in report.get("rejected", []):
		out.append(str((rejected as Dictionary).get("code", "")))
	return out


func _first_item_id() -> String:
	return str(ItemRegistry.get_instance().get_all_items()[0].get("id", ""))


func _first_monster_id() -> String:
	var ids := _SPEC.known_monster_ids()
	return ids[0] if not ids.is_empty() else ""
