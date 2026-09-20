extends Node
## 远征关卡01（expedition）闭环验收。替代已废弃的 verify_rogue_map_segment_flow。
##
## 断言的是「从远征情报室点 E → 读取界面 → 远征关卡01 → 满足基础玩法」这条主线：
##   1) 基地目录动作：mission_operations 仍打开 RogueMapSelectMenu；
##   2) 菜单冒烟：标题/说明/五行版图/传送与关闭按钮可用，目标链路常量正确；
##   3) 读取界面 ExpeditionLoadingScreen：真实构建面包屑 + 标题 + 进度 + 步骤，
##      并把关卡路径指向远征关卡场景（本场景不入树，避免 headless 直接切场景）；
##   4) 远征关卡场景：单层、独立区块 Blocks/Expedition、无天台/基地/楼梯/电梯，
##      且场景本身**不继承塔楼关卡场景**（只搭公共关卡基座 Dungeon3D.tscn）；
##   5) 版图：入口安全屋 15×15（v007 双门美术）+ room_01…room_05 各 25×25 + 撤离房 25×25；
##   6) 房型池按种子洗牌且必含 2 战斗房与 1 搜索房；
##   7) 玩法接线：刷怪、搜索容器、过门命运卡三选一、终点 STANDARD 撤离信标；
##   8) 门策略：入口门免费通行；01 之后的门恢复清房/钥匙/命运卡；
##   9) 退出战局：清空随身物品并按独立副本结算返回正式基地；
##  10) 默认塔楼（TowerDescent3D.tscn）行为不被远征改动污染。

const SAFE_ROOM_SIZE := Vector2(15.0, 15.0)
const EXPEDITION_ROOM_SIZE := Vector2(25.0, 25.0)
const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
## 设计源 id（同时是 LevelPlanLoader 的目录名与「数据驱动开关」的载体）。
## 与 EXPEDITION_SCENE 同样**有意写死**：作为独立旁证，不跟产品代码共用常量。
const EXPEDITION_LEVEL_ID := "expedition_01"
const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const MENU_SCENE := "res://scenes/RogueMapSelectMenu.tscn"
const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const SAFE_ROOM_ART_VERSION := "v007"
## 家具碰撞盒必须覆盖「走行面以上这一段身位」才算真的挡住。用带宽而不是精确身高，
## 是因为判据只要求「盒子的竖直区间与玩家身位区间有交」，避免绑死角色尺寸。
const FACILITY_BLOCK_BAND_MAX_Y := 1.0
const MAIN_ROOM_IDS: Array[String] = ["room_01", "room_02", "room_03", "room_04", "room_05"]
const EXPECTED_ROOM_IDS: Array[String] = [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "extraction",
]
const ROOM_TYPE_POOL: Array[String] = ["COMBAT", "COMBAT", "SCAVENGE", "STORAGE", "EVENT"]
const SIDE_DIRECTIONS := {
	"north": Vector3(0.0, 0.0, -1.0),
	"south": Vector3(0.0, 0.0, 1.0),
	"west": Vector3(-1.0, 0.0, 0.0),
	"east": Vector3(1.0, 0.0, 0.0),
}

var _expedition_snapshot: Dictionary = {}


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_catalog_and_menu(failures)
	await _verify_loading_screen(failures)
	_verify_plan_generator_seeds(failures)
	await _verify_expedition_level(failures)
	await _verify_default_tower(failures)
	await _verify_expedition_exit_contract(failures)
	_report(failures)


## 规划器多种子扫描：远征关卡只有「整图旋转/镜像」与「房型洗牌」两个随机量，
## 两者都必须保持可建造（门间净距 ≥5m、房间不越界、不重叠）。
func _verify_plan_generator_seeds(failures: Array[String]) -> void:
	var layouts: Dictionary = {}
	for seed_value in range(1, 97):
		var plan := FloorPlanGenerator.generate_expedition({
			"run_seed": seed_value, "expedition_id": "expedition_01",
		})
		if not bool(plan.get("valid", false)):
			failures.append("种子 %d 的远征规划不可建造：%s" % [
				seed_value, str(plan.get("validation_errors", [])),
			])
			continue
		layouts[str(plan.get("layout_variant", ""))] = true
		var ids: Array[String] = []
		var types: Array[String] = []
		for room_value in plan.get("rooms", []):
			var spec := room_value as Dictionary
			ids.append(str(spec.get("id", "")))
			if str(spec.get("role", "")) == "main":
				types.append(str(spec.get("type", "")))
		if ids != EXPECTED_ROOM_IDS:
			failures.append("种子 %d 房间清单不正确：%s" % [seed_value, [ids]])
		var sorted_types := types.duplicate()
		var expected_types := ROOM_TYPE_POOL.duplicate()
		sorted_types.sort()
		expected_types.sort()
		if sorted_types != expected_types:
			failures.append("种子 %d 房型池不正确：%s" % [seed_value, [types]])
	# 旋转 0/90/180/270 与镜像都必须真实出现过，否则「随机」是假的。
	if layouts.size() < 4:
		failures.append("远征关卡版图变体过少（随机未生效）：%s" % [layouts.keys()])


# —— 1) 基地目录动作 + 菜单冒烟 ——

