extends Node
## 12只唯一精英：固定名册、预约唯一性、成长、夺械、存档迁移与3D绑定。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const TEMP_SAVE := "user://verification_elite_roster.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	var original_failure := BaseManager.force_save_failure_for_test
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	BaseManager.force_save_failure_for_test = false
	EliteRosterService.reset_roster_for_test()

	var roster := EliteRosterService.get_all_elites()
	if roster.size() != 12:
		failures.append("Unique elite roster is not exactly 12: %d" % roster.size())
	var ids: Array[String] = []
	for elite in roster:
		var elite_id := str(elite.get("elite_id", ""))
		if elite_id.is_empty() or elite_id in ids:
			failures.append("Elite roster has an empty or duplicate stable ID: %s" % elite_id)
		ids.append(elite_id)
		for key in ["name", "base_enemy_id", "behavior_id", "modifier_id", "translation"]:
			if str(elite.get(key, "")).is_empty():
				failures.append("Elite %s lacks definition field %s" % [elite_id, key])
		var behavior_enemy := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(behavior_enemy)
		behavior_enemy.configure_from_enemy_data({
			"enemy_type": str(elite.get("base_enemy_id", "melee_chaser")),
			"is_elite": true, "elite_id": elite_id,
			"elite_behavior_id": str(elite.get("behavior_id", "")),
			"elite_level": 4, "modifier_id_en": str(elite.get("modifier_id", "Elite.Huge")),
			"hp": 120, "max_hp": 120, "damage": 8, "speed": 60,
		})
		for _attack in range(7):
			behavior_enemy._apply_unique_elite_attack_behavior(Vector3.FORWARD)
		var behavior_snapshot := behavior_enemy.get_state_snapshot()
		if int(behavior_snapshot.get("elite_attack_counter", 0)) != 7 or int(behavior_snapshot.get("elite_behavior_trigger_count", 0)) < 1:
			failures.append("Elite %s did not execute its unique live behavior" % elite_id)
		behavior_enemy.queue_free()

	var first_seed := _seed_for_floor(98, 990000)
	var first := EliteRosterService.select_and_reserve(first_seed, 98, "verify_run:98:elite")
	var repeated := EliteRosterService.select_and_reserve(123, 98, "verify_run:98:elite")
	var first_id := str(first.get("elite_id", ""))
	if first_id.is_empty() or str(repeated.get("elite_id", "")) != first_id:
		failures.append("Same encounter did not resolve to its existing unique reservation")
	if EliteRosterService.reserve(first_id, "verify_run:other:elite", 97):
		failures.append("One elite was reserved into two simultaneous encounters")
	if not EliteRosterService.confirm_reservation(first_id, "verify_run:98:elite"):
		failures.append("Elite reservation could not be confirmed")
	if not EliteRosterService.settle(first_id, "verify_run:98:elite", "escaped", {
		"floor_number": 98,
		"room_id": "elite_room",
		"weapon_snapshot": {
			"content_id": "weapon_rifle_standard",
			"weapon_instance_id": "must_not_persist",
			"content_version": 3,
		},
	}):
		failures.append("Elite escape settlement failed")
	var grown := EliteRosterService.get_record(first_id)
	var stolen := grown.get("stolen_modules", []) as Array
	if int(grown.get("level", 0)) != 2 or int(grown.get("escape_count", 0)) != 1:
		failures.append("Elite did not grow exactly once after escape: %s" % str(grown))
	if stolen.size() != 1 or str((stolen[0] as Dictionary).get("module_id", "")) != "weapon_rifle_standard":
		failures.append("Elite did not persist the stable stolen weapon content module")
	if str(stolen[0]).contains("must_not_persist"):
		failures.append("Elite archive illegally persisted the player's weapon_instance_id")

	var packed := BaseManager.data._to_dict()
	var restored := BaseData.from_dict(packed)
	if restored.elite_archive_records.size() != 12:
		failures.append("BaseData 1.7 did not round-trip all elite archive records")
	var legacy := BaseData.from_dict({"save_version": "1.6", "total_runs": 4})
	if not legacy.elite_archive_records.is_empty():
		failures.append("Legacy BaseData migration fabricated archive records before service hydration")

	var second_seed := _seed_for_floor(97, 991000)
	var second := EliteRosterService.select_and_reserve(second_seed, 97, "verify_run:97:elite")
	if str(second.get("elite_id", "")) != first_id:
		failures.append("The escaped first deployed elite did not remain eligible in its 98-96 window")
	EliteRosterService.settle(first_id, "verify_run:97:elite", "despawned")
	var injector := MonsterInjector.new()
	var floor_96_seed := _seed_for_floor(96, 445500)
	injector.set_seed(floor_96_seed)
	var generated := injector.generate_enemies({
		"type": "elite", "floor": 2, "floor_level": RoomData.FloorLevel.MEDIUM,
		"floor_number": 96, "encounter_id": "verify_run:96:elite", "seed": floor_96_seed,
	})
	if generated.size() != 1:
		failures.append("MonsterInjector did not return one unique elite config")
	else:
		var config := generated[0]
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(enemy)
		enemy.configure_from_enemy_data(config)
		var snapshot := enemy.get_state_snapshot()
		if (
			str(snapshot.get("elite_id", "")).is_empty()
			or str(snapshot.get("elite_behavior_id", "")).is_empty()
			or int(snapshot.get("elite_level", 0)) < 1
		):
			failures.append("Enemy3D did not bind the unique archive identity: %s" % str(snapshot))
		EliteRosterService.settle(
			str(snapshot.get("elite_id", "")),
			str(snapshot.get("elite_encounter_instance_id", "")),
			"despawned"
		)
		enemy.queue_free()

	BaseManager.force_save_failure_for_test = true
	var before_failed := EliteRosterService.get_all_elites()
	if EliteRosterService.reserve(first_id, "verify_failed:elite", 96):
		failures.append("Reservation reported success after atomic profile save failure")
	var after_failed := EliteRosterService.get_all_elites()
	if str((after_failed[ids.find(first_id)] as Dictionary).get("reserved_encounter_id", "")) == "verify_failed:elite":
		failures.append("Failed reservation was not rolled back in memory")
	if before_failed.size() != after_failed.size():
		failures.append("Failed reservation changed roster cardinality")

	BaseManager.force_save_failure_for_test = original_failure
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))

	if failures.is_empty():
		print("UNIQUE_ELITE_ROSTER_FLOW_OK: 12 definitions and live behaviors, reservation, growth, weapon translation, save migration and 3D binding pass")
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
