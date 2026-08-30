extends Node

const ROOM_GRAPH_SCRIPT = preload("res://src/world3d/RoomGraphRuntime.gd")
const PERSISTENCE_SCRIPT = preload("res://src/world3d/RunPersistenceService.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var graph: RoomGraphRuntime = ROOM_GRAPH_SCRIPT.new()
	var records: Array[Dictionary] = [
		{"id": "a", "parent": ""},
		{"id": "b", "parent": "a"},
		{"id": "c", "parent": "b"},
	]
	graph.configure(
		records,
		{"a": ["b"], "b": ["a", "c"], "c": ["b"]},
		{"a|b": true, "b|c": false}
	)
	_expect(graph.resolve_stream_state("a", "a", 0, 1, 2) == 2, "Current room is not active", failures)
	_expect(graph.resolve_stream_state("b", "a", 0, 1, 2) == 1, "Open neighbor is not shell-ready", failures)
	_expect(graph.resolve_stream_state("c", "a", 0, 1, 2) == 0, "Non-neighbor did not remain data-only", failures)
	graph.commit_stream_state("a", 2, 0)
	var hibernate := graph.commit_stream_state("a", 0, 0)
	_expect(bool(hibernate.get("hibernate", false)), "Active-to-data transition did not request hibernation", failures)
	_expect(graph.edge_key("b", "a") == "a|b", "Edge key is not canonical", failures)

	var raw_snapshot := {
		"run_seed": 42,
		"current_room_id": "b",
		"current_floor_index": 7,
		"player_position": [1, 2.5, -3],
		"inventory_slots": [{"item": {"id": "item_health_potion"}, "count": 1}],
		"insurance_slots": [],
		"equipped_weapon_items": [],
		"edge_states": {"a|b": false, "removed|room": true},
		"world_state": PERSISTENCE_SCRIPT.build_world_state(
			"tower_world_state_v1", {"b": {"visited": true}}
		),
	}
	var snapshot: Dictionary = PERSISTENCE_SCRIPT.finalize_runtime_snapshot(raw_snapshot)
	_expect(PERSISTENCE_SCRIPT.supports_runtime_snapshot(snapshot), "Finalized runtime schema is unsupported", failures)
	_expect(snapshot.get("player_position", []) == [1.0, 2.5, -3.0], "Player position was not normalized", failures)
	var restored_segment: Dictionary = PERSISTENCE_SCRIPT.read_segment_runtime_state(snapshot)
	_expect(bool((restored_segment.get("b", {}) as Dictionary).get("visited", false)), "Segment state did not round-trip", failures)
	var merged_edges: Dictionary = PERSISTENCE_SCRIPT.merge_known_edge_states(
		{"a|b": true, "b|c": false}, snapshot.get("edge_states", {})
	)
	_expect(not bool(merged_edges.get("a|b", true)), "Known edge state was not restored", failures)
	_expect(not merged_edges.has("removed|room"), "Unknown historical edge leaked into current topology", failures)

	_finish(failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("ROOM_GRAPH_PERSISTENCE_SERVICES_OK: topology streaming and v2 snapshot compatibility pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
