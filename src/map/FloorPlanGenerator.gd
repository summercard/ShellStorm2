class_name FloorPlanGenerator
extends RefCounted
## 纯数据楼层规划器。输入种子与楼层语义，输出可复现的房间树、面积预算和验收结果。
## 本类不创建 Node，不依赖场景树，便于存档恢复、批量性质测试和独立维护。

const LEVEL_AREA_BUDGET := preload("res://src/map/LevelAreaBudget.gd")
const LEVEL_PLAN_LOADER := preload("res://src/map/LevelPlanLoader.gd")
## 显式 preload 而非依赖 class_name 全局：新增脚本在 global_script_class_cache.cfg
## 刷新前用全局名会直接 parse error（headless 门禁会静默红掉）。
const LEVEL_PLAN_VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
## 显式 preload：净距与门槽口径必须与校验器/加载器同源，不得在本类里重算一遍。
const ROOM_DOOR_LANE := preload("res://src/map/RoomDoorLane.gd")
## 5m 通用壳体组合器（纯 RefCounted）。第 4 环在这里：本项目**唯一**的
## 「房间几何 → 5 类通用件实例清单」实现，设计期 dump 脚本与运行时共用同一份。
const ROOM_SHELL_LAYOUT_BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")
## Boss 房 6 件专属件的摆位源（真源）。通用壳体件由组合器按每局现算的几何产出，
## 这 6 件是**设计死件**：在源竞技场里相对房间中心定死、与版图无关，只有坐标搬运。
const BOSS_LAYOUT_SOURCE_PATH := (
	"res://assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002/"
	+ "boss_room_50x40_v002.layout.json"
)

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
## `boss_content_id`（首领指派）、`reward_plan`（统一掉落计划）、
## `authored_layout_*`（授权布局壳体，区块00 / 远征01）。两处消费方
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
		# —— 授权布局壳体（区块00 / 远征01）——
		# 整房 5m 组件实例清单（房间局部坐标）。与上列字段一样「设计源钉死优先」：
		# 本层只透传，不解释 slot_role、不重算门位。声明点只在房表；
		# 消费方 DungeonRoom3D._build_authored_layout_shell() 按 slot_role 分派。
		# 缺省 false ⇒ 未接管的房间一个字段都不多，行为逐字不变。
		"authored_layout_shell": bool(src.get("authored_layout_shell", false)),
		"authored_layout_asset_id": str(src.get("authored_layout_asset_id", "")),
		"authored_layout_version": str(src.get("authored_layout_version", "")),
		"authored_layout_room_id": str(src.get("authored_layout_room_id", "")),
		"authored_layout_peaceful": bool(src.get("authored_layout_peaceful", false)),
		"authored_layout_instances": (
			src.get("authored_layout_instances", []) as Array
		).duplicate(true),
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
	var mode := str(normalized.get("mode", "authored"))
	# —— mode = "constrained"：几何由「蓝图（L2 的房表/主路/支线挂法）+ 种子」现算 ——
	# L2 里存的那一份房表此时只承担两件事：拓扑蓝图（key / role / parent_key）与
	# 「生成失败时的兜底样例」。这样做的理由见 `_generate_constrained_floor` 头注释。
	var used_fallback := false
	var floor_source := normalized
	if mode == "constrained":
		var generated := _generate_constrained_floor(
			level_id, floor_number, run_seed, normalized, policy, templates
		)
		if generated.is_empty():
			used_fallback = true
		else:
			floor_source = generated
	# 校验必须打在「真正会用到的几何」上：constrained 时是生成结果，不是文件里的样例。
	var errors := LEVEL_PLAN_VALIDATOR.validate_normalized(
		level_id, floor_number, floor_source, policy, templates
	)
	var boss_floor := false
	for value in floor_source.get("rooms", []):
		var src := value as Dictionary
		if str(src.get("role", "")) == "boss":
			boss_floor = true
	var rooms: Array[Dictionary] = []
	for value in floor_source.get("rooms", []):
		rooms.append(room_from_source(value as Dictionary))
	var rng := RandomNumberGenerator.new()
	# abci/absi 返回 int：^ 的左右操作数必须都是 int，absf 会让此处 parse error。
	rng.seed = run_seed ^ absi(str(level_id).hash()) ^ (floor_number << 17)
	_assign_content_types_data_driven(rooms, rng, boss_floor, policy)
	var main_path: Array[String] = []
	for value in floor_source.get("main_path", []):
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
	var entry_side := str(floor_source.get("entry_side", "east"))
	var plan := {
		"layout_id": _data_driven_layout_id(level_id, floor_number, floor_source, mode, run_seed),
		"run_seed": run_seed,
		"level_id": level_id,
		"mode": mode,
		"floor_number": int(floor_source.get("floor_number", floor_number)),
		"floor_index": int(floor_source.get("floor_index", 0)),
		"sequence_index": int(floor_source.get("sequence_index", 0)),
		"boss_floor": boss_floor,
		"entry_side": entry_side,
		"exit_side": str(floor_source.get("exit_side", _opposite_side(entry_side))),
		"layout_variant": "data_driven_%s" % mode,
		"trigger": "level_plan_data",
		"rooms": rooms,
		"main_path_keys": main_path,
		"main_path_content_count": main_path.size(),
		"branch_count": branch_count,
		"branch_room_count": branch_room_count,
		"content_room_count": content_room_count,
		"area_budget": _calculate_area_budget(rooms, policy),
		"room_size_catalog": catalog,
		"terminal_mode": terminal_mode,
		# 掉落调度投影（05 §11）。本路径的设计源房间可写 reward_plan，投影出真槽位。
		"reward_slots": reward_slots_from_rooms(rooms),
	}
	plan["valid"] = errors.is_empty()
	plan["validation_errors"] = errors
	plan["attempt_count"] = 1
	plan["used_fallback"] = used_fallback
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


