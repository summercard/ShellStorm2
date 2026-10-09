extends Node
## 只读探针：dump 两套鸟群 GLB 的动画清单与 AnimationPlayer 结构。

const FLYBY := "res://assets/art/vfx/environment_3d/bird_flocks/components/flyby/vfx_env_birds_flyby_visual.glb"
const GROUND := "res://assets/art/vfx/environment_3d/bird_flocks/components/ground/vfx_env_birds_ground_visual.glb"


func _ready() -> void:
	_dump("FLYBY", FLYBY)
	_dump("GROUND", GROUND)
	print("STRUCT_DONE")
	get_tree().quit(0)


func _dump(label: String, path: String) -> void:
	var root := (load(path) as PackedScene).instantiate() as Node3D
	add_child(root)
	print("%s root=%s children=%d" % [label, root.name, root.get_child_count()])
	for node in root.find_children("*", "", true, false):
		if node is AnimationPlayer:
			var player := node as AnimationPlayer
			var names := player.get_animation_list()
			print("  %s ANIM_PLAYER path=%s root_node=%s autoplay=%s count=%d" % [label, str(root.get_path_to(player)), str(player.root_node), str(player.autoplay), names.size()])
			print("  %s ANIM_NAMES=%s" % [label, str(names)])
		elif node is AnimationMixer:
			print("  %s MIXER path=%s" % [label, str(root.get_path_to(node))])
	for child in root.get_children():
		print("  %s TOPCHILD %s (%s)" % [label, child.name, child.get_class()])
	root.queue_free()
