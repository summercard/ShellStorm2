class_name LevelPlanLoader
extends RefCounted
## L1/L2/L3 白盒设计源读取器（依据 docs/v0.1/05.2_关卡版图白盒与生成规范.md §3）。
##
## 职责边界（刻意收窄，避免制造第四份几何实现）：
##   文件 IO + schema 校验 + JSON → 中间结构（Vector2 / Array[String]）。
##   **不实现**门槽算法（走 RoomDoorLane）、**不实现**面积预算（走 FloorPlanGenerator）、
##   **不生成** plan 字典（走 FloorPlanGenerator.generate_from_level_plan）。
##
## 目录约定：
##   res://data/level_plans/<level_id>/
##     ├─ level_plan.json                    L1 关卡级
##     ├─ floors/floor_<NN>.json             L2 层级（房间表 + 主路 + 例外）
##     └─ room_templates/<template_id>.json  L3 房间模板
##
## 设计母版保留在 source/；scripts/sync_runtime_design_data.py 原样投影 JSON。
##
## 更新设计源后先同步投影；--check 确保源与运行数据逐字节一致。

const SCHEMA_LEVEL := "shellstorm2.battle.level_plan"
const SCHEMA_FLOOR := "shellstorm2.battle.floor_plan_whitebox"
const SCHEMA_TEMPLATE := "shellstorm2.battle.room_template_whitebox"

const TOWER_ZONES_ROOT := "data/level_plans"
const DEFAULT_VERSION_DIR := "v001"
## 版本目录覆盖：S1 反导出产物落在 v004，其余关卡默认 v001。
const DATA_ROOT_OVERRIDES := {
	"battle_level01": "res://data/level_plans/battle_level01",
}

const VALID_ROOM_TYPES := ["SAFE_ROOM", "COMMON_ROOM", "BOSS_ROOM", "EXTRACTION_ROOM"]
## `flow` = EGT 式：L2 房表只是样例，几何由「抽骨架 + 组装 + 桥接」在开局时现算
## （`FloorPlanGenerator._generate_flow_floor`）。远征03 的 `floor_00.json` 早已声明
## `mode: "flow"`，但本白名单一直没有它 —— 于是那份设计源一读就被判 `floor_mode_invalid`。
const VALID_MODES := ["authored", "constrained", "flow"]
const VALID_RULES := ["normal", "boss"]
## 端口落在房间边界上的判定容差（米）。设计源按 5m 网格书写，1cm 足够吸收浮点误差，
## 又不会把"离边界 0.3m 的偏心门"误判成贴边门。
const PORT_BOUNDARY_EPS := 0.01


## 该关卡的运行数据根目录。未登记覆盖时按 <level_id> 推导。
static func data_root_for(level_id: String) -> String:
	if DATA_ROOT_OVERRIDES.has(level_id):
		return str(DATA_ROOT_OVERRIDES[level_id])
	return "res://%s/%s" % [TOWER_ZONES_ROOT, level_id]


## 该关卡是否已提供设计源（决定运行时走数据驱动还是内置房表）。
static func has_level_plan(level_id: String) -> bool:
	return not load_level_plan(level_id).is_empty()


## 读取任意 JSON 文件；路径不存在或解析失败一律返回空字典（不抛错）。
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## 读取 L1 关卡级。schema 不符视为不可用，返回空字典。
static func load_level_plan(level_id: String) -> Dictionary:
	var root := data_root_for(level_id)
	var plan := read_json("%s/level_plan.json" % root)
	if plan.is_empty():
		return {}
	if str(plan.get("schema", "")) != SCHEMA_LEVEL:
		return {}
	plan["_data_root"] = root
	return plan


