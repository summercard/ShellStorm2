class_name HologramExpeditionFacility3D
extends BaseFacility3D

## 基地中央圆形全息平台的正式交互包装。
## 继承基地设施的距离检测和 E 键交互，同时保持原有全息动画循环。

func get_interaction_candidate(player: Player3D) -> Dictionary:
	var candidate := super(player)
	if not candidate.is_empty():
		candidate["position"] = to_global(Vector3(5, 0, -1.72))
	return candidate


func _ready() -> void:
	super()
	for child in find_children("*", "AnimationPlayer", true, false):
		var player := child as AnimationPlayer
		var animations := player.get_animation_list()
		for animation_name in animations:
			if animation_name == "RESET":
				continue
			var animation := player.get_animation(animation_name)
			if animation != null:
				animation.loop_mode = Animation.LOOP_LINEAR
			player.play(animation_name)
			break
