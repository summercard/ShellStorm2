class_name LevelPlanValidator
extends RefCounted
## L1/L2/L3 白盒设计源语义校验器（依据 docs/v0.1/05.2 §3.5 / §3.6 / §3.7）。
##
## 单一实现：命令行校验工具（tools/level_plan/verify_level_plan.gd）与
## 运行时数据驱动路径（FloorPlanGenerator.generate_from_level_plan）共用本类，
## 禁止各自复刻校验规则。
##
## 几何一律走 RoomDoorLane 唯一实现；面积预算走 FloorPlanGenerator。
## 校验只报错不修补 —— 发现不合法即逐条列出，由设计者回去改设计源。

const ROOM_DOOR_LANE := preload("res://src/map/RoomDoorLane.gd")
const AREA_BUDGET := preload("res://src/map/LevelAreaBudget.gd")
## 显式 preload 而非依赖 class_name 全局：新增脚本在 global_script_class_cache.cfg
## 刷新前用全局名会直接 parse error，headless 门禁会因此静默红掉。
const LOADER := preload("res://src/map/LevelPlanLoader.gd")

const EPS := 0.01
## 安全房/楼梯厅允许压核心筒与楼梯保留区（它们是核心筒的交通接口）。
const SAFE_ROLES := ["stair_entry", "stair_exit"]
## 房间级刷怪计划（enemy_spawn_plan）的合法性口径。
## 用 preload 而非 class_name 全局名：新脚本在全局类缓存刷新前用全局名会 parse error。
const MONSTER_INJECTOR := preload("res://src/map/MonsterInjector.gd")
const GAME_DESIGN_CONFIG := preload("res://src/framework/GameDesignConfig.gd")
## 首领名册：只用来查 `boss_content_id` 是否指向真实存在的内容，绝不复制名册表本身。
const BOSS_CONTENT_CATALOG := preload("res://src/enemy3d/BossContentCatalog.gd")
## 掉落池登记表：查 `reward_plan` 里的池引用是否已登记且 active。
## 只调 `has_pool / is_active / get_pool` —— 这三个不碰 ItemRegistry，静态校验可以独立跑。
const REWARD_POOLS := preload("res://src/rewards/RewardPoolRegistry.gd")
## 规格契约：trigger 列表与槽位写法取这里的唯一口径（禁止在本处复刻一份字面量）。
const REWARD_SPEC := preload("res://src/rewards/RewardSpec.gd")
## 关卡级地图×怪物掉落表：结构与 RewardSpec 编译共用同一实现，避免校验器复刻语义。
const MONSTER_DROP_TABLE := preload("res://src/rewards/MonsterDropTable.gd")
## 硬上限：设计源写超大数字不该变成性能事故或开局卡死，直接在静态校验拦住。
const SPAWN_PLAN_MAX_WAVES := 6
const SPAWN_PLAN_MAX_PER_WAVE := 24
const SPAWN_PLAN_MAX_TOTAL := 64

## 触发器刷怪：盒子资产库（id → 路径 + 解析 + 自检）。见 `docs/v0.1/design/触发器刷怪设计.md`。
const SPAWN_BOX_CATALOG := preload("res://src/map/SpawnBoxCatalog.gd")
## 调用层波次上限：与 SPAWN_PLAN_MAX_WAVES 同口径（一次遭遇不该超过 6 波）。
const SPAWN_BOX_MAX_STAGES := 6


## 校验整张关卡（L1 + 全部 L2 + 引用的全部 L3）。
## 返回：{ ok, errors, checks, floors, rooms, templates }
static func validate_level(level_id: String) -> Dictionary:
	var errors: Array[String] = []
	var checks := 0
	var room_total := 0
	var level_plan := LOADER.load_level_plan(level_id)
	if level_plan.is_empty():
		return {
			"ok": false,
			"errors": ["level_plan_missing_or_bad_schema:%s" % level_id],
			"checks": 0, "floors": 0, "rooms": 0, "templates": 0,
		}
	errors.append_array(_validate_level_header(level_plan))
	checks += 6
	var drop_table_value: Variant = level_plan.get("monster_drop_table", {})
	if not (drop_table_value is Dictionary):
		errors.append("monster_drop_table_not_object")
	else:
		var drop_table := drop_table_value as Dictionary
		if not drop_table.is_empty():
			var drop_check := MONSTER_DROP_TABLE.compile(level_id, drop_table)
			checks += int(drop_check.get("row_count", 0))
			for error_value in drop_check.get("errors", []):
				var error := error_value as Dictionary
				errors.append("%s:%s:%s" % [
					str(error.get("code", "MONSTER_DROP_TABLE_INVALID")),
					str(error.get("path", "")),
					str(error.get("detail", "")),
				])
	var templates := LOADER.load_room_templates(level_id)
	var declared: Array = level_plan.get("room_templates", [])
	for value in declared:
		var template_id := str(value)
		checks += 1
		if not templates.has(template_id):
			errors.append("template_missing:%s" % template_id)
	for template_id in templates:
		var template := templates[template_id] as Dictionary
		var template_errors := _validate_template(str(template_id), template)
		checks += 8
		errors.append_array(template_errors)
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var floor_rows := LOADER.list_floors(level_plan)
	var seen_index := {}
	for entry in floor_rows:
		var floor_index := int(entry.get("floor_index", -9999))
		checks += 1
		if seen_index.has(floor_index):
			errors.append("floor_index_duplicate:%d" % floor_index)
		seen_index[floor_index] = true
	for entry in floor_rows:
		var floor_number := int(entry.get("floor_number", 0))
		var floor_errors := validate_floor(level_id, floor_number, policy, templates)
		checks += 20
		errors.append_array(floor_errors)
		var normalized := LOADER.normalize_floor(level_id, floor_number)
		room_total += (normalized.get("rooms", []) as Array).size()
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"checks": checks,
		"floors": floor_rows.size(),
		"rooms": room_total,
		"templates": templates.size(),
	}


## 校验单层（自行从设计源读文件）。
static func validate_floor(
	level_id: String,
	floor_number: int,
	policy: Dictionary = {},
	templates: Dictionary = {}
) -> Array[String]:
	var normalized := LOADER.normalize_floor(level_id, floor_number)
	if normalized.is_empty():
		return ["floor_plan_missing:%s:%d" % [level_id, floor_number]]
	return validate_normalized(level_id, floor_number, normalized, policy, templates)


