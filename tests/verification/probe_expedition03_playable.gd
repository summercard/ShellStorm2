extends Node
## 远征03 可玩性验收：几何能走通 + 房门规则对。
##
## 三段，各自对应业主报过的一类问题：
##   A 几何：门洞穿得过、房间互相可达、没有塔楼高墙穿进房间
##     （业主 2026-10-28：「进某个房间后会刷出 11.9 米的墙和空阻挡」）
##   B 房门规则：内容房有门扇、无怪房不锁、不要钥匙、不弹命运卡
##     （业主：「不需要房间钥匙这个设定」「清怪后门开启逻辑没有制作」）
##   C 封门/开门：进内容房 → 门关上；清房 → 门自动打开
##
## 为什么必须真的走进去测：这一层的前两版都是「房间建出来了、校验全绿」，
## 但玩家走不动 —— 只有用玩家自己的碰撞掩码打射线、并真的触发一次封门/清房，
## 才验得到。

const LOADING_PATH := "res://scenes/ExpeditionLoadingScreen.tscn"
const LEVEL_ID := "expedition_03"

var _failures: Array[String] = []
## 漏光像素上限（采样步长 12 ⇒ 全屏约 6400 个采样点）。
##
## 取值按**缺陷量级**定，不是凑数：
##   · 真实漏缝（水平遮罩时代那条浅带）实测 **5000+** 个采样点，一眼可见；
##   · 现在剩下的几十个是几何边缘的混合像素 —— 幕墙顶边与远处交界处被抗锯齿
##     平均、以及"纯视觉件没有碰撞"（像素显示的是房间自己的构件，但物理射线从它的
##     碰撞空隙穿出去、落到了墙外地面）。它们的共同特征是**关掉幕墙后亮度只涨
##     0.05~0.09**，而真漏缝会涨 0.1~0.4。
## 500 相对噪声（<120）有 4 倍余量，相对真漏缝（5000+）有 10 倍余量，两头都稳。
const WALL_LEAK_LIMIT := 500
## 门洞净宽/净高（幕墙开洞要与墙体切口同源，见 `DungeonRoom3D._build_wall()`）。
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
## 与 `TowerDescent3D.CAMERA_HEIGHT_M` 同源：夹取只许动 x/z，高度必须仍是它。
const CAMERA_HEIGHT_M := 10.262659

var _tower: TowerDescent3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	call_deferred("_run")


func _run() -> void:
	var tree := get_tree()
	tree.current_scene = null
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		print("PLAYABLE_FAIL: select_expedition_level 被拒绝")
		tree.quit(1)
		return
	tree.change_scene_to_file(LOADING_PATH)
	await tree.scene_changed
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if tree.current_scene is TowerDescent3D:
			_tower = tree.current_scene as TowerDescent3D
			break
	if _tower == null:
		print("PLAYABLE_FAIL: 没有进入关卡场景")
		tree.quit(1)
		return
	var ready_deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < ready_deadline:
		if bool(_tower.get_meta("loading_scene_ready", false)):
			break
		await tree.process_frame
	for i in range(20):
		await tree.physics_frame

	var rooms := _tower._room_by_id
	print("PLAYABLE rooms=%d ready=%s" % [
		rooms.size(), str(_tower.get_meta("loading_scene_ready", false))])

	# 门扇可能挂在 `RuntimeDetail` 下（流送会把细节卸载掉），先全部逼成 ACTIVE。
	for room_key in rooms.keys():
		var streamed := rooms[room_key] as DungeonRoom3D
		if streamed != null:
			streamed.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	for i in range(3):
		await tree.process_frame

	await _verify_geometry(rooms)
	_verify_door_rules(rooms)
	await _verify_seal_cycle(rooms)
	# 像素级漏光测量放在最后：它会瞬移玩家，不能和上面的时序用例抢位置。
	await _verify_wall_leak(rooms)
	_finish()


