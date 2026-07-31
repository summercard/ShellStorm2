class_name PlayerVision3D
extends Node3D
## 独立于灯光的 3D 单位视野。
## 目标显隐使用 360° 逐目标遮挡；定向射线只驱动地面目光场，灯光不参与玩法判定。

@export_range(6.0, 40.0, 0.5) var vision_range := 21.0
@export_range(30.0, 160.0, 1.0) var vision_angle_degrees := 96.0
@export_range(0.03, 0.25, 0.01) var visibility_interval := 0.04
@export_range(0.5, 5.0, 0.1) var proximity_reveal := 2.4
@export_range(17, 81, 2) var cone_ray_count := 49
@export_range(12, 48, 2) var proximity_ray_count := 28
@export_flags_3d_physics var occlusion_mask := 1

const VISION_TARGET_GROUPS := [
	&"enemy_3d", &"ground_loot_3d", &"room_key_pickup_3d",
	&"hazard_3d", &"service_station_3d", &"extraction_beacon_3d",
]
const VISION_PLANE_HEIGHT := 0.82
const GAMEPLAY_ANGLE_DEGREES := 360.0
const SURFACE_HEIGHT_OFFSET := 0.14
const HIT_EDGE_PADDING := 0.08
const EDGE_FEATHER_WIDTH := 1.85
const DISTANCE_RELEASE_SPEED := 12.0
# 手电表现层：真实 SpotLight3D 的地面贡献会与太阳、房间灯相加，各楼层对比度不同。
# 这里额外画一层固定透明度、受同一套物理射线裁切的无光照扇形，
# 让玩家在任何背景亮度下都能看到完全一致的手电范围。
const FLASHLIGHT_OVERLAY_ALPHA := 0.15
const FLASHLIGHT_OVERLAY_MAX_ANGLE := 150.0
const FLASHLIGHT_OVERLAY_HEIGHT_OFFSET := 0.008
var _player: Player3D
var _cone_surface: MeshInstance3D
var _proximity_surface: MeshInstance3D
var _flashlight_surface: MeshInstance3D
var _cone_mesh := ImmediateMesh.new()
var _proximity_mesh := ImmediateMesh.new()
var _flashlight_mesh := ImmediateMesh.new()
var _fill_material: StandardMaterial3D
var _near_fill_material: StandardMaterial3D
var _flashlight_material: StandardMaterial3D
var _flashlight: PlayerFlashlight3D
var _accumulator := 0.0
var _visible_target_count := 0
var _occluded_target_count := 0
var _last_cone_points := PackedVector3Array()
var _last_proximity_points := PackedVector3Array()
var _last_flashlight_points := PackedVector3Array()
var _visual_refresh_count := 0
var _mesh_redraw_count := 0
var _target_cone_distances := PackedFloat32Array()
var _target_proximity_distances := PackedFloat32Array()
var _target_flashlight_distances := PackedFloat32Array()
var _display_cone_distances := PackedFloat32Array()
var _display_proximity_distances := PackedFloat32Array()
var _display_flashlight_distances := PackedFloat32Array()
var _flashlight_overlay_active := false
var _flashlight_overlay_angle_degrees := 0.0
var _geometry_dirty := true


func _ready() -> void:
	_player = get_parent() as Player3D
	_flashlight = get_node_or_null("../PlayerFlashlight3D") as PlayerFlashlight3D
	if _flashlight != null:
		_flashlight.light_enabled_changed.connect(_on_flashlight_enabled_changed)
	_build_visualization()
	call_deferred("force_refresh")


func _on_flashlight_enabled_changed(_enabled: bool) -> void:
	_geometry_dirty = true


func _process(delta: float) -> void:
	if _player == null:
		return
	_update_visual_transforms()
	_smooth_and_draw_geometry(delta)
	_accumulator += delta
	if _accumulator < visibility_interval:
		return
	_accumulator = fmod(_accumulator, visibility_interval)
	_refresh_vision_samples(false)
	_refresh_target_visibility()


