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
##   res://source/art/whitebox/tower_zones/<level_id>/v001/data/
##     ├─ level_plan.json                    L1 关卡级
##     ├─ floors/floor_<NN>.json             L2 层级（房间表 + 主路 + 例外）
##     └─ room_templates/<template_id>.json  L3 房间模板
##
## battle_level01 是 S1 反导出产物，版本目录固定 v004，见 DATA_ROOT_OVERRIDES。
##
## 新关卡只要把设计源放到上述目录，无需改任何代码即可被本读取器发现。

const SCHEMA_LEVEL := "shellstorm2.battle.level_plan"
const SCHEMA_FLOOR := "shellstorm2.battle.floor_plan_whitebox"
const SCHEMA_TEMPLATE := "shellstorm2.battle.room_template_whitebox"

const TOWER_ZONES_ROOT := "source/art/whitebox/tower_zones"
const DEFAULT_VERSION_DIR := "v001"
## 版本目录覆盖：S1 反导出产物落在 v004，其余关卡默认 v001。
const DATA_ROOT_OVERRIDES := {
	"battle_level01": "res://source/art/whitebox/tower_zones/battle_level01/v004/data",
}

const VALID_ROOM_TYPES := ["SAFE_ROOM", "COMMON_ROOM", "BOSS_ROOM", "EXTRACTION_ROOM"]
const VALID_MODES := ["authored", "constrained"]
const VALID_RULES := ["normal", "boss"]


## 该关卡的设计源根目录。未登记覆盖时按 <level_id>/v001/data 推导。
static func data_root_for(level_id: String) -> String:
	if DATA_ROOT_OVERRIDES.has(level_id):
		return str(DATA_ROOT_OVERRIDES[level_id])
	return "res://%s/%s/%s/data" % [TOWER_ZONES_ROOT, level_id, DEFAULT_VERSION_DIR]


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
			"content_type": str(raw.get("content_type", "")),
			"declared_ports": raw.get("ports", []),
			"ports": [],
			"ports_derived": false,
		}
		if str(room["key"]).is_empty():
			errors.append("room_key_empty")
		rooms.append(room)
	var center_by_key := {}
	var size_by_key := {}
	for room in rooms:
		var key := str(room["key"])
		center_by_key[key] = room["center"]
		size_by_key[key] = room["size"]
	# —— 门槽（ports）——
	# 05.2 §3.3 第 1 条：`ports[].lane_m` 是**数据不是算法**，运行时只校验不推导。
	# 因此设计源写了就原样采信；只有在缺失时才由几何派生，并标记 ports_derived。
	# 两者是否一致由 LevelPlanValidator 的 `port_derivation_mismatch` 断言盯住 ——
	# 本处绝不静默用派生值覆盖设计值（历史病根：S1 导出的 N/S 门侧曾整体反向而无人发现）。
	for room in rooms:
		var declared: Variant = room["declared_ports"]
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
		if (room["ports"] as Array).is_empty():
			room["ports"] = derived
			room["ports_derived"] = true
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
		"errors": errors,
	}


static func _vec2(value: Variant) -> Vector2:
	if value is Array:
		var arr := value as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


static func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in (value as Array):
			out.append(str(item))
	return out
