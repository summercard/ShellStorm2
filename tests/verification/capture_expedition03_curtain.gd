extends Node
## 远征03 过门观感取证（业主 2026-10-29 的两条报单）：
##   ① 过房间时镜头不许弹；
##   ② 门洞里不能是一块纯黑 —— 要能直接看到门后那间。
##
## 为什么必须用真实渲染器：这两条都是**画面**问题，headless 只能验数据。
## 取景固定为"角色站在门内侧不远处 / 正在跨门 / 已跨过、镜头落在走道里"，
## 正是玩家过门的视角。
##
## 产出四张 + 一张对照：
##   e3_door_0_inside_far.png   房里远端，看整面墙与门洞
##   e3_door_1_inside_mid.png   房中部
##   e3_door_2_at_door.png      站在门洞上
##   e3_door_3_crossed.png      已跨过、镜头在走道里（验证幕墙收起）
##   e3_door_9_no_curtain.png   对照：整圈幕墙关闭（门后到底是什么）

const LOADING_PATH := "res://scenes/ExpeditionLoadingScreen.tscn"
const LEVEL_ID := "expedition_03"

var tower: TowerDescent3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("远征03 过门取证需要真实渲染器")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1600, 1000)
	get_viewport().scaling_3d_scale = 1.0
	# 必须走与 `probe_expedition03_playable` 相同的引导链（游戏入口 + 加载屏）。
	# 直接 `instantiate()` 场景会命中装配期校验
	# `spawn_boxes_missing_for_hostile_room:boss` —— 那条校验依赖入口流程准备好的
	# 关卡选择与内容计划，不经过它 Boss 房就没有刷怪框，整局装配被判失败。
	var tree := get_tree()
	tree.current_scene = null
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		push_error("select_expedition_level 被拒绝")
		tree.quit(1)
		return
	tree.change_scene_to_file(LOADING_PATH)
	await tree.scene_changed
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if tree.current_scene is TowerDescent3D:
			tower = tree.current_scene as TowerDescent3D
			if bool(tower.get_meta("loading_scene_ready", false)):
				break
	if tower == null or (tower.get("_room_by_id") as Dictionary).is_empty():
		push_error("没有装配出关卡（重跑一次；装配校验对部分随机骨架会失败）")
		tree.quit(1)
		return
	await _settle()
	var rooms: Dictionary = tower.get("_room_by_id")
	for room_id in rooms:
		(rooms[room_id] as DungeonRoom3D).set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await _settle()

	var pick := _pick_door(rooms)
	if pick.is_empty():
		push_error("没有找到带南北门的房间")
		get_tree().quit(1)
		return
	var room: DungeonRoom3D = pick["room"]
	print("E3_DOOR_LIGHTS room=%d peer=%d" % [
		_light_count(room), _light_count(pick["peer"] as DungeonRoom3D)])
	print("E3_DOOR_PICK room=%s type=%s dims=%s peer=%s peer_type=%s peer_dims=%s" % [
		room.room_id, room.room_type, str(room.get_dimensions()),
		str(pick["peer"].room_id if pick["peer"] != null else ""),
		str((pick["peer"] as DungeonRoom3D).room_type) if pick["peer"] != null else "-",
		str((pick["peer"] as DungeonRoom3D).get_dimensions()) if pick["peer"] != null else "-"])
	var peer: DungeonRoom3D = pick["peer"]
	var door: RoomDoor3D = pick["door"]
	var side := str(pick["side"])
	# 取景前把两侧房间的灯打开：这一轮看的是"过门能不能看见下一间"，
	# 而房间灯是玩家可开关的状态（关灯时本来就该是暗的，那是设计不是缺陷）。
	room.set_room_light_on(true)
	peer.set_room_light_on(true)
	# 门全开：这次要看的是"门洞后面的东西"，不是门板。
	door.set_open(true)
	var peer_door := peer.get_door_node_towards(room.room_id)
	if peer_door != null:
		peer_door.set_open(true)
	tower.set("_current_room_id", room.room_id)
	tower.set("_flow_view_mask_room_id", "")
	tower.call("_refresh_flow_view_mask", true)
	# HUD 会挡住画面，但不是被测对象。
	for value in tower.find_children("*", "CanvasLayer", true, false):
		(value as CanvasLayer).visible = false
	var player := tower.get("player") as Node3D
	if player != null:
		player.visible = false

	var out := OS.get_environment("E3_CURTAIN_QA_DIR")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://outputs/expedition03_curtain_20261029")
	DirAccess.make_dir_recursive_absolute(out)

	# 门在北边 ⇒ 角色朝北（yaw 0），镜头落在南侧看北；门在南边反之。
	var yaw := 0.0 if side == "north" else PI
	var inward := Vector3(0.0, 0.0, 1.0) if side == "north" else Vector3(0.0, 0.0, -1.0)
	var anchor := door.global_position
	# 从房里到门洞再到门后，六档距离（正数 = 还在房里）。
	# 2026-10-29 晚业主报的是"进门的时候会看到外边的房间"，所以取景点特意加密到
	# 跨门前后各一档（±0.6 / ±1.5），这几帧正是问题最容易露出来的位置。
	var steps := [6.0, 3.0, 1.5, 0.6, -0.6, -1.5]
	var labels := ["inside_far", "inside_mid", "inside_near", "at_door", "crossed", "far_out"]
	for index in range(steps.size()):
		var target := anchor + inward * float(steps[index]) + Vector3.UP * 0.05
		for i in range(40):
			player.global_position = target
			player.velocity = Vector3.ZERO
			player.rotation.y = yaw
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/e3_door_%d_%s.png" % [out, index, labels[index]])
		var cam := tower.get("player").camera as Camera3D
		# 当前房间按**玩家实际所处**的房间报（基类靠触发区换房，可能滞后一帧）。
		var now_room := _room_at(player.global_position, rooms)
		var inside_now := false
		if now_room != null:
			var nd := now_room.get_dimensions()
			var np := now_room.global_position
			inside_now = (
				absf(cam.global_position.x - np.x) <= nd.x * 0.5 + 0.01
				and absf(cam.global_position.z - np.z) <= nd.y * 0.5 + 0.01)
		print("E3_DOOR_SHOT %s side=%s room=%s cam=%s cam_in_room=%s curtain=%s" % [
			labels[index], side,
			"-" if now_room == null else now_room.room_id,
			str(cam.global_position.snapped(Vector3.ONE * 0.1)),
			str(inside_now),
			"on" if _curtain_visible() else "off"])

	# 对照：整圈幕墙关掉，用来证明"门洞里的黑不是幕墙"（换房后本来就能看见）。
	var root := tower.call("find_child", "FlowViewWalls", true, false) as Node3D
	if root != null:
		root.visible = false
		for i in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/e3_door_9_no_curtain.png" % out)
		root.visible = true
	print("E3_DOOR_DIR ", out)
	print("E3_DOOR_OK")
	get_tree().quit(0)