func _verify_catalog_and_menu(failures: Array[String]) -> void:
	var def := BaseFacilityCatalog.get_definition("mission_operations")
	if str(def.get("action_kind", "")) != BaseFacilityCatalog.ACTION_MENU:
		failures.append("mission_operations 动作类型不是 menu：%s" % str(def.get("action_kind", "")))
	if str(def.get("action_path", "")) != MENU_SCENE:
		failures.append("mission_operations 目标菜单不是 RogueMapSelectMenu：%s" % str(def.get("action_path", "")))

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

	var consts := _script_constants(menu)
	if str(consts.get("LOADING_SCENE", "")) != LOADING_SCENE:
		failures.append("远征情报室没有先进入读取界面：LOADING_SCENE=%s" % str(consts.get("LOADING_SCENE", "")))
	if str(consts.get("LEVEL_SCENE", "")) != EXPEDITION_SCENE:
		failures.append("远征情报室关卡目标不是远征关卡01：LEVEL_SCENE=%s" % str(consts.get("LEVEL_SCENE", "")))

	var title := menu.find_child("Title", true, false) as Label
	if title == null or not title.text.contains("远征关卡01"):
		failures.append("远征情报室标题未标明远征关卡01：%s" % (title.text if title != null else "<缺失>"))
	var desc := menu.find_child("Description", true, false) as Label
	if desc == null or not desc.text.contains("单层独立行动"):
		failures.append("远征情报室说明未描述单层独立行动")
	var map_view := menu.find_child("MapView", true, false) as VBoxContainer
	if map_view == null or map_view.get_child_count() != 5:
		failures.append(
			"远征情报室版图行数不是 5：%d" % (map_view.get_child_count() if map_view != null else -1)
		)
	var menu_panel := menu.find_child("Panel", true, false) as Control
	if menu_panel == null:
		failures.append("RogueMapSelectMenu 缺少主面板")
	else:
		var viewport_center := get_viewport().get_visible_rect().size * 0.5
		var panel_center := menu_panel.get_global_rect().get_center()
		if not panel_center.is_equal_approx(viewport_center):
			failures.append("RogueMapSelectMenu 主面板未居中：panel=%s viewport=%s" % [panel_center, viewport_center])
	var teleport := menu.find_child("TeleportButton", true, false) as Button
	if teleport == null or not teleport.text.contains("远征"):
		failures.append("RogueMapSelectMenu 缺少远征传送按钮")
	var close_btn := menu.find_child("CloseButton", true, false) as Button
	if close_btn == null:
		failures.append("RogueMapSelectMenu 缺少关闭按钮")
	elif not close_btn.pressed.is_connected(menu._on_close_pressed):
		failures.append("RogueMapSelectMenu 关闭按钮未连接关闭逻辑")
	else:
		close_btn.pressed.emit()
		await get_tree().process_frame
		if is_instance_valid(menu):
			failures.append("RogueMapSelectMenu 关闭按钮未释放菜单")
	if is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame


# —— 2) 读取界面 ——

func _verify_loading_screen(failures: Array[String]) -> void:
	if not ResourceLoader.exists(LOADING_SCENE, "PackedScene"):
		failures.append("读取界面场景不存在：%s" % LOADING_SCENE)
		return
	var packed := load(LOADING_SCENE) as PackedScene
	var screen := packed.instantiate() as CanvasLayer
	if screen == null:
		failures.append("ExpeditionLoadingScreen 实例化失败")
		return
	# 刻意不入树：本界面的 _ready 在 headless 环境会立即 change_scene_to_file，
	# 入树会把这份验收场景整个替换掉。这里只验证它的结构与目标路径。
	var consts := _script_constants(screen)
	if str(consts.get("LEVEL_SCENE", "")) != EXPEDITION_SCENE:
		failures.append("读取界面未指向远征关卡场景：%s" % str(consts.get("LEVEL_SCENE", "")))
	if float(consts.get("TOTAL_DURATION_S", 0.0)) <= 0.0:
		failures.append("读取界面缺少正向过场时长")
	var step_texts := consts.get("STEP_TEXTS", []) as Array
	if step_texts.size() < 3:
		failures.append("读取界面步骤文案不足：%d" % step_texts.size())
	screen.call("_build_ui")
	var root := screen.get_node_or_null("Root") as Control
	if root == null:
		failures.append("读取界面缺少 Root 层")
	else:
		var breadcrumb := screen.get_node_or_null("Root/Center/Breadcrumb") as Label
		if breadcrumb == null or not breadcrumb.text.contains("远征情报室"):
			failures.append("读取界面缺少「远征情报室 → 关卡」面包屑")
		var title := screen.get_node_or_null("Root/Center/Title") as Label
		if title == null or title.text != "远征关卡01":
			failures.append("读取界面标题不是远征关卡01：%s" % (title.text if title != null else "<缺失>"))
		var progress := screen.get_node_or_null("Root/Center/Progress") as ProgressBar
		if progress == null or progress.max_value <= 0.0:
			failures.append("读取界面缺少进度条")
		var step := screen.get_node_or_null("Root/Center/Step") as Label
		if step == null or step.text.is_empty():
			failures.append("读取界面缺少步骤文案")
	screen.free()


# —— 3) 远征关卡本体 ——

func _verify_expedition_level(failures: Array[String]) -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		failures.append("ExpeditionLevel01_3D.tscn 加载失败")
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		failures.append("ExpeditionLevel01_3D 实例化失败")
		return
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	if not tower.is_expedition():
		failures.append("远征关卡场景未开启 expedition_mode")
	if tower.get_expedition_run_id() != "expedition_01":
		failures.append("远征关卡运行时标识不正确：%s" % tower.get_expedition_run_id())
	if str(tower.get_runtime_map_id()) != "expedition_01":
		failures.append("远征关卡存档隔离标识不正确：%s" % str(tower.get_runtime_map_id()))
	if tower.return_scene_path != GameDesignConfig.MAIN_SCENE:
		failures.append("远征关卡退出落点不是玩家出发的塔楼 99F 基地：%s" % tower.return_scene_path)

	# 单层：只有 floor_index 0，不存在 99F 基地、98—95F 战局与 94F 以下。
	var planned_layers := tower.get_expedition_planned_floor_numbers()
	if planned_layers != [0]:
		failures.append("远征关卡不是单层：规划层索引=%s" % [planned_layers])
	for forbidden_layer in [1, 2, 3, 4, 5, 6]:
		if tower._floor_plan_snapshots.has(forbidden_layer):
			failures.append("远征关卡不应规划层索引 %d" % forbidden_layer)
	if tower._room_by_id.has("facility"):
		failures.append("远征关卡不应存在 99F 基地房 facility")
	if tower._room_by_id.has("floor_01_entry"):
		failures.append("远征关卡不应存在塔楼 98F 房间 floor_01_entry")
	if not (tower._elevator_facilities_by_floor as Dictionary).is_empty():
		failures.append("远征关卡不应生成楼层电梯")

	_verify_expedition_block(tower, failures)
	_verify_clean_scene(tower, failures)
	await _verify_level_enclosure(tower, failures)
	_verify_expedition_rooms(tower, failures)
	_verify_expedition_plan(tower, failures)
	var start_room := _verify_safe_room(tower, failures)
	_verify_door_policies(tower, failures)
	_verify_extraction(tower, failures)
	_verify_spawn_and_search(tower, failures)
	await _verify_fate_on_door(tower, failures)

	_expedition_snapshot = tower.build_runtime_save_snapshot()
	if str(_expedition_snapshot.get("scope", "")) != "combat":
		failures.append("远征关卡入口不是战局范围：%s" % str(_expedition_snapshot.get("scope", "")))
	if str(_expedition_snapshot.get("runtime_map_id", "")) != "expedition_01":
		failures.append("远征关卡行动快照缺少 expedition_01 隔离标记")

	if start_room != null:
		# 出生点必须落在入口安全屋内部，且不是房间正中（避免开局顶着抵达门）。
		var spawn_offset := tower._expedition_entry_spawn_offset(start_room)
		if spawn_offset.length() < 1.0:
			failures.append("远征关卡出生点偏移退化到房间正中：%s" % spawn_offset)

	_verify_hud_labels(tower, failures)

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## HUD 文案门禁：远征关卡不得残留塔楼楼层/区域语义。
## 这两处文案是运行时按 room_id 与 minimap 状态拼出来的字符串，
## 几何、区块、包络校验全都看不见 —— 属于「数据全对但玩家看到错字」那一类，
## 只能靠直接驱动房间进入、再读玩家真正看到的那条文案来守。
func _verify_hud_labels(tower: TowerDescent3D, failures: Array[String]) -> void:
	var level_name := tower.get_expedition_display_name()
	var area_text := str(tower.call("_hud_floor_label_text"))
	if area_text.contains("高塔外层") or area_text.contains("100F"):
		failures.append("远征关卡地图区域标签残留塔楼语义：%s" % area_text)
	elif not area_text.contains(level_name):
		failures.append("远征关卡地图区域标签未标明关卡名：%s" % area_text)
	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		failures.append("HUD 文案门禁缺少入口安全屋")
		return
	# 真实驱动一次「进入房间」，断言顶栏上真正显示的那条文案。
	tower.call("_on_room_entered", start_room)
	var room_text := str(tower.room_label.text)
	if room_text.contains("100F") or room_text.contains("99F"):
		failures.append("远征关卡房间标签残留塔楼楼层语义：%s" % room_text)
	elif not room_text.contains(level_name):
		failures.append("远征关卡房间标签未标明关卡名：%s" % room_text)


