extends Node

const MAP := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const FIGHT := preload("res://src/world3d/PlatformSentinelEncounter3D.gd")
var failed := 0
var checks := 0
var tower: TowerDescent3D
var room: DungeonRoom3D
var fight: PlatformSentinelEncounter3D

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
	print("PLATFORM_CHECK ", "PASS" if value else "FAIL", " ", label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	BaseManager.replace_narrative_history_for_test({"nar_main_032_monitor_audience": {"completed_count": 1}})
	await _load_expedition()
	if fight == null:
		_finish()
		return
	var deck := fight.deck
	check(deck.tiles.size() == 25 and deck.grapples.size() == 4 and deck.sentries.size() == 16, "formal room instantiates 25 floor tiles, four grapples, sixteen sentries")
	check(deck.red_black and deck.tiles.all(func(tile: Node3D) -> bool: return tile.has_meta("screen")), "red-black room grade and 25 display materials")
	var roles := {}
	for value in deck.get_node("PlatformSentinel").find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface)
			if material != null:
				roles[material.get_rid()] = material.resource_name
	check(roles.size() == 5 and roles.values().has("05_平台拼接显示屏"), "all 120 components share four canonical materials and one display resource")
	print("PLATFORM_MATERIAL_ROLES ", roles.values())
	check(deck._collapse.size() == 25, "Blender baked collapse has 25 bone tracks")
	var center := _floor(Vector3.ZERO)
	var outer := _floor(Vector3(10, 0, 10))
	var inner := _floor(Vector3(0, 0, -5))
	var foot := _floor(Vector3(0, 0.75, 15))
	check(center and outer and inner and foot, "continuous floor and stair support before activation")
	check(_floor(Vector3(-13.0, 0, 0)) and _floor(Vector3(13.0, 0, 0)), "both side bridges connect before combat")
	var arm := deck.grapples[0]
	deck.play(arm, "attack_grapple_slam", 0.0, 0.0)
	var windup := fight._palm_world(0)
	deck.play(arm, "attack_grapple_slam", 0.0, FIGHT.IMPACT)
	var contact := fight.to_local(fight._palm_world(0))
	check(windup.distance_to(fight._palm_world(0)) > 1.3 and absf(contact.y) < 0.45 and absf(contact.z) < 12.5, "imported palm moves and lands on the platform")
	print("PLATFORM_POSE ", fight.to_local(windup), " -> ", contact)
	deck.play(arm, "activate_grapple", 0.0)
	var rack := deck.sentries[0]
	deck.play(rack, "attack_sentry", 0.0, FIGHT.AUTHORED_FIRE)
	var muzzle := deck.socket(rack, "muzzle_exit")
	check(muzzle != null and absf(fight.to_local(muzzle.global_position).y - 1.3) < 0.15, "imported sentry socket is 1.3 m above deck")
	if muzzle != null:
		print("PLATFORM_MUZZLE ", fight.to_local(muzzle.global_position))
	deck.play(rack, "activate_sentry", 0.0)

	var monitor := tower.get_main_story_boss() as Enemy3D
	check(monitor != null, "first challenge legally spawns a Monitor002")
	if monitor == null:
		_finish()
		return
	monitor.set_story_activation_hold(false)
	monitor._commit_death()
	await get_tree().process_frame
	check(fight.stage == FIGHT.Stage.TAKEOVER, "Monitor death requests cinematic")
	check(not room.cleared and not tower.is_room_boss_defeated(room.room_id), "first victory does not award or clear room")
	check(not room.get_persistent_detail_state("treasure_chests").has("drop_boss"), "no boss chest before phase 2 victory")
	check(await _wait_stage(FIGHT.Stage.DEPLOY, 30.0), "narrative plays and emits deploy")
	check(BaseManager.has_narrative_completed(FIGHT.TAKEOVER), "takeover history committed")
	check(await _wait_stage(FIGHT.Stage.COMBAT, 4.0), "sentries finish deployment and combat starts")
	await get_tree().physics_frame
	check(not _floor(Vector3(0, 0.75, 15)) and _floor(Vector3(0, 4, 29)), "only lower staircase segments fall")
	check(not _floor(Vector3(-13.0, 0, 0)) and not _floor(Vector3(13.0, 0, 0)), "both bridges shift their support away from the deck")
	check(_floor(Vector3(-18.0, 0, 0)) and _floor(Vector3(18.0, 0, 0)), "moving bridges retain their displaced solid surfaces")
	check(tower._boss_panel != null and tower._boss_panel.visible and "武装平台" in tower._boss_label.text, "existing boss HUD uses phase-two health")
	check(tower._boss_bar.get_parent().get_node("PlatformArmSegments").get_child_count() == 4, "HUD shows four distinct brace segments")
	await _verify_attack_rules()
	for relay in fight._arm_targets:
		relay.take_damage(FIGHT.ARM_HP)
	check(fight.stage == FIGHT.Stage.COLLAPSE, "independent arm losses start collapse")
	for i in range(30):
		await get_tree().physics_frame
	check(_floor(Vector3(10, 0, 10)), "warning interval keeps outer support")
	check(fight._active_arm < 0 and fight._active_gun < 0 and fight._route_markers.size() == 12, "collapse stops attacks and outlines the standing route")
	var shaken := deck.tiles[0]
	var at_rest: Transform3D = shaken.get_meta("rest")
	fight._clock = PlatformSentinelDeck3D.OUTER_START - 0.65
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not shaken.transform.is_equal_approx(at_rest) and _floor(Vector3(10, 0, 10)), "tile visibly shudders before its support breaks")
	await _capture("retreat_route")
	fight._clock = PlatformSentinelDeck3D.OUTER_START + 3.4
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not _floor(Vector3(10, 0, 10)) and _floor(Vector3(0, 0, -5)), "outer floor ceases to collide while inner ring is intact")
	fight._clock = PlatformSentinelDeck3D.FINISH
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(fight.stage == FIGHT.Stage.CORE and not _floor(Vector3(0, 0, -5)) and _floor(Vector3.ZERO), "inner floor disappears and center remains")
	check(not room.cleared and not fight._core.has_method("take_damage"), "isolated core has no damageable phase")
	fight.restore_state({"schema": 1, "stage": FIGHT.Stage.CORE, "arm_hp": [0, 0, 0, 0], "core_hp": 3600}, false)
	check(fight.stage == FIGHT.Stage.CORE and fight._core.visible and _floor(Vector3.ZERO), "legacy core checkpoint opens the shutdown on surviving support")
	tower.player.global_position = fight.to_global(Vector3(0, 0.08, 0.8))
	tower.player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	check(tower.player.request_interaction_for_test(), "shutdown can start through the usual interaction key")
	tower.player.global_position = fight.to_global(Vector3(2.32, 0.08, 2.32))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not fight.get_interaction_progress().active and not room.cleared, "walking away cancels the shutdown")
	tower.player.global_position = fight.to_global(Vector3(0, 0.08, 0.8))
	tower.player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	check(tower.player.request_interaction_for_test(), "standard interaction starts the ammo-free shutdown")
	check(await _wait_stage(FIGHT.Stage.WON, 2.0), "shutdown completes and bridge powers up")
	await get_tree().process_frame
	await get_tree().physics_frame
	check(room.cleared and tower.is_room_boss_defeated(room.room_id), "phase two resolves through formal boss and room flags")
	check(_floor(Vector3(6.0, 0, 0)) and _floor(Vector3(13.0, 0, 0)) and not _floor(Vector3(-13.0, 0, 0)), "shutdown connects the center to the east bridge while west stays open to the shaft")
	check(room.get_persistent_detail_state("treasure_chests").has("drop_boss"), "formal reward chest appears after final victory")
	for chest in room.get_treasure_chests():
		if chest.chest_id == "drop_boss":
			var safe := fight.to_local(chest.global_position)
			check(absf(safe.x) < 2.4 and absf(safe.z) < 2.4, "reward is physically reachable on the surviving tile")
			var claim := tower._story_chest_claim(room, chest)
			check(bool(claim.get("success", false)) and not bool(claim.get("duplicate", false)), "formal chest transaction grants the first rare-earth key")
			if not bool(claim.get("success", false)):
				print("PLATFORM_KEY ", claim)
			else:
				var expected: Array = tower._new_main_story_extraction_state()["local_position"]
				var beacon := fight.to_local(room.to_global(Vector3(expected[0], expected[1], expected[2])))
				check(beacon.distance_to(Vector3(1.1, 0.10, -1.35)) < 0.05 and _floor(beacon), "return beacon request is over remaining support")
				var after_commit: Callable = claim.get("after_commit", Callable())
				if after_commit.is_valid():
					after_commit.call()
			break
	var saved := fight.export_state()
	check(int(saved.stage) == FIGHT.Stage.WON and int(saved.schema) == 2 and not saved.has("core_hp"), "runtime checkpoint describes final stage without obsolete core health")
	var history := BaseManager.get_narrative_history(FIGHT.TAKEOVER)
	tower.queue_free()
	await get_tree().process_frame
	await _load_expedition()
	if fight != null:
		check(tower.get_main_story_boss() == null, "new run after completed takeover does not spawn monitor")
		check(await _wait_stage(FIGHT.Stage.COMBAT, 5.0), "new run starts phase two from deck without dialogue")
		check(BaseManager.get_narrative_history(FIGHT.TAKEOVER) == history, "rematch does not write the story a second time")
		if fight.stage == FIGHT.Stage.COMBAT:
			await _verify_fall()
	_finish()

