extends Node

class QueueingState:
	extends State
	var machine: StateMachine
	var queued_target: String

	func _init(target_machine: StateMachine, target: String = "") -> void:
		machine = target_machine
		queued_target = target

	func enter() -> void:
		if not queued_target.is_empty():
			machine.transition_to(queued_target)


var _rejections: Array[Dictionary] = []


func _ready() -> void:
	var failures: Array[String] = []
	var machine := StateMachine.new()
	machine.owner_node = self
	machine.transition_rejected.connect(_on_transition_rejected)
	add_child(machine)

	machine.register("a", QueueingState.new(machine, "b"))
	machine.register("b", QueueingState.new(machine, "c"))
	machine.register("c", QueueingState.new(machine))
	machine.configure_transition_map({
		"a": ["b"],
		"b": ["c"],
		"c": [],
	})

	if not machine.start("a"):
		failures.append("cannot start registered state")
	if machine.current_state_name != "c" or machine.previous_state_name != "b":
		failures.append("reentrant enter transitions were not safely queued to c")
	if machine.transition_count != 3:
		failures.append("transition count is incorrect after queued start transitions")
	machine.physics_update(0.25)
	if not is_equal_approx(machine.state_elapsed, 0.25):
		failures.append("state elapsed time is not tracked")

	if machine.transition_to("a"):
		failures.append("terminal state c accepted an illegal transition")
	if _rejections.is_empty() or _rejections.back().get("reason") != "transition_not_allowed":
		failures.append("illegal transition did not emit an auditable rejection")

	var snapshot := machine.get_snapshot()
	if snapshot.get("current") != "c" or not bool(snapshot.get("rules_enabled", false)):
		failures.append("state snapshot is incomplete")
	machine.stop()
	if machine.is_running() or machine.previous_state_name != "c":
		failures.append("machine stop did not preserve previous state")

	if failures.is_empty():
		print("STATE_MACHINE_SAFETY_OK: whitelist, rejection audit, reentrant queue, snapshot, terminal guard")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _on_transition_rejected(from_state: String, to_state: String, reason: String) -> void:
	_rejections.append({"from": from_state, "to": to_state, "reason": reason})
