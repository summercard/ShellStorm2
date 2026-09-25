## 探针：远征01 通道桥房「多层几何」（下沉坑 + 跨桥）消费验证。
##
## 为什么需要它：多层几何是**区块组合器装不下的一层**（`build_block()` 的输入契约是
## 「轴对齐矩形 + 四面墙 + 门位 + 单水平面」），所以走 `FloorPlanGenerator` 的第 6 环
## 独立通路，且它**不参与 lane 归属模型**（不占 lane、不进 wall_lanes）——
## 也就是说「区块级探针」天生看不到它。没有本探针，这层几何写错了整层照样绿。
##
## ⚠ **两种取向都必须测**：桥房只有**一张模板** `bridge_60x50`，取向是同一张模板的两种旋转 ——
## `0°` 本体（桥沿 x 跨）／`90°` 转置（桥沿 z 跨，占位 50×60）。
## 生成器按连接方向自动选姿态，实测 324 种子 391 个桥房实例里 235 个是转置姿态
## ⇒ 只测本体等于漏掉 60% 的实例。
## 历史缺陷（本探针扩到两取向时抓出）：坑壁开口与桥侧护栏曾按「桥沿 x 跨」写死 ——
## 转置姿态下南北壁不留口（玩家上不了桥）、东西壁被整片删掉、护栏横在桥两端堵死桥。
##
## 断言分两段：
##   A. **纯规划级**（`_bridge_multi_level_plan()`，两种取向各跑一遍）：坑/桥矩形、深度、
##      三层件数、格线对齐、墙底标高、纵向拉伸比、桥口开在**桥实际贴到的那两条坑沿**上、
##      护栏沿**桥长轴**排、朝向合法性、确定性、非桥房返回空。
##   B. **真实生成路径**（`_generate_constrained_floor()` → 房记录）：平台砖真扣了坑区、
##      多层件真进了 `authored_layout_instances`、每个 component_id 都能在运行时注册表里
##      解析成 prefab（ID 写错会在这里炸，而不是等到进游戏才炸）、两种取向都真出现过。
##
## 「坑区一律保留承重、玩家无跳跃」是本环的设计前提（见 `FloorPlanGenerator` 第 6 环
## 头注释），因此承重归 `TowerFloorStage3D._build_support()` 不动 —— 本探针不测承重。
extends Node

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
const ROOM := preload("res://src/world3d/DungeonRoom3D.gd")

const LEVEL := "expedition_01"
## 桥房唯一的模板 id。两种取向**不是**两个 id，而是同一张模板的两种旋转
## （业主裁定 2026-09-25「不要两批代号」，见 05.2 §3.4/§3.6）。
const BRIDGE_TEMPLATE := "bridge_60x50"
## 取向：0° ＝ 本体（桥沿 x 跨）／90° ＝ 转置（桥沿 z 跨）。
const BRIDGE_ROTATION_NATIVE := 0
const BRIDGE_ROTATION_POSE := 90
const GRID := 5.0
## 本体 60×50：坑 30×20 于 x∈[-15,15] z∈[-10,10]；桥 30×5 于 x∈[-15,15] z∈[-5,0]。
const NATIVE_SIZE := Vector2(60.0, 50.0)
const NATIVE_PIT := Rect2(-15.0, -10.0, 30.0, 20.0)
const NATIVE_BRIDGE := Rect2(-15.0, -5.0, 30.0, 5.0)
## 转置姿态 50×60：坑 20×30 于 x∈[-10,10] z∈[-15,15]；桥 5×30 于 x∈[-5,0] z∈[-15,15]。
const POSE_SIZE := Vector2(50.0, 60.0)
const POSE_PIT := Rect2(-10.0, -15.0, 20.0, 30.0)
const POSE_BRIDGE := Rect2(-5.0, -15.0, 5.0, 30.0)
## 深度由模板 `sunken_pit.depth_m` 推出（两取向同）。
const EXPECTED_DEPTH := 12.0
## 坑壁 + 护栏件数（**两种取向同数**：坑周长 100m 同、桥长 30m 同）：
## ① 坑壁 18 件（四周铺满，其中 2 格让给桥口）＋ ② 桥侧护栏 12 件（沿桥长轴 6 格 × 2 面）。
const EXPECTED_PIT_WALLS := 30
## 坑底地砖：两取向的坑都是 6×4 = 24 格。
const EXPECTED_PIT_TILES := 24
## 坑区 24 格里有桥面那条 6 格保留原砖 ⇒ 上层地砖比满铺少 18 块（两取向同）。
const EXPECTED_PLATFORM_TILES_DROPPED := 18
## 一件标准墙 11.9m 拉到「坑深 12m + 地面护栏 0.8m」。
const EXPECTED_WALL_SCALE_Y := 12.8 / 11.9
const EPS := 0.01
## 真实生成路径的种子数：桥房按种子从内容池抽，「两种取向都真出现过」需要足够样本。
const RUNTIME_SEEDS := 24

