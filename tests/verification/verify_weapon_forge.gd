extends Node
## verify_weapon_forge — 武器改造台（6×6 炼金盘）专项验收。
##
## 业主口径（2026-10-18）：投入武器与弹药模块，产出品质（蓝/紫/金）与弹种重新掷骰的新枪。
##
## 覆盖：
##   ① 规格自洽（熔炼值表、盘面容量、参数与文档一致）
##   ② 三条配方判定 + 稳定拒绝码
##   ③ 非法物品拒绝（非武器非模块）
##   ④ 品质分布收敛到公式值
##   ⑤ 武器数上限截断
##   ⑥ 产出实例规格（命运卡不继承、弹药不锁定、品质落盘）
##   ⑦ 三次读档往返不复利
##   ⑧ 确定性（同 seed 同结果）
##   ⑨ 蓝本 = 伤害最高的那把
##   ⑩ 事务：背包满时产出写不进去，产出物不重复消耗实例 ID
##   ⑪ 源码门禁：规则层不得硬编码品质常量

const FORGE := preload("res://src/weapons/WeaponForge.gd")
const GRADE := preload("res://src/weapons/WeaponDropGrade.gd")
const BULLET := preload("res://src/weapons/WeaponBulletDrop.gd")
const INSTANCE := preload("res://src/weapons/WeaponInstance.gd")
const INVENTORY := preload("res://src/game/InventoryModule.gd")
const PANEL := preload("res://src/ui/WorkbenchPanel.gd")

const SAMPLES := 20000
const TOLERANCE := 0.015

var _failures: Array[String] = []


func _ready() -> void:
	_case_spec()
	_case_recipes()
	_case_rejects()
	_case_grade_distribution()
	_case_weapon_cap()
	_case_output_spec()
	_case_reload_no_compound()
	_case_deterministic()
	_case_blueprint_pick()
	_case_coin_cost()
	_case_materials_raise_grade()
	_case_bullet_layers()
	_case_backpack_rollback()
	_case_panel_builds()
	await _case_panel_tray_and_forge()
	_case_source_guards()

	if _failures.is_empty():
		print("WEAPON_FORGE_OK: spec / recipes / rejects / distribution / cap / output / reload / determinism / blueprint-random / coin-cost / materials-raise-grade / bullet-layers / rollback / panel-build / panel-transaction / guards pass")
		print(FORGE.summary_line())
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# ————————————————————————————————
# ① 规格
# ————————————————————————————————

func _case_spec() -> void:
	# 业主 2026-10-18 口径：盘面「尽可能四方形」，先按 5×5 做。
	_expect(FORGE.TRAY_COLUMNS == 5 and FORGE.TRAY_ROWS == 5, "盘面必须是 5×5")
	_expect(FORGE.TRAY_CAPACITY == 25, "盘面容量必须是 25")
	# 行列必须相等 —— 用户要的就是正方形，一旦有人改成 6×4 就必须红。
	_expect(FORGE.TRAY_COLUMNS == FORGE.TRAY_ROWS, "盘面必须是正方形")

	# 规则层与面板各存一份盘面常量（面板要据此建棋盘），两处漂移会让
	# 玩家看到的格子数与规则算出的容量不一致。逐值钉住。
	_expect(PANEL.TRAY_COLUMNS == FORGE.TRAY_COLUMNS, "面板列数必须与规则层一致")
	_expect(PANEL.TRAY_ROWS == FORGE.TRAY_ROWS, "面板行数必须与规则层一致")
	_expect(PANEL.TRAY_CAPACITY == FORGE.TRAY_CAPACITY, "面板容量必须与规则层一致")
	_expect(FORGE.MELT_THRESHOLD == 6, "合成门槛必须是 6 点")
	_expect(FORGE.MAX_MELT_OUTPUT == 3, "单次合成产出上限必须是 3")
	_expect(FORGE.MAX_BLUEPRINT_WEAPONS == 6, "武器数硬上限必须是 6")
	# 熔炼值表与物品表 rarity 逐项对齐：这是"改一处忘了改另一处"的头号风险点。
	var expected := {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 6}
	for rarity in expected.keys():
		_expect(
			int(FORGE.MELT_VALUES.get(rarity, -1)) == int(expected[rarity]),
			"熔炼值表 %s 应为 %d" % [rarity, int(expected[rarity])]
		)
	_expect(
		FORGE.melt_value_of({"id": "x", "rarity": "unknown_rarity"}) == 1,
		"未知 rarity 必须回落 1 点，不得凭空抬高"
	)
	_expect(
		FORGE.melt_value_of({"id": "x", "rarity": "common", "count": 5}) == 5,
		"熔炼值必须按堆叠数量累加"
	)
	# 稀有度分：与熔炼值是两张表，common 必须是 0（否则"堆白装刷金"零成本）。
	var rarity_expected := {"common": 0, "uncommon": 1, "rare": 2, "epic": 4, "legendary": 7}
	for rarity in rarity_expected.keys():
		_expect(
			int(FORGE.RARITY_POINTS.get(rarity, -1)) == int(rarity_expected[rarity]),
			"稀有度分表 %s 应为 %d" % [rarity, int(rarity_expected[rarity])]
		)
	_expect(int(FORGE.RARITY_POINTS["common"]) == 0, "common 稀有度分必须为 0，堵死白装刷金")
	_expect(
		FORGE.rarity_points_of({"id": "x", "rarity": "unknown"}) == 0,
		"未知 rarity 稀有度分必须回落 0"
	)
	_expect(
		FORGE.rarity_points_of({"id": "x", "rarity": "rare", "count": 3}) == 6,
		"稀有度分必须按堆叠数量累加"
	)
	# 已带品质的物品，品质本身折算稀有度分（紫 +1 / 金 +2）
	_expect(
		FORGE.rarity_points_of({"id": "x", "rarity": "rare", "drop_grade": "gold"}) == 4,
		"金品质武器必须额外 +2 稀有度分（rare 2 + gold 2 = 4）"
	)
	_expect(
		FORGE.rarity_points_of({"id": "x", "rarity": "rare", "drop_grade": "purple"}) == 3,
		"紫品质武器必须额外 +1 稀有度分"
	)
	_expect(FORGE.FUEL_THRESHOLD == 3, "R1 燃料门槛必须是 3 点熔炼值")


# ————————————————————————————————
# ② 三条配方
# ————————————————————————————————

