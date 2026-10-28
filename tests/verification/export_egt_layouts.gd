extends SceneTree
## 把组装结果导出成 JSON，交给 Python 画俯视图。
##
## 导出两组：
## 1. **六张骨架**：固定 seed，逐张看形状对不对；
## 2. **随机抽关**：每局按 `pick_flow()` 抽一张骨架，模拟真实开局 ——
##    用来证明"换种子真的得到不同的关卡"，不是同一张图换个标题。
##
## godot --headless --path . --script res://tests/verification/export_egt_layouts.gd

const ASSEMBLER := preload("res://src/map/EgtFlowAssembler.gd")
const PLAN_DIR := "res://data/level_plans/expedition_03"
const OUT_DIR := "res://docs/art/egt_flow_layouts"
const SEED := 4100
## 随机抽关的局数：每局按 `pick_flow()` 抽一张骨架，模拟真实开局。
const DRAW_COUNT := 8
const DRAW_BASE_SEED := 20261028


func _init() -> void:
	var templates := {}
	var dir := DirAccess.open("%s/room_templates" % PLAN_DIR)
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/room_templates/%s" % [PLAN_DIR, file_name])) as Dictionary
			templates[str(data.get("template_id", ""))] = data

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var all_flows: Array = []
	var flow_dir := DirAccess.open("%s/flows" % PLAN_DIR)
	var names: Array[String] = []
	for file_name in flow_dir.get_files():
		if file_name.begins_with("flow_") and file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		all_flows.append(JSON.parse_string(FileAccess.get_file_as_string(
			"%s/flows/%s" % [PLAN_DIR, file_name])) as Dictionary)

	# 1) 六张骨架，固定 seed
	var flows: Array = []
	for flow in all_flows:
		var record := _build_record(flow, templates, SEED, "")
		flows.append(record)
		print("EXPORT %-14s ok=%s rooms=%d corridors=%d conn=%s" % [
			str(record["flow_id"]), str(record["ok"]),
			(record["rooms"] as Array).size(), (record["corridors"] as Array).size(),
			str(record.get("connector_sizes", []))])

	# 2) 随机抽关
	var draws: Array = []
	for i in range(DRAW_COUNT):
		var seed_value := DRAW_BASE_SEED + i * 7919
		var flow: Dictionary = ASSEMBLER.pick_flow(all_flows, seed_value)
		if flow.is_empty():
			continue
		var record := _build_record(flow, templates, seed_value, "draw_%02d" % (i + 1))
		draws.append(record)
		print("EXPORT %-14s ok=%s rooms=%d corridors=%d conn=%s" % [
			str(record["flow_id"]), str(record["ok"]),
			(record["rooms"] as Array).size(), (record["corridors"] as Array).size(),
			str(record.get("connector_sizes", []))])

	var payload := {
		"seed": SEED, "level_id": "expedition_03",
		"draw_base_seed": DRAW_BASE_SEED,
		"flows": flows, "draws": draws,
	}
	var file := FileAccess.open("%s/layouts.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("EXPORTED -> %s/layouts.json" % OUT_DIR)
	quit(0)


## `label` 非空时作为文件名前缀（随机抽关用），避免与骨架名冲突。
func _build_record(flow: Dictionary, templates: Dictionary, seed_value: int,
		label: String) -> Dictionary:
	var result: Dictionary = ASSEMBLER.assemble_flow(flow, templates, {}, seed_value)
	var record := {
		"flow_file": "%s.json" % str(flow.get("flow_id", "")),
		"flow_id": str(flow.get("flow_id", "")),
		"flow_name_zh": str(flow.get("flow_name_zh", "")),
		"label": label,
		"seed": seed_value,
		"ok": bool(result["ok"]),
		"error": str(result["error"]),
		"loops": (result["loops"] as Array).size(),
		"corridors": [],
		"rooms": [],
		"edges": [],
		"connector_sizes": [],
	}
	for value in result["rooms"] as Array:
		var room := value as Dictionary
		var ports := {}
		for side in (room["ports"] as Dictionary):
			var lanes: Array = []
			for lane in (room["ports"] as Dictionary)[side] as Array:
				lanes.append(float(lane))
			ports[str(side)] = lanes
		var size: Vector2 = room["size"]
		var node_id := str(room["node_id"])
		if node_id.begins_with("conn"):
			(record["connector_sizes"] as Array).append("%s %.0fx%.0f" % [
				str(room["template_id"]), size.x, size.y])
		(record["rooms"] as Array).append({
			"node_id": node_id,
			"template_id": str(room["template_id"]),
			"center": [(room["center"] as Vector2).x, (room["center"] as Vector2).y],
			"size": [size.x, size.y],
			"ports": ports,
		})
	for value in result["edges"] as Array:
		var edge := value as Dictionary
		(record["edges"] as Array).append({
			"from": str(edge["from"]), "to": str(edge["to"]),
			"kind": str(edge.get("kind", "direct")),
			"gap_m": float(edge["gap_m"]),
			"corridor_length_m": float(edge.get("corridor_length_m", 0.0)),
		})
	for value in result["corridors"] as Array:
		var corridor := value as Dictionary
		(record["corridors"] as Array).append({
			"from": str(corridor["from_node"]), "to": str(corridor["to_node"]),
			"from_side": str(corridor.get("from_side", "")),
			"from_lane": float(corridor.get("from_lane", 0.0)),
			"to_side": str(corridor.get("to_side", "")),
			"to_lane": float(corridor.get("to_lane", 0.0)),
			"length_m": float(corridor["length_m"]),
		})
	return record
