extends Node3D
## 目视验收：把调试面板的「镜头雾气」页渲染出来存成 PNG。
##
## ⚠️ 必须在**带真实渲染器**的窗口下跑（`--headless` 是 dummy 渲染器，取不到画面）：
##   godot --path . res://tests/verification/preview_debug_camera_fog_panel.tscn
## 产物：outputs/debug_camera_fog_panel_preview.png

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const PANEL_PATH := "FlashlightTweakerLayer/FlashlightColorTweaker"
const OUTPUT_PATH := "res://outputs/debug_camera_fog_panel_preview.png"
const VIEWPORT_SIZE := Vector2i(1280, 900)


func _ready() -> void:
	await _run()


func _run() -> void:
	get_window().size = VIEWPORT_SIZE
	DisplayServer.window_set_size(VIEWPORT_SIZE)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.10, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.46, 0.52)
	environment.ambient_light_energy = 0.6
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.40, 0.48, 0.55)
	environment.fog_density = 0.030
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.009
	var world_environment := WorldEnvironment.new()
	world_environment.name = "PreviewEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.15
	add_child(sun)

	_build_reference_geometry()

	# configure() 必须在 add_child() 之前；太阳要先入树，否则会撞
	# GameplaySpatialRegistry3D 的 "!is_inside_tree()"。
	var atmosphere := TowerAtmosphere3D.new()
	atmosphere.name = "PreviewAtmosphere"
	atmosphere.legacy_city_silhouette_enabled = false
	atmosphere.background_music_enabled = false
	atmosphere.configure(environment, sun)
	add_child(atmosphere)

	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	var panel := player.get_node_or_null(PANEL_PATH) as FlashlightColorTweaker
	if panel == null:
		printerr("PREVIEW_DEBUG_CAMERA_FOG_PANEL_FAILED panel_missing")
		get_tree().quit(1)
		return

	# 走一遍三条新链路，让读数不是空的。
	panel._on_camera_pitch(Player3D.DEBUG_CAMERA_PITCH_STEP_DEG)
	panel._on_camera_dolly(Player3D.DEBUG_CAMERA_TRAILING_STEP_M)
	panel._on_camera_pan(FlashlightColorTweaker.CAMERA_PAN_UP)
	panel._select_tab(FlashlightColorTweaker.TabId.CAMERA_FOG)
	panel.visible = true

	for _frame in range(10):
		await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		printerr("PREVIEW_DEBUG_CAMERA_FOG_PANEL_FAILED save_error=%d" % error)
		get_tree().quit(1)
		return
	print("PREVIEW_DEBUG_CAMERA_FOG_PANEL_OK -> %s" % OUTPUT_PATH)
	get_tree().quit(0)


func _build_reference_geometry() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.24, 0.26, 0.30)
	floor_mesh.material = floor_material
	var floor_instance := MeshInstance3D.new()
	floor_instance.name = "PreviewFloor"
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(0.0, 0.0, -3.0)
	add_child(floor_instance)

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.2, 2.4, 1.2)
	var box_material := StandardMaterial3D.new()
	box_material.albedo_color = Color(0.55, 0.32, 0.26)
	box_mesh.material = box_material
	for index in range(4):
		var box_instance := MeshInstance3D.new()
		box_instance.name = "PreviewBox%d" % index
		box_instance.mesh = box_mesh
		box_instance.position = Vector3(-3.0 + float(index) * 2.0, 1.2, -6.0 - float(index % 2) * 2.0)
		add_child(box_instance)
