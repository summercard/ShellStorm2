extends Node
## 远征01 room_08 局内自动贩卖机探针（2026-11-15）。
##
## 业主：「中间地方增加一个自动贩卖机，局内用的，参考远征03」。这一批改的是
## 「房间中部多一台可交易的贩卖机」，而这类需求最容易出现两种静默失败：
##   ① 锚点写了没人认领 —— 进房什么也没有，日志一行不报；
##   ② 认领了但摆进了墙里 / 摆进没有地砖的凹口 —— 模型在那，玩家走不到也点不到。
##
## 所以这里量的是**可玩事实**，不读配置：
##   ① 房间只有一台 merchant 服务点，且来自作者锚点；
##   ② 它落在真地砖上、离房心在合理距离内（=「中部」）；
##   ③ 视觉真的是贩卖机（不是程序化占位盒），实体碰撞挡人、交互盒在正面；
##   ④ 从门上进来能走到它正前方（0.45m 半径的连通性洪泛，不是直线距离）；
##   ⑤ 交互真的能开商人页（走 ServiceStation3D → 房间 → Dungeon3D 整条链）。
##
## 用法：godot --headless --path . res://tools/_exp01_room08_vending_probe.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const ROOM_ID := "room_08"
const WAIT_LIMIT_S := 60.0
## 连通性洪泛的格宽。
const WALK_GRID_M := 0.75
## 「中部」判据：服务点离房心的平面距离上限。
const MIDDLE_RADIUS_M := 7.0

var _failures: Array[String] = []
var _notes: Array[String] = []
var _room: DungeonRoom3D = null
var _tower: TowerDescent3D = null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
	print("%s %s" % ["  OK  " if condition else " FAIL ", message])


func _ready() -> void:
	print("=== EXP01_ROOM08_VENDING_PROBE ===")
	var packed := load(EXPEDITION_SCENE) as PackedScene
	_check(packed != null, "远征01场景必须可加载")
	_tower = packed.instantiate() as TowerDescent3D
	_check(_tower != null, "远征01场景根必须是 TowerDescent3D")
	if _tower == null:
		_finish()
		return
	# **必须走真实流程**（`test_mode = false`）：只有新战局（朝向 180）才是玩家看到的那一局；
	# `test_mode = true` 载入的是旧快照分支（朝向 0），美术根会朝反方向转，实测把机器
	# 摆到墙里 —— 那是探针的帧选错，不是摆放错。用户存档由 APPDATA 隔离保护。
	_tower.test_mode = false
	add_child(_tower)
	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (_tower.get("_records") as Array).is_empty():
			break
	for _i in range(4):
		await get_tree().process_frame

	for node in _tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and str((node as DungeonRoom3D).room_id) == ROOM_ID:
			_room = node as DungeonRoom3D
			break
	_check(_room != null, "%s 必须存在" % ROOM_ID)
	if _room != null:
		_room.ensure_shell_built()
		_room.ensure_detail_built()
		for _i in range(4):
			await get_tree().process_frame
			await get_tree().physics_frame
		await _probe_station()
	_finish()


