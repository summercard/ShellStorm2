extends "res://tests/verification/support/SecondEliteStateFixture.gd"

func _ready() -> void:
	verify_confiscation()
	setup_ground()
	await get_tree().physics_frame
	verify_health_contract()
	await verify_action()
	await verify_interrupts()
	await verify_forced_motion()
	await verify_facing_and_escape()
	await verify_locomotion()
	await verify_death()
	# The live pistol publishes an AI sound stimulus. Run it after the movement
	# fixtures so the patrol sample has no combat stimulus.
	await verify_bullet_hit_volumes()
	clean_effects()
	await get_tree().process_frame
	finish("SECOND_ELITE_STATE_FLOW_OK")

func verify_bullet_hit_volumes() -> void:
	var enemy := make_enemy()
	present(enemy)
	var proxy := enemy.get_animated_hit_volume_body()
	var volumes := enemy.get_animated_hit_volumes()
	check(proxy != null and volumes.size() == 16, "Elite did not assemble its animated bullet volumes")
	if proxy == null or volumes.size() != 16:
		enemy.free()
		return
	check(enemy.collision_layer == 0 and enemy.collision_mask == 1, "Elite movement cylinder still intercepts bullets or lost its movement mask")
	check(proxy.collision_layer == Enemy3D.ENEMY_BULLET_LAYER and proxy.collision_mask == 0, "Bullet proxy can participate in movement")
	var gap := enemy.global_position + Vector3(0, 0.8, 0)
	var hp := enemy.current_hp
	var passed := await fire_at_elite(gap + Vector3.FORWARD * 2.0, Vector3.BACK)
	check(passed > gap.z + 1.1 and enemy.current_hp == hp, "A real bullet through the space between the legs did not clear the movement cylinder")
	var boot := proxy.get_node("Volume_L_Foot") as CollisionShape3D
	var outside := boot.global_position
	var foot_size := (boot.shape as BoxShape3D).size
	var foot_bounds := boot.global_transform * AABB(-foot_size * 0.5, foot_size)
	var side := signf(outside.x - enemy.global_position.x)
	outside.x = (foot_bounds.end.x if side > 0.0 else foot_bounds.position.x) + side * 0.18
	passed = await fire_at_elite(outside + Vector3.FORWARD * 2.0, Vector3.BACK)
	check(passed > outside.z + 1.1 and enemy.current_hp == hp, "A projectile outside the boot outline was stopped")
	for bone in ["L_Hand", "R_Hand", "L_Foot", "R_Foot", "Spine01", "Head"]:
		var volume := proxy.get_node_or_null("Volume_" + bone) as CollisionShape3D
		check(volume != null, "Missing bullet volume for %s" % bone)
		if volume == null:
			continue
		var center := volume.global_position
		var shot_found := false
		for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP]:
			var origin: Vector3 = center + direction * 2.0
			var ray := PhysicsRayQueryParameters3D.create(origin, center, 5)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.get("collider") != proxy or proxy.shape_owner_get_owner(proxy.shape_find_owner(hit.shape)) != volume:
				continue
			hp = enemy.current_hp
			await fire_at_elite(origin, -direction)
			check(enemy.current_hp == hp - 1, "A real bullet aimed at %s did not damage the elite exactly once" % bone)
			shot_found = true
			break
		check(shot_found, "No clear bullet path to %s" % bone)
	for bone in ["L_Foot", "R_Foot"]:
		var volume := proxy.get_node("Volume_" + bone) as CollisionShape3D
		var box := volume.shape as BoxShape3D
		var edge := volume.to_global(Vector3(0.0275, 0, box.size.z * 0.25))
		var hit_edge := false
		for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP]:
			var origin: Vector3 = edge + direction * 2.0
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, edge, 5))
			if hit.get("collider") != proxy or proxy.shape_owner_get_owner(proxy.shape_find_owner(hit.shape)) != volume:
				continue
			hp = enemy.current_hp
			await fire_at_elite(origin, -direction)
			check(enemy.current_hp == hp - 1, "Expanded %s boot edge let a real projectile through" % bone)
			hit_edge = true
			break
		check(hit_edge, "Expanded boot edge was not reachable: %s" % bone)
	await verify_player_pistol(enemy, proxy)
	enemy.configure_from_enemy_data({"enemy_type": "melee_chaser"})
	check(proxy.collision_layer == 0 and enemy.collision_layer == Enemy3D.ENEMY_BULLET_LAYER, "Reconfiguration left a stale proxy or failed to restore the ordinary enemy layer")
	enemy.free()
	clean_effects()
	await get_tree().process_frame


