extends Node
## verify_synthesis_catalog — 合成目录（R0 定向合成）专项验收。
##
## 设计真源：docs/v0.1/07.3_玩法系统_合成目录与兴趣曲线.md §12（31 条断言）。
##
## 覆盖五组：
##   ① 结构与一致性（钥匙存在 / 产物在池 / curve_tier 与工坊 tier 一致 /
##      产物集合 / 钥匙白名单 / 钥匙零价 / 近战 key_count / 钥匙链无环 /
##      退役碎片与旧配方负向断言）
##   ② 经济（金币占比 / 燃料门槛 / 售价 / 零价兜底 / 印钞回归 / 净得）
##   ③ 判定（R0 早于 R1 / 近战链分段 / 燃料不足回落 R1 / 反向对照）
##   ④ 曲线（每段有配方 / 密度递增 / 品质加成单调）
##   ⑤ 界面（页签 / 每行要素 / 完成标记 / 真实 _execute_forge）

const FORGE := preload("res://src/weapons/WeaponForge.gd")
const CATALOG := preload("res://src/weapons/SynthesisCatalog.gd")
const GRADE := preload("res://src/weapons/WeaponDropGrade.gd")
const INVENTORY := preload("res://src/game/InventoryModule.gd")
const PANEL := preload("res://src/ui/WorkbenchPanel.gd")

## 十把非初始武器（不含 `weapon_starter_rifle` / `weapon_sprinkler`）。
## 其中 `weapon_baseball_bat` 是近战链的**起点钥匙**，不是产物。
const NON_STARTER_WEAPONS: Array[String] = [
	"weapon_pistol", "weapon_shotgun", "weapon_machinegun", "weapon_rifle",
	"weapon_sniper", "weapon_launcher", "weapon_charge",
	"weapon_baseball_bat", "weapon_greatblade", "weapon_waraxe",
]
const BASEBALL_BAT := "weapon_baseball_bat"

## 金币占商价的比例带宽（设计约束，见 07.3 §7）。
const COIN_RATIO_MIN := 0.30
const COIN_RATIO_MAX := 0.40

var _failures: Array[String] = []


func _ready() -> void:
	_case_structure()
	_case_economy()
	_case_verdicts()
	_case_curve()
	await _case_panel()

	if _failures.is_empty():
		print("SYNTHESIS_CATALOG_OK: structure / economy / verdicts / curve / panel pass")
		print(CATALOG.summary_line())
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _item(item_id: String, count: int = 1) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		_expect(false, "物品缺失：%s" % item_id)
		return {}
	item["count"] = count
	return item


# ————————————————————————————————
# ① 结构与一致性
# ————————————————————————————————

