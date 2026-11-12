extends RefCounted

# 只缓存节点来源及顺序；所有碰撞属性和几何仍由调用方实时读取。
static var _trees: Dictionary = {}


static func get_sources(root: Node) -> Array:
	if not root.is_inside_tree():
		var sources: Array = root.find_children("*", "CollisionShape3D", true, false)
		sources.make_read_only()
		return sources
	var tree := root.get_tree()
	var tree_id := tree.get_instance_id()
	if not _trees.has(tree_id):
		var index := TreeIndex.new()
		index.tree = weakref(tree)
		index.on_empty = _remove_tree.bind(tree_id)
		_trees[tree_id] = index
		tree.tree_changed.connect(index.changed)
	var index: TreeIndex = _trees[tree_id]
	return index.sources(root)


static func _remove_tree(id: int) -> void:
	_trees.erase(id)


class TreeIndex extends RefCounted:
	var tree: WeakRef
	var on_empty: Callable
	var generation := 0
	var roots: Dictionary = {}

	func changed() -> void:
		generation += 1

	func sources(root: Node) -> Array:
		var id := root.get_instance_id()
		if not roots.has(id):
			var exiting := remove_root.bind(id)
			roots[id] = {"root": weakref(root), "generation": -1, "nodes": [], "exiting": exiting}
			root.tree_exiting.connect(exiting)
		var entry: Dictionary = roots[id]
		if entry.generation != generation:
			var nodes: Array = root.find_children("*", "CollisionShape3D", true, false)
			nodes.make_read_only()
			entry.nodes = nodes
			entry.generation = generation
		return entry.nodes

	func remove_root(id: int) -> void:
		var entry: Dictionary = roots[id]
		var root := entry.root.get_ref() as Node
		if is_instance_valid(root) and root.tree_exiting.is_connected(entry.exiting):
			root.tree_exiting.disconnect(entry.exiting)
		roots.erase(id)
		if roots.is_empty():
			var source_tree := tree.get_ref() as SceneTree
			if is_instance_valid(source_tree):
				if source_tree.tree_changed.is_connected(changed):
					source_tree.tree_changed.disconnect(changed)
			on_empty.call()
