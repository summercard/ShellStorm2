extends RefCounted

const DEFAULT_PIXELS_PER_UNIT := 100.0
const MIN_RADIUS_PX := 0.001

# 在物理帧查询。start、motion、radius 和返回的 normal 都使用 Godot 3D 世界坐标；Z 不参与。
static func hit(emitter: Node3D, start: Vector3, motion: Vector3, radius: float, mask: int, dynamic: bool) -> Dictionary:
	var layer_mask := mask & 0xffffffff
	if not is_instance_valid(emitter) or not emitter.is_inside_tree() or layer_mask == 0:
		return {}
	var context := _canvas_context(emitter)
	var world: World2D = context.world
	var canvas: Transform2D = context.transform
	var ppu: float = context.pixels_per_unit
	var from := canvas * (Vector2(start.x, -start.y) * ppu)
	var travel := canvas.basis_xform(Vector2(motion.x, -motion.y) * ppu)
	if world == null or not from.is_finite() or not travel.is_finite() or travel.length_squared() <= 1.0e-12:
		return {}
	if not is_finite(radius) or is_zero_approx(canvas.determinant()):
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}

	# 非等比/斜切时用覆盖仿射椭圆的最小圆；等比缩放和旋转时精确。
	var xx := canvas.x.length_squared()
	var yy := canvas.y.length_squared()
	var xy := canvas.x.dot(canvas.y)
	var largest_scale := sqrt(0.5 * (xx + yy + sqrt((xx - yy) * (xx - yy) + 4.0 * xy * xy)))
	var circle := CircleShape2D.new()
	circle.radius = maxf(MIN_RADIUS_PX, radius * ppu * largest_scale)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = layer_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = []
	var length := travel.length()
	var forward := travel / length
	while true:
		query.exclude = excluded
		query.transform = Transform2D(0.0, from)
		query.motion = travel
		query.margin = 0.0
		var fractions := space.cast_motion(query)
		if fractions.size() != 2 or (fractions[0] >= 1.0 and fractions[1] >= 1.0):
			return {}

		# cast_motion 给出安全和接触区间，但不返回法线。只在接触点附近取法线，不能退化为中心射线。
		query.motion = Vector2.ZERO
		query.transform = Transform2D(0.0, from + travel * fractions[1])
		var info := space.get_rest_info(query)
		if info.is_empty():
			var contact_slop := clampf(circle.radius * 0.001, 0.001, 0.03)
			query.transform = Transform2D(0.0, query.transform.origin + forward * contact_slop)
			query.margin = contact_slop
			info = space.get_rest_info(query)
		if info.is_empty():
			return {}
		var rid: RID = info.rid
		if not dynamic:
			var collider := instance_from_id(int(info.get("collider_id", 0)))
			if collider is RigidBody2D or collider is CharacterBody2D or collider is AnimatableBody2D:
				if not rid.is_valid() or excluded.has(rid):
					return {}
				excluded.append(rid)
				continue
		var normal: Vector2 = info.normal
		# 法线使用 3D→2D 线性映射的转置拉回，而非直接将变换逆向应用于法线。
		var world_normal := Vector3(canvas.x.dot(normal), -canvas.y.dot(normal), 0.0).normalized()
		if world_normal.is_zero_approx() or motion.dot(world_normal) >= 0.0:
			return {}
		return {"fraction": float(fractions[0]), "normal": world_normal}
	return {}

# 可逐级设置 unity_pixels_per_unit、unity_canvas_origin（世界像素）、
# unity_canvas_transform（将局部像素映射至二维世界）和 unity_canvas_world（World2D）。
# 最近的配置优先；宿主也可提供实时 unity_canvas_collision_context()。
static func _canvas_context(emitter: Node3D) -> Dictionary:
	var world: World2D = null
	var canvas := Transform2D.IDENTITY
	var origin: Variant = null
	var has_transform := false
	var ppu := 0.0
	var node: Node = emitter
	while node != null:
		if ppu <= 0.0:
			var scale_value: Variant = node.get_meta(&"unity_pixels_per_unit", 0.0)
			if not _valid_scale(scale_value) and node == emitter and &"pixels_per_unit" in emitter:
				scale_value = emitter.get(&"pixels_per_unit")
			if _valid_scale(scale_value):
				ppu = float(scale_value)
		if origin == null:
			var origin_value: Variant = node.get_meta(&"unity_canvas_origin", Vector2.INF)
			if origin_value is Vector2 and origin_value.is_finite():
				origin = origin_value
		if not has_transform and node.has_meta(&"unity_canvas_transform"):
			var transform_value: Variant = node.get_meta(&"unity_canvas_transform")
			if transform_value is Transform2D:
				canvas = transform_value
				has_transform = true
		if world == null and node.has_meta(&"unity_canvas_world"):
			world = node.get_meta(&"unity_canvas_world") as World2D
		if node.has_method(&"unity_canvas_collision_context"):
			var injected: Dictionary = node.call(&"unity_canvas_collision_context")
			if world == null:
				world = injected.get("world") as World2D
			if not has_transform and injected.get("transform") is Transform2D:
				canvas = injected.transform
				has_transform = true
			var scale_value: Variant = injected.get("pixels_per_unit")
			if ppu <= 0.0 and _valid_scale(scale_value):
				ppu = float(scale_value)
		if world != null and has_transform and ppu > 0.0 and origin != null:
			break
		node = node.get_parent()
	if world == null:
		world = emitter.get_viewport().find_world_2d()
	if origin != null:
		canvas.origin = origin
	return {"world": world, "transform": canvas, "pixels_per_unit": ppu if ppu > 0.0 else DEFAULT_PIXELS_PER_UNIT}

static func _valid_scale(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0
