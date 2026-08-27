extends Node
## 首只正式精英：内容解耦、98—96层投放、独立模型、专属命名血条与碰撞归属。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const ELITE_SCENE := "res://assets/art/enemies/elite_3d/rift_boar_armed/runtime/enm_elite_rift_boar_armed_root_top3d_v001.tscn"
const TEMP_SAVE := "user://verification_first_elite.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()

	var all_definitions := EliteContentCatalog.get_all()
	var deployed := all_definitions.filter(func(definition: Dictionary) -> bool:
		return str(definition.get("deployment_status", "")) == EliteContentCatalog.DEPLOYED
	)
	if all_definitions.size() != 12 or deployed.size() != 1:
		failures.append("Expected 12 preserved definitions with exactly one deployed elite")
	for floor_number in [98, 97, 96]:
		var eligible := EliteContentCatalog.get_deployable_for_floor(floor_number)
		if eligible.size() != 1 or str(eligible[0].get("elite_id", "")) != "elite_rift_boar_armed":
			failures.append("Floor %d does not deploy only elite_rift_boar_armed" % floor_number)
	if not EliteContentCatalog.get_deployable_for_floor(95).is_empty():
		failures.append("The first elite leaked into the 95F boss floor")
	var selected_floors: Dictionary = {}
	for seed_value in range(30):
		selected_floors[EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", seed_value)] = true
	if selected_floors.size() != 3:
		failures.append("Run seeds do not distribute the first elite across all three eligible floors")

	var injector := MonsterInjector.new()
	var floor_98_seed := _seed_for_floor(98, 982000)
	injector.set_seed(floor_98_seed)
	var generated := injector.generate_enemies({
		"type":"elite", "floor":1, "floor_level":RoomData.FloorLevel.SHALLOW,
		"floor_number":98, "encounter_id":"first_elite:98:random_room", "seed":floor_98_seed,
	})
	if generated.size() != 1:
		failures.append("98F did not generate the first deployed elite")
	else:
		var config := generated[0]
		if str(config.get("elite_id", "")) != "elite_rift_boar_armed":
			failures.append("Generated the wrong elite identity")
		if str(config.get("presentation_scene", "")) != ELITE_SCENE:
			failures.append("Elite config did not receive the decoupled presentation scene")
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(enemy)
		enemy.configure_from_enemy_data(config)
		var snapshot := enemy.get_state_snapshot()
		var components := snapshot.get("component_snapshot", {}) as Dictionary
		if not bool(components.get("formal_elite_asset", false)):
			failures.append("EnemyAvatar3D did not load the independent elite PackedScene")
		if str(components.get("elite_presentation_asset_id", "")) != "ENM-ELITE-RIFT-BOAR-ARMED-3D":
			failures.append("Elite presentation AssetID was not preserved")
		if not bool(snapshot.get("elite_health_bar", false)):
			failures.append("Elite did not receive the special health bar")
		if str(snapshot.get("elite_health_bar_name", "")) != "背枪的裂口爬虫":
			failures.append("Elite name is missing from the overhead health bar")
		if (snapshot.get("overhead_health_bar_size", Vector2.ZERO) as Vector2).x < 2.0:
			failures.append("Elite health bar did not use the distinctive wide profile")
		var collision := snapshot.get("collision_profile", {}) as Dictionary
		var base_footprint := EnemyAvatar3D.get_footprint_profile("melee_chaser")
		if not is_equal_approx(float(collision.get("radius", 0.0)), float(base_footprint.get("radius", -1.0))):
			failures.append("Presentation asset changed the gameplay collision radius")
		var formal_scene := load(ELITE_SCENE) as PackedScene
		var formal_root := formal_scene.instantiate() as Node3D if formal_scene != null else null
		if formal_root == null:
			failures.append("Independent elite PackedScene cannot be loaded")
		else:
			if _contains_collision_object(formal_root):
				failures.append("Presentation-only elite scene illegally owns gameplay collision")
			formal_root.queue_free()
		EliteRosterService.settle(
			str(snapshot.get("elite_id", "")),
			str(snapshot.get("elite_encounter_instance_id", "")),
			"despawned"
		)
		enemy.queue_free()

	var forbidden := injector.generate_enemies({
		"type":"elite", "floor":2, "floor_level":RoomData.FloorLevel.MEDIUM,
		"floor_number":95, "encounter_id":"first_elite:95:boss", "seed":1,
	})
	if not forbidden.is_empty():
		failures.append("An incomplete elite was generated outside the 98-96 deployment window")

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
	if failures.is_empty():
		print("FIRST_ELITE_DEPLOYMENT_FLOW_OK: catalog/archive/presentation decoupling, 98-96 deployment, named elite bar and collision ownership pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _contains_collision_object(root: Node) -> bool:
	if root is CollisionObject3D or root is CollisionShape3D:
		return true
	for child in root.get_children():
		if _contains_collision_object(child):
			return true
	return false


func _seed_for_floor(floor_number: int, start: int) -> int:
	for seed_value in range(start, start + 100):
		if EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", seed_value) == floor_number:
			return seed_value
	return start