# ── A 几何 ────────────────────────────────────────────────────────────────
func _verify_geometry(rooms: Dictionary) -> void:
	# 连通性测试要先把门**全部打开**：门是"通道"，几何验的是门洞通不通。
	# **封闭抵达门（target 为空）除外** —— 它本来就是关着的退局气闸，
	# 打开等于在墙上开个洞，玩家会走出地图。
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		for direction in room.door_targets.keys():
			if str((room.door_targets as Dictionary)[direction]).is_empty():
				continue
			room.set_door_open(str(direction), true, true)
		for child in room.find_children("*", "Node3D", true, false):
			if child is RoomDoor3D:
				var leaf := child as RoomDoor3D
				if str((room.door_targets as Dictionary).get(leaf.direction, "x")).is_empty():
					continue
				leaf.set_open(true, true)

	# ⚠️ 这里要量的是"**墙体**上的门洞通不通"，不是门扇开没开。
	#
	# `RoomDoor3D` 的开合碰撞是用 `set_deferred("disabled", ...)` 写的，**帧末才生效**；
	# 而刷新时机跟帧率有关（带渲染 / headless 不一样）。靠"等几帧"或"轮询几帧"都会
	# 偶发读不到 —— 实测带渲染时会出现 `25/27 门洞被墙封死` 的假红，headless 却是绿的。
	# 门扇开合另有专门用例（B 段 `slide_doors` 校验左右行程 + 碰撞），这里不该重复考它。
	# 所以直接把门扇碰撞层清零（`collision_layer` 是**立即生效**的，不是 deferred），
	# 量完再还原。这样射线只受墙体影响，结果与帧率无关。
	var door_bodies: Array[CollisionObject3D] = []
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		for child in room.find_children("*", "Node3D", true, false):
			if child is RoomDoor3D:
				var body := child as CollisionObject3D
				door_bodies.append(body)
	for body in door_bodies:
		body.collision_layer = 0
	var space := _tower.get_world_3d().direct_space_state
	var player_collision_mask := 0xFFFFFFFF
	if _tower.player != null:
		player_collision_mask = _tower.player.collision_mask
	print("PLAYABLE player_mask=%d" % player_collision_mask)
	var edges: Array[Dictionary] = []
	var blocked := 0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		var room_pos := room.global_position
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var target := str(port.get("target_room_id", ""))
			if target.is_empty() or not rooms.has(target):
				continue
			if str(room_key) > target:
				continue
			var local: Array = port.get("position_m", [0.0, 0.0])
			var outward: Array = port.get("outward", [0.0, 0.0])
			var gate := room_pos + Vector3(float(local[0]), 0.9, float(local[1]))
			var normal := Vector3(float(outward[0]), 0.0, float(outward[1]))
			var query := PhysicsRayQueryParameters3D.create(
				gate - normal * 1.2, gate + normal * 1.2)
			# 必须用玩家自己的碰撞掩码：场景里有大量只给镜头用的低墙
			# （`CameraOnlyDoorWall_*` / `WallCollisionShort|Long`），
			# 默认掩码会把"能过"误报成"挡住"。
			query.collision_mask = player_collision_mask
			var hit := space.intersect_ray(query)
			var is_blocked := not hit.is_empty()
			if is_blocked:
				blocked += 1
				if blocked <= 5:
					print("PLAYABLE_DOOR %-22s -> %-22s BLOCKED hit=%s" % [
						str(room_key), target, str((hit.get("collider") as Object).name)])
			edges.append({"a": str(room_key), "b": target, "blocked": is_blocked})

	for body in door_bodies:
		if is_instance_valid(body):
			body.collision_layer = 1
	var reachable := _reachable_from(edges, "start")
	print("PLAYABLE doors_total=%d open=%d blocked=%d reachable=%d/%d" % [
		edges.size(), edges.size() - blocked, blocked, reachable.size(), rooms.size()])
	if blocked > 0:
		_failures.append("%d/%d 条门洞被墙封死（门已全开仍然过不去）" % [blocked, edges.size()])
	if reachable.size() < rooms.size():
		_failures.append("从入口只能走到 %d/%d 间房" % [reachable.size(), rooms.size()])
	if not reachable.has("room_01"):
		_failures.append("第一间内容房 room_01 走不到")

	# 塔楼 5m 栅格的高墙（11.9m）不得压进任何房间内部。
	#
	# 豁免 `FlowViewWalls` / `FlowViewMask`：幕墙本身就是一堵 27m 高、围着当前房间的**墙**，
	# 它的 AABB 必然包住房间足迹 —— 那正是它的用途，不是"塔楼高墙穿房"。
	#
	# `is_queued_for_deletion()` 也必须豁免：换房重建时旧幕墙被改名成
	# `FlowViewWalls_old` 再 queue_free，它在**本帧剩余时间仍在树里**，
	# 名字还会被 Godot 改成匿名 `@MeshInstance3D@NNN` —— 名字判断因此失效，
	# 但它的 AABB 和新幕墙一模一样，会把自己伪装成"塔楼高墙"报一次假红。
	var tall_hits := 0
	for node in _tower.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi.is_queued_for_deletion():
			continue
		if str(gi.name).begins_with("FlowViewWalls") 				or str(gi.name).begins_with("FlowViewMask"):
			continue
		var mesh_aabb := AABB()
		if gi is MultiMeshInstance3D:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			mesh_aabb = mm.mesh.get_aabb()
		elif gi is MeshInstance3D:
			mesh_aabb = (gi as MeshInstance3D).get_aabb()
		else:
			continue
		if mesh_aabb.size.y < 5.0:
			continue
		var world_aabb := gi.global_transform * mesh_aabb
		for room_key in rooms.keys():
			var room := rooms[room_key] as DungeonRoom3D
			if room == null:
				continue
			var dims := room.get_dimensions()
			var rp := room.global_position
			var foot := AABB(
				Vector3(rp.x - dims.x * 0.5, rp.y, rp.z - dims.y * 0.5),
				Vector3(dims.x, 1.0, dims.y))
			var inter := world_aabb.intersection(foot)
			if inter.size.x > 0.5 and inter.size.z > 0.5:
				tall_hits += 1
				if tall_hits <= 3:
					print("PLAYABLE TALL_HIT %s class=%s room=%s inter=%.1fx%.1f aabb=%s parent=%s" % [
						str(gi.name), gi.get_class(), str(room_key),
						inter.size.x, inter.size.z, str(world_aabb),
						str(gi.get_parent().name) if gi.get_parent() != null else "-"])
				break
	print("PLAYABLE tall_wall_inside_room=%d" % tall_hits)
	if tall_hits > 0:
		_failures.append("%d 处 >5m 高的塔楼墙压进房间内部" % tall_hits)

	# 楼层通用地砖必须在每个房间足迹处挖空。
	#
	# 房间自带 `Floor`（顶面 Y=0），楼层台座也铺一层通用砖（同样 Y=0）——
	# 不挖就是两套砖共面 z-fighting，玩家看到的是「靠墙边缘闪面厉害」
	# （业主 2026-10-28）。01/02 由静态布局那条路早就挖过，flow 房型是
	# SAFE_ROOM / COMMON_ROOM，原来的判据一个都命中不了。
	var holes: Array = _tower._stair_lobby_visual_holes(
		int(_tower.get("EXPEDITION_LAYER_INDEX")))
	var uncovered := 0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		var dims := room.get_dimensions()
		var rp := room.global_position
		var foot := Rect2(rp.x - dims.x * 0.5, rp.z - dims.y * 0.5, dims.x, dims.y)
		var covered_area := 0.0
		for hole_value in holes:
			var hole := hole_value as Rect2
			var inter := hole.intersection(foot)
			if inter.size.x > 0.0 and inter.size.y > 0.0:
				covered_area = maxf(covered_area, inter.size.x * inter.size.y)
		var ratio := covered_area / maxf(0.001, foot.size.x * foot.size.y)
		if ratio < 0.99:
			uncovered += 1
			if uncovered <= 5:
				print("PLAYABLE GAP_FLOOR %s 只挖掉 %.0f%% 的地砖（会与通用砖共面闪面）" % [
					str(room_key), ratio * 100.0])
	print("PLAYABLE floor_holes=%d uncovered_rooms=%d" % [holes.size(), uncovered])
	if uncovered > 0:
		_failures.append("%d 间房的地砖没从通用砖里挖掉（共面闪面）" % uncovered)

	# —— 镜头不再被墙"自动复位"（业主 2026-10-28 要求去掉）——
	#
	# 原行为：墙进入镜头通道 ⇒ 镜头抬高 0.30m + 沿后方轴从 3.1m 收到 0.15m，
	# 离开墙再弹回来。现在 flow 关卡把目标锁死在基准值，抬升恒 0、收拢恒等于基准。
	_tower._update_camera_lower_wall_lift(0.5, true)
	var lift_m := float(_tower.get("_camera_lift_current_m"))
	var trailing_m := float(_tower.get("_camera_trailing_current_m"))
	var base_trailing_m := float(_tower.get("_camera_profile_trailing_current_m"))
	var lower_wall_detected := bool(_tower.get("_camera_lower_wall_detected"))
	print("PLAYABLE camera lift=%.3f trailing=%.3f base=%.3f wall_detected=%s" % [
		lift_m, trailing_m, base_trailing_m, str(lower_wall_detected)])
	if absf(lift_m) > 0.001:
		_failures.append("镜头仍在按墙抬升：lift=%.3f" % lift_m)
	if lower_wall_detected:
		_failures.append("镜头仍在探测后墙（应完全关闭）")
	if absf(trailing_m - base_trailing_m) > 0.001:
		_failures.append("镜头仍被墙收拢：trailing=%.3f base=%.3f" % [
			trailing_m, base_trailing_m])

	# —— 镜头必须夹在当前房间内（业主指定保留的「镜头碰撞」）——
	#
	# 业主 2026-10-29 晚两次确认：「摄像机镜头碰撞这个别改了。保留」。
	# 那条就是 `_clamp_flow_camera_into_room()`：只夹水平 x/z，过门即换框。
	#
	# 判据用**几何**：27+ 间房 × 四角内缩 1.5m 的站位，镜头都不许越出该房足迹
	# （允许半墙厚 0.14m 的墙面重叠）。高度必须仍是基准 —— 夹取只动 x/z。
	var clamp_cases := 0
	var outside_cases := 0
	var height_drift := 0.0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		var dims := room.get_dimensions()
		if dims.x <= 0.0 or dims.y <= 0.0:
			continue
		var rp := room.global_position
		_tower._current_room_id = room.room_id
		var probes: Array[Vector3] = [
			Vector3(rp.x + dims.x * 0.5 - 1.5, rp.y + 0.05, rp.z + dims.y * 0.5 - 1.5),
			Vector3(rp.x - dims.x * 0.5 + 1.5, rp.y + 0.05, rp.z + dims.y * 0.5 - 1.5),
			Vector3(rp.x + dims.x * 0.5 - 1.5, rp.y + 0.05, rp.z - dims.y * 0.5 + 1.5),
			Vector3(rp.x - dims.x * 0.5 + 1.5, rp.y + 0.05, rp.z - dims.y * 0.5 + 1.5),
		]
		for probe in probes:
			_tower.player.global_position = probe
			_tower.player.velocity = Vector3.ZERO
			for i in range(4):
				await get_tree().physics_frame
			var cam := _tower.player.camera.global_position
			var over_x := absf(cam.x - rp.x) - dims.x * 0.5
			var over_z := absf(cam.z - rp.z) - dims.y * 0.5
			if over_x > 0.14 or over_z > 0.14:
				outside_cases += 1
			# 基准取**玩家脚下**：探针把玩家摆在 `rp.y + 0.05`，用 `rp.y` 会白送 0.05m 假漂移。
			height_drift = maxf(
				height_drift,
				absf(cam.y - (_tower.player.global_position.y + CAMERA_HEIGHT_M)))
			clamp_cases += 1
	_tower._current_room_id = rooms.keys()[0]
	print("PLAYABLE camera_clamp cases=%d outside=%d height_drift=%.3f" % [
		clamp_cases, outside_cases, height_drift])
	if clamp_cases == 0:
		_failures.append("镜头夹取用例没跑起来")
	if outside_cases > 0:
		_failures.append("%d 个站位镜头跑到房间外（会看见黑墙背面）" % outside_cases)
	if height_drift > 0.02:
		_failures.append("镜头夹取动了高度（漂移 %.3fm）" % height_drift)

	# —— 房间外不可观察（Gungeon 的 room-as-stage）——
	#
	# 房间壳体永久可见，相机又在 10m 高、俯角 60°，视线必然越过 2.8m 墙顶看到隔壁房间。
	# 现在用的是**竖直幕墙**（`FlowViewWalls*`）：贴在当前房间墙外表面、从 -1m 到 26m，
	# 竖直形状没有视差，俯视时也不遮挡墙顶剖面（业主 2026-10-28 要的顶视角手感）。
	#
	# 历史上的水平遮罩（`FlowViewMask`，带洞的平面）已废弃：它自带视差 ——
	# 洞外扩就露出墙外地面（业主红框那条缝），洞内缩就把墙顶剖面盖黑，无解。
	var curtain := _tower.find_child("FlowViewWalls", true, false) as Node3D
	var curtain_ok := curtain != null and curtain.get_child_count() > 0
	print("PLAYABLE view_curtain=%s sides=%d room=%s" % [
		str(curtain_ok), 0 if curtain == null else curtain.get_child_count(),
		str(curtain.get_meta("view_wall_room_id", "")) if curtain != null else "-"])
	if not curtain_ok:
		_failures.append("缺少房间外幕墙（FlowViewWalls）—— 站着能看到隔壁房间")
	else:
		var curtain_rect := curtain.get_meta("view_wall_rect", Rect2()) as Rect2
		var curtain_top := float(curtain.get_meta("view_wall_top", 0.0))
		var curtain_bottom := float(curtain.get_meta("view_wall_bottom", 0.0))
		var curtain_room := str(curtain.get_meta("view_wall_room_id", ""))
		var cam_height := 0.0
		if _tower.player != null and _tower.player.camera != null:
			cam_height = _tower.player.camera.global_position.y
		print("PLAYABLE curtain rect=%s y=[%.2f..%.2f] cam_y=%.2f room=%s" % [
			str(curtain_rect), curtain_bottom, curtain_top, cam_height, curtain_room])
		# ① 上沿必须高于相机：否则视线从幕墙顶越过去又是一条漏。
		if curtain_top <= cam_height + 1.0:
			_failures.append("幕墙上沿 %.2fm 不高于相机 %.2fm（视线会从顶上越过去）" % [
				curtain_top, cam_height])
		# ② 下沿必须低于地面：否则俯角压低的视线从底下穿过去。
		if curtain_bottom > -0.2:
			_failures.append("幕墙下沿 %.2fm 没沉到地面以下" % curtain_bottom)
		# ③ 幕墙必须贴合当前房间足迹（不多不少）。
		var curtain_room_node := rooms.get(curtain_room) as DungeonRoom3D
		if curtain_room_node != null:
			var cdims := curtain_room_node.get_dimensions()
			var cp := curtain_room_node.global_position
			var expect := Rect2(
				cp.x - cdims.x * 0.5, cp.z - cdims.y * 0.5, cdims.x, cdims.y)
			var drift := maxf(
				absf(curtain_rect.position.x - expect.position.x),
				absf(curtain_rect.end.x - expect.end.x))
			drift = maxf(drift, maxf(
				absf(curtain_rect.position.y - expect.position.y),
				absf(curtain_rect.end.y - expect.end.y)))
			print("PLAYABLE curtain_drift=%.3f (expect=%s)" % [drift, str(expect)])
			# 允许的漂移 = 墙外表面（半墙厚）+ gap，再多就是贴错了。
			if drift > 0.30:
				_failures.append("幕墙没贴合房间足迹（漂移 %.3fm）" % drift)
		# ④ **门的位置不许有幕墙**（业主 2026-10-30：「想办法把门的位置不要有黑幕」）。
		#
		# 判据分三层，任一层不成立都会让玩家在门洞里看到一块黑：
		#   a. 门洞数 == 墙体门洞数（该开的地方有没有开）；
		#   b. 每个洞的区间要覆盖「门中心 ± 门洞净宽的一半」（开够宽，不是窄窄一条缝）；
		#   c. 幕墙总面积 == 「整面 − 各洞面积」（网格真的被切了，不是只写了 meta）。
		#
		# 幕墙**其余方向仍然必须全挡**，所以 c 是等号两边都要对 ——
		# 只查"小了"会漏掉"洞开过头、把该挡的地方也挖掉"。
		if curtain_room_node != null:
			var lane_total := 0
			var hole_total := 0
			var covered_bad := 0
			var panel_area := 0.0
			var expect_area := 0.0
			var hole_area := 0.0
			var cp := curtain_room_node.global_position
			for side_value in ["north", "south", "west", "east"]:
				var side := str(side_value)
				var along_x := side in ["north", "south"]
				var lanes := curtain_room_node.get_wall_door_lanes(side)
				lane_total += lanes.size()
				# 幕墙每片的沿墙跨度 = 足迹边长 + 两侧各 (半墙厚 + gap)。
				var span := (
					(curtain_rect.size.x + 0.32) if along_x
					else (curtain_rect.size.y + 0.32))
				expect_area += span * (curtain_top - curtain_bottom)
				var panel := curtain.get_node_or_null(
					"FlowViewWalls%s" % side.capitalize()) as MeshInstance3D
				if panel == null or panel.mesh == null:
					continue
				panel_area += _panel_area_m2(panel)
				var panel_holes: Array = panel.get_meta("view_wall_holes", [])
				# 洞顶由幕墙自己写在 meta 上：门洞竖向挖到顶（见 `_build_flow_view_walls()`
				# 里那段"为什么可以挖到顶"），所以这里不能硬编码 `DOOR_CLEAR_HEIGHT_M`。
				var hole_top := float(panel.get_meta("view_wall_hole_top", curtain_top))
				hole_total += panel_holes.size()
				for hole_value in panel_holes:
					var hole: Vector2 = hole_value
					hole_area += (hole.y - hole.x) * (hole_top - curtain_bottom)
				# 每扇门都必须被某个洞盖住「门中心 ± 净宽的一半」。
				var axis_origin := cp.x if along_x else cp.z
				for lane_value in lanes:
					var center: float = axis_origin + float(lane_value)
					var half := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5
					var covered := false
					for hole_value2 in panel_holes:
						var hole2: Vector2 = hole_value2
						if hole2.x <= center - half + 0.02 and hole2.y >= center + half - 0.02:
							covered = true
							break
					if not covered:
						covered_bad += 1
						if covered_bad <= 5:
							print("PLAYABLE DOOR_HOLE_MISS room=%s side=%s lane=%.2f holes=%s" % [
								curtain_room, side, center, str(panel_holes)])
			print("PLAYABLE curtain_door_holes=%d lanes=%d covered_bad=%d" % [
				hole_total, lane_total, covered_bad])
			if hole_total != lane_total:
				_failures.append("幕墙门洞数 %d 与墙体门洞数 %d 不一致（门洞里会是一块黑）" % [
					hole_total, lane_total])
			if covered_bad > 0:
				_failures.append("%d 个门洞没被幕墙切开（门的位置还有黑幕）" % covered_bad)
			var solid_expect := expect_area - hole_area
			print("PLAYABLE curtain_area=%.1f expect=%.1f (full=%.1f hole=%.1f)" % [
				panel_area, solid_expect, expect_area, hole_area])
			if absf(panel_area - solid_expect) > 2.0:
				_failures.append(
					"幕墙实面积 %.1f㎡ 与「整面 %.1f − 门洞 %.1f」= %.1f㎡ 不符" % [
						panel_area, expect_area, hole_area, solid_expect])

		# ⑤ 幕墙**恒显**：镜头跑到房间外也必须继续挡，不许按镜头位置收起。
		#    收起过一次就会看到外面房间（业主截图的正是这个）。
		if _tower.player != null and _tower.player.camera != null:
			var cam := _tower.player.camera
			var saved_cam := cam.global_position
			cam.global_position = Vector3(
				curtain_rect.get_center().x,
				cam.global_position.y,
				curtain_rect.position.y - 2.0)
			_tower._apply_indoor_camera_pose()
			var still_shown := curtain.visible
			print("PLAYABLE curtain_always_on cam_outside_visible=%s" % [
				str(still_shown)])
			if not still_shown:
				_failures.append("镜头在房间外时幕墙被收起了（会看见外面房间）")
			cam.global_position = saved_cam
			_tower._apply_indoor_camera_pose()

	# ④ 像素级漏光测量**放到整个用例最后**做 —— 它会瞬移玩家去贴墙的四个角落。
	#    插在这里会撞进后面「进房 → 等落门」的窗口：落门协程逐帧读玩家位置，
	#    玩家被挪走它就（正确地）放弃落门，于是封门/刷怪整段假红。


