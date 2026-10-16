extends CanvasLayer
class_name ExpeditionLoadingScreen
## 基地远征情报室或塔3门前 →「远征关卡01」之间的读取界面。
##
## 职责刻意保持单一：不提交运行态检查点、不消费入口意图、不改动任何存档。
## 基地落盘与入口登记由 RogueMapSelectMenu 在切场景前完成；本界面只负责
## 展示真实资源与场景装配进度，并跨场景保留遮罩直到 Tower 就绪。
##
## 视觉（2026-10 改为「棱镜线框」；原 2026-10-09 的黑白极简为其前身）：
##   · 深墨底；右下角主角小兔子的**纯白正侧面剪影**原地跑动；
##   · 旁边一个逐字起伏的波浪 `LOADING` 字样（棱镜字距）；
##   · 屏幕底部一条白色进度条，剪影正好站在它上面。
##   · 进/出各由全局光圈过场 IrisTransition 负责：进来时黑圈往中心收拢，
##     读条走满后黑圈从中心往外展开、露出关卡。
##
## 无头环境只跳过渲染收尾的 post_draw 等待；资源加载和场景就绪仍然走真实流程。
##
## 🔴 验收契约：本界面的 `_build_ui()` 会被 `verify_expedition_level01_flow` /
## `verify_test_level_99_flow` 在**不入树**的情况下直接调用，并断言
## `Root/Center/{Breadcrumb,Title,Progress,Step}` 四个节点的存在与取值。
## 因此这四个节点必须始终保留（视觉上隐藏，但文本/取值照旧可读），
## 且 `_build_ui()` 内**不得**创建 3D 视图（兔子舞台只在真正入树时另建）。

## 到达关卡路径**不在此处硬编码**：终点真源统一为 GameDesignConfig 的远征关卡清单。
## 本常量只是**默认终点**（远征关卡01）；实际去向由选关菜单写入的待进入关卡 id 决定，
## 见 `_destination_level_id()`。
const RESOURCE_WARMUP := preload("res://src/world3d/LoadingResourceWarmup.gd")
const LEVEL_SCENE := GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D
## 旧探针常量仍保留；真实进度不再由固定时长驱动。
const TOTAL_DURATION_S := 1.35
## 真实运行时读取页的最低可见时长。即使资源与地图装配提前完成，
## 也要让黑底、兔子、进度条和完整开圈过场至少稳定展示 2 秒。
const MIN_LOADING_SCREEN_SECONDS := 2.0
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
const SHOWCASE_SIZE := Vector2i(180, 200)
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

## 棱镜线框下读取页是「深墨底 + 白线 + 白字」：底色从纯黑提到棱镜深墨
## （与启动壳、主菜单、暂停菜单同一底色族），白线与白字不变 —— 剪影仍是纯白。
const INK := Color(0.031, 0.055, 0.086, 1.0)
const PAPER := Color(1.0, 1.0, 1.0, 1.0)
const BAR_TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.16)

var _world_render_was_disabled := false
var _owns_world_render_gate := false
var _elapsed := 0.0
var _loading_started_msec: int = 0
## 兼容旧截图/探针；不再作为真实进度或切场景条件。
var _advanced := false
var _level_id := ""
var _target_scene := ""
var _target_name := ""
var _resource_request_active := false
var _resource_warmup_active := false
var _warm_resources: Array[Resource] = []
var _resource_poll_after_frame := 0
var _scene_change_started: bool = false
var _scene_changed_seen: bool = false
var _requires_loading_scene_ready_contract: bool = true
var _finalizing: bool = false
var _failure_kind := ""
var _intro_tween: Tween

# 既有验收依赖的节点（Root/Center/{Breadcrumb,Title,Progress,Step}）——保留但视觉隐藏。
var _progress: ProgressBar
var _step_label: Label

var _root: Control
var _content: Control
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _status_label: Label
var _retry_button: Button
var _wave_slots: Array[Dictionary] = []
var _wave_time := 0.0
var _showcase_viewport: SubViewport
var _bunny: Node3D
var _bunny_motion: CharacterMotionLibrary3D


func _ready() -> void:
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world_render_was_disabled = get_viewport().disable_3d
	get_viewport().disable_3d = true
	_owns_world_render_gate = true
	_capture_destination()
	if _root == null:
		_build_ui()
	_set_loading_contract()
	if IrisTransition != null:
		IrisTransition.clear_now()
	if not _should_skip_delay() and not Engine.is_editor_hint():
		_build_showcase()
	_play_intro()
	# UI/兔子舞台构建耗时不能挤占最低展示时长。
	_loading_started_msec = Time.get_ticks_msec()
	_start_after_intro()


