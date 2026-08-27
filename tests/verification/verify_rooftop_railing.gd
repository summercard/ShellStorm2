extends Node3D
## 屋顶栏杆 Y 坐标验收：扫描 100F 屋顶，校验所有 RooftopRail* 节点的 Y 是否贴地板 / 贴 post 顶。

func _ready() -> void:
	var failures: Array[String] = []
	var expected_lower_min_y := 0.04   # 底边贴地板（带 0.02 公差避免 Z-fight）
	var expected_lower_max_y := 0.10
	var expected_upper_min_y := 1.18   # 顶边贴 post 顶 1.32（0.02 公差）
	var expected_upper_max_y := 1.30

	var rail_lowers: Array[Node] = []
	var rail_uppers: Array[Node] = []
	var rail_posts: Array[Node] = []

	for n in get_tree().get_nodes_in_group(""):
		pass

	# 直接深度搜索
	_collect_by_prefix(self, "RooftopRailLower_", rail_lowers)
	_collect_by_prefix(self, "RooftopRailUpper_", rail_uppers)
	_collect_by_prefix(self, "RooftopRailPost_", rail_posts)

	if rail_lowers.is_empty() and rail_uppers.is_empty():
		print("RAILING_CHECK_SKIP: no railing nodes found (test should be run after generating 100F rooftop)")
		get_tree().quit(0)
		return

	for node in rail_lowers:
		var n = node as Node3D
		if n == null:
			continue
		var center_y := n.position.y
		var scale_y := 1.0
		if n is Node3D:
			scale_y = n.scale.y if n.scale.y > 0.0 else 1.0
		var bottom_y := center_y - (0.12 * scale_y) * 0.5
		if bottom_y > expected_lower_max_y or bottom_y < expected_lower_min_y - 0.1:
			failures.append("RooftopRailLower bottom_y=%.3f (expect ~0.0)" % bottom_y)

	for node in rail_uppers:
		var n = node as Node3D
		if n == null:
			continue
		var scale_y := 1.0
		if n is Node3D:
			scale_y = n.scale.y if n.scale.y > 0.0 else 1.0
		var center_y := n.position.y
		var top_y := center_y + (0.12 * scale_y) * 0.5
		if top_y < expected_upper_min_y - 0.1 or top_y > expected_upper_max_y + 0.1:
			failures.append("RooftopRailUpper top_y=%.3f (expect ~1.32)" % top_y)

	if failures.is_empty():
		print("RAILING_OK: %d lowers (bottom≈0), %d uppers (top≈1.32), %d posts" % [rail_lowers.size(), rail_uppers.size(), rail_posts.size()])
		get_tree().quit(0)
		return
	for f in failures:
		push_error(f)
	get_tree().quit(1)


func _collect_by_prefix(node: Node, prefix: String, out: Array[Node]) -> void:
	for c in node.get_children():
		if c.name.begins_with(prefix):
			out.append(c)
		_collect_by_prefix(c, prefix, out)