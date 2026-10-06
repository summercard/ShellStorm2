extends Node

const OUTPUT_PATH := "C:/tmp/ss2_base99_radio_v003_placement.log"
const RADIO_NAME := "99F床边桌独立收音机"

func _ready() -> void:
	var lines: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	await _settle()
	var rooms := tower.get("_room_by_id") as Dictionary
	var facility := rooms.get("facility") as DungeonRoom3D
	if facility == null:
		lines.append("ERROR=facility_missing")
		_write(lines, 1)
		return
	tower.player.global_position = facility.to_global(Vector3(0.0, 5.05, 0.0))
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var radio := tower.find_child(RADIO_NAME, true, false) as Base99Radio3D
	var battery := tower.find_child("46_BATTERY模块收纳箱_资产包", true, false) as Node3D
	var medical := tower.find_child("45_MEDICAL模块收纳箱_资产包", true, false) as Node3D
	var food := tower.find_child("47_FOOD模块收纳箱_资产包", true, false) as Node3D
	lines.append("RADIO_PATH=%s" % str(radio.get_path()) if radio != null else "RADIO_MISSING")
	if radio != null:
		lines.append("RADIO_NODE global=%s local=%s rot_y=%.6f scale=%s" % [_v3(radio.global_position), _v3(radio.position), radio.global_rotation.y, _v3(radio.scale)])
		var rb := _world_bounds(radio)
		var visual_bounds := _world_bounds(radio.get_node_or_null("Visual"))
		lines.append("RADIO_BOUNDS_ALL_MESHES min=%s max=%s size=%s" % [_v3(rb.position), _v3(rb.end), _v3(rb.size)])
		lines.append("RADIO_BOUNDS_VISUAL min=%s max=%s size=%s" % [_v3(visual_bounds.position), _v3(visual_bounds.end), _v3(visual_bounds.size)])
		lines.append("RADIO_GROUND=%0.6f RADIO_TOP=%0.6f" % [visual_bounds.position.y, visual_bounds.end.y])
		lines.append("RADIO_COLLISION=%s" % _shape_info(radio.get_node_or_null("WorldCollision/Shape") as CollisionShape3D))
		lines.append("RADIO_HIT=%s" % _shape_info(radio.get_node_or_null("InteractionHitArea/Shape") as CollisionShape3D))
	for item in [battery, medical, food]:
		if item == null:
			lines.append("CABINET_MISSING")
			continue
		var b := _world_bounds(item)
		lines.append("CABINET name=%s path=%s bounds_min=%s bounds_max=%s size=%s" % [item.name, str(item.get_path()), _v3(b.position), _v3(b.end), _v3(b.size)])
		_dump_meshes(item, lines)
	if radio != null and battery != null:
		var radio_visual := radio.get_node_or_null("Visual") as Node3D
		var radio_bounds := _world_bounds(radio_visual)
		var table_bounds := _world_bounds(battery)
		var support := _support_surface(battery)
		var footprint := _radio_footprint_samples(radio)
		var covered := 0
		for point in footprint:
			if _point_on_support(point, support):
				covered += 1
		lines.append("RELATION radio_visual_over_battery=%s ground_delta=%.6f x_overlap=%.6f z_overlap=%.6f" % [
			radio_bounds.position.y >= table_bounds.end.y - 0.01,
			radio_bounds.position.y - table_bounds.end.y,
			_min_overlap(radio_bounds.position.x, radio_bounds.end.x, table_bounds.position.x, table_bounds.end.x),
			_min_overlap(radio_bounds.position.z, radio_bounds.end.z, table_bounds.position.z, table_bounds.end.z),
		])
		lines.append("SUPPORT_TOP_TRIANGLES=%d support_y=[%.6f,%.6f] footprint_samples=%d covered=%d fully_supported=%s" % [support.size(), _support_y_min(support), _support_y_max(support), footprint.size(), covered, covered == footprint.size()])
		for triangle in support:
			lines.append("  SUPPORT_TRIANGLE %s %s %s" % [_v3(triangle[0]), _v3(triangle[1]), _v3(triangle[2])])
		var bad_point := radio.global_position + Vector3(2.0, 0.0, 0.0)
		var negative_pass := not _point_on_support(bad_point, support)
		lines.append("NEGATIVE_OUTSIDE_SUPPORT_REJECTED=%s" % negative_pass)
		var no_overlap := true
		var art := facility.get_node_or_null("Art")
		for value in art.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := value as MeshInstance3D
			if radio.is_ancestor_of(mesh_node) or battery.is_ancestor_of(mesh_node) or not mesh_node.is_visible_in_tree():
				continue
			var other := _world_mesh_bounds(mesh_node)
			var overlap := radio_bounds.intersection(other)
			if overlap.size.x > 0.002 and overlap.size.y > 0.002 and overlap.size.z > 0.002:
				var intersects := _mesh_intersects_radio_box(mesh_node, radio)
				lines.append("OBSTACLE_BROAD_PHASE=%s precise_triangle_box_hit=%s" % [str(mesh_node.get_path()), intersects])
				if intersects:
					no_overlap = false
		lines.append("NO_OTHER_VISIBLE_ART_TRIANGLE_BOX_INTERSECTION=%s" % no_overlap)
		var geometry_negative_pass := _triangle_box_overlap(Vector3(-0.1, 0.0, -0.1), Vector3(0.1, 0.0, -0.1), Vector3(0.0, 0.0, 0.1), Vector3.ONE) and not _triangle_box_overlap(Vector3(2.0, 0.0, 0.0), Vector3(2.0, 0.1, 0.0), Vector3(2.0, 0.0, 0.1), Vector3.ONE)
		lines.append("TRIANGLE_BOX_POSITIVE_AND_NEGATIVE_SELFTEST=%s" % geometry_negative_pass)
		var passed := not support.is_empty() and covered == footprint.size() and negative_pass and geometry_negative_pass and no_overlap and radio.scale.is_equal_approx(Vector3.ONE)
		lines.append("PLACEMENT_ACCEPTED=%s" % passed)
		tower.free()
		await get_tree().process_frame
		_write(lines, 0 if passed else 1)
		return
	tower.free()
	await get_tree().process_frame
	_write(lines, 1)

