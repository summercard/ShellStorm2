extends "res://tests/verification/support/SecondEliteStateFixture.gd"

func _ready() -> void:
	verify_confiscation()
	setup_ground()
	await get_tree().physics_frame
	verify_body_scale_curve()
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
	check(proxy != null and volumes.size() == 17, "Elite did not assemble its animated bullet volumes")
	if proxy == null or volumes.size() != 17:
		enemy.free()
		return
	check(enemy.collision_layer == 0 and enemy.collision_mask == 1, "Elite movement cylinder still intercepts bullets or lost its movement mask")
	check(proxy.collision_layer == Enemy3D.ENEMY_BULLET_LAYER and proxy.collision_mask == 0, "Bullet proxy can participate in movement")
	var column := proxy.get_node_or_null("Volume_TorsoColumn") as CollisionShape3D
	check(column != null, "Elite did not assemble the ground-locked torso column")
	if column != null:
		var column_box := column.shape as BoxShape3D
		var column_bounds := column.global_transform * AABB(-column_box.size * 0.5, column_box.size)
		var sole := INF
		for bone in ["L_Foot", "R_Foot"]:
			var foot := proxy.get_node("Volume_" + bone) as CollisionShape3D
			var foot_box := foot.shape as BoxShape3D
			sole = minf(sole, (foot.global_transform * AABB(-foot_box.size * 0.5, foot_box.size)).position.y)
		var waist := proxy.get_node("Volume_Waist") as CollisionShape3D
		var waist_box := waist.shape as BoxShape3D
		var waist_top := (waist.global_transform * AABB(-waist_box.size * 0.5, waist_box.size)).end.y
		check(absf(column_bounds.position.y - sole) <= 0.01,
			"Torso column bottom (%.3f) is not flush with the supporting sole (%.3f)" % [column_bounds.position.y, sole])
		check(absf(column_bounds.end.y - waist_top) <= 0.06,
			"Torso column top (%.3f) does not meet the waist volume (%.3f)" % [column_bounds.end.y, waist_top])
		check(column_bounds.size.x > 0.15 and column_bounds.size.z > 0.15,
			"Torso column cross section collapsed to %.2f x %.2f m" % [column_bounds.size.x, column_bounds.size.z])
	# 两腿之间原本是空的；补底柱之后这条弹道必须掉血（业主 2026-11-09 改）。
	var gap := enemy.global_position + Vector3(0, 0.8, 0)
	var hp := enemy.current_hp
	await fire_at_elite(gap + Vector3.FORWARD * 2.0, Vector3.BACK)
	check(enemy.current_hp == hp - 1, "A real bullet through the space between the legs still passed the elite")
	var boot := proxy.get_node("Volume_L_Foot") as CollisionShape3D
	var outside := boot.global_position
	var foot_size := (boot.shape as BoxShape3D).size
	var foot_bounds := boot.global_transform * AABB(-foot_size * 0.5, foot_size)
	var side := signf(outside.x - enemy.global_position.x)
	outside.x = (foot_bounds.end.x if side > 0.0 else foot_bounds.position.x) + side * 0.18
	hp = enemy.current_hp
	var passed := await fire_at_elite(outside + Vector3.FORWARD * 2.0, Vector3.BACK)
	check(passed > outside.z + 1.1 and enemy.current_hp == hp, "A projectile outside the boot outline was stopped by the torso column")
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
	check(player.weapon.try_fire(Vector3.BACK, player), "Pistol did not fire toward the gap between the legs")
	await get_tree().create_timer(0.5).timeout
	check(enemy.current_hp < hp, "The player pistol passed the gap between the legs without damaging the torso column")
	var calf := proxy.get_node("Volume_L_Calf") as CollisionShape3D
	player.position.x += calf.global_position.x - muzzle.global_position.x
	player.weapon._cooldown = 0.0
	hp = enemy.current_hp
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
		var volume := proxy.get_node_or_null("Volume_" + str(spec.get("label", spec["bone"]))) as CollisionShape3D
		if bool(spec.get("ground_locked", false)):
			# 补底柱刻意不跟骨骼旋转，只要求它的底边始终贴着当前姿态的支撑面。
			if volume == null:
				check(false, "Missing torso column during %s" % stage)
				continue
			var column_box := volume.shape as BoxShape3D
			var column_bounds := volume.global_transform * AABB(-column_box.size * 0.5, column_box.size)
			var sole := INF
			for foot in ["L_Foot", "R_Foot"]:
				var foot_shape := proxy.get_node_or_null("Volume_" + foot) as CollisionShape3D
				if foot_shape == null:
					continue
				var foot_box := foot_shape.shape as BoxShape3D
				sole = minf(sole, (foot_shape.global_transform * AABB(-foot_box.size * 0.5, foot_box.size)).position.y)
			check(absf(column_bounds.position.y - sole) <= 0.02, "Torso column left the supporting surface during %s" % stage)
			continue
		var bone_name: String = spec["bone"]
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


