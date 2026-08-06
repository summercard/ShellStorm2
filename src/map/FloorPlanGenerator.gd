class_name FloorPlanGenerator
extends RefCounted
## 纯数据楼层规划器。输入种子与楼层语义，输出可复现的房间树、面积预算和验收结果。
## 本类不创建 Node，不依赖场景树，便于存档恢复、批量性质测试和独立维护。

const MAP_SIZE_M := 250.0
const CORE_SIZE_M := 65.0
const CORE_CENTER := Vector2(2.5, 2.5)
const GRID_UNIT_M := 5.0
const WALL_THICKNESS_M := 0.30
const CORRIDOR_WIDTH_M := 6.0
const MIN_CORRIDOR_GAP_M := 5.0
const SAFE_ROOM_SIZE := Vector2(15.0, 15.0)
const TARGET_OCCUPANCY_RATIO := 0.42
const REFERENCE_CONTENT_ROOM_COST_M2 := 1450.0
const MAX_GENERATION_ATTEMPTS := 24
const MIN_MAIN_CONTENT_ROOMS := 10
const MIN_BRANCH_COUNT := 2
const MAX_BRANCH_COUNT := 5
const STAIR_RESERVATION_OUTWARD_M := 20.0
const STAIR_RESERVATION_TANGENT_M := 30.0

const ROOM_SIZES := {
	"STANDARD": Vector2(30.0, 25.0),
	"WIDE": Vector2(40.0, 25.0),
	"DEEP": Vector2(30.0, 40.0),
	"MEDIUM": Vector2(35.0, 30.0),
	"LARGE": Vector2(40.0, 35.0),
	"BOSS_ARENA": Vector2(90.0, 90.0),
}

const CONTENT_TYPES := [
	"COMBAT", "COMBAT", "EVENT", "STORAGE", "SCAVENGE", "ELITE", "TRAP", "UPGRADE",
]


static func generate(request: Dictionary) -> Dictionary:
	var run_seed := int(request.get("run_seed", 1))
	var floor_number := int(request.get("floor_number", 98))
	var floor_index := int(request.get("floor_index", maxi(2, 100 - floor_number)))
	var sequence_index := int(request.get("sequence_index", maxi(1, 99 - floor_number)))
	var entry_side := str(request.get("entry_side", "east"))
	var boss_floor := bool(request.get("boss_floor", floor_number % 5 == 0))
	var last_errors: Array[String] = []
	for attempt in range(MAX_GENERATION_ATTEMPTS):
		var candidate := _build_candidate(
			run_seed,
			floor_number,
			floor_index,
			sequence_index,
			entry_side,
			boss_floor,
			attempt
		)
		last_errors = validate(candidate)
		if last_errors.is_empty():
			candidate["valid"] = true
			candidate["validation_errors"] = []
			candidate["attempt_count"] = attempt + 1
			candidate["used_fallback"] = false
			return candidate
	var fallback := _build_candidate(
		run_seed,
		floor_number,
		floor_index,
		sequence_index,
		entry_side,
		boss_floor,
		0
	)
	var fallback_errors := validate(fallback)
	fallback["valid"] = fallback_errors.is_empty()
	fallback["validation_errors"] = fallback_errors
	fallback["rejected_candidate_errors"] = last_errors
	fallback["attempt_count"] = MAX_GENERATION_ATTEMPTS
	fallback["used_fallback"] = true
	return fallback