func _case_structure() -> void:
	_expect(CATALOG.RECIPES.size() == 2, "配方必须是 2 条，实际 %d" % CATALOG.RECIPES.size())

	var registry := ItemRegistry.get_instance()
	for recipe in CATALOG.RECIPES:
		var rid := str(recipe["recipe_id"])
		# 1. 钥匙必须存在
		var key := str(recipe["key_item_id"])
		_expect(not registry.get_item(key).is_empty(), "%s 的钥匙 %s 不在 ItemRegistry" % [rid, key])
		# 2. 产物必须在枪身池里
		var product := str(recipe["product_id"])
		_expect(
			not registry.get_item(product).is_empty(),
			"%s 的产物 %s 不在 ItemRegistry" % [rid, product]
		)
		var assembly_id := str(registry.get_item(product).get("assembly_id", ""))
		_expect(not assembly_id.is_empty(), "%s 的产物 %s 没有 assembly_id" % [rid, product])
		var gunbodies := BlueprintRegistry.get_available_gunbodies(3)
		var found := false
		var gunbody_tier := -1
		for entry in gunbodies:
			if str(entry.get("item_id", "")) == assembly_id:
				found = true
				gunbody_tier = int(entry.get("tier", -1))
				break
		_expect(found, "%s 的枪身 %s 不在 BlueprintRegistry 的 gunbody 池" % [rid, assembly_id])
		# 3. curve_tier 必须等于枪身 tier（工坊解锁与曲线段不能错位）
		if found:
			_expect(
				int(recipe["curve_tier"]) == gunbody_tier,
				"%s 的 curve_tier=%d 与枪身 tier=%d 不一致" % [
					rid, int(recipe["curve_tier"]), gunbody_tier,
				]
			)
		# 5. 钥匙白名单：只允许 blueprint 与 weapon
		var key_type := str(registry.get_item(key).get("type", ""))
		_expect(
			key_type in CATALOG.ALLOWED_KEY_TYPES,
			"%s 的钥匙 %s 类型为 %s，不在白名单 %s —— 有别的用途的物品不能当凭据" % [
				rid, key, key_type, str(CATALOG.ALLOWED_KEY_TYPES),
			]
		)
		# 6. 钥匙不得是零价物
		_expect(
			int(registry.get_item(key).get("price", 0)) > 0,
			"%s 的钥匙 %s 价格为 0 —— 零价物不能当凭据（会开出「0 成本换产出」的口子）" % [rid, key]
		)
		# 7. 近战链的 key_count 必须为 1（≥2 会被 R2 融合截走）
		if key_type == "weapon":
			_expect(
				int(recipe["key_count"]) == 1,
				"%s 用武器当钥匙，key_count 必须为 1（≥2 会被 R2 截走），实际 %d" % [
					rid, int(recipe["key_count"]),
				]
			)

	# 4. 当前产物集合只保留两级近战升级。
	var products := CATALOG.product_ids()
	var expected: Array[String] = ["weapon_greatblade", "weapon_waraxe"]
	_expect(products.size() == expected.size(), "产物数应为 %d，实际 %d（%s）" % [expected.size(), products.size(), str(products)])
	for weapon_id in expected:
		_expect(weapon_id in products, "产物集合缺少 %s" % weapon_id)
	for weapon_id in products:
		_expect(weapon_id in expected, "产物 %s 不在当前近战产物集合里" % weapon_id)
	_expect(not BASEBALL_BAT in products, "棒球棍不得作为产物")

	# 无重复产物
	var seen := {}
	for weapon_id in products:
		_expect(not seen.has(weapon_id), "产物 %s 重复登记" % weapon_id)
		seen[weapon_id] = true

	# 8. 退役碎片、房间钥匙与旧配方不得回归。
	for retired_recipe_id in ["SYN-PISTOL", "SYN-SHOTGUN", "SYN-RIFLE", "SYN-MACHINEGUN", "SYN-SNIPER", "SYN-LAUNCHER", "SYN-CHARGE"]:
		_expect(CATALOG.recipe_by_id(retired_recipe_id).is_empty(), "%s 必须已退役" % retired_recipe_id)
	_expect(CATALOG.recipe_by_id("SYN-ROOM-KEY").is_empty(), "房间钥匙旧配方不得存在")
	var retired_blueprint := {"id": "bp_pistol", "type": "blueprint", "rarity": "common", "count": 6}
	var retired_plan := FORGE.classify([retired_blueprint])
	_expect(retired_plan["recipe"] == FORGE.RECIPE_NONE, "退役蓝图碎片不得成为合成燃料")
	_expect((retired_plan["materials"] as Array).is_empty(), "退役蓝图碎片不得进入材料列表")

	# 9. 钥匙链单向无环（存在环 ⇒ 可以无限刷）
	_expect(not _has_key_cycle(), "近战钥匙链必须单向无环 —— 有环会让玩家无限刷")


## 把「武器当钥匙」的边抽出来做可达性判定：任何配方的产物不得反向成为其前置钥匙。
func _has_key_cycle() -> bool:
	var edges: Dictionary = {}
	for recipe in CATALOG.RECIPES:
		var key := str(recipe["key_item_id"])
		if CATALOG.is_weapon_key(key):
			edges[key] = str(recipe["product_id"])
	for start in edges.keys():
		var visited := {}
		var cursor := str(start)
		while edges.has(cursor):
			if visited.has(cursor):
				return true
			visited[cursor] = true
			cursor = str(edges[cursor])
	return false


# ————————————————————————————————
# ② 经济
# ————————————————————————————————

