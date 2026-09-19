extends Node
## 测试关卡99（远征体系第二张独立关卡）接入验收。
##
## 与 verify_expedition_level01_flow 刻意分工：那一份钉的是「远征关卡01 的玩法闭环」；
## 这一份钉的是「再加一张关卡到底要动哪些地方」这条可复用契约，只覆盖三件事：
##   1) 登记：GameDesignConfig 关卡清单里有 99，且它指向自己的场景与运行时标识；
##   2) 设计源：99 的 L1/L2/L3 能被加载，且**运行时真的走数据驱动**（不是内置房表）；
##   3) 入口：99F 远征情报室的选关菜单里出现「进入测试关卡99」按钮，
##      读取界面按待进入态决定终点（而不是硬编码远征关卡01）。
##
## 为什么必须单独一份、不能只靠 generate 单测：新关卡真正的失效方式全都是**静默**的 ——
##   * 房间运行时编号没跟运行时契约（`start` / `room_01..N` / `extraction`）对齐时，
##     几何校验与静态设计源校验全部通过，只是玩家出生点取不到房、撤离信标落在
##     一个不存在的房 id 上（`_commit_floor_bundle` 按 key 找房所以照样绿）；
##   * 内置远征房表硬编码 5 间内容房，2 间内容房的关卡一旦回退到它就会**多出 3 间房**，
##     而回退只在 `runtime_enabled` 缺失时才发生，没有任何报错；
##   * 菜单按钮绑错关卡 id 时按钮照样能点、读取界面照样能进，只是去了别的关卡。
## 这三类都只有「真装配一次 + 真读一次产出」才看得见，所以本脚本两件事都做。

const LEVEL_ID := "99"
const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const MENU_SCENE := "res://scenes/RogueMapSelectMenu.tscn"
const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
## 未指定关卡时的默认终点（远征关卡01）。新增关卡不得改变这条回退行为。
const DEFAULT_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const DEFAULT_DISPLAY_NAME := "远征关卡01"
const LEVEL_DISPLAY_NAME := "测试关卡99"
## 内置房表里远征恒为 5 间内容房。99 只有 2 间，因此「没有回退到内置房表」
## 本身就是一个可断言的事实 —— 见 _verify_design_source 与 _verify_level_scene。
const BUILTIN_EXPEDITION_CONTENT_ROOMS := 5

const SAFE_ROOM_SIZE := Vector2(15.0, 15.0)
const CONTENT_ROOM_SIZE := Vector2(25.0, 25.0)
const EXPECTED_ROOM_IDS: Array[String] = ["start", "room_01", "room_02", "extraction"]
const EXPECTED_MAIN_KEYS: Array[String] = ["room_01", "room_02"]
## 设计源里按房间钉死的内容类型（不是随机洗牌的），运行时必须逐值复现。
const EXPECTED_ROOM_TYPES := {
	"start": "STAIR_LOBBY",
	"room_01": "COMBAT",
	"room_02": "COMBAT",
	"extraction": "EXTRACTION",
}
const GENERATOR_SEED := 20260919


func _ready() -> void:
	var failures: Array[String] = []
	_verify_registry(failures)
	_verify_design_source(failures)
	await _verify_menu_entry(failures)
	_verify_loading_destination(failures)
	await _verify_level_scene(failures)
	# 待进入态是全局静态量：本脚本用过就必须还原，否则会影响同进程内后续断言。
	GameDesignConfig.pending_expedition_level_id = ""
	_report(failures)


# —— 1) 关卡登记 ——

func _verify_registry(failures: Array[String]) -> void:
	if not GameDesignConfig.expedition_level_ids().has(LEVEL_ID):
		failures.append("GameDesignConfig 关卡清单里没有测试关卡99：%s" % [
			GameDesignConfig.expedition_level_ids(),
		])
		return
	if GameDesignConfig.expedition_level_scene(LEVEL_ID) != LEVEL_SCENE:
		failures.append("测试关卡99 的到达场景不正确：%s" % GameDesignConfig.expedition_level_scene(LEVEL_ID))
	if GameDesignConfig.expedition_run_id(LEVEL_ID) != LEVEL_ID:
		failures.append("测试关卡99 的运行时标识不正确：%s" % GameDesignConfig.expedition_run_id(LEVEL_ID))
	if GameDesignConfig.expedition_level_display_name(LEVEL_ID) != LEVEL_DISPLAY_NAME:
		failures.append("测试关卡99 的显示名不正确：%s" % GameDesignConfig.expedition_level_display_name(LEVEL_ID))
	if GameDesignConfig.expedition_level_subtitle(LEVEL_ID).is_empty():
		failures.append("测试关卡99 缺少读取界面副标题")
	if GameDesignConfig.expedition_level_objective(LEVEL_ID).is_empty():
		failures.append("测试关卡99 缺少 HUD 行动目标文案")
	# 续局路由：存档只记 run_id，必须能凭它回到 99 的场景。
	if GameDesignConfig.expedition_scene_for_run_id(LEVEL_ID) != LEVEL_SCENE:
		failures.append("按运行时标识 %s 无法路由回测试关卡99" % LEVEL_ID)
	# 未登记的关卡 id 必须查不到 —— 这样才能解释成「拒绝登记」而不是「静默改道」。
	# 刻意**不**调用 select_expedition_level()：那条路会 push_error，而本套件靠
	# 「日志里没有 ERROR」判绿，故意制造的引擎错误会污染判据。
	if not GameDesignConfig.expedition_level("__not_a_level__").is_empty():
		failures.append("未登记的关卡 id 竟然能查到登记项")
	if not GameDesignConfig.expedition_scene_for_run_id("__not_a_level__").is_empty():
		failures.append("未登记的运行时标识竟然能路由到场景")
	# 默认终点不得被新增关卡挤掉：远征关卡01 仍是清单首条。
	if GameDesignConfig.default_expedition_level_id() == LEVEL_ID:
		failures.append("测试关卡99 不该成为默认终点")


