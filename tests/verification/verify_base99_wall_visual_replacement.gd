extends Node
## 基地99/100层九件Blender模块正式接入：验证99层普通墙圈、100层中庭、
## 可编辑楼板/楼梯、可行走坡面，以及原有门功能没有被表现替换破坏。

const WALL_SCENE: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_plain_5x9/env_base99_wall_plain_5x9_root_top3d_v001.tscn"
)


func _ready() -> void:
	var failures: Array[String] = []
	_validate_standalone_wall(failures)
	await _validate_facility_shell(failures)
	if failures.is_empty():
		print("BASE99_MODULAR_ASSET_INTEGRATION_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BASE99_MODULAR_ASSET_INTEGRATION_FAIL: %s" % " | ".join(failures))
	get_tree().quit(1)


func _validate_standalone_wall(failures: Array[String]) -> void:
	var wall := WALL_SCENE.instantiate()
	add_child(wall)
	var meshes := wall.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		failures.append("普通墙PackedScene不是单一整合视觉网格")
	else:
		var mesh_instance := meshes[0] as MeshInstance3D
		var bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if not bounds.size.is_equal_approx(Vector3(5.0, 8.9, 0.36)):
			failures.append("普通墙视觉包围盒不是5×8.9×0.36m: %s" % bounds.size)
		if not is_equal_approx(bounds.position.y, 0.0):
			failures.append("普通墙底部原点没有落在y=0: %s" % bounds.position.y)
		if mesh_instance.mesh.get_surface_count() != 2:
			failures.append("普通墙没有保留两种PaletteUV材质表面")
	if not wall.find_children("*", "CollisionObject3D", true, false).is_empty():
		failures.append("普通墙视觉PackedScene意外携带玩法碰撞")
	if not bool(wall.get_meta("visual_only", false)):
		failures.append("普通墙PackedScene缺少visual_only契约")
	wall.queue_free()


func _validate_facility_shell(failures: Array[String]) -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		failures.append("未生成99层基地房间")
	else:
		var snapshot := facility.get_room_snapshot()
		if int(snapshot.get("base99_floor_plain_instance_count", 0)) != 18:
			failures.append("基地普通地板不是18个5m视觉实例")
		if int(snapshot.get("base99_floor_rivet_instance_count", 0)) != 18:
			failures.append("基地铆钉地板不是18个5m视觉实例")
		if int(snapshot.get("base99_wall_plain_instance_count", 0)) != 14:
			failures.append("99层外圈普通墙不是14个5m视觉实例")
		if int(snapshot.get("base99_wall_window_instance_count", -1)) != 0:
			failures.append("99层错误放入了100层专用窗墙")
		if int(snapshot.get("base99_wall_door_module_count", 0)) != 2:
			failures.append("基地带门墙不是2个独立模块")
		if int(snapshot.get("base100_upper_shell_count", 0)) != 1:
			failures.append("基地缺少独立可编辑的100层上层围护与封顶Prefab")
		if int(snapshot.get("base100_wall_plain_instance_count", 0)) != 19:
			failures.append("100层上层围护普通墙不是19块")
		if int(snapshot.get("base100_wall_window_instance_count", 0)) != 4:
			failures.append("100层北墙窗墙不是中间4块")
		if int(snapshot.get("base100_wall_door_instance_count", 0)) != 1:
			failures.append("100层东墙侧向门墙不是1块")
		if int(snapshot.get("base100_roof_tile_count", 0)) != 36:
			failures.append("18米封顶不是6×6共36块5米模块")
		if int(snapshot.get("base100_structure_collision_count", 0)) != 1:
			failures.append("100层上层围护没有独立连续结构碰撞")
		if int(snapshot.get("base99_door_lift_count", 0)) != 3:
			failures.append("基地两扇原有门与阁楼天台门没有全部使用正式滑升门视觉")
		var rooftop_door := facility.find_child("BaseRooftopTransitDoor", true, false) as RoomDoor3D
		if rooftop_door == null or str(rooftop_door.get_meta("door_role", "")) != "base_rooftop_transit":
			failures.append("100层东侧门洞没有组合既有Godot天台门")
		var base_door_bindings := tower.call("_get_configured_base_door_bindings") as Array
		if base_door_bindings.size() != 3:
			failures.append("基地三个门没有统一注册到同一交互分发器")
		if int(snapshot.get("base99_mezzanine_count", 0)) != 1:
			failures.append("基地缺少二层楼中楼楼板")
		if int(snapshot.get("base99_stair_l_count", 0)) != 1:
			failures.append("基地缺少L型楼梯")
		if int(snapshot.get("base99_stair_exterior_count", 0)) != 1:
			failures.append("基地缺少二楼外门小楼梯")
		if int(snapshot.get("base99_camera_stair_slab_count", 0)) < 3:
			failures.append("楼板/楼梯没有建立下方摄像机净空碰撞标记")
		if int(snapshot.get("tower_door_wall_module_count", 0)) != 2:
			failures.append("两个带门墙的模块数量被改变")
		if int(snapshot.get("tower_corner_module_count", 0)) != 4:
			failures.append("四个原有L型墙角被改变")
		if (snapshot.get("door_snapshots", []) as Array).size() != 2:
			failures.append("基地两个门的运行时快照数量被改变")
		_validate_base_scene_shadow_policy(facility, failures)
		_validate_base100_upper_shell(facility, failures)
		_validate_editable_component_layout(facility, failures)
		_validate_base99_camera_collisions(facility, failures)
		_validate_walkable_ramp_angles(facility, failures)
		_validate_base_atrium(tower, failures)
		await _validate_l_stair_climb(tower, facility, failures)
		await _validate_exterior_stair_climb(tower, facility, failures)
		await _validate_base99_door_contract(facility, failures)
		await _validate_base99_camera_clearance(tower, facility, failures)
	tower.queue_free()
	await get_tree().process_frame


