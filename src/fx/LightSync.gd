extends Node
class_name LightSync

# 单一光源纹理同时包含脚下微光和前方锥形视野，避免两盏灯在角色处叠加过曝。
# 房间墙体上的 LightOccluder2D 会截断可视区域，墙后仍保持黑暗。

const VISION_SYSTEM_SCRIPT := preload("res://src/game/VisionSystem.gd")
const LIGHT_TEXTURE_SIZE: int = 512
const CONE_EDGE_SOFTNESS: float = PI * 3.0 / 180.0
const RANGE_EDGE_SOFTNESS: float = 18.0

var _tracked_light: PointLight2D = null


func _ready() -> void:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main:
		call_deferred("_ensure_vision_nodes", main)


func _process(_delta: float) -> void:
	if _tracked_light == null or not is_instance_valid(_tracked_light):
		var main: Node = get_tree().root.find_child("Main", true, false)
		if main:
			_ensure_vision_nodes(main)
		if _tracked_light == null:
			return

	var player: Node2D = _find_player()
	if player == null or not is_instance_valid(player):
		return
	_tracked_light.global_position = player.global_position
	if player.has_method("get_aim_direction"):
		var aim_direction: Vector2 = player.call("get_aim_direction") as Vector2
		if aim_direction.length_squared() > 0.0001:
			_tracked_light.global_rotation = aim_direction.angle()


func _ensure_vision_nodes(main: Node) -> void:
	if main == null or not is_instance_valid(main) or not main.is_inside_tree():
		return
	var darkness: CanvasModulate = main.get_node_or_null("VisionDarkness") as CanvasModulate
	if darkness == null:
		darkness = CanvasModulate.new()
		darkness.name = "VisionDarkness"
		main.add_child(darkness)
	darkness.color = Color(0.0, 0.0, 0.0, 1.0)

	var stale_near_light: PointLight2D = main.get_node_or_null("PlayerNearLight") as PointLight2D
	if stale_near_light != null:
		stale_near_light.enabled = false
		stale_near_light.queue_free()

	_tracked_light = main.get_node_or_null("PlayerVisionLight") as PointLight2D
	if _tracked_light == null:
		_tracked_light = PointLight2D.new()
		_tracked_light.name = "PlayerVisionLight"
		main.add_child(_tracked_light)
	_tracked_light.texture = _make_vision_texture()
	_tracked_light.texture_scale = (
		VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_RADIUS / (LIGHT_TEXTURE_SIZE * 0.5)
	)
	_tracked_light.energy = 1.0
	_tracked_light.shadow_enabled = true
	_tracked_light.shadow_item_cull_mask = 1


func _make_vision_texture() -> ImageTexture:
	var image := Image.create(LIGHT_TEXTURE_SIZE, LIGHT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(LIGHT_TEXTURE_SIZE * 0.5, LIGHT_TEXTURE_SIZE * 0.5)
	var source_radius: float = LIGHT_TEXTURE_SIZE * 0.5
	var half_angle: float = VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_ANGLE * 0.5
	var near_radius: float = (
		source_radius * VISION_SYSTEM_SCRIPT.NEAR_VIEW_RADIUS / VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_RADIUS
	)
	for py in range(LIGHT_TEXTURE_SIZE):
		for px in range(LIGHT_TEXTURE_SIZE):
			var offset := Vector2(float(px), float(py)) - center
			var distance: float = offset.length()
			var angle: float = absf(offset.angle()) if distance > 0.001 else 0.0
			var cone_intensity: float = 0.0
			if distance <= source_radius and angle <= half_angle:
				var edge_alpha := clampf((half_angle - angle) / CONE_EDGE_SOFTNESS, 0.0, 1.0)
				var range_alpha := clampf((source_radius - distance) / RANGE_EDGE_SOFTNESS, 0.0, 1.0)
				cone_intensity = minf(edge_alpha, range_alpha)
			var near_intensity := clampf((near_radius - distance) / RANGE_EDGE_SOFTNESS, 0.0, 1.0)
			var intensity: float = maxf(cone_intensity, near_intensity)
			image.set_pixel(px, py, Color(intensity, intensity, intensity, intensity))
	return ImageTexture.create_from_image(image)


func _find_player() -> Node2D:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main == null:
		return null
	return main.find_child("Player", true, false) as Node2D
