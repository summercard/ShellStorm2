extends Node

const MAP := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const MAP_99 := preload("res://scenes/ExpeditionLevel99_3D.tscn")
@export var test_99 := false
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
	test_99 = test_99 or "--boss-99" in OS.get_cmdline_user_args()
	var intro := "nar_main_032_monitor_audience"
	var seeded_history := {MainStoryChapter3D.BRIEFING_ID: {"completed_count": 1}}
	if test_99:
		seeded_history[intro] = {"completed_count": 1}
		seeded_history[FIGHT.TAKEOVER] = {"completed_count": 2}
	BaseManager.replace_narrative_history_for_test(seeded_history)
	var before_takeover := BaseManager.get_narrative_history(FIGHT.TAKEOVER)
	var before_intro := BaseManager.get_narrative_history(intro)
	var before_story := BaseManager.get_main_story_snapshot().duplicate(true)
	var path := TowerDescent3D.expedition_static_layout_path("expedition_01", "boss")
	check(path == TowerDescent3D.expedition_static_layout_path("99", "boss"), "01 and 99 resolve the exact same scene path")
	await _load_expedition()
	if fight == null:
		_finish()
		return
	check(str(room.get_meta("static_layout_scene_path", "")) == path and fight.get_parent().scene_file_path == path,
		"loaded formal layout is the shared scene, not a local override")
	check(fight.get_parent().find_children("PlatformSentinelEncounter", "", true, false).size() == 1,
		"shared scene instantiates exactly one encounter")
	check(room.boss_reinforcement_plan == TowerDescent3D.shared_database_boss_content()["boss_reinforcement_plan"],
		"running encounter shares the 01 reinforcement source")
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
	print("PLATFORM_MONITOR_HP level=%s current=%d max=%d" % [tower.get_expedition_level_id(), monitor.current_hp, monitor.max_hp])
	check(monitor.current_hp == 8000 and monitor.max_hp == 8000, "shared first-stage Monitor spawns at 8000/8000 HP")
	check(fight.arm_health() == [2200, 2200, 2200, 2200], "four platform arms retain 2200 HP each")
	check(deck._rails.size() == 17 and deck._rails.all(func(rail: Node3D) -> bool: return rail.visible), "first phase has its 17 rails")
	var north_wall := deck.get_node("../../BossRoom02/Components/外壳_后墙/CollisionBody") as StaticBody3D
	check(is_equal_approx(fight.to_local(north_wall.global_position).z, -47.5) and _wall_ray(Vector3(0, 12, -44), Vector3(0, 12, -51), north_wall), "moved north wall retains its own actual collision")
	check(_wall_ray(Vector3(38, 12, -30), Vector3(42, 12, -30)) and _wall_ray(Vector3(-38, 12, -30), Vector3(-42, 12, -30)), "both extension corners have side-wall collision")
	var gate := deck.get_node("../../BossRoom02/ArenaGate") as BossRoom02ArenaGate3D
	check(not gate.use_stair_camera_override, "room disables forced stair camera")
	for z: float in [-30, -35, -40, -45]:
		check(_wall_ray(Vector3(38, 12, z), Vector3(42, 12, z)) and _wall_ray(Vector3(-38, 12, z), Vector3(-42, 12, z)), "both wall returns at z=%s" % z)
	_verify_boss_camera("before")
	if "--hp-only" in OS.get_cmdline_user_args():
		_finish()
		return
	var screen := deck._rear_rest.keys()[0] as Node3D
	var screen_rest := screen.position
	check(await _rail_projectile(), "real projectile is stopped by phase-one rail")
	var intro_deadline := Time.get_ticks_msec() + 150000
	var intro_started := false
	while Time.get_ticks_msec() < intro_deadline:
		intro_started = intro_started or NarrativeDirector.active_id() == intro
		if intro_started and not NarrativeDirector.is_playing():
			break
		await get_tree().process_frame
	check(intro_started and bool(monitor.get_story_activation_snapshot().get("completed", false)),
		"shared 3.2 automatically starts and runs the real activation")
	check(not tower.player.input_locked and tower._boss_panel.visible and tower._boss_bar.max_value == 8000,
		"first fight starts unlocked with the shared HUD at 8000 max HP")
	check(not is_instance_valid(monitor._overhead_health_root) or not monitor._overhead_health_root.visible, "monitor does not show a world health bar")
	if test_99:
		check(BaseManager.get_narrative_history(intro) == before_intro, "99 intro leaves 01 history untouched")
	else:
		check(BaseManager.has_narrative_completed(intro), "01 intro writes its normal history")
	if "--floor-display" in OS.get_cmdline_user_args():
		await _verify_floor_display(monitor)
		_finish()
		return
	if "--rear-screens" in OS.get_cmdline_user_args():
		await _verify_rear_screens(monitor)
		_finish()
		return
	var shared_hud := tower._boss_panel
	monitor.take_damage(1000000)
	await get_tree().process_frame
	check(fight.stage == FIGHT.Stage.TAKEOVER, "Monitor death requests cinematic")
	check(is_instance_valid(fight._proxy) and fight._proxy.position.is_equal_approx(FIGHT.MONITOR_MARK), "death away from the north mark does not move the proxy spawn")
	check(not room.cleared and not tower.is_room_boss_defeated(room.room_id), "first victory does not award or clear room")
	check(not room.get_persistent_detail_state("treasure_chests").has("drop_boss"), "no boss chest before phase 2 victory")
	if not OS.get_environment("PLATFORM_TUNING_PREVIEWS").is_empty():
		await get_tree().create_timer(2.0).timeout
		await _capture("north_mark")
		await get_tree().create_timer(18.1).timeout
		await _capture("grapple_lift")
		await get_tree().create_timer(1.15).timeout
		await _capture("grapple_release")
		await get_tree().create_timer(2.0).timeout
		await _capture("platform_lifting_fixed")
	check(await _wait_stage(FIGHT.Stage.DEPLOY, 30.0), "narrative plays and emits deploy")
	if test_99:
		check(BaseManager.get_narrative_history(FIGHT.TAKEOVER) == before_takeover, "99 takeover leaves 01 history untouched")
	else:
		check(BaseManager.has_narrative_completed(FIGHT.TAKEOVER), "takeover history committed")
	check(await _wait_stage(FIGHT.Stage.COMBAT, 4.0), "sentries finish deployment and combat starts")
	await get_tree().physics_frame
	check(deck._rails.all(func(rail: Node3D) -> bool: return not rail.visible), "combat removes all rail visuals")
	check(screen.position.is_equal_approx(screen_rest + Vector3.FORWARD * 6.0), "three screen groups finish their authored retraction")
	check(not await _rail_projectile(), "same real projectile passes the rail lane in phase two")
	check(await _hit_arms_with_projectiles(), "four actual projectiles damage the four arms independently")
	_verify_boss_camera("combat")
	await _capture("combat_no_rails")
	check(not _floor(Vector3(0, 0.75, 15)) and _floor(Vector3(0, 4, 29)), "only lower staircase segments fall")
	check(not _floor(Vector3(-13.0, 0, 0)) and not _floor(Vector3(13.0, 0, 0)), "both bridges shift their support away from the deck")
	check(_floor(Vector3(-18.0, 0, 0)) and _floor(Vector3(18.0, 0, 0)), "moving bridges retain their displaced solid surfaces")
	check(tower._boss_panel != null and tower._boss_panel.visible and "武装平台" in tower._boss_label.text, "existing boss HUD uses phase-two health")
	check(tower._boss_panel == shared_hud and tower._boss_bar.max_value == 8800 and not tower.player.input_locked, "stage two reuses the HUD and returns player control")
	check(tower._boss_bar.get_parent().get_node("PlatformArmSegments").get_child_count() == 4, "HUD shows four distinct brace segments")
	await _verify_attack_rules()
	for arm_target in fight._arm_targets:
		arm_target.take_damage(FIGHT.ARM_HP)
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
	var retained := 0
	for tile in deck.tiles:
		var origin: Vector3 = (tile.get_meta("rest") as Transform3D).origin
		if maxf(absf(origin.x), absf(origin.z)) <= 5.0 and tile.visible and _floor(origin):
			retained += 1
	check(fight.stage == FIGHT.Stage.CORE and retained == 9, "all nine inner tiles stay visible and physically supported")
	await _capture("inner_nine")
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
	var chest := room.find_chest_by_id("drop_boss")
	if chest != null:
		var safe := fight.to_local(chest.global_position)
		check(safe.length() < 0.1 and _floor(safe), "reward chest is fixed at the supported platform center")
		tower.player.global_position = fight.to_global(Vector3(0, 0.08, 0.9))
		tower.player.velocity = Vector3.ZERO
		for frame in range(4):
			await get_tree().physics_frame
		await get_tree().create_timer(TreasureChest3D.CHEST_SPOTLIGHT_APPEAR_DURATION_S + 0.2).timeout
		print("CHEST_PROBE locked=", tower.player.input_locked, " in_range=", chest._player_in_range, " chest=", chest.global_position, " player=", tower.player.global_position)
		check(tower.player.request_interaction_for_test(), "player uses normal chest interaction")
		await get_tree().process_frame
		check(chest.is_opened(), "reward chest actually opens")
		await _capture("center_chest_open")
		if test_99:
			check(BaseManager.get_main_story_snapshot() == before_story, "99 chest leaves formal key unchanged")
		else:
			check(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), MainStoryChapter3D.KEY_RARE_EARTH) == "acquired", "01 chest grants the actual rare-earth key")
			var deadline := Time.get_ticks_msec() + 30000
			while not is_instance_valid(tower._main_story_safe_beacon) and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			check(is_instance_valid(tower._main_story_safe_beacon), "01 call unlocks the real safe-return beacon")
			if is_instance_valid(tower._main_story_safe_beacon):
				var beacon := tower._main_story_safe_beacon
				await get_tree().create_timer(0.85).timeout
				tower.player.global_position = beacon.global_position
				tower.player.velocity = Vector3.ZERO
				for frame in range(4):
					await get_tree().physics_frame
				check(tower.player.request_interaction_for_test(), "01 uses the real safe-return interaction")
				deadline = Time.get_ticks_msec() + 40000
				while not tower._completed and Time.get_ticks_msec() < deadline:
					await get_tree().process_frame
				check(tower._completed, "01 completes the safe-return countdown and run settlement")
	if not tower._completed:
		_verify_boss_camera("after")
	var saved := fight.export_state()
	check(int(saved.stage) == FIGHT.Stage.WON and int(saved.schema) == 2 and not saved.has("core_hp"), "runtime checkpoint describes final stage without obsolete core health")
	if test_99:
		var exit_edge := tower._edge_key("boss", "extraction")
		check(tower.try_open_room_door("extraction"), "99 cleared boss unlocks the real extraction door")
		var door_deadline := Time.get_ticks_msec() + 5000
		while not tower._open_edges.get(exit_edge, false) and Time.get_ticks_msec() < door_deadline:
			await get_tree().process_frame
		check(bool(tower._open_edges.get(exit_edge, false)), "99 exit edge actually opens")
		var extraction := tower.get_main_story_room("extraction") as DungeonRoom3D
		check(extraction != null and tower.has_expedition_extraction(), "99 retains the standard extraction room")
		if extraction != null and tower.has_expedition_extraction():
			var beacon := tower._extraction as ExtractionBeacon3D
			check(beacon.get_parent() == extraction and not beacon.locked, "99 standard beacon is available after shutdown")
			var finished := [false]
			beacon.extraction_completed.connect(func() -> void: finished[0] = true, CONNECT_ONE_SHOT)
			tower.player.global_position = beacon.global_position + Vector3.UP * 0.12
			tower.player.hold_post_settlement_invulnerability() # Isolate countdown from 99’s existing defense waves.
			tower._on_room_entered(extraction)
			tower.player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			check(beacon.force_start_for_test(), "standard extraction countdown can start")
			var deadline := Time.get_ticks_msec() + 120000
			while not finished[0] and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			print("PLATFORM_EXTRACTION ", finished[0], " completed=", tower._completed, " active=", beacon._active if is_instance_valid(beacon) else false, " hp=", tower.player.current_hp)
			check(finished[0] and tower._completed, "standard 99 extraction countdown settles the run")
		_finish()
		return
	if "--single-pass" in OS.get_cmdline_user_args():
		_finish()
		return
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
	tower = (MAP_99 if test_99 else MAP).instantiate()
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
		tower.player.global_position = fight.to_global(Vector3(0.0, 12.08, 64.0) if not fight._returning_visit else Vector3(0.1, 0.08, 2.0))
		tower._on_room_entered(room)
	await get_tree().physics_frame
	await get_tree().physics_frame