func _verify_expedition_block(tower: TowerDescent3D, failures: Array[String]) -> void:
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		failures.append("远征关卡缺少 Blocks/Expedition 区块")
		return
	if str(block.get_meta("block_id", "")) != "expedition":
		failures.append("Expedition 区块 block_id 不正确：%s" % str(block.get_meta("block_id", "")))
	if str(block.get_meta("display_name", "")) != "远征关卡01":
		failures.append("Expedition 区块 display_name 不正确：%s" % str(block.get_meta("display_name", "")))
	if str(block.get_meta("runtime_owner", "")) != "TowerDescent3D":
		failures.append("Expedition 区块 runtime_owner 不正确")


## 干净场景契约（2026-09-19 起由「运行时减法」升级为「结构独立」）：
##   远征关卡场景直接搭在公共关卡基座 `scenes/Dungeon3D.tscn` 上，**不再继承塔楼关卡
##   场景** `scenes/TowerDescent3D.tscn`。于是塔楼专属内容不是「被运行时排除」，
##   而是「根本不参与加载」——少一处运行时守卫就是一次污染的旧模型已经被拆掉。
##   1) 场景文件不得把塔楼场景**作为 `ext_resource` 引入** —— 那才是「继承 /
##      子实例化塔楼」，会让塔楼内容整棵随加载。
##      ⚠️ 判据**不能**退化成「源文里出现了塔楼路径字符串」：远征的
##      `return_scene_path` 合法地指向塔楼主场景（那是玩家出发点），它只是
##      一个普通字符串属性，不含任何继承语义（2026-09-19 踩过这个误判）。
##      也不得出现 99F 基地美术 `Blocks/Base/Art`：只置 visible=false 时它的
##      碰撞体仍留在关卡地面上，形成「看不见却撞得到」的空气墙。
##   2) `Blocks` 根下只允许远征自己的 `Blocks/Expedition`；`Rooftop` / `Base` /
##      `Battle` / `Stairs` 必须**不存在**（一旦出现即说明又退回了继承塔楼场景，
##      或有人在远征场景里手工加了塔楼容器）。
##   3) 水平走廊必须挂在 `Blocks/Expedition` 下，而不是塔楼的 `Blocks/Battle`。
func _verify_clean_scene(tower: TowerDescent3D, failures: Array[String]) -> void:
	var scene_text := _read_text(EXPEDITION_SCENE)
	if scene_text.is_empty():
		failures.append("远征关卡场景文件不可读：%s" % EXPEDITION_SCENE)
	else:
		var tower_ref := 'path="%s"' % TOWER_SCENE
		for line in scene_text.split("\n"):
			var trimmed := line.strip_edges()
			if not trimmed.begins_with("[ext_resource"):
				continue
			if trimmed.contains(tower_ref):
				failures.append(
					"远征关卡场景仍把塔楼场景 %s 作为 ext_resource 引入（继承/子实例化会让塔楼内容整棵随加载）" % TOWER_SCENE
				)
				break
	if tower.get_node_or_null("Blocks/Base/Art") != null:
		failures.append("远征关卡残留 99F 基地美术 Blocks/Base/Art（会在地面留下隐形碰撞）")
	var blocks := tower.get_node_or_null("Blocks") as Node3D
	if blocks == null:
		failures.append("远征关卡缺少 Blocks 根节点")
	else:
		var names: Array[String] = []
		for child in blocks.get_children():
			names.append(str(child.name))
		if names != ["Expedition"]:
			failures.append("远征关卡 Blocks 子节点不是唯一的 Expedition：%s" % [names])
		for block_name in ["Rooftop", "Base", "Battle", "Stairs"]:
			if blocks.get_node_or_null(block_name) != null:
				failures.append(
					"远征关卡出现塔楼区块 Blocks/%s（场景已不继承塔楼，出现即回归）" % block_name
				)
	var expedition_block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if expedition_block == null:
		return
	if (tower._corridor_by_edge as Dictionary).is_empty():
		failures.append("远征关卡没有任何走廊连接，干净场景断言无法成立")
	for edge_value in tower._corridor_by_edge.keys():
		var corridor := tower._corridor_by_edge.get(edge_value) as Node3D
		if corridor == null:
			continue
		if corridor.get_parent() != expedition_block:
			failures.append("远征走廊 %s 不在 Blocks/Expedition 下（父节点：%s）" % [
				corridor.name, str(corridor.get_parent()),
			])


