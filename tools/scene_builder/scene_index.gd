@tool
extends RefCounted
## Discover layouts without instantiating their scripts or maintaining a second registry.

const ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances"
const PLAN_ROOT := "res://data/level_plans"
const RUNTIME_ART := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const GAME_CONFIG := preload("res://src/framework/GameDesignConfig.gd")

## A passive identity only: no game script, scene, imported mesh or Autoload is loaded.
## Keep matching in the runtime contract instead of copying its hash/style rules here.
class RoomIdentity extends Node3D:
	var dimensions := Vector2.ZERO
	var room_id := ""
	var room_type := ""
	var template_id := ""
	var safe_room_corner_l := false
	var connection_ports: Array = []

	func get_dimensions() -> Vector2:
		return dimensions


## One row per registered game resource. New authoring outputs and reference shells
## remain discoverable through scan(), but are not presented as game rooms.
## Missing/invalid level bindings, identity metadata or current reuse keys are
## deliberately omitted: directory membership alone is not runtime integration.
static func game_rooms() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen := {}
	var bindings := {}
	for candidate in scan():
		var path := str(candidate["path"])
		var level := str(candidate.get("level_id", ""))
		if level.is_empty() or seen.has(path):
			continue
		if not bindings.has(level):
			bindings[level] = _game_bindings(level)
		var binding: Dictionary = bindings[level]
		if binding.is_empty():
			continue
		var row: Dictionary = {}
		if str(binding["mode"]) == "flow":
			row = _runtime_art_row(candidate)
		else:
			var registered: Dictionary = binding["rooms"]
			if registered.has(path):
				row = candidate.duplicate(true)
				# Legacy scenes use different metadata names. The registered floor
				# owns dimensions; adapt display data without rewriting those files.
				row["size_m"] = (registered[path] as Dictionary).get("size_m", row.get("size_m", []))
				row["source_label"] = "关卡房表绑定的正式房间文件"
				# A bound game room may still use whitebox visuals. This flag
				# identifies references in the picker, not the art's finish level.
				row["whitebox"] = false
				row["game_room"] = true
		if row.is_empty():
			continue
		var level_label := str(binding["display_name"])
		var previous_label := str(row["level"])
		row["level"] = level_label
		row["label"] = str(row["label"]).replace(previous_label, level_label)
		row["search"] = str(row["search"]) + " " + level_label.to_lower()
		seen[path] = true
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var left := str(a["level"]) + "/" + str(a["label"])
		var right := str(b["level"]) + "/" + str(b["label"])
		return left.naturalnocasecmp_to(right) < 0)
	return rows


static func _game_bindings(level: String) -> Dictionary:
	var entry: Dictionary = GAME_CONFIG.expedition_level(level)
	if entry.is_empty() or not FileAccess.file_exists(str(entry.get("scene_3d", ""))):
		return {}
	var root := PLAN_ROOT.path_join(level)
	var plan := _read_json(root.path_join("level_plan.json"))
	if str(plan.get("schema", "")) != "shellstorm2.battle.level_plan":
		return {}
	var policy: Dictionary = plan.get("generation_policy", {})
	if not bool(policy.get("runtime_enabled", false)):
		return {}
	var display_name := str(entry.get("display_name", plan.get("level_name_zh", level))).replace("远征关卡", "远征")
	var mode := str(policy.get("mode", (plan.get("provenance", {}) as Dictionary).get("mode", "")))
	if mode == "flow":
		return {"mode": mode, "rooms": {}, "display_name": display_name}
	var registered := {}
	for value in plan.get("floors", []):
		if not value is Dictionary:
			continue
		var relative := str((value as Dictionary).get("plan", ""))
		if relative.is_empty() or relative.is_absolute_path() or ".." in relative.split("/"):
			continue
		var floor_plan := _read_json(root.path_join(relative))
		for room_value in floor_plan.get("rooms", []):
			if not room_value is Dictionary:
				continue
			var room := room_value as Dictionary
			var runtime_id := str(room.get("legacy_room_id", ""))
			if runtime_id.is_empty():
				runtime_id = str(room.get("room_id", ""))
			if runtime_id.is_empty():
				continue
			# Existing fixed-room binding convention in TowerDescent3D:
			# expedition_static_layout_path(level, runtime_id). Only room IDs
			# declared by an enabled level's floor table can enter this list.
			var path := ROOT.path_join(level).path_join("f00_%s_static_layout.tscn" % runtime_id)
			registered[path] = room
	return {"mode": mode, "rooms": registered, "display_name": display_name}


