extends Node
## 诊断探针：不修改产品逻辑，复现门外 2.5 -> 99F -> 离开 -> 返回 99F。
## 重点记录每个边界前后的：玩法灯、Art 表现灯、收音机、房间流送与 facility 快照。

const SEED := 990099
const BLACKOUT_ID := "nar_tower_opening_02_5_stairwell_blackout"
const FACILITY_DOOR_OUTSIDE := Vector3(17.0, -12.0, 2.5)

var _tower: TowerDescent3D = null
var _facility: DungeonRoom3D = null
var _player: Player3D = null
var _radio: Base99Radio3D = null
var _rooms: Dictionary = {}
var _last_light := ""
var _last_radio := ""
var _last_facility_stream := ""
var _last_runtime_light := ""

func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		printerr("DIAG_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	_tower = scene.instantiate() as TowerDescent3D
	_tower.test_mode = true
	_tower.run_seed_override = SEED
	add_child(_tower)
	await _settle()

	_rooms = _tower.get("_room_by_id") as Dictionary
	_facility = _rooms.get("facility") as DungeonRoom3D
	_player = _tower.get("player") as Player3D
	_radio = _tower.find_child("99F床边桌独立收音机", true, false) as Base99Radio3D
	_dump_room_positions()
	_dump_stair_connector()
	_dump("BOOT")

	# 1) 真实位置评估：99F 基地东门外触发 2.5。
	_player.global_position = FACILITY_DOOR_OUTSIDE + Vector3.UP * 0.05
	_player.velocity = Vector3.ZERO
	_tower.call("_refresh_physical_location_authority", true)
	await _settle()
	for i in 30:
		_player.global_position = FACILITY_DOOR_OUTSIDE + Vector3.UP * 0.05
		_player.velocity = Vector3.ZERO
		NarrativeDirector.evaluate_point_for_test()
		await get_tree().process_frame
		if NarrativeDirector.active_id() == BLACKOUT_ID or NarrativeDirector.dispatch_log().has("start:" + BLACKOUT_ID):
			break
	_dump("2.5_ACTIVE")
	await _wait_until_narrative_idle(2.0)
	_dump("2.5_IDLE")

	# 2) 进入 99F 基地地面，走真实物理位置权威与 room_entered 链。
	_enter_room("facility")
	_dump("ENTER_FACILITY_AFTER_2.5")

	# 3) 在 99F 打开收音机，作为跨楼层状态对照样本。
	if _radio != null:
		_radio.set_radio_state("a")
	await _settle_short()
	_dump("FACILITY_RADIO_A")

	# 4) 离开基地进入 98F 入口房；这里会触发 radio.set_floor_active(false)，
	#    也会触发 facility 的 room transition / streaming / runtime capture。
	_enter_room("floor_01_entry")
	_dump("LEAVE_FACILITY_TO_98F")

	# 5) 返回 99F，观察 DATA_ONLY 恢复或壳体保留，以及灯光快照来源。
	_enter_room("facility")
	_dump("RETURN_FACILITY")

	# 给任何 deferred detail 重建/表现灯同步一个观察窗。
	await _settle()
	_dump("RETURN_FACILITY_SETTLED")
	_print_logs()
	get_tree().quit(0)

func _enter_room(room_id: String) -> void:
	var room := _rooms.get(room_id) as DungeonRoom3D
	if room == null:
		printerr("DIAG_FAIL: room missing: %s" % room_id)
		return
	room.ensure_shell_built()
	_player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	_player.velocity = Vector3.ZERO
	_tower.call("_refresh_physical_location_authority", true)
	await _settle_short()

func _dump_room_positions() -> void:
	print("\n########## ROOM POSITIONS ##########")
	for room_id in ["start", "facility", "floor_01_entry"]:
		var room := _rooms.get(room_id) as DungeonRoom3D
		if room == null:
			print("ROOM %s MISSING" % room_id)
		else:
			print("ROOM %s pos=%s dims=%s stream=%s" % [
			room_id, str(room.global_position), str(room.get_dimensions()), room.get_stream_state_name()
			])

func _dump_stair_connector() -> void:
	print("\n########## FACILITY <-> 98F DOOR / STAIR ##########")
	var corridors: Dictionary = _tower.get("_corridor_by_edge") as Dictionary
	for edge_value in corridors.keys():
		var edge := str(edge_value)
		if not ("facility" in edge and "floor_01_entry" in edge):
			continue
		var connector := corridors[edge] as Node3D
		print("CONNECTOR edge=%s name=%s meta=%s" % [edge, connector.name, str(connector.get_meta_list())])
		print("PATH_POINTS=%s" % str(connector.get_meta("path_points", [])))
		print("UPPER_DOOR_POSITION=%s" % str(connector.get_meta("upper_door_position", Vector3.INF)))
		print("LOWER_DOOR_POSITION=%s" % str(connector.get_meta("lower_door_position", Vector3.INF)))
		print("UPPER_SIDE=%s LOWER_SIDE=%s" % [
			str(connector.get_meta("upper_door_side", "")),
			str(connector.get_meta("lower_door_side", "")),
		])

func _dump(label: String) -> void:
	var runtime_states: Dictionary = _tower.get("_segment_runtime_state") as Dictionary
	var facility_runtime: Variant = runtime_states.get("facility", null)
	var facility_snapshot := _facility.get_room_snapshot() if _facility != null else {}
	var physical := _tower.call("get_physical_location_snapshot") as Dictionary
	var radio_snapshot := _radio.get_state_snapshot() if _radio != null else {}
	var light_on := bool(_facility.call("is_room_light_on")) if _facility != null else false
	var stream_name := _facility.get_stream_state_name() if _facility != null else "MISSING"
	var runtime_light := "MISSING"
	if facility_runtime is Dictionary:
		runtime_light = str((facility_runtime as Dictionary).get("room_light_on", "MISSING"))
	var art_states: Array[String] = []
	if _facility != null:
		for node in _facility.find_children("*", "BaseFixtureGlow3D", true, false):
			if node.has_method("get_presentation_snapshot"):
				var art := node.call("get_presentation_snapshot") as Dictionary
				art_states.append("%s:%s" % [node.name, str(art.get("presentation_lighting_enabled", "?"))])
	var active_light_count := 0
	var facility_light_count := 0
	for node in get_tree().get_nodes_in_group("wasteland_light_3d"):
		if node is WastelandLight3D and _tower.is_ancestor_of(node):
			if _facility != null and _facility.is_ancestor_of(node):
				facility_light_count += 1
				var light_snapshot := (node as WastelandLight3D).get_snapshot()
				if bool(light_snapshot.get("illumination_active", false)):
					active_light_count += 1
	var changed := (
			_last_light != str(light_on)
			or _last_radio != str(radio_snapshot.get("state", "MISSING"))
			or _last_facility_stream != stream_name
			or _last_runtime_light != runtime_light
	)
	print("\n########## %s changed=%s ##########" % [label, str(changed)])
	print("PHYSICAL %s" % str(physical))
	print("CURRENT_ROOM=%s" % str(_tower.get("_current_room_id")))
	print("FACILITY light_on=%s stream=%s snapshot=%s" % [str(light_on), stream_name, str(facility_snapshot)])
	print("FACILITY_RUNTIME=%s" % str(facility_runtime))
	print("LIGHTS facility=%d active=%d" % [facility_light_count, active_light_count])
	print("ART_GLOW=%s" % str(art_states))
	print("RADIO=%s" % str(radio_snapshot))
	print("STREAM_STATES=%s" % str((_tower.get("_room_graph_runtime").get_stream_states_snapshot())))
	_last_light = str(light_on)
	_last_radio = str(radio_snapshot.get("state", "MISSING"))
	_last_facility_stream = stream_name
	_last_runtime_light = runtime_light

func _print_logs() -> void:
	print("\n########## DISPATCH LOG ##########")
	for line in NarrativeDirector.dispatch_log():
		print("   %s" % line)
	print("\n########## DIAGNOSTICS ##########")
	for line in NarrativeDirector.diagnostics():
		print("   %s" % line)

func _wait_until_narrative_idle(timeout_seconds: float) -> void:
	var waited := 0.0
	while waited < timeout_seconds and not NarrativeDirector.active_id().is_empty():
		await get_tree().process_frame
		waited += get_process_delta_time()

func _settle_short() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame

func _settle() -> void:
	await _settle_short()
	await get_tree().create_timer(0.35).timeout