func _start_after_intro() -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		await _intro_tween.finished
	_start_resource_request()


func _process(delta: float) -> void:
	_elapsed += delta
	_wave_time += delta
	_drive_bunny(delta)
	_animate_wave()
	if _resource_request_active:
		_poll_resource_request()
	elif _scene_change_started and not _finalizing:
		_poll_target_scene()


## 只跳过截图收尾的 post_draw；绝不跳过真实 ResourceLoader 或场景 ready。
func _should_skip_delay() -> bool:
	return DisplayServer.get_name() == "headless"


## 旧调用方仍可安全调用；真实流程由资源状态和目标场景 ready 驱动。
func _enter_level() -> void:
	if not is_inside_tree() or _scene_change_started or _finalizing:
		return
	if _resource_request_active:
		_poll_resource_request()
	elif _failure_kind.is_empty():
		if _target_scene.is_empty():
			_capture_destination()
			_set_loading_contract()
		_start_resource_request()


func _capture_destination() -> void:
	var destination_scene := str(_iris_value("loading_destination_scene", ""))
	var destination_name := str(_iris_value("loading_destination_name", ""))
	if IrisTransition != null:
		_iris_set("loading_destination_scene", "")
		_iris_set("loading_destination_name", "")
	if not destination_scene.is_empty():
		_target_scene = destination_scene
		_target_name = destination_name if not destination_name.is_empty() else destination_scene.get_file().get_basename()
	else:
		# 读取页是唯一消费点；peek 不能让上一次选关意图泄漏。
		_level_id = GameDesignConfig.consume_pending_expedition_level_id()
		_target_scene = GameDesignConfig.expedition_level_scene(_level_id)
		_target_name = GameDesignConfig.expedition_level_display_name(_level_id)
	_requires_loading_scene_ready_contract = not _is_base_destination(_target_scene)


func _is_base_destination(scene_path: String) -> bool:
	return (
		scene_path == GameDesignConfig.MAIN_SCENE
		or scene_path == GameDesignConfig.BASE_SCENE_3D
	)


func _set_loading_contract() -> void:
	_requires_loading_scene_ready_contract = not _is_base_destination(_target_scene)
	if IrisTransition == null:
		return
	_iris_set("loading_target_scene", _target_scene)
	_iris_set("loading_progress", 0.0)
	_iris_set("loading_status", "正在读取 %s" % _destination_display_name())
	_iris_set("loading_scene_ready", false)
	_iris_set("loading_scene_failed", false)
	_report_loading(0.0, "正在读取 %s" % _destination_display_name())


func _iris_value(property_name: String, fallback: Variant) -> Variant:
	if IrisTransition == null:
		return fallback
	var value = IrisTransition.get(property_name)
	return fallback if value == null else value


func _iris_set(property_name: String, value: Variant) -> void:
	if IrisTransition == null:
		return
	IrisTransition.set(property_name, value)


func _report_loading(progress: float, status: String) -> void:
	if IrisTransition != null and IrisTransition.has_method("report_loading"):
		IrisTransition.report_loading(progress, status)
	else:
		_iris_set("loading_progress", progress)
		_iris_set("loading_status", status)


func _start_resource_request() -> void:
	if _resource_warmup_active:
		return
	if _target_scene.is_empty():
		_show_failure("resource", "目标场景为空，无法读取")
		return
	_resource_warmup_active = true
	_set_status("正在读取 %s" % _destination_display_name())
	var warm_error := await RESOURCE_WARMUP.warm(_target_scene, get_tree(), _warm_resources, _report_resource_warmup, _requires_loading_scene_ready_contract)
	_resource_warmup_active = false
	if warm_error != OK:
		_show_failure("resource", "资源预读取失败：%s" % error_string(warm_error))
		return
	_resource_request_active = true
	_resource_poll_after_frame = Engine.get_process_frames()
	_failure_kind = ""
	_set_status("正在读取 %s" % _destination_display_name())
	var error := ResourceLoader.load_threaded_request(_target_scene, "PackedScene")
	if error != OK:
		_resource_request_active = false
		_show_failure("resource", "资源读取失败：%s" % error_string(error))