## 关卡包围契约：远征是单层关卡，floor_index 同样是 0，最容易误继承 100F 天台窄轮廓
## （90×80 + 99F 中庭洞）——那样 x>40 / z<-35 的房间与走廊会同时失去承重楼面与
## 外圈墙，玩家直接掉出关卡，表现就是「房间没有阻挡」，故必须先断言标准网格已启用。
##
## 在标准网格前提下，楼面与外墙不再铺满塔楼整块 250×250，而是收缩到「7 个房间的
## 实际包围盒 + 一格（5m）留白」（content bounds），于是远处空地上不会再立着一圈
## 没有内容的墙。这里同时断言：内容外框覆盖全部房间、外墙可视高度与碰撞等高
## （防隐形挡墙）、以及真实物理射线（脚下有楼面、四向有墙）。
func _verify_level_enclosure(tower: TowerDescent3D, failures: Array[String]) -> void:
	var stage := tower._floor_stages.get(0) as Node3D
	if stage == null:
		failures.append("远征关卡缺少 0 层楼面舞台")
		return
	var stage_snapshot: Dictionary = stage.get_snapshot()
	if not bool(stage_snapshot.get("force_standard_map", false)):
		failures.append("远征楼面舞台未显式启用标准网格，会继承天台窄轮廓：%s" % stage_snapshot)
		return
	if not bool(stage_snapshot.get("has_content_bounds", false)):
		failures.append("远征楼面舞台没有按内容外框生成：%s" % stage_snapshot)
		return
	var content_rect := stage_snapshot.get("content_world_rect", Rect2()) as Rect2
	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		failures.append("远征内容外框退化为空：%s" % str(content_rect))
		return
	# 外框必须对齐 5m 网格，否则 _world_rect_to_grid 会产生非整数格映射。
	var grid_unit: float = TowerFloorStage3D.GRID_UNIT
	if not is_equal_approx(fmod(content_rect.size.x, grid_unit), 0.0) \
			or not is_equal_approx(fmod(content_rect.size.y, grid_unit), 0.0):
		failures.append("远征内容外框未对齐 %sm 网格：%s" % [str(grid_unit), str(content_rect)])
	# 楼面与外圈墙必须共用同一外框，否则会出现悬空墙或楼面缺口。
	if (stage_snapshot.get("floor_world_rect", Rect2()) as Rect2) != content_rect:
		failures.append("远征楼面世界矩形与内容外框不一致：%s vs %s" % [
			str(stage_snapshot.get("floor_world_rect")), str(content_rect),
		])
	# 全部 7 个房间都必须完整落在内容外框内，否则房间会悬空。
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
			failures.append("房间 %s 不在远征内容外框内：%s ⊄ %s" % [
				room_id, str(room_rect), str(content_rect),
			])
	if int(stage_snapshot.get("support_rect_count", 0)) < 1:
		failures.append("远征楼面没有任何承重碰撞：%s" % stage_snapshot)
	if bool(stage_snapshot.get("base_99_100_atrium_enabled", true)):
		failures.append("远征单层关卡不应挖 99F 中庭洞，否则入口安全房会悬空")
	if not is_equal_approx(
		float(stage_snapshot.get("outer_wall_height", 0.0)), TowerGeometry3D.WALL_LOGICAL_HEIGHT_M
	):
		failures.append("远征外圈墙不是整墙高度：%s" % str(stage_snapshot.get("outer_wall_height")))
	# 可视墙与碰撞墙必须等高：早期 floor_index==0 会把外墙可视高度误压到一半（0.5），
	# 上半截就成了「看不见却挡人」的空气墙。只有真正的 100F 天台女儿墙才允许 0.5。
	if not is_equal_approx(float(stage_snapshot.get("outer_visual_scale_y", 0.0)), 1.0):
		failures.append("远征外圈墙可视高度被异常缩放（隐形挡墙风险）：%s" % str(
			stage_snapshot.get("outer_visual_scale_y")
		))
	if str(stage.get_meta("block_id", "")) != "expedition":
		failures.append("远征楼面舞台 block_id 不是 expedition：%s" % str(stage.get_meta("block_id", "")))

	var space := tower.get_viewport().world_3d.direct_space_state
	# 逐房：脚下必须有承重楼面，四向必须撞到本房间墙。
	for room_id_value in EXPECTED_ROOM_IDS:
		var room_id := str(room_id_value)
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var center := room.global_position
		if _ray(space, center + Vector3(0, 3.0, 0), center + Vector3(0, -3.0, 0)).is_empty():
			failures.append("%s 脚下没有承重楼面，玩家会掉出关卡" % room_id)
		var reach := room.get_dimensions().x * 0.5 + 3.0
		for side_value in SIDE_DIRECTIONS.keys():
			var side := str(side_value)
			var from := center + Vector3(0, 1.5, 0)
			if _ray(space, from, from + (SIDE_DIRECTIONS[side] as Vector3) * reach).is_empty():
				failures.append("%s 的 %s 侧没有墙体阻挡" % [room_id, side])

	# 走廊：房间之间是 10m 真实间隔，通道必须能提供地面与两侧墙。
	var restored_edges: Dictionary = (tower._open_edges as Dictionary).duplicate()
	for edge_value in tower._corridor_by_edge.keys():
		var edge := str(edge_value)
		var corridor := tower._corridor_by_edge[edge_value] as Node3D
		if corridor == null:
			continue
		var start := corridor.get_meta("start_door_position", Vector3.ZERO) as Vector3
		var end := corridor.get_meta("end_door_position", Vector3.ZERO) as Vector3
		var mid := (start + end) * 0.5
		if _ray(space, mid + Vector3(0, 2.0, 0), mid + Vector3(0, -2.0, 0)).is_empty():
			failures.append("走廊 %s 中点没有地面" % edge)
		if start.distance_to(end) <= 0.05:
			continue
		var direction := (end - start).normalized()
		var perpendicular := Vector3(-direction.z, 0.0, direction.x)
		tower._open_edges[edge] = true
		tower.call("_update_corridor_streaming", edge.split("|")[0])
		await get_tree().physics_frame
		if not corridor.visible:
			failures.append("走廊 %s 在房间门开启后仍不可见" % edge)
		var from := mid + Vector3(0, 1.5, 0)
		for sign_value in [-1.0, 1.0]:
			if _ray(space, from, from + perpendicular * (sign_value * 3.5)).is_empty():
				failures.append("走廊 %s 开启后缺少一侧侧墙阻挡" % edge)
	tower._open_edges.clear()
	tower._open_edges.merge(restored_edges)
	tower.call("_update_corridor_streaming", str(tower._current_room_id))


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)


