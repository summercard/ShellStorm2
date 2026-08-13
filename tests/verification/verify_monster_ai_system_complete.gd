extends Node3D
## AI 完整契约：统一记忆、房间/楼层目标合法性、有限告警、攻击令牌、
## 30怪错峰/空间注册，以及 Boss 技能袋确定性。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	GameplaySpatialRegistry3D.clear_runtime_records()
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)

	await _verify_memory_legality_and_alert(player, failures)
	await _verify_target_hysteresis(player, failures)
	await _verify_attack_tokens(player, failures)
	await _verify_thirty_enemy_registry(failures)
	await _verify_boss_skill_bag(failures)

	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		var manager := MonsterAIManager.get_manager_snapshot()
		print("MONSTER_AI_SYSTEM_COMPLETE_OK: memory/legality/hysteresis/alert/tokens/30-enemy registry/boss bag pass snapshot=%s" % manager)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_target_hysteresis(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3(0, 0, -12.5)
	var enemy := _make_enemy("melee_chaser", Vector3.ZERO, "hysteresis", 0)
	enemy.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2, -5)
	lamp.omni_range = 20.0
	lamp.light_energy = 5.0
	lamp.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	lamp.set_meta("gameplay_light_kind", "omni")
	add_child(lamp)
	GameplaySpatialRegistry3D.register_node(lamp, GameplaySpatialRegistry3D.KIND_LOCAL_LIGHT)
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	var first := MonsterAIManager.force_refresh_enemy(enemy)
	var challenger := PLAYER_SCENE.instantiate() as Player3D
	challenger.start_with_weapon = false
	challenger.position = Vector3(0.4, 0, -11.8)
	add_child(challenger)
	await get_tree().process_frame
	challenger.set_physics_process(false)
	var held := MonsterAIManager.force_refresh_enemy(enemy)
	challenger.position = Vector3(0.2, 0, -1.0)
	var switched := MonsterAIManager.force_refresh_enemy(enemy)
	if (
		int(first.get("target_instance_id", 0)) != player.get_instance_id()
		or int(held.get("target_instance_id", 0)) != player.get_instance_id()
		or str(held.get("reason_code", "")) != "target_lock_hysteresis"
		or int(switched.get("target_instance_id", 0)) != challenger.get_instance_id()
	):
		failures.append("15%% target-switch hysteresis is not stable: %s / %s / %s" % [first, held, switched])
	for node in [enemy, lamp, challenger]:
		node.queue_free()
	await get_tree().process_frame
	player.position = Vector3.ZERO


func _verify_memory_legality_and_alert(player: Player3D, failures: Array[String]) -> void:
	var source := _make_enemy("melee_chaser", Vector3(0, 0, -6), "room_a", 0)
	var ally := _make_enemy("shielded", Vector3(3, 0, -5), "room_a", 1)
	var other_room := _make_enemy("melee_chaser", Vector3(4, 0, -5), "room_b", 2)
	await get_tree().physics_frame
	source.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)
	var visual := MonsterAIManager.force_refresh_enemy(source)
	var ally_decision := MonsterAIManager.force_refresh_enemy(ally)
	var other_decision := MonsterAIManager.force_refresh_enemy(other_room)
	var source_snapshot := MonsterAIManager.get_enemy_snapshot(source)
	if (
		str(visual.get("reason_code", "")) != "highest_threat_visible"
		or float(visual.get("threat_score", 0.0)) <= 0.0
		or (source_snapshot.get("memory", []) as Array).is_empty()
	):
		failures.append("Visual decision lacks threat reason code or unified stimulus memory: %s" % visual)
	if str(ally_decision.get("awareness", "")) != "ally_alert" or int(ally_decision.get("target_instance_id", -1)) != 0:
		failures.append("Limited ally alert did not share only a position: %s" % ally_decision)
	if str(other_decision.get("awareness", "")) == "ally_alert":
		failures.append("Ally alert crossed the room boundary")

	source.notify_attacked_by(player)
	var damage := MonsterAIManager.force_refresh_enemy(source)
	if str(damage.get("reason_code", "")) != "damage_target_locked":
		failures.append("Damage aggro did not take deterministic priority: %s" % damage)
	player.position.y = 9.0
	var illegal := MonsterAIManager.force_refresh_enemy(source)
	if int(illegal.get("target_instance_id", 0)) != 0 or str(illegal.get("awareness", "")) in ["damage_contact", "visual_contact"]:
		failures.append("Cross-floor player remained a legal combat target: %s" % illegal)
	player.position = Vector3.ZERO
	for enemy in [source, ally, other_room]:
		enemy.queue_free()
	await get_tree().process_frame


