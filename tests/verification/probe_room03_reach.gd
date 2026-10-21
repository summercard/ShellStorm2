extends Node

## 一次性探针（业主 2026-10-21）：
##   「room03 手动调整布局后，四个角落围起来了，中间还有角色去不了的地方，刷怪会刷在那些位置。」
##
## 只回答三件事：
##   ① 房间主层里，**玩家胶囊（r=0.34）从任一连接门走得到** 的区域是哪些格；
##   ② 哪些格**能落怪（刷怪净距 r=1.15 / 高 2.6）但玩家走不到** —— 这就是要禁刷的死区；
##   ③ 运行时真实 `_spawn_candidates` 里有多少落点踩在这些死区上。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_room03_reach.tscn
##   SS2_ROOM=f00_room_03   可换房间

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
const GRID_STEP_M := 0.5
const PLAYER_RADIUS_M := 0.34
const PLAYER_HEIGHT_M := 1.5
const SPAWN_CLEARANCE_M := 1.15
const SPAWN_HEIGHT_M := 2.6

var _tower: TowerDescent3D = null
var _room: DungeonRoom3D = null
var _dead_keys: Array[Vector2i] = []


func _ready() -> void:
	var want_room := OS.get_environment("SS2_ROOM")
	if want_room.is_empty():
		want_room = "room_03"
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	var seed_env := OS.get_environment("SS2_SEED")
	if not seed_env.is_empty():
		tower.run_seed_override = int(seed_env)
	_tower = tower
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var rooms := tower.get("_rooms") as Array
		if rooms != null and rooms.size() >= 4:
			break
	_find_room(want_room)
	print("")
	print("=== 可达性/死区  room=%s  seed=%s  等待=%.1fs ===" % [
		want_room, seed_env if not seed_env.is_empty() else "<随机器>", waited
	])
	if _room == null:
		print("**找不到房间 %s**，现有房间：" % want_room)
		var rooms_now := _tower.get("_rooms") as Array
		if rooms_now != null:
			for value in rooms_now:
				var r := value as DungeonRoom3D
				if r != null:
					print("    room_id=%s  dims=%s  type=%s" % [r.room_id, str(r.get_dimensions()), r.room_type])
		print("REACH_PROBE_END")
		get_tree().quit(0)
		return
	_room.ensure_shell_built()
	_room.ensure_detail_built()
	for _i in range(4):
		await get_tree().physics_frame
	_analyze()
	_report_gate()
	_verify_gate_candidates()
	_check_boxes()
	print("")
	print("REACH_PROBE_END")
	get_tree().quit(0)


## 闸门（`DungeonRoom3D._ensure_spawn_reach`）自身状态：是否启用、覆盖多少、候选池缩了多少。
func _report_gate() -> void:
	_room.call("_ensure_spawn_reach")
	var active := bool(_room.get("_spawn_reach_active"))
	var cells := _room.get("_spawn_reach_cells") as Dictionary
	var candidates := _room.get("_spawn_candidates") as Array
	print("")
	print("--- 闸门 ---")
	print("active=%s  可达格=%d  _spawn_candidates=%d" % [
		str(active), cells.size() if cells != null else 0, candidates.size() if candidates != null else 0
	])


## 盒子还能不能取满：`spawn_points_in_box` 取不满时尾部补 INF，调用方按有限点截断
## ⇒ 少出怪。整房所有盒都取不到点才是灾难（房间白送、门永远不开），这里要盯住。
func _check_boxes() -> void:
	var placements := _room.get("spawn_placements") as Array
	print("spawn_boxes_only=%s  spawn_placements=%d" % [str(_room.spawn_boxes_only), placements.size()])
	for index in placements.size():
		var placement := _tower.call("_box_placement_at", placements, index) as Dictionary
		if placement.is_empty():
			print("  盒#%d 解析失败" % index)
			continue
		var points := _room.spawn_points_in_box(
			placement.get("box_center", Vector2.ZERO) as Vector2,
			placement.get("box_size", Vector2.ZERO) as Vector2,
			13,
			0.0,
			0.0,
			int(placement.get("box_wall_recess_tiles", 1))
		)
		var finite := 0
		for value in points:
			if (value as Vector3).is_finite():
				finite += 1
		print("  盒#%d center=%s size=%s → 取到 %d/13" % [
			index, str(placement.get("box_center", Vector2.ZERO)),
			str(placement.get("box_size", Vector2.ZERO)), finite
		])


