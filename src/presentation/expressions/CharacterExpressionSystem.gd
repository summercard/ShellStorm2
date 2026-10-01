class_name CharacterExpressionSystem
extends Node
## Sole owner of expression selection and cosmetic timing. No actor/Autoload dependencies.

signal expression_changed(expression_id: String)
var current_expression := "neutral"
var random_enabled := true
var random_seed := 0
var _hold_remaining := 0.0
var _remaining_to_random := 4.0
var _change_count := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

func _process(delta: float) -> void:
	advance(delta)

func request_expression(expression_id: String, hold_seconds := 2.0) -> bool:
	if not CharacterExpressionCatalog.has_expression(expression_id) or not is_finite(hold_seconds) or hold_seconds < 0.0:
		return false
	_hold_remaining = hold_seconds
	_remaining_to_random = _rng.randf_range(3.0, 6.0)
	if expression_id != current_expression:
		current_expression = expression_id
		_change_count += 1
		expression_changed.emit(current_expression)
	return true

func request_random(hold_seconds := 2.0) -> bool:
	if not is_finite(hold_seconds) or hold_seconds < 0.0:
		return false
	var choices := CharacterExpressionCatalog.get_ids()
	choices.erase(current_expression)
	if choices.is_empty():
		return false
	return request_expression(choices[_rng.randi_range(0, choices.size() - 1)], hold_seconds)

func set_random_enabled(enabled: bool) -> void:
	random_enabled = enabled

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var available := maxf(0.0, delta - _hold_remaining)
	_hold_remaining = maxf(0.0, _hold_remaining - delta)
	if not random_enabled or available <= 0.0:
		return
	_remaining_to_random -= available
	if _remaining_to_random <= 0.0:
		request_random(0.0)

func get_snapshot() -> Dictionary:
	return {"schema": 1, "expression_id": current_expression, "random_enabled": random_enabled,
		"hold_remaining": _hold_remaining, "remaining_to_random": _remaining_to_random, "change_count": _change_count}
