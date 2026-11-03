extends Node3D
## 逐段量「根骨/胯骨」位移：判定是不是原地动画、接地如何、循环能不能对上。
## 只读 GLB 里的剪辑数据，不依赖玩法。

const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const SAMPLES := 40
const CLIPS := [
	"idle", "walk", "run", "turn_left", "turn_right",
	"attack_light", "attack_heavy", "attack_jump",
	"block", "dodge", "hit", "stagger", "stunned",
	"death", "kneel", "roar", "spawn_standup", "slam",
]


func _ready() -> void:
	_run()
	await get_tree().process_frame
	get_tree().quit(0)


func _run() -> void:
	var packed: PackedScene = load(ELITE_SCENE)
	if packed == null:
		print("A FAIL scene")
		return
	var node := packed.instantiate()
	add_child(node)
	var player := _find_first(node, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(node, "Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		print("A FAIL player/skel")
		return
	print("A bones=%d clips=%d" % [skeleton.get_bone_count(), player.get_animation_list().size()])
	print("A root_bone=%s hip_bone=%s" % [skeleton.get_bone_name(0), skeleton.get_bone_name(1)])

	for clip in CLIPS:
		if not player.has_animation(clip):
			print("A %s MISSING" % clip)
			continue
		_measure(player, skeleton, clip)


func _measure(player: AnimationPlayer, skeleton: Skeleton3D, clip: String) -> void:
	var anim := player.get_animation(clip)
	var length := anim.length
	player.play(clip, 0.0)
	player.seek(0.0, true)
	var first_root := skeleton.get_bone_pose_position(0)
	var first_hip := skeleton.get_bone_pose_position(1)
	var min_y := 1e9
	var max_y := -1e9
	var path_len := 0.0
	var prev := first_hip
	var hip_min := Vector3.ZERO
	var hip_max := Vector3.ZERO
	var initialized := false
	for i in range(SAMPLES + 1):
		var t := length * float(i) / float(SAMPLES)
		player.seek(minf(t, length), true)
		var hip := skeleton.get_bone_pose_position(1)
		var root := skeleton.get_bone_pose_position(0)
		var y := minf(hip.y, root.y)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
		if not initialized:
			hip_min = hip
			hip_max = hip
			initialized = true
		else:
			path_len += prev.distance_to(hip)
			hip_min = Vector3(minf(hip_min.x, hip.x), minf(hip_min.y, hip.y), minf(hip_min.z, hip.z))
			hip_max = Vector3(maxf(hip_max.x, hip.x), maxf(hip_max.y, hip.y), maxf(hip_max.z, hip.z))
		prev = hip
	player.seek(length, true)
	var last_hip := skeleton.get_bone_pose_position(1)
	var last_root := skeleton.get_bone_pose_position(0)
	var net_dxz := Vector2(last_hip.x - first_hip.x, last_hip.z - first_hip.z).length()
	var range_x := hip_max.x - hip_min.x
	var range_z := hip_max.z - hip_min.z
	var loop_delta := Vector2(last_hip.x - first_hip.x, last_hip.z - first_hip.z).length()
	print("A %-14s len=%5.2f net=%5.3f path=%5.3f rngX=%5.3f rngZ=%5.3f yMin=%6.3f yMax=%6.3f rootNet=%5.3f loopd=%5.3f" % [
		clip, length, net_dxz, path_len, range_x, range_z, min_y, max_y,
		Vector2(last_root.x - first_root.x, last_root.z - first_root.z).length(), loop_delta])


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f = _find_first(c, cls)
		if f != null:
			return f
	return null
