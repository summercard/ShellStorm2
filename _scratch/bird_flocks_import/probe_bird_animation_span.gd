extends Node
## 只读探针：dump 两套鸟群动画的位置轨首末关键帧，判断「首尾是否在画外」、
## 以及动画本身在局部空间里从哪走到哪。用于决定接入端摆位与循环间隔。

const FLYBY := "res://assets/art/vfx/environment_3d/bird_flocks/components/flyby/vfx_env_birds_flyby_visual.glb"
const GROUND := "res://assets/art/vfx/environment_3d/bird_flocks/components/ground/vfx_env_birds_ground_visual.glb"


func _ready() -> void:
	_dump("FLYBY", FLYBY)
	_dump("GROUND", GROUND)
	get_tree().quit(0)


func _dump(label: String, path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("%s LOAD_FAILED" % label)
		return
	var root := scene.instantiate() as Node3D
	add_child(root)
	var players := root.find_children("*", "AnimationPlayer", true, false)
	print("%s players=%d" % [label, players.size()])
	for node in players:
		var player := node as AnimationPlayer
		print("%s player_path=%s" % [label, str(root.get_path_to(player))])
		for animation_name in player.get_animation_list():
			if animation_name == "RESET":
				continue
			var animation := player.get_animation(animation_name)
			print("%s anim=%s length=%.3f tracks=%d" % [label, animation_name, animation.length, animation.get_track_count()])
			var union_start := AABB()
			var union_end := AABB()
			var has_start := false
			var has_end := false
			for i in animation.get_track_count():
				if animation.track_get_type(i) != Animation.TYPE_POSITION_3D:
					continue
				var track_path := animation.track_get_path(i)
				var key_count := animation.track_get_key_count(i)
				if key_count < 2:
					continue
				var first := animation.track_get_key_value(i, 0) as Vector3
				var last := animation.track_get_key_value(i, key_count - 1) as Vector3
				var packed_start := AABB(first, Vector3.ZERO)
				var packed_end := AABB(last, Vector3.ZERO)
				union_start = packed_start if not has_start else union_start.merge(packed_start)
				union_end = packed_end if not has_end else union_end.merge(packed_end)
				has_start = true
				has_end = true
				if i < 4:
					print("   track%d %s first=%s last=%s" % [i, str(track_path), str(first), str(last)])
			print("%s SPAN start=%s end=%s" % [label, str(union_start.position) if has_start else "n/a", str(union_end.position) if has_end else "n/a"])
	root.queue_free()
