@tool
extends RefCounted
## Pure layout operations shared by the editor and its saved-scene tests.

const CATALOG_PATH := "res://assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
const WHITEBOX_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03"
const MAX_BATCH := 4096
const EPS := 0.015
const TAGS := preload("res://tools/scene_builder/catalog_tags.gd")
const SCENE_INDEX := preload("res://tools/scene_builder/scene_index.gd")

static func catalog() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var rows: Array[Dictionary] = []
	var errors: Array[String] = []
	if not raw is Dictionary or not raw.get("components") is Array:
		return {"rows": rows, "errors": ["共享组件目录无法读取"]}
	var ids := {}
	for value in raw["components"]:
		var row: Dictionary = value.duplicate(true)
		var id := str(row.get("component_id", ""))
		var path := str(row.get("prefab_path", ""))
		if id.is_empty() or ids.has(id) or not path.ends_with(".tscn") or not ResourceLoader.exists(path, "PackedScene"):
			errors.append("组件无效或资源缺失：%s / %s" % [id, path])
			continue
		ids[id] = true
		row["group"] = TAGS.kit(row)
		row["type_tag"] = TAGS.type_tag(row)
		row["label"] = TAGS.caption(row)
		rows.append(row)
	return {"rows": rows, "errors": errors}

static func library_group(path: String) -> String:
	for pair in [["boss_room_02", "Boss房02"], ["boss_room", "Boss房"], ["office_room", "办公室"],
		["db_room", "数据库"], ["database", "数据库"], ["corridor", "走廊"],
		["bridge_room", "通道桥"], ["entry_safe_room", "入口安全房"], ["rooftop", "天台"]]:
		if path.contains(pair[0]):
			return pair[1]
	return "通用组件"

static func whiteboxes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in SCENE_INDEX.scan():
		if not entry["whitebox"] or not str(entry["search"]).contains("expedition_03"):
			continue
		rows.append({"label": "%s · %s" % [entry["source_label"], entry["label"]], "path": entry["path"],
			"template_id": entry["template_id"], "size_m": entry["size_m"]})
	return rows

static func default_art_path(whitebox_path: String) -> String:
	var directory := WHITEBOX_DIR if whitebox_path.contains("/egt_room_types/") else whitebox_path.get_base_dir()
	var stem := whitebox_path.get_file().trim_suffix("_static_layout.tscn").trim_prefix("rt_")
	return directory.path_join("art_" + stem + "_a.tscn")

