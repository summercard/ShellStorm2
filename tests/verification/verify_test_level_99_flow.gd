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
##   * 内置远征房表硬编码 5 间内容房，1 间内容房的关卡一旦回退到它就会**多出 4 间房**，
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
## 内置房表里远征恒为 5 间内容房。99 只有 1 间内容房 + 1 间 Boss 房，因此
## 「没有回退到内置房表」本身就是一个可断言的事实 —— 见 _verify_design_source。
const BUILTIN_EXPEDITION_CONTENT_ROOMS := 5

const SAFE_ROOM_SIZE := Vector2(15.0, 15.0)
const CONTENT_ROOM_SIZE := Vector2(25.0, 25.0)
const BOSS_ROOM_SIZE := Vector2(45.0, 45.0)
const EXPECTED_ROOM_IDS: Array[String] = ["start", "room_01", "boss", "extraction"]
const EXPECTED_MAIN_KEYS: Array[String] = ["room_01"]
## 设计源里按房间钉死的内容类型（不是随机洗牌的），运行时必须逐值复现。
const EXPECTED_ROOM_TYPES := {
	"start": "STAIR_LOBBY",
	"room_01": "COMBAT",
	"boss": "BOSS",
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
	# 开关是**逐关卡**的，两侧都要钉住 —— 只断言「99 开着」会漏掉开关被误关或误开。
	# 2026-09-20：远征关卡01 由主人决定打开（要砍掉「每局 0/90/180/270 旋转 + Z 镜像」的
	# 版图随机），故此处的远征断言改为**正向**。原反向断言的理由是「既有存档口径会被改变」，
	# 已实测澄清：唯一比对 layout_id 的恢复闸门
	# TowerDescent3D._restore_runtime_world_save_snapshot 只遍历 floor_index > 1 的已提交层，
	# 而远征是单层 floor_index 0，不进比对 ⇒ 不会整档恢复失败；真实代价是进行中的存档会
	# resume 到未旋转的固定版图（room_progress 按 room_id 走，进度不丢）。
	# 对方侧（远征关卡01 自己）的对应断言见 verify_expedition_level01_flow。
	if not FloorPlanGenerator.data_driven_enabled(LEVEL_ID):
		failures.append("测试关卡99 未打开数据驱动（design_source.generation_policy.runtime_enabled）")
	if not FloorPlanGenerator.data_driven_enabled("expedition_01"):
		failures.append("远征关卡01 的数据驱动开关被关闭，版图会退回每局旋转的随机口径")
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
		failures.append("测试关卡99 的主通道不是 01 号房：%s" % [main_keys])
	# 设计源把唯一一间内容房钉死成 COMBAT、Boss 房钉死成 BOSS，运行时不得被洗成别的类型。
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
	if not by_key.has("boss"):
		failures.append("测试关卡99 的 L2 缺少 Boss 房 key=boss（运行时按该 key 指派首领）")
	else:
		var boss_room := by_key.get("boss") as Dictionary
		if str(boss_room.get("room_type", "")) != "BOSS_ROOM":
			failures.append("测试关卡99 的 boss 房 room_type 不是 BOSS_ROOM：%s" % str(boss_room.get("room_type", "")))
		if str(boss_room.get("boss_content_id", "")) != "boss_monitor002":
			failures.append("测试关卡99 的 boss 房首领指派不是 boss_monitor002：%s" % str(boss_room.get("boss_content_id", "")))
	var main_path: Array = normalized.get("main_path", []) as Array
	if main_path != EXPECTED_MAIN_KEYS.duplicate():
		failures.append("测试关卡99 的 L2 主路不是 01 号房：%s" % [main_path])
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
	var fixture: Dictionary = preload("res://tests/verification/helpers/hologram_city_fixture.gd").create(self)
	var menu: RogueMapSelectMenu = fixture.menu
	await get_tree().process_frame
	if menu.LEVEL_IDS != ["expedition_01", "99"]:
		failures.append("两座楼的目的关卡ID映射错误")
	if menu._city == null or menu._city.labels.size() != 2:
		failures.append("城市缺少两座入口楼")
	elif menu._city.labels[1].text != LEVEL_DISPLAY_NAME:
		failures.append("99入口名称未读取关卡清单")
	if not menu.find_children("*", "Control", true, false).is_empty():
		failures.append("99入口仍使用平面按钮")

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
	fixture.host.queue_free()
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
	_verify_boss_identity(failures)
	await _verify_boss_reinforcements(tower, failures)
	_verify_reward_plan(failures)

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## 规划快照必须来自数据驱动，且**内容房只有 1 间（另加 Boss 房）** —— 这是「没有静默回退内置房表」的运行时证据。
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
		failures.append("测试关卡99 运行时内容房计数不是 1：%s" % str(plan.get("content_room_count", -1)))
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
		var expected_size := SAFE_ROOM_SIZE if room_id == "start" else BOSS_ROOM_SIZE if room_id == "boss" else CONTENT_ROOM_SIZE
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
## 这条在一次只有 1 间内容房的关卡里更重要 —— 少了内容房分摊，命运卡一旦卡在入口
## 就会让整局只剩 Boss 房可打。
func _verify_entry_gate(tower: TowerDescent3D, failures: Array[String]) -> void:
	var policy := tower._door_policy_for_edge("start", "room_01")
	for key in ["requires_clear", "requires_key", "triggers_fate"]:
		if bool(policy.get(key, true)):
			failures.append("测试关卡99 的入口门应为免费通行：%s" % policy)
	# 01 → Boss 是内容房到 Boss 房的门，必须保留默认门策略（清房/钥匙/命运卡）。
	var inner := tower._door_policy_for_edge("room_01", "boss")
	for key in ["requires_clear", "requires_key", "triggers_fate"]:
		if not bool(inner.get(key, false)):
			failures.append("测试关卡99 的 01→Boss 门策略应保留默认：%s" % inner)


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
## 本关只有一间内容房 room_01，且它**不填** enemy_spawn_plan（走全局公式）。
## 因此这里钉的是「没填计划 → 照常走全局公式」以及「BOSS 房不归设计源管」两条口径：
##   * room_01 没填     → 必须仍走全局公式刷出敌人（不填不等于不刷）；
##   * BOSS 房不写计划 → 静态校验与运行时兜底两道都要拦住（Boss 有独立出场逻辑）。
func _verify_enemy_spawn_plan(tower: TowerDescent3D, failures: Array[String]) -> void:
	var room_01 := tower._room_by_id.get("room_01") as DungeonRoom3D
	var boss := tower._room_by_id.get("boss") as DungeonRoom3D
	if room_01 == null:
		failures.append("刷怪计划断言取不到 room_01")
		return
	# room_01 是唯一内容房、未填计划 → 必须仍走全局公式（覆盖是「按房间可选」）。
	if not room_01.enemy_spawn_plan.is_empty():
		failures.append(
			"room_01 本应保持全局公式（未填 enemy_spawn_plan），实为 %s" % [room_01.enemy_spawn_plan]
		)
	if not bool(tower.call("_spawn_room_enemies", room_01)):
		failures.append("room_01 走全局公式时刷怪失败")
		return
	var formula_live := tower._enemy_nodes_by_room.get("room_01", []) as Array
	if formula_live.is_empty():
		failures.append("room_01 未按全局公式刷出任何敌人")

	# BOSS 房不归设计源管：Boss 的出场与结算由生成工具（BossContentCatalog）决定。
	# 在 BOSS 房写计划会让刷怪入口先于 match room.room_type 返回，boss + elite 整段被跳过。
	# 静态校验与运行时兜底两道都要在，这里逐条钉住。
	if GameDesignConfig.is_spawn_plan_authorable_room("BOSS"):
		failures.append("唯一口径 is_spawn_plan_authorable_room 把 BOSS 判成可写，口径反了")
	if boss == null:
		failures.append("刷怪计划断言取不到 boss 房")
	elif not boss.enemy_spawn_plan.is_empty():
		failures.append("boss 房不应带 enemy_spawn_plan（Boss 有独立出场逻辑）：%s" % [boss.enemy_spawn_plan])
	var boss_probe := LevelPlanValidator._validate_enemy_spawn_plan({
		"key": "boss_probe",
		"content_type": "BOSS",
		"enemy_spawn_plan": {
			"waves": [{"monsters": [{"type": "melee_chaser", "count": 1}]}],
		},
	})
	if not _has_error_prefix(boss_probe, "enemy_spawn_plan_on_boss_room"):
		failures.append("BOSS 房写 enemy_spawn_plan 未被静态校验拦住：%s" % [boss_probe])
	var combat_probe := LevelPlanValidator._validate_enemy_spawn_plan({
		"key": "combat_probe",
		"content_type": "COMBAT",
		"enemy_spawn_plan": {
			"waves": [{"monsters": [{"type": "melee_chaser", "count": 1}]}],
		},
	})
	if not combat_probe.is_empty():
		failures.append("合法的内容房计划竟被静态校验判错：%s" % [combat_probe])


## 首领指派（`boss_content_id`）：设计源可以指定本房出场的是名册里的哪一个首领。
##
## 三条口径必须钉死，否则失效方式全是静默的：
##   ① 未指定 + 本层没有按层指派的内容（单层关卡 floor_number=0）→ **不出 Boss**，
##      而不是退化成「通用外壳首领」；
##   ② 指定了名册里的一条 → 身份/正式模型/竞技场/阶段技能袋全部来自该条目（层号也取名册的）；
##   ③ 写了名册里没有的 ID → 解析为空且**绝不静默换成另一个首领**，静态校验另行拦住。
## 另加一条「白名单防漏登记」：LevelPlanLoader.normalize_floor 是重建式白名单，
## 漏登记房间级新字段会静默丢弃（不报错、不警告），只有断言 key 存在才能防住。
func _verify_boss_identity(failures: Array[String]) -> void:
	# —— ① 没写 boss = 不刷 boss ——
	var single_layer := BossContentCatalog.resolve_profile("", 0)
	if not single_layer.is_empty():
		failures.append(
			"单层关卡未指派首领时竟解析出了 Boss（口径应为不出 Boss）：%s" % str(single_layer)
		)
	# —— ② 按 ID 指派优先，且层号取名册条目的固有层号 ——
	var authored := BossContentCatalog.resolve_profile("boss_hollow_choir_85", 0)
	if str(authored.get("boss_content_id", "")) != "boss_hollow_choir_85":
		failures.append("设计源指派的首领身份没有被优先采纳：%s" % str(authored))
	if int(authored.get("floor_number", 0)) != 85:
		failures.append(
			"按 ID 指派时层号应取名册条目的固有层号(85)，实为 %d"
			% int(authored.get("floor_number", 0))
		)
	if str(authored.get("arena_asset_id", "")).is_empty():
		failures.append("按 ID 指派的首领没有带出竞技场资产")
	# 按层指派必须照旧工作：塔楼 95/90/85 不写 ID 也要能出场，否则塔楼整体失去 Boss。
	var by_floor := BossContentCatalog.resolve_profile("", 95)
	if str(by_floor.get("boss_content_id", "")) != "boss_abyss_archivist_95":
		failures.append("未指派时「按层号取名册条目」的回退被破坏：%s" % str(by_floor))
	# —— ③ 写错 ID 不得静默换人 ——
	var typo := BossContentCatalog.resolve_profile("boss_not_in_roster", 0)
	if not typo.is_empty():
		failures.append("写错的首领内容 ID 竟解析出别的内容（不得静默替换）：%s" % str(typo))

	# 运行时证据：拿不到名册条目就是**不刷 Boss**，而不是刷一个通用外壳。
	var injector := MonsterInjector.new()
	var none_spawned := injector.generate_enemies({
		"type": "boss", "floor": 1, "floor_level": RoomData.FloorLevel.SHALLOW,
		"floor_number": 0,
	})
	if not none_spawned.is_empty():
		failures.append(
			"单层未指派首领的 Boss 房仍刷出了 %d 只敌人（应为 0）" % none_spawned.size()
		)
	var one_spawned := injector.generate_enemies({
		"type": "boss", "floor": 1, "floor_level": RoomData.FloorLevel.SHALLOW,
		"floor_number": 0, "boss_content_id": "boss_hollow_choir_85",
	})
	if one_spawned.size() != 1:
		failures.append("按 ID 指派后应恰好刷出 1 只 Boss，实为 %d" % one_spawned.size())
	elif str(one_spawned[0].get("boss_content_id", "")) != "boss_hollow_choir_85":
		failures.append("刷出的 Boss 不是设计源指定的那一个：%s" % str(one_spawned[0]))
	var floor_spawned := injector.generate_enemies({
		"type": "boss", "floor": 1, "floor_level": RoomData.FloorLevel.SHALLOW,
		"floor_number": 95,
	})
	if (
		floor_spawned.size() != 1
		or str(floor_spawned[0].get("boss_content_id", "")) != "boss_abyss_archivist_95"
	):
		failures.append("未指派时按层号出场 Boss 的路径被破坏：%s" % str(floor_spawned))

	# —— 静态校验两条判据 ——
	var non_boss_probe := LevelPlanValidator._validate_boss_content_id({
		"key": "combat_probe", "role": "main", "content_type": "COMBAT",
		"boss_content_id": "boss_hollow_choir_85",
	})
	if not _has_error_prefix(non_boss_probe, "boss_content_id_on_non_boss_room"):
		failures.append("非 Boss 房写 boss_content_id 未被拦住：%s" % [non_boss_probe])
	var unknown_probe := LevelPlanValidator._validate_boss_content_id({
		"key": "boss_probe", "role": "boss", "content_type": "BOSS",
		"boss_content_id": "boss_not_in_roster",
	})
	if not _has_error_prefix(unknown_probe, "boss_content_id_unknown"):
		failures.append("Boss 房写了名册里不存在的 boss_content_id 未被拦住：%s" % [unknown_probe])
	var legal_probe := LevelPlanValidator._validate_boss_content_id({
		"key": "boss_probe", "role": "boss", "content_type": "BOSS",
		"boss_content_id": "boss_abyss_archivist_95",
	})
	if not legal_probe.is_empty():
		failures.append("合法的首领指派竟被静态校验判错：%s" % [legal_probe])
	# 只写 role=boss（没写 content_type）也是 Boss 房 —— 生成器会把这种房钉成 BOSS 型，
	# 只看 content_type 会让它绕过静态校验。
	var role_only_probe := LevelPlanValidator._validate_boss_content_id({
		"key": "boss_probe", "role": "boss", "content_type": "",
		"boss_content_id": "boss_abyss_archivist_95",
	})
	if not role_only_probe.is_empty():
		failures.append("只写 role=boss 的 Boss 房被误判成非 Boss 房：%s" % [role_only_probe])

	# —— 白名单防漏登记 ——
	var normalized := LevelPlanLoader.normalize_floor(LEVEL_ID, 0)
	for value in normalized.get("rooms", []):
		if not (value as Dictionary).has("boss_content_id"):
			failures.append(
				"LevelPlanLoader 白名单漏登记 boss_content_id，房间级该字段会被静默丢弃"
			)
			break

	# —— 透传防漏登记（出口侧）——
	# 上面那条只钉住「入口白名单」，本函数是「设计源 → 运行时计划」的出口登记点。
	# 为什么必须用手写 patch 而不是读现成关卡：**当前没有任何关卡在数据里写
	# boss_content_id**，端到端断言会退化成 0 样本空跑并静默通过。
	# 两侧只要漏一侧，字段就会静默消失，作者只会看到「我明明指定了却没出现」。
	var authored_boss_room := FloorPlanGenerator.room_from_source({
		"key": "boss_probe", "room_id": "boss_probe", "role": "boss",
		"content_type": "BOSS", "size": Vector2(25.0, 25.0),
		"boss_content_id": "boss_hollow_choir_85",
		"enemy_spawn_plan": {"waves": [{"monsters": [{"type": "melee_chaser", "count": 2}]}]},
	})
	if str(authored_boss_room.get("boss_content_id", "")) != "boss_hollow_choir_85":
		failures.append(
			"FloorPlanGenerator 未把 boss_content_id 透传进运行时房间：%s"
			% str(authored_boss_room.get("boss_content_id", "<缺失>"))
		)
	if str(authored_boss_room.get("type", "")) != "BOSS":
		failures.append("手写 Boss 房的 content_type 未按设计源钉死：%s" % str(authored_boss_room))
	# 没写就不许凭空长出来 —— 否则「没写 boss」会被上游残留值污染成「有 boss」。
	var plain_room := FloorPlanGenerator.room_from_source({
		"key": "room_probe", "room_id": "room_probe", "role": "main",
		"content_type": "COMBAT", "size": Vector2(25.0, 25.0),
	})
	if not str(plain_room.get("boss_content_id", "")).is_empty():
		failures.append(
			"没写 boss_content_id 的普通房竟被赋了值：%s"
			% str(plain_room.get("boss_content_id", ""))
		)


## 测试关卡99 Boss 双排持续增援的端到端验收。
## 覆盖设计源四段透传、运行时挂点、激活后10秒边界、3→4递增、朝中心抛射、18只上限、
## 离房暂停、快照恢复、Boss死亡停止，以及“Boss死后仍须清完剩余增援才清房”。
func _verify_boss_reinforcements(
	tower: TowerDescent3D, failures: Array[String]
) -> void:
	var failures_before := failures.size()
	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	if room == null:
		failures.append("Boss增援验收取不到 boss 房")
		return
	var expected_plan := {
		"enabled": true,
		"boss_spawn_local_m": [0.0, 0.0],
		"activation_delay_sec": 10.0,
		"spawn_rows": [
			{"side": "west", "x_m": -18.0, "z_m": [-14.0, -7.0, 0.0, 7.0, 14.0], "height_m": 3.0},
			{"side": "east", "x_m": 18.0, "z_m": [-14.0, -7.0, 0.0, 7.0, 14.0], "height_m": 3.0},
		],
		"enemy_request_type": "ambush",
		"initial_count": 3.0,
		"count_step": 1.0,
		"max_count_per_round": 8.0,
		"initial_interval_sec": 6.0,
		"interval_step_sec": -0.35,
		"min_interval_sec": 2.5,
		"max_reinforcement_alive": 18.0,
		"launch_speed_mps": 8.5,
		"launch_duration_sec": 0.38,
	}

	# —— 四段白名单：L2规范化 → 计划 → record → 房实例 ——
	var normalized := LevelPlanLoader.normalize_floor(LEVEL_ID, 0)
	var normalized_boss := {}
	for value in normalized.get("rooms", []):
		var candidate := value as Dictionary
		if str(candidate.get("key", "")) == "boss":
			normalized_boss = candidate
			break
	if normalized_boss.is_empty():
		failures.append("规范化层取不到 boss 房，增援计划入口验收无法成立")
	elif (normalized_boss.get("boss_reinforcement_plan", {}) as Dictionary) != expected_plan:
		failures.append("L2规范化后的 boss_reinforcement_plan 与设计源不一致：%s" % [
			normalized_boss.get("boss_reinforcement_plan", {}),
		])
	var plan_snapshot := tower._floor_plan_snapshots.get(0, {}) as Dictionary
	var planned_boss := {}
	for value in plan_snapshot.get("rooms", []):
		var candidate := value as Dictionary
		if str(candidate.get("id", "")) == "boss":
			planned_boss = candidate
			break
	if (planned_boss.get("boss_reinforcement_plan", {}) as Dictionary) != expected_plan:
		failures.append("生成器计划丢失或改写 boss_reinforcement_plan：%s" % [
			planned_boss.get("boss_reinforcement_plan", {}),
		])
	var record_plan := {}
	for record in tower._records:
		if str(record.get("id", "")) == "boss":
			record_plan = record.get("boss_reinforcement_plan", {}) as Dictionary
			break
	if record_plan != expected_plan:
		failures.append("TowerDescent3D record 丢失或改写 boss_reinforcement_plan：%s" % [record_plan])
	if room.boss_reinforcement_plan != expected_plan:
		failures.append("DungeonRoom3D 实例丢失或改写 boss_reinforcement_plan：%s" % [
			room.boss_reinforcement_plan,
		])

	# 内容参数不属于几何指纹；调整数量/间隔不能让既有房间进度失配。
	if not normalized.is_empty():
		var mode := str(normalized.get("mode", "authored"))
		var baseline_id := FloorPlanGenerator._data_driven_layout_id(
			LEVEL_ID, 0, normalized, mode, GENERATOR_SEED
		)
		var tainted := normalized.duplicate(true)
		for room_value in tainted.get("rooms", []) as Array:
			if str((room_value as Dictionary).get("key", "")) == "boss":
				(room_value as Dictionary)["boss_reinforcement_plan"] = {
					"enabled": true, "initial_count": 99,
				}
		var tainted_id := FloorPlanGenerator._data_driven_layout_id(
			LEVEL_ID, 0, tainted, mode, GENERATOR_SEED
		)
		if tainted_id != baseline_id:
			failures.append("boss_reinforcement_plan 竟参与 layout_id（调增援会使旧存档失配）")

	# —— Marker几何：Boss正中心，两侧各5点，全部离地3米 ——
	var center := room.get_node_or_null("BossSpawnCenter") as Marker3D
	if center == null:
		failures.append("Boss房没有运行时 BossSpawnCenter")
	elif center.position.distance_to(Vector3.ZERO) > 0.001:
		failures.append("BossSpawnCenter 不在房间局部正中心：%s" % center.position)
	var markers := room.boss_reinforcement_spawn_markers()
	if markers.size() != 10:
		failures.append("Boss增援挂点应为两侧各5个、共10个，实为 %d" % markers.size())
	var west := 0
	var east := 0
	for marker in markers:
		var side := str(marker.get_meta("spawn_side", ""))
		west += 1 if side == "west" else 0
		east += 1 if side == "east" else 0
		if not is_equal_approx(marker.position.y, 3.0):
			failures.append("Boss增援挂点未离地3米：%s=%s" % [marker.name, marker.position])
		if side == "west" and not is_equal_approx(marker.position.x, -18.0):
			failures.append("西侧挂点横坐标错误：%s=%s" % [marker.name, marker.position])
		if side == "east" and not is_equal_approx(marker.position.x, 18.0):
			failures.append("东侧挂点横坐标错误：%s=%s" % [marker.name, marker.position])
	if west != 5 or east != 5:
		failures.append("Boss增援挂点分组错误：west=%d east=%d" % [west, east])
	var marker_cycle := tower._boss_reinforcement_marker_cycle(room)
	if marker_cycle.size() != 10:
		failures.append("Boss增援轮询挂点数不为10：%d" % marker_cycle.size())
	else:
		for index in range(marker_cycle.size()):
			var expected_side := "west" if index % 2 == 0 else "east"
			if str(marker_cycle[index].get_meta("spawn_side", "")) != expected_side:
				failures.append("双排轮询未按 west/east 交替：index=%d" % index)
				break

	# —— 静态语义门禁正反例 ——
	var legal_probe := LevelPlanValidator._validate_boss_reinforcement_plan({
		"key": "boss_probe", "role": "boss", "content_type": "BOSS",
		"size": BOSS_ROOM_SIZE, "boss_reinforcement_plan": expected_plan,
	})
	if not legal_probe.is_empty():
		failures.append("合法 boss_reinforcement_plan 被静态校验误报：%s" % [legal_probe])
	var non_boss_probe := LevelPlanValidator._validate_boss_reinforcement_plan({
		"key": "combat_probe", "role": "main", "content_type": "COMBAT",
		"size": CONTENT_ROOM_SIZE, "boss_reinforcement_plan": expected_plan,
	})
	if not _has_error_prefix(non_boss_probe, "boss_reinforcement_plan_on_non_boss_room"):
		failures.append("非Boss房写增援计划未被拦住：%s" % [non_boss_probe])
	var broken_plan := expected_plan.duplicate(true)
	broken_plan["spawn_rows"] = [
		{"side": "west", "x_m": -40.0, "z_m": [], "height_m": 0.0},
		{"side": "west", "x_m": 18.0, "z_m": [40.0], "height_m": 3.0},
	]
	broken_plan["enemy_request_type"] = "minion"
	broken_plan["initial_count"] = 3.5
	var broken_probe := LevelPlanValidator._validate_boss_reinforcement_plan({
		"key": "broken_boss", "role": "boss", "content_type": "BOSS",
		"size": BOSS_ROOM_SIZE, "boss_reinforcement_plan": broken_plan,
	})
	for prefix in [
		"boss_reinforcement_row_x_outside_room",
		"boss_reinforcement_row_z_empty",
		"boss_reinforcement_row_height_invalid",
		"boss_reinforcement_row_side_duplicate",
		"boss_reinforcement_rows_require_west_east",
		"boss_reinforcement_enemy_request_type_invalid",
		"boss_reinforcement_initial_count_invalid",
	]:
		if not _has_error_prefix(broken_probe, prefix):
			failures.append("坏增援参数未触发静态错误 %s：%s" % [prefix, broken_probe])

	# —— 正式进房、Boss中心出生与激活后计时 ——
	room.ensure_shell_built()
	room.ensure_detail_built()
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower._on_room_entered(room)
	await get_tree().physics_frame
	var boss: Enemy3D = null
	for value in tower._enemy_nodes_by_room.get(room.room_id, []) as Array:
		if value is Enemy3D and str((value as Enemy3D).get_enemy_data().get("boss_content_id", "")) == "boss_monitor002":
			boss = value as Enemy3D
			break
	if boss == null:
		failures.append("正式进入Boss房后没有生成 boss_monitor002")
		return
	if boss.global_position.distance_to(room.boss_spawn_position_world()) > 0.05:
		failures.append("Boss未出生在Boss房正中心：%s vs %s" % [
			boss.global_position, room.boss_spawn_position_world(),
		])
	if not boss.boss_activation_completed.is_connected(tower._on_boss_activation_completed):
		failures.append("Boss激活完成信号未接入Dungeon3D增援控制器")
	# 避免本测试手动推进时又被场景_process自动推进一份。
	tower.set_process(false)
	tower._on_boss_activation_completed(boss)
	var state := tower._boss_reinforcement_states.get(room.room_id, {}) as Dictionary
	if not bool(state.get("armed", false)) or not is_zero_approx(float(state.get("elapsed", -1.0))):
		failures.append("Boss激活完成后没有从0秒武装增援状态：%s" % [state])
	tower._tick_boss_reinforcements(9.99)
	if tower._boss_reinforcement_alive(room.room_id) != 0:
		failures.append("Boss激活完成未满10秒就生成了增援")
	tower._tick_boss_reinforcements(0.01)
	if tower._boss_reinforcement_alive(room.room_id) != 3:
		failures.append("第10秒第一轮应预约3只增援，实为 %d" % tower._boss_reinforcement_alive(room.room_id))
	if int((tower._boss_reinforcement_states[room.room_id] as Dictionary).get("round", -1)) != 1:
		failures.append("第一轮后round未推进到1：%s" % [tower._boss_reinforcement_states[room.room_id]])
	# 私有抛射参数必须随预约保留到实例化前；实到后必须从enemy_data移除，但速度朝房心。
	var reserved := tower._reserved_room_spawns.get(room.room_id, []) as Array
	if reserved.is_empty() or ((reserved[0] as Dictionary).get("configs", []) as Array).size() != 3:
		failures.append("第一轮3只增援未完整进入正式预约队列：%s" % [reserved])
	else:
		var first_config := (((reserved[0] as Dictionary).get("configs", []) as Array)[0] as Dictionary)
		if not first_config.get("spawn_launch_target", null) is Vector3:
			failures.append("增援预约丢失朝中心抛射目标")
		if not is_equal_approx(float(first_config.get("spawn_launch_speed_mps", 0.0)), 8.5):
			failures.append("增援预约抛射速度不是8.5m/s：%s" % [first_config])
	tower._flush_reserved_room_spawns(room.room_id)
	var first_wave := _boss_reinforcement_enemies(tower, room.room_id)
	if first_wave.size() != 3:
		failures.append("第一轮预约实到后应为3只增援，实为%d" % first_wave.size())
	for enemy in first_wave:
		var to_center := room.boss_spawn_position_world() - enemy.global_position
		to_center.y = 0.0
		var velocity := enemy._external_velocity
		velocity.y = 0.0
		if velocity.length_squared() <= 0.01 or velocity.normalized().dot(to_center.normalized()) < 0.999:
			failures.append("增援出生外力没有朝房间中心：%s -> %s" % [enemy.global_position, enemy._external_velocity])
		if enemy.get_enemy_data().has("spawn_launch_target"):
			failures.append("出生抛射私有字段污染了敌人配置/存档数据")

	# 第一轮后间隔=6-0.35=5.65秒；边界前不刷，跨界刷4只。
	tower._tick_boss_reinforcements(5.64)
	if tower._boss_reinforcement_alive(room.room_id) != 3:
		failures.append("第二轮间隔未满5.65秒就刷怪")
	# 明确跨过5.65秒边界：5.64 + 0.01 在二进制浮点下可能略小于5.65，不能拿它做越界样本。
	tower._tick_boss_reinforcements(0.02)
	if tower._boss_reinforcement_alive(room.room_id) != 7:
		failures.append("第二轮应递增4只、累计7只，实为%d" % tower._boss_reinforcement_alive(room.room_id))
	if int((tower._boss_reinforcement_states[room.room_id] as Dictionary).get("round", -1)) != 2:
		failures.append("第二轮后round未推进到2")
	tower._flush_reserved_room_spawns(room.room_id)

	# 离开当前活动房时倒计时暂停；回来后从原值继续。
	state = tower._boss_reinforcement_states[room.room_id] as Dictionary
	state["elapsed"] = 1.25
	tower._boss_reinforcement_states[room.room_id] = state
	tower._current_room_id = "room_01"
	tower._tick_boss_reinforcements(100.0)
	if not is_equal_approx(float((tower._boss_reinforcement_states[room.room_id] as Dictionary).get("elapsed", 0.0)), 1.25):
		failures.append("离开Boss房后增援倒计时仍在后台推进")
	tower._current_room_id = room.room_id

	# 快照保存并恢复倒计时、轮次和挂点游标，不得重置为第一轮。
	state = tower._boss_reinforcement_states[room.room_id] as Dictionary
	state["elapsed"] = 2.2
	state["round"] = 4
	state["cursor"] = 7
	tower._boss_reinforcement_states[room.room_id] = state
	tower._capture_room_runtime_state(room.room_id)
	var captured := (tower._segment_runtime_state[room.room_id] as Dictionary).get(
		"boss_reinforcement_state", {}
	) as Dictionary
	if int(captured.get("round", -1)) != 4 or int(captured.get("cursor", -1)) != 7:
		failures.append("Boss增援状态未写入房间段快照：%s" % [captured])
	tower._boss_reinforcement_states[room.room_id] = {
		"armed": false, "stopped": false, "elapsed": 0.0, "round": 0, "cursor": 0,
	}
	tower._restore_room_runtime_state(room.room_id)
	var restored := tower._boss_reinforcement_states[room.room_id] as Dictionary
	if (
		int(restored.get("round", -1)) != 4
		or int(restored.get("cursor", -1)) != 7
		or not is_equal_approx(float(restored.get("elapsed", 0.0)), 2.2)
	):
		failures.append("Boss增援快照恢复后轮次/游标/倒计时被重置：%s" % [restored])

	# 存活上限同时计算实体与预约：当前7只，从高轮次先约8、再约3到18，第三次必须拒绝。
	var cap_state := {"armed": true, "stopped": false, "elapsed": 0.0, "round": 5, "cursor": 0}
	var cap_first := int(tower._spawn_boss_reinforcement_round(room, cap_state))
	var cap_second := int(tower._spawn_boss_reinforcement_round(room, cap_state))
	var cap_third := int(tower._spawn_boss_reinforcement_round(room, cap_state))
	if [cap_first, cap_second, cap_third] != [8, 3, 0]:
		failures.append("18只上限未同时计入实体与预约：%s（期望[8,3,0]）" % [[cap_first, cap_second, cap_third]])
	if tower._boss_reinforcement_alive(room.room_id) != 18:
		failures.append("Boss增援存活上限应锁在18，实为%d" % tower._boss_reinforcement_alive(room.room_id))
	tower._flush_reserved_room_spawns(room.room_id)
	if _boss_reinforcement_enemies(tower, room.room_id).size() != 18:
		failures.append("18只上限的预约实到后实体数不为18")

	# Boss死亡后停止新轮次；但18只增援仍在时房间不能提前清除。
	boss.take_damage(1000000)
	tower._tick_boss_reinforcements(100.0)
	if not bool((tower._boss_reinforcement_states[room.room_id] as Dictionary).get("stopped", false)):
		failures.append("Boss死亡后增援控制器未停止")
	if room.cleared:
		failures.append("Boss死亡但剩余增援未清完时房间提前清除")
	var alive_before_stop := tower._boss_reinforcement_alive(room.room_id)
	tower._tick_boss_reinforcements(100.0)
	if tower._boss_reinforcement_alive(room.room_id) != alive_before_stop:
		failures.append("Boss死亡后仍继续生成增援")
	for enemy in _boss_reinforcement_enemies(tower, room.room_id):
		enemy.take_damage(1000000)
	# Boss房还可能有正式精英随从；全部清除后才应清房。
	for value in (tower._enemy_nodes_by_room.get(room.room_id, []) as Array).duplicate():
		if value is Enemy3D and is_instance_valid(value) and (value as Enemy3D).ai_state != "dead":
			(value as Enemy3D).take_damage(1000000)
	await get_tree().process_frame
	if not room.cleared:
		failures.append("Boss与剩余增援全部清除后房间仍未清除")

	tower.set_process(true)
	if failures.size() == failures_before:
		print(
			"TEST_LEVEL_99_BOSS_REINFORCEMENT_OK 计划四段透传/layout_id隔离/中心Boss/"
			+ "双排3米挂点/10秒延迟/3→4递增/朝中心抛射/18只上限/离房暂停/"
			+ "快照恢复/Boss死亡停止/剩余敌人清房门禁 全绿"
		)


func _boss_reinforcement_enemies(
	tower: TowerDescent3D, room_id: String
) -> Array[Enemy3D]:
	var result: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get(room_id, []) as Array:
		if (
			value is Enemy3D
			and is_instance_valid(value)
			and not (value as Enemy3D).is_queued_for_deletion()
			and (value as Enemy3D).ai_state != "dead"
			and bool((value as Enemy3D).get_enemy_data().get("boss_reinforcement_spawned", false))
		):
			result.append(value as Enemy3D)
	return result


## 房间级掉落计划（`reward_plan`）的端到端落地断言。
##
## 与 `_verify_boss_identity` 末段同一处境：**当前没有任何关卡在数据里写
## reward_plan**，纯读现成关卡会让端到端断言退化成 0 样本空跑并静默通过。
## 故这里用手写 patch 直接驱动入口（Loader 白名单）与出口（Generator 透传）两侧，
## 把四段契约各钉成一条真会失败的断言：
##   ① 入口白名单：`LevelPlanLoader.normalize_floor` 漏登记 = 字段静默丢弃；
##   ② 出口透传：`FloorPlanGenerator.room_from_source` 漏登记 = 字段静默丢弃；
##   ③ 槽位投影：`reward_slots_from_rooms` 必须带 `ref`（池简写 / 内联两种写法
##      **没有 spec_id**，只投影 spec_id 会在这一步静默丢内容）；
##   ④ 指纹隔离：`reward_plan` 属于内容不属几何，改它**不得**改变 `layout_id`
##      —— 否则调掉落会让既有存档的房间进度失配。
## 另加静态校验两条正反例：合法槽位不得误报、未登记池 / Boss 房写 kill 必须拦住。
## 失效方式全是静默的，作者只会看到「我明明填了却没生效」或「存档莫名其妙要我重打」。
func _verify_reward_plan(failures: Array[String]) -> void:
	var failures_before := failures.size()
	# —— ① 入口白名单防漏登记 ——
	var normalized := LevelPlanLoader.normalize_floor(LEVEL_ID, 0)
	# 取不到规范化数据 = 下面 ①④ 两条断言退化成空跑并静默通过。宁可红，不要假绿。
	if normalized.is_empty():
		failures.append("取不到测试关卡99 的规范化层数据，reward_plan 断言会退化成空跑（不得静默通过）")
	for value in normalized.get("rooms", []):
		if not (value as Dictionary).has("reward_plan"):
			failures.append(
				"LevelPlanLoader 白名单漏登记 reward_plan，房间级该字段会被静默丢弃"
			)
			break

	# —— ② 出口透传：三种合法写法各驱动一次（池简写 / 命名规格 / 内联）——
	var active_pool := _first_active_pool_id()
	if active_pool.is_empty():
		failures.append("掉落池登记表里没有一个可用池，reward_plan 断言无法成立")
		return
	var authored := FloorPlanGenerator.room_from_source({
		"key": "reward_probe", "room_id": "reward_probe", "role": "main",
		"content_type": "COMBAT", "size": CONTENT_ROOM_SIZE,
		"reward_plan": {
			"clear": {"pool_id": active_pool, "draws": 2},
			"search": {"spec_id": "probe_named_spec"},
			"kill": {"entries": [
				{"kind": "currency", "currency_id": "extraction_points", "amount": 3},
			]},
		},
	})
	var carried := authored.get("reward_plan", {}) as Dictionary
	if carried.size() != 3:
		failures.append(
			"FloorPlanGenerator 未把 reward_plan 透传进运行时房间（应为 3 个 trigger 槽，实为 %d）：%s"
			% [carried.size(), str(carried)]
		)
	else:
		var pool_slot := carried.get("clear", {}) as Dictionary
		if str(pool_slot.get("pool_id", "")) != active_pool:
			failures.append("reward_plan 的 pool_id 写法透传后被改写：%s" % str(pool_slot))
		elif int(pool_slot.get("draws", 0)) != 2:
			failures.append("reward_plan 的 draws 在透传后被改写：%s" % str(pool_slot))
		var spec_slot := carried.get("search", {}) as Dictionary
		if str(spec_slot.get("spec_id", "")) != "probe_named_spec":
			failures.append("reward_plan 的 spec_id 写法透传后被改写：%s" % str(spec_slot))
		var inline_slot := carried.get("kill", {}) as Dictionary
		var inline_entries := inline_slot.get("entries", []) as Array
		if inline_entries.size() != 1 or str((inline_entries[0] as Dictionary).get("kind", "")) != "currency":
			failures.append("reward_plan 的内联 entries 写法透传后被改写：%s" % str(inline_slot))
	# 没写就不许凭空长出来 —— 否则「本房不覆盖」会被上游残留值污染成「已覆盖」。
	var plain_room := FloorPlanGenerator.room_from_source({
		"key": "plain_probe", "room_id": "plain_probe", "role": "main",
		"content_type": "COMBAT", "size": CONTENT_ROOM_SIZE,
	})
	if not (plain_room.get("reward_plan", {}) as Dictionary).is_empty():
		failures.append(
			"没写 reward_plan 的普通房竟被赋了值：%s" % str(plain_room.get("reward_plan"))
		)

	# —— ③ 槽位投影（05 §11）——
	var slots := FloorPlanGenerator.reward_slots_from_rooms([authored])
	if slots.size() != 3:
		failures.append("reward_slots 投影条数应为 3，实为 %d（槽位静默丢失）" % slots.size())
	else:
		var typed_pool := _slot_by_trigger(slots, "clear")
		var typed_spec := _slot_by_trigger(slots, "search")
		var typed_inline := _slot_by_trigger(slots, "kill")
		# slot_id 必须稳定 = "<运行时 room_id>:<trigger>"：它是存档与事件去重的键。
		if str(typed_pool.get("slot_id", "")) != "reward_probe:clear":
			failures.append("clear 槽的 slot_id 不稳定：%s" % str(typed_pool.get("slot_id", "")))
		if str(typed_pool.get("room_id", "")) != "reward_probe":
			failures.append("reward_slots 的 room_id 不是运行时房间 ID：%s" % str(typed_pool))
		if str(typed_spec.get("spec_id", "")) != "probe_named_spec":
			failures.append("命名规格槽的 spec_id 没投影出来：%s" % str(typed_spec))
		# 池简写与内联写法**没有 spec_id**，必须靠 ref 才能不丢内容。
		if str(typed_pool.get("spec_id", "")) != "":
			failures.append("池简写槽不该有 spec_id（写法里本就没有）：%s" % str(typed_pool))
		if str((typed_pool.get("ref", {}) as Dictionary).get("pool_id", "")) != active_pool:
			failures.append("reward_slots 丢掉池简写的 ref，该槽解析时会退化成空：%s" % str(typed_pool))
		var inline_ref := typed_inline.get("ref", {}) as Dictionary
		if (inline_ref.get("entries", []) as Array).size() != 1:
			failures.append("reward_slots 丢掉内联槽的 ref，该槽解析时会退化成空：%s" % str(typed_inline))
	# 没写 reward_plan 的房不产槽位（投影不得凭空造槽）。
	var no_slots := FloorPlanGenerator.reward_slots_from_rooms([plain_room])
	if not no_slots.is_empty():
		failures.append("没写 reward_plan 的房竟投影出 %d 条槽位" % no_slots.size())

	# —— ④ 指纹隔离：改掉落不得改 layout_id ——
	# 直接拿真实关卡的规范化数据算两次指纹：一次原样、一次给每间房塞满 reward_plan。
	# 两者必须逐字相同 —— 掉落是内容不是几何，绝不参与房间进度指纹。
	# （若哪天有人把 reward_plan 加进 _data_driven_layout_id 的白名单，这条立刻红。）
	if not normalized.is_empty():
		var mode := str(normalized.get("mode", "authored"))
		var baseline_id := FloorPlanGenerator._data_driven_layout_id(
			LEVEL_ID, 0, normalized, mode, GENERATOR_SEED
		)
		var tainted := normalized.duplicate(true)
		var tainted_rooms: Array = tainted.get("rooms", [])
		for room_value in tainted_rooms:
			(room_value as Dictionary)["reward_plan"] = {
				"clear": { "pool_id": active_pool },
				"search": { "entries": [{ "kind": "currency", "currency_id": "extraction_points", "amount": 1 }] },
				"kill": { "spec_id": "probe_named_spec" },
			}
		var tainted_id := FloorPlanGenerator._data_driven_layout_id(
			LEVEL_ID, 0, tainted, mode, GENERATOR_SEED
		)
		if tainted_id != baseline_id:
			failures.append(
				"reward_plan 竟参与了 layout_id 指纹（改掉落会让既有存档失配）：%s -> %s"
				% [baseline_id, tainted_id]
			)

	# —— 静态校验：两条正反例 ——
	var legal_probe := LevelPlanValidator._validate_reward_plan({
		"key": "legal_probe", "role": "main", "content_type": "COMBAT",
		"reward_plan": {
			"clear": { "pool_id": active_pool, "draws": 1 },
			"search": { "entries": [{ "kind": "currency", "currency_id": "extraction_points", "amount": 2 }] },
			"kill": { "spec_id": "probe_named_spec" },
		},
	})
	if not legal_probe.is_empty():
		failures.append("合法的 reward_plan 竟被静态校验判错：%s" % [legal_probe])
	var unknown_pool_probe := LevelPlanValidator._validate_reward_plan({
		"key": "unknown_pool_probe", "role": "main", "content_type": "COMBAT",
		"reward_plan": { "clear": { "pool_id": "pool_not_registered_at_all" } },
	})
	if not _has_error_prefix(unknown_pool_probe, "reward_plan_unknown_pool"):
		failures.append("未登记的掉落池未被静态校验拦住：%s" % [unknown_pool_probe])
	# Boss 房不刷普通怪 ⇒ 永不产生击杀事件，写 kill 槽等于静默失效；非战斗房同理。
	var boss_kill_probe := LevelPlanValidator._validate_reward_plan({
		"key": "boss_probe", "role": "boss", "content_type": "BOSS",
		"reward_plan": { "kill": { "pool_id": active_pool } },
	})
	if not _has_error_prefix(boss_kill_probe, "reward_plan_kill_on_boss_room"):
		failures.append("Boss 房写 kill 掉落槽未被拦住：%s" % [boss_kill_probe])
	var safe_kill_probe := LevelPlanValidator._validate_reward_plan({
		"key": "safe_probe", "role": "stair_entry", "content_type": "STAIR_LOBBY",
		"reward_plan": { "kill": { "pool_id": active_pool } },
	})
	if not _has_error_prefix(safe_kill_probe, "reward_plan_kill_on_non_hostile_room"):
		failures.append("安全房写 kill 掉落槽未被拦住：%s" % [safe_kill_probe])
	# 一个槽位同时写两种写法 = 语义不明，必须当场拦（运行时只认其中一种，另一种静默失效）。
	var ambiguous_probe := LevelPlanValidator._validate_reward_plan({
		"key": "ambiguous_probe", "role": "main", "content_type": "COMBAT",
		"reward_plan": { "clear": { "pool_id": active_pool, "spec_id": "probe_named_spec" } },
	})
	if not _has_error_prefix(ambiguous_probe, "reward_plan_slot_ambiguous"):
		failures.append("同时写 pool_id 与 spec_id 的槽位未被拦住：%s" % [ambiguous_probe])

	# 成功标记：本块的全部门禁是「设计源零样本 + 手写 patch」，静默通过极难与真跑区分，
	# 故必须打一行可 grep 的绿标（其它分段级断言同此约定）。
	if failures.size() == failures_before:
		print(
			"TEST_LEVEL_99_REWARD_OK 入口白名单/出口透传(池简写·命名规格·内联)/槽位投影(含 ref)"
			+ "/layout_id 指纹隔离/静态校验正反例 全绿（设计源零样本，走手写 patch 探针）"
		)


## 取登记表里第一个可用（未弃用）的掉落池，供上面断言当「已知合法」样本。
## 不写死池名：池会随版本弃用，写死会让这条断言在无关改动下变红（噪音）。
func _first_active_pool_id() -> String:
	for pool_id in RewardPoolRegistry.pool_ids():
		if RewardPoolRegistry.is_active(pool_id):
			return pool_id
	return ""


## 按 trigger 取投影出来的一条槽位；取不到返回空字典（调用方的判据自会红）。
func _slot_by_trigger(slots: Array[Dictionary], trigger: String) -> Dictionary:
	for slot in slots:
		if str(slot.get("trigger", "")) == trigger:
			return slot
	return {}


## 断言错误列表里存在指定前缀的错误码。
func _has_error_prefix(errors: Array, prefix: String) -> bool:
	for error in errors:
		if str(error).begins_with(prefix):
			return true
	return false


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
			+ "design source loaded with runtime_enabled pinned per level (99 + expedition_01 on, "
			+ "battle_level01 off), "
			+ "generator trigger=level_plan_data with 4 rooms start/room_01/boss/extraction "
			+ "(no fallback to the 5-content-room builtin table), "
			+ "standalone single-layer scene on Dungeon3D base with Blocks/Expedition only, "
			+ "content bounds shrunk to the 4-room footprint with real raycast floor/walls, "
			+ "free entry gate, STANDARD extraction beacon in the extraction room, "
			+ "99F mission-operations menu exposes the test-level-99 entry button, "
			+ "room_01 stays on the global formula while the boss room is authored "
			+ "boss_content_id=boss_monitor002, "
			+ "boss rooms excluded from spawn-plan authoring at both validator and runtime, "
			+ "boss identity authorable per room via boss_content_id through one resolver "
			+ "(authored id wins over the floor roster, an unknown id is never silently swapped, "
			+ "and an unspecified single-layer boss room spawns no boss at all), "
			+ "boss_content_id survives both the loader whitelist and the generator passthrough "
			+ "(level 99 authors boss_monitor002 for its boss room), "
			+ "reward_plan survives both the loader whitelist and the generator passthrough, "
			+ "projects to reward_slots with ref intact for pool/inline forms, stays out of "
			+ "layout_id, and is gated on unknown pools plus kill slots on non-hostile rooms "
			+ "(hand-written patch probe, same reason), "
			+ "loading screen follows the pending level and falls back to expedition_01 unchanged"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