func _load_expedition() -> void:
	tower = MAP.instantiate()
	tower.test_mode = true
	tower.force_main_story_for_test = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	room = tower.get_main_story_room("boss") as DungeonRoom3D
	if room == null:
		check(false, "formal boss room exists")
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	fight = tower._bind_platform_sentinel(room)
	check(fight != null, "formal assembly owns the encounter")
	if fight != null:
		tower.player.global_position = fight.to_global(Vector3(0.1, 0.08, 2.0))
		tower._on_room_entered(room)
	await get_tree().physics_frame
	await get_tree().physics_frame

func _verify_attack_rules() -> void:
	fight.set_physics_process(false)
	var rider := tower.player
	rider.global_position = fight.to_global(Vector3(0.1, 0.08, 0.2))
	rider.velocity = Vector3.ZERO
	await get_tree().physics_frame
	fight._clock = 2.0
	fight._tick_combat(0.0, fight.to_local(rider.global_position))
	check(fight._active_arm < 0 and fight._active_gun >= 0, "central target gets a real gun warning instead of an out-of-range slam")
	if fight._active_gun >= 0:
		var index := fight._active_gun
		var original: Array[Vector3] = fight._barrage_lanes[index].duplicate()
		var rack := fight.deck.sentries[index]
		var side := fight._side_of(index)
		var port := fight._ports[side]
		check(absf(fight.to_local(original[0]).y - 1.30) < 0.15 and is_equal_approx(original[0].y, original[1].y), "locked burst launches at 1.3 m from the real muzzle")
		check(fight._shot_lane(rack)[0].distance_to(original[0]) < 0.05, "muzzle matches the frozen warning")
		check(port.get_aim_assist_points().size() == 1, "active gun side exposes its feed port")
		port.take_damage(1)
		check(fight._barrage == FIGHT.Barrage.NONE and fight._rounds.is_empty(), "feed hit cancels the pending barrage")
		check(fight._port_ready[side] >= 14.0 and fight._gun_ready[side] >= 7.0, "local suppression and rearm cooldown start")
		var fallback := fight._start_gun()
		check(fallback and fight._side_of(fight._active_gun) != side, "another valid side can take over")
		if fallback:
			var locked: Array[Vector3] = fight._barrage_lanes[fight._active_gun].duplicate()
			var hp := rider.current_hp
			await _capture("gun_warning")
			fight._tick_gun(0.91)
			check(fight._rounds.size() == 1 and rider.current_hp == hp, "first shot spawns a projectile without instant damage")
			if not fight._rounds.is_empty():
				var first := fight._rounds[0]
				check(is_equal_approx(first.speed, FIGHT.BULLET_SPEED) and first.direction.dot(locked[0].direction_to(locked[1])) > 0.999, "first projectile has slow speed and matches the warned line")
				var initial := first.global_position
				for i in range(18):
					await get_tree().physics_frame
				check(first.visible and first.global_position.distance_to(initial) > 1.0 and rider.current_hp == hp, "visible projectile travels for multiple frames before reaching the player")
			fight._tick_gun(0.80)
			check(fight._shot_index == 3 and fight._rounds.size() == 3, "first three shots spawn separately along the fixed axis")
			fight._tick_gun(0.55)
			var pellets := fight._rounds.filter(func(round: Projectile3D) -> bool: return is_equal_approx(round.speed, FIGHT.PELLET_SPEED))
			check(fight._shot_index == 4 and pellets.size() == 5, "fourth shot creates a five-pellet fan")
			for i in range(144):
				await get_tree().physics_frame
			check(rider.current_hp < hp, "slow projectiles reach the native player damage path after flight")
			fight._finish_gun(true)
			fight._cancel_rounds()
	await _verify_barrage_patterns()
	for ref in fight._arm_slots:
		check(ref.size() == 2, "each grapple has inward and outward choices")
	var local: Vector3 = fight._arm_slots[0][1].point
	rider.global_position = fight.to_global(Vector3(local.x, 0.08, local.z - 1.2))
	rider.velocity = Vector3.ZERO
	await get_tree().physics_frame
	check(fight._start_slam(), "eligible grapple starts its actual inward strike")
	if fight._active_arm >= 0:
		var selected := fight._active_arm
		var target := fight._arm_targets[selected]
		var contact := fight._slam_point
		check(absf(fight._slam_angle) > 0.1, "inward pose uses the shoulder axis")
		await _capture("palm_warning")
		fight._tick_slam(FIGHT.IMPACT, fight.to_local(rider.global_position))
		var actual := fight._palm_world(selected)
		check((actual - contact).slide(Vector3.UP).length() < 0.065 and absf(fight.to_local(actual).y) < 0.10, "palm lands on the indicated circle")
		check(target.get_melee_hit_points().size() == 2 and target.get_shape_owners().size() == 2, "arm relay and exposed wrist share a single damage body")
		var was := fight._next_attack_at
		check(was >= fight._clock + 1.19, "recovery reserves 1.2 seconds of response time")
		fight._tick_slam(FIGHT.SLAM_RESPONSE - 0.01, fight.to_local(rider.global_position))
		var points := target.get_melee_hit_points()
		check(points.size() == 2 and absf(fight.to_local(points[1]).y - 0.82) < 0.45, "wrist stays reachable throughout the response window")
		fight._tick_slam(0.08, fight.to_local(rider.global_position))
		check(target.get_melee_hit_points().size() == 1, "wrist closes when the arm lifts")
		fight._finish_slam(true)
		check(target.get_melee_hit_points().size() == 1, "wrist closes at recovery end")
	rider.global_position = fight.to_global(Vector3(0.1, 0.08, 0.8))
	rider.velocity = Vector3.ZERO
	fight.set_physics_process(true)
	await get_tree().physics_frame


