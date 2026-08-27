extends Node
## 首只正式精英：残血逃脱、跨局成长、夺械预算转译、副枪频率和悬赏兑现配置。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const TEMP_SAVE := "user://verification_first_elite_growth.json"


class WeaponCarrier:
	extends Node3D

	func get_weapon_snapshot() -> Dictionary:
		return {
			"gun_id": "bp_shotgun",
			"weapon_kind": "ranged",
			"fire_rate": 2.4,
			"projectile_count": 3,
			"bullet_tags": ["explosive", "unsupported_runtime_tag"],
		}


func _ready() -> void:
	var failures: Array[String] = []
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	var original_save_failure := BaseManager.force_save_failure_for_test
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	BaseManager.force_save_failure_for_test = false
	EliteRosterService.reset_roster_for_test()

	var seed_value := _seed_for_floor(98, 773000)
	var injector := MonsterInjector.new()
	injector.set_seed(seed_value)
	var generated := injector.generate_enemies({
		"type":"elite", "floor":1, "floor_level":RoomData.FloorLevel.SHALLOW,
		"floor_number":98, "encounter_id":"growth_run:98:elite", "seed":seed_value,
	})
	if generated.size() != 1:
		failures.append("First elite growth encounter was not generated")
	else:
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		var carrier := WeaponCarrier.new()
		add_child(carrier)
		add_child(enemy)
		enemy.configure_from_enemy_data(generated[0])
		enemy._target = carrier
		var player := PLAYER_SCENE.instantiate() as Player3D
		player.start_with_weapon = false
		add_child(player)
		player.notify_attacked_by(enemy)
		var damage_source := player.get_last_damage_source_snapshot()
		if (
			str(damage_source.get("elite_id", "")) != "elite_rift_boar_armed"
			or str(damage_source.get("encounter_instance_id", "")) != "growth_run:98:elite"
		):
			failures.append("Player death attribution did not preserve the unique elite encounter identity")
		var escaped_signal := {"count": 0}
		enemy.escaped.connect(func(_source: Enemy3D, _context: Dictionary) -> void:
			escaped_signal["count"] = int(escaped_signal["count"]) + 1
		)
		var target_hp := maxi(1, int(floor(float(enemy.max_hp) * 0.19)))
		enemy.take_damage(enemy.current_hp - target_hp)
		var escape_snapshot := enemy.get_state_snapshot()
		if not bool(escape_snapshot.get("elite_escape_active", false)):
			failures.append("Elite did not enter its readable low-health escape state")
		if "撤离中" not in str(escape_snapshot.get("elite_health_bar_name", "")):
			failures.append("Elite health bar did not announce the escape window")
		BaseManager.force_save_failure_for_test = true
		enemy.force_complete_elite_escape_for_test()
		if not bool(enemy.get_state_snapshot().get("elite_escape_active", false)) or int(escaped_signal["count"]) != 0:
			failures.append("Failed archive save allowed the unique elite to disappear")
		BaseManager.force_save_failure_for_test = false
		enemy.force_complete_elite_escape_for_test()
		if int(escaped_signal["count"]) != 1:
			failures.append("Elite escape did not emit exactly one room-resolution signal")
		carrier.queue_free()
		player.queue_free()

	var grown := EliteRosterService.get_record("elite_rift_boar_armed")
	var stolen := grown.get("stolen_modules", []) as Array
	if int(grown.get("level", 0)) != 2 or int(grown.get("escape_count", 0)) != 1:
		failures.append("Successful runtime escape did not grow the archive exactly once")
	if int(grown.get("bounty_reward_level", 0)) != 1:
		failures.append("First escape did not establish bounty tier 1")
	if stolen.size() != 1:
		failures.append("Runtime escape did not capture one bounded weapon module")
	else:
		var module := stolen[0] as Dictionary
		if str(module.get("module_id", "")) != "weapon_shotgun":
			failures.append("Player gun ID was not normalized into a stable content ID")
		if int(module.get("shot_count_budget", 0)) != 3:
			failures.append("Shot count was not converted into the bounded enemy budget")
		if (module.get("bullet_traits", []) as Array) != ["explosive"]:
			failures.append("Weapon translation persisted unsupported runtime traits")

	# 连续逃脱到5级，验证“副枪射击频率”确实从每3次攻击提升到每2次。
	for growth_index in range(3):
		var encounter_id := "growth_run:repeat_%d:elite" % growth_index
		if not EliteRosterService.reserve("elite_rift_boar_armed", encounter_id, 98):
			failures.append("Grown elite could not be reserved for repeat encounter %d" % growth_index)
			continue
		EliteRosterService.confirm_reservation("elite_rift_boar_armed", encounter_id)
		if not EliteRosterService.settle("elite_rift_boar_armed", encounter_id, "escaped", {
			"floor_number": 98,
			"room_id": "repeat_room",
			"weapon_snapshot": {"gun_id":"bp_rifle", "fire_rate":6.0, "projectile_count":1},
		}):
			failures.append("Repeat escape %d did not settle" % growth_index)

	var level_five := EliteRosterService.get_record("elite_rift_boar_armed")
	var level_five_config := EliteRosterService.apply_archive_to_enemy_config({
		"enemy_type":"melee_chaser", "hp":100, "max_hp":100, "damage":10,
	}, level_five)
	var grown_enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(grown_enemy)
	grown_enemy.configure_from_enemy_data(level_five_config)
	var grown_snapshot := grown_enemy.get_state_snapshot()
	if int(grown_snapshot.get("elite_level", 0)) != 5:
		failures.append("Archive did not reach level 5 after four escapes")
	if int(grown_snapshot.get("elite_sidearm_attack_interval", 0)) != 2:
		failures.append("Level 5 did not improve sidearm frequency from every 3 attacks to every 2")
	if (
		not is_equal_approx(float(level_five_config.get("elite_growth_hp_mult", 0.0)), 1.32)
		or not is_equal_approx(float(level_five_config.get("elite_growth_damage_mult", 0.0)), 1.18)
		or grown_enemy.max_hp <= 100
		or grown_enemy.contact_damage <= 10
	):
		failures.append("Level 5 HP/damage growth was not applied after the shared 3D balance pipeline")
	if int(level_five_config.get("elite_bounty_tier", 0)) != 3 or int(level_five_config.get("elite_bounty_currency", 0)) != 115:
		failures.append("Four escapes did not produce the configured tier-3 115-soul bounty")
	grown_enemy.queue_free()

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	BaseManager.force_save_failure_for_test = original_save_failure
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
	if failures.is_empty():
		print("FIRST_ELITE_GROWTH_FLOW_OK: runtime escape, player-weapon translation, level scaling, sidearm frequency and bounty config pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _seed_for_floor(floor_number: int, start: int) -> int:
	for seed_value in range(start, start + 100):
		if EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", seed_value) == floor_number:
			return seed_value
	return start
