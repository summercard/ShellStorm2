extends Node3D
## 一次性取证工具：玩家角色 + 怪物 + 飞行中的子弹，真实渲染截图。
## 用途：2026-11-05 业主「子弹尾迹先隐藏」的效果确认 —— 看尾巴没了之后画面成什么样。
##
## 用法（**必须带窗口，不能用 --headless**）：
##   godot --path . res://tools/_bullet_trail_shot.tscn -- <全景图路径> <特写图路径>
##
## 为什么是真的：玩家是 `scenes/Player3D.tscn`、怪是 `Enemy3D`、枪是 `WeaponModel3D`
## 走真实 `_fire_now()` 生成 `Projectile3D`，弹体是 `VfxBulletBody3D` 子类走 `visual_id` 路由。
##
## 只有两件事是人为的：
##   ① 弹体物理关掉、位置手动摆 —— 真实弹速 23 m/s，从枪口到怪只要 0.26 秒，
##      60fps 下只有十几帧，靠等帧根本抓不准；physics 里 `velocity = direction * speed`
##      逐帧重算，改 `speed` 会被下一帧覆盖，所以只能关物理摆位。
##   ② 怪物物理冻结（本工具不做 AI，只要站桩）。
##
## 特写对照的第二格把尾巴**手动点亮**：只改这一次实例的 `visible`，
## 不碰 `GameDesignConfig.BULLET_TRAIL_VISIBLE`（那是产品开关，const）。

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)

const ENEMY_KIND := "melee_chaser"
const PLAYER_POS := Vector3(0.0, 0.0, 0.0)
## 4.6m 而不是 6m：机位能同时压紧两侧又容得下怪物头顶血条，主体占比更大。
const ENEMY_POS := Vector3(0.0, 0.0, -4.6)
## 弹道上取的三个比例位置（0 = 枪口，1 = 怪物身前）。
const TRACK_T := [0.30, 0.58, 0.84]

var _cam: Camera3D
var _player: Player3D
var _enemy: Enemy3D
var _weapon: WeaponModel3D
var _projectile: Projectile3D
var _label: Label
var _sublabel: Label
var _muzzle := Vector3.ZERO
var _target := Vector3.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var wide_path := "res://outputs/bullet_trail_hidden_shot.png"
	var ab_path := "res://outputs/bullet_trail_hidden_ab.png"
	if args.size() >= 1:
		wide_path = args[0]
	if args.size() >= 2:
		ab_path = args[1]

	# 固定窗口尺寸：不设的话截图尺寸随窗口漂，拼接比例算不准。
	get_window().size = Vector2i(1280, 720)

	_build_stage()
	_build_hud()

	_player = PLAYER_SCENE.instantiate() as Player3D
	if _player == null:
		printerr("[shot] 玩家实例化失败")
		get_tree().quit(2)
		return
	# 走真实的出厂枪装配：枪挂在 Avatar 的 weapon_socket 上，不是漂浮的独立模型。
	_player.start_with_weapon = true
	_player.position = PLAYER_POS
	add_child(_player)
	_player.set_physics_process(false)
	# 玩家场景自带 current 相机，会抢机位。
	for child in _player.get_children():
		if child is Camera3D:
			(child as Camera3D).current = false

	_enemy = ENEMY_SCENE.instantiate() as Enemy3D
	if _enemy == null:
		printerr("[shot] 怪物实例化失败")
		get_tree().quit(2)
		return
	_enemy.enemy_kind = ENEMY_KIND
	_enemy.room_id = "shot_room"
	_enemy.enemy_data = {"spawn_index": 0, "floor": 1}
	_enemy.position = ENEMY_POS
	add_child(_enemy)
	_enemy.set_physics_process(false)

	await get_tree().process_frame
	await get_tree().process_frame
	_enemy._position_overhead_health_bar()

	await _setup_weapon()
	# 让环境/材质/光照先画几帧，否则前几张可能是空帧。
	for i in range(10):
		await RenderingServer.frame_post_draw

	await _capture_wide(wide_path)
	await _capture_ab(ab_path)
	get_tree().quit(0)