func _verify_attack_rules() -> void:
	fight.set_physics_process(false)
	fight._finish_standby()
	var saved_clock := fight._clock
	var saved_attack := fight._next_attack_at
	fight._standby_rng.seed = 179
	var variants := {"arm": {}, "rack": {}}
	for sample in range(20):
		fight._clock += 5.0
		fight._tick_standby()
		var arm_anim := fight._standby_arm.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var rack_anim := fight._standby_rack.find_child("AnimationPlayer", true, false) as AnimationPlayer
		variants.arm[arm_anim.current_animation] = true
		variants.rack[rack_anim.current_animation] = true
	check(variants.arm.size() == 2 and variants.rack.size() == 2 and fight._next_attack_at == saved_attack,
		"both authored standby variants per family leave attack timing untouched")
	fight._clock = saved_clock
	fight._next_standby_at = 0.0
	fight._standby_end = 0.0
	var rider := tower.player
	rider.global_position = fight.to_global(Vector3(0.1, 0.08, 0.2))
	rider.velocity = Vector3.ZERO
	await get_tree().physics_frame
	fight._clock = 2.0
	fight._tick_combat(0.0, fight.to_local(rider.global_position))
	check(fight._active_arm < 0 and fight._active_gun >= 0, "central target gets a gun burst instead of an out-of-range slam")
	check(fight._standby_arm == null and fight._standby_rack == null, "gun attack interrupts both standby clips")
	if fight._active_gun >= 0:
		var index := fight._active_gun
		var original: Array[Vector3] = fight._barrage_lanes[index].duplicate()
		var rack := fight.deck.sentries[index]
		check(absf(fight.to_local(original[0]).y - 1.30) < 0.15 and is_equal_approx(original[0].y, original[1].y), "locked burst launches at 1.3 m from the real muzzle")
		check(fight._shot_lane(rack)[0].distance_to(original[0]) < 0.05, "muzzle matches the locked firing lane")
		check(fight.find_children("GunFeed_*", "", true, false).is_empty(), "gun feeds are no longer targets")
		if fight._barrage != FIGHT.Barrage.NONE:
			var locked: Array[Vector3] = fight._barrage_lanes[fight._active_gun].duplicate()
			var hp := rider.current_hp
			check(_gun_strip_count() == 0 and fight._rounds.is_empty(), "burst charges without long strip or early projectile")
			await _capture("gun_charge_no_strips")
			fight._tick_gun(0.91)
			check(fight._rounds.size() == 1 and rider.current_hp == hp, "first shot spawns a projectile without instant damage")
			if not fight._rounds.is_empty():
				var first := fight._rounds[0]
				check(is_equal_approx(first.speed, FIGHT.BULLET_SPEED) and first.direction.dot(locked[0].direction_to(locked[1])) > 0.999, "first projectile has slow speed and matches the locked firing line")
				var initial := first.global_position
				for i in range(18):
					await get_tree().physics_frame
				check(first.visible and first.global_position.distance_to(initial) > 1.0 and rider.current_hp == hp, "visible projectile travels for multiple frames before reaching the player")
			fight._tick_gun(0.80)
			check(fight._shot_index == 3 and fight._rounds.size() == 3, "first three shots spawn separately along the fixed axis")
			fight._tick_gun(0.55)
			var pellets := fight._rounds.filter(func(round: Projectile3D) -> bool: return is_equal_approx(round.speed, FIGHT.PELLET_SPEED))
			check(fight._shot_index == 4 and pellets.size() == 5 and _gun_strip_count() == 0, "fourth shot creates a five-pellet fan without strips")
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
		target.sync_pose()
		check(target.get_melee_hit_points().size() == 4 and target.get_shape_owners().size() == 3, "three arm volumes share a single damage body")
		var was := fight._next_attack_at
		check(was >= fight._clock + 1.19, "recovery reserves 1.2 seconds of response time")
		fight._tick_slam(FIGHT.SLAM_RESPONSE - 0.01, fight.to_local(rider.global_position))
		target.sync_pose()
		var points := target.get_melee_hit_points()
		check(points.size() == 4 and (points[3] - actual).length() < 1.8, "wrist stays reachable throughout the response window")
		fight._tick_slam(0.08, fight.to_local(rider.global_position))
		target.sync_pose()
		check(target.get_melee_hit_points()[3].distance_to(points[3]) > 0.03, "wrist target follows the returning arm")
		fight._finish_slam(true)
		target.sync_pose()
		check(target.get_melee_hit_points().size() == 4, "arm remains targetable after recovery")
	rider.global_position = fight.to_global(Vector3(0.1, 0.08, 0.8))
	rider.velocity = Vector3.ZERO
	fight.set_physics_process(true)
	await get_tree().physics_frame


