@tool
extends RefCounted

const TEST_SCENE := "res://tests/visual/scene_cyber_space_preview.tscn"
var failures: Array[String] = []
var checks := 0


func run(plugin: EditorPlugin) -> void:
	EditorInterface.open_scene_from_path(TEST_SCENE)
	var root: Node3D
	for i in range(120):
		var candidate := EditorInterface.get_edited_scene_root() as Node3D
		if candidate != null and candidate.scene_file_path == TEST_SCENE:
			root = candidate
			break
		await plugin.get_tree().create_timer(0.25).timeout
	check(root != null, "preview scene opened")
	if root == null:
		finish(plugin)
		return

	var target := MeshInstance3D.new()
	target.name = "ShaderVolumeProbeTarget"
	target.mesh = BoxMesh.new()
	var excluded := MeshInstance3D.new()
	excluded.name = "ExcludedNPC"
	excluded.mesh = BoxMesh.new()
	target.add_child(excluded)
	root.add_child(target)
	var actor := Node3D.new()
	actor.add_to_group(&"base_npc_3d")
	root.add_child(actor)
	var actor_mesh := MeshInstance3D.new()
	actor_mesh.name = "ActorAttachment"
	actor_mesh.mesh = BoxMesh.new()
	actor.add_child(actor_mesh)
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
	for preset in range(5):
		var selection := EditorInterface.get_selection()
		selection.clear()
		if preset != 0:
			selection.add_node(target)
		plugin._presets.select(preset)
		plugin._add_button.pressed.emit()
		var selected := selection.get_selected_nodes()
		check(selected.size() == 1 and selected[0] != target, "toolbar selected inserted node %d" % preset)
		if selected.size() != 1 or selected[0] == target:
			continue
		var volume := selected[0] as Node3D
		check(volume.owner == root, "inserted node has scene owner %d" % preset)
		check(volume.target_roots.is_empty(), "selection is not a whitelist %d" % preset)
		check(volume.strict_box_bounds and volume.affected_categories == 3, "both categories enabled %d" % preset)
		check(plugin._gizmo._has_gizmo(volume), "range gizmo applies %d" % preset)
		var exclusions: Array[NodePath] = [volume.get_path_to(excluded)]
		volume.excluded_roots = exclusions
		volume.refresh_targets()
		var coatings: Dictionary = volume._boxed_instances if preset == 4 else volume._render_instances
		var target_id := target.get_instance_id()
		var actor_id := actor_mesh.get_instance_id()
		check(coatings.has(target_id) and coatings.has(actor_id) and not coatings.has(excluded.get_instance_id()), "both categories with exclusions %d" % preset)
		volume.affected_categories = 1
		volume.refresh_targets()
		check(coatings.has(target_id) and not coatings.has(actor_id), "scene only %d" % preset)
		volume.affected_categories = 2
		volume.refresh_targets()
		check(not coatings.has(target_id) and coatings.has(actor_id), "characters only %d" % preset)
		volume.affected_categories = 0
		check(volume.refresh_targets() == 0, "no categories no coverage %d" % preset)
		volume.affected_categories = 3
		var material: ShaderMaterial = volume._overlay if preset == 4 else volume._material
		check(material.get_shader_parameter(&"strict_box_bounds") == true, "strict clipping uniform %d" % preset)
		volume.box_size = Vector3(6, 8, 10)
		volume.scale = Vector3(2, 1, 0.5)
		volume.position = Vector3(1, 2, 3)
		volume.force_update_transform()
		check(material.get_shader_parameter(&"half_size") == Vector3(6, 4, 2.5), "realtime resize uniform %d" % preset)
		var uniform_name := &"world_to_volume" if preset == 4 else &"world_to_field"
		var inverse: Transform3D = material.get_shader_parameter(uniform_name)
		check((inverse * volume.global_position).is_zero_approx(), "realtime move uniform %d" % preset)
		volume.progress = 0.5
		check(material.get_shader_parameter(&"progress") == 0.5, "realtime progress uniform %d" % preset)
		volume.progress = 0.0
		check(volume.refresh_targets() == 0, "zero progress unbinds meshes %d" % preset)
		volume.progress = 1.0
		volume.require_explicit_targets = true
		volume.refresh_targets()
		check(coatings.has(target_id) and coatings.has(actor_id), "legacy empty whitelist migrates to categories %d" % preset)
		var late_mesh := MeshInstance3D.new()
		late_mesh.mesh = BoxMesh.new()
		actor.add_child(late_mesh)
		await plugin.get_tree().process_frame
		check(coatings.has(late_mesh.get_instance_id()), "late actor mesh discovered %d" % preset)
		actor.remove_child(late_mesh)
		late_mesh.queue_free()
		await plugin.get_tree().process_frame
		history.undo()
		check(volume.get_parent() == null, "undo removes range %d" % preset)
		history.redo()
		check(volume.get_parent() == root and volume.owner == root, "redo restores range %d" % preset)
		history.undo()
	root.remove_child(target)
	target.queue_free()
	await plugin.get_tree().process_frame
	finish(plugin)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("SHADER_VOLUME_EDITOR_FAIL " + message)


func finish(plugin: EditorPlugin) -> void:
	print("SHADER_VOLUME_EDITOR checks=%d failures=%d" % [checks, failures.size()])
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
