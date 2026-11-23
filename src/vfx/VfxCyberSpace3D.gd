@tool
extends Node3D
## A scoped holographic coat for static scenery. Draws below the void surface overlay.

const SPACE_SHADER := preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/scene_cyber_space.gdshader")
const MESH_SCOPE := preload("res://src/vfx/VfxSceneMeshScope.gd")

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
@export var excluded_roots: Array[NodePath] = []:
	set(value):
		excluded_roots = value
		_queue_refresh()
## Preserve serialized legacy hosts; box volumes use category selection instead.
@export_storage var require_explicit_targets := false:
	set(value):
		require_explicit_targets = value
		_queue_refresh()
## 开启后，过渡也严格限制在盒内，节点缩放参与范围计算。
@export var strict_box_bounds := false:
	set(value):
		strict_box_bounds = value
		_set_uniform(&"strict_box_bounds", value)
		_update_box_extent()
@export var enabled := true:
	set(value):
		enabled = value
		_queue_refresh()
@export_tool_button("刷新场景网格") var refresh_button: Callable = refresh_targets

@export_group("范围与过渡")
@export var box_size := Vector3(36.0, 14.0, 36.0):
	set(value):
		box_size = value.abs().max(Vector3(0.05, 0.05, 0.05))
		_update_box_extent()
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
@export_color_no_alpha var edge_shadow_color := Color(0.035, 0.022, 0.095):
	set(value):
		edge_shadow_color = value
		_set_uniform(&"edge_shadow_color", value)
@export_color_no_alpha var edge_highlight_color := Color(0.91, 0.84, 1.0):
	set(value):
		edge_highlight_color = value
		_set_uniform(&"edge_highlight_color", value)
@export_range(0.0, 2.0, 0.01) var edge_shadow_strength := 0.72:
	set(value):
		edge_shadow_strength = maxf(value, 0.0)
		_set_uniform(&"edge_shadow_strength", edge_shadow_strength)
@export_range(0.0, 2.0, 0.01) var edge_highlight_strength := 1.0:
	set(value):
		edge_highlight_strength = maxf(value, 0.0)
		_set_uniform(&"edge_highlight_strength", edge_highlight_strength)
@export_group("亮边光照")
## World-space direction the virtual light comes from. The gradient is continuous.
@export var edge_light_direction := Vector3(-0.42, 0.76, 0.38):
	set(value):
		edge_light_direction = value.normalized() if value.length_squared() > 0.0001 else Vector3.UP
		_set_uniform(&"edge_light_direction", edge_light_direction)
@export var edge_light_position := Vector3(-10.0, 10.0, 12.0):
	set(value):
		edge_light_position = value
		_set_uniform(&"edge_light_position", value)
@export_range(0.1, 100.0, 0.1, "suffix:m") var edge_light_range := 48.0:
	set(value):
		edge_light_range = maxf(value, 0.1)
		_set_uniform(&"edge_light_range", edge_light_range)
@export_range(0.05, 4.0, 0.01) var edge_light_falloff := 1.0:
	set(value):
		edge_light_falloff = maxf(value, 0.05)
		_set_uniform(&"edge_light_falloff", edge_light_falloff)
@export_range(0.0, 1.0, 0.01) var edge_gradient_strength := 0.86:
	set(value):
		edge_gradient_strength = clampf(value, 0.0, 1.0)
		_set_uniform(&"edge_gradient_strength", edge_gradient_strength)
@export_range(0.01, 2.0, 0.01) var edge_gradient_softness := 0.96:
	set(value):
		edge_gradient_softness = maxf(value, 0.01)
		_set_uniform(&"edge_gradient_softness", edge_gradient_softness)
@export_range(0.0, 1.0, 0.01) var edge_light_ambient := 0.26:
	set(value):
		edge_light_ambient = clampf(value, 0.0, 1.0)
		_set_uniform(&"edge_light_ambient", edge_light_ambient)
@export_range(0.05, 4.0, 0.01) var edge_light_contrast := 1.35:
	set(value):
		edge_light_contrast = maxf(value, 0.05)
		_set_uniform(&"edge_light_contrast", edge_light_contrast)
@export_range(0.0, 3.0, 0.01) var edge_light_energy := 1.15:
	set(value):
		edge_light_energy = maxf(value, 0.0)
		_set_uniform(&"edge_light_energy", edge_light_energy)
@export_group("局部亮度")
## Low-frequency world-space light variation for close-up readability.
@export_range(0.01, 2.0, 0.01) var edge_noise_scale := 0.32:
	set(value):
		edge_noise_scale = maxf(value, 0.01)
		_set_uniform(&"edge_noise_scale", edge_noise_scale)
@export_range(0.0, 1.0, 0.01) var edge_noise_strength := 0.52:
	set(value):
		edge_noise_strength = clampf(value, 0.0, 1.0)
		_set_uniform(&"edge_noise_strength", edge_noise_strength)
@export_range(0.0, 1.0, 0.01) var edge_spot_strength := 0.36:
	set(value):
		edge_spot_strength = clampf(value, 0.0, 1.0)
		_set_uniform(&"edge_spot_strength", edge_spot_strength)
@export_range(0.0, 1.0, 0.01) var edge_spot_threshold := 0.58:
	set(value):
		edge_spot_threshold = clampf(value, 0.0, 1.0)
		_set_uniform(&"edge_spot_threshold", edge_spot_threshold)