func _verify_expedition_rooms(tower: TowerDescent3D, failures: Array[String]) -> void:
	var ids := tower.get_expedition_room_ids()
	if ids != EXPECTED_ROOM_IDS:
		failures.append("远征关卡房间清单不正确：%s" % [ids])
	for room_id_value in EXPECTED_ROOM_IDS:
		var room_id := str(room_id_value)
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			failures.append("远征关卡缺少房间 %s" % room_id)
			continue
		if room.name != room_id:
			failures.append("%s 节点名被改写为 %s" % [room_id, room.name])
		var parent := room.get_parent()
		if parent == null or str(parent.name) != "Expedition":
			failures.append("%s 不在 Blocks/Expedition 内：%s" % [room_id, str(room.get_path())])
		if str(room.get_meta("block_id", "")) != "expedition":
			failures.append("%s 的 block_id 元数据不是 expedition：%s" % [
				room_id, str(room.get_meta("block_id", "")),
			])
		var expected_size := SAFE_ROOM_SIZE if room_id == "start" else EXPEDITION_ROOM_SIZE
		if not room.get_dimensions().is_equal_approx(expected_size):
			failures.append("%s 尺寸不是 %s：%s" % [room_id, expected_size, room.get_dimensions()])
	if not tower.get_first_safe_room_dimensions().is_equal_approx(SAFE_ROOM_SIZE):
		failures.append("远征关卡首间安全房尺寸不是 15×15：%s" % tower.get_first_safe_room_dimensions())


func _verify_expedition_plan(tower: TowerDescent3D, failures: Array[String]) -> void:
	var plan := tower._floor_plan_snapshots.get(0, {}) as Dictionary
	if plan.is_empty():
		failures.append("远征关卡缺少单层规划快照")
		return
	if not bool(plan.get("valid", false)):
		failures.append("远征关卡规划校验未通过：%s" % str(plan.get("validation_errors", [])))
	# 规划来源判据：期望**由设计源推出**，不写死「应该走哪条路」。
	# 两条路径写进来的 mode 不是同一个概念 —— 内置远征生成器（generate_expedition）写
	# mode="expedition" 并带 trigger="expedition_bootstrap"；数据驱动路径
	# （generate_from_level_plan，由 L1 generation_policy.runtime_enabled 开启）写的是 L2
	# 文件的 mode（合法值只有 LevelPlanLoader.VALID_MODES 的 authored / constrained），
	# 来源改由 trigger="level_plan_data" 标明。
	# 为什么从设计源推：开关被误开或被误关都必须红。若只放行「二者之一」，开关被悄悄关掉
	# 时这条断言仍然绿 —— 那等于把「版图几何从哪来」的契约又丢了。
	var plan_mode := str(plan.get("mode", ""))
	var plan_trigger := str(plan.get("trigger", ""))
	if FloorPlanGenerator.data_driven_enabled(EXPEDITION_LEVEL_ID):
		if plan_trigger != "level_plan_data":
			failures.append(
				"远征关卡声明了 runtime_enabled 却仍走内置房表：trigger=%s" % plan_trigger
			)
	elif plan_mode != "expedition":
		failures.append(
			"远征关卡未声明 runtime_enabled，规划却不是内置远征口径：mode=%s" % plan_mode
		)
	if str(plan.get("terminal_mode", "")) != "extraction_room":
		failures.append("远征关卡终局模式不是撤离房：%s" % str(plan.get("terminal_mode", "")))
	var main_keys := plan.get("main_path_keys", []) as Array
	var expected_main: Array = MAIN_ROOM_IDS.duplicate()
	if main_keys != expected_main:
		failures.append("远征关卡主通道不是 01—05 号房：%s" % [main_keys])
	# 撤离房必须挂在最后一间主通道房之后。
	for room_value in plan.get("rooms", []):
		var spec := room_value as Dictionary
		if str(spec.get("key", "")) != "extraction":
			continue
		if str(spec.get("parent_key", "")) != "room_05":
			failures.append("撤离房父房不是 05 号房：%s" % str(spec.get("parent_key", "")))
		if not (spec.get("dimensions", Vector2.ZERO) as Vector2).is_equal_approx(EXPEDITION_ROOM_SIZE):
			failures.append("撤离房不是 25×25：%s" % str(spec.get("dimensions", Vector2.ZERO)))
	# 房型池按种子洗牌，但必须稳定包含 2 间战斗房与 1 间可搜索房。
	var actual_types: Array[String] = []
	for room_id in MAIN_ROOM_IDS:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room != null:
			actual_types.append(room.room_type)
	var sorted_actual := actual_types.duplicate()
	var sorted_expected := ROOM_TYPE_POOL.duplicate()
	sorted_actual.sort()
	sorted_expected.sort()
	if sorted_actual != sorted_expected:
		failures.append("远征关卡房型池不正确：%s（期望 %s）" % [actual_types, ROOM_TYPE_POOL])
	if actual_types.count("COMBAT") < 2:
		failures.append("远征关卡战斗房不足 2 间，无法保证刷怪：%s" % [actual_types])
	var has_search_room := actual_types.has("SCAVENGE") or actual_types.has("STORAGE")
	if not has_search_room:
		failures.append("远征关卡缺少可搜索房：%s" % [actual_types])