## 闸门启用后，候选池里还有没有落在「物理死区」的点 —— 这条必须为 0。
func _verify_gate_candidates() -> void:
	var dims := _room.get_dimensions()
	var dead := {}
	for key in _dead_keys:
		dead[key] = true
	var candidates := _room.get("_spawn_candidates") as Array
	var bad := 0
	for value in candidates:
		var point := value as Vector3
		var key := Vector2i(
			int(floor((point.x + dims.x * 0.5) / GRID_STEP_M)),
			int(floor((point.z + dims.y * 0.5) / GRID_STEP_M))
		)
		if dead.has(key):
			bad += 1
	print("闸门后候选点 %d 个，仍落在物理死区的 = %d 个" % [candidates.size(), bad])


func _find_room(room_id: String) -> void:
	var rooms := _tower.get("_rooms") as Array
	if rooms == null:
		return
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		if String(room.room_id) == room_id:
			_room = room
			return
	for value in rooms:
		var room := value as DungeonRoom3D
		if room != null and String(room.room_id).ends_with(room_id):
			_room = room
			return


func _analyze() -> void:
	var dims := _room.get_dimensions()
	print("room_id=%s  dims=%.1f x %.1f  global=%s  rot_y=%.1f" % [
		_room.room_id, dims.x, dims.y, str(_room.global_position), rad_to_deg(_room.global_rotation.y)
	])
	var space := _room.get_world_3d().direct_space_state
	var nx := int(floor(dims.x / GRID_STEP_M))
	var nz := int(floor(dims.y / GRID_STEP_M))
	var playable := {}
	var spawnable := {}
	var walk_shape := CapsuleShape3D.new()
	walk_shape.radius = PLAYER_RADIUS_M
	walk_shape.height = PLAYER_HEIGHT_M
	var spawn_shape := CylinderShape3D.new()
	spawn_shape.radius = SPAWN_CLEARANCE_M
	spawn_shape.height = SPAWN_HEIGHT_M
	for ix in nx:
		for iz in nz:
			var x := -dims.x * 0.5 + GRID_STEP_M * (ix + 0.5)
			var z := -dims.y * 0.5 + GRID_STEP_M * (iz + 0.5)
			var key := Vector2i(ix, iz)
			playable[key] = _shape_free(space, walk_shape, Vector3(x, PLAYER_HEIGHT_M * 0.5 + 0.02, z))
			spawnable[key] = _shape_free(space, spawn_shape, Vector3(x, SPAWN_HEIGHT_M * 0.5 + 0.02, z))
	var reached := _flood_from_ports(playable, dims)
	var blocked_total := 0
	var dead_keys: Array[Vector2i] = []
	for key in playable.keys():
		if not playable[key]:
			blocked_total += 1
	for key in spawnable.keys():
		if spawnable[key] and not reached.has(key):
			dead_keys.append(key)
	_dead_keys = dead_keys
	_dump_bitmap(playable, reached, spawnable, nx, nz)
	dead_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	print("网格 %.1fm：%d×%d = %d 格" % [GRID_STEP_M, nx, nz, nx * nz])
	print("玩家不可站格 = %d；玩家可达格 = %d；**能刷怪但玩家到不了 = %d**" % [
		blocked_total, reached.size(), dead_keys.size()
	])
	_dump_components(dead_keys, dims)
	_dump_runtime_candidates(dead_keys, dims)


## 位图：`#` = 能刷怪但玩家到不了（死区）；`.` = 玩家能站；`o` = 玩家到不了、也站不下；
## ` ` = 站得下但刷怪净距不够。每行一格 0.5 m。
func _dump_bitmap(playable: Dictionary, reached: Dictionary, spawnable: Dictionary, nx: int, nz: int) -> void:
	var rows: Array[String] = []
	for iz in nz:
		var line := ""
		for ix in nx:
			var key := Vector2i(ix, iz)
			if spawnable.get(key, false) and not reached.has(key):
				line += "#"
			elif reached.has(key):
				line += "."
			elif not playable.get(key, false):
				line += "o"
			else:
				line += " "
		rows.append(line)
	print("DEADZONE_MAP_BEGIN")
	for line in rows:
		print("MAP|" + line)
	print("DEADZONE_MAP_END")


func _shape_free(space: PhysicsDirectSpaceState3D, shape: Shape3D, local_point: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), _room.to_global(local_point))
	params.collision_mask = 1
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits := space.intersect_shape(params, 2)
	return hits.is_empty()