@export var edge_noise_offset := Vector3(17.3, -4.1, 9.7):
	set(value):
		edge_noise_offset = value
		_set_uniform(&"edge_noise_offset", value)
@export_range(0.0, 1.0, 0.01) var base_color_strength := 0.58:
	set(value):
		base_color_strength = clampf(value, 0.0, 1.0)
		_set_uniform(&"base_color_strength", base_color_strength)
@export_color_no_alpha var guide_color := Color(0.17, 0.79, 1.0):
	set(value):
		guide_color = value
		_set_uniform(&"guide_color", value)
@export_color_no_alpha var signal_color := Color(1.0, 0.28, 0.78):
	set(value):
		signal_color = value
		_set_uniform(&"signal_color", value)

var _material: ShaderMaterial
var _render_instances: Dictionary[int, MeshInstance3D] = {}
var _refresh_queued := false


func _enter_tree() -> void:
	set_notify_transform(true)
	_material = ShaderMaterial.new()
	_material.shader = SPACE_SHADER
	_material.render_priority = -1
	_set_uniform(&"strict_box_bounds", strict_box_bounds)
	_set_uniform(&"progress", progress)
	_set_uniform(&"strength", strength)
	_set_uniform(&"cell_size", cell_size)
	_set_uniform(&"grid_origin_offset", grid_origin_offset)
	_set_uniform(&"edge_width", edge_width)
	_set_uniform(&"scan_speed", scan_speed)
	_set_uniform(&"face_color", face_color)
	_set_uniform(&"grid_color", grid_color)
	_set_uniform(&"outline_color", outline_color)
	_set_uniform(&"edge_shadow_color", edge_shadow_color)
	_set_uniform(&"edge_highlight_color", edge_highlight_color)
	_set_uniform(&"edge_shadow_strength", edge_shadow_strength)
	_set_uniform(&"edge_highlight_strength", edge_highlight_strength)
	_set_uniform(&"edge_light_direction", edge_light_direction)
	_set_uniform(&"edge_light_position", edge_light_position)
	_set_uniform(&"edge_light_range", edge_light_range)
	_set_uniform(&"edge_light_falloff", edge_light_falloff)
	_set_uniform(&"edge_gradient_strength", edge_gradient_strength)
	_set_uniform(&"edge_gradient_softness", edge_gradient_softness)
	_set_uniform(&"edge_light_ambient", edge_light_ambient)
	_set_uniform(&"edge_light_contrast", edge_light_contrast)
	_set_uniform(&"edge_light_energy", edge_light_energy)
	_set_uniform(&"edge_noise_scale", edge_noise_scale)
	_set_uniform(&"edge_noise_strength", edge_noise_strength)
	_set_uniform(&"edge_spot_strength", edge_spot_strength)
	_set_uniform(&"edge_spot_threshold", edge_spot_threshold)
	_set_uniform(&"edge_noise_offset", edge_noise_offset)
	_set_uniform(&"base_color_strength", base_color_strength)
	_set_uniform(&"guide_color", guide_color)
	_set_uniform(&"signal_color", signal_color)
	_update_field_transform()
	MESH_SCOPE.watch(self, _on_source_tree_changed)
	_queue_refresh()


func _exit_tree() -> void:
	MESH_SCOPE.unwatch(self, _on_source_tree_changed)
	_clear_instances()
	_refresh_queued = false
	_material = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _material != null:
		_update_field_transform()


func refresh_targets() -> int:
	_refresh_queued = false
	if not is_inside_tree() or not _is_active():
		_clear_instances()
		return 0
	var candidates: Dictionary[int, MeshInstance3D] = {}
	if strict_box_bounds:
		candidates = MESH_SCOPE.collect_box(self, target_roots, excluded_roots, affected_categories)
	elif not require_explicit_targets or not target_roots.is_empty():
		candidates = MESH_SCOPE.collect(self, target_roots, excluded_roots)
	MESH_SCOPE.sync_coatings(candidates, _render_instances, _material, strict_box_bounds)
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


func _on_source_tree_changed(node: Node) -> void:
	if strict_box_bounds and affected_categories != 0 and _is_active() and MESH_SCOPE.is_source_mesh(node):
		_queue_refresh()


func _queue_refresh() -> void:
	if is_inside_tree() and not _refresh_queued:
		_refresh_queued = true
		_refresh_if_queued.call_deferred()


func _refresh_if_queued() -> void:
	if _refresh_queued:
		refresh_targets()


func _clear_instances() -> void:
	MESH_SCOPE.clear_coatings(_render_instances)


func _update_field_transform() -> void:
	var frame := Transform3D(global_basis.orthonormalized(), global_position)
	_set_uniform(&"world_to_field", frame.inverse())
	_update_box_extent()


func _update_box_extent() -> void:
	var scale_factor := global_basis.get_scale().abs() if strict_box_bounds and is_inside_tree() else Vector3.ONE
	_set_uniform(&"half_size", box_size * scale_factor.max(Vector3.ONE * 0.001) * 0.5)
	if Engine.is_editor_hint() and is_inside_tree():
		update_gizmos()


func _set_uniform(parameter: StringName, value: Variant) -> void:
	if _material != null:
		_material.set_shader_parameter(parameter, value)