static func create_room(whitebox_path: String, source: PackedScene = null) -> Node3D:
	var scene: PackedScene = source if source != null else load(whitebox_path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return null
	var reference := instance as Node3D
	var root := Node3D.new()
	root.name = "RoomArtLayout"
	for key in ["template_id", "variant", "size_m", "grid_unit_m", "wall_height_m", "footprint_polygon_m",
		"footprint_area_m2", "footprint_is_rect", "walkable_navigation_polygons", "door_width_m", "level_id",
		"shell_id", "egt_kind", "egt_kind_zh", "door_sides"]:
		if reference.has_meta(key):
			root.set_meta(key, reference.get_meta(key))
	if not root.has_meta("template_id") and reference.has_meta("shell_id"):
		root.set_meta("template_id", reference.get_meta("shell_id"))
	if not root.has_meta("level_id") and (whitebox_path.begins_with(WHITEBOX_DIR + "/") or whitebox_path.contains("/egt_room_types/")):
		root.set_meta("level_id", "expedition_03")
	root.set_meta("scene_builder_schema", "shellstorm2.component_scene.v1")
	root.set_meta("whitebox_reference", whitebox_path)
	root.set_meta("room_owned_geometry", false)
	for group_name in ["ArtComponents", "Lighting", "ConnectionPorts"]:
		var group := Node3D.new()
		group.name = group_name
		root.add_child(group)
		group.owner = root
	var ports := reference.get_node_or_null("ConnectionPorts")
	if ports != null:
		for child in ports.get_children():
			if not child is Marker3D:
				continue
			var marker := Marker3D.new()
			marker.name = child.name
			marker.transform = child.transform
			for key in child.get_meta_list():
				marker.set_meta(key, child.get_meta(key))
			root.get_node("ConnectionPorts").add_child(marker)
			marker.owner = root
	reference.free()
	return root

static func phase(root: Node3D, step: float, cell_centers: bool) -> Vector2:
	if not cell_centers or not root.has_meta("size_m"):
		return Vector2.ZERO
	var size: Variant = root.get_meta("size_m")
	return Vector2(-float(size[0]) * 0.5 + step * 0.5, -float(size[1]) * 0.5 + step * 0.5)

static func snap_point(point: Vector3, step: float, origin: Vector2) -> Vector3:
	return Vector3(snappedf(point.x - origin.x, step) + origin.x, point.y,
		snappedf(point.z - origin.y, step) + origin.y)

static func component_phase(root: Node3D, step: float, cell_centers: bool, row: Dictionary, yaw: float) -> Vector2:
	var origin := phase(root, step, cell_centers)
	if not cell_centers or not root.has_meta("size_m") or str(row.get("slot_role", "")) not in ["solid_wall", "door_wall"]:
		return origin
	# Wall centers sit on tile boundaries, while their long axis follows tile centers.
	var room_size: Variant = root.get_meta("size_m")
	var size := component_size(row)
	var along_x := absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.z
	var along_z := absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.z
	if along_x >= along_z:
		origin.y = -float(room_size[1]) * 0.5
	else:
		origin.x = -float(room_size[0]) * 0.5
	return origin

static func line_points(a: Vector3, b: Vector3, step: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var count := maxi(absi(roundi((b.x - a.x) / step)), absi(roundi((b.z - a.z) / step)))
	if count + 1 > MAX_BATCH:
		return points
	for index in range(count + 1):
		var t := float(index) / maxf(1.0, float(count))
		var offset := b - a
		points.append(a + Vector3(roundf(offset.x / step * t) * step, 0,
			roundf(offset.z / step * t) * step))
	return points

static func rectangle_points(a: Vector3, b: Vector3, step: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var nx := absi(roundi((b.x - a.x) / step)) + 1
	var nz := absi(roundi((b.z - a.z) / step)) + 1
	if nx * nz > MAX_BATCH:
		return points
	for x in range(nx):
		for z in range(nz):
			points.append(Vector3(minf(a.x, b.x) + x * step, a.y, minf(a.z, b.z) + z * step))
	return points

static func brush_points(point: Vector3, diameter: int, step: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var offset := int(diameter / 2)
	for x in range(diameter):
		for z in range(diameter):
			points.append(point + Vector3((x - offset) * step, 0, (z - offset) * step))
	return points

static func polygon(root: Node3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not root.has_meta("footprint_polygon_m") or not root.has_meta("size_m"):
		return points
	var size: Variant = root.get_meta("size_m")
	for point in root.get_meta("footprint_polygon_m"):
		points.append(Vector2(float(point[0]) - float(size[0]) * 0.5,
			float(point[1]) - float(size[1]) * 0.5))
	return points

static func inside(point: Vector2, outline: PackedVector2Array) -> bool:
	if outline.is_empty() or Geometry2D.is_point_in_polygon(point, outline):
		return true
	for i in range(outline.size()):
		if Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()]).distance_to(point) < EPS:
			return true
	return false

static func component_size(row: Dictionary) -> Vector3:
	var value: Array = row.get("bounds_size_m_godot", [1, 1, 1])
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func fits(point: Vector3, row: Dictionary, yaw: float, outline: PackedVector2Array) -> bool:
	if outline.is_empty():
		return true
	var size := component_size(row)
	if str(row.get("slot_role", "")) in ["solid_wall", "door_wall"]:
		# Structural walls straddle the perimeter. Clip the wall centerline, not its thickness.
		if size.x >= size.z:
			size.z = 0.01
		else:
			size.x = 0.01
	# Check corners AND the boundary segments: corners alone miss a narrow concave notch.
	var corners := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var local := Vector3(corner.x * size.x * 0.5, 0, corner.y * size.z * 0.5).rotated(Vector3.UP, yaw)
		corners.append(Vector2(point.x + local.x, point.z + local.z))
	for i in range(4):
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var samples := maxi(2, ceili(a.distance_to(b) / 0.25))
		for j in range(samples + 1):
			if not inside(a.lerp(b, float(j) / samples), outline):
				return false
	return inside(Vector2(point.x, point.z), outline)

static func surface_component(row: Dictionary) -> bool:
	var role := str(row.get("slot_role", ""))
	return role.contains("floor") or role in ["tile_upper", "tile_lower"] or str(row.get("category", "")).contains("地砖")

static func blocks_port(root: Node3D, point: Vector3, row: Dictionary, yaw: float) -> bool:
	if surface_component(row) or str(row.get("slot_role", "")) in ["door_wall", "door_leaf_preview"] or point.y >= 3.0:
		return false
	var ports := root.get_node_or_null("ConnectionPorts")
	if ports == null:
		return false
	var size := component_size(row)
	var rotated := Vector3(absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.z,
		size.y, absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.z)
	var bounds := AABB(point - Vector3(rotated.x * 0.5, 0, rotated.z * 0.5), rotated)
	for port in ports.get_children():
		if not port is Node3D:
			continue
		var along_x := str(port.get_meta("side", "")) in ["north", "south"]
		var opening: Variant = port.get_meta("door_opening_m", [2.2, 2.8])
		var port_size := Vector3(float(opening[0]), float(opening[1]), 4.0) if along_x else Vector3(4.0, float(opening[1]), float(opening[0]))
		var port_point: Vector3 = root.to_local(port.global_position) if port.is_inside_tree() else port.position
		if bounds.intersects(AABB(port_point - Vector3(port_size.x * 0.5, 0, port_size.z * 0.5), port_size)):
			return true
	return false

static func instantiate_component(row: Dictionary) -> Node3D:
	var scene := load(str(row.get("prefab_path", ""))) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D if Engine.is_editor_hint() else scene.instantiate() as Node3D
	if node == null:
		return null
	node.set_meta("scene_builder_component", true)
	node.set_meta("component_id", str(row.get("component_id", "")))
	node.set_meta("slot_role", str(row.get("slot_role", "")))
	return node

static func managed_components(root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in root.get_children():
		if child is Node3D and bool(child.get_meta("scene_builder_component", false)):
			result.append(child)
		else:
			result.append_array(managed_components(child))
	return result

static func same_cell(node: Node3D, root: Node3D, point: Vector3) -> bool:
	return root.to_local(node.global_position).distance_to(point) < 0.05

static func position_key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 10), roundi(point.y * 10), roundi(point.z * 10))

static func spatial_index(root: Node3D) -> Dictionary:
	var index := {}
	for node in managed_components(root):
		var key := position_key(root.to_local(node.global_position))
		if not index.has(key):
			index[key] = []
		(index[key] as Array).append(node)
	return index

static func nearby(index: Dictionary, point: Vector3) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var key := position_key(point)
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				for node in index.get(key + Vector3i(x, y, z), []) as Array:
					result.append(node)
	return result

static func validate(root: Node3D) -> Array[String]:
	var issues: Array[String] = []
	var seen := {}
	for node in managed_components(root):
		if node.scene_file_path.is_empty() or not ResourceLoader.exists(node.scene_file_path):
			issues.append("组件失去 Prefab 引用：%s" % node.name)
		if not node.scale.is_equal_approx(Vector3.ONE):
			issues.append("组件存在缩放：%s" % node.name)
		var key := "%s:%s" % [node.get_meta("component_id", ""), root.to_local(node.global_position)]
		if seen.has(key):
			issues.append("同格重复组件：%s" % node.name)
		seen[key] = true
	return issues
