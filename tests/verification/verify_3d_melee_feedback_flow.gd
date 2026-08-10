extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

var _hits: Array[Dictionary] = []


func _ready() -> void:
	var failures: Array[String] = []
	AudioManager.reset_feedback_debug()
	var pool := CombatEffectPool3D.new()
	add_child(pool)
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var locomotion_machine := player.get("_state_machine") as StateMachine
	locomotion_machine.stop()
	locomotion_machine.start("idle")
	player.aim_direction = Vector3.FORWARD
	player.combat_enabled = true
	player.melee_hit_resolved.connect(func(result: Dictionary): _hits.append(result.duplicate(true)))
	var item := ItemRegistry.get_instance().get_item("weapon_greatblade")
	if not bool(player.equip_weapon_item_to_slot(item, 0).get("success", false)):
		failures.append("Cannot equip greatblade for melee feedback verification")
	var enemy_left := _make_enemy(Vector3(-0.55, 0.0, -1.95))
	var enemy_right := _make_enemy(Vector3(0.55, 0.0, -1.95))
	await get_tree().physics_frame

	player.request_melee_attack()
	_tick_until_ready(player)
	var melee_snapshot := player.melee_combat.get_snapshot()
	var feedback := melee_snapshot.get("feedback", {}) as Dictionary
	var pool_snapshot := pool.get_snapshot()
	var acquired := pool_snapshot.get("acquire_counts", {}) as Dictionary
	var audio := AudioManager.get_feedback_debug_snapshot().get("request_counts", {}) as Dictionary
	if _hits.size() != 2:
		failures.append("One wide melee attack did not resolve exactly two target hits")
	if int(feedback.get("swing_count", 0)) != 1 or int(feedback.get("impact_target_count", 0)) != 2:
		failures.append("Melee feedback snapshot does not separate one swing from two target impacts")
	if int(acquired.get("slash", 0)) != 1 or int(acquired.get("melee_impact", 0)) != 2:
		failures.append("Parameterized combat VFX kit did not emit one slash and two impacts")
	if int(audio.get("melee_swing", 0)) != 1 or int(audio.get("melee_impact", 0)) != 1:
		failures.append("Multi-target melee audio is not layered as one swing plus one contact event")
	for event_name in ["melee_swing", "melee_impact"]:
		var path := str(AudioManager.SFX.get(event_name, ""))
		if path.is_empty() or not path.ends_with("_v001.ogg") or not FileAccess.file_exists(path):
			failures.append("Melee runtime audio event is missing its versioned OGG: %s" % event_name)
	if pool.find_children("*", "CollisionObject3D", true, false).size() != 0:
		failures.append("Melee feedback VFX introduced gameplay collision")
	if pool.find_children("*", "MeshInstance3D", true, false).size() < 10:
		failures.append("Melee feedback VFX does not build readable slash/impact geometry")

	enemy_left.queue_free()
	enemy_right.queue_free()
	await get_tree().process_frame
	player.request_melee_attack()
	_tick_until_ready(player)
	var miss_audio := AudioManager.get_feedback_debug_snapshot().get("request_counts", {}) as Dictionary
	if int(miss_audio.get("melee_swing", 0)) != 2 or int(miss_audio.get("melee_impact", 0)) != 1:
		failures.append("A missed swing does not keep air audio while suppressing contact audio")

	if failures.is_empty():
		print("3D_MELEE_FEEDBACK_FLOW_OK: pooled slash/impact VFX, multi-target audio dedupe, miss feedback, versioned OGG and collision isolation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _make_enemy(spawn_position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = "melee_chaser"
	enemy.position = spawn_position
	add_child(enemy)
	enemy.set_runtime_active(false, true)
	return enemy


func _tick_until_ready(player: Player3D) -> void:
	for _frame in range(180):
		player.melee_combat.physics_update(0.02)
		if str(player.melee_combat.get_snapshot().get("phase", "")) == "ready":
			return

