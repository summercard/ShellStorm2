extends Node3D
## 验证补丁思路：MANUAL 模式下 seek 之后补一次 advance(0) 才能真的刷到骨骼。

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
	player.play("idle", 0.0)
	player.seek(0.0, true)
	print("P9 base fp=%.6f" % _fp(skeleton))
	for t in [1.0, 2.0, 3.0]:
		player.seek(t, true)
		var a := _fp(skeleton)
		player.advance(0.0)
		var b := _fp(skeleton)
		print("P9 t=%.1f seek_only=%.6f after_advance0=%.6f" % [t, a, b])


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
