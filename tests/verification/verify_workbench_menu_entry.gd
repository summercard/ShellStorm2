extends Node
## verify_workbench_menu_entry — 武器改造台在 99F 基地的**设施入口**验收。
##
## 业主 2026-10-19 口径：
## 「99 层基地里面的左下角的部分有一个建筑设施是怪物档案馆，就是在西边的门的下面，
##   帮我把这怪物档案馆的这个……开始的这个指向给它转到这个功能的这个界面这边来，
##   就是同样的设置换一个功能。」
##
## 也就是说：**位点、模型、E 键交互都不动，只把打开的界面换成武器改造台。**
## 这条验收盯的正是「不动的那部分有没有被误伤」和「换的那部分有没有真的生效」。
##
## ## 为什么用真实场景而不是 mock
##
## 这一段最容易碎的地方是**装配**：设施 id → catalog → 菜单场景 → CanvasLayer →
## 面板 Control → 背包注入。每一环都对，但接不上就什么都不发生（点 E 没反应，
## 或者菜单打开了却是空壳）。所以整条链在真 `TowerDescent3D` 里跑一遍。

const TOWER := preload("res://scenes/TowerDescent3D.tscn")

## 改造台在 99F 的原位点（先前是怪物档案室）。业主描述是"左下角、西边门下面"，
## 所以断言写成半空间而不是精确坐标 —— 位点允许美术微调，但不能跑到另一边去。
const SITE_IS_WEST := -5.0
const SITE_IS_SOUTH := 5.0

## 这个位点用的美术资产包。业主只要求换功能，模型不许跟着换。
const EXPECTED_ASSET := "weapon_workshop_station"

var _failures: Array[String] = []


