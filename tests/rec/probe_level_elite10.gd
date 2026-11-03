extends Node3D
## 逐帧把「内部状态」和「骨骼读数」并排打出来，定位到底是谁把姿势钉住了。

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

	for step in range(4):
		for _i in range(20):
			await get_tree().process_frame
		var prev: Array = root.get("_previous_pose")
		print("P10 s=%d fp=%.6f ptime=%.4f phase=%.4f sample=%.4f blend=%.4f prev=%d looping=%s clip=%s state=%s" % [
			step, _fp(skeleton), player.current_animation_position,
			float(root.get("_phase")), float(root.get("_sample")),
			float(root.get("_blend_time")), prev.size(),
			str(root.get("_looping")), str(root.get("_clip")), str(root.get("_state"))])


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