## 用玩家手里的真实武器开火（`Player3D._ensure_weapon_model()` 挂在 Avatar 的 weapon_socket 上）。
## 不自己实例化枪 —— 那样会得到一把悬空的枪，画面不像实机。
func _setup_weapon() -> void:
	_weapon = _player.weapon
	if _weapon == null or not is_instance_valid(_weapon):
		printerr("[shot] 玩家没有武器模型")
		return
	if _weapon.gun_id.is_empty():
		printerr("[shot] 玩家武器没有装配树（gun_id 为空）")
		return
	_weapon.projectile_spawned.connect(_on_projectile_spawned)

	_target = ENEMY_POS + Vector3(0.0, 1.0, 0.35)
	# 枪口世界坐标：开火前先读 `_muzzle`，开火后用它当弹道起点。
	var muzzle_node := _weapon.get_node_or_null("Muzzle") as Node3D
	var start := muzzle_node.global_position if muzzle_node != null else _weapon.global_position
	var dir := (_target - start).normalized()
	var fired: bool = _weapon.try_fire(dir, _player)
	print("[shot] 开火 gun=%s fired=%s dir=%s" % [_weapon.gun_id, fired, dir])

	for i in range(2):
		await get_tree().process_frame
	if _projectile == null:
		printerr("[shot] 开火没有生成投射物")
		return
	# 弹道起点取投射物的真实出生点（= 枪口世界坐标），不是估算值。
	_muzzle = _projectile.global_position
	# 关物理：之后位置完全由本工具摆，不受 speed / 射程 / 生命周期牵动。
	_projectile.set_physics_process(false)
	print("[shot] 弹道 %.2fm  枪口=%s" % [_muzzle.distance_to(_target), _muzzle])


func _on_projectile_spawned(projectile: Projectile3D) -> void:
	if projectile == null or _projectile != null:
		return
	_projectile = projectile


func _track_point(t: float) -> Vector3:
	return _muzzle.lerp(_target, t)


## 尾巴节点：`VfxBulletBody3D` 是 BulletRoot/Trail，通用弹体是 BulletRoot/Trail。
func _trail_node() -> Node3D:
	if _projectile == null or not is_instance_valid(_projectile):
		return null
	for visual in _projectile.get_children():
		if not visual.has_method("get_presentation_snapshot"):
			continue
		var direct := visual.get_node_or_null("BulletRoot/Trail")
		if direct != null:
			return direct as Node3D
		var deep := visual.find_child("Trail", true, false)
		if deep is Node3D:
			return deep as Node3D
	return null


func _trail_visible_state() -> String:
	var t := _trail_node()
	if t == null:
		return "无"
	return "是" if t.visible else "否"


## 全景：玩家 + 怪 + 子弹三个时刻。机位是侧视，垂直于弹道。
func _capture_wide(out_path: String) -> void:
	# 侧视机位：垂直于弹道（弹道沿 -Z），玩家与怪各占画面一侧。
	# 垂直方向要同时装下「玩家脚底 ~0m」与「怪物头顶血条 ~2.6m」，
	# 所以 focus 定在 1.35 居中、距离按半幅 3.4m / tan(19°) ≈ 9.9m 反算后再收一点。
	var focus := Vector3(0.0, 1.35, -2.3)
	_cam.global_position = Vector3(7.4, 2.55, -2.32)
	_cam.fov = 38.0
	_cam.current = true
	_cam.look_at(focus, Vector3.UP)

	var shots: Array[Image] = []
	var tags: Array[String] = []
	for i in range(TRACK_T.size()):
		var t := float(TRACK_T[i])
		if _projectile != null:
			_projectile.global_position = _track_point(t)
		var dist := _muzzle.distance_to(_track_point(t))
		await _set_label("尾巴已隐藏 — 子弹离枪口 %.1f m" % dist,
			"玩家 / 怪物 / 子弹 三者同框 · 弹道 %.0f%%" % (t * 100.0))
		for k in range(3):
			await RenderingServer.frame_post_draw
		var img := _grab()
		if img == null:
			continue
		shots.append(img)
		tags.append("%.1fm" % dist)
	var sheet := _compose_stack(shots, 1280)
	_save(sheet, out_path)
	print("[shot] 全景 %d 格 %s（尾巴可见=%s）" % [shots.size(), ", ".join(tags), _trail_visible_state()])


## 特写 A/B：同一颗子弹、同一机位，左格尾巴关（当前产品状态），右格尾巴手动打开。
func _capture_ab(out_path: String) -> void:
	if _projectile == null:
		print("[shot] 无投射物，跳过特写")
		return
	var trail := _trail_node()
	if trail == null:
		print("[shot] 找不到尾巴节点，跳过特写")
		return

	# 子弹停在弹道 45% 处，机位垂直贴近 —— 这个距离下 0.2m 的弹体 + 0.46m 的尾巴能占满画幅。
	_projectile.global_position = _track_point(0.45)
	var focus := _projectile.global_position
	_cam.fov = 32.0
	_cam.global_position = focus + Vector3(1.62, 0.30, 0.28)
	_cam.current = true
	_cam.look_at(focus, Vector3.UP)

	var shots: Array[Image] = []
	for state in [false, true]:
		trail.visible = state
		await _set_label(
			"尾巴已隐藏（当前产品状态）" if not state else "尾巴打开（对照：仅本工具临时点亮）",
			"同一颗子弹 / 同一机位 / 距弹体 1.65 m"
		)
		for k in range(4):
			await RenderingServer.frame_post_draw
		var img := _grab()
		if img == null:
			continue
		shots.append(img)
	trail.visible = false
	# 特写横排两格。
	var sheet := _compose_row(shots, 1180)
	_save(sheet, out_path)
	print("[shot] 特写 %d 格（左=关 右=开）" % shots.size())


