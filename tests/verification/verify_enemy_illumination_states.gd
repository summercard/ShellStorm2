extends Node3D
## 怪物/Boss 三态受光、太阳投影、局部灯范围/锥体/遮挡与优先级专项。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const WASTELAND_LIGHT_SCRIPT := preload("res://src/world3d/WastelandLight3D.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var enemy := _make_enemy("melee_chaser", Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().process_frame
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "no-light baseline", failures)

	var sun := DirectionalLight3D.new()
	sun.name = "TestGameplaySun"
	sun.light_energy = 1.0
	sun.light_cull_mask = 1
	add_child(sun)
	sun.add_to_group(EnemyIllumination3D.SUN_GROUP)
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_SUNLIGHT, "unoccluded sunlight", failures)

	var sun_blocker := _make_blocker("SunBlocker", Vector3(0, 1.0, 3.0), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "sun shadow", failures)
	if float(enemy.get_state_snapshot().get("illumination", {}).get("sun_exposure_ratio", 1.0)) != 0.0:
		failures.append("Sun shadow still reports non-zero body exposure")

	sun.light_energy = 0.0
	var omni := OmniLight3D.new()
	omni.name = "TestRoomLamp"
	omni.position = Vector3(0, 1.2, -3.0)
	omni.light_energy = 4.0
	omni.omni_range = 9.0
	omni.omni_attenuation = 1.0
	omni.light_cull_mask = 1
	add_child(omni)
	omni.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	sun.light_energy = 1.0
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "room light under sun shadow", failures)
	sun.light_energy = 0.0

	var lamp_blocker := _make_blocker("LampBlocker", Vector3(0, 1.0, -1.5), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "room light wall shadow", failures)
	lamp_blocker.queue_free()
	await get_tree().physics_frame

	omni.light_energy = 0.0
	var spot := SpotLight3D.new()
	spot.name = "TestFlashlight"
	spot.position = Vector3(0, 1.0, -4.0)
	spot.light_energy = 7.2
	spot.spot_range = 10.0
	spot.spot_angle = 32.0
	spot.spot_attenuation = 0.5
	spot.spot_angle_attenuation = 1.0
	spot.light_cull_mask = 1
	add_child(spot)
	spot.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	spot.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	spot.set_meta("gameplay_light_kind", "flashlight")
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "flashlight cone", failures)
	var illumination := enemy.get_state_snapshot().get("illumination", {}) as Dictionary
	if str(illumination.get("dominant_light_kind", "")) != "flashlight":
		failures.append("Flashlight is not reported as the dominant artificial light")
	var flashlight_blocker := _make_blocker("FlashlightBlocker", Vector3(0, 1.0, -2.0), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "flashlight wall shadow", failures)
	flashlight_blocker.queue_free()
	await get_tree().physics_frame

	spot.look_at(Vector3(0, 1.0, -8.0), Vector3.UP)
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "flashlight facing away", failures)
	spot.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	spot.position = Vector3(0, 1.0, -14.0)
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "flashlight outside range", failures)
	spot.position = Vector3(0, 1.0, -4.0)
	spot.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	spot.light_energy = 0.0
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "depleted flashlight energy", failures)
	spot.light_energy = 7.2
	await _verify_ambusher_uses_real_light(failures)

	# Runtime samples require two identical candidates, preventing one-frame shadow-edge flicker.
	spot.light_energy = 0.0
	enemy.force_refresh_illumination()
	spot.light_energy = 7.2
	enemy.force_refresh_illumination(false)
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "hysteresis first sample", failures)
	enemy.force_refresh_illumination(false)
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "hysteresis second sample", failures)

	spot.light_energy = 0.0
	var fixture := WASTELAND_LIGHT_SCRIPT.new() as WastelandLight3D
	fixture.position = Vector3(0, -1.3, -3.0)
	fixture.configure(Color.WHITE, 4.6, 10.0, 7, true, false, "ceiling")
	add_child(fixture)
	await get_tree().process_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "registered room fixture", failures)
	fixture.set_light_enabled(false)
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "room fixture switch off", failures)
	await _verify_player_flashlight_registration(failures)
	await _verify_real_player_flashlight_hit(failures)
	await _verify_player_spill_does_not_light_behind(failures)

	sun_blocker.queue_free()
	await get_tree().physics_frame
	sun.light_energy = 1.0
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_SUNLIGHT, "sun priority over flashlight", failures)

	_verify_all_enemy_kinds_share_contract(failures)
	await _verify_boss_phase_is_independent(failures)
	_verify_raycast_budget(enemy, failures)
	await _verify_thirty_enemy_budget(failures)

	enemy.queue_free()
	if failures.is_empty():
		print("ENEMY_ILLUMINATION_STATES_OK: darkness, artificial light, sunlight, physical shadow, flashlight cone, priority, hysteresis and Boss isolation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_all_enemy_kinds_share_contract(failures: Array[String]) -> void:
	var kinds := ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher", "boss"]
	for index in range(kinds.size()):
		var candidate := _make_enemy(kinds[index], Vector3(30.0 + index * 3.0, 0.0, 30.0))
		candidate.force_refresh_illumination()
		var snapshot := candidate.get_state_snapshot()
		var valid := snapshot.get("illumination", {}).get("valid_illumination_states", []) as Array
		if (
			candidate.illumination_sensor == null
			or str(snapshot.get("illumination_state", "")) not in EnemyIllumination3D.VALID_STATES
			or valid.size() != 3
		):
			failures.append("Enemy kind lacks the shared three-state illumination contract: %s" % kinds[index])
		candidate.queue_free()


func _verify_boss_phase_is_independent(failures: Array[String]) -> void:
	var boss := _make_enemy("boss", Vector3(60.0, 0.0, 60.0))
	await get_tree().process_frame
	boss.current_hp = int(float(boss.max_hp) * 0.2)
	boss.call("_update_boss_phase")
	var phase_before := boss.boss_phase
	var cooldown_before := boss.attack_cooldown
	boss.force_refresh_illumination()
	if boss.boss_phase != phase_before or not is_equal_approx(boss.attack_cooldown, cooldown_before):
		failures.append("Boss illumination refresh mutates HP phase or attack timing")
	boss.queue_free()


func _verify_player_flashlight_registration(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(100.0, 0.0, 100.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D if flashlight != null else null
	var spill := flashlight.get_node_or_null("FlashlightKit/EnvironmentSpill") as OmniLight3D if flashlight != null else null
	var fill := flashlight.get_node_or_null("FlashlightKit/AvatarFrontFill") as SpotLight3D if flashlight != null else null
	if (
		flashlight == null
		or beam == null
		or spill == null
		or fill == null
		or not beam.is_in_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		or spill.is_in_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		or fill.is_in_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		or str(beam.get_meta("gameplay_light_kind", "")) != "flashlight"
	):
		failures.append("Only the player's forward spotlight may register as gameplay illumination")
	player.queue_free()


func _verify_real_player_flashlight_hit(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(120.0, 0.0, -6.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.aim_direction = Vector3.BACK
	var target := _make_enemy("melee_chaser", Vector3(120.0, 0.0, 0.0))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("Real player flashlight hit test cannot find PlayerFlashlight3D")
		target.queue_free()
		player.queue_free()
		return
	flashlight.set_light_enabled(true)
	flashlight.force_sync()
	await get_tree().physics_frame
	target.force_refresh_illumination()
	var illumination := target.get_state_snapshot().get("illumination", {}) as Dictionary
	if (
		target.get_illumination_state() != EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
		or str(illumination.get("dominant_light_kind", "")) != "flashlight"
	):
		failures.append(
			"Real player spotlight is blocked by its owner's collision or misses illumination: %s"
			% str(illumination)
		)
	target.queue_free()
	player.queue_free()


func _verify_player_spill_does_not_light_behind(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(150.0, 0.0, 0.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.aim_direction = Vector3.FORWARD
	var target := _make_enemy("melee_chaser", Vector3(150.0, 0.0, 3.0))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	flashlight.set_light_enabled(true)
	flashlight.force_sync()
	await get_tree().physics_frame
	target.force_refresh_illumination()
	if target.get_illumination_state() != EnemyIllumination3D.STATE_DARKNESS:
		failures.append("Player environment spill incorrectly lights a monster behind the spotlight")
	target.queue_free()
	player.queue_free()


func _verify_ambusher_uses_real_light(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(20.0, 0.0, -8.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var ambusher := _make_enemy("ambusher", Vector3(20.0, 0.0, 0.0))
	ambusher.set_runtime_active(true)
	var beam := SpotLight3D.new()
	beam.position = Vector3(20.0, 1.0, -4.0)
	beam.light_energy = 7.2
	beam.spot_range = 10.0
	beam.spot_angle = 32.0
	beam.light_cull_mask = 1
	add_child(beam)
	beam.look_at(Vector3(20.0, 0.7, 0.0), Vector3.UP)
	beam.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	beam.set_meta("gameplay_light_kind", "flashlight")
	var wall := _make_blocker("AmbusherFlashlightWall", Vector3(20.0, 1.0, -2.0), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	ambusher.force_refresh_illumination()
	await get_tree().physics_frame
	if bool(ambusher.get_state_snapshot().get("ambush_triggered", false)):
		failures.append("Ambusher reveals from a flashlight through a wall")
	wall.queue_free()
	await get_tree().physics_frame
	ambusher.force_refresh_illumination()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not bool(ambusher.get_state_snapshot().get("ambush_triggered", false)):
		failures.append("Ambusher does not reveal when a real unobstructed flashlight beam reaches it")
	ambusher.queue_free()
	beam.queue_free()
	player.queue_free()


func _verify_state(enemy: Enemy3D, expected: String, label: String, failures: Array[String]) -> void:
	var actual := enemy.get_illumination_state()
	if actual != expected:
		failures.append("Illumination mismatch (%s): got %s expected %s" % [label, actual, expected])


func _verify_raycast_budget(enemy: Enemy3D, failures: Array[String]) -> void:
	enemy.force_refresh_illumination()
	var illumination := enemy.get_state_snapshot().get("illumination", {}) as Dictionary
	if (
		int(illumination.get("last_sun_raycast_count", 99)) > 3
		or int(illumination.get("last_local_raycast_count", 99)) > 4
	):
		failures.append("Per-sample illumination raycast budget exceeded: %s" % str(illumination))


func _verify_thirty_enemy_budget(failures: Array[String]) -> void:
	var enemies: Array[Enemy3D] = []
	var total_rays := 0
	for index in range(30):
		var enemy := _make_enemy("melee_chaser", Vector3(100.0 + index * 2.0, 0.0, 120.0))
		enemy.force_refresh_illumination()
		var illumination := enemy.get_state_snapshot().get("illumination", {}) as Dictionary
		total_rays += int(illumination.get("last_sun_raycast_count", 0))
		total_rays += int(illumination.get("last_local_raycast_count", 0))
		if enemy.get_child_count() > 3:
			failures.append("Illumination implementation adds per-enemy scene nodes")
		enemies.append(enemy)
	if total_rays > 30 * 7:
		failures.append("Thirty-enemy illumination ray budget exceeded: %d" % total_rays)
	for enemy in enemies:
		enemy.queue_free()
	await get_tree().process_frame


func _make_enemy(kind: String, world_position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	enemy.position = world_position
	add_child(enemy)
	enemy.set_runtime_active(false, true)
	return enemy


func _make_blocker(node_name: String, world_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = world_position
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body
