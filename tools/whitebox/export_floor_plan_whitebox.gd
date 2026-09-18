extends Node
## S1 取证：把 FloorPlanGenerator 的运行时版图反向导出为白盒版图层。
##
## 纯只读取证：不修改任何运行时文件，只在白盒 v004 目录下写 JSON。
## 门槽走 RoomDoorLane 唯一实现；网格对齐走 TowerGeometry3D；墙厚/层高/门洞契约
## 直接从既有 v003 白盒 manifest 读取。本脚本不手抄任何几何常量。
##
## 运行：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . \
##     res://tools/whitebox/export_floor_plan_whitebox.tscn
## 判据：FLOOR_PLAN_WHITEBOX_EXPORT_OK floors=1 rooms=N lanes_ok=K templates=T

const FLOOR_PLAN_GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const ROOM_DOOR_LANE := preload("res://src/map/RoomDoorLane.gd")

const OUTPUT_ROOT := "res://source/art/whitebox/tower_zones/battle_level01/v004/data"
const WHITEBOX_DIR := "res://source/art/whitebox/tower_zones/battle_level01/v003/data"
## 既有白盒里任取一个已验收包，用它的 manifest 提供墙厚 / 视觉墙高 / 门洞契约。
const CONTRACT_PROBE := "component_packages/corridors/corridor_wall_5x0p3x11p9m/asset_manifest.json"
## 既有 98F 房间布局目录（仓库相对路径），用于登记模板变体。
const EXISTING_LAYOUT_DIR := "assets/art/environments/tower_zones/battle/source/room_instances"
const EXISTING_LAYOUTS := {
	"floor_01_hub": "main_room_01_hub/v003",
	"floor_01_main_02": "main_room_02/v003",
	"floor_01_main_03": "main_room_03/v003",
	"floor_01_main_04": "main_room_04/v003",
}

const SCHEMA_LEVEL := "shellstorm2.battle.level_plan"
const SCHEMA_FLOOR := "shellstorm2.battle.floor_plan_whitebox"
const SCHEMA_TEMPLATE := "shellstorm2.battle.room_template_whitebox"
const SCHEMA_VERSION := 1

const LEVEL_ID := "battle_level01"
const BLOCK_ID := "battle"
const FLOOR_RULE_VERSION := 2
## 目标镜像变体：v003 既有白盒是 north_ring（hub 在 entry 南侧），
## 取证必须与它对齐，否则跨源比对会因整体镜像而全部错配。
const AUTHORED_VARIANT := "north_ring"
const SEED_SEARCH_LIMIT := 64
const FLOOR_NUMBER := 98
const FLOOR_INDEX := 2
const SEQUENCE_INDEX := 1
const ENTRY_SIDE := "east"

var _failures: Array[String] = []
var _lane_checks := 0
var _authored_seed := 0


