extends Node
## 远征03「商店房 + 统一金币」实测探针（2026-10-30）。
##
## 回答两个只有实测能答的问题：
##   ① **商店房到底是不是商店房？** 每张 flow 的 `SHOP` 节点，运行时拿到的
##      `room_type` 必须真的是 `MERCHANT` —— 否则 `DungeonRoom3D._build_detail()`
##      里那句 `if room_type in ["MERCHANT","UPGRADE","EVENT"]` 不成立，服务点不建、
##      商人 UI 永远打不开（症状是"房间在、人进得去、什么都没有"，且**没有任何报错**）。
##   ② **统一金币之后一层到底多少钱？** 按 `RuntimeRewardCoordinator.resolve_kill()`
##      逐只跑，再按六张 flow 的真实怪数加权，得到"清一层的金币收益"，
##      与原作一层的量级（社区统计 ≈59，非官方）比对。
##
## 用法：godot --headless --path . --scene res://tools/_egt_shop_currency_probe.tscn
## ⚠ 必须 `--scene`：要编译 FloorPlanGenerator / RuntimeRewardCoordinator，它们依赖 autoload。

const LEVEL_ID := "expedition_03"
const SEEDS := [1, 2, 3, 7, 11, 42]
const PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"
const COORD := preload("res://src/rewards/RuntimeRewardCoordinator.gd")

## 原作一层金币收益量级（社区统计，非官方）。见
## `docs/v0.1/reference/挺进地牢/普通怪掉落.md` §2「总量参照」。
const EGT_FLOOR_SHELLS := 59.0
## 允许的偏离比例。原作数字本身是"大概 59"，给 ±30% 的宽松带 ——
## 这条判据只防止"数量级错"（比如每只 3 枚那种 2.7 倍通胀），不追求逐枚吻合。
const TOLERANCE := 0.30

const SELF_DESTRUCT := [
	"egt_pinhead", "egt_nitra", "egt_bullat", "egt_shotgat", "egt_grenat", "egt_spirat",
]
const SPECIAL_DROP := ["egt_keybullet_kin", "egt_chance_kin"]

var _failures: Array[String] = []
var _coord: RuntimeRewardCoordinator


func _ready() -> void:
	print("=== EGT_SHOP_CURRENCY_PROBE ===")
	_probe_shop_rooms()
	_probe_currency()
	_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


# ---------------------------------------------------------------------------
# ① 商店房
# ---------------------------------------------------------------------------

func _probe_shop_rooms() -> void:
	print("\n--- 商店房（每张 flow 必须有且只有 1 间，且 room_type == MERCHANT）---")
	var seen_flows := {}
	for seed_value in SEEDS:
		var plan := FloorPlanGenerator.generate_from_level_plan(LEVEL_ID, 0, seed_value)
		if plan.is_empty():
			_failures.append("种子 %d：生成失败（返回空）" % seed_value)
			continue
		var flow_id := str(plan.get("layout_variant", "?"))
		if seen_flows.has(flow_id):
			continue
		seen_flows[flow_id] = true

		var merchant_rooms: Array[Dictionary] = []
		for value in plan.get("rooms", []):
			var room := value as Dictionary
			if str(room.get("type", "")) == "MERCHANT":
				merchant_rooms.append(room)
		var shop_keys: Array[String] = []
		for value in plan.get("rooms", []):
			var room := value as Dictionary
			var key := str(room.get("key", ""))
			if key.begins_with("shop"):
				shop_keys.append(key)

		print("  %-8s 种子 %-3d  房间 %2d  商店键 %s  MERCHANT 房 %d"
			% [flow_id, seed_value, (plan.get("rooms", []) as Array).size(),
			   str(shop_keys), merchant_rooms.size()])

		if shop_keys.is_empty():
			_failures.append("%s：骨架里没有 SHOP 节点（原作一层必有商店）" % flow_id)
			continue
		if merchant_rooms.is_empty():
			_failures.append(
				"%s：有 SHOP 节点 %s，但没有任何房间的 room_type 是 MERCHANT —— 商人链路断在生成期"
				% [flow_id, str(shop_keys)]
			)
			continue
		if merchant_rooms.size() > 1:
			_failures.append("%s：出现 %d 间 MERCHANT 房（应为 1）" % [flow_id, merchant_rooms.size()])

		var shop := merchant_rooms[0]
		# 商店是 enemyless 房（EGT：单门死路，不封门、不刷怪）。
		if not bool(shop.get("authored_layout_peaceful", false)):
			_failures.append("%s：MERCHANT 房不是和平区（会被封门打一波）" % flow_id)
		if not (shop.get("spawn_placements", []) as Array).is_empty():
			_failures.append("%s：MERCHANT 房带了刷怪编成（商店里不该有怪）" % flow_id)
		if not (shop.get("chest_placements", []) as Array).is_empty():
			_failures.append("%s：MERCHANT 房带了宝箱（商店不是宝箱房）" % flow_id)


