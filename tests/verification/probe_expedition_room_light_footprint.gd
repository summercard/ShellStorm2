extends Node
## 探针：远征01「非矩形房（L / U 型）的中央顶灯与墙面开关落位真源＝真砖格」回归。
##
## 背景：`DungeonRoom3D` 的中央顶灯与墙面开关原先一律按**包围盒**落位（顶灯取 local
## 原点、开关取 `absi(room_seed)%4` 那面墙的包围盒墙面）。L 型 / U 型房的凹口在摆位阶段
## 就被 `point_in_polygon` 剔掉了砖 —— 那里**既没有地砖也没有墙**：
##   · 顶灯被吊到凹口（房外）⇒ 房间天然偏暗，按开关也照不亮房间；
##   · 开关被贴到包围盒假墙（凹口侧）⇒ 悬在空地上，玩家在房内进不了它的交互球
##     （`RoomLightSwitch3D.INTERACTION_RANGE` 2.2m）。
## 真源与 `_build_spawn_points()` 同一套：`_authored_tile_cells`（房内真实砖格心）。
##
## 逐房实测四条（只在**本房有地砖清单**时判定，无清单的房沿用旧行为）：
##   ① 顶灯落点在真砖格上（房内）；
##   ② 开关落点在真砖格上（贴的是真墙，不是包围盒假墙）；
##   ③ 从**可走地砖**能走到开关跟前（最近可走点到开关 ≤ 交互半径）；
##   ④ 交互链真通：玩家站上该点 → 归属切到本房 → 交互候选出现 → perform_interaction
##      返回 true → 灯状态翻转且点亮的灯 omni_energy > 0。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_probe'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://tests/verification/probe_expedition_room_light_footprint.tscn

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199
## 地砖可视边长 4.94m（含 0.06m 拼缝）⇒ 可站立矩形取 2.47m 半宽；
## 摆位口径的砖格半宽是 `AUTHORED_TILE_HALF_M` 2.5m，两者不同，别混用。
const TILE_STAND_HALF_M := 2.47
## 玩家胶囊半径量级：贴墙站立时身体中心离墙皮约这么远，用来把测试站位从墙皮退开。
const PLAYER_BODY_RADIUS_M := 0.45
const INTERACTION_RANGE_M := 2.2
const MIN_LIGHT_ENERGY := 0.01
## 无地砖清单的房没有砖格可算：从开关沿「指向房间中心」的方向退这么远当测试站位。
const SWITCH_STAND_BACK_M := 0.8
## 开关背后实墙判定：0.9m 高、四个水平方向里至少一个方向在这么近内命中实体碰撞。
const SWITCH_WALL_PROBE_M := 1.1

var _violations: Array[String] = []
var _checks := 0


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var rooms := _collect_rooms(tower)
	var player := tower.player
	print("EXPEDITION_ROOM_LIGHT_FOOTPRINT rooms=%d seed=%d player=%s" % [
		rooms.size(), RUN_SEED, str(player != null),
	])
	print("%-11s %-5s %-8s %-9s %-9s %-22s %s" % [
		"room", "tiles", "灯在房内", "开关在房内", "可走点距", "开关落点(local)", "交互链",
	])
	for room in rooms:
		await _probe_room(tower, room, player)
	print("")
	if _violations.is_empty():
		print("EXPEDITION_ROOM_LIGHT_FOOTPRINT_OK rooms=%d checks=%d" % [rooms.size(), _checks])
		get_tree().quit(0)
		return
	for violation in _violations:
		print("FAIL %s" % violation)
	get_tree().quit(1)


func _collect_rooms(tower: TowerDescent3D) -> Array[DungeonRoom3D]:
	var rooms: Array[DungeonRoom3D] = []
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms.append(room)
	return rooms


