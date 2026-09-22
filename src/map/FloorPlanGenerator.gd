class_name FloorPlanGenerator
extends RefCounted
## 纯数据楼层规划器。输入种子与楼层语义，输出可复现的房间树、面积预算和验收结果。
## 本类不创建 Node，不依赖场景树，便于存档恢复、批量性质测试和独立维护。

const LEVEL_AREA_BUDGET := preload("res://src/map/LevelAreaBudget.gd")
const LEVEL_PLAN_LOADER := preload("res://src/map/LevelPlanLoader.gd")
## 显式 preload 而非依赖 class_name 全局：新增脚本在 global_script_class_cache.cfg
## 刷新前用全局名会直接 parse error（headless 门禁会静默红掉）。
const LEVEL_PLAN_VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")

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

## 功能房 role 全集 —— 这些房间的身份由 role 决定，不是「内容类型」，不参与内容洗牌、
## 不计入 content_room_count。它们的 type 缺省值见 `_default_type_for_role`。
## 断言方（tests/verification/verify_level_plan_design_source.gd）按同一张表逐值核对。
const FUNCTIONAL_ROLES := ["stair_entry", "stair_exit", "extraction", "boss", "boss_prep"]

## —— 远征关卡01（独立单层关卡）——
## 一张入口安全屋（15×15，沿用塔楼安全房契约）+ 5 个 25×25 内容房（编号 01-05）
## + 末尾一间 25×25 撤离房。单层、无楼梯、无电梯，撤离即终局。
## 尺寸与"内容房最小 30×25m"的塔楼规则无关：远征关卡单列房型表（见 05.2 §7.4）。
const EXPEDITION_ROOM_SIZE := Vector2(25.0, 25.0)
const EXPEDITION_ROOM_COUNT := 5
## 5 个内容房的房型池：固定含 2 间战斗房（保证刷怪）与 1 间可搜索房，
## 顺序由种子洗牌 —— 这就是"受约束随机"里的随机部分。
const EXPEDITION_CONTENT_TYPES := ["COMBAT", "COMBAT", "SCAVENGE", "STORAGE", "EVENT"]
## 房间中心必须落在 2.5 + 5k 上，TowerGeometry3D.snap_component_axis 才是恒等映射。
## 15×15 与 25×25 同属该格点集，35m 步长 = 25m 房 + 10m 门间净距。
const EXPEDITION_GRID_STEP_M := 35.0
const EXPEDITION_GRID_ORIGIN_M := 2.5


static func generate_expedition(request: Dictionary) -> Dictionary:
	# 单层受约束随机：模板固定（蛇形主通道），随机量只有两个 ——
	# 整图绕入口安全屋的 0/90/180/270 旋转（可叠加 Z 轴镜像）与 5 间房的房型顺序。
	# 两者都不改变"每间房仍与前一间共轴、门间净距 10m"这一可建造约束。
	var run_seed := int(request.get("run_seed", 1))
	var expedition_id := str(request.get("expedition_id", "expedition_01"))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ 0x45585031
	var rooms := _expedition_rooms()
	var rotation_steps := rng.randi_range(0, 3)
	var mirror_z := rng.randi_range(0, 1) == 1
	for room_value in rooms:
		var room := room_value as Dictionary
		var position := room["position"] as Vector2
		if mirror_z:
			position = Vector2(position.x, CORE_CENTER.y * 2.0 - position.y)
		room["position"] = _rotate_point(position, rotation_steps)
	_shuffle_expedition_types(rooms, rng)
	var main_path_keys: Array[String] = []
	for room_value in rooms:
		var room := room_value as Dictionary
		if str(room.get("role", "")) == "main":
			main_path_keys.append(str(room["key"]))
	var layout_variant := "expedition_rot_%d%s" % [rotation_steps, "_mirror" if mirror_z else ""]
	var plan := {
		"layout_id": "expedition_%s_%d" % [
			expedition_id, abs(hash("%d:%s" % [run_seed, layout_variant])),
		],
		"run_seed": run_seed,
		"expedition_id": expedition_id,
		"mode": "expedition",
		"floor_number": 0,
		"floor_index": 0,
		"entry_side": "east",
		"exit_side": "west",
		"layout_variant": layout_variant,
		"trigger": "expedition_bootstrap",
		"rooms": rooms,
		"main_path_keys": main_path_keys,
		"main_path_content_count": main_path_keys.size(),
		"content_room_count": EXPEDITION_ROOM_COUNT,
		"branch_count": 0,
		"branch_room_count": 0,
		"room_size_catalog": {"EXPEDITION_STANDARD": EXPEDITION_ROOM_SIZE},
		"terminal_mode": "extraction_room",
		# 契约一致性：远征的房间由代码程序化生成（房表不含 reward_plan），故投影恒为空数组。
		# 仍然落键 —— 消费方不必区分"没有这个键"与"没有槽位"。
		"reward_slots": reward_slots_from_rooms(rooms),
	}
	var errors := validate_expedition(plan)
	plan["valid"] = errors.is_empty()
	plan["validation_errors"] = errors
	plan["attempt_count"] = 1
	plan["used_fallback"] = false
	return plan