func _probe_station() -> void:
	var art := _room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	var cells := _room.get("_authored_tile_cells") as Array
	var snaps := _tower.get("_floor_plan_snapshots") as Dictionary
	var plan := snaps.get(0, {}) as Dictionary
	print("  · 规划: global_rot=%d valid=%s rooms=%d" % [
		int(plan.get("expedition_global_rotation_deg", -1)),
		str(plan.get("valid", false)), (plan.get("rooms", []) as Array).size(),
	])
	print("  · 帧: art_rot=%.1f template_rot=%.1f doors=%s tile_cells=%d spawn_points=%d room_pos=(%.1f,%.1f)" % [
		rad_to_deg(art.rotation.y) if art != null else -999.0,
		float(_room.get_meta("template_rotation_deg", -999.0)),
		str(_room.doors), cells.size(),
		(_room.get("enemy_spawn_points") as Array).size(),
		_room.global_position.x, _room.global_position.z,
	])
	var stations := _room.find_children("*", "ServiceStation3D", true, false)
	var merchants: Array[ServiceStation3D] = []
	for value in stations:
		var station := value as ServiceStation3D
		if station != null and station.station_type == "merchant":
			merchants.append(station)
	_check(merchants.size() == 1, "%s 只能有一台 merchant 服务点（实测 %d）" % [ROOM_ID, merchants.size()])
	_check(
		_room.get_service_station("merchant") != null,
		"get_service_station(\"merchant\") 必须返回该服务点"
	)
	if merchants.size() != 1:
		for value in stations:
			print("  · station=%s type=%s" % [value.name, (value as ServiceStation3D).station_type])
		return
	var station := merchants[0]

	# ── ① 来自作者锚点，不是别的房间那套程序化落位 ────────────────────────────
	_check(bool(station.get_meta("authored_service_station", false)), "服务点必须来自静态布局锚点")
	var marker := _find_marker()
	_check(marker != null, "静态布局里必须留有成对的 Marker3D 锚点")

	# ── ② 在「中部」而且踩在真地砖上 ──────────────────────────────────────────
	var local := _room.global_transform.affine_inverse() * station.global_position
	var planar := Vector2(local.x, local.z)
	_check(
		planar.length() <= MIDDLE_RADIUS_M,
		"服务点必须靠近房心（离中心 %.2f m ≤ %.1f m）" % [planar.length(), MIDDLE_RADIUS_M]
	)
	# 站得住 = 脚下真有楼板，而不是「在生成器清单里」。用物理往下打射线量实际地板，
	# 不用 `_inside_authored_footprint()`：那个口径读的是**生成器产出的**地砖清单，
	# 业主改了房间结构（新增中庭地砖）之后它已经不覆盖新地面了（见本轮 NOTE）。
	_check(
		_floor_under_footprint(station, 4.339, 1.545),
		"服务点整块占地脚下必须有楼板（实测 (%.2f, %.2f)）" % [planar.x, planar.y]
	)
	print("  · 服务点房间帧位置 (%.2f, %.2f)，朝向 yaw=%.1f°" % [
		planar.x, planar.y, rad_to_deg(station.rotation.y),
	])

	# ── ③ 视觉是贩卖机 + 实体挡人 + 交互盒在正面 ──────────────────────────────
	var visual := station.get_node_or_null("Visual") as Node3D
	_check(visual != null, "服务点必须有 Visual（主题贩卖机视觉）")
	var vending_glb := ""
	if visual != null:
		for node in visual.find_children("*", "", true, false):
			var path := (node as Node).scene_file_path
			if path.contains("vending_machine"):
				vending_glb = path
				break
	_check(not vending_glb.is_empty(), "视觉必须引用贩卖机 GLB（不能退回程序化占位盒）")
	var body := station.get_node_or_null("StaticBody3D") as StaticBody3D
	_check(body != null, "服务点必须有实体碰撞体")
	if body != null:
		_check(body.collision_layer != 0, "实体碰撞必须挡人（collision_layer ≠ 0）")
	var interaction := station.get_node_or_null("InteractionShape") as CollisionShape3D
	_check(interaction != null, "服务点必须有交互形状")
	# 交互盒要盖住正面（+Z，货窗侧）：99F 包装把它放在 −Z（朝向基地墙面），局内若照抄
	# 就会「站在货窗前点不到、绕到背面才触发」。判据是交互盒深度能覆盖 +Z 一侧。
	if interaction != null:
		var box := interaction.shape as BoxShape3D
		var reach := interaction.position.z + box.size.z * 0.5
		_check(reach > 2.0, "交互盒必须覆盖机器正面（+Z 侧）玩家站位，实测到 z=%.2f" % reach)
		print("  · 交互盒 pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f) 覆盖 z %.2f..%.2f" % [
			interaction.position.x, interaction.position.y, interaction.position.z,
			box.size.x, box.size.y, box.size.z,
			interaction.position.z - box.size.z * 0.5, reach,
		])

	# ── ④ 从门上能走到正面 ────────────────────────────────────────────────────
	# 正面 = 模型 **+Z**（货窗与「UI灯光」发光网格在 +Z 面，实测 z 0.175~0.772）。
	# 包装里 `InteractionShape` 落在 −Z 是 99F 基地设施自己的口径（交互区够大，两面都能进），
	# 不能拿它当「正面」判据，否则会把机器背面朝玩家。
	var front := station.global_transform.basis.z
	front.y = 0.0
	front = front.normalized()
	var approach := station.global_position + front * 2.3
	approach.y = WALK_CENTER_Y_M
	_check(_is_walkable(approach), "机器正前方 %.1f m 处必须站得下人" % 2.3)
	var door_point := _door_inside_point()
	_check(door_point != Vector3.INF, "房间必须有可用的门内落点")
	if door_point != Vector3.INF:
		var reached := _flood_reaches(door_point, approach)
		_check(reached, "从门内落点必须能靠 0.45m 半径走到机器正面（不是直线可达）")

	# ── ⑤ 交互开得出商人页（整条链） ──────────────────────────────────────────
	station.set("_player_in_range", true)
	station.perform_interaction(null, {})
	await get_tree().process_frame
	var merchant_ui: Variant = _tower.get("_merchant_ui")
	var opened := merchant_ui != null and is_instance_valid(merchant_ui)
	_check(opened, "交互后必须打开商人页")
	if opened:
		var ui := merchant_ui as MerchantUI
		_check(ui.visible, "商人页必须可见")
		var offers: Variant = _tower.get("_merchant_service")
		var stock_ok := offers != null and (offers as RunMerchantService).has_stock(ROOM_ID)
		_check(stock_ok, "商人货架必须以房间 ID 建立（room_08）")
		# 战斗房里成交**不该**顺手开撤离点（本关只有撤离房能结算）。
		_check(
			not bool(_tower.get("_trade_extraction_unlocked")),
			"普通战斗房成交前不得解锁交易撤离条件"
		)
		ui.hide_merchant()
	else:
		_notes.append("商人页未打开：见上方打印的 Dungeon3D 状态，不冒充通过")

	# ── ⑥ 出怪点没被机器吞掉 ──────────────────────────────────────────────────
	var spawn_points := _room.get("enemy_spawn_points") as Array
	if spawn_points.is_empty():
		_notes.append("出怪点池在本探针时序下为空（由遭遇触发前的 `_compute_spawn_reach()` 重建），不做断言")
	var inside := 0
	for value in spawn_points:
		var point := value as Vector3
		var flat := Vector2(point.x - local.x, point.z - local.z).length()
		if flat < 1.2:
			inside += 1
	_check(inside == 0, "不得有出怪点落在贩卖机体内（实测 %d 个）" % inside)


