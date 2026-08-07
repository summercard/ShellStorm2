extends Node
class_name LightSync

# 单一光源纹理同时包含脚下微光和前方锥形视野，避免两盏灯在角色处叠加过曝。
# 房间墙体上的 LightOccluder2D 会截断可视区域，墙后仍保持黑暗。

const VISION_SYSTEM_SCRIPT := preload("res://src/game/VisionSystem.gd")
const VISIBILITY_LIGHT_SCRIPT := preload("res://src/fx/VisibilityLight2D.gd")

# 玩家位置/朝向阈值；未超过阈值时跳过光照位置/角度写入。
const POS_EPSILON_SQ := 0.0025
const ANG_EPSILON := 0.005
# 每 N 帧（按 60FPS ≈ 每秒 6 次）强制重写一次光源位置，保证长时间静止时
# 灯仍能跟上世界状态变化。
const FORCE_REFRESH_INTERVAL := 10

var _tracked_light: PointLight2D = null
var _last_player_pos := Vector2.ZERO
var _last_player_aim := 0.0
var _has_last_state := false
var _frame_counter := 0


func _ready() -> void:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main:
		call_deferred("_ensure_vision_nodes", main)


func _process(_delta: float) -> void:
	_frame_counter += 1
	if _tracked_light == null or not is_instance_valid(_tracked_light):
		var main: Node = get_tree().root.find_child("Main", true, false)
		if main:
			_ensure_vision_nodes(main)
		if _tracked_light == null:
			return

	var player: Node2D = _find_player()
	if player == null or not is_instance_valid(player):
		return

	var current_pos := player.global_position
	# 玩家没移动、瞄准方向没变，且还没到强制刷新间隔时，跳过写入。
	if _has_last_state and _frame_counter < FORCE_REFRESH_INTERVAL:
		if current_pos.distance_squared_to(_last_player_pos) < POS_EPSILON_SQ:
			var aim_direction: Vector2 = player.call("get_aim_direction") as Vector2
			if (
				aim_direction.length_squared() <= 0.0001
				or absf(aim_direction.angle() - _last_player_aim) < ANG_EPSILON
			):
				return
	_frame_counter = 0
	_last_player_pos = current_pos
	_has_last_state = true

	_tracked_light.global_position = current_pos
	if player.has_method("get_aim_direction"):
		var aim_direction2: Vector2 = player.call("get_aim_direction") as Vector2
		if aim_direction2.length_squared() > 0.0001:
			var new_angle: float = aim_direction2.angle()
			_tracked_light.global_rotation = new_angle
			_last_player_aim = new_angle


func _ensure_vision_nodes(main: Node) -> void:
	if main == null or not is_instance_valid(main) or not main.is_inside_tree():
		return
	var darkness: CanvasModulate = main.get_node_or_null("VisionDarkness") as CanvasModulate
	if darkness == null:
		darkness = CanvasModulate.new()
		darkness.name = "VisionDarkness"
		main.add_child(darkness)
	# Preserve tension without erasing the level.  Pure black made navigation,
	# enemy silhouettes and authored replacement assets disappear outside the cone.
	darkness.color = Color(0.24, 0.30, 0.42, 1.0)

	var stale_near_light: PointLight2D = main.get_node_or_null("PlayerNearLight") as PointLight2D
	if stale_near_light != null:
		stale_near_light.enabled = false
		stale_near_light.queue_free()

	var player: Node2D = _find_player()
	var created_light := false
	if player != null:
		_tracked_light = player.get_node_or_null("PlayerVisionLight") as PointLight2D
	else:
		_tracked_light = null
	if _tracked_light == null:
		_tracked_light = main.get_node_or_null("PlayerVisionLight") as PointLight2D
	if _tracked_light == null:
		_tracked_light = VISIBILITY_LIGHT_SCRIPT.new() as PointLight2D
		_tracked_light.name = "PlayerVisionLight"
		_tracked_light.energy = 0.92
		_tracked_light.color = Color(0.72, 0.90, 1.0, 1.0)
		_tracked_light.call(
			"configure_flashlight",
			VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_RADIUS,
			VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_ANGLE,
			VISION_SYSTEM_SCRIPT.NEAR_VIEW_RADIUS
		)
		if player != null:
			player.add_child(_tracked_light)
		else:
			main.add_child(_tracked_light)
		created_light = true
	elif player != null and _tracked_light.get_parent() != player:
		_tracked_light.get_parent().remove_child(_tracked_light)
		player.add_child(_tracked_light)
	_tracked_light.position = Vector2.ZERO
	_tracked_light.energy = 0.92
	_tracked_light.color = Color(0.72, 0.90, 1.0, 1.0)
	if not created_light and _tracked_light.has_method("configure_flashlight"):
		_tracked_light.call(
			"configure_flashlight",
			VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_RADIUS,
			VISION_SYSTEM_SCRIPT.DEFAULT_VIEW_ANGLE,
			VISION_SYSTEM_SCRIPT.NEAR_VIEW_RADIUS
		)


func _find_player() -> Node2D:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main == null:
		return null
	return main.find_child("Player", true, false) as Node2D
