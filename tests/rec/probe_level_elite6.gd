extends Node3D
## 只回答三件事：树长什么样、轨道路径按 player 的父节点解析得开吗、重绑后骨骼会不会动。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const ROOM_ID := "room_01"


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var scene: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	add_child(scene)
	var rooms: Array = []
	for i in range(600):
		await get_tree().process_frame
		var value: Variant = scene.get("_rooms")
		if value is Array and (value as Array).size() >= 4:
			rooms = value as Array
			break
	var target: DungeonRoom3D = null
	for room in rooms:
		var typed := room as DungeonRoom3D
		if typed != null and typed.room_id == ROOM_ID:
			target = typed
	scene.call("_spawn_room_enemies", target)
	for _i in range(6):
		await get_tree().process_frame
	var elite: Enemy3D = null
	var by_room: Dictionary = scene.get("_enemy_nodes_by_room") as Dictionary
	for node in (by_room.get(ROOM_ID, []) as Array):
		var e := node as Enemy3D
		if e != null and is_instance_valid(e) and bool(e.get_enemy_data().get("is_elite", false)):
			elite = e
	for _i in range(20):
		await get_tree().process_frame

	var root := _find_presentation(elite)
	var player := _find_first(root, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(root, "Skeleton3D") as Skeleton3D
	var anim := player.get_animation("idle")
	var parent := player.get_parent()

	print("P6 player=%s parent=%s" % [player.name, parent.name])
	print("P6 skel=%s skel_parent=%s" % [skeleton.name, skeleton.get_parent().name])
	print("P6 parent_to_skel=%s" % str(parent.get_path_to(skeleton)))

	var depth := 0
	_dump(parent, parent, 0)

	var path0 := anim.track_get_path(0)
	var prefix := str(path0).split(":")[0]
	print("P6 track0=%s prefix=%s node_under_parent=%s node_under_root=%s" % [
		str(path0), prefix,
		str(parent.get_node_or_null(NodePath(prefix)) != null),
		str(root.get_node_or_null(NodePath(prefix)) != null)])

	# 重绑到真实骨架路径
	var real := parent.get_path_to(skeleton)
	var rebound := 0
	for a_name in player.get_animation_list():
		var a := player.get_animation(a_name)
		for track in a.get_track_count():
			var s := str(a.track_get_path(track))
			var colon := s.find(":")
			if colon < 0:
				continue
			a.track_set_path(track, NodePath(str(real) + s.substr(colon)))
			rebound += 1
	print("P6 rebound_tracks=%d" % rebound)

	var before := skeleton.get_bone_pose_rotation(1)
	player.seek(2.5, true)
	print("P6 after_rebind seek2.5 fp=%.6f bone1=%s (was %s)" % [
		_fp(skeleton), str(skeleton.get_bone_pose_rotation(1).get_euler()),
		str(before.get_euler())])


func _fp(skeleton: Skeleton3D) -> float:
	var v := 0.0
	for b in [1, 2, 10]:
		v += skeleton.get_bone_pose_rotation(b).get_euler().length()
	return v


func _dump(node: Node, base: Node, depth: int) -> void:
	if depth > 3:
		return
	print("P6 tree %s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()])
	for c in node.get_children():
		_dump(c, base, depth + 1)


func _find_presentation(root: Node) -> Node:
	if root.name.begins_with("FormalElite_"):
		return root
	for c in root.get_children():
		var f = _find_presentation(c)
		if f != null:
			return f
	return null


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f = _find_first(c, cls)
		if f != null:
			return f
	return null
