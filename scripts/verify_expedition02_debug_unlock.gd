extends Node
## 只读+受控写入探针：验证 P 键调试面板「预留」页的远征02 一键解锁。
##
## 覆盖三件事：
##   ① 面板脚本可加载；「预留」页已建；tab 按钮不再是 disabled
##   ② 按钮真的能改写解锁标志并落盘（走 BaseManager 正式保存口）
##   ③ 反向按钮能把关卡退回未解锁（证明标志不是单向写死的）
##
## 结束状态刻意留在「已解锁」—— 业主本轮就是要它解锁。
## 运行：godot --headless --path <项目> res://scripts/verify_expedition02_debug_unlock.tscn

const LEVEL_ID := "expedition_02"

var _fails: Array[String] = []


func _fail(message: String) -> void:
	_fails.append(message)
	push_error("[PROBE] %s" % message)


func _ready() -> void:
	await _run()
	if _fails.is_empty():
		print("EXPEDITION02_DEBUG_UNLOCK_VERIFY_OK")
	else:
		print("EXPEDITION02_DEBUG_UNLOCK_VERIFY_FAIL count=%d" % _fails.size())
		for message in _fails:
			print("   - %s" % message)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var original := BaseManager.is_expedition_level_unlocked(LEVEL_ID)
	print("初始状态 expedition_02 unlocked = %s" % str(original))

	# ---- ① 面板脚本与「预留」页 ----
	var script: GDScript = load("res://src/player3d/FlashlightColorTweaker.gd")
	if script == null:
		_fail("调试面板脚本加载失败（多半是解析错误）")
		return

	var panel := script.new() as PanelContainer
	if panel == null:
		_fail("调试面板脚本实例化失败")
		return
	add_child(panel)
	await get_tree().process_frame

	var pages: Dictionary = panel.get("_tab_pages")
	if not pages.has(3):
		_fail("「预留」页（TabId.RESERVED_3）没有建出来")
	var tab_button := panel.get_node_or_null("Root/TabBar/TabButton_3") as Button
	if tab_button == null:
		_fail("找不到预留 tab 按钮 TabButton_3")
	elif tab_button.disabled:
		_fail("预留 tab 仍是 disabled，点不进去")

	var unlock_button := panel.get_node_or_null(
		"Root/ReservedPage/UnlockExpedition02Button"
	) as Button
	var relock_button := panel.get_node_or_null(
		"Root/ReservedPage/RelockExpedition02Button"
	) as Button
	if unlock_button == null:
		_fail("「预留」页里找不到一键解锁按钮")
	if relock_button == null:
		_fail("「预留」页里找不到回退按钮")
	if unlock_button == null:
		return
	print("「预留」页 OK：tab 已启用，解锁 / 回退按钮就位")

	# ---- ② 先退到未解锁，再按解锁按钮 ----
	BaseManager.debug_relock_expedition_level(LEVEL_ID)
	if BaseManager.is_expedition_level_unlocked(LEVEL_ID):
		_fail("回退失败：按回退接口后仍为已解锁")

	unlock_button.emit_signal("pressed")
	await get_tree().process_frame
	if not BaseManager.is_expedition_level_unlocked(LEVEL_ID):
		_fail("按了「一键解锁」但解锁标志没变")
	else:
		print("一键解锁 OK：is_expedition_level_unlocked = true")

	# ---- ③ 落盘复核：直接读回存档，确认不是只改了内存 ----
	# 项目把「从 Variant 推断类型」当错误 ⇒ 返回 Variant 的函数必须显式标注。
	var persisted: Variant = _read_persisted_flag()
	if persisted == null:
		_fail("存档里读不到 expedition_02_unlocked 字段（可能被别的进程覆盖过）")
	elif not bool(persisted):
		_fail("内存已解锁但存档里仍是 false —— 没落盘")
	else:
		print("落盘 OK：存档 payload.expedition_02_unlocked = true")

	# ---- ④ 回退按钮也得有牙（否则标志是单向的，没法复测正式流程）----
	relock_button.emit_signal("pressed")
	await get_tree().process_frame
	if BaseManager.is_expedition_level_unlocked(LEVEL_ID):
		_fail("按了「恢复未解锁」但标志没变")
	else:
		print("回退按钮 OK")

	# ---- ⑤ 结束状态留在「已解锁」----
	unlock_button.emit_signal("pressed")
	await get_tree().process_frame
	if not BaseManager.is_expedition_level_unlocked(LEVEL_ID):
		_fail("收尾解锁失败")
	else:
		var final_value: Variant = _read_persisted_flag()
		if final_value == null or not bool(final_value):
			_fail("收尾解锁没落盘")
		else:
			print("收尾 OK：最终状态 = 已解锁且已落盘")

	# ---- ⑥ 抗覆盖：模拟别的 Godot 实例把存档里的标志冲回 false ----
	# 覆盖文件独立于 base_save.json，所以此时仍应判为已解锁 ——
	# 这正是本机制存在的理由（实测有长驻实例每 ~10s 回写存档）。
	BaseManager.data.expedition_02_unlocked = false
	if not BaseManager.is_expedition_level_unlocked(LEVEL_ID):
		_fail("存档标志被冲掉后解锁失效 —— 调试覆盖没生效")
	else:
		print("抗覆盖 OK：存档标志置 false 后仍判为已解锁（覆盖文件生效）")


func _read_persisted_flag() -> Variant:
	var path := str(BaseManager.save_path)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	var envelope := parsed as Dictionary
	if not envelope.has("payload"):
		return null
	var payload := envelope["payload"] as Dictionary
	if not payload.has("expedition_02_unlocked"):
		return null
	return payload["expedition_02_unlocked"]