var failures: Array[String] = []
var checks := 0


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _approx(a: float, b: float, tol := EPS) -> bool:
	return absf(a - b) <= tol


## 沿墙坐标必须落在 5m 格心（全局 `5k + 2.5`）。
func _on_lane_lattice(value: float) -> bool:
	return absf(fposmod(value - 2.5, GRID)) <= EPS


func _ready() -> void:
	print("---- 远征01 通道桥多层几何 探针（本体 0° + 转置 90°）----")
	var templates := LOADER.load_room_templates(LEVEL)
	if templates.is_empty():
		print("PROBE_FAIL: room_templates 加载失败")
		get_tree().quit(1)
		return
	if not templates.has(BRIDGE_TEMPLATE):
		print("PROBE_FAIL: 缺模板 %s" % BRIDGE_TEMPLATE)
		get_tree().quit(1)
		return
	# 反向断言：转置姿态**不允许**是另一个模板 —— 存在即说明有人又建了一族代号。
	if templates.has("bridge_50x60"):
		print("PROBE_FAIL: 模板目录里出现了 bridge_50x60 —— 转置姿态必须用旋转表达，不得另建 id")
		get_tree().quit(1)
		return

	_check_plan(templates, NATIVE_SIZE, "本体0°", NATIVE_PIT, NATIVE_BRIDGE)
	_check_plan(templates, POSE_SIZE, "转置90°", POSE_PIT, POSE_BRIDGE)
	_check_non_bridge(templates)
	_check_runtime_path(templates)

	print("checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("BRIDGE_MULTI_LEVEL_OK checks=%d" % checks)
		get_tree().quit(0)
		return
	for failure in failures:
		print("FAIL  %s" % failure)
	print("PROBE_FAIL")
	get_tree().quit(1)


## 桥口开在哪两条坑沿上：由「桥矩形哪两条边与坑沿贴合」解出，不写死轴向。
## 返回 `{"zs": [沿 x 走向的开口坑沿（z 常量）], "xs": [沿 z 走向的开口坑沿（x 常量）]}`。
func _open_edges(pit: Rect2, bridge: Rect2) -> Dictionary:
	var zs: Array[float] = []
	var xs: Array[float] = []
	if _approx(bridge.position.y, pit.position.y):
		zs.append(pit.position.y)
	if _approx(bridge.position.y + bridge.size.y, pit.position.y + pit.size.y):
		zs.append(pit.position.y + pit.size.y)
	if _approx(bridge.position.x, pit.position.x):
		xs.append(pit.position.x)
	if _approx(bridge.position.x + bridge.size.x, pit.position.x + pit.size.x):
		xs.append(pit.position.x + pit.size.x)
	return {"zs": zs, "xs": xs}


## —— A. 纯规划级（一种取向跑一遍）——
##
## `label` 是取向标签（"本体0°/转置90°"）；函数体沿用局部名 `template_id` 书写文案，
## 两种取向共用同一张模板，只有 `size` 与 `rotation_deg` 不同。
func _check_plan(
	templates: Dictionary,
	room_size: Vector2,
	label: String,
	expected_pit: Rect2,
	expected_bridge: Rect2
) -> void:
	var template_id := label
	var room := {
		"key": "bridge_%s" % label,
		"template_id": BRIDGE_TEMPLATE,
		"size": room_size,
		"center": Vector2.ZERO,
		"rotation_deg": float(
			BRIDGE_ROTATION_POSE if room_size.x < room_size.y else BRIDGE_ROTATION_NATIVE
		),
	}
	var plan := GENERATOR._bridge_multi_level_plan(room, templates)
	_check(not plan.is_empty(), "① %s：桥房应产出多层几何规划" % template_id)
	if plan.is_empty():
		return

	var pit := plan.get("pit_rect", Rect2()) as Rect2
	_check(
		pit.position.is_equal_approx(expected_pit.position)
		and pit.size.is_equal_approx(expected_pit.size),
		"② %s：坑矩形应为 %s，实得 %s" % [template_id, str(expected_pit), str(pit)]
	)
	var span := plan.get("bridge_rect", Rect2()) as Rect2
	_check(
		span.position.is_equal_approx(expected_bridge.position)
		and span.size.is_equal_approx(expected_bridge.size),
		"③ %s：桥矩形应为 %s，实得 %s" % [template_id, str(expected_bridge), str(span)]
	)
	_check(
		_approx(float(plan.get("depth_m", 0.0)), EXPECTED_DEPTH),
		"④ %s：坑深应为 12m（一整层层高），实得 %s"
		% [template_id, str(plan.get("depth_m", 0.0))]
	)

	var instances := plan.get("instances", []) as Array
	var wall_count := 0
	var tile_count := 0
	var role_ok := true
	var part_ok := true
	var wall_y_ok := true
	var wall_scale_ok := true
	var wall_lattice_ok := true
	var wall_face_ok := true
	var wall_axis_ok := true
	var tile_y_ok := true
	var tile_lattice_ok := true
	var bridge_mouth_open := true
	# 坑壁四侧都必须有件（朝向集合 = 四个方向都用上）。
	var wall_faces: Dictionary = {}
	# 开口坑沿（桥实际贴到的那两条）：这两条坑沿上、桥跨区间内的格必须**没有**坑壁件。
	var open_z := (_open_edges(expected_pit, expected_bridge)["zs"] as Array)
	var open_x := (_open_edges(expected_pit, expected_bridge)["xs"] as Array)
	# 坑沿与桥长边的常量轴取值集合（坑壁只许坐在这些位置上）。
	var axis_z := [expected_pit.position.y, expected_pit.position.y + expected_pit.size.y,
		expected_bridge.position.y, expected_bridge.position.y + expected_bridge.size.y]
	var axis_x := [expected_pit.position.x, expected_pit.position.x + expected_pit.size.x,
		expected_bridge.position.x, expected_bridge.position.x + expected_bridge.size.x]
	for value in instances:
		var instance := value as Dictionary
		if str(instance.get("slot_role", "")) != GENERATOR.MULTI_LEVEL_SLOT_ROLE:
			role_ok = false
		var part := str(instance.get("part", ""))
		var local := instance.get("position", Vector3.ZERO) as Vector3
		var rotation := float(instance.get("rotation_y_deg", 0.0))
		match part:
			GENERATOR.MULTI_LEVEL_PART_PIT_WALL:
				wall_count += 1
				wall_faces[rotation] = int(wall_faces.get(rotation, 0)) + 1
				if not _approx(local.y, -EXPECTED_DEPTH):
					wall_y_ok = false
				if not _approx(float(instance.get("scale_y", 0.0)), EXPECTED_WALL_SCALE_Y):
					wall_scale_ok = false
				# 朝向只能是四个正交墙向之一（0/180 = 沿 x 铺；±90 = 沿 z 铺）。
				if not (
					_approx(rotation, 0.0)
					or _approx(rotation, 180.0)
					or _approx(rotation, 90.0)
					or _approx(rotation, -90.0)
				):
					wall_face_ok = false
				var along_x := _approx(rotation, 0.0) or _approx(rotation, 180.0)
				if along_x:
					# 沿 x 铺：常量轴是 z（坑南/北壁 或 桥长边），沿墙坐标是 x。
					if not _in_list(local.z, axis_z):
						wall_axis_ok = false
					if not _on_lane_lattice(local.x):
						wall_lattice_ok = false
					# 桥口：开口坑沿上、桥跨 x 区间内不许有坑壁件。
					if _in_list(local.z, open_z) and _inside(local.x, expected_bridge.position.x, expected_bridge.position.x + expected_bridge.size.x):
						bridge_mouth_open = false
				else:
					# 沿 z 铺：常量轴是 x（坑东/西壁 或 桥长边），沿墙坐标是 z。
					if not _in_list(local.x, axis_x):
						wall_axis_ok = false
					if not _on_lane_lattice(local.z):
						wall_lattice_ok = false
					if _in_list(local.x, open_x) and _inside(local.z, expected_bridge.position.y, expected_bridge.position.y + expected_bridge.size.y):
						bridge_mouth_open = false
			GENERATOR.MULTI_LEVEL_PART_PIT_FLOOR_TILE:
				tile_count += 1
				if not _approx(local.y, -EXPECTED_DEPTH):
					tile_y_ok = false
				if not (_on_lane_lattice(local.x) and _on_lane_lattice(local.z)):
					tile_lattice_ok = false
			_:
				part_ok = false

	_check(role_ok, "⑤ %s：多层件 slot_role 必须一律 %s" % [template_id, GENERATOR.MULTI_LEVEL_SLOT_ROLE])
	_check(part_ok, "⑥ %s：多层件 part 只能是 pit_wall / pit_floor_tile" % template_id)
	_check(
		wall_count == EXPECTED_PIT_WALLS,
		"⑦ %s：坑壁+护栏应为 %d 件，实得 %d" % [template_id, EXPECTED_PIT_WALLS, wall_count]
	)
	_check(
		tile_count == EXPECTED_PIT_TILES,
		"⑧ %s：坑底砖应为 %d 块（满铺），实得 %d" % [template_id, EXPECTED_PIT_TILES, tile_count]
	)
	_check(wall_y_ok, "⑨ %s：坑壁墙底应落在坑底标高 −12m" % template_id)
	_check(wall_scale_ok, "⑩ %s：坑壁应纵向拉伸到 12.8/11.9（坑深 12 + 地面护栏 0.8）" % template_id)
	_check(wall_lattice_ok, "⑪ %s：坑壁沿墙坐标必须落在 5m 格心" % template_id)
	_check(tile_lattice_ok, "⑫ %s：坑底砖中心必须落在 5m 格心" % template_id)
	_check(
		wall_axis_ok,
		"⑬ %s：坑壁常量轴必须是坑沿（%s / %s）或桥长边" % [template_id, str(axis_x), str(axis_z)]
	)
	_check(wall_face_ok, "⑭ %s：坑壁朝向必须是四正交墙向之一" % template_id)
	_check(
		bridge_mouth_open,
		"⑮ %s：开口坑沿（z=%s / x=%s）在桥跨那一段必须留口（否则上不了桥）"
		% [template_id, str(open_z), str(open_x)]
	)
	_check(
		wall_faces.size() == 4,
		"⑯ %s：坑壁四侧朝向都要用到（实得 %s）" % [template_id, str(wall_faces.keys())]
	)
	# ⑰ 桥侧护栏必须沿**桥的长轴**排：本体沿 x（常量轴 z = 桥两长边），转置姿态沿 z（常量轴 x = 桥两长边）。
	var rail_axis_ok := true
	for value in instances:
		var instance := value as Dictionary
		if str(instance.get("name", "")).begins_with("PIT_BRIDGE_"):
			var local := instance.get("position", Vector3.ZERO) as Vector3
			if expected_bridge.size.x >= expected_bridge.size.y:
				if not (
					_approx(local.z, expected_bridge.position.y)
					or _approx(local.z, expected_bridge.position.y + expected_bridge.size.y)
				):
					rail_axis_ok = false
			elif not (
				_approx(local.x, expected_bridge.position.x)
				or _approx(local.x, expected_bridge.position.x + expected_bridge.size.x)
			):
				rail_axis_ok = false
	_check(rail_axis_ok, "⑰ %s：桥侧护栏必须坐在桥的两条长边上（沿桥长轴排）" % template_id)

	# ⑱ 确定性：同输入两次规划结果逐字段一致（探针与运行时必须同源可复现）。
	var second := GENERATOR._bridge_multi_level_plan(room, templates)
	_check(
		str(second.get("pit_rect", Rect2())) == str(pit)
		and (second.get("instances", []) as Array).size() == instances.size()
		and str(second.get("instances", [])) == str(instances),
		"⑱ %s：同输入两次规划结果必须完全一致" % template_id
	)


## ⑲ 非通道桥模板不得产出多层几何（否则「整层多出一圈坑」会静默发生）。
func _check_non_bridge(templates: Dictionary) -> void:
	var plain := {
		"key": "branch_04",
		"template_id": "std_25x25",
		"size": Vector2(25.0, 25.0),
		"center": Vector2.ZERO,
	}
	_check(
		GENERATOR._bridge_multi_level_plan(plain, templates).is_empty(),
		"⑲ 非通道桥房型不得产出多层几何"
	)


## 严格落在开区间内（与生成器的桥口判据同口径：端点那一格不算）。
func _inside(value: float, low: float, high: float) -> bool:
	return value > low + EPS and value < high - EPS


func _in_list(value: float, values: Array) -> bool:
	for candidate in values:
		if _approx(value, float(candidate)):
			return true
	return false


## —— B. 真实生成路径（房记录级）——
func _check_runtime_path(templates: Dictionary) -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	if level_plan.is_empty():
		_check(false, "⑳ level_plan 加载失败")
		return
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	# 按**取向**计数（同一张模板，0° 本体 / 90° 转置）—— 「两个模板 id」的时代已结束。
	var rooms_by_pose := {BRIDGE_ROTATION_NATIVE: 0, BRIDGE_ROTATION_POSE: 0}
	var catalog_ok := true
	# 多个种子扫一遍：通道桥房是按种子从内容池抽的、姿态又按连接方向定，
	# 单次抽样可能一次都不出现（或只出现一种取向）。
	for index in range(RUNTIME_SEEDS):
		var run_seed := 700000 + index * 7919
		var generated := GENERATOR._generate_constrained_floor(
			LEVEL, 0, run_seed, normalized, policy, templates
		)
		if generated.is_empty():
			_check(false, "㉑ seed %d 生成为空" % run_seed)
			continue
		var errors := VALIDATOR.validate_normalized(LEVEL, 0, generated, policy, templates)
		if not errors.is_empty():
			_check(false, "㉒ seed %d 校验失败 %s" % [run_seed, str(errors)])
			continue
		for value in generated.get("rooms", []) as Array:
			var room_record := value as Dictionary
			if str(room_record.get("template_id", "")) != BRIDGE_TEMPLATE:
				continue
			var template_id := str(room_record.get("template_id", ""))
			var pose := int(round(float(room_record.get("rotation_deg", 0.0))))
			var room_label := "%s@%d°" % [template_id, pose]
			rooms_by_pose[pose] = int(rooms_by_pose.get(pose, 0)) + 1
			var room_key := str(room_record.get("key", ""))
			var instances := room_record.get("authored_layout_instances", []) as Array
			var size := room_record.get("size", Vector2.ZERO) as Vector2
			# 两取向的满铺格数同（12×10 / 10×12 = 120），坑区与桥面格数也同 ⇒ 扣数同。
			var full_tiles := int(round(size.x / GRID)) * int(round(size.y / GRID))
			var tile_count := 0
			var multi_count := 0
			for instance_value in instances:
				var instance := instance_value as Dictionary
				var role := str(instance.get("slot_role", ""))
				if role == "floor_tile":
					tile_count += 1
				elif role == GENERATOR.MULTI_LEVEL_SLOT_ROLE:
					multi_count += 1
					if ROOM._authored_component_prefab(str(instance.get("component_id", ""))) == null:
						catalog_ok = false
			_check(
				bool(room_record.get("authored_layout_multi_level_room", false)),
				"㉓ seed %d %s(%s)：通道桥房必须标记 authored_layout_multi_level_room"
				% [run_seed, room_key, room_label]
			)
			_check(
				tile_count == full_tiles - EXPECTED_PLATFORM_TILES_DROPPED,
				(
					"㉔ seed %d %s(%s)：上层地砖应为满铺 %d − 坑区 %d = %d，实得 %d"
					% [
						run_seed, room_key, room_label, full_tiles, EXPECTED_PLATFORM_TILES_DROPPED,
						full_tiles - EXPECTED_PLATFORM_TILES_DROPPED, tile_count,
					]
				)
			)
			_check(
				multi_count == EXPECTED_PIT_WALLS + EXPECTED_PIT_TILES,
				"㉕ seed %d %s(%s)：多层件应为 %d 件，实得 %d"
				% [
					run_seed, room_key, room_label,
					EXPECTED_PIT_WALLS + EXPECTED_PIT_TILES, multi_count,
				]
			)
	_check(
		int(rooms_by_pose[BRIDGE_ROTATION_NATIVE]) > 0,
		"㉖ %d 个种子里应出现桥房本体（0°）（否则只测到转置）" % RUNTIME_SEEDS
	)
	_check(
		int(rooms_by_pose[BRIDGE_ROTATION_POSE]) > 0,
		"㉗ %d 个种子里应出现桥房转置（90°）（否则只测到本体）" % RUNTIME_SEEDS
	)
	_check(catalog_ok, "㉘ 多层件的 component_id 必须都能在运行时注册表解析成 prefab")
