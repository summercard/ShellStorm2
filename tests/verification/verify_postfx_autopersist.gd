extends Node
## 验收：FlashlightColorTweaker 的后处理参数自动持久化（改动即落盘 + 启动自动恢复）。
##
## 正向：改滑条 -> 防抖(0.4s) -> user://postfx_tuning.json 出现该值。
## 反向对照 A：清空内存覆盖后新建面板 -> 值只能来自文件，必须被读回。
## 反向对照 B：把文件里的值改成第三个数 -> 重读必须跟着变（排除“巧合默认值”）。
## 防假绿哨兵：checks 计数低于下限直接判失败；打印实际比对样本数。
##
## ⚠️ 验收会真实改写 user://postfx_tuning.json（那是玩家的实际滤镜参数），
##    因此开头先快照、结束（含失败路径）无条件还原，避免污染真实画面。
##
## 跑法：--headless --path . res://tests/verification/verify_postfx_autopersist.tscn

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const PANEL_PATH := "FlashlightTweakerLayer/FlashlightColorTweaker"
const PERSIST_PATH := "user://postfx_tuning.json"

const PROBE_BRIGHTNESS := 1.37
const PROBE_SATURATION := 0.42
const PROBE_TAMPERED := 0.63
# 实际断言数：brightness / saturation / restored_brightness / restored_saturation / tampered
const MIN_CHECKS := 5

var _checks := 0
var _original_exists := false
var _original_text := ""


func _ready() -> void:
	await _run()


func _run() -> void:
	_capture_original()
	# 干净起点：先删历史文件，确保后面读到的一定是本次写出来的。
	if FileAccess.file_exists(PERSIST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PERSIST_PATH))

	var player := await _spawn_player()
	var panel := player.get_node_or_null(PANEL_PATH)
	if panel == null:
		_fail("panel_missing")
		return

	# ---------- 正向：改动 -> 防抖 -> 落盘 ----------
	panel._postfx_brightness_slider.value = PROBE_BRIGHTNESS
	panel._postfx_saturation_slider.value = PROBE_SATURATION
	# 必须大于 FlashlightColorTweaker.PERSIST_DEBOUNCE_SECONDS(0.4)。
	await get_tree().create_timer(0.9).timeout

	if not FileAccess.file_exists(PERSIST_PATH):
		_fail("no_file_after_change")
		return
	var written := _read_params()
	if not _expect(written.get("debug_postfx_adjustment_brightness", null), PROBE_BRIGHTNESS, "brightness_persisted"):
		return
	if not _expect(written.get("debug_postfx_adjustment_saturation", null), PROBE_SATURATION, "saturation_persisted"):
		return

	# ---------- 反向对照 A：内存清空，值只能从文件回来 ----------
	GraphicsSettingsManager.clear_debug_postfx()
	player.queue_free()
	await get_tree().process_frame
	var player2 := await _spawn_player()
	var panel2 := player2.get_node_or_null(PANEL_PATH)
	if panel2 == null:
		_fail("panel2_missing")
		return
	if not _expect(panel2._postfx_brightness_slider.value, PROBE_BRIGHTNESS, "restored_brightness_from_file"):
		return
	if not _expect(panel2._postfx_saturation_slider.value, PROBE_SATURATION, "restored_saturation_from_file"):
		return

	# ---------- 反向对照 B：改文件 -> 读回必须跟着变 ----------
	var tampered := written.duplicate()
	tampered["debug_postfx_adjustment_brightness"] = PROBE_TAMPERED
	_write_params(tampered)
	GraphicsSettingsManager.clear_debug_postfx()
	player2.queue_free()
	await get_tree().process_frame
	var player3 := await _spawn_player()
	var panel3 := player3.get_node_or_null(PANEL_PATH)
	if panel3 == null:
		_fail("panel3_missing")
		return
	if not _expect(panel3._postfx_brightness_slider.value, PROBE_TAMPERED, "tampered_value_followed"):
		return

	if _checks < MIN_CHECKS:
		_fail("too_few_checks_%d" % _checks)
		return
	_restore_original()
	print("[POSTFX_AUTOPERSIST] POSTFX_AUTOPERSIST_OK checks=%d panels=%d" % [_checks, 3])
	get_tree().quit(0)


func _capture_original() -> void:
	_original_exists = FileAccess.file_exists(PERSIST_PATH)
	if not _original_exists:
		return
	var file := FileAccess.open(PERSIST_PATH, FileAccess.READ)
	if file != null:
		_original_text = file.get_as_text()
		file.close()


func _restore_original() -> void:
	if _original_exists:
		var file := FileAccess.open(PERSIST_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_original_text)
			file.close()
	elif FileAccess.file_exists(PERSIST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PERSIST_PATH))


func _spawn_player() -> Node:
	var player := PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	return player


func _expect(actual: Variant, want: float, tag: String) -> bool:
	_checks += 1
	if actual == null:
		_fail("%s_null" % tag)
		return false
	if not is_equal_approx(float(actual), want):
		_fail("%s_got_%s_expect_%s" % [tag, str(actual), str(want)])
		return false
	return true


func _fail(reason: String) -> void:
	printerr("[POSTFX_AUTOPERSIST] FAIL %s checks=%d" % [reason, _checks])
	_restore_original()
	get_tree().quit(1)


func _read_params() -> Dictionary:
	var file := FileAccess.open(PERSIST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text().strip_edges()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _write_params(values: Dictionary) -> void:
	var file := FileAccess.open(PERSIST_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(values) + "\n")
		file.close()
