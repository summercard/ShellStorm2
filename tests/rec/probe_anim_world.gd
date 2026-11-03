extends Node3D
## 世界坐标量法：水平位移（是否原地）、脚底最低点（接地）、首末是否闭合（能不能循环）。
## 只读 GLB。

const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const SAMPLES := 24
const CLIPS := [
	"idle", "walk", "run", "attack_light", "attack_heavy", "attack_jump",
	"turn_left", "turn_right", "block", "dodge", "hit", "stagger", "stunned",
	"death", "kneel", "roar", "spawn_standup", "slam",
]


func _ready() -> void:
	_run()
	await get_tree().process_frame
	get_tree().quit(0)


func _run() -> void:
	var node: Node = (load(ELITE_SCENE) as PackedScene).instantiate()
	add_child(node)
	var player := _find_first(node, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(node, "Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		print("W FAIL")
		return
	var hip := skeleton.find_bone("Hip")
	var ltoe := skeleton.find_bone("L_ToeBase")
	var rtoe := skeleton.find_bone("R_ToeBase")
	var lfoot := skeleton.find_bone("L_Foot")
	var rfoot := skeleton.find_bone("R_Foot")
	print("W hip=%d ltoe=%d rtoe=%d lfoot=%d rfoot=%d" % [hip, ltoe, rtoe, lfoot, rfoot])
	print("W clip len start_end_xz hipRangeXZ lowestY riseY loopClose")

	for clip in CLIPS:
		if not player.has_animation(clip):
			print("W %s MISSING" % clip)
			continue
		var length := player.get_animation(clip).length
		player.play(clip, 0.0)
		var first := Vector3.INF
		var last := Vector3.ZERO
		var min_y := 1e9
		var max_y := -1e9
		var min_x := 1e9
		var max_x := -1e9
		var min_z := 1e9
		var max_z := -1e9
		for i in range(SAMPLES + 1):
			var t: float = length * float(i) / float(SAMPLES)
			player.seek(minf(t, length), true)
			var hp := _world(skeleton, hip)
			var lo := 1e9
			for b in [ltoe, rtoe, lfoot, rfoot]:
				if b >= 0:
					lo = minf(lo, _world(skeleton, b).y)
			min_y = minf(min_y, lo)
			max_y = maxf(max_y, lo)
			min_x = minf(min_x, hp.x)
			max_x = maxf(max_x, hp.x)
			min_z = minf(min_z, hp.z)
			max_z = maxf(max_z, hp.z)
			if i == 0:
				first = hp
			last = hp
		var net := Vector2(last.x - first.x, last.z - first.z).length()
		var line := "W " + clip.rpad(14)
		line += " len=%.2f" % length
		line += " netXZ=%.3f" % net
		line += " rangeXZ=%.3f" % maxf(max_x - min_x, max_z - min_z)
		line += " footY=%.3f" % min_y
		line += " riseY=%.3f" % (max_y - min_y)
		print(line)


func _world(skeleton: Skeleton3D, bone: int) -> Vector3:
	if bone < 0:
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f := _find_first(c, cls)
		if f != null:
			return f
	return null