func _verify_safe_room(tower: TowerDescent3D, failures: Array[String]) -> DungeonRoom3D:
	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		failures.append("远征关卡缺少入口安全屋 start")
		return null
	if start_room.room_type != "STAIR_LOBBY":
		failures.append("入口安全屋类型不是 STAIR_LOBBY：%s" % start_room.room_type)
	var snapshot := start_room.get_room_snapshot()
	if str(snapshot.get("safe_room_art_version", "")) != SAFE_ROOM_ART_VERSION:
		failures.append("远征关卡入口未接入 v007 安全房美术：%s" % snapshot)
	# 期望值由 SAFE_ROOM_CORNER_IDS / SAFE_ROOM_WALL_SLOTS 推出，不硬编码：
	# 四角补 L 件后每条边两端各 5m 让位给 L 臂，直墙只留中段槽位（15m = 5 + 5 + 5），
	# 实墙 = 中段槽位数 − 门墙数（门洞本来就在中段）。见 DungeonRoom3D._build_safe_room_shell。
	if not bool(snapshot.get("safe_room_corner_l", false)):
		failures.append("远征入口安全房未启用四角 L 型墙角：%s" % snapshot)
	var expected_corner_count := DungeonRoom3D.SAFE_ROOM_CORNER_IDS.size()
	if int(snapshot.get("safe_room_corner_module_count", -1)) != expected_corner_count:
		failures.append("安全房四角 L 件不是 %d 件：%s" % [expected_corner_count, snapshot])
	var expected_door_wall_count := start_room.doors.size()
	var expected_solid_wall_count := maxi(
		0, DungeonRoom3D.safe_room_middle_slot_count() - expected_door_wall_count
	)
	if int(snapshot.get("safe_room_wall_module_count", -1)) != expected_solid_wall_count:
		failures.append("安全房实墙不是 %d 段：%s" % [expected_solid_wall_count, snapshot])
	if int(snapshot.get("safe_room_door_wall_module_count", -1)) != expected_door_wall_count:
		failures.append("安全房门墙不是 %d 段：%s" % [expected_door_wall_count, snapshot])
	if int(snapshot.get("safe_room_floor_tile_count", -1)) != 9:
		failures.append("安全房地砖不是 9 块：%s" % snapshot)
	# 期望值由常量推出，不硬编码数字：房间包清单会随美术需求增删（2026-09-20 已由
	# 17 减到 15），硬编码会在每次去件时误红。此处只盯「清单里的包全部装配成功」。
	var expected_package_count := DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS.size()
	if int(snapshot.get("safe_room_package_count", -1)) != expected_package_count:
		failures.append("安全房房间包不是 %d 个：%s" % [expected_package_count, snapshot])
	_verify_safe_room_facility_blocking(start_room, expected_package_count, failures)
	if start_room.doors.size() != 2:
		failures.append("安全房必须保留双门结构：%s" % [start_room.doors])
	else:
		var axis_of := {
			"north": "z", "south": "z", "east": "x", "west": "x",
		}
		var first_axis := ""
		var second_axis := ""
		if start_room.doors.size() == 2:
			first_axis = str(axis_of.get(str(start_room.doors[0]), ""))
			second_axis = str(axis_of.get(str(start_room.doors[1]), ""))
		if first_axis.is_empty() or first_axis == second_axis:
			failures.append("安全房两扇门不互相垂直：%s" % [start_room.doors])
	var open_target_count := 0
	var closed_target_count := 0
	var retreat_door_count := 0
	for side_value in start_room.door_targets.keys():
		var side := str(side_value)
		if str(start_room.door_targets[side_value]).is_empty():
			closed_target_count += 1
			var retreat_door := start_room.get_door_node(side)
			if retreat_door != null and retreat_door.get_interaction_prompt_text() == "[E] 退出战局":
				retreat_door_count += 1
		else:
			open_target_count += 1
	if open_target_count != 1:
		failures.append("安全房应有唯一前门目标：%s" % [start_room.door_targets])
	if closed_target_count != 1:
		failures.append("安全房应有唯一封闭抵达门：%s" % [start_room.door_targets])
	if retreat_door_count != 1:
		failures.append("安全房未注册唯一退出战局门：%d" % retreat_door_count)
	var front_targets: Array[String] = []
	for target_value in start_room.door_targets.values():
		if not str(target_value).is_empty():
			front_targets.append(str(target_value))
	if front_targets != ["room_01"]:
		failures.append("安全房前门目标不是 01 号房：%s" % [front_targets])
	return start_room


## 2026-09-20：安全房房间包补齐了「内嵌玩法阻挡」（范例 B：模型 + 碰撞同包）。
## 在这之前 15 个包的 collision_owner 指向 godot_0p30m_structural_proxy —— 一个全仓
## 并不存在的代理，于是设施全部可穿模。本函数盯三件事，期望值全部由包自身 metadata
## 与走行面常量推出，不硬编码件数/尺寸：
##   1. 元数据真实性：collision_shape_count 必须等于实测启用形状数（双向：多一个少一个都红）
##   2. 几何契约：碰撞盒必须是 BoxShape3D 且尺寸 == bounds_size_m
##   3. 可达性：盒子的竖直区间必须与「走行面以上 FACILITY_BLOCK_BAND_MAX_Y」有交
##      —— 挡住看不到的东西不算挡，浮在 4m 高的盒子对玩家等价于不存在
func _verify_safe_room_facility_blocking(
	start_room: DungeonRoom3D, expected_package_count: int, failures: Array[String]
) -> void:
	var art_root := start_room.get_node_or_null("SafeRoomArtRoot")
	if art_root == null:
		failures.append("安全房缺少 SafeRoomArtRoot，无法核对房间包阻挡")
		return
	var checked := 0
	var blocking := 0
	var declared_total := 0
	for value in art_root.get_children():
		var package := value as Node3D
		if package == null or not package.name.begins_with("SafeRoomPackage_"):
			continue
		checked += 1
		var slug := str(package.get_meta("slug", package.name))
		var declared := int(package.get_meta("collision_shape_count", -1))
		var bounds := package.get_meta("bounds_size_m", Vector3.ZERO) as Vector3
		var live := 0
		for body_value in package.find_children("*", "StaticBody3D", true, false):
			var body := body_value as StaticBody3D
			if body.collision_layer == 0:
				continue
			for shape_value in body.find_children("*", "CollisionShape3D", true, false):
				var shape := shape_value as CollisionShape3D
				if shape.disabled or shape.shape == null:
					continue
				live += 1
				var box := shape.shape as BoxShape3D
				if box == null:
					failures.append("%s 阻挡形状不是 BoxShape3D" % slug)
					continue
				if not box.size.is_equal_approx(bounds):
					failures.append("%s 碰撞盒 %s != bounds_size_m %s" % [
						slug, box.size, bounds
					])
				var bottom := shape.global_position.y - box.size.y * 0.5
				var top := shape.global_position.y + box.size.y * 0.5
				if bottom > FACILITY_BLOCK_BAND_MAX_Y or top < 0.0:
					failures.append("%s 碰撞盒 y=[%.2f..%.2f] 与玩家身位无交，等于没挡" % [
						slug, bottom, top
					])
		if declared != live:
			failures.append("%s 元数据 collision_shape_count=%d 与实测启用形状数 %d 不一致" % [
				slug, declared, live
			])
		declared_total += declared
		if declared > 0:
			blocking += 1
	# 防假绿哨兵：脚本报错会静默中断，0 样本断言恒真。
	if checked != expected_package_count:
		failures.append("哨兵：核对到的房间包 %d 件 != 清单 %d 件" % [checked, expected_package_count])
	if blocking == 0:
		failures.append("哨兵：有阻挡的房间包样本为 0，阻挡断言恒真、结论不可信")
	if declared_total == 0:
		failures.append("哨兵：所有房间包声明的碰撞形状数合计为 0，设施可穿模")


