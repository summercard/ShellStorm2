extends Node
## 只读探针：找出两套鸟群动画里**真正承载位移**的轨道并按时序采样。

const FLYBY := "res://assets/art/vfx/environment_3d/bird_flocks/components/flyby/vfx_env_birds_flyby_visual.glb"
const GROUND := "res://assets/art/vfx/environment_3d/bird_flocks/components/ground/vfx_env_birds_ground_visual.glb"


func _ready() -> void:
	_sample("FLYBY", FLYBY, "鸟01", 25)
	_sample("GROUND", GROUND, "鸟01", 25)
	print("SAMPLE_DONE")
	get_tree().quit(0)


func _sample(label: String, path: String, bird: String, steps: int) -> void:
	var scene := load(path) as PackedScene
	var root := scene.instantiate() as Node3D
	add_child(root)
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var animation_name := ""
	for candidate in player.get_animation_list():
		if candidate != "RESET":
			animation_name = candidate
			break
	var animation := player.get_animation(animation_name)
	var length := animation.length
	print("%s anim=%s length=%.3f tracks=%d" % [label, animation_name, length, animation.get_track_count()])
	var want: Array[int] = []
	for i in animation.get_track_count():
		if animation.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var track_path := str(animation.track_get_path(i))
		if not track_path.contains(bird):
			continue
		var key_count := animation.track_get_key_count(i)
		var first := animation.track_get_key_value(i, 0) as Vector3
		var last := animation.track_get_key_value(i, key_count - 1) as Vector3
		print("  %s track%d %s first=%s last=%s span=%.2f" % [label, i, track_path, str(first), str(last), first.distance_to(last)])
		if first.distance_to(last) > 0.05:
			want.append(i)
	for step in steps + 1:
		var t := length * float(step) / float(steps)
		var parts: Array[String] = []
		for i in want:
			var p: Vector3 = animation.position_track_interpolate(i, t)
			parts.append("(%6.2f,%6.2f,%6.2f)" % [p.x, p.y, p.z])
		print("%s t=%5.2f %s" % [label, t, " ".join(parts)])
	root.queue_free()
