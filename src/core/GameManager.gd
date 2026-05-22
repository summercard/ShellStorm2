extends Node

signal hp_changed(current: int, maximum: int)
signal shield_changed(current: int, maximum: int)
signal currency_changed(amount: int)

var max_hp: int = 100
var current_hp: int = 100
var max_shield: int = 0
var current_shield: int = 0
var currency: int = 0

var difficulty_multiplier: float = 1.0

func _ready() -> void:
	hp_changed.emit(current_hp, max_hp)
	currency_changed.emit(currency)

func take_damage(amount: int) -> void:
	var remaining = amount
	if current_shield > 0:
		var shield_damage = min(current_shield, remaining)
		current_shield -= shield_damage
		remaining -= shield_damage
		shield_changed.emit(current_shield, max_shield)
	
	if remaining > 0:
		current_hp = max(0, current_hp - remaining)
		hp_changed.emit(current_hp, max_hp)
		if current_hp <= 0:
			Global.trigger_game_over()

func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)

func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)

func spend_currency(amount: int) -> bool:
	if currency >= amount:
		currency -= amount
		currency_changed.emit(currency)
		return true
	return false

func reset() -> void:
	current_hp = max_hp
	current_shield = 0
	hp_changed.emit(current_hp, max_hp)
	shield_changed.emit(current_shield, max_shield)