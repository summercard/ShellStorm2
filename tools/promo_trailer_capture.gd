extends Node3D
## ShellStorm2 promotional trailer capture.
## Uses real project assets and Godot Movie Maker. This is a read-only presentation scene:
## no gameplay state, save data, or production assets are modified.

const OUT_W := 1280
const OUT_H := 720
const FPS := 30
const TOTAL_FRAMES := 3600 # 120 seconds
const INTRO_FRAMES := 150
const OUTRO_FRAMES := 180

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const BOSS_SCENE: PackedScene = preload("res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn")
const ENEMY_SCENES := [
	"res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn",
	"res://assets/art/enemies/normal_enemy_3d/melee_chaser/runtime/enm_melee_fungboar01_root_top3d.tscn",
	"res://assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn",
]
const WEAPON_SCENES := [
	"res://assets/art/weapons/weapon_3d/runtime/hair_dryer/wpn_hair_dryer_root_top3d_v001.tscn",
	"res://assets/art/weapons/weapon_3d/runtime/broom_rifle/wpn_broom_rifle_root_top3d_v001.tscn",
	"res://assets/art/weapons/weapon_3d/runtime/water_tank_blaster/wpn_water_tank_blaster_root_top3d.tscn",
]

var _frame := 0
var _camera: Camera3D
var _stage: Node3D
var _actors: Node3D
var _props: Node3D
var _lights: Node3D
var _hud: CanvasLayer
var _caption: Label
var _subcaption: Label
var _progress: ColorRect
var _accent: ColorRect
var _logo: Label
var _spawned: Array[Node] = []
var _sfx: AudioStreamPlayer
var _font: Font

func _ready() -> void:
	if Engine.get_write_movie_path() != "":
		get_window().content_scale_size = Vector2i(OUT_W, OUT_H)
		DisplayServer.window_set_size(Vector2i(OUT_W, OUT_H))
	_build_stage()
	_build_hud()
	_build_audio()
	for i in range(8):
		await RenderingServer.frame_post_draw
	print("[promo] trailer capture ready: %d frames / %dfps = %.1fs" % [TOTAL_FRAMES, FPS, float(TOTAL_FRAMES) / FPS])

func _process(_delta: float) -> void:
	if Engine.get_write_movie_path() == "":
		return
	if _frame >= TOTAL_FRAMES:
		print("[promo] done frames=%d" % _frame)
		get_tree().quit(0)
		return
	_apply_frame(_frame)
	_frame += 1

func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "TrailerStage"
	add_child(_stage)
	_actors = Node3D.new()
	_actors.name = "Actors"
	_stage.add_child(_actors)
	_props = Node3D.new()
	_props.name = "Props"
	_stage.add_child(_props)
	_lights = Node3D.new()
	_lights.name = "Lights"
	_stage.add_child(_lights)

	_camera = Camera3D.new()
	_camera.name = "TrailerCamera"
	_camera.fov = 42.0
	_camera.near = 0.05
	_camera.far = 120.0
	_camera.current = true
	_stage.add_child(_camera)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#040914")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8ba5c5")
	e.ambient_light_energy = 0.72
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.16
	env.environment = e
	_stage.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -32.0, 0.0)
	key.light_energy = 1.25
	key.light_color = Color("#ffe6c6")
	key.shadow_enabled = true
	_lights.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	rim.light_energy = 1.1
	rim.light_color = Color("#4db9ff")
	_lights.add_child(rim)
	var cyan := OmniLight3D.new()
	cyan.position = Vector3(-5.0, 3.0, 2.0)
	cyan.omni_range = 18.0
	cyan.light_energy = 6.0
	cyan.light_color = Color("#1c8bff")
	_lights.add_child(cyan)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(50.0, 50.0)
	floor.mesh = floor_mesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#111827")
	fm.roughness = 0.82
	floor.material_override = fm
	_stage.add_child(floor)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 100
	add_child(_hud)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.color = Color(0.0, 0.0, 0.0, 0.0)
	_hud.add_child(shade)
	_accent = ColorRect.new()
	_accent.position = Vector2(60, 606)
	_accent.size = Vector2(4, 55)
	_accent.color = Color("#50d9ff")
	_hud.add_child(_accent)
	_caption = Label.new()
	_caption.position = Vector2(82, 600)
	_caption.size = Vector2(1120, 48)
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color("#f6fbff"))
	_hud.add_child(_caption)
	_subcaption = Label.new()
	_subcaption.position = Vector2(84, 646)
	_subcaption.size = Vector2(1100, 30)
	_subcaption.add_theme_font_size_override("font_size", 16)
	_subcaption.add_theme_color_override("font_color", Color("#8fa8bb"))
	_hud.add_child(_subcaption)
	_logo = Label.new()
	_logo.position = Vector2(58, 42)
	_logo.size = Vector2(720, 50)
	_logo.add_theme_font_size_override("font_size", 24)
	_logo.add_theme_color_override("font_color", Color("#8de7ff"))
	_logo.text = "SHELLSTORM 2  //  弹壳风暴2"
	_hud.add_child(_logo)
	_progress = ColorRect.new()
	_progress.position = Vector2(0, 716)
	_progress.size = Vector2(1, 4)
	_progress.color = Color("#55dfff")
	_hud.add_child(_progress)

