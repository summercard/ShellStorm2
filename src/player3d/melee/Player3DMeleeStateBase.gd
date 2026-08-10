class_name Player3DMeleeStateBase
extends State

var melee: PlayerMeleeCombat3D = null


func enter() -> void:
	melee = owner as PlayerMeleeCombat3D


func _go(next_state: String) -> void:
	if melee != null:
		melee.transition_to(next_state)
