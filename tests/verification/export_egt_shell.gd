extends SceneTree
## 把「组装器 → 桥接层 → 壳体区块」的**最终几何**导出成 JSON，交给 Python 画。
##
## 与 `export_egt_layouts.gd` 的区别：那个导出的是**房间表**（矩形 + 门槽），
## 画出来是"计划图"；这个导出的是 `build_block()` 真正吐出来的**实例清单** ——
## 墙、门洞、L 角件、地砖，一格一格都在。画出来就是玩家会看到的俯视平面。
##
## 这一层必须出图：房间表看着都对、壳体却少一面墙 / 门开在实墙上 / 走廊拐角缺失，
## 逻辑断言一条都抓不到（走廊房与主房共用墙时，lane 归属是靠"先声明者拥有"合并的）。
##
## godot --headless --path . --script res://tests/verification/export_egt_shell.gd

const ASSEMBLER := preload("res://src/map/EgtFlowAssembler.gd")
const BRIDGE := preload("res://src/map/EgtPlanBridge.gd")
const BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")

const PLAN_DIR := "res://data/level_plans/expedition_03"
const OUT_DIR := "res://docs/art/egt_shell_layouts"
const SEED := 4100
## 随机抽关的局数（与房间表图集分开，看的是"每一局都像样"）。
const DRAW_COUNT := 4
const DRAW_BASE_SEED := 20261028


func _init() -> void:
	var templates := _load_templates()
	var flows := _load_flows()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var payload := {"seed": SEED, "level_id": "expedition_03", "cases": []}
	for flow in flows:
		payload["cases"].append(_build(flow, templates, SEED, ""))
	for i in range(DRAW_COUNT):
		var seed_value := DRAW_BASE_SEED + i * 7919
		var flow: Dictionary = ASSEMBLER.pick_flow(flows, seed_value)
		if flow.is_empty():
			continue
		payload["cases"].append(_build(flow, templates, seed_value, "draw_%02d" % (i + 1)))

	var file := FileAccess.open("%s/shells.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("EXPORTED -> %s/shells.json" % OUT_DIR)
	quit(0)


func _build(flow: Dictionary, templates: Dictionary, seed_value: int, label: String) -> Dictionary:
	var result: Dictionary = ASSEMBLER.assemble_flow(flow, templates, {}, seed_value)
	var record := {
		"label": label,
		"flow_id": str(flow.get("flow_id", "")),
		"seed": seed_value,
		"ok": bool(result.get("ok", false)),
		"error": str(result.get("error", "")),
		"rooms": [],
		"walls": [],
		"doors": [],
		"corners": [],
		"floors": [],
		"stats": {},
	}
	if not record["ok"]:
		return record
	var bridged: Dictionary = BRIDGE.to_block(result)
	record["bridge_errors"] = bridged["errors"]
	record["stats"] = bridged["stats"]
	var built: Dictionary = BUILDER.build_block(bridged["block"] as Array)
	record["build_errors"] = built["errors"]
	if not (built["errors"] as Array).is_empty():
		return record

	for value in bridged["block"] as Array:
		var room := value as Dictionary
		var bx: Array = room["bounds_x_m"]
		var by: Array = room["bounds_y_m"]
		var doors := {}
		for side_value in (room["doors"] as Dictionary).keys():
			doors[str(side_value)] = []
			for gate in BUILDER._port_offsets((room["doors"] as Dictionary)[side_value]):
				(doors[str(side_value)] as Array).append(float(gate))
		(record["rooms"] as Array).append({
			"room_id": str(room["room_id"]),
			"bounds_x": [float(bx[0]), float(bx[1])],
			"bounds_y": [float(by[0]), float(by[1])],
			"doors": doors,
			"is_corridor": str((bridged["room_meta"] as Dictionary).get(
				str(room["room_id"]), {}).get("is_corridor", false)),
		})

	for value in built["instances"] as Array:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		var position: Array = instance.get("position_m", [0.0, 0.0, 0.0]) as Array
		var item := {
			"id": str(instance.get("instance_id", "")),
			"pos": [float(position[0]), float(position[1])],
			"rot": float(instance.get("rotation_z_deg", 0.0)),
			"room_id": str(instance.get("room_id", "")),
		}
		if role == "floor_tile":
			(record["floors"] as Array).append(item)
		elif role == "door_leaf_preview":
			(record["doors"] as Array).append(item)
		elif role == "corner_l":
			(record["corners"] as Array).append(item)
		else:
			(record["walls"] as Array).append(item)
	print("EXPORT %-10s %-8s rooms=%d walls=%d doors=%d floors=%d" % [
		label if not label.is_empty() else "flow", str(record["flow_id"]),
		(record["rooms"] as Array).size(), (record["walls"] as Array).size(),
		(record["doors"] as Array).size(), (record["floors"] as Array).size()])
	return record


func _load_templates() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("%s/room_templates" % PLAN_DIR)
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/room_templates/%s" % [PLAN_DIR, file_name])) as Dictionary
			out[str(data.get("template_id", ""))] = data
	return out


func _load_flows() -> Array:
	var out: Array = []
	var dir := DirAccess.open("%s/flows" % PLAN_DIR)
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.begins_with("flow_") and file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		out.append(JSON.parse_string(FileAccess.get_file_as_string(
			"%s/flows/%s" % [PLAN_DIR, file_name])) as Dictionary)
	return out