func _build_audio() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "TrailerAudio"
	add_child(_sfx)
	# The game soundtrack is intentionally not loaded here: the visual cut remains deterministic.

func _apply_frame(f: int) -> void:
	var t := float(f) / FPS
	_progress.size.x = OUT_W * clampf(float(f) / float(TOTAL_FRAMES), 0.0, 1.0)
	if f < INTRO_FRAMES:
		_intro(f)
	elif f < 720:
		_base_reveal(f)
	elif f < 1500:
		_combat(f)
	elif f < 2130:
		_expedition(f)
	elif f < 2880:
		_boss_reveal(f)
	elif f < TOTAL_FRAMES - OUTRO_FRAMES:
		_feature_montage(f)
	else:
		_outro(f)
	# Slight continuous camera drift keeps the presentation cinematic even during stage transitions.
	if is_instance_valid(_camera):
		_camera.current = true
		_camera.rotation_degrees.z = sin(t * 0.55) * 0.6

func _intro(f: int) -> void:
	_clear_actors()
	_camera.position = Vector3(0, 2.3, 11.5)
	_camera.look_at(Vector3(0, 1.4, 0), Vector3.UP)
	_logo.modulate.a = clampf(float(f) / 45.0, 0.0, 1.0)
	_caption.text = ""
	_subcaption.text = ""
	if f > 28:
		_caption.text = "弹壳风暴 2"
		_subcaption.text = "2075 · 基地生存档案"
		_caption.modulate.a = clampf(float(f - 28) / 50.0, 0.0, 1.0)
	_set_lighting(Color("#50d9ff"), 0.85)

func _base_reveal(f: int) -> void:
	if f == INTRO_FRAMES:
		_spawn_player(Vector3(0, 0, 0), 0.0)
		_spawn_prop(0, Vector3(0, 0.5, 1.3), 0.0, 0.9)
	var p := float(f - 720) / 780.0
	_camera.position = Vector3(3.8 - p * 1.3, 2.7 - p * 0.2, 5.1 - p * 0.7)
	_camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	_caption.text = "整备、改造，决定下一次出发"
	_subcaption.text = "基地 · 武器构建 · 外观装配"
	_caption.modulate.a = 1.0
	_set_lighting(Color("#66d8ff"), 1.0)

func _combat(f: int) -> void:
	if f == 720:
		_clear_actors()
		_spawn_player(Vector3(0, 0, 1.5), 0.0)
		_spawn_enemy(0, Vector3(-2.8, 0, -1.0), 0.5)
		_spawn_enemy(1, Vector3(2.5, 0, -2.0), -0.5)
		_spawn_enemy(2, Vector3(0.5, 0, -4.0), 0.0)
		_spawn_prop(1, Vector3(0.2, 0.45, 0.6), -0.15, 1.0)
	var p := float(f - 720) / 780.0
	_camera.position = Vector3(4.8 * cos(p * 2.4), 2.8 + sin(p * 2.0) * 0.3, 4.8 * sin(p * 2.4))
	_camera.look_at(Vector3(0, 0.9, -0.7), Vector3.UP)
	_caption.text = "搜寻目标，压制威胁"
	_subcaption.text = "移动射击 · 闪避 · 命中反馈 · 战斗节奏"
	_set_lighting(Color("#ff8d54") if int(f / 12) % 2 == 0 else Color("#55dfff"), 1.35)

func _expedition(f: int) -> void:
	if f == 1500:
		_clear_actors()
		_spawn_player(Vector3(0, 0, 1.2), 0.0)
		_spawn_enemy(0, Vector3(-3.0, 0, -2.0), 0.4)
		_spawn_enemy(2, Vector3(3.4, 0, -3.8), -0.6)
	var p := float(f - 1500) / 630.0
	_camera.position = Vector3(5.8 - p * 1.8, 3.5 - p * 0.7, 6.8 - p * 2.2)
	_camera.look_at(Vector3(0, 1.0, -1.0), Vector3.UP)
	_caption.text = "每次进入，都是一条新的路线"
	_subcaption.text = "远征 · 随机房间 · 搜打撤 · 高价值战利品"
	_set_lighting(Color("#d5a46e"), 1.1)