## 像素级漏光测量（用例末尾才跑，见 gating 处的注释）。
func _verify_wall_leak(rooms: Dictionary) -> void:
	# headless（`--headless`）用 dummy 渲染器，`get_image()` 会报
	# `ERROR: Parameter "t" is null` 再返回 null —— 不是干净的"没有图像"。
	# 所以先按 DisplayServer 判断，别去碰它。
	if DisplayServer.get_name() == "headless":
		print("PLAYABLE wall_leak=SKIP（headless 无渲染）")
		return
	# 先回到入口房，保证起点一致。
	var start_room := rooms.get("start") as DungeonRoom3D
	if start_room != null:
		_tower._current_room_id = start_room.room_id
		_tower._refresh_flow_view_mask(true)
		await get_tree().process_frame
		await get_tree().process_frame
	# ⚠️ 必须**重新查节点**，不能用早先存下的引用：
	# 上面 `_refresh_flow_view_mask()` 会 remove_child + queue_free 旧幕墙，
	# 而 `is_instance_valid()` 对"已移除但未释放"的节点**仍返回 true** ——
	# 用旧引用会在下一帧撞上 `previously freed`。
	var curtain := _tower.find_child("FlowViewWalls", true, false) as Node3D
	var leak := await _measure_wall_leak(curtain, rooms)
	if leak < 0:
		print("PLAYABLE wall_leak=SKIP（无渲染，headless 下无法取图）")
		return
	# 阈值 30（采样步长 12 ⇒ 全屏约 6400 个采样点）是按**量级**定的，不是凑数：
	#   · 真漏缝（业主报的那条浅带）实测 **5000+** 像素，肉眼一眼可见；
	#   · 剩下的十几个是几何边缘的抗锯齿 + "纯视觉件没有碰撞"造成的误判
	#     （像素显示的是房间自己的构件，但物理射线从它的碰撞空隙穿出去打到墙外地面）。
	# 两者差三个数量级，30 是安全分界。若哪天又出现成片漏光，这个数会直接跳上去。
	print("PLAYABLE wall_leak=%d limit=%d" % [leak, WALL_LEAK_LIMIT])
	if leak > WALL_LEAK_LIMIT:
		_failures.append("%d 个像素能看到房间外的地面（幕墙没盖住，上限 %d）" % [
			leak, WALL_LEAK_LIMIT])


