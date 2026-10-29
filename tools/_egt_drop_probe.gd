extends Node
## 远征03 掉落实测探针。
##
## 回答一个只有实测能答的问题：**这 33 只 EGT 复刻怪打死后到底掉什么、掉多少。**
## 读代码只能看到"走哪条覆盖链"，看不到「26% × 池子权重 × 空掉落」叠加后的真实产出。
##
## 做法：直接调 `RuntimeRewardCoordinator.resolve_kill()` 跑 N 次，
## 统计「空手率 / 物品率 / 每件是什么 / 弹药率 / 货币率与均值」。
## 不生成实体、不进场景树 —— 与运行时同一条解析链路。

const COORD := preload("res://src/rewards/RuntimeRewardCoordinator.gd")
const INJECTOR := preload("res://src/map/MonsterInjector.gd")
const GEN := preload("res://src/map/FloorPlanGenerator.gd")
const PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"

const SAMPLES := 4000
const CONTROL := "melee_chaser"

var _coord: RuntimeRewardCoordinator


func _ready() -> void:
	_coord = COORD.new()
	_coord.configure(12345)

	var plan := _load_plan()
	var table: Dictionary = plan.get("monster_drop_table", {}) as Dictionary
	var table_report := _coord.configure_level_drop_table("expedition_03", table)
	# 货币分档必须一起装 —— 不装的话每只怪都"只掉金币"却一个金币都不掉，
	# 探针会误判成"掉落全空了"。
	var currency_rules: Dictionary = (plan.get("monster_rules", {}) as Dictionary).get("currency", {}) as Dictionary
	_coord.configure_level_currency(currency_rules)

	print("=".repeat(72))
	print("远征03 掉落实测（每只 %d 次击杀）" % SAMPLES)
	print("  monster_drop_table 存在=%s  rows=%d  empty_chance=%.2f"
		% [not table.is_empty(), int(table_report.get("row_count", 0)),
		   float(table.get("empty_chance", 0.0))])
	print("  monster_rules.currency 配置=%s"
		% (not (plan.get("monster_rules", {}) as Dictionary).get("currency", {}).is_empty()))
	print("=".repeat(72))

	var kinds: Array[String] = []
	for kind in INJECTOR.BASE_ENEMY_TYPES.keys():
		if str(kind).begins_with("egt_"):
			kinds.append(str(kind))
	kinds.sort()

	var summary: Array[Dictionary] = []
	for kind in kinds:
		summary.append(_sample(kind))
	summary.append(_sample(CONTROL))

	_print_table(summary)
	_verify(summary)
	_verify_clear_rewards(plan)
	_verify_legacy_default()
	get_tree().quit(0)


