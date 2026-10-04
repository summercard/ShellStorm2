extends Node
var failures: Array[String] = []
var counts: Dictionary = {}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	var injector := MonsterInjector.new()
	check(not MonsterInjector.BASE_ENEMY_TYPES.has("shielded"), "retired base is authorable")
	check(not SpawnBoxCatalog.ALLOWED_BOX_TYPES.has("shielded"), "retired box type is authorable")
	check(injector.generate_box_enemy("shielded", 1, 0).is_empty(), "retired explicit spawn accepted")
	for level in range(4):
		var pool := injector._get_available_types_for_level(level, 2)
		check("shielded" not in pool, "default random pool still shielded")
	for path in ["res://data/map_themes/rust_foundry.tres", "res://data/map_themes/abyss_archive.tres"]:
		injector.set_theme_profile(load(path))
		var pool := injector._get_available_types_for_level(1, 2)
		check("shielded" not in pool and "fat_zombie03" in pool, "theme pool replacement " + path)
	for id in SpawnBoxCatalog.all_ids():
		var box := SpawnBoxCatalog.load_box(id)
		check(not box.is_empty(), "invalid box " + id)
		for entry in box.get("spawns", []):
			check(entry.type != "shielded", "box references retired " + id)
	var tower := load("res://scenes/ExpeditionLevel01_3D.tscn").instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	for value in tower._room_by_id.values():
		var room := value as DungeonRoom3D
		var waves := tower._spawn_box_waves(room, 1, 0)
		for batch in waves:
			for data in batch:
				var kind := str(data.get("enemy_type", ""))
				check(kind != "shielded", "runtime spawned retired kind")
				counts[kind] = int(counts.get(kind, 0)) + 1
	check(int(counts.get("fat_zombie03", 0)) > 0, "expedition has no fat zombie")
	var enemy := load("res://scenes/enemies/fat_zombie03.tscn").instantiate() as Enemy3D
	add_child(enemy)
	enemy.set_physics_process(false)
	check(enemy.avatar.has_formal_normal() and enemy.max_hp == 696 and enemy.enemy_kind == "fat_zombie03", "replacement entity wrong profile")
	enemy.free()
	tower.queue_free()
	await get_tree().process_frame
	var out := "res://outputs/fat_zombie03_retirement"
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out + "/runtime.json", FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(), "failures":failures, "expedition_counts":counts}, "\t"))
	for failure in failures: push_error(failure)
	print("SHIELDED_RETIREMENT_", "OK" if failures.is_empty() else "FAILED", " ", counts)
	get_tree().quit(0 if failures.is_empty() else 1)
