extends SceneTree
## 完整隔断录制：首次交谈、三选分支、3秒转台与墙面裂口表现。

const ENCOUNTER = preload("res://assets/art/characters/npc/channel_manager/runtime/channel_manager_encounter.gd")
var output := ""
var frames := 0
var encounter: Node
var room: Node3D
var player: Node3D
var camera: Camera3D
var title: Label

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Expected output directory")
		quit(1)
		return
	output = args[0]
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("Cannot create output")
		quit(1)
		return
	call_deferred("_capture")

func tick(seconds: float) -> void:
	var count := roundi(seconds * 24.0)
	for i in range(count):
		await process_frame
		frames += 1
		await _shot()

func dialogue(seconds: float, caption: String) -> void:
	title.text = caption
	await tick(seconds)

func _capture() -> void:
	root.size = Vector2i(960, 720)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#151122")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#e3c7ff")
	world.environment.ambient_light_energy = 0.6
	root.add_child(world)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new(); floor_mesh.size = Vector2(34, 34); floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new(); floor_mat.albedo_color = Color("#45375d"); floor_mat.roughness = 0.86; floor.material_override = floor_mat
	root.add_child(floor)
	var light := OmniLight3D.new(); light.position = Vector3(2, 10, 6); light.light_energy = 8.0; light.omni_range = 25.0; light.light_color = Color("#e7c5ff"); root.add_child(light)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 10.5; camera.position = Vector3(7, 7.5, 13); root.add_child(camera); camera.look_at_from_position(camera.position, Vector3(0, 2.7, 0)); camera.make_current()
	room = Node3D.new(); root.add_child(room)
	player = Node3D.new(); player.name = "MainCharacterPreview"; room.add_child(player); player.position = Vector3(0, 0, 7)
	encounter = ENCOUNTER.new(); encounter.configure(null, room, player)
	var ui := CanvasLayer.new(); root.add_child(ui); title = Label.new(); title.position = Vector2(28, 24); title.add_theme_font_size_override("font_size", 26); title.add_theme_color_override("font_color", Color("#f7d8ff")); ui.add_child(title)
	await dialogue(2.0, "01  进入 room_09 · 频道管理者休眠")
	player.position = Vector3(0, 0, -1.7)
	await dialogue(0.8, "02  接近并按 E · 主屏先睁眼")
	encounter.interact()
	await dialogue(6.8, "03  首次对话 · 寻找主人 / 听见模糊回声")
	await dialogue(1.2, "04  选择 · 把金币交给它 / 先离开这里")
	var game_manager := root.get_node_or_null("GameManager")
	game_manager.set("currency", 1500); game_manager.emit_signal("currency_changed", 1500)
	encounter._on_pay_pressed()
	await dialogue(0.8, "05  已支付 · 进入 3 秒老虎机转台")
	await dialogue(3.0, "06  滚屏中 · 各屏独立刷新")
	await dialogue(0.75, "07  锁定结果 · 识别 / 监听 / 中继")
	camera.position = Vector3(7, 7.5, 13); camera.look_at(Vector3(0, 3.0, -4.8)); camera.size = 11.5
	await dialogue(1.8, "08  技能释放 · 墙面裂口从中心向两侧展开")
	await dialogue(1.4, "09  裂口完成 · 玩家穿越逻辑待下一轮")
	await dialogue(1.0, "10  再次对话 · 再问一句")
	encounter._on_information_pressed()
	await dialogue(4.5, "11  追加信息 · 监听区 / 中继方向")
	print("CHANNEL_MANAGER_EXPEDITION_EVENT_CAPTURE_OK ", frames, " frames")
	quit()

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.save_png(output.path_join("frame_%05d.png" % frames)) != OK:
		printerr("frame save failed")
		quit(2)