# —— 2) 设计源与数据驱动开关 ——

func _verify_design_source(failures: Array[String]) -> void:
	if not LevelPlanLoader.has_level_plan(LEVEL_ID):
		failures.append("测试关卡99 的设计源加载失败（L1 缺失或 schema 不符）")
		return
	# 开关是**逐关卡**的：99 打开，远征关卡01 不打开（后者仍走内置房表以保住既有存档口径）。
	if not FloorPlanGenerator.data_driven_enabled(LEVEL_ID):
		failures.append("测试关卡99 未打开数据驱动（design_source.generation_policy.runtime_enabled）")
	if FloorPlanGenerator.data_driven_enabled("expedition_01"):
		failures.append("远征关卡01 的数据驱动开关被误开，既有存档口径会被改变")
	if FloorPlanGenerator.data_driven_enabled("battle_level01"):
		failures.append("battle_level01 的数据驱动开关被误开")

	var plan := FloorPlanGenerator.generate_from_level_plan(LEVEL_ID, 0, GENERATOR_SEED)
	if plan.is_empty():
		failures.append("测试关卡99 的生成器产出为空计划")
		return
	if not bool(plan.get("valid", false)):
		failures.append("测试关卡99 的生成器自校验未通过：%s" % str(plan.get("validation_errors", [])))
	# trigger 是「真的走了哪条路」的唯一凭据：内置房表给的是 expedition_bootstrap。
	if str(plan.get("trigger", "")) != "level_plan_data":
		failures.append("测试关卡99 没有走数据驱动路径：trigger=%s" % str(plan.get("trigger", "")))
	if str(plan.get("mode", "")) != "authored":
		failures.append("测试关卡99 的生成模式不是 authored：%s" % str(plan.get("mode", "")))
	if str(plan.get("terminal_mode", "")) != "extraction_room":
		failures.append("测试关卡99 的终局模式不是撤离房：%s" % str(plan.get("terminal_mode", "")))
	var ids: Array[String] = []
	var types_by_id := {}
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		var room_id := str(spec.get("id", ""))
		ids.append(room_id)
		types_by_id[room_id] = str(spec.get("type", ""))
	if ids != EXPECTED_ROOM_IDS:
		failures.append("测试关卡99 的运行时房间编号没对齐运行时契约：%s（期望 %s）" % [ids, EXPECTED_ROOM_IDS])
	for room_id_value in EXPECTED_ROOM_IDS:
		var room_id := str(room_id_value)
		if not types_by_id.has(room_id):
			continue
		var expected := str(EXPECTED_ROOM_TYPES[room_id])
		if str(types_by_id[room_id]) != expected:
			failures.append("%s 的运行时类型应为 %s，实为 %s" % [room_id, expected, str(types_by_id[room_id])])
	if int(plan.get("content_room_count", -1)) != EXPECTED_MAIN_KEYS.size():
		failures.append("测试关卡99 的内容房计数不正确：%s（期望 %d）" % [
			str(plan.get("content_room_count", -1)), EXPECTED_MAIN_KEYS.size(),
		])
	# 内置房表会给出 5 间内容房。产出仍是 5 间即说明真的回退了内置表而无人察觉。
	if ids.size() == BUILTIN_EXPEDITION_CONTENT_ROOMS + 2:
		failures.append("测试关卡99 的房间数等于内置远征房表（7 房），疑似回退到了内置房表")
	var main_keys: Array = plan.get("main_path_keys", []) as Array
	if main_keys != EXPECTED_MAIN_KEYS.duplicate():
		failures.append("测试关卡99 的主通道不是 01—02 号房：%s" % [main_keys])
	# 设计源把两间内容房钉死成 COMBAT，运行时不得被洗成别的类型。
	_verify_level_plan_rooms(failures)


