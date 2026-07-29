class_name Player3DIdleState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	_announce("idle")
	player.set("is_dashing", false)


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	if bool(player.get("input_locked")):
		_go("locked")
		return
	_tick_dash_cooldown(delta)
	if Input.is_action_just_pressed("dash") and _begin_dash():
		return
	var direction := _input_direction()
	if direction != Vector3.ZERO:
		player.set("last_move_direction", direction)
		player.set("velocity", _grounded_velocity(direction * float(player.call("get_move_speed"))))
		player.call("move_and_slide")
		_go("moving")
		return
	player.set("velocity", _grounded_velocity(Vector3.ZERO))
	player.call("move_and_slide")


func handle_event(event_name: String, _data = null) -> void:
	if event_name == "request_dash":
		_begin_dash()
