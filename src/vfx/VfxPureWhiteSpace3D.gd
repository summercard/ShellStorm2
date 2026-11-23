@tool
extends Node3D
## White-space presentation coat: white material, screen-space AO and stepped voxel-like edges.

const WHITE_SHADER := preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/scene_pure_white_space.gdshader")
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
@export_range(0.08, 5.0, 0.01, "suffix:m") var block_size := 0.72:
	set(value):
		block_size = maxf(value, 0.08)
		_set_uniform(&"block_size", block_size)
@export_range(0.08, 6.0, 0.01, "suffix:m") var edge_width := 1.25:
	set(value):
		edge_width = maxf(value, 0.08)
		_set_uniform(&"edge_width", edge_width)

@export_group("AO与方块边缘")
@export_range(0.05, 3.0, 0.01, "suffix:m") var ao_radius := 0.72:
	set(value):
		ao_radius = maxf(value, 0.05)
		_set_uniform(&"ao_radius", ao_radius)
@export_range(0.0, 1.0, 0.01) var ao_strength := 0.82:
	set(value):
		ao_strength = clampf(value, 0.0, 1.0)
		_set_uniform(&"ao_strength", ao_strength)
@export_range(0.0, 1.0, 0.001) var ao_bias := 0.018:
	set(value):
		ao_bias = clampf(value, 0.0, 1.0)
		_set_uniform(&"ao_bias", ao_bias)
@export_range(0.0, 2.0, 0.01) var edge_strength := 0.68:
	set(value):
		edge_strength = maxf(value, 0.0)
		_set_uniform(&"edge_strength", edge_strength)
@export_range(0.01, 1.0, 0.01) var edge_softness := 0.12:
	set(value):
		edge_softness = maxf(value, 0.01)
		_set_uniform(&"edge_softness", edge_softness)

@export_group("白色调")
@export_color_no_alpha var white_color := Color(0.94, 0.95, 1.0):
	set(value):
		white_color = value
		_set_uniform(&"white_color", value)
@export_color_no_alpha var shadow_color := Color(0.52, 0.55, 0.64):
	set(value):
		shadow_color = value
		_set_uniform(&"shadow_color", value)
@export_color_no_alpha var edge_color := Color(0.72, 0.77, 0.88):
	set(value):
		edge_color = value
		_set_uniform(&"edge_color", value)
@export_color_no_alpha var edge_highlight_color := Color(1.0, 1.0, 1.0):
	set(value):
		edge_highlight_color = value
		_set_uniform(&"edge_highlight_color", value)

var _material: ShaderMaterial
var _render_instances: Dictionary[int, MeshInstance3D] = {}
var _refresh_queued := false

func _enter_tree() -> void:
	set_notify_transform(true)
	_material = ShaderMaterial.new()
	_material.shader = WHITE_SHADER
	_material.render_priority = -1
	_set_uniform(&"strict_box_bounds", strict_box_bounds)
	_set_uniform(&"progress", progress)
	_set_uniform(&"strength", strength)
	_set_uniform(&"block_size", block_size)
	_set_uniform(&"edge_width", edge_width)
	_set_uniform(&"ao_radius", ao_radius)
	_set_uniform(&"ao_strength", ao_strength)
	_set_uniform(&"ao_bias", ao_bias)
	_set_uniform(&"edge_strength", edge_strength)
	_set_uniform(&"edge_softness", edge_softness)
	_set_uniform(&"white_color", white_color)
	_set_uniform(&"shadow_color", shadow_color)
	_set_uniform(&"edge_color", edge_color)
	_set_uniform(&"edge_highlight_color", edge_highlight_color)
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
			warnings.append("纯白空间目标路径无效：%s" % path)
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
