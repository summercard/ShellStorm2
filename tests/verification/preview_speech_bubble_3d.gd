extends Node3D
## 头顶气泡视觉预览：把三种文字长度的气泡并排渲染出来，存成 PNG。
## 用途是"亲眼确认样式"（硬边倒角、随文字自适应、正对摄像机），
## 不参与自动验收，故不注册进 run_verification_suite.sh。
## 运行方式：不带 --headless，直接跑本场景。

const SAMPLE_LINES := [
	"灯亮了。",
	"灯亮了。这层还有电。",
	"还有电。有电就说明有东西在运转，这座塔还没死透。",
]
const ACTOR_SPACING_M := 3.9
const SNAPSHOT_PATH := "user://speech_bubble_preview.png"


func _ready() -> void:
	_build_environment()
	_build_camera()
	var bubbles: Array[SpeechBubble3D] = []
	var count := SAMPLE_LINES.size()
	for index in range(count):
		var x := (float(index) - float(count - 1) * 0.5) * ACTOR_SPACING_M
		bubbles.append(_build_actor_with_bubble(Vector3(x, 0.0, 0.0), SAMPLE_LINES[index]))
	# 等弹出动画（0.16s）结束再截图，否则拍到半透明中间态。
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(SNAPSHOT_PATH)
	if error != OK:
		push_error("气泡预览截图保存失败：%s" % error_string(error))
	else:
		print("SPEECH_BUBBLE_PREVIEW_OK: 已保存 %s（%d 个样本）" % [SNAPSHOT_PATH, bubbles.size()])
	get_tree().quit(0 if error == OK else 1)


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.09, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.light_energy = 1.4
	add_child(sun)


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(0.0, 5.6, 7.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.85, 0.0))
	camera.current = true


## 一个示意用的小机器人（胶囊 + 球头）+ 头顶气泡。真实角色资产不在预览范围内。
func _build_actor_with_bubble(origin: Vector3, line: String) -> SpeechBubble3D:
	var actor := Node3D.new()
	actor.name = "Actor"
	actor.position = origin
	add_child(actor)

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.60, 0.66)
	material.roughness = 0.6
	body.material_override = material
	actor.add_child(body)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.52
	head.mesh = sphere
	head.position = Vector3(0.0, 1.62, 0.0)
	head.material_override = material
	actor.add_child(head)

	var bark := CharacterBark3D.attach_to(actor, 2.55)
	bark.say_text(line, 30.0)
	return bark.get_bubble()
