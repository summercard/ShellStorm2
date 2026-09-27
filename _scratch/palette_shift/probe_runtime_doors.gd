extends Node
## 读取**运行时实际门位**并落盘：证明逐房间清单里的门位口径与实跑一致（不靠静态推导）。
##
## 输出：I:/ss2_iso/room_type_after_import/runtime_doors.txt
##       每行 `room_id side -> target_room_id local=Vector3 world=Vector3`

const OUT := "I:/ss2_iso/room_type_after_import/runtime_doors.txt"
const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const LEVEL_ID := "expedition_01"
const RUN_SEED := 77001199
const TARGETS := ["room_03", "room_05", "room_09", "boss"]

var _report: FileAccess


func _ready() -> void:
	_report = FileAccess.open(OUT, FileAccess.WRITE)
	_emit("LEVEL=%s SEED=%d" % [LEVEL_ID, RUN_SEED])

	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	if tower == null:
		_emit("!! 无法实例化 ExpeditionLevel01_3D")
		_finish(2)
		return
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame

	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		_emit("!! 未生成 Blocks/Expedition")
		_finish(2)
		return

	var problems := 0
	for room_id in TARGETS:
		var room := block.get_node_or_null(room_id) as DungeonRoom3D
		if room == null:
			_emit("!! 未生成房间 %s" % room_id)
			problems += 1
			continue
		room.ensure_shell_built()
		var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		var origin := art_root.global_transform if art_root != null else room.global_transform
		_emit("ROOM %s center=%s doors=%s" % [
			room_id, str(room.global_position.snappedf(0.001)), str(room.doors),
		])
		if room.doors.size() != 2:
			_emit("   !! 门数应为 2，实得 %d" % room.doors.size())
			problems += 1
		for side in room.doors:
			var door := room.get_door_node(str(side))
			if door == null:
				_emit("   !! %s 缺门节点" % side)
				problems += 1
				continue
			var local := origin.affine_inverse() * door.global_position
			_emit("   %-5s -> %-12s local=(%.3f, %.3f, %.3f) world=(%.3f, %.3f, %.3f)" % [
				side, door.target_room_id,
				local.x, local.y, local.z,
				door.global_position.x, door.global_position.y, door.global_position.z,
			])

	remove_child(tower)
	tower.free()
	if problems == 0:
		_emit("RUNTIME_DOORS_OK")
		_finish(0)
	else:
		_emit("RUNTIME_DOORS_FAIL problems=%d" % problems)
		_finish(1)


func _emit(line: String) -> void:
	print(line)
	if _report != null:
		_report.store_line(line)


func _finish(code: int) -> void:
	if _report != null:
		_report.close()
	get_tree().quit(code)