static func _runtime_art_row(candidate: Dictionary) -> Dictionary:
	var path := str(candidate["path"])
	if not path.contains("/runtime_rooms/"):
		return {}
	var meta := read_metadata(path)
	var geometry: Variant = meta.get("runtime_room_geometry")
	if not geometry is Dictionary:
		return {}
	var source := geometry as Dictionary
	var dimensions: Variant = source.get("size")
	if str(source.get("schema", "")) != RUNTIME_ART.SCHEMA or not dimensions is Array:
		return {}
	if (dimensions as Array).size() != 2 or not _valid_dimensions(dimensions as Array):
		return {}
	if not source.get("type", null) is String or not source.get("safe_corner", null) is bool:
		return {}
	var identity := RoomIdentity.new()
	identity.dimensions = Vector2(float(dimensions[0]), float(dimensions[1]))
	identity.room_id = str(meta.get("room_id", ""))
	identity.room_type = str(source["type"])
	identity.template_id = str(meta.get("template_id", ""))
	identity.safe_room_corner_l = bool(source["safe_corner"])
	var descriptor := RUNTIME_ART.describe(identity)
	identity.free()
	# art_path uses only this anchor's directory. Do not instantiate the game
	# or use matching_path(), which would load the entire PackedScene graph.
	var anchor := path.get_base_dir().get_base_dir().path_join("index_anchor.tscn")
	if RUNTIME_ART.art_path(anchor, descriptor) != path:
		return {}
	if str(meta.get("runtime_room_signature", "")) != str(descriptor["signature"]):
		return {}
	var row := candidate.duplicate(true)
	var type_names := {"COMBAT": "战斗房", "BOSS": "Boss房", "STAIR_LOBBY": "入口安全房",
		"SAFE_ROOM": "安全房", "UPGRADE": "准备房", "MERCHANT": "商店", "EVENT": "事件房",
		"SCAVENGE": "搜索房", "STORAGE": "储藏房", "TRAP": "陷阱房", "EXTRACTION": "撤离房"}
	var type_label := str(type_names.get(str(source["type"]), "连接房"))
	var style: Dictionary = descriptor["style"]
	var title := "%s-%s %d×%dm · %s" % [row["level"], type_label,
		int(round(float(dimensions[0]))), int(round(float(dimensions[1]))), str(style.get("note", ""))]
	row["source_room_id"] = str(meta.get("room_id", meta.get("runtime_source_room_id", "")))
	row["room_id"] = str(descriptor["template_id"])
	row["template_id"] = str(descriptor["template_id"])
	row["kit"] = "正式房型"
	row["label"] = title
	row["whitebox"] = false
	row["game_room"] = true
	row["size_m"] = dimensions
	row["source_label"] = "游戏运行时匹配的正式房间文件 · " + str(descriptor["style_label"])
	row["search"] = (title + " " + str(row["level_id"]) + " " + str(row["template_id"]) + " " + path).to_lower()
	return row


static func _valid_dimensions(values: Array) -> bool:
	for value in values:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0:
			return false
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}