## —— mode = "constrained"：按种子现算几何（远征关卡01）——
##
## 为什么需要：远征是肉鸽式单层行动，**每局的版图应当不一样**（主路 6 间内容房的
## 房型顺序随机、4 间支线随机选型），但随机只能发生在硬约束之内 —— 门槽、5m 模数、
## 父子共轴、房间互斥这些一条都不能破。故这里不写"自由布局"，而写一个
## **贪心自避走（self-avoiding walk）**：
##   · 主路一线到底：safe → room_01…room_06 → boss → extraction；
##   · 每间新房**贴着父房**摆（4 个方向里挑第一个不撞的）⇒ 父子边恒为墙贴墙
##     （净距 0，逐条进 `edge_policy` 白名单），不需要过渡走廊；
##   · 支线 4 间挂在主路中间那 4 间上，同样贴墙（房表里的 `parent_key` 决定挂法）；
##   · 贴墙位移 = 两边半尺寸之和，从已吸附的原点累加 ⇒ 尺寸/中心天然落在 5m 模数上。
## 摆不下（越界 / 撞满 / 包围盒超 250）就换一份房型重试；重试全败则由调用方回退到
## L2 里存的那份样例（`used_fallback = true`），保证任何种子都能进图。
## 生成重试上限：每次重试换一份「房型抽取」再摆一次。
## 摆位已改为带回溯的搜索（见 `_place_constrained_slots`），单次尝试成功率≈100%，
## 故本值只作极端兜底，取小值以免个别种子把时间吃光。
const CONSTRAINED_MAX_ATTEMPTS := 12
## 单次尝试内回溯搜索的节点预算。DFS 一旦找到解立刻返回，正常情形只需百来个节点；
## 打满预算意味着「这份房型组合真的摆不下」，及早放弃、换一份房型重抽更划算。
const CONSTRAINED_SEARCH_BUDGET := 3000
## 每层最多展开几个候选位。**必须截断**：同一面墙常有多个横向候选，若不截断，
## 分支因子会到十几，失败时 DFS 的搜索空间呈指数爆炸（实测：不截断时平均耗时
## 542 ms、最慢 2.98 s —— 进图会明显卡顿）。截断后好候选仍在最前（按「正对优先、
## 离场地中心近优先」排序），成功率不受影响。
const CONSTRAINED_BRANCH_LIMIT := 6
const CONSTRAINED_EPS := 0.01


static func _generate_constrained_floor(
	level_id: String,
	floor_number: int,
	run_seed: int,
	blueprint: Dictionary,
	policy: Dictionary,
	templates: Dictionary
) -> Dictionary:
	if (blueprint.get("rooms", []) as Array).is_empty() or templates.is_empty():
		return {}
	for attempt in range(CONSTRAINED_MAX_ATTEMPTS):
		var rng := RandomNumberGenerator.new()
		rng.seed = (
			run_seed
			^ absi(str(level_id).hash())
			^ (floor_number << 17)
			^ (attempt * 2654435761)
		)
		var slots := _constrained_slots(blueprint, policy, templates, rng)
		if slots.is_empty():
			continue
		var placed := _place_constrained_slots(slots, rng)
		if placed.is_empty():
			continue
		return _constrained_floor_from(blueprint, floor_number, placed, slots, policy, templates)
	return {}


