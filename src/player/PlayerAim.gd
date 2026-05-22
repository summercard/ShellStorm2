extends Node2D

@onready var player: CharacterBody2D = get_parent()
@onready var aim_line: Line2D = $AimLine

var aim_range: float = 200.0

func _process(_delta: float) -> void:
	_aim_at_mouse()

func _aim_at_mouse() -> void:
	var mouse_position = get_global_mouse_position()
	var direction = (mouse_position - global_position).normalized()
	player.set_aim_direction(direction)
	rotation = direction.angle()
	
	if aim_line:
		aim_line.points = [Vector2.ZERO, direction * aim_range]