func _probe_room(tower: TowerDescent3D, room: DungeonRoom3D, player: Node3D) -> void:
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle()
	var cells: Array = room.get("_authored_tile_cells") as Array
	var lights: Array = room.get("_room_lights") as Array
	var light_text := _check_lights(room, cells, lights)
	var switch := room.get("_light_switch") as RoomLightSwitch3D
	if switch == null:
		# 屋顶房与 99F 基地房按设计没有程序开关（常驻灯 / 露天甲板），远征 13 房都应有。
		if not cells.is_empty():
			_violations.append("%s 有地砖却实例化不出墙面开关" % room.room_id)
		print("%-11s %-5d %-8s %-9s %-9s %-22s %s" % [
			room.room_id, cells.size(), light_text, "无开关", "-", "-", "-",
		])
		return
	_checks += 1
	var switch_inside := bool(room.call("_inside_authored_footprint", switch.position))
	if not cells.is_empty() and not switch_inside:
		_violations.append("%s 开关落位不在真砖格上 %s（贴的是包围盒假墙）" % [
			room.room_id, _v3(switch.position),
		])
	var reach := _nearest_walkable_point(switch.position, cells)
	var reach_distance := float(reach.get("distance", INF))
	if reach_distance < INF and reach_distance > INTERACTION_RANGE_M:
		_violations.append("%s 开关到最近可走点 %.2fm > 交互半径 %.2fm" % [
			room.room_id, reach_distance, INTERACTION_RANGE_M,
		])
	var light_chain := await _probe_interaction(tower, room, player, switch, reach)
	print("%-11s %-5d %-8s %-9s %-9s %-22s %s" % [
		room.room_id, cells.size(), light_text, str(switch_inside),
		"%.2fm" % reach_distance if reach_distance < INF else "无砖",
		_v3(switch.position), light_chain,
	])


func _check_lights(room: DungeonRoom3D, cells: Array, lights: Array) -> String:
	var all_inside := true
	var counted := 0
	var first := Vector3.ZERO
	for value in lights:
		var light := value as WastelandLight3D
		if light == null:
			continue
		if counted == 0:
			first = light.position
		counted += 1
		_checks += 1
		var inside := bool(room.call("_inside_authored_footprint", light.position))
		all_inside = all_inside and inside
		if not cells.is_empty() and not inside:
			_violations.append("%s 顶灯 %s 落位不在真砖格上 %s（吊在凹口/房外）" % [
				room.room_id, light.name, _v3(light.position),
			])
	if counted == 0:
		return "无灯"
	return "%s%s%s" % [
		str(all_inside), _v3(first), "" if counted == 1 else " ×%d" % counted,
	]


## 玩家从可走地砖走到开关跟前，走完整条交互链。返回一行结论文本。
func _probe_interaction(
	tower: TowerDescent3D,
	room: DungeonRoom3D,
	player: Node3D,
	switch: RoomLightSwitch3D,
	reach: Dictionary
) -> String:
	if player == null:
		return "无玩家"
	# 「最近可走砖上、离墙皮一个胶囊半径」的位置：真实玩家站得到的地方。
	# 顶灯 / 开关落位若在房内，这一点自然就在开关跟前；落在凹口时它会退到房内砖上。
	var stand_local := _fallback_stand_position(switch)
	if float(reach.get("distance", INF)) < INF:
		stand_local = reach.get("point", stand_local) as Vector3
	player.global_position = room.to_global(stand_local) + Vector3(0.0, 0.05, 0.0)
	await _settle()
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var owner_ok := str(tower.get("_current_room_id")) == room.room_id
	var detail_ok := bool(room.get("_detail_built"))
	if not owner_ok:
		_violations.append("%s 玩家站上可走砖后归属仍是 %s" % [
			room.room_id, str(tower.get("_current_room_id")),
		])
	if not detail_ok:
		_violations.append("%s 玩家进房后 detail 未建（拿不到开关）" % room.room_id)
	var wall_ok := _has_wall_behind(room, switch)
	if not wall_ok:
		_violations.append("%s 开关 %s 背后 %.2fm 内没有实墙（悬空）" % [
			room.room_id, _v3(switch.position), SWITCH_WALL_PROBE_M,
		])
	var in_range := bool(switch.get("_player_in_range"))
	var candidate: Dictionary = switch.get_interaction_candidate(player as Player3D)
	if not in_range or candidate.is_empty():
		_violations.append("%s 站上可走砖后仍无交互候选（in_range=%s 归属=%s）" % [
			room.room_id, str(in_range), str(tower.get("_current_room_id")),
		])
		return "★无候选"
	var before := switch.is_light_on()
	var performed := switch.perform_interaction(player as Player3D, candidate)
	await get_tree().process_frame
	await get_tree().process_frame
	var after := switch.is_light_on()
	_checks += 1
	if not performed or after == before:
		_violations.append("%s perform_interaction=%s 灯状态 %s→%s 未翻转" % [
			room.room_id, str(performed), str(before), str(after),
		])
		return "★未翻转"
	var energy_ok := _lights_follow_state(room, after)
	if not energy_ok:
		_violations.append("%s 灯状态 %s 与 omni 实况不一致" % [room.room_id, str(after)])
	return "%s→%s 贴墙=%s" % [str(before), str(after), str(wall_ok)]