## 像素级漏光测量。
##
## 判据三条同时成立才算漏光：
##   ① 射线（碰撞掩码 1 = 墙/地）终点在**房间足迹之外的地面**上；
##   ② 该像素不是黑的；
##   ③ **关掉幕墙后该像素明显变亮**（说明挡住它的正是幕墙，它确实在幕墙后面）。
##
## ⚠️ ② 的阈值 0.12 不是随手定的：相机被夹到贴墙位置时，幕墙在屏幕上占掉大半，
## 它的**边缘抗锯齿带**会贡献上千个 0.03~0.12 的过渡像素。这些像素肉眼即黑，
## 若按 <0.06 判黑就会整片假红（实测 1847 vs 90）。真漏光像素则是 0.40~0.50。
##
## 第 ③ 条不能省：墙顶剖面（0.28m 宽的一圈水平面）本来就该可见（业主 2026-10-28
## 「顶部横截面可以露出来，这样更有顶视角游戏的感觉」）。那些像素的射线会从墙顶边缘
## 擦过去落在墙外地面，但它显示的是房间自己的墙顶，幕墙开关对它毫无影响。
func _measure_wall_leak(curtain: Node3D, rooms: Dictionary) -> int:
	var room := rooms.get("start") as DungeonRoom3D
	if room == null or _tower.player == null:
		return -1
	if curtain == null or not is_instance_valid(curtain):
		return -1
	var dims := room.get_dimensions()
	var rp := room.global_position
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	# 贴墙的四个站位：整个房间里最容易看到墙外的就是这些位置。
	var spots: Array[Vector3] = [
		Vector3(0.0, 0.0, half_z - 1.5),
		Vector3(0.0, 0.0, -(half_z - 1.5)),
		Vector3(half_x - 1.5, 0.0, 0.0),
		Vector3(-(half_x - 1.5), 0.0, 0.0),
	]
	var saved := _tower.player.global_position
	var total := 0
	for spot in spots:
		var target := rp + spot + Vector3.UP * 0.05
		# 相机是平滑跟随的：连续把站位钉住，等它收敛。
		for i in range(30):
			_tower.player.global_position = target
			_tower.player.velocity = Vector3.ZERO
			await get_tree().physics_frame
		for i in range(3):
			await get_tree().process_frame
		# **必须把"当前房间"锁回被测房间再重建幕墙**：
		# 上面把玩家瞬移到房间边缘时，房间追踪可能把 `_current_room_id` 换掉，
		# `_refresh_flow_view_mask()` 于是按**另一间房**建幕墙 —— 那样量的不是这间房。
		# 这是测试要隔离的变量，不是绕过判定：被测场景就是"玩家站在这间房里"。
		_tower._current_room_id = room.room_id
		_tower._refresh_flow_view_mask(true)
		_tower.player.global_position = target
		_tower.player.velocity = Vector3.ZERO
		for i in range(2):
			await get_tree().process_frame
		var cam := _tower.player.camera
		var on_img := get_viewport().get_texture().get_image()
		if on_img == null:
			# 没有渲染（headless）。调用方已经按 DisplayServer 提前跳过，这里是兜底。
			_tower.player.global_position = saved
			return -1
		# ⚠️ 幕墙引用必须**在这里现查**，不能提前拿：
		# 上面把玩家瞬移到房间另一侧会触发换房 → `_refresh_flow_view_mask()` 重建幕墙 →
		# 旧节点被 remove_child + queue_free。`is_instance_valid()` 对"已移除未释放"的
		# 节点仍返回 true，所以在旧引用上写 `.visible` 会直接 `previously freed`（实测必现）。
		var curtain_now := _tower.find_child("FlowViewWalls", true, false) as Node3D
		if curtain_now == null:
			continue
		curtain_now.visible = false
		for i in range(3):
			await get_tree().process_frame
		var off_img := get_viewport().get_texture().get_image()
		# 恢复前再确认一次：这几帧里可能又重建过。
		curtain_now = _tower.find_child("FlowViewWalls", true, false) as Node3D
		if curtain_now != null:
			curtain_now.visible = true
		for i in range(2):
			await get_tree().process_frame
		if off_img != null:
			var spot_leak := _count_leak_pixels(cam, on_img, off_img, rp, half_x, half_z)
			# 只在明显异常时打印：正常每站位有 10~40 个边缘混合像素，逐条打会淹掉日志。
			if spot_leak > 200:
				print("PLAYABLE leak_spot=%s count=%d curtain_room=%s" % [
					str(spot.snapped(Vector3.ONE * 0.1)), spot_leak,
					str(curtain_now.get_meta("view_wall_room_id", "?"))])
			total += spot_leak
	_tower.player.global_position = saved
	var restore := _tower.find_child("FlowViewWalls", true, false) as Node3D
	if restore != null:
		restore.visible = true
	return total


## 单侧幕墙的三角形面积合计（㎡）。门洞判据用它 —— 只看节点/meta 计数是自证，
## 面积对不上就说明网格没切（门洞里还是一片黑）。
func _panel_area_m2(panel: MeshInstance3D) -> float:
	var mesh := panel.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var area := 0.0
	var index := 0
	while index + 2 < vertices.size():
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		area += 0.5 * (b - a).cross(c - a).length()
		index += 3
	return area


