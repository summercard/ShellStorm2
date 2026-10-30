extends Node3D
## 探针：远征03（flow 关卡）门态的存档往返取证。
##
## 业主报「安全屋下线再上线，出口的门就不见了」。
## 门不见 = `RoomDoor3D` 的 slide 双扇被 `set_open(true)` 滑进墙体（见该文件 §_set_open_slide）。
##
## 三段取证，只读不改游戏逻辑：
##   A 装配完成后 dump 门态
##   B 构造"该门关着"的存档并调 `_restore_runtime_save_snapshot()`，dump（存档应用后的门态）
##   C 再调 `_open_all_flow_doors()`（装配收尾会走这里），dump（是否被覆盖）
##
## ⚠️ 必须隔离用户数据目录，否则 autoload（GameTimeManager）会写真实存档：
##   APPDATA=/tmp/godot_iso godot --headless --path . res://tests/verification/probe_expedition03_save_doors.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
const EDGE_A := "start"
const EDGE_B := "room_01"

var _scene: Node


func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("SAVE_DOOR_PROBE FAIL: 场景加载失败")
		get_tree().quit(1)
		return
	_scene = packed.instantiate()
	add_child(_scene)
	var first_open := -1
	var frame := 0
	for i in range(600):
		await get_tree().process_frame
		frame += 1
		if first_open < 0:
			first_open = _probe_start_door_state(frame)
		var rooms_value: Variant = _scene.get("_rooms")
		if rooms_value is Array and (rooms_value as Array).size() >= 10:
			break
	await get_tree().process_frame
	print("SAVE_DOOR_PROBE first_open_frame=%d current_room=%s" % [
		first_open, str(_scene.get("_current_room_id"))])
	print("SAVE_DOOR_PROBE level=%s flow=%s rooms=%d" % [
		str(_scene.call("get_expedition_level_id")),
		str(_scene.get("_flow_rules_active")),
		(_scene.get("_rooms") as Array).size(),
	])
	print("SAVE_DOOR_PROBE flow_doors openable_on_start=%d closed_on_start=%d" % [
		int(_scene.get_meta("flow_doors_openable_on_start", -1)),
		int(_scene.get_meta("flow_doors_closed_on_start", -1)),
	])
	_dump("A_after_bootstrap")

	# B：存档里明确写"该门关着"，期望恢复后门保持关。
	var snapshot := {
		"valid": true,
		"schema": "runtime_player_state_v2",
		"scope": "combat",
		"run_seed": 1,
		"run_id": "probe:expedition_03",
		"layout_id": "probe",
		"checkpoint_id": "probe",
		"current_room_id": EDGE_A,
		"current_floor_index": 0,
		"player_position": [],
		"runtime_map_id": str(_scene.call("get_runtime_map_id")),
		"edge_states": {_edge_key(EDGE_A, EDGE_B): false},
		"world_state": {"schema": "tower_world_state_v1", "segment_runtime_state": {}},
	}
	_scene.call("_restore_runtime_save_snapshot", snapshot)
	await get_tree().process_frame
	_dump("B_after_restore_false")

	# C：装配收尾无条件把所有连通门打开（TowerDescent3D:868）。
	_scene.call("_open_all_flow_doors")
	await get_tree().process_frame
	_dump("C_after_open_all_flow_doors")

	_dump_save_snapshot_fields()
	get_tree().quit(0)


## 逐帧盯 start 房「北门」（通往 room_01）何时变成**可开启**。
##
## 2026-10-30 起「可开启」不再等于「门板被推开」：门板留在门洞里，
## 走近才感应推开（见 `RoomDoor3D` 的感应段），所以这里盯 `openable`。
func _probe_start_door_state(frame: int) -> int:
	var rooms: Dictionary = _scene.get("_room_by_id") as Dictionary
	var start: Node = rooms.get(EDGE_A) as Node
	if start == null:
		return -1
	var door: Node = start.call("get_door_node", "north") as Node
	if door == null:
		return -1
	if not bool(door.get("openable")):
		return -1
	print("SAVE_DOOR_PROBE door_openable_at_frame=%d start_cleared=%s spawned=%s" % [
		frame,
		str(start.get("cleared")),
		str((_scene.get("_spawned_rooms") as Dictionary).has(EDGE_A)),
	])
	return frame


func _dump(tag: String) -> void:
	var open_edges: Dictionary = _scene.get("_open_edges") as Dictionary
	var edge := _edge_key(EDGE_A, EDGE_B)
	print("SAVE_DOOR_PROBE %s edge_open=%s open_edges_count=%d declared=%d edges=%s" % [
		tag,
		str(open_edges.get(edge, "missing")),
		open_edges.size(),
		(_scene.get("_declared_edges") as Array).size(),
		str(open_edges.keys().slice(0, 6)),
	])
	for room_id in [EDGE_A, EDGE_B]:
		var room: Node = (_scene.get("_room_by_id") as Dictionary).get(room_id) as Node
		if room == null:
			print("SAVE_DOOR_PROBE %s room=%s MISSING" % [tag, room_id])
			continue
		for value in (room.get("_door_nodes") as Dictionary).values():
			if value == null or not is_instance_valid(value):
				continue
			var snap: Dictionary = (value as Node).call("get_snapshot")
			print("SAVE_DOOR_PROBE %s room=%s dir=%s target=%s openable=%s open=%s panel_x=%.2f right_x=%.2f style=%s blocks=%s" % [
				tag,
				room_id,
				str(snap.get("direction", "")),
				str(snap.get("target_room_id", "")),
				str(snap.get("openable", "")),
				str(snap.get("is_open", "")),
				float(snap.get("panel_x", 0.0)),
				float(snap.get("second_panel_x", 0.0)),
				str(snap.get("opening_style", "")),
				str(snap.get("blocks_passage", "")),
			])


## 存档里到底有哪些房间级状态 —— 直接读采集出来的快照。
func _dump_save_snapshot_fields() -> void:
	if not _scene.has_method("build_runtime_save_snapshot"):
		return
	var snap: Dictionary = _scene.call("build_runtime_save_snapshot")
	if snap.is_empty():
		print("SAVE_DOOR_PROBE snapshot EMPTY（test_mode 下可能不采集）")
		return
	var keys: Array = snap.keys()
	keys.sort()
	print("SAVE_DOOR_PROBE snapshot_keys=%s" % str(keys))
	var saved_edges: Dictionary = snap.get("edge_states", {}) as Dictionary
	var saved_edge_keys: Array = saved_edges.keys()
	saved_edge_keys.sort()
	print("SAVE_DOOR_PROBE saved_edge_states_count=%d keys=%s" % [
		saved_edges.size(), str(saved_edge_keys)])
	var neighbors: Dictionary = _scene.get("_room_neighbors") as Dictionary
	print("SAVE_DOOR_PROBE neighbors[start]=%s neighbors[room_01]=%s" % [
		str(neighbors.get(EDGE_A, [])), str(neighbors.get(EDGE_B, []))])
	var segment: Dictionary = (
		(snap.get("world_state", {}) as Dictionary).get("segment_runtime_state", {}) as Dictionary
	)
	print("SAVE_DOOR_PROBE segment_rooms=%d" % segment.size())
	for room_id in [EDGE_A, EDGE_B]:
		if not segment.has(room_id):
			continue
		var room_state: Dictionary = segment[room_id] as Dictionary
		var state_keys: Array = room_state.keys()
		state_keys.sort()
		print("SAVE_DOOR_PROBE segment[%s]_keys=%s" % [room_id, str(state_keys)])


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