func _verify_level_plan_rooms(failures: Array[String]) -> void:
	var normalized := LevelPlanLoader.normalize_floor(LEVEL_ID, 0)
	if normalized.is_empty():
		failures.append("测试关卡99 的 L2 规范化失败")
		return
	if str(normalized.get("mode", "")) != "authored":
		failures.append("测试关卡99 的 L2 模式不是 authored：%s" % str(normalized.get("mode", "")))
	var by_key := {}
	for value in normalized.get("rooms", []):
		var room := value as Dictionary
		by_key[str(room.get("key", ""))] = room
	if not by_key.has("entry"):
		failures.append("测试关卡99 的 L2 缺少入口房 key=entry（运行时按该 key 找入口）")
	if not by_key.has("extraction"):
		failures.append("测试关卡99 的 L2 缺少撤离房 key=extraction（运行时按该 key 挂撤离信标）")
	var main_path: Array = normalized.get("main_path", []) as Array
	if main_path != EXPECTED_MAIN_KEYS.duplicate():
		failures.append("测试关卡99 的 L2 主路不是 01—02：%s" % [main_path])
	# 入口房的门槽必须指向 01 号房，否则开局动线断在安全屋里。
	var entry_ports: Array = (by_key.get("entry", {}) as Dictionary).get("ports", []) as Array
	if entry_ports.size() != 1:
		failures.append("测试关卡99 的入口房应只有 1 个门槽：%d" % entry_ports.size())
	else:
		if str((entry_ports[0] as Dictionary).get("target", "")) != "room_01":
			failures.append("测试关卡99 的入口门槽目标不是 room_01：%s" % str(
				(entry_ports[0] as Dictionary).get("target", "")
			))


# —— 3) 99F 远征情报室入口按钮 ——

func _verify_menu_entry(failures: Array[String]) -> void:
	var menu_scene := load(MENU_SCENE) as PackedScene
	if menu_scene == null:
		failures.append("RogueMapSelectMenu.tscn 加载失败")
		return
	var menu := menu_scene.instantiate() as CanvasLayer
	if menu == null:
		failures.append("RogueMapSelectMenu 实例化失败")
		return
	add_child(menu)
	await get_tree().process_frame

	# 默认关卡那一段必须原样保留（本次改动只允许「追加」，不允许「替换」）。
	var map_view := menu.find_child("MapView", true, false) as VBoxContainer
	if map_view == null or map_view.get_child_count() != 5:
		failures.append("远征情报室的默认版图行数被改动：%d" % (
			map_view.get_child_count() if map_view != null else -1
		))
	var teleport := menu.find_child("TeleportButton", true, false) as Button
	if teleport == null or not teleport.text.contains("远征"):
		failures.append("默认传送按钮被改动：%s" % (teleport.text if teleport != null else "<缺失>"))
	elif teleport.text.contains(LEVEL_DISPLAY_NAME):
		failures.append("默认传送按钮被改成了测试关卡99 的入口：%s" % teleport.text)

	# 本关卡的入口按钮：节点名按关卡 id 生成，验收才能稳定命中。
	var enter := menu.find_child("EnterLevelButton_%s" % LEVEL_ID, true, false) as Button
	if enter == null:
		failures.append("远征情报室缺少「进入%s」按钮" % LEVEL_DISPLAY_NAME)
	else:
		if not enter.text.contains(LEVEL_DISPLAY_NAME):
			failures.append("关卡99 入口按钮文案不正确：%s" % enter.text)
		if enter.pressed.get_connections().size() <= 0:
			failures.append("关卡99 入口按钮没有接任何处理函数")
	# 说明行必须来自关卡清单，而不是菜单里再抄一份关卡名。
	var heading := menu.find_child("AlternateLevelHeading_%s" % LEVEL_ID, true, false) as Label
	if heading == null or heading.text != LEVEL_DISPLAY_NAME:
		failures.append("关卡99 入口说明标题不正确：%s" % (heading.text if heading != null else "<缺失>"))

	# 待进入态契约：菜单登记 → 读取界面取值。这里只验机制，不真的点按钮
	# （点了会 change_scene_to_file，把本验收场景整个换掉）。
	# 「清空」只能查静态量本身：peek()/consume() 都刻意做了「空则回退默认关卡」，
	# 所以它们永远不会返回空串，拿返回值判清空会永远失败。
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		failures.append("登记待进入关卡 %s 被拒绝" % LEVEL_ID)
	elif GameDesignConfig.peek_pending_expedition_level_id() != LEVEL_ID:
		failures.append("待进入关卡登记后读回不一致：%s" % GameDesignConfig.peek_pending_expedition_level_id())
	elif GameDesignConfig.consume_pending_expedition_level_id() != LEVEL_ID:
		failures.append("待进入关卡取值（消费）结果不一致")
	elif not GameDesignConfig.pending_expedition_level_id.is_empty():
		failures.append("待进入关卡消费后没有清空，会泄漏到下一次传送")
	# 清空后再登记另一个关卡，必须覆盖而不是叠加（读回是新的那个）。
	elif not GameDesignConfig.select_expedition_level(GameDesignConfig.default_expedition_level_id()):
		failures.append("清空后无法登记默认关卡")
	elif GameDesignConfig.peek_pending_expedition_level_id() != GameDesignConfig.default_expedition_level_id():
		failures.append("待进入关卡登记没有覆盖旧值：%s" % GameDesignConfig.peek_pending_expedition_level_id())
	GameDesignConfig.pending_expedition_level_id = ""

	if is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame


