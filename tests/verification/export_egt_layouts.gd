extends SceneTree
## 把六张骨架的组装结果导出成 JSON，交给 Python 画俯视图。
## godot --headless --path . --script res://tests/verification/export_egt_layouts.gd

const ASSEMBLER := preload("res://src/map/EgtFlowAssembler.gd")
const PLAN_DIR := "res://data/level_plans/expedition_03"
const OUT_DIR := "res://docs/art/egt_flow_layouts"
const SEED := 4100


func _init() -> void:
	var templates := {}
	var dir := DirAccess.open("%s/room_templates" % PLAN_DIR)
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/room_templates/%s" % [PLAN_DIR, file_name])) as Dictionary
			templates[str(data.get("template_id", ""))] = data

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var flows := []
	var flow_dir := DirAccess.open("%s/flows" % PLAN_DIR)
	var names: Array[String] = []
	for file_name in flow_dir.get_files():
		if file_name.begins_with("flow_") and file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()

	for file_name in names:
		var flow: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"%s/flows/%s" % [PLAN_DIR, file_name])) as Dictionary
		var result: Dictionary = ASSEMBLER.assemble_flow(flow, templates, {}, SEED)
		var record := {
			"flow_file": file_name,
			"flow_id": str(flow.get("flow_id", "")),
			"flow_name_zh": str(flow.get("flow_name_zh", "")),
			"seed": SEED,
			"ok": bool(result["ok"]),
			"error": str(result["error"]),
			"loops": (result["loops"] as Array).size(),
			"corridors": [],
			"rooms": [],
			"edges": [],
		}
		for value in result["rooms"] as Array:
			var room := value as Dictionary
			var ports := {}
			for side in (room["ports"] as Dictionary):
				var lanes: Array = []
				for lane in (room["ports"] as Dictionary)[side] as Array:
					lanes.append(float(lane))
				ports[str(side)] = lanes
			(record["rooms"] as Array).append({
				"node_id": str(room["node_id"]),
				"template_id": str(room["template_id"]),
				"center": [(room["center"] as Vector2).x, (room["center"] as Vector2).y],
				"size": [(room["size"] as Vector2).x, (room["size"] as Vector2).y],
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
		flows.append(record)
		print("EXPORT %-14s ok=%s rooms=%d corridors=%d" % [
			str(record["flow_id"]), str(record["ok"]),
			(record["rooms"] as Array).size(), (record["corridors"] as Array).size()])

	var payload := {"seed": SEED, "level_id": "expedition_03", "flows": flows}
	var file := FileAccess.open("%s/layouts.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("EXPORTED -> %s/layouts.json" % OUT_DIR)
	quit(0)
