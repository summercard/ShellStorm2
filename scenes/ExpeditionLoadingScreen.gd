extends CanvasLayer
class_name ExpeditionLoadingScreen
## 远征情报室 →「远征关卡01」之间的读取界面。
##
## 职责刻意保持单一：不提交运行态检查点、不消费入口意图、不改动任何存档。
## 基地落盘与入口登记由 RogueMapSelectMenu 在切场景前完成；本界面只负责
## 把"正在读取关卡"这件事显式地画给玩家看，进度走满后切到正式关卡场景。
##
## 视觉（2026-10-09 主人指定，黑白极简）：
##   · 纯黑底；右下角主角小兔子的**纯白正侧面剪影**原地跑动；
##   · 旁边一个逐字起伏的波浪 `LOADING` 字样；
##   · 屏幕底部一条白进度条，剪影正好站在它上面。
##   · 进/出各由全局光圈过场 IrisTransition 负责：进来时黑圈往中心收拢，
##     读条走满后黑圈从中心往外展开、露出关卡。
##
## 无头/编辑器环境直接跳过等待，保证验收脚本不会被过场拖住。
##
## 🔴 验收契约：本界面的 `_build_ui()` 会被 `verify_expedition_level01_flow` /
## `verify_test_level_99_flow` 在**不入树**的情况下直接调用，并断言
## `Root/Center/{Breadcrumb,Title,Progress,Step}` 四个节点的存在与取值。
## 因此这四个节点必须始终保留（视觉上隐藏，但文本/取值照旧可读），
## 且 `_build_ui()` 内**不得**创建 3D 视图（兔子舞台只在真正入树时另建）。

## 到达关卡路径**不在此处硬编码**：终点真源统一为 GameDesignConfig 的远征关卡清单。
## 本常量只是**默认终点**（远征关卡01）；实际去向由选关菜单写入的待进入关卡 id 决定，
## 见 `_destination_level_id()`。
const LEVEL_SCENE := GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D
## 过场总时长。只影响观感，不影响关卡数据；全部真实生成发生在关卡场景的 _ready()。
const TOTAL_DURATION_S := 1.35
const STEP_TEXTS: Array[String] = [
	"正在同步远征情报…",
	"正在规划房间序列…",
	"正在装配区块与门…",
	"正在生成敌对信号…",
	"读取完成，正在进入关卡",
]

## —— 主角剪影 ——
## 与 Player3D.tscn 引用同一份正式母版，保证剪影和游戏内是同一只兔子。
const BUNNY_SCENE := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/runtime/chr_bunny01_root_v021.tscn"
## 侧视跑动直接取动作库剪辑：`_state = "moving"` 且"未持械"时解析为
## `unarmed_moving_forward`（0.8s / 49 帧循环）。不改剪辑数据、不新增美术资产。
const BUNNY_RUN_STATE := "moving"
const SHOWCASE_SIZE := Vector2i(360, 400)
## 正交相机：站在兔子 +X 侧看向 -X（正侧面），视锥竖直刚好从地面 y=0 起算。
## 留约 23% 顶部余量，保证耳朵尖与脚都在画面内、剪影完整可读。
const ORTHO_SIZE := 1.95
const CAMERA_DISTANCE := 2.6

## —— 布局（像素，自屏幕右下/底部起算）——
const BAR_BOTTOM_MARGIN := 54.0
const BAR_HEIGHT := 6.0
const SHOWCASE_RIGHT_MARGIN := 72.0
const SHOWCASE_BOTTOM_MARGIN := BAR_BOTTOM_MARGIN + BAR_HEIGHT
const WAVE_RIGHT_MARGIN := SHOWCASE_RIGHT_MARGIN + float(SHOWCASE_SIZE.x) + 8.0
const WAVE_BOTTOM_MARGIN := BAR_BOTTOM_MARGIN + BAR_HEIGHT + 92.0
const WAVE_FONT_SIZE := 34
const WAVE_AMPLITUDE := 7.0
const WAVE_SPEED := 3.4
const WAVE_PHASE_STEP := 0.62

