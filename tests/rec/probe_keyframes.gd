extends Node3D
## 直接读关键帧数据（不播放、不 seek）：胯骨/根骨到底有没有水平位移。
## 这样避开播放器取样的干扰，结果是文件里写的真数据。

const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const OUT_PATH := "res://tests/rec/keyframe_report.txt"
const CLIPS := [
	"idle", "walk", "run", "attack_light", "attack_heavy", "attack_jump",
	"turn_left", "turn_right", "block", "dodge", "hit", "stagger", "stunned",
	"death", "kneel", "roar", "spawn_standup", "slam",
]


func _ready() -> void:
	var lines: Array[String] = []
	var node: Node = (load(ELITE_SCENE) as PackedScene).instantiate()
	add_child(node)
	var player := _find_first(node, "AnimationPlayer") as AnimationPlayer
	lines.append("clip|bone|keys|first_xz|last_xz|net_xz|range_x|range_z")
	for clip in CLIPS:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		for t in range(anim.get_track_count()):
			var path := str(anim.track_get_path(t))
			var bone := path.get_slice(":", 1)
			if bone != "Hip" and bone != "Root":
				continue
			if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			var keys := anim.track_get_key_count(t)
			if keys < 1:
				continue
			var first: Vector3 = anim.track_get_key_value(t, 0)
			var last: Vector3 = anim.track_get_key_value(t, keys - 1)
			var mn := Vector3(first.x, 0, first.z)
			var mx := mn
			for k in range(keys):
				var v: Vector3 = anim.track_get_key_value(t, k)
				mn = Vector3(minf(mn.x, v.x), 0, minf(mn.z, v.z))
				mx = Vector3(maxf(mx.x, v.x), 0, maxf(mx.z, v.z))
			var net := Vector2(last.x - first.x, last.z - first.z).length()
			lines.append("%s|%s|%d|(%.2f,%.2f)|(%.2f,%.2f)|%.3f|%.3f|%.3f" % [
				clip, bone, keys, first.x, first.z, last.x, last.z, net, mx.x - mn.x, mx.z - mn.z])
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	for line in lines:
		f.store_line(line)
	f.close()
	print("KF_DONE %d" % lines.size())
	get_tree().quit(0)


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f := _find_first(c, cls)
		if f != null:
			return f
	return null
