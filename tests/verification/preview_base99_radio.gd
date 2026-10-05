extends Node3D
## 真渲染收音机近景：正式床头柜Prefab + 正式radioPrefab + 桌面摆位。

const NIGHTSTAND_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/loft_nightstand/loft_nightstand_root_top3d.tscn"
const RADIO_PATH := "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"
const OUTPUT_PATH := "res://outputs/base99_radio_v001/base99_radio_nightstand_runtime.png"

func _ready() -> void:
	var nightstand_scene := load(NIGHTSTAND_PATH) as PackedScene
	var radio_scene := load(RADIO_PATH) as PackedScene
	if nightstand_scene == null or radio_scene == null:
		push_error("BASE99_RADIO_RENDER_FAIL: 正式桌子或收音机Prefab加载失败")
		get_tree().quit(1)
		return
	var nightstand := nightstand_scene.instantiate()
	add_child(nightstand)
	var radio := radio_scene.instantiate() as Base99Radio3D
	radio.position = Vector3(-3.20, 7.25, -10.88)
	radio.rotation.y = deg_to_rad(20.0)
	add_child(radio)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.045, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.58, 0.72)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var key_light := OmniLight3D.new()
	key_light.position = Vector3(-4.6, 9.0, -6.0)
	key_light.light_color = Color(0.55, 0.72, 1.0)
	key_light.light_energy = 8.0
	key_light.omni_range = 8.0
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-1.8, 8.4, -10.0)
	fill_light.light_color = Color(1.0, 0.3, 0.72)
	fill_light.light_energy = 4.0
	fill_light.omni_range = 5.0
	add_child(fill_light)

	var camera := Camera3D.new()
	camera.fov = 47.0
	camera.position = Vector3(-4.6, 8.35, -8.85)
	add_child(camera)
	camera.look_at(Vector3(-3.20, 7.35, -10.88), Vector3.UP)
	camera.current = true

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	radio.set_radio_state("a")
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("BASE99_RADIO_RENDER_FAIL: 视口纹理为空")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/base99_radio_v001"))
	if image.save_png(OUTPUT_PATH) != OK:
		push_error("BASE99_RADIO_RENDER_FAIL: PNG写入失败")
		get_tree().quit(1)
		return
	print("BASE99_RADIO_RENDER_OK: "+OUTPUT_PATH)
	get_tree().quit(0)
