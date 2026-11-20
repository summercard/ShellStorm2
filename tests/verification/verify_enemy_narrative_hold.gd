extends Node3D

const TOWER := "res://scenes/TowerDescent3D.tscn"
const STORY := "nar_tower_opening_02_zombies"
const ROOM := "floor_01_main_02"
var tower: TowerDescent3D
var failures := 0
var checks := 0


func _ready() -> void:
	if OS.get_environment("SS2_ENEMY_NARRATIVE_ISOLATED") != "1":
		push_error("isolated APPDATA required")
		get_tree().quit(2)
		return
	print("ENEMY_NARRATIVE_USER_DIR ", OS.get_user_data_dir())
	await _run()
	if is_instance_valid(tower):
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("ENEMY_NARRATIVE_%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _run() -> void:
	BaseManager.replace_narrative_history_for_test({})
	tower = (load(TOWER) as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.force_new_game_opening_for_test = true
	tower.run_seed_override = 990098
	add_child(tower)
	await get_tree().process_frame
	NarrativeDirector.abort("prepare_room_probe")
	var room := tower._room_by_id.get(ROOM) as DungeonRoom3D
	_check(room != null and is_instance_valid(tower.player), "production tower, meeting room and player")
	if room == null or not is_instance_valid(tower.player):
		return
	var origin: Variant = NarrativeDirector.point_origin_for_test(STORY)
	_check(origin is Vector3, "catalogue resolves authored point")
	if not origin is Vector3:
		return
	# Place the player just outside the authored point; the production room entrance,
	# point polling, actual JSON, spawning, flashlight and director are not mocked.
	tower.player.global_position = (origin as Vector3) + Vector3(4.0, 0.05, 0.0)
	tower._on_room_entered(room)
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	flashlight.set_light_enabled(false)
	var spawner := MonsterInjector.new()
	spawner.set_level_rules({"strong_variant": {"chance": 1.0}})
	var parent_data := spawner.generate_box_enemy("exploder", 1, 1)
	_check(str(parent_data.get("enemy_type", "")) == "exploder_strong", "ordinary box entry upgrades through the common roll")
	var members: Array[Enemy3D] = []
	var center := room.global_position
	var pool := tower.get_node("ProjectilePool3D") as ProjectilePool3D
	var inputs: Array[Dictionary] = [parent_data, parent_data, parent_data, spawner.generate_box_enemy("fat_zombie03_strong", 1, 1), spawner.generate_box_enemy("ranged_caster_strong", 1, 1)]
	var positions: Array = [center + Vector3(1, 0.1, 0), center + Vector3(5, 0.1, -2), center + Vector3(-4, 0.1, 4), center + Vector3(4, 0.1, 5), center + Vector3(0, 0.1, 5)]
	_check(tower._spawn_enemy_batch(room, inputs, true, false, positions) == 5, "production spawn batch")
	for node in tower._enemy_nodes_by_room.get(ROOM, []):
		if node is Enemy3D and not node.has_meta("narrative_spawned"):
			members.append(node)
	if members.size() < 5:
		return
	var lethal := members[members.size() - 5]
	var active := members[members.size() - 4]
	var other := members[members.size() - 3]
	var fat := members[members.size() - 2]
	var ranged := members[members.size() - 1]
	var baseline_fat_data := spawner.generate_box_enemy("fat_zombie03", 1, 1)
	_check(lethal.max_hp == 504 and lethal.current_hp == 504 and lethal.avatar.has_formal_normal(), "exploder strong uses actual 504 HP and production model")
	_check(fat.max_hp == 2784 and fat.current_hp == 2784 and str(baseline_fat_data.get("enemy_type")) == "fat_zombie03_strong", "existing fat variant: 1392 to 2784 HP at same unoverridden profile")
	print("ENEMY_NARRATIVE_HP exploder_normal=126 exploder_strong=", lethal.max_hp, " fat_strong_baseline=1392 fat_strong=", fat.max_hp)
	var fragments_before := get_tree().get_nodes_in_group("hostile_projectile_3d").size()
	lethal.take_damage(lethal.max_hp + 1)
	lethal.take_damage(lethal.max_hp + 1)
	_check(get_tree().get_nodes_in_group("hostile_projectile_3d").size() == fragments_before + 8, "lethal strong preserves exactly eight death fragments")
	var split_nodes: Array[Enemy3D] = []
	for i in 4:
		await get_tree().process_frame
	for node in tower._enemy_nodes_by_room.get(ROOM, []):
		if node is Enemy3D and node.get_persistent_id().contains(":split_"):
			split_nodes.append(node)
	_check(split_nodes.size() == 3, "lethal strong creates exactly three room-owned actors")
	var child_floor := maxi(1, tower.visual_theme.difficulty_rank)
	var expected_child_hp := roundi(126.0 * float(tower._monster_injector.generate_split_child("exploder", child_floor, 1)["max_hp"]) / 10.0)
	for child in split_nodes:
		print("ENEMY_NARRATIVE_CHILD kind=", child.enemy_kind, " hp=", child.max_hp, " expected=", expected_child_hp, " active=", child.is_runtime_ai_active())
		_check(child.enemy_kind == "exploder" and child.max_hp == expected_child_hp and child.is_runtime_ai_active(), "ordinary child uses the same floor-adjusted HP, kind and active room AI")
	var counted := split_nodes.size()
	var active_fragments := get_tree().get_nodes_in_group("hostile_projectile_3d").size()
	active._explode()
	_check(active.ai_state == "dead" and active._active_explosion_committed and get_tree().get_nodes_in_group("hostile_projectile_3d").size() == active_fragments, "active explosion commits without death fragments")
	other._die()
	await get_tree().process_frame
	var final_children := 0
	for node in tower._enemy_nodes_by_room.get(ROOM, []):
		if node is Enemy3D and node.get_persistent_id().contains(":split_"):
			final_children += 1
	_check(final_children == counted, "active explosion and noncombat removal add zero children")
	var moving := split_nodes[0] if not split_nodes.is_empty() else fat
	moving.transition_to("chase")
	moving.velocity = Vector3(3, 0, 0)
	ranged.transition_to("telegraph")
	ranged._pending_volleys.append({"timer": 0.4})
	var bullet := pool.acquire({"hostile": true, "damage": 90, "speed": 1.0, "direction": Vector3.FORWARD}, center + Vector3(0, 1, 0))
	tower.player.global_position = (origin as Vector3) + Vector3.UP * .05
	for i in 150:
		if NarrativeDirector.active_id() == STORY:
			break
		await get_tree().physics_frame
	_check(NarrativeDirector.active_id() == STORY, "real position trigger starts authored meeting-room story")
	if NarrativeDirector.active_id() != STORY:
		return
	_check(NarrativeDirector.holds_enemy_combat() and ranged._pending_volleys.is_empty() and ranged.ai_state not in ["telegraph", "attack"], "takeover drops winding attack and queued volley")
	_check(not bullet._active, "already flying hostile projectile is retired at takeover")
	var held_position := moving.global_position
	var player_hp := tower.player.current_hp
	var spawned_in_story: Array[Enemy3D] = []
	for i in 30:
		await get_tree().physics_frame
	for node in tower._enemy_nodes_by_room.get(ROOM, []):
		if node is Enemy3D and node.has_meta("narrative_spawned"):
			spawned_in_story.append(node)
	_check(not spawned_in_story.is_empty(), "real scene.spawn cue creates new actors during hold")
	var new_positions: Array[Vector3] = []
	for enemy in spawned_in_story:
		new_positions.append(enemy.global_position)
	for i in 45:
		await get_tree().physics_frame
	_check(moving.global_position.distance_to(held_position) < .001 and tower.player.current_hp == player_hp, "existing mover held, no player damage")
	for i in spawned_in_story.size():
		_check(spawned_in_story[i].global_position.distance_to(new_positions[i]) < .001, "newly spawned actor held")
	for i in 900:
		if NarrativeDirector.is_waiting_for_flashlight():
			break
		await get_tree().physics_frame
	_check(NarrativeDirector.is_waiting_for_flashlight() and DialogueUI.is_active(), "real story reaches flashlight dialogue without stopping task progress")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.physical_keycode = KEY_F
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	for i in 20:
		await get_tree().physics_frame
	_check(flashlight.is_light_enabled() and not NarrativeDirector.holds_enemy_combat() and not NarrativeDirector.is_playing(), "physical F finishes flow.end and releases combat")
	print("ENEMY_NARRATIVE_REAL room=", ROOM, " born=", spawned_in_story.size(), " children=", final_children, " finish=", NarrativeDirector.dispatch_log().back())
	var moved := false
	for i in 240:
		await get_tree().physics_frame
		if is_instance_valid(moving) and moving.global_position.distance_to(held_position) > 0.1:
			moved = true
			break
	_check(moved, "normal AI moves again after the production exit")
	for reason in ["skip", "abort"]:
		_check(NarrativeDirector.play(STORY) and NarrativeDirector.holds_enemy_combat(), "real script reacquires for " + reason)
		get_tree().paused = true
		if reason == "skip":
			NarrativeDirector.skip()
		else:
			NarrativeDirector.abort("probe")
		_check(get_tree().paused and not NarrativeDirector.holds_enemy_combat(), reason + " releases only the narrative hold")
		get_tree().paused = false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