func _verify_door_policies(tower: TowerDescent3D, failures: Array[String]) -> void:
	# 入口门是固定交通接口：免费开启，不弹命运卡。
	var entry_policy := tower._door_policy_for_edge("start", "room_01")
	for key in ["requires_clear", "requires_key", "triggers_fate"]:
		if bool(entry_policy.get(key, true)):
			failures.append("安全屋→01 号房入口门应为免费通行：%s" % entry_policy)
	# 01 之后恢复默认清房 / 钥匙 / 命运卡。
	for edge_index in range(MAIN_ROOM_IDS.size() - 1):
		var from_id := MAIN_ROOM_IDS[edge_index]
		var to_id := MAIN_ROOM_IDS[edge_index + 1]
		var policy := tower._door_policy_for_edge(from_id, to_id)
		for key in ["requires_clear", "requires_key", "triggers_fate"]:
			if not bool(policy.get(key, false)):
				failures.append("%s→%s 门策略应保留默认：%s" % [from_id, to_id, policy])


func _verify_extraction(tower: TowerDescent3D, failures: Array[String]) -> void:
	if not tower.has_expedition_extraction():
		failures.append("远征关卡未装配可用撤离信标")
		return
	var beacon := tower._extraction as ExtractionBeacon3D
	var extraction_room := tower._room_by_id.get("extraction") as DungeonRoom3D
	if extraction_room == null:
		failures.append("远征关卡缺少终点撤离房")
		return
	if extraction_room.room_type != "EXTRACTION":
		failures.append("终点房类型不是 EXTRACTION：%s" % extraction_room.room_type)
	if beacon == null:
		failures.append("撤离信标为空")
		return
	if beacon.beacon_type != "STANDARD":
		failures.append("远征撤离信标不是常驻可用的 STANDARD：%s" % beacon.beacon_type)
	if beacon.locked:
		failures.append("远征撤离信标不应上锁")
	if beacon.get_parent() != extraction_room:
		failures.append("撤离信标不在终点撤离房内：%s" % str(beacon.get_path()))
	if (tower._conditional_extractions.get("STANDARD") as ExtractionBeacon3D) != beacon:
		failures.append("撤离信标未登记进条件撤离表")


func _verify_spawn_and_search(tower: TowerDescent3D, failures: Array[String]) -> void:
	# 刷怪：进入第一间战斗房后必须出现敌人。
	var combat_id := ""
	for room_id in MAIN_ROOM_IDS:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		if combat_id.is_empty() and room.room_type == "COMBAT":
			combat_id = room_id
	if combat_id.is_empty():
		failures.append("远征关卡没有战斗房，无法验证刷怪")
	else:
		var combat_room := tower._room_by_id.get(combat_id) as DungeonRoom3D
		combat_room.cleared = false
		tower._current_room_id = ""
		tower._on_room_entered(combat_room)
		if int(tower._alive_by_room.get(combat_id, 0)) <= 0:
			failures.append("进入战斗房 %s 后没有生成敌人" % combat_id)
		var enemies := tower.find_children("*", "Enemy3D", true, false)
		if enemies.is_empty():
			failures.append("远征关卡场景树里没有 Enemy3D 节点")
	# 搜索：可搜索房必须存在，且全场搜索容器全部接入搜索回调。
	# 房间细节按需构建，验收前先显式 ensure_detail_built()。
	var search_room_id := ""
	var searchable_total := 0
	var wired_searchable := 0
	for room_id in MAIN_ROOM_IDS:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		room.ensure_detail_built()
		if search_room_id.is_empty() and room.room_type in ["SCAVENGE", "STORAGE"]:
			search_room_id = room_id
		for node in room.find_children("*", "RoomFurniture3D", true, false):
			var prop := node as RoomFurniture3D
			if prop == null or not prop.searchable:
				continue
			searchable_total += 1
			if prop.searched.get_connections().size() > 0:
				wired_searchable += 1
	if search_room_id.is_empty():
		failures.append("远征关卡没有可搜索房，无法满足搜索玩法")
	if searchable_total <= 0:
		failures.append("远征关卡全场没有可搜索容器")
	elif wired_searchable != searchable_total:
		failures.append("可搜索容器未全部接入搜索回调：%d/%d" % [wired_searchable, searchable_total])


func _verify_fate_on_door(tower: TowerDescent3D, failures: Array[String]) -> void:
	# 过门命运卡：清空 01 号房、给足钥匙后开门，必须弹出命运卡三选一。
	var from_room := tower._room_by_id.get("room_01") as DungeonRoom3D
	if from_room == null:
		failures.append("命运卡检查缺少 01 号房")
		return
	from_room.cleared = true
	tower._room_key_count = maxi(tower._room_key_count, 3)
	tower._current_room_id = "room_01"
	if not tower._try_open_room_door("room_02"):
		failures.append("01→02 门未开启（命运卡无法触发）：%s" % tower.status_label.text)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not tower._door_fate_active:
		failures.append("过门后没有进入命运卡选择")
	else:
		if tower._door_fate_choices.size() != 3:
			failures.append("命运卡不是三选一：%d" % tower._door_fate_choices.size())
		if tower.get_node_or_null("HUD/DoorFateOverlay3D") == null:
			failures.append("命运卡选择界面未构建")
		tower._cancel_door_fate_selection()
		await get_tree().process_frame


# —— 4) 默认塔楼回归 ——