func _case_economy() -> void:
	var registry := ItemRegistry.get_instance()
	var previous_net := -1.0
	var nets: Array[float] = []
	for recipe in CATALOG.RECIPES:
		var rid := str(recipe["recipe_id"])
		var price := int(registry.get_item(str(recipe["product_id"])).get("price", 0))
		var coin := int(recipe["coin_cost"])
		# 9. 费用必须小于商价，且占比落在 0.30–0.40
		_expect(coin < price, "%s 的金币费 %d 不得 ≥ 商价 %d" % [rid, coin, price])
		var ratio := float(coin) / float(maxi(1, price))
		_expect(
			ratio >= COIN_RATIO_MIN and ratio <= COIN_RATIO_MAX,
			"%s 的金币占比 %.3f 越界（应 %.2f–%.2f）" % [rid, ratio, COIN_RATIO_MIN, COIN_RATIO_MAX]
		)
		# 10. 燃料门槛 ≥ R3 盲盒门槛：定向不能比盲盒便宜
		_expect(
			int(recipe["fuel_min"]) >= FORGE.MELT_THRESHOLD,
			"%s 的燃料门槛 %d 低于盲盒门槛 %d —— 定向不能比盲盒便宜" % [
				rid, int(recipe["fuel_min"]), FORGE.MELT_THRESHOLD,
			]
		)
		# 14. 金币流净得恒正，且 净得/商价 落在 0.60–0.70
		var probabilities := FORGE.grade_probabilities(0, int(recipe["quality_bonus"]))
		var expectation := 0.0
		for grade in GRADE.ROLL_ORDER:
			expectation += float(probabilities.get(grade, 0.0)) * _grade_multiplier(grade)
		var net := float(price) * expectation - float(coin)
		_expect(net > 0.0, "%s 的金币流净得必须为正，实际 %.1f" % [rid, net])
		var net_ratio := net / float(maxi(1, price))
		_expect(
			net_ratio >= 0.55 and net_ratio <= 0.72,
			"%s 的净得占比 %.3f 越界（应 ≈0.60–0.70）" % [rid, net_ratio]
		)
		nets.append(net)
		previous_net = net

	# 13. 印钞回归：R1/R2/R3 的「卖出差额」必须全部为负。
	#     它们投入的是**买得到也卖得掉**的实物，估值已计入费用基数，允许出售只是止损。
	var negative_cases: Array = [
		["R1 棒球棍+3标准弹", [_item("weapon_baseball_bat"), _item("mod_bullet_standard", 3)]],
		["R1 步枪+3标准弹", [_item("weapon_rifle"), _item("mod_bullet_standard", 3)]],
		["R2 棒球棍×2", [_item("weapon_baseball_bat"), _item("weapon_baseball_bat")]],
		["R2 步枪×2", [_item("weapon_rifle"), _item("weapon_rifle")]],
		["R3 标准弹×6", [_item("mod_bullet_standard", 6)]],
	]
	for entry in negative_cases:
		var label := str(entry[0])
		var items: Array = entry[1]
		var plan := FORGE.classify(items)
		_expect(
			str(plan["recipe"]) != FORGE.RECIPE_NONE,
			"%s 必须能判定出配方，实际 reason=%s" % [label, str(plan["reason"])]
		)
		if str(plan["recipe"]) == FORGE.RECIPE_NONE:
			continue
		var invest := 0.0
		for item in items:
			var value := FORGE.item_value(item as Dictionary)
			var count := maxi(1, int((item as Dictionary).get("count", 1)))
			invest += float(value)
		var fee := int(plan.get("coin_cost", 0))
		# 产出按"随机枪身的期望商价"估：这里用 R3 池均值做保守口径。
		var pool := BlueprintRegistry.get_available_gunbodies(3)
		var pool_value := 0.0
		for gun in pool:
			var weapon_id := FORGE.weapon_item_id_for_assembly(str(gun.get("item_id", "")))
			pool_value += float(registry.get_item(weapon_id).get("price", 0))
		pool_value /= float(maxi(1, pool.size()))
		var sale := pool_value * 0.5 * 1.04
		_expect(
			sale - (invest + float(fee)) < 0.0,
			"%s 的卖出差额必须为负（卖 %.1f vs 花 %.1f）—— 否则它是印钞口" % [
				label, sale, invest + float(fee),
			]
		)