func force_refresh() -> void:
	if _player == null or not is_inside_tree():
		return
	_refresh_vision_samples(true)
	_update_visual_transforms()
	_smooth_and_draw_geometry(1.0)
	_refresh_target_visibility()


func is_position_visible(world_position: Vector3) -> bool:
	if _player == null:
		return false
	var offset := world_position - _player.global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > vision_range:
		return false
	if distance <= 0.001:
		return true
	return not _is_occluded(world_position)


func get_snapshot() -> Dictionary:
	var light_snapshot := _flashlight.get_snapshot() if _flashlight != null else {}
	return {
		"range": vision_range,
		# 兼容旧诊断字段；新代码应显式读取 gameplay/presentation 两个角度。
		"angle_degrees": vision_angle_degrees,
		"gameplay_angle_degrees": GAMEPLAY_ANGLE_DEGREES,
		"presentation_angle_degrees": vision_angle_degrees,
		"gameplay_omnidirectional": true,
		"visibility_mode": "omnidirectional_range_with_physical_occlusion",
		"presentation_mode": "directional_gaze_and_flashlight",
		"proximity_reveal": proximity_reveal,
		"visibility_interval": visibility_interval,
		"visible_targets": _visible_target_count,
		"occluded_targets": _occluded_target_count,
		"visible_enemies": _count_visible_enemies(),
		"shadow_light_count": int(light_snapshot.get("shadow_light_count", 0)),
		"presentation_light_count": int(light_snapshot.get("real_light_count", 0)),
		"spotlight_count": int(light_snapshot.get("spotlight_count", 0)),
		"spill_light_count": int(light_snapshot.get("spill_light_count", 0)),
		"front_fill_light_count": int(light_snapshot.get("front_fill_light_count", 0)),
		"flashlight_real_lighting": not light_snapshot.is_empty(),
		"flashlight_aim_alignment": float(light_snapshot.get("aim_alignment", 0.0)),
		"flashlight_beam_energy": float(light_snapshot.get("beam_energy", 0.0)),
		"flashlight_spill_energy": float(light_snapshot.get("spill_energy", 0.0)),
		"gameplay_light_dependent": false,
		"visual_mode": "soft_raycast_field_with_real_flashlight_rig",
		"soft_edge": true,
		"hard_outline": false,
		"surface_no_depth_test": true,
		"wall_occlusion_enabled": true,
		"cone_ray_count": cone_ray_count,
		"proximity_ray_count": proximity_ray_count,
		"cone_point_count": _last_cone_points.size(),
		"proximity_point_count": _last_proximity_points.size(),
		"flashlight_overlay_active": _flashlight_overlay_active,
		"flashlight_overlay_wall_clipped": true,
		"flashlight_overlay_unshaded": true,
		"flashlight_overlay_alpha": FLASHLIGHT_OVERLAY_ALPHA,
		"flashlight_overlay_angle_degrees": _flashlight_overlay_angle_degrees,
		"flashlight_overlay_range": float(light_snapshot.get("beam_range", 0.0)),
		"flashlight_overlay_point_count": _last_flashlight_points.size(),
		"visual_refresh_count": _visual_refresh_count,
		"mesh_redraw_count": _mesh_redraw_count,
	}


func get_cone_points_for_test() -> PackedVector3Array:
	return _last_cone_points.duplicate()


func get_proximity_points_for_test() -> PackedVector3Array:
	return _last_proximity_points.duplicate()


func _refresh_vision_samples(snap: bool) -> void:
	var aim := _player.aim_direction
	aim.y = 0.0
	if aim.length_squared() <= 0.0001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	_target_cone_distances = _sample_arc_distances(
		aim,
		deg_to_rad(-vision_angle_degrees * 0.5),
		deg_to_rad(vision_angle_degrees * 0.5),
		cone_ray_count,
		vision_range,
	)
	_target_proximity_distances = _sample_arc_distances(
		Vector3.FORWARD,
		-PI,
		PI,
		proximity_ray_count + 1,
		proximity_reveal,
	)
	_refresh_flashlight_overlay_samples(aim)
	if snap or _display_cone_distances.size() != _target_cone_distances.size():
		_display_cone_distances = _target_cone_distances.duplicate()
	if snap or _display_proximity_distances.size() != _target_proximity_distances.size():
		_display_proximity_distances = _target_proximity_distances.duplicate()
	if snap or _display_flashlight_distances.size() != _target_flashlight_distances.size():
		_display_flashlight_distances = _target_flashlight_distances.duplicate()
	if snap:
		_geometry_dirty = true
	_visual_refresh_count += 1