## —— 单间房的「设计源 → 运行时计划」透传（唯一登记点）——
##
## 房间级**可选**字段只在此处登记一次：`enemy_spawn_plan`（刷怪计划）、
## `boss_content_id`（首领指派）、`reward_plan`（统一掉落计划）。两处消费方
## （`generate_from_level_plan` 与验收脚本）都走本函数，禁止各自复刻字段表。
##
## 为什么抽成独立函数：这些字段**当前没有任何关卡在数据里写**，端到端断言
## 因此会退化成空跑（0 个样本、静默通过）。抽出来之后可以用手写 patch 直接
## 驱动本函数，把「透传不漏字段」钉成一条真会失败的断言。
## 同时它与 `LevelPlanLoader.normalize_floor` 的白名单是一对：那边漏登记
## 字段会被静默丢弃（源头），这边漏登记会被静默丢弃（出口），两头都要有闸。
static func room_from_source(src: Dictionary) -> Dictionary:
	var role := str(src.get("role", "main"))
	# 运行时房间 ID：优先 legacy_room_id，使既有存档的 room_progress 索引不变；
	# 新关卡没有 legacy 字段时才用 05.2 §7.1 的新规则 room_id。
	var runtime_id := str(src.get("legacy_room_id", ""))
	if runtime_id.is_empty():
		runtime_id = str(src.get("room_id", ""))
	var content_type := str(src.get("content_type", ""))
	if content_type.is_empty():
		# 功能性 role 的缺省 type，口径与内置房表逐值一致（见 _default_type_for_role）。
		# 设计源显式写了 content_type 时以设计源为准（钉死优先）。
		content_type = _default_type_for_role(role)
	return {
		"key": str(src.get("key", "")),
		"id": runtime_id,
		"type": content_type,
		"role": role,
		"position": src.get("center", Vector2.ZERO) as Vector2,
		"dimensions": src.get("size", Vector2.ZERO) as Vector2,
		"parent_key": str(src.get("parent_key", "")),
		# 房间级刷怪计划（设计源覆盖）。空字典 = 该房走全局公式。
		# 与 content_type 同样属于「设计源钉死优先」的字段，本层只透传不解释。
		"enemy_spawn_plan": (src.get("enemy_spawn_plan", {}) as Dictionary).duplicate(true),
		# 房间级首领指派（仅 Boss 房有效）。空串 = 不指派：
		# 塔楼按层号取名册条目，单层关卡则**不出 Boss**（口径见 BossContentCatalog.resolve_profile）。
		# 只透传不解释；本字段**不进 layout_id**，故改它不会让既有存档失配。
		"boss_content_id": str(src.get("boss_content_id", "")),
		# 房间级统一掉落计划（04 §22.7 覆盖链：房间 > 关卡 > 怪物表 > 全局默认）。
		# 空字典 = 本房在该 trigger 上不覆盖，逐级回退。**不进 layout_id**：
		# 掉落是内容不是几何，改它不得让既有存档的房间进度失配。
		"reward_plan": (src.get("reward_plan", {}) as Dictionary).duplicate(true),
	}


