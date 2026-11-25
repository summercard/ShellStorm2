@tool
extends RefCounted
## Owns one aperture request. Each static shape is rebuilt from its original
## resource and the union of all currently active requests.

class Aperture:
	var frame: Transform3D
	var half_size: Vector3


class Binding:
	var source: CollisionShape3D
	var body: StaticBody3D
	var owner_id: int
	var shape: Shape3D
	var apertures: Dictionary[int, Aperture] = {}


static var _bindings: Dictionary[int, Binding] = {}
var _bound: Dictionary[int, bool] = {}
var unsupported_count := 0


static func collect_sources(host: Node, roots: Array[NodePath], exclusions: Array[NodePath]) -> Array[CollisionShape3D]:
	var sources: Dictionary[int, CollisionShape3D] = {}
	if roots.is_empty():
		_collect(host.get_parent(), sources)
	else:
		for path in roots:
			_collect(host.get_node_or_null(path), sources)
	var excluded: Dictionary[int, CollisionShape3D] = {}
	for path in exclusions:
		_collect(host.get_node_or_null(path), excluded)
	for id in excluded:
		sources.erase(id)
	var result: Array[CollisionShape3D] = []
	result.assign(sources.values())
	return result


static func _collect(node: Node, result: Dictionary[int, CollisionShape3D]) -> void:
	if node == null or (node is PhysicsBody3D and not _is_stationary_body(node)):
		return
	var source := node as CollisionShape3D
	if source != null and _is_stationary_body(source.get_parent()):
		result[source.get_instance_id()] = source
	for child in node.get_children():
		_collect(child, result)


static func _is_stationary_body(node: Node) -> bool:
	return node is StaticBody3D and not node is AnimatableBody3D


func tracks_source(node: Node) -> bool:
	return node is CollisionShape3D and (_is_stationary_body(node.get_parent()) or _bound.has(node.get_instance_id()))


## Called outside physics query callbacks, after node topology has settled.
func sync(sources: Array[CollisionShape3D], frame: Transform3D, half_size: Vector3) -> void:
	unsupported_count = 0
	var active: Dictionary[int, bool] = {}
	if half_size.x > 0.0 and half_size.y > 0.0 and half_size.z > 0.0:
		var opening := AABB(-half_size, half_size * 2.0)
		var world_bounds := frame * opening
		var from_world := frame.inverse()
		for source in sources:
			if not is_instance_valid(source) or not source.is_inside_tree() or source.shape == null:
				continue
			var bounds := _shape_bounds(source.shape)
			var shape_frame := source.global_transform
			if not world_bounds.intersects(shape_frame * bounds):
				continue
			if not (source.shape is BoxShape3D or source.shape is ConcavePolygonShape3D):
				if not opening.encloses(from_world * shape_frame * bounds):
					unsupported_count += 1
					continue
			var id := source.get_instance_id()
			if _bind(source, id, shape_frame.affine_inverse() * frame, half_size):
				active[id] = true
	for id in _bound:
		if not active.has(id):
			_unbind(id)
	_bound = active


func clear() -> void:
	for id in _bound:
		_unbind(id)
	_bound.clear()
	unsupported_count = 0


func active_count() -> int:
	return _bound.size()


func _bind(source: CollisionShape3D, id: int, local_frame: Transform3D, half_size: Vector3) -> bool:
	var body := source.get_parent() as StaticBody3D
	if not _is_stationary_body(body):
		return false
	var binding: Binding = _bindings.get(id)
	if binding != null and (binding.body != body or not body.get_shape_owners().has(binding.owner_id)):
		_bindings.erase(id)
		binding = null
	if binding == null:
		for owner_id in body.get_shape_owners():
			if body.shape_owner_get_owner(owner_id) == source:
				binding = Binding.new()
				binding.source = source
				binding.body = body
				binding.owner_id = owner_id
				_bindings[id] = binding
				break
		if binding == null:
			return false
	var key := get_instance_id()
	var previous: Aperture = binding.apertures.get(key)
	if (previous != null and binding.shape == source.shape
			and previous.frame.is_equal_approx(local_frame) and previous.half_size.is_equal_approx(half_size)):
		return true
	var hole := Aperture.new()
	hole.frame = local_frame
	hole.half_size = half_size
	binding.apertures[key] = hole
	_rebuild(binding)
	return true


func _unbind(id: int) -> void:
	var binding: Binding = _bindings.get(id)
	if binding == null:
		return
	binding.apertures.erase(get_instance_id())
	_rebuild(binding)
	if binding.apertures.is_empty():
		_bindings.erase(id)