func verify_player_pistol(enemy: Enemy3D, proxy: EnemyHitVolume3D) -> void:
	var player := preload("res://scenes/Player3D.tscn").instantiate() as Player3D
	add_child(player)
	player.position = Vector3(0, enemy.position.y, -4.0)
	player.rotation.y = PI
	player.set_physics_process(false)
	var equipped := player.equip_weapon("bp_pistol", "mod_bullet_standard")
	check(equipped, "Could not equip the real player pistol for the hit volume test")
	if not equipped:
		player.free()
		return
	await get_tree().process_frame
	var muzzle := player.weapon._muzzle
	player.position.x += enemy.global_position.x - muzzle.global_position.x
	var hp := enemy.current_hp
	check(player.weapon.try_fire(Vector3.BACK, player), "Pistol did not fire toward the gap")
	await get_tree().create_timer(0.5).timeout
	check(enemy.current_hp == hp, "The player pistol damaged the elite through the gap")
	var calf := proxy.get_node("Volume_L_Calf") as CollisionShape3D
	player.position.x += calf.global_position.x - muzzle.global_position.x
	player.weapon._cooldown = 0.0
	check(player.weapon.try_fire(Vector3.BACK, player), "Pistol did not fire toward the calf")
	await get_tree().create_timer(0.5).timeout
	check(enemy.current_hp < hp, "The player pistol did not damage the calf at its normal muzzle height")
	player.free()


func fire_at_elite(origin: Vector3, direction: Vector3) -> float:
	var bullet := Projectile3D.new()
	bullet.configure({"direction": direction, "speed": 40.0, "damage": 1, "hostile": false})
	add_child(bullet)
	bullet.global_position = origin
	bullet.set_physics_process(false)
	for frame in 8:
		await get_tree().physics_frame
		bullet._physics_process(1.0 / 60.0)
		if not bullet._active:
			break
	var end_z := bullet.global_position.z
	bullet.queue_free()
	return end_z


func verify_hit_volume_pose(enemy: Enemy3D, stage: String) -> void:
	var visual := enemy.avatar.get_animated_elite_root()
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var proxy := enemy.get_animated_hit_volume_body()
	if proxy == null:
		check(false, "Missing hit proxy during %s" % stage)
		return
	for spec in visual.call("get_hit_volume_spec"):
		var bone_name: String = spec["bone"]
		var volume := proxy.get_node_or_null("Volume_" + bone_name) as CollisionShape3D
		var bone := skeleton.find_bone(bone_name)
		var expected := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		expected = expected.translated_local(spec["center"])
		if volume != null and bone_name.ends_with("_Foot"):
			expected.origin.y = volume.global_position.y
		check(volume != null and volume.global_transform.is_equal_approx(expected), "%s bullet volume separated from bone during %s" % [bone_name, stage])

func verify_confiscation() -> void:
	var dungeon := Dungeon3D.new()
	var player := Player3D.new()
	var label := Label.new()
	dungeon.player = player
	dungeon.status_label = label
	dungeon._inventory = InventoryModule.new(2)
	dungeon._quick_inventory = InventoryModule.new(2)
	var item := {"id": "item_ammo_pack", "name": "备弹", "stackable": true, "max_stack": 10}
	dungeon._quick_inventory.put_item_in_empty_slot(0, item, 2)
	dungeon.confiscate_player_carried_item(null)
	check(dungeon._quick_inventory.get_item_count("item_ammo_pack") == 2, "Confiscation accepted a different target")
	dungeon.confiscate_player_carried_item(player)
	check(dungeon._quick_inventory.get_item_count("item_ammo_pack") == 1, "Confiscation must remove exactly one from a stack")
	dungeon.confiscate_player_carried_item(player)
	dungeon.confiscate_player_carried_item(player)
	check(dungeon._quick_inventory.get_occupied_slots().is_empty(), "Confiscation did not handle an empty loadout")
	dungeon.free()
	player.free()
	label.free()