func _count_leak_pixels(
	cam: Camera3D, on_img: Image, off_img: Image,
	rp: Vector3, half_x: float, half_z: float
) -> int:
	var viewport_size := on_img.get_size()
	var space := cam.get_world_3d().direct_space_state
	var origin := cam.global_position
	var exclude: Array[RID] = []
	if _tower.player is CollisionObject3D:
		exclude.append((_tower.player as CollisionObject3D).get_rid())
	var leak := 0
	for y in range(0, viewport_size.y, 12):
		for x in range(0, viewport_size.x, 12):
			var dir := cam.project_ray_normal(Vector2(x, y))
			if dir.y >= -0.02:
				continue
			var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 400.0)
			query.collision_mask = 1
			query.exclude = exclude
			query.collide_with_areas = false
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var point: Vector3 = hit["position"]
			if point.y > 0.35:
				continue
			if absf(point.x - rp.x) <= half_x + 0.30 					and absf(point.z - rp.z) <= half_z + 0.30:
				continue
			var on_px := on_img.get_pixel(x, y)
			var on_lum := maxf(on_px.r, maxf(on_px.g, on_px.b))
			# "视觉上算黑"的阈值 = 0.12（≈ 30/255）。
			#
			# 取值依据是**实测两端**，不是凑数：
			#   · 幕墙面本体：PNG 采样是纯 `(0,0,0)`（1600×1000 图上占 80% 采样点）；
			#   · 幕墙**边缘**：与亮面（地板/墙顶剖面）交界的抗锯齿过渡带，
			#     实测稳定落在 0.027~0.12。相机贴墙（夹取生效）时幕墙边缘在屏幕上很长，
			#     这类像素会到一千多个 —— 它们肉眼看就是黑的，判成漏光会整片假红；
			#   · 真漏光：像素显示的是**墙外地面**，亮度 0.40~0.50（与房间地面同档）。
			# 0.12 与 0.40 差 3 倍以上，两头都留足余量。
			if on_lum <= 0.12:
				continue
			var off_px := off_img.get_pixel(x, y)
			var off_lum := maxf(off_px.r, maxf(off_px.g, off_px.b))
			# 关掉幕墙后必须明显变亮，才说明"挡住它的是幕墙"（排除墙顶剖面，见函数注释）。
			if off_lum - on_lum < 0.05:
				continue
			if leak < 4:
				print("PLAYABLE_LEAKPX px=(%d,%d) hit=(%.2f,%.2f,%.2f) on=%.3f off=%.3f" % [
					x, y, point.x, point.y, point.z, on_lum, off_lum])
			leak += 1
	return leak