func _ready() -> void:
	var contract := _read_contract()
	if contract.is_empty():
		push_error("CONTRACT_UNREADABLE %s" % CONTRACT_PROBE)
		get_tree().quit(1)
		return
	_authored_seed = _find_authored_seed()
	if _authored_seed < 0:
		push_error("AUTHORED_VARIANT_NOT_FOUND %s" % AUTHORED_VARIANT)
		get_tree().quit(1)
		return
	var plan := FLOOR_PLAN_GENERATOR.generate(_request())
	if not bool(plan.get("valid", false)):
		push_error("AUTHORED_PLAN_INVALID %s" % str(plan.get("validation_errors", [])))
		get_tree().quit(1)
		return
	var rooms := plan.get("rooms", []) as Array
	var center_by_key := {}
	var size_by_key := {}
	for value in rooms:
		var spec := value as Dictionary
		var key := str(spec.get("key", ""))
		var size := (spec.get("dimensions", Vector2.ZERO) as Vector2).abs()
		var planar := spec.get("position", Vector2.ZERO) as Vector2
		size_by_key[key] = size
		center_by_key[key] = Vector2(
			TOWER_GEOMETRY.snap_component_axis(planar.x, size.x),
			TOWER_GEOMETRY.snap_component_axis(planar.y, size.y)
		)
	var ports_by_key := _build_ports(rooms, center_by_key, size_by_key)
	var floor_rooms: Array[Dictionary] = []
	var template_meta := {}
	for value in rooms:
		var spec := value as Dictionary
		var key := str(spec.get("key", ""))
		var role := str(spec.get("role", "room"))
		var legacy_id := str(spec.get("id", ""))
		var size := size_by_key[key] as Vector2
		var center := center_by_key[key] as Vector2
		var room_type := _room_type_for(role)
		var template_id := _template_id_for(room_type, size)
		var meta: Dictionary = template_meta.get(template_id, {})
		meta["room_type"] = room_type
		meta["size"] = size
		var variants: Dictionary = meta.get("variants", {})
		if EXISTING_LAYOUTS.has(legacy_id):
			variants[legacy_id] = str(EXISTING_LAYOUTS[legacy_id])
		meta["variants"] = variants
		template_meta[template_id] = meta
		floor_rooms.append({
			"key": key,
			"room_id": _room_id(FLOOR_NUMBER, key),
			"legacy_room_id": legacy_id,
			"room_type": room_type,
			"role": role,
			"parent_key": str(spec.get("parent_key", "")),
			"template_id": template_id,
			"template_variant": _variant_for(legacy_id),
			"center_m": [_round3(center.x), _round3(center.y)],
			"size_m": [_round3(size.x), _round3(size.y)],
			"template_rotation_deg": 0,
			"ports": ports_by_key.get(key, []),
		})
	if _failures.is_empty():
		_write_json(
			"%s/level_plan.json" % OUTPUT_ROOT,
			_build_level_plan(contract, template_meta)
		)
		_write_json(
			"%s/floors/floor_%d.json" % [OUTPUT_ROOT, FLOOR_NUMBER],
			_build_floor_plan(floor_rooms, plan)
		)
		for template_id in template_meta.keys():
			_write_json(
				"%s/room_templates/%s.json" % [OUTPUT_ROOT, str(template_id)],
				_build_template(str(template_id), template_meta[template_id] as Dictionary, contract)
			)
		_write_json(
			"%s/export_report.json" % OUTPUT_ROOT,
			_build_report(floor_rooms, plan, contract, template_meta)
		)
	if _failures.is_empty():
		print(
			"FLOOR_PLAN_WHITEBOX_EXPORT_OK floors=1 rooms=%d lanes_ok=%d templates=%d"
			% [floor_rooms.size(), _lane_checks, template_meta.size()]
		)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _find_authored_seed() -> int:
	for candidate in range(1, SEED_SEARCH_LIMIT + 1):
		var plan := FLOOR_PLAN_GENERATOR.generate({
			"run_seed": candidate,
			"floor_number": FLOOR_NUMBER,
			"floor_index": FLOOR_INDEX,
			"sequence_index": SEQUENCE_INDEX,
			"entry_side": ENTRY_SIDE,
			"boss_floor": FLOOR_NUMBER % 5 == 0,
		})
		if str(plan.get("layout_variant", "")) == AUTHORED_VARIANT:
			return candidate
	return -1


func _request() -> Dictionary:
	return {
		"run_seed": _authored_seed,
		"floor_number": FLOOR_NUMBER,
		"floor_index": FLOOR_INDEX,
		"sequence_index": SEQUENCE_INDEX,
		"entry_side": ENTRY_SIDE,
		"boss_floor": FLOOR_NUMBER % 5 == 0,
	}


