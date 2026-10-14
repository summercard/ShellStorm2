extends Node
## 修复成品实拍：三档背包走正式装备链路（equip_backpack_item + 运行时同步），
## 输出前 / 侧 / 后 / 后三分之四四个机位，并在画面顶部标注槽位。
## 只读预览，不改产品代码。

const PLAYER = preload("res://scenes/Player3D.tscn")
const OUT := "res://outputs/backpack_worn_fix_20261014/"

var root: Window
var stage: Node3D
var camera: Camera3D
var sheet: Control


func _ready() -> void:
	root = get_tree().root
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("必须使用真实渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1500, 900)
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.17, 0.19, 0.24)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.91, 1.0)
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	stage.add_child(world)
	for settings in [[Vector3(-40, -30, 0), 0.95], [Vector3(-30, 135, 0), 0.45]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = settings[0]
		light.light_energy = settings[1]
		stage.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.make_current()
	stage.add_child(camera)

	sheet = Control.new()
	root.add_child(sheet)
	for label_index in 3:
		var label := Label.new()
		label.text = ["2 槽 / SMALL", "4 槽 / MEDIUM", "8 槽 / LARGE"][label_index]
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		label.position = Vector2(560 + (label_index - 1) * 110, 828)
		sheet.add_child(label)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
	title.position = Vector2(60, 40)
	sheet.add_child(title)

	var players: Array[Player3D] = []
	for i in 3:
		var p := PLAYER.instantiate() as Player3D
		p.start_with_weapon = false
		stage.add_child(p)
		p.set_physics_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		p.set_physics_process(false)
		p.position = Vector3((i - 1) * 1.08, 0, 0)
		p.get_node("AimCursor").hide()
		p.equip_backpack_item(ItemRegistry.get_instance().get_item("equipment_backpack_%d" % [2, 4, 8][i]))
		players.append(p)
	for _f in 20:
		await get_tree().process_frame
	# 冻结 idle 首帧，三档同相位可比
	for p in players:
		var motion: CharacterMotionLibrary3D = p.avatar.get("_authored_motion")
		p.avatar.set("_state", "idle")
		motion.pose_lock_enabled = true
		motion.pose_lock_phase = 0.0
		motion.apply(p.avatar, 1.0)
		p.avatar.body.force_update_transform()
		p.call("_sync_backpack_body_follow")
		p.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame

	for view in [
		{"name": "back", "pos": Vector3(0, 0.85, -7.0), "title": "修复后 · 背后机位（背包回到背面）"},
		{"name": "three_quarter", "pos": Vector3(4.4, 1.05, -5.2), "title": "修复后 · 后三分之四"},
		{"name": "side", "pos": Vector3(7.0, 0.85, 0.0), "title": "修复后 · 侧视（贴背不穿躯干）"},
		{"name": "front", "pos": Vector3(0, 0.85, 7.0), "title": "修复后 · 正面（胸前不再有包）"},
	]:
		title.text = str(view["title"])
		camera.size = 3.05
		camera.look_at_from_position(view["pos"], Vector3(0, 0.62, 0))
		await _capture("worn_%s.png" % str(view["name"]))
	for p in players:
		p.queue_free()
	sheet.queue_free()
	stage.queue_free()
	await get_tree().process_frame
	print("BACKPACK_WORN_FINAL_RENDER_DONE")
	get_tree().quit(0)


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	camera.make_current()
	for _f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(OUT + filename)
	if code != OK:
		push_error("截图保存失败：" + filename)
