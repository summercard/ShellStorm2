@tool
extends Node3D
## Scene-owned overlay for opaque MeshInstance3D surfaces.

const EROSION_SHADER := preload("res://assets/art/vfx/environment_3d/void_erosion/runtime/scene_void_erosion.gdshader")
const MESH_SCOPE := preload("res://src/vfx/VfxSceneMeshScope.gd")
const COLLISION_CUT := preload("res://src/vfx/VoidCollisionCut3D.gd")
const COLLISION_REVEAL_PROGRESS := 0.075

# RenderingServer exposes one overlay slot per mesh. Claims never enter scene files.
static var _claims: Dictionary[int, WeakRef] = {}

@export_group("覆盖范围")
@export_flags("场景模型", "角色（玩家 / NPC / 敌人）") var affected_categories: int = 3:
	set(value):
		affected_categories = value
		_queue_refresh()
## 可选：指定后，只在这些子树中按类别筛选。留空自动收集。
@export var target_roots: Array[NodePath] = []:
	set(value):
		target_roots = value
		_queue_refresh()
## Use for glass, foliage with vertex animation, and props outside the effect.
@export var excluded_roots: Array[NodePath] = []:
	set(value):
		excluded_roots = value
		_queue_refresh()
## Optional hidden PlaneMesh markers behind seams. Their copies draw only inside the aperture.
@export var seam_fill_planes: Array[NodePath] = []:
	set(value):
		seam_fill_planes = value
		_queue_refresh()
## Preserve serialized legacy hosts; box volumes use category selection instead.
@export_storage var require_explicit_targets := false:
	set(value):
		require_explicit_targets = value
		_queue_refresh()
## 开启后，方块侵蚀也严格限制在盒内，节点缩放参与范围计算。
@export var strict_box_bounds := false:
	set(value):
		strict_box_bounds = value
		_set_uniform(&"strict_box_bounds", value)
		_update_box_extent()
		_queue_refresh()
@export var enabled := true:
	set(value):
		enabled = value
		_queue_refresh()
@export_tool_button("刷新侵蚀目标") var refresh_button: Callable = refresh_targets

@export_group("物理开口")
## 虚空移除阻挡。游戏运行时，在洞内切除选中环境静态碰撞。
@export var remove_collision_in_void := false:
	set(value):
		if remove_collision_in_void == value:
			return
		remove_collision_in_void = value
		_queue_refresh()
## 留空沿用视觉目标树。用于指定与视觉模型分开装配的楼面支撑。
@export var collision_roots: Array[NodePath] = []:
	set(value):
		collision_roots = value
		_queue_refresh()

@export_group("展开")
## Animate this property: 0 is off, 1 is the full box.
@export_range(0.0, 1.0, 0.001) var progress := 1.0:
	set(value):
		var was_active := progress > 0.0
		progress = clampf(value, 0.0, 1.0)
		_set_uniform(&"progress", progress)
		if was_active != (progress > 0.0):
			_queue_refresh()
		_queue_collision_update()
## Full extent in metres. Rotate the node to align the grid with the building.
@export var box_size := Vector3(9.0, 5.0, 9.0):
	set(value):
		box_size = value.abs().max(Vector3(0.05, 0.05, 0.05))
		_update_box_extent()
@export_range(0.08, 5.0, 0.01, "or_greater", "suffix:m") var cell_size := 0.55:
	set(value):
		cell_size = maxf(value, 0.08)
		_set_uniform(&"cell_size", cell_size)
		_queue_collision_update()
@export_range(0.08, 5.0, 0.01, "or_greater", "suffix:m") var edge_width := 1.35:
	set(value):
		edge_width = maxf(value, 0.08)
		_set_uniform(&"edge_width", edge_width)
@export_range(0.0, 1.5, 0.01) var edge_irregularity := 0.8:
	set(value):
		edge_irregularity = clampf(value, 0.0, 1.5)
		_set_uniform(&"edge_irregularity", edge_irregularity)