func _boss_reveal(f: int) -> void:
	if f == 2130:
		_clear_actors()
		_spawn_player(Vector3(-4.0, 0, 3.2), 0.0)
		var boss := BOSS_SCENE.instantiate()
		boss.position = Vector3(0, 0, -1.4)
		boss.scale = Vector3.ONE * 0.82
		_actors.add_child(boss)
		_spawned.append(boss)
	var p := float(f - 2130) / 750.0
	_camera.position = Vector3(6.8 - p * 2.4, 3.7 - p * 0.5, 7.8 - p * 2.1)
	_camera.look_at(Vector3(0, 1.5, -1.2), Vector3.UP)
	_caption.text = "真正的考验，才刚刚开始"
	_subcaption.text = "Boss战 · 多阶段攻击 · 观察、应对、反击"
	_set_lighting(Color("#ff4f7c") if int(f / 18) % 2 == 0 else Color("#5e7dff"), 1.5)

func _feature_montage(f: int) -> void:
	var local := f - 2880
	var shot := int(local / 120) % 6
	if local % 120 == 0:
		_clear_actors()
		_spawn_player(Vector3(0, 0, 0), 0.0)
		if shot == 0:
			_spawn_prop(2, Vector3(0, 0.5, -1.0), 0.0, 1.0)
		elif shot == 1:
			_spawn_enemy(1, Vector3(0, 0, -2.0), 0.0)
		elif shot == 2:
			_spawn_enemy(0, Vector3(0, 0, -2.0), 0.0)
		elif shot == 3:
			_spawn_prop(0, Vector3(0, 0.5, -1.0), 0.0, 1.15)
		elif shot == 4:
			_spawn_enemy(2, Vector3(0, 0, -2.0), 0.0)
		else:
			_spawn_prop(1, Vector3(0, 0.5, -1.0), 0.0, 1.05)
	_camera.position = Vector3(3.8 * cos(float(local) / 150.0), 2.3, 3.8 * sin(float(local) / 150.0))
	_camera.look_at(Vector3(0, 1.0, -0.4), Vector3.UP)
	var captions := ["武器，不止一种答案", "敌人，会记住你的每一次失误", "资源有限，选择必须有代价", "改造你的装备，建立自己的打法", "看清威胁，抓住窗口", "带得走的战利品，才是真正的成长"]
	_caption.text = captions[shot]
	_subcaption.text = "弹壳风暴 2 · 你的路线，由你决定"
	_set_lighting(Color("#55dfff") if shot % 2 == 0 else Color("#ffb86b"), 1.15)

func _outro(f: int) -> void:
	_clear_actors()
	_camera.position = Vector3(0, 2.3, 12.0)
	_camera.look_at(Vector3(0, 1.4, 0), Vector3.UP)
	_logo.text = "SHELLSTORM 2  //  弹壳风暴2"
	_caption.text = "现在，进入下一次远征"
	_subcaption.text = "探索 · 战斗 · 带着战利品活着回来"
	var alpha := clampf(float(f - (TOTAL_FRAMES - OUTRO_FRAMES)) / 45.0, 0.0, 1.0)
	_caption.modulate.a = alpha
	_subcaption.modulate.a = alpha
	_logo.modulate.a = alpha
	_set_lighting(Color("#50d9ff"), 0.8)

func _spawn_player(pos: Vector3, yaw: float) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.position = pos
	player.rotation.y = yaw
	_actors.add_child(player)
	# Player3D 是正式玩法预制体，内含自己的俯视摄像机；宣传片必须由
	# TrailerCamera 统一接管镜头，避免运行时摄像机覆盖宣传片机位。
	_deactivate_actor_cameras(player)
	player.set_process(false)
	player.set_physics_process(false)
	_spawned.append(player)

func _spawn_enemy(index: int, pos: Vector3, yaw: float) -> void:
	var scene := load(ENEMY_SCENES[clampi(index, 0, ENEMY_SCENES.size() - 1)]) as PackedScene
	if scene == null:
		return
	var enemy := scene.instantiate()
	enemy.position = pos
	enemy.rotation.y = yaw
	_actors.add_child(enemy)
	_deactivate_actor_cameras(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	_spawned.append(enemy)

func _spawn_prop(index: int, pos: Vector3, yaw: float, scale_value: float) -> void:
	var scene := load(WEAPON_SCENES[clampi(index, 0, WEAPON_SCENES.size() - 1)]) as PackedScene
	if scene == null:
		return
	var prop := scene.instantiate()
	prop.position = pos
	prop.rotation.y = yaw
	prop.scale = Vector3.ONE * scale_value
	_props.add_child(prop)
	_deactivate_actor_cameras(prop)
	_spawned.append(prop)

func _deactivate_actor_cameras(root: Node) -> void:
	for node in root.find_children("*", "Camera3D", true, false):
		var camera := node as Camera3D
		if camera != null:
			camera.current = false
			camera.process_mode = Node.PROCESS_MODE_DISABLED

func _clear_actors() -> void:
	for item in _spawned:
		if is_instance_valid(item):
			item.queue_free()
	_spawned.clear()

func _set_lighting(color: Color, energy: float) -> void:
	for child in _lights.get_children():
		if child is OmniLight3D:
			child.light_color = color
			child.light_energy = energy * 5.0
		elif child is DirectionalLight3D:
			child.light_color = color.lerp(Color.WHITE, 0.45)
			child.light_energy = energy