# —— 4) 读取界面按待进入态决定终点 ——

func _verify_loading_destination(failures: Array[String]) -> void:
	if not ResourceLoader.exists(LOADING_SCENE, "PackedScene"):
		failures.append("读取界面场景不存在：%s" % LOADING_SCENE)
		return
	var packed := load(LOADING_SCENE) as PackedScene

	# 4a) 指定了关卡 99：标题/面包屑/终点都必须是 99。
	# 刻意不入树（入树后 _ready 在 headless 会立即切场景），所以直接喂私有字段 ——
	# _ready 里做的就是「取待进入态写进 _level_id」，此处等价地注入同一结果。
	var screen := packed.instantiate() as CanvasLayer
	if screen == null:
		failures.append("ExpeditionLoadingScreen 实例化失败")
		return
	screen.set("_level_id", LEVEL_ID)
	screen.call("_build_ui")
	var title := screen.get_node_or_null("Root/Center/Title") as Label
	if title == null or title.text != LEVEL_DISPLAY_NAME:
		failures.append("读取界面标题没有跟随待进入关卡：%s" % (title.text if title != null else "<缺失>"))
	var breadcrumb := screen.get_node_or_null("Root/Center/Breadcrumb") as Label
	if breadcrumb == null or not breadcrumb.text.contains(LEVEL_DISPLAY_NAME):
		failures.append("读取界面面包屑没有跟随待进入关卡：%s" % (
			breadcrumb.text if breadcrumb != null else "<缺失>"
		))
	if str(screen.call("_destination_scene")) != LEVEL_SCENE:
		failures.append("读取界面终点不是测试关卡99 的场景：%s" % str(screen.call("_destination_scene")))
	screen.free()

	# 4b) 没指定关卡：行为必须与引入关卡清单之前一字不变（回退远征关卡01）。
	var fallback := packed.instantiate() as CanvasLayer
	fallback.call("_build_ui")
	var fallback_title := fallback.get_node_or_null("Root/Center/Title") as Label
	if fallback_title == null or fallback_title.text != DEFAULT_DISPLAY_NAME:
		failures.append("未指定关卡时读取界面标题被改变：%s" % (
			fallback_title.text if fallback_title != null else "<缺失>"
		))
	if str(fallback.call("_destination_scene")) != DEFAULT_SCENE:
		failures.append("未指定关卡时读取界面终点被改变：%s" % str(fallback.call("_destination_scene")))
	fallback.free()


# —— 5) 关卡本体：单层、独立场景、四间房、入口门免费、撤离信标可用 ——