func _case_recipes() -> void:
	var rifle := _weapon("weapon_rifle")
	var pistol := _weapon("weapon_pistol")
	# 燃料按熔炼值门槛算（3 点）：3 个白装弹，或 1 件 rare 材料。
	var standard := _module("mod_bullet_standard", 3)

	# R1 重铸：1 把武器 + 燃料 ≥3 点
	var remelt := FORGE.classify([rifle, standard])
	_expect(str(remelt["recipe"]) == FORGE.RECIPE_REMELT, "1 武器 + 3 点燃料必须判为重铸")
	_expect(int(remelt["output_count"]) == 1, "重铸产出 1 把")
	_expect(not (remelt["blueprint"] as Dictionary).is_empty(), "重铸必须有蓝本")

	# R2 融合：≥2 把武器（无模块也行）
	var fusion := FORGE.classify([rifle, pistol])
	_expect(str(fusion["recipe"]) == FORGE.RECIPE_FUSION, "2 把武器必须判为融合")
	_expect(int(fusion["output_count"]) == 1, "融合产出 1 把")

	# R3 合成：纯模块，按 6 点整数倍
	var six := FORGE.classify([_module("mod_bullet_standard", 6)])
	_expect(str(six["recipe"]) == FORGE.RECIPE_SYNTHESIS, "6 个标准弹必须判为合成")
	_expect(int(six["output_count"]) == 1, "6 点产出 1 把")
	var twelve := FORGE.classify([_module("mod_bullet_standard", 12)])
	_expect(int(twelve["output_count"]) == 2, "12 点产出 2 把")
	var overflowing := FORGE.classify([_module("mod_bullet_standard", 40)])
	_expect(int(overflowing["output_count"]) == FORGE.MAX_MELT_OUTPUT, "超过 3 把必须截断到 3")

	# 稀有弹混投：1 个 epic(4) + 1 个 uncommon(2) = 6
	var mixed := FORGE.classify([
		_module("mod_bullet_homing", 1), _module("mod_bullet_sticky", 1),
	])
	_expect(str(mixed["recipe"]) == FORGE.RECIPE_SYNTHESIS, "4+2 点必须够合成门槛")
	_expect(int(mixed["melt"]) == 6, "4+2 点熔炼值必须为 6，实际 %d" % int(mixed["melt"]))

	# 单武器无燃料：拒绝（这是防套利的核心规则）
	var no_fuel := FORGE.classify([rifle])
	_expect(
		str(no_fuel["reason"]) == FORGE.REJECT_SINGLE_WEAPON_WITHOUT_FUEL,
		"单枪无模块必须拒绝，实际 '%s'" % str(no_fuel["reason"])
	)


func _case_rejects() -> void:
	_expect(
		str(FORGE.classify([])["reason"]) == FORGE.REJECT_EMPTY_TRAY,
		"空盘必须返回 empty_tray"
	)
	# 5 点不够 6 点
	var short := FORGE.classify([_module("mod_bullet_standard", 5)])
	_expect(
		str(short["reason"]) == FORGE.REJECT_INSUFFICIENT_MELT,
		"5 点必须不足门槛，实际 '%s'" % str(short["reason"])
	)
	# **所有物品都能当材料**（2026-10-18 业主裁决）：只有空字典不算材料。
	for item in [
		{"id": "attach_scope", "type": "attachment", "rarity": "rare"},
		{"id": "item_health_potion", "type": "consumable", "rarity": "common"},
		{"id": "mod_bullet_standard", "type": "module", "subtype": "bullet"},
		{"id": "weapon_rifle", "type": "weapon"},
		{"id": "equipment_backpack", "type": "equipment", "subtype": "backpack"},
		{"id": "bp_fragment", "type": "blueprint"},
	]:
		_expect(FORGE.accepts(item), "%s 必须被接受为材料" % str(item.get("id", "?")))
	_expect(not FORGE.accepts({}), "空字典不是材料")

	# 混入消耗品不再整盘拒绝：它变成了燃料，并真的参与凑门槛。
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	if potion.is_empty():
		_expect(false, "物品表必须存在 item_health_potion（熔炼台最典型的材料）")
		return
	var mixed := FORGE.classify([_module("mod_bullet_standard", 5), potion])
	_expect(
		str(mixed["recipe"]) == FORGE.RECIPE_SYNTHESIS,
		"5 个标准弹 + 1 瓶药水（共 6 点）必须够合成门槛，实际 '%s'" % str(mixed["reason"])
	)
	_expect(int(mixed["melt"]) == 6, "熔炼值应把药水算进去（5+1=6），实际 %d" % int(mixed["melt"]))

	# R1 燃料门槛：1 件白装（1 点）不够，3 件才够。
	var rifle := _weapon("weapon_rifle")
	var thin := FORGE.classify([rifle, potion])
	_expect(
		str(thin["reason"]) == FORGE.REJECT_INSUFFICIENT_FUEL,
		"1 件白装当燃料必须不足 3 点，实际 '%s'" % str(thin["reason"])
	)
	var enough := FORGE.classify([rifle, _item("item_health_potion", 3)])
	_expect(
		str(enough["recipe"]) == FORGE.RECIPE_REMELT,
		"3 件白装当燃料必须够重铸门槛，实际 '%s'" % str(enough["reason"])
	)
	# 稀有材料一件就够（rare 熔炼值 3）
	var rich := FORGE.classify([rifle, _item("attach_scope", 1)])
	_expect(
		str(rich["recipe"]) == FORGE.RECIPE_REMELT,
		"1 件 rare 材料（3 点）必须够重铸门槛，实际 '%s'" % str(rich["reason"])
	)


# ————————————————————————————————
# ④ 品质分布
# ————————————————————————————————