# ── B 房门规则 ────────────────────────────────────────────────────────────
func _verify_door_rules(rooms: Dictionary) -> void:
	if not bool(_tower.get("_flow_rules_active")):
		_failures.append("_flow_rules_active 未置真：flow 关卡规则没生效")
	var key_locked := 0
	var fate_gated := 0
	var combat_rooms := 0
	var peaceful_rooms := 0
	var leaf_by_room := {}
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		var leaves := 0
		for child in room.find_children("*", "Node3D", true, false):
			if child is RoomDoor3D:
				leaves += 1
		leaf_by_room[str(room_key)] = leaves
		if room.authored_layout_peaceful:
			peaceful_rooms += 1
		else:
			combat_rooms += 1
		for direction_value in (room.door_targets as Dictionary).keys():
			var policy: Dictionary = (room.door_policies as Dictionary).get(
				str(direction_value), {}) as Dictionary
			if bool(policy.get("requires_key", false)):
				key_locked += 1
			if bool(policy.get("triggers_fate", false)):
				fate_gated += 1
	print("PLAYABLE combat_rooms=%d peaceful_rooms=%d" % [combat_rooms, peaceful_rooms])
	print("PLAYABLE key_locked=%d fate_gated=%d" % [key_locked, fate_gated])

	# 门扇按**边**判：共享边只由一端持扇，两端合计 ≥1 才有门可关。
	var edge_without_leaf := 0
	var seen_edges := {}
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		for direction_value in (room.door_targets as Dictionary).keys():
			var peer_id := str((room.door_targets as Dictionary)[direction_value])
			var pair_key := "%s|%s" % [str(room_key), peer_id] if str(room_key) < peer_id \
				else "%s|%s" % [peer_id, str(room_key)]
			if seen_edges.has(pair_key):
				continue
			seen_edges[pair_key] = true
			var peer := rooms.get(peer_id) as DungeonRoom3D
			var total := int(leaf_by_room.get(str(room_key), 0)) + (
				int(leaf_by_room.get(peer_id, 0)) if peer != null else 0)
			if total == 0:
				edge_without_leaf += 1
				if edge_without_leaf <= 5:
					print("PLAYABLE NO_LEAF %s <-> %s" % [str(room_key), peer_id])
	print("PLAYABLE edges_without_leaf=%d/%d" % [edge_without_leaf, seen_edges.size()])
	if edge_without_leaf > 0:
		_failures.append("%d 条连通边两端都没有门扇（无法关门）" % edge_without_leaf)
	if key_locked > 0:
		_failures.append("%d 扇门要求房间钥匙（业主：本关不要钥匙）" % key_locked)
	if fate_gated > 0:
		_failures.append("%d 扇门会弹命运卡（本关不走远征01 的规则）" % fate_gated)

	# —— 入口安全房的「[E] 退出战局」门 ——
	#
	# 这扇门不挂任何拓扑边（`door_targets` 该侧为空串），所以在 flow 关卡上
	# 只有"补一条无目标端口"才会有门扇。缺了它的表现是：按门毫无反应，
	# 玩家进图后只能往前打，不能主动弃局。
	var start_room := rooms.get("start") as DungeonRoom3D
	var retreat_side := ""
	if start_room != null:
		for direction_value in (start_room.door_targets as Dictionary).keys():
			if str((start_room.door_targets as Dictionary)[direction_value]).is_empty():
				retreat_side = str(direction_value)
				break
	# 交互绑定是**拉取式**的：`_get_configured_base_door_bindings()` 在被收集时
	# 才给门设 `[E] 退出战局` 的提示覆盖。这里主动拉一次，验的就是玩家会看到的那条链。
	var retreat_door: RoomDoor3D = null
	for binding in _tower._get_configured_base_door_bindings():
		if str(binding.get("mode", "")) == "expedition_retreat":
			retreat_door = binding.get("door") as RoomDoor3D
			break
	var retreat_prompt := retreat_door.get_interaction_prompt_text() if retreat_door != null else ""
	print("PLAYABLE retreat_door side=%s has_leaf=%s prompt=%s" % [
		retreat_side if not retreat_side.is_empty() else "-",
		str(retreat_door != null), retreat_prompt])
	if retreat_side.is_empty():
		_failures.append("入口安全房缺少封闭抵达门（door_targets 无空目标侧）")
	if retreat_door == null:
		_failures.append("入口安全房的退出门没有门扇（按了没反应）")
	elif not retreat_prompt.contains("退出战局"):
		_failures.append("退出门的提示不是「退出战局」：%s" % retreat_prompt)

	# —— 退出门内侧的 EXIT 霓虹灯标牌（ENV-BATTLE-EXIT-NEON-SIGN）——
	#
	# 远征01/02 的入口房走静态布局 TSCN，标牌在那条分支里单独补过；
	# 远征03 走**程序化壳体**，原先三条建壳路径都没有摆这块牌
	# （业主 2026-10-29 指着入口安全屋的门报「没有摆放退出关卡的功能」）。
	#
	# 判据不能只看"节点在不在"：牌摆错位置一样等于没有 —— 它必须
	# ① 是唯一一块（幂等）、② 声明 visual_only（不得在走行面造隐形台阶）、
	# ③ 平铺在门内侧地面（发光面朝上、底边贴走行面）、
	# ④ 切向中心对齐退出门扇，且比门更靠房内。
	if start_room != null and not retreat_side.is_empty():
		var sign_nodes: Array[Node] = []
		for child in start_room.get_children():
			if str(child.name) == "SafeRoomExitSign":
				sign_nodes.append(child)
		print("PLAYABLE exit_sign count=%d" % sign_nodes.size())
		if sign_nodes.size() != 1:
			_failures.append("入口安全房的 EXIT 灯牌节点数应为 1，实得 %d" % sign_nodes.size())
		else:
			var sign := sign_nodes[0] as Node3D
			if str(sign.get_meta("exit_sign_direction", "")) != retreat_side:
				_failures.append("EXIT 灯牌方位(%s) 与退出门(%s) 不一致" % [
					str(sign.get_meta("exit_sign_direction", "")), retreat_side])
			if not bool(sign.get_meta("visual_only", false)):
				_failures.append("EXIT 灯牌未声明 visual_only")
			if not sign.find_children("*", "StaticBody3D", true, false).is_empty():
				_failures.append("EXIT 灯牌带 StaticBody3D（会在走行面制造隐形台阶）")
			var facing := -(sign.global_transform.basis.z).normalized()
			if absf(facing.y - 1.0) > 0.02:
				_failures.append("EXIT 灯牌发光面未朝上：%s" % str(facing))
			var sign_min := Vector3.INF
			var sign_max := -Vector3.INF
			var sign_meshes := 0
			for value in sign.find_children("*", "MeshInstance3D", true, false):
				var mi := value as MeshInstance3D
				if mi == null or mi.mesh == null:
					continue
				sign_meshes += 1
				var bb := mi.mesh.get_aabb()
				for corner in range(8):
					var world: Vector3 = sign.global_transform * bb.get_endpoint(corner)
					sign_min = sign_min.min(world)
					sign_max = sign_max.max(world)
			if sign_meshes == 0:
				_failures.append("EXIT 灯牌内没有网格")
			else:
				var room_origin := start_room.global_position
				var normal := start_room.call("_direction_normal", retreat_side) as Vector3
				var normal_along_x := absf(normal.x) > 0.99
				var walk_y := float(start_room.get_meta("walk_surface_y_m", 0.0))
				var center_local := (sign_min + sign_max) * 0.5 - room_origin
				var bottom_y := sign_min.y - room_origin.y
				var door_local := (
					retreat_door.global_position - room_origin
					if retreat_door != null else Vector3.ZERO
				)
				var tangential_sign := center_local.z if normal_along_x else center_local.x
				var tangential_door := door_local.z if normal_along_x else door_local.x
				var radial_sign := center_local.x if normal_along_x else center_local.z
				var radial_door := door_local.x if normal_along_x else door_local.z
				print("PLAYABLE exit_sign tangential sign=%.2f door=%.2f  radial sign=%.2f door=%.2f  bottom_y=%.3f" % [
					tangential_sign, tangential_door, radial_sign, radial_door, bottom_y])
				if absf(bottom_y - walk_y) > 0.02:
					_failures.append("EXIT 灯牌未贴走行面：底面 y=%.3f，走行面 %.3f" % [bottom_y, walk_y])
				if absf(tangential_sign - tangential_door) > 0.35:
					_failures.append("EXIT 灯牌切向与门扇错开 %.3f m" % absf(tangential_sign - tangential_door))
				# 沿门法向（normal 指向门外）：牌的投影必须比门更靠房内。
				var sign_along_normal := center_local.dot(normal)
				var door_along_normal := door_local.dot(normal)
				if sign_along_normal >= door_along_normal:
					_failures.append("EXIT 灯牌未落在门内侧：牌法向投影 %.3f ≥ 门 %.3f" % [
						sign_along_normal, door_along_normal])

	# —— 门扇是**双扇对开**（业主 2026-10-28：「这个门，帮我做成左右打开的」）——
	#
	# 只验"有没有两扇"不够：真正要验的是**开门时两扇朝相反方向让开**。
	# 判据是左右行程的符号相反、且各自行程 ≥ 半个门洞（否则门还挡着通道）。
	var slide_doors := 0
	var wrong_style := 0
	var missing_second_panel := 0
	var wrong_geometry := 0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		for child in room.find_children("*", "Node3D", true, false):
			if not (child is RoomDoor3D):
				continue
			var door := child as RoomDoor3D
			if door.get_opening_style() != RoomDoor3D.OPENING_STYLE_SLIDE:
				wrong_style += 1
				continue
			slide_doors += 1
			var left_panel := door.get_node_or_null("DoorPanel") as Node3D
			var right_panel := door.get_node_or_null("DoorPanelRight") as Node3D
			if left_panel == null or right_panel == null:
				missing_second_panel += 1
				continue
			# 记录原状并在测完恢复：这一段的门里有「封闭抵达门」（退局气闸），
			# 它必须保持关闭 —— 开着会让 `_get_configured_base_door_bindings()`
			# 认不出它（那一段只收关着的门），后面的退出门断言就会假红。
			var was_open := door.is_open
			door.set_open(false, true)
			var closed_left := left_panel.position.x
			var closed_right := right_panel.position.x
			door.set_open(true, true)
			var travelled_left := left_panel.position.x - closed_left
			var travelled_right := right_panel.position.x - closed_right
			var clear_width := float(door.get_snapshot().get("clear_width_m", 2.2))
			if (
				travelled_left > -clear_width * 0.45
				or travelled_right < clear_width * 0.45
			):
				wrong_geometry += 1
				if wrong_geometry <= 3:
					print("PLAYABLE SLIDE_BAD %s L%+.2f R%+.2f (门洞 %.2f)" % [
						str(door.name), travelled_left, travelled_right, clear_width])
			door.set_open(was_open, true)
	print("PLAYABLE slide_doors=%d wrong_style=%d missing_second=%d bad_geometry=%d" % [
		slide_doors, wrong_style, missing_second_panel, wrong_geometry])
	if slide_doors == 0:
		_failures.append("没有任何门是双扇对开（slide）")
	if wrong_style > 0:
		_failures.append("%d 扇门仍走升降开合（应为 slide）" % wrong_style)
	if missing_second_panel > 0:
		_failures.append("%d 扇 slide 门缺少第二扇门板（DoorPanelRight）" % missing_second_panel)
	if wrong_geometry > 0:
		_failures.append("%d 扇 slide 门的左右行程不对（未向两侧让开）" % wrong_geometry)

	# —— 门板厚度必须**小于墙厚**，否则开门后凸出墙面 ——
	#
	# 业主 2026-10-28 报过「门看起来贴在墙外面」。根因是入口房原本用基地 99F 的
	# 滑升门体（可视厚度 0.88m），滑到门洞两侧时凸出 0.28m 墙厚 0.31m，露出一整块门体。
	# 判据：门板可视包络在**门法线方向**的厚度必须小于墙厚，才有"滑进墙里"的效果。
	const WALL_THICKNESS_M := 0.28
	var thick_doors := 0
	var worst := ""
	var worst_thick := 0.0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		for child in room.find_children("*", "Node3D", true, false):
			if not (child is RoomDoor3D):
				continue
			var door := child as RoomDoor3D
			if door.get_opening_style() != RoomDoor3D.OPENING_STYLE_SLIDE:
				continue
			var panel := door.get_node_or_null("DoorPanel") as Node3D
			if panel == null:
				continue
			var vis := panel.get_node_or_null("ImportedDoorVisual") as Node3D
			if vis == null:
				continue
			# 门局部 z 是门法线方向（墙厚方向）
			var union := AABB()
			var first := true
			for node in vis.find_children("*", "GeometryInstance3D", true, false):
				var gi := node as GeometryInstance3D
				if not (gi is MeshInstance3D):
					continue
				var world := gi.global_transform * (gi as MeshInstance3D).get_aabb()
				union = world if first else union.merge(world)
				first = false
			if first:
				continue
			# 换算到门的局部法线方向厚度
			var basis := door.global_transform.basis.orthonormalized()
			var extent := absf(basis.z.x) * union.size.x \
				+ absf(basis.z.y) * union.size.y + absf(basis.z.z) * union.size.z
			if extent > worst_thick:
				worst_thick = extent
				worst = str(door.name)
			if extent >= WALL_THICKNESS_M:
				thick_doors += 1
	print("PLAYABLE slide_panel_thickness worst=%.3f(%s) too_thick=%d wall=%.2f" % [
		worst_thick, worst, thick_doors, WALL_THICKNESS_M])
	if thick_doors > 0:
		_failures.append(
			"%d 扇 slide 门板厚 ≥ 墙厚 %.2fm（开门后会凸出墙面）" % [
				thick_doors, WALL_THICKNESS_M])
	# —— 开门后门板必须**留在视野里**（业主 2026-10-30）——
	#
	# 报单：「门应该是可打开和不可打开的状态，而不是直接消失」。
	# 病根：门板只沿 x 滑出，整块退进 0.28m 厚的墙体内，被深度测试挡在墙后。
	# 判据：开到位时门板沿门法线的偏移 |panel_z| 必须 ≥ 半个门板厚 ——
	# 低于这个值就意味着门板有一半以上埋在墙体里，画面上读不出"这里有扇门"。
	const MIN_VISIBLE_PANEL_Z := 0.09
	var invisible_panels := 0
	var min_panel_z := 999.0
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		if room == null:
			continue
		for child in room.find_children("*", "Node3D", true, false):
			if not (child is RoomDoor3D):
				continue
			var door := child as RoomDoor3D
			if door.get_opening_style() != RoomDoor3D.OPENING_STYLE_SLIDE:
				continue
			var was_open := door.is_open
			door.set_open(true, true)
			var panel_z := absf(float((door.get_snapshot() as Dictionary).get("panel_z", 0.0)))
			door.set_open(was_open, true)
			min_panel_z = minf(min_panel_z, panel_z)
			if panel_z < MIN_VISIBLE_PANEL_Z:
				invisible_panels += 1
				if invisible_panels <= 3:
					print("PLAYABLE SLIDE_HIDDEN %s panel_z=%.3f" % [
						str(door.name), panel_z])
	print("PLAYABLE slide_park min_panel_z=%.3f hidden=%d limit=%.2f" % [
		min_panel_z, invisible_panels, MIN_VISIBLE_PANEL_Z])
	if invisible_panels > 0:
		_failures.append(
			"%d 扇 slide 门开到位后门板埋进墙里（画面上等于消失）" % invisible_panels)
	# "有门扇 + 有提示"仍不等于"按 E 有用"：交互候选是**按距离**收集的，
	# 门在房里但玩家站太远就收不到。这里真的把玩家挪到门口、走完整条交互链。
	if retreat_door != null:
		var saved_position := _tower.player.global_position
		# 站到门**内侧 1.2m**，而不是门中心：门中心在房间边界上，物理一步就会把
		# 玩家挤出房间，位置权威判定随即把他挪到最近房间中心 —— 那样测的不是门，
		# 是"人被挪走了"。1.2m 在交互距离内、也稳稳站在房内。
		var inward := (start_room.global_position - retreat_door.global_position)
		inward.y = 0.0
		inward = inward.normalized()
		_tower.player.global_position = retreat_door.global_position + inward * 1.2 + Vector3.UP * 0.05
		_tower.player.velocity = Vector3.ZERO
		# **不 await 物理帧**：这边一 await，物理会把刚放下的玩家挪回去
		# （位于边界附近的临时传送会被位置权威纠正），于是测的根本不是门。
		# 交互候选是纯距离判定，用刚设置的位置查一次即可。
		var candidate := _tower.get_interaction_candidate(_tower.player)
		print("PLAYABLE retreat_probe dist=%.2f current_room=%s" % [
			_tower.player.global_position.distance_to(retreat_door.global_position),
			str(_tower._current_room_id)])
		var mode := str(candidate.get("mode", ""))
		var opened := false
		if mode == "configured_expedition_retreat":
			opened = _tower.perform_interaction(_tower.player, candidate)
		await get_tree().process_frame
		var overlay := _tower.get_node_or_null("HUD/ExpeditionExitWarning") as Control
		print("PLAYABLE retreat_interact mode=%s opened=%s overlay=%s" % [
			mode, str(opened), str(overlay != null)])
		if mode != "configured_expedition_retreat":
			_failures.append("退出门没有产生 expedition_retreat 交互候选（mode=%s）" % mode)
		if not opened:
			_failures.append("按 E 没有打开退出确认")
		if overlay == null:
			_failures.append("按 E 后没有弹出 ExpeditionExitWarning")
		else:
			# 取消掉，别把后面几段拖进"行动已结束"的状态。
			for button_value in overlay.find_children("*", "Button", true, false):
				var button := button_value as Button
				if str(button.name) == "CancelButton":
					button.pressed.emit()
					break
			await get_tree().process_frame
		_tower.player.global_position = saved_position
		await get_tree().physics_frame


