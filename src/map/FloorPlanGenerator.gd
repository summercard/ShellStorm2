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
## 房型默认组件布局（02 产物）直接重放。这里只登记稳定房型模板到真源的映射；
## 实例数量、位置、旋转全部读取 component_instances.json，不在 Godot 维护第二套摆位。
const ROOM_TYPE_LAYOUT_SOURCES := {
	"office_60x70": {
		"path": "res://assets/art/environments/tower_zones/expedition/source/common_components/v006/component_instances.json",
		"version": "v006",
		"asset_id": "ENV-EXPEDITION-L01-OFFICE-ROOM-TYPE-LAYOUT",
		"size_m": Vector2(30.0, 40.0),
		"door_wall_component_id": "ENV-EXPEDITION-L01-OFFICE-DOOR_WALL",
	},
	"bridge_60x50": {
		"path": "res://assets/art/environments/tower_zones/expedition/source/common_components/v007/component_instances.json",
		"version": "v007",
		"asset_id": "ENV-EXPEDITION-L01-BRIDGE-ROOM-TYPE-LAYOUT",
		"size_m": Vector2(30.0, 60.0),
		"door_wall_component_id": "",
	},
}
const SHELL_COMPONENT_CATALOG_PATH := (
	"res://assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)

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
## `spawn_placements` / `encounter`（触发盒放置与调用，触发器刷怪设计 §3.2）、
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
		# 触发盒放置层 + 调用机制层（触发器刷怪设计 §3.2 / §3.3）。
		# 与 enemy_spawn_plan 同样「设计源钉死优先」：本层只透传，不解释盒心/尺寸/下标。
		# 同样**必须在此登记**，否则设计源写了也被静默丢弃（出口白名单）。
		"spawn_placements": (src.get("spawn_placements", []) as Array).duplicate(true),
		"encounter": (src.get("encounter", {}) as Dictionary).duplicate(true),
		# 「只认盒子」标记（触发器刷怪设计 §7-A）：由层下发到每间房，运行时据此判定
		# 「没盒子就不刷」。未声明 = false ⇒ 未迁移关卡行为逐字不变。
		"spawn_boxes_only": bool(src.get("spawn_boxes_only", false)),
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
		# 掉落调度投影（05 §11）。房间 reward_plan 是逐房特例；monster_drop_table
		# 是 L1 关卡级规则，必须留在 plan 顶层，不复制进每个 room record。
		"reward_slots": reward_slots_from_rooms(rooms),
		"monster_drop_table": (
			level_plan.get("monster_drop_table", {}) as Dictionary
		).duplicate(true),
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
	# 取向不在这里定，也不靠第二个模板 id：每个槽位自带本模板的**转置尺寸**
	# （见 `_constrained_slot`），落位阶段按连接方向二选一（见 `_placement_candidates`）。
	# —— 房型是否钉死（业主 2026-09-26 裁定：远征主路房型固定）——
	# 为真时主路内容房一律用 L2 蓝图钉死的 `template_id` / `template_variant`，
	# **不再从 `content_template_pool` 按种子洗牌**；短边受限房型的槽位对调也随之跳过
	# （它对「按种子抽取」才成立，钉死后无用）。
	# 为什么要这个开关：房型洗牌 ⇒ 房间尺寸每局变 ⇒ 房内地砖格心每局不同，
	# 「触发盒以地砖格心为中心、逐盒手调」这条业主口径就落不了地（声明坐标会落到房外）。
	# 钉死后尺寸与砖格每局稳定，绝对砖心坐标才有意义。缺省 false = 洗牌（旧行为逐字不变）。
	var pin_templates := bool(policy.get("pin_content_templates", false))
	var content_count := main_keys.size() + branch_keys.size()
	var draws := _constrained_template_draws(content_count, pool, rng)
	if not pin_templates:
		# 短边受限房型（通道桥房）只许抽进「连接数 ≤ 2」的槽位 —— 抽中多连接槽位时与
		# 一个「连接数 ≤ 2」的槽位对调。见 `_relieve_short_edge_slots` 的完整推导。
		_relieve_short_edge_slots(
			draws, _draw_slot_descriptors(chain, by_key, branches_by_parent), templates
		)
	var slots: Array[Dictionary] = []
	var content_index := 0
	for key in chain:
		var raw := by_key[key] as Dictionary
		var template_id := str(raw.get("template_id", ""))
		var variant := str(raw.get("template_variant", ""))
		if str(raw.get("role", "")) == "main":
			content_index += 1
			if pin_templates:
				# 钉死：蓝图写了什么就用什么；带变体族但蓝图漏写变体时，
				# 取该族**第一个**变体（确定性），绝不退回按种子随机 —— 否则砖格仍不稳。
				if not templates.has(template_id):
					return []
				variant = _pinned_variant(templates, template_id, variant)
			else:
				# 内容房：房型按种子洗牌（含变体），尺寸随之改 —— 这正是"每局不同"的来源。
				template_id = draws[content_index - 1]
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


## —— 短边受限房型（通道桥房）的落位资格 ——
##
## 通道桥房的业主口径是「长边不连、只在短边开门」，而「短边」是**一对相向的墙**
## （长轴沿 x ⇒ 东/西；沿 y ⇒ 南/北）。两墙里各只能挂一间子房 —— 门槽的横向容差
## `RoomDoorLane.LATERAL_TOLERANCE_M = 5.01 m` 决定了子房中心相对父房中心沿横轴的偏移
## 不超过 5 m，同一面墙上挂两间必然相互重叠。
## ⇒ **桥房（不论取哪种取向）最多只有 2 条连接**（一个连接面一条）。
##
## 而本关拓扑里「带支线的主路房」有 3 条连接（父 + 子 + 支线），4 间中段主路房
## （room_02…room_05）各有 1 条支线 ⇒ 这 4 个槽位结构上**摆不下桥房**
## （实测：不设限时 324 个种子回落 165 个，51%；把搜索预算抬到 40000 只降到 43%
## ⇒ 是结构无解，不是搜索不够）。
##
## 故在抽取阶段就把桥房挡在多连接槽位之外：把它和一个「连接数 ≤ 2」的槽位**对调**。
## 只换位、不动族出现次数（`_constrained_template_draws` 的「每族至少一次」不受影响），
## 也不动 L2 蓝图的 `parent_key` ⇒ 支线挂法、房间 id、内容类型分配逐字不变。
##
## 每个「抽取槽位」的落位画像，顺序与 `_constrained_template_draws` 的 draws 完全一致：
## 沿 chain 走，主路房记「前 + 后 + 支线数」，紧随其后的每条支线各记 1。
## 非主路的 chain 房（入口/Boss/撤离）模板固定、不参与抽取，故不记；挂在其上的支线照记。
##
## `main` 区分「主路房槽位」与「支线槽位」—— `_relieve_short_edge_slots` 靠它排序：
## 桥房放在主路端位是**直通过道**（父在一短边、子在对侧短边，取向自适应）⇒ 与普通房同样好摆；
## 放在支线位则是「垂直挂出的大房」⇒ 要凭空多出 60m 垂向净空，几乎必败。两者难度天差地别。
static func _draw_slot_descriptors(
	chain: Array[String], by_key: Dictionary, branches_by_parent: Dictionary
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in range(chain.size()):
		var key := str(chain[index])
		var raw := by_key[key] as Dictionary
		var branches := branches_by_parent.get(key, []) as Array
		if str(raw.get("role", "")) == "main":
			var links := branches.size()
			if index > 0:
				links += 1
			if index < chain.size() - 1:
				links += 1
			rows.append({"links": links, "main": true})
		for _branch_value in branches:
			rows.append({"links": 1, "main": false})
	return rows


## 把「短边受限房型抽到多连接槽位」的错配就地纠正：与一个「非短边受限、且连接数 ≤ 2」的
## 槽位对调。**目标槽位按「桥房摆得下的难度」排序**，主路端位优先，其中**后段端位又先于前段**：
##
##   · 主路端位是天然位置 —— 桥房在这里是直通过道：父房在一侧短边、子房在对侧短边，
##     取向随方向自适应，摆位难度与普通房没有区别。
##   · **但前段端位（`room_01`）与前段的「子房」一起会越界**。入口锚在场地正中，
##     `entry(15)` 东墙在 x=10，桥房 60 长 ⇒ 到 x=70；而 `room_01` 的子房是 `room_02`，
##     被短边锁钉在同一轴、还可能是 70×50 / 60×70 的大房 ⇒ 需要 x 到 130~140，
##     而场地只到 125。**实测：桥房落在 `room_01` 时，`room_02` 必然无位可放**
##     （回落轨迹里反复出现 `已放 entry + room_01(bridge_60x50)` 后卡在 `room_02`）。
##   · **后段端位（`room_06`）的子房是 Boss 房（`boss_50x40`，全场最小之一）**
##     ⇒ 同一个 60 m 桥房之后只需再让出 25 m，稳得多。
##   · 支线位排最后：桥房垂直挂出需要凭空多出 60 m 垂向净空，成功率最低。
##
## 贪心即可 —— 桥房抽中次数（池 5 族 × 10 槽 ⇒ 期望 2 次、上界 6 次）不大于可放槽位数。
## 真到无可对调位时保留原状并告警，交由落位阶段与回落兜底。
static func _relieve_short_edge_slots(
	draws: Array, descriptors: Array[Dictionary], templates: Dictionary
) -> void:
	var main_targets: Array[int] = []
	var branch_targets: Array[int] = []
	for index in range(draws.size()):
		if _requires_short_edge_links(templates, str(draws[index])):
			continue
		if int(descriptors[index]["links"]) > 2:
			continue
		if bool(descriptors[index]["main"]):
			main_targets.append(index)
		else:
			branch_targets.append(index)
	# 主路端位**后段优先**（见上方推导：前段端位的子房紧邻场地中心，越界风险最高）。
	var ordered_main: Array[int] = []
	for offset in range(main_targets.size() - 1, -1, -1):
		ordered_main.append(main_targets[offset])
	var targets: Array[int] = []
	targets.append_array(ordered_main)
	targets.append_array(branch_targets)
	var used: Dictionary = {}
	for index in range(draws.size()):
		if not _requires_short_edge_links(templates, str(draws[index])):
			continue
		if int(descriptors[index]["links"]) <= 2:
			continue
		var chosen := -1
		for target in targets:
			if not used.has(target):
				chosen = target
				break
		if chosen < 0:
			push_warning(
				"FloorPlanGenerator: 短边受限房型 %s 落在连接数 %d 的槽位，且无可对调位"
				% [str(draws[index]), int(descriptors[index]["links"])]
			)
			continue
		used[chosen] = true
		var held: Variant = draws[index]
		draws[index] = draws[chosen]
		draws[chosen] = held


## 该模板是否「连接面被限死在一对相向短墙」⇒ 最多 2 条连接。
## 判据取模板是否声明 `sunken_pit` —— 与 `_bridge_multi_level_plan`、验收探针
## `probe_expedition01_bridge_short_edge` 同一口径（通道桥房是本关唯一带下沉坑的房型）。
static func _requires_short_edge_links(templates: Dictionary, template_id: String) -> bool:
	var template := templates.get(template_id, {}) as Dictionary
	if template.is_empty():
		return false
	return template.has("sunken_pit")


static func _pick_template_variant(
	templates: Dictionary, template_id: String, rng: RandomNumberGenerator
) -> String:
	var template := templates.get(template_id, {}) as Dictionary
	var variants := template.get("variants", []) as Array
	if variants.is_empty():
		return ""
	return str(variants[rng.randi_range(0, variants.size() - 1)])


## 钉死房型时的变体解析：蓝图写了就用；带变体族却漏写时取**第一个**变体（确定性）。
## 与 `_pick_template_variant` 的分工：那个要随机（洗牌路径），这个要**可复现**（钉死路径）。
## 无变体族恒返回空串 —— 与模板 `variants: []` 一致。
static func _pinned_variant(templates: Dictionary, template_id: String, declared: String) -> String:
	var template := templates.get(template_id, {}) as Dictionary
	var variants := template.get("variants", []) as Array
	if not declared.is_empty():
		return declared
	if variants.is_empty():
		return ""
	return str(variants[0])


## 单间内容房 → 槽位。槽位自带本模板的**转置尺寸**（`rotated_size`）：供落位阶段
## 按连接方向二选一（见 `_placement_candidates`）。
##
## ⚠ 转置姿态**不是**一个独立房型 id（业主裁定 2026-09-25，见 05.2 §3.4/§3.6）：
## 它就是同一份模板绕竖轴转 90°，占位尺寸两分量互换。曾经的做法是在模板目录里再建
## 一个 `bridge_50x60` 并用 `axis_pose_of` 指回本体 —— 那会造出「两批代号」，同一间房
## 在两份文档里叫两个名字，管理必乱。现已撤销，全项目统一用 `template_rotation_deg`。
##
## ⚠ 「可取向」不等于「有短边封锁」，两者**必须分开判**（本轮踩过的坑）：
##   · 旧实现里「有取向」靠「模板声明了 `axis_pose_of` 配对」识别，恰好只有桥房有配对，
##     于是 `orientable` 一个字段兼职了两件事：可转置 + 长边封锁。
##   · 配对机制撤销后，若把「非正方形」当可取向，全体内容房（`db_70x50` / `office_60x70`
##     / `corridor_45x40` …）都会拿到 `orientable = true`，而该字段又驱动「父房的长边
##     封锁子房」⇒ 每条主路都被迫反复换轴，实测 300/300 个种子全部回落。
##   · 故本关只用桥房的**唯一功能判据** `sunken_pit`（= `_requires_short_edge_links`）
##     决定「可转置且长边封锁」，其余房型一律无取向，行为与改动前逐字相同。
##
## `rotated_size` 为 `Vector2.ZERO` 表示**本模板无取向** ⇒ 落位阶段不会为它做取向选择。
static func _constrained_slot(
	key: String, raw: Dictionary, templates: Dictionary, template_id: String, variant: String
) -> Dictionary:
	var template := templates[template_id] as Dictionary
	var size := _vec2(template.get("size_m", []))
	var short_edge_locked := _requires_short_edge_links(templates, template_id)
	return {
		"key": key,
		"room_id": str(raw.get("room_id", "")),
		"legacy_room_id": str(raw.get("legacy_room_id", "")),
		"room_type": str(raw.get("room_type", "")),
		"role": str(raw.get("role", "")),
		"parent_key": str(raw.get("parent_key", "")),
		"template_id": template_id,
		"template_variant": variant,
		"short_edge_locked": short_edge_locked,
		"rotated_size": _transposed_size(size) if short_edge_locked else Vector2.ZERO,
		"size": size,
		# —— 设计源房间级字段（与 `room_from_source` 的出口白名单同名）——
		# 槽位必须把这四项带到 `_constrained_floor_from`：那里产出的 rooms 会被
		# `generate_from_level_plan` 经 `room_from_source` 转成运行时房表，按
		# `content_type` / `boss_content_id` / `enemy_spawn_plan` / `reward_plan` 逐项取用。
		# 槽位漏带 = 设计源写了也被静默丢弃（2026-09-25 人报「刷怪批次与设计不符」的根因）。
		"content_type": str(raw.get("content_type", "")),
		"boss_content_id": str(raw.get("boss_content_id", "")),
		"enemy_spawn_plan": (raw.get("enemy_spawn_plan", {}) as Dictionary).duplicate(true),
		"reward_plan": (raw.get("reward_plan", {}) as Dictionary).duplicate(true),
		# 触发盒放置/调用：槽位必须带，否则 `_constrained_floor_from` 产出的房表
		# 在 `room_from_source` 处取到空 —— 与 2026-09-25「刷怪批次与设计不符」同一类坑。
		"spawn_placements": (raw.get("spawn_placements", []) as Array).duplicate(true),
		"encounter": (raw.get("encounter", {}) as Dictionary).duplicate(true),
		"spawn_boxes_only": bool(raw.get("spawn_boxes_only", false)),
	}


## —— 桥房族：取向随连接方向 ——
##
## 通道桥房（模板声明了 `sunken_pit`）带一条业主口径的**硬约束**：长边不连、只在短边开门。
## 长轴方向一并钉死「哪两面墙是短墙」⇒ 桥房的父边与全部子边都必须落在那对短墙上。
## 只许一种取向（长轴恒沿 x）时，「父—桥—子」被迫排成同一条水平线；而首房锚在正中，
## 单侧只剩约 122.5 m，`entry(15)+桥(60)+db(70)=145` 这类组合必然越界
## —— 实测 24 个种子回落 18 个（75%，见 `memory/0112`）。
##
## 解法（业主裁决 2026-09-25）：**取向不是房型属性，是落位属性** ——
## 连东/西用「长轴沿 x」的取向，连南/北用「长轴沿 y」的取向。门因此永远落在短边上，
## 而桥房族可以在水平 / 垂直两种排列间自由选择，不再被单一轴钉死。
##
## ⚠ 取向的载体只有**一份模板文件**：转置姿态就是同一张模板绕竖轴转 90°
## （设计源写法 `template_rotation_deg: 90`），占位尺寸由本函数现算。
## 曾短暂存在过「再建一个转置模板 id（`bridge_50x60`）+ `axis_pose_of` 指回本体」的做法，
## 已被业主裁定撤销 —— 同一间房在两份文档里叫两个名字必生混乱（「不要两批代号」），
## 全项目统一用旋转表达。房型池 `content_template_pool` 里因此只出现族代表（本体）。
static func _transposed_size(size: Vector2) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	if is_equal_approx(size.x, size.y):
		return Vector2.ZERO
	return Vector2(size.y, size.x)


## 取向选择：**短边法向 = 长轴方向** ⇒ 连东/西要「长轴沿 x」的那个取向，连南/北要「长轴沿 y」的。
## 无取向（`rotated_size` 为零：正方形或尺寸缺失）时恒返回本体尺寸，调用方不必再分支。
static func _axised_size_for(along_x: bool, base_size: Vector2, rotated_size: Vector2) -> Vector2:
	if rotated_size.x <= 0.0 or rotated_size.y <= 0.0:
		return base_size
	var base_long_x := base_size.x > base_size.y
	return base_size if along_x == base_long_x else rotated_size


## 桥房（可取向房）的**短边法向**两个方向：长轴沿 x ⇒ 短边是东/西墙 ⇒ {east, west}；
## 长轴沿 y ⇒ {north, south}。桥房的长边是「过道那一侧」，按业主口径不连任何房，
## 因此它的子房只许落在这两个方向里。
##
## 入参 `preferred` 是原本的方向试探序；本函数**保留其中属于允许集的顺序**
## （子房仍优先延续直行），再把允许集里剩下的补进末尾 —— 保证至少有一个方向可试。
static func _short_edge_directions(parent_size: Vector2, preferred: Array) -> Array:
	var allowed := ["east", "west"] if parent_size.x > parent_size.y else ["north", "south"]
	var ordered: Array = []
	for direction_value in preferred:
		if allowed.has(direction_value) and not ordered.has(direction_value):
			ordered.append(direction_value)
	for direction_value in allowed:
		if not ordered.has(direction_value):
			ordered.append(direction_value)
	return ordered


## 按槽位顺序贴墙摆放，**带回溯**。全部分配成功返回按槽位序的摆放表，否则返回空。
##
## 为什么必须回溯：单遍贪心在「大房把场地切成碎片」时只能整份作废重抽房型，
## 实测含大房的内容房池成功率只有 ~33%（且与尺寸强相关：只放 25×25 时 100%）。
## 回溯的代价很低 —— 每间房最多十来个候选位，而绝大多数情况第一个候选就成立。
##
## 首房锚在「与该尺寸同相位的原点」上（15×15 → (2.5,2.5)），全场再靠
## `_placement_candidates` 的**锚点软引导**蛇形展开 ⇒ 版图自然收拢，
## 不需要事后整体平移（平移反而会破坏贴墙净距为 0 的关系）。
## 这里**没有**场地边界约束 —— 见 `_constrained_fits` 的头注释。
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
	for candidate_value in _placement_candidates(slot, placed, rng):
		var candidate := candidate_value as Dictionary
		var center := candidate["center"] as Vector2
		placed.append({
			"key": str(slot["key"]),
			"center": center,
			# 桥房族的实际落位尺寸由**连接方向**决定（本体 / 转置），不等于槽位尺寸。
			"size": candidate["size"],
			"template_id": str(candidate.get("template_id", "")),
			"template_variant": str(candidate.get("template_variant", "")),
			"short_edge_locked": bool(candidate.get("short_edge_locked", false)),
			"rotation_deg": float(candidate.get("rotation_deg", 0.0)),
			"dir": _direction_from_delta(center - _parent_center(slot, placed)),
		})
		if _place_recursive(slots, index + 1, placed, rng, state):
			return true
		placed.pop_back()
	return false


## 一个候选落位点。带**实际尺寸与旋转角** —— 桥房族的尺寸由连接方向决定（本体 / 转置），
## 与槽位里存的本体不同，所以不能只留在槽位里。模板 id 不跟着换（转置只是旋转，
## 不是另一个房型），尺寸差异由 `rotation_deg` 解释。
static func _placement_candidate(
	center: Vector2, size: Vector2, slot: Dictionary, rotation_deg: float = 0.0
) -> Dictionary:
	return {
		"center": center,
		"size": size,
		"template_id": str(slot.get("template_id", "")),
		"template_variant": str(slot.get("template_variant", "")),
		"short_edge_locked": bool(slot.get("short_edge_locked", false)),
		"rotation_deg": rotation_deg,
	}


## —— 蛇形折返：方向序的锚点软引导 ——
##
## 主路房的候选方向按「该方向候选位离入口锚点的最近距离」升序重排 ⇒ 版图自然拐回来。
##
## 为什么要它：主路房的方向试探序以「延续来向」打头（成走廊感），而场地边界已退出
## 摆位剪枝（05.2 §3.7，2026-09-25 业主裁定 —— 任何位置只要不重叠就合法），
## 于是开阔场地里永远走得通、主路会一路直走出去（8 间主路房的半尺寸之和约 415 m）。
## 这是**软引导不是硬边界**：距离远的候选仍留在序里，关卡想长多大就长多大。
static func _anchored_direction_order(per_direction: Array, anchor: Vector2) -> Array:
	var order: Array[int] = []
	for index in range(per_direction.size()):
		order.append(index)
	# 距离相同时以**方向名的固定优先级**做 tie-break，**不再用数组下标**：
	# `per_direction` 的入序来自 `_direction_trial_order`，其 `rest` 段按种子打乱 ⇒
	# 下标随种子漂移，等距并列会翻方向 → 换门位 → 换变体轮廓 → 换砖格
	# （实测根因：钉死房型后 room_01 的砖格仍跨种子不一致）。
	# `sort_custom` 本身不稳定，故必须给一个与入序无关的全序键。
	order.sort_custom(func(a: int, b: int) -> bool:
		var entry_a := per_direction[a] as Dictionary
		var entry_b := per_direction[b] as Dictionary
		var distance_a := _direction_anchor_distance(entry_a["row"] as Array, anchor)
		var distance_b := _direction_anchor_distance(entry_b["row"] as Array, anchor)
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		return _direction_priority(str(entry_a["dir"])) < _direction_priority(str(entry_b["dir"]))
	)
	var out: Array = []
	for index in order:
		out.append(per_direction[index])
	return out


## 某个方向的候选行离锚点的最近距离；无候选时给 INF（排到最后）。
static func _direction_anchor_distance(row: Array, anchor: Vector2) -> float:
	var best := INF
	for candidate_value in row:
		var center := (candidate_value as Dictionary)["center"] as Vector2
		best = minf(best, center.distance_to(anchor))
	return best


## 方向的**固定**优先级：并列时用它定序，与种子无关。
## 为什么不用「来向优先」或数组下标：`_direction_trial_order` 的 `rest` 段按种子打乱，
## 下标随之漂移 ⇒ 等距并列会翻方向，进而换门位、换变体轮廓、换砖格。
## 钉死房型后我们要的是**每局同一张图**，故并列一律按本表（东→北→西→南）定序。
const DIRECTION_PRIORITY := {"east": 0, "north": 1, "west": 2, "south": 3}


static func _direction_priority(direction: String) -> int:
	return int(DIRECTION_PRIORITY.get(direction, 99))


## 第 `index` 个槽位当前可用的全部落位候选（已通过吸附 + 不重叠二连检查），
## 按「好位置优先」排序。首房/无父房只有一个候选（尺寸同相位的原点）。
##
## 桥房族在这里定**取向**：同一个方向枚举里，连东/西用长轴沿 x 的取向、连南/北用长轴沿 y 的，
## 门因此永远落在短墙上。父房是桥房时反向收窄 —— 子房只许落在父房的短边法向那一对上
## （桥房的长边按业主口径不连任何房）。
##
## 主路房另叠一层蛇形折返软引导，见 `_anchored_direction_order`。
static func _placement_candidates(
	slot: Dictionary, placed: Array[Dictionary], rng: RandomNumberGenerator
) -> Array:
	var size := slot["size"] as Vector2
	var parent_key := str(slot.get("parent_key", ""))
	if placed.is_empty() or parent_key.is_empty():
		var origin := _snapped_origin_for(size)
		if _constrained_fits(origin, size, _placed_rects(placed)):
			return [_placement_candidate(origin, size, slot)]
		return []
	var parent_index := _placed_index_by_key(placed, parent_key)
	if parent_index < 0:
		return []
	var parent_room := placed[parent_index] as Dictionary
	var parent_center := parent_room["center"] as Vector2
	var parent_size := parent_room["size"] as Vector2
	var rects := _placed_rects(placed)
	# 桥房族：长轴方向由落位方向定，短边随之固定；槽位里带着本模板的转置尺寸。
	var rotated_size := slot.get("rotated_size", Vector2.ZERO) as Vector2
	var directions := _direction_trial_order(
		str(slot.get("role", "")), _incoming_dir(placed, parent_index), rng
	)
	# 父房是桥房 ⇒ **长边封锁**：子房只许贴在它那对短墙上。
	# 判据用 `short_edge_locked`（= 模板声明 `sunken_pit`），**不是**「父房可转置」——
	# 两者在本关恰好同义，但混用会误伤：见 `_constrained_slot` 头注释里的踩坑记录。
	if bool(parent_room.get("short_edge_locked", false)):
		directions = _short_edge_directions(parent_size, directions)
	# 先按方向收集每个方向的候选（各自已按「横向离父房近 → 远」排好）。
	var per_direction: Array = []
	for direction_value in directions:
		var direction := str(direction_value)
		var along_x := direction == "east" or direction == "west"
		var child_size := _axised_size_for(along_x, size, rotated_size)
		var rotation_deg := 0.0
		if not child_size.is_equal_approx(size):
			# 转置姿态 = 同一张模板转 90°（不是另一个房型 id）。校验器按
			# `template_rotation_deg` 解析期望尺寸 ⇒ 尺寸换了就必须把角度写上，
			# 否则 `room_size_differs_from_template` 必红。
			rotation_deg = 90.0
		var parent_cross := parent_center.y if along_x else parent_center.x
		var child_cross_size := child_size.y if along_x else child_size.x
		var row: Array = []
		for cross in _lateral_candidates(parent_cross, child_cross_size):
			var center := _touching_center(parent_center, parent_size, child_size, direction, cross)
			if _constrained_fits(center, child_size, rects):
				row.append(_placement_candidate(center, child_size, slot, rotation_deg))
		# 行里带上方向名：`_anchored_direction_order` 的并列 tie-break 要用它。
		# 只用「行」时 tie-break 只能退回数组下标，而下标继承 `_direction_trial_order`
		# 里被种子打乱的 `rest` 序 ⇒ 等距时会翻方向、进而换门位、换变体轮廓、换砖格
		# （实测：同房型同变体的 room_01 在三个种子下砖格不一致的根因）。
		per_direction.append({"dir": direction, "row": row})
	# 主路房走锚点软引导（折返），支线房保持「先垂直侧向」的原序不动。
	if str(slot.get("role", "")) != "branch":
		per_direction = _anchored_direction_order(per_direction, placed[0]["center"] as Vector2)
	# 再**按横向名次轮转**跨方向取：先各方向的第 1 候选，再各方向的第 2 候选……
	# 这样截断到 `CONSTRAINED_BRANCH_LIMIT` 个后，仍能覆盖多个方向，
	# 不至于只把「首选方向」的候选全试完、其它方向一个都没轮到。
	var result: Array = []
	var rank := 0
	var progressed := true
	while progressed and result.size() < CONSTRAINED_BRANCH_LIMIT:
		progressed = false
		for entry_value in per_direction:
			var row := (entry_value as Dictionary)["row"] as Array
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


## 位置合法性二连：中心吸附在 5m 模数上、与已摆房间不重叠（相切允许）。
##
## **场地边界自 2026-09-25 起不再是判据**（业主裁定，全项目适用）：摆位不再拒绝
## 「超出 250×250 场地」的位置，`MAP_SIZE_M` 退出本类。理由见 05.2 §3.7 ——
## 单层独立关卡没有边界预算，面积只报数字、不设上限。
##
## ⚠ 但旧实现里那条边界检查**同时兼任了「逼路径拐弯」的职责**：主路房的试探序以
## 「延续来向」打头（成走廊感），开阔场地里永远不撞别的房 ⇒ 没有边界逼停就会一路直走
## （8 间主路房的半尺寸之和约 415 m）。折返职责**已迁到 `_placement_candidates` 的
## 锚点距离软引导**（按「候选位离入口锚点的距离」排方向），那里不设任何硬上限 ——
## 版图该多大就多大，只是自然会拐回来。
static func _constrained_fits(center: Vector2, size: Vector2, rects: Array[Rect2]) -> bool:
	var rect := _rect_at(center, size)
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
	var placed_by_key: Dictionary = {}
	for value in placed:
		var placed_room := value as Dictionary
		placed_by_key[str(placed_room["key"])] = placed_room
	var rooms: Array[Dictionary] = []
	for value in slots:
		var slot := value as Dictionary
		var key := str(slot["key"])
		if not placed_by_key.has(key):
			return {}
		# 房型与尺寸都以**落位结果**为准：桥房族的 template_id / size 由落位方向决定
		# （本体或转置姿态），槽位里存的是本体，落位时才可能被换成转置。
		var placed_room := placed_by_key[key] as Dictionary
		rooms.append({
			"key": key,
			"room_id": str(slot.get("room_id", "")),
			"legacy_room_id": str(slot.get("legacy_room_id", "")),
			"room_type": str(slot.get("room_type", "")),
			"role": str(slot.get("role", "")),
			"parent_key": str(slot.get("parent_key", "")),
			"template_id": str(placed_room.get("template_id", slot.get("template_id", ""))),
			"template_variant": str(
				placed_room.get("template_variant", slot.get("template_variant", ""))
			),
			"center": placed_room["center"],
			"size": placed_room["size"],
			# 转置姿态（同一张模板旋转 90°）由落位阶段定，必须带回房间记录 ——
			# 校验器 `expected_size_for_rotation` 靠它把转置尺寸认成合法。
			"rotation_deg": float(placed_room.get("rotation_deg", 0.0)),
			# 设计源房间级字段从槽位透传（槽位由 `_constrained_slot` 从 L2 房表带出）。
			# 口径与 `room_from_source` 的出口白名单一致：本层只搬运、不解释。
			# 这四项曾被硬写空 ⇒ 设计源即便声明了也被静默丢弃，运行时恒回退公式波次。
			"content_type": str(slot.get("content_type", "")),
			"boss_content_id": str(slot.get("boss_content_id", "")),
			"enemy_spawn_plan": (slot.get("enemy_spawn_plan", {}) as Dictionary).duplicate(true),
			"reward_plan": (slot.get("reward_plan", {}) as Dictionary).duplicate(true),
			# 触发盒放置/调用（触发器刷怪设计 §3.2 / §3.3）：与上列字段同口径，
			# 本层只搬运不解释。这四项曾因硬写空而静默丢弃过，别再犯。
			"spawn_placements": (slot.get("spawn_placements", []) as Array).duplicate(true),
			"encounter": (slot.get("encounter", {}) as Dictionary).duplicate(true),
			"spawn_boxes_only": bool(slot.get("spawn_boxes_only", false)),
			"declared_ports": [],
			"ports": [],
			"ports_derived": false,
		})
	LEVEL_PLAN_LOADER.derive_ports(rooms)
	# 「只认盒子」标记逐房下发（与 normalize_floor 同一口径，禁止分叉）。
	if bool(blueprint.get("spawn_boxes_only", false)):
		for room_value: Dictionary in rooms:
			room_value["spawn_boxes_only"] = true
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
		# 触发器刷怪（设计 §7-A）：只认盒子层。true ⇒ 敌对房无实例即不刷怪。
		# 本层必须透传，否则「没盒子就不刷」在 constrained 模式下静默失效。
		"spawn_boxes_only": bool(blueprint.get("spawn_boxes_only", false)),
		# 几何权威性：本结构的 `center` / `size` 是**生成器按种子算出的真几何**
		# （`placed_room` 的实测值），不是 L2 文件里的样例 ⇒ 置真，放行校验器里
		# 依赖真实尺寸的判据（盒越界 / 贴墙内缩 / 砖心相位）。
		# 与 `LevelPlanLoader.normalize_floor` 的 `mode == "constrained" ⇒ false` 成对：
		# 同一份结构，读文件得到 false、生成器算完覆写 true。缺任一侧，门禁就会
		# 「要么全盲（样例几何照样判、误报），要么全哑（真几何也不判、漏报）」。
		"geometry_authoritative": true,
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
		# 02 已冻结的房型默认布局优先于运行时通用壳体。成功读取后直接把完整实例清单
		# 写入现有 authored_layout_instances 通道；办公室和桥房都不再叠加第二套程序化视觉。
		var room_type_layout := _room_type_layout_for_room(room)
		if not room_type_layout.is_empty():
			room["authored_layout_shell"] = true
			room["authored_layout_asset_id"] = str(room_type_layout.get("asset_id", ""))
			room["authored_layout_version"] = str(room_type_layout.get("version", ""))
			room["authored_layout_room_id"] = key
			room["authored_layout_peaceful"] = false
			room["authored_layout_instances"] = (
				room_type_layout.get("instances", []) as Array
			).duplicate(true)
			if str(room.get("template_id", "")) == "bridge_60x50":
				room["authored_layout_multi_level_room"] = true
			continue
		# 多层几何规划（仅未接入正式房型组件库的通道桥房有内容）：坑/桥矩形 + 三层几何实例。
		# bridge_60x50 的 v007 完整布局在上方已 continue，绝不会再叠加旧程序化坑/桥视觉。
		var multi_level := _bridge_multi_level_plan(room, templates)
		var pit_rect := Rect2()
		var bridge_rect := Rect2()
		if not multi_level.is_empty():
			pit_rect = multi_level.get("pit_rect", Rect2()) as Rect2
			bridge_rect = multi_level.get("bridge_rect", Rect2()) as Rect2
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
			# 通道桥房：坑区（桥面那 6 格除外）不铺上层地砖 —— 那里是 12m 深的洞，
			# 砖落到坑底（见第 6 环 `_bridge_multi_level_plan`）。桥面格保留原砖：
			# 它本来就在 y=0，只是四周从「平台」变成「悬空桥面」。
			if not multi_level.is_empty() and str(instance.get("slot_role", "")) == "floor_tile":
				var cell := instance.get("position", Vector3.ZERO) as Vector3
				var cell_xy := Vector2(cell.x, cell.z)
				if pit_rect.has_point(cell_xy) and not bridge_rect.has_point(cell_xy):
					continue
			filtered.append(instance)
		# 专属件（Boss 房 6 件）叠加在通用壳体之上：它们**不是落地件**，坐标直接取摆位源。
		if str(room.get("role", "")) == "boss":
			filtered.append_array(_boss_room_exclusive_instances(room, boss_layout))
		# 多层件（通道桥房坑壁/护栏/坑底砖）同样叠加在通用壳体之上。
		if not multi_level.is_empty():
			filtered.append_array(multi_level.get("instances", []) as Array)
			room["authored_layout_multi_level_room"] = true
		room["authored_layout_shell"] = true
		room["authored_layout_asset_id"] = "EXPEDITION-GENERIC-SHELL-%s" % key.to_upper()
		room["authored_layout_version"] = "runtime_generated"
		room["authored_layout_room_id"] = key
		room["authored_layout_peaceful"] = false
		room["authored_layout_instances"] = filtered


## —— 房型默认布局：02 的 component_instances.json → authored_layout_instances ——
##
## 一个 component_id 对应一个稳定 PackedScene；本函数只搬运实例变换，并从运行时 catalog
## 读取 slot_role。Blender 平面 XY / 垂直 Z 转为 Godot XZ / 垂直 Y：
## `(bx, by, bz) -> (bx, bz, -by)`；历史字段 rotation_y_deg 在 Blender 端实际是绕 Z，
## 转换后直接成为 Godot rotation.y，禁止重复转轴。
static func _room_type_layout_for_room(room: Dictionary) -> Dictionary:
	var template_id := str(room.get("template_id", ""))
	if not ROOM_TYPE_LAYOUT_SOURCES.has(template_id):
		return {}
	var source_spec := ROOM_TYPE_LAYOUT_SOURCES[template_id] as Dictionary
	var want_size := source_spec.get("size_m", Vector2.ZERO) as Vector2
	var got_size := room.get("size", Vector2.ZERO) as Vector2
	var room_rotation := float(room.get("rotation_deg", 0.0))
	if is_equal_approx(fposmod(room_rotation, 180.0), 90.0):
		want_size = Vector2(want_size.y, want_size.x)
	if absf(want_size.x - got_size.x) > CONSTRAINED_EPS or absf(want_size.y - got_size.y) > CONSTRAINED_EPS:
		push_error(
			"FloorPlanGenerator: 房型 %s 的运行尺寸 %s 与组件布局期望 %s 不符"
			% [template_id, str(got_size), str(want_size)]
		)
		return {}
	var source_path := str(source_spec.get("path", ""))
	var source := _read_json_dictionary(source_path, "房型组件布局")
	if source.is_empty():
		return {}
	var catalog_roles := _load_shell_component_roles()
	if catalog_roles.is_empty():
		return {}
	var expected_count := int((source.get("validation", {}) as Dictionary).get("instance_count", -1))
	var instances: Array = []
	for value in source.get("instances", []):
		if not (value is Dictionary):
			push_error("FloorPlanGenerator: 房型 %s 的 instances[] 含非对象条目" % template_id)
			return {}
		var item := value as Dictionary
		var component_id := str(item.get("component_id", ""))
		if component_id.is_empty() or not catalog_roles.has(component_id):
			push_error(
				"FloorPlanGenerator: 房型 %s 的组件 %s 未登记 slot_role"
				% [template_id, component_id]
			)
			return {}
		var raw_position: Variant = item.get("position_m", [])
		var raw_scale: Variant = item.get("scale", [])
		if not (raw_position is Array) or (raw_position as Array).size() != 3:
			push_error("FloorPlanGenerator: 房型实例 %s 的 position_m 不是三元组" % str(item.get("instance_id", "")))
			return {}
		if not (raw_scale is Array) or (raw_scale as Array).size() != 3:
			push_error("FloorPlanGenerator: 房型实例 %s 的 scale 不是三元组" % str(item.get("instance_id", "")))
			return {}
		var p := raw_position as Array
		var s := raw_scale as Array
		var local_position := Vector3(float(p[0]), float(p[2]), -float(p[1]))
		var local_rotation := float(item.get("rotation_y_deg", 0.0))
		if not is_zero_approx(room_rotation):
			local_position = local_position.rotated(Vector3.UP, deg_to_rad(room_rotation))
			local_rotation += room_rotation
		var role := str(catalog_roles[component_id])
		# 只有主层地砖进入 floor_tile；坑底 tile_lower 在 catalog 中是普通房型视觉件，
		# 因而不会进入 _authored_tile_cells，也不会参与主层刷怪格。
		instances.append({
			"name": str(item.get("instance_id", "RoomTypeComponent")),
			"component_id": component_id,
			"slot_role": role,
			"position": local_position,
			"rotation_y_deg": local_rotation,
			"scale": Vector3(float(s[0]), float(s[2]), float(s[1])),
			"preserve_authored_y": true,
			"door_wall_component_id": str(source_spec.get("door_wall_component_id", "")),
		})
	if expected_count >= 0 and instances.size() != expected_count:
		push_error(
			"FloorPlanGenerator: 房型 %s 实例数 %d 与 validation.instance_count=%d 不符"
			% [template_id, instances.size(), expected_count]
		)
		return {}
	return {
		"asset_id": str(source_spec.get("asset_id", "")),
		"version": str(source_spec.get("version", "")),
		"instances": instances,
	}


static func _load_shell_component_roles() -> Dictionary:
	var source := _read_json_dictionary(SHELL_COMPONENT_CATALOG_PATH, "壳体组件注册表")
	if source.is_empty():
		return {}
	var result: Dictionary = {}
	for value in source.get("components", []):
		if not (value is Dictionary):
			push_error("FloorPlanGenerator: 壳体组件注册表 components[] 含非对象条目")
			return {}
		var entry := value as Dictionary
		var component_id := str(entry.get("component_id", ""))
		var role := str(entry.get("slot_role", ""))
		if component_id.is_empty() or role.is_empty() or result.has(component_id):
			push_error("FloorPlanGenerator: 壳体组件注册表 ID/slot_role 非法或重复（%s）" % component_id)
			return {}
		result[component_id] = role
		for alias_value in entry.get("aliases", []):
			var alias := str(alias_value)
			if alias.is_empty() or result.has(alias):
				push_error("FloorPlanGenerator: 壳体组件注册表 alias 非法或重复（%s）" % alias)
				return {}
			result[alias] = role
	return result


static func _read_json_dictionary(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("FloorPlanGenerator: %s缺失 %s" % [label, path])
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("FloorPlanGenerator: %s为空 %s" % [label, path])
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("FloorPlanGenerator: %s不是 JSON 对象 %s" % [label, path])
		return {}
	return parsed as Dictionary


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



## —— 第 6 环（多层几何）：通道桥房的下沉坑 + 跨桥 ——
##
## 本关唯一多层几何房型（桥块族 `bridge_60x50`，只有这一张模板；取向不是第二个 id，
## 而是**同一张模板旋转 90°** `template_rotation_deg: 90` —— 桥沿 x 跨 / 桥沿 z 跨，
## 尺寸与坑/桥矩形同时互转）：
## 四周 15m 宽上层平台、中央 30×20 下沉坑
## （深 12m = 一整层层高）、一座 5m 宽桥横跨坑顶。模板已声明 `sunken_pit` / `bridge_span`
## （坐标口径 = 模板自有 `bbox_nw_x_east_y_south`，与 `variant_footprints` 同源），
## 但组合器 `build_block()` 的输入契约是「轴对齐矩形 + 四面墙 + 门位 + 单水平面」，
## 装不下「同一房内的第二个水平面」⇒ 多层件走这条独立通路，与 Boss 房专属件同模式：
## 叠加在通用壳体之上，**不参与 lane 归属模型**（不占 lane、不进 wall_lanes）。
##
## ⚠ **两种取向都必须通**：坑壁开口与桥侧护栏按轴解算（`_bridge_pit_edge_open()`），
## 任何一轴写死都会让另一种取向的桥不通（详见该函数头注释）。
##
## 三层几何（全部落在 5m 格心/格线上，与地砖同模数）：
##   ① **上层平台**：通用地砖照旧铺满房内，但**扣掉坑区格**；桥面那 6 格保留 ——
##      它本来就在 y=0，只是四周从「平台」变成「悬空桥面」。
##   ② **坑壁 + 护栏**：一件标准墙件纵向拉伸到 `坑深 + 护栏高`，沿坑四周与桥两侧各铺一排。
##      坑壁在**桥实际贴到的那两条坑沿**上留口；桥侧护栏沿**桥的长轴**排在桥的两条长边上
##      （本体 → 开口在东西壁、护栏沿 x；转置姿态 → 开口在南北壁、护栏沿 z）。
##      **护栏与坑壁共用同一件墙**（业主裁决 2026-09-25「坑沿加护栏」）：墙顶露在地面上
##      0.8m 即护栏，与坑壁同材质、视觉连贯，不需要一件新资产。
##      ⚠ 玩家**没有跳跃能力**（`Player3D` 状态机无 jump 态、InputMap 无跳跃 action）
##        ⇒ 0.8m 足够挡人 ⇒ 坑区**保留承重**（`TowerFloorStage3D._build_support()`
##        照旧铺满）。因此本环**不碰承重系统**，玩家客观上也掉不进坑。
##   ③ **坑底**：通用地砖满铺坑区（30×20 = 6×4 = 24 块）在 `y = −坑深`。
##      **不可达纯装饰**（裁决「下层下不去、就是装饰」）：不做楼梯/坡道/梯井，
##      内嵌静态碰撞在装配层照常关掉（承重归上层，坑底不是走行面）。
##
## ⚠ **多层墙件不写 `tower_wall_direction`**：坑壁不是房间外墙，写上去会被门槽判据
##   （`DungeonRoom3D.classify_door_lane`）与塔楼墙验收当成房墙统计 ⇒ 门槽归属与墙数全错。
##
## 坐标换算（模板 → 房局部）：`x = vx − size.x/2`、`z = vy − size.y/2`。
## 与 `_authored_shell_block_room()` 的 `bx = bounds_x_m[0] + vx` 等价
## （`bounds_x_m[0] = center.x − size.x/2` ⇒ `bx − center.x = vx − size.x/2`，z 同理经
## `to_runtime_instances` 的 `−(by − cby)` 后同样归到 `vy − size.y/2`）。
const MULTI_LEVEL_SLOT_ROLE := "multi_level_component"
const MULTI_LEVEL_PART_PIT_WALL := "pit_wall"
const MULTI_LEVEL_PART_PIT_FLOOR_TILE := "pit_floor_tile"
const COMPONENT_WALL_STANDARD_5M := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"
const COMPONENT_FLOOR_TILE_C01 := "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01"
const COMPONENT_FLOOR_TILE_C02 := "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C02"
## 坑深兜底值（模板 `sunken_pit.depth_m` 缺失时用）。= 一整层层高（`FLOOR_HEIGHT_M`）。
const MULTI_LEVEL_PIT_DEPTH_M := 12.0
## 标准墙件可视高（`shell_component_catalog.json` 的 `bounds_size_m_godot[1]`）：
## 坑壁靠**纵向拉伸**一件墙同时拿到「坑深 + 护栏高」。
const MULTI_LEVEL_WALL_HEIGHT_M := 11.9
## 坑沿护栏高（业主裁决 2026-09-25）。玩家无跳跃 ⇒ 0.8m 足够挡人。
const MULTI_LEVEL_RAILING_HEIGHT_M := 0.8
## 多层墙件的装饰面法向（值 = `rotation_y_deg`）。墙件 `forward_axis = -Z`、装饰面朝局部 −Z，
## 于是 0° 朝世界 −z、180° 朝 +z、90° 朝 −x、−90° 朝 +x。
## 与 `RoomShellLayoutBuilder3D.FACE_IN_ROTATION_DEG` 同源（south=0 的墙坐在房南侧、
## 装饰面朝房内那颗 −z）。
const MULTI_LEVEL_FACE_NEG_Z := 0.0
const MULTI_LEVEL_FACE_POS_Z := 180.0
const MULTI_LEVEL_FACE_NEG_X := 90.0
const MULTI_LEVEL_FACE_POS_X := -90.0
## 「桥边贴合坑沿 / 桥长轴分派」的坐标容差（两端都是 5m 模数算出来的数，取 0.01 足够）。
const MULTI_LEVEL_EPS := 0.01


## 通道桥多层几何的规划结果：坑/桥矩形（房局部）＋ 三层几何实例清单。
## 非通道桥房（模板没有 `sunken_pit`）返回空字典 ⇒ 调用方整段跳过，行为逐字不变。
static func _bridge_multi_level_plan(room: Dictionary, templates: Dictionary) -> Dictionary:
	var template_id := str(room.get("template_id", ""))
	if template_id.is_empty() or templates.is_empty() or not templates.has(template_id):
		return {}
	var template := templates[template_id] as Dictionary
	var pit_value: Variant = template.get("sunken_pit")
	if not (pit_value is Dictionary):
		return {}
	var size := room.get("size", Vector2.ZERO) as Vector2
	if size.x <= 0.0 or size.y <= 0.0:
		return {}
	# 转置姿态（同模板旋转 90°）：模板的 `sunken_pit` / `bridge_span` 矩形是按**本体**
	# 坐标声明的，转置房里必须把两侧互换后再换算 —— 否则坑与桥会落到错的位置。
	var rotated := _is_rotated_size(size, _vec2(template.get("size_m", [])))
	var depth := float((pit_value as Dictionary).get("depth_m", MULTI_LEVEL_PIT_DEPTH_M))
	if depth <= 0.0:
		push_error(
			"FloorPlanGenerator: 房间 %s 的模板 %s 声明了 sunken_pit 但 depth_m 非法（%s）"
			% [str(room.get("key", "")), template_id, str(depth)]
		)
		return {}
	var pit_rect := _template_rect_to_local(
		(pit_value as Dictionary).get("rect_m", {}) as Dictionary, size, rotated
	)
	if pit_rect.size.x <= 0.0 or pit_rect.size.y <= 0.0:
		push_error(
			"FloorPlanGenerator: 房间 %s 的模板 %s 的 sunken_pit.rect_m 非法"
			% [str(room.get("key", "")), template_id]
		)
		return {}
	var bridge_rect := Rect2()
	var span_value: Variant = template.get("bridge_span")
	if span_value is Dictionary:
		bridge_rect = _template_rect_to_local(
			(span_value as Dictionary).get("rect_m", {}) as Dictionary, size, rotated
		)
	return {
		"pit_rect": pit_rect,
		"bridge_rect": bridge_rect,
		"depth_m": depth,
		"instances": _bridge_multi_level_instances(room, pit_rect, bridge_rect, depth),
	}


## 房记录里的尺寸是否是模板的「转置姿态」：非正方形、且两分量互换。
## 与校验器 `LevelPlanValidator.expected_size_for_rotation` 同一判据 —— 那边读
## `rotation_deg`，这边从尺寸反推。两侧必须一致，否则生成器摆出来的坑位与校验器
## 认的房尺寸会互相打架。
static func _is_rotated_size(size: Vector2, template_size: Vector2) -> bool:
	if template_size.x <= 0.0 or template_size.y <= 0.0:
		return false
	if is_equal_approx(template_size.x, template_size.y):
		return false
	return (
		is_equal_approx(size.x, template_size.y)
		and is_equal_approx(size.y, template_size.x)
	)


## 模板 `rect_m`（`{x: [vx0, vx1], y: [vy0, vy1]}`，`bbox_nw_x_east_y_south` 口径）
## → 房局部 `Rect2`（x 向东、y 即 z 向南，原点 = 房中心）。口径见上一条头注释。
##
## `rotated = true`（转置姿态）时模板的 `(vx, vy)` 对应房局部的 `(vy, vx)`：
## 两侧互换即可沿用同一套公式 —— 调用方传进来的 `size` 已经是转置后的尺寸
## （宽 = 模板高），故不需要再改公式本身。
static func _template_rect_to_local(
	rect_m: Dictionary, size: Vector2, rotated: bool = false
) -> Rect2:
	var xs: Variant = rect_m.get("x", [])
	var ys: Variant = rect_m.get("y", [])
	if not (xs is Array) or not (ys is Array):
		return Rect2()
	if (xs as Array).size() != 2 or (ys as Array).size() != 2:
		return Rect2()
	var x_values := xs as Array
	var y_values := ys as Array
	if rotated:
		x_values = ys as Array
		y_values = xs as Array
	var lx0 := float(x_values[0]) - size.x * 0.5
	var lx1 := float(x_values[1]) - size.x * 0.5
	var lz0 := float(y_values[0]) - size.y * 0.5
	var lz1 := float(y_values[1]) - size.y * 0.5
	return Rect2(
		Vector2(minf(lx0, lx1), minf(lz0, lz1)),
		Vector2(absf(lx1 - lx0), absf(lz1 - lz0))
	)


## 区间（端点落在 5m 格线上）内的 5m 格心列表。与地砖格心同一模数（全局 `5k + 2.5`）。
static func _multi_level_lane_centers(min_m: float, max_m: float) -> Array[float]:
	var centers: Array[float] = []
	var count := int(round((max_m - min_m) / GRID_UNIT_M))
	for index in range(count):
		centers.append(min_m + GRID_UNIT_M * (float(index) + 0.5))
	return centers


## 桥跨是否在这条坑沿上开了口。
##
## `along_x = true` 表示这条坑沿**沿 x 走向**（即 z = `edge_m` 的南/北壁），此时判
## 桥矩形的 z 边是否贴到它；`false` 表示沿 z 走向（x = `edge_m` 的东西壁），判 x 边。
## 为什么要这个判据：桥块族有**两种取向**（本体桥沿 x 跨、`template_rotation_deg: 90`
## 转置后桥沿 z 跨），桥口必须开在**桥实际贴到的那两条坑沿**上。
## 旧实现把「桥口开在东西壁、护栏排在 z=z0/z1」写死了 —— 那只对本体成立；转置姿态下
## 南北壁不留口（玩家上不了桥）、东西壁被整片删掉（坑少两面壁）、护栏还会横在桥两端
## 把桥堵死。故本判据与 `_bridge_multi_level_instances()` 的护栏分派一起按轴解算。
static func _bridge_pit_edge_open(bridge: Rect2, along_x: bool, edge_m: float) -> bool:
	if bridge.size.x <= 0.0 or bridge.size.y <= 0.0:
		return false
	if along_x:
		return (
			absf(bridge.position.y - edge_m) <= MULTI_LEVEL_EPS
			or absf(bridge.position.y + bridge.size.y - edge_m) <= MULTI_LEVEL_EPS
		)
	return (
		absf(bridge.position.x - edge_m) <= MULTI_LEVEL_EPS
		or absf(bridge.position.x + bridge.size.x - edge_m) <= MULTI_LEVEL_EPS
	)


## 三层几何实例清单（房局部坐标，形状与通用件逐字同构 + 一个 `part` 分派键）。
## `part = pit_wall` 走墙件语义（自带碰撞、承担阴影、按 `scale_y` 拉伸）；
## `part = pit_floor_tile` 走地砖语义（关内嵌碰撞、按 `snap_to_walk_plane_offset_m` 吸地）。
##
## ⚠ 坑壁与桥侧护栏**都必须按轴解算**（见 `_bridge_pit_edge_open` 头注释）：桥块族两种
## 取向的坑长轴互转，写死任何一轴都会让另一种取向的桥不通。
static func _bridge_multi_level_instances(
	room: Dictionary, pit: Rect2, bridge: Rect2, depth: float
) -> Array:
	var tag := str(room.get("key", "")).to_upper()
	var instances: Array = []
	var counter := 0
	# 墙件原点 = 底面中心、可视高 11.9m ⇒ 一条 `scale_y` 就同时给出坑深与地上护栏。
	var wall_scale_y := (depth + MULTI_LEVEL_RAILING_HEIGHT_M) / MULTI_LEVEL_WALL_HEIGHT_M
	var pit_x0 := pit.position.x
	var pit_x1 := pit.position.x + pit.size.x
	var pit_z0 := pit.position.y
	var pit_z1 := pit.position.y + pit.size.y
	var lane_xs := _multi_level_lane_centers(pit_x0, pit_x1)
	var lane_zs := _multi_level_lane_centers(pit_z0, pit_z1)
	var has_bridge := bridge.size.x > 0.0 and bridge.size.y > 0.0
	var bridge_x0 := bridge.position.x
	var bridge_x1 := bridge.position.x + bridge.size.x
	var bridge_z0 := bridge.position.y
	var bridge_z1 := bridge.position.y + bridge.size.y
	# 四条坑沿各自是否被桥跨开口。
	var open_north := _bridge_pit_edge_open(bridge, true, pit_z0)
	var open_south := _bridge_pit_edge_open(bridge, true, pit_z1)
	var open_west := _bridge_pit_edge_open(bridge, false, pit_x0)
	var open_east := _bridge_pit_edge_open(bridge, false, pit_x1)
	# ① 坑四周壁。装饰面朝**背离坑心**的一侧（= 玩家所在的平台侧）：玩家在平台上
	# 平视护栏、俯瞰坑壁，看到的都是这一面 ⇒ 装饰面不浪费。
	# 开口判据与旧实现同口径：格心**严格落在桥跨区间内**才算（桥跨恰与坑同长时，
	# 端点那一格不算开口）。
	for center_x in lane_xs:
		if not (open_north and center_x > bridge_x0 and center_x < bridge_x1):
			counter += 1
			instances.append(_pit_wall_instance(
				"PIT_WALL_%s_%02d" % [tag, counter], Vector3(center_x, -depth, pit_z0),
				MULTI_LEVEL_FACE_NEG_Z, wall_scale_y
			))
		if not (open_south and center_x > bridge_x0 and center_x < bridge_x1):
			counter += 1
			instances.append(_pit_wall_instance(
				"PIT_WALL_%s_%02d" % [tag, counter], Vector3(center_x, -depth, pit_z1),
				MULTI_LEVEL_FACE_POS_Z, wall_scale_y
			))
	for center_z in lane_zs:
		if not (open_west and center_z > bridge_z0 and center_z < bridge_z1):
			counter += 1
			instances.append(_pit_wall_instance(
				"PIT_WALL_%s_%02d" % [tag, counter], Vector3(pit_x0, -depth, center_z),
				MULTI_LEVEL_FACE_NEG_X, wall_scale_y
			))
		if not (open_east and center_z > bridge_z0 and center_z < bridge_z1):
			counter += 1
			instances.append(_pit_wall_instance(
				"PIT_WALL_%s_%02d" % [tag, counter], Vector3(pit_x1, -depth, center_z),
				MULTI_LEVEL_FACE_POS_X, wall_scale_y
			))
	# ② 桥两侧壁：同时是桥面护栏与桥的支撑壁（从桥面下延到坑底）。
	# 护栏沿**桥的长轴**排、坐在桥的两条长边上，朝向朝**桥面内侧**（玩家站在桥上，
	# 看到的是这两面）。长轴判据用 `>=`：桥恰好正方形时按 x 向处理（坑本身不是正方形，
	# 不会走到这一支）。
	if has_bridge:
		if bridge.size.x >= bridge.size.y:
			for center_x in _multi_level_lane_centers(bridge_x0, bridge_x1):
				counter += 1
				instances.append(_pit_wall_instance(
					"PIT_BRIDGE_%s_%02d" % [tag, counter],
					Vector3(center_x, -depth, bridge_z0), MULTI_LEVEL_FACE_POS_Z, wall_scale_y
				))
				counter += 1
				instances.append(_pit_wall_instance(
					"PIT_BRIDGE_%s_%02d" % [tag, counter],
					Vector3(center_x, -depth, bridge_z1), MULTI_LEVEL_FACE_NEG_Z, wall_scale_y
				))
		else:
			for center_z in _multi_level_lane_centers(bridge_z0, bridge_z1):
				counter += 1
				instances.append(_pit_wall_instance(
					"PIT_BRIDGE_%s_%02d" % [tag, counter],
					Vector3(bridge_x0, -depth, center_z), MULTI_LEVEL_FACE_POS_X, wall_scale_y
				))
				counter += 1
				instances.append(_pit_wall_instance(
					"PIT_BRIDGE_%s_%02d" % [tag, counter],
					Vector3(bridge_x1, -depth, center_z), MULTI_LEVEL_FACE_NEG_X, wall_scale_y
				))
	# ③ 坑底地砖（满铺坑区，棋盘格与上层同规则）。
	for i in range(lane_xs.size()):
		for j in range(lane_zs.size()):
			var is_c01 := (i + j) % 2 == 0
			instances.append({
				"name": "PIT_FLOOR_%s_R%02d_C%02d" % [tag, j + 1, i + 1],
				"component_id": COMPONENT_FLOOR_TILE_C01 if is_c01 else COMPONENT_FLOOR_TILE_C02,
				"slot_role": MULTI_LEVEL_SLOT_ROLE,
				"part": MULTI_LEVEL_PART_PIT_FLOOR_TILE,
				# y = 坑底**走行面**标高；装配层再按砖件自己的 `snap_to_walk_plane_offset_m`
				# 把砖顶面抬到该标高（与上层地砖 `position.y = snap_offset` 同口径）。
				"position": Vector3(lane_xs[i], -depth, lane_zs[j]),
				"rotation_y_deg": 0.0,
			})
	return instances


static func _pit_wall_instance(
	instance_name: String, position: Vector3, rotation_y_deg: float, scale_y: float
) -> Dictionary:
	return {
		"name": instance_name,
		"component_id": COMPONENT_WALL_STANDARD_5M,
		"slot_role": MULTI_LEVEL_SLOT_ROLE,
		"part": MULTI_LEVEL_PART_PIT_WALL,
		"position": position,
		"rotation_y_deg": rotation_y_deg,
		"scale_y": scale_y,
	}


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
	# 场地边界不再是判据（2026-09-25 业主裁定，全项目适用）：此处不检查
	# `outside_floor_bounds`，也不再有 `map_rect`。面积只报数字、不设上限。
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
	# 场地边界不再是判据（2026-09-25 业主裁定，全项目适用）：本函数不检查
	# `outside_floor_bounds`。核区排斥（`occupies_core`）与楼梯厅预留仍照判 ——
	# 它们约束的是「谁占了谁的位置」，不是「谁超了场地」。
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
	# 面积不再是判据（2026-09-25 业主裁定）：`area_budget` 只作为数据留在 plan 里
	# 供报告与诊断读取，本函数不再报 `area_budget_exceeded`。
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
