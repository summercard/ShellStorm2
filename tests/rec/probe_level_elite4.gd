extends Node3D
## 动画数据是否真的绑在骨架上：轨道路径能不能被解析、采样点变化时骨骼变不变。

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
	print("P4 anims=%s" % str(player.get_animation_list()))
	print("P4 root_node=%s" % str(player.root_node))
	print("P4 skel_name=%s bones=%d" % [skeleton.name, skeleton.get_bone_count()])
	var anim := player.get_animation("idle")
	print("P4 idle len=%.3f tracks=%d" % [anim.length, anim.get_track_count()])
	for t in range(mini(6, anim.get_track_count())):
		var path := anim.track_get_path(t)
		print("P4 track%d type=%d path=%s keys=%d resolved=%s" % [
			t, anim.track_get_type(t), str(path), anim.track_get_key_count(t),
			str(root.get_node_or_null(path) != null)])
	# 直接把播放头拽到不同位置，看骨骼是否跟着变
	for t in [0.5, 2.0, 4.0]:
		player.seek(t, true)
		var fp := 0.0
		for b in [1, 2, 10]:
			fp += skeleton.get_bone_pose_rotation(b).get_euler().length()
		print("P4 seek=%.1f fp=%.6f bone1=%s" % [t, fp, str(skeleton.get_bone_pose_rotation(1).get_euler())])


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