## 体型曲线横跨三处真源：`EliteContentCatalog`（系数）、`Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER`
## （全局 0.70）、`Enemy3D.MAX_COLLISION_RADIUS_M`（门洞硬上限）。任一处单独改动都会让这里变红。
## 业主 2026-11-09：1 级 1.5 倍（3.675 m），12 级 3 倍（7.350 m）。
func verify_body_scale_curve() -> void:
	var definition := EliteContentCatalog.get_by_id("elite_arms_taker")
	var growth: Dictionary = definition["growth_profile"]
	var base := float(growth.get("body_scale_base", 1.0))
	var step := float(growth.get("body_scale_per_level", 0.06))
	var cap := int(growth.get("level_cap", 12))
	var model_height := float(definition["health_bar_profile"]["visual_height"])
	var global_scale := Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER
	check(is_equal_approx(base, 1.5), "Level 1 body scale is %.3f, expected 1.5" % base)
	var cap_scale := base + float(cap - 1) * step
	check(is_equal_approx(cap_scale, 3.0),
		"Level %d body scale is %.4f, expected exactly 3.0" % [cap, cap_scale])
	var level_one := model_height * global_scale * base
	var level_cap := model_height * global_scale * cap_scale
	check(absf(level_one - 3.675) < 0.01,
		"Level 1 height %.3f m is not 3.675 m (3.5 x 0.70 x 1.5)" % level_one)
	check(absf(level_cap - 7.35) < 0.02,
		"Level %d height %.3f m is not 7.35 m (3.5 x 0.70 x 3.0)" % [cap, level_cap])
	var small := make_enemy(false, 1, growth)
	var large := make_enemy(false, cap, growth)
	check(is_equal_approx(small.scale.y, global_scale * base),
		"Level 1 instance scale %.4f is not 0.70 x 1.5" % small.scale.y)
	check(is_equal_approx(large.scale.y, global_scale * 3.0),
		"Level %d instance scale %.4f is not 0.70 x 3.0" % [cap, large.scale.y])
	# 3 倍把碰撞柱顶到 1.714 m（超门洞上限 83%）。`_apply_presentation_scale()` 必须把它
	# 钳回上限，否则满级收租人"看得见、走不过门"。这里钉的是**钳制后**的世界半径。
	var cap_radius := large.get_world_body_radius()
	check(cap_radius <= Enemy3D.MAX_COLLISION_RADIUS_M + 0.0005,
		"Level %d collision radius %.3f m exceeds the walkable doorway limit %.3f m" % [
			cap, cap_radius, Enemy3D.MAX_COLLISION_RADIUS_M])
	check(cap_radius > Enemy3D.MAX_COLLISION_RADIUS_M * 0.9,
		"Level %d collision radius %.3f m is over-clamped; the cylinder should stay as wide as the doorway allows" % [
			cap, cap_radius])
	check(small.get_world_body_radius() < Enemy3D.MAX_COLLISION_RADIUS_M,
		"Level 1 collision radius %.3f m should stay below the doorway limit and unclamped" % small.get_world_body_radius())
	present(small)
	present(large)
	var small_top := _head_volume_top(small)
	var large_top := _head_volume_top(large)
	check(small_top > 2.5, "Level 1 head hit volume tops out at %.3f m, expected about 2.9 m" % small_top)
	check(large_top > 5.5, "Level %d head hit volume tops out at %.3f m, expected about 5.8 m" % [cap, large_top])
	# 受击盒侧缝随体型线性放大，而弹径固定 0.24 m。补底柱横截面已为 3 倍预设加宽，
	# 这里逐等级钉住"任何高度的横向覆盖都没有大于弹径的空洞"。
	for level in [1, 6, cap]:
		var probe := make_enemy(false, level, growth)
		present(probe)
		for height in [0.75, 0.8, 1.2, 2.0]:
			var widest := _widest_horizontal_gap(probe, height)
			check(widest < 0.24,
				"Level %d has a %.3f m bullet gap at y=%.2f m; the torso column no longer covers the gap between the legs" % [
					level, widest, height])
		probe.free()
		clean_effects()
	check(
		large._overhead_health_root.global_position.y - large.global_position.y
		> small._overhead_health_root.global_position.y - small.global_position.y,
		"Overhead health bar did not follow the taller body"
	)
	# 上面几条用的是夹具手传的 growth_profile，测的是"数值本身"。
	# 这一段走真实链路：内容库 → EliteRosterService.get_record() →
	# apply_archive_to_enemy_config() → Enemy3D，测的是"玩家真的会变这么大"。
	# 2026-11-09 发现夹具从不传 growth_profile 而让专项一直测 fallback，
	# 所以这条链路必须单独钉住，否则改了内容库也可能没人发现。
	var snapshot := EliteRosterService.get_record("elite_arms_taker")
	check(not snapshot.is_empty(), "EliteRosterService returned no archive record for elite_arms_taker")
	var routed := EliteRosterService.apply_archive_to_enemy_config({}, snapshot)
	var routed_growth: Dictionary = routed.get("elite_growth_profile", {})
	check(
		is_equal_approx(float(routed_growth.get("body_scale_base", 0.0)), 1.5),
		"Real roster→config path dropped body_scale_base (got %s)" % str(routed_growth.get("body_scale_base", "missing"))
	)
	var routed_enemy := make_enemy(false, 1, routed_growth)
	present(routed_enemy)
	check(
		is_equal_approx(routed_enemy.scale.y, global_scale * 1.5),
		"Real roster path produced instance scale %.4f, expected %.4f" % [
			routed_enemy.scale.y, global_scale * 1.5]
	)
	check(
		not routed_enemy.export_runtime_state().get("elite_growth_profile", {}).has("body_scale_base")
		or is_equal_approx(float(routed_enemy.export_runtime_state()["elite_growth_profile"]["body_scale_base"]), 1.5),
		"Runtime snapshot pinned a stale body_scale_base"
	)
	routed_enemy.free()
	small.free()
	large.free()
	clean_effects()


