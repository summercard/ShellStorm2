extends SceneTree
## 运行时探针：确认塔楼 4 模块换成正式美术后，PaletteUV 真的可见
## （即验证 preserve_authored_palette 生效，MultiMesh 没有被主题单色材质覆盖）。
##
## 断言：
##   1. Imported_SolidWall5M_*  —— material_override == null（未被 A/B 主题覆盖），
##      mesh 高 == 11.9（是 v003 而非 9m 占位）。
##      （实墙 GLB 本就单表面，PaletteUV 在单材质 UV 通道内取色，故不要求多表面。）
##   2. ImportedOuterParapetGrid5M —— mesh 高 == 1.50（女儿墙 v001），无主题覆盖。
##   3. ImportedFloorTileGrid5M_A/B —— material_override == null，mesh 表面数 >= 2（美术双表面）。
##   4. Imported_DoorWall5M_* 上不得有主题材质覆盖，且其子树里**不得存在**静态门扇
##      节点。门墙美术自 2026-09-19 起改为由战局通用组件库的 wall_door_5m_通用包
##      派生（v004），该通用包本身不含门扇，所以旧 v003 自带的那片 DoorLeaf_OPEN
##      已随重导出消失 —— 门扇一律由 RoomDoor3D 提供。断言方向因此从「必须隐藏」
##      反转为「必须不存在」：留着这条旧方向会让探针在正确资产上反而报错。
##
## 跑法：
##   Godot --headless --path <项目> --script res://assets/art/props/dungeon_3d/qa/probe_tower_palette_visible.gd

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"

var _failures: Array[String] = []
var _lines: Array[String] = []


func _initialize() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	if scene == null:
		printerr("PROBE_FAIL: 无法加载 %s" % TOWER_SCENE)
		quit(1)
		return
	var tower := scene.instantiate()
	tower.test_mode = true
	tower.run_seed_override = 990095
	root.add_child(tower)
	await process_frame
	await process_frame
	if not tower.generate_through_floor_for_test(95):
		_failures.append("关卡生成失败（generate_through_floor_for_test(95)）")

	# 门墙模块要等房间 stream 进来才实例化（与 verify_tower_grid_component_alignment 同做法）。
	var room_by_id := tower.get("_room_by_id") as Dictionary
	if room_by_id == null or room_by_id.is_empty():
		_failures.append("未取到 _room_by_id，无法 stream 房间")
	else:
		for room_value in room_by_id.values():
			var room := room_value as Node
			if room != null and room.has_method("set_stream_state"):
				room.set_stream_state(1)
	await process_frame
	await process_frame

	_scan(tower)

	if _failures.is_empty():
		for line in _lines:
			print(line)
		print("TOWER_PALETTE_VISIBLE_OK: 塔楼墙/女儿墙/地砖均保留美术自带多表面材质，未被主题单色覆盖")
		quit(0)
	else:
		for line in _lines:
			print(line)
		for f in _failures:
			printerr("FAIL: %s" % f)
		printerr("TOWER_PALETTE_VISIBLE_FAILED count=%d" % _failures.size())
		quit(1)