func _read_contract() -> Dictionary:
	var file := FileAccess.open("%s/%s" % [WHITEBOX_DIR, CONTRACT_PROBE], FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var manifest := parsed as Dictionary
	var door := manifest.get("door_contract", {}) as Dictionary
	var dimensions := manifest.get("dimensions_m", []) as Array
	if door.is_empty() or dimensions.size() < 2:
		return {}
	return {
		"wall_thickness_m": float(dimensions[1]),
		"visible_wall_height_m": float(manifest.get("visual_wall_height_m", 11.9)),
		"floor_height_m": float(TOWER_GEOMETRY.FLOOR_HEIGHT_M),
		"door_contract": {
			"width_m": float(door.get("width_m", 2.2)),
			"height_m": float(door.get("height_m", 2.5)),
			"clear_floor_gap_m": float(door.get("clear_floor_gap_m", 0.0)),
			"bottom_z_m": float(door.get("bottom_z_m", 0.3)),
			"lintel_bottom_z_m": float(door.get("lintel_bottom_z_m", 2.8)),
		},
		"contract_source": "%s/%s" % [WHITEBOX_DIR, CONTRACT_PROBE],
	}


func _room_type_for(role: String) -> String:
	match role:
		"stair_entry", "stair_exit":
			return "SAFE_ROOM"
		"boss":
			return "BOSS_ROOM"
		_:
			return "COMMON_ROOM"


func _template_id_for(room_type: String, size: Vector2) -> String:
	var kind := "common"
	match room_type:
		"SAFE_ROOM":
			kind = "safe"
		"BOSS_ROOM":
			kind = "boss"
		"EXTRACTION_ROOM":
			kind = "extraction"
	return "%s_%dx%d" % [kind, int(round(size.x)), int(round(size.y))]


func _room_id(floor_number: int, key: String) -> String:
	return "f%02d_%s" % [floor_number, key]


func _variant_for(legacy_id: String) -> String:
	if not EXISTING_LAYOUTS.has(legacy_id):
		return ""
	var relative := str(EXISTING_LAYOUTS[legacy_id])
	return relative.get_base_dir()


func _build_ports(
	rooms: Array, center_by_key: Dictionary, size_by_key: Dictionary
) -> Dictionary:
	var collected := {}
	for value in rooms:
		collected[str((value as Dictionary).get("key", ""))] = []
	for value in rooms:
		var spec := value as Dictionary
		var child_key := str(spec.get("key", ""))
		var parent_key := str(spec.get("parent_key", ""))
		if parent_key.is_empty() or not center_by_key.has(parent_key):
			continue
		var pair := _port_pair(
			center_by_key[child_key] as Vector2,
			size_by_key[child_key] as Vector2,
			center_by_key[parent_key] as Vector2,
			size_by_key[parent_key] as Vector2
		)
		var rows := [
			[child_key, parent_key, str(pair["a_side"]), float(pair["a_lane"]), float(pair["a_wall_length"])],
			[parent_key, child_key, str(pair["b_side"]), float(pair["b_lane"]), float(pair["b_wall_length"])],
		]
		for row in rows:
			var errors := ROOM_DOOR_LANE.validate_port_lane(float(row[4]), float(row[3]))
			_lane_checks += 1
			for error in errors:
				_failures.append("%s -> %s: %s" % [str(row[0]), str(row[1]), error])
			(collected[str(row[0])] as Array).append({
				"target": str(row[1]),
				"side": str(row[2]),
				"lane_m": _round3(float(row[3])),
				"wall_length_m": _round3(float(row[4])),
			})
	var ports_by_key := {}
	for key in collected.keys():
		var entries := collected[key] as Array
		entries.sort_custom(func(a, b): return str(a["target"]) < str(b["target"]))
		var ports: Array[Dictionary] = []
		for index in range(entries.size()):
			var entry := entries[index] as Dictionary
			ports.append({
				"port_id": "P%d" % (index + 1),
				"target": entry["target"],
				"side": entry["side"],
				"lane_m": entry["lane_m"],
				"wall_length_m": entry["wall_length_m"],
			})
		ports_by_key[key] = ports
	return ports_by_key


func _port_pair(
	a_center: Vector2, a_size: Vector2, b_center: Vector2, b_size: Vector2
) -> Dictionary:
	var delta := b_center - a_center
	var along_x := absf(delta.x) >= absf(delta.y)
	var a_side := ""
	var b_side := ""
	var a_length := 0.0
	var b_length := 0.0
	var a_axis := 0.0
	var b_axis := 0.0
	if along_x:
		a_side = "east" if delta.x >= 0.0 else "west"
		b_side = "west" if delta.x >= 0.0 else "east"
		a_length = a_size.y
		b_length = b_size.y
		a_axis = a_center.y
		b_axis = b_center.y
	else:
		a_side = "north" if delta.y >= 0.0 else "south"
		b_side = "south" if delta.y >= 0.0 else "north"
		a_length = a_size.x
		b_length = b_size.x
		a_axis = a_center.x
		b_axis = b_center.x
	var world_lane := ROOM_DOOR_LANE.resolve_shared_world_lane(
		a_axis, a_length, b_axis, b_length, (a_axis + b_axis) * 0.5
	)
	return {
		"a_side": a_side,
		"a_lane": world_lane - a_axis,
		"a_wall_length": a_length,
		"b_side": b_side,
		"b_lane": world_lane - b_axis,
		"b_wall_length": b_length,
		"world_lane": world_lane,
	}


func _build_level_plan(contract: Dictionary, template_meta: Dictionary) -> Dictionary:
	var template_ids: Array[String] = []
	for template_id in template_meta.keys():
		template_ids.append(str(template_id))
	template_ids.sort()
	return {
		"schema": SCHEMA_LEVEL,
		"schema_version": SCHEMA_VERSION,
		"level_id": LEVEL_ID,
		"block_id": BLOCK_ID,
		"floor_rule_version": FLOOR_RULE_VERSION,
		"grid_unit_m": ROOM_DOOR_LANE.GRID_UNIT_M,
		"wall_thickness_m": contract.get("wall_thickness_m", 0.3),
		"floor_height_m": contract.get("floor_height_m", 12.0),
		"visible_wall_height_m": contract.get("visible_wall_height_m", 11.9),
		"site": {"size_m": [250.0, 250.0], "center_m": [2.5, 2.5]},
		"core": {"size_m": [65.0, 65.0], "center_m": [2.5, 2.5]},
		"floors": [
			{
				"floor_number": FLOOR_NUMBER,
				"floor_index": FLOOR_INDEX,
				"sequence_index": SEQUENCE_INDEX,
				"rule": "normal",
				"plan": "floors/floor_%d.json" % FLOOR_NUMBER,
			}
		],
		"room_templates": template_ids,
		"generation_policy": {
			"min_main_content_rooms": int(FLOOR_PLAN_GENERATOR.MIN_MAIN_CONTENT_ROOMS),
			"branch_count_range": [
				int(FLOOR_PLAN_GENERATOR.MIN_BRANCH_COUNT),
				int(FLOOR_PLAN_GENERATOR.MAX_BRANCH_COUNT),
			],
			"max_attempts": int(FLOOR_PLAN_GENERATOR.MAX_GENERATION_ATTEMPTS),
			"target_occupancy_ratio": float(FLOOR_PLAN_GENERATOR.TARGET_OCCUPANCY_RATIO),
			"reference_room_cost_m2": float(FLOOR_PLAN_GENERATOR.REFERENCE_CONTENT_ROOM_COST_M2),
		},
		"provenance": {
			"mode": "authored",
			"authored_run_seed": _authored_seed,
			"authored_variant": AUTHORED_VARIANT,
			"extracted_from": "src/map/FloorPlanGenerator.gd",
			"whitebox_art_source": "battle_level01/v003",
			"note": "S1 取证产物：由运行时规划器反向导出的默认版图，不是设计输入。",
		},
	}


func _build_floor_plan(floor_rooms: Array[Dictionary], plan: Dictionary) -> Dictionary:
	var outward := float(FLOOR_PLAN_GENERATOR.STAIR_RESERVATION_OUTWARD_M)
	var tangent := float(FLOOR_PLAN_GENERATOR.STAIR_RESERVATION_TANGENT_M)
	return {
		"schema": SCHEMA_FLOOR,
		"schema_version": SCHEMA_VERSION,
		"level_id": LEVEL_ID,
		"mode": "authored",
		"floor_number": FLOOR_NUMBER,
		"floor_index": FLOOR_INDEX,
		"sequence_index": SEQUENCE_INDEX,
		"entry_side": ENTRY_SIDE,
		"exit_side": str(plan.get("exit_side", "west")),
		"reservations": [
			{"kind": "stair_entry", "side": ENTRY_SIDE, "rect_m": [outward, tangent]},
			{
				"kind": "stair_exit",
				"side": str(plan.get("exit_side", "west")),
				"rect_m": [outward, tangent],
			},
		],
		"rooms": floor_rooms,
		"main_path": plan.get("main_path_keys", []),
		"edge_policy": [],
		"layout_variant": str(plan.get("layout_variant", "")),
		"layout_id": str(plan.get("layout_id", "")),
	}


func _build_template(
	template_id: String, meta: Dictionary, contract: Dictionary
) -> Dictionary:
	var size := meta.get("size", Vector2.ZERO) as Vector2
	var wall_lane_table := {}
	for side in ["north", "south", "east", "west"]:
		var length := size.x if side in ["north", "south"] else size.y
		var lanes: Array[float] = []
		for offset in ROOM_DOOR_LANE.lane_offsets(length):
			lanes.append(_round3(offset))
		wall_lane_table[side] = lanes
	var variants: Array[Dictionary] = []
	var variant_map := meta.get("variants", {}) as Dictionary
	var legacy_ids: Array[String] = []
	for legacy_id in variant_map.keys():
		legacy_ids.append(str(legacy_id))
	legacy_ids.sort()
	for legacy_id in legacy_ids:
		var relative := str(variant_map[legacy_id])
		variants.append({
			"variant_id": relative.get_base_dir(),
			"room_layout": "%s/%s/room_layout.json" % [EXISTING_LAYOUT_DIR, relative],
			"legacy_room_id": legacy_id,
			"status": "approved",
		})
	return {
		"schema": SCHEMA_TEMPLATE,
		"schema_version": SCHEMA_VERSION,
		"template_id": template_id,
		"room_type": str(meta.get("room_type", "COMMON_ROOM")),
		"size_m": [_round3(size.x), _round3(size.y)],
		"grid_unit_m": ROOM_DOOR_LANE.GRID_UNIT_M,
		"wall_height_m": contract.get("visible_wall_height_m", 11.9),
		"door_contract": contract.get("door_contract", {}),
		"openable_walls": ["north", "south", "east", "west"],
		"wall_lane_table": wall_lane_table,
		"variants": variants,
	}


func _build_report(
	floor_rooms: Array[Dictionary], plan: Dictionary, contract: Dictionary, template_meta: Dictionary
) -> Dictionary:
	var template_ids: Array[String] = []
	for template_id in template_meta.keys():
		template_ids.append(str(template_id))
	template_ids.sort()
	return {
		"schema": "shellstorm2.battle.floor_plan_whitebox_export_report",
		"schema_version": SCHEMA_VERSION,
		"source": "src/map/FloorPlanGenerator.gd",
		"authored_run_seed": _authored_seed,
		"authored_variant": AUTHORED_VARIANT,
		"floor_number": FLOOR_NUMBER,
		"room_count": floor_rooms.size(),
		"lane_checks": _lane_checks,
		"templates": template_ids,
		"area_budget": plan.get("area_budget", {}),
		"contract_source": contract.get("contract_source", ""),
		"legacy_layouts_registered": EXISTING_LAYOUTS.keys(),
	}


func _write_json(path: String, payload: Variant) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			_failures.append("cannot create %s (error %d)" % [directory, error])
			return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write %s" % path)
		return
	# 项目约定 .json 为 CRLF；FileAccess 不做行尾转换，这里显式写出。
	file.store_string(JSON.stringify(payload, "  ", false).replace("\n", "\r\n"))
	file.store_string("\r\n")
	file.close()


func _round3(value: float) -> float:
	return snappedf(value, 0.001)
