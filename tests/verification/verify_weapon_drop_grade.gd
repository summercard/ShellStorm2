extends Node
## verify_weapon_drop_grade — 掉落枪械三档品质（蓝 / 紫 / 金）专项验收。
##
## 业主口径（2026-10-18）：蓝=基础；紫=伤害+10%、命运卡格子+2；金=伤害+15%、格子+4。
##
## 覆盖：
##   ① 规格自洽（权重和 = 1、加成逐值）
##   ② 掷骰分布收敛
##   ③ 掉落边界逐把掷骰，非枪械不写品质
##   ④ 运行时伤害倍率真的生效（装配树出口）
##   ⑤ **反复读档不复利**（快照不存倍率）
##   ⑥ 同 seed 可复现
##   ⑦ 掉落文字体现品质
##   ⑧ 反向对照：未知品质不得凭空加强

const GRADE := preload("res://src/weapons/WeaponDropGrade.gd")
const BULLET := preload("res://src/weapons/WeaponBulletDrop.gd")
const SERVICE := preload("res://src/rewards/RewardService.gd")
const INSTANCE := preload("res://src/weapons/WeaponInstance.gd")

const SAMPLES := 20000
const TOLERANCE := 0.01

var _failures: Array[String] = []


func _ready() -> void:
	_case_spec()
	_case_roll_distribution()
	_case_apply_to_item()
	_case_reward_service_rolls_only_weapons()
	_case_runtime_damage_multiplier()
	_case_reload_no_compound()
	_case_deterministic()
	_case_label()
	_case_bullet_spec()
	_case_bullet_bound_on_drop()
	_case_bullet_lock_guards()

	if _failures.is_empty():
		print("WEAPON_DROP_GRADE_OK: spec / distribution / drop boundary / runtime multiplier / reload idempotence / determinism / label / bound-bullet / lock-guards pass")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _case_spec() -> void:
	var total := 0.0
	for grade in GRADE.ROLL_ORDER:
		total += float(GRADE.ROLL_WEIGHTS[grade])
	_expect(is_equal_approx(total, 1.0), "品质权重之和必须为 1.0，实际 %.4f" % total)
	_expect(is_equal_approx(GRADE.damage_multiplier(GRADE.GRADE_BLUE), 1.00), "蓝色伤害倍率必须为 1.00")
	_expect(is_equal_approx(GRADE.damage_multiplier(GRADE.GRADE_PURPLE), 1.10), "紫色伤害倍率必须为 1.10")
	_expect(is_equal_approx(GRADE.damage_multiplier(GRADE.GRADE_GOLD), 1.15), "金色伤害倍率必须为 1.15")
	_expect(GRADE.fate_slot_bonus(GRADE.GRADE_BLUE) == 0, "蓝色命运槽加成必须为 0")
	_expect(GRADE.fate_slot_bonus(GRADE.GRADE_PURPLE) == 2, "紫色命运槽加成必须为 +2")
	_expect(GRADE.fate_slot_bonus(GRADE.GRADE_GOLD) == 4, "金色命运槽加成必须为 +4")


