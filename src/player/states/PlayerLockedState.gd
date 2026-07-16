## PlayerLockedState - 菜单、交互和转场的显式输入锁定态。

class_name PlayerLockedState
extends PlayerStateBase


func enter() -> void:
	super.enter()
	_announce("locked")
	player.velocity = Vector2.ZERO


func physics_update(delta: float) -> void:
	if player.current_hp <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	player.velocity = Vector2.ZERO
	player.move_and_slide()
	if not player.input_locked:
		player.call("_transition_to_locomotion")
