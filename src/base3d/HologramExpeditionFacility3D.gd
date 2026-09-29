class_name HologramExpeditionFacility3D
extends BaseFacility3D

var _projection_meshes: Array[Dictionary] = []
var _projection_blend := 0.0

func get_hologram_anchor() -> Vector3:
	return to_global(Vector3(5, 1.85, -1.72))

func set_hologram_city_blend(value: float) -> void:
	_projection_blend = value
	for item in _projection_meshes:
		if is_instance_valid(item.node):
			item.node.transparency = lerpf(float(item.transparency), 1.0, value)

func _collect_projection_meshes() -> void:
	# Geometry above the physical disk is the original animated hologram.
	for item in find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		var bounds := mesh.get_aabb()
		var center := to_local(mesh.to_global(bounds.get_center()))
		if center.y > 1.7:
			_projection_meshes.append({"node": mesh, "transparency": mesh.transparency})

## 基地中央圆形全息平台的正式交互包装。
## 继承基地设施的距离检测和 E 键交互，同时保持原有全息动画循环。

func get_interaction_candidate(player: Player3D) -> Dictionary:
	var candidate := super(player)
	if not candidate.is_empty():
		candidate["position"] = to_global(Vector3(5, 0, -1.72))
	return candidate


func _ready() -> void:
	super()
	_collect_projection_meshes.call_deferred()
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