## 无地砖清单的房（v007 安全房 / 塔楼程序化房）没有砖格可算：从开关沿「指向房间中心」
## 的方向退 `SWITCH_STAND_BACK_M`。这些房都是矩形，该方向必然指向房内。
func _fallback_stand_position(switch: RoomLightSwitch3D) -> Vector3:
	var inward := Vector3(-switch.position.x, 0.0, -switch.position.z)
	if inward.length() < 1e-4:
		return switch.position
	return switch.position + inward.normalized() * SWITCH_STAND_BACK_M


## 开关必须贴在**实墙**上：0.9m 高处四个水平方向里至少有一个方向在 `SWITCH_WALL_PROBE_M`
## 内命中实体碰撞（`collide_with_areas=false` 排除房间触发器等 Area3D）。
func _has_wall_behind(room: DungeonRoom3D, switch: RoomLightSwitch3D) -> bool:
	var origin := switch.global_position + Vector3(0.0, 0.9, 0.0)
	var space := room.get_world_3d().direct_space_state
	if space == null:
		return true
	for direction in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * SWITCH_WALL_PROBE_M
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if not space.intersect_ray(query).is_empty():
			return true
	return false


## 灯点亮时必须真的亮（omni_energy > 0）；灯灭时不要求能量为 0（有启动序列）。
func _lights_follow_state(room: DungeonRoom3D, lit: bool) -> bool:
	if not lit:
		return true
	var lights: Array = room.get("_room_lights") as Array
	var checked := false
	for value in lights:
		var light := value as WastelandLight3D
		if light == null:
			continue
		checked = true
		var omni := light.get("_light") as OmniLight3D
		if omni == null or omni.light_energy <= MIN_LIGHT_ENERGY:
			return false
	return checked


## 开关到**可走地砖并集**最近点的距离与落点。无砖清单时返回 distance = INF。
func _nearest_walkable_point(planar_position: Vector3, cells: Array) -> Dictionary:
	var best := INF
	var best_point := planar_position
	for value in cells:
		var cell := value as Vector3
		var point := Vector3(
			clampf(planar_position.x, cell.x - TILE_STAND_HALF_M, cell.x + TILE_STAND_HALF_M),
			0.0,
			clampf(planar_position.z, cell.z - TILE_STAND_HALF_M, cell.z + TILE_STAND_HALF_M),
		)
		var distance := Vector2(point.x - planar_position.x, point.z - planar_position.z).length()
		if distance < best:
			best = distance
			best_point = point
	if best == INF:
		return { "distance": INF, "point": planar_position }
	# 从墙皮退开一个胶囊半径（方向取「最近砖心」），避免测试站位站进墙里。
	var inward := _nearest_cell(planar_position, cells) - best_point
	inward.y = 0.0
	if inward.length() > 1e-4:
		best_point += inward.normalized() * minf(PLAYER_BODY_RADIUS_M, inward.length())
	return { "distance": best, "point": best_point }


func _nearest_cell(planar_position: Vector3, cells: Array) -> Vector3:
	var nearest := Vector3.ZERO
	var nearest_distance := INF
	for value in cells:
		var cell := value as Vector3
		var distance := Vector2(cell.x - planar_position.x, cell.z - planar_position.z).length_squared()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = cell
	return nearest


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout


func _v3(value: Vector3) -> String:
	return "(%+.2f,%+.2f)" % [value.x, value.z]
