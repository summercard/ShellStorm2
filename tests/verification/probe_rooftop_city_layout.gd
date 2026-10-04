extends Node
## 2026-10-04：远景楼只按用户手工布局。禁止旧环带或程序城市叠加。
## 比较已保存编辑源与正式运行场景；不写回、不自动补楼、不约束手工环距。

const SOURCE_PATH := "res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn"
var _failures: Array[String] = []

func _world_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _ready() -> void:
	var source_hash := FileAccess.get_sha256(SOURCE_PATH)
	var source := (load(SOURCE_PATH) as PackedScene).instantiate()
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", 990095)
	add_child(tower)
	for frame in range(120):
		await get_tree().process_frame
		if frame == 11 or frame == 119:
			_verify(tower, source, frame + 1)
	_expect(source_hash == FileAccess.get_sha256(SOURCE_PATH), "检查期间编辑源发生变化，请停止编辑后重测")
	source.free()
	tower.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("PROBE_CITY_LAYOUT_OK 手工布局逐件一致；旧环带和程序城市均未生成")
	else:
		for message in _failures:
			print("PROBE_CITY_LAYOUT_FAIL: ", message)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _verify(tower: Node, source: Node, frame: int) -> void:
	var atmosphere := tower.get_node_or_null("TowerAtmosphere3D")
	_expect(atmosphere != null, "缺少环境控制器")
	if atmosphere != null:
		_expect(not bool(atmosphere.get("legacy_city_silhouette_enabled")), "正式入口启用了旧城市")
		var legacy_layout: Array = atmosphere.call("get_city_layout")
		_expect(legacy_layout.is_empty(), "旧城市摆位表应为空")
	_expect(tower.find_children("RooftopCityBelow", "Node3D", true, false).is_empty(), "旧环带节点被生成")
	var chunks := tower.get_node_or_null("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation/AuthoredCityChunks")
	_expect(chunks != null, "缺少正式手工布局节点")
	if chunks == null:
		return
	_expect(chunks.get_parent().get_node_or_null("ProceduralCity500") == null, "不允许程序城市叠加")
	var count := 0
	var buildings := 0
	var meshes := 0
	for child in source.get_children():
		if not child is Node3D or not child.has_meta("chunk_id"):
			continue
		count += 1
		var actual := chunks.get_node_or_null(NodePath(str(child.name))) as Node3D
		_expect(actual != null, "缺少区块 " + str(child.name))
		if actual == null:
			continue
		_expect(child.scene_file_path == actual.scene_file_path, "区块资源不同 " + str(child.name))
		_expect(_world_transform(child).is_equal_approx(actual.global_transform), "区块世界变换不同 " + str(child.name))
		_expect(child.visible == actual.visible, "区块可见性覆盖不同 " + str(child.name))
		for building in child.get_node("buildings").get_children():
			buildings += 1
			var actual_building := actual.get_node_or_null(child.get_path_to(building)) as Node3D
			_expect(actual_building != null, "缺少楼栋 " + str(building.name))
			if actual_building != null:
				_expect(_world_transform(building).is_equal_approx(actual_building.global_transform), "楼栋世界变换不同 " + str(building.name))
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			var actual_mesh := actual.get_node_or_null(child.get_path_to(mesh)) as Node3D
			_expect(actual_mesh != null, "缺少网格 " + str(mesh.name))
			if actual_mesh != null:
				_expect(_world_transform(mesh).is_equal_approx(actual_mesh.global_transform), "网格世界变换不同 " + str(mesh.name))
	_expect(count == chunks.get_child_count(), "存在未授权区块或区块缺失")
	print("CITY_LAYOUT frame=%d chunks=%d buildings=%d meshes=%d failures=%d legacy_city=absent" % [frame, count, buildings, meshes, _failures.size()])