## —— 房间级掉落计划 → 运行时 `reward_slots[]` 投影（05 §11）——
##
## 每条 = `{slot_id, room_id, trigger, spec_id, ref}`：
##   · `slot_id` 稳定 = `"<room_id>:<trigger>"` —— 房间与触发唯一确定一条；
##   · `room_id` 取**运行时房间 ID**（`room_from_source` 已按 legacy 优先解析过），
##     不是设计源的 `key` —— 运行时只认 room_id；
##   · `spec_id` 是命名规格引用（槽位用命名规格时非空，其余写法为空串）；
##   · `ref` 是**设计源原文**（`{spec_id}` / `{entries}` / `{pool_id}` 三种写法之一）。
##
## 为什么必须带 `ref` 而不是只留 `spec_id`：槽位允许写 `{pool_id}` 简写与内联
## `{entries}`，这两种写法**压根没有 spec_id**。只投影 spec_id 会让它们在投影
## 这一步静默丢内容（05 §11 的列定义只列了 spec_id，此处按实现需要补 ref）。
##
## 本函数是**纯投影**：不校验、不解释、不重算。合法性由 `LevelPlanValidator` 保证，
## 解析由 `RewardService` 保证。它不进 `layout_id`（指纹见 `_data_driven_layout_id`，
## 那是显式白名单，不含本字段）。
static func reward_slots_from_rooms(rooms: Array) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for value in rooms:
		var room := value as Dictionary
		var room_id := str(room.get("id", ""))
		if room_id.is_empty():
			continue
		var plan := room.get("reward_plan", {}) as Dictionary
		if plan.is_empty():
			continue
		for trigger_value in plan.keys():
			var ref_value: Variant = plan[trigger_value]
			if not (ref_value is Dictionary):
				continue
			var ref := ref_value as Dictionary
			slots.append({
				"slot_id": "%s:%s" % [room_id, str(trigger_value)],
				"room_id": room_id,
				"trigger": str(trigger_value),
				"spec_id": str(ref.get("spec_id", "")),
				"ref": ref.duplicate(true),
			})
	slots.sort_custom(func(a, b): return str(a["slot_id"]) < str(b["slot_id"]))
	return slots


