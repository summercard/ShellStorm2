extends Node
## 探针：远征03 房间的导航面**是否穿墙**。
##
## 背景（2026-11-09 业主）：回字型房间里怪贴着墙走、不朝玩家来。
## 前面几轮已经把可疑范围收到「导航面本身」：
##   · 房间节点 `walkable_navigation_polygons` = 0（美术壳里明明有）；
##   · `_authored_tile_cells` = 0（这些房没有地砖清单）；
##   · 一部分房间 `furnishing_navigation_polygons` 有几千个 0.5m 格，另一部分是**单块矩形**。
##
## 本探针只回答一件事：**在导航图上求出来的路径，会不会穿过实体墙**。
## 判据（不依赖任何 meta 命名）：房间内每 4m 取一个采样点，两两求 `map_get_path`，
## 再对每一段在 y=0.7（腰高，避开地板）打一条 layer 1 射线 —— 命中即穿墙。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_navprobe'
##   godot --headless --path . --scene res://scripts/probe_expedition03_nav_wallcross.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const STEP_M := 4.0
const RAY_HEIGHT_M := 0.7

var _root: Window
## 累计穿墙段数。任何一间房 > 0 就是失败 —— 这条是防「导航面退回整块矩形」的回归断言。
var _total_cross := 0


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	var tower: TowerDescent3D = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20261109
	_root.add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var rooms: Array[DungeonRoom3D] = []
	var stack: Array[Node] = [tower]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is DungeonRoom3D:
			rooms.append(node as DungeonRoom3D)
		for child in node.get_children():
			stack.append(child)

	for room in rooms:
		room.ensure_shell_built()
		room.ensure_detail_built()
	for _i in 30:
		await get_tree().physics_frame
	NavigationServer3D.map_force_update(_root.get_world_3d().navigation_map)
	await get_tree().process_frame

	var space := _root.get_world_3d().direct_space_state
	for room in rooms:
		var dims := room.get_dimensions()
		if dims.x < 20.0 or dims.y < 20.0:
			continue
		_scan(room, space)

	print("WALLCROSS_DONE")
	if _total_cross > 0:
		print("NAV_WALLCROSS_FAIL total_cross_segments=%d" % _total_cross)
		get_tree().quit(1)
		return
	print("NAV_WALLCROSS_OK")
	get_tree().quit(0)


func _scan(room: DungeonRoom3D, space: PhysicsDirectSpaceState3D) -> void:
	var map := _root.get_world_3d().navigation_map
	var dims := room.get_dimensions()
	var samples: Array[Vector3] = []
	var x := -dims.x * 0.5 + 2.0
	while x <= dims.x * 0.5 - 1.0:
		var z := -dims.y * 0.5 + 2.0
		while z <= dims.y * 0.5 - 1.0:
			samples.append(Vector3(x, 0.0, z))
			z += STEP_M
		x += STEP_M
	var pairs := 0
	var cross_segments := 0
	var worst := ""
	var worst_hits := 0
	var hit_names := {}
	var far_gap := 0.0
	var far_pair := ""
	for i in samples.size():
		for j in range(i + 1, samples.size()):
			var a := samples[i]
			var b := samples[j]
			if Vector2(a.x - b.x, a.z - b.z).length() < 6.0:
				continue
			var path := NavigationServer3D.map_get_path(
				map, room.to_global(a + Vector3.UP * 0.15),
				room.to_global(b + Vector3.UP * 0.15), true
			)
			if path.size() < 2:
				continue
			pairs += 1
			var last := path[path.size() - 1]
			var gap := Vector2(last.x - b.x, last.z - b.z).length()
			if gap > far_gap:
				far_gap = gap
				far_pair = "(%s,%s)→(%s,%s)" % [
					_f(a.x), _f(a.z), _f(b.x), _f(b.z),
				]
			var hits := 0
			for k in range(path.size() - 1):
				var from := path[k] + Vector3.UP * RAY_HEIGHT_M
				var to := path[k + 1] + Vector3.UP * RAY_HEIGHT_M
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
				if not hit.is_empty():
					var who := str((hit.collider as Node).name)
					# 敌人受击体也是 layer 1 —— 探针自己会刷怪，必须排除，否则全是假阳性。
					if who.contains("HitReceiver") or who.contains("Enemy") or who.contains("Player"):
						continue
					hits += 1
					if not hit_names.has(who):
						hit_names[who] = 0
					hit_names[who] = int(hit_names[who]) + 1
			if hits > 0:
				cross_segments += hits
				_total_cross += hits
				if hits > worst_hits:
					worst_hits = hits
					worst = "(%s)→(%s)" % [
						_f(a.x) + "," + _f(a.z), _f(b.x) + "," + _f(b.z),
					]
	var region := room.get_node_or_null("RuntimeDetail/RuntimeNavigationRegion3D") as NavigationRegion3D
	var polys := -1
	if region != null and region.navigation_mesh != null:
		polys = region.navigation_mesh.get_polygon_count()
	print("CROSS id=%-24s dims=%s polys=%d pairs=%d cross_seg=%d worst=%d %s" % [
		room.room_id, str(dims), polys, pairs, cross_segments, worst_hits, worst,
	])
	if room.room_id == "hub_02":
		var demo_from: Vector3 = room.to_global(Vector3(-10.0, 0.15, 0.0))
		var demo_to: Vector3 = room.to_global(Vector3(10.0, 0.15, 0.0))
		var demo := NavigationServer3D.map_get_path(map, demo_from, demo_to, true)
		print("  DEMO from=%s to=%s path=%s closest_from=%s" % [
			str(demo_from), str(demo_to), str(demo),
			str(NavigationServer3D.map_get_closest_point(map, demo_from)),
		])
	print("  REACH id=%-20s gate=%s cells=%d blockers=%d build_ms=%.1f refresh=%d far_gap=%.2f %s" % [
		room.room_id, str(room._spawn_reach_active), room._spawn_reach_cells.size(),
		room._spawn_blockers.size(),
		float(room.get_meta("furnishing_navigation_build_ms", -1.0)),
		int(room.get_meta("furnishing_navigation_refresh_count", 0)),
		far_gap, far_pair,
	])
	if not hit_names.is_empty():
		var top: Array = []
		for key in hit_names.keys():
			top.append([key, int(hit_names[key])])
		top.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
		var shown: Array[String] = []
		for index in range(mini(6, top.size())):
			shown.append("%s×%d" % [str(top[index][0]), int(top[index][1])])
		print("  HITBY id=%-20s %s" % [room.room_id, ", ".join(shown)])


func _f(value: float) -> String:
	return "%.0f" % value