## 挑一间南北有门的房 —— 门的朝向决定角色/镜头朝向，只取南北是为了取景稳定。
func _pick_door(rooms: Dictionary) -> Dictionary:
	# 两轮：先只要非 Boss 房（普通战斗房有顶灯，取景亮度稳定），再退回任意房。
	for pass_index in range(2):
		for room_id in rooms:
			var room := rooms[room_id] as DungeonRoom3D
			if room == null or minf(room.get_dimensions().x, room.get_dimensions().y) < 20.0:
				continue
			if pass_index == 0 and room.room_type == "BOSS":
				continue
			for side in ["north", "south"]:
				var door := room.get_door_node(side)
				if door == null or not is_instance_valid(door):
					continue
				var peer_id := str((room.door_targets as Dictionary).get(side, ""))
				var peer := rooms.get(peer_id) as DungeonRoom3D
				if peer == null or not is_instance_valid(peer):
					continue
				if pass_index == 0 and _light_count(peer) == 0:
					continue
				return {"room": room, "peer": peer, "door": door, "side": side}
	return {}


func _light_count(room: DungeonRoom3D) -> int:
	if room == null:
		return 0
	return room.find_children("*", "WastelandLight3D", true, false).size() 		+ room.find_children("FlowPassageFill", "OmniLight3D", true, false).size()


## 玩家脚下落在哪间房的足迹里（含走廊小间）。用于取证时标出"此刻算哪间房"。
func _room_at(point: Vector3, rooms: Dictionary) -> DungeonRoom3D:
	var best: DungeonRoom3D = null
	var best_area := INF
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		var dims := room.get_dimensions()
		var rp := room.global_position
		if absf(point.x - rp.x) > dims.x * 0.5 or absf(point.z - rp.z) > dims.y * 0.5:
			continue
		var area := dims.x * dims.y
		if area < best_area:
			best_area = area
			best = room
	return best


func _curtain_visible() -> bool:
	var root := tower.call("find_child", "FlowViewWalls", true, false) as Node3D
	return root != null and root.visible


func _settle() -> void:
	for step in range(5):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
