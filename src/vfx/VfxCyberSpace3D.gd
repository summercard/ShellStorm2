@tool
extends Node3D
## A scoped holographic coat for static scenery. Draws below the void surface overlay.

const SPACE_SHADER := preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/scene_cyber_space.gdshader")
const MESH_SCOPE := preload("res://src/vfx/VfxSceneMeshScope.gd")

@export_group("接入")
@export var target_roots: Array[NodePath] = []:
	set(value):
		target_roots = value
		_queue_refresh()
@export var excluded_roots: Array[NodePath] = []:
	set(value):
		excluded_roots = value
		_queue_refresh()
@export var enabled := true:
	set(value):
		enabled = value
		_queue_refresh()
@export_tool_button("刷新场景网格") var refresh_button: Callable = refresh_targets

@export_group("范围与过渡")
@export var box_size := Vector3(36.0, 14.0, 36.0):
	set(value):
		box_size = value.abs().max(Vector3(0.05, 0.05, 0.05))
		_set_uniform(&"half_size", box_size * 0.5)
@export_range(0.0, 1.0, 0.001) var progress := 1.0:
	set(value):
		var was_active := _is_active()
		progress = clampf(value, 0.0, 1.0)
		_set_uniform(&"progress", progress)
		if was_active != _is_active():
			_queue_refresh()
@export_range(0.0, 1.0, 0.001) var strength := 1.0:
	set(value):
		var was_active := _is_active()
		strength = clampf(value, 0.0, 1.0)
		_set_uniform(&"strength", strength)
		if was_active != _is_active():
			_queue_refresh()
@export_range(0.08, 5.0, 0.01, "suffix:m") var cell_size := 0.48:
	set(value):
		cell_size = maxf(value, 0.08)
		_set_uniform(&"cell_size", cell_size)
## Local metre offset for aligning the surface grid with another effect.
@export var grid_origin_offset := Vector3.ZERO:
	set(value):
		grid_origin_offset = value
		_set_uniform(&"grid_origin_offset", value)
@export_range(0.08, 6.0, 0.01, "suffix:m") var edge_width := 1.25:
	set(value):
		edge_width = maxf(value, 0.08)
		_set_uniform(&"edge_width", edge_width)
@export_range(0.0, 2.0, 0.01) var scan_speed := 0.54:
	set(value):
		scan_speed = maxf(value, 0.0)
		_set_uniform(&"scan_speed", scan_speed)

@export_group("调色")
@export_color_no_alpha var face_color := Color(0.116, 0.068, 0.26):
	set(value):
		face_color = value
		_set_uniform(&"face_color", value)
@export_color_no_alpha var grid_color := Color(0.47, 0.35, 1.0):
	set(value):
		grid_color = value
		_set_uniform(&"grid_color", value)
@export_color_no_alpha var outline_color := Color(0.79, 0.62, 1.0):
	set(value):
		outline_color = value
		_set_uniform(&"outline_color", value)
@export_color_no_alpha var guide_color := Color(0.17, 0.79, 1.0):
	set(value):
		guide_color = value
		_set_uniform(&"guide_color", value)
@export_color_no_alpha var signal_color := Color(1.0, 0.28, 0.78):
	set(value):
		signal_color = value
		_set_uniform(&"signal_color", value)

var _material: ShaderMaterial
var _render_instances: Array[MeshInstance3D] = []
var _refresh_queued := false


func _enter_tree() -> void:
	set_notify_transform(true)
	_material = ShaderMaterial.new()
	_material.shader = SPACE_SHADER
	_material.render_priority = -1
	_set_uniform(&"half_size", box_size * 0.5)
	_set_uniform(&"progress", progress)
	_set_uniform(&"strength", strength)
	_set_uniform(&"cell_size", cell_size)
	_set_uniform(&"grid_origin_offset", grid_origin_offset)
	_set_uniform(&"edge_width", edge_width)
	_set_uniform(&"scan_speed", scan_speed)
	_set_uniform(&"face_color", face_color)
	_set_uniform(&"grid_color", grid_color)
	_set_uniform(&"outline_color", outline_color)
	_set_uniform(&"guide_color", guide_color)
	_set_uniform(&"signal_color", signal_color)
	_update_field_transform()
	_queue_refresh()


func _exit_tree() -> void:
	_clear_instances()
	_material = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _material != null:
		_update_field_transform()


func refresh_targets() -> int:
	_refresh_queued = false
	_clear_instances()
	if not is_inside_tree() or not _is_active():
		return 0

	for source in MESH_SCOPE.collect(self, target_roots, excluded_roots).values():
		if source.skin != null:
			continue
		var coating := MeshInstance3D.new()
		coating.mesh = source.mesh
		coating.material_override = _material
		coating.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		coating.layers = source.layers
		coating.lod_bias = source.lod_bias
		source.add_child(coating, false, Node.INTERNAL_MODE_BACK)
		_render_instances.append(coating)
	update_configuration_warnings()
	return _render_instances.size()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for path in target_roots:
		if get_node_or_null(path) == null:
			warnings.append("赛博空间目标路径无效：%s" % path)
	if _is_active() and _render_instances.is_empty():
		warnings.append("当前没有可覆盖网格。请检查父节点、Target Roots 和排除项。")
	return warnings


func _is_active() -> bool:
	return enabled and progress > 0.0 and strength > 0.0


func _queue_refresh() -> void:
	if is_inside_tree() and not _refresh_queued:
		_refresh_queued = true
		_refresh_if_queued.call_deferred()


func _refresh_if_queued() -> void:
	if _refresh_queued:
		refresh_targets()


func _clear_instances() -> void:
	for coating in _render_instances:
		if is_instance_valid(coating):
			coating.hide()
			coating.queue_free()
	_render_instances.clear()


func _update_field_transform() -> void:
	var frame := Transform3D(global_basis.orthonormalized(), global_position)
	_set_uniform(&"world_to_field", frame.inverse())


func _set_uniform(parameter: StringName, value: Variant) -> void:
	if _material != null:
		_material.set_shader_parameter(parameter, value)