func _head_volume_top(enemy: Enemy3D) -> float:
	var body := enemy.get_animated_hit_volume_body()
	if body == null:
		return 0.0
	var shape := body.get_node_or_null("Volume_Head") as CollisionShape3D
	if shape == null:
		return 0.0
	var box := shape.shape as BoxShape3D
	return (shape.global_transform * AABB(-box.size * 0.5, box.size)).end.y


## 给定世界高度上，所有受击盒的 x 向覆盖之间最宽的一段空洞（米）。
## 弹体是半径 0.12 的球（直径 0.24），空洞 > 0.24 就意味着子弹能整条穿过去。
func _widest_horizontal_gap(enemy: Enemy3D, height: float) -> float:
	var body := enemy.get_animated_hit_volume_body()
	if body == null:
		return INF
	var spans: Array = []
	for node in body.get_children():
		var shape := node as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var aabb: AABB = shape.global_transform * AABB(-box.size * 0.5, box.size)
		if height >= aabb.position.y and height <= aabb.end.y:
			spans.append([aabb.position.x, aabb.end.x])
	if spans.is_empty():
		return INF
	spans.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var widest := 0.0
	var cursor: float = spans[0][1]
	for index in range(1, spans.size()):
		if float(spans[index][0]) > cursor:
			widest = maxf(widest, float(spans[index][0]) - cursor)
		cursor = maxf(cursor, float(spans[index][1]))
	return widest


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