func _report_resource_warmup(ratio: float) -> void:
	var mapped := ratio * 0.50
	_apply_progress(mapped)
	_report_loading(mapped, "正在读取 %s" % _destination_display_name())


func _poll_resource_request() -> void:
	if Engine.get_process_frames() <= _resource_poll_after_frame:
		return
	var load_progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_target_scene, load_progress)
	var actual := 0.0
	if not load_progress.is_empty():
		actual = clampf(float(load_progress[0]), 0.0, 1.0)
	var mapped := 0.50 + actual * 0.20
	_apply_progress(mapped)
	_report_loading(mapped, "正在读取 %s" % _destination_display_name())
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(_target_scene) as PackedScene
			_resource_request_active = false
			if packed == null:
				_show_failure("resource", "资源读取完成但不是 PackedScene")
			else:
				_apply_progress(0.70)
				_report_loading(0.70, "正在启动关卡")
				_begin_scene_change(packed)
			return
		_:
			_resource_request_active = false
			_show_failure("resource", "资源读取失败：%s" % _target_scene)


func _begin_scene_change(packed: PackedScene) -> void:
	if _scene_change_started or packed == null or not is_inside_tree():
		return
	var tree := get_tree()
	_scene_change_started = true
	_scene_changed_seen = false
	if not tree.scene_changed.is_connected(_on_tree_scene_changed):
		tree.scene_changed.connect(_on_tree_scene_changed)
	var previous_scene := tree.current_scene
	var previous_parent := get_parent()
	# 缓存 SceneTree：remove_child 后 get_tree() 会返回 null；读取页本来就在 root 时不必重挂。
	if previous_parent != tree.root:
		reparent(tree.root)
	if previous_scene == self:
		tree.current_scene = null
	var error := tree.change_scene_to_packed(packed)
	if error != OK:
		# change_scene_to_packed 返回错误时尚未移除旧场景；恢复原归属，不猜测异步失败。
		if is_instance_valid(previous_parent) and get_parent() != previous_parent:
			reparent(previous_parent)
		if is_instance_valid(previous_scene):
			tree.current_scene = previous_scene
		else:
			tree.current_scene = self
		_scene_change_started = false
		_disconnect_scene_changed()
		_show_failure("resource", "进入关卡失败：%s" % error_string(error))


func _on_tree_scene_changed() -> void:
	if _scene_change_started:
		_scene_changed_seen = true


func _poll_target_scene() -> void:
	var status := str(_iris_value("loading_status", "正在生成关卡"))
	_set_status(status)
	var target := get_tree().current_scene
	if target != null and target.has_method("hold_loading_render"):
		target.call("hold_loading_render")
	if bool(_iris_value("loading_scene_failed", false)):
		_scene_change_started = false
		_disconnect_scene_changed()
		_show_failure("map_bootstrap", status if not status.is_empty() else "关卡生成失败")
		return
	# complete_loading 可能上报 1；正式显示 100% 仍须经过 Tower ready 和渲染门禁。
	_apply_progress(clampf(float(_iris_value("loading_progress", 0.70)), 0.70, 0.96))
	if not _target_is_ready(target):
		return
	_finalizing = true
	if not _requires_loading_scene_ready_contract:
		await _wait_for_basic_scene_ready(target)
		if get_tree().current_scene != target or not is_instance_valid(target):
			_finalizing = false
			return
		_apply_progress(0.88)
		_report_loading(0.88, "基地场景已就绪")
	await _finish_loaded_scene(target)


func _target_is_ready(target: Node) -> bool:
	if not _scene_changed_seen or not _is_loading_scene(target):
		return false
	if bool(_iris_value("loading_scene_failed", false)):
		return false
	if not _requires_loading_scene_ready_contract:
		# 基地分帧装配时 Node.ready 先到；等待其持久化与出生点交接完成。
		return not bool(target.get_meta("loading_bootstrap_pending", false))
	return (
		bool(_iris_value("loading_scene_ready", false))
		# 父类 generation_completed/Node.ready 都早于 Tower 装配末尾，不能作为完成依据。
		and bool(target.get_meta("loading_scene_ready", false))
	)