func _load_plan() -> Dictionary:
	var file := FileAccess.open(PLAN_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开 %s" % PLAN_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


## 跑 N 次击杀，汇总一条。
func _sample(kind: String) -> Dictionary:
	var data := {
		"enemy_type": kind,
		"floor": 1,
		"loot_table": "loot_floor_1_2",
	}
	var item_hits := 0
	var ammo_hits := 0
	var currency_hits := 0
	var currency_total := 0
	var item_counts: Dictionary = {}
	var empty_hits := 0

	for index in range(SAMPLES):
		var report := _coord.resolve_kill({}, data, "probe:%s:%d" % [kind, index])
		var grants: Array = report.get("grants", []) as Array
		var has_item := false
		var has_ammo := false
		var has_currency := false
		for value in grants:
			var grant := value as Dictionary
			var gid := str(grant.get("item_id", grant.get("currency_id", "")))
			match str(grant.get("kind", "")):
				"currency":
					has_currency = true
					currency_total += int(grant.get("amount", 0))
				"item":
					if gid == "item_ammo_pack":
						has_ammo = true
					else:
						has_item = true
						item_counts[gid] = int(item_counts.get(gid, 0)) + 1
				_:
					has_item = true
					item_counts[gid] = int(item_counts.get(gid, 0)) + 1
		if has_item:
			item_hits += 1
		if has_ammo:
			ammo_hits += 1
		if has_currency:
			currency_hits += 1
		if not has_item and not has_ammo and not has_currency:
			empty_hits += 1

	var top: Array = []
	for gid in item_counts.keys():
		top.append({"id": gid, "rate": float(item_counts[gid]) / float(SAMPLES)})
	top.sort_custom(func(a, b): return float(a["rate"]) > float(b["rate"]))

	return {
		"kind": kind,
		"item_rate": float(item_hits) / float(SAMPLES),
		"ammo_rate": float(ammo_hits) / float(SAMPLES),
		"currency_rate": float(currency_hits) / float(SAMPLES),
		"currency_avg": float(currency_total) / float(SAMPLES),
		"empty_rate": float(empty_hits) / float(SAMPLES),
		"top_items": top.slice(0, 4),
	}


func _print_table(rows: Array[Dictionary]) -> void:
	print("%-24s %8s %8s %8s %8s %9s  %s"
		% ["怪种", "物品率", "弹药率", "货币率", "空手率", "均币", "最常掉"])
	for row in rows:
		var top_parts: Array[String] = []
		for value in row["top_items"]:
			var item := value as Dictionary
			top_parts.append("%s %.1f%%" % [item["id"], float(item["rate"]) * 100.0])
		print("%-24s %7.1f%% %7.1f%% %7.1f%% %7.1f%% %9.2f  %s"
			% [
				row["kind"], float(row["item_rate"]) * 100.0, float(row["ammo_rate"]) * 100.0,
				float(row["currency_rate"]) * 100.0, float(row["empty_rate"]) * 100.0,
				float(row["currency_avg"]), ", ".join(top_parts),
			])


## 与 EGT 原作结构逐条比对（原作事实见 docs/v0.1/reference/挺进地牢/普通怪掉落.md）。
##
## **判据分两层，因为「对齐」在这个字段上有两种含义**：
##   · 原作规则（不可妥协）：普通怪不掉装备 / 逐只不掉弹药 / 自爆怪什么都不掉。
##   · 本工程裁定（业主 2026-10-14）：货币是**独立通道、100% 必掉**，不算物品。
##     这条与「原作金币是概率掉」不同，属于项目内已裁定的口径，探针按裁定判。
const SELF_DESTRUCT := [
	"egt_pinhead", "egt_nitra", "egt_bullat", "egt_shotgat", "egt_grenat", "egt_spirat",
]
const SPECIAL_DROP := ["egt_keybullet_kin", "egt_chance_kin"]

func _verify(rows: Array[Dictionary]) -> void:
	var failures: Array[String] = []
	for row in rows:
		var kind := str(row["kind"])
		var is_self_destruct := SELF_DESTRUCT.has(kind)
		var is_special := SPECIAL_DROP.has(kind)
		# ① 原作：普通怪**不掉装备**（装备只来自宝箱 / 商店 / Boss）。
		#    唯一的例外是 Chance Kin —— 原作明写「drop a random pickup upon death」。
		if not is_special and float(row["item_rate"]) > 0.0:
			failures.append("%s 掉了物品 %.1f%%（原作普通怪不掉物品）"
				% [kind, float(row["item_rate"]) * 100.0])
		# ② 原作：弹药是**清房 6% 判定**，不是每只怪掉。
		#    Chance Kin 掉到弹药是它那个随机拾取物抽到了弹药，不算违规。
		if not is_special and float(row["ammo_rate"]) > 0.0:
			failures.append("%s 逐只掉弹药 %.1f%%（原作：清房 6%%，非逐只）"
				% [kind, float(row["ammo_rate"]) * 100.0])
		# ③ 原作：「自爆的敌人不掉铸币」。
		if is_self_destruct and float(row["currency_rate"]) > 0.0:
			failures.append("%s 自爆怪掉了 %.1f%% 货币（原作：self-destruct 不掉）"
				% [kind, float(row["currency_rate"]) * 100.0])
		# ④ 本工程裁定：非自爆怪 100% 必掉货币（独立通道）。
		if not is_self_destruct and float(row["currency_rate"]) < 0.999:
			failures.append("%s 货币必掉率只有 %.1f%%（本工程裁定 100%%）"
				% [kind, float(row["currency_rate"]) * 100.0])
		# ⑤ 两只逃跑怪的招牌掉落必须垄断各自的那一格。
		if kind == "egt_keybullet_kin":
			var top := (row["top_items"] as Array)
			var ok := not top.is_empty() and str((top[0] as Dictionary)["id"]) == "item_room_key"
			if not ok or float(row["item_rate"]) < 0.999:
				failures.append("钥匙小子没有 100%% 掉钥匙（实际 %.1f%%）"
					% (float(row["item_rate"]) * 100.0))
		if kind == "egt_chance_kin":
			if float(row["item_rate"]) + float(row["ammo_rate"]) < 0.999:
				failures.append("运气小子没有 100%% 掉随机拾取物（物品 %.1f%% + 弹药 %.1f%%）"
					% [float(row["item_rate"]) * 100.0, float(row["ammo_rate"]) * 100.0])

	if failures.is_empty():
		print("\nEGT_DROP_PROBE_OK 33 只普通怪掉落结构与原作对齐")
		return
	print("\nEGT_DROP_PROBE_FAIL 共 %d 项不符：" % failures.size())
	for line in failures:
		print("  - ", line)


## 清房结算：原作两个独立判定（20% 拾取物 / 6% 弹药），挂在「房间清空」上。
func _verify_clear_rewards(plan: Dictionary) -> void:
	var cfg: Dictionary = plan.get("clear_rewards", {}) as Dictionary
	print("\n--- 清房结算（`clear_rewards` → `reward_plan.clear`）---")
	if cfg.is_empty():
		print("EGT_DROP_PROBE_FAIL 未配置 clear_rewards")
		return
	var failures: Array[String] = []

	# 和平区不该结算：走廊 / 入口 / 撤离 / 商店 / 宝箱房都不进战斗清房流程。
	for kind in ["SHOP", "REWARD", "ENTRANCE", "EXIT", "CONNECTOR"]:
		var empty_spec: Dictionary = GEN._clear_reward_spec_for(kind, cfg)
		if not empty_spec.is_empty():
			failures.append("%s 房也配到了清房结算（和平区不该有）" % kind)

	var spec: Dictionary = GEN._clear_reward_spec_for("NORMAL", cfg)
	if spec.is_empty():
		print("EGT_DROP_PROBE_FAIL NORMAL 房没有拿到清房 spec")
		return

	var pickups := 0
	var ammo := 0
	var comp: Dictionary = {}
	for index in range(SAMPLES):
		var report := _coord.resolve_clear({"clear": spec}, 1, "probe:clear:%d" % index)
		var grants: Array = report.get("grants", []) as Array
		var has_ammo := false
		for value in grants:
			var grant := value as Dictionary
			var gid := str(grant.get("item_id", grant.get("currency_id", "")))
			if gid == "item_ammo_pack":
				has_ammo = true
				ammo += 1
				continue
			pickups += 1
			comp[gid] = int(comp.get(gid, 0)) + 1

	var pickup_rate := float(pickups) / float(SAMPLES)
	var ammo_rate := float(ammo) / float(SAMPLES)
	var rounded := {}
	for gid in comp.keys():
		rounded[gid] = "%.1f%%" % (float(comp[gid]) / float(pickups) * 100.0)
	print("  拾取物率 %.1f%%（原作 20%%）｜弹药率 %.1f%%（原作 6%%）" % [pickup_rate * 100.0, ammo_rate * 100.0])
	print("  拾取物构成：", JSON.stringify(rounded))

	if absf(pickup_rate - 0.20) > 0.03:
		failures.append("拾取物率 %.1f%% 与配置 20%% 偏离过大" % (pickup_rate * 100.0))
	if absf(ammo_rate - 0.06) > 0.02:
		failures.append("弹药率 %.1f%% 与配置 6%% 偏离过大" % (ammo_rate * 100.0))
	if not comp.has("item_room_key"):
		failures.append("清房拾取物里没有钥匙（原作权重 24.36%，必须存在）")

	if failures.is_empty():
		print("EGT_CLEAR_REWARDS_PROBE_OK 清房结算与原作两项独立判定一致")
		return
	print("EGT_CLEAR_REWARDS_PROBE_FAIL：")
	for line in failures:
		print("  - ", line)


## 对照组：**没有 `legacy_fallback` 的关卡不受影响**。
##
## `full_coverage` 是本次新加的开关，缺省必须等价于旧行为 —— 否则远征01 / 塔楼
## 的掉落会被这次改动静默改掉（它们依赖「表只登记部分怪，其余走通用公式」）。
## 判据：不装任何表，`melee_chaser` 必须仍拿到旧公式的装备与备弹。
func _verify_legacy_default() -> void:
	print("\n--- 对照组：未配置 `legacy_fallback` 的关卡（远征01 / 塔楼）---")
	var coord: RuntimeRewardCoordinator = COORD.new()
	coord.configure(999)
	# 故意**不**调 configure_level_drop_table / configure_level_currency。
	var item_hits := 0
	var ammo_hits := 0
	for index in range(2000):
		var report := coord.resolve_kill({}, {
			"enemy_type": "melee_chaser", "floor": 1, "loot_table": "loot_floor_1_2",
		}, "legacy:%d" % index)
		for value in report.get("grants", []) as Array:
			var grant := value as Dictionary
			var gid := str(grant.get("item_id", ""))
			if str(grant.get("kind", "")) != "item":
				continue
			if gid == "item_ammo_pack":
				ammo_hits += 1
			else:
				item_hits += 1
	var item_rate := float(item_hits) / 2000.0
	var ammo_rate := float(ammo_hits) / 2000.0
	print("  melee_chaser 物品 %.1f%% / 弹药 %.1f%%（旧公式应为 ~16%% / ~34%%）"
		% [item_rate * 100.0, ammo_rate * 100.0])
	if item_rate < 0.10 or ammo_rate < 0.25:
		print("EGT_LEGACY_FALLBACK_FAIL 未配置关卡的兜底被改动（旧公式没生效）")
		return
	print("EGT_LEGACY_FALLBACK_OK 未配置关卡仍走通用公式，`full_coverage` 缺省不影响它们")