## —— 数据驱动路径（依据 05.2 §3 / §8 S3）——
##
## 读 L1/L2/L3 设计源，产出与 generate() 同形的 plan 字典，供
## TowerDescent3D._commit_floor_bundle() 消费。
##
## 与内置房表路径并存，不是替换：登记了设计源的关卡走本路径，
## 未登记的关卡行为一字不变（因此对既有存档零影响）。
##
## 等价性声明（重要）：本路径保证 **几何、拓扑、运行时房间 ID** 与设计源一致；
## **不宣称** 内容类型分配与旧 `_shuffle_content_types` 逐位一致 —— 设计源
## 钉死了 `content_type` 就用钉死值，留空则用数据驱动种子洗牌（05.2 §5 第 5 项
## 「内容类型分配保留现行行为」指的是随机性保留，不是序列逐位复现）。
##
## 设计源缺失或校验不通过时返回 {}（空字典），由调用方决定拒绝进入还是回退内置房表。
static func generate_from_level_plan(level_id: String, floor_number: int, run_seed: int) -> Dictionary:
	var level_plan := LEVEL_PLAN_LOADER.load_level_plan(level_id)
	if level_plan.is_empty():
		return {}
	var normalized := LEVEL_PLAN_LOADER.normalize_floor(level_id, floor_number)
	if normalized.is_empty():
		return {}
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LEVEL_PLAN_LOADER.load_room_templates(level_id)
	var errors := LEVEL_PLAN_VALIDATOR.validate_floor(level_id, floor_number, policy, templates)
	var mode := str(normalized.get("mode", "authored"))
	var boss_floor := false
	for value in normalized.get("rooms", []):
		var src := value as Dictionary
		if str(src.get("role", "")) == "boss":
			boss_floor = true
	var rooms: Array[Dictionary] = []
	for value in normalized.get("rooms", []):
		rooms.append(room_from_source(value as Dictionary))
	var rng := RandomNumberGenerator.new()
	# abci/absi 返回 int：^ 的左右操作数必须都是 int，absf 会让此处 parse error。
	rng.seed = run_seed ^ absi(str(level_id).hash()) ^ (floor_number << 17)
	_assign_content_types_data_driven(rooms, rng, boss_floor, policy)
	var main_path: Array[String] = []
	for value in normalized.get("main_path", []):
		main_path.append(str(value))
	var branch_count := 0
	var branch_room_count := 0
	var content_room_count := 0
	var role_by_key: Dictionary = {}
	for room in rooms:
		role_by_key[str(room["key"])] = str(room["role"])
	for room in rooms:
		var role := str(room["role"])
		if role == "branch":
			branch_room_count += 1
			if str(role_by_key.get(str(room["parent_key"]), "")) != "branch":
				branch_count += 1
		# 内容房计数排除全部功能房：入口 / 出口楼梯厅 / 撤离房 / Boss / Boss 前厅
		# 都不是内容房。远征内置路径硬编码 EXPEDITION_ROOM_COUNT=5（7 房减 entry 与
		# extraction），这里逐值对齐；此前漏排 extraction 会算出 6。
		if not role in FUNCTIONAL_ROLES:
			content_room_count += 1
	var terminal_mode := "down_stair_lobby"
	for room in rooms:
		if str(room["role"]) == "extraction":
			terminal_mode = "extraction_room"
			break
	if terminal_mode == "down_stair_lobby" and boss_floor:
		terminal_mode = "boss_down_stair_lobby"
	var catalog: Dictionary = {}
	for room in rooms:
		var dimensions := room["dimensions"] as Vector2
		catalog[_size_catalog_key(dimensions)] = dimensions
	var entry_side := str(normalized.get("entry_side", "east"))
	var plan := {
		"layout_id": _data_driven_layout_id(level_id, floor_number, normalized, mode, run_seed),
		"run_seed": run_seed,
		"level_id": level_id,
		"mode": mode,
		"floor_number": int(normalized.get("floor_number", floor_number)),
		"floor_index": int(normalized.get("floor_index", 0)),
		"sequence_index": int(normalized.get("sequence_index", 0)),
		"boss_floor": boss_floor,
		"entry_side": entry_side,
		"exit_side": str(normalized.get("exit_side", _opposite_side(entry_side))),
		"layout_variant": "data_driven_%s" % str(normalized.get("mode", "authored")),
		"trigger": "level_plan_data",
		"rooms": rooms,
		"main_path_keys": main_path,
		"main_path_content_count": main_path.size(),
		"branch_count": branch_count,
		"branch_room_count": branch_room_count,
		"content_room_count": content_room_count,
		"area_budget": _calculate_area_budget(rooms),
		"room_size_catalog": catalog,
		"terminal_mode": terminal_mode,
		# 掉落调度投影（05 §11）。本路径的设计源房间可写 reward_plan，投影出真槽位。
		"reward_slots": reward_slots_from_rooms(rooms),
	}
	plan["valid"] = errors.is_empty()
	plan["validation_errors"] = errors
	plan["attempt_count"] = 1
	plan["used_fallback"] = false
	return plan


