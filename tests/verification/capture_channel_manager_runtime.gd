extends SceneTree
## Real-render checks: --script <this> -- <output-directory> [--video]
const NPC = preload("res://assets/art/characters/npc/channel_manager/runtime/channel_manager_runtime.tscn")
var actor: Node3D
var camera: Camera3D
var target: Node3D
var output := ""
var video := false
var video_dir := ""
var video_frame := 0
var caption: Label
const VIDEO_FPS := 24

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args.size() > 2 or (args.size() == 2 and args[1] != "--video"):
		printerr("Expected output directory and optional --video")
		quit(1)
		return
	output = args[0]
	video = args.has("--video")
	if video:
		video_dir = output.path_join("video_frames_v002")
		if DirAccess.make_dir_recursive_absolute(video_dir) != OK:
			printerr("Cannot create video frame directory: " + video_dir)
			quit(1)
			return
	call_deferred("_capture_all")

func _capture_all() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	root.size = Vector2i(864, 920)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#221c38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#e8c4ef")
	environment.environment.ambient_light_energy = 0.44
	stage.add_child(environment)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(60, 60)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#4a3b62"); mat.roughness = 0.89
	ground.material_override = mat
	stage.add_child(ground)
	_light(stage, Vector3(-3, 10, 5), Color("#ffe1d8"), 4.5)
	_light(stage, Vector3(1, 6, -5), Color("#9634ff"), 3.5)
	_light(stage, Vector3(6, 6, 2), Color("#ffaa9f"), 1.7)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.6
	stage.add_child(camera)
	camera.position = Vector3(5, 11, 16)
	camera.look_at(Vector3(0, 2.75, 0))
	camera.make_current()
	actor = NPC.instantiate()
	actor.auto_activate = false; actor.rng_seed = 76432
	stage.add_child(actor)
	actor.set_process(false)
	var anim := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if video:
		await _capture_video()
		return
	await _shot("09_Godot_sleep")
	actor.activate()
	_tick(0.92)
	await _shot("10_Godot_activate")
	_tick(1.58)
	target = Node3D.new(); stage.add_child(target); target.position = Vector3(1.7, 4.8, 4.5); actor.set_observer(target)
	_tick(0.75)
	await _shot("11_Godot_tracking")
	actor.set_observer(null)
	actor.begin_talk("happy", 0.9); _tick(0.25)
	await _shot("12_Godot_talk_happy")
	_tick(0.67)
	actor.trigger_skill("识别"); _tick(0.18)
	await _shot("13_Godot_warning")
	_tick(0.57)
	await _shot("14_Godot_rolling")
	_tick(0.83)
	await _shot("15_Godot_lock_white")
	_tick(0.75)
	camera.position = Vector3(9, 10, 14); camera.look_at(Vector3(0.1, 3.2, 2.5)); camera.size = 10.3
	await _shot("16_Godot_release_beam")
	_tick(1.1)
	camera.position = Vector3(5, 11, 16); camera.look_at(Vector3(0, 2.75, 0)); camera.size = 8.6
	actor.trigger_skill("监听"); _tick(1.58)
	await _shot("17_Godot_lock_purple")
	_tick(1.5); actor.trigger_skill("中继"); _tick(1.58)
	await _shot("18_Godot_lock_blue")
	print("CHANNEL_MANAGER_RENDER_OK")
	quit()

func _capture_video() -> void:
	root.size = Vector2i(768, 816)
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var panel := ColorRect.new()
	panel.position = Vector2(20, 20); panel.size = Vector2(728, 67)
	panel.color = Color(0.07, 0.03, 0.13, 0.85)
	ui.add_child(panel)
	caption = Label.new()
	caption.position = Vector2(19, 14)
	caption.add_theme_font_size_override("font_size", 25)
	panel.add_child(caption)
	actor.set_observer(null)
	await _record(1.15, "01   休眠 · 暗雪花")
	actor.activate()
	await _record(2.55, "02   激活 · 主屏睁眼 / 线缆撑起")
	target = Node3D.new(); actor.get_parent().add_child(target); actor.set_observer(target)
	await _record(3.0, "03   激活待机 · 眼睛追随 / 雪花换台", true)
	actor.set_observer(null)
	for pair: Array in [["normal", "普通"], ["happy", "开心"], ["angry", "愤怒"], ["scheme", "阴谋"]]:
		actor.begin_talk(pair[0], 1.65)
		await _record(1.75, "04   说话 · " + pair[1])
	actor.trigger_skill("识别")
	await _record(0.46, "05   技能前摇 · 全屏警告")
	await _record(0.96, "06   技能前摇 · 独立滚屏")
	await _record(0.58, "07   锁定 · 识别 / 白底")
	camera.position = Vector3(9, 10, 14); camera.look_at(Vector3(0.1, 3.2, 2.5)); camera.size = 10.3
	await _record(1.05, "08   释放 · 主屏前倾与光束")
	camera.position = Vector3(5, 11, 16); camera.look_at(Vector3(0, 2.75, 0)); camera.size = 8.6
	actor.trigger_skill("监听")
	await _record(1.43, "09   再抽一次 · 监听")
	await _record(0.58, "10   锁定 · 监听 / 紫底")
	_tick(1.15)
	actor.trigger_skill("中继")
	await _record(1.43, "11   再抽一次 · 中继")
	await _record(0.58, "12   锁定 · 中继 / 蓝底")
	print("CHANNEL_MANAGER_VIDEO_OK ", video_frame, " frames @ ", VIDEO_FPS)
	quit()

func _record(seconds: float, title: String, sweep := false) -> void:
	caption.text = title
	var count := roundi(seconds * float(VIDEO_FPS))
	for n in range(count):
		if sweep:
			target.position = Vector3(1.5 * sin(TAU * float(n) / float(count)), 3.4, 4.6)
		_tick(1.0 / float(VIDEO_FPS))
		await _shot("frame_%05d" % video_frame, video_dir)
		video_frame += 1
		if video_frame % 96 == 0:
			print("CHANNEL_MANAGER_VIDEO_FRAME ", video_frame)

func _light(stage: Node3D, loc: Vector3, color: Color, strength: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color; l.light_energy = strength; l.omni_range = 24.0; l.shadow_enabled = true
	stage.add_child(l); l.position = loc

func _tick(seconds: float) -> void:
	var anim := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for j in range(ceili(seconds * 120.0)):
		anim.advance(1.0 / 120.0)
		actor.step_presentation(1.0 / 120.0)

func _shot(title: String, folder := "") -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var destination := output if folder.is_empty() else folder
	if img == null or img.is_empty() or img.save_png(destination.path_join(title + ".png")) != OK:
		printerr("Capture failed: " + title)
		quit(2)
