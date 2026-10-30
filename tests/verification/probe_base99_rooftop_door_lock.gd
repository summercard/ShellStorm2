extends Node
## 一次性探针：99F 基地 ↔ 100F 天台的**西侧楼梯门**是否真的被钉成「不可开启」。
##
## 判据（全部来自运行时快照，不看源码推测）：
##   A. 两端门板（99F `facility` 西 / 100F `start` 西）都存在且 `openable == false`；
##   B. 门是**关着**的，且碰撞仍挡路（`blocks_passage == true`）；
##   C. 交互文案含「需要钥匙」，门顶挂着同文案的 `LockedDoorSign`；
##   D. 走 E 交互通道（`_open_bound_simple_room_edge_door`）后门**仍然关着**；
##   E. 反向路径（`_activate_stair_return_interaction`）同样开不了。
##
## 只读：不改存档、不改门态之外的任何状态（D/E 只调用一次拒绝分支）。

const FACILITY_ROOM_ID := "facility"
const ROOFTOP_ROOM_ID := "start"
const EXPECTED_REASON := "需要钥匙"

var _failures: Array[String] = []


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("!! 无法加载 TowerDescent3D.tscn")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var facility := room_by_id.get(FACILITY_ROOM_ID) as DungeonRoom3D
	var rooftop := room_by_id.get(ROOFTOP_ROOM_ID) as DungeonRoom3D
	if facility == null or rooftop == null:
		print("!! 找不到房间：facility=", facility, " start=", rooftop)
		get_tree().quit(1)
		return

	var facility_door := _door_towards(facility, ROOFTOP_ROOM_ID)
	var rooftop_door := _door_towards(rooftop, FACILITY_ROOM_ID)

	print("")
	print("############ A. 门板存在性 ############")
	_report("99F facility 西侧楼梯门存在", facility_door != null)
	_report("100F start 西侧楼梯门存在", rooftop_door != null)
	if facility_door == null or rooftop_door == null:
		_finish()
		return

	print("")
	print("############ B. 不可开启 + 仍然挡路 ############")
	_dump_door("facility/" + facility_door.name, facility_door)
	_dump_door("start/" + rooftop_door.name, rooftop_door)
	_report("facility 门 openable == false", not facility_door.openable)
	_report("start 门 openable == false", not rooftop_door.openable)
	_report("facility 门处于关闭态", not facility_door.is_open)
	_report("start 门处于关闭态", not rooftop_door.is_open)
	_report(
		"facility 门碰撞仍在挡路",
		bool(facility_door.get_snapshot().get("blocks_passage", false))
	)

	print("")
	print("############ C. 文案与门牌 ############")
	var facility_prompt := facility_door.get_interaction_prompt_text()
	var rooftop_prompt := rooftop_door.get_interaction_prompt_text()
	print("  facility prompt = ", facility_prompt)
	print("  start    prompt = ", rooftop_prompt)
	_report("facility 文案含「%s」" % EXPECTED_REASON, facility_prompt.contains(EXPECTED_REASON))
	_report("start 文案含「%s」" % EXPECTED_REASON, rooftop_prompt.contains(EXPECTED_REASON))
	var sign_label := facility_door.get_node_or_null("LockedDoorSign") as Label3D
	print("  facility LockedDoorSign = ", sign_label.text if sign_label != null else "<缺>")
	_report("facility 门顶挂了 LockedDoorSign", sign_label != null)
	_report(
		"门牌文案含「%s」" % EXPECTED_REASON,
		sign_label != null and sign_label.text.contains(EXPECTED_REASON)
	)
	_report(
		"门牌 no_depth_test（不被门框裁掉）",
		sign_label != null and sign_label.no_depth_test
	)

	print("")
	print("############ D. E 交互通道开不了 ############")
	var edge := str(tower.call("_edge_key", FACILITY_ROOM_ID, ROOFTOP_ROOM_ID))
	var consumed := bool(
		tower.call(
			"_open_bound_simple_room_edge_door",
			facility_door,
			FACILITY_ROOM_ID,
			ROOFTOP_ROOM_ID,
			edge
		)
	)
	_report("交互被消费（有反馈，不是按键失灵）", consumed)
	_report("交互后 facility 门仍关闭", not facility_door.is_open)
	_report(
		"交互后 facility 门仍不可开启",
		not bool(facility_door.get_snapshot().get("openable", true))
	)

	print("")
	print("############ E. 楼梯返回通道开不了 ############")
	var return_door := rooftop_door
	var return_openable_before := return_door.openable
	var return_result := bool(
		tower.call("_activate_stair_return_interaction", {"upper_door": return_door})
	)
	_report("下行交互被消费", return_result)
	_report("下行交互后 start 门仍关闭", not return_door.is_open)
	_report("下行交互未篡改 openable", return_door.openable == return_openable_before)

	print("")
	print("############ F. 对照：东侧阁楼门未被误锁 ############")
	var transit := tower.get("_base_rooftop_transit_door") as RoomDoor3D
	if transit == null:
		print("  (东侧阁楼门未安装，跳过对照)")
	else:
		print("  BaseRooftopTransitDoor openable = ", transit.openable)
		_report("东侧阁楼门仍可开启", transit.openable)

	_finish()


func _door_towards(room: DungeonRoom3D, target_room_id: String) -> RoomDoor3D:
	for side_value in room.door_targets.keys():
		if str(room.door_targets[side_value]) != target_room_id:
			continue
		return room.get_door_node(str(side_value))
	return null


func _dump_door(label: String, door: RoomDoor3D) -> void:
	var snap := door.get_snapshot()
	print("--- ", label, " ---")
	print("  direction       = ", door.direction, "  target = ", door.target_room_id)
	print("  GLOBAL position = ", door.global_position.snappedf(0.001))
	print("  openable/open/blocks = ", snap.get("openable"), "/", snap.get("is_open"), "/",
		snap.get("blocks_passage"))
	print("  requires_key    = ", snap.get("requires_key"))
	print("  locked meta     = ", door.get_meta("base99_rooftop_stair_door_locked", false))
	print("  lock_reason     = ", door.get_meta("lock_reason", "<无>"))


func _report(label: String, ok: bool) -> void:
	if ok:
		print("  [OK]   ", label)
	else:
		print("  [FAIL] ", label)
		_failures.append(label)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("RESULT: PASS —— 西侧楼梯门两端均已钉死为不可开启")
		get_tree().quit(0)
		return
	print("RESULT: FAIL —— ", _failures.size(), " 项未通过")
	for item in _failures:
		print("  - ", item)
	get_tree().quit(1)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