## 校验一份**已规范化**的层结构。
##
## 与 `validate_floor` 的区别只有取数方式：后者自己去读 L2 文件，本函数接受调用方
## 产出的结构。存在的理由是 `mode = "constrained"` 的关卡 —— 它的几何由生成器按
## 种子算出，L2 文件里存的那一份只是「样例 / 兜底」。此时静态门禁若只校验文件里的
## 样例，真正的运行时几何就完全没有闸；故生成器把产出交给本函数。
##
## 校验规则与 validate_floor 逐条一致（同一份实现，禁止分叉）。
static func validate_normalized(
	level_id: String,
	floor_number: int,
	normalized: Dictionary,
	policy: Dictionary = {},
	templates: Dictionary = {}
) -> Array[String]:
	var errors: Array[String] = []
	# normalize_floor（或生成器）的 schema 层错误是非类型化数组，逐条收进强类型结果。
	for schema_error in normalized.get("errors", []):
		errors.append(str(schema_error))
	var mode := str(normalized.get("mode", "authored"))
	if not mode in LOADER.VALID_MODES:
		errors.append("floor_mode_invalid:%s" % mode)
	var rooms := normalized.get("rooms", []) as Array
	if rooms.is_empty():
		errors.append("floor_has_no_rooms:%d" % floor_number)
		return errors
	var center_by_key := {}
	var size_by_key := {}
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		if center_by_key.has(key):
			errors.append("room_key_duplicate:%s" % key)
			continue
		center_by_key[key] = room.get("center", Vector2.ZERO) as Vector2
		size_by_key[key] = room.get("size", Vector2.ZERO) as Vector2
		errors.append_array(_validate_room(room, templates))
	# —— 触发器刷怪：盒子放置层 + 波次调用层（设计 §3.2 / §3.3 / §7）——
	# 为什么要有这一关：盒子写错（引用不存在的 box_id、盒心跑到房外、盒尺寸撑出房、
	# stage 下标越界）在运行时全部表现为「这房不出怪 / 出怪位置离奇」，且**不会报错**。
	# 静态层拦住是唯一能把「写错了」与「没生效」分开的地方。
	errors.append_array(_validate_spawn_boxes(rooms, center_by_key, size_by_key, normalized))
	# —— 门槽：设计源数据 vs 几何推导（05.2 §3.3 / §8 S2 断言）——
	# 这是盯住「跨语言门槽镜像」的那条会失败的断言：设计源写了 ports 就必须与
	# RoomDoorLane 的推导逐字段一致，不一致直接报错，绝不静默采信任何一侧。
	errors.append_array(_validate_port_derivation(rooms))
	# —— 房间矩形互斥 ——
	# 场地外边界自 2026-09-25 起**不再是判据**（主人裁定，见 05.2 §3.7）：拼接不再考虑
	# 是否超出 250×250，MAP_SIZE_M 退出摆位剪枝与校验判定，只作坐标原点与美术参照保留。
	var core_rect := Rect2(Vector2(2.5, 2.5) - Vector2.ONE * 32.5, Vector2.ONE * 65.0)
	# 核心区排除是「塔楼口径」：塔楼有电梯核心筒。单层独立关卡（如远征）无核心筒，
	# 由 L1 generation_policy.enforce_core_exclusion = false 关闭，避免对既有关卡误报。
	var enforce_core := bool(policy.get("enforce_core_exclusion", true))
	var keys: Array = center_by_key.keys()
	for first_index in range(keys.size()):
		var first_key := str(keys[first_index])
		var first_rect := _room_rect(first_key, center_by_key, size_by_key)
		var first_role := _role_of(rooms, first_key)
		if (
			enforce_core
			and not first_role in SAFE_ROLES
			and first_rect.intersection(core_rect).get_area() > EPS
		):
			errors.append("occupies_core:%s" % first_key)
		for second_index in range(first_index + 1, keys.size()):
			var second_key := str(keys[second_index])
			var second_rect := _room_rect(second_key, center_by_key, size_by_key)
			if first_rect.intersection(second_rect).get_area() > EPS:
				errors.append("room_overlap:%s:%s" % [first_key, second_key])
	# —— 楼梯保留区 ——
	var reservation_errors := _validate_reservations(normalized, rooms, center_by_key, size_by_key)
	errors.append_array(reservation_errors)
	# —— 父边与走廊可建性 ——
	var zero_length_pairs := _zero_length_pairs(normalized)
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var parent_key := str(room.get("parent_key", ""))
		if parent_key.is_empty():
			continue
		if parent_key == key:
			errors.append("room_is_own_parent:%s" % key)
			continue
		if not center_by_key.has(parent_key):
			errors.append("missing_parent:%s:%s" % [key, parent_key])
			continue
		var clear := ROOM_DOOR_LANE.corridor_clear(
			center_by_key[parent_key] as Vector2,
			size_by_key[parent_key] as Vector2,
			center_by_key[key] as Vector2,
			size_by_key[key] as Vector2
		)
		var lateral := ROOM_DOOR_LANE.lateral_offset(
			center_by_key[parent_key] as Vector2, center_by_key[key] as Vector2
		)
		if lateral > ROOM_DOOR_LANE.LATERAL_TOLERANCE_M:
			errors.append("corridor_not_colinear:%s:%s:lateral=%.2f" % [parent_key, key, lateral])
		var pair := "%s|%s" % [parent_key, key]
		var reversed_pair := "%s|%s" % [key, parent_key]
		var allows_zero := zero_length_pairs.has(pair) or zero_length_pairs.has(reversed_pair)
		if allows_zero:
			if clear > EPS:
				errors.append("edge_policy_stale:%s:%s:clear=%.2f" % [parent_key, key, clear])
		elif clear < ROOM_DOOR_LANE.MIN_CORRIDOR_CLEAR_M - EPS:
			errors.append("corridor_too_short:%s:%s:clear=%.2f" % [parent_key, key, clear])
		elif absf(round(clear / ROOM_DOOR_LANE.GRID_UNIT_M) - clear / ROOM_DOOR_LANE.GRID_UNIT_M) > EPS:
				errors.append("corridor_not_integer_segments:%s:%s:clear=%.3f" % [parent_key, key, clear])
	# —— 通道桥房「长边不连」——
	errors.append_array(_validate_short_edge_links(rooms, center_by_key, size_by_key, templates))
	# —— 主路与支线 ——
	var main_path := normalized.get("main_path", []) as Array
	for main_key in main_path:
		if not center_by_key.has(str(main_key)):
			errors.append("main_path_unknown_room:%s" % str(main_key))
	var main_content := 0
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("key", "")) in main_path:
			main_content += 1
	var min_main := int(policy.get("min_main_content_rooms", 10))
	if main_content < min_main:
		errors.append("main_path_short:%d< %d" % [main_content, min_main])
	var branch_count := _count_branches(rooms)
	var branch_range := policy.get("branch_count_range", [0, 999]) as Array
	if branch_range.size() >= 2:
		if branch_count < int(branch_range[0]) or branch_count > int(branch_range[1]):
			errors.append(
				"branch_count_out_of_range:%d not in [%d,%d]"
				% [branch_count, int(branch_range[0]), int(branch_range[1])]
			)
	# —— 面积预算（只算不判）——
	# 面积自 2026-09-25 起**只报数据、不设上限**（主人裁定，见 05.2 §3.7）：数字照算并
	# 落进 area_budget 供文档与验收读，但不再报 `area_budget_exceeded`。`enforce_area_budget`
	# 键保留读取以免旧数据报未知键，降级为「是否按超限口径打印」的日志开关，不影响准入。
	var _budget := AREA_BUDGET.calculate(rooms, policy)
	# —— Boss 层规则 ——
	var has_boss := false
	var exit_parent := ""
	for value in rooms:
		var room := value as Dictionary
		var role := str(room.get("role", ""))
		if role == "boss":
			has_boss = true
		if role == "stair_exit":
			exit_parent = str(room.get("parent_key", ""))
	if _is_boss_floor(level_id, floor_number):
		if not has_boss:
			errors.append("boss_floor_without_boss_room")
		elif not exit_parent.is_empty():
			var exit_room := _room_by_key(rooms, exit_parent)
			if str(exit_room.get("role", "")) != "boss":
				errors.append("boss_exit_parent_not_boss:%s" % exit_parent)
	return errors


## 门槽数据一致性：设计源 ports 必须与几何推导逐个 target 对上 side 与 lane。
##
## 只在设计源显式写了 ports 的房间上比对（缺失时 loader 用派生值回填，无从比对）。
## 这条断言的价值：S1 导出的 v004 数据曾把 7 处南/北门侧整体写反而无人发现 ——
## 门侧写反不会让任何几何校验失败（lane 是对的），只有跨源比对能抓住。
static func _validate_port_derivation(rooms: Array) -> Array[String]:
	var errors: Array[String] = []
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var declared := room.get("ports", []) as Array
		var derived := room.get("derived_ports", []) as Array
		if declared.is_empty() or bool(room.get("ports_derived", false)):
			continue
		var derived_by_target := {}
		for derived_value in derived:
			var derived_port := derived_value as Dictionary
			derived_by_target[str(derived_port.get("target", ""))] = derived_port
		for declared_value in declared:
			var declared_port := declared_value as Dictionary
			var target := str(declared_port.get("target", ""))
			if not derived_by_target.has(target):
				errors.append("port_target_not_neighbor:%s:%s" % [key, target])
				continue
			var derived_port := derived_by_target[target] as Dictionary
			var declared_side := str(declared_port.get("side", ""))
			var derived_side := str(derived_port.get("side", ""))
			if declared_side != derived_side:
				errors.append(
					"port_derivation_mismatch:%s:%s:side %s vs %s"
					% [key, target, declared_side, derived_side]
				)
			var declared_lane := float(declared_port.get("lane_m", 0.0))
			var derived_lane := float(derived_port.get("lane_m", 0.0))
			if absf(declared_lane - derived_lane) > 0.001:
				errors.append(
					"port_derivation_mismatch:%s:%s:lane %s vs %s"
					% [key, target, str(declared_lane), str(derived_lane)]
				)
		if declared.size() != derived.size():
			errors.append(
				"port_count_mismatch:%s:%d vs %d" % [key, declared.size(), derived.size()]
			)
	return errors


