extends Node3D
## 真关卡里「收租人」到底动没动 —— 直接读数，不靠肉眼。
## godot --headless --path . res://tests/rec/probe_level_elite.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const SAMPLES := 40
const DT := 1.0 / 30.0


func _ready() -> void:
	_run()
	await get_tree().process_frame
	get_tree().quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("PROBE_FAIL scene load")
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
	print("PROBE rooms=%d" % rooms.size())
	if rooms.is_empty():
		print("PROBE_FAIL no rooms")
		return

	# 收集场景里所有敌人
	var enemies := _all_enemies(scene)
	print("PROBE enemies=%d" % enemies.size())
	for e in enemies:
		print("  enemy node=%s class=%s" % [e.name, e.get_class()])

	# 逐帧采样每个敌人：状态名 + 表现层 clip + 骨骼指纹
	for e in enemies:
		_sample_enemy(e)


func _all_enemies(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "", true, false):
		if n is Node3D and n.has_method("sync_presentation"):
			out.append(n)
	return out


func _sample_enemy(enemy: Node3D) -> void:
	var elite_root = _find_presentation(enemy)
	if elite_root == null:
		print("PROBE enemy=%s no presentation root" % enemy.name)
		return
	var player = _find_first(elite_root, "AnimationPlayer")
	var skeleton = _find_first(elite_root, "Skeleton3D")
	print("PROBE enemy=%s pres=%s player=%s skel=%s" % [
		enemy.name, elite_root.name, str(player != null), str(skeleton != null)])
	if player == null or skeleton == null:
		return
	var fingerprints: Array[float] = []
	var states := {}
	var clips := {}
	for i in range(SAMPLES):
		await get_tree().process_frame
		var snap: Dictionary = {}
		if enemy.has_method("get_state_snapshot"):
			snap = enemy.get_state_snapshot()
		var st := str(snap.get("state", snap.get("ai_state", "?")))
		states[st] = true
		var esnap: Dictionary = {}
		if elite_root.has_method("get_presentation_snapshot"):
			esnap = elite_root.call("get_presentation_snapshot")
		clips[str(esnap.get("clip", "?"))] = true
		var fp := 0.0
		for b in [1, 2, mini(10, skeleton.get_bone_count() - 1)]:
			fp += skeleton.get_bone_pose_rotation(b).get_euler().length()
		fingerprints.append(fp)
	print("PROBE states=%s" % str(states.keys()))
	print("PROBE clips=%s" % str(clips.keys()))
	print("PROBE playing=%s" % str((player as AnimationPlayer).current_animation))
	print("PROBE spread=%.6f min=%.5f max=%.5f" % [
		fingerprints.max() - fingerprints.min(), fingerprints.min(), fingerprints.max()])


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