# The retired ground strips were direct children, with 0.63 m × 0.028 m cross-sections.
func _gun_strip_count() -> int:
	var count := 0
	for child in fight.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			var size: Vector3 = child.mesh.size
			if is_equal_approx(size.x, 0.63) and is_equal_approx(size.y, 0.028):
				count += 1
	return count


func _verify_barrage_patterns() -> void:
	fight._clock = 24.0
	check(fight._start_pattern(FIGHT.Barrage.CROSS), "cross pattern selects two opposite gun banks")
	if fight._barrage == FIGHT.Barrage.CROSS:
		check(fight._barrage_lanes.size() == 8 and _gun_strip_count() == 0, "first cross bank locks lanes without strips")
		fight._tick_gun(1.06)
		check(fight._rounds.size() == 12 and _gun_strip_count() == 0, "cross launches 12 pellets without next-bank strips")
		fight._cancel_rounds()
		fight._tick_gun(1.50)
		check(fight._rounds.size() == 12 and fight._cross_at == 24.0 + FIGHT.CROSS_COOLDOWN, "second cross bank follows after 1.5s with a skill cooldown")
		fight._finish_gun(true)
		fight._cancel_rounds()
	check(fight._start_pattern(FIGHT.Barrage.VOLLEY), "volley prepares all four sides")
	if fight._barrage == FIGHT.Barrage.VOLLEY:
		check(fight._barrage_lanes.size() == 16 and _gun_strip_count() == 0, "sixteen racks prepare without strips")
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


