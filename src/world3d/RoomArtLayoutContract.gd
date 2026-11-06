@tool
extends RefCounted
## Read-only authoring checks. Runtime assembly never edits furnishings through this API.
const LANES := preload("res://src/map/RoomDoorLane.gd")
const FURNISH := preload("res://src/world3d/ManorFurnishing.gd")
const ART := preload("res://src/world3d/RuntimeRoomArtSource.gd")

static func applies(root: Node3D) -> bool:
	return str(root.get_meta("runtime_room_source_schema", "")) == ART.SCHEMA

static func dimensions(root: Node3D) -> Vector2:
	var size: Variant = root.get_meta("size_m", [])
	return Vector2(float(size[0]), float(size[1])) if size is Array and size.size() == 2 else Vector2.ZERO

static func candidate_ports(dim: Vector2) -> Array[Dictionary]:
	var ports: Array[Dictionary] = []
	for side in ["north", "south", "west", "east"]:
		for lane in LANES.lane_offsets(dim.x if side in ["north", "south"] else dim.y):
			ports.append({"side": side, "lane_m": lane})
	return ports

static func door_boxes(dim: Vector2) -> Array[Dictionary]:
	# The existing authoring clearance owns width/margin/depth; do not mirror it.
	return FURNISH._door_boxes(candidate_ports(dim), dim.x * 0.5, dim.y * 0.5)

static func local_transform(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

static func is_structure(root: Node3D, node: Node) -> bool:
	var current := node
	while current != null and current != root:
		if ART.is_structure_prefab(current.scene_file_path):
			return true
		current = current.get_parent()
	return false

static func footprint(tf: Transform3D, size: Vector3) -> PackedVector2Array:
	var points := PackedVector2Array()
	var bounds := AABB(-size * 0.5, size)
	for index in 8:
		var point: Vector3 = tf * bounds.get_endpoint(index)
		points.append(Vector2(point.x, point.z))
	return Geometry2D.convex_hull(points)

static func overlaps_box(points: PackedVector2Array, box: Dictionary) -> bool:
	var corners := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(Vector2(float(box["x"]), float(box["z"])) + corner * Vector2(float(box["hx"]), float(box["hz"])))
	var axes := PackedVector2Array([Vector2.RIGHT, Vector2.DOWN])
	for index in points.size():
		var edge := points[(index + 1) % points.size()] - points[index]
		if edge.length_squared() > 0.000001:
			axes.append(Vector2(-edge.y, edge.x).normalized())
	for axis in axes:
		var a_min := INF
		var a_max := -INF
		var b_min := INF
		var b_max := -INF
		for point in points:
			a_min = minf(a_min, point.dot(axis))
			a_max = maxf(a_max, point.dot(axis))
		for point in corners:
			b_min = minf(b_min, point.dot(axis))
			b_max = maxf(b_max, point.dot(axis))
		if a_max <= b_min + 0.0001 or b_max <= a_min + 0.0001:
			return false
	return true

static func furnishing_conflicts(root: Node3D, actual_ports: Array = []) -> Array[String]:
	var issues: Array[String] = []
	if not applies(root):
		return issues
	var dim := dimensions(root)
	if dim.x <= 0.0 or dim.y <= 0.0:
		issues.append("正式房间缺少有效尺寸，无法检查全部合法门位")
		return issues
	var ports: Array = candidate_ports(dim) if actual_ports.is_empty() else actual_ports
	var boxes := FURNISH._door_boxes(ports, dim.x * .5, dim.y * .5)
	for value in root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := value as CollisionShape3D
		if shape_node.disabled or shape_node.shape == null or is_structure(root, shape_node):
			continue
		var body := shape_node.get_parent() as CollisionObject3D
		if body == null or body is Area3D or body.collision_layer & 1 == 0:
			continue
		var tf := local_transform(root, shape_node)
		var bounds: AABB = tf * shape_node.shape.get_debug_mesh().get_aabb()
		if bounds.end.y <= 0.05 or bounds.position.y >= 2.8:
			continue
		# Existing room furniture uses boxes. Other shapes get a conservative
		# projected envelope instead of being silently declared safe.
		var points := footprint(tf, (shape_node.shape as BoxShape3D).size) if shape_node.shape is BoxShape3D else footprint(Transform3D(Basis.IDENTITY, bounds.get_center()), bounds.size)
		for index in boxes.size():
			if overlaps_box(points, boxes[index]):
				issues.append("陈设挡住合法门前净空：%s · %s@%.2fm" % [root.get_path_to(shape_node), ports[index]["side"], float(ports[index]["lane_m"])])
	return issues
