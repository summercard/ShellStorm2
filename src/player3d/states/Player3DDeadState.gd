class_name Player3DDeadState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	_announce("dead")
	player.set("input_locked", true)
	player.call("set_combat_enabled", false)
	player.set("velocity", Vector3.ZERO)


func physics_update(delta: float) -> void:
	_move_grounded(Vector3.ZERO, delta, false)


func exit() -> void:
	pass