func _refresh_flashlight_overlay_samples(aim: Vector3) -> void:
	## 表现层直接读手电当前的开关、朝向、张角和射程，不复制任何调参数值。
	_flashlight_overlay_active = _flashlight != null and _flashlight.is_light_enabled()
	if not _flashlight_overlay_active:
		_flashlight_overlay_angle_degrees = 0.0
		_target_flashlight_distances = PackedFloat32Array()
		return
	# SpotLight3D.spot_angle 是与中轴的夹角，地面开口角是它的两倍。
	_flashlight_overlay_angle_degrees = minf(
		_flashlight.beam_angle_degrees * 2.0, FLASHLIGHT_OVERLAY_MAX_ANGLE
	)
	_target_flashlight_distances = _sample_arc_distances(
		aim,
		deg_to_rad(-_flashlight_overlay_angle_degrees * 0.5),
		deg_to_rad(_flashlight_overlay_angle_degrees * 0.5),
		cone_ray_count,
		_flashlight.beam_range,
	)


func _sample_arc_distances(
	world_base_direction: Vector3,
	start_angle: float,
	end_angle: float,
	sample_count: int,
	max_distance: float
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var denominator := float(maxi(1, sample_count - 1))
	for index in range(sample_count):
		var ratio := float(index) / denominator
		var angle := lerpf(start_angle, end_angle, ratio)
		var direction := world_base_direction.rotated(Vector3.UP, angle).normalized()
		var distance := _raycast_distance(direction, max_distance)
		result.append(distance)
	return result


func _smooth_and_draw_geometry(delta: float) -> void:
	if _target_cone_distances.is_empty() or _target_proximity_distances.is_empty():
		return
	var needs_redraw := (
		_geometry_dirty
		or _last_cone_points.is_empty()
		or _distance_buffer_changed(_display_cone_distances, _target_cone_distances)
		or _distance_buffer_changed(_display_proximity_distances, _target_proximity_distances)
		or _distance_buffer_changed(_display_flashlight_distances, _target_flashlight_distances)
	)
	if not needs_redraw:
		return
	_display_cone_distances = _smooth_distance_buffer(_display_cone_distances, _target_cone_distances, delta)
	_display_proximity_distances = _smooth_distance_buffer(
		_display_proximity_distances, _target_proximity_distances, delta
	)
	_display_flashlight_distances = _smooth_distance_buffer(
		_display_flashlight_distances, _target_flashlight_distances, delta
	)
	_last_cone_points = _points_from_distances(
		_display_cone_distances,
		deg_to_rad(-vision_angle_degrees * 0.5),
		deg_to_rad(vision_angle_degrees * 0.5),
	)
	_last_proximity_points = _points_from_distances(_display_proximity_distances, -PI, PI)
	_draw_soft_fan(
		_cone_mesh,
		_last_cone_points,
		_fill_material,
		Color(0.13, 0.68, 0.84, 0.13),
		false,
	)
	_draw_flashlight_overlay()
	# Proximity disc disabled: 不再绘制贴身的 360° 圆盘，alpha 也归零。
	# 保留 _proximity_surface 节点和缓冲区方便将来随时打开。
	_proximity_mesh.clear_surfaces()
	_proximity_surface.visible = false
	_mesh_redraw_count += 1
	_geometry_dirty = false


func _draw_flashlight_overlay() -> void:
	if not _flashlight_overlay_active or _display_flashlight_distances.size() < 2:
		_flashlight_mesh.clear_surfaces()
		_last_flashlight_points = PackedVector3Array()
		_flashlight_surface.visible = false
		return
	_last_flashlight_points = _points_from_distances(
		_display_flashlight_distances,
		deg_to_rad(-_flashlight_overlay_angle_degrees * 0.5),
		deg_to_rad(_flashlight_overlay_angle_degrees * 0.5),
	)
	var beam := _flashlight.beam_color
	# alpha 固定，不随 beam_energy、太阳或房间灯变化：这正是"跨楼层一致"的部分。
	_draw_soft_fan(
		_flashlight_mesh,
		_last_flashlight_points,
		_flashlight_material,
		Color(beam.r, beam.g, beam.b, FLASHLIGHT_OVERLAY_ALPHA),
		false,
	)
	_flashlight_surface.visible = true


func _distance_buffer_changed(current: PackedFloat32Array, target: PackedFloat32Array) -> bool:
	if current.size() != target.size():
		return true
	for index in range(target.size()):
		if absf(current[index] - target[index]) > 0.002:
			return true
	return false


func _smooth_distance_buffer(
	current: PackedFloat32Array,
	target: PackedFloat32Array,
	delta: float
) -> PackedFloat32Array:
	if current.size() != target.size():
		return target.duplicate()
	var release_weight := 1.0 - exp(-DISTANCE_RELEASE_SPEED * maxf(0.0, delta))
	for index in range(target.size()):
		var target_distance := target[index]
		# 遮挡靠近时立即收回，避免平滑过程中短暂透墙；空间打开时再柔和展开。
		current[index] = target_distance if target_distance < current[index] else lerpf(
			current[index], target_distance, release_weight
		)
	return current


func _points_from_distances(
	distances: PackedFloat32Array,
	start_angle: float,
	end_angle: float
) -> PackedVector3Array:
	var points := PackedVector3Array()
	var denominator := float(maxi(1, distances.size() - 1))
	for index in range(distances.size()):
		var angle := lerpf(start_angle, end_angle, float(index) / denominator)
		points.append(Vector3.FORWARD.rotated(Vector3.UP, angle) * distances[index])
	return points


func _draw_soft_fan(
	mesh: ImmediateMesh,
	points: PackedVector3Array,
	fill_material: Material,
	fill_color: Color,
	closed_arc: bool
) -> void:
	mesh.clear_surfaces()
	if points.size() < 2:
		return
	var inner_points := PackedVector3Array()
	for point in points:
		var distance := point.length()
		inner_points.append(point.normalized() * maxf(0.04, distance - minf(EDGE_FEATHER_WIDTH, distance * 0.22)))
	var side_feather_samples := maxi(2, int(ceil(points.size() * 0.08)))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill_material)
	for index in range(points.size() - 1):
		var alpha_a := 1.0 if closed_arc else _side_alpha(index, points.size(), side_feather_samples)
		var alpha_b := 1.0 if closed_arc else _side_alpha(index + 1, points.size(), side_feather_samples)
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_set_color(Color(
			fill_color.r,
			fill_color.g,
			fill_color.b,
			fill_color.a if closed_arc else 0.0,
		))
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_set_color(Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_a))
		mesh.surface_add_vertex(inner_points[index])
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_set_color(Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_b))
		mesh.surface_add_vertex(inner_points[index + 1])

		_add_colored_triangle(
			mesh,
			inner_points[index],
			points[index],
			points[index + 1],
			Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_a),
			Color(fill_color.r, fill_color.g, fill_color.b, 0.0),
			Color(fill_color.r, fill_color.g, fill_color.b, 0.0),
		)
		_add_colored_triangle(
			mesh,
			inner_points[index],
			points[index + 1],
			inner_points[index + 1],
			Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_a),
			Color(fill_color.r, fill_color.g, fill_color.b, 0.0),
			Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_b),
		)
	mesh.surface_end()


