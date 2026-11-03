extends Node3D
## 最后一问：骨名对得上吗？直接 advance 能不能动？

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

	print("P7 bones=%d" % skeleton.get_bone_count())
	var names := []
	for b in range(mini(8, skeleton.get_bone_count())):
		names.append(skeleton.get_bone_name(b))
	print("P7 first_bones=%s" % str(names))
	print("P7 find_L_ToeBase=%d find_Hip=%d" % [
		skeleton.find_bone("L_ToeBase"), skeleton.find_bone("Hip")])
	var track_bones := []
	for t in range(mini(4, anim.get_track_count())):
		track_bones.append(str(anim.track_get_path(t)))
	print("P7 track_paths=%s" % str(track_bones))
	var k0 = anim.track_get_key_value(0, 0)
	print("P7 track0_keys=%d first=%s" % [anim.track_get_key_count(0), str(k0)])

	var fp0 := _fp(skeleton)
	player.play("walk", 0.0)
	player.seek(0.4, true)
	var fp1 := _fp(skeleton)
	player.seek(1.2, true)
	var fp2 := _fp(skeleton)
	print("P7 seek fp0=%.6f fp1=%.6f fp2=%.6f" % [fp0, fp1, fp2])
	player.advance(1.0)
	print("P7 advance fp3=%.6f" % _fp(skeleton))
	print("P7 bone1_rot=%s bone10_rot=%s" % [
		str(skeleton.get_bone_pose_rotation(1)), str(skeleton.get_bone_pose_rotation(10))])


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