func _verify_attack_tokens(player: Player3D, failures: Array[String]) -> void:
	var enemies: Array[Enemy3D] = []
	for index in range(6):
		enemies.append(_make_enemy("melee_chaser", Vector3(20 + index, 0, 20), "tokens", index))
	await get_tree().process_frame
	var melee_granted := 0
	var ranged_granted := 0
	for index in range(3):
		melee_granted += 1 if MonsterAIManager.request_attack_token(enemies[index], player, "melee") else 0
		ranged_granted += 1 if MonsterAIManager.request_attack_token(enemies[index + 3], player, "ranged") else 0
	if melee_granted != 2 or ranged_granted != 2:
		failures.append("Attack token budget is not exactly 2 melee + 2 ranged: %d/%d" % [melee_granted, ranged_granted])
	MonsterAIManager.release_attack_token(enemies[0])
	if not MonsterAIManager.request_attack_token(enemies[2], player, "melee"):
		failures.append("Released melee token was not reusable")
	for enemy in enemies:
		enemy.queue_free()
	await get_tree().process_frame


func _verify_thirty_enemy_registry(failures: Array[String]) -> void:
	var enemies: Array[Enemy3D] = []
	for index in range(30):
		var enemy := _make_enemy(
			"ranged_caster" if index % 3 == 0 else "melee_chaser",
			Vector3(80 + float(index % 6) * 2.0, 0, 80 + float(index / 6) * 2.0),
			"stress_room",
			index
		)
		if enemy.visible:
			failures.append("A newly registered far enemy was visible before the vision query admitted it")
		enemy.set_runtime_active(false, true)
		enemies.append(enemy)
	await get_tree().process_frame
	var before := MonsterAIManager.get_manager_snapshot()
	var registry := before.get("spatial_registry", {}) as Dictionary
	if int((registry.get("by_room", {}) as Dictionary).get("stress_room", 0)) != 30:
		failures.append("Spatial registry does not hold exactly 30 stress enemies: %s" % registry)
	for enemy in enemies:
		MonsterAIManager.evaluate_enemy(enemy)
	for enemy in enemies:
		MonsterAIManager.evaluate_enemy(enemy)
	var after := MonsterAIManager.get_manager_snapshot()
	if int(after.get("cache_hit_count", 0)) <= int(before.get("cache_hit_count", 0)):
		failures.append("110ms AI update budget did not serve cached decisions")
	for enemy in enemies:
		enemy.queue_free()
	await get_tree().process_frame
	GameplaySpatialRegistry3D.prune_stale()
	var final_registry := GameplaySpatialRegistry3D.get_snapshot()
	if int((final_registry.get("by_room", {}) as Dictionary).get("stress_room", 0)) != 0:
		failures.append("Freed stress enemies remained in the spatial registry: %s" % final_registry)


func _verify_boss_skill_bag(failures: Array[String]) -> void:
	var boss := _make_enemy("boss", Vector3(140, 0, 140), "boss_room", 0)
	boss.configure_from_enemy_data({"enemy_type": "boss", "floor": 5, "spawn_index": 0})
	boss.boss_phase = 2
	var sequence: Array[String] = []
	for _index in range(4):
		sequence.append(str(boss.call("_next_boss_skill")))
	for index in range(1, sequence.size()):
		if sequence[index] == sequence[index - 1] and sequence[index] in ["burst", "summon"]:
			failures.append("Boss skill bag repeated a high-pressure skill: %s" % sequence)
	boss.queue_free()
	await get_tree().process_frame


func _make_enemy(kind: String, world_position: Vector3, room_id: String, spawn_index: int) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	enemy.room_id = room_id
	enemy.enemy_data = {"spawn_index": spawn_index, "floor": 1}
	enemy.position = world_position
	add_child(enemy)
	return enemy