func _verify_level_scene(failures: Array[String]) -> void:
	var scene := load(LEVEL_SCENE) as PackedScene
	if scene == null:
		failures.append("测试关卡99 的场景加载失败：%s" % LEVEL_SCENE)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		failures.append("测试关卡99 的场景实例化失败")
		return
	tower.test_mode = true
	tower.run_seed_override = 77199999
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	if not tower.is_expedition():
		failures.append("测试关卡99 的场景未开启 expedition_mode")
	if tower.get_expedition_run_id() != LEVEL_ID:
		failures.append("测试关卡99 的运行时标识不正确：%s" % tower.get_expedition_run_id())
	if str(tower.get_runtime_map_id()) != LEVEL_ID:
		failures.append("测试关卡99 的存档隔离标识不正确：%s" % str(tower.get_runtime_map_id()))
	# 远征关卡（含本测试关）的退出/结算落点 = 玩家出发点 = 塔楼 99F 基地主场景。
	# 用 BaseWorld3D 会把玩家退回旧的「兼容基地」，见 2026-09-19 构建记录 §10。
	if tower.return_scene_path != GameDesignConfig.MAIN_SCENE:
		failures.append("测试关卡99 的结算返回场景不是塔楼 99F 基地：%s" % tower.return_scene_path)
	if tower.get_expedition_display_name() != LEVEL_DISPLAY_NAME:
		failures.append("测试关卡99 的 HUD 显示名不正确：%s" % tower.get_expedition_display_name())
	# HUD 文案不得顶着塔楼语义（顶栏房间标签 / 小地图上方区域标签是运行时拼字符串，
	# 几何/区块/包络校验全看不见 —— 见 2026-09-19 构建记录 §10.1）。
	var area_text := str(tower.call("_hud_floor_label_text"))
	if area_text.contains("高塔外层") or area_text.contains("100F"):
		failures.append("测试关卡99 地图区域标签残留塔楼语义：%s" % area_text)
	elif not area_text.contains(LEVEL_DISPLAY_NAME):
		failures.append("测试关卡99 地图区域标签未标明关卡名：%s" % area_text)
	var hud_start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if hud_start_room != null:
		tower.call("_on_room_entered", hud_start_room)
		var hud_room_text := str(tower.room_label.text)
		if hud_room_text.contains("100F") or hud_room_text.contains("99F"):
			failures.append("测试关卡99 房间标签残留塔楼楼层语义：%s" % hud_room_text)
		elif not hud_room_text.contains(LEVEL_DISPLAY_NAME):
			failures.append("测试关卡99 房间标签未标明关卡名：%s" % hud_room_text)

	# 单层：只有 floor_index 0。
	var planned_layers := tower.get_expedition_planned_floor_numbers()
	if planned_layers != [0]:
		failures.append("测试关卡99 不是单层：规划层索引=%s" % [planned_layers])
	for forbidden_layer in [1, 2, 3, 4, 5, 6]:
		if tower._floor_plan_snapshots.has(forbidden_layer):
			failures.append("测试关卡99 不应规划层索引 %d" % forbidden_layer)
	if tower._room_by_id.has("facility"):
		failures.append("测试关卡99 不应存在 99F 基地房 facility")
	if not (tower._elevator_facilities_by_floor as Dictionary).is_empty():
		failures.append("测试关卡99 不应生成楼层电梯")

	_verify_plan_snapshot(tower, failures)
	_verify_scene_structure(tower, failures)
	_verify_content_bounds(tower, failures)
	_verify_rooms(tower, failures)
	_verify_entry_gate(tower, failures)
	_verify_extraction(tower, failures)
	_verify_enemy_spawn_plan(tower, failures)

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## 规划快照必须来自数据驱动，且**内容房只有 2 间** —— 这是「没有静默回退内置房表」的运行时证据。
func _verify_plan_snapshot(tower: TowerDescent3D, failures: Array[String]) -> void:
	var plan := tower._floor_plan_snapshots.get(0, {}) as Dictionary
	if plan.is_empty():
		failures.append("测试关卡99 缺少单层规划快照")
		return
	if str(plan.get("trigger", "")) != "level_plan_data":
		failures.append(
			"测试关卡99 运行时没有走数据驱动（trigger=%s），很可能静默回退到了内置房表"
			% str(plan.get("trigger", ""))
		)
	if int(plan.get("content_room_count", -1)) != EXPECTED_MAIN_KEYS.size():
		failures.append("测试关卡99 运行时内容房计数不是 2：%s" % str(plan.get("content_room_count", -1)))
	if not bool(plan.get("valid", false)):
		failures.append("测试关卡99 的规划校验未通过：%s" % str(plan.get("validation_errors", [])))
	if str(plan.get("terminal_mode", "")) != "extraction_room":
		failures.append("测试关卡99 的终局模式不是撤离房：%s" % str(plan.get("terminal_mode", "")))


## 结构独立：场景只搭公共关卡基座，不继承塔楼场景；Blocks 下只有 Expedition。
## ⚠️ 判据必须是「把塔楼场景**作为 ext_resource 引入**」（= 继承/子实例化）。
##      绝不能退化成「源文里出现塔楼路径字符串」：本关的 `return_scene_path`
##      合法地指向塔楼主场景（那是玩家出发点），它只是普通字符串属性，
##      不含任何继承语义（2026-09-19 踩过这个误判）。
func _verify_scene_structure(tower: TowerDescent3D, failures: Array[String]) -> void:
	var scene_text := _read_text(LEVEL_SCENE)
	if scene_text.is_empty():
		failures.append("测试关卡99 的场景文件不可读：%s" % LEVEL_SCENE)
	else:
		var tower_ref := 'path="%s"' % TOWER_SCENE
		for line in scene_text.split("\n"):
			var trimmed := line.strip_edges()
			if not trimmed.begins_with("[ext_resource"):
				continue
			if trimmed.contains(tower_ref):
				failures.append(
					"测试关卡99 仍把塔楼场景 %s 作为 ext_resource 引入（继承/子实例化会让塔楼内容整棵随加载）" % TOWER_SCENE
				)
				break
	if tower.get_node_or_null("Blocks/Base/Art") != null:
		failures.append("测试关卡99 残留 99F 基地美术 Blocks/Base/Art（会留下隐形碰撞）")
	var blocks := tower.get_node_or_null("Blocks") as Node3D
	if blocks == null:
		failures.append("测试关卡99 缺少 Blocks 根节点")
	else:
		var names: Array[String] = []
		for child in blocks.get_children():
			names.append(str(child.name))
		if names != ["Expedition"]:
			failures.append("测试关卡99 的 Blocks 子节点不是唯一的 Expedition：%s" % [names])
		for block_name in ["Rooftop", "Base", "Battle", "Stairs"]:
			if blocks.get_node_or_null(block_name) != null:
				failures.append("测试关卡99 出现塔楼区块 Blocks/%s" % block_name)
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		failures.append("测试关卡99 缺少 Blocks/Expedition 区块")
		return
	if str(block.get_meta("block_id", "")) != "expedition":
		failures.append("Expedition 区块 block_id 不正确：%s" % str(block.get_meta("block_id", "")))
	# 场景自带的显示名必须就是本关卡的，而不是从塔楼或 01 号关卡抄来的。
	if str(block.get_meta("display_name", "")) != LEVEL_DISPLAY_NAME:
		failures.append("Expedition 区块 display_name 不是测试关卡99：%s" % str(
			block.get_meta("display_name", "")
		))
	if (tower._corridor_by_edge as Dictionary).is_empty():
		failures.append("测试关卡99 没有任何走廊连接")
	for edge_value in tower._corridor_by_edge.keys():
		var corridor := tower._corridor_by_edge.get(edge_value) as Node3D
		if corridor != null and corridor.get_parent() != block:
			failures.append("走廊 %s 不在 Blocks/Expedition 下（父节点：%s）" % [
				corridor.name, str(corridor.get_parent()),
			])