## 数据驱动 layout_id（05.2 §7.2）：canonical 只含语义字段，排除时间戳与哈希顺序。
## authored 模式几何与种子无关，故 canonical 不含 run_seed；
## constrained 模式随机与种子相关，必须含 —— 否则两局不同图会撞同一个 layout_id。
static func _data_driven_layout_id(
	level_id: String, floor_number: int, normalized: Dictionary, mode: String, run_seed: int
) -> String:
	var rows: Array = []
	for value in normalized.get("rooms", []):
		var room := value as Dictionary
		var center := room.get("center", Vector2.ZERO) as Vector2
		var size := room.get("size", Vector2.ZERO) as Vector2
		var port_rows: Array = []
		for port_value in room.get("ports", []):
			var port := port_value as Dictionary
			port_rows.append([
				str(port.get("target", "")), str(port.get("side", "")),
				snappedf(float(port.get("lane_m", 0.0)), 0.001),
			])
		port_rows.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
		rows.append({
			"key": str(room.get("key", "")),
			"template_id": str(room.get("template_id", "")),
			"template_variant": str(room.get("template_variant", "")),
			"center": [snappedf(center.x, 0.001), snappedf(center.y, 0.001)],
			"size": [snappedf(size.x, 0.001), snappedf(size.y, 0.001)],
			"rotation_deg": snappedf(float(room.get("rotation_deg", 0.0)), 0.001),
			"ports": port_rows,
		})
	rows.sort_custom(func(a, b): return str(a["key"]) < str(b["key"]))
	var canonical := {
		"level_id": level_id,
		"floor_number": floor_number,
		"floor_index": int(normalized.get("floor_index", 0)),
		"entry_side": str(normalized.get("entry_side", "")),
		"rooms": rows,
	}
	if mode == "constrained":
		canonical["run_seed"] = run_seed
	return "f%02d_%s" % [floor_number, JSON.stringify(canonical, "", true).sha256_text().substr(0, 16)]