static func _shape_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		return AABB(shape.size * -0.5, shape.size)
	return shape.get_debug_mesh().get_aabb()


static func _rebuild(binding: Binding) -> void:
	if not is_instance_valid(binding.source) or not is_instance_valid(binding.body):
		return
	if not binding.body.get_shape_owners().has(binding.owner_id):
		return
	var original := binding.source.shape
	binding.shape = original
	var replacements: Array[Shape3D] = []
	if original != null:
		if binding.apertures.is_empty():
			replacements.append(original)
		elif original is BoxShape3D:
			replacements = _cut_box(original, binding.apertures.values())
		elif original is ConcavePolygonShape3D:
			var remainder := _cut_triangle_mesh(original, binding.apertures.values())
			if remainder != null:
				replacements.append(remainder)
		else:
			var bounds := _shape_bounds(original)
			var fully_cut := false
			for aperture: Aperture in binding.apertures.values():
				var cut := AABB(-aperture.half_size, aperture.half_size * 2.0)
				if cut.encloses(aperture.frame.affine_inverse() * bounds):
					fully_cut = true
					break
			if not fully_cut:
				replacements.append(original)
	# Keep the actual CollisionObject3D, shape owner, transform and disabled flag.
	binding.body.shape_owner_clear_shapes(binding.owner_id)
	for shape in replacements:
		binding.body.shape_owner_add_shape(binding.owner_id, shape)


static func _planes(aperture: Aperture) -> Array[Plane]:
	var planes := Geometry3D.build_box_planes(aperture.half_size)
	for i in planes.size():
		planes[i] = aperture.frame * planes[i]
	return planes


static func _cut_box(box: BoxShape3D, apertures: Array[Aperture]) -> Array[Shape3D]:
	var regions: Array = [Geometry3D.build_box_planes(box.size * 0.5)]
	for aperture in apertures:
		var cut := _planes(aperture)
		var next: Array = []
		for region: Array[Plane] in regions:
			if not _has_volume(Geometry3D.compute_convex_mesh_points(region + cut)):
				next.append(region)
				continue
			var inside := region.duplicate()
			# Outside pieces are disjoint. Each cut plane keeps one piece on
			# its outside while the inside remainder advances to the next plane.
			for plane in cut:
				var outside := inside.duplicate()
				outside.append(-plane)
				if _has_volume(Geometry3D.compute_convex_mesh_points(outside)):
					next.append(outside)
				inside.append(plane)
		regions = next
	var result: Array[Shape3D] = []
	for region: Array[Plane] in regions:
		var piece := ConvexPolygonShape3D.new()
		piece.points = Geometry3D.compute_convex_mesh_points(region)
		piece.margin = box.margin
		result.append(piece)
	return result


static func _has_volume(points: PackedVector3Array) -> bool:
	if points.size() < 4:
		return false
	var pivot := points[0]
	var axis := Vector3.ZERO
	var normal := Vector3.ZERO
	for point in points:
		var direction := point - pivot
		if axis == Vector3.ZERO and direction.length_squared() > 0.00000001:
			axis = direction.normalized()
		elif normal == Vector3.ZERO:
			var cross := axis.cross(direction)
			if cross.length_squared() > 0.00000001:
				normal = cross.normalized()
		elif absf(normal.dot(direction)) > 0.0001:
			return true
	return false


static func _cut_triangle_mesh(shape: ConcavePolygonShape3D, apertures: Array[Aperture]) -> ConcavePolygonShape3D:
	var faces := shape.get_faces()
	var output := PackedVector3Array()
	var cuts: Array = []
	for aperture in apertures:
		cuts.append(_planes(aperture))
	for i in range(0, faces.size(), 3):
		var polygons: Array[PackedVector3Array] = [PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]])]
		for cut: Array[Plane] in cuts:
			var next: Array[PackedVector3Array] = []
			for polygon in polygons:
				var inside := polygon
				for plane in cut:
					var outside := Geometry3D.clip_polygon(inside, -plane)
					if outside.size() >= 3:
						next.append(outside)
					inside = Geometry3D.clip_polygon(inside, plane)
					if inside.size() < 3:
						break
			polygons = next
		for polygon in polygons:
			for vertex in range(1, polygon.size() - 1):
				if (polygon[vertex] - polygon[0]).cross(polygon[vertex + 1] - polygon[0]).length_squared() > 0.0000000001:
					output.append(polygon[0])
					output.append(polygon[vertex])
					output.append(polygon[vertex + 1])
	if output.is_empty():
		return null
	var result := ConcavePolygonShape3D.new()
	result.set_faces(output)
	result.backface_collision = shape.backface_collision
	result.margin = shape.margin
	return result
