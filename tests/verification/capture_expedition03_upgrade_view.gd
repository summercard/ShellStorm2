extends Node
## 实拍 + 测量：把玩家真正传送进 UPGRADE 房间，用玩家自己的视野系统
## （`PlayerVision3D`）刷新目标显隐，再做胶囊站点扫描。
##
## godot --path . res://tests/verification/capture_expedition03_upgrade_view.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
const LEVEL_ID := "expedition_03"
const SEED := 163794671
const CELL := 0.5
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.7


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("需要真实渲染器")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		push_error("select_expedition_level 被拒绝")
		get_tree().quit(1)
		return
	var tower := (load(LEVEL_SCENE) as PackedScene).instantiate() as TowerDescent3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for step in range(120):
		await get_tree().process_frame
		if not (tower.get("_room_by_id") as Dictionary).is_empty():
			break
	await _settle()

	var rooms: Dictionary = tower.get("_room_by_id")
	var target: DungeonRoom3D = null
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		if room != null and room.room_type == "UPGRADE":
			target = room
			break
	if target == null:
		push_error("没有 UPGRADE 房间")
		get_tree().quit(1)
		return
	target.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	target.ensure_detail_built()
	target.set_room_light_on(true)
	await _settle()

	var out := ProjectSettings.globalize_path("res://outputs/expedition03_upgrade_view_20261030")
	DirAccess.make_dir_recursive_absolute(out)
	for value in tower.find_children("*", "CanvasLayer", true, false):
		(value as CanvasLayer).visible = false

	var center: Vector3 = target.global_position
	var dims: Vector2 = target.get_dimensions()
	print("UPVIEW room=%s dims=%s center=%s" % [target.room_id, str(dims), str(center)])

	# 把玩家传送进房间（这是关键：视野系统的显隐按玩家位置算）。
	var player := tower.get("player") as Player3D
	if player != null:
		player.global_position = center + Vector3(0, 0.1, 1.5)
		player.velocity = Vector3.ZERO
		await _settle()
		print("UPVIEW player=%s" % str(player.global_position))
	# 用独立相机拍（玩家的跟随相机在传送后尚未收敛，拍出来会卡在墙里）。
	var camera := Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 300.0
	add_child(camera)
	camera.make_current()
	var station_ref := _find_station(target)
	if station_ref != null:
		# 站在房间中部、正对改造台 —— 就是业主截图那个位置关系。
		camera.global_position = center + Vector3(0, 1.75, 2.5)
		camera.look_at(station_ref.global_position + Vector3(0, 0.7, 0), Vector3.UP)
	else:
		camera.global_position = center + Vector3(0, 1.75, dims.y * 0.12)
		camera.look_at(center + Vector3(0, 1.2, -dims.y * 0.5), Vector3.UP)

	# ① 玩家所在位置的第一视角（覆盖业主截图那一帧）
	await _shoot(out, "01_player_live_view")

	# ② 服务台显隐状态（此时玩家就在房间里）
	var station := station_ref
	if station != null:
		print("UPVIEW station_visible_in_tree=%s self_visible=%s" % [
			str(station.is_visible_in_tree()), str(station.visible)])
		for child in station.get_children():
			if child is MeshInstance3D:
				print("UPVIEW station_mesh %s visible_in_tree=%s" % [
					str(child.name), str((child as Node3D).is_visible_in_tree())])

	# ③ 对照实验：把服务台自身碰撞层清零后强制刷新视野，看它是否立刻变可见。
	#    若变可见 ⇒ 确认「遮挡射线被目标自己的碰撞盒挡住」是空阻挡的成因。
	var vision := player.get_node_or_null("PlayerVision3D") if player != null else null
	var station_body := station.get_node_or_null("StationBody") if station != null else null
	if vision != null and station_body != null:
		print("UPVIEW station_ray_visible_before=%s" % str(
			vision.call("is_position_visible", station.global_position + Vector3(0, 0.65, 0))))
		(station_body as StaticBody3D).collision_layer = 0
		vision.call("force_refresh")
		await _settle()
		print("UPVIEW station_ray_visible_after=%s self_visible=%s" % [
			str(vision.call("is_position_visible", station.global_position + Vector3(0, 0.65, 0))),
			str(station.visible)])
		(station_body as StaticBody3D).collision_layer = 1
		vision.call("force_refresh")
		await _settle()
		print("UPVIEW station_after_restore_visible=%s" % str(station.visible))

	# ④ 胶囊站点扫描（此时物理与视野都按真实运行状态）
	_scan_capsules(target, center, dims)

	# ④ 俯瞰
	camera.global_position = center + Vector3(dims.x * 0.3, dims.x * 0.85, dims.y * 0.3)
	camera.look_at(center, Vector3.UP)
	await _shoot(out, "02_topdown")

	print("UPVIEW_DIR ", out)
	print("UPVIEW_OK")
	get_tree().quit(0)


func _scan_capsules(room: Node3D, center: Vector3, dims: Vector2) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.collision_mask = 0xFFFFFFFF
	params.collide_with_areas = false
	var half_x := maxf(dims.x * 0.5 - 1.0, 0.0)
	var half_z := maxf(dims.y * 0.5 - 1.0, 0.0)
	var by_collider := {}
	var x := -half_x
	while x <= half_x:
		var z := -half_z
		while z <= half_z:
			var probe := center + Vector3(x, CAPSULE_HEIGHT * 0.5 + 0.05, z)
			params.transform = Transform3D(Basis(), probe)
			for hit in space.intersect_shape(params, 8):
				var collider := hit.get("collider") as Node
				if collider == null:
					continue
				# 只统计挡路的 StaticBody / CharacterBody
				if not (collider is StaticBody3D or collider is CharacterBody3D):
					continue
				var key := str(collider.get_path())
				by_collider[key] = int(by_collider.get(key, 0)) + 1
			z += CELL
		x += CELL
	print("UPSCAN colliders=%d" % by_collider.size())
	for key in by_collider.keys():
		var node := get_node_or_null(NodePath(str(key)))
		var visible_in_tree := str((node as Node3D).is_visible_in_tree()) if node is Node3D else "-"
		print("UPSCAN collider=%s cells=%d visible_in_tree=%s" % [
			str(key), int(by_collider[key]), visible_in_tree])


func _shoot(out_dir: String, shot_name: String) -> void:
	for step in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])


func _find_station(room: Node) -> Node3D:
	for child in room.find_children("*", "ServiceStation3D", true, false):
		return child as Node3D
	return null


func _settle() -> void:
	for step in range(5):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