## 楼面/外墙包络必须按**本关卡的 4 间房**收缩，而不是套用远征关卡01 的 7 房外框。
## 用错外框时的表现是「远处立着一圈没有内容的墙」或「房间落在楼面之外」，都不会报错。
func _verify_content_bounds(tower: TowerDescent3D, failures: Array[String]) -> void:
	var stage := tower._floor_stages.get(0) as Node3D
	if stage == null:
		failures.append("测试关卡99 缺少 0 层楼面舞台")
		return
	var snapshot: Dictionary = stage.get_snapshot()
	if not bool(snapshot.get("force_standard_map", false)):
		failures.append("测试关卡99 的楼面舞台未显式启用标准网格：%s" % snapshot)
		return
	if not bool(snapshot.get("has_content_bounds", false)):
		failures.append("测试关卡99 的楼面舞台没有按内容外框生成：%s" % snapshot)
		return
	var content_rect := snapshot.get("content_world_rect", Rect2()) as Rect2
	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		failures.append("测试关卡99 的内容外框退化为空：%s" % str(content_rect))
		return
	var grid_unit: float = TowerFloorStage3D.GRID_UNIT
	if not is_equal_approx(fmod(content_rect.size.x, grid_unit), 0.0) \
			or not is_equal_approx(fmod(content_rect.size.y, grid_unit), 0.0):
		failures.append("测试关卡99 的内容外框未对齐 %sm 网格：%s" % [str(grid_unit), str(content_rect)])
	if (snapshot.get("floor_world_rect", Rect2()) as Rect2) != content_rect:
		failures.append("测试关卡99 的楼面世界矩形与内容外框不一致：%s vs %s" % [
			str(snapshot.get("floor_world_rect")), str(content_rect),
		])
	# 一定是「按内容收缩」的结果，不是 250×250 整块场地。
	if content_rect.size.x >= 250.0 or content_rect.size.y >= 250.0:
		failures.append("测试关卡99 的楼面没有按内容收缩：%s" % str(content_rect))
	for room_id_value in EXPECTED_ROOM_IDS:
		var room_id := str(room_id_value)
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var dimensions := room.get_dimensions()
		var room_rect := Rect2(
			Vector2(room.position.x - dimensions.x * 0.5, room.position.z - dimensions.y * 0.5),
			dimensions
		)
		if not content_rect.encloses(room_rect):
			failures.append("房间 %s 不在内容外框内：%s ⊄ %s" % [room_id, str(room_rect), str(content_rect)])
	if int(snapshot.get("support_rect_count", 0)) < 1:
		failures.append("测试关卡99 的楼面没有任何承重碰撞：%s" % snapshot)
	if bool(snapshot.get("base_99_100_atrium_enabled", true)):
		failures.append("测试关卡99 不应挖 99F 中庭洞，否则入口安全房会悬空")
	if not is_equal_approx(
		float(snapshot.get("outer_wall_height", 0.0)), TowerGeometry3D.WALL_LOGICAL_HEIGHT_M
	):
		failures.append("测试关卡99 的外圈墙不是整墙高度：%s" % str(snapshot.get("outer_wall_height")))

	# 真实物理射线：脚下有楼面、四向有墙。
	var space := tower.get_viewport().world_3d.direct_space_state
	var side_directions := {
		"north": Vector3(0.0, 0.0, -1.0),
		"south": Vector3(0.0, 0.0, 1.0),
		"west": Vector3(-1.0, 0.0, 0.0),
		"east": Vector3(1.0, 0.0, 0.0),
	}
	for room_id_value in EXPECTED_ROOM_IDS:
		var room_id := str(room_id_value)
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var center := room.global_position
		if _ray(space, center + Vector3(0, 3.0, 0), center + Vector3(0, -3.0, 0)).is_empty():
			failures.append("%s 脚下没有承重楼面，玩家会掉出关卡" % room_id)
		var reach := room.get_dimensions().x * 0.5 + 3.0
		for side_value in side_directions.keys():
			var side := str(side_value)
			var from := center + Vector3(0, 1.5, 0)
			if _ray(space, from, from + (side_directions[side] as Vector3) * reach).is_empty():
				failures.append("%s 的 %s 侧没有墙体阻挡" % [room_id, side])


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)


