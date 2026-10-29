@tool
extends RefCounted
## Discover layouts without instantiating their scripts or maintaining a second registry.

const ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances"

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
			source_label = "远征03旧静态参考 · 11.9m；非实际运行房间"
		var kit := str(meta.get("kit_tag", ""))
		if kit.is_empty():
			kit = _suite(str(meta.get("asset_id", "")) + " " + template + " " + file)
		if egt:
			kit = "旧静态参考 11.9m / " + str(meta.get("egt_kind_zh", meta.get("egt_kind", "房型")))
		elif level == "expedition_03" and whitebox:
			kit = "旧静态参考 11.9m / " + kit
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
		rows.append({"path": path, "level": level_label, "kit": kit, "label": title, "source_label": source_label,
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
	var result := {}
	var found_root := false
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("[node "):
			if found_root:
				break
			found_root = true
			result["_root"] = true
		if found_root and line.begins_with("metadata/") and line.contains(" = "):
			var key := line.get_slice(" = ", 0).trim_prefix("metadata/")
			# Primitive values only: never parse or evaluate arbitrary object expressions.
			if key in ["level_id", "authored_room_id", "room_id", "template_id", "asset_id", "source_mode", "kit_tag", "display_name", "room_name", "scene_builder_schema", "schema", "whitebox", "shell_id", "egt_kind", "egt_kind_zh", "door_sides", "door_count", "size_m"]:
				result[key] = str_to_var(line.substr(line.find(" = ") + 3))
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
