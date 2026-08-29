class_name PlayerInteractionController3D
extends Node
## 3D世界唯一的“interact”输入入口。
## 可交互对象只实现候选/聚焦/执行协议，不得自行读取E键。

const PROVIDER_GROUP := "interaction_provider_3d"

var player: Player3D
var _focused_provider: Node
var _focused_candidate: Dictionary = {}


func configure(p_player: Player3D) -> void:
	player = p_player
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_refresh_focused_candidate()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if request_interaction():
		get_viewport().set_input_as_handled()


func request_interaction() -> bool:
	if not _can_player_interact():
		_clear_focus()
		return false
	_refresh_focused_candidate()
	if _focused_provider == null or _focused_candidate.is_empty():
		return false
	if not _focused_provider.has_method("perform_interaction"):
		return false
	return bool(_focused_provider.call(
		"perform_interaction", player, _focused_candidate.duplicate()
	))


func get_focus_snapshot() -> Dictionary:
	if _focused_provider == null or _focused_candidate.is_empty():
		return {}
	return {
		"provider": _focused_provider.name,
		"interaction_id": str(_focused_candidate.get("interaction_id", "")),
		"prompt": str(_focused_candidate.get("prompt", "")),
		"priority": int(_focused_candidate.get("priority", 0)),
		"distance_m": float(_focused_candidate.get("distance_m", INF)),
	}


func _refresh_focused_candidate() -> void:
	if not _can_player_interact() or not is_inside_tree():
		_clear_focus()
		return
	var best_provider: Node = null
	var best_candidate: Dictionary = {}
	for value in get_tree().get_nodes_in_group(PROVIDER_GROUP):
		var provider := value as Node
		if not _provider_is_eligible(provider):
			continue
		var candidate := provider.call("get_interaction_candidate", player) as Dictionary
		if candidate.is_empty() or not bool(candidate.get("available", false)):
			continue
		var position := candidate.get("position", Vector3.INF) as Vector3
		if not position.is_finite():
			continue
		candidate["distance_m"] = player.global_position.distance_to(position)
		if _candidate_is_better(candidate, provider, best_candidate, best_provider):
			best_provider = provider
			best_candidate = candidate
	_set_focus(best_provider, best_candidate)


func _provider_is_eligible(provider: Node) -> bool:
	if (
		provider == null
		or not is_instance_valid(provider)
		or not provider.is_inside_tree()
		or not provider.has_method("get_interaction_candidate")
		or not provider.has_method("perform_interaction")
	):
		return false
	if provider is Node3D:
		return (provider as Node3D).get_world_3d() == player.get_world_3d()
	return true


func _candidate_is_better(
	candidate: Dictionary,
	provider: Node,
	current: Dictionary,
	current_provider: Node
) -> bool:
	if current_provider == null or current.is_empty():
		return true
	var priority := int(candidate.get("priority", 0))
	var current_priority := int(current.get("priority", 0))
	if priority != current_priority:
		return priority > current_priority
	var distance := float(candidate.get("distance_m", INF))
	var current_distance := float(current.get("distance_m", INF))
	if not is_equal_approx(distance, current_distance):
		return distance < current_distance
	return provider.get_instance_id() < current_provider.get_instance_id()


func _set_focus(provider: Node, candidate: Dictionary) -> void:
	var previous_id := str(_focused_candidate.get("interaction_id", ""))
	var next_id := str(candidate.get("interaction_id", ""))
	if (
		_focused_provider != null
		and is_instance_valid(_focused_provider)
		and (_focused_provider != provider or previous_id != next_id)
		and _focused_provider.has_method("set_interaction_focus")
	):
		_focused_provider.call("set_interaction_focus", _focused_candidate, false)
	_focused_provider = provider
	_focused_candidate = candidate
	if (
		_focused_provider != null
		and _focused_provider.has_method("set_interaction_focus")
	):
		_focused_provider.call("set_interaction_focus", _focused_candidate, true)


func _clear_focus() -> void:
	if (
		_focused_provider != null
		and is_instance_valid(_focused_provider)
		and _focused_provider.has_method("set_interaction_focus")
	):
		_focused_provider.call("set_interaction_focus", _focused_candidate, false)
	_focused_provider = null
	_focused_candidate.clear()


func _can_player_interact() -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.is_inside_tree()
		and not get_tree().paused
		and not player.input_locked
		and player.current_hp > 0
	)
