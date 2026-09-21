extends Node3D
## 底栏对话系统视觉预览：渲染一条系统提示并存成 PNG。
## 用途是"亲眼确认版式与打字机"，不参与自动验收，故不注册进 run_verification_suite.sh。
## 运行方式：不带 --headless。

const SNAPSHOT_PATH := "user://dialogue_ui_preview.png"
const PREVIEW_LINE := "欢迎回到基地。"
const TYPING_WAIT_S := 1.5


func _ready() -> void:
	_build_scene()
	var ui := get_node_or_null("/root/DialogueUI")
	if ui == null:
		push_error("DIALOGUE_UI_PREVIEW_FAIL: DialogueUI autoload 缺失")
		get_tree().quit(1)
		return
	# auto_advance_sec = 0 → 等玩家推进（预览要停在屏幕上给我们截图）
	ui.call("announce", PREVIEW_LINE, 0.0)
	await get_tree().create_timer(TYPING_WAIT_S).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(SNAPSHOT_PATH)
	if error != OK:
		push_error("DIALOGUE_UI_PREVIEW_FAIL: 截图保存失败 %s" % error_string(error))
	else:
		print("DIALOGUE_UI_PREVIEW_OK: 已保存 %s" % SNAPSHOT_PATH)
	get_tree().quit(0 if error == OK else 1)


## 造一个"像游戏画面"的暗场景，用来检验底栏在真实画面上是否压得住、读得清。
func _build_scene() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.07, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.2
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.17, 0.19)
	floor_material.roughness = 0.9
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)

	# 几个立方体当"基地设施"，让底栏背后不是纯色，便于判断可读性。
	var accents := [
		[Vector3(-4.2, 1.0, -2.0), Color(0.20, 0.42, 0.48)],
		[Vector3(0.0, 1.4, -4.5), Color(0.28, 0.36, 0.44)],
		[Vector3(4.4, 0.8, -1.2), Color(0.34, 0.30, 0.26)],
	]
	for accent in accents:
		var box := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(2.4, 2.0, 2.4)
		box.mesh = cube
		var material := StandardMaterial3D.new()
		material.albedo_color = accent[1]
		material.roughness = 0.7
		box.material_override = material
		box.position = accent[0]
		add_child(box)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.6, 7.2)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, -2.0))
	camera.current = true