func _validate_base_scene_shadow_policy(root: Node, failures: Array[String]) -> void:
	var base_asset_roots: Array[Node] = []
	_collect_base_asset_roots(root, base_asset_roots)
	for asset_root in base_asset_roots:
		for geometry_value in asset_root.find_children("*", "GeometryInstance3D", true, false):
			var geometry := geometry_value as GeometryInstance3D
			if geometry is Label3D:
				continue
			if geometry != null and geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				failures.append("基地场景组件没有产生投影: %s/%s" % [asset_root.name, geometry.name])
	for facility_value in root.find_children("*", "BaseFacility3D", true, false):
		var facility_component := facility_value as BaseFacility3D
		for mesh_value in facility_component.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_value as MeshInstance3D
			if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				failures.append("基地设施组件模型没有产生投影: %s/%s" % [facility_component.name, mesh.name])


func _collect_base_asset_roots(root: Node, result: Array[Node]) -> void:
	var asset_id := str(root.get_meta("asset_id", root.get_meta("visual_asset_id", "")))
	if asset_id.begins_with("ENV-BASE99-"):
		result.append(root)
		return
	for child in root.get_children():
		_collect_base_asset_roots(child, result)


func _validate_base100_upper_shell(facility: DungeonRoom3D, failures: Array[String]) -> void:
	var shell := facility.get_node_or_null(
		"基地99层_美术布置层/基地结构组件_可移动旋转/100层上层围护与18米封顶"
	) as Node3D
	if shell == null:
		failures.append("可编辑布局tscn缺少100层上层围护与18米封顶")
		return
	var wall_group := shell.get_node_or_null("100层围护墙_可移动旋转")
	var roof_group := shell.get_node_or_null("18米封顶_6x6地砖")
	if wall_group == null or wall_group.get_child_count() != 24:
		failures.append("100层围护墙不是24块独立可编辑模块")
	if roof_group == null or roof_group.get_child_count() != 36:
		failures.append("封顶不是36块独立可编辑地板模块")
	if wall_group != null:
		var north_windows := 0
		for child in wall_group.get_children():
			if str(child.name).begins_with("北墙_") and str(child.name).contains("窗墙"):
				north_windows += 1
				if not is_equal_approx((child as Node3D).position.z, -15.0):
					failures.append("100层窗墙没有位于北侧z=-15")
		if north_windows != 4:
			failures.append("100层北侧窗墙节点数量不是4")
	var collision_body := shell.get_node_or_null("UpperShellStructureCollision") as StaticBody3D
	if collision_body == null:
		failures.append("100层围护/屋顶结构碰撞体缺失")
	else:
		var shapes := collision_body.find_children("*", "CollisionShape3D", true, false)
		if shapes.size() != 9:
			failures.append("100层围护/屋顶结构碰撞片数量不是9: %d" % shapes.size())
		var roof_collision_count := 0
		for shape_value in shapes:
			var shape := shape_value as CollisionShape3D
			if str(shape.get_meta("base100_structure_role", "")) == "roof":
				roof_collision_count += 1
		if roof_collision_count != 1:
			failures.append("18米封顶没有唯一屋顶碰撞")
	for mesh_value in shell.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_value as MeshInstance3D
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("100层围护或封顶没有产生投影: %s" % mesh.name)


