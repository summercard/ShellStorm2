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
## 硬上限：设计源写超大数字不该变成性能事故或开局卡死，直接在静态校验拦住。
const SPAWN_PLAN_MAX_WAVES := 6
const SPAWN_PLAN_MAX_PER_WAVE := 24
const SPAWN_PLAN_MAX_TOTAL := 64


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
## 结构：{"waves": [ {"monsters": [ {"type": "<种类>", "count": <正整数>} ]} ]}
##   waves 长度        = 波次数
##   一波内 count 之和 = 该波数量
##   monsters 列表     = 该波的怪物组成
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
		var raw_monsters: Variant = (wave_value as Dictionary).get("monsters", [])
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