func _floor_feed() -> Vector2:
	var face := fight.deck.tiles[12].get_meta("screen") as MeshInstance3D
	var raw: Variant = face.get_instance_shader_parameter("deck_feed")
	return raw if raw is Vector2 else Vector2.ZERO


func _verify_floor_display(monitor: Enemy3D) -> void:
	var deck := fight.deck
	var shader_path := "res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/screen.gdshader"
	var faces := deck._feed_faces
	check(faces.size() == 25 and faces.all(func(face: MeshInstance3D) -> bool:
		var material := face.get_active_material(0) as ShaderMaterial
		if material == null or material.shader.resource_path != shader_path:
			return false
		var atlas := material.get_shader_parameter("screen_atlas") as Texture2D
		return atlas != null and atlas.resource_path == shader_path.get_base_dir() + "/screen_atlas.png"), "25 ground faces only use the existing display material")
	check(_floor_feed() == Vector2.ZERO and _rear_matches(PlatformSentinelDeck3D.SignalPicture.MONITOR), "floor stays unpowered while the rear screens run independently")
	monitor.take_damage(monitor.current_hp)
	await get_tree().process_frame
	check(await _wait_stage(FIGHT.Stage.COMBAT, 34.0), "real takeover and launch finish before the floor effect starts")
	if fight.stage != FIGHT.Stage.COMBAT:
		return
	tower.player.hold_post_settlement_invulnerability() # Isolate the display sample from live combat damage.
	tower.player.global_position = fight.to_global(Vector3(0.0, 0.08, 0.0))
	tower.player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.50).timeout
	_verify_boss_camera("floor_display")
	await _capture("feed_00_original_cyan")
	var palette := int(_floor_feed().x)
	var interference := 0.0
	var trips: Array[float] = []
	var cuts: Array[float] = []
	var palettes: Array[int] = [palette]
	var tears_seen := 0
	for tick in range(780):
		if not is_instance_valid(fight) or fight.stage != FIGHT.Stage.COMBAT:
			break
		await get_tree().physics_frame
		var sample := _floor_feed()
		if sample.y > 0.15 and interference <= 0.15:
			trips.append(fight._clock)
		if sample.y > 0.60 and interference <= 0.60:
			tears_seen += 1
			await _capture("feed_%02d_tear" % (tears_seen * 2 - 1))
		if int(sample.x) != palette:
			cuts.append(fight._clock)
			palette = int(sample.x)
			palettes.append(palette)
			await _capture("feed_%02d_palette_%d" % [cuts.size() * 2, palette])
		if cuts.size() == 3:
			break
		interference = sample.y
	print("FLOOR_TIMING palettes=", palettes, " tear_start=", trips, " cuts=", cuts)
	check(palettes == [0, 1, 2, 0] and trips.size() == 3 and cuts.size() == 3, "three successive tear-to-tint cycles at normal combat view")
	if cuts.size() == 3 and trips.size() == 3:
		check(absf(cuts[1] - cuts[0] - 3.6) < 0.05 and absf(cuts[2] - cuts[1] - 3.6) < 0.05, "measured consecutive tint interval is 3.6 seconds")
		check(range(3).all(func(i: int) -> bool: return cuts[i] - trips[i] > 0.12 and cuts[i] - trips[i] < 0.27), "tearing always starts before, never after, the tint change")
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.ONLINE) and faces.all(func(face: MeshInstance3D) -> bool:
		return (face.get_instance_shader_parameter("deck_feed") as Vector2).is_equal_approx(_floor_feed())), "three wall screens remain online and the 25 ground faces match one canvas")
	fight._arm_targets[0].take_damage(FIGHT.ARM_HP)
	fight._arm_targets[1].take_damage(FIGHT.ARM_HP)
	check(_floor_feed() == Vector2.ZERO and is_equal_approx(float(faces[12].get_instance_shader_parameter("phase")), 1.0), "real yellow arm-loss warning takes priority over decorative tint")
	await _capture("feed_07_true_warning")
	for i in [2, 3]:
		fight._arm_targets[i].take_damage(FIGHT.ARM_HP)
	check(fight.stage == FIGHT.Stage.COLLAPSE and _rear_matches(PlatformSentinelDeck3D.SignalPicture.OUTER_WARNING) and _floor_feed() == Vector2.ZERO, "collapse stops floor loop and keeps existing rear warning")
	await _capture("feed_08_collapse_warning")
	check(await _wait_stage(FIGHT.Stage.CORE, 10.0), "real collapse completes without advancing its clock in the fixture")
	check(_floor_feed() == Vector2.ZERO and _rear_matches(PlatformSentinelDeck3D.SignalPicture.SAFE) and _floor(Vector3.ZERO) and not _floor(Vector3(10, 0, 10)), "inner ground remains, outer collision is gone, and wall screens return to safe")
	await _capture("feed_09_after_collapse")