func _dump_meshes(root: Node, lines: Array[String]) -> void:
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		var b := _world_mesh_bounds(mesh)
		lines.append("  MESH name=%s bounds_min=%s bounds_max=%s size=%s" % [mesh.name, _v3(b.position), _v3(b.end), _v3(b.size)])

func _shape_info(node: CollisionShape3D) -> String:
	if node == null or node.shape == null:
		return "missing"
	return "%s pos=%s size=%s" % [node.shape.get_class(), _v3(node.global_position), _v3((node.shape as BoxShape3D).size if node.shape is BoxShape3D else Vector3.ZERO)]

func _world_bounds(root: Node) -> AABB:
	var result := AABB()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var b := _world_mesh_bounds(value as MeshInstance3D)
		if not found:
			result = b
			found = true
		else:
			result = result.merge(b)
	return result

func _world_mesh_bounds(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var result := AABB()
	var found := false
	for i in 8:
		var point := mesh.global_transform * local.get_endpoint(i)
		if not found:
			result = AABB(point, Vector3.ZERO)
			found = true
		else:
			result = result.expand(point)
	return result

func _support_surface(root: Node) -> Array:
	var candidates: Array = []
	var highest := -INF
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := value as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_INDEX] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var a := mesh_node.global_transform * vertices[indices[i]]
				var b := mesh_node.global_transform * vertices[indices[i + 1]]
				var c := mesh_node.global_transform * vertices[indices[i + 2]]
				# Godot 正面三角形采用顺时针绕序。
				var normal := (c - a).cross(b - a).normalized()
				var y := (a.y + b.y + c.y) / 3.0
				if normal.y > 0.8:
					highest = max(highest, y)
					candidates.append([a, b, c, y])
	var result: Array = []
	for triangle in candidates:
		if triangle[3] >= highest - 0.002:
			result.append([triangle[0], triangle[1], triangle[2]])
	return result

