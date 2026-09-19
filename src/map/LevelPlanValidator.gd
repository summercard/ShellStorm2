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


## 校验单层。
static func validate_floor(
	level_id: String,
	floor_number: int,
	policy: Dictionary = {},
	templates: Dictionary = {}
) -> Array[String]:
	var errors: Array[String] = []
	var normalized := LOADER.normalize_floor(level_id, floor_number)
	if normalized.is_empty():
		return ["floor_plan_missing:%s:%d" % [level_id, floor_number]]
	# normalize_floor 的 schema 层错误是非类型化数组，逐条收进强类型结果。
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
	# —— 房间矩形互斥与出界 ——
	var map_rect := Rect2(Vector2(-125.0, -125.0), Vector2(250.0, 250.0))
	var core_rect := Rect2(Vector2(2.5, 2.5) - Vector2.ONE * 32.5, Vector2.ONE * 65.0)
	# 核心区排除是「塔楼口径」：塔楼有电梯核心筒。单层独立关卡（如远征）无核心筒，
	# 由 L1 generation_policy.enforce_core_exclusion = false 关闭，避免对既有关卡误报。
	var enforce_core := bool(policy.get("enforce_core_exclusion", true))
	var keys: Array = center_by_key.keys()
	for first_index in range(keys.size()):
		var first_key := str(keys[first_index])
		var first_rect := _room_rect(first_key, center_by_key, size_by_key)
		if not _rect_inside(map_rect, first_rect):
			errors.append("outside_floor_bounds:%s" % first_key)
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
	# —— 面积预算 ——
	var budget := AREA_BUDGET.calculate(rooms)
	var used := float(budget.get("estimated_used_area_m2", 0.0))
	var target := float(budget.get("target_usable_area_m2", 0.0))
	if used > target:
		errors.append("area_budget_exceeded:used=%.1f target=%.1f" % [used, target])
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
			if not size.is_equal_approx(template_size):
				errors.append(
					"room_size_differs_from_template:%s:%s vs %s"
					% [key, str(size), str(template_size)]
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


static func _rect_inside(container: Rect2, child: Rect2) -> bool:
	return (
		child.position.x >= container.position.x - EPS
		and child.position.y >= container.position.y - EPS
		and child.end.x <= container.end.x + EPS
		and child.end.y <= container.end.y + EPS
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
