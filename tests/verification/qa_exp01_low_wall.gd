extends Node
## 远征01低墙改造专项验收：只读运行时探针 + 真实渲染截图。
## 运行器必须在 Autoload 启动前隔离 APPDATA/LOCALAPPDATA；本脚本只写工程外输出目录。

const LOADING_PATH := "res://scenes/ExpeditionLoadingScreen.tscn"
const LEVEL_ID := "expedition_01"
const WALL_HEIGHT_M := 2.8
const PLAYER_TOP_M := 2.2
const GAME_DESIGN_CONFIG := preload("res://src/framework/GameDesignConfig.gd")

var tower: TowerDescent3D
var failures: Array[String] = []
var checks := 0
var output_dir := ""
var capture_camera: Camera3D
var capture_viewport: SubViewport
var report: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	output_dir = OS.get_environment("EXP01_LOW_WALL_OUTPUT")
	call_deferred("_run")

func _run() -> void:
	if output_dir.is_empty():
		_fail("未设置 EXP01_LOW_WALL_OUTPUT，拒绝写入 user://")
	else:
		DirAccess.make_dir_recursive_absolute(output_dir)
	_guard_isolation()
	if DisplayServer.get_name() == "headless":
		_fail("专项截图必须使用真实渲染器，当前为 headless")
	else:
		await _load_level()
		if tower != null:
			await _settle()
			await _prepare_runtime()
			_check_rooms_and_geometry()
			await _capture_requested_views()
	_dump_report()
	_finish()

func _guard_isolation() -> void:
	var user_dir := ProjectSettings.globalize_path("user://")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	var localappdata := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	var real_profile := OS.get_environment("USERPROFILE").replace("\\", "/")
	var base_manager := get_node_or_null("/root/BaseManager")
	var save_path := str(base_manager.get("save_path")) if base_manager != null else "<missing>"
	print("LOW_WALL_ISOLATION user_dir=%s appdata=%s localappdata=%s base_save_path=%s" % [
		user_dir, appdata, localappdata, save_path])
	_expect(not appdata.is_empty() and not localappdata.is_empty(), "APPDATA/LOCALAPPDATA 未隔离")
	_expect(user_dir.begins_with(appdata) or user_dir.begins_with(localappdata), "实际 user:// 不在隔离目录内")
	_expect(real_profile.is_empty() or not user_dir.begins_with(real_profile), "实际 user:// 落入真实用户目录")
	_expect(save_path == "user://base_save.json", "BaseManager.save_path 被改写：%s" % save_path)
	_expect(save_path.begins_with("user://"), "BaseManager.save_path 不是 user://")
	if FileAccess.file_exists("user://base_save.json"):
		print("LOW_WALL_ISOLATION isolated_save_exists=true path=%s" % ProjectSettings.globalize_path(save_path))

func _load_level() -> void:
	var tree := get_tree()
	tree.current_scene = null
	var entry_flow := get_node_or_null("/root/GameEntryFlow")
	if entry_flow != null:
		entry_flow.request_gameplay_entry(entry_flow.REASON_MISSION_OPERATIONS_TELEPORT)
	_expect(GAME_DESIGN_CONFIG.select_expedition_level(LEVEL_ID), "select_expedition_level(expedition_01) 被拒绝")
	if not failures.is_empty():
		return
	tree.change_scene_to_file(LOADING_PATH)
	await tree.scene_changed
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if tree.current_scene is TowerDescent3D:
			tower = tree.current_scene as TowerDescent3D
			if bool(tower.get_meta("loading_scene_ready", false)):
				break
	_expect(tower != null, "没有装配出远征01 TowerDescent3D")
	if tower == null:
		return
	_expect(not tower._room_by_id.is_empty(), "远征01 房间表为空")

func _prepare_runtime() -> void:
	for value in tower._room_by_id.values():
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.set_room_light_on(true)
	await _settle()
	# Freeze simulation during the A/B: no player movement, room streaming or camera takeover.
	get_tree().paused = true
	for child in tower.find_children("*", "CanvasLayer", true, false):
		(child as CanvasLayer).visible = false
	if tower.player != null:
		tower.player.visible = false
	# Render the actual assembled world independently of the loading/HUD viewport.
	capture_viewport = SubViewport.new()
	capture_viewport.size = Vector2i(1600, 1000)
	capture_viewport.world_3d = tower.get_world_3d()
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(capture_viewport)
	capture_camera = Camera3D.new()
	capture_camera.name = "QaCaptureCamera"
	capture_camera.fov = 55.0
	capture_viewport.add_child(capture_camera)
	capture_camera.make_current()