func _case_grade_distribution() -> void:
	var cases := [
		{"weapons": 1, "melt": 0},
		{"weapons": 1, "melt": 6},
		{"weapons": 2, "melt": 0},
		{"weapons": 2, "melt": 6},
		{"weapons": 3, "melt": 0},
	]
	for entry in cases:
		var weapons := int(entry["weapons"])
		var melt := int(entry["melt"])
		# 变量名沿用 melt 只是历史包袱；这里喂进去的是**稀有度分**。
		var points := melt
		var expected := FORGE.grade_probabilities(weapons, melt)
		var total := 0.0
		for grade in GRADE.ROLL_ORDER:
			total += float(expected.get(grade, 0.0))
		_expect(
			is_equal_approx(total, 1.0),
			"n=%d R=%d 的概率之和必须为 1.0，实际 %.6f" % [weapons, points, total]
		)
		var counts := {
			GRADE.GRADE_BLUE: 0, GRADE.GRADE_PURPLE: 0, GRADE.GRADE_GOLD: 0,
		}
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261018 + weapons
		for _index in range(SAMPLES):
			counts[FORGE.roll_grade(rng, weapons, points)] += 1
		for grade in GRADE.ROLL_ORDER:
			var observed := float(counts[grade]) / float(SAMPLES)
			var want := float(expected.get(grade, 0.0))
			_expect(
				absf(observed - want) <= TOLERANCE,
				"n=%d R=%d 品质 %s 实测 %.4f 偏离公式 %.4f 超过 %.3f" % [
					weapons, points, grade, observed, want, TOLERANCE,
				]
			)

	# n=1 R=0 必须回到野生基础池（不许凑出第二个真源）
	var base := FORGE.grade_probabilities(1, 0)
	_expect(
		is_equal_approx(float(base[GRADE.GRADE_BLUE]), float(GRADE.ROLL_WEIGHTS[GRADE.GRADE_BLUE])),
		"n=1 R=0 的蓝概率必须等于 WeaponDropGrade 基础权重"
	)
	# R3（n=0）R=0 也必须等于基础池
	var plain := FORGE.grade_probabilities(0, 0)
	_expect(
		is_equal_approx(float(plain[GRADE.GRADE_GOLD]), float(GRADE.ROLL_WEIGHTS[GRADE.GRADE_GOLD])),
		"n=0 R=0 的金概率必须等于基础池"
	)
	# **R3 现在吃稀有度分**（2026-10-18 改）：纯材料也能靠稀有材料搏金。
	var rich_materials := FORGE.grade_probabilities(0, 24)
	_expect(
		float(rich_materials[GRADE.GRADE_GOLD]) > float(plain[GRADE.GRADE_GOLD]),
		"R3 投稀有材料必须抬高金概率（%.3f → %.3f）" % [
			float(plain[GRADE.GRADE_GOLD]), float(rich_materials[GRADE.GRADE_GOLD]),
		]
	)
	_expect(
		float(rich_materials[GRADE.GRADE_BLUE]) < float(plain[GRADE.GRADE_BLUE]),
		"R3 投稀有材料必须压低蓝概率"
	)
	# 反向对照：投越多，蓝必须单调下降
	var blue_1 := float(FORGE.grade_probabilities(1, 0)[GRADE.GRADE_BLUE])
	var blue_2 := float(FORGE.grade_probabilities(2, 0)[GRADE.GRADE_BLUE])
	var blue_3 := float(FORGE.grade_probabilities(3, 0)[GRADE.GRADE_BLUE])
	_expect(blue_1 > blue_2 and blue_2 > blue_3, "蓝概率必须随投入武器数单调下降")


func _case_weapon_cap() -> void:
	var capped := FORGE.grade_probabilities(99, 0)
	var maxed := FORGE.grade_probabilities(FORGE.MAX_BLUEPRINT_WEAPONS, 0)
	for grade in GRADE.ROLL_ORDER:
		_expect(
			is_equal_approx(float(capped[grade]), float(maxed[grade])),
			"武器数超过上限后必须按 6 把计，%s 概率不等" % grade
		)
	# 蓝权重地板：再怎么加权也不能到 0
	_expect(
		float(FORGE.grade_probabilities(6, 100)[GRADE.GRADE_BLUE]) > 0.0,
		"蓝权重必须有地板，不得降到 0"
	)


# ————————————————————————————————
# ⑥⑦⑧ 产出规格
# ————————————————————————————————

func _case_output_spec() -> void:
	var output := FORGE.build_output({
		"assembly_id": "bp_rifle",
		"grade": GRADE.GRADE_GOLD,
		"bullet_id": "mod_bullet_blackhole",
		"attachments": [],
	})
	_expect(not output.is_empty(), "产出必须能构建（bp_rifle → weapon_rifle）")
	if output.is_empty():
		return
	_expect(str(output.get("drop_grade", "")) == GRADE.GRADE_GOLD, "产出必须落盘金色品质")
	_expect(
		(output.get("fate_upgrades", []) as Array).is_empty(),
		"产出不得继承命运卡"
	)
	_expect(
		not bool(output.get("bullet_module_locked", true)),
		"炼金产出不得锁定弹药（锁定是野生掉落专属）"
	)
	_expect(
		str(output.get("bullet_module_id", "")) == "mod_bullet_blackhole",
		"产出必须带指定弹种，实际 '%s'" % str(output.get("bullet_module_id", ""))
	)
	var gold_capacity := int(output.get("fate_slot_capacity", 0))
	_expect(gold_capacity > 8, "金色产出命运槽必须高于基线（+4），实际 %d" % gold_capacity)

	var instance := INSTANCE.from_item(output)
	_expect(instance != null, "产出必须能构造实例")
	if instance != null:
		var snapshot := instance.get_presentation_snapshot()
		_expect(
			str((snapshot.get("bullet_module", {}) as Dictionary).get("item_id", ""))
			== "mod_bullet_blackhole",
			"实例快照必须还原同一弹种"
		)

	# 近战：不配弹
	var melee_item := FORGE.build_output({
		"assembly_id": "bp_baseball_bat",
		"grade": GRADE.GRADE_BLUE,
		"bullet_id": "mod_bullet_standard",
		"attachments": [],
	})
	_expect(not melee_item.is_empty(), "近战产出必须能构建")
	if not melee_item.is_empty():
		_expect(
			str(melee_item.get("bullet_module_id", "")).is_empty(),
			"近战产出不得写弹种"
		)

	# 未知枪身：明确返回空，不伪造一把枪
	_expect(
		FORGE.build_output({"assembly_id": "bp_not_exist", "grade": GRADE.GRADE_BLUE}).is_empty(),
		"未知枪身必须返回空字典"
	)
	# 反查映射必须双向自洽
	_expect(
		FORGE.weapon_item_id_for_assembly("bp_rifle") == "weapon_rifle",
		"bp_rifle 必须反查到 weapon_rifle"
	)


func _case_reload_no_compound() -> void:
	var output := FORGE.build_output({
		"assembly_id": "bp_rifle",
		"grade": GRADE.GRADE_PURPLE,
		"bullet_id": "mod_bullet_piercing",
		"attachments": [],
	})
	var expected_capacity := int(output.get("fate_slot_capacity", 0))
	var item := output
	# 三次「存档 → 读档」往返：命运槽与伤害都必须逐值不变
	for round_index in range(3):
		var instance := INSTANCE.from_item(item)
		_expect(instance != null, "第 %d 次读档必须成功" % round_index)
		if instance == null:
			return
		_expect(
			instance.fate_slot_capacity == expected_capacity,
			"第 %d 次读档命运槽复利：期望 %d，实际 %d" % [
				round_index, expected_capacity, instance.fate_slot_capacity,
			]
		)
		item = instance.to_item_dictionary()