func verify_health_contract() -> void:
	var enemy := make_enemy()
	var config := enemy.enemy_data.duplicate(true)
	config["override_max_hp"] = 100
	enemy.configure_from_enemy_data(config)
	check(enemy.max_hp == 2000 and enemy.current_hp == 2000, "Initial same-config health was not multiplied by twenty")
	enemy.take_damage(199)
	check(not enemy._elite_escape_active, "Retreat began below ten percent accumulated damage")
	var saved := enemy.export_runtime_state()
	var restored := make_enemy()
	restored.configure_from_enemy_data(config)
	restored.import_runtime_state(saved)
	check(restored.max_hp == 2000 and restored.current_hp == 1801 and restored._elite_encounter_damage_taken == 199, "Mid-appearance damage did not survive actor snapshot")
	restored.take_damage(1)
	check(restored._elite_escape_active and restored.current_hp == 1800, "Restored appearance did not retreat at the exact threshold")
	restored._elite_escape_elapsed = 1.25
	saved = restored.export_runtime_state()
	restored.configure_from_enemy_data(config)
	restored.import_runtime_state(saved)
	check(restored._elite_escape_active and is_equal_approx(restored._elite_escape_elapsed, 1.25), "Retreat progress did not survive reload")
	enemy.free()
	restored.free()

func verify_action() -> void:
	var target := make_target(Vector3(0,0.05,-1.8))
	var enemy := make_enemy()
	bind_target(enemy,target)
	check(enemy.arms_taker_combat != null,"Formal enemy has no authoritative action controller")
	check(enemy.scale.is_equal_approx(Vector3.ONE * Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER * 1.0), "Elite root did not scale model and collision together")
	check(not enemy.avatar.get_component_snapshot().procedural_pose,"Skeletal elite still receives outer procedural pose")
	check(not enemy.uses_no_corpse_death() and not enemy.uses_goo_death_burst(),"Independent elite still inherits zombie death")
	var footprint := enemy.collision_shape.shape as CylinderShape3D
	check(is_equal_approx(footprint.radius,EnemyAvatar3D.get_footprint_profile("melee_chaser").radius),"Elite changed the shared gameplay footprint")
	var bottom_offset := (enemy.collision_shape.position.y - footprint.height * 0.5) * enemy.scale.y
	check(absf(bottom_offset - 0.001) < 0.000001, "Elite movement cylinder base was not raised by one world millimeter")
	enemy.transition_to("chase")
	enemy._attack_timer = 0.0
	step(enemy)
	check(enemy.ai_state == "telegraph","Real chase did not enter telegraph")
	var origin := enemy.position
	var observed: Array[String] = []
	var max_sample_error := 0.0
	for frame in range(1,162):
		step(enemy)
		if not observed.has(enemy.ai_state):observed.append(enemy.ai_state)
		var action := enemy.arms_taker_combat
		var snapshot: Dictionary = enemy.avatar._formal_elite_root.get_presentation_snapshot()
		if action.active:
			max_sample_error = maxf(max_sample_error,absf(float(snapshot.clip_time)-action.elapsed))
			check(snapshot.clip == "attack_light","Action switched away from its source attack clip")
			check(Vector2(enemy.position.x-origin.x,enemy.position.z-origin.z).length()<0.02,"Autonomous movement leaked into attack/recovery")
			if frame % 12 == 0:
				verify_hit_volume_pose(enemy, enemy.ai_state)
		if frame <= 78:check(target.damage_events == 0,"Damage happened before source frame 40")
		if frame >= 82:check(target.damage_events == 1,"Attack did not commit exactly once")
		if frame >= 90 and frame <= 158:check(enemy.ai_state == "recovery","Full followthrough was cut short")
	check(observed.has("attack") and observed.has("recovery") and observed.has("chase"),"Real action skipped a state")
	check(max_sample_error<0.001,"Gameplay clock and animation sample diverged")
	check(enemy.arms_taker_combat.attack_attempts == 1,"Attack was committed multiple times")
	# Active cast can be saved, but loading never replays an old damage frame.
	enemy.transition_to("telegraph")
	step(enemy)
	var saved := enemy.export_runtime_state()
	enemy.import_runtime_state(saved)
	check(enemy.ai_state == "alert" and not enemy.arms_taker_combat.active,"Restore resumed an unsafe damage frame")
	enemy.free()
	target.free()
	clean_effects()
	await get_tree().process_frame