static func scan(extra_paths: Array = []) -> Array[Dictionary]:
	var paths: Array[String] = []
	_walk(ROOT, paths)
	for path in extra_paths:
		if str(path).ends_with(".tscn") and FileAccess.file_exists(str(path)) and not str(path) in paths:
			paths.append(str(path))
	paths.sort()
	var rows: Array[Dictionary] = []
	var plans := {}
	for path in paths:
		var file := path.get_file()
		if file.contains("walk_surface"):
			continue
		# Old room_static_layout aliases coexist with their canonical expedition_01 files.
		if file == "room_static_layout.tscn":
			var alias := ROOT.path_join("expedition_01/" + path.get_base_dir().get_file() + "_static_layout.tscn")
			if FileAccess.file_exists(alias):
				continue
		var meta := read_metadata(path)
		if meta.is_empty():
			continue
		var level := str(meta.get("level_id", ""))
		if level.is_empty():
			for segment in path.split("/"):
				if segment.begins_with("expedition_0"):
					level = segment
		var level_label := "远征" + level.trim_prefix("expedition_") if not level.is_empty() else "共享房型"
		if not plans.has(level):
			plans[level] = _plan(level)
		var room_id := str(meta.get("authored_room_id", meta.get("room_id", file.trim_suffix("_static_layout.tscn").trim_suffix(".tscn")))).trim_prefix("f00_")
		var plan_row: Dictionary = (plans[level] as Dictionary).get(room_id, {})
		var template := str(meta.get("template_id", plan_row.get("template_id", "")))
		var authored_art := not str(meta.get("scene_builder_schema", "")).is_empty()
		var whitebox := not authored_art and (bool(meta.get("whitebox", false)) or file.begins_with("rt_") or file.begins_with("cr_") or path.contains("/egt_room_types/") or str(meta.get("source_mode", "")).contains("whitebox"))
		var egt := str(meta.get("schema", "")) == "shellstorm2.egt_room_type.whitebox.v001"
		var source_label := level_label
		var aliases := ""
		if egt:
			level_label = "共享白盒"
			source_label = "EGT旧静态参考 · 11.9m；非远征03实际运行房间"
			aliases = "远征03 expedition_03 EGT共享白盒"
			template = str(meta.get("shell_id", template))
		elif level == "expedition_03" and whitebox:
			source_label = "远征03白盒模板 · 2.8m；非实际运行房间"
		var kit := str(meta.get("kit_tag", ""))
		if kit.is_empty():
			kit = _suite(str(meta.get("asset_id", "")) + " " + template + " " + file)
		if egt:
			kit = "旧静态参考 11.9m / " + str(meta.get("egt_kind_zh", meta.get("egt_kind", "房型")))
		elif level == "expedition_03" and whitebox:
			kit = "白盒模板 2.8m / " + kit
		var title := str(meta.get("display_name", meta.get("room_name", "")))
		if title.is_empty():
			if egt:
				title = "EGT-%s-%s" % [meta.get("egt_kind_zh", "房型"), meta.get("door_sides", "")]
			elif room_id.begins_with("room_"):
				title = "%s-%s%s房" % [level_label, kit.trim_suffix("套件"), room_id.trim_prefix("room_")]
			elif room_id in ["boss", "boss_room_02", "extraction", "entry", "start"]:
				title = level_label + "-" + {"boss": "Boss房", "boss_room_02": "Boss02房", "extraction": "撤离房", "entry": "入口安全房", "start": "入口安全房"}[room_id]
			elif room_id.begins_with("secret_"):
				title = level_label + "-" + kit.trim_suffix("套件") + "秘密房"
			else:
				title = level_label + "-" + room_id.trim_prefix("rt_").trim_prefix("art_")
		rows.append({"path": path, "level": level_label, "level_id": level, "kit": kit, "label": title, "source_label": source_label,
			"room_id": room_id, "template_id": template, "whitebox": whitebox,
			"size_m": meta.get("size_m", []), "door_count": meta.get("door_count", 0),
			"search": (title + " " + room_id + " " + template + " " + kit + " " + aliases + " " + path).to_lower()})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_shared := str(a["level"]).begins_with("共享")
		var b_shared := str(b["level"]).begins_with("共享")
		if a_shared != b_shared:
			return not a_shared
		var left := str(a["level"]) + "/" + str(a["kit"]) + "/" + str(a["label"])
		var right := str(b["level"]) + "/" + str(b["kit"]) + "/" + str(b["label"])
		return left.naturalnocasecmp_to(right) < 0)
	return rows

static func _walk(directory: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tscn"):
			paths.append(directory.path_join(file))
	for folder in DirAccess.get_directories_at(directory):
		_walk(directory.path_join(folder), paths)

static func read_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var lines := file.get_as_text().split("\n")
	var result := {}
	var found_root := false
	var index := 0
	while index < lines.size():
		var line := str(lines[index])
		index += 1
		if line.begins_with("[node "):
			if found_root:
				break
			found_root = true
			result["_root"] = true
		if found_root and line.begins_with("metadata/") and line.contains(" = "):
			var key := line.get_slice(" = ", 0).trim_prefix("metadata/")
			# JSON primitives/collections only. In particular, never evaluate
			# Object(), Resource(), ExtResource() or SubResource() expressions.
			if key in ["level_id", "authored_room_id", "room_id", "template_id", "asset_id", "source_mode", "kit_tag", "display_name", "room_name", "scene_builder_schema", "schema", "whitebox", "shell_id", "egt_kind", "egt_kind_zh", "door_sides", "door_count", "size_m", "runtime_room_geometry", "runtime_room_signature", "runtime_source_room_id"]:
				var value := line.substr(line.find(" = ") + 3)
				if key == "runtime_room_geometry" and value.strip_edges() == "{":
					# Godot writes this JSON-compatible dictionary across lines.
					# Bound the read to the dictionary; malformed data is omitted.
					while index < lines.size():
						var next := str(lines[index])
						if next.begins_with("[node ") or next.begins_with("metadata/"):
							break
						index += 1
						value += "\n" + next
						if next.strip_edges() == "}":
							break
				var json := JSON.new()
				if json.parse(value) == OK:
					result[key] = json.data
	return result

static func _plan(level: String) -> Dictionary:
	var path := "res://data/level_plans/%s/floors/floor_00.json" % level
	var result := {}
	if not FileAccess.file_exists(path):
		return result
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if plan is Dictionary:
		for room in plan.get("rooms", []):
			result[str(room.get("key", ""))] = room
	return result

static func _suite(text: String) -> String:
	text = text.to_lower()
	for pair in [["boss_room_02", "Boss房02套件"], ["boss", "Boss房套件"], ["office", "办公室套件"],
		["db_", "数据库套件"], ["database", "数据库套件"], ["corridor", "走廊套件"],
		["bridge", "通道桥套件"], ["hotel", "酒店套件"], ["extraction", "撤离房套件"], ["safe", "安全房套件"]]:
		if text.contains(pair[0]):
			return pair[1]
	return "通用套件"
