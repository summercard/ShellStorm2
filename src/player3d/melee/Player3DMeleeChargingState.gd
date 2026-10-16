extends Player3DMeleeStateBase

func enter() -> void:
	super.enter()
	melee.enter_charging()

func physics_update(_delta: float) -> void:
	melee.tick_charging()
