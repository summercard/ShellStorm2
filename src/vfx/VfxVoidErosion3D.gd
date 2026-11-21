@tool
extends Node3D
## Scene-owned overlay for opaque MeshInstance3D surfaces.

const EROSION_SHADER := preload("res://assets/art/vfx/environment_3d/void_erosion/runtime/scene_void_erosion.gdshader")
const MESH_SCOPE := preload("res://src/vfx/VfxSceneMeshScope.gd")

# RenderingServer exposes one overlay slot per mesh. Claims never enter scene files.
static var _claims: Dictionary[int, WeakRef] = {}

@export_group("接入")
## Scene roots relative to this node. Leave empty to include the host parent's scene components.
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
@export var enabled := true:
	set(value):
		enabled = value
		_queue_refresh()
@export_tool_button("刷新侵蚀目标") var refresh_button: Callable = refresh_targets

@export_group("展开")
## Animate this property: 0 is off, 1 is the full box.
@export_range(0.0, 1.0, 0.001) var progress := 1.0:
	set(value):
		var was_active := progress > 0.0
		progress = clampf(value, 0.0, 1.0)
		_set_uniform(&"progress", progress)
		if was_active != (progress > 0.0):
			_queue_refresh()
## Full extent in metres. Rotate the node to align the grid with the building.
@export var box_size := Vector3(9.0, 5.0, 9.0):
	set(value):
		box_size = value.abs().max(Vector3(0.05, 0.05, 0.05))
		_set_uniform(&"half_size", box_size * 0.5)
@export_range(0.08, 5.0, 0.01, "or_greater", "suffix:m") var cell_size := 0.55:
	set(value):
		cell_size = maxf(value, 0.08)
		_set_uniform(&"cell_size", cell_size)
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
var _refresh_queued := false


func _enter_tree() -> void:
	set_notify_transform(true)
	_overlay = ShaderMaterial.new()
	_overlay.shader = EROSION_SHADER
	_overlay.render_priority = 1
	_overlay.set_shader_parameter(&"progress", progress)
	_overlay.set_shader_parameter(&"half_size", box_size * 0.5)
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
	_queue_refresh()


func _exit_tree() -> void:
	_release_targets()
	_overlay = null
	_seam_material = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _overlay != null:
		_update_volume_transform()


func refresh_targets() -> int:
	_refresh_queued = false
	_release_targets()
	if not is_inside_tree() or not enabled or progress <= 0.0:
		return 0

	var candidates := MESH_SCOPE.collect(self, target_roots, excluded_roots)
	for path in seam_fill_planes:
		var marker := _get_seam_marker(path)
		if marker != null:
			candidates.erase(marker.get_instance_id())
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
	return _targets.size()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for path in target_roots:
		if get_node_or_null(path) == null:
			warnings.append("侵蚀目标路径无效：%s" % path)
	if enabled and progress > 0.0 and _targets.is_empty():
		warnings.append("当前没有可绑定网格。请检查父节点、Target Roots 和排除项。")
	for path in seam_fill_planes:
		if _get_seam_marker(path) == null:
			warnings.append("接缝补面需要引用已隐藏的 PlaneMesh 节点：%s" % path)
	return warnings


func _queue_refresh() -> void:
	if is_inside_tree() and not _refresh_queued:
		_refresh_queued = true
		_refresh_if_queued.call_deferred()


func _refresh_if_queued() -> void:
	if _refresh_queued:
		refresh_targets()


func _release_targets() -> void:
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
	# The inspector size is in metres, even under a scaled parent.
	var frame := Transform3D(global_basis.orthonormalized(), global_position)
	_set_uniform(&"world_to_volume", frame.inverse())


func _set_uniform(parameter: StringName, value: Variant) -> void:
	if _overlay != null:
		_overlay.set_shader_parameter(parameter, value)
	if _seam_material != null:
		_seam_material.set_shader_parameter(parameter, value)
