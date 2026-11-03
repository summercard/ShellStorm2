extends "res://tests/verification/support/SecondEliteStateFixture.gd"

func _ready() -> void:
	setup_ground()
	await get_tree().physics_frame
	await verify_action()
	await verify_interrupts()
	await verify_forced_motion()
	await verify_facing_and_escape()
	await verify_locomotion()
	await verify_death()
	clean_effects()
	await get_tree().process_frame
	finish("SECOND_ELITE_STATE_FLOW_OK")

func verify_action() -> void:
	var target := make_target(Vector3(0,0.05,-1.8))
	var enemy := make_enemy()
	bind_target(enemy,target)
	check(enemy.arms_taker_combat != null,"Formal enemy has no authoritative action controller")
	check(not enemy.avatar.get_component_snapshot().procedural_pose,"Skeletal elite still receives outer procedural pose")
	check(not enemy.uses_no_corpse_death() and not enemy.uses_goo_death_burst(),"Independent elite still inherits zombie death")
	var footprint := enemy.collision_shape.shape as CylinderShape3D
	check(is_equal_approx(footprint.radius,EnemyAvatar3D.get_footprint_profile("melee_chaser").radius),"Elite changed the shared gameplay footprint")
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
	enemy.transition_to("patrol")
	enemy._patrol_target = Vector3(0,0,-20)
	var previous := hip_position(enemy)
	var max_moving_jump := 0.0
	for frame in 240:
		step(enemy)
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
	step(enemy)
	check(enemy.ai_state == "chase" and not enemy.arms_taker_combat.active,"Elite begins an attack while facing backwards")
	for frame in 40:
		step(enemy)
		if enemy.arms_taker_combat.active:break
	check(enemy.arms_taker_combat.active,"Elite cannot attack after turning towards the target")
	enemy._elite_growth_profile = {"escape_enabled":true,"escape_health_ratio":0.2,"escape_duration":4.2}
	enemy.current_hp = int(enemy.max_hp*0.2)+1
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
	present(enemy)
	check(not enemy.is_queued_for_deletion() and enemy.avatar.visible,"Elite death is removed before its authored clip")
	check(enemy.collision_layer == 0 and not enemy.is_in_group("enemy_3d"),"Dead elite remains a combat target")
	check(enemy.avatar._formal_elite_root.get_presentation_snapshot().clip == "death","Death did not select the death clip")
	check(is_equal_approx(enemy.avatar.get_formal_death_duration(),4.6),"Death retention differs from the 4.6s source")
	await get_tree().create_timer(4.7).timeout
	check(reference.get_ref() == null,"Dead elite was not reclaimed at animation end")