## 蓝图 + 模板池 → 有序「槽位表」。每项 = 一间房用哪个模板、多大、挂谁。
## 拓扑（key / role / parent_key / 主路顺序）完全照抄 L2 蓝图，本函数只决定**房型**。
static func _constrained_slots(
	blueprint: Dictionary, policy: Dictionary, templates: Dictionary, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var raw_rooms := blueprint.get("rooms", []) as Array
	var by_key: Dictionary = {}
	for value in raw_rooms:
		var raw := value as Dictionary
		by_key[str(raw.get("key", ""))] = raw
	if by_key.is_empty():
		return []
	# —— 主路顺序：入口 → main_path → Boss → 撤离 ——
	var chain: Array[String] = []
	var entry_key := _first_key_with_role(raw_rooms, "stair_entry")
	if not entry_key.is_empty():
		chain.append(entry_key)
	for value in blueprint.get("main_path", []):
		var key := str(value)
		if by_key.has(key) and not chain.has(key):
			chain.append(key)
	for role in ["boss", "extraction"]:
		var key := _first_key_with_role(raw_rooms, role)
		if not key.is_empty() and not chain.has(key):
			chain.append(key)
	# —— 支线：按 L2 房表顺序（挂法由 L2 的 parent_key 决定）——
	var branch_keys: Array[String] = []
	for value in raw_rooms:
		var raw := value as Dictionary
		var key := str(raw.get("key", ""))
		if str(raw.get("role", "")) == "branch" and not branch_keys.has(key):
			branch_keys.append(key)
	# —— 内容房模板池：优先读 policy，缺省取「全部 COMMON_ROOM 模板」——
	var pool: Array[String] = []
	for value in policy.get("content_template_pool", []):
		var template_id := str(value)
		if templates.has(template_id):
			pool.append(template_id)
	if pool.is_empty():
		for template_id in templates.keys():
			var template := templates[template_id] as Dictionary
			if str(template.get("room_type", "")) == "COMMON_ROOM":
				pool.append(str(template_id))
	if pool.is_empty():
		return []
	var main_keys: Array[String] = []
	for key in chain:
		if str((by_key[key] as Dictionary).get("role", "")) == "main":
			main_keys.append(key)
	var content_count := main_keys.size() + branch_keys.size()
	var draws := _constrained_template_draws(content_count, pool, rng)
	# 支线按「父键」归组，父房落到槽位表后**立即跟随**摆放 —— 越早摆可选面越多。
	# 若把 4 条支线全部堆到最后再摆，主路房四周早被后续主路房占满（实测：那样做
	# 300 个种子只有 46 个能摆下，成功率 15%）。就近插入后主路房刚落位、周边最空。
	var branches_by_parent: Dictionary = {}
	for key in branch_keys:
		var raw := by_key[key] as Dictionary
		var parent_key := str(raw.get("parent_key", ""))
		if not branches_by_parent.has(parent_key):
			branches_by_parent[parent_key] = []
		(branches_by_parent[parent_key] as Array).append(key)
	var slots: Array[Dictionary] = []
	var content_index := 0
	for key in chain:
		var raw := by_key[key] as Dictionary
		var template_id := str(raw.get("template_id", ""))
		var variant := str(raw.get("template_variant", ""))
		if str(raw.get("role", "")) == "main":
			# 内容房：房型按种子洗牌（含变体），尺寸随之改 —— 这正是"每局不同"的来源。
			template_id = draws[content_index]
			content_index += 1
			variant = _pick_template_variant(templates, template_id, rng)
		if not templates.has(template_id):
			return []
		slots.append(_constrained_slot(key, raw, templates, template_id, variant))
		for branch_key in (branches_by_parent.get(key, []) as Array):
			var branch_raw := by_key[str(branch_key)] as Dictionary
			var branch_template := draws[content_index]
			content_index += 1
			slots.append(_constrained_slot(
				str(branch_key), branch_raw, templates, branch_template,
				_pick_template_variant(templates, branch_template, rng)
			))
	return slots


## 每间内容房的房型抽取：**先保证每个房型族至少出现一次**，再补足其余槽位后整体洗牌。
## 为什么不让纯随机：10 个槽位纯随机很容易整局只出 2~3 种房（含"全标准房"），
## 玩法上等于没有版图差异；先铺一轮族再洗牌，既保证 9 房型都被用到，又保持全随机顺序。
static func _constrained_template_draws(
	count: int, pool: Array[String], rng: RandomNumberGenerator
) -> Array[String]:
	var draws: Array[String] = []
	for index in range(count):
		if index < pool.size():
			draws.append(pool[index])
		else:
			draws.append(pool[rng.randi_range(0, pool.size() - 1)])
	for index in range(draws.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := draws[index]
		draws[index] = draws[swap_index]
		draws[swap_index] = held
	return draws


static func _pick_template_variant(
	templates: Dictionary, template_id: String, rng: RandomNumberGenerator
) -> String:
	var template := templates.get(template_id, {}) as Dictionary
	var variants := template.get("variants", []) as Array
	if variants.is_empty():
		return ""
	return str(variants[rng.randi_range(0, variants.size() - 1)])


static func _constrained_slot(
	key: String, raw: Dictionary, templates: Dictionary, template_id: String, variant: String
) -> Dictionary:
	var template := templates[template_id] as Dictionary
	return {
		"key": key,
		"room_id": str(raw.get("room_id", "")),
		"legacy_room_id": str(raw.get("legacy_room_id", "")),
		"room_type": str(raw.get("room_type", "")),
		"role": str(raw.get("role", "")),
		"parent_key": str(raw.get("parent_key", "")),
		"template_id": template_id,
		"template_variant": variant,
		"size": _vec2(template.get("size_m", [])),
	}


## 按槽位顺序贴墙摆放，**带回溯**。全部分配成功返回按槽位序的摆放表，否则返回空。
##
## 为什么必须回溯：单遍贪心在「大房把场地切成碎片」时只能整份作废重抽房型，
## 实测含大房的内容房池成功率只有 ~33%（且与尺寸强相关：只放 25×25 时 100%）。
## 回溯的代价很低 —— 每间房最多十来个候选位，而绝大多数情况第一个候选就成立。
##
## 首房锚在「与该尺寸同相位的场地原点」上（15×15 → (2.5,2.5)，即场地正中），
## 全场再在 `_constrained_fits` 的边界约束内蛇形展开 ⇒ 产出天然落在场地内，
## 无需事后整体平移（平移反而可能把已经贴边的房间推出边界）。
static func _place_constrained_slots(
	slots: Array[Dictionary], rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var placed: Array[Dictionary] = []
	var state := {"nodes": 0}
	if _place_recursive(slots, 0, placed, rng, state):
		return placed
	return []


## 递归摆第 `index` 个槽位。摆不进就回退上一间房换位置；节点预算耗尽即放弃本次尝试
## （交由外层重抽房型），避免个别种子把时间吃光。
static func _place_recursive(
	slots: Array[Dictionary],
	index: int,
	placed: Array[Dictionary],
	rng: RandomNumberGenerator,
	state: Dictionary
) -> bool:
	if index >= slots.size():
		return true
	state["nodes"] = int(state["nodes"]) + 1
	if int(state["nodes"]) > CONSTRAINED_SEARCH_BUDGET:
		return false
	var slot := slots[index]
	var size := slot["size"] as Vector2
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	for candidate in _placement_candidates(slot, placed, rng):
		var center := candidate as Vector2
		placed.append({
			"key": str(slot["key"]),
			"center": center,
			"size": size,
			"dir": _direction_from_delta(center - _parent_center(slot, placed)),
		})
		if _place_recursive(slots, index + 1, placed, rng, state):
			return true
		placed.pop_back()
	return false


## 第 `index` 个槽位当前可用的全部落位坐标（已通过吸附 + 场地 + 不重叠三重检查），
## 按「好位置优先」排序。首房/无父房只有一个候选（场地原点）。
static func _placement_candidates(
	slot: Dictionary, placed: Array[Dictionary], rng: RandomNumberGenerator
) -> Array:
	var size := slot["size"] as Vector2
	var parent_key := str(slot.get("parent_key", ""))
	if placed.is_empty() or parent_key.is_empty():
		var origin := _snapped_origin_for(size)
		if _constrained_fits(origin, size, _placed_rects(placed)):
			return [origin]
		return []
	var parent_index := _placed_index_by_key(placed, parent_key)
	if parent_index < 0:
		return []
	var parent_center := placed[parent_index]["center"] as Vector2
	var parent_size := placed[parent_index]["size"] as Vector2
	var rects := _placed_rects(placed)
	# 先按方向收集每个方向的候选（各自已按「横向离父房近 → 远」排好）。
	var per_direction: Array = []
	for direction_value in _direction_trial_order(
		str(slot.get("role", "")), _incoming_dir(placed, parent_index), rng
	):
		var direction := str(direction_value)
		var along_x := direction == "east" or direction == "west"
		var parent_cross := parent_center.y if along_x else parent_center.x
		var child_cross_size := size.y if along_x else size.x
		var row: Array = []
		for cross in _lateral_candidates(parent_cross, child_cross_size):
			var center := _touching_center(parent_center, parent_size, size, direction, cross)
			if _constrained_fits(center, size, rects):
				row.append(center)
		per_direction.append(row)
	# 再**按横向名次轮转**跨方向取：先各方向的第 1 候选，再各方向的第 2 候选……
	# 这样截断到 `CONSTRAINED_BRANCH_LIMIT` 个后，仍能覆盖多个方向，
	# 不至于只把「首选方向」的候选全试完、其它方向一个都没轮到。
	var result: Array = []
	var rank := 0
	var progressed := true
	while progressed and result.size() < CONSTRAINED_BRANCH_LIMIT:
		progressed = false
		for row_value in per_direction:
			var row := row_value as Array
			if rank < row.size():
				result.append(row[rank])
				progressed = true
				if result.size() >= CONSTRAINED_BRANCH_LIMIT:
					break
		rank += 1
	return result


## 已落位房间的矩形表（回溯时不能缓存 —— placed 会被反复 pop/push）。
static func _placed_rects(placed: Array[Dictionary]) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for value in placed:
		var room := value as Dictionary
		rects.append(_rect_at(room["center"] as Vector2, room["size"] as Vector2))
	return rects


## 已落位房间相对它自己父房的朝向（主路房用它延续直行、支线房用它取侧向）。
static func _incoming_dir(placed: Array[Dictionary], index: int) -> String:
	var stored := str((placed[index] as Dictionary).get("dir", ""))
	return stored if not stored.is_empty() else "east"


static func _parent_center(slot: Dictionary, placed: Array[Dictionary]) -> Vector2:
	var parent_key := str(slot.get("parent_key", ""))
	var parent_index := _placed_index_by_key(placed, parent_key)
	if parent_index < 0:
		return Vector2.ZERO
	return placed[parent_index]["center"] as Vector2


## 某面墙上子房可以取的横向坐标（按「离父房中心近 → 远」排序）。
##
## 取值必须是**子房的合法相位**（`size/2 mod 5` 的等价类），否则中心吸附校验会红；
## 同时相对父房中心的偏移不得超过同轴容差 5.01 m，否则 `corridor_not_colinear`。
## 相位与父房一致时得 0 / ±5；差 2.5 m 时只能得 ±2.5。
static func _lateral_candidates(parent_axis: float, child_cross_size: float) -> Array[float]:
	var base := _snap_axis(parent_axis, child_cross_size)
	var limit := ROOM_DOOR_LANE.LATERAL_TOLERANCE_M - CONSTRAINED_EPS
	var result: Array[float] = []
	# base ± 2 格足以覆盖容差窗口（窗口半宽 5.01 < 2×5）。
	for step in range(-2, 3):
		var value: float = base + float(step) * GRID_UNIT_M
		if absf(value - parent_axis) <= limit:
			result.append(value)
	result.sort_custom(func(a, b): return absf(a - parent_axis) < absf(b - parent_axis))
	return result


## 新房试探方向的优先序。
##
## 主路房：**先延续父房的来向**（成走廊感），堵了再走其余方向。
## 支线房：**先走垂直于来向的两个侧面**，绝不与主路下一间抢同一个来向。
##   这一条是硬需求：支线若也优先直行，就会占掉主路下一间唯一想去的方向，
##   主路被迫改道、再往下越走越挤（实测：支线沿用直行序时 300 个种子只成功 6 个）。
##
## 末尾的三个兜底方向**按种子打乱**：同一份房型下，不同尝试要能有不同摆法，
## 否则 128 次重试其实只等价于 1 次（实测：兜底序固定时成功率约 33%）。
static func _direction_trial_order(role: String, preferred: String, rng: RandomNumberGenerator) -> Array:
	var directions: Array = []
	if role == "branch":
		directions = _perpendicular_dirs(preferred)
	else:
		directions = [preferred]
	var rest: Array = []
	for direction_value in ["east", "west", "north", "south"]:
		if not directions.has(direction_value):
			rest.append(direction_value)
	for index in range(rest.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held: Variant = rest[index]
		rest[index] = rest[swap_index]
		rest[swap_index] = held
	for direction_value in rest:
		directions.append(direction_value)
	return directions


## 与给定方向垂直的两个方向（先给「主轴不同侧」的那个，保持确定性顺序）。
static func _perpendicular_dirs(direction: String) -> Array:
	if direction == "east" or direction == "west":
		return ["north", "south"]
	return ["east", "west"]


## 贴着父房某个面时的子房中心：主轴位移 = 两侧半尺寸之和（净距恰为 0）。
##
## `cross_axis` 是横轴（垂直于贴墙法线的那个轴）的绝对坐标，由
## `_lateral_candidates` 给出 —— **必须**取子房自己的合法相位，绝不能直接沿用
## 父房中心：奇数格宽房（15/25/45）中心落 `5k+2.5`、偶数格宽（40/50/60/70）落 `5k`，
## 两者相差 2.5 m。沿用父房中心会让偶数高的子房横轴偏 2.5 m，
## `room_center_not_snapped` 判红，而主轴又已是 0 净距 ⇒ 该尝试必废
## （实测：不吸附时 300/300 个种子全部回退）。
static func _touching_center(
	parent_center: Vector2,
	parent_size: Vector2,
	child_size: Vector2,
	direction: String,
	cross_axis: float
) -> Vector2:
	match direction:
		"east":
			return Vector2(parent_center.x + (parent_size.x + child_size.x) * 0.5, cross_axis)
		"west":
			return Vector2(parent_center.x - (parent_size.x + child_size.x) * 0.5, cross_axis)
		"north":
			return Vector2(cross_axis, parent_center.y - (parent_size.y + child_size.y) * 0.5)
		_:
			return Vector2(cross_axis, parent_center.y + (parent_size.y + child_size.y) * 0.5)


## 把某个横轴坐标吸附到「该尺寸的合法中心相位」上，取离原值最近的那个。
## 与校验器 `_snap_component_axis` 同一公式：`snappedf(center - size/2, 5) + size/2`。
static func _snap_axis(value: float, size: float) -> float:
	return snappedf(value - size * 0.5, GRID_UNIT_M) + size * 0.5


static func _snapped_origin_for(size: Vector2) -> Vector2:
	return Vector2(fposmod(size.x * 0.5, GRID_UNIT_M), fposmod(size.y * 0.5, GRID_UNIT_M))


## 位置合法性三连：在场地内、中心吸附在 5m 模数上、与已摆房间不重叠（相切允许）。
##
## 场地边界这条**必须保留**，它不是「顺手多判一下」—— 它是逼路径拐弯的唯一机制。
## `_first_adjacent_center` 的优先序是「先延续来向（成走廊感）」，而开阔场地里永远
## 不会撞到别的房，于是若不在边界处逼停，主路会一路直走：8 间主路房（含入口与 Boss）
## 沿单一轴的半尺寸之和约 415 m，远超 250 m 场地 ⇒ 每个种子都越界、100% 回退
## （实测：删掉本检查后 300/300 个种子全部回退）。留边界后蛇形自动折返。
static func _constrained_fits(center: Vector2, size: Vector2, rects: Array[Rect2]) -> bool:
	var rect := _rect_at(center, size)
	if not _rect_contains_rect(_map_rect(), rect):
		return false
	var snapped := Vector2(
		snappedf(center.x - size.x * 0.5, GRID_UNIT_M) + size.x * 0.5,
		snappedf(center.y - size.y * 0.5, GRID_UNIT_M) + size.y * 0.5
	)
	if absf(snapped.x - center.x) > CONSTRAINED_EPS or absf(snapped.y - center.y) > CONSTRAINED_EPS:
		return false
	for other in rects:
		if rect.intersection(other).get_area() > CONSTRAINED_EPS:
			return false
	return true


## 摆位结果 → 规范化层结构（形状与 LevelPlanLoader.normalize_floor 的返回一致）。
static func _constrained_floor_from(
	blueprint: Dictionary,
	floor_number: int,
	placed: Array[Dictionary],
	slots: Array[Dictionary],
	policy: Dictionary,
	templates: Dictionary
) -> Dictionary:
	var center_by_key: Dictionary = {}
	for value in placed:
		var room := value as Dictionary
		center_by_key[str(room["key"])] = room["center"]
	var rooms: Array[Dictionary] = []
	for value in slots:
		var slot := value as Dictionary
		var key := str(slot["key"])
		if not center_by_key.has(key):
			return {}
		rooms.append({
			"key": key,
			"room_id": str(slot.get("room_id", "")),
			"legacy_room_id": str(slot.get("legacy_room_id", "")),
			"room_type": str(slot.get("room_type", "")),
			"role": str(slot.get("role", "")),
			"parent_key": str(slot.get("parent_key", "")),
			"template_id": str(slot.get("template_id", "")),
			"template_variant": str(slot.get("template_variant", "")),
			"center": center_by_key[key],
			"size": slot["size"],
			"rotation_deg": 0.0,
			"content_type": "",
			"boss_content_id": "",
			"enemy_spawn_plan": {},
			"reward_plan": {},
			"declared_ports": [],
			"ports": [],
			"ports_derived": false,
		})
	LEVEL_PLAN_LOADER.derive_ports(rooms)
	attach_authored_layout_shell(rooms, policy, templates)
	return {
		"level_id": str(blueprint.get("level_id", "")),
		"mode": "constrained",
		"floor_number": int(blueprint.get("floor_number", floor_number)),
		"floor_index": int(blueprint.get("floor_index", 0)),
		"sequence_index": int(blueprint.get("sequence_index", 0)),
		"entry_side": str(blueprint.get("entry_side", "east")),
		"exit_side": str(blueprint.get("exit_side", "west")),
		"reservations": blueprint.get("reservations", []),
		"rooms": rooms,
		"main_path": _string_array(blueprint.get("main_path", [])),
		"edge_policy": _constrained_edge_policy(rooms),
		"errors": [],
	}


## —— 第 4 环：整房 5m 通用壳体组件清单（`authored_layout_instances`）——
##
## 关卡在 `generation_policy.authored_layout_shell = true` 时，本函数把生成器算出的
## 房间几何翻译成「5 类通用件实例清单」并按房写回 `authored_layout_*` 六个键
## （由 `room_from_source` → `TowerDescent3D._append_plan_room_record` →
## `DungeonRoom3D._build_authored_layout_shell` 逐层透传到装配层）。
## 未开启该开关的关卡**一个字段都不多**：`rooms` 原样返回，程序化壳体行为逐字不变。
##
## 为什么由生成器现算，而不是把清单写进 `floors/floor_00.json`：
## `mode = "constrained"` 会整份替换几何（房型每局按种子重抽、摆位随之变），
## 写死的实例坐标第二次进图就全错位。设计源只能声明「要做」，做出来的几何必须现算。
##
## 坐标换算是本函数唯一的几何知识，口径来自 `RoomShellLayoutBuilder3D` 头注释：
## 设计源 planar → Blender 世界为 `bx = plan.x`、`by = −plan.y`
## （设计源 +y 对应世界 +z 即「南」，与 `TowerDescent3D._plan_world_position` 同源）；
## 门位一律复用 `LevelPlanLoader.derive_ports()` 产出的 `ports[].lane_m`——
## 它与运行时 `_plan_room_layout()` 同走 `RoomDoorLane`，是门槽的唯一口径，此处不重算。
##
## 生成器侧的几何错误（房界不在 5m 格线、门位不在 lane 中心、门位落在轮廓凹口上）**不静默吞掉**：
## 一旦发生就是「清单与门槽对不上」，宁可不接管（保持程序化旧拼装）也不给出错位的壳。
##
## `templates` 是 `LevelPlanLoader.load_room_templates(level_id)` 的原样结果，本函数只用它取
## `variant_footprints`（非矩形外轮廓）。取不到 = 该房按矩形处理，不是错误。
static func attach_authored_layout_shell(
	rooms: Array, policy: Dictionary, templates: Dictionary = {}
) -> void:
	if not bool(policy.get("authored_layout_shell", false)):
		return
	if rooms.is_empty():
		return
	var block := authored_shell_block(rooms, templates)
	if block.is_empty():
		return
	var result := ROOM_SHELL_LAYOUT_BUILDER.build_block(block)
	var errors := result.get("errors", []) as Array
	if not errors.is_empty():
		for error_value in errors:
			push_warning(
				"FloorPlanGenerator: 通用壳体清单未生成（%s），本层回退程序化壳体" % str(error_value)
			)
		return
	var instances := result.get("instances", []) as Array
	# Boss 房专属件摆位源：只有本层真有 Boss 房时才读盘（远征 01 有，塔楼普通层没有）。
	var boss_layout: Dictionary = {}
	for value in rooms:
		if str((value as Dictionary).get("role", "")) == "boss":
			boss_layout = _load_boss_layout_instances()
			break
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		if key.is_empty() or str(room.get("role", "")) == "stair_entry":
			continue
		var center := room.get("center", Vector2.ZERO) as Vector2
		# `to_runtime_instances` 的 y 恒为 0：清单里只有**落地件**（墙/L/地砖），
		# 悬空件（Boss 房专属组件）走各自布局源的 `position_m`，不从这里投影。
		var projected := ROOM_SHELL_LAYOUT_BUILDER.to_runtime_instances(
			instances, key, center.x, -center.y
		)
		var filtered: Array = []
		for instance_value in projected:
			var instance := instance_value as Dictionary
			# `door_leaf_preview` 是摆位源的编辑器预览件：运行时门扇由 RoomDoor3D 唯一
			# 生成，带下去只会撞上装配层「未接线的 slot_role」告警。
			if str(instance.get("slot_role", "")) == "door_leaf_preview":
				continue
			filtered.append(instance)
		# 专属件（Boss 房 6 件）叠加在通用壳体之上：它们**不是落地件**，坐标直接取摆位源。
		if str(room.get("role", "")) == "boss":
			filtered.append_array(_boss_room_exclusive_instances(room, boss_layout))
		room["authored_layout_shell"] = true
		room["authored_layout_asset_id"] = "EXPEDITION-GENERIC-SHELL-%s" % key.to_upper()
		room["authored_layout_version"] = "runtime_generated"
		room["authored_layout_room_id"] = key
		room["authored_layout_peaceful"] = false
		room["authored_layout_instances"] = filtered


## —— 第 5 环（专属件）：Boss 房 6 件专属件摆位源 ——
##
## 与通用壳体件的关键差别：组合器 `build_block()` 的输入契约是「轴对齐矩形 + 四面墙 + 门位」，
## 且 `to_runtime_instances()` 的 y **硬编码 0.0**，只对**落地件**（墙 / L 角件 / 地砖）成立。
## 专属件里有**悬空件**（主屏底面 3.805m、北墙标识 7.4461m），塞进组合器会被压回地面，
## 所以它们走这条独立通路：真源是摆位源 JSON，运行时只做坐标搬运。
##
## 坐标换算口径来自摆位源自带的 `coordinate_contract.room_local`：
## `Godot 房间局部 = (bx − cbx, bz, −(by − cby))`，cbx/cby = 本房 bounds 中心。
##   · Godot **y 取 bz**（该件底面离走行面的悬空高度）—— 不是 0，这是本函数存在的理由；
##   · Godot z 取 `−(by − cby)`，与 `RoomShellLayoutBuilder3D` 的 `by = −plan.y` 同源。
## 输出形状与通用件逐字同构（`{name, component_id, slot_role, position, rotation_y_deg}`），
## 因此装配层只需多一个 `slot_role` 分支，不需要新的房间级字段。
static func _load_boss_layout_instances() -> Dictionary:
	if not FileAccess.file_exists(BOSS_LAYOUT_SOURCE_PATH):
		push_error("FloorPlanGenerator: Boss 房专属件摆位源缺失 %s" % BOSS_LAYOUT_SOURCE_PATH)
		return {}
	var text := FileAccess.get_file_as_string(BOSS_LAYOUT_SOURCE_PATH)
	if text.is_empty():
		push_error("FloorPlanGenerator: Boss 房专属件摆位源为空 %s" % BOSS_LAYOUT_SOURCE_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("FloorPlanGenerator: Boss 房专属件摆位源不是 JSON 对象 %s" % BOSS_LAYOUT_SOURCE_PATH)
		return {}
	var source := parsed as Dictionary
	var result: Dictionary = {}
	for room_value in source.get("rooms", []):
		if not (room_value is Dictionary):
			push_error("FloorPlanGenerator: Boss 房摆位源 rooms[] 有条目不是 JSON 对象，已跳过")
			continue
		var room := room_value as Dictionary
		var room_id := str(room.get("room_id", ""))
		if room_id.is_empty():
			push_error("FloorPlanGenerator: Boss 房摆位源有房间缺 room_id，已跳过")
			continue
		var bounds_x := _vec2(room.get("bounds_x_m", []))
		var bounds_y := _vec2(room.get("bounds_y_m", []))
		if is_zero_approx(bounds_x.y - bounds_x.x) or is_zero_approx(bounds_y.y - bounds_y.x):
			push_error("FloorPlanGenerator: Boss 房摆位源房间 %s 的 bounds 非法" % room_id)
			continue
		var cbx := (bounds_x.x + bounds_x.y) * 0.5
		var cby := (bounds_y.x + bounds_y.y) * 0.5
		var instances: Array = []
		for instance_value in source.get("instances", []):
			if not (instance_value is Dictionary):
				push_error("FloorPlanGenerator: Boss 房专属件摆位源 instances[] 有条目不是 JSON 对象，已跳过")
				continue
			var instance := instance_value as Dictionary
			if str(instance.get("room_id", "")) != room_id:
				continue
			if not bool(instance.get("enabled", true)):
				continue
			var raw: Variant = instance.get("position_m", [])
			if not (raw is Array) or (raw as Array).size() != 3:
				push_error(
					"FloorPlanGenerator: Boss 房专属件 %s 的 position_m 不是三元组，已跳过"
					% str(instance.get("instance_id", ""))
				)
				continue
			var position_m := raw as Array
			var component_id := str(instance.get("component_id", ""))
			if component_id.is_empty():
				push_error(
					"FloorPlanGenerator: Boss 房专属件 %s 缺 component_id，已跳过"
					% str(instance.get("instance_id", ""))
				)
				continue
			instances.append({
				"name": str(instance.get("instance_id", "ExclusiveComponent")),
				"component_id": component_id,
				"slot_role": "exclusive_component",
				"position": Vector3(
					float(position_m[0]) - cbx,
					# ⚠️ bz（高度）不是 0：悬空件靠这一项挂在半空。
					float(position_m[2]),
					-(float(position_m[1]) - cby)
				),
				"rotation_y_deg": float(instance.get("rotation_z_deg", 0.0)),
			})
		result[room_id] = {
			"size": _vec2(room.get("size_m", [])),
			"instances": instances,
		}
	return result


## 取某间 Boss 房应叠加的专属件。匹配顺序：`key` → `legacy_room_id` → `room_id`
##（摆位源的 `room_id` 是**设计源 key**，运行时 key 由 constrained 版图定，两侧不保证同名）。
##
## **房型不符直接不挂**：这 6 件的包络跨满 50×40（主屏 21.52m、北墙标识 35.9m），
## 落到别的尺寸就是穿墙或悬在墙外 —— 与其交出穿墙的壳，不如报错退化成通用壳体。
static func _boss_room_exclusive_instances(room: Dictionary, boss_layout: Dictionary) -> Array:
	if boss_layout.is_empty():
		return []
	var matched := ""
	for candidate in [
		str(room.get("key", "")),
		str(room.get("legacy_room_id", "")),
		str(room.get("room_id", "")),
	]:
		if not candidate.is_empty() and boss_layout.has(candidate):
			matched = candidate
			break
	if matched.is_empty():
		return []
	var entry := boss_layout[matched] as Dictionary
	var instances := entry.get("instances", []) as Array
	var want := entry.get("size", Vector2.ZERO) as Vector2
	var got := room.get("size", Vector2.ZERO) as Vector2
	if absf(want.x - got.x) > CONSTRAINED_EPS or absf(want.y - got.y) > CONSTRAINED_EPS:
		push_error(
			"FloorPlanGenerator: Boss 房 %s 尺寸 %s 与专属件摆位源声明的 %s 不符，%d 件专属件已跳过"
			% [str(room.get("key", "")), str(got), str(want), instances.size()]
		)
		return []
	return instances.duplicate(true)



## 生成器房间表 → `RoomShellLayoutBuilder3D.build_block()` 的区块输入（公开给验收探针，
## 使「区块级门槽覆盖」可以独立复核，而不必复刻一遍坐标换算）。
##
## 入口安全房**不并入区块**：它仍走 v007 正式整房（v004 通用墙/地/门 + 17 个房间包），
## 已经消费同一批通用件；而且它是本区块**唯一与区块外房间共墙**的房间（15×15 单格，
## 四邻皆可为内容房）。并进来会让区块 lane 归属与 v007 自带的四面墙互相重叠 ——
## 收益为零，风险是整房双壳。
static func authored_shell_block(rooms: Array, templates: Dictionary = {}) -> Array:
	var block: Array = []
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("role", "")) == "stair_entry":
			continue
		var built := _authored_shell_block_room(room, templates)
		if built.is_empty():
			continue
		block.append(built)
	return block


## 单个房间 → `RoomShellLayoutBuilder3D.build_block()` 的输入形状。
## 房界必须落在 5m 格线上（生成器 `_constrained_fits` 已保证），否则 builder 报
## `room_bound_off_grid`，由调用方放弃接管。
##
## 非矩形轮廓从模板取：`room.template_id` + `room.template_variant` → 模板的
## `variant_footprints.<variant>`（**模板坐标系**，口径见 `RoomShellLayoutBuilder3D` 头注释）。
## 两条护栏：
##   · 模板未声明该变体的轮廓 ⇒ 按矩形处理（不是错误，多数模板就是矩形）；
##   · 模板的 `size_m` 与房间实算尺寸不符 ⇒ 只告警、**不挂轮廓**（挂了必然越界，
##     那会让 builder 报错并让整层退回程序化壳体，把一处不一致放大成整层回退）。
static func _authored_shell_block_room(room: Dictionary, templates: Dictionary = {}) -> Dictionary:
	var key := str(room.get("key", ""))
	if key.is_empty():
		return {}
	var center := room.get("center", Vector2.ZERO) as Vector2
	var size := room.get("size", Vector2.ZERO) as Vector2
	if size.x < GRID_UNIT_M or size.y < GRID_UNIT_M:
		return {}
	var by_center := -center.y
	var doors: Dictionary = {}
	for port_value in room.get("ports", []):
		if not (port_value is Dictionary):
			continue
		var port := port_value as Dictionary
		var side := str(port.get("side", ""))
		var lane_m := float(port.get("lane_m", 0.0))
		if side in ["north", "south"]:
			# 南北墙的门「沿墙坐标」在 bx 轴上：bx = plan.x，无镜像。
			doors[side] = center.x + lane_m
		elif side in ["west", "east"]:
			# 东西墙的门「沿墙坐标」在 by 轴上：by = −plan.y，故是**减** lane。
			doors[side] = by_center - lane_m
	var built := {
		"room_id": key,
		"bounds_x_m": [center.x - size.x * 0.5, center.x + size.x * 0.5],
		"bounds_y_m": [by_center - size.y * 0.5, by_center + size.y * 0.5],
		"doors": doors,
		"exits": {},
		"use_corner_l": true,
	}
	var footprint := _room_variant_footprint(
		room, size, built["doors"] as Dictionary, built["bounds_x_m"] as Array,
		built["bounds_y_m"] as Array, templates
	)
	if not footprint.is_empty():
		var variant := str(footprint.get("variant", str(room.get("template_variant", ""))))
		built["footprint_vertices_m"] = footprint.get("vertices_m", [])
		built["footprint_frame"] = str(
			footprint.get("frame", ROOM_SHELL_LAYOUT_BUILDER.FOOTPRINT_FRAME)
		)
		built["footprint_variant"] = variant
		# 声明变体的凹口压在本房门位上时换成了别的变体（尺寸不变，只换外轮廓）。
		# 回写让 `template_variant` 与实际外轮廓一致，否则日志/取证里会看到一个没被用上的变体。
		if variant != str(room.get("template_variant", "")):
			room["template_variant"] = variant
			room["template_variant_reconciled"] = true
	return built


## 取本房（模板 + 变体）的非矩形外轮廓；矩形房 / 不兼容返回空字典。
##
## 为什么还要**按门位筛选变体**：房型（含变体）是按种子从模板池抽的，抽到哪个变体
## 与房间落位无关 ⇒ 一个 L 形 / U 形轮廓的凹口很容易正好压在**本房的门位**上。
## 凹口恒在包围盒内部、房间按包围盒摆放互不重叠 ⇒ 凹口里不可能有邻房 ⇒ 门落在凹口上
## 就是开向虚空。builder 会因此报 `door_offset_off_lane`，而那是**整层**放弃接管的粒度
## （回到程序化壳体）—— 把一处局部冲突放大成全图回退，不可接受。
## 所以在这里按「声明变体优先 → 模板 variants 顺序」筛出第一个能承接全部门/出口的变体；
## 一个都不行才退矩形（矩形房的门位恒落在包围盒外边上，永远兼容）。
##
## 判据与 `build_block()` 同源：`RoomShellLayoutBuilder3D.footprint_accepts_ports()`。
static func _room_variant_footprint(
	room: Dictionary,
	size: Vector2,
	doors: Dictionary,
	bounds_x_m: Array,
	bounds_y_m: Array,
	templates: Dictionary
) -> Dictionary:
	var template_id := str(room.get("template_id", ""))
	if template_id.is_empty() or templates.is_empty() or not templates.has(template_id):
		return {}
	var template := templates[template_id] as Dictionary
	var variants: Variant = template.get("variant_footprints", {})
	if not (variants is Dictionary) or (variants as Dictionary).is_empty():
		return {}
	var declared := _vec2(template.get("size_m", []))
	if (
		not is_equal_approx(declared.x, size.x)
		or not is_equal_approx(declared.y, size.y)
	):
		push_warning(
			"FloorPlanGenerator: 房间 %s 的实算尺寸 %s 与模板 %s 的 size_m %s 不符，"
			% [str(room.get("key", "")), str(size), template_id, str(declared)]
			+ "本次按矩形处理（非矩形轮廓不挂）"
		)
		return {}
	var by_variant := variants as Dictionary
	for variant in _variant_candidate_order(template, by_variant, str(room.get("template_variant", ""))):
		var entry: Variant = by_variant[variant]
		if not (entry is Dictionary):
			continue
		var outline := entry as Dictionary
		if not ROOM_SHELL_LAYOUT_BUILDER.footprint_accepts_ports(
			outline.get("vertices_m", []) as Array,
			str(outline.get("frame", ROOM_SHELL_LAYOUT_BUILDER.FOOTPRINT_FRAME)),
			bounds_x_m, bounds_y_m, doors, {}
		):
			continue
		var accepted := outline.duplicate()
		accepted["variant"] = variant
		return accepted
	return {}


## 变体候选顺序：**声明的那一个优先**（保留本局随机性），其后按模板 `variants`
## 的声明顺序，最后补上 `variant_footprints` 里有、但 `variants` 没列出的键。
## 所有遍历都取声明顺序 ⇒ 同一 seed 的结果可复现（不依赖 Dictionary 的哈希序）。
static func _variant_candidate_order(
	template: Dictionary, by_variant: Dictionary, preferred: String
) -> Array[String]:
	var order: Array[String] = []
	if by_variant.has(preferred):
		order.append(preferred)
	for value in template.get("variants", []) as Array:
		var variant := str(value)
		if by_variant.has(variant) and variant not in order:
			order.append(variant)
	for value in by_variant.keys():
		var variant := str(value)
		if variant not in order:
			order.append(variant)
	return order


## 墙贴墙的父子边要显式进白名单，否则校验器按 corridor_too_short 报红；反过来
## 净距 > 0 的边**不能**进白名单（会报 edge_policy_stale）。故按实算净距逐条取舍。
static func _constrained_edge_policy(rooms: Array) -> Array:
	var by_key: Dictionary = {}
	for value in rooms:
		by_key[str((value as Dictionary).get("key", ""))] = value
	var policy: Array = []
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var parent_key := str(room.get("parent_key", ""))
		if parent_key.is_empty() or not by_key.has(parent_key):
			continue
		var parent := by_key[parent_key] as Dictionary
		var clear := ROOM_DOOR_LANE.corridor_clear(
			parent.get("center", Vector2.ZERO) as Vector2,
			parent.get("size", Vector2.ZERO) as Vector2,
			room.get("center", Vector2.ZERO) as Vector2,
			room.get("size", Vector2.ZERO) as Vector2
		)
		if clear <= CONSTRAINED_EPS:
			policy.append({
				"a": parent_key,
				"b": key,
				"allow_zero_length": true,
				"note": "程序化生成：墙贴墙",
			})
	return policy


static func _first_key_with_role(rooms: Array, role: String) -> String:
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("role", "")) == role:
			return str(room.get("key", ""))
	return ""


static func _placed_index_by_key(placed: Array[Dictionary], key: String) -> int:
	for index in range(placed.size()):
		if str((placed[index] as Dictionary).get("key", "")) == key:
			return index
	return -1


static func _direction_from_delta(delta: Vector2) -> String:
	if absf(delta.x) >= absf(delta.y):
		return "east" if delta.x >= 0.0 else "west"
	return "south" if delta.y >= 0.0 else "north"


static func _rect_at(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)


static func _map_rect() -> Rect2:
	return Rect2(
		Vector2(-MAP_SIZE_M * 0.5, -MAP_SIZE_M * 0.5),
		Vector2(MAP_SIZE_M, MAP_SIZE_M)
	)


static func _vec2(value: Variant) -> Vector2:
	if value is Array:
		var array := value as Array
		if array.size() >= 2:
			return Vector2(float(array[0]), float(array[1]))
	return Vector2.ZERO


static func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in (value as Array):
			out.append(str(item))
	return out


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


static func _calculate_area_budget(rooms: Array[Dictionary], policy: Dictionary = {}) -> Dictionary:
	# 公式已抽到 LevelAreaBudget 唯一实现（校验器与加载路径共用，避免第三份）。
	# 本处保留同名转发，调用点与返回键完全不变（policy 缺省 = 塔楼口径）。
	return LEVEL_AREA_BUDGET.calculate(rooms, policy)


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
