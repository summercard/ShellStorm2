@tool
extends Node3D

func _ready() -> void:
	for child in find_children("*", "AnimationPlayer", true, false):
		var player := child as AnimationPlayer
		var animations := player.get_animation_list()
		for animation_name in animations:
			if animation_name != "RESET":
				player.play(animation_name)
				return

