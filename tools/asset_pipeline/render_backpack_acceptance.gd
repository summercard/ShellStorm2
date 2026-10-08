extends Node
## 原生Godot渲染：四方向同尺度三款背包、真实玩家背负及实际UI图标。

const CONTRACT = preload("res://tests/verification/backpack_asset_contract.gd")
const PLAYER = preload("res://scenes/Player3D.tscn")
const ICON = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
const OUT := "res://outputs/backpack_head_fit_20261008/"
var failures: Array[String] = []
var stage: Node3D
var camera: Camera3D
var report: Dictionary = {}

var root: Window

func _ready() -> void:
	root = get_tree().root
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("必须使用真实渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1440, 900)
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.17, 0.19, 0.24)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.91, 1.0)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	stage.add_child(world)
	for settings in [[Vector3(-40, -30, 0), 0.9], [Vector3(-30, 135, 0), 0.4]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = settings[0]
		light.light_energy = settings[1]
		stage.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.65
	stage.add_child(camera)
	var group := Node3D.new()
	stage.add_child(group)
	for i in 3:
		var slots := [2, 4, 8][i] as int
		var item := ItemRegistry.get_instance().get_item("equipment_backpack_%d" % slots)
		var model := ItemModelFactory3D.create_model(item)
		group.add_child(model)
		model.position.x = (i-1)*1.25
		CONTRACT.verify(model, slots, failures)
	for view in [["front", Vector3(0, 0.32, 6.5)], ["three_quarter", Vector3(3.0, 1.35, 6.5)], ["back", Vector3(0, 0.32, -6.5)], ["side", Vector3(6.5, 0.32, 0)], ["top", Vector3(0, 5.8, 0.01)]]:
		camera.size = 3.1
		camera.look_at_from_position(view[1], Vector3.ZERO)
		await _capture("models_" + str(view[0]) + ".png")
	group.queue_free()
	await get_tree().process_frame
	var players: Array[Player3D] = []
	for i in 3:
		var p := PLAYER.instantiate() as Player3D
		p.start_with_weapon = false
		stage.add_child(p)
		p.position.x = (i-1)*1.15
		p.set_physics_process(false)
		var slots := [2,4,8][i] as int
		var result := p.equip_backpack_item(ItemRegistry.get_instance().get_item("equipment_backpack_%d" % slots))
		if not bool(result.get("success", false)):
			failures.append("玩家装备失败")
		players.append(p)
	await get_tree().process_frame
	report["worn_measurements"] = []
	for p in players:
		p.process_mode = Node.PROCESS_MODE_DISABLED
		var model := p.get("_backpack_model") as Node3D
		var socket := p.avatar.get_backpack_socket()
		if model == null or model.get_parent() != socket:
			failures.append("背负未挂到现有BackpackSocket")
		if model != null and not is_equal_approx(model.scale.x, 0.68):
			failures.append("背负显示缩放未使用已验收的0.68")
		var slots := int(model.get_meta("extra_slots"))
		report["worn_measurements"].append(CONTRACT.measure_worn(p, slots, failures, not "--baseline" in OS.get_cmdline_user_args()))
		if socket.global_transform.basis.z.normalized().dot((socket.global_position-p.global_position).normalized()) < 0:
			failures.append("背包正面没有朝离开角色身体的方向")
	camera.make_current()
	camera.size = 3.4
	for view in [["front", Vector3(0, 1.0, 7.0), 0.0], ["side", Vector3(7.0, 1.0, 0), PI * 0.5], ["back", Vector3(0, 1.0, -7.0), PI]]:
		var view_name: String = view[0]
		var view_position: Vector3 = view[1]
		var view_yaw: float = view[2]
		for i in players.size():
			var p := players[i]
			p.position = Vector3((i-1)*1.55, 0, 0) if view_name != "side" else Vector3(0, 0, (i-1)*1.55)
			p.rotation.y = view_yaw
			p.get_node("AimCursor").hide()
			p.avatar.visual_root.rotation.y = 0.0
		camera.size = 3.35
		camera.look_at_from_position(view_position, Vector3(0, 0.72, 0))
		await _capture("worn_" + view_name + ".png")
	for pose in [["idle", 0.0], ["unarmed_moving_forward", 0.25], ["hurt", 0.125], ["dashing", 0.5], ["dead", 0.4], ["landing", 0.5]]:
		for i in players.size():
			var p := players[i]
			p.position = Vector3((i-1)*1.55, 0, 0)
			p.rotation.y = 0.0
			p.get_node("AimCursor").hide()
			p.avatar.visual_root.rotation.y = 0.0
			var motion: CharacterMotionLibrary3D = p.avatar.get("_authored_motion")
			p.avatar.set("_state", str(pose[0]))
			motion.pose_lock_enabled = true
			motion.pose_lock_phase = float(pose[1])
			motion.apply(p.avatar, 1.0)
		camera.size = 3.2
		camera.look_at_from_position(Vector3(0, 1.0, 7), Vector3(0, 0.72, 0))
		await _capture("fit_" + str(pose[0]) + "_front.png")
	for p in players: p.queue_free()
	await get_tree().process_frame
	var sheet := Control.new()
	root.add_child(sheet)
	var bg := ColorRect.new()
	bg.color = Color(0.13,0.15,0.19)
	bg.size = Vector2(1440,900)
	sheet.add_child(bg)
	for i in 3:
		var label := Label.new()
		label.text = ["SMALL / 2", "MEDIUM / 4", "LARGE / 8"][i]
		label.position = Vector2(255+i*350,190)
		label.add_theme_font_size_override("font_size", 24)
		sheet.add_child(label)
		var icon := ICON.instantiate() as ItemModelIcon3D
		icon.position = Vector2(180+i*350,290)
		icon.size = Vector2(280,280)
		sheet.add_child(icon)
		icon.configure(ItemRegistry.get_instance().get_item("equipment_backpack_%d" % [2,4,8][i]))
	await _capture("ui_icons.png")
	report["failures"] = failures
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["driver"] = DisplayServer.get_name()
	report["passed"] = failures.is_empty()
	var file := FileAccess.open(OUT+"runtime_render_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	sheet.queue_free()
	stage.queue_free()
	await get_tree().process_frame
	if not failures.is_empty():
		for failure in failures: push_error(failure)
	print("BACKPACK_RENDER_ACCEPTANCE_", "OK" if failures.is_empty() else "FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(filename: String) -> void:
	camera.make_current()
	for frame in 4: await get_tree().process_frame
	if root.get_camera_3d() != camera:
		failures.append("截图相机被其他玩家相机抢占：" + filename)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(OUT+filename)
	if code != OK: failures.append("截图保存失败："+filename)
	report[filename] = {"width": image.get_width(), "height": image.get_height(), "save_exit": code}
