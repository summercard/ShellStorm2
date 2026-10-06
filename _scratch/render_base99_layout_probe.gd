extends Node3D

const LAYOUT_PATH: String = "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"
const OUTPUT_PATH: String = "res://_scratch/base99_layout_runtime_probe.png"

func _ready() -> void:
	var packed: PackedScene = load(LAYOUT_PATH) as PackedScene
	if packed == null:
		push_error("LAYOUT_RENDER_FAIL: scene missing")
		get_tree().quit(1)
		return
	var layout: Node3D = packed.instantiate() as Node3D
	add_child(layout)
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.58, 0.72)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(-3.0, 15.0, -9.0)
	fill.light_energy = 12.0
	fill.omni_range = 30.0
	fill.light_color = Color(0.55, 0.72, 1.0)
	add_child(fill)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 55.0
	camera.position = Vector3(0.0, 29.0, 1.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 6.5, -6.0), Vector3.FORWARD)
	camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("LAYOUT_RENDER_FAIL: empty image")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_scratch"))
	var err: Error = image.save_png(OUTPUT_PATH)
	if err != OK:
		push_error("LAYOUT_RENDER_FAIL: png error %s" % err)
		get_tree().quit(1)
		return
	print("LAYOUT_RENDER_OK: %s" % OUTPUT_PATH)
	get_tree().quit(0)