# ---------------------------------------------------------------------------
# ② 统一金币
# ---------------------------------------------------------------------------

func _probe_currency() -> void:
	print("\n--- 金币产出（`monster_rules.currency`，期望：非自爆 1 枚 / 自爆 0 / 精英 70 / Boss 220）---")
	var plan := _load_plan()
	if plan.is_empty():
		return
	_coord = COORD.new()
	_coord.configure(20261030)
	_coord.configure_level_drop_table(LEVEL_ID, plan.get("monster_drop_table", {}) as Dictionary)
	_coord.configure_level_currency(
		(plan.get("monster_rules", {}) as Dictionary).get("currency", {}) as Dictionary
	)

	var injector := preload("res://src/map/MonsterInjector.gd")
	var kinds: Array[String] = []
	for kind in injector.BASE_ENEMY_TYPES.keys():
		if str(kind).begins_with("egt_"):
			kinds.append(str(kind))
	kinds.sort()

	var sample_total := 0.0
	var sample_count := 0
	for kind in kinds:
		var got := _sample_amount(kind, "normal")
		# 1~2 枚的期望是 1.5。给 ±0.12 的带宽吸收抽样噪声（4000 次的标准差约 0.01）。
		var expect := 0.0 if SELF_DESTRUCT.has(kind) else 1.5
		var gold_note := "自爆怪·不掉" if SELF_DESTRUCT.has(kind) else "1~2 枚"
		if SPECIAL_DROP.has(kind):
			gold_note = "招牌掉落 + 1~2 枚"
		print("  %-24s %.2f 枚  %s" % [kind, got, gold_note])
		if absf(got - expect) > 0.12:
			_failures.append("%s 掉 %.2f 枚金币（期望 %.1f）" % [kind, got, expect])
		if not SELF_DESTRUCT.has(kind):
			sample_total += got
			sample_count += 1

	# 精英 / Boss 必须仍走 `per_tier`。**这是最容易被 default 误伤的两位**：
	# 缺少 per_tier 时它们会一起掉进 default 的 1 枚（Boss 从 220 掉到 1）。
	var elite := _sample_amount("egt_bullet_kin", "elite")
	var boss := _sample_amount("boss", "boss")
	print("  %-24s %.2f 枚  （per_tier.elite，期望 70 = 50+20×1）" % ["<elite 强化变种>", elite])
	print("  %-24s %.2f 枚  （per_tier.boss，期望 220 = 200+20×1）" % ["<boss>", boss])
	if absf(elite - 70.0) > 0.001:
		_failures.append("精英变种掉 %.2f 枚（期望 70 —— per_tier 没生效？）" % elite)
	if absf(boss - 220.0) > 0.001:
		_failures.append("Boss 掉 %.2f 枚（期望 220 —— per_tier 没生效？）" % boss)

	_verify_floor_total(kinds)


## 跑 2000 次取平均。货币是 100% 必掉，但**金额是 1~2 枚区间**（`{min,max}` 分档），
## 所以这里必须多跑几次取均值 —— 跑 1 次只会看到 1 或 2。
##
## ⚠ `tier` 不能靠传 `monster_tier` 字符串：`RuntimeRewardCoordinator.resolve_kill()`
## 判档位读的是 `enemy_data.is_boss` / `enemy_data.is_elite` 两个布尔，
## 传错字段会让精英与 Boss 都被当成 normal（实测：两者都掉 1~2 枚而不是 70 / 220）。
func _sample_amount(monster_id: String, tier: String) -> float:
	var data := {
		"enemy_type": monster_id,
		"floor": 1,
		"loot_table": "loot_floor_1_2",
	}
	if tier == "elite":
		data["is_elite"] = true
	elif tier == "boss":
		data["is_boss"] = true
	var total := 0
	var runs := 4000
	for index in range(runs):
		var report := _coord.resolve_kill({}, data, "probe:%s:%s:%d" % [monster_id, tier, index])
		for value in report.get("grants", []):
			var grant := value as Dictionary
			if str(grant.get("kind", "")) == "currency":
				total += int(grant.get("amount", 0))
	return float(total) / float(runs)


