## PlayerDashingState - 玩家强制突进状态。

class_name PlayerDashingState
extends PlayerStateBase

var _remaining := 0.0


func enter() -> void:
	super.enter()
	_announce("dashing", {"direction": player.dash_direction})
	player.is_dashing = true
	player.is_invincible = true
	_remaining = player.DASH_DURATION


func physics_update(delta: float) -> void:
	if player.current_hp <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	if player.input_locked:
		player.velocity = Vector2.ZERO
		_go("locked")
		return
	else:
		player.velocity = player.dash_direction * player.DASH_SPEED
	player.move_and_slide()
	_remaining -= delta
	if _remaining <= 0.0:
		player.call("_transition_to_locomotion")


func exit() -> void:
	player.is_dashing = false
	# 无敌由 InvincibleTimer 独立解除，状态退出不提前改写。
	_emit_dash_ended()