func _set_label(main_text: String, sub_text: String) -> void:
	if _label != null:
		_label.text = main_text
	if _sublabel != null:
		_sublabel.text = sub_text
	await get_tree().process_frame


func _grab() -> Image:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		printerr("[shot] 取图失败")
		return null
	# Vulkan 下可能是 RGBAH，blit 会静默不写；必须显式转 RGBA8。
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, out_path: String) -> void:
	var resolved := ProjectSettings.globalize_path(out_path)
	if img.save_png(resolved) == OK:
		print("[shot] saved -> %s" % resolved)
	else:
		printerr("[shot] save_png 失败 -> %s" % resolved)


## 竖排（全景三格）。
func _compose_stack(shots: Array[Image], width: int) -> Image:
	if shots.is_empty():
		return Image.create(width, 1, false, Image.FORMAT_RGBA8)
	var cell_h := int(float(shots[0].get_height()) * float(width) / float(shots[0].get_width()))
	var sheet := Image.create(width, cell_h * shots.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.06, 0.08, 1.0))
	for i in range(shots.size()):
		var scaled := shots[i].duplicate()
		scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(width, cell_h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), Vector2i(0, i * cell_h))
		if i > 0:
			for x in range(width):
				sheet.set_pixel(x, i * cell_h, Color(0.55, 0.62, 0.72, 1.0))
				sheet.set_pixel(x, i * cell_h + 1, Color(0.55, 0.62, 0.72, 1.0))
	return sheet


## 横排（特写两格）。
func _compose_row(shots: Array[Image], total_width: int) -> Image:
	if shots.is_empty():
		return Image.create(total_width, 1, false, Image.FORMAT_RGBA8)
	var cell_w := int(float(total_width) / float(shots.size()))
	var cell_h := int(float(shots[0].get_height()) * float(cell_w) / float(shots[0].get_width()))
	var sheet := Image.create(cell_w * shots.size(), cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.06, 0.08, 1.0))
	for i in range(shots.size()):
		var scaled := shots[i].duplicate()
		scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(cell_w, cell_h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), Vector2i(i * cell_w, 0))
		if i > 0:
			for y in range(cell_h):
				sheet.set_pixel(i * cell_w, y, Color(0.55, 0.62, 0.72, 1.0))
				sheet.set_pixel(i * cell_w + 1, y, Color(0.55, 0.62, 0.72, 1.0))
	return sheet


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShotHud"
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(22, 16)
	_label.add_theme_font_size_override("font_size", 27)
	_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(_label)

	_sublabel = Label.new()
	_sublabel.position = Vector2(22, 54)
	_sublabel.add_theme_font_size_override("font_size", 19)
	_sublabel.add_theme_color_override("font_color", Color(0.62, 0.88, 1.0))
	_sublabel.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	_sublabel.add_theme_constant_override("outline_size", 6)
	layer.add_child(_sublabel)


func _build_stage() -> void:
	_cam = Camera3D.new()
	_cam.name = "ShotCamera"
	_cam.far = 220.0
	_cam.near = 0.05
	add_child(_cam)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -32.0, 0.0)
	key.light_energy = 2.0
	add_child(key)

	# 侧后补光：子弹是自发光的小件，没有侧光读不出轮廓与体积。
	var rim := OmniLight3D.new()
	rim.position = Vector3(3.2, 2.6, -4.4)
	rim.light_energy = 5.0
	rim.omni_range = 16.0
	rim.light_color = Color(0.68, 0.82, 1.0)
	add_child(rim)

	var front := OmniLight3D.new()
	front.position = Vector3(-2.6, 2.2, 1.2)
	front.light_energy = 3.0
	front.omni_range = 14.0
	front.light_color = Color(1.0, 0.92, 0.86)
	add_child(front)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.145, 0.18, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.76, 1.0)
	e.ambient_light_energy = 1.15
	# 一点点辉光：子弹是自发光件，没有辉光会读成一块死白方块。
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.04
	env.environment = e
	add_child(env)

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(90.0, 1.0, 90.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	add_child(floor_body)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90.0, 90.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.33, 0.38, 1.0)
	mat.roughness = 0.88
	floor_mesh.material_override = mat
	add_child(floor_mesh)