func _verify_rooms(tower: TowerDescent3D, failures: Array[String]) -> void:
	var ids := tower.get_expedition_room_ids()
	if ids != EXPECTED_ROOM_IDS:
		failures.append("测试关卡99 的房间清单不正确：%s（期望 %s）" % [ids, EXPECTED_ROOM_IDS])
	for room_id_value in EXPECTED_ROOM_IDS:
		var room_id := str(room_id_value)
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			failures.append("测试关卡99 缺少房间 %s —— 运行时按字面量认房，缺一个就断一条玩法" % room_id)
			continue
		if room.name != room_id:
			failures.append("%s 节点名被改写为 %s" % [room_id, room.name])
		if str(room.room_type) != str(EXPECTED_ROOM_TYPES[room_id]):
			failures.append("%s 的房间类型应为 %s，实为 %s" % [
				room_id, str(EXPECTED_ROOM_TYPES[room_id]), str(room.room_type),
			])
		var parent := room.get_parent()
		if parent == null or str(parent.name) != "Expedition":
			failures.append("%s 不在 Blocks/Expedition 内：%s" % [room_id, str(room.get_path())])
		if str(room.get_meta("block_id", "")) != "expedition":
			failures.append("%s 的 block_id 元数据不是 expedition" % room_id)
		var expected_size := SAFE_ROOM_SIZE if room_id == "start" else CONTENT_ROOM_SIZE
		if not room.get_dimensions().is_equal_approx(expected_size):
			failures.append("%s 尺寸不是 %s：%s" % [room_id, expected_size, room.get_dimensions()])
	if not tower.get_first_safe_room_dimensions().is_equal_approx(SAFE_ROOM_SIZE):
		failures.append("测试关卡99 的入口安全房尺寸不是 15×15：%s" % tower.get_first_safe_room_dimensions())
	# 入口安全屋必须是双门、且前门指向 01 号房、另有一扇退出战局门。
	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		return
	if start_room.doors.size() != 2:
		failures.append("测试关卡99 的入口安全房不是双门结构：%s" % [start_room.doors])
	var front_targets: Array[String] = []
	for target_value in start_room.door_targets.values():
		if not str(target_value).is_empty():
			front_targets.append(str(target_value))
	if front_targets != ["room_01"]:
		failures.append("测试关卡99 的入口前门目标不是 room_01：%s" % [front_targets])


## 入口门是固定交通接口：免费通行（不清房、不耗钥匙、不弹命运卡）。
## 这条在一次只有 2 间内容房的关卡里更重要 —— 少了内容房分摊，命运卡一旦卡在入口
## 就会让整局只剩一间房可打。
func _verify_entry_gate(tower: TowerDescent3D, failures: Array[String]) -> void:
	var policy := tower._door_policy_for_edge("start", "room_01")
	for key in ["requires_clear", "requires_key", "triggers_fate"]:
		if bool(policy.get(key, true)):
			failures.append("测试关卡99 的入口门应为免费通行：%s" % policy)
	# 01 → 02 是唯一一间内容房之间的门，必须保留默认门策略（清房/钥匙/命运卡）。
	var inner := tower._door_policy_for_edge("room_01", "room_02")
	for key in ["requires_clear", "requires_key", "triggers_fate"]:
		if not bool(inner.get(key, false)):
			failures.append("测试关卡99 的 01→02 门策略应保留默认：%s" % inner)


func _verify_extraction(tower: TowerDescent3D, failures: Array[String]) -> void:
	if not tower.has_expedition_extraction():
		failures.append("测试关卡99 没有装配可用的撤离信标")
		return
	var extraction_room := tower._room_by_id.get("extraction") as DungeonRoom3D
	if extraction_room == null:
		failures.append("测试关卡99 缺少终点撤离房 extraction")
		return
	var beacon := tower._extraction as ExtractionBeacon3D
	if beacon == null:
		failures.append("测试关卡99 的撤离信标为空")
		return
	if beacon.beacon_type != "STANDARD":
		failures.append("测试关卡99 的撤离信标不是常驻可用的 STANDARD：%s" % beacon.beacon_type)
	if beacon.locked:
		failures.append("测试关卡99 的撤离信标不应上锁")
	if beacon.get_parent() != extraction_room:
		failures.append("撤离信标不在终点撤离房内：%s" % str(beacon.get_path()))