## L1.floors 中登记的层条目（已按 floor_index 升序）。
static func list_floors(level_plan: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value in level_plan.get("floors", []):
		if value is Dictionary:
			rows.append(value as Dictionary)
	rows.sort_custom(
		func(a, b): return int(a.get("floor_index", 0)) < int(b.get("floor_index", 0))
	)
	return rows


## 按层号取 L1 里的层条目；找不到返回空字典。
static func floor_entry(level_plan: Dictionary, floor_number: int) -> Dictionary:
	for entry in list_floors(level_plan):
		if int(entry.get("floor_number", -9999)) == floor_number:
			return entry
	return {}


## 读取 L2 层级。floor_number 为显示层号。
static func load_floor_plan(level_id: String, floor_number: int) -> Dictionary:
	var level_plan := load_level_plan(level_id)
	if level_plan.is_empty():
		return {}
	var entry := floor_entry(level_plan, floor_number)
	if entry.is_empty():
		return {}
	var relative := str(entry.get("plan", ""))
	if relative.is_empty():
		return {}
	var root := str(level_plan.get("_data_root", data_root_for(level_id)))
	var floor_plan := read_json("%s/%s" % [root, relative])
	if floor_plan.is_empty():
		return {}
	if str(floor_plan.get("schema", "")) != SCHEMA_FLOOR:
		return {}
	return floor_plan


## 读取该关卡 L1 声明的全部 L3 模板，键为 template_id。
static func load_room_templates(level_id: String) -> Dictionary:
	var level_plan := load_level_plan(level_id)
	if level_plan.is_empty():
		return {}
	var root := str(level_plan.get("_data_root", data_root_for(level_id)))
	var templates: Dictionary = {}
	for value in level_plan.get("room_templates", []):
		var template_id := str(value)
		var template := read_json("%s/room_templates/%s.json" % [root, template_id])
		if template.is_empty():
			continue
		if str(template.get("schema", "")) != SCHEMA_TEMPLATE:
			continue
		templates[template_id] = template
	return templates


## 读取该关卡 L1 声明的全部 flow 骨架（`generation_policy.mode == "flow"` 用）。
##
## flow 只有拓扑（`nodes` / `tree_edges` / `loop_edges` / `injections`），**没有坐标** ——
## 坐标由 `EgtFlowAssembler` 在开局时按种子算出来。顺序按 `flow_plans` 声明序，
## 保证同一种子的「第 k 张」稳定（抽关靠索引，不靠目录遍历顺序）。
static func load_flows(level_id: String) -> Array[Dictionary]:
	var flows: Array[Dictionary] = []
	var level_plan := load_level_plan(level_id)
	if level_plan.is_empty():
		return flows
	var root := str(level_plan.get("_data_root", data_root_for(level_id)))
	for value in level_plan.get("flow_plans", []) as Array:
		var entry := value as Dictionary
		var relative := str(entry.get("path", ""))
		if relative.is_empty():
			continue
		var flow := read_json("%s/%s" % [root, relative])
		if flow.is_empty():
			continue
		flows.append(flow)
	return flows


## 把 L2 规范化：数值转 Vector2、字符串数组收敛类型、补全派生 ports。
## 返回结构含 "errors" 键（空数组 = schema 层无致命问题；语义约束由校验器负责）。
static func normalize_floor(level_id: String, floor_number: int) -> Dictionary:
	var floor_plan := load_floor_plan(level_id, floor_number)
	if floor_plan.is_empty():
		return {"errors": ["floor_plan_missing:%s:%d" % [level_id, floor_number]]}
	var errors: Array[String] = []
	var rooms: Array[Dictionary] = []
	for value in floor_plan.get("rooms", []):
		if not (value is Dictionary):
			errors.append("room_not_object")
			continue
		var raw := value as Dictionary
		# 本字典是**白名单重建**，不是原样透传：设计源新增字段若忘记在此登记，
		# 会被静默丢掉（不会报错、也不会红），因此每次扩字段都要连这里一起改。
		# 已登记的房间级可选字段：enemy_spawn_plan（刷怪计划）、boss_content_id（首领指派）、
		# boss_reinforcement_plan（Boss 激活后并发增援）、reward_plan（统一掉落计划，
		# 04 §22.7 / 05 §11 reward_slots）、spawn_placements（触发盒放置，触发器刷怪设计 §3.2）、
		# encounter（波次调用 §3.3）、secret_site（传送支线位点，支线秘密房间设计 §3.2）。
		var spawn_plan: Dictionary = {}
		var raw_spawn_plan: Variant = raw.get("enemy_spawn_plan", {})
		if raw_spawn_plan is Dictionary:
			spawn_plan = (raw_spawn_plan as Dictionary).duplicate(true)
		# 触发盒放置：本层只做**类型守卫 + 深拷贝**，几何语义（盒在房内、尺寸 ⊆ 房、
		# box 引用存在）由 LevelPlanValidator 与 SpawnBoxCatalog 负责。
		# 与 enemy_spawn_plan 同样「只透传不解释」—— 但**必须在此登记**，否则被静默丢弃。
		var spawn_placements: Array = []
		var raw_placements: Variant = raw.get("spawn_placements", [])
		if raw_placements is Array:
			spawn_placements = (raw_placements as Array).duplicate(true)
		# 调用机制：第 N 波调用哪几个盒子实例。同样只透传。
		var encounter: Dictionary = {}
		var raw_encounter: Variant = raw.get("encounter", {})
		if raw_encounter is Dictionary:
			encounter = (raw_encounter as Dictionary).duplicate(true)
		# Boss 激活后并发增援：只透传，不在加载层解释挂点、曲线或抛射参数。
		var boss_reinforcement_plan: Dictionary = {}
		var raw_boss_reinforcement: Variant = raw.get("boss_reinforcement_plan", {})
		if raw_boss_reinforcement is Dictionary:
			boss_reinforcement_plan = (raw_boss_reinforcement as Dictionary).duplicate(true)
		elif raw.has("boss_reinforcement_plan"):
			errors.append(
				"boss_reinforcement_plan_not_object:%s" % str(raw.get("key", ""))
			)
		# 统一掉落计划：键是 trigger（clear / search / kill），值是槽位引用。
		# 本层只做**类型守卫 + 深拷贝**，语义（trigger 合法、spec 存在、池已登记）由
		# LevelPlanValidator 与 RewardSpec 负责 —— 与 enemy_spawn_plan 同样「只透传不解释」。
		var reward_plan: Dictionary = {}
		var raw_reward_plan: Variant = raw.get("reward_plan", {})
		if raw_reward_plan is Dictionary:
			reward_plan = (raw_reward_plan as Dictionary).duplicate(true)
		# 授权布局壳体（区块00 / 远征01）：整房 5m 组件清单随房表下传。本层只做
		# 类型守卫 + 深拷贝，几何语义（lane 归属、门位顶替）由消费方 DungeonRoom3D 负责。
		# 与 enemy_spawn_plan 同样「只透传不解释」—— 但**必须在此登记**，否则被静默丢弃。
		var authored_instances: Array = []
		var raw_authored_instances: Variant = raw.get("authored_layout_instances", [])
		if raw_authored_instances is Array:
			authored_instances = (raw_authored_instances as Array).duplicate(true)
			for instance in authored_instances:
				var position_value: Variant = (instance as Dictionary).get("position", null)
				if position_value is Array and (position_value as Array).size() >= 3:
					instance["position"] = Vector3(float(position_value[0]), float(position_value[1]), float(position_value[2]))
		var camera_profile: Dictionary = {}
		var raw_camera_profile: Variant = raw.get("camera_profile", {})
		if raw_camera_profile is Dictionary:
			camera_profile = (raw_camera_profile as Dictionary).duplicate(true)
		# 传送支线位点（支线秘密房间设计 §3.2）：本房哪面墙上有一个可打破的隐藏门。
		# 只声明 `wall`（north/south/east/west）与配对角色，**不存世界坐标** ——
		# 坐标由房间外框 + wall 在运行时推导，改版图时位点自动跟随，不会两处不同步。
		# 本层只做类型守卫 + 深拷贝；位点合法性（该墙无端口、两侧留白）由
		# `verify_secret_branch_flow` 的静态断言负责。
		# 缺省空字典 ⇒ 本房无位点，未声明关卡一个字段都不多，行为逐字不变。
		var secret_site: Dictionary = {}
		var raw_secret_site: Variant = raw.get("secret_site", {})
		if raw_secret_site is Dictionary:
			secret_site = (raw_secret_site as Dictionary).duplicate(true)
		elif raw.has("secret_site"):
			errors.append("secret_site_not_object:%s" % str(raw.get("key", "")))
		# 房间连接端口是房间美术局部空间里的稳定接口。位置与朝外法线随整房
		# rotation_deg 一起旋转；target 只声明本端口接哪一个房间 key。
		# 未连接候选端口保留 target=""，装配时必须由实墙封回，不能留下镂空。
		#
		# `side`（端口开在哪面墙上）**必须在本层派生**，不能指望设计源写、也不能读 outward：
		#   · 白盒端口只写 `position_m` + `outward`，从不写 `side`；本层此前把它静默丢掉，
		#     于是 `TowerDescent3D._declare_and_register_edge()` 取到空 side，两门坐标
		#     退化成房间中心 ⇒ 相邻房之间凭空长出 5m×N 的通用走廊（地板 + 双侧墙 + 挡人碰撞）。
		#     远征02 实测 23/25 条边中招，多出 286 段墙 / 143 块地板 / 46 个挡人碰撞体。
		#   · `outward` **不可**作为依据：白盒门表的 outward 只编码「谁排 side_a」，
		#     同一面竖墙上东西两侧的门都可能是 (+1,0)（实测 d_w1 与 d_e1 都是），
		#     拿它判方向会得到与几何相反的 side。
		# 唯一可靠依据是**端口压在房间哪条边界上**，与
		# `FloorPlanGenerator._connection_port_is_on_room_boundary()` 的 side 定义同源。
		var room_size := _vec2(raw.get("size_m", []))
		var connection_ports: Array = []
		var raw_connection_ports: Variant = raw.get("connection_ports", [])
		if raw_connection_ports is Array:
			for port_value in raw_connection_ports as Array:
				if not (port_value is Dictionary):
					continue
				var port := port_value as Dictionary
				var port_position := _vec2(port.get("position_m", []))
				var port_side := _side_from_room_boundary(port_position, room_size)
				connection_ports.append({
					"port_id": str(port.get("port_id", "")),
					"target": str(port.get("target", "")),
					"position_m": (port.get("position_m", []) as Array).duplicate(),
					"outward": (port.get("outward", []) as Array).duplicate(),
					"side": port_side,
					# lane_m 与 side 必须同源产出：南北墙的门沿墙坐标在 x 轴，东西墙在 y 轴。
					"lane_m": (
						port_position.x if port_side in ["north", "south"] else port_position.y
					),
					# 门宽是**建不建实体门扇**的唯一判据（≤3m = 标准门，5m = 通洞 / 坍塌）。
					# 本层同样只透传不解释 —— 但**必须登记**，否则消费方读到 0，
					# 会把 21 个门洞全部当成通洞、一扇门扇都不建（实测踩过）。
					"door_width_m": float(port.get("door_width_m", 0.0)),
						"height_m": float(port.get("height_m", 0.0)),
					"door_axis": str(port.get("door_axis", "")),
					"door_line_m": float(port.get("door_line_m", 0.0)),
					"door_center_m": float(port.get("door_center_m", 0.0)),
				})
		var room := {
			"key": str(raw.get("key", "")),
			"room_id": str(raw.get("room_id", "")),
			"legacy_room_id": str(raw.get("legacy_room_id", "")),
			"room_type": str(raw.get("room_type", "")),
			"role": str(raw.get("role", "")),
			"parent_key": str(raw.get("parent_key", "")),
			"template_id": str(raw.get("template_id", "")),
			"template_variant": str(raw.get("template_variant", "")),
			"center": _vec2(raw.get("center_m", [])),
			"size": _vec2(raw.get("size_m", [])),
			"rotation_deg": float(raw.get("template_rotation_deg", 0.0)),
			"floor_offset_m": float(raw.get("floor_offset_m", 0.0)),
			"anchor_policy": str(raw.get("anchor_policy", "grid")),
			"content_type": str(raw.get("content_type", "")),
			"boss_content_id": str(raw.get("boss_content_id", "")),
			"boss_reinforcement_plan": boss_reinforcement_plan,
			"enemy_spawn_plan": spawn_plan,
			"spawn_placements": spawn_placements,
			"encounter": encounter,
			"reward_plan": reward_plan,
			"declared_ports": raw.get("ports", []),
			"ports": [],
			"ports_derived": false,
			# 授权布局壳体：房表声明了才落字段，未接管的房间一个字段都不多
			# （TowerDescent3D._append_plan_room_record 同样按这个布尔判透传）。
			"authored_layout_shell": bool(raw.get("authored_layout_shell", false)),
			"authored_layout_asset_id": str(raw.get("authored_layout_asset_id", "")),
			"authored_layout_version": str(raw.get("authored_layout_version", "")),
			"authored_layout_room_id": str(raw.get("authored_layout_room_id", "")),
			"authored_layout_peaceful": bool(raw.get("authored_layout_peaceful", false)),
			"authored_layout_instances": authored_instances,
			"camera_profile": camera_profile,
			"connection_ports": connection_ports,
			"secret_site": secret_site,
		}
		if str(room["key"]).is_empty():
			errors.append("room_key_empty")
		rooms.append(room)
	# 「只认盒子」标记：层里写一次，**逐房下发**。
	# 为什么下发而不是运行时再查层：Dungeon3D 只拿得到房间记录，拿不到层的规范化结构；
	# 不下发的话「没盒子就不刷」在运行时无从判断，规则会静默失效。
	if bool(floor_plan.get("spawn_boxes_only", false)):
		for room: Dictionary in rooms:
			room["spawn_boxes_only"] = true
	derive_ports(rooms)
	return {
		"level_id": level_id,
		"mode": str(floor_plan.get("mode", "authored")),
		"floor_number": int(floor_plan.get("floor_number", floor_number)),
		"floor_index": int(floor_plan.get("floor_index", 0)),
		"sequence_index": int(floor_plan.get("sequence_index", 0)),
		"entry_side": str(floor_plan.get("entry_side", "east")),
		"exit_side": str(floor_plan.get("exit_side", "west")),
		"reservations": floor_plan.get("reservations", []),
		"rooms": rooms,
		"main_path": _string_array(floor_plan.get("main_path", [])),
		"edge_policy": floor_plan.get("edge_policy", []),
		# 触发器刷怪（设计 §3.3 / §7-A）：本层是否为「**只认盒子**」层。
		# true ⇒ 敌对房没有 spawn_placements 就**不刷怪**（业主裁定「没盒子就不刷」），
		# 且校验器把「敌对房实例为空」判为错误。缺省 false ⇒ 未迁移关卡行为逐字不变。
		"spawn_boxes_only": bool(floor_plan.get("spawn_boxes_only", false)),
		# 几何权威性：本结构里的 `center` / `size` 是不是**真几何**。
		#
		# `mode = "constrained"` 的 L2 文件里 `center_m` / `size_m` 只是「拓扑蓝图 + 样例 /
		# 兜底」—— 真正的几何由 `FloorPlanGenerator` 按种子算（见 `_constrained_floor_from`）。
		# 因此**从文件读出来的这一份不是真几何**，标记 false，让 `LevelPlanValidator` 跳过
		# 一切依赖真实尺寸的判据（盒越界 / 贴墙内缩 / 砖心相位）。
		# 实测教训：远征 room_05 房表声明 30×60、运行时是 60×30（生成器按连接方向转置），
		# 拿样例几何判会把一整房合法盒位误报成「越出房间」。
		# `authored` 关卡（塔楼）的文件几何就是真几何 ⇒ true，判据全开、行为逐字不变。
		"geometry_authoritative": str(floor_plan.get("mode", "authored")) != "constrained",
		"errors": errors,
	}


## 门槽（ports）派生：把 `rooms` 的父子几何翻译成每面墙上的门槽，就地写回三个键。
##
## 05.2 §3.3 第 1 条：`ports[].lane_m` 是**数据不是算法**，运行时只校验不推导。
## 因此设计源写了就原样采信（`declared_ports`）；只有在缺失时才由几何派生并标记
## `ports_derived`。两者是否一致由 LevelPlanValidator 的 `port_derivation_mismatch`
## 断言盯住 —— 本处绝不静默用派生值覆盖设计值（历史病根：S1 导出的 N/S 门侧曾整体
## 反向而无人发现）。
##
## 为什么抽成独立静态函数：`mode = "constrained"` 的关卡几何由 FloorPlanGenerator
## 按种子产出，它同样需要派生门槽。抽出来两边共用，避免第二份门槽实现。
static func derive_ports(rooms: Array) -> void:
	var center_by_key := {}
	var size_by_key := {}
	for room in rooms:
		var key := str(room["key"])
		center_by_key[key] = room["center"]
		size_by_key[key] = room["size"]
	for room in rooms:
		var declared: Variant = room.get("declared_ports", [])
		if declared is Array and not (declared as Array).is_empty():
			var declared_ports: Array[Dictionary] = []
			for port_value in (declared as Array):
				if not (port_value is Dictionary):
					continue
				var port := port_value as Dictionary
				declared_ports.append({
					"port_id": str(port.get("port_id", "")),
					"target": str(port.get("target", "")),
					"side": str(port.get("side", "")),
					"lane_m": float(port.get("lane_m", 0.0)),
					"wall_length_m": float(port.get("wall_length_m", 0.0)),
				})
			room["ports"] = declared_ports
	# ports 由父子房几何派生 —— 复用 RoomDoorLane 唯一实现，本处不复制算法。
	var ports_by_key: Dictionary = {}
	for room in rooms:
		ports_by_key[str(room["key"])] = []
	for room in rooms:
		var child_key := str(room["key"])
		var parent_key := str(room["parent_key"])
		if parent_key.is_empty() or not center_by_key.has(parent_key):
			continue
		var pair := RoomDoorLane.port_pair(
			center_by_key[child_key] as Vector2,
			size_by_key[child_key] as Vector2,
			center_by_key[parent_key] as Vector2,
			size_by_key[parent_key] as Vector2
		)
		(ports_by_key[child_key] as Array).append({
			"target": parent_key,
			"side": str(pair["a_side"]),
			"lane_m": float(pair["a_lane"]),
			"wall_length_m": float(pair["a_wall_length"]),
		})
		(ports_by_key[parent_key] as Array).append({
			"target": child_key,
			"side": str(pair["b_side"]),
			"lane_m": float(pair["b_lane"]),
			"wall_length_m": float(pair["b_wall_length"]),
		})
	for room in rooms:
		var key := str(room["key"])
		var entries := ports_by_key[key] as Array
		entries.sort_custom(func(a, b): return str(a["target"]) < str(b["target"]))
		var derived: Array[Dictionary] = []
		for index in range(entries.size()):
			var entry := entries[index] as Dictionary
			derived.append({
				"port_id": "P%d" % (index + 1),
				"target": entry["target"],
				"side": entry["side"],
				"lane_m": entry["lane_m"],
				"wall_length_m": entry["wall_length_m"],
			})
		# 派生值始终产出，供校验器比对；只有设计源没写端口时才回填给消费方。
		room["derived_ports"] = derived
		if (room.get("ports", []) as Array).is_empty():
			room["ports"] = derived
			room["ports_derived"] = true


static func _vec2(value: Variant) -> Vector2:
	if value is Array:
		var arr := value as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


## 端口所在墙面的方向 —— 由端口在**房间局部坐标**中压在哪条边界上判定。
##
## 与 `FloorPlanGenerator._connection_port_is_on_room_boundary()` 的 `side` 定义同源：
##   north → position.y ≈ −half.y     south → position.y ≈ +half.y
##   west  → position.x ≈ −half.x     east  → position.x ≈ +half.x
##
## 为什么先比「离哪条边界更近」而不是直接取绝对值最大的那个分量：
## 长条房（如 10×75 的旅馆长廊）的侧墙门会离房间中心很远
## （local x=−5、y=−30 ⇒ |y| = 30 ≫ |x| = 5），按分量最大会判成南北门，
## 而它其实开在西墙上。实测 56/56 个远征02 端口两种判法一致、配对 0 冲突。
static func _side_from_room_boundary(position: Vector2, room_size: Vector2) -> String:
	if room_size.x <= 0.0 or room_size.y <= 0.0:
		return ""
	var half := room_size * 0.5
	var gap_x := absf(absf(position.x) - half.x)
	var gap_y := absf(absf(position.y) - half.y)
	# 平局（角上端口）时优先 x 轴，与 `_connection_port_is_on_room_boundary` 的书写序一致。
	if gap_x <= PORT_BOUNDARY_EPS and gap_x <= gap_y:
		return "east" if position.x > 0.0 else "west"
	if gap_y <= PORT_BOUNDARY_EPS:
		return "south" if position.y > 0.0 else "north"
	# 既不贴边也没有房间尺寸 ⇒ 派生不出 side。调用方会退回旧的「按房间中心猜向」，
	# 那种猜法对长廊侧房是错的，所以这里明确告警，不让它再静默发生。
	push_warning(
		"[LevelPlanLoader] 端口位置 %s 不在房间尺寸 %s 的任何边界上，side 无法派生"
		% [str(position), str(room_size)]
	)
	return ""


static func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in (value as Array):
			out.append(str(item))
	return out
