extends Node
## 临时诊断（不进验收注册表）：切开「设备缺陷」与「探针站位算法缺陷」。
##
## 对 start / boss 两房，把「探针现有站位算法」与「几种更鲁棒的站位算法」并列实测：
##   · cells    = room._authored_tile_cells.size()（探针站位依赖它）
##   · switch 的 局部 / 世界 坐标，room / art_root 的世界变换（查坐标口径）
##   · 候选 A = 探针原算法：_tile_stand(switch, cells) 再 room.to_global(...)
##   · 候选 B = 世界直算：switch.global_position + 朝房心方向 × 0.9
##   · 候选 C = 世界直算 × 1.2
##   · 候选 D = 世界直算 × 0.6
## 每个候选点都真放玩家、刷新归属、读交互候选 —— 谁非空谁就说明「开关可达」。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199
const TILE_STAND_HALF_M := 2.47
const TARGETS: Array[String] = ["start", "boss", "room_01"]
const STATIC_ROOT_NAMES: Array[String] = ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		print("DIAG_FATAL 没有 Blocks/Expedition")
		get_tree().quit(1)
		return
	for room_id in TARGETS:
		var room := block.get_node_or_null(room_id) as DungeonRoom3D
		if room == null:
			print("DIAG_FATAL 缺少房间 %s" % room_id)
			continue
		await _diag_room(tower, room)
	get_tree().quit(0)


func _diag_room(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle()
	var cells: Array = room.get("_authored_tile_cells") as Array
	var sw := room.get("_light_switch") as RoomLightSwitch3D
	var art := _static_root(room) as Node3D
	if sw == null:
		print("DIAG room=%s 没有开关" % room.room_id)
		return
	print("DIAG room=%s cells=%d dims=%s" % [
		room.room_id, cells.size(), str(room.call("get_dimensions")),
	])
	print("DIAG room=%s room_global_origin=%s" % [
		room.room_id, var_to_str(room.global_position),
	])
	print("DIAG room=%s art_local_tf=%s art_global_origin=%s" % [
		room.room_id,
		var_to_str(art.transform) if art != null else "<none>",
		var_to_str(art.global_position) if art != null else "<none>",
	])
	print("DIAG room=%s switch_local=%s switch_global=%s" % [
		room.room_id, var_to_str(sw.position), var_to_str(sw.global_position),
	])
	var center := room.global_position
	var flat := Vector3(center.x - sw.global_position.x, 0.0, center.z - sw.global_position.z)
	var inward := flat.normalized() if flat.length() > 1e-4 else Vector3.FORWARD
	print("DIAG room=%s inward=%s" % [room.room_id, var_to_str(inward)])

	# A：探针原算法（tile cell clamp → room.to_global）
	var tile_point := _tile_stand(sw, cells)
	var cand_a: Vector3 = room.to_global(tile_point)
	await _try_stand(tower, room, sw, "A_tile_room_to_global", cand_a)
	# A2：同一局部点，但用 art_root 换算（查坐标口径）
	if art != null:
		await _try_stand(tower, room, sw, "A2_tile_art_to_global", art.to_global(tile_point))
	# B/C/D：世界直算
	for spec in [["B_0.9m", 0.9], ["C_1.2m", 1.2], ["D_0.6m", 0.6]]:
		var point: Vector3 = sw.global_position + inward * float(spec[1])
		point.y = center.y + 0.05
		await _try_stand(tower, room, sw, str(spec[0]), point)


func _try_stand(
	tower: TowerDescent3D, room: DungeonRoom3D, sw: RoomLightSwitch3D,
	label: String, point: Vector3,
) -> void:
	var player := tower.player
	if player == null:
		print("DIAG room=%s %s 无玩家" % [room.room_id, label])
		return
	player.global_position = point
	await _settle()
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var candidate: Dictionary = sw.get_interaction_candidate(player as Player3D)
	var dist := Vector2(point.x - sw.global_position.x, point.z - sw.global_position.z).length()
	print("DIAG room=%s %-20s point=%s dist=%.3f owner=%s candidate=%s" % [
		room.room_id, label, var_to_str(point), dist,
		str(tower.get("_current_room_id")), "YES" if not candidate.is_empty() else "no",
	])


func _tile_stand(switch: RoomLightSwitch3D, cells: Array) -> Vector3:
	var best := INF
	var best_point := switch.position
	for value in cells:
		var cell := value as Vector3
		var point := Vector3(
			clampf(switch.position.x, cell.x - TILE_STAND_HALF_M, cell.x + TILE_STAND_HALF_M),
			0.0,
			clampf(switch.position.z, cell.z - TILE_STAND_HALF_M, cell.z + TILE_STAND_HALF_M),
		)
		var distance := Vector2(point.x - switch.position.x, point.z - switch.position.z).length()
		if distance < best:
			best = distance
			best_point = point
	if best == INF:
		var inward := Vector3(-switch.position.x, 0.0, -switch.position.z)
		return switch.position + (inward.normalized() * 0.8 if inward.length() > 1e-4 else Vector3.ZERO)
	return best_point


func _static_root(room: DungeonRoom3D) -> Node:
	for name in STATIC_ROOT_NAMES:
		var found := room.get_node_or_null(name)
		if found != null:
			return found
	return null


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
