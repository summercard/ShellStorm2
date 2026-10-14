extends Node3D
## 一次性工具：把「怪物启动过程」跑一遍并截三帧，作为可核证据。
## 用法：godot --path . res://tools/monster_startup_capture.tscn -- <out.png>
##
## 必须是**场景**而不是 `-s` 脚本：`--script` 模式不挂 autoload，而 `Enemy3D` 依赖
## `MonsterAIManager` 等单例，在 `-s` 下根本编译不过（实测报 Identifier not found）。
##
## 三帧：
##   A 进入警觉（背对玩家，尚未转身）
##   B 转身完成（正对玩家）
##   C 吼叫中（头顶图标已弹出）
##
## ⚠️ 刻意**不依赖真 AI**：本工具只要画面。真 AI 路径由
## `verify_monster_startup_roar` 的端到端用例负责断言；这里驱动的是同一条门禁函数
## （`_begin_monster_startup` / `_tick_alert_state`）。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)

const KIND := "melee_chaser"
const STEP := 1.0 / 60.0
const PLAYER_MARKER_POS := Vector3(-5.0, 0.9, 5.4)

var _cam: Camera3D
var _enemy: Enemy3D
var _shots: Array[Image] = []
var _phase_label: Label
var _readout_label: Label
var _roar_shot_delay := 0.0
var _phase_text := ""
## ③ 的延迟触发点（-1 = 已拍完）。


func _ready() -> void:
	_build_hud()
	var args := OS.get_cmdline_user_args()
	var out_path := "res://outputs/monster_startup_capture.png"
	if args.size() >= 1:
		out_path = args[0]

	_build_stage()
	# 让环境/光照/材质先画几帧再开始，否则第一张可能是空帧。
	for i in range(5):
		await RenderingServer.frame_post_draw

	# 玩家位置只用一个胶囊当参照 —— 不实例化 Player3D，省掉它那一串重依赖。
	_add_player_marker(PLAYER_MARKER_POS)

	_enemy = ENEMY_SCENE.instantiate() as Enemy3D
	if _enemy == null:
		printerr("[capture] Enemy3D 实例化失败（脚本链编译问题）")
		get_tree().quit(2)
		return
	_enemy.enemy_kind = KIND
	_enemy.room_id = "capture_room"
	_enemy.enemy_data = {"spawn_index": 0, "floor": 1}
	_enemy.position = Vector3.ZERO
	_enemy.rotation.y = deg_to_rad(155.0)  # 初始背对玩家
	add_child(_enemy)
	# 本工具自己驱动状态机，别让引擎的 AI 帧进来覆写目标。
	_enemy.set_physics_process(false)
	_enemy._position_overhead_health_bar()

	var to_target := PLAYER_MARKER_POS - _enemy.global_position
	if _enemy.ai_state == "idle":
		_enemy.transition_to("alert")
	var began: bool = _enemy._begin_monster_startup(to_target)
	print("[capture] 启动=(%s) 转角=%.1f° 转身段=%.4fs 总时长=%.4fs" % [
		began, _enemy._startup_delta_yaw_deg, _enemy._startup_turn_sec, _enemy._startup_total
	])
	if not began:
		printerr("[capture] 启动过程未开始，放弃")
		get_tree().quit(2)
		return

	await _shot("① 进入警觉 — 背对玩家，启动过程开始计时（尚未转身）")
	var alert_duration: float = _enemy._ai_param(
		"alert_duration_sec", float(Enemy3D.PROFILES[KIND].get("alert", 0.28))
	)
	var t := 0.0
	var shot_turn := false
	var shot_roar := false
	var guard := 0
	while guard < 600 and _enemy.ai_state == "alert":
		guard += 1
		_enemy._state_time += STEP
		t += STEP
		_enemy._tick_alert_state(to_target, STEP, alert_duration)
		await get_tree().physics_frame
		if not shot_turn and t >= _enemy._startup_turn_sec:
			shot_turn = true
			await _shot("② 转身完成 — 已转向玩家；此处起吼，头顶图标弹出")
		if shot_roar and _roar_shot_delay < 0.0:
			pass
		elif not shot_roar and _enemy._roar_icon_fired:
			shot_roar = true
			# 再走 ~0.09s 才截 ③：否则它和 ② 是同一帧，看起来像重复。
			_roar_shot_delay = _enemy._state_time + 0.09
		if shot_roar and _roar_shot_delay > 0.0 and _enemy._state_time >= _roar_shot_delay:
			_roar_shot_delay = -1.0
			await _shot("③ 吼叫中 — 头顶蓝色吼叫图标可见，仍在启动窗口内")
	print("[capture] 结束 state=%s 用时=%.4fs 图标=%s 截图=%d 张" % [
		_enemy.ai_state, t, "有" if _enemy._roar_icon_fired else "无", _shots.size()
	])

	var sheet := _compose(1200, out_path)
	var resolved := ProjectSettings.globalize_path(out_path)
	var err := sheet.save_png(resolved)
	if err != OK:
		printerr("[capture] save_png err=%d -> %s" % [err, resolved])
		get_tree().quit(3)
		return
	print("[capture] saved -> %s" % resolved)

	# 第二张：同一支图标在「弹出 → 回稳 → 停顿 → 淡出」各时刻的取样条。
	# 这是业主「要有弹出停顿一下的动画」的直接视觉证据：
	# 第 1 格最小（刚弹出）→ 第 2 格最大（过冲）→ 后面几格**完全一样大**（停顿）。
	await _capture_pop_rhythm(out_path.get_basename() + "_pop_rhythm.png")
	get_tree().quit(0)