## 一层总收益 = Σ(每只怪的金币期望) over 该层实际怪数。
##
## 怪数按六张 flow 的真实编成统计（`by_node` 优先、`by_kind` 兜底）。
## 自爆怪按原作掉 0，但仍占"怪数"一格 —— 这正是「统一 1~2 枚」而不是
## 「统一 2 枚」的原因：它们在我们编成里占 25%，把那 25% 的缺口算进去之后
## 均值才落在原作量级上。
const CURRENCY_EXPECT_PER_KILL := 1.5

func _verify_floor_total(_kinds: Array[String]) -> void:
	print("\n--- 一层金币总量（六张 flow 逐张算，与 EGT ≈%.0f 比对，容差 ±%.0f%%）---"
		% [EGT_FLOOR_SHELLS, TOLERANCE * 100.0])
	var plan := _load_plan()
	var totals: Array[float] = []
	for flow_path in [
		"res://data/level_plans/expedition_03/flows/flow_01.json",
		"res://data/level_plans/expedition_03/flows/flow_02.json",
		"res://data/level_plans/expedition_03/flows/flow_03.json",
		"res://data/level_plans/expedition_03/flows/flow_04.json",
		"res://data/level_plans/expedition_03/flows/flow_05.json",
		"res://data/level_plans/expedition_03/flows/flow_06.json",
	]:
		var flow := _load_json(flow_path)
		if flow.is_empty():
			continue
		var roster: Dictionary = plan.get("spawn_roster", {}) as Dictionary
		var by_node: Dictionary = roster.get("by_node", {}) as Dictionary
		var by_kind: Dictionary = roster.get("by_kind", {}) as Dictionary
		var total := 0.0
		var monsters := 0
		for node_value in flow.get("nodes", []):
			var node := node_value as Dictionary
			var node_id := str(node.get("node_id", ""))
			var kind := str(node.get("kind", ""))
			var record: Dictionary = by_node.get(node_id, {}) as Dictionary
			if record.is_empty():
				record = by_kind.get(kind, {}) as Dictionary
			if record.is_empty():
				continue
			for box_value in record.get("boxes", []):
				var box := _load_json("res://data/spawn_boxes/%s.json" % str(box_value))
				for spawn_value in box.get("spawns", []):
					var spawn := spawn_value as Dictionary
					var count := int(spawn.get("count", 1))
					monsters += count
					if SELF_DESTRUCT.has(str(spawn.get("type", ""))):
						continue
					total += float(count) * CURRENCY_EXPECT_PER_KILL
		var flow_id := str(flow.get("flow_id", "?"))
		totals.append(total)
		print("  %-8s 怪 %2d 只  →  %5.1f 枚" % [flow_id, monsters, total])

	if totals.is_empty():
		_failures.append("没有任何 flow 可统计")
		return
	var sum := 0.0
	for value in totals:
		sum += value
	var avg := sum / float(totals.size())
	print("  均值 %.1f 枚（原作 ≈%.0f）  偏差 %+.1f%%"
		% [avg, EGT_FLOOR_SHELLS, (avg - EGT_FLOOR_SHELLS) / EGT_FLOOR_SHELLS * 100.0])
	var low := EGT_FLOOR_SHELLS * (1.0 - TOLERANCE)
	var high := EGT_FLOOR_SHELLS * (1.0 + TOLERANCE)
	for index in range(totals.size()):
		if totals[index] < low or totals[index] > high:
			_failures.append(
				"某张 flow 的一层金币 %.0f 枚 偏离原作 ≈%.0f 超过 ±%.0f%%"
				% [totals[index], EGT_FLOOR_SHELLS, TOLERANCE * 100.0]
			)
	if avg < low or avg > high:
		_failures.append("一层金币均值 %.1f 偏离原作 ≈%.0f 超过 ±%.0f%%"
			% [avg, EGT_FLOOR_SHELLS, TOLERANCE * 100.0])


# ---------------------------------------------------------------------------

func _load_plan() -> Dictionary:
	return _load_json(PLAN_PATH)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("无法打开 %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _report() -> void:
	if _failures.is_empty():
		print("\nEGT_SHOP_CURRENCY_PROBE_OK 商店房可识别 · 金币统一口径落地")
		return
	print("\nEGT_SHOP_CURRENCY_PROBE_FAIL 共 %d 项：" % _failures.size())
	for line in _failures:
		print("  - ", line)