## Base depth of the voxel walls inside the opening, in metres.
@export_range(0.0, 3.0, 0.01, "suffix:m") var rim_depth := 0.82:
	set(value):
		rim_depth = clampf(value, 0.0, 3.0)
		_set_uniform(&"rim_depth", rim_depth)

@export_group("虚空外观")
@export_color_no_alpha var edge_color := Color(0.73, 0.26, 1.0):
	set(value):
		edge_color = value
		_set_uniform(&"edge_color", edge_color)
@export_color_no_alpha var nebula_color := Color(0.39, 0.19, 0.95):
	set(value):
		nebula_color = value
		_set_uniform(&"nebula_color", nebula_color)
@export_color_no_alpha var warm_accent := Color(1.0, 0.56, 0.67):
	set(value):
		warm_accent = value
		_set_uniform(&"warm_accent", warm_accent)
## Local direction in which the cube field recedes.
@export var interior_axis := Vector3(-0.4, -0.68, -0.62):
	set(value):
		interior_axis = Vector3.DOWN if value.is_zero_approx() else value
		_set_uniform(&"interior_axis", interior_axis.normalized())
@export_range(0.4, 3.0, 0.01) var depth_scale := 1.0:
	set(value):
		depth_scale = clampf(value, 0.4, 3.0)
		_set_uniform(&"depth_scale", depth_scale)
@export_range(0, 12) var cube_count := 12:
	set(value):
		cube_count = clampi(value, 0, 12)
		_set_uniform(&"cube_count", cube_count)
@export_range(0, 12) var far_cube_count := 10:
	set(value):
		far_cube_count = clampi(value, 0, 12)
		_set_uniform(&"far_cube_count", far_cube_count)
@export_range(0.0, 2.0, 0.01) var drift_speed := 0.5:
	set(value):
		drift_speed = clampf(value, 0.0, 2.0)
		_set_uniform(&"drift_speed", drift_speed)
@export_range(0.0, 1.0, 0.01) var star_density := 0.82:
	set(value):
		star_density = clampf(value, 0.0, 1.0)
		_set_uniform(&"star_density", star_density)

var _overlay: ShaderMaterial
var _seam_material: ShaderMaterial
var _targets: Dictionary[int, MeshInstance3D] = {}
var _seam_instances: Array[MeshInstance3D] = []
var _boxed_instances: Dictionary[int, MeshInstance3D] = {}
var _refresh_queued := false
var _collision_cut := COLLISION_CUT.new()
var _collision_sources: Array[CollisionShape3D] = []
var _collision_update_queued := false
var _collision_mode_active := false
var _collision_extent := Vector3.ZERO


func _enter_tree() -> void:
	set_notify_transform(true)
	_overlay = ShaderMaterial.new()
	_overlay.shader = EROSION_SHADER
	_overlay.render_priority = 1
	_overlay.set_shader_parameter(&"progress", progress)
	_overlay.set_shader_parameter(&"strict_box_bounds", strict_box_bounds)
	_overlay.set_shader_parameter(&"cell_size", cell_size)
	_overlay.set_shader_parameter(&"edge_width", edge_width)
	_overlay.set_shader_parameter(&"edge_irregularity", edge_irregularity)
	_overlay.set_shader_parameter(&"rim_depth", rim_depth)
	_overlay.set_shader_parameter(&"edge_color", edge_color)
	_overlay.set_shader_parameter(&"nebula_color", nebula_color)
	_overlay.set_shader_parameter(&"warm_accent", warm_accent)
	_overlay.set_shader_parameter(&"interior_axis", interior_axis.normalized())
	_overlay.set_shader_parameter(&"depth_scale", depth_scale)
	_overlay.set_shader_parameter(&"cube_count", cube_count)
	_overlay.set_shader_parameter(&"far_cube_count", far_cube_count)
	_overlay.set_shader_parameter(&"drift_speed", drift_speed)
	_overlay.set_shader_parameter(&"star_density", star_density)
	_seam_material = _overlay.duplicate() as ShaderMaterial
	_seam_material.render_priority = 0
	_seam_material.set_shader_parameter(&"fill_aperture_only", true)
	_update_volume_transform()
	MESH_SCOPE.watch(self, _on_source_tree_changed)
	_queue_refresh()


