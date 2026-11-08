class_name RoamingEliteRunDirector
extends RefCounted
## One run-owned journal. Enemy nodes are temporary views of this encounter.

var rules: Dictionary = {}
var state: Dictionary = {}


func configure(config: Dictionary, seed_value: int, run_id: String, room_budget: int) -> void:
	rules = config.duplicate(true)
	state.clear()
	if not bool(rules.get("enabled", false)) or str(rules.get("elite_id", "")).is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x41524d53
	var limit := mini(room_budget, rng.randi_range(3, 5))
	if limit <= 0:
		return
	state = {
		"schema_version": 1, "session_id": "%s:roaming:%s" % [run_id, rules.elite_id],
		"elite_id": rules.elite_id, "seed": seed_value, "room_budget": room_budget,
		"appearance_limit": limit, "appearances": 0, "visited_rooms": [],
		"next_visit": rng.randi_range(1, mini(5, room_budget - limit + 1)),
		"status": "waiting", "room_id": "", "max_hp": 0, "hp": 0, "damage_taken": 0,
	}


func observe_room(room_id: String) -> void:
	if state.is_empty() or room_id in state.visited_rooms:
		return
	(state.visited_rooms as Array).append(room_id)
	if state.status == "waiting" and state.visited_rooms.size() >= int(state.next_visit):
		state.status = "pending"
		state.room_id = room_id


func pending_in(room_id: String) -> bool:
	return not state.is_empty() and state.status == "pending" and state.room_id == room_id


func owns(config: Dictionary) -> bool:
	return not state.is_empty() and config.get("roaming_elite_session_id", "") == state.session_id


func keeps_actor(config: Dictionary) -> bool:
	return not owns(config) or state.status == "active"


func bind_actor(enemy: Enemy3D) -> void:
	if not owns(enemy.enemy_data):
		return
	if int(state.max_hp) == 0:
		state.max_hp = enemy.max_hp
		state.hp = enemy.current_hp
	else:
		enemy.max_hp = int(state.max_hp)
		enemy.current_hp = int(state.hp)
	enemy._elite_encounter_damage_taken = int(state.damage_taken)
	if state.status == "pending":
		state.appearances = int(state.appearances) + 1
		state.status = "active"
		state.damage_taken = 0
		enemy._elite_encounter_damage_taken = 0
	enemy.health_changed.emit(enemy, enemy.current_hp, enemy.max_hp)


func capture_actor(enemy: Enemy3D) -> void:
	if owns(enemy.enemy_data) and state.status == "active":
		state.hp = enemy.current_hp
		state.max_hp = enemy.max_hp
		state.damage_taken = enemy._elite_encounter_damage_taken


func stage_escape(enemy: Enemy3D) -> void:
	capture_actor(enemy)
	state.room_id = ""
	if int(state.appearances) >= int(state.appearance_limit):
		state.status = "finished"
		return
	state.status = "waiting"
	var first: int = state.visited_rooms.size() + 1
	var remaining := int(state.appearance_limit) - int(state.appearances)
	var last := maxi(first, int(state.room_budget) - remaining + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.seed) ^ (int(state.appearances) * 104729)
	state.next_visit = rng.randi_range(first, last)


func stage_death(enemy: Enemy3D) -> void:
	capture_actor(enemy)
	state.hp = 0
	state.status = "killed"


func stage_defeat(enemy: Enemy3D) -> void:
	capture_actor(enemy)
	if str(state.get("room_id", "")).is_empty():
		state.room_id = enemy.room_id
	state.hp = 0
	state.status = "defeated"


func export_snapshot() -> Dictionary:
	return state.duplicate(true)


func import_snapshot(saved: Dictionary) -> bool:
	if state.is_empty() or saved.is_empty():
		return false
	if saved.get("session_id", "") != state.session_id or int(saved.get("schema_version", 0)) != 1:
		return false
	if saved.get("status", "") not in ["waiting", "pending", "active", "finished", "killed", "defeated"]:
		return false
	if not saved.get("visited_rooms", null) is Array:
		return false
	for key in ["seed", "room_budget", "appearance_limit", "appearances", "next_visit", "max_hp", "hp", "damage_taken"]:
		if typeof(saved.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			return false
	var limit := int(saved.appearance_limit)
	if limit < 1 or limit > 5 or int(saved.appearances) < 0 or int(saved.appearances) > limit:
		return false
	if int(saved.seed) != int(state.seed) or int(saved.room_budget) != int(state.room_budget) or int(saved.next_visit) < 1 or int(saved.damage_taken) < 0:
		return false
	var visited: Array = []
	for room_id in saved.visited_rooms:
		if not room_id is String or room_id.is_empty() or room_id in visited:
			return false
		visited.append(room_id)
	if saved.status in ["active", "pending", "defeated"] and str(saved.get("room_id", "")).is_empty():
		return false
	if int(saved.get("max_hp", 0)) < 0 or int(saved.get("hp", 0)) < 0 or int(saved.get("hp", 0)) > int(saved.get("max_hp", 0)):
		return false
	state = saved.duplicate(true)
	return true