## 远征关卡专用校验：不使用塔楼的 10 房/2-5 支线/30×25 最小内容房口径。
static func validate_expedition(plan: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rooms := plan.get("rooms", []) as Array
	var room_by_key: Dictionary = {}
	var map_rect := Rect2(
		Vector2(-MAP_SIZE_M * 0.5, -MAP_SIZE_M * 0.5),
		Vector2(MAP_SIZE_M, MAP_SIZE_M)
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
		var expected := SAFE_ROOM_SIZE if role == "stair_entry" else EXPEDITION_ROOM_SIZE
		if not dimensions.is_equal_approx(expected):
			errors.append("expedition_room_size:%s:%s" % [key, dimensions])
		if not _rect_contains_rect(map_rect, _room_rect(room)):
			errors.append("outside_floor_bounds:%s" % key)
	for first_index in range(rooms.size()):
		var first := rooms[first_index] as Dictionary
		for second_index in range(first_index + 1, rooms.size()):
			var second := rooms[second_index] as Dictionary
			if _room_rect(first).intersection(_room_rect(second)).get_area() > 0.01:
				errors.append("room_overlap:%s:%s" % [first.get("key", ""), second.get("key", "")])
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
	if main_keys.size() != EXPEDITION_ROOM_COUNT:
		errors.append("expedition_main_path_count:%d" % main_keys.size())
	for main_key in main_keys:
		if not room_by_key.has(str(main_key)):
			errors.append("missing_main_room:%s" % main_key)
	var extraction_room := room_by_key.get("extraction", {}) as Dictionary
	if extraction_room.is_empty():
		errors.append("missing_extraction_room")
	elif not main_keys.is_empty():
		var last_key := str(main_keys[main_keys.size() - 1])
		if str(extraction_room.get("parent_key", "")) != last_key:
			errors.append("extraction_not_after_last_room")
	return errors


static func _expedition_rooms() -> Array[Dictionary]:
	# 蛇形主通道：入口 → 01 → 02 → 03 → 04 → 05 → 撤离房。
	# 所有中心坐标都是 2.5 + 35k，坐标吸附是恒等映射，房间记录位置即规划位置。
	var origin := EXPEDITION_GRID_ORIGIN_M
	var step := EXPEDITION_GRID_STEP_M
	var near := origin + step
	var mid := origin - step
	var far := origin - step * 2.0
	var tail := origin - step * 3.0
	return [
		_room("entry", "start", "STAIR_LOBBY", "stair_entry", Vector2(origin, origin), SAFE_ROOM_SIZE),
		_room("room_01", "room_01", "COMBAT", "main", Vector2(origin, mid), EXPEDITION_ROOM_SIZE, "entry"),
		_room("room_02", "room_02", "COMBAT", "main", Vector2(near, mid), EXPEDITION_ROOM_SIZE, "room_01"),
		_room("room_03", "room_03", "COMBAT", "main", Vector2(near, far), EXPEDITION_ROOM_SIZE, "room_02"),
		_room("room_04", "room_04", "COMBAT", "main", Vector2(origin, far), EXPEDITION_ROOM_SIZE, "room_03"),
		_room("room_05", "room_05", "COMBAT", "main", Vector2(origin, tail), EXPEDITION_ROOM_SIZE, "room_04"),
		_room(
			"extraction", "extraction", "EXTRACTION", "extraction",
			Vector2(near, tail), EXPEDITION_ROOM_SIZE, "room_05"
		),
	]


static func _shuffle_expedition_types(
	rooms: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	var shuffled: Array[String] = []
	for type_id in EXPEDITION_CONTENT_TYPES:
		shuffled.append(str(type_id))
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = held
	var content_index := 0
	for room in rooms:
		if str(room.get("role", "")) != "main":
			continue
		room["type"] = shuffled[content_index % shuffled.size()]
		content_index += 1


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
		# 同上：内置房表路径的房间无 reward_plan，投影恒为空数组，仍落键保持契约一致。
		"reward_slots": reward_slots_from_rooms(rooms),
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
	# 95F保留历史稳定ID extraction；后续Boss必须使用逐层唯一ID，否则90/85F
	# 会错误复用95F节点并把跨层走廊连到旧竞技场。
	var boss_room_id := "extraction" if sequence_index == 4 else "%s_boss" % prefix
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
		_room("boss", boss_room_id, "BOSS", "boss", Vector2(80.0, 80.0), ROOM_SIZES.BOSS_ARENA, "prep"),
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


## 数据驱动路径是否对该关卡启用（05.2 §8 S3 接缝）。
##
## **默认关闭**，两个条件必须同时满足：
##   1. 该关卡已提供设计源（level_plan.json 可读且 schema 正确）；
##   2. L1 `generation_policy.runtime_enabled == true`。
##
## 为什么默认关：把既有关卡切到数据驱动会改变 `layout_id`，而存档按
## `floor_layout_ids[floor_index]` 比对，不一致直接整档恢复失败（05.2 §7.2）。
## 05.2 §9 的 D4（存档兼容策略）尚未裁决，相关条款不得作为施工依据 —— 因此
## 本接缝先建好但不接通任何关卡，等 D4 裁决 + 新旧 layout_id 等价性证明落地后再逐个开。
static func data_driven_enabled(level_id: String) -> bool:
	var level_plan := LEVEL_PLAN_LOADER.load_level_plan(level_id)
	if level_plan.is_empty():
		return false
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	return bool(policy.get("runtime_enabled", false))


## 数据驱动路径的内容类型分配（05.2 §5 第 5 项「保留现行随机行为」）。
##
## 与 `_shuffle_content_types` 的三点差异，都是设计源路径必需：
##   1. **设计源钉死优先**：L2 写了 `content_type` 就该生效，不能被洗牌覆盖。
##      钉死的房间不消耗池子序号，未钉死的房间按声明顺序依次取池内下一项。
##   2. **池子可声明**：`generation_policy.content_type_pool` 缺省时才用塔楼 CONTENT_TYPES。
##      远征关卡的池子是 5 项（COMBAT×2/SCAVENGE/STORAGE/EVENT），与塔楼 8 项不同。
##   3. **撤离房不参与**：role `extraction` 是终局房，不是内容房，不得被分配内容类型
##      （内置路径靠「只给 role==main 赋值」保证，本处显式列出）。
## 功能性 role 的缺省 type —— 与内置房表（`generate()` / `generate_expedition()` 里的
## `_room()` 写死值）逐值一致。
##
## 为什么必须有：这几个不是「内容类型」，运行时靠它们认出这是入口安全房 / 出口楼梯厅 /
## 撤离房，从而决定刷什么功能（信标、撤离点）。设计源不写 content_type 时若留空，
## 这些房间会失去身份 —— 实测数据驱动路径曾把 entry/extraction 的 type 产成空串。
static func _default_type_for_role(role: String) -> String:
	match role:
		"stair_entry", "stair_exit":
			return "STAIR_LOBBY"
		"extraction":
			return "EXTRACTION"
		"boss":
			return "BOSS"
		"boss_prep":
			return "UPGRADE"
		_:
			return ""


## `room_size_catalog` 的键：把 "25.0 x 25.0" 写成 "25x25"，小数（如 27.5）原样保留。
## 不用 `"%g" %`：GDScript 的 `%` 格式化**不支持 %g**，会抛
## "String formatting error: unsupported format character"（实测每房一次引擎 ERROR）。
static func _size_catalog_key(dimensions: Vector2) -> String:
	return "%sx%s" % [_trim_trailing_zero(dimensions.x), _trim_trailing_zero(dimensions.y)]


static func _trim_trailing_zero(value: float) -> String:
	var text := "%.3f" % value
	text = text.rstrip("0").rstrip(".")
	if text.is_empty() or text == "-":
		return "0"
	return text


static func _assign_content_types_data_driven(
	rooms: Array[Dictionary], rng: RandomNumberGenerator, boss_floor: bool, policy: Dictionary
) -> void:
	var pool_value: Variant = policy.get("content_type_pool", [])
	var pool: Array[String] = []
	if pool_value is Array and not (pool_value as Array).is_empty():
		for type_id in (pool_value as Array):
			pool.append(str(type_id))
	else:
		for type_id in CONTENT_TYPES:
			pool.append(str(type_id))
	if pool.is_empty():
		return
	var shuffled: Array[String] = []
	for type_id in pool:
		shuffled.append(type_id)
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = held
	var content_index := 0
	for room in rooms:
		var role := str(room.get("role", ""))
		# boss 恒 BOSS：玩法不变量（Boss 层必须能识别 Boss 房），与内置写死口径一致。
		if role == "boss":
			room["type"] = "BOSS"
			continue
		# 其余功能性 role 保留 _default_type_for_role 给的缺省值，不参与内容洗牌
		# （内置 _shuffle_content_types 的 skip 列表为 stair_entry/stair_exit/boss/boss_prep，
		#  本处另加 extraction —— 它是终局房，不是内容房）。
		if role in ["stair_entry", "stair_exit", "extraction", "boss_prep"]:
			continue
		if not str(room.get("type", "")).is_empty():
			continue
		room["type"] = shuffled[content_index % shuffled.size()]
		content_index += 1
	if boss_floor:
		for room in rooms:
			if str(room.get("role", "")) == "hub":
				room["type"] = "ELITE"


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
	# 公式已抽到 LevelAreaBudget 唯一实现（校验器与加载路径共用，避免第三份）。
	# 本处保留同名转发，调用点与返回键完全不变。
	return LEVEL_AREA_BUDGET.calculate(rooms)


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