func _case_deterministic() -> void:
	var first := _forge_sequence(424242)
	var second := _forge_sequence(424242)
	_expect(first == second, "同 seed 必须得到同品质序列：%s vs %s" % [str(first), str(second)])
	var other := _forge_sequence(424243)
	_expect(first != other, "不同 seed 应得到不同序列")


func _forge_sequence(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grades: Array = []
	for _index in range(12):
		grades.append(FORGE.roll_grade(rng, 2, 3))
	return grades


# ————————————————————————————————
# ⑨ 蓝本选择
# ————————————————————————————————

func _case_blueprint_pick() -> void:
	# 业主 2026-10-18：「两把随机」—— 蓝本不再取伤害最高那把，而是真的掷骰。
	var rifle := _weapon("weapon_rifle")
	var pistol := _weapon("weapon_pistol")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var hits: Dictionary = {}
	for _index in range(4000):
		var picked := FORGE.pick_blueprint([pistol, rifle], rng)
		var item := picked.get("item", {}) as Dictionary
		var item_id := str(item.get("id", ""))
		var index := int(picked.get("index", -1))
		_expect(not item_id.is_empty(), "蓝本必须命中一把真实武器")
		# 下标必须与返回的物品一致，否则面板拿 index 去做后续逻辑会错位。
		_expect(
			[pistol, rifle][index].get("id", "") == item_id,
			"蓝本下标与物品不一致：index=%d item=%s" % [index, item_id]
		)
		hits[item_id] = int(hits.get(item_id, 0)) + 1
	var rifle_ratio := float(hits.get("weapon_rifle", 0)) / 4000.0
	var pistol_ratio := float(hits.get("weapon_pistol", 0)) / 4000.0
	_expect(
		absf(rifle_ratio - 0.5) <= 0.03 and absf(pistol_ratio - 0.5) <= 0.03,
		"两把武器的蓝本必须各约 50%%，实测步枪 %.3f / 手枪 %.3f" % [rifle_ratio, pistol_ratio]
	)
	# 反向对照：只投一把时随机退化为取它，不能返回空。
	var single := FORGE.pick_blueprint([rifle], rng)
	_expect(str((single["item"] as Dictionary).get("id", "")) == "weapon_rifle", "单把时必须取那一把")
	_expect(int(single["index"]) == 0, "单把时下标必须为 0")
	_expect(int(FORGE.pick_blueprint([], rng).get("index", 0)) == -1, "空列表必须返回 -1")
	# R2 的解析阶段**不预设**蓝本：否则 UI 会显示一个还没掷的假结论。
	var plan := FORGE.classify([_weapon("weapon_rifle"), _weapon("weapon_pistol")])
	_expect(
		(plan["blueprint"] as Dictionary).is_empty(),
		"R2 解析阶段不得预设蓝本"
	)
	_expect(
		(plan["blueprint_candidates"] as Array).size() == 2,
		"R2 必须给出 2 个蓝本候选"
	)


# ————————————————————————————————
# ⑨½ 金币费用
# ————————————————————————————————

func _case_coin_cost() -> void:
	# 公式：max(min, ceil(投入估值 × rate))。参数与文档 §4.4 同批改，改一处即变红。
	var rifle := _weapon("weapon_rifle")          # price 150
	var pistol := _weapon("weapon_pistol")        # price 70
	var standard := _module("mod_bullet_standard", 3)  # price 30 × 3 = 90

	var remelt := FORGE.classify([rifle, standard])
	_expect(str(remelt["recipe"]) == FORGE.RECIPE_REMELT, "费用用例：1 枪 + 3 弹应是重铸")
	_expect(int(remelt["value"]) == 240, "投入估值应为 150+90=240，实际 %d" % int(remelt["value"]))
	_expect(
		int(remelt["coin_cost"]) == 72,
		"重铸费用应为 ceil(240×0.30)=72，实际 %d" % int(remelt["coin_cost"])
	)

	var fusion := FORGE.classify([rifle, pistol])
	_expect(int(fusion["value"]) == 220, "融合估值应为 150+70=220，实际 %d" % int(fusion["value"]))
	_expect(
		int(fusion["coin_cost"]) == 88,
		"融合费用应为 ceil(220×0.40)=88，实际 %d" % int(fusion["coin_cost"])
	)

	var synthesis := FORGE.classify([_module("mod_bullet_standard", 6)])
	_expect(int(synthesis["value"]) == 180, "合成估值应为 30×6=180，实际 %d" % int(synthesis["value"]))
	_expect(
		int(synthesis["coin_cost"]) == 90,
		"合成费用应为 ceil(180×0.50)=90，实际 %d" % int(synthesis["coin_cost"])
	)

	# 最低价：两把球棒（45+45=90）按 40% 只有 36，必须抬到 40。
	var cheap := FORGE.classify([_weapon("weapon_baseball_bat"), _weapon("weapon_baseball_bat")])
	_expect(
		int(cheap["coin_cost"]) == 40,
		"低价投入必须抬到最低价 40，实际 %d" % int(cheap["coin_cost"])
	)
	_expect(
		FORGE.coin_cost_for("not_a_recipe", 1000) == 0,
		"未知配方不得收费"
	)
	# 费用必须随投入价值单调上升，否则"拿贵枪熔炼"会比"拿垃圾熔炼"更划算。
	_expect(
		int(FORGE.coin_cost_for(FORGE.RECIPE_REMELT, 600))
		> int(FORGE.coin_cost_for(FORGE.RECIPE_REMELT, 200)),
		"费用必须随投入估值单调上升"
	)
	# 原始物品定义没有 price 字段被剥离的情况，必须能回查物品表算出费用
	_expect(
		FORGE.item_value({"id": "weapon_rifle"}) == 150,
		"物品字典缺 price 时必须回查物品表估值"
	)


# ————————————————————————————————
# ⑨⅔ 材料的稀有度提升品质（业主 2026-10-18 核心裁决）
# ————————————————————————————————

func _case_materials_raise_grade() -> void:
	var rifle := _weapon("weapon_rifle")
	# 同一把枪 + 同样 6 点熔炼值，只换材料稀有度 ⇒ 品质概率必须不同，
	# 且稀有的一组金概率严格更高。这是"材料的稀有度会提升稀有度"的最直接判据。
	var common_mats := FORGE.classify([rifle, _item("mod_bullet_standard", 6)])
	var rare_mats := FORGE.classify([rifle, _item("mod_bullet_homing", 1), _item("attach_scope", 1)])
	_expect(str(common_mats["recipe"]) == FORGE.RECIPE_REMELT, "白装材料组应判为重铸")
	_expect(str(rare_mats["recipe"]) == FORGE.RECIPE_REMELT, "稀有材料组应判为重铸")
	_expect(
		int(common_mats["rarity_points"]) == 0,
		"6 个 common 弹的稀有度分必须为 0，实际 %d" % int(common_mats["rarity_points"])
	)
	_expect(
		int(rare_mats["rarity_points"]) > 0,
		"稀有材料组稀有度分必须为正，实际 %d" % int(rare_mats["rarity_points"])
	)
	var common_probs := FORGE.grade_probabilities(1, int(common_mats["rarity_points"]))
	var rare_probs := FORGE.grade_probabilities(1, int(rare_mats["rarity_points"]))
	_expect(
		float(rare_probs[GRADE.GRADE_GOLD]) > float(common_probs[GRADE.GRADE_GOLD]),
		"稀有材料必须抬高金概率（%.3f → %.3f）" % [
			float(common_probs[GRADE.GRADE_GOLD]), float(rare_probs[GRADE.GRADE_GOLD]),
		]
	)
	_expect(
		float(rare_probs[GRADE.GRADE_BLUE]) < float(common_probs[GRADE.GRADE_BLUE]),
		"稀有材料必须压低蓝概率"
	)

	# 单调性：稀有度分越高，金概率越高、蓝概率越低（跨多个档位）
	var previous_gold := -1.0
	var previous_blue := 2.0
	for points in [0, 2, 4, 8, 16, 32]:
		var probs := FORGE.grade_probabilities(1, points)
		var gold := float(probs[GRADE.GRADE_GOLD])
		var blue := float(probs[GRADE.GRADE_BLUE])
		_expect(gold >= previous_gold, "R=%d 金概率必须不降（%.4f vs %.4f）" % [points, gold, previous_gold])
		_expect(blue <= previous_blue, "R=%d 蓝概率必须不升（%.4f vs %.4f）" % [points, blue, previous_blue])
		previous_gold = gold
		previous_blue = blue

	# 白装堆再多也不提升品质：这是"堆白装刷金"的堵口。
	var many_common := FORGE.classify([_item("mod_bullet_standard", 30)])
	_expect(
		int(many_common["rarity_points"]) == 0,
		"30 个白装弹稀有度分仍必须为 0，实际 %d" % int(many_common["rarity_points"])
	)
	var many_common_probs := FORGE.grade_probabilities(0, int(many_common["rarity_points"]))
	_expect(
		is_equal_approx(
			float(many_common_probs[GRADE.GRADE_GOLD]),
			float(GRADE.ROLL_WEIGHTS[GRADE.GRADE_GOLD])
		),
		"堆白装不得抬高金概率"
	)
	# 但它仍然能凑数量（熔炼值 30 ⇒ 5 把，被上限截到 3）
	_expect(int(many_common["melt"]) == 30, "30 个白装熔炼值应为 30")

	# 已带金品质的枪当材料，比同名蓝品质的更"稀有"
	var gold_gun := _weapon("weapon_rifle")
	gold_gun["drop_grade"] = "gold"
	var blue_gun := _weapon("weapon_rifle")
	blue_gun["drop_grade"] = "blue"
	_expect(
		FORGE.rarity_points_of(gold_gun) > FORGE.rarity_points_of(blue_gun),
		"金品质枪当材料必须比蓝品质的更值钱"
	)
	# 两把枪融合时，两把的稀有度都要计入（不能只算第二把）
	var fusion := FORGE.classify([gold_gun, blue_gun])
	_expect(
		int(fusion["rarity_points"]) == FORGE.rarity_points_of(gold_gun) + FORGE.rarity_points_of(blue_gun),
		"融合必须累计两把枪的稀有度分，实际 %d" % int(fusion["rarity_points"])
	)


# ————————————————————————————————
# ⑨¾ 弹种两层候选（"从枪的属性和子弹模块中随机"）
# ————————————————————————————————

func _case_bullet_layers() -> void:
	# ① 枪自带绑定弹种必须能被读出来（盘面上的枪就是靠这个字段参与抽取）
	var rifle := _weapon("weapon_rifle")
	rifle["bullet_module_id"] = "mod_bullet_piercing"
	_expect(
		FORGE.weapon_bound_bullet(rifle) == "mod_bullet_piercing",
		"顶层 bullet_module_id 必须能读到"
	)
	# 嵌套层同样要认（不同流转阶段的枪字段层级不同）
	var nested := _weapon("weapon_shotgun")
	nested["weapon_instance"] = {"bullet_module_id": "mod_bullet_explosive"}
	_expect(
		FORGE.weapon_bound_bullet(nested) == "mod_bullet_explosive",
		"weapon_instance 嵌套层的弹种必须能读到"
	)
	# 无弹种的枪返回空（近战 / 手工构造）
	_expect(FORGE.weapon_bound_bullet(_weapon("weapon_baseball_bat")) == "", "无弹种必须返回空串")
	_expect(FORGE.weapon_bound_bullet({}) == "", "空字典必须返回空串")

	# ② 两把枪的绑定弹种会被收进候选池，且去重
	var a := _weapon("weapon_rifle")
	a["bullet_module_id"] = "mod_bullet_piercing"
	var b := _weapon("weapon_shotgun")
	b["bullet_module_id"] = "mod_bullet_explosive"
	var c := _weapon("weapon_pistol")
	c["bullet_module_id"] = "mod_bullet_piercing"
	var bound := FORGE.collect_bound_bullets([a, b, c])
	_expect(bound.size() == 2, "两把不同弹种的枪必须收出 2 个候选，实际 %d" % bound.size())
	_expect("mod_bullet_piercing" in bound and "mod_bullet_explosive" in bound, "候选集合内容错")

	# ③ 不投任何模块，弹种也必须能从两把枪的弹道里随机出来（这是业主"从枪的属性随机"的核心）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var hits: Dictionary = {}
	for _index in range(4000):
		var rolled := FORGE.roll_bullet([], rng, bound)
		hits[rolled] = int(hits.get(rolled, 0)) + 1
	var piercing_ratio := float(hits.get("mod_bullet_piercing", 0)) / 4000.0
	var explosive_ratio := float(hits.get("mod_bullet_explosive", 0)) / 4000.0
	_expect(
		absf(piercing_ratio - 0.5) <= 0.04 and absf(explosive_ratio - 0.5) <= 0.04,
		"两把枪各 1 票应各约 50%%，实测穿透 %.3f / 爆炸 %.3f" % [piercing_ratio, explosive_ratio]
	)
	_expect(hits.size() == 2, "不应出现候选之外的弹种，实测 %s" % str(hits.keys()))

	# ④ 模块按数量计票：2 个标准弹（2 票）压过 1 把枪（1 票）⇒ 标准弹约 2/3
	var with_module := {}
	for _index in range(4000):
		var rolled := FORGE.roll_bullet(
			[_module("mod_bullet_standard", 2)], rng, ["mod_bullet_piercing"]
		)
		with_module[rolled] = int(with_module.get(rolled, 0)) + 1
	var standard_ratio := float(with_module.get("mod_bullet_standard", 0)) / 4000.0
	_expect(
		absf(standard_ratio - 2.0 / 3.0) <= 0.04,
		"2 票模块应压过 1 票枪弹种（约 66%%），实测 %.3f" % standard_ratio
	)

	# ⑤ 候选全空时必须回落野生池，不能产出空弹种（那等于给了一把打不出子弹的枪）
	var fallback := FORGE.roll_bullet([], rng, [])
	_expect(BULLET.is_valid(fallback), "候选全空必须回落到合法弹种，实际 '%s'" % fallback)

	# ⑥ 生成端到端：R2 带绑定弹种的枪不投模块，产出弹种必须落在候选集内
	var plan := FORGE.classify([a, b])
	_expect(str(plan["recipe"]) == FORGE.RECIPE_FUSION, "两把带弹种的枪应判为融合")
	var candidates := FORGE.collect_bound_bullets(plan["weapons"])
	for _index in range(40):
		var picked := FORGE.roll_bullet(plan["modules"], rng, candidates)
		_expect(picked in candidates, "R2 产出弹种必须来自枪自带弹种集合，实际 '%s'" % picked)


# ————————————————————————————————
# ⑩ 背包回滚
# ————————————————————————————————

func _case_backpack_rollback() -> void:
	# 背包只有 2 格：一枚 2×1 弹药模块就占满，4×2 的枪必然写不进去。
	var inventory = INVENTORY.new(2)
	_expect(inventory != null, "背包模块必须能构造")
	if inventory == null:
		return
	var filler := ItemRegistry.get_instance().get_item("mod_bullet_standard").duplicate(true)
	_expect(inventory.add_item(filler, 1) > 0, "测试背包必须能放入占位物（2 格塞 2×1 模块）")
	var before := inventory.get_slots_snapshot()
	var output := FORGE.build_output({
		"assembly_id": "bp_rifle",
		"grade": GRADE.GRADE_BLUE,
		"bullet_id": "mod_bullet_standard",
	})
	_expect(not output.is_empty(), "回滚用例的产出必须能构建")
	var written := inventory.add_item(output, 1)
	_expect(written <= 0, "满包不得写进产出，实际写入 %d" % written)
	inventory.restore_slots_snapshot(before)
	_expect(
		inventory.get_slots_snapshot() == before,
		"回滚后背包必须与快照逐项一致"
	)
	# 产出实例 ID 必须唯一：同一 context 连续构建两次不能撞号
	var second := FORGE.build_output({
		"assembly_id": "bp_rifle",
		"grade": GRADE.GRADE_BLUE,
		"bullet_id": "mod_bullet_standard",
	})
	_expect(
		str(output.get("weapon_instance_id", "")) != str(second.get("weapon_instance_id", "")),
		"两次构建必须得到不同实例 ID"
	)


# ————————————————————————————————
# ⑪ 界面构建冒烟
# ————————————————————————————————

func _case_panel_builds() -> void:
	# 面板在 headless 下也必须能构建：它会在 3D 战局里被动态实例化，
	# 构建期崩掉的表现是"按 E 没反应"，比数值算错更难查。
	var panel := PANEL.new()
	panel.name = "ForgePanelSmoke"
	add_child(panel)
	var tray := panel.find_child("TrayBoard", true, false)
	_expect(tray != null, "炼金盘棋盘必须存在")
	if tray != null:
		_expect(
			tray.cells.size() == FORGE.TRAY_CAPACITY,
			"棋盘格数必须是 %d，实际 %d" % [FORGE.TRAY_CAPACITY, tray.cells.size()]
		)
		_expect(tray.columns == FORGE.TRAY_COLUMNS, "棋盘列数必须等于盘面列数")
		_expect(str(tray.slot_kind) == "alchemy", "棋盘拖拽类型必须是 alchemy")
	var bag := panel.find_child("BagBoard", true, false)
	_expect(bag != null, "背包棋盘必须存在")
	# 空盘时熔炼按钮必须是禁用的 —— 不能让玩家点了没反应又不知道原因
	var forge_button := panel.find_child("ForgeButton", true, false) as Button
	_expect(forge_button != null, "熔炼按钮必须存在")
	if forge_button != null:
		_expect(forge_button.disabled, "空盘时熔炼按钮必须禁用")
	_expect(
		panel.get_node_or_null("ConfirmLayer") != null,
		"销毁确认层必须存在（盘内含武器时先确认）"
	)

	# ——— 版式：页头 / 主体（炼炉 + 背包）/ 页脚 ———
	# 业主 2026-10-18：右边是背包，中间是炼炉，按钮和信息全压到底部。
	var body := panel.find_child("Body", true, false)
	_expect(body != null, "主体容器必须存在")
	if body != null:
		var tray_column := panel.find_child("TrayColumn", true, false)
		var bag_column := panel.find_child("BagColumn", true, false)
		_expect(tray_column != null and bag_column != null, "炼炉与背包两栏必须都存在")
		if tray_column != null and bag_column != null:
			_expect(tray_column.get_parent() == body, "炼炉必须直接挂在主体容器里")
			_expect(bag_column.get_parent() == body, "背包必须直接挂在主体容器里")
			# 炼炉在背包**左边**：这是"中间炼炉、右边背包"的硬判据。
			_expect(
				tray_column.get_index() < bag_column.get_index(),
				"炼炉必须排在背包左侧"
			)
	# 主体里不允许再夹读数或按钮 —— 那就是旧版"信息挤在中间"的布局。
	if body != null:
		for child_name in ["Readout", "Actions", "ForgeButton"]:
			_expect(
				body.find_child(child_name, true, false) == null,
				"主体区不得包含 %s（信息与按钮必须全在页脚）" % child_name
			)

	var footer := panel.find_child("Footer", true, false)
	_expect(footer != null, "页脚容器必须存在")
	if footer != null:
		_expect(footer.get_child_count() == 2, "页脚必须是「读数 + 操作」两行")
		if footer.get_child_count() == 2:
			_expect(
				str(footer.get_child(0).name) == "Readout",
				"页脚第一行必须是读数，实际 %s" % str(footer.get_child(0).name)
			)
			_expect(
				str(footer.get_child(1).name) == "Actions",
				"页脚第二行必须是操作行，实际 %s" % str(footer.get_child(1).name)
			)
		# 页脚必须是整个 VBox 的最后一个子节点 —— "按钮直接放在底下"的字面判据。
		var vbox := panel.find_child("VBox", true, false)
		_expect(vbox != null, "主竖列必须存在")
		if vbox != null:
			_expect(
				vbox.get_child(vbox.get_child_count() - 1) == footer,
				"页脚必须排在页面最底部"
			)
		# 关闭按钮也在页脚：旧版它挂在页头右上，与"按钮都放底下"冲突。
		var close_button := footer.find_child("CloseButton", true, false) as Button
		_expect(close_button != null, "关闭按钮必须在页脚")
	panel.queue_free()


# ————————————————————————————————
# ⑫ 面板级事务（真实驱动盘面与熔炼）
# ————————————————————————————————

## 最小宿主：只提供面板需要的 `get_inventory_module`。
class _StubRef:
	extends Node
	var inventory: InventoryModule = null
	func get_inventory_module() -> InventoryModule:
		return inventory


func _case_panel_tray_and_forge() -> void:
	var stub := _StubRef.new()
	stub.inventory = INVENTORY.new(40)
	add_child(stub)
	_put(stub.inventory, "weapon_rifle", 1)
	_put(stub.inventory, "weapon_pistol", 1)
	_put(stub.inventory, "mod_bullet_standard", 6)
	_put(stub.inventory, "item_health_potion", 1)

	# 熔炼要收费：先给一笔预算，否则每条熔炼都会被"金币不足"拦下。
	var coins_before := int(GameManager.currency)
	GameManager.currency = 1000

	var panel = PANEL.new()
	panel.set_workbench_ref(stub)
	add_child(panel)
	await get_tree().process_frame

	# ① 所有物品都能入场（2026-10-18）：消耗品/配件都可以拖进盘面当材料。
	var potion := ItemRegistry.get_instance().get_item("item_health_potion").duplicate(true)
	_expect(
		bool(panel.call("_validate_tray_drop", {
			"item": potion, "source_kind": "inventory", "source_index": 0,
		}, 24)),
		"消耗品必须能被盘面接受为材料"
	)
	var scope := ItemRegistry.get_instance().get_item("attach_scope").duplicate(true)
	_expect(
		bool(panel.call("_validate_tray_drop", {
			"item": scope, "source_kind": "inventory", "source_index": 0,
		}, 22)),
		"配件必须能被盘面接受为材料"
	)

	# ② 叠放冲突：两把 4×2 步枪不能落在重叠锚点
	var rifle := _weapon("weapon_rifle")
	_expect(bool(panel.call("_tray_append", rifle, 1, 0, 0)), "首把步枪必须能放入左上角")
	_expect(
		not bool(panel.call("_tray_append", rifle.duplicate(true), 1, 1, 0)),
		"重叠锚点必须被拒绝（4×2 从 0 起占满前两行）"
	)
	# 越界：5 列盘面上，4×2 从列 2 起会横跨到列 5（不存在）
	_expect(
		not bool(panel.call("_tray_append", rifle.duplicate(true), 1, 2, 0)),
		"越界锚点必须被拒绝"
	)

	# ③ 单枪无燃料：熔炼按钮禁用 + 状态给原因
	panel.call("_refresh_readout")
	var plan := FORGE.classify(panel.call("_tray_probe_items"))
	_expect(
		str(plan["reason"]) == FORGE.REJECT_SINGLE_WEAPON_WITHOUT_FUEL,
		"面板解析必须识别单枪无燃料，实际 '%s'" % str(plan["reason"])
	)
	var forge_button := panel.find_child("ForgeButton", true, false) as Button
	_expect(forge_button != null and forge_button.disabled, "单枪无燃料时熔炼按钮必须禁用")

	# ③½ 稀有度分必须显示到读数栏（"材料的稀有度提升品质"的唯一可见抓手）
	var rarity_label := panel.get("_stat_rarity") as Label
	_expect(rarity_label != null, "RARITY 读数块必须存在")
	if rarity_label != null:
		panel.call("_tray_append", _item("attach_scope", 1), 1, 10, 0)
		panel.call("_refresh_readout")
		_expect(
			rarity_label.text == "2",
			"投 1 件 rare 配件后 RARITY 应显示 2，实际 '%s'" % rarity_label.text
		)
		panel.call("_tray_remove_anchor", 10)
		panel.call("_refresh_readout")

	# ④ 补 3 个标准弹 ⇒ 变成重铸；执行熔炼后盘面清空、背包多出一把新枪
	panel.call("_tray_append", _module("mod_bullet_standard", 3), 3, 20, 0)
	panel.call("_refresh_all")
	var before_count := _weapon_count(stub.inventory)
	var plan_before_forge := FORGE.classify(panel.call("_tray_probe_items"))
	var fee := int(plan_before_forge["coin_cost"])
	var coins_before_forge := int(GameManager.currency)
	_expect(fee > 0, "重铸必须有金币费用，实际 %d" % fee)
	panel.call("_execute_forge", plan_before_forge)
	await get_tree().process_frame
	_expect(
		int(GameManager.currency) == coins_before_forge - fee,
		"熔炼必须扣掉 %d 金币（%d → %d）" % [
			fee, coins_before_forge, int(GameManager.currency),
		]
	)
	var tray_after: Array = panel.get("_tray")
	_expect(tray_after.is_empty(), "熔炼成功后盘面必须清空，实际剩 %d 条" % tray_after.size())
	var after_count := _weapon_count(stub.inventory)
	_expect(after_count >= before_count, "熔炼后背包枪械数不得减少（%d → %d）" % [before_count, after_count])
	var produced := _latest_weapon(stub.inventory)
	_expect(not produced.is_empty(), "熔炼必须在背包里产出一把枪")
	if not produced.is_empty():
		_expect(GRADE.is_valid(str(produced.get("drop_grade", ""))), "产出必须带合法品质")
		_expect(
			(produced.get("fate_upgrades", []) as Array).is_empty(),
			"产出不得继承命运卡"
		)

	# ⑤ 关面板必须把盘内残留退回背包
	panel.call("_tray_append", _module("mod_bullet_standard", 2), 2, 10, 0)
	var before_return := _count_of(stub.inventory, "mod_bullet_standard")
	_expect(bool(panel.call("_return_tray_to_inventory")), "盘内物品必须能退回背包")
	_expect((panel.get("_tray") as Array).is_empty(), "退回后盘面必须清空")
	_expect(
		_count_of(stub.inventory, "mod_bullet_standard") == before_return + 2,
		"退回必须归还 2 个模块（%d → %d）" % [
			before_return, _count_of(stub.inventory, "mod_bullet_standard"),
		]
	)

	# ⑥ 金币不足：拒绝且盘面一件不少、金币不动
	GameManager.currency = 0
	panel.call("_tray_append", _weapon("weapon_rifle"), 1, 0, 0)
	panel.call("_tray_append", _weapon("weapon_pistol"), 1, 20, 0)
	panel.call("_refresh_all")
	var deny_plan := FORGE.classify(panel.call("_tray_probe_items"))
	_expect(str(deny_plan["recipe"]) == FORGE.RECIPE_FUSION, "拒付用例应判为融合")
	_expect(int(deny_plan["coin_cost"]) > 0, "拒付用例必须有费用")
	var tray_count_before := (panel.get("_tray") as Array).size()
	panel.call("_execute_forge", deny_plan)
	await get_tree().process_frame
	_expect(
		(panel.get("_tray") as Array).size() == tray_count_before,
		"金币不足时盘面必须原样保留（%d → %d）" % [
			tray_count_before, (panel.get("_tray") as Array).size(),
		]
	)
	_expect(int(GameManager.currency) == 0, "金币不足时不得扣成负数")

	# ⑦ 按钮在买不起时必须禁用
	panel.call("_refresh_readout")
	_expect(forge_button != null and forge_button.disabled, "金币不足时熔炼按钮必须禁用")
	var cost_label := panel.find_child("Stat_FEE", true, false)
	if cost_label == null:
		var stat_fee := panel.get_node_or_null("Panel/Margin/VBox/Readout/Stat_FEE")
		_expect(stat_fee != null, "费用读数块必须存在")
		if stat_fee != null:
			_expect(
				(stat_fee.get_children().size() >= 2),
				"费用块必须是「弱标签 + 强数值」两级结构"
			)

	GameManager.currency = coins_before
	panel.queue_free()
	stub.queue_free()


# ————————————————————————————————
# ⑬ 源码门禁
# ————————————————————————————————

func _case_source_guards() -> void:
	var source := FileAccess.get_file_as_string("res://src/weapons/WeaponForge.gd")
	_expect(not source.is_empty(), "规则层源文件必须可读")
	# 正向门禁：品质基线必须从 WeaponDropGrade 取，且不得在这里另立一张权重表。
	# （只查裸数字会误伤文档注释 —— 注释里写公式是好事，不是违规。）
	_expect(
		source.contains("WeaponDropGrade.ROLL_WEIGHTS"),
		"WeaponForge 必须从 WeaponDropGrade.ROLL_WEIGHTS 取基础权重"
	)
	_expect(
		not source.contains("var ROLL_WEIGHTS"),
		"WeaponForge 不得自建 ROLL_WEIGHTS —— 品质基线唯一真源是 WeaponDropGrade"
	)
	# 不得自己定义弹种池
	_expect(
		not source.contains("mod_bullet_balloon"),
		"WeaponForge 不得复制弹种池 —— 唯一真源是 WeaponBulletDrop"
	)
	_expect(
		source.contains("WeaponBulletDrop.roll"),
		"WeaponForge 的兜底弹种必须走 WeaponBulletDrop.roll"
	)
	# 面板不得再出现旧的免费换枪入口
	var panel := FileAccess.get_file_as_string("res://src/ui/WorkbenchPanel.gd")
	_expect(not panel.is_empty(), "面板源文件必须可读")
	_expect(
		not panel.contains("tree.set_root("),
		"面板不得再直接 set_root（旧的免费换枪身旁路必须彻底移除）"
	)
	_expect(
		panel.contains("WeaponForge.classify"),
		"面板必须走 WeaponForge.classify 判定配方"
	)
	_expect(
		panel.contains("single_weapon_without_fuel") or panel.contains("_reason_text"),
		"面板必须把拒绝原因呈现给玩家"
	)


# ————————————————————————————————
# 工具
# ————————————————————————————————

func _weapon(item_id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		_expect(false, "武器物品缺失：%s" % item_id)
		return {}
	item["count"] = 1
	return item


func _module(item_id: String, count: int) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		_expect(false, "弹药模块物品缺失：%s" % item_id)
		return {}
	item["count"] = count
	return item


## 按物品表取一件任意物品并打上堆叠数（材料可以是配件/消耗品/装备，不限弹药）。
func _item(item_id: String, count: int) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		_expect(false, "物品缺失：%s" % item_id)
		return {}
	item["count"] = count
	return item


func _put(inventory: InventoryModule, item_id: String, count: int) -> void:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		_expect(false, "物品缺失：%s" % item_id)
		return
	var added := inventory.add_item(item, count)
	_expect(added > 0, "测试背包必须能放入 %s ×%d" % [item_id, count])


func _count_of(inventory: InventoryModule, item_id: String) -> int:
	var total := 0
	for entry in inventory.get_occupied_slots():
		var item := (entry as Dictionary).get("item", {}) as Dictionary
		if str(item.get("id", "")) == item_id:
			total += int((entry as Dictionary).get("count", 1))
	return total


func _weapon_count(inventory: InventoryModule) -> int:
	var total := 0
	for entry in inventory.get_occupied_slots():
		var item := (entry as Dictionary).get("item", {}) as Dictionary
		if str(item.get("type", "")) == "weapon":
			total += 1
	return total


## 取背包里最后一件武器（DLC 产出的那把）。
func _latest_weapon(inventory: InventoryModule) -> Dictionary:
	var found: Dictionary = {}
	var best_index := -1
	for entry in inventory.get_occupied_slots():
		var slot_index := int((entry as Dictionary).get("slot", -1))
		var item := (entry as Dictionary).get("item", {}) as Dictionary
		if str(item.get("type", "")) != "weapon":
			continue
		if slot_index > best_index:
			best_index = slot_index
			found = item
	return found