func _case_roll_distribution() -> void:
	var counts := {GRADE.GRADE_BLUE: 0, GRADE.GRADE_PURPLE: 0, GRADE.GRADE_GOLD: 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for _index in range(SAMPLES):
		counts[GRADE.roll(rng.randf())] += 1
	for grade in GRADE.ROLL_ORDER:
		var observed := float(counts[grade]) / float(SAMPLES)
		var expected := float(GRADE.ROLL_WEIGHTS[grade])
		_expect(
			absf(observed - expected) <= TOLERANCE,
			"品质 %s 实测频率 %.4f 偏离期望 %.4f 超过 %.2f" % [grade, observed, expected, TOLERANCE]
		)
	# 边界：0 必出蓝、接近 1 必出金（防止累计判断的 <= / < 写错档）
	_expect(GRADE.roll(0.0) == GRADE.GRADE_BLUE, "抽样 0.0 必须落蓝色")
	_expect(GRADE.roll(0.9999) == GRADE.GRADE_GOLD, "抽样 0.9999 必须落金色")


func _case_apply_to_item() -> void:
	var base := ItemRegistry.get_instance().get_item("weapon_rifle")
	var blue := GRADE.apply_to_item(base, GRADE.GRADE_BLUE)
	var purple := GRADE.apply_to_item(base, GRADE.GRADE_PURPLE)
	var gold := GRADE.apply_to_item(base, GRADE.GRADE_GOLD)
	var base_capacity := int(blue.get("fate_slot_capacity", 0))
	_expect(base_capacity >= 8, "蓝色命运槽应取物品基线（>=8），实际 %d" % base_capacity)
	_expect(int(purple.get("fate_slot_capacity", 0)) == base_capacity + 2, "紫色命运槽应为基线 +2")
	_expect(int(gold.get("fate_slot_capacity", 0)) == base_capacity + 4, "金色命运槽应为基线 +4")
	_expect(str(blue.get("drop_grade", "")) == GRADE.GRADE_BLUE, "物品字典必须写入 drop_grade")
	# 嵌套层同步：WeaponInstance.from_item 会优先读顶层，但存档兼容层可能只读嵌套，
	# 两处不同步会让同一把枪在背包里是紫、在装配时变蓝。
	var nested_purple := purple.get("weapon_instance", {}) as Dictionary
	_expect(
		str(nested_purple.get("drop_grade", "")) == GRADE.GRADE_PURPLE,
		"weapon_instance 嵌套层必须同步 drop_grade"
	)
	_expect(
		int(nested_purple.get("fate_slot_capacity", 0)) == base_capacity + 2,
		"weapon_instance 嵌套层必须同步命运槽"
	)
	# 入参不得被就地改写（池成员是同一次击杀共享的副本）
	_expect(not base.has("drop_grade"), "apply_to_item 不得就地改写入参")
	# 幂等守卫：对已带品质的物品再调一次，不得再加格子
	var again := GRADE.apply_to_item(purple, GRADE.GRADE_PURPLE)
	_expect(
		int(again.get("fate_slot_capacity", 0)) == base_capacity + 2,
		"重复 apply 不得二次叠加命运槽：期望 %d，实际 %d" % [base_capacity + 2, int(again.get("fate_slot_capacity", 0))]
	)


func _case_reward_service_rolls_only_weapons() -> void:
	var report := SERVICE.resolve({
		"spec_id": "grade:weapons",
		"entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 4}],
	}, {"seed": 20261018, "floor": 1})
	_expect(bool(report.get("ok", false)), "武器掉落规格应解析成功：%s" % str(report.get("errors", [])))
	var grants := report.get("grants", []) as Array
	_expect(grants.size() == 4, "count=4 的枪械必须产出 4 个独立 grant，实际 %d" % grants.size())
	var seen: Dictionary = {}
	for value in grants:
		var item := (value as Dictionary).get("item", {}) as Dictionary
		var grade := str(item.get("drop_grade", ""))
		_expect(GRADE.is_valid(grade), "掉落枪械必须带合法品质，实际 '%s'" % grade)
		var instance_id := str(item.get("weapon_instance_id", ""))
		if not instance_id.is_empty():
			seen[instance_id] = true
	_expect(seen.size() == grants.size(), "4 把枪必须是 4 个不同实例")
	# 4 把全是蓝的概率是 0.7^4 ≈ 24%，测试有 1/4 概率假绿 —— 用 12 把把概率压到 1.4%。
	var wide := SERVICE.resolve({
		"spec_id": "grade:weapons-wide",
		"entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 12}],
	}, {"seed": 20261018, "floor": 1})
	var distinct: Dictionary = {}
	for value in wide.get("grants", []):
		var item := (value as Dictionary).get("item", {}) as Dictionary
		distinct[str(item.get("drop_grade", ""))] = true
	_expect(distinct.size() >= 2, "12 把枪不应全部同一品质（实测只有 %s）" % str(distinct.keys()))

	var non_weapon := SERVICE.resolve({
		"spec_id": "grade:non-weapon",
		"entries": [{"kind": "item", "item_id": "mod_bullet_standard", "count": 1}],
	}, {"seed": 20261018, "floor": 1})
	var module_item := (non_weapon.get("grants", [])[0] as Dictionary).get("item", {}) as Dictionary
	_expect(not module_item.has("drop_grade"), "非枪械不得写 drop_grade")


func _case_runtime_damage_multiplier() -> void:
	var base := ItemRegistry.get_instance().get_item("weapon_rifle")
	var blue_stats := _stats_for(base, GRADE.GRADE_BLUE)
	var purple_stats := _stats_for(base, GRADE.GRADE_PURPLE)
	var gold_stats := _stats_for(base, GRADE.GRADE_GOLD)
	var blue_damage := float(blue_stats.get("damage", 0))
	var purple_damage := float(purple_stats.get("damage", 0))
	var gold_damage := float(gold_stats.get("damage", 0))
	_expect(blue_damage > 0.0, "蓝色枪械伤害必须大于 0")
	_expect(
		is_equal_approx(purple_damage, float(int(round(blue_damage * 1.10)))),
		"紫色伤害应为蓝色 ×1.10（取整），实测 %.2f vs %.2f" % [purple_damage, blue_damage * 1.10]
	)
	_expect(
		is_equal_approx(gold_damage, float(int(round(blue_damage * 1.15)))),
		"金色伤害应为蓝色 ×1.15（取整），实测 %.2f vs %.2f" % [gold_damage, blue_damage * 1.15]
	)
	# 子弹伤害必须同步：远程最终伤害 = damage + bullet_damage，只乘其一等于打折。
	if blue_stats.has("bullet_damage"):
		_expect(
			is_equal_approx(
				float(purple_stats.get("bullet_damage", 0)),
				float(int(round(float(blue_stats["bullet_damage"]) * 1.10)))
			),
			"紫色必须同步放大 bullet_damage"
		)


func _case_reload_no_compound() -> void:
	var base := ItemRegistry.get_instance().get_item("weapon_rifle")
	var purple := GRADE.apply_to_item(base, GRADE.GRADE_PURPLE)
	var expected_capacity := int(purple.get("fate_slot_capacity", 0))
	var expected_damage := float(_stats_for(base, GRADE.GRADE_PURPLE).get("damage", 0))
	var item := purple
	# 三次「存档 → 读档」往返：容量与伤害都必须逐值不变。
	for round_index in range(3):
		var instance := INSTANCE.from_item(item)
		_expect(instance != null, "第 %d 次读档必须成功构造实例" % round_index)
		if instance == null:
			return
		_expect(
			instance.fate_slot_capacity == expected_capacity,
			"第 %d 次读档命运槽复利：期望 %d，实际 %d" % [round_index, expected_capacity, instance.fate_slot_capacity]
		)
		var tree := instance.build_runtime_tree()
		_expect(tree != null, "第 %d 次读档必须建出装配树" % round_index)
		if tree == null:
			return
		var damage := float(tree.get_computed_stats().get("damage", 0))
		_expect(
			is_equal_approx(damage, expected_damage),
			"第 %d 次读档伤害复利：期望 %.2f，实际 %.2f" % [round_index, expected_damage, damage]
		)
		item = instance.to_item_dictionary()
		tree.free()


func _case_deterministic() -> void:
	var spec := {
		"spec_id": "grade:deterministic",
		"entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 12}],
	}
	var first_report := SERVICE.resolve(spec, {"seed": 777, "floor": 1})
	var second_report := SERVICE.resolve(spec, {"seed": 777, "floor": 1})
	var first := _grades_of(first_report)
	var second := _grades_of(second_report)
	_expect(first == second, "同 seed 同 spec 的品质序列必须逐位一致：%s vs %s" % [str(first), str(second)])
	# 实例 ID 必须每把不同（同一条 spec 里不能重复发同一把枪）
	var ids := _instance_ids_of(first_report)
	var unique: Dictionary = {}
	for id in ids:
		unique[id] = true
	_expect(unique.size() == ids.size(), "同次掉落的每把枪必须是独立实例：%d/%d" % [unique.size(), ids.size()])
	var other := _grades_of(SERVICE.resolve(spec, {"seed": 778, "floor": 1}))
	_expect(first != other, "不同 seed 应得到不同品质序列（否则品质没在掷骰）：%s vs %s" % [str(first), str(other)])


func _case_label() -> void:
	var blue := {"type": "weapon", "name": "步枪", "drop_grade": GRADE.GRADE_BLUE}
	var purple := {"type": "weapon", "name": "步枪", "drop_grade": GRADE.GRADE_PURPLE}
	var gold := {"type": "weapon", "name": "步枪", "drop_grade": GRADE.GRADE_GOLD}
	_expect(GRADE.label_for(blue) == "蓝｜步枪", "蓝色名牌应为「蓝｜步枪」，实际 '%s'" % GRADE.label_for(blue))
	_expect(GRADE.label_for(purple) == "紫｜步枪", "紫色名牌应为「紫｜步枪」，实际 '%s'" % GRADE.label_for(purple))
	_expect(GRADE.label_for(gold) == "金｜步枪", "金色名牌应为「金｜步枪」，实际 '%s'" % GRADE.label_for(gold))
	_expect(GRADE.label_for({"type": "module", "name": "标准子弹模块"}) == "标准子弹模块", "非枪械名牌只写名字")
	# 反向对照：未知品质不得凭空套一个前缀，也不得加强
	_expect(
		GRADE.label_for({"type": "weapon", "name": "步枪", "drop_grade": "rainbow"}) == "步枪",
		"未知品质不得出现在名牌上"
	)
	_expect(is_equal_approx(GRADE.damage_multiplier("rainbow"), 1.0), "未知品质伤害倍率必须回落到 1.0")
	_expect(GRADE.fate_slot_bonus("rainbow") == 0, "未知品质命运槽加成必须回落到 0")


func _case_bullet_spec() -> void:
	var total := 0.0
	for bullet_id in BULLET.ROLL_ORDER:
		total += float(BULLET.ROLL_WEIGHTS[bullet_id])
	_expect(is_equal_approx(total, 100.0), "弹药模块权重之和必须为 100，实际 %.2f" % total)
	for bullet_id in BULLET.ROLL_ORDER:
		_expect(
			ItemRegistry.get_instance().has_item(bullet_id),
			"弹药模块池里的 '%s' 必须真实存在于物品表" % bullet_id
		)
		var item := ItemRegistry.get_instance().get_item(bullet_id)
		_expect(
			str(item.get("subtype", "")) == "bullet",
			"'%s' 必须是 bullet 子类的模块" % bullet_id
		)
	# 分布收敛：按 100 分制的权重表折算成频率，容差 1.5 个百分点。
	var samples := 20000
	var counts: Dictionary = {}
	for bullet_id in BULLET.ROLL_ORDER:
		counts[bullet_id] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for _index in range(samples):
		counts[BULLET.roll(rng.randf())] += 1
	for bullet_id in BULLET.ROLL_ORDER:
		var observed := 100.0 * float(counts[bullet_id]) / float(samples)
		var expected := float(BULLET.ROLL_WEIGHTS[bullet_id]) / total * 100.0
		_expect(
			absf(observed - expected) <= 1.5,
			"弹药 %s 实测 %.2f%% 偏离期望 %.2f%% 超过 1.5" % [bullet_id, observed, expected]
		)
	# 边界：0 落首项、接近 1 落末项（防累计判断写错档）
	_expect(BULLET.roll(0.0) == BULLET.ROLL_ORDER[0], "抽样 0.0 应落首个弹药模块")
	_expect(
		BULLET.roll(0.9999) == BULLET.ROLL_ORDER[BULLET.ROLL_ORDER.size() - 1],
		"抽样 0.9999 应落最后一个弹药模块"
	)
	_expect(BULLET.normalize("mod_bullet_unknown") == BULLET.FALLBACK_BULLET, "未知弹药模块必须回落标准弹")
	_expect(BULLET.is_melee_weapon({"subtype": "melee_weapon"}), "近战判定必须认 subtype")
	_expect(BULLET.is_melee_weapon({"tags": ["weapon", "melee"]}), "近战判定必须认 melee 标签")
	_expect(not BULLET.is_melee_weapon({"subtype": "gun_body"}), "远程枪不得被判成近战")


func _case_bullet_bound_on_drop() -> void:
	# ① 远程枪：带绑定弹药 + 锁定
	var report := SERVICE.resolve({
		"spec_id": "bullet:ranged",
		"entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 1}],
	}, {"seed": 20261018, "floor": 1})
	_expect(bool(report.get("ok", false)), "远程枪掉落规格应解析成功：%s" % str(report.get("errors", [])))
	var gun_item := (report.get("grants", [])[0] as Dictionary).get("item", {}) as Dictionary
	_expect(bool(gun_item.get("bullet_module_locked", false)), "掉落枪必须标记弹药模块绑定锁定")
	var instance := INSTANCE.from_item(gun_item)
	_expect(instance != null, "掉落枪必须能构造实例")
	if instance == null:
		return
	_expect(instance.bullet_module_locked, "实例必须继承锁定标记")
	var bullet_module := instance.get_presentation_snapshot().get("bullet_module", {}) as Dictionary
	var first_bullet := str(bullet_module.get("item_id", ""))
	_expect(BULLET.is_valid(first_bullet), "掉落枪必须自带一个合法弹药模块，实际 '%s'" % first_bullet)

	# ② 读档不换弹：连做三次「序列化 → 反序列化」，弹种必须一致
	var item := instance.to_item_dictionary()
	for round_index in range(3):
		var reloaded := INSTANCE.from_item(item)
		_expect(reloaded != null, "第 %d 次读档必须成功" % round_index)
		if reloaded == null:
			return
		var reloaded_module := reloaded.get_presentation_snapshot().get("bullet_module", {}) as Dictionary
		_expect(
			str(reloaded_module.get("item_id", "")) == first_bullet,
			"第 %d 次读档弹种被换掉了：期望 %s，实际 %s" % [
				round_index, first_bullet, str(reloaded_module.get("item_id", "")),
			]
		)
		_expect(reloaded.bullet_module_locked, "第 %d 次读档丢失绑定锁定标记" % round_index)
		item = reloaded.to_item_dictionary()

	# ③ 运行时树必须带锁（三个换弹入口读的是树上的字段）
	var tree := instance.build_runtime_tree()
	_expect(tree != null, "掉落枪必须能建出运行时树")
	if tree != null:
		_expect(tree.bullet_module_locked, "运行时树必须带弹药绑定锁，否则局内快捷装配会绕过去")
		tree.free()

	# ④ 近战：不配弹、不锁
	var melee_report := SERVICE.resolve({
		"spec_id": "bullet:melee",
		"entries": [{"kind": "item", "item_id": "weapon_baseball_bat", "count": 1}],
	}, {"seed": 20261018, "floor": 1})
	var melee_item := (melee_report.get("grants", [])[0] as Dictionary).get("item", {}) as Dictionary
	_expect(not bool(melee_item.get("bullet_module_locked", true)), "近战武器不得标记弹药绑定（它没有弹药槽）")
	var melee_instance := INSTANCE.from_item(melee_item)
	if melee_instance != null:
		_expect(
			(melee_instance.get_presentation_snapshot().get("bullet_module", {}) as Dictionary).is_empty(),
			"近战武器不得带弹药模块"
		)

	# ⑤ 非掉落来源（出厂枪 / 蓝图合成 / 商人）不锁，仍可自由换弹
	var fresh := INSTANCE.from_item(ItemRegistry.get_instance().get_item("weapon_rifle"))
	_expect(fresh != null and not fresh.bullet_module_locked, "非掉落枪不得被锁弹药")


func _case_bullet_lock_guards() -> void:
	# 换弹执行入口各自独立：任何一条漏了判据，「不能拆卸」就是假的。
	# 2026-10-18：武器改造台改为 6×6 炼金盘，**不再提供换弹入口**，
	# 因此把它的守卫改成反向门禁 —— 钉住"这个旁路不许再长回来"。
	# I 键背包的安装最终仍走 Dungeon3D._install_weapon_module_from_item，判据未丢。
	var guards := {
		"res://src/player3d/Player3D.gd": "install_bullet_module_to_weapon_slot",
		"res://src/world3d/Dungeon3D.gd": "_install_weapon_module_from_item",
	}
	for path in guards.keys():
		var source := FileAccess.get_file_as_string(str(path))
		_expect(not source.is_empty(), "换弹入口源文件读取失败：%s" % path)
		_expect(
			source.contains("bullet_module_locked"),
			"%s 的 %s 缺少弹药绑定判据 —— 该入口能绕过「不可拆卸」" % [path, guards[path]]
		)
	var forge_source := FileAccess.get_file_as_string("res://src/ui/WorkbenchPanel.gd")
	_expect(not forge_source.is_empty(), "改造台源文件读取失败")
	_expect(
		not forge_source.contains("bullet_module_install") and not forge_source.contains("SlotType.BULLET"),
		"武器改造台不得重新长出换弹旁路 —— 它现在只做炼金，换弹统一走 I 键背包"
	)


func _stats_for(base_item: Dictionary, grade: String) -> Dictionary:
	var item := GRADE.apply_to_item(INSTANCE.ensure_weapon_item(base_item), grade)
	var instance := INSTANCE.from_item(item)
	if instance == null:
		return {}
	var tree := instance.build_runtime_tree()
	if tree == null:
		return {}
	var stats := tree.get_computed_stats()
	tree.free()
	return stats


func _grades_of(report: Dictionary) -> Array:
	var out: Array = []
	for value in report.get("grants", []):
		var item := (value as Dictionary).get("item", {}) as Dictionary
		out.append(str(item.get("drop_grade", "")))
	return out


func _instance_ids_of(report: Dictionary) -> Array:
	var out: Array = []
	for value in report.get("grants", []):
		var item := (value as Dictionary).get("item", {}) as Dictionary
		out.append(str(item.get("weapon_instance_id", "")))
	return out