func _flood_from_ports(playable: Dictionary, dims: Vector2) -> Dictionary:
	var starts: Array[Vector2i] = []
	var ports := _room.get_node_or_null("ConnectionPorts")
	if ports == null:
		ports = _find_by_name(_room, "ConnectionPorts")
	if ports != null:
		for child in ports.get_children():
			if not (child is Marker3D):
				continue
			var local := _room.to_local((child as Marker3D).global_position)
			var key := Vector2i(
				int(floor((local.x + dims.x * 0.5) / GRID_STEP_M)),
				int(floor((local.z + dims.y * 0.5) / GRID_STEP_M))
			)
			print("  门 %s → 格 %s（local=%.2f,%.2f）可站=%s" % [
				child.name, str(key), local.x, local.z, str(playable.get(key, false))
			])
			# 门所在格可能正好压在门框上，向内 3 格找第一个可站格作起点。
			for step in range(0, 8):
				var probe := Vector2i(key.x + step, key.y)
				if playable.get(probe, false):
					starts.append(probe)
					break
				probe = Vector2i(key.x - step, key.y)
				if playable.get(probe, false):
					starts.append(probe)
					break
	var visited := {}
	var queue: Array[Vector2i] = []
	for start in starts:
		if not visited.has(start):
			visited[start] = true
			queue.append(start)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in dirs:
			var nxt: Vector2i = cur + d
			if visited.has(nxt) or not playable.get(nxt, false):
				continue
			visited[nxt] = true
			queue.append(nxt)
	return visited


func _find_by_name(node: Node, part: String) -> Node:
	for child in node.get_children():
		if part.to_lower() in String(child.name).to_lower():
			return child
		var found := _find_by_name(child, part)
		if found != null:
			return found
	return null


func _dump_components(keys: Array[Vector2i], dims: Vector2) -> void:
	if keys.is_empty():
		print("死区：无")
		return
	var remaining := {}
	for key in keys:
		remaining[key] = true
	var groups: Array = []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for key in keys:
		if not remaining.has(key):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [key]
		remaining.erase(key)
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			group.append(cur)
			for d in dirs:
				var nxt: Vector2i = cur + d
				if remaining.has(nxt):
					remaining.erase(nxt)
					queue.append(nxt)
		groups.append(group)
	groups.sort_custom(func(a, b) -> bool: return a.size() > b.size())
	print("死区分组（按格数降序，房间局部坐标）：")
	for index in groups.size():
		var group: Array = groups[index]
		var min_x := 1e9
		var max_x := -1e9
		var min_z := 1e9
		var max_z := -1e9
		for key_value in group:
			var key: Vector2i = key_value
			var x := -dims.x * 0.5 + GRID_STEP_M * (key.x + 0.5)
			var z := -dims.y * 0.5 + GRID_STEP_M * (key.y + 0.5)
			min_x = minf(min_x, x)
			max_x = maxf(max_x, x)
			min_z = minf(min_z, z)
			max_z = maxf(max_z, z)
		print("  [%d] 格数=%d  x∈[%.2f, %.2f]  z∈[%.2f, %.2f]  面积≈%.1f m²" % [
			index, group.size(), min_x - GRID_STEP_M * 0.5, max_x + GRID_STEP_M * 0.5,
			min_z - GRID_STEP_M * 0.5, max_z + GRID_STEP_M * 0.5,
			group.size() * GRID_STEP_M * GRID_STEP_M
		])


func _dump_runtime_candidates(dead_keys: Array[Vector2i], dims: Vector2) -> void:
	var dead := {}
	for key in dead_keys:
		dead[key] = true
	var candidates := _room.get("_spawn_candidates") as Array
	if candidates == null:
		print("_spawn_candidates 读不到")
		return
	var hit: Array[Vector3] = []
	for value in candidates:
		var point := value as Vector3
		var key := Vector2i(
			int(floor((point.x + dims.x * 0.5) / GRID_STEP_M)),
			int(floor((point.z + dims.y * 0.5) / GRID_STEP_M))
		)
		if dead.has(key):
			hit.append(point)
	print("运行时 _spawn_candidates = %d 个；落在死区的 = %d 个" % [candidates.size(), hit.size()])
	for point in hit:
		print("    死区落点 local=(%.2f, %.2f)" % [point.x, point.z])