## 通道桥房「长边不连」门禁（业主硬口径）。
##
## 桥房跨坑而建：基坑 30×20 占掉房心，只有**一对短边**（相对长轴的两面墙）的
## 端头有实体平台可开门；两条长边全程封在平台侧壁上，门口会直接开在坑的投影里
## —— 实测（24 种子）所有门位沿长轴偏移 ≤ 5.01m，即全部落在坑投影内（见
## `probe_expedition01_bridge_short_edge` 的门位分布）。故长边**不许**出现在任何
## 一条连接上。
##
## 判据取 `RoomDoorLane.port_pair()` 的 `a_wall_length`（本侧墙长）—— 与生成器、
## 白盒导出共用同一份门槽实现，本处不另立几何推导。桥房短边墙长 == min(宽,高)，
## 墙长大于它即说明门开在长边上。
##
## 覆盖两类几何：
##   ① `mode = "constrained"` 关卡的运行时生成几何（生成器把产出交本函数校验）；
##   ② L2 文件里写死的样例 / 兜底版图（兜底路径不经生成器，只能靠本函数拦）。
## 桥房判据取模板 `sunken_pit` —— 与 `FloorPlanGenerator._requires_short_edge_links`
## 同口径，禁止在本处复刻桥房模板 id 列表。
static func _validate_short_edge_links(
	rooms: Array, center_by_key: Dictionary, size_by_key: Dictionary, templates: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	if templates.is_empty():
		return errors
	# 短边墙长 = 该房两条边长里较短的一条。
	var short_span_by_key := {}
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var template_id := str(room.get("template_id", ""))
		if template_id.is_empty() or not templates.has(template_id):
			continue
		if not (templates[template_id] as Dictionary).has("sunken_pit"):
			continue
		if not size_by_key.has(key):
			continue
		var size := size_by_key[key] as Vector2
		short_span_by_key[key] = minf(size.x, size.y)
	# 邻居表：父 + 子。支线与主路一视同仁 —— 规则只认几何，不认链路语义。
	var children_by_parent := {}
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var parent_key := str(room.get("parent_key", ""))
		if parent_key.is_empty() or parent_key == key:
			continue
		if not children_by_parent.has(parent_key):
			children_by_parent[parent_key] = []
		(children_by_parent[parent_key] as Array).append(key)
	for bridge_value in short_span_by_key.keys():
		var bridge_key := str(bridge_value)
		var short_span := float(short_span_by_key[bridge_key])
		var links: Array = []
		var parent_key := str(_room_by_key(rooms, bridge_key).get("parent_key", ""))
		if not parent_key.is_empty() and center_by_key.has(parent_key):
			links.append(parent_key)
		for child_value in (children_by_parent.get(bridge_key, []) as Array):
			links.append(str(child_value))
		for link_index in range(links.size()):
			var neighbor_key := str(links[link_index])
			if not center_by_key.has(neighbor_key):
				continue
			var port := ROOM_DOOR_LANE.port_pair(
				center_by_key[bridge_key] as Vector2,
				size_by_key[bridge_key] as Vector2,
				center_by_key[neighbor_key] as Vector2,
				size_by_key[neighbor_key] as Vector2
			)
			var wall_length := float(port.get("a_wall_length", 0.0))
			# 正方形桥房（无长边概念）时条件恒假，不误报。
			if wall_length > short_span + EPS:
				errors.append(
					"bridge_long_edge_link:%s:%s:side=%s:wall=%.1f>short=%.1f"
					% [bridge_key, neighbor_key, str(port.get("a_side", "")), wall_length, short_span]
				)
	return errors


## 房间按其 `template_rotation_deg` 解析出的**期望占位尺寸**。
## 奇数步（90 / 270）旋转交换两个分量 —— 这是「同一模板转置姿态」的唯一表达
## （2026-09-25 主人裁定，见 05.2 §3.6 第 4 条）：模板 id 集合锁定，转置不另建模板。
static func expected_size_for_rotation(template_size: Vector2, room: Dictionary) -> Vector2:
	var rotation_deg := float(room.get("rotation_deg", room.get("template_rotation_deg", 0.0)))
	var quarter_turns := int(round(rotation_deg / 90.0))
	if posmod(quarter_turns, 4) % 2 != 0:
		return Vector2(template_size.y, template_size.x)
	return template_size


## 单房间字段校验。
static func _validate_room(room: Dictionary, templates: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var key := str(room.get("key", ""))
	var size := room.get("size", Vector2.ZERO) as Vector2
	var room_type := str(room.get("room_type", ""))
	var role := str(room.get("role", ""))
	var center := room.get("center", Vector2.ZERO) as Vector2
	if key.is_empty():
		errors.append("room_key_empty_for_type:%s" % room_type)
		return errors
	if not room_type in LOADER.VALID_ROOM_TYPES:
		errors.append("room_type_invalid:%s:%s" % [key, room_type])
	if role.is_empty():
		errors.append("room_role_empty:%s" % key)
	if size.x <= 0.0 or size.y <= 0.0:
		errors.append("room_size_non_positive:%s" % key)
	if absf(size.x - round(size.x / 5.0) * 5.0) > EPS or absf(size.y - round(size.y / 5.0) * 5.0) > EPS:
		errors.append("room_size_not_grid_multiple:%s:%s" % [key, str(size)])
	var snapped_x := _snap_component_axis(center.x, size.x)
	var snapped_y := _snap_component_axis(center.y, size.y)
	if absf(snapped_x - center.x) > EPS or absf(snapped_y - center.y) > EPS:
		errors.append(
			"room_center_not_snapped:%s:(%.3f,%.3f)->(%.3f,%.3f)"
			% [key, center.x, center.y, snapped_x, snapped_y]
		)
	var template_id := str(room.get("template_id", ""))
	if template_id.is_empty():
		errors.append("room_template_id_empty:%s" % key)
	elif not templates.is_empty():
		if not templates.has(template_id):
			errors.append("room_template_unknown:%s:%s" % [key, template_id])
		else:
			var template := templates[template_id] as Dictionary
			var template_size := _vec2(template.get("size_m", []))
			# 转置姿态（奇数步旋转）下 L2 写的是**交换后**的尺寸（05.2 §3.6 第 4 条）：
			# 「同一模板换个朝向」只能用 `template_rotation_deg` 表达，不另建模板 id，
			# 所以这里必须按旋转后的期望尺寸比对，否则合法转置会被误报成尺寸不符。
			var expected_size := expected_size_for_rotation(template_size, room)
			if not size.is_equal_approx(expected_size):
				errors.append(
					"room_size_differs_from_template:%s:%s vs %s"
					% [key, str(size), str(expected_size)]
				)
			# 门位必须落在该墙的合法槽上（走唯一实现）。
			var lane_table := template.get("wall_lane_table", {}) as Dictionary
			for port_value in room.get("ports", []):
				var port := port_value as Dictionary
				var side := str(port.get("side", ""))
				var lane := float(port.get("lane_m", 0.0))
				var wall_length := float(port.get("wall_length_m", 0.0))
				if wall_length <= 0.0:
					continue
				var lane_errors := ROOM_DOOR_LANE.validate_port_lane(wall_length, lane)
				for lane_error in lane_errors:
					errors.append("port_lane_invalid:%s:%s:%s" % [key, side, lane_error])
				if lane_table.has(side):
					var declared_lanes := lane_table[side] as Array
					var matched := false
					for declared_lane in declared_lanes:
						if absf(float(declared_lane) - lane) <= 0.001:
							matched = true
							break
					if not matched and not declared_lanes.is_empty():
						errors.append(
							"port_lane_not_in_template_table:%s:%s:%s" % [key, side, str(lane)]
						)
	errors.append_array(_validate_enemy_spawn_plan(room))
	errors.append_array(_validate_reward_plan(room))
	return errors


## 校验房间级刷怪计划 enemy_spawn_plan。
## 结构：`{"waves": [ <波次> ]}`；`waves` 长度 = 波次数（**钉死**）。
## 每波两种写法，**互斥**：
##   ① 逐值固定：`{"monsters": [ {"type": "<种类>", "count": <正整数>} ]}`
##   ② 半钉死：  `{"pool": [<种类>...], "kinds": {"min": <n>, "max": <n>},
##                "count": {"min": <n>, "max": <n>}}`
##      —— 从 pool 无重复抽 `kinds` 种（缺省 = 全池），总数量落 `count` 区间；
##         数量下限必须 ≥ `kinds.max`，否则「抽中的每种至少 1 只」兑现不了。
## 允许留空/不写（回退全局公式）；但一旦写了就必须完全合法 ——
## 运行时的 build_waves_from_plan 对非法输入是「整份丢弃并回退」，
## 若不在这里拦住，"写错了"会表现为"没生效"，很难查。
static func _validate_enemy_spawn_plan(room: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var key := str(room.get("key", ""))
	var raw: Variant = room.get("enemy_spawn_plan", {})
	if raw == null:
		return errors
	if not (raw is Dictionary):
		errors.append("enemy_spawn_plan_not_object:%s" % key)
		return errors
	var plan := raw as Dictionary
	if plan.is_empty():
		return errors
	# 只有会刷怪的房型才允许声明：其它房型永不调用刷怪入口，写了等于静默失效。
	# BOSS 房单列一条错误码 —— 它不是「不刷怪」（它刷 Boss），而是**不归设计源管**：
	# Boss 的出场与结算由生成工具（BossContentCatalog）决定，设计源只声明 role/content_type。
	# 写在这里会让刷怪入口跳过 boss 生成，表现为「Boss 房没有 Boss」。
	# 判据统一取 GameDesignConfig.is_spawn_plan_authorable_room，禁止在本处复刻房型列表。
	var content_type := str(room.get("content_type", ""))
	if GAME_DESIGN_CONFIG.is_boss_room(content_type, str(room.get("role", ""))):
		errors.append(
			"enemy_spawn_plan_on_boss_room:%s:%s" % [key, content_type]
		)
	elif not GAME_DESIGN_CONFIG.is_spawn_plan_authorable_room(content_type):
		errors.append(
			"enemy_spawn_plan_on_non_hostile_room:%s:%s" % [key, content_type]
		)
	var raw_waves: Variant = plan.get("waves", [])
	if not (raw_waves is Array) or (raw_waves as Array).is_empty():
		errors.append("enemy_spawn_plan_waves_empty:%s" % key)
		return errors
	var waves := raw_waves as Array
	if waves.size() > SPAWN_PLAN_MAX_WAVES:
		errors.append(
			"enemy_spawn_plan_too_many_waves:%s:%d>%d"
			% [key, waves.size(), SPAWN_PLAN_MAX_WAVES]
		)
	var total := 0
	for wave_index in range(waves.size()):
		var wave_value: Variant = waves[wave_index]
		if not (wave_value is Dictionary):
			errors.append("enemy_spawn_plan_wave_not_object:%s:%d" % [key, wave_index])
			continue
		var wave := wave_value as Dictionary
		# 两种写法互斥：`pool`（半钉死）或 `monsters`（逐值固定）。同时写 = 歧义，
		# 都不写 = 空波次。运行时按 `has("pool")` 分派，故此处必须与它同判据。
		var has_pool := wave.has("pool")
		var has_monsters := wave.has("monsters")
		if has_pool and has_monsters:
			errors.append("enemy_spawn_plan_wave_ambiguous:%s:%d" % [key, wave_index])
			continue
		if has_pool:
			total += maxi(0, _validate_pool_wave(key, wave_index, wave, errors))
			continue
		if not has_monsters:
			errors.append("enemy_spawn_plan_wave_empty:%s:%d" % [key, wave_index])
			continue
		var raw_monsters: Variant = wave.get("monsters", [])
		if not (raw_monsters is Array) or (raw_monsters as Array).is_empty():
			errors.append(
				"enemy_spawn_plan_wave_monsters_empty:%s:%d" % [key, wave_index]
			)
			continue
		var wave_total := 0
		for monster_value in (raw_monsters as Array):
			if not (monster_value is Dictionary):
				errors.append(
					"enemy_spawn_plan_monster_not_object:%s:%d" % [key, wave_index]
				)
				continue
			var monster := monster_value as Dictionary
			var type_id := str(monster.get("type", ""))
			var count := int(monster.get("count", 0))
			if not MONSTER_INJECTOR.BASE_ENEMY_TYPES.has(type_id):
				errors.append(
					"enemy_spawn_plan_unknown_monster:%s:%d:%s" % [key, wave_index, type_id]
				)
			elif not MONSTER_INJECTOR.is_authorable_enemy_type(type_id):
				# Boss 有独立的出场与结算路径，从刷怪入口硬塞会绕过 Boss 逻辑。
				errors.append(
					"enemy_spawn_plan_monster_not_authorable:%s:%d:%s"
					% [key, wave_index, type_id]
				)
			if count <= 0:
				errors.append(
					"enemy_spawn_plan_monster_count_invalid:%s:%d:%s:%d"
					% [key, wave_index, type_id, count]
				)
			wave_total += maxi(0, count)
		if wave_total > SPAWN_PLAN_MAX_PER_WAVE:
			errors.append(
				"enemy_spawn_plan_wave_too_large:%s:%d:%d>%d"
				% [key, wave_index, wave_total, SPAWN_PLAN_MAX_PER_WAVE]
			)
		total += wave_total
	if total > SPAWN_PLAN_MAX_TOTAL:
		errors.append(
			"enemy_spawn_plan_total_too_large:%s:%d>%d" % [key, total, SPAWN_PLAN_MAX_TOTAL]
		)
	return errors


## 校验「半钉死」波次：`pool` + 可选 `kinds{min,max}` + `count{min,max}`。
## 返回该波的**最坏总数量**（= `count.max`）；返回 0 表示这一波非法（错误已写进 `errors`）。
##
## 为什么必须静态拦住：运行时 `_roll_pool_wave` 对非法输入是「整份丢弃并回退」，
## 放在这里才查得动 —— 否则「池里写了 boss」这种错会表现为「这间房忽然不刷怪了」。
static func _validate_pool_wave(
	key: String, wave_index: int, wave: Dictionary, errors: Array[String]
) -> int:
	var raw_pool: Variant = wave.get("pool", [])
	if not (raw_pool is Array) or (raw_pool as Array).is_empty():
		errors.append("enemy_spawn_plan_pool_empty:%s:%d" % [key, wave_index])
		return 0
	var pool := raw_pool as Array
	for type_value in pool:
		var type_id := str(type_value)
		if not MONSTER_INJECTOR.BASE_ENEMY_TYPES.has(type_id):
			errors.append(
				"enemy_spawn_plan_unknown_monster:%s:%d:%s" % [key, wave_index, type_id]
			)
		elif not MONSTER_INJECTOR.is_authorable_enemy_type(type_id):
			# 与 monsters 写法同口径：Boss 走独立出场路径，塞进池里会绕过它。
			errors.append(
				"enemy_spawn_plan_monster_not_authorable:%s:%d:%s"
				% [key, wave_index, type_id]
			)
	# `kinds` 可选：缺省 = 池里每种都出（等价于 kinds = {池长度, 池长度}）。
	var kinds_min := pool.size()
	var kinds_max := pool.size()
	var raw_kinds: Variant = wave.get("kinds", null)
	if raw_kinds != null:
		if not (raw_kinds is Dictionary):
			errors.append("enemy_spawn_plan_kinds_not_object:%s:%d" % [key, wave_index])
			return 0
		var kinds := raw_kinds as Dictionary
		kinds_min = int(kinds.get("min", pool.size()))
		kinds_max = int(kinds.get("max", pool.size()))
		if kinds_min < 1 or kinds_max < kinds_min:
			errors.append(
				"enemy_spawn_plan_kinds_invalid:%s:%d:%d-%d"
				% [key, wave_index, kinds_min, kinds_max]
			)
			return 0
		if kinds_max > pool.size():
			errors.append(
				"enemy_spawn_plan_kinds_exceeds_pool:%s:%d:%d>%d"
				% [key, wave_index, kinds_max, pool.size()]
			)
			return 0
	# `count` 必填：本波**总数量**区间。
	var raw_count: Variant = wave.get("count", null)
	if not (raw_count is Dictionary):
		errors.append("enemy_spawn_plan_count_missing:%s:%d" % [key, wave_index])
		return 0
	var count_data := raw_count as Dictionary
	var count_min := int(count_data.get("min", 0))
	var count_max := int(count_data.get("max", 0))
	if count_min <= 0 or count_max < count_min:
		errors.append(
			"enemy_spawn_plan_count_invalid:%s:%d:%d-%d"
			% [key, wave_index, count_min, count_max]
		)
		return 0
	# 总数量至少够「抽中的每一种各 1 只」—— 即不低于 `kinds_max`（缺省 kinds 时 = 池长度）。
	if count_min < kinds_max:
		errors.append(
			"enemy_spawn_plan_count_below_kinds:%s:%d:%d<%d"
			% [key, wave_index, count_min, kinds_max]
		)
		return 0
	if count_max > SPAWN_PLAN_MAX_PER_WAVE:
		errors.append(
			"enemy_spawn_plan_wave_too_large:%s:%d:%d>%d"
			% [key, wave_index, count_max, SPAWN_PLAN_MAX_PER_WAVE]
		)
	return count_max


## 校验房间级统一掉落计划 `reward_plan`（可选字段，04 §22.7 / 05 §11 `reward_slots[]`）。
##
## 结构：`{"clear": <slot_ref>, "search": <slot_ref>, "kill": <slot_ref>}`（键全可选）
## 槽位引用三种写法：
##   `{"spec_id": "exp01_room_03_clear"}`           命名规格
##   `{"entries": [...]}` / `{"fallback": [...]}`   内联规格
##   `{"pool_id": "loot_floor_1_2"}`                单条池简写（可带 draws / chance）
##
## 本校验器**只查它查得动的**：
##   ① trigger 拼错（写成 `killed` 而非 `kill`）会静默失效 ⇒ 必须当场报；
##   ② 三种写法必须**恰好给一种** —— 同时给是歧义（运行时按 spec_id 优先），
##      写错的人不会知道自己另一份写废了；
##   ③ 池引用（`pool_id` 或内联 pool 条目）**能在静态查证**（登记表是静态数据）⇒
##      未登记报 `unknown_pool`、已弃用报 `deprecated_pool`；
##   ④ 命名 `spec_id` 的**存在性查不了** —— 命名规格在运行时才装载。
##      故这里只校验非空字符串；拼错的后果由 `RewardService` 的 `UNKNOWN_SPEC`
##      在运行时拒绝且**不回退到别级**兜住（这是覆盖链的失败语义，不是静默）；
##   ⑤ `kill` 槽位只对「会刷怪的房型」有意义：取与 `enemy_spawn_plan` 相同的判据
##      （`is_spawn_plan_authorable_room`）。Boss 房不刷普通怪、安全/撤离房无击杀事件，
##      写了 `kill` 永不触发 ⇒ 与"静默失效"同类，当场报。
static func _validate_reward_plan(room: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var key := str(room.get("key", ""))
	var raw: Variant = room.get("reward_plan", {})
	if raw == null:
		return errors
	if not (raw is Dictionary):
		errors.append("reward_plan_not_object:%s" % key)
		return errors
	var plan := raw as Dictionary
	if plan.is_empty():
		return errors

	var content_type := str(room.get("content_type", ""))
	var is_boss := GAME_DESIGN_CONFIG.is_boss_room(content_type, str(room.get("role", "")))
	var hostile := GAME_DESIGN_CONFIG.is_spawn_plan_authorable_room(content_type)

	for trigger_value in plan.keys():
		var trigger := str(trigger_value)
		if not REWARD_SPEC.TRIGGERS.has(trigger):
			errors.append("reward_plan_unknown_trigger:%s:%s" % [key, trigger])
			continue
		var slot_value: Variant = plan[trigger_value]
		if not (slot_value is Dictionary):
			errors.append("reward_plan_slot_not_object:%s:%s" % [key, trigger])
			continue
		var slot := slot_value as Dictionary
		if slot.is_empty():
			errors.append("reward_plan_slot_empty:%s:%s" % [key, trigger])
			continue

		var forms := 0
		if slot.has("spec_id"):
			forms += 1
		if slot.has("entries") or slot.has("fallback"):
			forms += 1
		if slot.has("pool_id"):
			forms += 1
		if forms == 0:
			errors.append("reward_plan_slot_ambiguous:%s:%s:none" % [key, trigger])
			continue
		if forms > 1:
			errors.append("reward_plan_slot_ambiguous:%s:%s:multiple" % [key, trigger])
			continue

		if slot.has("spec_id") and str(slot["spec_id"]).is_empty():
			errors.append("reward_plan_spec_id_empty:%s:%s" % [key, trigger])
		if slot.has("pool_id"):
			errors.append_array(_validate_reward_pool_ref(str(slot["pool_id"]), key, trigger))
		for list_key in ["entries", "fallback"]:
			var list_value: Variant = slot.get(list_key, [])
			if not (list_value is Array):
				errors.append("reward_plan_%s_not_array:%s:%s" % [list_key, key, trigger])
				continue
			for entry_value in (list_value as Array):
				if not (entry_value is Dictionary):
					errors.append("reward_plan_entry_not_object:%s:%s" % [key, trigger])
					continue
				var entry := entry_value as Dictionary
				if str(entry.get("kind", "")) == "pool":
					errors.append_array(
						_validate_reward_pool_ref(str(entry.get("pool_id", "")), key, trigger)
					)
		if trigger == "kill" and not hostile:
			var reason := "boss_room" if is_boss else "non_hostile_room"
			errors.append("reward_plan_kill_on_%s:%s:%s" % [reason, key, content_type])
	return errors


## 池引用查证：未登记 / 已弃用各自成码，空串另算（空 pool_id 是写漏，不是拼错）。
static func _validate_reward_pool_ref(pool_id: String, key: String, trigger: String) -> Array[String]:
	var errors: Array[String] = []
	if pool_id.is_empty():
		errors.append("reward_plan_pool_id_empty:%s:%s" % [key, trigger])
		return errors
	if not REWARD_POOLS.has_pool(pool_id):
		errors.append("reward_plan_unknown_pool:%s:%s:%s" % [key, trigger, pool_id])
		return errors
	if not REWARD_POOLS.is_active(pool_id):
		errors.append("reward_plan_deprecated_pool:%s:%s:%s" % [key, trigger, pool_id])
	return errors


## 校验房间级首领指派 `boss_content_id`（可选字段）。
##
## 两条判据，缺一不可：
##   ① 只有 **Boss 房**能写 —— 其余房型永不生成 Boss，写了等于静默失效；
##   ② 必须指向 `BossContentCatalog` 里**真实存在**的内容 —— 拼写错误必须当场报错，
##      否则运行时表现为「这间房没 Boss」（`resolve_profile` 对未知 ID 一律返回空，
##      刻意不静默换成另一个首领），作者只会看到「我明明指定了却没出现」。
## 判据①走 GameDesignConfig.is_boss_room 唯一口径，禁止在本处复刻房型/角色列表。
static func _validate_boss_content_id(room: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var content_id := str(room.get("boss_content_id", ""))
	if content_id.is_empty():
		return errors
	var key := str(room.get("key", ""))
	var content_type := str(room.get("content_type", ""))
	if not GAME_DESIGN_CONFIG.is_boss_room(content_type, str(room.get("role", ""))):
		errors.append("boss_content_id_on_non_boss_room:%s:%s" % [key, content_type])
	if BOSS_CONTENT_CATALOG.floor_number_for_content_id(content_id) <= 0:
		errors.append("boss_content_id_unknown:%s:%s" % [key, content_id])
	return errors


## —— 触发器刷怪：盒子放置层 + 波次调用层（设计 §3.2 / §3.3 / §7）——
##
## 逐条判据：
##   A `spawn_boxes_only` 层里，**真敌对房**（`ROOM_TYPES_WITH_HOSTILES`）`spawn_placements`
##     必须非空（没盒子就不刷）；**EVENT 房例外** —— 它默认是纯事件房、**允许没有盒子**，
##     但也**允许**显式摆盒变成「事件 + 战斗」双职房（业主 2026-09-26「EVENT 房也可刷怪」，
##     可否摆盒的判据 = `GAME_DESIGN_CONFIG.room_type_uses_spawn_boxes`）；不在此判据里的
##     房型摆了盒仍报 `spawn_placement_on_non_hostile_room`；
##   B 每个实例的盒（按 rotation_deg 旋转后的 AABB）**完全落在本房名义包围盒内**；
##   C `encounter.stages[].boxes` 下标不越界、不重复，且每个实例**至少被一波引用**；
##   D 引用的 `box_id` 在资产库中已登记且文件合法；
##   F `spawn_boxes_only` 层里，旧字段 `enemy_spawn_plan` 必须归零；
##   G 盒心必须是**砖心相位**：全局 5m 砖格心恒在 `5k + 2.5`（实测 13 房逐值成立），
##     盒心不在此相位 ⇒ 运行时 `snap_box_center_to_tile` 一定把它静默挪到最近的砖心，
##     作者写的坐标与实得坐标对不上，「01 号盒调了没生效」的根因就在这里；
##   H **整个盒**（含边缘）到房墙的净距 ≥ `5*wall_recess_tiles` ——
##     即「**最外一圈地砖不得有任何刷怪点**」（业主 2026-09-26「最外一圈不要刷怪，
##     往里头布置刷怪盒子」）。判盒边而非盒心：怪只在盒内取样，盒不压进最外圈 ⇒
##     那圈必无怪；判盒心时「盒心够、盒边不够」仍会让怪出在最外一圈（详见实现处注释）；
##   I 同房内两个实例**盒心不得重合**、**AABB 不得互叠**（重复刷 = 必是笔误；互叠则
##     两盒各自贪心、互不知情，落点会挤在一起 —— 见设计文档「待修缺口 (a)」）；
##   J 逐实例生效尺寸不得低于 `SpawnBoxCatalog.MIN_SIZE_M`（2×2 m，业主口径）；
##   K `rotation_deg` 只许 0 / 90 / 180 / 270（斜置盒的 AABB 与砖格对不上）。
##
## ⚠ **几何门控**：B / G / H 依赖「房间的真实尺寸与真实位置」，而 `mode = "constrained"`
## 关卡里 L2 文件存的 `center_m` / `size_m` 只是「样例 / 兜底」（真正的几何由生成器按种子算，
## 见 `FloorPlanGenerator._constrained_floor_from` 的注释）。因此这三条只在
## `normalized.geometry_authoritative == true` 时执行 —— 读文件得到 false、生成器算完
## 覆写成 true（成对见 `LevelPlanLoader.normalize_floor`）。实测教训：远征 room_05 房表
## 声明 30×60、运行时却是 60×30，拿样例几何判会把一整房合法盒位误报成「越出房间」。
## G 额外要求「本房真有授权地砖」—— 没有授权壳体的房（如远征入口）`_authored_tile_cells`
## 为空，`snap_box_center_to_tile` 直接原样返回声明点，此时砖心相位无意义。
## I / J / K 只用**房内相对量**（局部盒心、盒尺寸、旋转角），与几何权威性无关，恒执行。
##
## 为什么这些必须在静态层拦住：运行时对非法放置的策略是「跳过该实例」，
## 于是「写错了」与「这房本来就没怪」**在表现上完全一样**，且不报错。
static func _validate_spawn_boxes(
	rooms: Array,
	center_by_key: Dictionary,
	size_by_key: Dictionary,
	normalized: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	var boxes_only := bool(normalized.get("spawn_boxes_only", false))
	# 见本函数头注释 ⚠：缺省 true（`authored` 关卡的文件几何就是真几何，行为逐字不变）。
	var geometry_real := bool(normalized.get("geometry_authoritative", true))
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var content_type := str(room.get("content_type", ""))
		var hostile := (
			GAME_DESIGN_CONFIG.ROOM_TYPES_WITH_HOSTILES.has(content_type)
			and not bool(room.get("authored_layout_peaceful", false))
		)
		# 「可否摆盒」= 真敌对房 ＋ EVENT（见函数头判据 A）。⚠️ 与 `hostile` 是两件事：
		# `hostile` 决定「**必须**有盒」，`box_authorable` 决定「**允许**有盒」。
		var box_authorable := (
			GAME_DESIGN_CONFIG.room_type_uses_spawn_boxes(content_type)
			and not bool(room.get("authored_layout_peaceful", false))
		)
		var placements := _placement_entries(room, key, errors)
		if boxes_only and hostile:
			if placements.is_empty():
				errors.append("spawn_boxes_missing_for_hostile_room:%s" % key)
			if not (room.get("enemy_spawn_plan", {}) as Dictionary).is_empty():
				errors.append("enemy_spawn_plan_on_spawn_boxes_layer:%s" % key)
		elif not box_authorable and not placements.is_empty():
			# 不在「可摆盒」判据里的房型永不调用刷怪入口，摆了等于静默失效（与 enemy_spawn_plan 同口径）。
			errors.append("spawn_placement_on_non_hostile_room:%s:%s" % [key, content_type])
		var room_center := center_by_key.get(key, Vector2.ZERO) as Vector2
		var room_rect := _room_rect(key, center_by_key, size_by_key)
		# G 的额外门控：本房真有**授权地砖**才谈得上砖心相位。判据用 `authored_layout_room_id`
		# 非空 —— 它就是「本房拿了整房 5m 通用壳体（含 floor_tile 实例）」的标记
		# （`FloorPlanGenerator.attach_authored_layout_shell` 置位、`normalize_floor` 透传）。
		# 无授权壳体的房（远征入口 `entry`、塔楼程序化房）没有砖格，`snap_box_center_to_tile`
		# 会原样返回声明点，此时判砖心相位纯属误报。
		var has_authored_tiles := not str(room.get("authored_layout_room_id", "")).is_empty()
		# 同房内已登记的盒（**局部**矩形 + 盒心），供判据 I 逐对比较。
		# 为什么用局部量：与房表几何是否权威无关，故不受 `geometry_authoritative` 门控 ——
		# 这是唯一能在「样例几何」（校验 L2 文件）下依然生效的几何判据。
		var seen_local_centers: Array[Vector2] = []
		var seen_local_rects: Array[Rect2] = []
		for index in range(placements.size()):
			var placement_value: Variant = placements[index]
			var slot := "%s[%d]" % [key, index]
			if not (placement_value is Dictionary):
				errors.append("spawn_placement_not_object:%s" % slot)
				continue
			var placement := placement_value as Dictionary
			var box_id := str(placement.get("box", ""))
			if box_id.is_empty():
				errors.append("spawn_placement_box_empty:%s" % slot)
				continue
			if not SPAWN_BOX_CATALOG.has_id(box_id):
				errors.append("spawn_placement_box_unregistered:%s:%s" % [slot, box_id])
				continue
			var box := SPAWN_BOX_CATALOG.load_box(box_id)
			if box.is_empty():
				errors.append("spawn_placement_box_invalid:%s:%s" % [slot, box_id])
				continue
			if not placement.has("center_m"):
				errors.append("spawn_placement_center_missing:%s" % slot)
			var local_center := _vec2(placement.get("center_m", []))
			var box_size := box.get("size_m", Vector2.ZERO) as Vector2
			var raw_size: Variant = placement.get("size_m", null)
			var size_overridden := raw_size is Array and (raw_size as Array).size() >= 2
			if size_overridden:
				box_size = _vec2(raw_size)
			if box_size.x <= 0.0 or box_size.y <= 0.0:
				errors.append("spawn_placement_size_non_positive:%s" % slot)
				continue
			# 判据 J：**逐实例生效尺寸**（资产缺省 or 实例覆盖）不得低于 2×2 m。
			# 资产侧的缺省尺寸另有 `SpawnBoxCatalog.validate_box` 把关，这里只管运行时
			# 真正用的那一份 —— 实例覆盖可以把它改小，那就是漏洞。
			if (
				box_size.x < SPAWN_BOX_CATALOG.MIN_SIZE_M - EPS
				or box_size.y < SPAWN_BOX_CATALOG.MIN_SIZE_M - EPS
			):
				errors.append(
					"spawn_placement_size_below_minimum:%s:%.2f×%.2f<%.1f%s"
					% [
						slot, box_size.x, box_size.y, SPAWN_BOX_CATALOG.MIN_SIZE_M,
						"(size_m 覆盖)" if size_overridden else "(资产缺省)",
					]
				)
			var rotation_deg := float(placement.get("rotation_deg", 0.0))
			# 判据 K：只许 90° 的整数倍。斜置盒的 AABB 与砖格、与 `_box_local_point` 的
			# 落点系都对不上，运行时同样静默错位。
			var rotation_residual := fposmod(rotation_deg, 90.0)
			if rotation_residual > EPS and absf(rotation_residual - 90.0) > EPS:
				errors.append("spawn_placement_rotation_invalid:%s:%.2f" % [slot, rotation_deg])
			var radians := deg_to_rad(rotation_deg)
			# 旋转后的轴对齐外包尺寸：盒是矩形，绕 Y 转 θ 后 AABB 由 |cos|/|sin| 定。
			var extent := Vector2(
				absf(box_size.x * cos(radians)) + absf(box_size.y * sin(radians)),
				absf(box_size.x * sin(radians)) + absf(box_size.y * cos(radians))
			)
			var box_center := room_center + local_center
			var box_rect := Rect2(box_center - extent * 0.5, extent)
			# 判据 B：盒 AABB 完全落在本房包围盒内（受几何门控 —— 样例几何下必误报）。
			if geometry_real and not room_rect.encloses(box_rect):
				errors.append(
					"spawn_placement_outside_room:%s:box=%s:room=%s"
					% [slot, str(box_rect), str(room_rect)]
				)
			# 判据 G：盒心必须是砖心相位。
			if geometry_real and has_authored_tiles and not _tile_center_phase(box_center):
				errors.append(
					"spawn_placement_not_tile_center:%s:%.2f,%.2f"
					% [slot, box_center.x, box_center.y]
				)
			# 判据 H：**整个盒**（含边缘）到房墙净距 ≥ 5*wall_recess_tiles。
			##
			## 业主口径（2026-09-26）：「**最外一圈地砖不要刷怪**，往里头布置刷怪盒子」。
			## 为什么判**盒边**而不是盒心就能兑现这句话：怪只在盒内取样 ⇒ 盒不压进最外一圈
			## ⇒ 那圈必然一只怪都没有。反过来「盒心够、盒边不够」时，盒仍会盖住最外圈，
			## 怪就会出在贴墙的第一排 —— 正是业主看到的坏体验。
			##
			## 口径沿革（旧版只判**盒心**）：盒心 ≥5 m ＋ 盒半宽 2 m ⇒ 盒边可以只离墙 3 m，
			## 而最外一圈地砖横跨墙内 0~5 m ⇒ 盒边仍压在最外圈上。实测旧版数据确实如此
			## （房间级落点 183/192 落在最外圈，最近离墙 1.35 m）；判据改判盒边后，
			## 「最外一圈禁刷」从「数据碰巧满足」变成**静态可拦的硬约束**。
			## 现网 39 盒实测：盒边最近净距 5.55 m ≥ 5，故本次收紧不触发任何既有盒位改动。
			if geometry_real:
				var recess := int(box.get("wall_recess_tiles", SPAWN_BOX_CATALOG.DEFAULT_WALL_RECESS_TILES))
				var need := ROOM_DOOR_LANE.GRID_UNIT_M * float(maxi(0, recess))
				var edge_clearance := minf(
					minf(box_rect.position.x - room_rect.position.x, room_rect.end.x - box_rect.end.x),
					minf(box_rect.position.y - room_rect.position.y, room_rect.end.y - box_rect.end.y)
				)
				if edge_clearance < need - EPS:
					errors.append(
						"spawn_placement_wall_recess_short:%s:%.2f<%.2f(=%d圈)"
						% [slot, edge_clearance, need, maxi(0, recess)]
					)
			# 判据 I：同房盒心不得重合、AABB 不得互叠（局部量，恒执行）。
			# 互叠为什么是错：运行时**同波多盒之间没有排斥**（每盒各自贪心、互不知情），
			# 重叠的两个盒会把两组怪挤在同一片地上、彼此穿模。修好前先在静态层拦住。
			var local_rect := Rect2(local_center - extent * 0.5, extent)
			for prior in range(seen_local_centers.size()):
				if seen_local_centers[prior].distance_to(local_center) <= EPS:
					errors.append("spawn_placement_center_duplicate:%s:%d" % [slot, prior])
				elif seen_local_rects[prior].intersects(local_rect):
					errors.append("spawn_placement_overlap:%s:%d" % [slot, prior])
			seen_local_centers.append(local_center)
			seen_local_rects.append(local_rect)
			if float(placement.get("delay_sec", 0.0)) < 0.0:
				errors.append("spawn_placement_delay_negative:%s" % slot)
		# —— 调用层 ——
		# 没有 encounter 时全部实例并进一波（运行时口径），故只在写了 encounter 时校验。
		if not placements.is_empty() or not (room.get("encounter", {}) as Dictionary).is_empty():
			errors.append_array(_validate_encounter(room, key, placements.size()))
	return errors


## 房间级放置数组的类型守卫：非数组报错，逐项不是对象也报错（运行时按「跳过」处理）。
static func _placement_entries(
	room: Dictionary, key: String, errors: Array[String]
) -> Array:
	var raw: Variant = room.get("spawn_placements", [])
	if raw == null:
		return []
	if not (raw is Array):
		errors.append("spawn_placements_not_array:%s" % key)
		return []
	return raw as Array


## 波次调用层（`encounter.stages`）。判据 C：下标不越界、不重复、每个实例都被排到。
static func _validate_encounter(
	room: Dictionary, key: String, placement_count: int
) -> Array[String]:
	var errors: Array[String] = []
	var raw: Variant = room.get("encounter", {})
	if raw == null or (raw is Dictionary and (raw as Dictionary).is_empty()):
		return errors
	if not (raw is Dictionary):
		errors.append("encounter_not_object:%s" % key)
		return errors
	var encounter := raw as Dictionary
	if placement_count <= 0:
		errors.append("encounter_without_placements:%s" % key)
		return errors
	if float(encounter.get("intermission_sec", 2.0)) < 0.0:
		errors.append("encounter_intermission_negative:%s" % key)
	var raw_stages: Variant = encounter.get("stages", [])
	if not (raw_stages is Array):
		errors.append("encounter_stages_not_array:%s" % key)
		return errors
	var stages := raw_stages as Array
	if stages.is_empty():
		return errors
	if stages.size() > SPAWN_BOX_MAX_STAGES:
		errors.append(
			"encounter_too_many_stages:%s:%d>%d" % [key, stages.size(), SPAWN_BOX_MAX_STAGES]
		)
	var scheduled := {}
	for stage_index in range(stages.size()):
		var stage_value: Variant = stages[stage_index]
		if not (stage_value is Dictionary):
			errors.append("encounter_stage_not_object:%s:%d" % [key, stage_index])
			continue
		var stage := stage_value as Dictionary
		var raw_boxes: Variant = stage.get("boxes", [])
		if not (raw_boxes is Array) or (raw_boxes as Array).is_empty():
			errors.append("encounter_stage_boxes_empty:%s:%d" % [key, stage_index])
			continue
		for box_value in (raw_boxes as Array):
			if not (box_value is float or box_value is int):
				errors.append("encounter_stage_box_index_not_int:%s:%d" % [key, stage_index])
				continue
			var index := int(box_value)
			if index < 0 or index >= placement_count:
				errors.append(
					"encounter_stage_box_index_out_of_range:%s:%d:%d"
					% [key, stage_index, index]
				)
				continue
			if scheduled.has(index):
				errors.append("encounter_stage_box_index_duplicate:%s:%d" % [key, index])
				continue
			scheduled[index] = true
	# 摆了却永不排到的实例 = 一个永远不出怪的盒子 —— 静默失效，必须报。
	for index in range(placement_count):
		if not scheduled.has(index):
			errors.append("spawn_placement_never_scheduled:%s:%d" % [key, index])
	return errors


static func _validate_template(template_id: String, template: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var size := _vec2(template.get("size_m", []))
	if size.x <= 0.0 or size.y <= 0.0:
		errors.append("template_size_non_positive:%s" % template_id)
	if absf(size.x - round(size.x / 5.0) * 5.0) > EPS or absf(size.y - round(size.y / 5.0) * 5.0) > EPS:
		errors.append("template_size_not_grid_multiple:%s" % template_id)
	var openable := template.get("openable_walls", []) as Array
	if openable.is_empty():
		errors.append("template_openable_walls_empty:%s" % template_id)
	var lane_table := template.get("wall_lane_table", {}) as Dictionary
	for side in openable:
		var side_id := str(side)
		if not lane_table.has(side_id):
			errors.append("template_lane_table_missing_side:%s:%s" % [template_id, side_id])
			continue
		var lanes := lane_table[side_id] as Array
		var expected := ROOM_DOOR_LANE.lane_offsets(_wall_length_for(size, side_id))
		if lanes.size() != expected.size():
			errors.append(
				"template_lane_table_size_mismatch:%s:%s:%d vs %d"
				% [template_id, side_id, lanes.size(), expected.size()]
			)
			continue
		for index in range(lanes.size()):
			if absf(float(lanes[index]) - float(expected[index])) > 0.001:
				errors.append(
					"template_lane_table_drift:%s:%s:index=%d:%s vs %s"
					% [template_id, side_id, index, str(lanes[index]), str(expected[index])]
				)
	if not lane_table.has("north") or not lane_table.has("east"):
		errors.append("template_lane_table_incomplete:%s" % template_id)
	return errors


static func _validate_reservations(
	normalized: Dictionary, rooms: Array, center_by_key: Dictionary, size_by_key: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	var reservations := normalized.get("reservations", []) as Array
	if reservations.is_empty():
		return errors
	for reservation_value in reservations:
		if not (reservation_value is Dictionary):
			continue
		var reservation := reservation_value as Dictionary
		var side := str(reservation.get("side", ""))
		var rect_size := _vec2(reservation.get("rect_m", []))
		var rect := _reservation_rect(side, rect_size)
		for value in rooms:
			var room := value as Dictionary
			var key := str(room.get("key", ""))
			if str(room.get("role", "")) in SAFE_ROLES:
				continue
			var room_rect := _room_rect(key, center_by_key, size_by_key)
			if rect.intersection(room_rect).get_area() > EPS:
				errors.append("occupies_%s_stair_reservation:%s" % [side, key])
	return errors


## 保留区矩形：由核心筒对应边向外 20m、沿切向 30m。
static func _reservation_rect(side: String, rect_size: Vector2) -> Rect2:
	var outward := {
		"north": Vector2.UP, "south": Vector2.DOWN,
		"west": Vector2.LEFT, "east": Vector2.RIGHT,
	}.get(side, Vector2.LEFT) as Vector2
	var tangent := Vector2(outward.y, -outward.x)
	var interface := Vector2(2.5, 2.5) + outward * 32.5
	var outward_distance := rect_size.x
	var tangent_distance := rect_size.y
	var corners: Array[Vector2] = []
	for outward_step in [0.0, outward_distance]:
		for tangent_step in [-tangent_distance * 0.10, tangent_distance * 0.90]:
			corners.append(
				interface + outward * float(outward_step) + tangent * float(tangent_step)
			)
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


static func _validate_level_header(level_plan: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(level_plan.get("schema_version", 0)) < 1:
		errors.append("level_schema_version_missing")
	if int(level_plan.get("floor_rule_version", 0)) < 1:
		errors.append("level_floor_rule_version_missing")
	var floors := level_plan.get("floors", []) as Array
	if floors.is_empty():
		errors.append("level_has_no_floors")
	for value in floors:
		var entry := value as Dictionary
		var rule := str(entry.get("rule", ""))
		if not rule in LOADER.VALID_RULES:
			errors.append("floor_rule_invalid:%s" % rule)
		if str(entry.get("plan", "")).is_empty():
			errors.append("floor_plan_path_empty:%d" % int(entry.get("floor_number", 0)))
	var grid := float(level_plan.get("grid_unit_m", 0.0))
	if absf(grid - ROOM_DOOR_LANE.GRID_UNIT_M) > EPS:
		errors.append("level_grid_unit_not_5m:%.3f" % grid)
	return errors


static func _role_of(rooms: Array, key: String) -> String:
	return str(_room_by_key(rooms, key).get("role", ""))


static func _room_by_key(rooms: Array, key: String) -> Dictionary:
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("key", "")) == key:
			return room
	return {}


static func _room_rect(key: String, center_by_key: Dictionary, size_by_key: Dictionary) -> Rect2:
	if not center_by_key.has(key):
		return Rect2()
	var center := center_by_key[key] as Vector2
	var size := size_by_key[key] as Vector2
	return Rect2(center - size * 0.5, size)


## 判据 G 的核：全局 5m 砖格的**格心相位**。
##
## 砖心恒在 `5k + 2.5`（两个轴独立同式）。为什么与房宽奇偶无关：奇数格宽房心在 `5k+2.5`、
## 偶数格宽房心在 `5k`，两种情形下掐出来的砖心相位都落在 `2.5`（5m 模数口径，见 05.2 §3.4）。
## 已用远征 01 全部 13 房（含 boss / extraction）的探针 `tile_cells_local` 逐值实测：全局
## 砖心的 X / Z 相位集合都恰好是 `{2.5}`。
##
## 判据不看房的尺寸与中心 —— 砖格是**全局锚定**的，所以这条天然免疫「房表几何 ≠ 真几何」
## 的问题；真正需要门控的是「本房到底有没有授权地砖」（见 `_validate_spawn_boxes` 里
## `has_authored_tiles` 的注释）。
static func _tile_center_phase(point: Vector2) -> bool:
	var unit := ROOM_DOOR_LANE.GRID_UNIT_M
	var half := unit * 0.5
	return (
		absf(fposmod(point.x, unit) - half) <= EPS
		and absf(fposmod(point.y, unit) - half) <= EPS
	)




static func _wall_length_for(size: Vector2, side: String) -> float:
	if side in ["north", "south"]:
		return size.x
	return size.y


static func _zero_length_pairs(normalized: Dictionary) -> Dictionary:
	var pairs := {}
	for value in normalized.get("edge_policy", []):
		if not (value is Dictionary):
			continue
		var policy := value as Dictionary
		if not bool(policy.get("allow_zero_length", false)):
			continue
		pairs["%s|%s" % [str(policy.get("a", "")), str(policy.get("b", ""))]] = true
	return pairs


static func _count_branches(rooms: Array) -> int:
	var role_by_key := {}
	for value in rooms:
		var room := value as Dictionary
		role_by_key[str(room.get("key", ""))] = str(room.get("role", ""))
	var count := 0
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("role", "")) != "branch":
			continue
		var parent_key := str(room.get("parent_key", ""))
		if str(role_by_key.get(parent_key, "")) != "branch":
			count += 1
	return count


static func _is_boss_floor(level_id: String, floor_number: int) -> bool:
	var level_plan := LOADER.load_level_plan(level_id)
	var entry := LOADER.floor_entry(level_plan, floor_number)
	return str(entry.get("rule", "")) == "boss"


static func _vec2(value: Variant) -> Vector2:
	if value is Array:
		var arr := value as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


## 坐标吸附唯一实现转发（与 TowerGeometry3D.snap_component_axis 同式）。
static func _snap_component_axis(center_m: float, size_m: float) -> float:
	return snappedf(center_m - size_m * 0.5, ROOM_DOOR_LANE.GRID_UNIT_M) + size_m * 0.5
