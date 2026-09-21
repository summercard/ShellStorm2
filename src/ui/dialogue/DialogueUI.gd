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
const MARGIN_SIDE := 96.0
const MARGIN_BOTTOM := 34.0
const PANEL_HEIGHT := 122.0
const DEFAULT_CHARS_PER_SEC := 30.0
const DEFAULT_AUTO_ADVANCE_S := 3.2
const SPEAKER_SYSTEM := "系统"

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
	if _paused:
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


func _unhandled_input(event: InputEvent) -> void:
	if _paused:
		return
	if not _active or _typing:
		# 打字中按确认键 = 立即全显（仍消费该次输入）
		if _active and event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_reveal_all()
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_step_next()


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


## 推进：打字中 → 立即全显；已全显 → 下一行。
func advance() -> bool:
	if not _active:
		return false
	if _typing:
		_reveal_all()
		return true
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
	_panel.add_theme_stylebox_override("panel", UIStyleFactory.make_tactical_panel())
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN_SIDE
	_panel.offset_right = -MARGIN_SIDE
	_panel.offset_top = -(PANEL_HEIGHT + MARGIN_BOTTOM)
	_panel.offset_bottom = -MARGIN_BOTTOM
	root.add_child(_panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	_speaker_label = UIStyleFactory.make_outline_label("", UIPalette.NEON_CYAN)
	_speaker_label.name = "Speaker"
	_speaker_label.add_theme_font_size_override("font_size", 15)
	column.add_child(_speaker_label)

	_text_label = UIStyleFactory.make_outline_label("", UIPalette.TEXT_PRIMARY)
	_text_label.name = "Text"
	_text_label.add_theme_font_size_override("font_size", 19)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text_label)

	_hint_label = UIStyleFactory.make_outline_label("[回车] 继续", UIPalette.TEXT_SECONDARY)
	_hint_label.name = "Hint"
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint_label)
