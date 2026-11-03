extends Node3D
## 判 idle 是不是「静止段」：直接把播放头拉到多个时间点，看骨骼姿势有没有差别。

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

	for clip in ["idle", "walk", "run", "block"]:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		player.play(clip, 0.0)
		var line := ""
		for t in [0.0, 0.5, 1.0, 2.0, 3.0, 4.0]:
			if t > anim.length:
				continue
			player.seek(t, true)
			line += " t%.1f=%.5f" % [t, _fp(skeleton)]
		print("P8 %s%s" % [clip, line])

	# 直接看轨道关键值有没有变化（不依赖播放）
	var idle := player.get_animation("idle")
	var varying := 0
	var flat := 0
	for track in idle.get_track_count():
		var keys := idle.track_get_key_count(track)
		if keys < 2:
			continue
		var first = idle.track_get_key_value(track, 0)
		var diff := false
		for k in range(1, keys):
			if str(idle.track_get_key_value(track, k)) != str(first):
				diff = true
				break
		if diff:
			varying += 1
		else:
			flat += 1
	print("P8 idle_tracks varying=%d flat=%d total=%d" % [varying, flat, idle.get_track_count()])


func _fp(skeleton: Skeleton3D) -> float:
	var v := 0.0
	for b in [1, 2, 10]:
		v += skeleton.get_bone_pose_rotation(b).get_euler().length()
	return v


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
