## StateMachine - 通用、可审计的有限状态机
##
## 默认保持“任意已注册状态可互转”，兼容敌人/Boss 旧调用；调用
## configure_transition_map() 后启用显式转移白名单。切换期间再次请求切换时，
## 请求会进入队列，避免 enter/exit 重入破坏 current_state。

class_name StateMachine
extends Node

signal state_changing(from: String, to: String)
signal state_changed(from: String, to: String)
signal transition_rejected(from: String, to: String, reason: String)
signal machine_started(initial_state: String)
signal machine_stopped(previous_state: String)

var current_state_name: String = ""
var previous_state_name: String = ""
var current_state: State = null
var owner_node: Node = null
var state_elapsed: float = 0.0
var transition_count: int = 0

var _states: Dictionary = {}
var _allowed_transitions: Dictionary = {}
var _transition_queue: Array[Dictionary] = []
var _is_transitioning: bool = false
var _rules_enabled: bool = false

const MAX_QUEUED_TRANSITIONS := 16


func register(state_name: String, state: State) -> void:
	if state_name.is_empty():
		push_error("StateMachine.register: 状态名称为空")
		return
	if state == null:
		push_error("StateMachine.register: 状态对象为空")
		return
	state.state_name = state_name
	state.owner = owner_node
	_states[state_name] = state


## 启用转移白名单。格式：{"idle": ["moving", "dead"], "dead": []}
func configure_transition_map(transition_map: Dictionary) -> void:
	_allowed_transitions.clear()
	for from_key in transition_map:
		var from_state := str(from_key)
		var target_set: Dictionary = {}
		var targets = transition_map[from_key]
		if targets is Array:
			for target in targets:
				target_set[str(target)] = true
		_allowed_transitions[from_state] = target_set
	_rules_enabled = true


func clear_transition_rules() -> void:
	_allowed_transitions.clear()
	_rules_enabled = false


func start(state_name: String) -> bool:
	if not _states.has(state_name):
		_reject("", state_name, "unregistered_state")
		return false
	if current_state != null:
		_reject(current_state_name, state_name, "already_started")
		return false
	_rebind_owner()
	current_state_name = state_name
	previous_state_name = ""
	current_state = _states[state_name]
	state_elapsed = 0.0
	transition_count = 1
	_is_transitioning = true
	current_state.enter()
	machine_started.emit(state_name)
	state_changed.emit("", state_name)
	_is_transitioning = false
	_drain_transition_queue()
	return true


func stop() -> void:
	if current_state == null:
		return
	var stopped_state := current_state_name
	current_state.exit()
	previous_state_name = stopped_state
	current_state_name = ""
	current_state = null
	state_elapsed = 0.0
	_transition_queue.clear()
	_is_transitioning = false
	machine_stopped.emit(stopped_state)


func transition_to(state_name: String, force: bool = false) -> bool:
	var reason := get_transition_rejection_reason(state_name, force)
	if not reason.is_empty():
		_reject(current_state_name, state_name, reason)
		return false
	if state_name == current_state_name and not force:
		return false
	if _is_transitioning:
		if _transition_queue.size() >= MAX_QUEUED_TRANSITIONS:
			_reject(current_state_name, state_name, "transition_queue_overflow")
			return false
		_transition_queue.append({"state": state_name, "force": force})
		return true
	_perform_transition(state_name)
	_drain_transition_queue()
	return true


func can_transition_to(state_name: String, force: bool = false) -> bool:
	return get_transition_rejection_reason(state_name, force).is_empty()


func get_transition_rejection_reason(state_name: String, force: bool = false) -> String:
	if not _states.has(state_name):
		return "unregistered_state"
	if current_state == null:
		return "machine_not_started"
	if state_name == current_state_name:
		return "" if force else "same_state"
	if not _rules_enabled:
		return ""
	var targets: Dictionary = _allowed_transitions.get(current_state_name, {})
	if not targets.has(state_name):
		return "transition_not_allowed"
	return ""


func dispatch_event(event_name: String, data = null) -> void:
	if current_state == null:
		return
	var active_state := current_state
	active_state.handle_event(event_name, data)


func physics_update(delta: float) -> void:
	if current_state == null:
		return
	state_elapsed += maxf(0.0, delta)
	var active_state := current_state
	active_state.physics_update(delta)


func has_state(state_name: String) -> bool:
	return _states.has(state_name)


func get_state_count() -> int:
	return _states.size()


func get_state_names() -> Array:
	var names: Array = _states.keys()
	names.sort()
	return names


func is_running() -> bool:
	return current_state != null


func get_snapshot() -> Dictionary:
	return {
		"current": current_state_name,
		"previous": previous_state_name,
		"elapsed": state_elapsed,
		"transition_count": transition_count,
		"queued_transitions": _transition_queue.size(),
		"rules_enabled": _rules_enabled,
		"states": get_state_names(),
	}


func _perform_transition(state_name: String) -> void:
	_is_transitioning = true
	var from_name := current_state_name
	var from_state := current_state
	state_changing.emit(from_name, state_name)
	from_state.exit()
	previous_state_name = from_name
	current_state_name = state_name
	current_state = _states[state_name]
	state_elapsed = 0.0
	transition_count += 1
	current_state.enter()
	state_changed.emit(from_name, state_name)
	_is_transitioning = false


func _drain_transition_queue() -> void:
	var processed := 0
	while not _transition_queue.is_empty() and processed < MAX_QUEUED_TRANSITIONS:
		var request: Dictionary = _transition_queue.pop_front()
		var target := str(request.get("state", ""))
		var force := bool(request.get("force", false))
		var reason := get_transition_rejection_reason(target, force)
		if reason.is_empty() and (target != current_state_name or force):
			_perform_transition(target)
		elif reason != "same_state":
			_reject(current_state_name, target, reason)
		processed += 1
	if not _transition_queue.is_empty():
		_transition_queue.clear()
		_reject(current_state_name, "", "transition_queue_overflow")


func _rebind_owner() -> void:
	for state in _states.values():
		(state as State).owner = owner_node


func _reject(from_state: String, to_state: String, reason: String) -> void:
	transition_rejected.emit(from_state, to_state, reason)
