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
	var vertical_target_count := 0
	var vertical_access_count := 0
	var sloped_corridor_count := 0
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
		for record in snapshot.get("records", []):
			if int(record.get("vertical_level", 0)) != 0:
				vertical_target_count += 1
			if str(record.get("type", "")) in ["STAIRS_DOWN", "STAIRS_UP", "ELEVATOR"]:
				vertical_access_count += 1
		for corridor in (dungeon.get("_corridor_by_edge") as Dictionary).values():
			if corridor is Node3D and absf((corridor as Node3D).rotation.x) > 0.01:
				sloped_corridor_count += 1
		var sizes: Dictionary = snapshot.get("size_counts", {})
		for size_id in ["small", "medium", "large", "arena"]:
			if int(sizes.get(size_id, 0)) <= 0:
				failures.append("Room size class %s missing in %s" % [size_id, definition["id"]])
		var room_nodes := dungeon.get_tree().get_nodes_in_group("dungeon_room_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if room_nodes.size() != int(snapshot.get("room_count", -1)):
			failures.append("Generated room records/nodes disagree in %s" % definition["id"])
		var runtime := dungeon.get_runtime_snapshot()
		if int(runtime.get("detailed_rooms", 0)) != 1 or int(runtime.get("active_rooms", 0)) != 1 or int(runtime.get("built_shells", 0)) != 1:
			failures.append("Room streaming must start with current room only: %s" % definition["id"])
		var lights := dungeon.get_tree().get_nodes_in_group("wasteland_light_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if lights.size() != 1:
			failures.append("Initial streamed light budget invalid in %s: %d" % [definition["id"], lights.size()])
		else:
			var light_snapshot := (lights[0] as WastelandLight3D).get_snapshot()
			if str(light_snapshot.get("fixture_style", "")) != "ceiling" or bool(light_snapshot.get("has_light_pool", true)):
				failures.append("Room still uses a streetlight/light-pool instead of one central ceiling fixture")
			if float(light_snapshot.get("energy", 0.0)) < 4.8 or float(light_snapshot.get("range", 0.0)) < 13.5:
				failures.append("Central ceiling light is outside the balanced room-light envelope")
			if bool(light_snapshot.get("light_enabled", true)):
				failures.append("Room ceiling light must start switched off")
		var switches := dungeon.get_tree().get_nodes_in_group("room_light_switch_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if switches.size() != 1:
			failures.append("Initial room has no single wall switch: %s" % definition["id"])
		elif not (switches[0] as RoomLightSwitch3D).toggle_light():
			failures.append("Room wall switch cannot toggle the central real light")
		elif not bool((lights[0] as WastelandLight3D).get_snapshot().get("illumination_active", false)):
			failures.append("Wall switch did not enable central room illumination")
		if index == 0:
			var starter_pickups := dungeon.get_tree().get_nodes_in_group("ground_loot_3d").filter(
				func(node):
					return dungeon.is_ancestor_of(node) and str((node as GroundLootPickup3D).item_data.get("id", "")) == "weapon_shotgun"
			)
			if starter_pickups.size() != 1:
				failures.append("Start room does not expose one visible alternate weapon pickup")
			else:
				var starter := starter_pickups[0] as GroundLootPickup3D
				var starter_model := starter.get_model_snapshot()
				if str(starter_model.get("model_kind", "")) != "weapon" or int(starter_model.get("mesh_count", 0)) <= 0:
					failures.append("Starter shotgun pickup does not use the shared visible 3D weapon model")
				dungeon.call("_on_ground_loot_requested", starter, starter.item_data)
				if dungeon.get_inventory_module().get_item_count("weapon_shotgun") != 1:
					failures.append("Starter shotgun cannot enter the real 12-slot inventory")
				else:
					var starter_slot := _find_inventory_slot(dungeon.get_inventory_module(), "weapon_shotgun")
					var inventory_ui := dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
					var slots: Array = inventory_ui.get("_slots") if inventory_ui != null else []
					if starter_slot < 0 or starter_slot >= slots.size() or not slots[starter_slot] is ItemSlot:
						failures.append("Starter shotgun has no actual clickable inventory slot")
					else:
						(slots[starter_slot] as ItemSlot).slot_clicked.emit(starter_slot)
						await get_tree().process_frame
						if str(dungeon.player.get_weapon_snapshot().get("gun_id", "")) != "bp_shotgun":
							failures.append("Picked-up starter shotgun cannot be equipped through the real UI signal path")
		var search_record: Dictionary = {}
		for record in snapshot["records"]:
			if str(record["type"]) in ["SCAVENGE", "STORAGE"]:
				search_record = record
				break
		if not search_record.is_empty():
			dungeon.force_open_edge_for_test(str(search_record["parent"]), str(search_record["id"]))
			dungeon.force_enter_room_for_test(str(search_record["id"]))
			await get_tree().process_frame
		var searchable := dungeon.get_tree().get_nodes_in_group("searchable_prop_3d").filter(func(node): return dungeon.is_ancestor_of(node))
		if searchable.is_empty():
			failures.append("No searchable 3D furniture generated in %s" % definition["id"])
		if index == 0:
			first_signature = snapshot["records"].duplicate(true)
			var combat_id := ""
			for record in snapshot["records"]:
				if str(record["type"]) in ["COMBAT", "ELITE", "BOSS", "TRAP"]:
					combat_id = str(record["id"])
					break
			dungeon.force_enter_room_for_test(combat_id)
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
	if vertical_target_count <= 0 or vertical_access_count <= 0 or sloped_corridor_count <= 0:
		failures.append("Vertical basement/upper-room access and physical sloped corridor parity are missing")

	await _verify_enemy_ecosystem(failures)
	await _verify_weapon_matrix(failures)
	# 该用例会组合四主题和概率垂直支路；1300用于吸收合法支路数量波动
	# 以及正式角色表现挂点。硬预算仍由专项分账。
	# 正式硬预算继续由 verify_3d_performance_budget 分账阻断，不能在此替代。
	if node_peak > 1300:
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


func _find_inventory_slot(inventory: InventoryModule, item_id: String) -> int:
	for slot in inventory.get_occupied_slots():
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(slot.get("slot", -1))
	return -1


func _verify_enemy_ecosystem(failures: Array[String]) -> void:
	var scene := load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn") as PackedScene
	var behavior_roles: Dictionary = {}
	for kind in ENEMY_KINDS:
		var enemy := scene.instantiate() as Enemy3D
		enemy.enemy_kind = kind
		enemy.position = Vector3(100, 0, 100)
		add_child(enemy)
		await get_tree().process_frame
		var snapshot := enemy.get_state_snapshot()
		if snapshot["enemy_kind"] != kind or snapshot["valid_states"].size() < 9:
			failures.append("Enemy state contract invalid: %s" % kind)
		if int(snapshot["component_snapshot"].get("component_count", 0)) != 4:
			failures.append("Enemy modular avatar invalid: %s" % kind)
		var behavior_role := str(snapshot.get("behavior_role", ""))
		if behavior_role.is_empty() or behavior_roles.has(behavior_role):
			failures.append("Enemy type has no distinct 3D action role: %s" % kind)
		behavior_roles[behavior_role] = true
		var before := enemy.current_hp
		enemy.take_damage(7, false, Vector3.RIGHT)
		if enemy.current_hp >= before:
			failures.append("Enemy cannot receive 3D projectile damage: %s" % kind)
		var collision_profile := snapshot.get("collision_profile", {}) as Dictionary
		var visual_profile := snapshot["component_snapshot"].get("footprint", {}) as Dictionary
		if absf(float(collision_profile.get("radius", 0.0)) - float(visual_profile.get("radius", -1.0))) > 0.01:
			failures.append("Enemy hit radius does not match modular model footprint: %s" % kind)
		if absf(float(collision_profile.get("height", 0.0)) - float(visual_profile.get("height", -1.0))) > 0.01:
			failures.append("Enemy hit height does not match modular model footprint: %s" % kind)
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
	if not test_player.equip_weapon("bp_launcher", "mod_bullet_standard") or "explosive" not in test_player.get_weapon_snapshot().get("bullet_tags", []):
		failures.append("Launcher gun-body behavior does not make standard ammunition explosive")
	if not test_player.equip_weapon("bp_charge", "mod_bullet_standard"):
		failures.append("Charge gun cannot be equipped")
	else:
		var before_ammo := int(test_player.get_weapon_snapshot().get("current_ammo", 0))
		test_player.weapon.try_fire(Vector3.FORWARD, test_player)
		test_player.weapon.call("_process", test_player.weapon.charge_time)
		if not test_player.weapon.release_charge():
			failures.append("Charge gun does not consume charge_time and release a shot")
		elif int(test_player.get_weapon_snapshot().get("current_ammo", 0)) != before_ammo - 1:
			failures.append("Charge gun release does not consume exactly one round")
	var orientation_probe := Projectile3D.new()
	orientation_probe.configure({
		"direction": Vector3.RIGHT, "speed": 0.0, "damage": 1, "hostile": false,
		"tags": [], "color": Color.WHITE, "shooter": test_player,
	})
	add_child(orientation_probe)
	await get_tree().process_frame
	var orientation := orientation_probe.get_orientation_snapshot()
	if float(orientation.get("alignment", 0.0)) < 0.999 or not bool(orientation.get("trail_is_behind", false)):
		failures.append("Projectile visual/trail orientation does not match travel direction")
	orientation_probe.queue_free()
	var avatar_snapshot := test_player.avatar.get_component_snapshot()
	if int(avatar_snapshot.get("visible_hand_count", 0)) != 2 or not bool(avatar_snapshot.get("has_weapon_socket", false)):
		failures.append("Player two-hand modular weapon contract regressed")
	var state_snapshot := test_player.get_state_machine_snapshot()
	var expected_states := [
		"dashing", "dead", "falling", "hurt", "idle", "landing", "locked", "moving",
	]
	if state_snapshot.get("states", []) != expected_states or not bool(state_snapshot.get("rules_enabled", false)):
		failures.append("Player eight-state whitelist contract regressed")
	test_player.queue_free()
	await get_tree().process_frame


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _finish(failures: Array[String], node_peak: int) -> void:
	if failures.is_empty():
		print("FULL_3D_GAME_FLOW_OK: four themes, seeded rooms including vertical levels, four sizes, streamed shells/lights/props, nine-state enemies, 56 weapon combinations, combat and extraction pass (peak_nodes=%d)" % node_peak)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
