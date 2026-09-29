class_name Player3DSeatedState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	_announce("seated")
	player.set("is_dashing", false)


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	player.call("_tick_seated", delta)