func _exit_tree() -> void:
	MESH_SCOPE.unwatch(self, _on_source_tree_changed)
	_release_targets()
	_collision_cut.clear()
	_collision_sources.clear()
	_collision_extent = Vector3.ZERO
	_collision_update_queued = false
	_collision_mode_active = false
	_refresh_queued = false
	_overlay = null
	_seam_material = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _overlay != null:
		_update_volume_transform()


func refresh_targets() -> int:
	_refresh_queued = false
	var active := is_inside_tree() and enabled and progress > 0.0
	_collision_sources.clear()
	if active and _wants_collision_cut() and not Engine.is_editor_hint():
		var roots := target_roots if collision_roots.is_empty() else collision_roots
		_collision_sources = COLLISION_CUT.collect_sources(self, roots, excluded_roots)
	_queue_collision_update()
	_release_targets(strict_box_bounds and active)
	if not active:
		return 0
	var candidates: Dictionary[int, MeshInstance3D] = {}
	if strict_box_bounds:
		candidates = MESH_SCOPE.collect_box(self, target_roots, excluded_roots, affected_categories)
	elif not require_explicit_targets or not target_roots.is_empty():
		candidates = MESH_SCOPE.collect(self, target_roots, excluded_roots)
	for path in seam_fill_planes:
		var marker := _get_seam_marker(path)
		if marker != null:
			candidates.erase(marker.get_instance_id())
	if strict_box_bounds:
		# Multiple boxes can receive the same source without competing for its overlay slot.
		MESH_SCOPE.sync_coatings(candidates, _boxed_instances, _overlay, true)
		if (affected_categories & MESH_SCOPE.SCENE) != 0:
			_create_seam_fills()
		update_configuration_warnings()
		return _boxed_instances.size()
	if require_explicit_targets and target_roots.is_empty():
		update_configuration_warnings()
		return 0
	for id in candidates:
		var mesh := candidates[id]
		if mesh.material_overlay != null:
			continue
		var claim := _claims.get(id) as WeakRef
		if claim != null and claim.get_ref() != null:
			continue
		_claims[id] = weakref(self)
		_targets[id] = mesh
		RenderingServer.instance_geometry_set_material_overlay(mesh.get_instance(), _overlay.get_rid())
	_create_seam_fills()
	update_configuration_warnings()
	return _targets.size() + _boxed_instances.size()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for path in target_roots:
		if get_node_or_null(path) == null:
			warnings.append("侵蚀目标路径无效：%s" % path)
	if enabled and progress > 0.0 and _targets.is_empty() and _boxed_instances.is_empty():
		warnings.append("当前没有可绑定网格。请检查父节点、Target Roots 和排除项。")
	for path in seam_fill_planes:
		if _get_seam_marker(path) == null:
			warnings.append("接缝补面需要引用已隐藏的 PlaneMesh 节点：%s" % path)
	if remove_collision_in_void:
		for path in collision_roots:
			if get_node_or_null(path) == null:
				warnings.append("物理目标路径无效：%s" % path)
	return warnings


func _on_source_tree_changed(node: Node) -> void:
	if not enabled or progress <= 0.0:
		return
	var mesh_changed := strict_box_bounds and affected_categories != 0 and MESH_SCOPE.is_source_mesh(node)
	var collision_changed := remove_collision_in_void and _collision_cut.tracks_source(node)
	if mesh_changed or collision_changed:
		_queue_refresh()


func _queue_refresh() -> void:
	if is_inside_tree() and not _refresh_queued:
		_refresh_queued = true
		_refresh_if_queued.call_deferred()


func _refresh_if_queued() -> void:
	if _refresh_queued:
		refresh_targets()


func _release_targets(keep_boxed := false) -> void:
	if not keep_boxed:
		MESH_SCOPE.clear_coatings(_boxed_instances)
	for fill in _seam_instances:
		if is_instance_valid(fill):
			fill.hide()
			fill.queue_free()
	_seam_instances.clear()
	for id in _targets:
		var mesh := _targets[id]
		if is_instance_valid(mesh):
			var original := mesh.material_overlay
			var original_rid := original.get_rid() if original != null else RID()
			RenderingServer.instance_geometry_set_material_overlay(mesh.get_instance(), original_rid)
		_claims.erase(id)
	_targets.clear()


