extends Node
## 远征03 房门「可开启 / 不可开启」两态观感取证（业主 2026-10-30 二次口径）：
##
##   「这个门的状态，使用可开启和不可开启。在可开启状态，人走近了会自动打开，
##     然后再关闭。不可开启状态人走近了不会打开。」
##
## 这是**画面 + 手感**问题，必须真实渲染：headless 只能验数据，验不出
## "门板在不在视野里""走近那一刻门有没有动"。
##
## 四张同机位图，每张都由**真实机制**驱动（不手工摆门板）：
##   e3_doorstates_0_openable_closed.png  可开启·静止：门板在门洞，挡路
##   e3_doorstates_1_openable_near.png    可开启·走近 1.5m：自动双扇滑开
##   e3_doorstates_2_openable_away.png    可开启·走回房心：0.45s 后自动关上
##   e3_doorstates_3_locked_near.png      不可开启（封锁中）·走近：纹丝不动
##
## 跑法（**不要** --headless）：
##   godot --path . res://tests/verification/capture_expedition03_door_state.tscn

const LOADING_PATH := "res://scenes/ExpeditionLoadingScreen.tscn"
const LEVEL_ID := "expedition_03"
## 走近取 1.5m：远小于 `RoomDoor3D.PROXIMITY_OPEN_DISTANCE_M`（3.6m），
## 又足够站在房内、不触发位置权威把玩家弹回房心。
const NEAR_DISTANCE_M := 1.5

var tower: TowerDescent3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("房门开合取证需要真实渲染器")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1600, 1000)
	get_viewport().scaling_3d_scale = 1.0
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
		push_error("没有找到适合取景的门")
		tree.quit(1)
		return
	var room: DungeonRoom3D = pick["room"]
	var door: RoomDoor3D = pick["door"]
	var side := str(pick["side"])
	# 灯属于房间 detail（`_central_light` 随 `ensure_detail_built()` 建出），
	# detail 没建时 `set_room_light_on(true)` 是空转 —— 第一次拍出来全黑就是这个问题。
	room.ensure_detail_built()
	await _settle()
	room.set_room_light_on(true)
	await _settle()
	print("E3_DOORSTATE_LIGHT room_light_on=%s central=%s" % [
		str(room.is_room_light_on()),
		str(room.get("_central_light") != null)])
	print("E3_DOORSTATE_PICK room=%s type=%s dims=%s side=%s door=%s target=%s" % [
		room.room_id, room.room_type, str(room.get_dimensions()),
		side, str(door.name), str(door.target_room_id)])

	# 视角切换到当前房：幕墙挖洞跟着走，否则画面被黑幕挡死。
	tower.set("_current_room_id", room.room_id)
	tower.set("_flow_view_mask_room_id", "")
	tower.call("_refresh_flow_view_mask", true)
	for value in tower.find_children("*", "CanvasLayer", true, false):
		(value as CanvasLayer).visible = false
	var player := tower.get("player") as Node3D
	if player != null:
		player.visible = false

	var out := OS.get_environment("E3_DOORSTATE_QA_DIR")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://outputs/expedition03_door_states_20261030")
	DirAccess.make_dir_recursive_absolute(out)

	# 门在哪面墙 ⇒ 房间内侧方向与朝向（角色朝门站）。
	var inward := Vector3.ZERO
	var yaw := 0.0
	match side:
		"north":
			inward = Vector3(0.0, 0.0, 1.0)
			yaw = 0.0
		"south":
			inward = Vector3(0.0, 0.0, -1.0)
			yaw = PI
		"west":
			inward = Vector3(1.0, 0.0, 0.0)
			yaw = PI * 0.5
		"east":
			inward = Vector3(-1.0, 0.0, 0.0)
			yaw = -PI * 0.5
	var anchor := door.global_position
	# 玩家跟随相机在 10.26m 高、拖尾 4.91m：站在门附近时门只占画面顶上一小块，
	# 看不清门板到底在不在。取证改用一台**独立相机**对着门洞拍 ——
	# 画面能不能读出「可开启 / 不可开启」是这次要证明的东西，取景本身不该成为变量。
	var cam := _make_evidence_camera(anchor, inward)
	await _settle()
	# 感应器的检测目标是本局玩家：先把人从门边挪开，让四张图都从"门关着"起步。
	var room_center := room.global_position + Vector3(0.0, 0.05, 0.0)
	await _hold_player_at(room_center, 40)

	# ① 可开启 · 静止：已清房（`cleared = true`）⇒ 门权限为**可开启**，
	#    门板留在门洞里挡路 —— 这正是业主截图里那个状态。
	room.cleared = true
	tower.call("set_room_seal", room.room_id, false, "")
	tower.call("_apply_flow_room_seal", room)
	await _await_door_settled()
	await _shot("%s/e3_doorstates_0_openable_closed.png" % out, cam)
	_report("openable_closed", room, door)

	# ② 可开启 · 走近 1.5m：不按 E、不调任何开门接口，只把人走过去。
	var near := anchor + inward * NEAR_DISTANCE_M + Vector3.UP * 0.05
	await _hold_player_at(near, 30)
	var opened_near := door.is_open
	await _await_door_settled()
	await _shot("%s/e3_doorstates_1_openable_near.png" % out, cam)
	_report("openable_near", room, door)
	print("E3_DOORSTATES auto_open_near=%s" % str(opened_near))

	# ③ 可开启 · 走回房心：距门远超关阈，0.45s 延迟后应自动关上。
	await _hold_player_at(room_center, 90)
	var closed_away := not door.is_open
	await _await_door_settled()
	await _shot("%s/e3_doorstates_2_openable_away.png" % out, cam)
	_report("openable_away", room, door)
	print("E3_DOORSTATES auto_close_away=%s" % str(closed_away))

	# ④ 不可开启 · 走近：封锁中（战斗）门权限翻成不可开启，
	#    同样把人放到门边，门必须纹丝不动 —— 与 ② 唯一的差别就是权限。
	tower.call("set_room_seal", room.room_id, true, "door_state_capture")
	await _await_door_settled()
	await _hold_player_at(near, 40)
	var opened_locked := door.is_open
	await _await_door_settled()
	await _shot("%s/e3_doorstates_3_locked_near.png" % out, cam)
	_report("locked_near", room, door)
	print("E3_DOORSTATES locked_open_near=%s（必须为 false）" % str(opened_locked))

	# 诊断图放最后：给两扇门板刷高亮自发光，用来区分"被墙挡住"与"太暗看不出"。
	# 必须在正式图之后 —— 染色会污染同机位的后续截图。
	_debug_paint_panels(door)
	await _settle()
	await _shot("%s/e3_doorstates_9_debug.png" % out, cam)
	print("E3_DOORSTATE_SHOT dir=%s" % out)
	tree.quit(0)