func _validate_base99_camera_collisions(root: Node, failures: Array[String]) -> void:
	var roles: Dictionary = {}
	for body_value in root.find_children("*", "StaticBody3D", true, false):
		var body := body_value as StaticBody3D
		if body == null or not bool(body.get_meta("camera_stair_slab", false)):
			continue
		roles[str(body.get_meta("camera_stair_slab_role", ""))] = true
		var shapes := body.find_children("*", "CollisionShape3D", true, false)
		if shapes.is_empty() or (shapes[0] as CollisionShape3D).disabled:
			failures.append("摄像机净空碰撞未启用: %s" % body.name)
		if str(body.get_meta("camera_stair_slab_role", "")) == "l_stair_unified" and shapes.size() != 3:
			failures.append("L型楼梯统一摄像机净空体不是三个连续形状")
	for required_role in ["mezzanine", "l_stair_unified", "exterior_stair"]:
		if not roles.has(required_role):
			failures.append("缺少摄像机净空角色: %s" % required_role)


func _validate_editable_component_layout(facility: DungeonRoom3D, failures: Array[String]) -> void:
	var layout := facility.get_node_or_null("基地99层_美术布置层/基地结构组件_可移动旋转") as Node3D
	if layout == null:
		failures.append("基地结构组件没有进入可编辑美术布局tscn")
		return
	var expected := {
		"二层楼中楼楼板_20x10米_Z5": Vector3(5.0, 0.0, -10.0),
		"L型楼梯_一楼至二楼_Z5": Vector3(-9.58, 0.0, -9.15),
		"外门小楼梯_二楼至100层_H4": Vector3(10.78, 5.0, -7.5),
	}
	for node_name in expected:
		var component := layout.get_node_or_null(node_name) as Node3D
		if component == null:
			failures.append("可编辑布局缺少结构组件: %s" % node_name)
		elif not component.position.is_equal_approx(expected[node_name] as Vector3):
			failures.append("结构组件没有采用Blender母版初始坐标: %s=%s" % [node_name, component.position])


func _validate_walkable_ramp_angles(root: Node, failures: Array[String]) -> void:
	var ramp_count := 0
	for shape_value in root.find_children("*RampShape", "CollisionShape3D", true, false):
		var collision := shape_value as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		ramp_count += 1
		var surface_up := collision.basis.y.normalized()
		var angle := acos(clampf(surface_up.dot(Vector3.UP), -1.0, 1.0))
		if angle >= deg_to_rad(44.0):
			failures.append("楼梯坡面超过角色44度可行走上限: %s %.2f度" % [collision.name, rad_to_deg(angle)])
	if ramp_count != 3:
		failures.append("基地两套楼梯应有3段简化可行走坡面，当前%d段" % ramp_count)


func _validate_base_atrium(tower: TowerDescent3D, failures: Array[String]) -> void:
	var stages := tower.get_tower_snapshot().get("floor_stages", []) as Array
	for stage_value in stages:
		var stage := stage_value as Dictionary
		if int(stage.get("floor_index", -1)) != 0:
			continue
		if (
			not bool(stage.get("base_99_100_atrium_enabled", false))
			or int(stage.get("base_99_100_atrium_tile_count", 0)) != 36
			or int(stage.get("tile_count", 0)) != 208
		):
			failures.append("100层与99层之间没有正确移除36块地砖/承重碰撞: %s" % stage)
		return
	failures.append("没有找到100层floor_index=0楼板")


func _validate_l_stair_climb(tower: TowerDescent3D, facility: DungeonRoom3D, failures: Array[String]) -> void:
	tower.force_enter_room_for_test("facility")
	tower.player.set_input_locked(false)
	tower.player.velocity = Vector3.ZERO
	var waypoints := [
		Vector3(-12.48, 0.10, -3.75),
		Vector3(-12.48, 2.48, -10.50),
		Vector3(-12.48, 2.52, -12.55),
		Vector3(-11.76, 2.52, -12.87),
		Vector3(-5.03, 5.04, -12.87),
		Vector3(-4.20, 5.06, -12.50),
	]
	tower.player.global_position = facility.to_global(waypoints[0])
	await get_tree().physics_frame
	for index in range(1, waypoints.size()):
		if not await _walk_player_to(tower.player, facility.to_global(waypoints[index] as Vector3)):
			failures.append("角色无法沿简化碰撞走上L型楼梯，停在路径点%d: %s" % [index, tower.player.global_position])
			break
	tower.player.set_test_move_direction(Vector3.ZERO)


