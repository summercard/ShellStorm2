class_name Player3DDeadState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	_announce("dead")
	player.set("input_locked", true)
	player.call("set_combat_enabled", false)
	player.set("velocity", Vector3.ZERO)
	player.call("move_and_slide")


func physics_update(_delta: float) -> void:
	player.set("velocity", Vector3.ZERO)
	player.call("move_and_slide")


func exit() -> void:
	pass
