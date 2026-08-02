extends Node

const LEVELS := [
	{
		"scene": "res://scenes/levels/IronFrontier.tscn",
		"profile": "res://data/map_themes/iron_frontier.tres",
	},
	{
		"scene": "res://scenes/levels/RustFoundry.tscn",
		"profile": "res://data/map_themes/rust_foundry.tres",
	},
	{
		"scene": "res://scenes/levels/SporeDepths.tscn",
		"profile": "res://data/map_themes/spore_depths.tres",
	},
	{
		"scene": "res://scenes/levels/AbyssArchive.tscn",
		"profile": "res://data/map_themes/abyss_archive.tres",
	},
]


func _ready() -> void:
	var failures: Array[String] = []
	var signatures: Dictionary = {}
	var scene_paths: Dictionary = {}
	for entry in LEVELS:
		var scene_path := str(entry["scene"])
		var profile_path := str(entry["profile"])
		_verify_level_scene(scene_path, profile_path, scene_paths, failures)
		_verify_theme_generation(profile_path, signatures, failures)
	if signatures.size() != LEVELS.size():
		failures.append("Theme profiles do not produce four distinct generation signatures")
	_finish(failures, signatures)


func _verify_level_scene(
	scene_path: String, profile_path: String, scene_paths: Dictionary, failures: Array[String]
) -> void:
	if scene_paths.has(scene_path):
		failures.append("Two level entries share the same scene: %s" % scene_path)
	scene_paths[scene_path] = true
	var level_scene := load(scene_path) as PackedScene
	if level_scene == null:
		failures.append("Independent level scene does not load: %s" % scene_path)
		return
	var level := level_scene.instantiate()
	var expected_profile := load(profile_path) as Resource
	if level.get("theme_profile") != expected_profile:
		failures.append("Independent level does not bind its theme profile: %s" % scene_path)
	if not level.has_method("get_room_game_mode"):
		failures.append("Independent level does not use the shared themed runtime contract: %s" % scene_path)
	level.free()


func _verify_theme_generation(
	profile_path: String, signatures: Dictionary, failures: Array[String]
) -> void:
	var profile := load(profile_path) as Resource
	if profile == null:
		failures.append("Theme profile does not load: %s" % profile_path)
		return
	var validation: Array = profile.call("validate_profile")
	if not validation.is_empty():
		failures.append("%s profile invalid: %s" % [profile_path, validation])
		return

	var manager := MapManager.new()
	var graph := manager.generate_themed_map(profile, 424242)
	var repeated_manager := MapManager.new()
	var repeated_graph := repeated_manager.generate_themed_map(profile, 424242)
	if manager.map_generator.debug_map(graph) != repeated_manager.map_generator.debug_map(repeated_graph):
		failures.append("%s is not reproducible with a fixed seed" % profile_path)

	var room_types: Array[String] = []
	var themed_npc_count := 0
	var normal_enemy_types: Dictionary = {}
	for node in graph.get_all_nodes():
		var data: RoomData = node.room_data
		room_types.append(RoomData.get_type_id_name(data.room_type))
		if data.theme_id != str(profile.get("theme_id")):
			failures.append("%s generated a room without the correct theme id" % profile_path)
			break
		if "theme:%s" % str(profile.get("theme_id")) not in data.tags:
			failures.append("%s generated a room without a theme tag" % profile_path)
			break
		for interactable in data.get_content_config().get("interactables", []):
			if interactable is Dictionary and str(interactable.get("type", "")) == "themed_npc":
				themed_npc_count += 1
		for enemy in manager.get_room_enemy_plan(node.id):
			var enemy_type := str(enemy.get("enemy_type", ""))
			if enemy_type not in ["", "boss"]:
				normal_enemy_types[enemy_type] = true

	for required_name in profile.get("required_branch_types"):
		if required_name not in room_types:
			failures.append("%s did not generate required room %s" % [profile_path, required_name])
	if themed_npc_count <= 0:
		failures.append("%s did not inject a themed NPC" % profile_path)

	var enemy_pool: Array = profile.call("get_enemy_rule", "enemy_pool", [])
	for enemy_type in normal_enemy_types:
		if enemy_type not in enemy_pool:
			failures.append("%s generated off-theme enemy %s" % [profile_path, enemy_type])

	var signature := "%s|%s|%s" % [
		profile.call("get_layout_rule", "pattern", ""),
		",".join(room_types),
		",".join(normal_enemy_types.keys()),
	]
	signatures[signature] = true
	manager.free()
	repeated_manager.free()


func _finish(failures: Array[String], signatures: Dictionary) -> void:
	if failures.is_empty():
		print("THEME_LEVEL_FRAMEWORK_OK: four independent scenes produce designed, reproducible theme rules for layouts, enemies, content, and NPCs (signatures=%d)" % signatures.size())
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