## 弹出节奏取样条：把图标按各时刻的 scale 摆成一排，直观看出「弹出去 → 停住」。
##
## 关键取证点：③ 停顿段的几格必须**像素级一样大**。若有人把停顿做成慢慢收，
## 这里一眼就能看出格子越往右越小。
func _capture_pop_rhythm(out_path: String) -> void:
	# 先把主场景的怪与玩家参照收掉：本张图只讲图标节奏，留着它们只会误导读者。
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
		_enemy = null
	for child in get_children():
		if child is MeshInstance3D or child is StaticBody3D:
			child.queue_free()
	await get_tree().process_frame

	# 用大一点的边长，让「弹出段 vs 停顿段」的尺寸差一眼可辨。
	var edge := 0.90
	var hold := VfxMonsterRoarIcon3D.DEFAULT_HOLD_SECONDS
	var fade := VfxMonsterRoarIcon3D.DEFAULT_FADE_SECONDS

	# 取样时刻：① 弹出起点 / 过冲峰值 / ② 回稳中点 / ③ 停顿三点 / ④ 淡出中点
	var marks := [
		{"t": 0.00, "tag": "① 0.00s 弹出起点"},
		{"t": VfxMonsterRoarIcon3D.POP_PEAK_AT, "tag": "① 0.10s 过冲峰值"},
		{"t": (VfxMonsterRoarIcon3D.POP_PEAK_AT + VfxMonsterRoarIcon3D.POP_SETTLE_AT) * 0.5,
			"tag": "② 0.14s 回稳中"},
		{"t": VfxMonsterRoarIcon3D.POP_SETTLE_AT, "tag": "③ 0.18s 停顿起"},
		{"t": (VfxMonsterRoarIcon3D.POP_SETTLE_AT + hold) * 0.5, "tag": "③ 0.37s 停顿中"},
		{"t": hold, "tag": "③ 0.55s 停顿末"},
		{"t": hold + fade * 0.5, "tag": "④ 0.64s 淡出中"},
	]
	var strip: Array[Node3D] = []
	var spacing := 1.55
	var x0 := -float(marks.size() - 1) * 0.5 * spacing
	var fade_index := marks.size() - 1
	for i in range(marks.size()):
		var one := VfxMonsterRoarIcon3D.new()
		add_child(one)
		one.global_position = Vector3(x0 + float(i) * spacing, 1.20, 0.0)
		# ⚠️ 除最后一格外，hold 都给 600s：否则取样条自己会在截图前淡出，
		# 前几格就全变透明了。只有「④ 淡出」那一格必须用真实 hold/fade，
		# 否则它永远是 alpha=1.0，读数会说谎（本次已踩过）。
		if i == fade_index:
			one.activate(one.global_position, Color.WHITE, edge,
				{"hold_seconds": hold, "fade_seconds": fade})
		else:
			one.activate(one.global_position, Color.WHITE, edge,
				{"hold_seconds": 600.0, "fade_seconds": 0.0})
		strip.append(one)

	# 逐格取实际 scale。读数**从实测值生成**，不写死 ——
	# 写死的话一旦改 edge 或曲线，图上的数字就成了假证据（本次已踩过一次）。
	var scales: Array[float] = []
	var alphas: Array[float] = []
	for i in range(marks.size()):
		var m: Dictionary = marks[i]
		strip[i]._on_tick(float(m["t"]), 600.0)
		var sp := strip[i].get_node_or_null("RoarIconSprite") as Sprite3D
		scales.append(sp.scale.x if sp != null else -1.0)
		alphas.append(sp.modulate.a if sp != null else -1.0)
		print("[capture] 节奏 %s → scale=%.4f alpha=%.3f" % [
			String(m["tag"]), scales[i], alphas[i]
		])

	# 停顿段三格必须完全一致 —— 在读数里直接标出来，图形与数字互证。
	var still_same := (
		absf(scales[3] - scales[4]) <= 0.0005 and absf(scales[4] - scales[5]) <= 0.0005
	)
	_set_phase("弹出节奏：① 弹出 → ② 回稳 → ③ 停顿（静止不变）→ ④ 淡出")
	_readout_label.text = (
		"取样 = 同一支图标在不同时刻的实拍（边长为 %.2fm 的图标）\n" % edge
		+ "① 弹出起 %.4f  →  ① 过冲峰值 %.4f（最大）\n" % [scales[0], scales[1]]
		+ "② 回稳中 %.4f\n" % scales[2]
		+ "③ 停顿起/中/末 = %.4f / %.4f / %.4f  %s\n"
			% [scales[3], scales[4], scales[5], "**三格完全相同 = 真静止**" if still_same else "**不一致！停顿段在动**"]
		+ "④ 淡出中尺寸 %.4f 不变，alpha %.2f（只变淡）" % [scales[6], alphas[6]]
	)

	# 取样条本身自证：三格完全相同这件事也进日志，供 CI 侧 grep。
	print("[capture] 停顿段三格同尺度 = %s" % ("YES" if still_same else "NO"))

	_cam.global_position = Vector3(0.0, 2.55, 7.0)
	_cam.look_at(Vector3(0.0, 1.18, 0.0), Vector3.UP)
	for i in range(4):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	var resolved := ProjectSettings.globalize_path(out_path)
	if img.save_png(resolved) == OK:
		print("[capture] saved -> %s" % resolved)
	for o in strip:
		o.queue_free()