func _radio_footprint_samples(radio: Node3D) -> Array[Vector3]:
	var local_bounds := AABB()
	var found := false
	for value in radio.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		for i in 8:
			var point := radio.to_local(mesh.global_transform * mesh.get_aabb().get_endpoint(i))
			if not found:
				local_bounds = AABB(point, Vector3.ZERO)
				found = true
			else:
				local_bounds = local_bounds.expand(point)
	var points: Array[Vector3] = []
	for x in 11:
		for z in 11:
			points.append(radio.to_global(Vector3(lerp(local_bounds.position.x, local_bounds.end.x, x / 10.0), local_bounds.position.y, lerp(local_bounds.position.z, local_bounds.end.z, z / 10.0))))
	return points

func _point_on_support(point: Vector3, triangles: Array) -> bool:
	for triangle in triangles:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		if abs(point.y - a.y) > 0.01 or abs(point.y - b.y) > 0.01 or abs(point.y - c.y) > 0.01:
			continue
		var v0 := b - a
		var v1 := c - a
		var v2 := point - a
		var d00 := v0.dot(v0)
		var d01 := v0.dot(v1)
		var d11 := v1.dot(v1)
		var d20 := v2.dot(v0)
		var d21 := v2.dot(v1)
		var denominator := d00 * d11 - d01 * d01
		if abs(denominator) < 0.000001:
			continue
		var v := (d11 * d20 - d01 * d21) / denominator
		var w := (d00 * d21 - d01 * d20) / denominator
		var u := 1.0 - v - w
		if u >= -0.001 and v >= -0.001 and w >= -0.001:
			return true
	return false

func _support_y_min(triangles: Array) -> float:
	var result := INF
	for triangle in triangles:
		for point in triangle:
			result = min(result, (point as Vector3).y)
	return result if result < INF else NAN

func _support_y_max(triangles: Array) -> float:
	var result := -INF
	for triangle in triangles:
		for point in triangle:
			result = max(result, (point as Vector3).y)
	return result if result > -INF else NAN

func _mesh_intersects_radio_box(mesh_node: MeshInstance3D, radio: Node3D) -> bool:
	var center := Vector3(0.0, 0.411, 0.0)
	var half := Vector3(0.414, 0.411, 0.228)
	for surface in mesh_node.mesh.get_surface_count():
		var arrays := mesh_node.mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_INDEX] == null:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a := radio.to_local(mesh_node.global_transform * vertices[indices[i]]) - center
			var b := radio.to_local(mesh_node.global_transform * vertices[indices[i + 1]]) - center
			var c := radio.to_local(mesh_node.global_transform * vertices[indices[i + 2]]) - center
			if _triangle_box_overlap(a, b, c, half):
				return true
	return false

func _triangle_box_overlap(a: Vector3, b: Vector3, c: Vector3, half: Vector3) -> bool:
	var edges := [b - a, c - b, a - c]
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK, (b - a).cross(c - a)]
	for edge in edges:
		for box_axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			axes.append((edge as Vector3).cross(box_axis))
	for axis in axes:
		if axis.length_squared() < 0.00000001:
			continue
		var radius: float = half.x * absf(axis.x) + half.y * absf(axis.y) + half.z * absf(axis.z)
		var low: float = minf(a.dot(axis), minf(b.dot(axis), c.dot(axis)))
		var high: float = maxf(a.dot(axis), maxf(b.dot(axis), c.dot(axis)))
		if low > radius + 0.000001 or high < -radius - 0.000001:
			return false
	return true

func _min_overlap(a0: float, a1: float, b0: float, b1: float) -> float:
	return max(0.0, min(a1, b1) - max(a0, b0))

func _v3(value: Vector3) -> String:
	return "(%.5f,%.5f,%.5f)" % [value.x, value.y, value.z]

func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout

func _write(lines: Array[String], code: int) -> void:
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for line in lines:
		print(line)
	get_tree().quit(code)
