extends Node
## 只读探针：**真实远征01** 入口安全房（start）的 EXIT 霓虹灯标牌。
##
## 背景：远征01 入口房走**静态布局 TSCN**（`f00_start_static_layout.tscn`），
## `_build_shell()` 在该分支提前 return、不经过 `_build_safe_room_shell()`
## ⇒ 标牌必须由静态分支单独补一次。本探针就验这件事在真实关卡里成立。
##
## 手跑（headless 即可）：
##   godot --headless --path . --scene res://tests/verification/probe_expedition_start_exit_sign.tscn

const DEFAULT_EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const EXPEDITION_02_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
const RUN_SEED := 77001199
const SIGN_NODE_NAME := "SafeRoomExitSign"
const EXPECTED_ASSET_ID := "ENV-BATTLE-EXIT-NEON-SIGN"
const EXPECTED_STAIR_ASSET_ID := "ENV-BASE99-STAIR-EXTERIOR-H4"

var expedition_scene := DEFAULT_EXPEDITION_SCENE
var failures: Array[String] = []


func _read_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var value := str(raw)
		if value == EXPEDITION_02_SCENE:
			expedition_scene = value


func _ready() -> void:
	_read_args()
	var is_expedition_02 := expedition_scene == EXPEDITION_02_SCENE
	print("=== 探针：%s 入口安全房 EXIT 标牌（静态布局路径）===" % (
		"远征02 + H4楼梯" if is_expedition_02 else "远征01"
	))
	var scene := load(expedition_scene) as PackedScene
	if scene == null:
		failures.append("入口远征场景加载失败：%s" % expedition_scene)
		_finish(null)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		failures.append("入口远征场景实例化失败：%s" % expedition_scene)
		_finish(null)
		return
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		failures.append("远征01 缺少入口房 start")
		_finish(tower)
		return

	print("room_id=%s  room_type=%s" % [start_room.room_id, start_room.room_type])
	print("doors=%s  door_targets=%s" % [str(start_room.doors), str(start_room.door_targets)])
	print("static_layout_scene_path=%s" % start_room.static_layout_scene_path)
	print("static_layout_scene_loaded=%s" % str(start_room.get_meta("static_layout_scene_loaded", false)))

	# 本房确实是静态布局路径（否则本探针没验到该验的东西）
	if str(start_room.static_layout_scene_path).is_empty():
		failures.append("入口房未走静态布局路径，本探针失去意义")
	var retreat_direction := str(start_room.call("_safe_room_retreat_direction"))
	print("retreat_direction=%s" % retreat_direction)
	if retreat_direction.is_empty():
		failures.append("入口房找不到退出门（door_targets 无空目标侧）")

	# 幂等：恰好一块
	var signs: Array[Node] = []
	for child in start_room.get_children():
		if child.name == SIGN_NODE_NAME:
			signs.append(child)
	print("SafeRoomExitSign 节点数=%d" % signs.size())
	if signs.size() != 1:
		failures.append("EXIT 标牌节点数应为 1，实得 %d" % signs.size())
		_finish(tower)
		return
	var sign_node := signs[0] as Node3D

	if str(sign_node.get_meta("exit_sign_asset_id", "")) != EXPECTED_ASSET_ID:
		failures.append("标牌 asset_id 不符：%s" % sign_node.get_meta("exit_sign_asset_id", ""))
	if str(sign_node.get_meta("exit_sign_direction", "")) != retreat_direction:
		failures.append("标牌方位(%s) 与退出门(%s) 不一致" % [
			sign_node.get_meta("exit_sign_direction", ""), retreat_direction,
		])
	if not bool(sign_node.get_meta("visual_only", false)):
		failures.append("标牌未声明 visual_only")
	if not sign_node.find_children("*", "StaticBody3D", true, false).is_empty():
		failures.append("标牌带 StaticBody3D（会在走行面制造隐形台阶）")

	# 世界几何：贴地 + 发光面朝上 + 长边平行门洞 + 落在门内侧
	var xform := sign_node.global_transform
	var mn := Vector3.INF
	var mx := -Vector3.INF
	var mesh_count := 0
	for value in sign_node.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mesh_count += 1
		var bb := mi.mesh.get_aabb()
		for i in range(8):
			var world: Vector3 = xform * bb.get_endpoint(i)
			mn = mn.min(world)
			mx = mx.max(world)
	if mesh_count == 0:
		failures.append("标牌内没有网格")
		_finish(tower)
		return
	var size := mx - mn
	var facing := -(xform.basis.z).normalized()
	print("世界 AABB min=%s max=%s size=%s" % [_v(mn), _v(mx), _v(size)])
	print("facing = %s" % _v(facing))

	if absf(facing.y - 1.0) > 0.02:
		failures.append("发光面未朝上：%s" % _v(facing))
	# 房间局部坐标 = 房间世界坐标 − 房间原点（探针里 tower 在原点）
	var room_origin := start_room.global_position
	var expected_walk_surface_y := float(start_room.get_meta("walk_surface_y_m", 0.0))
	var half := minf(start_room.get_dimensions().x, start_room.get_dimensions().y) * 0.5
	var local_min := mn - room_origin
	var local_max := mx - room_origin
	print("房间局部 AABB x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]  半边长=%.2f" % [
		local_min.x, local_max.x, local_min.y, local_max.y, local_min.z, local_max.z, half,
	])
	if absf((mn.y - room_origin.y) - expected_walk_surface_y) > 0.02:
		failures.append("牌背面未贴走行面：底面 y=%.4f，预期 %.4f" % [
			mn.y - room_origin.y, expected_walk_surface_y
		])
	# 牌必须整体落在房间内（不穿墙）
	if local_min.x < -half or local_max.x > half or local_min.z < -half or local_max.z > half:
		failures.append("标牌超出房间边界，可能穿墙：%s ~ %s" % [_v(local_min), _v(local_max)])
	# 长边必须平行退出门洞。east/west 门法向沿 X ⇒ 法向占地 = x 向尺寸；
	# north/south 门法向沿 Z ⇒ 法向占地 = z 向尺寸。
	var normal := start_room.call("_direction_normal", retreat_direction) as Vector3
	var normal_along_x := absf(normal.x) > 0.99
	var depth_extent := size.x if normal_along_x else size.z
	var width_extent := size.z if normal_along_x else size.x
	print("门法向=%s  沿门法向占地=%.3f（应 0.76）  平行门洞长边=%.3f（应 1.84）" % [
		_v(normal), depth_extent, width_extent,
	])
	if absf(depth_extent - 0.76) > 0.03:
		failures.append("沿门法向占地 %.3f 不符 0.76" % depth_extent)
	if absf(width_extent - 1.84) > 0.03:
		failures.append("平行门洞长边 %.3f 不符 1.84" % width_extent)

	# 硬断言：标牌的**切向中心**必须对齐退出门扇的实际世界位置切向坐标。
	# 静态布局的门墙会被 `_rehome_static_layout_door` 搬回本局自持侧 ⇒ 门可能挪动；
	# 标牌若按「烘焙方位」而非本局门位摆放，就会与门错开。这条能抓住那种错位。
	var door_node := start_room.get_door_node(retreat_direction)
	if door_node == null:
		failures.append("找不到退出门扇节点：%s" % retreat_direction)
	else:
		var door_world := door_node.global_position
		var door_local := door_world - room_origin
		var sign_center_local := (local_min + local_max) * 0.5
		var tangential_sign := sign_center_local.z if normal_along_x else sign_center_local.x
		var tangential_door := door_local.z if normal_along_x else door_local.x
		print("切向：标牌中心=%.3f  门扇=%.3f（差 %.3f）" % [
			tangential_sign, tangential_door, absf(tangential_sign - tangential_door),
		])
		if absf(tangential_sign - tangential_door) > 0.35:
			failures.append("标牌切向中心与门扇错开 %.3f m（>0.35）" % absf(
				tangential_sign - tangential_door
			))
		# 牌必须落在门内侧（比门更靠房内），不能跑到门外
		var radial_sign := sign_center_local.x if normal_along_x else sign_center_local.z
		var radial_door := door_local.x if normal_along_x else door_local.z
		print("径向：门扇=%.3f  标牌中心=%.3f（应更靠房内）" % [radial_door, radial_sign])
		if float(radial_sign) * float(normal.x + normal.z) >= float(radial_door) * float(normal.x + normal.z):
			failures.append("标牌未落在门内侧：门径向=%.3f 牌径向=%.3f" % [radial_door, radial_sign])

	if is_expedition_02:
		await _verify_expedition_02_stair_exit(tower, start_room, retreat_direction)

	_finish(tower)


