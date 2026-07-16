## PlayerMovingState - 玩家持续移动状态。

class_name PlayerMovingState
extends PlayerStateBase


func enter() -> void:
	super.enter()
	_announce("moving")
	player.is_dashing = false


func physics_update(delta: float) -> void:
	if player.current_hp <= 0:
		_go("dead")
		return
	if player.input_locked:
		_go("locked")
		return
	_tick_dash_cooldown(delta)
	if Input.is_action_just_pressed("dash") and _begin_dash():
		return
	var direction := _input_direction()
	if direction == Vector2.ZERO:
		player.velocity = Vector2.ZERO
		player.move_and_slide()
		_go("idle")
		return
	player.last_move_direction = direction
	player.velocity = direction * player.SPEED
	player.move_and_slide()


func handle_event(event_name: String, _data = null) -> void:
	if event_name == "request_dash":
		_begin_dash()