func _rear_parameters() -> Array[Vector4]:
	var result: Array[Vector4] = []
	for node in fight.deck._rear_displays:
		var mesh := node.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
		result.append(mesh.get_instance_shader_parameter("signal_picture") as Vector4)
	return result


func _rear_matches(expected: int) -> bool:
	var params := _rear_parameters()
	if params.size() != 3:
		return false
	for slot in range(3):
		if int(params[slot].x) != expected or int(params[slot].y) != slot:
			return false
	return true


func _sample_screen_frame_times(label: String) -> void:
	var values: Array[float] = []
	var start := Time.get_ticks_usec()
	for i in range(90):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		values.append(float(now - start) / 1000.0)
		start = now
	values.sort()
	print("REAR_SCREEN_FRAME ", label, " n=", values.size(), " p50_ms=", values[45], " p95_ms=", values[85])


func _verify_rear_screens(monitor: Enemy3D) -> void:
	var deck := fight.deck
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.MONITOR), "three existing screens use the shared signal material, with ordered slots")
	if deck._rear_displays.size() != 3:
		return
	monitor.take_damage(1000000)
	var center_led := false
	var elapsed := 0.0
	while elapsed < 0.28 and not center_led:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var pulse := _rear_parameters()
		center_led = pulse[1].z > 0.45 and pulse[2].z < 0.1
	check(center_led, "defeat pulse hits the main screen before the right screen")
	await _capture("fixed_defeat_pulse")
	await get_tree().create_timer(0.82).timeout
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.LINK_LOST) and _rear_parameters().all(func(v: Vector4) -> bool: return v.z < 0.01), "defeat settles to readable lost-link state")
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.LEGACY)
	await _capture("fixed_before")
	await _sample_screen_frame_times("fixed_legacy")
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.LINK_LOST)
	await _capture("fixed_after")
	await _sample_screen_frame_times("fixed_updated")
	while fight.stage == FIGHT.Stage.TAKEOVER and fight._deployment_started_at < 0.0 and fight._clock < 26.0:
		await get_tree().physics_frame
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.RISING), "mechanical launch cue updates the screens before fixed shot ends")
	await get_tree().create_timer(0.26).timeout
	await _capture("fixed_launch_pulse")
	check(await _wait_stage(FIGHT.Stage.COMBAT, 9.0), "ordinary camera and control are restored at combat")
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.ONLINE) and not tower.player.input_locked, "online panels do not own camera or input")
	# Look north from the real deck with the gameplay camera; no camera override.
	tower.player.global_position = fight.to_global(Vector3(0, 0.08, -8.7))
	tower.player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.48).timeout
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.LEGACY)
	await _capture("gameplay_before")
	await _sample_screen_frame_times("gameplay_legacy")
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.ONLINE)
	await _capture("gameplay_after")
	await _sample_screen_frame_times("gameplay_updated")
	for arm_target in fight._arm_targets:
		arm_target.take_damage(FIGHT.ARM_HP)
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.OUTER_WARNING), "collapse warning changes content but does not break signal before a tile drops")
	tower.player.global_position = fight.to_global(Vector3(0, 0.08, -6.7))
	tower.player.velocity = Vector3.ZERO
	for i in range(500):
		if fight._sent_racks or fight.stage != FIGHT.Stage.COLLAPSE:
			break
		await get_tree().physics_frame
	check(fight._sent_racks and _rear_matches(PlatformSentinelDeck3D.SignalPicture.OUTER_RELEASE), "actual outer tile release triggers the collapse signal pulse")
	await get_tree().create_timer(0.20).timeout
	await _capture("gameplay_collapse_pulse")
	check(await _wait_stage(FIGHT.Stage.CORE, 8.0), "original collapse reaches the shutdown beat")
	check(_rear_matches(PlatformSentinelDeck3D.SignalPicture.SAFE), "screen shows safe state after the disturbance")
	await _capture("gameplay_safe")


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
	for arm_target in fight._arm_targets:
		arm_target.take_damage(FIGHT.ARM_HP)
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