## 屏幕左上角的阶段标签 + 右上角实时读数。截图里带上它，证据才自解释。
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CaptureHud"
	add_child(layer)

	_phase_label = Label.new()
	_phase_label.position = Vector2(18, 12)
	_phase_label.add_theme_font_size_override("font_size", 26)
	_phase_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_phase_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	_phase_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_phase_label)

	_readout_label = Label.new()
	_readout_label.position = Vector2(18, 48)
	_readout_label.add_theme_font_size_override("font_size", 18)
	_readout_label.add_theme_color_override("font_color", Color(0.62, 0.86, 1.0))
	_readout_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	_readout_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_readout_label)


func _set_phase(title: String) -> void:
	_phase_text = title
	if _phase_label != null:
		_phase_label.text = title


## 每物理帧刷新：让「怪在哪个状态 / 启动还剩多少 / 图标有没有」直接印在图上。
func _process(_delta: float) -> void:
	if _readout_label == null or _enemy == null:
		return
	var icon_state := "—"
	if _enemy.get_node_or_null("OverheadHealthBar/VfxMonsterRoarIcon3D") != null:
		icon_state = "头顶吼叫图标：已出现"
	else:
		icon_state = "头顶吼叫图标：未出现"
	_readout_label.text = (
		"state = %s\n启动过程 = %s    已走 %.3fs / %.3fs\n转角 = %.1f°    图标弹出 = %s\n%s"
		% [
			_enemy.ai_state,
			"计时中" if _enemy._startup_active else "未计时",
			_enemy._state_time,
			_enemy._startup_total,
			_enemy._startup_delta_yaw_deg,
			"是" if _enemy._roar_icon_fired else "否",
			icon_state,
		]
	)