func _add_colored_triangle(
	mesh: ImmediateMesh,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color_a: Color,
	color_b: Color,
	color_c: Color
) -> void:
	for entry in [[a, color_a], [b, color_b], [c, color_c]]:
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_set_color(entry[1] as Color)
		mesh.surface_add_vertex(entry[0] as Vector3)


func _side_alpha(index: int, point_count: int, feather_samples: int) -> float:
	var edge_distance := mini(index, point_count - 1 - index)
	var value := clampf(float(edge_distance) / float(maxi(1, feather_samples)), 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)


func _update_visual_transforms() -> void:
	var surface_origin := _player.global_position + Vector3(0, SURFACE_HEIGHT_OFFSET, 0)
	_cone_surface.global_position = surface_origin
	_cone_surface.global_rotation = Vector3(0, _player.aim_yaw, 0)
	_proximity_surface.global_position = surface_origin + Vector3(0, 0.004, 0)
	_proximity_surface.global_rotation = Vector3.ZERO
	_flashlight_surface.global_position = surface_origin + Vector3(
		0, FLASHLIGHT_OVERLAY_HEIGHT_OFFSET, 0
	)
	_flashlight_surface.global_rotation = Vector3(0, _player.aim_yaw, 0)


func _refresh_target_visibility() -> void:
	_visible_target_count = 0
	_occluded_target_count = 0
	var visited: Dictionary = {}
	for group_name in VISION_TARGET_GROUPS:
		for value in get_tree().get_nodes_in_group(group_name):
			var target := value as Node3D
			if target == null or visited.has(target.get_instance_id()):
				continue
			visited[target.get_instance_id()] = true
			if target is Enemy3D:
				var enemy := target as Enemy3D
				if enemy.ai_state == "dead":
					continue
				if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
					enemy.visible = false
					_occluded_target_count += 1
					continue
			var visible_to_player := is_position_visible(_get_target_sample_position(target))
			target.visible = visible_to_player
			if visible_to_player:
				_visible_target_count += 1
			else:
				_occluded_target_count += 1


