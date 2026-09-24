## 探针：远征01 通道桥房「多层几何」（下沉坑 + 跨桥）消费验证。
##
## 为什么需要它：多层几何是**区块组合器装不下的一层**（`build_block()` 的输入契约是
## 「轴对齐矩形 + 四面墙 + 门位 + 单水平面」），所以走 `FloorPlanGenerator` 的第 6 环
## 独立通路，且它**不参与 lane 归属模型**（不占 lane、不进 wall_lanes）——
## 也就是说「区块级探针」天生看不到它。没有本探针，这层几何写错了整层照样绿。
##
## 断言分两段：
##   A. **纯规划级**（`_bridge_multi_level_plan()`）：坑/桥矩形、深度、三层件数、
##      格线对齐、墙底标高、纵向拉伸比、桥口开洞、朝向合法性、确定性、非桥房返回空。
##   B. **真实生成路径**（`_generate_constrained_floor()` → 房记录）：平台砖真扣了坑区、
##      多层件真进了 `authored_layout_instances`、每个 component_id 都能在运行时注册表里
##      解析成 prefab（ID 写错会在这里炸，而不是等到进游戏才炸）。
##
## 「坑区一律保留承重、玩家无跳跃」是本环的设计前提（见 `FloorPlanGenerator` 第 6 环
## 头注释），因此承重归 `TowerFloorStage3D._build_support()` 不动 —— 本探针不测承重。
extends Node

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
const ROOM := preload("res://src/world3d/DungeonRoom3D.gd")

const LEVEL := "expedition_01"
const BRIDGE_TEMPLATE := "bridge_60x50"
## 通道桥房尺寸（模板 `size_m`）。12×10 = 120 格。
const BRIDGE_SIZE := Vector2(60.0, 50.0)
const GRID := 5.0
## 期望值（全部由模板 `sunken_pit` / `bridge_span` 推出，改数据必须同步改这里）。
const EXPECTED_PIT := Rect2(-15.0, -10.0, 30.0, 20.0)
const EXPECTED_BRIDGE := Rect2(-15.0, -5.0, 30.0, 5.0)
const EXPECTED_DEPTH := 12.0
const EXPECTED_PIT_WALLS := 30
const EXPECTED_PIT_TILES := 24
## 坑区格 6×4 = 24，其中桥面那条 6 格保留原砖 ⇒ 上层地砖比满铺少 18 块。
const EXPECTED_PLATFORM_TILES_DROPPED := 18
## 一件标准墙 11.9m 拉到「坑深 12m + 地面护栏 0.8m」。
const EXPECTED_WALL_SCALE_Y := 12.8 / 11.9
const EPS := 0.01

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
	print("---- 远征01 通道桥多层几何 探针 ----")
	var templates := LOADER.load_room_templates(LEVEL)
	if templates.is_empty():
		print("PROBE_FAIL: room_templates 加载失败")
		get_tree().quit(1)
		return
	if not templates.has(BRIDGE_TEMPLATE):
		print("PROBE_FAIL: 缺模板 %s" % BRIDGE_TEMPLATE)
		get_tree().quit(1)
		return

	_check_plan(templates)
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


