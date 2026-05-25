extends Node
class_name LightSync

# LightSync — 将 PlayerVisionLight 绑定到 Player 位置
# 挂载在 Main 节点下（与 VisionDarkness 同级）
# 每帧查找 Player 并同步光源位置（轻量实现，无硬依赖）

var _tracked_light: Light2D = null
var _player_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main:
		_tracked_light = main.find_child("PlayerVisionLight", true, false) as Light2D

func _process(delta: float) -> void:
	if _tracked_light == null or not is_instance_valid(_tracked_light):
		# 重新查找
		var main: Node = get_tree().root.find_child("Main", true, false)
		if main:
			_tracked_light = main.find_child("PlayerVisionLight", true, false) as Light2D
		if _tracked_light == null:
			return
	
	# 查找玩家位置
	var player: Node2D = _find_player()
	if player and is_instance_valid(player):
		_player_pos = player.global_position
		_tracked_light.global_position = _player_pos

func _find_player() -> Node2D:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main == null:
		return null
	return main.find_child("Player", true, false) as Node2D