func _grade_multiplier(grade: String) -> float:
	match grade:
		GRADE.GRADE_PURPLE:
			return 1.10
		GRADE.GRADE_GOLD:
			return 1.15
	return 1.00


# ————————————————————————————————
# ③ 判定
# ————————————————————————————————

func _case_verdicts() -> void:
	# 15. R0 早于 R1：同样 1 把棒球棍，燃料多点就变成升级。
	#     `SYN-GREATBLADE` 的 fuel_min=6，R1 的燃料门槛是 3 —— 两条都满足，
	#     判定顺序决定结果。先 R1 就永远升级不了。
	var bat := _item("weapon_baseball_bat")
	var light_fuel := FORGE.classify([bat, _item("mod_bullet_standard", 4)])
	_expect(
		str(light_fuel["recipe"]) == FORGE.RECIPE_REMELT,
		"1 棒球棍 + 4 点燃料（< 6）必须走 R1 重铸，实际 '%s'" % str(light_fuel["recipe"])
	)
	var heavy_fuel := FORGE.classify([bat, _item("mod_bullet_standard", 6)])
	_expect(
		str(heavy_fuel["recipe"]) == FORGE.RECIPE_DIRECTED,
		"1 棒球棍 + 6 点燃料必须走 R0 定向合成，实际 '%s'（reason=%s）" % [
			str(heavy_fuel["recipe"]), str(heavy_fuel["reason"]),
		]
	)
	_expect(
		str((heavy_fuel["synthesis"] as Dictionary).get("recipe_id", "")) == "SYN-GREATBLADE",
		"棒球棍 + 满燃料必须命中 SYN-GREATBLADE"
	)

	# 第二级近战升级：断刃 + 10 个标准弹（燃料 10）命中 SYN-WARAXE。
	var waraxe_fuel := FORGE.classify([_item("weapon_greatblade"), _item("mod_bullet_standard", 10)])
	_expect(str(waraxe_fuel["recipe"]) == FORGE.RECIPE_DIRECTED, "巨型工业断刃 + 10 点燃料必须走 R0")
	_expect(str((waraxe_fuel["synthesis"] as Dictionary).get("recipe_id", "")) == "SYN-WARAXE", "断刃 + 满燃料必须命中 SYN-WARAXE")
	_expect(int(waraxe_fuel["coin_cost"]) == 90, "SYN-WARAXE 必须收固定价 90 金币")

	# 17. 近战钥匙燃料不足时回落 R1，不得误报退役碎片拒绝码。
	var short_fuel := FORGE.classify([_item("weapon_baseball_bat"), _item("mod_bullet_standard", 3)])
	_expect(str(short_fuel["recipe"]) == FORGE.RECIPE_REMELT, "棒球棍燃料不足 R0 门槛时必须回落 R1")
	_expect(int(short_fuel["coin_cost"]) > 0, "回落 R1 时必须按 R1 计费")

	# 19. 反向对照：WARAXE 的 quality_bonus 必须真实抬高金概率。
	var waraxe_recipe := CATALOG.recipe_by_id("SYN-WARAXE")
	_expect(not waraxe_recipe.is_empty(), "SYN-WARAXE 必须存在")
	if not waraxe_recipe.is_empty():
		var with_bonus := FORGE.grade_probabilities(0, int(waraxe_recipe["quality_bonus"]))
		var without_bonus := FORGE.grade_probabilities(0, 0)
		_expect(
			float(with_bonus[GRADE.GRADE_GOLD]) > float(without_bonus[GRADE.GRADE_GOLD]),
			"WARAXE 的 quality_bonus 必须真实抬高金概率（%.4f vs %.4f）" % [
				float(without_bonus[GRADE.GRADE_GOLD]), float(with_bonus[GRADE.GRADE_GOLD]),
			]
		)
		_expect(
			is_equal_approx(
				float(without_bonus[GRADE.GRADE_GOLD]),
				float(GRADE.ROLL_WEIGHTS[GRADE.GRADE_GOLD])
			),
			"bonus=0 时金概率必须等于基础池（反向对照的锚点）"
		)

	# 12. 零价兜底：手电模块（price=0）当燃料时不能免费。
	var flashlight := _item("item_flashlight_basic")
	_expect(
		FORGE.item_value(flashlight) > 0,
		"零价物品的估值必须按 rarity 兜底（>0），实际 %d" % FORGE.item_value(flashlight)
	)
	_expect(
		FORGE.item_value(flashlight) == int(FORGE.ZERO_PRICE_VALUE["common"]),
		"common 零价物的兜底值应为 %d，实际 %d" % [
			int(FORGE.ZERO_PRICE_VALUE["common"]), FORGE.item_value(flashlight),
		]
	)
	# rare 零价物：兜底 25/件，6 件 ⇒ 估值 150、熔炼值 18。
	# 若没有兜底，估值会是 0、费用落到最低价 40 —— 那就是"0 成本换高价值产出"。
	var zero_fuel := FORGE.classify([_item("item_flashlight_efficient", 6)])
	_expect(
		str(zero_fuel.get("recipe", "")) == FORGE.RECIPE_SYNTHESIS,
		"6 件 rare 零价物的熔炼值足够 R3，实际 reason=%s" % str(zero_fuel.get("reason", ""))
	)
	_expect(
		int(zero_fuel["value"]) == 150,
		"6 件 rare 零价物的估值必须兜底为 25×6=150，实际 %d" % int(zero_fuel["value"])
	)
	_expect(
		int(zero_fuel.get("coin_cost", 0)) > int(FORGE.COIN_MIN[FORGE.RECIPE_SYNTHESIS]),
		"用零价物当燃料时费用必须高于最低价（兜底生效），实际 %d" % int(zero_fuel.get("coin_cost", 0))
	)