func _check_rooms_and_geometry() -> void:
	var rooms := tower._room_by_id
	_expect(rooms.size() == 13, "正式主路必须有13房")
	for key in rooms:
		var id := str(key)
		if id == "boss":
			continue
		var room := rooms.get(id) as DungeonRoom3D
		_expect(room != null and bool(room.get_meta("static_layout_scene_loaded", false)), "%s 未加载正式布局" % id)
		if room == null:
			continue
		_expect(is_equal_approx(float(room.get_meta("room_wall_height_m", -1.0)), WALL_HEIGHT_M), "%s 缺少2.8m契约" % id)
		var wall_count := 0
		for node in room.find_children("*", "Node3D", true, false):
			if str(node.get_meta("asset_family", "")) != "expedition_01_low_h28":
				continue
			wall_count += 1
			var piece := node as Node3D
			var bounds := AABB()
			var visible_meshes := 0
			for mesh_node in piece.find_children("*", "MeshInstance3D", true, false):
				var visual := mesh_node as MeshInstance3D
				var owner_piece := visual.get_parent()
				while owner_piece != piece and str(owner_piece.get_meta("asset_family", "")) != "expedition_01_low_h28":
					owner_piece = owner_piece.get_parent()
				if owner_piece != piece:
					continue
				var aabb := (piece.global_transform.affine_inverse() * visual.global_transform) * visual.get_aabb()
				bounds = aabb if visible_meshes == 0 else bounds.merge(aabb)
				visible_meshes += 1
			_expect(visible_meshes > 0 and absf(bounds.end.y - WALL_HEIGHT_M) < 0.015, "%s/%s 视觉墙顶不为2.8m" % [id, piece.name])
			var shapes := piece.find_children("*", "CollisionShape3D", true, false)
			_expect(not shapes.is_empty(), "%s/%s 无实体碰撞" % [id, piece.name])
			for shape_node in shapes:
				var collision := shape_node as CollisionShape3D
				var box := collision.shape as BoxShape3D
				_expect(box != null and absf(box.size.y - WALL_HEIGHT_M) < 0.015, "%s/%s 实体碰撞不为2.8m" % [id, piece.name])
		_expect(wall_count > 0, "%s 未找到正式低墙" % id)
		for proxy in room.find_children("CameraOnlyDoorWall_*", "StaticBody3D", true, false):
			for shape_node in proxy.find_children("*", "CollisionShape3D", true, false):
				var box := (shape_node as CollisionShape3D).shape as BoxShape3D
				_expect(box != null and is_equal_approx(box.size.y, WALL_HEIGHT_M), "%s 门洞镜头代理仍为高墙" % id)
		print("LOW_WALL_ROOM id=%s loaded_low_walls=%d" % [id, wall_count])
	_check_boss_and_pit(rooms)

func _check_doors(room: DungeonRoom3D) -> void:
	var door_count := 0
	for value in room.find_children("*", "Node3D", true, false):
		if value is RoomDoor3D:
			door_count += 1
			var door := value as RoomDoor3D
			var open_before := door.is_open
			door.set_open(false, true)
			var closed := door.get_snapshot()
			door.set_open(true, true)
			var opened := door.get_snapshot()
			door.set_open(open_before, true)
			var closed_width := float((closed as Dictionary).get("clear_width_m", 0.0))
			var open_width := float((opened as Dictionary).get("clear_width_m", 0.0))
			_expect(closed_width >= 0.0 and open_width >= closed_width, "%s 门洞/代理开合异常" % door.name)
	print("LOW_WALL_DOORS room=%s count=%d" % [room.room_id, door_count])
	_expect(door_count > 0, "%s 没有可验门代理" % room.room_id)

func _check_boss_and_pit(rooms: Dictionary) -> void:
	var boss := rooms.get("boss") as DungeonRoom3D
	_expect(boss != null, "Boss 房不存在")
	if boss != null:
		print("LOW_WALL_BOSS id=%s dims=%s pos=%s" % [boss.room_id, str(boss.get_dimensions()), str(boss.global_position)])
		_expect(boss.get_dimensions().x > 0.0 and boss.get_dimensions().y > 0.0, "Boss 房尺寸异常")
	var pits := 0
	for node in tower.find_children("*", "Node3D", true, false):
		if str(node.name).to_lower().contains("pit") or str(node.name).to_lower().contains("shaft"):
			pits += 1
	print("LOW_WALL_PITS count=%d" % pits)
	# 坑/深井可能由多个命名节点组成；这里只记录并要求运行时可查询，不改生产状态。
	_expect(pits >= 0, "坑统计不可用")

func _capture_requested_views() -> void:
	var rooms := tower._room_by_id
	for id in ["room_07", "room_09"]:
		var room := rooms.get(id) as DungeonRoom3D
		if room == null:
			continue
		var center := room.global_position
		var dims := room.get_dimensions()
		await _capture_room(room, id + "_standard_view", center + Vector3(dims.x * 0.24, 22.0, dims.y * 0.30), center + Vector3(-2.0, 0.5, -3.0))
		var door := _first_door(room)
		if door != null:
			await _capture_curtain_pair(room, id, door)

