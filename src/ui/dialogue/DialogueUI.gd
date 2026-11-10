extends CanvasLayer
## 屏幕底栏对话系统：**系统 / 画外音**的台词载体。
##
## 定位（[技术架构总则](../../docs/v0.1/02_技术架构总则.md) §4 五层、§8 依赖方向）：
##   本系统**独立**，不认识剧情、不认识基地、不认识玩家、不认识任何玩法系统；
##   它只认"谁在什么时候说什么"。任何系统都可以调用 show_message() / show_lines()。
##   它不判断该不该说话（那是调用方的权力），不持有玩法状态，也不写存档。
##
## 与 3D 头顶气泡的分工（[18 号文档](../../docs/v0.1/18_技术施工_UI与对话系统.md) §1.1）：
##   - 说话人**有实体**（玩家 / NPC / 敌人）→ 头顶气泡 SpeechBubble3D
##   - 说话人**无实体**（系统、旁白、区域播报）→ 本系统
##
## 注册为 autoload：对话是跨场景能力（基地 / 塔楼 / 远征都要用）。
## 注意：_ready() 里**不得**触碰 user:// —— 本工程 runner 尚未隔离用户数据目录，
## 自动测试会在 Autoload 启动前污染正式存档（见 AGENTS.md）。

signal dialogue_shown(run_id: String, line_id: String)
signal line_finished(run_id: String, line_id: String)
signal dialogue_finished(run_id: String, outcome: String)

## 层级取模态档（与设施菜单同档，低于移动端输入层 128）。
## 数值只在这里定义一处，不在场景里另写。
const LAYER := 100
## 底栏宽度占视口比例（左右各 15%）。
##
## 业主 2026-11-10 给的范围图：1080 宽下红框 x=180→935，即 **70%**、居中偏左一点。
## 原来是 `MARGIN_SIDE=96` 的“满屏减两边”（1080 下占 82%），看着像一条通栏横幅；
## 收窄到 70% 后才是“对话框”的比例。字号不动（业主：“就用原来的字体和大小”）。
const PANEL_SIDE_RATIO := 0.15
const MARGIN_BOTTOM := 24.0
const PANEL_HEIGHT := 118.0
const DEFAULT_CHARS_PER_SEC := 30.0
const DEFAULT_AUTO_ADVANCE_S := 3.2
const SPEAKER_SYSTEM := "系统"
## 玩家自己说话时的署名。剧情里主角是台机器人，没有名字，NPC 也从不呼名。
const SPEAKER_PLAYER := "主角"

const OUTCOME_COMPLETED := "completed"
const OUTCOME_SKIPPED := "skipped"
const OUTCOME_ABORTED := "aborted"

var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _hint_label: Label

var _lines: Array[Dictionary] = []
var _index := 0
var _run_seq := 0
var _run_id := ""
var _elapsed := 0.0
var _auto_left := 0.0
var _typing := false
var _active := false
var _last_input_frame := -1
var _advance_input_handler := Callable()
var _mouse_available_handler := Callable()
var _mouse_advance_handler := Callable()
var _mouse_left_down := false
var _mouse_dialogue_hold := false
var _mouse_poll_observed_down := false
var _mouse_window_focused := true
var _mouse_press_event_id := 0
var _mouse_consumed_frame := -1
var _mouse_consumed_physics_frame := -1
## 显式暂停标志。本节点是 PROCESS_MODE_ALWAYS（跨场景系统，改 process_mode
## 会波及它自己的独立验收），所以树暂停时它仍会打字并自动推进 ——
## 由剧情系统在暂停切换时调用 set_paused() 同步冻结（08 文档 §6.3 / §8.4）。
var _paused := false


## 剧情系统的暂停同步入口。冻结打字进度与自动推进计时，不关闭、不清行。
func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_shown(false)


func _process(delta: float) -> void:
	_sync_mouse_release()
	if _paused or get_tree().paused:
		return
	if not _active:
		return
	var line := _current_line()
	if line.is_empty():
		return
	if _typing:
		_advance_typing(delta, line)
		return
	if _auto_left > 0.0:
		_auto_left -= delta
		if _auto_left <= 0.0:
			_auto_left = 0.0
			_step_next()