const INK := Color(0.0, 0.0, 0.0, 1.0)
const PAPER := Color(1.0, 1.0, 1.0, 1.0)
const BAR_TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.16)

var _elapsed := 0.0
var _advanced := false
var _level_id := ""

# 既有验收依赖的节点（Root/Center/{Breadcrumb,Title,Progress,Step}）——保留但视觉隐藏。
var _progress: ProgressBar
var _step_label: Label

var _root: Control
var _content: Control
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _wave_slots: Array[Dictionary] = []
var _wave_time := 0.0
var _showcase_viewport: SubViewport
var _bunny: Node3D
var _bunny_motion: CharacterMotionLibrary3D


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 一次性取走菜单登记的关卡：取值即清空，上一次的选择不会泄漏到下一次传送。
	# 验收脚本只 `_build_ui()` 不入树，那时本函数不跑，待进入态保持默认 —— 因此
	# 「默认关卡01」这条既有断言不受影响。
	_level_id = GameDesignConfig.peek_pending_expedition_level_id()
	_build_ui()
	# 上一场景的黑圈收拢已经把整屏压到全黑；此处放开遮罩，让本界面的黑底接手，
	# 视觉上是"黑 → 黑底 + 内容淡入"，没有跳变。
	if IrisTransition != null:
		IrisTransition.clear_now()
	if _should_skip_delay():
		_enter_level()
		return
	_build_showcase()
	_play_intro()


func _process(delta: float) -> void:
	if _advanced:
		return
	_elapsed += delta
	_wave_time += delta
	_drive_bunny(delta)
	_animate_wave()
	var ratio := clampf(_elapsed / TOTAL_DURATION_S, 0.0, 1.0)
	_apply_progress(ratio)
	if ratio >= 1.0:
		_enter_level()


## 无头验收与编辑器内不播放过场：直接进入关卡，避免慢测试与编辑器卡帧。
func _should_skip_delay() -> bool:
	return (
		DisplayServer.get_name() == "headless"
		or Engine.is_editor_hint()
	)


func _enter_level() -> void:
	if _advanced:
		return
	_advanced = true
	_finish_and_change_scene()


## 收尾：内容淡回黑底 → 遮罩盖满 → 切场景 → 在新场景上开圈。
## 🔴 全过程只在**真实运行时**发生；无头/编辑器分支一步都不多做，
## 保持"读条结束即同步 change_scene"这条既有验收时序。
func _finish_and_change_scene() -> void:
	var use_iris := not _should_skip_delay() and IrisTransition != null
	if use_iris:
		if _content != null:
			var fade := create_tween()
			fade.tween_property(_content, "modulate:a", 0.0, 0.16)
			await fade.finished
		IrisTransition.cover_now()
	var error := get_tree().change_scene_to_file(_destination_scene())
	if error != OK:
		push_error(
			"[ExpeditionLoadingScreen] 进入远征关卡失败: %s" % error_string(error)
		)
		return
	if use_iris:
		IrisTransition.open_after_scene()


## 本次要去的关卡 id。`_level_id` 为真源（_ready 时取），空则回退默认关卡。
func _destination_level_id() -> String:
	if _level_id.is_empty():
		return GameDesignConfig.default_expedition_level_id()
	return _level_id


## 本次要去的关卡场景。
func _destination_scene() -> String:
	return GameDesignConfig.expedition_level_scene(_destination_level_id())


## 本次要去的关卡展示名。关卡清单里没有该 id 时返回 id 本身，至少不说谎。
func _destination_display_name() -> String:
	var level_id := _destination_level_id()
	var display_name := GameDesignConfig.expedition_level_display_name(level_id)
	if display_name.is_empty():
		return level_id
	return display_name


func _play_intro() -> void:
	if _content == null:
		return
	_content.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_content, "modulate:a", 1.0, 0.28)