## 静态布局里的服务点锚点（保留在 TSCN 里，是位置与朝向的作者事实源）。
func _find_marker() -> Marker3D:
	var art := _room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art == null:
		return null
	for node in art.find_children("*", "Marker3D", true, false):
		if (node as Node).has_meta("service_station_config"):
			return node as Marker3D
	return null


## 占地四角 + 中心各向下打一条射线，必须都落在 y≈0 的楼板上。
func _floor_under_footprint(station: Node3D, width: float, depth: float) -> bool:
	var basis := station.global_transform.basis
	var origin := station.global_position
	for u in [-0.5, 0.0, 0.5]:
		for v in [-0.5, 0.0, 0.5]:
			var at := origin + basis.x * (float(u) * width) + basis.z * (float(v) * depth)
			var from := Vector3(at.x, 6.0, at.z)
			var query := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, -1.0, at.z))
			query.collide_with_areas = false
			var hit := _space().intersect_ray(query)
			if hit.is_empty():
				print("  地板射线空: (%.2f, %.2f)" % [at.x, at.z])
				return false
			var y := (hit.get("position", Vector3.ZERO) as Vector3).y
			if absf(y) > 0.35:
				print("  地板射线高度异常 %.2f m @ (%.2f, %.2f)" % [y, at.x, at.z])
				return false
	return true


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


## 站立采样的盒心高度。盒子 = 0.9 × 1.1 × 0.9（玩家肩宽/身高量级），底在 0.20 m：
##
## 踩过两次：① 半径 0.45 的球放在 y=0.35，球底 −0.10 m，**扎进 y=0 的楼板**；
## ② 抬到 y=0.5 后球底 0.05 m，又撞上中庭那批 `y=0.08 / 0.16` 的地砖碰撞，
## 于是"有地砖的地方全都站不下"，洪泛只剩几百格。用底在 0.20 m 的盒子才既越过
## 地砖唇口、又能被墙/家具挡住。
const WALK_CENTER_Y_M := 0.75
const WALK_BOX_SIZE := Vector3(0.9, 1.1, 0.9)