func _scan(root_node: Node) -> void:
	var solid_wall := 0
	var parapet := 0
	var floor_grid := 0
	var door_wall := 0
	var door_leaf := 0
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node == null:
			continue
		for child in node.get_children():
			stack.append(child)
		var name := String(node.name)
		# 门墙与门扇是普通 Node3D 子树，不走 MultiMesh，必须在 MultiMesh 过滤之前判。
		if name.begins_with("Imported_DoorWall5M_"):
			door_wall += 1
			# 门墙美术不再自带静态门扇；这里数的是「残留」，期望恒为 0。
			var leaf_names := _names_containing(node, "DoorLeaf")
			door_leaf += leaf_names.size()
			_lines.append("[门墙] %-46s override=%s doorleaf=%s" % [
				name,
				_first_override_label(node),
				str(leaf_names) if leaf_names.size() > 0 else "none",
			])
			_expect(
				_first_override_label(node) == "null(美术自带)",
				"%s 存在主题材质覆盖，美术被盖掉" % name
			)
		var mm := node as MultiMeshInstance3D
		if mm == null or mm.multimesh == null or mm.multimesh.mesh == null:
			continue
		var mesh := mm.multimesh.mesh
		var surfaces := mesh.get_surface_count()
		var height := mesh.get_aabb().size.y
		if name.begins_with("Imported_SolidWall5M_"):
			solid_wall += 1
			_lines.append(
				"[实墙] %-46s instances=%4d surfaces=%d height=%.3f override=%s"
				% [name, mm.multimesh.instance_count, surfaces, height, _mat_label(mm)]
			)
			_expect(mm.material_override == null, "%s 被主题材质覆盖（material_override 非空）" % name)
			_expect(surfaces >= 1, "%s 没有可用表面" % name)
			_expect(absf(height - 11.9) < 0.05, "%s 墙高=%.3f，不是 v003 的 11.9m" % [name, height])
		elif name == "ImportedOuterParapetGrid5M":
			parapet += 1
			_lines.append(
				"[女儿墙] %-44s instances=%4d surfaces=%d height=%.3f override=%s"
				% [name, mm.multimesh.instance_count, surfaces, height, _mat_label(mm)]
			)
			_expect(surfaces >= 1, "%s 没有可用表面" % name)
			_expect(absf(height - 1.5) < 0.05, "%s 几何高=%.3f，不是 v001 的 1.50m" % [name, height])
		elif name.begins_with("ImportedFloorTileGrid5M_") or name.begins_with("ProtectedFloorPatch5M_"):
			floor_grid += 1
			if mm.multimesh.instance_count > 0:
				_lines.append(
					"[地砖] %-44s instances=%4d surfaces=%d override=%s"
					% [name, mm.multimesh.instance_count, surfaces, _mat_label(mm)]
				)
			_expect(mm.material_override == null, "%s 被主题地砖材质覆盖" % name)
			_expect(surfaces >= 2, "%s 表面数=%d，美术双表面 PaletteUV 缺失" % [name, surfaces])

	_expect(solid_wall > 0, "未找到任何 Imported_SolidWall5M_* 节点（实墙未接入）")
	_expect(parapet > 0, "未找到 ImportedOuterParapetGrid5M（女儿墙未接入）")
	_expect(floor_grid > 0, "未找到地砖 MultiMesh 节点（地砖未接入）")
	_expect(door_wall > 0, "未找到 Imported_DoorWall5M_* 节点（带门墙未接入）")
	_expect(
		door_leaf == 0,
		"带门墙子树里出现 %d 个 DoorLeaf 节点（美术已改为不含门扇的通用组件派生版，"
		% door_leaf + "出现即说明换回了会与 RoomDoor3D 重叠的旧资产）"
	)


## 收集子树里名字含指定片段的节点名（用于「门墙里不许再有静态门扇」这条断言）。
func _names_containing(root_node: Node, needle: String) -> Array[String]:
	var result: Array[String] = []
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node == null:
			continue
		for child in node.get_children():
			stack.append(child)
			if String(child.name).contains(needle):
				result.append(String(child.name))
	return result


## 在一整棵子树里找第一个非空 material_override 的名字；全为空则视为「美术自带」。
func _first_override_label(root_node: Node) -> String:
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node == null:
			continue
		for child in node.get_children():
			stack.append(child)
		var geometry := node as MeshInstance3D
		if geometry != null and geometry.material_override != null:
			return String(geometry.material_override.resource_name)
	return "null(美术自带)"


func _mat_label(mm: MultiMeshInstance3D) -> String:
	if mm.material_override == null:
		return "null(美术自带)"
	return String(mm.material_override.resource_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