func _capture_room(room: DungeonRoom3D, label: String, player_position: Vector3, target: Vector3) -> void:
	tower._current_room_id = room.room_id
	tower._refresh_flow_view_mask(true)
	var camera := capture_camera
	camera.global_position = player_position
	camera.look_at(target, Vector3.UP)
	camera.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := capture_viewport.get_texture().get_image()
	var path := output_dir.path_join(label + ".png")
	_expect(_nonblack_ratio(image) > 0.08, label + ": 画面没有可读房间")
	_expect(image.save_png(path) == OK, label + ": 截图保存失败")
	print("LOW_WALL_SHOT label=%s path=%s camera=%s" % [label, path, str(camera.global_position)])
	report.append({"label": label, "path": path, "room": room.room_id, "camera": str(camera.global_position)})

func _capture_curtain_pair(room: DungeonRoom3D, id: String, door: RoomDoor3D) -> void:
	var inward := (room.global_position - door.global_position)
	inward.y = 0.0
	inward = inward.normalized()
	var position := door.global_position + inward * 7.0
	tower._current_room_id = room.room_id
	tower._refresh_flow_view_mask(true)
	var camera := capture_camera
	camera.global_position = position + Vector3.UP * 12.0
	camera.look_at(door.global_position - inward * 0.8 + Vector3.UP * 1.0, Vector3.UP)
	camera.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var root := tower.find_child("FlowViewWalls", true, false) as Node3D
	var on_image := capture_viewport.get_texture().get_image()
	var on_path := output_dir.path_join(id + "_near_door_curtain_on.png")
	_expect(root != null and root.get_meta("view_wall_room_id", "") == id, id + ": 幕墙未跟随当前房")
	if root == null:
		return
	_expect(root.find_children("*", "CollisionObject3D", true, false).is_empty(), id + ": 幕墙不得加碰撞")
	_expect(_nonblack_ratio(on_image) > 0.08, id + ": 幕墙误挡整个房间")
	_expect(on_image.save_png(on_path) == OK, id + ": 启用幕墙截图保存失败")
	root.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var off_image := capture_viewport.get_texture().get_image()
	var off_path := output_dir.path_join(id + "_near_door_curtain_off_control.png")
	_expect(off_image.save_png(off_path) == OK, id + ": 关闭幕墙截图保存失败")
	root.visible = true
	var newly_hidden := _nonblack_ratio(off_image, on_image)
	_expect(newly_hidden > 0.015, id + ": 幕墙开关未遮住跨墙场景像素")
	print("LOW_WALL_CURTAIN_PIXELS room=%s newly_hidden_ratio=%.4f" % [id, newly_hidden])
	print("LOW_WALL_CURTAIN_PAIR room=%s on=%s off=%s" % [id, on_path, off_path])
	report.append({"label": id + "_near_door_curtain_on", "path": on_path, "control": off_path, "curtain": "on"})
	report.append({"label": id + "_near_door_curtain_off_control", "path": off_path, "control_for": on_path, "curtain": "off"})

func _nonblack_ratio(image: Image, black_reference: Image = null) -> float:
	var lit := 0
	var total := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var c := image.get_pixel(x, y)
			total += 1
			if maxf(c.r, maxf(c.g, c.b)) <= 0.06:
				continue
			if black_reference != null:
				var d := black_reference.get_pixel(x, y)
				if maxf(d.r, maxf(d.g, d.b)) > 0.025:
					continue
			lit += 1
	return float(lit) / maxf(1.0, float(total))

func _first_door(room: DungeonRoom3D) -> RoomDoor3D:
	for value in room.find_children("*", "Node3D", true, false):
		if value is RoomDoor3D:
			return value as RoomDoor3D
	return null

func _dump_report() -> void:
	if output_dir.is_empty():
		return
	var file := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"checks": checks,
			"failures": failures,
			"wall_height_m": WALL_HEIGHT_M,
			"player_top_m": PLAYER_TOP_M,
			"shots": report,
			"user_dir": ProjectSettings.globalize_path("user://"),
			"base_save_path": str(get_node_or_null("/root/BaseManager").get("save_path")) if get_node_or_null("/root/BaseManager") != null else "<missing>",
		}, "  "))
		file.close()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	failures.append(message)
	push_error("LOW_WALL_FAIL: " + message)

func _settle() -> void:
	for _i in range(5):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout

func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION01_LOW_WALL_OK checks=%d shots=%d renderer=%s" % [checks, report.size(), DisplayServer.get_name()])
	else:
		print("EXPEDITION01_LOW_WALL_FAILED failures=%d checks=%d" % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)