## 半径 0.45 m 的球放得进去 = 玩家站得下。
func _is_walkable(at: Vector3) -> bool:
	var box := BoxShape3D.new()
	box.size = WALK_BOX_SIZE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.collide_with_areas = false
	query.transform = Transform3D(Basis(), at)
	return _space().intersect_shape(query, 1).is_empty()


## 从门内 2.5 m 处往里走 2.5 m 的落点（进门后玩家实际站的位置）。
func _door_inside_point() -> Vector3:
	var doors := _room.get("_door_nodes") as Dictionary
	if doors.is_empty():
		return Vector3.INF
	var keys: Array = doors.keys()
	keys.sort()
	for key in keys:
		var door := doors[key] as Node3D
		if door == null or not is_instance_valid(door):
			continue
		var inward := _room.global_position - door.global_position
		inward.y = 0.0
		if inward.length_squared() < 0.01:
			continue
		var point := door.global_position + inward.normalized() * 2.5
		point.y = WALK_CENTER_Y_M
		if _is_walkable(point):
			return point
	return Vector3.INF


## 0.75 m 格宽的四邻域洪泛：只有球放得进去的格子才算通。禁飞区之外不做任何假设。
func _flood_reaches(from: Vector3, to: Vector3) -> bool:
	var dims := _room.get_dimensions()
	var origin := _room.global_position
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var columns := int(floor(dims.x / WALK_GRID_M))
	var rows := int(floor(dims.y / WALK_GRID_M))
	var start_cell := _cell_of(from, origin, half_x, half_z, columns, rows)
	var goal_cell := _cell_of(to, origin, half_x, half_z, columns, rows)
	if start_cell.x < 0 or goal_cell.x < 0:
		print("  洪泛：起点/终点不在房间格网内 %s %s" % [str(start_cell), str(goal_cell)])
		return false
	var walkable := {}
	var queue: Array[Vector2i] = [start_cell]
	var seen := {start_cell: true}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var point := _point_of(cell, origin, half_x, half_z)
		if not walkable.has(cell):
			walkable[cell] = _is_walkable(point)
		if not bool(walkable[cell]):
			continue
		if cell == goal_cell:
			print("  洪泛：%s → %s 连通（访问 %d 格）" % [str(start_cell), str(goal_cell), seen.size()])
			return true
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.y < 0 or next.x >= columns or next.y >= rows:
				continue
			if seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	print("  洪泛：%s → %s 不连通（访问 %d 格，终点可站=%s）" % [
		str(start_cell), str(goal_cell), seen.size(),
		str(walkable.get(goal_cell, "未访问")),
	])
	return false


func _cell_of(point: Vector3, origin: Vector3, half_x: float, half_z: float, columns: int, rows: int) -> Vector2i:
	var column := int(floor((point.x - origin.x + half_x) / WALK_GRID_M))
	var row := int(floor((point.z - origin.z + half_z) / WALK_GRID_M))
	if column < 0 or row < 0 or column >= columns or row >= rows:
		return Vector2i(-1, -1)
	return Vector2i(column, row)


func _point_of(cell: Vector2i, origin: Vector3, half_x: float, half_z: float) -> Vector3:
	return Vector3(
		origin.x - half_x + (float(cell.x) + 0.5) * WALK_GRID_M,
		WALK_CENTER_Y_M,
		origin.z - half_z + (float(cell.y) + 0.5) * WALK_GRID_M
	)


func _finish() -> void:
	print("")
	for note in _notes:
		print("NOTE %s" % note)
	if _failures.is_empty():
		print("EXP01_ROOM08_VENDING_OK")
		_quit(0)
		return
	for failure in _failures:
		print("FAIL %s" % failure)
	print("EXP01_ROOM08_VENDING_FAILED count=%d" % _failures.size())
	_quit(1)


func _quit(code: int) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.1
	timer.timeout.connect(get_tree().quit.bind(code))
	get_tree().root.add_child(timer)
	timer.start()
