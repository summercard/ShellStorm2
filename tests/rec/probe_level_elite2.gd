extends Node3D
## 真关卡·真生成路径下「收租人」是否在动 —— 数字判据。
## 复制 record_elite.gd 的生成路径（_spawn_room_enemies），再逐帧取样骨骼。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const ROOM_ID := "room_01"
const SAMPLES := 90

var _elite: Node3D = null


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("P2_FAIL scene load")
		return
	var scene := packed.instantiate()
	add_child(scene)

	var rooms: Array = []
	for i in range(600):
		await get_tree().process_frame
		var value: Variant = scene.get("_rooms")
		if value is Array and (value as Array).size() >= 4:
			rooms = value as Array
			break
	print("P2 rooms=%d" % rooms.size())
	if rooms.is_empty():
		print("P2_FAIL no rooms")
		return

	var target: DungeonRoom3D = null
	for room in rooms:
		var typed := room as DungeonRoom3D
		if typed != null and typed.room_id == ROOM_ID:
			target = typed
	if target == null:
		print("P2_FAIL no room %s" % ROOM_ID)
		return
	print("P2 room elite_id=%s" % str(target.elite_id))

	scene.call("_spawn_room_enemies", target)
	for _i in range(6):
		await get_tree().process_frame

	var by_room: Dictionary = scene.get("_enemy_nodes_by_room") as Dictionary
	var nodes: Array = by_room.get(ROOM_ID, []) as Array
	for node in nodes:
		var enemy := node as Enemy3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var data := enemy.get_enemy_data()
		if bool(data.get("is_elite", false)):
			_elite = enemy
			print("P2 elite found elite_id=%s" % str(data.get("elite_id", "?")))
	if _elite == null:
		print("P2_FAIL no elite in room")
		return

	for _i in range(20):
		await get_tree().process_frame
	print("P2 warmup pos=%s" % str((_elite as Node3D).global_position))

	var root = _find_presentation(_elite)
	if root == null:
		print("P2_FAIL no presentation root")
		return
	var player = _find_first(root, "AnimationPlayer") as AnimationPlayer
	var skeleton = _find_first(root, "Skeleton3D") as Skeleton3D
	print("P2 pres=%s player=%s skel=%s bones=%d" % [
		root.name, str(player != null), str(skeleton != null),
		skeleton.get_bone_count() if skeleton != null else -1])
	if player == null or skeleton == null:
		return

	var fps: Array[float] = []
	var states := {}
	var clips := {}
	var playing := {}
	for i in range(SAMPLES):
		await get_tree().process_frame
		if _elite.has_method("get_state_snapshot"):
			states[str((_elite.get_state_snapshot() as Dictionary).get("state", "?"))] = true
		if root.has_method("get_presentation_snapshot"):
			var snap := root.call("get_presentation_snapshot") as Dictionary
			clips[str(snap.get("clip", "?"))] = true
		playing[player.current_animation] = true
		var fp := 0.0
		for b in [1, 2, mini(10, skeleton.get_bone_count() - 1)]:
			fp += skeleton.get_bone_pose_rotation(b).get_euler().length()
		fps.append(fp)

	print("P2 states=%s" % str(states.keys()))
	print("P2 clips=%s" % str(clips.keys()))
	print("P2 playing=%s" % str(playing.keys()))
	print("P2 spread=%.6f min=%.5f max=%.5f" % [fps.max() - fps.min(), fps.min(), fps.max()])
	var deltas := []
	for i in range(1, fps.size()):
		deltas.append(absf(fps[i] - fps[i - 1]))
	deltas.sort()
	print("P2 stepdelta median=%.6f min=%.6f max=%.6f" % [
		deltas[deltas.size() / 2], deltas[0], deltas[deltas.size() - 1]])
	print("P2 VERDICT %s" % ("MOVING" if (fps.max() - fps.min()) > 0.002 else "FROZEN"))


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
