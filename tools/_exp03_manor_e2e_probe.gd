extends Node
## 端到端：公馆组件在工坊里摆好后，游戏内到底会不会呈现。
##
## 复刻工坊的真实保存动作，不做任何简化：
##   1. 取工坊采集出的**真实快照**（`Room_<id>` → `WhiteboxShell` → `ShellPart_NNN`）。
##   2. 模拟人在工坊里摆放：在根下建 `ArtComponents`，把公馆地砖/护墙/陈设按 5m 网格
##      实例进去（`owner` 设成根 —— 不设就存不进 PackedScene）。
##   3. `PackedScene.pack()` + `ResourceSaver.save()` 落到 `CONTRACT.art_path()`
##      —— 与 `editor_plugin.gd::_finish_runtime_room()` 和用户按保存时完全同一条路径。
##   4. 重新实例化关卡，检查美术是否真的进了场景树、可见、有网格、在房间范围内。
##
## 判定「游戏内会呈现」用四个硬指标，缺一不算：
##   · `art_layer_loaded` 为真（运行时认了这份美术）
##   · manor 节点在**活动场景树**里（`is_inside_tree()`）
##   · `is_visible_in_tree()` 为真（没被 hide，也没被祖先 hide）
##   · 有 MeshInstance3D 且全局 AABB 落在房间包围盒内（没跑到天上或隔壁）
##
## 结束自动删除临时文件。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const CACHE_DIR := "res://.godot/editor/scene_builder_runtime/expedition_03"
const MANOR_BASE := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
const SEED := 77003244
const GRID := 5.0

const FLOOR_PREFAB := MANOR_BASE + "/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn"
const WALL_PREFAB := MANOR_BASE + "/manor_wall_standard/env_manor_wall_standard_root_top3d.tscn"
const DOOR_PREFAB := MANOR_BASE + "/manor_wall_door/env_manor_wall_door_root_top3d.tscn"
const DECOR_PREFABS := [
	MANOR_BASE + "/manor_sofa/env_manor_sofa_root_top3d.tscn",
	MANOR_BASE + "/manor_rug_lounge/env_manor_rug_lounge_root_top3d.tscn",
	MANOR_BASE + "/manor_wall_lamp/env_manor_wall_lamp_root_top3d.tscn",
	MANOR_BASE + "/manor_table_lamp/env_manor_table_lamp_root_top3d.tscn",
	MANOR_BASE + "/manor_plant_large/env_manor_plant_large_root_top3d.tscn",
]

var _failures: Array[String] = []
var _written := ""