# ── C 封门 / 开门 ─────────────────────────────────────────────────────────
## 进房 → 落门 → 静默 → 出怪 → 清房开门。整套时序必须**一次连续观察**。
##
## 为什么不能"先探一间、再量一次"：落门协程是按时序跑的，**探查本身就会消耗掉
## 那段时序**。第一版就是先花 900ms 确认这间房真的会刷怪，再去量"进房瞬间是否
## 未封锁" —— 可那时门早就落完了，于是报"进房瞬间就落门了"的假红。
## 正确做法：把探查与测量合成同一轮，进房那一刻就开始记时，边等边判。
func _verify_seal_cycle(rooms: Dictionary) -> void:
	var first_cleared_room := ""
	var sealed_immediately := false
	var opened_immediately := 0
	var sealed := false
	var seal_delay_ms := 0
	var opened_after := 0
	var alive_at_seal := 0
	var alive_after := 0
	var target: DungeonRoom3D = null
	var room_center := Vector3.ZERO

	for room_key in rooms.keys():
		var candidate := rooms[room_key] as DungeonRoom3D
		if candidate == null or candidate.authored_layout_peaceful:
			continue
		if candidate.room_type != "COMBAT":
			continue
		if (candidate.door_targets as Dictionary).is_empty():
			continue
		# ⚠️ 必须还原成"首次进入"的状态：这几间房可能已被**存档检查点**恢复过
		# （`_restore_runtime_world_state` 把 `_spawned_rooms` / `cleared` 直接写回），
		# 那样进房只会走 `_repair_room_progress` 分支，压根不刷怪，测试必然假红。
		# 这不是测试专用技巧 —— 它正是"玩家第一次推开这扇门"时运行时的真实初始状态。
		_tower._spawned_rooms.erase(candidate.room_id)
		_tower._alive_by_room.erase(candidate.room_id)
		_tower._room_wave_queues.erase(candidate.room_id)
		# 波次账也要清：`_repair_hostile_room_progress()` 见到「建过波次但没有待发队列」
		# 就直接判已清 —— 那是给"终波已处理"用的兜底，用在首次进房会把战斗抹掉。
		_tower._room_wave_totals.erase(candidate.room_id)
		_tower._room_wave_numbers.erase(candidate.room_id)
		# 还有**房间运行时快照**：流送切回 ACTIVE 时 `_restore_room_runtime_state()` 会把
		# 上次离开时捕获的 `cleared` 原样写回。存档恢复出来的"已清"就是这么回来的。
		_tower._segment_runtime_state.erase(candidate.room_id)
		candidate.cleared = false
		room_center = candidate.global_position + Vector3(0.0, 0.05, 0.0)
		_tower.player.global_position = room_center
		_tower.player.velocity = Vector3.ZERO
		# —— 进房那一瞬间：**必须还没落门**（Gungeon 的"先走两步、门才落"）。
		#    立刻在这里读，晚一帧就会读到已经落上的状态。
		_tower._on_room_entered(candidate)
		var immediate_seal := bool(_tower._sealed_rooms.has(candidate.room_id))
		var immediate_open := _open_leaf_count(candidate)
		# 落门协程逐帧读玩家位置。测试里的人是瞬移进房的，物理会把"边界附近的瞬移"
		# 纠正掉（实测会把人挪到别的房间），所以每帧把站位钉回房内 ——
		# 它模拟的是「玩家走进去并站在屋里」这一事实，不是绕过判定。
		var wait_start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - wait_start < 1500:
			if bool(_tower._sealed_rooms.has(candidate.room_id)) or candidate.cleared:
				break
			_tower.player.global_position = room_center
			_tower.player.velocity = Vector3.ZERO
			await get_tree().process_frame
		var delay := Time.get_ticks_msec() - wait_start
		print("PLAYABLE_CAND %-20s cleared=%s sealed=%s open_now=%d" % [
			candidate.room_id, str(candidate.cleared),
			str(bool(_tower._sealed_rooms.has(candidate.room_id))), immediate_open])
		if candidate.cleared and not bool(_tower._sealed_rooms.has(candidate.room_id)):
			# 空房 / 未指派首领的房被**正确**放行（落门那一步发现没怪就开门）。
			# 这不能拿来测封门 —— 换下一间。
			first_cleared_room = candidate.room_id
			continue
		# 这间真的进入战斗时序了：本次观察就是正式测量结果。
		target = candidate
		sealed_immediately = immediate_seal
		opened_immediately = immediate_open
		sealed = bool(_tower._sealed_rooms.has(candidate.room_id))
		seal_delay_ms = delay
		opened_after = _open_leaf_count(candidate)
		# 门落之后还要有一段静默，敌人在这之后才出场（Gungeon 的落锁反馈窗口）。
		# 这一段同时验两件事：① 落门时**还没有**怪；② 静默结束后怪真的来了。
		alive_at_seal = int(_tower._alive_by_room.get(candidate.room_id, 0))
		var spawn_wait := Time.get_ticks_msec()
		while Time.get_ticks_msec() - spawn_wait < 2500:
			if int(_tower._alive_by_room.get(candidate.room_id, 0)) > 0:
				break
			_tower.player.global_position = room_center
			await get_tree().process_frame
		alive_after = int(_tower._alive_by_room.get(candidate.room_id, 0))
		break

	if target == null:
		_failures.append(
			"找不到会刷怪的内容房（COMBAT 房全部被正确放行%s）" % (
				"，最后一间是 %s" % first_cleared_room if not first_cleared_room.is_empty() else ""))
		return

	print("PLAYABLE seal room=%s immediate_sealed=%s opened_now=%d sealed=%s delay_ms=%d opened_after=%d alive_at_seal=%d alive_after=%d" % [
		target.room_id, str(sealed_immediately), opened_immediately,
		str(sealed), seal_delay_ms, opened_after, alive_at_seal, alive_after])
	if alive_at_seal > 0:
		_failures.append("落门时敌人就已经在场（缺少关门后的静默：%s）" % target.room_id)
	if alive_after <= 0:
		_failures.append("落门之后没有刷怪（%s）" % target.room_id)
	if sealed_immediately:
		_failures.append("进房瞬间就落门了（缺少落门延迟，会把玩家夹在门里）")
	if not sealed:
		_failures.append("进内容房后没有封门（%s）" % target.room_id)
	if opened_after > 0:
		_dump_open_leaves(target)
		_failures.append("封门后仍有 %d 扇门是开的（%s）" % [opened_after, target.room_id])

	# 清房：门恢复**可开启**（不是替玩家推开）。业主 2026-10-30：
	# 「可开启状态，人走近了会自动打开，然后再关闭。」
	_tower._mark_room_cleared(target, false)
	await get_tree().process_frame
	var still_sealed := bool(_tower._sealed_rooms.has(target.room_id))
	var openable_end := _openable_leaf_count(target)
	var opened_end := _open_leaf_count(target)
	print("PLAYABLE unseal room=%s sealed=%s openable_leaves=%d open_leaves=%d" % [
		target.room_id, str(still_sealed), openable_end, opened_end])
	if still_sealed:
		_failures.append("清房后仍然封锁（%s）" % target.room_id)
	if openable_end == 0:
		_failures.append("清房后门没有恢复可开启（%s）" % target.room_id)
	if opened_end != 0:
		_failures.append(
			"清房后门被直接推开（%d 扇）—— 可开启态应当关门待走近（%s）" % [
				opened_end, target.room_id])

	# —— 可开启 → 走近自动开 → 走远自动关 ——
	await _verify_proximity_cycle(target)