static func validate(plan: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rooms := plan.get("rooms", []) as Array
	var room_by_key: Dictionary = {}
	var map_rect := Rect2(
		Vector2(-MAP_SIZE_M * 0.5, -MAP_SIZE_M * 0.5),
		Vector2(MAP_SIZE_M, MAP_SIZE_M)
	)
	var core_rect := Rect2(
		CORE_CENTER - Vector2.ONE * CORE_SIZE_M * 0.5,
		Vector2.ONE * CORE_SIZE_M
	)
	for room_value in rooms:
		var room := room_value as Dictionary
		var key := str(room.get("key", ""))
		if key.is_empty() or room_by_key.has(key):
			errors.append("duplicate_or_empty_room_key:%s" % key)
			continue
		room_by_key[key] = room
		var dimensions := room.get("dimensions", Vector2.ZERO) as Vector2
		var role := str(room.get("role", ""))
		if role in ["stair_entry", "stair_exit"]:
			if not dimensions.is_equal_approx(SAFE_ROOM_SIZE):
				errors.append("safe_room_size:%s" % key)
		elif role != "boss" and (maxf(dimensions.x, dimensions.y) < 30.0 or minf(dimensions.x, dimensions.y) < 25.0):
			errors.append("content_room_too_small:%s" % key)
		var room_rect := _room_rect(room)
		if not _rect_contains_rect(map_rect, room_rect):
			errors.append("outside_floor_bounds:%s" % key)
		if role not in ["stair_entry", "stair_exit"] and room_rect.intersection(core_rect).get_area() > 0.01:
			errors.append("occupies_core:%s" % key)
	for first_index in range(rooms.size()):
		var first := rooms[first_index] as Dictionary
		for second_index in range(first_index + 1, rooms.size()):
			var second := rooms[second_index] as Dictionary
			if _room_rect(first).intersection(_room_rect(second)).get_area() > 0.01:
				errors.append("room_overlap:%s:%s" % [first.get("key", ""), second.get("key", "")])
	var stair_sides: Array[String] = [str(plan.get("entry_side", "east"))]
	if str(plan.get("terminal_mode", "")).ends_with("down_stair_lobby"):
		stair_sides.append(str(plan.get("exit_side", "west")))
	for stair_side in stair_sides:
		var reservation := _stair_reservation_rect(stair_side)
		for room_value in rooms:
			var room := room_value as Dictionary
			if str(room.get("role", "")) in ["stair_entry", "stair_exit"]:
				continue
			if reservation.intersection(_room_rect(room)).get_area() > 0.01:
				errors.append("occupies_%s_stair_reservation:%s" % [stair_side, room.get("key", "")])
	for room_value in rooms:
		var room := room_value as Dictionary
		var parent_key := str(room.get("parent_key", ""))
		if parent_key.is_empty():
			continue
		if not room_by_key.has(parent_key):
			errors.append("missing_parent:%s" % room.get("key", ""))
			continue
		if not _edge_is_buildable(room_by_key[parent_key] as Dictionary, room):
			errors.append("unbuildable_corridor:%s:%s" % [parent_key, room.get("key", "")])
	var main_keys := plan.get("main_path_keys", []) as Array
	if main_keys.size() < MIN_MAIN_CONTENT_ROOMS:
		errors.append("main_path_short:%d" % main_keys.size())
	for main_key in main_keys:
		if not room_by_key.has(str(main_key)):
			errors.append("missing_main_room:%s" % main_key)
	var branch_count := int(plan.get("branch_count", 0))
	if branch_count < MIN_BRANCH_COUNT or branch_count > MAX_BRANCH_COUNT:
		errors.append("branch_count:%d" % branch_count)
	if float((plan.get("area_budget", {}) as Dictionary).get("estimated_used_area_m2", INF)) > float((plan.get("area_budget", {}) as Dictionary).get("target_usable_area_m2", 0.0)):
		errors.append("area_budget_exceeded")
	return errors


static func _build_candidate(
	run_seed: int,
	floor_number: int,
	floor_index: int,
	sequence_index: int,
	entry_side: String,
	boss_floor: bool,
	attempt: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ (floor_number << 17) ^ (sequence_index << 9) ^ (attempt * 7919)
	var rooms := _boss_rooms(sequence_index) if boss_floor else _normal_rooms(sequence_index)
	var layout_variant := "boss_east_arena" if boss_floor else (
		"north_ring" if rng.randi_range(0, 1) == 0 else "south_ring"
	)
	if layout_variant == "south_ring":
		for room_value in rooms:
			var room := room_value as Dictionary
			var position := room["position"] as Vector2
			room["position"] = Vector2(position.x, CORE_CENTER.y * 2.0 - position.y)
	_shuffle_content_types(rooms, rng, boss_floor)
	var rotation_steps := _rotation_steps_for_entry(entry_side, boss_floor)
	for room_value in rooms:
		var room := room_value as Dictionary
		room["position"] = _rotate_point(room["position"] as Vector2, rotation_steps)
		if rotation_steps % 2 == 1:
			var dimensions := room["dimensions"] as Vector2
			room["dimensions"] = Vector2(dimensions.y, dimensions.x)
	var main_path_keys: Array[String] = []
	var branch_room_count := 0
	var content_room_count := 0
	var room_role_by_key: Dictionary = {}
	for room_value in rooms:
		var room := room_value as Dictionary
		room_role_by_key[str(room.get("key", ""))] = str(room.get("role", ""))
	for room_value in rooms:
		var room := room_value as Dictionary
		var role := str(room.get("role", ""))
		if role in ["hub", "main", "boss_prep"]:
			main_path_keys.append(str(room["key"]))
		if role == "branch":
			branch_room_count += 1
		if role not in ["stair_entry", "stair_exit"]:
			content_room_count += 1
	var area_budget := _calculate_area_budget(rooms)
	var branch_count := 0
	for room_value in rooms:
		var room := room_value as Dictionary
		if (
			str(room.get("role", "")) == "branch"
			and str(room_role_by_key.get(str(room.get("parent_key", "")), "")) != "branch"
		):
			branch_count += 1
	var layout_identity := "%d:%d:%d:%s:%s:%s" % [
		run_seed, floor_number, attempt, entry_side,
		"boss" if boss_floor else "normal", layout_variant,
	]
	return {
		"layout_id": "floor_%d_%s" % [floor_number, str(abs(hash(layout_identity)))],
		"run_seed": run_seed,
		"floor_number": floor_number,
		"floor_index": floor_index,
		"sequence_index": sequence_index,
		"boss_floor": boss_floor,
		"entry_side": entry_side,
		"exit_side": _opposite_side(entry_side),
		"layout_variant": layout_variant,
		"trigger": "floor_seed_gate",
		"rooms": rooms,
		"main_path_keys": main_path_keys,
		"main_path_content_count": main_path_keys.size(),
		"branch_count": branch_count,
		"branch_room_count": branch_room_count,
		"content_room_count": content_room_count,
		"area_budget": area_budget,
		"room_size_catalog": ROOM_SIZES.duplicate(true),
		"terminal_mode": "boss_down_stair_lobby" if boss_floor else "down_stair_lobby",
	}


static func _normal_rooms(sequence_index: int) -> Array[Dictionary]:
	var prefix := "floor_%02d" % sequence_index
	return [
		_room("entry", "%s_entry" % prefix, "STAIR_LOBBY", "stair_entry", Vector2(27.5, 2.5), SAFE_ROOM_SIZE),
		_room("hub", "%s_hub" % prefix, "COMBAT", "hub", Vector2(30.0, -42.5), ROOM_SIZES.STANDARD, "entry"),
		_room("main_02", "%s_main_02" % prefix, "COMBAT", "main", Vector2(65.0, -42.5), ROOM_SIZES.STANDARD, "hub"),
		_room("main_03", "%s_main_03" % prefix, "EVENT", "main", Vector2(100.0, -42.5), ROOM_SIZES.STANDARD, "main_02"),
		_room("main_04", "%s_main_04" % prefix, "STORAGE", "main", Vector2(100.0, -12.5), ROOM_SIZES.STANDARD, "main_03"),
		_room("main_05", "%s_main_05" % prefix, "SCAVENGE", "main", Vector2(100.0, 37.5), ROOM_SIZES.DEEP, "main_04"),
		_room("main_06", "%s_main_06" % prefix, "COMBAT", "main", Vector2(100.0, 87.5), ROOM_SIZES.STANDARD, "main_05"),
		_room("main_07", "%s_main_07" % prefix, "ELITE", "main", Vector2(65.0, 87.5), ROOM_SIZES.STANDARD, "main_06"),
		_room("main_08", "%s_main_08" % prefix, "TRAP", "main", Vector2(27.5, 87.5), ROOM_SIZES.MEDIUM, "main_07"),
		_room("main_09", "%s_main_09" % prefix, "COMBAT", "main", Vector2(-20.0, 87.5), ROOM_SIZES.WIDE, "main_08"),
		_room("main_10", "%s_main_10" % prefix, "UPGRADE", "main", Vector2(-20.0, 47.5), ROOM_SIZES.STANDARD, "main_09"),
		_room("exit", "%s_exit" % prefix, "STAIR_LOBBY", "stair_exit", Vector2(-22.5, 2.5), SAFE_ROOM_SIZE, "main_10"),
		_room("branch_01", "%s_branch_01" % prefix, "ELITE", "branch", Vector2(100.0, -77.5), ROOM_SIZES.STANDARD, "main_03"),
		_room("branch_02", "%s_branch_02" % prefix, "STORAGE", "branch", Vector2(65.0, -77.5), ROOM_SIZES.STANDARD, "branch_01"),
		_room("branch_03", "%s_branch_03" % prefix, "SCAVENGE", "branch", Vector2(-65.0, 87.5), ROOM_SIZES.LARGE, "main_09"),
		_room("branch_04", "%s_branch_04" % prefix, "EVENT", "branch", Vector2(-105.0, 87.5), ROOM_SIZES.STANDARD, "branch_03"),
	]


static func _boss_rooms(sequence_index: int) -> Array[Dictionary]:
	var prefix := "floor_%02d" % sequence_index
	return [
		_room("entry", "%s_entry" % prefix, "STAIR_LOBBY", "stair_entry", Vector2(-22.5, 2.5), SAFE_ROOM_SIZE),
		_room("hub", "%s_hub" % prefix, "ELITE", "hub", Vector2(-20.0, -42.5), ROOM_SIZES.STANDARD, "entry"),
		_room("main_02", "%s_main_02" % prefix, "COMBAT", "main", Vector2(-55.0, -42.5), ROOM_SIZES.STANDARD, "hub"),
		_room("main_03", "%s_main_03" % prefix, "EVENT", "main", Vector2(-90.0, -42.5), ROOM_SIZES.STANDARD, "main_02"),
		_room("main_04", "%s_main_04" % prefix, "STORAGE", "main", Vector2(-90.0, -77.5), ROOM_SIZES.STANDARD, "main_03"),
		_room("main_05", "%s_main_05" % prefix, "SCAVENGE", "main", Vector2(-55.0, -77.5), ROOM_SIZES.STANDARD, "main_04"),
		_room("main_06", "%s_main_06" % prefix, "COMBAT", "main", Vector2(-20.0, -77.5), ROOM_SIZES.STANDARD, "main_05"),
		_room("main_07", "%s_main_07" % prefix, "TRAP", "main", Vector2(15.0, -77.5), ROOM_SIZES.STANDARD, "main_06"),
		_room("main_08", "%s_main_08" % prefix, "ELITE", "main", Vector2(50.0, -77.5), ROOM_SIZES.STANDARD, "main_07"),
		_room("main_09", "%s_main_09" % prefix, "COMBAT", "main", Vector2(85.0, -77.5), ROOM_SIZES.STANDARD, "main_08"),
		_room("main_10", "%s_main_10" % prefix, "EVENT", "main", Vector2(85.0, -42.5), ROOM_SIZES.STANDARD, "main_09"),
		_room("prep", "%s_boss_prep" % prefix, "UPGRADE", "boss_prep", Vector2(85.0, -7.5), ROOM_SIZES.STANDARD, "main_10"),
		_room("boss", "extraction", "BOSS", "boss", Vector2(80.0, 80.0), ROOM_SIZES.BOSS_ARENA, "prep"),
		# Boss房后仍需一个真实15×15m出口大厅，专用门先从Boss房进入大厅，
		# 再由大厅接入B→B-1楼梯。大厅与Boss西边界共墙，不计入10房内容数。
		_room("exit", "%s_exit" % prefix, "STAIR_LOBBY", "stair_exit", Vector2(27.5, 77.5), SAFE_ROOM_SIZE, "boss"),
		_room("branch_01", "%s_branch_01" % prefix, "EVENT", "branch", Vector2(-90.0, -7.5), ROOM_SIZES.STANDARD, "main_03"),
		_room("branch_02", "%s_branch_02" % prefix, "STORAGE", "branch", Vector2(-90.0, 27.5), ROOM_SIZES.STANDARD, "branch_01"),
		_room("branch_03", "%s_branch_03" % prefix, "SCAVENGE", "branch", Vector2(-20.0, -107.5), ROOM_SIZES.STANDARD, "main_06"),
	]


static func _room(
	key: String,
	id: String,
	type_id: String,
	role: String,
	position: Vector2,
	dimensions: Vector2,
	parent_key := ""
) -> Dictionary:
	return {
		"key": key,
		"id": id,
		"type": type_id,
		"role": role,
		"position": position,
		"dimensions": dimensions,
		"parent_key": parent_key,
	}


static func _shuffle_content_types(rooms: Array[Dictionary], rng: RandomNumberGenerator, boss_floor: bool) -> void:
	var shuffled: Array[String] = []
	for type_id in CONTENT_TYPES:
		shuffled.append(str(type_id))
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = held
	var content_index := 0
	for room in rooms:
		var role := str(room.get("role", ""))
		if role in ["stair_entry", "stair_exit", "boss", "boss_prep"]:
			continue
		room["type"] = shuffled[content_index % shuffled.size()]
		content_index += 1
	if boss_floor:
		for room in rooms:
			if str(room.get("role", "")) == "hub":
				room["type"] = "ELITE"


static func _calculate_area_budget(rooms: Array[Dictionary]) -> Dictionary:
	var total_floor_area := MAP_SIZE_M * MAP_SIZE_M
	var outer_wall_area := MAP_SIZE_M * 4.0 * WALL_THICKNESS_M
	var core_area := CORE_SIZE_M * CORE_SIZE_M
	# 电梯井、双楼梯折返区、楼板洞、门前净空与不可规整角区统一先扣除。
	var stair_and_utility_reserve := 6500.0
	var available_area := total_floor_area - outer_wall_area - core_area - stair_and_utility_reserve
	var room_area := 0.0
	var interior_wall_area := 0.0
	var corridor_area := 0.0
	var room_by_key: Dictionary = {}
	for room in rooms:
		room_by_key[str(room["key"])] = room
		var dimensions := room["dimensions"] as Vector2
		room_area += dimensions.x * dimensions.y
		interior_wall_area += (dimensions.x + dimensions.y) * 2.0 * WALL_THICKNESS_M
	for room in rooms:
		var parent_key := str(room.get("parent_key", ""))
		if parent_key.is_empty() or not room_by_key.has(parent_key):
			continue
		corridor_area += _corridor_length(room_by_key[parent_key] as Dictionary, room) * CORRIDOR_WIDTH_M
	var estimated_used := room_area + interior_wall_area + corridor_area
	var target_usable_area := available_area * TARGET_OCCUPANCY_RATIO
	return {
		"total_floor_area_m2": total_floor_area,
		"outer_wall_area_m2": outer_wall_area,
		"core_area_m2": core_area,
		"stair_corridor_utility_reserve_m2": stair_and_utility_reserve,
		"available_area_m2": available_area,
		"target_occupancy_ratio": TARGET_OCCUPANCY_RATIO,
		"target_usable_area_m2": target_usable_area,
		"reference_content_room_cost_m2": REFERENCE_CONTENT_ROOM_COST_M2,
		"calculated_content_room_target": clampi(
			int(floor(target_usable_area / REFERENCE_CONTENT_ROOM_COST_M2)),
			14,
			16
		),
		"room_area_m2": room_area,
		"interior_wall_area_m2": interior_wall_area,
		"corridor_area_m2": corridor_area,
		"estimated_used_area_m2": estimated_used,
	}


static func _corridor_length(parent: Dictionary, child: Dictionary) -> float:
	var a := parent["position"] as Vector2
	var b := child["position"] as Vector2
	var a_size := parent["dimensions"] as Vector2
	var b_size := child["dimensions"] as Vector2
	if absf(a.x - b.x) >= absf(a.y - b.y):
		return maxf(0.0, absf(a.x - b.x) - (a_size.x + b_size.x) * 0.5)
	return maxf(0.0, absf(a.y - b.y) - (a_size.y + b_size.y) * 0.5)


static func _edge_is_buildable(parent: Dictionary, child: Dictionary) -> bool:
	var a := parent["position"] as Vector2
	var b := child["position"] as Vector2
	var delta := (b - a).abs()
	var direction_is_horizontal := delta.x >= delta.y
	var lateral_offset := delta.y if direction_is_horizontal else delta.x
	if lateral_offset > 5.01:
		return false
	# Boss房和15x15下行楼梯大厅共用一面墙，门洞直接对接，不需要再夹一段
	# 5m走廊。其余房间仍严格要求门外至少5m净距。
	if (
		str(parent.get("role", "")) == "boss"
		and str(child.get("role", "")) == "stair_exit"
	):
		return _corridor_length(parent, child) <= 0.01
	return _corridor_length(parent, child) >= MIN_CORRIDOR_GAP_M - 0.01


static func _room_rect(room: Dictionary) -> Rect2:
	var dimensions := room.get("dimensions", Vector2.ZERO) as Vector2
	return Rect2((room.get("position", Vector2.ZERO) as Vector2) - dimensions * 0.5, dimensions)


static func _rect_contains_rect(container: Rect2, child: Rect2) -> bool:
	return (
		container.has_point(child.position)
		and child.end.x <= container.end.x + 0.01
		and child.end.y <= container.end.y + 0.01
	)


static func _stair_reservation_rect(side: String) -> Rect2:
	var outward := {
		"north": Vector2.UP,
		"south": Vector2.DOWN,
		"west": Vector2.LEFT,
		"east": Vector2.RIGHT,
	}.get(side, Vector2.LEFT) as Vector2
	var tangent := Vector2(outward.y, -outward.x)
	var interface := CORE_CENTER + outward * (CORE_SIZE_M * 0.5)
	var corners: Array[Vector2] = []
	for outward_distance in [0.0, STAIR_RESERVATION_OUTWARD_M]:
		for tangent_distance in [
			-STAIR_RESERVATION_TANGENT_M * 0.10,
			STAIR_RESERVATION_TANGENT_M * 0.90,
		]:
			corners.append(
				interface
				+ outward * float(outward_distance)
				+ tangent * float(tangent_distance)
			)
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


static func _rotation_steps_for_entry(entry_side: String, boss_floor: bool) -> int:
	var base_side := "west" if boss_floor else "east"
	var order := ["north", "east", "south", "west"]
	return posmod(order.find(entry_side) - order.find(base_side), 4)


static func _rotate_point(point: Vector2, rotation_steps: int) -> Vector2:
	var result := point - CORE_CENTER
	for _step in range(posmod(rotation_steps, 4)):
		result = Vector2(-result.y, result.x)
	return result + CORE_CENTER


static func _opposite_side(side: String) -> String:
	return {"north": "south", "south": "north", "east": "west", "west": "east"}.get(side, "west")
