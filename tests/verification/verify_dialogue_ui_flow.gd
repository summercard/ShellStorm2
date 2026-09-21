extends Node
## 屏幕底栏对话系统验收：**不加载剧情系统、不加载关卡、不加载任何角色**。
## 这正是把对话 UI 切成独立系统的价值 —— 它应当能被独立验收。
##
## 覆盖：层级、打字机进度、advance 全显、自动推进、close 中断、
##       outcome 三态区分、空文本忽略、与移动端输入层的层级关系。

const OUTCOME_COMPLETED := "completed"
const OUTCOME_ABORTED := "aborted"
const EXPECTED_LAYER := 100
const MOBILE_INPUT_LAYER := 128

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await get_tree().process_frame
	var ui := _ui()
	if ui == null:
		push_error("DIALOGUE_UI_FAIL: DialogueUI autoload 不存在（project.godot 未注册？）")
		get_tree().quit(1)
		return

	_check_layer(ui)
	await _check_typing_progress(ui)
	await _check_advance_reveals_all(ui)
	await _check_auto_advance_completes(ui)
	await _check_close_aborts(ui)
	_check_empty_text_ignored(ui)
	_finish()


func _ui() -> Node:
	return get_node_or_null("/root/DialogueUI")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _reset(ui: Node) -> void:
	if bool(ui.call("is_active")):
		ui.call("close")
	await get_tree().process_frame


func _check_layer(ui: Node) -> void:
	_expect(int(ui.get("layer")) == EXPECTED_LAYER,
		"对话 UI 层级应为 %d，实际 %s" % [EXPECTED_LAYER, ui.get("layer")])
	# 移动端输入层必须仍在对话之上，否则触屏按钮会被底栏盖住点不到。
	_expect(EXPECTED_LAYER < MOBILE_INPUT_LAYER,
		"对话层级 %d 不得高于移动端输入层 %d" % [EXPECTED_LAYER, MOBILE_INPUT_LAYER])


func _check_typing_progress(ui: Node) -> void:
	await _reset(ui)
	var run_id: String = ui.call("announce", "欢迎回到基地。", 0.0)
	_expect(not run_id.is_empty(), "announce() 未返回 run_id")
	_expect(bool(ui.call("is_active")), "announce() 之后未进入激活态")
	_expect(str(ui.call("current_speaker")) == "系统",
		"系统提示的说话人应为『系统』，实际『%s』" % ui.call("current_speaker"))
	var total := int(ui.call("total_char_count"))
	_expect(total > 0, "文本长度为 0，无法验证打字机")
	var early := int(ui.call("visible_char_count"))
	_expect(early < total, "刚显示时已全显，打字机未生效（总长 %d）" % total)
	await get_tree().create_timer(0.35).timeout
	var later := int(ui.call("visible_char_count"))
	_expect(later > early, "打字机没有推进（early=%d later=%d）" % [early, later])
	_expect(later <= total, "可见字符数超过了文本总长")
	ui.call("close")


func _check_advance_reveals_all(ui: Node) -> void:
	await _reset(ui)
	ui.call("announce", "这是一句足够长的系统提示文本。", 0.0)
	await get_tree().process_frame
	_expect(bool(ui.call("is_typing")), "长文本应当处于打字中")
	ui.call("advance")
	_expect(not bool(ui.call("is_typing")), "advance() 之后仍在打字中")
	_expect(int(ui.call("visible_char_count")) == int(ui.call("total_char_count")),
		"advance() 未把文字立即全显（%s/%s）" % [ui.call("visible_char_count"), ui.call("total_char_count")])
	# 已全显时再 advance = 进入下一行；只有一行时应直接结束。
	ui.call("advance")
	_expect(not bool(ui.call("is_active")), "单行文本推进两次后应结束")


func _check_auto_advance_completes(ui: Node) -> void:
	await _reset(ui)
	var record := {"count": 0, "outcome": "", "run_id": ""}
	var recorder := func(run_id: String, outcome: String) -> void:
		record["count"] = int(record["count"]) + 1
		record["outcome"] = outcome
		record["run_id"] = run_id
	ui.connect("dialogue_finished", recorder)
	ui.call("announce", "短句。", 0.35)
	await get_tree().create_timer(1.4).timeout
	ui.disconnect("dialogue_finished", recorder)
	_expect(int(record["count"]) == 1, "自动推进应恰好结束一次，实际 %d 次" % record["count"])
	_expect(str(record["outcome"]) == OUTCOME_COMPLETED,
		"自动结束的 outcome 应为 %s，实际 %s" % [OUTCOME_COMPLETED, record["outcome"]])
	_expect(not bool(ui.call("is_active")), "自动结束后仍处于激活态")


func _check_close_aborts(ui: Node) -> void:
	await _reset(ui)
	var record := {"outcome": ""}
	var recorder := func(_run_id: String, outcome: String) -> void:
		record["outcome"] = outcome
	ui.connect("dialogue_finished", recorder)
	ui.call("announce", "还没播完就被打断。", 0.0)
	await get_tree().process_frame
	ui.call("close")
	await get_tree().process_frame
	ui.disconnect("dialogue_finished", recorder)
	_expect(not bool(ui.call("is_active")), "close() 之后仍处于激活态")
	# aborted 必须与 completed 区分：调用方据此判断"是否真的播完"。
	_expect(str(record["outcome"]) == OUTCOME_ABORTED,
		"close() 的 outcome 应为 %s，实际 %s" % [OUTCOME_ABORTED, record["outcome"]])
	_expect(str(record["outcome"]) != OUTCOME_COMPLETED, "close() 不得被当成正常播完")


func _check_empty_text_ignored(ui: Node) -> void:
	var run_id: String = ui.call("announce", "   ", 0.0)
	_expect(run_id.is_empty(), "空白文本应返回空 run_id 且不驱动 UI")
	_expect(not bool(ui.call("is_active")), "空白文本不应让对话变为激活态")


func _finish() -> void:
	if checks == 0:
		push_error("DIALOGUE_UI_FAIL: 没有任何断言被执行（防假绿哨兵）")
		get_tree().quit(1)
		return
	print("DIALOGUE_UI_SAMPLES: checks=%d" % checks)
	if failures.is_empty():
		print("DIALOGUE_UI_OK: 层级 / 打字机进度 / 立即全显 / 自动推进 / 中断 / 三态 outcome / 空文本忽略 全部通过")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("DIALOGUE_UI_FAIL: " + failure)
	get_tree().quit(1)