func _hit_arms_with_projectiles() -> bool:
	var ok := true
	for index in range(fight._arm_targets.size()):
		var target := fight._arm_targets[index]
		var before := fight.arm_health()
		var point := target.get_melee_hit_points()[1]
		var from := point + Vector3.UP * 2.4
		var shot := fight._projectiles.acquire({"shooter": tower.player, "direction": Vector3.DOWN,
			"speed": 20.0, "range": 4.0, "damage": 17, "projectile_collision_mask": 5}, from)
		for frame in range(12):
			await get_tree().physics_frame
		if shot._active:
			shot._retire()
		before[index] -= 17
		ok = ok and fight.arm_health() == before
	return ok


func _verify_boss_camera(stage_label: String) -> void:
	var base := tower._camera_default_local_position()
	var offsets := tower.player.get_camera_pose_offsets()
	print("BOSS_CAMERA ", stage_label, " level=", tower.get_expedition_level_id(), " baseline=", base, " offsets=", offsets)
	check(base.distance_to(Vector3(0, 12.514413, 6.214302)) < 0.01 and not tower.player.has_camera_pose_offset(),
		"ordinary 01 gameplay camera without low override: " + stage_label)


func _wall_ray(from: Vector3, to: Vector3, expected: StaticBody3D = null) -> bool:
	var query := PhysicsRayQueryParameters3D.create(fight.to_global(from), fight.to_global(to), 1)
	var space := fight.get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	for attempt in range(12):
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		if expected == null or hit.collider == expected:
			return true
		excluded.append(hit.rid)
	return false


func _rail_projectile() -> bool:
	var shot := fight._projectiles.acquire({"shooter": tower.player, "direction": fight.global_basis * Vector3.FORWARD,
		"speed": 20.0, "range": 12.0, "damage": 1, "projectile_collision_mask": 1},
		fight.to_global(Vector3(5.0, 0.65, -10.65)))
	for i in range(10):
		await get_tree().physics_frame
	var stopped := not shot._active
	if shot._active:
		shot._retire()
	return stopped


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