func _verify_default_tower(failures: Array[String]) -> void:
	var packed := load(TOWER_SCENE) as PackedScene
	if packed == null:
		failures.append("TowerDescent3D.tscn 加载失败")
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame

	if tower.is_expedition():
		failures.append("默认塔楼被意外标记为远征关卡")
	if not tower.get_expedition_run_id().is_empty():
		failures.append("默认塔楼不应携带远征关卡标识")
	# 同一份脚本服务两种关卡：远征覆写不能反向污染塔楼的 HUD 口径。
	var tower_area_text := str(tower.call("_hud_floor_label_text"))
	if not tower_area_text.begins_with("高塔外层"):
		failures.append("默认塔楼地图区域标签被改成非塔楼口径：%s" % tower_area_text)
	var blocks := tower.get_node_or_null("Blocks") as Node3D
	if blocks == null:
		failures.append("默认塔楼缺少 Blocks 根节点")
	else:
		var names: Array[String] = []
		for child in blocks.get_children():
			names.append(str(child.name))
		var expected: Array[String] = ["Rooftop", "Base", "Battle", "Stairs"]
		if names != expected:
			failures.append("默认塔楼区块被改写：%s（期望 %s）" % [names, expected])
		if blocks.get_node_or_null("Expedition") != null:
			failures.append("默认塔楼不应出现 Expedition 区块")
	if not tower._room_by_id.has("start"):
		failures.append("默认塔楼缺少 100F 天台(start)")
	if not tower._room_by_id.has("facility"):
		failures.append("默认塔楼缺少 99F 基地(facility)")
	if not tower._floor_plan_snapshots.has(6):
		failures.append("默认塔楼缺少 94F 规划（默认规划范围已变）")
	if not tower._floor_plan_snapshots.has(15):
		failures.append("默认塔楼缺少 85F 规划（默认规划范围已变）")

	# 存档路由：远征关卡快照必须回到远征场景；空 map id 的旧塔楼快照不得被路由。
	var resume_scene := tower.get_runtime_resume_scene_path(_expedition_snapshot)
	if resume_scene != EXPEDITION_SCENE:
		failures.append("主塔未把 expedition_01 战局快照路由回远征关卡：%s" % resume_scene)
	var tower_snapshot := _expedition_snapshot.duplicate(true)
	tower_snapshot["runtime_map_id"] = ""
	if not tower.get_runtime_resume_scene_path(tower_snapshot).is_empty():
		failures.append("旧塔楼战局快照被错误路由到远征关卡")

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# —— 5) 退出战局离场契约 ——

func _verify_expedition_exit_contract(failures: Array[String]) -> void:
	var packed := load(EXPEDITION_SCENE) as PackedScene
	if packed == null:
		failures.append("退出契约检查无法加载 ExpeditionLevel01_3D.tscn")
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		failures.append("退出契约检查缺少 start 安全房")
		tower.queue_free()
		return
	var exit_door: RoomDoor3D = null
	for side_value in start_room.door_targets.keys():
		if str(start_room.door_targets[side_value]).is_empty():
			exit_door = start_room.get_door_node(str(side_value)) as RoomDoor3D
			break
	if exit_door == null:
		failures.append("退出契约检查找不到无目标抵达侧门")
		tower.queue_free()
		return
	tower.player.global_position = exit_door.global_position + Vector3(0.0, 0.05, 0.0)
	await get_tree().physics_frame
	var candidate := tower.get_interaction_candidate(tower.player)
	if str(candidate.get("mode", "")) != "configured_expedition_retreat":
		failures.append("退出战局门未产生 expedition_retreat 交互候选：%s" % candidate)
	if not tower.perform_interaction(tower.player, candidate):
		failures.append("退出战局门按 E 未打开确认")
		tower.queue_free()
		return
	await get_tree().process_frame
	var overlay := tower.get_node_or_null("HUD/ExpeditionExitWarning") as Control
	if overlay == null:
		failures.append("退出战局未打开专属确认弹窗")
		tower.queue_free()
		return
	if tower.get_node_or_null("HUD/InitialLoopRetreatWarning") != null:
		failures.append("远征关卡退出误用了塔楼反向撤退弹窗")
	var rooms_before := tower._room_by_id.size()
	if tower._inventory != null:
		tower._inventory.add_item({"id": "verify_expedition_loot", "name": "验收物资", "count": 1})
	var confirm := _find_button(overlay, "确认退出")
	if confirm == null:
		failures.append("远征退出弹窗缺少确认按钮")
	else:
		confirm.pressed.emit()
		await get_tree().process_frame
	if not tower._completed:
		failures.append("确认退出后远征行动未标记结束")
	if str(tower.return_scene_path) != GameDesignConfig.MAIN_SCENE:
		failures.append("远征退出落点不是塔楼 99F 基地：%s" % tower.return_scene_path)
	if tower._room_by_id.size() != rooms_before:
		failures.append("确认退出后房间表被重建：%d -> %d，应为离场而非场景内复位" % [
			rooms_before, tower._room_by_id.size(),
		])
	if not tower._room_by_id.has("start"):
		failures.append("确认退出后 start 安全屋消失")
	if tower._room_by_id.has("floor_01_entry"):
		failures.append("确认退出后出现塔楼 98F 房间 floor_01_entry")
	if tower._room_by_id.has("facility"):
		failures.append("确认退出后出现不应存在的 99F 基地房")
	if tower._inventory != null and tower._inventory.get_occupied_slots().size() != 0:
		failures.append("确认退出后背包未被清空")
	var weapons_after := 0
	for slot_index in range(2):
		if not tower.player.get_equipped_weapon_item_for_slot(slot_index).is_empty():
			weapons_after += 1
	if weapons_after != 0:
		failures.append("确认退出后装备武器未被清空：%d 把" % weapons_after)
	var pending := GameEntryFlow.peek_pending_entry()
	if str(pending.get("reason", "")) != GameEntryFlow.REASON_ABORT_RETURN_99F:
		failures.append("确认退出未登记返回基地契约：%s" % pending)
	if str(pending.get("spawn_target", "")) != GameEntryFlow.SPAWN_BASE_99F:
		failures.append("确认退出的返回契约不是 99F 基地出生：%s" % pending)
	if int(pending.get("request_id", -1)) > 0:
		GameEntryFlow.cancel_request(int(pending["request_id"]))
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# —— 工具 ——

func _script_constants(node: Node) -> Dictionary:
	var script := node.get_script() as Script
	if script == null:
		return {}
	return script.get_script_constant_map()


## 读 `res://` 文本资源（远征关卡场景的「不继承塔楼」是文件级契约，
## 只有读原文才能在没有加载塔楼场景的前提下断言）。
func _read_text(res_path: String) -> String:
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _find_button(root: Node, text_fragment: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.text.contains(text_fragment):
			return button
	return null


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"EXPEDITION_LEVEL01_FLOW_OK: "
			+ "catalog->menu->loading->expedition, single layer, Blocks/Expedition only "
			+ "(scene is structurally independent of TowerDescent3D.tscn), "
			+ "15x15 v007 safe room with 2 perpendicular doors, room_01..05 25x25 + extraction 25x25, "
			+ "enemy spawn, searchable containers, door fate 3-choice, free entry gate, "
			+ "STANDARD extraction beacon, abort-return-to-base contract, default tower unchanged"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
