extends Node3D

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const OUTPUT := "res://outputs/verification/elite_rift_boar_20260827/elite_rift_boar_game_view_v001.png"
const TEMP_SAVE := "user://verification_first_elite_visual.json"


func _ready() -> void:
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()
	_build_stage()
	var injector := MonsterInjector.new()
	var elite_seed := 20260827
	while EliteContentCatalog.get_selected_floor_for_seed("elite_rift_boar_armed", elite_seed) != 98:
		elite_seed += 1
	var configs := injector.generate_enemies({
		"type":"elite", "floor":1, "floor_level":RoomData.FloorLevel.SHALLOW,
		"floor_number":98, "encounter_id":"visual:98:elite", "seed":elite_seed,
	})
	if configs.size() != 1:
		push_error("Visual verification could not generate the first elite")
		get_tree().quit(1)
		return
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy)
	enemy.position = Vector3.ZERO
	enemy.configure_from_enemy_data(configs[0])
	enemy.set_physics_process(false)
	for _frame in range(8):
		await get_tree().process_frame
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(output_path) if image != null and not image.is_empty() else ERR_CANT_CREATE
	var snapshot := enemy.get_state_snapshot()
	EliteRosterService.settle(
		str(snapshot.get("elite_id", "")),
		str(snapshot.get("elite_encounter_instance_id", "")),
		"despawned"
	)
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
	if result == OK:
		print("FIRST_ELITE_VISUAL_OK: %s" % output_path)
		get_tree().quit(0)
	else:
		push_error("Could not save first elite visual preview")
		get_tree().quit(1)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.40, 0.55)
	env.ambient_light_energy = 0.82
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -28, 0)
	sun.light_color = Color(1.0, 0.78, 0.58)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.4, 3.6, 1.7)
	rim.light_color = Color(0.05, 0.72, 1.0)
	rim.light_energy = 7.0
	rim.omni_range = 8.0
	add_child(rim)
	var camera := Camera3D.new()
	camera.position = Vector3(4.2, 4.0, 5.6)
	camera.look_at_from_position(camera.position, Vector3(0, 0.9, 0), Vector3.UP)
	camera.fov = 40.0
	camera.current = true
	add_child(camera)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9.0, 9.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.065, 0.075, 0.095)
	floor_material.metallic = 0.18
	floor_material.roughness = 0.72
	plane.material = floor_material
	floor_mesh.mesh = plane
	add_child(floor_mesh)