func _ready() -> void:
	var tower_a := await _spawn()
	var room_id := ""
	var size := Vector2.ZERO
	for value in tower_a.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		var dim: Vector2 = room.call("get_dimensions")
		if is_equal_approx(dim.x, 25.0) and is_equal_approx(dim.y, 25.0):
			room_id = room.room_id
			size = dim
			break
	tower_a.queue_free()
	await get_tree().process_frame
	if room_id.is_empty():
		print("E2E_SKIP 这个种子里没有 25×25 的程序化房间")
		get_tree().quit(2)
		return

	# ── 1. 算 art_path（与工坊 `capture_runtime.gd:54` 同一个函数）─────────
	var base_path := _base_static_path(room_id)
	var target := await _art_path_for(room_id, size, base_path)
	if target.is_empty():
		print("E2E_FAIL art_path 算不出来（room=%s）" % room_id)
		get_tree().quit(1)
		return
	print("E2E_TARGET %s" % target.get_file())

	# ── 2. 找对应的真实快照 ───────────────────────────────────────────────
	# 用**目标文件名**去缓存里找：工坊采集器就是 `cache_dir.path_join(art_path.get_file())`，
	# 所以缓存文件名 == art_path 文件名。按 mtime 挑最新会挑到**旧批次**的快照，
	# 其根节点 meta 里的签名与当前不符 —— 工坊遇到这种会直接报「关卡缓存已过期」。
	var snapshot_path := CACHE_DIR.path_join(target.get_file())
	if not FileAccess.file_exists(snapshot_path):
		print("E2E_SKIP 缓存里没有当前签名的快照 %s（请先重采集）" % target.get_file())
		get_tree().quit(2)
		return
	print("E2E_SNAPSHOT %s" % snapshot_path.get_file())

	# ── 3. 模拟摆放 + 工坊保存 ─────────────────────────────────────────────
	var placed := _place_and_save(snapshot_path, target, size)
	if not placed:
		print("E2E_FAIL 保存失败")
		get_tree().quit(1)
		return
	print("E2E_SAVED bytes=%d" % FileAccess.get_file_as_string(target).length())

	# ── 4. 跑起来看 ──────────────────────────────────────────────────────
	var tower_b := await _spawn()
	var room := _find(tower_b, room_id)
	if room == null:
		print("E2E_FAIL 重新实例化后找不到 %s" % room_id)
		get_tree().quit(1)
		return
	_inspect(room, room_id, size)
	tower_b.queue_free()
	await get_tree().process_frame
	_cleanup()
	print("E2E_%s failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("E2E_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _inspect(room: DungeonRoom3D, room_id: String, size: Vector2) -> void:
	var art_loaded := bool(room.get_meta("art_layer_loaded", false))
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	var kept := int(room.get_meta("art_layer_structure_kept", 0))
	var floor_skip := bool(room.get_meta("procedural_floor_skipped", false))
	var sides: Array = room.get_meta("art_layer_covered_sides", [])
	print("E2E_ROOM %-8s art_layer=%-5s kept=%-3d floor_skip=%-5s sides=%s"
		% [room_id, art_loaded, kept, floor_skip, str(sides)])
	_check(art_loaded, "运行时没加载美术层（工坊保存的没被认出来）")
	_check(art_root != null, "没有 AuthoredLayoutArtRoot（美术根没挂上）")
	if art_root == null:
		return
	_check(art_root.is_inside_tree(), "美术根不在场景树里（游戏内不会画）")
	_check(art_root.is_visible_in_tree(), "美术根在树里但不可见（被 hide 了）")

	# 逐类统计：进了树、可见、有网格
	var total := 0
	var in_tree := 0
	var visible := 0
	var with_mesh := 0
	var box := AABB()
	var has_box := false
	for node in art_root.find_children("*", "Node3D", true, false):
		var file := str(node.scene_file_path)
		if not file.contains("env_manor_") or not file.contains("_root_top3d"):
			continue
		total += 1
		if node.is_inside_tree():
			in_tree += 1
		if node.is_visible_in_tree():
			visible += 1
		var meshes: Array[Node] = []
		if node is MeshInstance3D:
			meshes.append(node)
		meshes.append_array(node.find_children("*", "MeshInstance3D", true, false))
		if not meshes.is_empty():
			with_mesh += 1
			for value in meshes:
				var mi := value as MeshInstance3D
				if mi == null or mi.mesh == null:
					continue
				var aabb: AABB = mi.global_transform * mi.get_aabb()
				box = box.merge(aabb) if has_box else aabb
				has_box = true
	print("E2E_NODES total=%d in_tree=%d visible=%d with_mesh=%d" % [total, in_tree, visible, with_mesh])
	_check(total >= 45, "美术层里的公馆件只有 %d 件（应 ≥45：25 地砖 + 20 墙）" % total)
	_check(in_tree == total, "有 %d 件公馆件不在场景树里" % (total - in_tree))
	_check(visible == total, "有 %d 件公馆件不可见（游戏内看不到）" % (total - visible))
	_check(with_mesh == total, "有 %d 件公馆件没有网格（空壳，画不出来）" % (total - with_mesh))

	if has_box:
		# AABB 是世界坐标；房间不在世界原点（实测 boss_foyer 在 x=104.75 z=-55.25），
		# 所以必须换算到**房间局部空间**再和半宽比，否则每条都会假失败。
		# 另注意 `AABB.position` 是**最小角**不是中心，要 + size/2 才是中心。
		var local: AABB = room.global_transform.affine_inverse() * box
		var center := local.position + local.size * 0.5
		print("E2E_AABB local_center=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)"
			% [center.x, center.y, center.z,
				local.size.x, local.size.y, local.size.z])
		var half := size * 0.5
		_check(local.size.x <= size.x + 1.0 and local.size.z <= size.y + 1.0,
			"美术整体尺寸 %.1f×%.1f 超出房间 %.1f×%.1f（摆歪了）"
			% [local.size.x, local.size.z, size.x, size.y])
		_check(absf(center.x) <= 0.6 and absf(center.z) <= 0.6,
			"美术没有居中（局部中心 x=%.2f z=%.2f，应≈0）" % [center.x, center.z])
		_check(local.position.y > -1.0 and local.position.y < 1.0,
			"美术没贴地（局部底面 y=%.2f）" % local.position.y)
	else:
		_fail("拿不到任何美术网格的 AABB")

	# 门扇仍在（美术负责洞口，门扇归程序化）
	var doors := room.find_children("*", "RoomDoor3D", true, false).size()
	print("E2E_DOORS %d" % doors)
	_check(doors > 0, "跳过程序化墙之后门扇没了（玩家会被关在房里）")


## 复刻工坊保存：实例化快照 → 建 ArtComponents → 塞公馆件（设 owner）→ pack → save。
func _place_and_save(snapshot_path: String, target: String, size: Vector2) -> bool:
	var packed := load(snapshot_path) as PackedScene
	if packed == null:
		_fail("快照加载不了 %s" % snapshot_path)
		return false
	var root := packed.instantiate() as Node3D
	if root == null:
		_fail("快照根不是 Node3D")
		return false
	root.transform = Transform3D.IDENTITY

	# 工坊里用户会先建这个组来放美术（快照里只有 WhiteboxShell）
	var art := Node3D.new()
	art.name = "ArtComponents"
	root.add_child(art)
	art.owner = root

	var cols := int(round(size.x / GRID))
	var rows := int(round(size.y / GRID))
	for row in range(rows):
		for col in range(cols):
			_add_prefab(FLOOR_PREFAB, art, root,
				Vector3(-size.x * 0.5 + (float(col) + 0.5) * GRID, 0.0,
					-size.y * 0.5 + (float(row) + 0.5) * GRID), 0.0,
				"Floor_%d_%d" % [col, row])
	for index in range(cols):
		var x := -size.x * 0.5 + (float(index) + 0.5) * GRID
		var north := "door" if index == cols / 2 else "wall"
		_add_prefab(DOOR_PREFAB if north == "door" else WALL_PREFAB, art, root,
			Vector3(x, 0.0, -size.y * 0.5), 0.0, "Wall_north_%d" % index)
		_add_prefab(WALL_PREFAB, art, root,
			Vector3(x, 0.0, size.y * 0.5), 180.0, "Wall_south_%d" % index)
	for index in range(rows):
		var z := -size.y * 0.5 + (float(index) + 0.5) * GRID
		_add_prefab(WALL_PREFAB, art, root,
			Vector3(-size.x * 0.5, 0.0, z), 90.0, "Wall_west_%d" % index)
		_add_prefab(WALL_PREFAB, art, root,
			Vector3(size.x * 0.5, 0.0, z), 90.0, "Wall_east_%d" % index)
	# 五件陈设
	var decor_positions := [
		Vector3(-6.0, 0.0, -6.0), Vector3(0.0, 0.0, 0.0), Vector3(6.0, 0.0, 6.0),
		Vector3(-6.0, 0.0, 6.0), Vector3(6.0, 0.0, -6.0),
	]
	for index in range(DECOR_PREFABS.size()):
		_add_prefab(str(DECOR_PREFABS[index]), art, root,
			decor_positions[index], 0.0, "Decor_%d" % index)

	var scene := PackedScene.new()
	var error := scene.pack(root)
	if error != OK:
		_fail("pack 失败：%s" % error_string(error))
		root.free()
		return false
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	error = ResourceSaver.save(scene, target)
	root.free()
	if error != OK:
		_fail("ResourceSaver.save 失败：%s" % error_string(error))
		return false
	_written = target
	return true


func _add_prefab(prefab_path: String, parent: Node3D, root: Node3D,
		position: Vector3, degrees: float, node_name: String) -> void:
	var packed := load(prefab_path) as PackedScene
	if packed == null:
		_fail("加载不了 prefab %s" % prefab_path)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_fail("prefab 根不是 Node3D %s" % prefab_path)
		return
	instance.name = node_name
	instance.position = position
	instance.rotation.y = deg_to_rad(degrees)
	parent.add_child(instance)
	# **这一行是关键**：不设 owner，节点不会进 PackedScene，保存后美术就没了。
	instance.owner = root


func _newest_cache_for(room_id: String) -> String:
	var best := ""
	var best_time := 0
	for file_name in DirAccess.get_files_at(CACHE_DIR):
		if not file_name.ends_with(".tscn"):
			continue
		if not file_name.begins_with(room_id + "_"):
			continue
		var path := CACHE_DIR.path_join(file_name)
		var mtime := FileAccess.get_modified_time(path)
		if mtime > best_time:
			best_time = mtime
			best = path
	return best


func _base_static_path(room_id: String) -> String:
	return "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/f00_%s_static_layout.tscn" % room_id


func _art_path_for(room_id: String, size: Vector2, base_path: String) -> String:
	# 用运行时真身算 signature，保证与 capture_runtime 和运行时三方一致
	var probe := SCENE.instantiate()
	probe.set("test_mode", true)
	probe.set("run_seed_override", SEED)
	add_child(probe)
	var found: DungeonRoom3D = null
	for _frame in 20:
		await get_tree().process_frame
	for value in probe.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null and room.room_id == room_id:
			found = room
			break
	var result := ""
	if found != null:
		var descriptor := CONTRACT.describe(found)
		result = CONTRACT.art_path(base_path, descriptor)
		print("E2E_SIGNATURE %s" % str(descriptor["signature"]).substr(0, 12))
	probe.queue_free()
	return result


func _spawn() -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower


func _find(tower: Node, room_id: String) -> DungeonRoom3D:
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null and room.room_id == room_id:
			return room
	return null


func _cleanup() -> void:
	if _written.is_empty():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_written))
	print("E2E_CLEANED %s" % _written.get_file())


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)