func _input(event: InputEvent) -> void:
	consume_advance_input(event)


func _unhandled_input(event: InputEvent) -> void:
	consume_advance_input(event)


func consume_advance_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return _consume_mouse_advance(event as InputEventMouseButton)
	if _paused or get_tree().paused or not _active:
		return false
	var key := event as InputEventKey
	var is_space := key != null and (key.keycode == KEY_SPACE or key.physical_keycode == KEY_SPACE)
	if not is_space and not event.is_action("ui_accept"):
		return false
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return true
	var frame := Engine.get_process_frames()
	if frame == _last_input_frame:
		return true
	_last_input_frame = frame
	if _advance_input_handler.is_valid() and bool(_advance_input_handler.call()):
		return true
	advance()
	return true


func set_advance_input_handler(handler: Callable) -> void:
	_advance_input_handler = handler


func set_mouse_advance_handlers(available: Callable, advance_handler: Callable) -> void:
	_mouse_available_handler = available
	_mouse_advance_handler = advance_handler


func _has_mouse_dialogue() -> bool:
	return _active or (_mouse_available_handler.is_valid() and bool(_mouse_available_handler.call()))


func _consume_mouse_advance(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var was_down := _mouse_left_down
	_mouse_left_down = event.pressed
	if event.pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_poll_observed_down = true
	if _paused or get_tree().paused or not _mouse_window_focused:
		if not event.pressed:
			_clear_mouse_hold()
		return false
	if not event.pressed:
		var owned := _mouse_dialogue_hold
		_clear_mouse_hold()
		if owned:
			_mark_mouse_consumed()
			get_viewport().set_input_as_handled()
		return owned
	if not _has_mouse_dialogue() and not _mouse_dialogue_hold:
		return false
	_mouse_dialogue_hold = true
	_mark_mouse_consumed()
	get_viewport().set_input_as_handled()
	if was_down or event.is_echo() or event.get_instance_id() == _mouse_press_event_id:
		return true
	_mouse_press_event_id = event.get_instance_id()
	var frame := Engine.get_process_frames()
	if frame == _last_input_frame:
		return true
	_last_input_frame = frame
	if _mouse_advance_handler.is_valid() and bool(_mouse_advance_handler.call()):
		return true
	advance()
	return true


func _mark_mouse_consumed() -> void:
	_mouse_consumed_frame = Engine.get_process_frames()
	_mouse_consumed_physics_frame = Engine.get_physics_frames()


func _clear_mouse_hold() -> void:
	if _mouse_dialogue_hold:
		_mark_mouse_consumed()
	_mouse_dialogue_hold = false
	_mouse_left_down = false
	_mouse_poll_observed_down = false


func _sync_mouse_release() -> void:
	if not _mouse_window_focused:
		return
	var physical_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _mouse_left_down and physical_down:
		_mouse_poll_observed_down = true
	# 仅曾被Input轮询确认的按压允许自动纠偏；Viewport/直接注入未更新Input的测试不误清。
	if _mouse_dialogue_hold and _mouse_poll_observed_down and not physical_down:
		_clear_mouse_hold()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_mouse_window_focused = false
		_clear_mouse_hold()
		_mark_mouse_consumed()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_mouse_window_focused = true
		_mark_mouse_consumed()


## 消费按压持有至release；物理release丢事件时校正，恢复/释放当帧不击发。
func is_dialogue_mouse_fire_blocked() -> bool:
	_sync_mouse_release()
	return not _mouse_window_focused or _mouse_dialogue_hold or _mouse_consumed_frame == Engine.get_process_frames() or _mouse_consumed_physics_frame == Engine.get_physics_frames()


## 播放一组台词。返回 run_id；lines 为空时返回空串。
func show_lines(request: Dictionary) -> String:
	var raw: Array = request.get("lines", [])
	if raw.is_empty():
		return ""
	if _active and not bool(request.get("interrupt", true)):
		# v1 不支持排队（没有多来源同时抢底栏的场景）；按调用方语义忽略。
		return ""
	_run_seq += 1
	_run_id = "dlg_%d" % _run_seq
	_lines.clear()
	for entry in raw:
		_lines.append(_normalize_line(entry))
	_index = 0
	_active = true
	_set_shown(true)
	_present_current()
	return _run_id


## 便捷入口：一句话。auto_advance_sec <= 0 表示等玩家按键推进。
func show_message(
	text: String,
	speaker := SPEAKER_SYSTEM,
	auto_advance_sec := DEFAULT_AUTO_ADVANCE_S,
	line_id := ""
) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return ""
	return show_lines({
		"lines": [{
			"line_id": line_id if not line_id.is_empty() else "inline",
			"speaker": speaker,
			"text": clean,
			"chars_per_sec": DEFAULT_CHARS_PER_SEC,
			"auto_advance_sec": auto_advance_sec,
		}],
		"interrupt": true,
	})


## 系统提示便捷入口：说话人固定为"系统"，默认自动消失（不打断玩家操作）。
func announce(text: String, auto_advance_sec := DEFAULT_AUTO_ADVANCE_S) -> String:
	return show_message(text, SPEAKER_SYSTEM, auto_advance_sec)


## 一句**对话**（实体角色说的）。底栏是对话文字的唯一载体（业主 2026-11-10），
## 头顶气泡只做示意。
##
## `auto_advance_sec < 0` 时按字数估算停留，保证“读完再收”；
## 传具体秒数时按调用方的节奏（剧情时间轴就是这么用的）。
func show_dialogue_line(text: String, speaker: String, auto_advance_sec := -1.0) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return ""
	var hold := auto_advance_sec if auto_advance_sec > 0.0 else line_hold_for_text(clean)
	return show_lines({
		"lines": [{
			"line_id": "inline",
			"speaker": speaker,
			"text": clean,
			"chars_per_sec": DEFAULT_CHARS_PER_SEC,
			"auto_advance_sec": hold,
		}],
		"interrupt": true,
	})


## 打完字后该停多久（秒）。
##
## 不盘到“总时长”口径：底栏自己还要按 30 字/秒逐字敲，那段已经占掉了。
## 这里只算**阅读停留**：20 字 → 3.07s，与旧气泡的 `hold_seconds=3.4` 同一个量级。
static func line_hold_for_text(text: String) -> float:
	return clampf(1.4 + float(text.strip_edges().length()) / 12.0, 1.8, 5.0)


## 推进：打字中 → 立即全显；已全显 → 下一行。
func advance() -> bool:
	if not _active:
		return false
	if _typing:
		_reveal_all()
		return true
	_step_next()
	return true


func reveal_all() -> void:
	_reveal_all()


func has_next_line() -> bool:
	return _active and _index + 1 < _lines.size()


func current_line_index() -> int:
	return _index


func finish_current_hold() -> bool:
	if not _active or _typing:
		return false
	_step_next()
	return true


func skip() -> bool:
	if not _active:
		return false
	_finish(OUTCOME_SKIPPED)
	return true


func close() -> void:
	if not _active:
		return
	_finish(OUTCOME_ABORTED)


func is_active() -> bool:
	return _active


## 当前正在播的 run_id；没有在播时为空串。
## 供调用方（剧情系统收口）判断「底栏现在挂着的这条，还是不是我摆上去的那条」——
## 已经不是了就不该去关它（那是别人的消息）。
func current_run_id() -> String:
	return _run_id


func is_typing() -> bool:
	return _typing


func current_speaker() -> String:
	return str(_current_line().get("speaker", ""))


func current_text() -> String:
	return _text_label.text if _text_label != null else ""


## 已显示字符数 —— 供验收检查打字机进度（不是"节点存在"这类假绿判据）。
func visible_char_count() -> int:
	return _text_label.visible_characters if _text_label != null else 0


func total_char_count() -> int:
	return _text_label.text.length() if _text_label != null else 0


func _current_line() -> Dictionary:
	if _index < 0 or _index >= _lines.size():
		return {}
	return _lines[_index]


func _normalize_line(entry: Dictionary) -> Dictionary:
	var text := str(entry.get("text", "")).strip_edges()
	return {
		"line_id": str(entry.get("line_id", "inline")),
		"speaker": str(entry.get("speaker", SPEAKER_SYSTEM)),
		"text": text,
		"chars_per_sec": float(entry.get("chars_per_sec", DEFAULT_CHARS_PER_SEC)),
		"auto_advance_sec": float(entry.get("auto_advance_sec", 0.0)),
	}


func _present_current() -> void:
	var line := _current_line()
	if line.is_empty():
		_finish(OUTCOME_COMPLETED)
		return
	_speaker_label.text = str(line["speaker"])
	_speaker_label.visible = not _speaker_label.text.is_empty()
	_text_label.text = str(line["text"])
	_text_label.visible_characters = 0
	_elapsed = 0.0
	_auto_left = 0.0
	_typing = _text_label.text.length() > 0
	if not _typing:
		_on_line_typed(line)
	_hint_label.visible = float(line["auto_advance_sec"]) <= 0.0
	dialogue_shown.emit(_run_id, str(line["line_id"]))


func _advance_typing(delta: float, line: Dictionary) -> void:
	var per_second := float(line["chars_per_sec"])
	var total := _text_label.text.length()
	if per_second <= 0.0:
		_text_label.visible_characters = total
	else:
		_elapsed += delta
		_text_label.visible_characters = mini(total, int(floor(_elapsed * per_second)))
	if _text_label.visible_characters >= total:
		_on_line_typed(line)


func _reveal_all() -> void:
	if not _typing:
		return
	_text_label.visible_characters = _text_label.text.length()
	_on_line_typed(_current_line())


func _on_line_typed(line: Dictionary) -> void:
	if not _typing:
		return
	_typing = false
	line_finished.emit(_run_id, str(line.get("line_id", "inline")))
	_auto_left = float(line.get("auto_advance_sec", 0.0))


func _step_next() -> void:
	if not _active:
		return
	_index += 1
	if _index >= _lines.size():
		_finish(OUTCOME_COMPLETED)
		return
	_present_current()


func _finish(outcome: String) -> void:
	var finished_run := _run_id
	_active = false
	_typing = false
	_lines.clear()
	_index = 0
	_run_id = ""
	_set_shown(false)
	dialogue_finished.emit(finished_run, outcome)


func _set_shown(shown: bool) -> void:
	if _panel == null:
		return
	_panel.visible = shown
	if not shown:
		_text_label.text = ""
		_text_label.visible_characters = 0
		_speaker_label.text = ""


func _build() -> void:
	var root := Control.new()
	root.name = "DialogueRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 叙事底栏：棱镜模态面板（冷蓝半透 + 1px 次级白线，全方角）。内容边距与旧战术面板逐值一致。
	var dialogue_panel_style := UIStyleFactory.make_prism_panel(true, 0.62)
	dialogue_panel_style.content_margin_left = 14.0
	dialogue_panel_style.content_margin_right = 14.0
	dialogue_panel_style.content_margin_top = 10.0
	dialogue_panel_style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", dialogue_panel_style)
	# 按视口比例定宽（不是固定像素边距）：换分辨率时框始终是屏幕的 70%，
	# 不会在 21:9 上拉成通栏、也不会在 4:3 上挤成方块。
	_panel.anchor_left = PANEL_SIDE_RATIO
	_panel.anchor_right = 1.0 - PANEL_SIDE_RATIO
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = -(PANEL_HEIGHT + MARGIN_BOTTOM)
	_panel.offset_bottom = -MARGIN_BOTTOM
	root.add_child(_panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	_speaker_label = UIStyleFactory.make_outline_label("", UIPalette.PRISM_LABEL)
	_speaker_label.name = "Speaker"
	UIStyleFactory.apply_prism_label(_speaker_label, "label", 3, 15)
	column.add_child(_speaker_label)

	_text_label = UIStyleFactory.make_outline_label("", UIPalette.PRISM_TEXT)
	_text_label.name = "Text"
	UIStyleFactory.apply_prism_label(_text_label, "value", 1, 19)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text_label)

	_hint_label = UIStyleFactory.make_outline_label("[左键/空格/回车] 继续", UIPalette.PRISM_TEXT_FAINT)
	_hint_label.name = "Hint"
	UIStyleFactory.apply_prism_label(_hint_label, "faint", 1, 13)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint_label)