func _is_loading_scene(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if IrisTransition != null and IrisTransition.has_method("is_loading_scene"):
		return bool(IrisTransition.is_loading_scene(node))
	return str(node.scene_file_path) == _target_scene


func _wait_for_basic_scene_ready(target: Node) -> void:
	var tree: SceneTree = get_tree()
	for _i: int in 2:
		await tree.process_frame
		if not _should_skip_delay():
			await RenderingServer.frame_post_draw
		if tree.current_scene != target:
			return


func _finish_loaded_scene(target: Node) -> void:
	var tree: SceneTree = get_tree()
	var settle_frames: int = 2 if _requires_loading_scene_ready_contract else 0
	for _i: int in settle_frames:
		await tree.process_frame
		if not _should_skip_delay():
			await RenderingServer.frame_post_draw
		if tree.current_scene != target or not _target_is_ready(target):
			_finalizing = false
			return
	_apply_progress(1.0)
	_report_loading(1.0, "读取完成")
	_set_status("读取完成")
	# 最低时长必须发生在内容淡出之前；否则兔子/文字会提前消失，只剩黑底等待。
	var elapsed_seconds := float(Time.get_ticks_msec() - _loading_started_msec) / 1000.0
	var remaining_seconds := maxf(0.0, MIN_LOADING_SCREEN_SECONDS - elapsed_seconds)
	if remaining_seconds > 0.0:
		_set_status("地图已就绪，正在完成过场…")
		await get_tree().create_timer(remaining_seconds).timeout
		if tree.current_scene != target or not _target_is_ready(target):
			_finalizing = false
			if _content != null:
				_content.modulate.a = 1.0
			return
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	if _content != null and not _should_skip_delay():
		var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade.tween_property(_content, "modulate:a", 0.0, 0.16)
		await fade.finished
	if tree.current_scene != target or not _target_is_ready(target):
		_finalizing = false
		if _content != null:
			_content.modulate.a = 1.0
		return
	if IrisTransition != null:
		IrisTransition.cover_now()
	# 首次世界渲染可能初始化 SDFGI/着色器。先结束读取页动画，再在全黑覆盖下
	# 预热目标的真实画面；玩家处理仍锁住，开圈时不再现建渲染管线。
	if target is Node3D:
		(target as Node3D).visible = bool(target.get_meta("loading_previous_visible", true))
	if target.has_method("prepare_loading_render"):
		target.call("prepare_loading_render")
	_restore_world_render()
	await _wait_for_basic_scene_ready(target)
	if tree.current_scene != target or not _target_is_ready(target):
		_finalizing = false
		return
	_disconnect_scene_changed()
	# 通过统一交接点恢复目标处理并清理读取契约；通知会让 Tower 恢复输入/子树。
	if IrisTransition != null:
		IrisTransition.release_loading_scene(target)
	else:
		target.process_mode = Node.PROCESS_MODE_INHERIT
	_scene_change_started = false
	if IrisTransition != null:
		IrisTransition.open_after_scene()
	# 先把开圈协程交给 autoload，再撤掉持久读取页；不在 free() 后继续执行。
	hide()
	queue_free()


func _disconnect_scene_changed() -> void:
	if get_tree() != null and get_tree().scene_changed.is_connected(_on_tree_scene_changed):
		get_tree().scene_changed.disconnect(_on_tree_scene_changed)


func _show_failure(kind: String, message: String) -> void:
	_failure_kind = kind
	_resource_request_active = false
	_finalizing = false
	_iris_set("loading_scene_ready", false)
	_iris_set("loading_scene_failed", true)
	_set_status(message)
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	if _content != null:
		_content.modulate.a = 1.0
	if IrisTransition != null:
		IrisTransition.clear_now()
	if _retry_button != null:
		_retry_button.visible = true
		_retry_button.text = "返回入口" if kind == "map_bootstrap" else "重试读取"
		_retry_button.grab_focus()
		# 目标场景可能捕获了鼠标；失败页必须能实际点到按钮。
		if not _should_skip_delay():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	push_warning("[ExpeditionLoadingScreen] " + message)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	if _step_label != null:
		_step_label.text = message
	_iris_set("loading_status", message)


func _on_retry_pressed() -> void:
	if _failure_kind == "map_bootstrap":
		_return_to_base()
		return
	if _scene_change_started:
		return
	if _retry_button != null:
		_retry_button.visible = false
	_failure_kind = ""
	_iris_set("loading_scene_failed", false)
	_apply_progress(0.0)
	_start_resource_request()


func _return_to_base() -> void:
	# 只登记内存入口意图；不结算、不改存档，避免基地按旧行动检查点再次跳回坏图。
	GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_ABORT_RETURN_99F,
		GameEntryFlow.SPAWN_TOWER03_ROOFTOP if str(BaseManager.get_active_run_checkpoint().get(ExpeditionEntryContext.SOURCE_KEY, "")) == ExpeditionEntryContext.TOWER03 else GameEntryFlow.SPAWN_BASE_99F
	)
	_failure_kind = ""
	_target_scene = GameDesignConfig.MAIN_SCENE
	_target_name = "塔3天台" if str(BaseManager.get_active_run_checkpoint().get(ExpeditionEntryContext.SOURCE_KEY, "")) == ExpeditionEntryContext.TOWER03 else "基地"
	_set_loading_contract()
	if _retry_button != null:
		_retry_button.visible = false
	_apply_progress(0.0)
	_start_resource_request()