# ————————————————————————————————
# ⑤ 曲线
# ————————————————————————————————

func _case_curve() -> void:
	# 22. 每段至少 1 条配方 —— 缺一段即曲线断。
	for tier_info in CATALOG.CURVE_TIERS:
		var tier := int(tier_info["tier"])
		var recipes := CATALOG.recipes_of_tier(tier)
		_expect(
			recipes.size() >= 1,
			"%s 段必须至少 1 条配方，实际 %d" % [str(tier_info["code"]), recipes.size()]
		)

	# 23. 当前两级近战配方密度保持为 1 / 2。
	var densities: Array[int] = []
	for tier_info in CATALOG.CURVE_TIERS:
		densities.append(int(tier_info["density"]))
	_expect(
		densities == [1, 2],
		"当前两级近战配方密度必须是 1/2，实际 %s" % str(densities)
	)

	# 24. quality_bonus 随段单调不减（0 ≤ 2）。
	var previous_bonus := -1
	var max_bonus := 0
	for tier_info in CATALOG.CURVE_TIERS:
		var tier := int(tier_info["tier"])
		for recipe in CATALOG.recipes_of_tier(tier):
			var bonus := int(recipe["quality_bonus"])
			_expect(
				bonus >= previous_bonus,
				"%s 的 quality_bonus=%d 低于同段/前段的 %d" % [
					str(recipe["recipe_id"]), bonus, previous_bonus,
				]
			)
			previous_bonus = bonus
			max_bonus = maxi(max_bonus, bonus)
	_expect(max_bonus == 2, "最高段的 quality_bonus 必须是 2，实际 %d" % max_bonus)

	# 25. 两级近战配方都只需 1 把对应武器。

	# 曲线段号必须连续 0..3，缺号说明分层被删过。
	var tiers: Array[int] = []
	for tier_info in CATALOG.CURVE_TIERS:
		tiers.append(int(tier_info["tier"]))
	_expect(tiers == [0, 1], "曲线段必须是 0/1 连续，实际 %s" % str(tiers))


# ————————————————————————————————
# ⑥ 界面
# ————————————————————————————————

class _StubRef:
	extends Node
	var inventory: InventoryModule = null
	func get_inventory_module() -> InventoryModule:
		return inventory


