@tool
extends RefCounted
## Resolves authored scene roots and category-based receivers for mesh VFX.

const SCENE := 1
const ACTORS := 2
const ACTOR_GROUPS: Array[StringName] = [&"player", &"player_3d", &"enemy_3d", &"base_npc_3d", &"shader_volume_actor"]
const ACTOR_SCRIPTS := {
	"res://src/player3d/Player3D.gd": true,
	"res://src/player3d/PlayerAvatar3D.gd": true,
	"res://src/npc/NpcCharacter3D.gd": true,
	"res://src/enemy3d/Enemy3D.gd": true,
	"res://src/enemy3d/EnemyAvatar3D.gd": true,
	"res://src/enemy3d/PlatformSentinelUnit3D.gd": true,
}
const COATING_META := &"_shader_volume_coating"


static func collect(host: Node, roots: Array[NodePath], exclusions: Array[NodePath]) -> Dictionary[int, MeshInstance3D]:
	var meshes: Dictionary[int, MeshInstance3D] = {}
	if roots.is_empty():
		_collect_meshes(host.get_parent(), meshes)
	else:
		for path in roots:
			_collect_meshes(host.get_node_or_null(path), meshes)
	_remove_exclusions(host, exclusions, meshes)
	return meshes


static func collect_box(host: Node3D, roots: Array[NodePath], exclusions: Array[NodePath], categories: int) -> Dictionary[int, MeshInstance3D]:
	var meshes: Dictionary[int, MeshInstance3D] = {}
	if categories == 0:
		return meshes
	if not roots.is_empty():
		for path in roots:
			var node := host.get_node_or_null(path)
			_collect_meshes(node, meshes, categories, _actor_ancestor(node))
	else:
		_collect_meshes(host.get_parent(), meshes, categories, _actor_ancestor(host.get_parent()))
		# Runtime actors can live next to the room layout, or under a central spawn root.
		if categories & ACTORS:
			var world := host.get_viewport().find_world_3d()
			var edited := host.get_tree().edited_scene_root if Engine.is_editor_hint() else null
			for group in ACTOR_GROUPS:
				for node in host.get_tree().get_nodes_in_group(group):
					if not node is Node3D or node.get_viewport().find_world_3d() != world:
						continue
					if edited != null and node != edited and not edited.is_ancestor_of(node):
						continue
					_collect_meshes(node, meshes, ACTORS, true)
	_remove_exclusions(host, exclusions, meshes)
	return meshes


## Tree notifications are coalesced by the host. Ignore our own generated meshes.
static func watch(host: Node, callback: Callable) -> void:
	host.get_tree().node_added.connect(callback)
	host.get_tree().node_removed.connect(callback)


static func unwatch(host: Node, callback: Callable) -> void:
	host.get_tree().node_added.disconnect(callback)
	host.get_tree().node_removed.disconnect(callback)


static func is_source_mesh(node: Node) -> bool:
	return node is MeshInstance3D and not node.has_meta(COATING_META)


static func _remove_exclusions(host: Node, exclusions: Array[NodePath], meshes: Dictionary[int, MeshInstance3D]) -> void:
	var excluded: Dictionary[int, MeshInstance3D] = {}
	for path in exclusions:
		_collect_meshes(host.get_node_or_null(path), excluded)
	for id in excluded:
		meshes.erase(id)


static func _collect_meshes(node: Node, meshes: Dictionary[int, MeshInstance3D], categories := 0, actor_branch := false) -> void:
	if node == null or node.has_meta(COATING_META):
		return
	if categories != 0 and not actor_branch:
		actor_branch = _is_actor_root(node)
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var category := ACTORS if actor_branch or mesh.skin != null else SCENE
		if categories == 0 or (categories & category) != 0:
			meshes[mesh.get_instance_id()] = mesh
	for child in node.get_children():
		_collect_meshes(child, meshes, categories, actor_branch)


static func _actor_ancestor(node: Node) -> bool:
	var cursor := node
	while cursor != null:
		if _is_actor_root(cursor):
			return true
		cursor = cursor.get_parent()
	return false


static func _is_actor_root(node: Node) -> bool:
	if node is CharacterBody3D or node is Skeleton3D:
		return true
	for group in ACTOR_GROUPS:
		if node.is_in_group(group):
			return true
	var script := node.get_script() as Script
	while script != null:
		if ACTOR_SCRIPTS.has(script.resource_path):
			return true
		script = script.get_base_script()
	return false


## Reuse coatings when the category mask changes or new scene meshes arrive.
## The generated nodes never become receivers or belong to the saved scene.
static func sync_coatings(candidates: Dictionary[int, MeshInstance3D], coatings: Dictionary[int, MeshInstance3D], material: ShaderMaterial, allow_skin: bool) -> void:
	for id in coatings.keys():
		var coating := coatings[id]
		if is_instance_valid(coating) and candidates.has(id) and (allow_skin or candidates[id].skin == null):
			continue
		if is_instance_valid(coating):
			coating.hide()
			coating.queue_free()
		coatings.erase(id)
	for id in candidates:
		var source := candidates[id]
		if coatings.has(id) or (not allow_skin and source.skin != null):
			continue
		var coating := MeshInstance3D.new()
		coating.set_meta(COATING_META, true)
		coating.mesh = source.mesh
		coating.material_override = material
		coating.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		coating.layers = source.layers
		coating.lod_bias = source.lod_bias
		coating.visibility_range_begin = source.visibility_range_begin
		coating.visibility_range_begin_margin = source.visibility_range_begin_margin
		coating.visibility_range_end = source.visibility_range_end
		coating.visibility_range_end_margin = source.visibility_range_end_margin
		coating.visibility_range_fade_mode = source.visibility_range_fade_mode
		var skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D if allow_skin and not source.skeleton.is_empty() else null
		if skeleton != null:
			coating.skin = source.skin
			coating.skeleton = NodePath("../" + str(source.get_path_to(skeleton)))
		else:
			coating.skeleton = NodePath()
		source.add_child(coating, false, Node.INTERNAL_MODE_BACK)
		for index in range(source.get_blend_shape_count()):
			coating.set_blend_shape_value(index, source.get_blend_shape_value(index))
		coatings[id] = coating


static func clear_coatings(coatings: Dictionary[int, MeshInstance3D]) -> void:
	for coating in coatings.values():
		if is_instance_valid(coating):
			coating.hide()
			coating.queue_free()
	coatings.clear()