func verify_interrupts() -> void:
	for stop in ["stagger","dormant","return","dead"]:
		var target := make_target(Vector3(0,0.05,-1.8))
		var enemy := make_enemy()
		bind_target(enemy,target)
		enemy.transition_to("telegraph")
		for frame in 12:step(enemy)
		enemy.transition_to(stop)
		check(not enemy.arms_taker_combat.active,"%s left a pending elite attack"%stop)
		for frame in 100:
			enemy.arms_taker_combat.tick(1.0/60.0)
		check(target.damage_events == 0,"Cancelled action dealt damage after %s"%stop)
		enemy.free()
		target.free()
		await get_tree().process_frame
	var target := make_target(Vector3(0,0.05,-1.8))
	var enemy := make_enemy()
	bind_target(enemy,target)
	enemy.transition_to("telegraph")
	var elapsed := enemy.arms_taker_combat.elapsed
	enemy._fate_freeze_remaining = 0.5
	step(enemy,0.2)
	check(is_equal_approx(elapsed,enemy.arms_taker_combat.elapsed),"Frozen action clock advanced")
	enemy._fate_freeze_remaining = 0.0
	# Actual damage must select the full hurt state, then return to combat.
	enemy.take_damage(1,false,Vector3.RIGHT)
	step(enemy)
	check(enemy.ai_state == "stagger" and enemy.avatar._formal_elite_root.get_presentation_snapshot().clip == "hit","Damage did not select the authoritative hurt pose")
	for frame in 100:step(enemy)
	check(enemy.ai_state == "stagger","Hurt animation was cut to the generic 0.16s window")
	verify_hit_volume_pose(enemy, "stagger")
	enemy.set_runtime_active(false,true)
	check(enemy.ai_state == "dormant" and not enemy.arms_taker_combat.active,"Dormancy did not cancel the action")
	enemy.set_physics_process(false)
	enemy.set_runtime_active(true)
	enemy.set_physics_process(false)
	enemy._target = null
	enemy.transition_to("telegraph")
	enemy.arms_taker_combat.tick(0.1)
	check(enemy.ai_state == "search" and not enemy.arms_taker_combat.active,"Lost target did not cancel uncommitted action")
	# Contact-frame line of sight is revalidated independently of the start decision.
	bind_target(enemy,target)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6,4,0.3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0,1,-0.9)
	add_child(wall)
	await get_tree().physics_frame
	enemy.transition_to("telegraph")
	enemy.arms_taker_combat.tick(1.34)
	check(target.damage_events == 0,"Contact frame hit through a wall")
	wall.free()
	enemy.free()
	target.free()
	clean_effects()
	await get_tree().process_frame