func _shot(label: String) -> void:
	# 先把阶段文字写进 HUD，再等绘制帧 —— 这样标签会被烧进截图里。
	_set_phase(label)
	for i in range(3):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("[capture] %s 取图失败" % label)
		return
	# 🔴 必须显式转成 RGBA8：Vulkan 下 `get_texture().get_image()` 可能是
	# FORMAT_RGBAH 之类的浮点格式，而 `blit_rect` 在源/目标格式不一致时**静默不写**，
	# 表现为「帧本身有内容、拼出来的整张图却只有背景色」（实测踩到）。
	img.convert(Image.FORMAT_RGBA8)
	_shots.append(img)
	print("[capture] 记录 %s（state=%s，图标=%s）" % [
		label, _enemy.ai_state,
		"有" if _enemy.get_node_or_null("OverheadHealthBar/VfxMonsterRoarIcon3D") != null else "无",
	])


## 空帧诊断用：图上出现过的最大 alpha。
func _alpha_max(img: Image) -> float:
	var best := 0.0
	for y in range(0, img.get_height(), 7):
		for x in range(0, img.get_width(), 7):
			best = maxf(best, img.get_pixel(x, y).a)
	return best


func _compose(width: int, _out_path: String) -> Image:
	if _shots.is_empty():
		return Image.create(width, 1, false, Image.FORMAT_RGBA8)
	var cell_h := int(float(width) * 0.52)
	var sheet := Image.create(width, cell_h * _shots.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.13, 1.0))
	for i in range(_shots.size()):
		var scaled := _shots[i].duplicate()
		scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(width, cell_h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), Vector2i(0, i * cell_h))
		if i > 0:
			for x in range(width):
				sheet.set_pixel(x, i * cell_h, Color(0.55, 0.62, 0.72, 1.0))
	return sheet


## 玩家位置的可视参照：一根竖胶囊，只用来读「怪有没有转过来面对它」。
func _add_player_marker(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.72, 0.95, 1.0)
	mat.roughness = 0.7
	mesh.material_override = mat
	mesh.position = at
	add_child(mesh)

	# 脚下的圈，便于看出朝向基准
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.60
	ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.95, 0.85, 0.35, 1.0)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	ring.position = Vector3(at.x, 0.03, at.z)
	add_child(ring)


func _build_stage() -> void:
	# 机位：把镜头对准「怪 ↔ 玩家参照」的中点，用 look_at 保证两个目标都在画内。
	# （先前用固定 rotation_degrees 试算，结果怪贴在画面顶边、玩家只露一条边。）
	var mid := (Vector3.ZERO + PLAYER_MARKER_POS) * 0.5
	var focus := Vector3(mid.x, 0.95, mid.z)

	_cam = Camera3D.new()
	_cam.position = Vector3(focus.x, 5.2, focus.z + 9.8)
	_cam.fov = 44.0
	_cam.current = true
	add_child(_cam)
	_cam.look_at(focus, Vector3.UP)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	key.light_energy = 1.25
	add_child(key)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.11, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.49, 0.58, 1.0)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80.0, 1.0, 80.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	add_child(floor_body)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.19, 0.21, 0.25, 1.0)
	mat.roughness = 0.95
	floor_mesh.material_override = mat
	add_child(floor_mesh)
