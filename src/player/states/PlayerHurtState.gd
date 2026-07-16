## PlayerHurtState - 短时受创恢复态；无敌时长仍由 InvincibleTimer 独立管理。

class_name PlayerHurtState
extends PlayerStateBase

const HURT_RECOVERY := 0.14
var _remaining := 0.0


func enter() -> void:
	super.enter()
	_remaining = HURT_RECOVERY
	_announce("hurt", {"damage": int(player.get("_last_damage_amount"))})
	player.velocity *= 0.24


func physics_update(delta: float) -> void:
	if player.current_hp <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	player.velocity = player.velocity.move_toward(Vector2.ZERO, player.SPEED * 7.0 * delta)
	player.move_and_slide()
	_remaining -= delta
	if _remaining <= 0.0:
		if player.input_locked:
			_go("locked")
		else:
			player.call("_transition_to_locomotion")