func _ready() -> void:
	var world := TOWER.instantiate() as TowerDescent3D
	world.test_mode = true
	add_child(world)
	for _frame in 14:
		await get_tree().process_frame

	var facilities := _collect_facilities()
	_expect(
		facilities.size() == 8,
		"99F 基地应保持 8 个常驻设施（本次只换一个的功能，不增不减），实际 %d" % facilities.size()
	)

	# ——— ① 旧的入口已经不在 ———
	_expect(
		not facilities.has("monster_archive"),
		"99F 不应再实例化 monster_archive —— 那个位点的功能已经被换掉"
	)

	# ——— ② 新入口在，且就在原位点 ———
	var forge := facilities.get("weapon_forge") as BaseFacility3D
	_expect(forge != null, "99F 必须实例化 weapon_forge（武器改造台）")
	if forge == null:
		_finish(world)
		return
	var site := forge.global_position
	_expect(
		site.x <= SITE_IS_WEST,
		"改造台必须在**西侧**（业主：西边门下面），实际 x=%.2f" % site.x
	)
	_expect(
		site.z >= SITE_IS_SOUTH,
		"改造台必须在**南侧/下方**（业主：左下角），实际 z=%.2f" % site.z
	)

	# ——— ③ 模型没换：还是那台武器工作台 ———
	_expect(
		EXPECTED_ASSET in str(forge.get_meta("asset_source", "")),
		"改造台必须沿用原位的 %s 模型（业主只要求换功能，不是换家具），实际 asset_source=%s"
		% [EXPECTED_ASSET, str(forge.get_meta("asset_source", ""))]
	)

	# ——— ④ 名字与交互动词都跟着功能走 ———
	_expect(
		str(forge.display_name) == "武器改造台",
		"设施名必须是「武器改造台」，实际「%s」" % str(forge.display_name)
	)
	_expect(
		"[E] 打开 武器改造台" == str(forge.prompt_label.text),
		"E 键提示必须是「[E] 打开 武器改造台」（action_kind=menu 时动词取「打开」），实际「%s」"
		% str(forge.prompt_label.text)
	)

	# ——— ⑤ catalog 与菜单场景都真的存在 ———
	var definition: Dictionary = BaseFacilityCatalog.get_definition("weapon_forge")
	_expect(not definition.is_empty(), "BaseFacilityCatalog 必须登记 weapon_forge")
	_expect(
		str(definition.get("action_path", "")) == "res://scenes/WorkbenchMenu.tscn",
		"catalog 的 action_path 必须指向 WorkbenchMenu.tscn，实际 %s" % str(definition.get("action_path", ""))
	)
	_expect(
		ResourceLoader.exists("res://scenes/WorkbenchMenu.tscn", "PackedScene"),
		"scenes/WorkbenchMenu.tscn 必须存在且可加载"
	)
	# 怪物档案室没有下线，只是没有地面入口 —— 以后要带回时不该还要重写组件。
	_expect(
		BaseFacilityCatalog.has_facility("monster_archive"),
		"catalog 必须保留 monster_archive（下线的是入口，不是设施能力）"
	)
	_expect(
		ResourceLoader.exists("res://scenes/MonsterArchiveMenu.tscn", "PackedScene"),
		"scenes/MonsterArchiveMenu.tscn 必须保留可加载"
	)

	# ——— ⑥ 真按一次 E：整条装配链必须接通 ———
	world.call("_on_facility_activated", forge)
	for _frame in 4:
		await get_tree().process_frame
	var menu = world.get("_active_facility_menu")
	_expect(menu != null, "激活改造台必须真的打开菜单")
	if menu == null:
		_finish(world)
		return
	_expect(
		menu is WorkbenchMenu,
		"打开的必须是 WorkbenchMenu，实际 %s" % str(menu.get_class())
	)
	var panel: WorkbenchPanel = null
	if menu.has_method("get_panel"):
		panel = menu.call("get_panel") as WorkbenchPanel
	_expect(panel != null, "WorkbenchMenu 里必须真的挂上 WorkbenchPanel（否则是空壳菜单）")
	if panel == null:
		_finish(world)
		return
	# 面板的三条依赖：背包（决定投什么）、玩家（锁输入）、金币（算费用）。
	_expect(panel.get("_inventory") != null, "面板必须拿到背包模块，否则盘面拖不进东西")
	_expect(panel.get("_player") != null, "面板必须拿到玩家，否则打开时不会锁输入")
	_expect(panel.get("_forge_button") != null, "面板必须真的构建出熔炼按钮（不是只 new 了个 Control）")
	_expect(
		panel.get("_body_tray_column") != null,
		"面板必须构建出炼炉栏 —— 它是闸门覆盖范围的依据"
	)

	# ——— ⑦ 打开期间基地 HUD 必须让位 ———
	# 改造台遮罩是 0.58 的 PRISM_DIM（刻意让 3D 实景可见），而基地 HUD 是**另一个
	# CanvasLayer**、层号与菜单相同：不显式隐藏，血条/金币/小地图会与炼炉叠在一起，
	# 读起来不是"两个界面"，是"界面坏了"。这条断言钉住这个行为。
	var hud := world.get_node_or_null("HUD") as CanvasLayer
	_expect(hud != null, "99F 必须有基地 HUD")
	if hud != null:
		_expect(
			not hud.visible,
			"改造台打开期间基地 HUD 必须隐藏（否则与面板叠成一团）"
		)

	# ——— ⑧ 打开期间再点别的设施不得叠加 ———
	world.call("_on_facility_activated", facilities.get("vault"))
	for _frame in 2:
		await get_tree().process_frame
	_expect(
		world.get("_active_facility_menu") == menu,
		"已有菜单打开时，再激活别的设施不得叠出第二个菜单"
	)

	# ——— ⑨ 关闭：菜单释放、引用清空、HUD 回来 —
	panel.call("_close")
	for _frame in 4:
		await get_tree().process_frame
	_expect(
		world.get("_active_facility_menu") == null,
		"关闭面板后 `_active_facility_menu` 必须清空（否则设施从此再也点不开）"
	)
	if hud != null:
		_expect(bool(hud.visible), "关闭改造台后基地 HUD 必须恢复可见")

	_finish(world)


func _collect_facilities() -> Dictionary:
	var result: Dictionary = {}
	for node in get_tree().get_nodes_in_group("base_facility"):
		var facility := node as BaseFacility3D
		if facility == null:
			continue
		result[facility.facility_id] = facility
	return result


func _finish(world: Node) -> void:
	var locked := false
	if world != null and is_instance_valid(world):
		var player := world.get("player") as Player3D
		if player != null and player.has_method("is_input_locked"):
			locked = bool(player.call("is_input_locked"))
		world.queue_free()
	# 面板关闭必须把输入还回去，否则玩家在基地里动不了。
	_expect(not locked, "关闭改造台后玩家输入必须解锁（否则基地里走不动）")
	if _failures.is_empty():
		print(
			"WORKBENCH_MENU_ENTRY_OK: 99F 仍是 8 个设施；原怪物档案室位点（西侧下方）已换成武器改造台，"
			+ "模型沿用 49_武器工作台、E 提示「[E] 打开 武器改造台」；激活真的打开 WorkbenchMenu→WorkbenchPanel 并注入背包/玩家；"
			+ "打开期间基地 HUD 让位、关闭后释放菜单并恢复 HUD 与输入；怪物档案室组件仍保留可恢复"
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