func verify_locomotion() -> void:
	var enemy := make_enemy()
	var visual := enemy.avatar._formal_elite_root
	var model := visual.get_node("VisualGLB") as Node3D
	check((model.basis*Vector3.BACK).dot(Vector3.FORWARD)>0.999,"Actual source +Z still faces opposite to gameplay -Z")
	var player := visual.find_child("AnimationPlayer",true,false) as AnimationPlayer
	var skeleton := visual.find_child("Skeleton3D",true,false) as Skeleton3D
	for clip in ["walk","run"]:
		var animation := player.get_animation(clip)
		var positions: Array[Vector3] = []
		for frame in range(181):
			player.play(clip)
			player.seek(animation.length*float(frame%180)/180.0,true)
			positions.append(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hip")).origin))
		var max_jump := 0.0
		for index in range(1,positions.size()):
			max_jump = maxf(max_jump,positions[index].distance_to(positions[index-1]))
		check(positions[0].distance_to(positions[179])<0.04,"%s still teleports at its loop boundary"%clip)
		check(max_jump<0.10,"%s contains a discontinuous root displacement"%clip)
	# Real patrol physical movement and body/visual facing agree across several loops.
	present(enemy)
	enemy.transition_to("patrol")
	enemy._patrol_target = Vector3(0,0,-20)
	var previous := hip_position(enemy)
	var max_moving_jump := 0.0
	for frame in 240:
		await get_tree().physics_frame
		step(enemy)
		if frame % 12 == 0:
			verify_hit_volume_pose(enemy, "patrol")
		var next := hip_position(enemy)
		max_moving_jump = maxf(max_moving_jump,next.distance_to(previous))
		previous = next
		if frame > 30:
			var velocity := Vector3(enemy.get_real_velocity().x,0,enemy.get_real_velocity().z)
			if velocity.length()>0.2:
				check((-enemy.global_basis.z).normalized().dot(velocity.normalized())>0.9,"Physical patrol moves backwards")
	check(max_moving_jump<0.20,"Running movement still snaps its visible skeleton")
	check(enemy.position.z < -1.0,"Patrol did not physically move")
	check(visual.position.is_zero_approx() and enemy.avatar._root.position.is_zero_approx(),"Procedural root offset leaked into the skeletal elite")
	visual.call("sync_context",{"state":"chase","action_id":"locomotion","speed":0.0,"base_speed":3.0},false)
	check(visual.get_presentation_snapshot().clip == "idle","Stopped/blocked movement keeps walking in place")
	enemy.free()
	await get_tree().process_frame

func verify_forced_motion() -> void:
	var enemy := make_enemy()
	var target := make_target(Vector3(0,0.05,-1.8))
	bind_target(enemy,target)
	enemy.transition_to("telegraph")
	enemy.apply_melee_knockback(Vector3.RIGHT,5.0,0.2)
	var peak := 0.0
	for frame in 6:
		step(enemy)
		peak=maxf(peak,enemy.velocity.x)
	check(peak<=5.001 and peak>=4.999,"Action multiplies or swallows externally applied velocity")
	for frame in 10:step(enemy)
	check(absf(enemy.velocity.x)<0.001,"Expired external velocity keeps accelerating the cast")
	check(enemy.ai_state=="telegraph","Forced motion silently skips the action state")
	enemy.take_damage(1,false,Vector3.RIGHT,4.0)
	step(enemy)
	check(is_equal_approx(enemy.velocity.x,4.0),"Hurt state swallowed projectile knockback")
	for frame in 12:step(enemy)
	check(absf(enemy.velocity.x)<0.001,"Full hurt clip incorrectly extends the old short knockback impulse")
	enemy.free()
	target.free()
	clean_effects()
	await get_tree().process_frame

func verify_facing_and_escape() -> void:
	var enemy := make_enemy()
	var target := make_target(Vector3(0,0.05,-1.8))
	bind_target(enemy,target)
	enemy.rotation.y = PI
	enemy.transition_to("chase")
	enemy._attack_timer = 0.0
	await get_tree().physics_frame
	step(enemy)
	check(enemy.ai_state == "chase" and not enemy.arms_taker_combat.active,"Elite begins an attack while facing backwards")
	for frame in 40:
		await get_tree().physics_frame
		step(enemy)
		if enemy.arms_taker_combat.active:break
	check(enemy.arms_taker_combat.active,"Elite cannot attack after turning towards the target")
	enemy._elite_growth_profile = {"escape_enabled":true,"escape_health_ratio":0.2,"escape_duration":4.2}
	enemy.current_hp = enemy.max_hp
	enemy._elite_encounter_damage_taken = int(ceil(enemy.max_hp * 0.1)) - 1
	enemy.take_damage(2)
	step(enemy)
	check(enemy.ai_state == "return" and enemy._elite_escape_active and not enemy.arms_taker_combat.active,"Low-health escape did not cancel the cast")
	check(enemy.avatar._formal_elite_root.get_presentation_snapshot().clip in ["walk","run"],"Escape is moving without a locomotion clip")
	enemy.free()
	target.free()
	clean_effects()
	await get_tree().process_frame

func verify_death() -> void:
	var enemy := make_enemy()
	var reference: WeakRef = weakref(enemy)
	enemy._die()
	check(enemy.get_animated_hit_volume_body().collision_layer == 0,"Dead elite still intercepts bullets before the next presentation frame")
	present(enemy)
	check(not enemy.is_queued_for_deletion() and enemy.avatar.visible,"Elite death is removed before its authored clip")
	check(enemy.collision_layer == 0 and not enemy.is_in_group("enemy_3d"),"Dead elite remains a combat target")
	check(enemy.avatar._formal_elite_root.get_presentation_snapshot().clip == "death","Death did not select the death clip")
	check(is_equal_approx(enemy.avatar.get_formal_death_duration(),4.6),"Death retention differs from the 4.6s source")
	await get_tree().create_timer(4.7).timeout
	check(reference.get_ref() == null,"Dead elite was not reclaimed at animation end")
