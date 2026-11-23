@tool
extends EditorPlugin

const GIZMO := preload("res://addons/shellstorm_shader_volume/volume_gizmo.gd")
const EXPORT_GUARD := preload("res://addons/shellstorm_shader_volume/export_guard.gd")
const PRESETS: Array[PackedScene] = [
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_blue_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_green_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_pure_white_space_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/void_erosion/runtime/vfx_env_void_erosion_root_top3d.tscn"),
]
const LABELS := ["赛博空间 · 蓝", "赛博空间 · 绿", "赛博空间 · 紫", "纯白空间", "赛博虚空"]
const DEFAULT_BOX := Vector3(10.0, 6.0, 10.0)

var _toolbar: HBoxContainer
var _presets: OptionButton
var _add_button: Button
var _gizmo: EditorNode3DGizmoPlugin
var _export_guard: EditorExportPlugin


func _enter_tree() -> void:
	_gizmo = GIZMO.new(get_undo_redo())
	add_node_3d_gizmo_plugin(_gizmo)
	_export_guard = EXPORT_GUARD.new()
	add_export_plugin(_export_guard)
	_toolbar = HBoxContainer.new()
	_toolbar.name = "ShaderVolumeToolbar"
	_presets = OptionButton.new()
	for label in LABELS:
		_presets.add_item(label)
	_presets.tooltip_text = "选择要添加的环境 Shader"
	_toolbar.add_child(_presets)
	_add_button = Button.new()
	_add_button.text = "添加 Shader 范围盒"
	_add_button.tooltip_text = "无需选模型。默认覆盖盒内场景模型和角色；可在检查器的覆盖范围中取消勾选。"
	_add_button.pressed.connect(_add_from_toolbar)
	_toolbar.add_child(_add_button)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	scene_changed.connect(_update_toolbar)
	_update_toolbar(EditorInterface.get_edited_scene_root())
	if "--shader-volume-editor-test" in OS.get_cmdline_user_args():
		_run_editor_test.call_deferred()


func _exit_tree() -> void:
	scene_changed.disconnect(_update_toolbar)
	remove_node_3d_gizmo_plugin(_gizmo)
	remove_export_plugin(_export_guard)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()


func _update_toolbar(root: Node) -> void:
	_add_button.disabled = not root is Node3D


func _add_from_toolbar() -> void:
	var root := EditorInterface.get_edited_scene_root() as Node3D
	if root == null:
		return
	var selection := EditorInterface.get_selection()
	var volume := _create_volume(root, _presets.selected, selection.get_selected_nodes())
	if volume != null:
		selection.clear()
		selection.add_node(volume)
		EditorInterface.edit_node(volume)


func _create_volume(root: Node3D, preset: int, targets: Array[Node]) -> Node3D:
	if preset < 0 or preset >= PRESETS.size():
		return null
	var volume := PRESETS[preset].instantiate() as Node3D
	volume.name = str(volume.name) + "Box"
	volume.set("strict_box_bounds", true)
	volume.set("box_size", DEFAULT_BOX)
	var anchor_count := 0
	var anchor := Vector3.ZERO
	var world_to_room := root.global_transform.affine_inverse()
	for target in targets:
		# Selection positions the box, but never restricts its receivers.
		if not target is Node3D or not root.is_ancestor_of(target) or GIZMO.is_volume(target):
			continue
		anchor_count += 1
		var spatial := target as Node3D
		var world_point := spatial.global_position
		if spatial is MeshInstance3D and spatial.mesh != null:
			world_point = spatial.to_global(spatial.get_aabb().get_center())
		anchor += world_to_room * world_point
	volume.position = anchor / float(anchor_count) if anchor_count > 0 else Vector3.ZERO

	var undo := get_undo_redo()
	undo.create_action("添加 Shader 范围盒", UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(root, "add_child", volume, true)
	undo.add_do_property(volume, "owner", root)
	undo.add_undo_method(root, "remove_child", volume)
	undo.add_do_reference(volume)
	undo.commit_action()
	return volume


func _run_editor_test() -> void:
	var test := load("res://addons/shellstorm_shader_volume/test_editor.gd").new() as RefCounted
	await test.run(self)