func _apply_progress(ratio: float) -> void:
	# 既有验收节点（隐藏）：保持真实推进，探针若读取不会拿到死值。
	if _progress != null:
		_progress.value = ratio * 100.0
	if _step_label != null and not STEP_TEXTS.is_empty():
		var step_index := clampi(
			int(ratio * float(STEP_TEXTS.size())), 0, STEP_TEXTS.size() - 1
		)
		_step_label.text = STEP_TEXTS[step_index]
	# 可见的底部白进度条。
	if _bar_track != null and _bar_fill != null:
		_bar_fill.size = Vector2(_bar_track.size.x * ratio, BAR_HEIGHT)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_root = root

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = INK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	# 🔴 验收契约节点：结构与文本必须原样保留，视觉隐藏即可（隐藏不影响 get_node/text 读取）。
	_build_legacy_readout(root)

	# 可见内容（黑底之上的全部可视元素），统一用一个父节点做淡入淡出。
	var content := Control.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(content)
	_content = content

	_build_wave_text(content)
	_build_progress_bar(content)


## 保留旧的"面包屑 + 标题 + 步骤 + 进度"节点树（含文本），但整体隐藏。
## 它们仍在原始路径上，`verify_*` 的断言照旧成立。
func _build_legacy_readout(root: Control) -> void:
	var center := VBoxContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -320.0
	center.offset_top = -140.0
	center.offset_right = 320.0
	center.offset_bottom = 140.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	root.add_child(center)

	var breadcrumb := Label.new()
	breadcrumb.name = "Breadcrumb"
	breadcrumb.text = "远征情报室  →  %s" % _destination_display_name()
	breadcrumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(breadcrumb)

	var title := Label.new()
	title.name = "Title"
	title.text = _destination_display_name()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	center.add_child(_progress)

	_step_label = Label.new()
	_step_label.name = "Step"
	_step_label.text = STEP_TEXTS[0]
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_step_label)

	# 视觉隐藏：新版是纯黑极简，旧彩色文案不上屏。
	center.visible = false


func _build_progress_bar(content: Control) -> void:
	_bar_track = ColorRect.new()
	_bar_track.name = "LoadingBar"
	_bar_track.color = BAR_TRACK_COLOR
	_bar_track.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_track.offset_top = -(BAR_BOTTOM_MARGIN + BAR_HEIGHT)
	_bar_track.offset_bottom = -BAR_BOTTOM_MARGIN
	_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_bar_track)

	_bar_fill = ColorRect.new()
	_bar_fill.name = "Fill"
	_bar_fill.color = PAPER
	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(0.0, BAR_HEIGHT)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_track.add_child(_bar_fill)


## 波浪 `LOADING`：每个字母一个 Label，各自按相位上下起伏（左起波浪式传导）。
func _build_wave_text(content: Control) -> void:
	var holder := Control.new()
	holder.name = "WaveLoading"
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.offset_left = -WAVE_RIGHT_MARGIN - 320.0
	holder.offset_top = -(WAVE_BOTTOM_MARGIN + 60.0)
	holder.offset_right = -WAVE_RIGHT_MARGIN
	holder.offset_bottom = -WAVE_BOTTOM_MARGIN
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(holder)

	var font := ThemeDB.fallback_font
	var word := "LOADING"
	var cursor := 0.0
	_wave_slots.clear()
	for index in word.length():
		var letter := word.substr(index, 1)
		var label := Label.new()
		label.name = "L%d" % index
		label.text = letter
		label.add_theme_font_size_override("font_size", WAVE_FONT_SIZE)
		label.add_theme_color_override("font_color", PAPER)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var width := WAVE_FONT_SIZE * 0.72
		if font != null:
			width = font.get_string_size(
				letter, HORIZONTAL_ALIGNMENT_LEFT, -1, WAVE_FONT_SIZE
			).x
		label.position = Vector2(cursor, 0.0)
		label.size = Vector2(width + 6.0, WAVE_FONT_SIZE + 24.0)
		holder.add_child(label)
		_wave_slots.append({"node": label, "x": cursor, "index": index})
		cursor += width + 7.0