func _report(tag: String, room: DungeonRoom3D, door: RoomDoor3D) -> void:
	var snapshot: Dictionary = door.get_snapshot()
	print("E3_DOORSTATES %-16s cleared=%s sealed=%s openable=%s open=%s panel_x=%.2f panel_z=%.2f blocks=%s" % [
		tag,
		str(room.cleared),
		str((tower.get("_sealed_rooms") as Dictionary).has(room.room_id)),
		str(snapshot.get("openable", "?")),
		str(snapshot.get("is_open", "?")),
		float(snapshot.get("panel_x", 0.0)),
		_panel_z(door),
		str(snapshot.get("blocks_passage", true))])


## 把玩家钉在一个位置上跑 `frames` 帧（门态由调用方读）。
##
## 逐帧钉是必须的：物理的位置权威会把"边界附近的瞬移"纠正回房心，
## 只设一次的话第一帧人就飞走了，测到的永远是"走远了"。
func _hold_player_at(position: Vector3, frames: int) -> void:
	var target := tower.get("player") as Node3D
	if target == null:
		return
	for i in range(frames):
		target.global_position = position
		target.velocity = Vector3.ZERO
		await get_tree().process_frame


## 一台固定机位的取证相机：站在**房间内**、眼高约 1.7m 平视门洞。
##
## ⚠️ 机位不能高于 2.8m 墙顶：房间壳体只有 2.8m，越过去就是墙外，
## 拍到的会是幕墙的黑，看不出门板在不在。
func _make_evidence_camera(anchor: Vector3, inward: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "DoorStateEvidenceCamera"
	cam.fov = 52.0
	# 必须先入树再定位：`look_at()` 依赖节点已在场景树里，
	# 先调会抛 "Node not inside tree"，机位保持默认目标点。
	add_child(cam)
	cam.global_position = anchor + inward * 5.6 + Vector3.UP * 1.72
	cam.look_at(anchor + Vector3.UP * 1.05)
	cam.make_current()
	return cam


## 门开合动画 0.24s（`DEFAULT_MOTION_DURATION_S`）：截前必须等它走完，
## 否则拍到的是两块门板在门洞中央的半途状态（那正是我第一次拍到的东西）。
func _await_door_settled() -> void:
	for i in range(40):
		await get_tree().physics_frame


## 挑一扇「两面都是真房间」的连通门：门板两侧都有墙体可参照，
## 也不挑封闭抵达门（那扇恒关，看不到开门态）。
func _pick_door(rooms: Dictionary) -> Dictionary:
	var order := ["room_01", "hub_01", "n02", "n03", "n04"]
	for room_id in order:
		var room := rooms.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		for side in ["north", "south", "east", "west"]:
			var door := room.get_door_node(side)
			if door == null or str(door.target_room_id).is_empty():
				continue
			if room.get_dimensions().x < 20.0 or room.get_dimensions().y < 20.0:
				continue
			return {"room": room, "door": door, "side": side}
	for room_id in rooms.keys():
		var room := rooms[room_id] as DungeonRoom3D
		if room == null:
			continue
		for side in ["north", "south", "east", "west"]:
			var door := room.get_door_node(side)
			if door != null and not str(door.target_room_id).is_empty():
				return {"room": room, "door": door, "side": side}
	return {}


func _debug_paint_panels(door: RoomDoor3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.1, 0.1)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.2, 0.2)
	material.emission_energy_multiplier = 4.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for panel_name in ["DoorPanel", "DoorPanelRight"]:
		var panel := door.get_node_or_null(panel_name) as Node3D
		if panel == null:
			continue
		for value in panel.find_children("*", "MeshInstance3D", true, false):
			(value as MeshInstance3D).material_override = material


func _panel_z(door: RoomDoor3D) -> float:
	var panel := door.get_node_or_null("DoorPanel") as Node3D
	return panel.position.z if panel != null else 0.0


func _hold(player: Node3D, target: Vector3, yaw: float) -> void:
	for i in range(48):
		player.global_position = target
		player.velocity = Vector3.ZERO
		player.rotation.y = yaw
		await get_tree().physics_frame


## 玩家相机每帧都会把自己设为 current；取证相机必须在截前重新夺回，
## 否则拍到的是跟随视角（第一次就踩了这个坑：两张图机位不一样）。
func _shot(path: String, cam: Camera3D = null) -> void:
	if cam != null:
		cam.make_current()
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _settle() -> void:
	for i in range(8):
		await get_tree().process_frame