func _walk_player_to(player: Player3D, target: Vector3) -> bool:
	var previous_planar_distance := INF
	var stalled_frames := 0
	for _frame in range(360):
		var offset := target - player.global_position
		var planar := Vector3(offset.x, 0.0, offset.z)
		if planar.length() <= 0.48 and absf(offset.y) <= 0.75:
			player.set_test_move_direction(Vector3.ZERO)
			await get_tree().physics_frame
			return true
		player.set_test_move_direction(planar.normalized())
		await get_tree().physics_frame
		var next_distance := Vector3(target.x - player.global_position.x, 0.0, target.z - player.global_position.z).length()
		if next_distance < previous_planar_distance - 0.006:
			stalled_frames = 0
		else:
			stalled_frames += 1
		previous_planar_distance = next_distance
		if stalled_frames >= 80:
			player.set_test_move_direction(Vector3.ZERO)
			return false
	player.set_test_move_direction(Vector3.ZERO)
	return false


func _validate_exterior_stair_climb(tower: TowerDescent3D, facility: DungeonRoom3D, failures: Array[String]) -> void:
	tower.player.velocity = Vector3.ZERO
	tower.player.global_position = facility.to_global(Vector3(6.64, 5.08, -7.5))
	await get_tree().physics_frame
	if not await _walk_player_to(tower.player, facility.to_global(Vector3(14.85, 8.98, -7.5))):
		failures.append("角色无法从5米楼板沿外门小楼梯走向9米门槛: %s" % tower.player.global_position)
	tower.player.set_test_move_direction(Vector3.ZERO)


func _validate_base99_door_contract(
	facility: DungeonRoom3D,
	failures: Array[String]
) -> void:
	var doors := facility.find_children("Door_*", "RoomDoor3D", true, false)
	if doors.size() != 2:
		failures.append("基地滑升门实例不是2个")
		return
	for door_value in doors:
		var door := door_value as RoomDoor3D
		var panel := door.get_node_or_null("DoorPanel") as Node3D
		door.set_open(true, true)
		await get_tree().physics_frame
		var opened := door.get_snapshot()
		if (
			not bool(opened.get("is_open", false))
			or bool(opened.get("blocks_passage", true))
			or panel == null
			or panel.position.y < 4.0
		):
			failures.append("替换门模型后，原滑升动画或通行碰撞失效: %s" % opened)
		door.set_open(false, true)
		await get_tree().physics_frame
		var closed := door.get_snapshot()
		if (
			bool(closed.get("is_open", true))
			or not bool(closed.get("blocks_passage", false))
			or panel == null
			or not is_equal_approx(panel.position.y, 1.25)
		):
			failures.append("替换门模型后，原关门阻挡或位置失效: %s" % closed)


func _validate_base99_camera_clearance(
	tower: TowerDescent3D,
	facility: DungeonRoom3D,
	failures: Array[String]
) -> void:
	tower.force_enter_room_for_test("facility")
	tower.player.velocity = Vector3.ZERO
	# 镜头位于角色身后约2.77m；此点让三根垂直探针都落在5m楼板下。
	tower.player.global_position = facility.to_global(Vector3(0.0, 0.08, -10.0))
	for _frame in range(8):
		await get_tree().physics_frame
	var blocked := tower.get_tower_snapshot()
	if (
		not bool(blocked.get("camera_stair_slab_detected", false))
		or float(blocked.get("camera_stair_slab_drop_current_m", 0.0)) < 0.5
		or tower.player.camera.position.y >= 5.0
	):
		failures.append("角色位于基地楼板下方时，摄像机没有按99→98层规则降低: %s" % blocked)

	# 离开楼板覆盖区后只能平滑恢复，不得永久保持压低状态。
	tower.player.global_position = facility.to_global(Vector3(-10.0, 0.08, 10.0))
	for _frame in range(90):
		await get_tree().physics_frame
	var recovered := tower.get_tower_snapshot()
	if (
		bool(recovered.get("camera_stair_slab_detected", true))
		or float(recovered.get("camera_stair_slab_drop_current_m", 1.0)) > 0.02
	):
		failures.append("角色离开基地低楼板后，摄像机没有恢复默认高度: %s" % recovered)
