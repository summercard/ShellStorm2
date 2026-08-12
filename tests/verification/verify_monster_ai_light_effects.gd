extends Node3D
## 三态战斗效果、临时头顶标识、独立AI管理、视野与光照反应组合验收。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)

	await _verify_state_effects_and_ui(failures)
	await _verify_vision(player, failures)
	await _verify_proximity_and_damage_aggro(player, failures)
	await _verify_dynamic_vision_and_sound(player, failures)
	await _verify_flashlight_hunter(player, failures)
	await _verify_darkness_seeker(player, failures)
	await _verify_room_light_search_does_not_leak_player(player, failures)
	await _verify_boss_effect_isolation(failures)

	player.queue_free()
	if failures.is_empty():
		print("MONSTER_AI_LIGHT_EFFECTS_OK: 40% lit-state multipliers, sunlight DOT, shared overhead marker, managed vision, flashlight pursuit, darkness seeking and room-light search pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_state_effects_and_ui(failures: Array[String]) -> void:
	var enemy := _make_enemy("melee_chaser", Vector3(40.0, 0.0, 40.0))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	var dark := enemy.get_state_snapshot()
	var status_label := enemy.get_node_or_null("OverheadHealthBar/IlluminationStatusText") as Label3D
	if (
		str(dark.get("illumination_state", "")) != EnemyIllumination3D.STATE_DARKNESS
		or not is_equal_approx(float(dark.get("illumination_move_multiplier", 0.0)), 1.0)
		or not is_equal_approx(float(dark.get("illumination_attack_frequency_multiplier", 0.0)), 1.0)
		or str(dark.get("illumination_ui_text", "")) != "暗"
		or not bool(dark.get("illumination_ui_before_health_bar", false))
		or status_label == null
		or status_label.text != "暗"
	):
		failures.append("Darkness does not preserve baseline combat values/UI: %s" % str(dark))

	var lamp := _make_omni("EffectLamp", Vector3(40.0, 1.5, 37.0), 4.6, 9.0, "omni")
	enemy.force_refresh_illumination()
	var lit := enemy.get_state_snapshot()
	if (
		str(lit.get("illumination_state", "")) != EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
		or not is_equal_approx(float(lit.get("illumination_move_multiplier", 0.0)), 0.40)
		or not is_equal_approx(float(lit.get("illumination_attack_frequency_multiplier", 0.0)), 0.40)
		or not is_equal_approx(enemy.get_effective_move_speed(), enemy.move_speed * 0.40)
		or str(lit.get("illumination_ui_text", "")) != "亮"
	):
		failures.append("Artificial light does not apply the exact 40%% movement/attack frequency multipliers: %s" % str(lit))
	enemy.set("_attack_timer", 1.0)
	enemy.call("_physics_process", 1.0)
	if not is_equal_approx(float(enemy.get("_attack_timer")), 0.60):
		failures.append("Artificial light attack frequency does not advance a 1s timer by exactly 0.40")
	lamp.light_energy = 0.0
	enemy.force_refresh_illumination()
	if not is_equal_approx(enemy.get_effective_move_speed(), enemy.move_speed):
		failures.append("Leaving artificial light does not restore the original move speed")

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.light_cull_mask = 1
	add_child(sun)
	sun.add_to_group(EnemyIllumination3D.SUN_GROUP)
	enemy.force_refresh_illumination()
	var sun_snapshot := enemy.get_state_snapshot()
	var hp_before := enemy.current_hp
	enemy.call("_tick_illumination_effects", 1.0)
	var expected_loss := maxi(1, int(ceil(float(enemy.max_hp) * Enemy3D.SUNLIGHT_MAX_HP_DAMAGE_PER_SECOND)))
	if (
		str(sun_snapshot.get("illumination_state", "")) != EnemyIllumination3D.STATE_SUNLIGHT
		or enemy.current_hp != hp_before - expected_loss
		or str(sun_snapshot.get("illumination_ui_text", "")) != "太阳"
	):
		failures.append("Sunlight does not apply 2%% max-HP damage and the three-segment UI marker")
	var blocker := _make_blocker("EffectSunShadow", Vector3(40.0, 1.0, 43.0), Vector3(5.0, 4.0, 0.7))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	var shadow_hp := enemy.current_hp
	enemy.call("_tick_illumination_effects", 1.1)
	if enemy.current_hp != shadow_hp:
		failures.append("Sunlight damage continues after the monster enters a physical shadow")
	enemy.queue_free()
	lamp.queue_free()
	sun.queue_free()
	blocker.queue_free()
	await get_tree().process_frame


func _verify_vision(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3.ZERO
	var enemy := _make_enemy("melee_chaser", Vector3(0.0, 0.0, -6.0))
	enemy.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)
	await get_tree().physics_frame
	var visible := MonsterAIManager.force_refresh_enemy(enemy)
	if str(visible.get("awareness", "")) != "visual_contact" or not bool(visible.get("target_visible", false)):
		failures.append("Managed vision cannot see a player inside range/cone with clear line of sight: %s" % str(visible))
	enemy.rotation.y += PI
	var behind := MonsterAIManager.force_refresh_enemy(enemy)
	if bool(behind.get("target_visible", true)) or str(behind.get("awareness", "")) == "visual_contact":
		failures.append("Managed vision sees a player behind the 120-degree cone")
	enemy.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)
	var wall := _make_blocker("VisionWall", Vector3(0.0, 1.0, -3.0), Vector3(4.0, 3.0, 0.5))
	await get_tree().physics_frame
	var occluded := MonsterAIManager.force_refresh_enemy(enemy)
	if bool(occluded.get("target_visible", true)) or str(occluded.get("awareness", "")) == "visual_contact":
		failures.append("Managed vision sees the player through a physical wall")
	enemy.queue_free()
	wall.queue_free()
	await get_tree().process_frame


