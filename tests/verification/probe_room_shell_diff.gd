extends Node

## 一次性探针（业主 2026-10-21）：为什么**同一份共享房壳**在主路房里地板完整、
## 在支线子图房里却大面积空掉。
##
## 做法：只盯一间房（`SS2_ROOM`），把它的壳体结构与地面碰撞来源**逐件摊开**：
##   · 壳根下每个顶层子节点的位置/朝向/子树规模；
##   · 名称含 floor / wall / door 的网格件清单（局部坐标）；
##   · 1m 网格向下打射线，把「命中物路径」按顶层祖先归类统计 ——
##     一眼看出主路房的地板到底是谁提供的。
##
## 用法：
##   SS2_ROOM=room_01      SS2_SEED=414339956 godot --headless --path . res://tests/verification/probe_room_shell_diff.tscn
##   SS2_ROOM=secret_0_0   SS2_SEED=414339956 godot --headless --path . res://tests/verification/probe_room_shell_diff.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
const GRID_STEP_M := 2.0

var _room: DungeonRoom3D = null


func _ready() -> void:
	var want := OS.get_environment("SS2_ROOM")
	if want.is_empty():
		want = "room_01"
	var seed_env := OS.get_environment("SS2_SEED")
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	if not seed_env.is_empty():
		tower.run_seed_override = int(seed_env)
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			for _i in range(4):
				await get_tree().process_frame
			break

	for node in tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and str((node as DungeonRoom3D).room_id) == want:
			_room = node as DungeonRoom3D
			break
	if _room == null:
		print("找不到房间 %s" % want)
		get_tree().quit(1)
		return

	var dims := _room.get_dimensions()
	print("")
	print("=== 壳体摊开  room=%s  seed=%s ===" % [want, seed_env])
	print("  世界=(%.2f, %.2f, %.2f)  尺寸=%.1f x %.1f  rotY=%.1f°  doors=%s" % [
		_room.global_position.x, _room.global_position.y, _room.global_position.z,
		dims.x, dims.y, rad_to_deg(_room.global_rotation.y), str(_room.doors),
	])
	print("  房间直接子节点: %s" % str(_child_names(_room)))

	var root := _room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if root == null:
		root = _room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if root != null:
		print("")
		print("── 壳根 %s  local=(%.2f, %.2f, %.2f) rotY=%.1f° ──" % [
			root.name, root.position.x, root.position.y, root.position.z, rad_to_deg(root.rotation.y),
		])
		for child in root.get_children():
			var node3d := child as Node3D
			var pos := node3d.position if node3d != null else Vector3.ZERO
			var rot := rad_to_deg(node3d.rotation.y) if node3d != null else 0.0
			print("  · %-28s local=(%6.2f, %5.2f, %6.2f) rotY=%6.1f°  子树=%d  网格=%d" % [
				str(child.name), pos.x, pos.y, pos.z, rot,
				child.find_children("*", "", true, false).size(),
				child.find_children("*", "MeshInstance3D", true, false).size(),
			])

	print("")
	print("── 向下射线的命中物来源（%0.0fm 网格）──" % GRID_STEP_M)
	_print_floor_sources(dims)

	print("")
	print("── 名含 floor 的网格件（最多 60 条）──")
	_print_named(dims, "floor", 60)

	print("")
	print("ROOM_SHELL_DIFF_END")
	get_tree().quit(0)


func _print_floor_sources(dims: Vector2) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var floor_y := _room.global_position.y
	var cols := maxi(1, int(floor(dims.x / GRID_STEP_M)))
	var rows := maxi(1, int(floor(dims.y / GRID_STEP_M)))
	var counts := {}
	var misses := 0
	for row in range(rows):
		for col in range(cols):
			var lx := -dims.x * 0.5 + (float(col) + 0.5) * (dims.x / float(cols))
			var lz := -dims.y * 0.5 + (float(row) + 0.5) * (dims.y / float(rows))
			var world := _room.global_transform * Vector3(lx, 0.0, lz)
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(world.x, floor_y + 2.2, world.z),
				Vector3(world.x, floor_y - 6.0, world.z)
			)
			query.collide_with_areas = false
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				misses += 1
				continue
			var collider := hit.get("collider") as Node
			var key := _top_owner(collider)
			var hit_y := float((hit.get("position", Vector3.ZERO) as Vector3).y) - floor_y
			var label := "%s  (y%+.2f)" % [key, hit_y]
			counts[label] = int(counts.get(label, 0)) + 1
	var rows_sorted: Array = counts.keys()
	rows_sorted.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	print("  打空 %d / %d" % [misses, cols * rows])
	for key in rows_sorted:
		print("  %5d 格  ← %s" % [int(counts[key]), str(key)])


## 命中物往上爬到「房间直接子节点」这一层，作为来源归类键。
func _top_owner(node: Node) -> String:
	var probe := node
	var last := node
	while probe != null and probe != _room:
		last = probe
		probe = probe.get_parent()
	if probe != _room:
		return "<房间外:%s>" % str(node.get_path())
	return str(last.name)


func _print_named(dims: Vector2, keyword: String, limit: int) -> void:
	var printed := 0
	for node in _room.find_children("*", "MeshInstance3D", true, false):
		if printed >= limit:
			break
		var mesh := node as MeshInstance3D
		if mesh == null or not str(mesh.name).to_lower().contains(keyword):
			continue
		var local := _room.global_transform.affine_inverse() * mesh.global_position
		print("  %-40s local=(%7.2f, %6.2f, %7.2f)  父=%s" % [
			str(mesh.name), local.x, local.y, local.z, str(mesh.get_parent().name),
		])
		printed += 1
	if printed == 0:
		print("  <没有名称含 %s 的网格件>" % keyword)


func _child_names(node: Node) -> Array:
	var names: Array = []
	for child in node.get_children():
		names.append(str(child.name))
	return names
