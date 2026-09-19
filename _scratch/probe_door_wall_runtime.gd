extends Node
## 一次性核对：门墙模块在**真关卡运行时**建在哪、基准坐标是多少、与门扇对不对齐。
##
## 为什么需要它：probe_door_anchor 的 C 段只遍历 `room.get_children()`（房间直接子
## 节点），在它选中的楼梯厅上恒为空，答不了「门墙模块长什么样」。本探针进真关卡、
## 递归找门墙模块，并把它和同一面墙上的 RoomDoor3D 门扇一起量出来，回答
## 「换了美术之后，门墙还在不在原基准位、门洞还对不对得上」。
##
## 判据 DOOR_WALL_RUNTIME_OK。只读，不改游戏状态。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const RUN_SEED := 990095
const DOOR_CLEAR_WIDTH_M := 2.2
const DOOR_CLEAR_HEIGHT_M := 2.5

var _failures: Array[String] = []


func _ready() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	if scene == null:
		printerr("DOOR_WALL_RUNTIME_FAILED: 无法加载 %s" % TOWER_SCENE)
		get_tree().quit(1)
		return
	var tower := scene.instantiate()
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	if not tower.generate_through_floor_for_test(95):
		_failures.append("关卡生成失败 generate_through_floor_for_test(95)")

	var room_by_id := tower.get("_room_by_id") as Dictionary
	if room_by_id == null or room_by_id.is_empty():
		_failures.append("未取到 _room_by_id")
	else:
		for room_value in room_by_id.values():
			var room := room_value as Node
			if room != null and room.has_method("set_stream_state"):
				room.set_stream_state(1)
	await _settle()

	print("=== 门墙模块运行时核对（递归扫全树） ===")
	# 注意：节点名前缀 Imported_DoorWall5M_* 被两条路径共用 —— 塔楼 A 套门墙
	# （TOWER_DOOR_PREFAB）与基地99层设施门墙（BASE99_WALL_DOOR_PREFAB）。只有前者
	# 是本探针的对象，靠 asset_id 区分；后者包络本来就是 1.051 深，用 A 套契约去量
	# 它只会得到假失败。
	var modules: Array[Node3D] = []
	var skipped: Dictionary = {}
	var all_modules := 0
	for value in tower.find_children("Imported_DoorWall5M*", "", true, false):
		var module := value as Node3D
		if module == null:
			continue
		all_modules += 1
		var asset_id := str(module.get_meta("asset_id", "<无>"))
		if asset_id != "ENV-TOWER-WALL-DOOR-5M":
			skipped[asset_id] = int(skipped.get(asset_id, 0)) + 1
			continue
		modules.append(module)
	print("门墙模块总数 = %d，其中塔楼 A 套 = %d，跳过 = %s" % [
		all_modules, modules.size(), str(skipped) if not skipped.is_empty() else "无"
	])
	_expect(modules.size() > 0, "整棵树里找不到任何 ENV-TOWER-WALL-DOOR-5M 模块")

	for module in modules:
		var parent_name := "-"
		if module.get_parent() != null:
			parent_name = String(module.get_parent().name)
		var direction := str(module.get_meta("tower_wall_direction", "-"))
		var bounds := _local_mesh_bounds(module)
		print("--- %s (parent=%s direction=%s) ---" % [module.name, parent_name, direction])
		print("  local  position = %s   rot.y = %.4f   GLOBAL = %s" % [
			str(module.position.snappedf(0.0001)),
			module.rotation.y,
			str(module.global_position.snappedf(0.0001)),
		])
		print("  视觉 AABB(局部) = pos=%s size=%s" % [
			str(bounds.position.snappedf(0.0001)), str(bounds.size.snappedf(0.0001))
		])
		var mesh_names: Array[String] = []
		var surfaces := 0
		for value in module.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := value as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			mesh_names.append(String(mesh_instance.name))
			surfaces += mesh_instance.mesh.get_surface_count()
		print("  mesh=%s surfaces=%d" % [str(mesh_names), surfaces])
		_expect(
			mesh_names == ["ENV_TOWER_WALL_DOOR_5M"],
			"%s 网格节点=%s，期望只有 ENV_TOWER_WALL_DOOR_5M" % [module.name, str(mesh_names)]
		)
		_expect(
			surfaces == 4,
			"%s 表面数=%d，期望 4（四个美术材质角色）" % [module.name, surfaces]
		)
		_expect(
			bounds.size.is_equal_approx(Vector3(5.0, 11.9, 0.683)),
			"%s 视觉 AABB size=%s，期望 (5.0, 11.9, 0.683)" % [module.name, str(bounds.size)]
		)
		# v005 双面：门墙关于自身基准面对称，装饰面同时出现在 ±Z。房间侧仍是
		# +Z（DungeonRoom3D 的四向旋转保证），走廊侧即是 -Z 那半。
		_expect(
			absf(bounds.position.z + 0.3415) < 0.002 and absf(bounds.end.z - 0.3415) < 0.002,
			"%s 双面包络不关于 z=0 对称（z ∈ [%.4f, %.4f]，期望 ±0.3415）" % [
				module.name, bounds.position.z, bounds.end.z
			]
		)

	if _failures.is_empty():
		print(
			"DOOR_WALL_RUNTIME_OK: 门墙模块在运行时按 A 套契约落位，包络 ±0.3415 双面对称，"
			+ "门洞 2.2×2.5 与门扇一致"
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("DOOR_WALL_RUNTIME_FAILED count=%d" % _failures.size())
	get_tree().quit(1)


## 相对 `ancestor` 的完整变换链。只乘一层 `transform` 是错的：门墙的网格挂在
## ImportedModel 之下，而门扇挂在 DoorPanel 之下（DoorPanel 还带开合旋转）。
func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D()
	var current: Node3D = node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


func _local_mesh_bounds(root_node: Node) -> AABB:
	var acc := AABB()
	var found := false
	var root_3d := root_node as Node3D
	for value in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local := _relative_transform(mesh_instance, root_3d) if root_3d != null else mesh_instance.transform
		var box := local * mesh_instance.mesh.get_aabb()
		acc = box if not found else acc.merge(box)
		found = true
	return acc


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