func _verify_flashlight_hunter(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3(0.0, 0.0, -8.0)
	var enemy := _make_enemy("shielded", Vector3(0.0, 0.0, 0.0))
	# 背对玩家，确保本次授权来自手电而不是普通视野。
	enemy.rotation.y = PI
	var beam := _make_spot("HunterFlashlight", Vector3(0.0, 1.0, -7.5), enemy.global_position + Vector3.UP * 0.7, player.get_instance_id())
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	var decision := MonsterAIManager.force_refresh_enemy(enemy)
	if (
		str(decision.get("awareness", "")) != "flashlight_contact"
		or int(decision.get("target_instance_id", 0)) != player.get_instance_id()
		or str(decision.get("light_response_policy", "")) != "light_hunter"
	):
		failures.append("Light-hunter does not pursue the owner of a real flashlight hit: %s" % str(decision))
	var before_distance := enemy.global_position.distance_to(player.global_position)
	enemy.set_runtime_active(true, true)
	await get_tree().create_timer(0.65).timeout
	var after_distance := enemy.global_position.distance_to(player.global_position)
	if after_distance >= before_distance - 0.05:
		failures.append("Flashlight awareness exists but does not drive the hunter toward the player: %.3f -> %.3f" % [before_distance, after_distance])
	beam.look_at(Vector3(0.0, 1.0, -15.0), Vector3.UP)
	enemy.force_refresh_illumination()
	var lost := MonsterAIManager.force_refresh_enemy(enemy)
	if str(lost.get("awareness", "")) == "flashlight_contact":
		failures.append("Flashlight stimulus remains active after the beam turns away")
	enemy.queue_free()
	beam.queue_free()
	await get_tree().process_frame


func _verify_proximity_and_damage_aggro(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3(0.0, 0.0, 0.0)
	var nearby := _make_enemy("melee_chaser", Vector3(0.0, 0.0, -4.0))
	# 默认朝-Z，玩家位于其+Z侧后方，验证接近不会伪装成视觉确认。
	nearby.rotation.y = 0.0
	await get_tree().physics_frame
	var proximity := MonsterAIManager.force_refresh_enemy(nearby)
	if (
		str(proximity.get("awareness", "")) != "proximity_contact"
		or str(proximity.get("engagement", "")) != "alert"
		or int(proximity.get("target_instance_id", -1)) != 0
	):
		failures.append("Close rear proximity must alert without granting a combat target: %s" % str(proximity))
	var nearby_before := nearby.global_position.distance_to(player.global_position)
	nearby.set_runtime_active(true, true)
	await get_tree().create_timer(0.65).timeout
	if nearby.global_position.distance_to(player.global_position) >= nearby_before - 0.02:
		failures.append("Close-range alert does not investigate its stimulus position")
	nearby.queue_free()

	player.position = Vector3(0.0, 0.0, 0.0)
	var distant := _make_enemy("melee_chaser", Vector3(0.0, 0.0, -24.0))
	distant.notify_attacked_by(player)
	var damage_decision := MonsterAIManager.force_refresh_enemy(distant)
	if (
		str(damage_decision.get("awareness", "")) != "damage_contact"
		or int(damage_decision.get("target_instance_id", 0)) != player.get_instance_id()
	):
		failures.append("A distant monster does not aggro the player who damaged it: %s" % str(damage_decision))
	var distant_before := distant.global_position.distance_to(player.global_position)
	distant.set_runtime_active(true, true)
	await get_tree().create_timer(0.75).timeout
	if distant.global_position.distance_to(player.global_position) >= distant_before - 0.05:
		failures.append("Damage aggro exists but does not drive the distant monster toward its attacker")
	distant.queue_free()
	await get_tree().process_frame


func _verify_dynamic_vision_and_sound(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3.ZERO
	var enemy := _make_enemy("melee_chaser", Vector3(0.0, 0.0, -11.0))
	enemy.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)
	await get_tree().physics_frame
	var dark := MonsterAIManager.force_refresh_enemy(enemy)
	if (
		str(dark.get("awareness", "")) == "visual_contact"
		or not is_equal_approx(float(dark.get("vision_range", 0.0)), MonsterVisionSystem3D.DARKNESS_VISION_RANGE)
	):
		failures.append("Dark-state vision must use the shorter 8.5m range: %s" % str(dark))
	var lamp := _make_omni("VisionRangeLamp", enemy.global_position + Vector3.UP * 2.0, 5.0, 10.0, "omni")
	enemy.force_refresh_illumination()
	var lit := MonsterAIManager.force_refresh_enemy(enemy)
	if (
		str(lit.get("awareness", "")) != "visual_contact"
		or str(lit.get("engagement", "")) != "combat"
		or not is_equal_approx(float(lit.get("vision_range", 0.0)), MonsterVisionSystem3D.ARTIFICIAL_LIGHT_VISION_RANGE)
	):
		failures.append("Lit-state vision does not extend to 13.5m and confirm combat: %s" % str(lit))
	enemy.queue_free()
	lamp.queue_free()
	await get_tree().process_frame

	player.position = Vector3(30.0, 0.0, 30.0)
	var listener := _make_enemy("melee_chaser", Vector3(0.0, 0.0, 0.0))
	await get_tree().physics_frame
	var sound_position := Vector3(5.0, 0.0, 0.0)
	var alerted := MonsterAIManager.broadcast_sound_stimulus(sound_position, 8.0, "container_open", player)
	var sound := MonsterAIManager.force_refresh_enemy(listener)
	if (
		alerted < 1
		or str(sound.get("awareness", "")) != "sound_contact"
		or str(sound.get("engagement", "")) != "alert"
		or int(sound.get("target_instance_id", -1)) != 0
		or not (sound.get("stimulus_position", Vector3.ZERO) as Vector3).is_equal_approx(sound_position)
	):
		failures.append("Interaction sound must alert toward the event without leaking a player target: %s" % str(sound))
	listener.queue_free()
	await get_tree().process_frame


func _verify_darkness_seeker(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3(20.0, 0.0, -8.0)
	var enemy := _make_enemy("ranged_caster", Vector3(20.0, 0.0, 0.0))
	enemy.rotation.y = PI
	var beam := _make_spot("SeekerFlashlight", Vector3(20.0, 1.0, -7.5), enemy.global_position + Vector3.UP * 0.7, player.get_instance_id())
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	var decision := MonsterAIManager.force_refresh_enemy(enemy)
	var dark_position := decision.get("stimulus_position", Vector3.ZERO) as Vector3
	if (
		str(decision.get("awareness", "")) != "seek_darkness"
		or int(decision.get("target_instance_id", -1)) != 0
		or str(decision.get("light_response_policy", "")) != "darkness_seeker"
		or dark_position == Vector3.ZERO
	):
		failures.append("Darkness-seeker does not choose a dark movement target after flashlight contact: %s" % str(decision))
	enemy.queue_free()
	beam.queue_free()
	await get_tree().process_frame


func _verify_room_light_search_does_not_leak_player(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3(-30.0, 0.0, -30.0)
	var enemy := _make_enemy("melee_chaser", Vector3(40.0, 0.0, 0.0))
	var lamp := _make_omni("RoomSearchLamp", Vector3(40.0, 2.0, -3.0), 5.0, 10.0, "omni")
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	var decision := MonsterAIManager.force_refresh_enemy(enemy)
	if (
		str(decision.get("awareness", "")) != "room_light_search"
		or int(decision.get("target_instance_id", -1)) != 0
		or bool(decision.get("target_visible", true))
		or (decision.get("stimulus_position", Vector3.ZERO) as Vector3).is_equal_approx(player.global_position)
	):
		failures.append("Room light search leaks an unseen player's position or fails to search: %s" % str(decision))
	enemy.queue_free()
	lamp.queue_free()
	await get_tree().process_frame


func _verify_boss_effect_isolation(failures: Array[String]) -> void:
	var boss := _make_enemy("boss", Vector3(80.0, 0.0, 80.0))
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.light_cull_mask = 1
	add_child(sun)
	sun.add_to_group(EnemyIllumination3D.SUN_GROUP)
	boss.force_refresh_illumination()
	boss.current_hp = int(float(boss.max_hp) * 0.2)
	boss.call("_update_boss_phase")
	var phase_before := boss.boss_phase
	var cooldown_before := boss.attack_cooldown
	boss.call("_tick_illumination_effects", 1.0)
	if (
		boss.boss_phase != phase_before
		or not is_equal_approx(boss.attack_cooldown, cooldown_before)
		or boss.get_illumination_state() != EnemyIllumination3D.STATE_SUNLIGHT
	):
		failures.append("Boss sunlight damage mutates its phase or attack contract")
	boss.queue_free()
	sun.queue_free()
	await get_tree().process_frame


func _make_enemy(kind: String, world_position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	enemy.position = world_position
	add_child(enemy)
	enemy.set_runtime_active(false, true)
	return enemy


func _make_omni(node_name: String, world_position: Vector3, energy: float, light_range: float, kind: String) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = world_position
	light.light_energy = energy
	light.omni_range = light_range
	light.light_cull_mask = 1
	add_child(light)
	light.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	light.set_meta("gameplay_light_kind", kind)
	return light


func _make_spot(node_name: String, world_position: Vector3, target: Vector3, owner_id: int) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = node_name
	light.position = world_position
	light.light_energy = 7.2
	light.spot_range = 12.0
	light.spot_angle = 36.0
	light.light_cull_mask = 1
	add_child(light)
	light.look_at(target, Vector3.UP)
	light.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	light.set_meta("gameplay_light_kind", "flashlight")
	light.set_meta("gameplay_light_owner_instance_id", owner_id)
	return light


func _make_blocker(node_name: String, world_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = world_position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body
