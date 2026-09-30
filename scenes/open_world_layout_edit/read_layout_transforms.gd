extends SceneTree

## 只读检查并输出变换；永不保存或修改正式场景。
const SCENE := "res://scenes/open_world_layout_edit/open_world_layout_edit.tscn"
const TARGETS := ["RooftopReference", "Tower2", "Tower3", "Skyline08"]
var failures: Array[String] = []

func _initialize() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("工作场景加载失败。")
		quit(1)
		return
	var layout := packed.instantiate() as Node3D
	_check(layout.transform.is_equal_approx(Transform3D.IDENTITY), "根节点必须保持 identity")
	var baseline_mode := "--verify-baseline" in OS.get_cmdline_user_args()
	var route := load(str(layout.get_meta("formal_route_scene"))).instantiate() as Node3D
	_check(route.transform.is_equal_approx(Transform3D.IDENTITY), "正式路线根节点必须保持 identity")
	var output: Dictionary = {"scene": SCENE, "auto_writeback": false, "nodes": {}}
	for target in TARGETS:
		var node := layout.get_node_or_null(target) as Node3D
		_check(node != null, "缺少节点 " + target)
		if node == null:
			continue
		_check(node.get_parent() == layout, target + " 必须位于根节点下")
		_check(node.has_meta("formal_target_scene") and node.has_meta("baseline_transform"), target + " 缺少回填元数据")
		_check(node.scale.is_equal_approx(Vector3.ONE), target + " 缩放必须为1")
		var baseline: Transform3D = node.get_meta("baseline_transform")
		if baseline_mode or target == "RooftopReference":
			_check(node.transform.is_equal_approx(baseline), target + " 与固定基准不一致")
		var mesh_total := _visible_mesh_count(node)
		_check(mesh_total > 0, target + " 没有可视网格")
		var bounds := TowerGeometry3D.resolve_visual_bounds(node, ".")
		_check(bounds.size.length() > 0, target + " 可视包络为空")
		var entry: Dictionary = {
			"position": _vector(node.position),
			"rotation_degrees": _vector(node.rotation_degrees),
			"scale": _vector(node.scale),
			"transform": _transform(node.transform),
			"baseline_transform": _transform(baseline),
			"changed_from_baseline": not node.transform.is_equal_approx(baseline),
			"formal_target_scene": node.get_meta("formal_target_scene"),
			"formal_target_node": node.get_meta("formal_target_node"),
			"writeback_allowed": node.get_meta("writeback_allowed"),
			"visible_mesh_count": mesh_total,
			"bounds_local": {"position": _vector(bounds.position), "size": _vector(bounds.size)},
		}
		if target != "RooftopReference":
			var formal := route.get_node(str(node.get_meta("formal_target_node"))) as Node3D
			entry["formal_current_transform"] = _transform(formal.transform)
			entry["formal_changed_since_baseline"] = not formal.transform.is_equal_approx(baseline)
			if baseline_mode:
				_check(formal.transform.is_equal_approx(baseline), target + " 正式摆位已偏离初始化基准")
		else:
			_check(_pure_visual(node), "天台快照不得含脚本或碰撞")
			_check(int(node.get_meta("floor_tile_count", 0)) == 266, "100×80天台楼面应为266格（扣除中庭和西楼梯井）")
			_check(int(node.get_meta("decor_instance_count", 0)) > 0, "真实天台装饰不能为空")
		output["nodes"][target] = entry
	_check(layout.get_node_or_null("BridgeReference") != null, "独立桥参照缺失")
	_check(layout.get_node("Tower3/support/lower_rail_0").visible == false, "塔3应保留正式入口栏杆隐藏覆写")
	output["failures"] = failures
	output["passed"] = failures.is_empty()
	print(JSON.stringify(output, "\t"))
	print("LAYOUT_CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	route.free()
	layout.free()
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _visible_mesh_count(node: Node) -> int:
	if node is Node3D and not node.visible:
		return 0
	var count := int(node is MeshInstance3D and node.mesh != null)
	for child in node.get_children():
		count += _visible_mesh_count(child)
	return count

func _pure_visual(node: Node) -> bool:
	if node.get_script() != null or node is CollisionObject3D or node is CollisionShape3D:
		print("NON_VISUAL_NODE ", node.name, " type=", node.get_class(), " script=", node.get_script())
		return false
	for child in node.get_children():
		if not _pure_visual(child):
			return false
	return true

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _vector(value.origin), "basis_x": _vector(value.basis.x), "basis_y": _vector(value.basis.y), "basis_z": _vector(value.basis.z)}