## 本次要去的关卡 id。`_level_id` 为真源（_ready 时取），空则回退默认关卡。
func _destination_level_id() -> String:
	if _level_id.is_empty():
		return GameDesignConfig.default_expedition_level_id()
	return _level_id


## 本次要去的关卡场景。
func _destination_scene() -> String:
	if not _target_scene.is_empty():
		return _target_scene
	return GameDesignConfig.expedition_level_scene(_destination_level_id())


## 本次要去的关卡展示名。关卡清单里没有该 id 时返回 id 本身，至少不说谎。
func _destination_display_name() -> String:
	if not _target_name.is_empty():
		return _target_name
	var level_id := _destination_level_id()
	var display_name := GameDesignConfig.expedition_level_display_name(level_id)
	if display_name.is_empty():
		return level_id
	return display_name


func _play_intro() -> void:
	if _content == null:
		return
	_content.modulate.a = 0.0
	_intro_tween = create_tween()
	_intro_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(_content, "modulate:a", 1.0, 0.28)


func _apply_progress(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
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
	_build_status_controls(content)


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
	breadcrumb.text = "%s  →  %s" % ["塔3天台" if str(BaseManager.get_active_run_checkpoint().get(ExpeditionEntryContext.SOURCE_KEY, "")) == ExpeditionEntryContext.TOWER03 else "远征情报室", _destination_display_name()]
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


func _build_status_controls(content: Control) -> void:
	_status_label = Label.new()
	_status_label.name = "LoadingStatus"
	_status_label.text = "正在读取…"
	UIStyleFactory.apply_prism_label(_status_label, "label", 3, 18)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_status_label.offset_left = -WAVE_RIGHT_MARGIN - 320.0
	_status_label.offset_top = -(BAR_BOTTOM_MARGIN + BAR_HEIGHT + 42.0)
	_status_label.offset_right = -WAVE_RIGHT_MARGIN
	_status_label.offset_bottom = -(BAR_BOTTOM_MARGIN + BAR_HEIGHT + 12.0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_status_label)

	_retry_button = Button.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = "重试读取"
	_retry_button.visible = false
	_retry_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_retry_button.offset_left = -WAVE_RIGHT_MARGIN - 220.0
	_retry_button.offset_top = -(BAR_BOTTOM_MARGIN + BAR_HEIGHT + 96.0)
	_retry_button.offset_right = -WAVE_RIGHT_MARGIN
	_retry_button.offset_bottom = -(BAR_BOTTOM_MARGIN + BAR_HEIGHT + 52.0)
	_retry_button.pressed.connect(_on_retry_pressed)
	content.add_child(_retry_button)
	UIStyleFactory.apply_prism_button(_retry_button, "ghost", 2, 16, 2, "none")


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

	# 字宽必须用**同一个字体对象**量，否则按回退量出来的宽度会和棱镜字距对不上，
	# 波浪字母会互相挤在一起或散开。
	var font: Font = UIStyleFactory.make_prism_font(3)
	if font == null:
		font = ThemeDB.fallback_font
	var word := "LOADING"
	var cursor := 0.0
	_wave_slots.clear()
	for index in word.length():
		var letter := word.substr(index, 1)
		var label := Label.new()
		label.name = "L%d" % index
		label.text = letter
		label.add_theme_font_size_override("font_size", WAVE_FONT_SIZE)
		if font != null:
			label.add_theme_font_override("font", font)
		label.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
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
	# 该视口只负责读取界面的视觉展示，不应接收键盘/手柄输入。
	_showcase_viewport.gui_disable_input = true
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


func _restore_world_render() -> void:
	if _owns_world_render_gate and get_viewport() != null:
		get_viewport().disable_3d = _world_render_was_disabled
		_owns_world_render_gate = false


func _exit_tree() -> void:
	_restore_world_render()
