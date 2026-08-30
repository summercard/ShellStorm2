extends Node3D
## 100F 正式房间栏杆验收：实例化 DungeonRoom3D 的 rooftop 壳，校验梁、立柱贴地与计数。

const EXPECTED_RAIL_SEGMENTS := 5
const EXPECTED_POSTS := 67
const FLOOR_Y := 0.0
const POST_TOP_Y := 1.32
const POSITION_TOLERANCE := 0.015


func _ready() -> void:
	var failures: Array[String] = []
	var rooftop := DungeonRoom3D.new()
	rooftop.name = "FormalRooftopRoom"
	rooftop.configure({
		"room_id": "verification_rooftop",
		"room_type": "START",
		"size_class": "rooftop",
		"doors": ["west"],
		"door_targets": {"west": "facility"},
		"seed": 100990,
	})
	add_child(rooftop)
	await get_tree().process_frame
	rooftop.ensure_shell_built()
	await get_tree().physics_frame

	var rail_lowers: Array[Node3D] = []
	var rail_uppers: Array[Node3D] = []
	var rail_posts: Array[Node3D] = []
	_collect_by_prefix(rooftop, "RooftopRailLower_", rail_lowers)
	_collect_by_prefix(rooftop, "RooftopRailUpper_", rail_uppers)
	_collect_by_prefix(rooftop, "RooftopRailPost_", rail_posts)

	_expect(rail_lowers.size() == EXPECTED_RAIL_SEGMENTS, "Rooftop lower-rail segment count is %d; expected %d" % [rail_lowers.size(), EXPECTED_RAIL_SEGMENTS], failures)
	_expect(rail_uppers.size() == EXPECTED_RAIL_SEGMENTS, "Rooftop upper-rail segment count is %d; expected %d" % [rail_uppers.size(), EXPECTED_RAIL_SEGMENTS], failures)
	_expect(rail_posts.size() == EXPECTED_POSTS, "Rooftop post count is %d; expected %d" % [rail_posts.size(), EXPECTED_POSTS], failures)

	for rail: Node3D in rail_lowers:
		var bottom_y: float = rail.position.y - absf(rail.scale.y) * 0.5
		_expect(absf(bottom_y - FLOOR_Y) <= POSITION_TOLERANCE, "%s lower edge is %.3f; expected floor %.3f" % [rail.name, bottom_y, FLOOR_Y], failures)
	for rail: Node3D in rail_uppers:
		var top_y: float = rail.position.y + absf(rail.scale.y) * 0.5
		_expect(absf(top_y - POST_TOP_Y) <= POSITION_TOLERANCE, "%s upper edge is %.3f; expected post top %.3f" % [rail.name, top_y, POST_TOP_Y], failures)
	for post: Node3D in rail_posts:
		var bottom_y: float = post.position.y - absf(post.scale.y) * 0.5
		var top_y: float = post.position.y + absf(post.scale.y) * 0.5
		_expect(absf(bottom_y - FLOOR_Y) <= POSITION_TOLERANCE, "%s bottom is %.3f; expected floor %.3f" % [post.name, bottom_y, FLOOR_Y], failures)
		_expect(absf(top_y - POST_TOP_Y) <= POSITION_TOLERANCE, "%s top is %.3f; expected %.3f" % [post.name, top_y, POST_TOP_Y], failures)

	rooftop.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_RAILING_OK: %d lower rails, %d upper rails and %d posts use the formal rooftop shell and align to Y %.2f..%.2f" % [rail_lowers.size(), rail_uppers.size(), rail_posts.size(), FLOOR_Y, POST_TOP_Y])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _collect_by_prefix(node: Node, prefix: String, output: Array[Node3D]) -> void:
	for child: Node in node.get_children():
		var child_3d := child as Node3D
		if child_3d != null and child.name.begins_with(prefix):
			output.append(child_3d)
		_collect_by_prefix(child, prefix, output)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