func _verify_barrage_patterns() -> void:
	fight._clock = 24.0
	for port in fight._ports:
		port.current_hp = 1
	check(fight._start_pattern(FIGHT.Barrage.CROSS), "cross pattern selects two opposite gun banks")
	if fight._barrage == FIGHT.Barrage.CROSS:
		check(fight._barrage_lanes.size() == 8 and fight._gun_markers.size() == 4, "first cross bank warns before firing")
		fight._tick_gun(1.06)
		check(fight._rounds.size() == 12 and fight._gun_markers.size() == 4, "cross launches 12 pellets and previews the next bank")
		fight._cancel_rounds()
		fight._tick_gun(1.50)
		check(fight._rounds.size() == 12 and fight._cross_at == 24.0 + FIGHT.CROSS_COOLDOWN, "second cross bank follows after 1.5s with a skill cooldown")
		fight._finish_gun(true)
		fight._cancel_rounds()
	check(fight._start_pattern(FIGHT.Barrage.VOLLEY), "volley prepares all four sides")
	if fight._barrage == FIGHT.Barrage.VOLLEY:
		check(fight._barrage_lanes.size() == 16 and fight._gun_markers.size() == 16, "sixteen racks participate in the volley")
		for elapsed in [1.11, 1.50, 1.50]:
			fight._tick_gun(elapsed)
			check(fight._rounds.size() == 80, "volley emits five pellets from each of 16 racks per pulse")
			if fight._shot_index == 1:
				for i in range(28):
					await get_tree().physics_frame
				check(fight._rounds.size() >= 72, "most volley pellets clear the mount and enter the deck")
				await _capture("volley_wave")
			fight._cancel_rounds()
		check(fight._shot_index == 3 and fight._volley_at == 24.0 + FIGHT.VOLLEY_COOLDOWN, "three volleys run at 1.5s intervals with independent cooldown")
		fight._finish_gun(true)