func _verify_expedition_02_stair_exit(
	tower: TowerDescent3D,
	start_room: DungeonRoom3D,
	retreat_direction: String
) -> void:
	var stair: Node3D = null
	for value in start_room.find_children("*", "Node3D", true, false):
		var candidate := value as Node3D
		if candidate != null and str(candidate.get_meta("asset_id", "")) == EXPECTED_STAIR_ASSET_ID:
			stair = candidate
			break
	if stair == null:
		failures.append("远征02 start 缺少 H4 外部退出楼梯")
		return
	if not bool(stair.get_meta("walkable", false)):
		failures.append("H4 外部退出楼梯未声明 walkable=true")
	if str(stair.get_meta("exit_port", "")) != "east_retreat":
		failures.append("H4 楼梯 exit_port 不是 east_retreat：%s" % stair.get_meta("exit_port", ""))
	var stair_bodies := stair.find_children("*", "StaticBody3D", true, false)
	var stair_shapes := stair.find_children("*", "CollisionShape3D", true, false)
	if stair_bodies.is_empty() or stair_shapes.is_empty():
		failures.append("H4 外部退出楼梯缺少真实碰撞：bodies=%d shapes=%d" % [
			stair_bodies.size(), stair_shapes.size()
		])
	else:
		var enabled_shapes := 0
		for shape_value in stair_shapes:
			var shape := shape_value as CollisionShape3D
			if shape != null and not shape.disabled and shape.shape != null:
				enabled_shapes += 1
		if enabled_shapes == 0:
			failures.append("H4 外部退出楼梯碰撞形状全部禁用或为空")

	var exit_door := start_room.get_door_node(retreat_direction)
	if exit_door == null:
		failures.append("远征02 无法用退出门校验楼梯低端")
	else:
		# H4 prefab 的 root contract 是 center_bottom；实测本地 -X 端为低端，
		# 不依赖静态布局根的 metadata 复制，直接从真实实例反算世界端点。
		var low_endpoint := stair.to_global(Vector3(-4.22, -0.04, 0.0))
		var high_endpoint := stair.to_global(Vector3(4.22, 4.0, 0.0))
		var door_planar := Vector2(exit_door.global_position.x, exit_door.global_position.z)
		var low_planar := Vector2(low_endpoint.x, low_endpoint.z)
		if low_planar.distance_to(door_planar) > 0.75:
			failures.append("楼梯低端未与退出门同位：low=%s door=%s" % [
				str(low_endpoint), str(exit_door.global_position)
			])
		if high_endpoint.y <= low_endpoint.y + 2.0:
			failures.append("H4 楼梯没有向上爬升到约4m：low=%s high=%s" % [
				str(low_endpoint), str(high_endpoint)
			])

	# 真实退出交互候选必须仍然来自这扇门，而不是只存在视觉楼梯。
	if exit_door != null:
		var player := tower.player
		player.global_position = exit_door.global_position + Vector3(0.0, 0.05, 0.0)
		await get_tree().physics_frame
		var candidate := tower.get_interaction_candidate(player)
		if str(candidate.get("mode", "")) != "configured_expedition_retreat":
			failures.append("远征02楼梯出口未绑定 expedition_retreat：%s" % candidate)


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _finish(tower: Node) -> void:
	if tower != null:
		tower.queue_free()
	if failures.is_empty():
		print("PROBE_EXPEDITION_START_EXIT_SIGN_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("PROBE_FAIL %s" % failure)
		print("PROBE_EXPEDITION_START_EXIT_SIGN_FAIL count=%d" % failures.size())
		get_tree().quit(1)
