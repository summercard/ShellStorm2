extends Player3DMeleeStateBase

func enter() -> void:
	super.enter()
	melee.enter_spinning()

func physics_update(delta: float) -> void:
	melee.tick_spinning(delta)