## 「可开启」的完整闭环：走近自动开、走远自动关。
##
## 判据走**真实感应**（把玩家真的放到门边 / 放回房心，让 `RoomDoor3D._process`
## 自己判），不手工 `set_open` —— 手工开门验的是门，不是业主说的那条手感。
func _verify_proximity_cycle(room: DungeonRoom3D) -> void:
	var pick := _first_connected_leaf(room)
	var door := pick.get("door") as RoomDoor3D
	if door == null:
		_failures.append("找不到可测的连通门（%s）" % room.room_id)
		return
	var room_center := room.global_position + Vector3(0.0, 0.05, 0.0)
	var inward := room_center - door.global_position
	inward.y = 0.0
	inward = inward.normalized()
	# 门边（距门 1.5m < 3.6m 开阈）：必须自动开。
	var near := door.global_position + inward * 1.5 + Vector3.UP * 0.05
	await _hold_player_at(near, 30)
	var opened_near := door.is_open
	# 房心（距门 > 4.4m 关阈 + 0.45s 延迟）：必须自动关。
	var away_distance := room_center.distance_to(door.global_position)
	await _hold_player_at(room_center, 90)
	var still_open := door.is_open
	print("PLAYABLE proximity room=%s door=%s dir=%s away_m=%.2f open_near=%s still_open_away=%s" % [
		room.room_id, str(door.name), str(door.direction), away_distance,
		str(opened_near), str(still_open)])
	if not opened_near:
		_failures.append("走近可开启门没有自动打开（%s）" % str(door.name))
	if away_distance > RoomDoor3D.PROXIMITY_CLOSE_DISTANCE_M and still_open:
		_failures.append("走远后门没有自动关上（%s）" % str(door.name))


## 把玩家钉在一个位置上跑 `frames` 帧（门态由调用方读）。
##
## 必须逐帧钉：物理会把"边界附近的瞬移"纠正回房间中心（位置权威），
## 不钉的话第一帧人就飞回去了，测到的永远是"走远了"。
func _hold_player_at(position: Vector3, frames: int) -> void:
	for i in range(frames):
		_tower.player.global_position = position
		_tower.player.velocity = Vector3.ZERO
		await get_tree().process_frame


## 本房（或共享边对端）第一个通向真实房间的门。
func _first_connected_leaf(room: DungeonRoom3D) -> Dictionary:
	for direction_value in (room.door_targets as Dictionary).keys():
		var peer_id := str((room.door_targets as Dictionary)[direction_value])
		if peer_id.is_empty():
			continue
		var door := room.get_door_node(str(direction_value))
		if door == null:
			var peer := _tower._room_by_id.get(peer_id) as DungeonRoom3D
			if peer != null and is_instance_valid(peer):
				door = peer.get_door_node_towards(room.room_id)
		if door != null:
			return {"door": door, "peer_id": peer_id}
	return {}


## 本房**可开启的**门扇数（共享边的门扇在对端，两边都数）。
func _openable_leaf_count(room: DungeonRoom3D) -> int:
	var count := 0
	for child in room.find_children("*", "Node3D", true, false):
		if child is RoomDoor3D and (child as RoomDoor3D).openable:
			count += 1
	for direction_value in (room.door_targets as Dictionary).keys():
		var peer_id := str((room.door_targets as Dictionary)[direction_value])
		var peer := _tower._room_by_id.get(peer_id) as DungeonRoom3D
		if peer == null or not is_instance_valid(peer):
			continue
		var peer_door := peer.get_door_node_towards(room.room_id)
		if peer_door != null and peer_door.openable:
			count += 1
	return count


func _dump_open_leaves(room: DungeonRoom3D) -> void:
	for child in room.find_children("*", "Node3D", true, false):
		if child is RoomDoor3D:
			var leaf := child as RoomDoor3D
			if leaf.is_open:
				print("PLAYABLE OPEN_LEAF 本房 dir=%s target=%s name=%s" % [
					leaf.direction, str(leaf.target_room_id), str(leaf.name)])
	for direction_value in (room.door_targets as Dictionary).keys():
		var peer_id := str((room.door_targets as Dictionary)[direction_value])
		var peer := _tower._room_by_id.get(peer_id) as DungeonRoom3D
		if peer == null or not is_instance_valid(peer):
			continue
		var peer_door := peer.get_door_node_towards(room.room_id)
		if peer_door != null and peer_door.is_open:
			print("PLAYABLE OPEN_LEAF 对端 %s dir=%s name=%s" % [
				peer_id, peer_door.direction, str(peer_door.name)])


## 本房**开着的**门扇数（共享边的门扇在对端，两边都数）。
func _open_leaf_count(room: DungeonRoom3D) -> int:
	var count := 0
	for child in room.find_children("*", "Node3D", true, false):
		if child is RoomDoor3D and (child as RoomDoor3D).is_open:
			count += 1
	for direction_value in (room.door_targets as Dictionary).keys():
		var peer_id := str((room.door_targets as Dictionary)[direction_value])
		var peer := _tower._room_by_id.get(peer_id) as DungeonRoom3D
		if peer == null or not is_instance_valid(peer):
			continue
		var peer_door := peer.get_door_node_towards(room.room_id)
		if peer_door != null and peer_door.is_open:
			count += 1
	return count


func _reachable_from(edges: Array[Dictionary], start: String) -> Dictionary:
	var adjacency := {}
	for edge in edges:
		if bool(edge["blocked"]):
			continue
		var a := str(edge["a"])
		var b := str(edge["b"])
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor in adjacency.get(current, []) as Array:
			var key := str(neighbor)
			if seen.has(key):
				continue
			seen[key] = true
			queue.append(key)
	return seen


func _finish() -> void:
	if _failures.is_empty():
		print("PLAYABLE_OK")
	else:
		for message in _failures:
			print("PLAYABLE_FAIL: %s" % message)
		print("PLAYABLE_FAILED count=%d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
