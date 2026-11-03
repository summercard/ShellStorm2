extends Node3D
## 精确定位「怪在动不了」的原因：是脚本没跑、还是跑了但没 seek。
## 只读，不改游戏状态。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const ROOM_ID := "room_01"


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL_SCENE)
	var scene := packed.instantiate()
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
	if target == null:
		print("P3_FAIL no room")
		return
	scene.call("_spawn_room_enemies", target)
	for _i in range(6):
		await get_tree().process_frame

	var elite: Enemy3D = null
	var by_room: Dictionary = scene.get("_enemy_nodes_by_room") as Dictionary
	for node in (by_room.get(ROOM_ID, []) as Array):
		var e := node as Enemy3D
		if e != null and is_instance_valid(e) and bool(e.get_enemy_data().get("is_elite", false)):
			elite = e
	if elite == null:
		print("P3_FAIL no elite")
		return
	for _i in range(20):
		await get_tree().process_frame

	var root = _find_presentation(elite)
	var player = _find_first(root, "AnimationPlayer") as AnimationPlayer
	var skeleton = _find_first(root, "Skeleton3D") as Skeleton3D

	_report("T0", elite, root, player, skeleton)
	for _i in range(60):
		await get_tree().process_frame
	_report("T60", elite, root, player, skeleton)

	print("P3 ai_active=%s ai_state=%s process_mode=%d is_processing=%s" % [
		str(elite.call("is_runtime_ai_active")), elite.ai_state,
		elite.process_mode, str(elite.is_processing())])
	print("P3 pres process_mode=%d is_processing=%s visible=%s" % [
		root.process_mode, str(root.is_processing()), str(root.visible)])
	print("P3 player callback_mode=%d speed=%.3f playing=%s active=%s" % [
		int(player.callback_mode_process), player.speed_scale,
		player.current_animation, str(player.active)])
	print("P3 clock=%.4f phase=%.4f sample=%.4f clip_len=%.4f looping=%s" % [
		float(root.get("_clock")), float(root.get("_phase")),
		float(root.get("_sample")), float(root.get("_clip_length")),
		str(root.get("_looping"))])
	print("P3 player_time=%.4f" % player.current_animation_position)


func _report(tag: String, elite: Node3D, root: Node, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var fp := 0.0
	for b in [1, 2, 10]:
		fp += skeleton.get_bone_pose_rotation(b).get_euler().length()
	print("P3 %s fp=%.6f state=%s clip=%s clock=%.4f phase=%.4f ptime=%.4f" % [
		tag, fp, str(root.get("_state")), str(root.get("_clip")),
		float(root.get("_clock")), float(root.get("_phase")), player.current_animation_position])


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