## —— A. 纯规划级 ——
func _check_plan(templates: Dictionary) -> void:
	var room := {
		"key": "room_05",
		"template_id": BRIDGE_TEMPLATE,
		"size": BRIDGE_SIZE,
		"center": Vector2.ZERO,
	}
	var plan := GENERATOR._bridge_multi_level_plan(room, templates)
	_check(not plan.is_empty(), "① 通道桥房应产出多层几何规划")
	if plan.is_empty():
		return

	var pit := plan.get("pit_rect", Rect2()) as Rect2
	_check(
		pit.position.is_equal_approx(EXPECTED_PIT.position)
		and pit.size.is_equal_approx(EXPECTED_PIT.size),
		"② 坑矩形应为 x∈[-15,15]、z∈[-10,10]（30×20），实得 %s" % str(pit)
	)
	var span := plan.get("bridge_rect", Rect2()) as Rect2
	_check(
		span.position.is_equal_approx(EXPECTED_BRIDGE.position)
		and span.size.is_equal_approx(EXPECTED_BRIDGE.size),
		"③ 桥矩形应为 x∈[-15,15]、z∈[-5,0]（30×5），实得 %s" % str(span)
	)
	_check(
		_approx(float(plan.get("depth_m", 0.0)), EXPECTED_DEPTH),
		"④ 坑深应为 12m（一整层层高），实得 %s" % str(plan.get("depth_m", 0.0))
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
					# 沿 x 铺：常量轴是 z（坑南北壁 z=∓10 或桥侧壁 z=0/−5），沿墙坐标是 x。
					if not (_approx(local.z, -10.0) or _approx(local.z, 10.0) or _approx(local.z, 0.0) or _approx(local.z, -5.0)):
						wall_axis_ok = false
					if not _on_lane_lattice(local.x):
						wall_lattice_ok = false
				else:
					# 沿 z 铺：常量轴是 x（坑东西壁 x=∓15），沿墙坐标是 z。
					if not (_approx(local.x, -15.0) or _approx(local.x, 15.0)):
						wall_axis_ok = false
					if not _on_lane_lattice(local.z):
						wall_lattice_ok = false
					# 桥口：东西壁在桥跨 z∈(−5, 0) 那一段必须留口，否则玩家从平台走不到桥上。
					if local.z > -EXPECTED_BRIDGE.size.y and local.z < 0.0:
						bridge_mouth_open = false
			GENERATOR.MULTI_LEVEL_PART_PIT_FLOOR_TILE:
				tile_count += 1
				if not _approx(local.y, -EXPECTED_DEPTH):
					tile_y_ok = false
				if not (_on_lane_lattice(local.x) and _on_lane_lattice(local.z)):
					tile_lattice_ok = false
			_:
				part_ok = false

	_check(role_ok, "⑤ 多层件 slot_role 必须一律 %s" % GENERATOR.MULTI_LEVEL_SLOT_ROLE)
	_check(part_ok, "⑥ 多层件 part 只能是 pit_wall / pit_floor_tile")
	_check(
		wall_count == EXPECTED_PIT_WALLS,
		"⑦ 坑壁+护栏应为 %d 件，实得 %d" % [EXPECTED_PIT_WALLS, wall_count]
	)
	_check(
		tile_count == EXPECTED_PIT_TILES,
		"⑧ 坑底砖应为 %d 块（30×20 满铺），实得 %d" % [EXPECTED_PIT_TILES, tile_count]
	)
	_check(wall_y_ok, "⑨ 坑壁墙底应落在坑底标高 −12m")
	_check(wall_scale_ok, "⑩ 坑壁应纵向拉伸到 12.8/11.9（坑深 12 + 地面护栏 0.8）")
	_check(wall_lattice_ok, "⑪ 坑壁沿墙坐标必须落在 5m 格心")
	_check(tile_lattice_ok, "⑫ 坑底砖中心必须落在 5m 格心")
	_check(wall_axis_ok, "⑬ 坑壁常量轴必须是坑边界（x=∓15 / z=∓10）或桥侧壁（z=0 / −5）")
	_check(wall_face_ok, "⑭ 坑壁朝向必须是四正交墙向之一")
	_check(bridge_mouth_open, "⑮ 坑东西壁在桥跨那一段必须留口（否则上不了桥）")
	_check(
		wall_faces.size() == 4,
		"⑯ 坑壁四侧朝向都要用到（实得 %s）" % str(wall_faces.keys())
	)

	# ⑰ 非通道桥模板不得产出多层几何（否则「整层多出一圈坑」会静默发生）。
	var plain := {
		"key": "branch_04",
		"template_id": "std_25x25",
		"size": Vector2(25.0, 25.0),
		"center": Vector2.ZERO,
	}
	_check(
		GENERATOR._bridge_multi_level_plan(plain, templates).is_empty(),
		"⑰ 非通道桥房型不得产出多层几何"
	)

	# ⑱ 确定性：同输入两次规划结果逐字段一致（探针与运行时必须同源可复现）。
	var second := GENERATOR._bridge_multi_level_plan(room, templates)
	_check(
		str(second.get("pit_rect", Rect2())) == str(pit)
		and (second.get("instances", []) as Array).size() == instances.size()
		and str(second.get("instances", [])) == str(instances),
		"⑱ 同输入两次规划结果必须完全一致"
	)


## —— B. 真实生成路径（房记录级）——
func _check_runtime_path(templates: Dictionary) -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	if level_plan.is_empty():
		_check(false, "⑲ level_plan 加载失败")
		return
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	var bridge_rooms := 0
	var catalog_ok := true
	# 多个种子扫一遍：通道桥房是按种子从内容池抽的，单次抽样可能一次都不出现。
	for index in range(12):
		var run_seed := 700000 + index * 7919
		var generated := GENERATOR._generate_constrained_floor(
			LEVEL, 0, run_seed, normalized, policy, templates
		)
		if generated.is_empty():
			_check(false, "⑲ seed %d 生成为空" % run_seed)
			continue
		var errors := VALIDATOR.validate_normalized(LEVEL, 0, generated, policy, templates)
		if not errors.is_empty():
			_check(false, "⑳ seed %d 校验失败 %s" % [run_seed, str(errors)])
			continue
		for value in generated.get("rooms", []) as Array:
			var room_record := value as Dictionary
			if str(room_record.get("template_id", "")) != BRIDGE_TEMPLATE:
				continue
			bridge_rooms += 1
			var room_key := str(room_record.get("key", ""))
			var instances := room_record.get("authored_layout_instances", []) as Array
			var size := room_record.get("size", Vector2.ZERO) as Vector2
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
				"㉑ seed %d %s: 通道桥房必须标记 authored_layout_multi_level_room" % [run_seed, room_key]
			)
			_check(
				tile_count == full_tiles - EXPECTED_PLATFORM_TILES_DROPPED,
				(
					"㉒ seed %d %s: 上层地砖应为满铺 %d − 坑区 %d = %d，实得 %d"
					% [
						run_seed, room_key, full_tiles, EXPECTED_PLATFORM_TILES_DROPPED,
						full_tiles - EXPECTED_PLATFORM_TILES_DROPPED, tile_count,
					]
				)
			)
			_check(
				multi_count == EXPECTED_PIT_WALLS + EXPECTED_PIT_TILES,
				"㉓ seed %d %s: 多层件应为 %d 件，实得 %d"
				% [
					run_seed, room_key, EXPECTED_PIT_WALLS + EXPECTED_PIT_TILES, multi_count,
				]
			)
	_check(
		bridge_rooms > 0,
		"㉔ 12 个种子里至少应出现一间通道桥房（否则本探针什么也没测到）"
	)
	_check(catalog_ok, "㉕ 多层件的 component_id 必须都能在运行时注册表解析成 prefab")