func _capture(label: String) -> void:
	var folder := OS.get_environment("PLATFORM_TUNING_PREVIEWS")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	print("PLATFORM_CAPTURE ", label, " ", image.save_png(folder.path_join(label + ".png")))


func _verify_fall() -> void:
	var rider := tower.player
	rider.global_position = fight.to_global(Vector3(9.7, 0.08, 9.8))
	rider.velocity = Vector3.ZERO
	for i in range(10):
		await get_tree().physics_frame
	check(rider.is_on_floor(), "player is supported before the tile drops")
	for relay in fight._arm_targets:
		relay.take_damage(FIGHT.ARM_HP)
	fight._clock = PlatformSentinelDeck3D.OUTER_START + 3.4
	var lowest := 0.0
	for i in range(100):
		await get_tree().physics_frame
		if not is_instance_valid(rider):
			break
		lowest = minf(lowest, fight.to_local(rider.global_position).y)
		if rider.current_hp <= 0:
			break
	check(lowest < -3.0, "real player falls after tile support disappears")
	check(is_instance_valid(rider) and rider.current_hp <= 0, "fall into shaft triggers the normal death path")


func _floor(local: Vector3) -> bool:
	var from := fight.to_global(local + Vector3.UP * 0.7)
	var to := fight.to_global(local - Vector3.UP * 0.7)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [tower.player.get_rid()])
	return not fight.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _wait_stage(stage: int, seconds: float) -> bool:
	for i in range(roundi(seconds * 60.0)):
		if fight.stage == stage:
			return true
		await get_tree().physics_frame
	return false

func _finish() -> void:
	print("PLATFORM_RESULT ", checks, " checks / ", failed, " failures")
	get_tree().quit(0 if failed == 0 else 1)
