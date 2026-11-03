extends Node3D
## 有没有「节点级」位移轨道（不是骨骼，是整个 Armature 被整体挪走）。

const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const OUT_PATH := "res://tests/rec/node_track_report.txt"
const CLIPS := ["idle", "walk", "run", "attack_light", "attack_heavy", "attack_jump"]


func _ready() -> void:
	var lines: Array[String] = []
	var node: Node = (load(ELITE_SCENE) as PackedScene).instantiate()
	add_child(node)
	var player := _find_first(node, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(node, "Skeleton3D") as Skeleton3D
	var armature := skeleton.get_parent() as Node3D
	lines.append("armature=%s parent=%s" % [armature.name, armature.get_parent().name])
	for clip in CLIPS:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		var node_tracks: Array[String] = []
		for t in range(anim.get_track_count()):
			var p := str(anim.track_get_path(t))
			if not p.contains("Skeleton3D:"):
				node_tracks.append("%s(type%d)" % [p, anim.track_get_type(t)])
		lines.append("%s tracks=%d non_bone=%s" % [clip, anim.get_track_count(), str(node_tracks)])
		player.play(clip, 0.0)
		var seq: Array[String] = []
		for i in range(6):
			var tt: float = anim.length * float(i) / 5.0
			player.seek(minf(tt, anim.length * 0.999), true)
			var p := armature.position
			seq.append("(%.2f,%.2f,%.2f)" % [p.x, p.y, p.z])
		lines.append("  armature_pos: %s" % " ".join(seq))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	for line in lines:
		f.store_line(line)
	f.close()
	print("NT_DONE")
	get_tree().quit(0)


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f := _find_first(c, cls)
		if f != null:
			return f
	return null
