class_name Player3DHurtState
extends Player3DStateBase

const HURT_RECOVERY := 0.14
var _remaining := 0.0


func enter() -> void:
	super.enter()
	_remaining = maxf(HURT_RECOVERY, float(player.call("get_hurt_recovery_duration")))
	_announce("hurt", {"damage": int(player.get("_last_damage_amount"))})
	player.set("velocity", (player.get("velocity") as Vector3) * 0.24)


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	var velocity: Vector3 = player.get("velocity") as Vector3
	velocity = velocity.move_toward(Vector3.ZERO, float(player.call("get_move_speed")) * 7.0 * delta)
	var knockback_velocity := player.call("consume_knockback_velocity", delta) as Vector3
	velocity += knockback_velocity
	player.set("velocity", _grounded_velocity(velocity))
	player.call("move_and_slide")
	_remaining -= delta
	if _remaining <= 0.0:
		if bool(player.get("input_locked")):
			_go("locked")
		else:
			player.call("_transition_to_locomotion")
