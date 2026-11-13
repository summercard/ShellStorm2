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
		tree.node_added.connect(index.collision_membership_changed)
		tree.node_removed.connect(index.collision_membership_changed)
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
		# 全树变化只要求复核顺序，不使来源成员列表失效。
		generation += 1

	func collision_membership_changed(node: Node) -> void:
		if not node is CollisionShape3D:
			return
		for entry: Dictionary in roots.values():
			var root := entry.root.get_ref() as Node
			if is_instance_valid(root) and root.is_ancestor_of(node):
				entry.membership += 1

	func sources(root: Node) -> Array:
		var id := root.get_instance_id()
		if not roots.has(id):
			var exiting := remove_root.bind(id)
			roots[id] = {"root": weakref(root), "generation": -1, "membership": 0,
				"built_membership": -1, "nodes": [], "exiting": exiting}
			root.tree_exiting.connect(exiting)
		var entry: Dictionary = roots[id]
		if entry.built_membership != entry.membership:
			var nodes: Array = root.find_children("*", "CollisionShape3D", true, false)
			nodes.make_read_only()
			entry.nodes = nodes
			entry.built_membership = entry.membership
		elif entry.generation != generation:
			# move_child 不触发节点进出树；只在树变过后线性复核一次，
			# 无关 UI/VFX 增删通常保持原顺序及同一数组，不再扫描全树。
			var nodes: Array = entry.nodes
			for position in range(1, nodes.size()):
				if not nodes[position].is_greater_than(nodes[position - 1]):
					var ordered := nodes.duplicate()
					ordered.sort_custom(func(a: Node, b: Node) -> bool: return b.is_greater_than(a))
					ordered.make_read_only()
					entry.nodes = ordered
					break
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
				source_tree.node_added.disconnect(collision_membership_changed)
				source_tree.node_removed.disconnect(collision_membership_changed)
			on_empty.call()