func _get_target_sample_position(target: Node3D) -> Vector3:
	var height := 0.65
	if target is Enemy3D and (target as Enemy3D).enemy_kind == "boss":
		height = 1.15
	return target.global_position + Vector3(0, height, 0)


func _is_occluded(world_position: Vector3) -> bool:
	var world := _player.get_world_3d()
	if world == null:
		return false
	var start := _player.global_position + Vector3(0, VISION_PLANE_HEIGHT, 0)
	var target := Vector3(world_position.x, start.y, world_position.z)
	if start.distance_squared_to(target) <= 0.0001:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		start,
		target,
		occlusion_mask,
		[_player.get_rid()]
	)
	query.collide_with_areas = false
	return not world.direct_space_state.intersect_ray(query).is_empty()


func _raycast_distance(direction: Vector3, max_distance: float) -> float:
	var world := _player.get_world_3d()
	if world == null:
		return max_distance
	var start := _player.global_position + Vector3(0, VISION_PLANE_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(
		start,
		start + direction * max_distance,
		occlusion_mask,
		[_player.get_rid()]
	)
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return max_distance
	var hit_position := hit.get("position", start + direction * max_distance) as Vector3
	var flat_offset := hit_position - start
	flat_offset.y = 0.0
	return clampf(flat_offset.length() - HIT_EDGE_PADDING, 0.04, max_distance)


func _build_visualization() -> void:
	_fill_material = _make_material(1)
	_near_fill_material = _make_material(2)
	_flashlight_material = _make_material(3)
	_cone_surface = _make_surface("VisionFieldSurface", _cone_mesh)
	_proximity_surface = _make_surface("VisionProximitySurface", _proximity_mesh)
	_flashlight_surface = _make_surface("FlashlightOverlaySurface", _flashlight_mesh)
	_flashlight_surface.visible = false
	if _flashlight != null:
		_flashlight_surface.extra_cull_margin = _flashlight.beam_range + 3.0


func _make_surface(node_name: String, mesh: ImmediateMesh) -> MeshInstance3D:
	var surface := MeshInstance3D.new()
	surface.name = node_name
	surface.mesh = mesh
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.extra_cull_margin = vision_range + 3.0
	surface.top_level = true
	add_child(surface)
	return surface


func _make_material(render_priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = render_priority
	return material


func _count_visible_enemies() -> int:
	var count := 0
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		if value is Enemy3D and (value as Enemy3D).visible and (value as Enemy3D).ai_state != "dead":
			count += 1
	return count
