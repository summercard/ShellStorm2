extends Node

# 以安全房（start）为样本，对比「动态装配」与「静态 TSCN」两条路径产出的
# 节点集与元数据，列出静态场景尚未带入的东西。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199
const TARGET_ROOM := "start"

var failures: Array[String] = []

func _ready() -> void:
	var dynamic := await _build_and_dump(false, "DYNAMIC")
	var static_ := await _build_and_dump(true, "STATIC")
	_compare(dynamic, static_)
	if failures.is_empty():
		print("SAFE_ROOM_STATIC_PARITY_OK")
	else:
		for failure in failures:
			print("GAP %s" % failure)
	print("SAFE_ROOM_STATIC_PARITY_DONE gaps=%d" % failures.size())
	get_tree().quit(0)

func _build_and_dump(use_static: bool, label: String) -> Dictionary:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = use_static
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _index in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	var room := block.get_node_or_null(TARGET_ROOM) as DungeonRoom3D
	room.ensure_shell_built()
	await get_tree().process_frame
	var art_root := room.get_node_or_null("SafeRoomArtRoot") as Node3D
	var result := {}
	result["art_root_found"] = art_root != null
	result["children"] = []
	result["child_metas"] = {}
	result["art_root_metas"] = {}
	result["room_metas"] = {}
	if art_root != null:
		for child in art_root.get_children():
			result["children"].append("%s:%s" % [child.name, child.get_class()])
			var metas := {}
			for meta_name in child.get_meta_list():
				metas[str(meta_name)] = str(child.get_meta(meta_name))
			result["child_metas"][str(child.name)] = metas
		for meta_name in art_root.get_meta_list():
			result["art_root_metas"][str(meta_name)] = str(art_root.get_meta(meta_name))
	for meta_name in room.get_meta_list():
		result["room_metas"][str(meta_name)] = str(room.get_meta(meta_name))
	result["room_children"] = []
	for child in room.get_children():
		result["room_children"].append("%s:%s" % [child.name, child.get_class()])
	result["room_child_counts"] = {}
	for child in room.get_children():
		var count := 0
		for value in child.find_children("*", "", true, false):
			count += 1
		result["room_child_counts"][str(child.name)] = count
	print("=== %s ===" % label)
	print("art_root=%s children=%d" % [str(result["art_root_found"]), result["children"].size()])
	for entry in result["children"]:
		print("  CHILD %s" % entry)
	print("ART_ROOT_METAS %s" % JSON.stringify(result["art_root_metas"]))
	print("ROOM_METAS %s" % JSON.stringify(result["room_metas"]))
	print("ROOM_CHILDREN %s" % JSON.stringify(result["room_children"]))
	print("ROOM_CHILD_COUNTS %s" % JSON.stringify(result["room_child_counts"]))
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	return result

## 把 `["名字:类", …]` 拆成「有名字的节点」与「自动命名节点的类→个数」。
## 🔴 运行时建的节点由 Godot 取名 `@Area3D@152` —— 尾号是**实例 id**，两次装配必然不同，
## 所以这类节点**不能按名字比对**（会稳定报出「静态缺一个 @Area3D@A、多一个 @Area3D@B」
## 的假阳性），只能按「类 + 个数」比对；有名字的节点仍逐个按名字比对。
func _split_children(entries: Array) -> Dictionary:
	var named := {}
	var auto_by_class := {}
	for entry in entries:
		var parts := str(entry).split(":")
		var node_name := parts[0]
		if node_name.begins_with("@"):
			var node_class := parts[1] if parts.size() > 1 else ""
			auto_by_class[node_class] = int(auto_by_class.get(node_class, 0)) + 1
		else:
			named[node_name] = str(entry)
	return {"named": named, "auto_by_class": auto_by_class}


func _compare_child_sets(dynamic_entries: Array, static_entries: Array, scope: String) -> void:
	var dynamic_split := _split_children(dynamic_entries)
	var static_split := _split_children(static_entries)
	var dynamic_named: Dictionary = dynamic_split["named"]
	var static_named: Dictionary = static_split["named"]
	for node_name in dynamic_named:
		if not static_named.has(node_name):
			failures.append("%s缺少子节点 %s（动态有）" % [scope, dynamic_named[node_name]])
		elif dynamic_named[node_name] != static_named[node_name]:
			failures.append(
				"%s子节点类型不同 %s vs %s"
				% [scope, dynamic_named[node_name], static_named[node_name]]
			)
	for node_name in static_named:
		if not dynamic_named.has(node_name):
			failures.append("%s多出子节点 %s" % [scope, static_named[node_name]])
	var dynamic_auto: Dictionary = dynamic_split["auto_by_class"]
	var static_auto: Dictionary = static_split["auto_by_class"]
	for node_class in dynamic_auto:
		var static_count := int(static_auto.get(node_class, 0))
		var dynamic_count := int(dynamic_auto[node_class])
		if static_count != dynamic_count:
			failures.append(
				"%s自动命名子节点数不同 class=%s 动态 %d vs 静态 %d"
				% [scope, node_class, dynamic_count, static_count]
			)
	for node_class in static_auto:
		if not dynamic_auto.has(node_class):
			failures.append(
				"%s多出自动命名子节点 class=%s（静态 %d 个）"
				% [scope, node_class, int(static_auto[node_class])]
			)


func _compare(dynamic: Dictionary, static_: Dictionary) -> void:
	if not bool(dynamic.get("art_root_found", false)):
		failures.append("动态路径没有 SafeRoomArtRoot")
	if not bool(static_.get("art_root_found", false)):
		failures.append("静态路径没有 SafeRoomArtRoot")
	var dynamic_children: Array = dynamic.get("children", [])
	var static_children: Array = static_.get("children", [])
	_compare_child_sets(dynamic_children, static_children, "静态场景")
	for meta_name in dynamic.get("art_root_metas", {}):
		if not static_.get("art_root_metas", {}).has(meta_name):
			failures.append(
				"静态艺术根缺少 meta %s=%s"
				% [meta_name, str(dynamic["art_root_metas"][meta_name])]
			)
	for meta_name in dynamic.get("room_metas", {}):
		if (
			str(meta_name).begins_with("safe_room")
			or str(meta_name).begins_with("tower_wall_door_offset")
		) and not static_.get("room_metas", {}).has(meta_name):
			failures.append(
				"静态路径房间缺少 meta %s=%s"
				% [meta_name, str(dynamic["room_metas"][meta_name])]
			)
	var dynamic_room_children: Array = dynamic.get("room_children", [])
	var static_room_children: Array = static_.get("room_children", [])
	_compare_child_sets(dynamic_room_children, static_room_children, "静态房间")
	var dynamic_child_metas: Dictionary = dynamic.get("child_metas", {})
	var static_child_metas: Dictionary = static_.get("child_metas", {})
	# 自动命名节点的 key 同样带实例 id，两侧对不上 ⇒ 这里天然只核对有名字的节点；
	# 自动命名节点的存在性已由上面的「类 + 个数」比对覆盖。
	for child_name in dynamic_child_metas:
		if not static_child_metas.has(child_name):
			continue
		for meta_name in dynamic_child_metas[child_name]:
			if not static_child_metas[child_name].has(meta_name):
				failures.append(
					"静态节点 %s 缺少 meta %s" % [child_name, meta_name]
				)
