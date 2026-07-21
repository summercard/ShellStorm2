extends Node

const THEMES := [
	{"scene": "res://scenes/levels3d/IronFrontier3D.tscn", "id": "iron_frontier"},
	{"scene": "res://scenes/levels3d/RustFoundry3D.tscn", "id": "rust_foundry"},
	{"scene": "res://scenes/levels3d/SporeDepths3D.tscn", "id": "spore_depths"},
	{"scene": "res://scenes/levels3d/AbyssArchive3D.tscn", "id": "abyss_archive"},
]
const ENEMY_KINDS := ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher", "boss"]


func _ready() -> void:
	var failures: Array[String] = []
	var node_peak := 0
	var first_signature: Array[Dictionary] = []
	for index in range(THEMES.size()):
		var definition: Dictionary = THEMES[index]
		var scene := load(definition["scene"]) as PackedScene
		if scene == null:
			failures.append("3D level scene does not load: %s" % definition["scene"])
			continue
		var dungeon := scene.instantiate() as Dungeon3D
		if dungeon == null:
			failures.append("3D level root has no Dungeon3D contract: %s" % definition["id"])
			continue
		dungeon.test_mode = true
		dungeon.run_seed_override = 4242
		add_child(dungeon)
		await get_tree().process_frame
		await get_tree().physics_frame
		var snapshot := dungeon.get_generation_snapshot()
		if snapshot.get("theme_id", "") != definition["id"] or snapshot.get("visual_theme_id", "") != definition["id"]:
			failures.append("Gameplay/visual theme identity mismatch: %s" % definition["id"])
		if not bool(snapshot.get("is_3d", false)) or not bool(snapshot.get("has_extraction", false)):
			failures.append("3D/extraction contract missing: %s" % definition["id"])
		if int(snapshot.get("room_count", 0)) < 10:
			failures.append("3D random layout is too small: %s" % definition["id"])
		var branches: Array = snapshot.get("branch_types", [])
		for required in snapshot.get("required_branch_types", []):
			if not branches.has(required):
				failures.append("Required branch %s missing in %s" % [required, definition["id"]])
		var sizes: Dictionary = snapshot.get("size_counts", {})
		for size_id in ["small", "medium", "large"]:
			if int(sizes.get(size_id, 0)) <= 0:
				failures.append("Room size class %s missing in %s" % [size_id, definition["id"]])
		var room_nodes := dungeon.get_tree().get_nodes_in_group("dungeon_room_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if room_nodes.size() != int(snapshot.get("room_count", -1)):
			failures.append("Generated room records/nodes disagree in %s" % definition["id"])
		var lights := dungeon.get_tree().get_nodes_in_group("wasteland_light_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if lights.size() < room_nodes.size() * 2:
			failures.append("Wasteland fixture coverage is too sparse in %s" % definition["id"])
		elif not bool((lights[0] as WastelandLight3D).get_snapshot().get("has_light_pool", false)):
			failures.append("Wasteland light does not include its ground pool")
		var searchable := dungeon.get_tree().get_nodes_in_group("searchable_prop_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if searchable.is_empty():
			failures.append("No searchable 3D furniture generated in %s" % definition["id"])
		if index == 0:
			first_signature = snapshot["records"].duplicate(true)
			dungeon.force_enter_room_for_test("main_01")
			await get_tree().process_frame
			var enemies := dungeon.get_tree().get_nodes_in_group("enemy_3d").filter(func(node): return dungeon.is_ancestor_of(node))
			if enemies.is_empty():
				failures.append("Entering a combat room does not spawn 3D enemies")
			dungeon.force_extract_for_test()
			await get_tree().process_frame
			if not bool(dungeon.get("_completed")):
				failures.append("Unlocked 3D extraction does not complete the run")
		node_peak = maxi(node_peak, _count_nodes(dungeon))
		dungeon.queue_free()
		await get_tree().process_frame

	# 同种子必须完全复现；不同种子必须改变支线拓扑。
	var repeat_signature := await _layout_signature(4242)
	if repeat_signature != first_signature:
		failures.append("Same seed does not reproduce the same 3D layout")
	var varied_signature := await _layout_signature(8888)
	if _topology_only(varied_signature) == _topology_only(first_signature):
		failures.append("Different seeds do not vary 3D branch topology")

	await _verify_enemy_ecosystem(failures)
	await _verify_weapon_matrix(failures)
	if node_peak > 3600:
		failures.append("3D level exceeds prototype node budget: %d" % node_peak)
	_finish(failures, node_peak)


func _layout_signature(seed: int) -> Array[Dictionary]:
	var scene := load(THEMES[0]["scene"]) as PackedScene
	var dungeon := scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = seed
	add_child(dungeon)
	await get_tree().process_frame
	var signature: Array[Dictionary] = dungeon.get_generation_snapshot()["records"].duplicate(true)
	dungeon.queue_free()
	await get_tree().process_frame
	return signature


func _topology_only(records: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for record in records:
		if not bool(record["main"]):
			result.append("%s:%s:%s" % [record["type"], record["parent"], record["position"]])
	return result


func _verify_enemy_ecosystem(failures: Array[String]) -> void:
	var scene := load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn") as PackedScene
	for kind in ENEMY_KINDS:
		var enemy := scene.instantiate() as Enemy3D
		enemy.enemy_kind = kind
		enemy.position = Vector3(100, 0, 100)
		add_child(enemy)
		await get_tree().process_frame
		var snapshot := enemy.get_state_snapshot()
		if snapshot["enemy_kind"] != kind or snapshot["valid_states"].size() != 7:
			failures.append("Enemy state contract invalid: %s" % kind)
		if int(snapshot["component_snapshot"].get("component_count", 0)) != 4:
			failures.append("Enemy modular avatar invalid: %s" % kind)
		var before := enemy.current_hp
		enemy.take_damage(7, false, Vector3.FORWARD)
		if enemy.current_hp >= before:
			failures.append("Enemy cannot receive 3D projectile damage: %s" % kind)
		enemy.queue_free()
		await get_tree().process_frame


func _verify_weapon_matrix(failures: Array[String]) -> void:
	var player_scene := load("res://scenes/Player3D.tscn") as PackedScene
	var test_player := player_scene.instantiate() as Player3D
	test_player.start_with_weapon = false
	test_player.position = Vector3(120, 0, 120)
	add_child(test_player)
	await get_tree().process_frame
	var guns := BlueprintRegistry.get_available_gunbodies(99)
	var bullets := BlueprintRegistry.get_available_bullets(99)
	var combinations := 0
	for gun in guns:
		for bullet in bullets:
			if test_player.equip_weapon(str(gun["item_id"]), str(bullet["item_id"])):
				var snapshot := test_player.get_weapon_snapshot()
				if bool(snapshot.get("has_model", false)) and int(snapshot.get("magazine_size", 0)) > 0:
					combinations += 1
	if combinations != guns.size() * bullets.size():
		failures.append("3D weapon model does not cover all gun/ammo combinations (%d/%d)" % [combinations, guns.size() * bullets.size()])
	var avatar_snapshot := test_player.avatar.get_component_snapshot()
	if int(avatar_snapshot.get("visible_hand_count", 0)) != 1 or not bool(avatar_snapshot.get("has_weapon_socket", false)):
		failures.append("Player one-hand modular weapon contract regressed")
	test_player.queue_free()
	await get_tree().process_frame


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _finish(failures: Array[String], node_peak: int) -> void:
	if failures.is_empty():
		print("FULL_3D_GAME_FLOW_OK: four themes, seeded rooms, three sizes, lighting, props, seven enemies, 56 weapon combinations, combat and extraction pass (peak_nodes=%d)" % node_peak)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