## 房间级刷怪计划（enemy_spawn_plan）的运行时落地断言。
##
## 只验「设计源透传到 plan」是不够的：plan 里的字段要真的驱动刷怪才有意义。
## 这里真装配 99、真调唯一刷怪入口 `_spawn_room_enemies`，逐值读产出：
##   * room_02 填了计划 → 波次数 / 每波数量 / 组成必须与设计源逐值一致（2 波 × 3 只）；
##   * room_01 没填     → 必须仍走全局公式（覆盖是「按房间可选」，不是「一填全改」）。
## 另钉一条状态不泄漏：命运卡注入的「下一间房」倍率与补兵计数，在被设计源接管的
## 房里也必须落账并清零 —— 漏清零会安静地污染后面几间房，没有任何几何/静态校验看得见。
func _verify_enemy_spawn_plan(tower: TowerDescent3D, failures: Array[String]) -> void:
	var room_01 := tower._room_by_id.get("room_01") as DungeonRoom3D
	var room_02 := tower._room_by_id.get("room_02") as DungeonRoom3D
	if room_01 == null or room_02 == null:
		failures.append("刷怪计划断言取不到 room_01 / room_02")
		return
	# A/B 前提：同一张关卡、同一种房型（都是 COMBAT），只有 room_02 填了计划。
	if not room_01.enemy_spawn_plan.is_empty():
		failures.append(
			"room_01 本应保持全局公式（未填 enemy_spawn_plan），实为 %s" % [room_01.enemy_spawn_plan]
		)
	if room_02.enemy_spawn_plan.is_empty():
		failures.append("room_02 的 enemy_spawn_plan 没有落到房间实例上（设计源字段被吞了）")
		return
	var authored_waves: Array = room_02.enemy_spawn_plan.get("waves", []) as Array
	if authored_waves.size() != 2:
		failures.append("room_02 设计源应为 2 波，实为 %d" % authored_waves.size())

	# 命运卡注入：临时设「下一间房」倍率 + 补兵计数，验证被接管的房照常落账/清零。
	tower._next_room_enemy_hp_multiplier = 2.5
	tower._next_room_enemy_count = 4
	if not bool(tower.call("_spawn_room_enemies", room_02)):
		failures.append("room_02 刷怪失败（入口会解锁房间防软锁）")
		return
	var live := tower._enemy_nodes_by_room.get("room_02", []) as Array
	var queue := tower._room_wave_queues.get("room_02", []) as Array
	var queued := int((queue[0] as Array).size()) if queue.size() == 1 else -1
	if live.size() != 3:
		failures.append("room_02 第一波应为 3 只（2 近战 + 1 远程），实为 %d" % live.size())
	if queue.size() != 1:
		failures.append("room_02 剩余波数应为 1，实为 %d" % queue.size())
	elif queued != 3:
		failures.append("room_02 第二波应为 3 只（1 护盾 + 2 自爆），实为 %d" % queued)
	if int(tower._room_wave_totals.get("room_02", 0)) != 2:
		failures.append(
			"room_02 波次总数应为 2，实为 %s" % str(tower._room_wave_totals.get("room_02", 0))
		)
	if live.size() + maxi(queued, 0) != 6:
		failures.append(
			"room_02 总敌数应为 6（数量以设计源为准，补兵计数不得追加到本房），实为 %d"
			% [live.size() + maxi(queued, 0)]
		)
	if not is_equal_approx(float(tower._room_enemy_hp_multipliers.get("room_02", 1.0)), 2.5):
		failures.append(
			"room_02 未落账命运卡倍率：%s" % str(tower._room_enemy_hp_multipliers.get("room_02", 1.0))
		)
	if not is_equal_approx(float(tower._next_room_enemy_hp_multiplier), 1.0):
		failures.append(
			"被设计源接管的房没有清零「下一间房」倍率，会泄漏给后面的房间：%s"
			% str(tower._next_room_enemy_hp_multiplier)
		)
	if int(tower._next_room_enemy_count) != 0:
		failures.append(
			"被设计源接管的房没有清零补兵计数：%d" % int(tower._next_room_enemy_count)
		)

	# room_01 未填计划 → 必须仍走全局公式（证明覆盖是按房间可选的）。
	if not bool(tower.call("_spawn_room_enemies", room_01)):
		failures.append("room_01 走全局公式时刷怪失败")
		return
	var formula_live := tower._enemy_nodes_by_room.get("room_01", []) as Array
	if formula_live.is_empty():
		failures.append("room_01 未按全局公式刷出任何敌人")


# —— 工具 ——

## 读 res:// 文本资源：场景的「不继承塔楼」是文件级契约，只有读原文才能断言。
func _read_text(res_path: String) -> String:
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"TEST_LEVEL_99_FLOW_OK: "
			+ "registry(99 -> ExpeditionLevel99_3D, run_id 99, resume route), "
			+ "design source loaded with runtime_enabled per-level (expedition_01/battle_level01 still off), "
			+ "generator trigger=level_plan_data with 4 rooms start/room_01/room_02/extraction "
			+ "(no fallback to the 5-content-room builtin table), "
			+ "standalone single-layer scene on Dungeon3D base with Blocks/Expedition only, "
			+ "content bounds shrunk to the 4-room footprint with real raycast floor/walls, "
			+ "free entry gate, STANDARD extraction beacon in the extraction room, "
			+ "99F mission-operations menu exposes the test-level-99 entry button, "
			+ "per-room enemy_spawn_plan drives room_02 (2 waves x 3) while room_01 stays "
			+ "on the global formula, fate-card next-room multipliers recorded then reset, "
			+ "loading screen follows the pending level and falls back to expedition_01 unchanged"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
