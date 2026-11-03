extends Node3D
## 世界坐标量法 v2：结果直接写文件，避免管道丢输出。
## 指标：水平净位移（是否原地）、水平活动范围、脚底最低点（接地）、首末闭合（能否循环）。

const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const OUT_PATH := "res://tests/rec/anim_report.txt"
const SAMPLES := 16
const CLIPS := [
	"idle", "walk", "run", "attack_light", "attack_heavy", "attack_jump",
	"turn_left", "turn_right", "block", "dodge", "hit", "stagger", "stunned",
	"death", "kneel", "roar", "spawn_standup", "slam",
]


func _ready() -> void:
	var lines: Array[String] = []
	_run(lines)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	for line in lines:
		f.store_line(line)
	f.close()
	print("WW_DONE %d" % lines.size())
	get_tree().quit(0)


func _run(lines: Array[String]) -> void:
	var node: Node = (load(ELITE_SCENE) as PackedScene).instantiate()
	add_child(node)
	var player := _find_first(node, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(node, "Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		lines.append("FAIL player/skel")
		return
	var hip := skeleton.find_bone("Hip")
	var toes := [skeleton.find_bone("L_ToeBase"), skeleton.find_bone("R_ToeBase"), skeleton.find_bone("L_Foot"), skeleton.find_bone("R_Foot")]
	lines.append("clip|len|netXZ|rangeXZ|footY|riseY|scale_check")
	for clip in CLIPS:
		if not player.has_animation(clip):
			lines.append("%s|MISSING" % clip)
			continue
		var length := player.get_animation(clip).length
		player.play(clip, 0.0)
		var first := Vector3.INF
		var last := Vector3.ZERO
		var foot_min := 1e9
		var foot_max := -1e9
		var hx_min := 1e9
		var hx_max := -1e9
		var hz_min := 1e9
		var hz_max := -1e9
		for i in range(SAMPLES + 1):
			var t: float = length * float(i) / float(SAMPLES)
			player.seek(minf(t, length), true)
			var hp := _world(skeleton, hip)
			var lo := 1e9
			for b in toes:
				if int(b) >= 0:
					lo = minf(lo, _world(skeleton, int(b)).y)
			foot_min = minf(foot_min, lo)
			foot_max = maxf(foot_max, lo)
			hx_min = minf(hx_min, hp.x)
			hx_max = maxf(hx_max, hp.x)
			hz_min = minf(hz_min, hp.z)
			hz_max = maxf(hz_max, hp.z)
			if i == 0:
				first = hp
			last = hp
		var net := Vector2(last.x - first.x, last.z - first.z).length()
		var rng := maxf(hx_max - hx_min, hz_max - hz_min)
		lines.append("%s|%.2f|%.3f|%.3f|%.3f|%.3f|%.2f" % [
			clip, length, net, rng, foot_min, foot_max - foot_min, skeleton.scale.y])


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