func _animate_wave() -> void:
	for slot in _wave_slots:
		var label := slot["node"] as Label
		if label == null:
			continue
		var index := float(slot["index"])
		var x := float(slot["x"])
		var lift := sin(_wave_time * WAVE_SPEED - index * WAVE_PHASE_STEP) * WAVE_AMPLITUDE
		label.position = Vector2(x, -lift)


## 兔子剪影舞台。只在真正入树、且非无头/编辑器时构建 —— 验收路径不碰这里。
func _build_showcase() -> void:
	if _content == null:
		return
	var container := SubViewportContainer.new()
	container.name = "BunnyStage"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	container.offset_left = -SHOWCASE_RIGHT_MARGIN - float(SHOWCASE_SIZE.x)
	container.offset_top = -SHOWCASE_BOTTOM_MARGIN - float(SHOWCASE_SIZE.y)
	container.offset_right = -SHOWCASE_RIGHT_MARGIN
	container.offset_bottom = -SHOWCASE_BOTTOM_MARGIN
	_content.add_child(container)

	_showcase_viewport = SubViewport.new()
	_showcase_viewport.name = "BunnyViewport"
	_showcase_viewport.size = SHOWCASE_SIZE
	_showcase_viewport.transparent_bg = true
	_showcase_viewport.own_world_3d = true
	_showcase_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_showcase_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_showcase_viewport)

	# 无环境、无背景：只有角色 + 纯白剪影材质，落在透明画布上。
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world_env.environment = env
	_showcase_viewport.add_child(world_env)

	var packed := load(BUNNY_SCENE) as PackedScene
	if packed == null:
		push_warning("[ExpeditionLoadingScreen] 主角剪影母版缺失：%s" % BUNNY_SCENE)
		return
	_bunny = packed.instantiate() as Node3D
	if _bunny == null:
		return
	_bunny.name = "BunnyShowcase"
	# 只借它的表现层：自己接管动画驱动，不用它依赖 Player3D 的 _process。
	_bunny.set_process(false)
	_bunny.set_physics_process(false)
	_bunny.set("_state", BUNNY_RUN_STATE)
	_showcase_viewport.add_child(_bunny)
	_bunny_motion = _bunny.get("_authored_motion") as CharacterMotionLibrary3D
	_paint_silhouette(_bunny)
	_add_showcase_camera()


## 把所有网格刷成纯白无光照材质 ⇒ 正侧面剪影；顺带关掉与角色无关的运行时特效。
func _paint_silhouette(node: Node3D) -> void:
	for path in [
		"VisualRoot/StateVFX",
		"ReloadProgress3D",
		"VisualRoot/WeaponSocket/Weapon",
	]:
		var hidden := node.get_node_or_null(path)
		if hidden is Node3D:
			(hidden as Node3D).visible = false
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = PAPER
	white.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	white.disable_receive_shadows = true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		mesh.material_override = white
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_showcase_camera() -> void:
	if _showcase_viewport == null:
		return
	var camera := Camera3D.new()
	camera.name = "ShowcaseCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	# 视锥竖直范围 = [0, ORTHO_SIZE]：地面 y=0 恰在画面下沿，剪影像"站在"进度条上。
	camera.position = Vector3(CAMERA_DISTANCE, ORTHO_SIZE * 0.5, 0.0)
	# rotation.y = +90° ⇒ 相机前向 -X，从 +X 侧看主角的正侧面。
	camera.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	camera.near = 0.05
	camera.far = 20.0
	camera.cull_mask = 0xFFFFFFFF
	camera.current = true
	_showcase_viewport.add_child(camera)


func _drive_bunny(delta: float) -> void:
	if _bunny == null or _bunny_motion == null:
		return
	_bunny_motion.apply(_bunny, delta)
