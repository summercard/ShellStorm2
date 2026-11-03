extends Node3D
## 打印表现层节点树 + 验证「重绑轨道路径」能不能让动画真的驱动骨骼。

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

	print("P5 player_path=%s root_node=%s" % [str(player.get_path()), str(player.root_node)])
	print("P5 skeleton_path=%s" % str(skeleton.get_path()))
	print("P5 real_bone_prefix=%s" % str(player.get_path().get_concatenated_names().slice(0, -1)))

	print("P5 === tree ===")
	_dump(root, root)

	# 试着重绑：把每条轨道换成「从 player.root_node 出发」的真实路径
	var base := NodePath("..")
	var want_suffix := anim.track_get_path(0)
	print("P5 sample_track=%s" % str(want_suffix))
	# 找出从 root 到 skeleton 的路径
	var skel_rel: NodePath = root.get_path_to(skeleton)
	print("P5 skel_rel_from_root=%s" % str(skel_rel))
	var from_player_parent: NodePath = player.get_node("..").get_path_to(skeleton)
	print("P5 skel_rel_from_player_parent=%s" % str(from_player_parent))

	var rebound := 0
	for track in anim.get_track_count():
		var p := anim.track_get_path(track)
		var s := str(p)
		var colon := s.find(":")
		if colon < 0:
			continue
		var bone := s.substr(colon)
		var new_path := NodePath(str(from_player_parent) + bone)
		anim.track_set_path(track, new_path)
		if root.get_node_or_null(new_path) != null:
			rebound += 1
	print("P5 rebound=%d/%d" % [rebound, anim.get_track_count()])
	for t in [0.5, 2.0, 4.0]:
		player.seek(t, true)
		var fp := 0.0
		for b in [1, 2, 10]:
			fp += skeleton.get_bone_pose_rotation(b).get_euler().length()
		print("P5 after seek=%.1f fp=%.6f bone1=%s" % [t, fp, str(skeleton.get_bone_pose_rotation(1).get_euler())])


func _dump(node: Node, root: Node) -> void:
	var depth := str(root.get_path_to(node)).count("/")
	if depth > 4:
		return
	print("  %s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()])
	for c in node.get_children():
		_dump(c, root)


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
