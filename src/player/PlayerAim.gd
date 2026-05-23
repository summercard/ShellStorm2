extends Node2D

# PlayerAim - 挂载在 Player/Aim 节点上
# 负责鼠标瞄准，更新 Player 的 aim_direction

var player: CharacterBody2D = null
var aim_range: float = 200.0

func _ready() -> void:
	player = get_parent()

func _process(_delta: float) -> void:
	_aim_at_mouse()

func _aim_at_mouse() -> void:
	if not player:
		return
	var mouse_position = get_global_mouse_position()
	var direction = (mouse_position - global_position).normalized()
	player.set_aim_direction(direction)
	rotation = direction.angle()