func _create_seam_fills() -> void:
	var used: Dictionary[int, bool] = {}
	for path in seam_fill_planes:
		var marker := _get_seam_marker(path)
		if marker == null:
			continue
		var id := marker.get_instance_id()
		if used.has(id):
			continue
		used[id] = true
		var fill := MeshInstance3D.new()
		fill.set_meta(MESH_SCOPE.COATING_META, true)
		fill.mesh = marker.mesh
		fill.material_override = _seam_material
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fill.layers = marker.layers
		marker.get_parent().add_child(fill, false, Node.INTERNAL_MODE_BACK)
		fill.global_transform = marker.global_transform
		marker.tree_exiting.connect(fill.queue_free, CONNECT_ONE_SHOT)
		_seam_instances.append(fill)


func _get_seam_marker(path: NodePath) -> MeshInstance3D:
	var marker := get_node_or_null(path) as MeshInstance3D
	if marker != null and not marker.visible and marker.mesh is PlaneMesh:
		return marker
	return null


func _update_volume_transform() -> void:
	_set_uniform(&"world_to_volume", _volume_frame().inverse())
	_update_box_extent()


func _update_box_extent() -> void:
	_set_uniform(&"half_size", _volume_half_size())
	_queue_collision_update()
	if Engine.is_editor_hint() and is_inside_tree():
		update_gizmos()


func _volume_frame() -> Transform3D:
	return Transform3D(global_basis.orthonormalized(), global_position)


func _volume_half_size() -> Vector3:
	var scale_factor := global_basis.get_scale().abs() if strict_box_bounds and is_inside_tree() else Vector3.ONE
	return box_size * scale_factor.max(Vector3.ONE * 0.001) * 0.5


func _wants_collision_cut() -> bool:
	if strict_box_bounds:
		return remove_collision_in_void and (affected_categories & MESH_SCOPE.SCENE) != 0
	return remove_collision_in_void and (not require_explicit_targets or not target_roots.is_empty())


func _queue_collision_update() -> void:
	if not is_inside_tree() or _overlay == null or _collision_update_queued:
		return
	if not remove_collision_in_void and not _collision_mode_active:
		return
	_collision_update_queued = true
	_sync_collision_opening.call_deferred()


func _sync_collision_opening() -> void:
	_collision_update_queued = false
	if not is_inside_tree() or _overlay == null:
		return
	_collision_mode_active = _wants_collision_cut()
	var extent := Vector3.ZERO
	if enabled and _collision_mode_active and progress >= COLLISION_REVEAL_PROGRESS:
		extent = _volume_half_size() * progress
		# Advance the geometry and the Shader together, with bounded rebuild steps.
		if progress < 1.0:
			var step_size := minf(cell_size * 0.5, 0.20)
			extent = (extent / step_size).floor() * step_size
	_collision_extent = extent
	_set_uniform(&"collision_cut_mode", _collision_mode_active)
	_set_uniform(&"collision_extent", extent)
	if not Engine.is_editor_hint():
		var previous_unsupported: int = _collision_cut.unsupported_count
		_collision_cut.sync(_collision_sources, _volume_frame(), extent)
		if _collision_cut.unsupported_count > previous_unsupported:
			push_warning("赛博虚空保留了 %d 个部分相交且不支持局部裁切的碰撞形状。" % _collision_cut.unsupported_count)


func get_collision_opening_snapshot() -> Dictionary:
	return {
		"half_size": _collision_extent,
		"active_shapes": _collision_cut.active_count(),
		"unsupported_shapes": _collision_cut.unsupported_count,
	}


func _set_uniform(parameter: StringName, value: Variant) -> void:
	if _overlay != null:
		_overlay.set_shader_parameter(parameter, value)
	if _seam_material != null:
		_seam_material.set_shader_parameter(parameter, value)