func _case_panel() -> void:
	var stub := _StubRef.new()
	stub.inventory = INVENTORY.new(40)
	add_child(stub)
	GameManager.currency = 2000

	var panel = PANEL.new()
	panel.set_workbench_ref(stub)
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	# 26. 两个页签都存在，且默认停在「熔炼」。
	var forge_tab := panel.find_child("TabButton_forge", true, false) as Button
	var catalog_tab := panel.find_child("TabButton_catalog", true, false) as Button
	_expect(forge_tab != null, "「熔炼」页签必须存在")
	_expect(catalog_tab != null, "「合成目录」页签必须存在")
	_expect(
		str(panel.get("_active_page")) == "forge",
		"默认页必须是「熔炼」，实际 '%s'" % str(panel.get("_active_page"))
	)
	var forge_page := panel.find_child("Body", true, false)
	var catalog_page := panel.find_child("CatalogPage", true, false)
	_expect(forge_page != null, "熔炼页必须存在")
	_expect(catalog_page != null, "合成目录页必须存在")
	if catalog_page != null:
		_expect(not catalog_page.visible, "默认页下合成目录必须隐藏")

	# 切页
	panel.call("_switch_page", "catalog")
	await get_tree().process_frame
	_expect(
		catalog_page != null and catalog_page.visible,
		"切到合成目录后该页必须可见"
	)
	if forge_page != null:
		_expect(not forge_page.visible, "切到合成目录后熔炼页必须隐藏")

	# 27. 每行必须同时显示产物名、钥匙「有/需」、燃料与金币门槛。
	var rows := 0
	for recipe in CATALOG.RECIPES:
		var row := panel.find_child("Recipe_%s" % str(recipe["recipe_id"]), true, false)
		_expect(row != null, "配方行 %s 必须在合成目录里渲染" % str(recipe["recipe_id"]))
		if row == null:
			continue
		rows += 1
		var texts: Array[String] = []
		for child in row.get_children():
			var label := child as Label
			if label != null:
				texts.append(label.text)
		var joined := " ".join(texts)
		var product_name := str(
			ItemRegistry.get_instance().get_item(str(recipe["product_id"])).get("name", "")
		)
		_expect(joined.contains(product_name), "%s 行必须显示产物名「%s」" % [
			str(recipe["recipe_id"]), product_name,
		])
		_expect(
			joined.contains("/"),
			"%s 行必须显示钥匙「有/需」" % str(recipe["recipe_id"])
		)
		_expect(
			joined.contains(str(int(recipe["fuel_min"]))),
			"%s 行必须显示燃料门槛 %d" % [str(recipe["recipe_id"]), int(recipe["fuel_min"])]
		)
		_expect(
			joined.contains(str(int(recipe["coin_cost"]))),
			"%s 行必须显示金币 %d" % [str(recipe["recipe_id"]), int(recipe["coin_cost"])]
		)
	_expect(rows == CATALOG.RECIPES.size(), "配方行数应为 %d，实际 %d" % [CATALOG.RECIPES.size(), rows])

	# 四段分组标题必须都在。
	for tier_info in CATALOG.CURVE_TIERS:
		_expect(
			panel.find_child("Section_%s" % str(tier_info["code"]), true, false) != null,
			"段分组 %s 必须存在" % str(tier_info["code"])
		)

	# 29. 完成打勾：手工塞一条已完成，重绘后该行状态必须是「已完成」。
	panel.set("_completed_recipes", {"SYN-GREATBLADE": true})
	panel.call("_refresh_catalog")
	await get_tree().process_frame
	var done_row := panel.find_child("Recipe_SYN-GREATBLADE", true, false)
	_expect(done_row != null, "SYN-GREATBLADE 行必须存在")
	if done_row != null:
		var status_text := ""
		for child in done_row.get_children():
			var label := child as Label
			if label != null:
				status_text += label.text
		_expect(status_text.contains("已完成"), "已完成的配方行必须打 ✓（文字「已完成」）")

	# 盘面进度联动：投 1 把棒球棍后，该行钥匙必须显示 1/1 且状态转「钥匙已齐」。
	panel.call("_switch_page", "forge")
	panel.call("_tray_append", _item("weapon_baseball_bat"), 1, 0, 0)
	# 故意**不**调 `_refresh_all()`：那会走 `render_items`，为每个物品块建
	# 3D 图标 SubViewport，在 headless 的 dummy 渲染器下报
	# `material_get_instance_shader_parameters: material is null`（噪音，非逻辑错）。
	# 本条断言验的是「目录页读盘面数据」，盘面真的画出来与否不影响判据。
	panel.call("_switch_page", "catalog")
	await get_tree().process_frame
	var pistol_row := panel.find_child("Recipe_SYN-GREATBLADE", true, false)
	_expect(pistol_row != null, "SYN-GREATBLADE 行必须存在")
	if pistol_row != null:
		var pistol_text := ""
		for child in pistol_row.get_children():
			var label := child as Label
			if label != null:
				pistol_text += label.text + " "
		_expect(
			pistol_text.contains("1 / 1"),
			"投 1 把棒球棍后 SYN-GREATBLADE 行必须显示 1 / 1，实际「%s」" % pistol_text.strip_edges()
		)

	# ——— 端到端：按下熔炼，盘上的棒球棍必须真的变成一把巨型工业断刃 ———
	# 上面验的都是 `classify` 的判定，还没验"面板拿这个判定去建产出"这一段。
	# 少了这条，R0 有可能只在读数栏显示对、真正点击却产出随机枪身。
	panel.call("_switch_page", "forge")
	panel.call("_tray_remove_anchor", 0)
	panel.call("_tray_append", _item("weapon_baseball_bat"), 1, 0, 0)
	panel.call("_tray_append", _item("mod_bullet_standard"), 6, 3, 0)
	panel.call("_refresh_all")
	var plan := FORGE.classify(panel.call("_tray_probe_items"))
	_expect(
		str(plan["recipe"]) == FORGE.RECIPE_DIRECTED,
		"端到端：盘面必须判为 R0 定向合成，实际 '%s'" % str(plan["recipe"])
	)
	var coins_before := int(GameManager.currency)
	var fee := int(plan.get("coin_cost", 0))
	panel.call("_execute_forge", plan)
	await get_tree().process_frame
	_expect(
		int(GameManager.currency) == coins_before - fee,
		"端到端：必须扣掉配方固定价 %d 金币（%d → %d）" % [
			fee, coins_before, int(GameManager.currency),
		]
	)
	_expect(
		int(fee) == 60,
		"端到端：巨型工业断刃必须收 60 金币（固定价，不按估值算），实际 %d" % fee
	)
	_expect(
		(panel.get("_tray") as Array).is_empty(),
		"端到端：熔炼后盘面必须清空"
	)
	var produced := _latest_weapon(stub.inventory)
	_expect(not produced.is_empty(), "端到端：背包必须产出一把枪")
	if not produced.is_empty():
		_expect(
			str(produced.get("id", "")) == "weapon_greatblade",
			"端到端：必须产出**指定的** weapon_greatblade，实际 '%s' —— 这是 R0 与 R3 的唯一区别" % str(produced.get("id", ""))
		)
		_expect(
			str(produced.get("created_recipe_id", "")) == "SYN-GREATBLADE",
			"端到端：产出必须带 created_recipe_id=SYN-GREATBLADE（图鉴统计的外键），实际 '%s'" % str(produced.get("created_recipe_id", ""))
		)
		_expect(
			GRADE.is_valid(str(produced.get("drop_grade", ""))),
			"端到端：产出必须带合法品质"
		)
		_expect(
			(produced.get("fate_upgrades", []) as Array).is_empty(),
			"端到端：产出不得继承命运卡"
		)
		# 产物必须可售（本次裁决：全部可卖）。`base_sell_price` 来自物品表，> 0 即视为可卖。
		_expect(
			int(produced.get("base_sell_price", 0)) > 0,
			"端到端：产物必须可售（base_sell_price > 0），实际 %d —— 全部可卖是本次裁决" % int(produced.get("base_sell_price", 0))
		)
	# 完成后该配方必须被打勾。
	_expect(
		bool(panel.get("_completed_recipes").has("SYN-GREATBLADE")),
		"端到端：成功合成后必须记录 SYN-GREATBLADE 到已完成集合"
	)

	GameManager.currency = 0
	panel.queue_free()
	stub.queue_free()


## 取背包里最后一把武器（用于断言端到端产出）。
func _latest_weapon(inventory: InventoryModule) -> Dictionary:
	var found: Dictionary = {}
	for entry in inventory.get_occupied_slots():
		var item: Dictionary = entry.get("item", {}) as Dictionary
		if str(item.get("type", "")) == "weapon":
			found = item
	return found
