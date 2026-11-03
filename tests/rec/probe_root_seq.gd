extends Node3D
## 把 Root 骨（根骨）在世界里的位置逐段打印出来：看它是「原地踏步」还是「一路往前挪」。

const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const OUT_PATH := "res://tests/rec/root_report.txt"
const SAMPLES := 12
const CLIPS := ["idle", "walk", "run", "attack_light", "attack_jump", "dodge"]


func _ready() -> void:
	var lines: Array[String] = []
	_run(lines)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	for line in lines:
		f.store_line(line)
	f.close()
	print("RR_DONE")
	get_tree().quit(0)


func _run(lines: Array[String]) -> void:
	var node: Node = (load(ELITE_SCENE) as PackedScene).instantiate()
	add_child(node)
	var player := _find_first(node, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(node, "Skeleton3D") as Skeleton3D
	var root_bone := 0
	lines.append("clip=bones root=%s hip=%s" % [skeleton.get_bone_name(0), skeleton.get_bone_name(1)])
	for clip in CLIPS:
		if not player.has_animation(clip):
			continue
		var length := player.get_animation(clip).length
		player.play(clip, 0.0)
		var seq: Array[String] = []
		for i in range(SAMPLES):
			var t: float = length * float(i) / float(SAMPLES - 1)
			player.seek(minf(t, length * 0.999), true)
			var wp := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone).origin
			seq.append("(%.2f,%.2f)" % [wp.x, wp.z])
		lines.append("%s len=%.2f root_xz: %s" % [clip, length, " ".join(seq)])


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f := _find_first(c, cls)
		if f != null:
			return f
	return null
