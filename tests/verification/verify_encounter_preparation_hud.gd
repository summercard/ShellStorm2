extends SceneTree
## 无Autoload纯表现专项；仅消费事件快照，不创建领域时钟。
const RING = preload("res://src/ui/EncounterCountdownRing.gd")
const OVERLAY = preload("res://src/ui/EncounterAlertOverlay.gd")
var checks := 0
var failures: Array[String] = []
var pulses: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run() -> void:
	var ring = RING.new()
	ring.size = Vector2(432, 36)
	root.add_child(ring)
	var label := Label.new()
	label.add_theme_color_override("font_color", RING.FILL_COLOR)
	ring.bind_label(label)
	var overlay = OVERLAY.new()
	root.add_child(overlay)
	var warning := Label.new()
	overlay.bind_warning_label(warning)
	ring.presentation_pulse_requested.connect(func(port, active): pulses.append([port, active]))
	var old := {"elapsed":38.0,"config":{"duration_sec":60.0}}
	ring.consume_snapshot(old)
	overlay.consume_snapshot(old)
	check(label.text == "0:22" and ring.visible and not overlay.visible, "未配置维持旧M:SS/金色环")
	check(ring.get_snapshot().fill_color == RING.FILL_COLOR, "旧环配色不变")
	ring.set_time(0.2,60)
	check(label.text == "0:01", "旧时间上取整不变")
	var row := {"instance_id":"prep#1","room_id":"room_03","config":{"alert_style":"red_eva","alert_text":"舱门封锁 · 接敌预警","alert_beep_interval_sec":0.5,"alert_pulse":true},"alert_phase":"preparation","alert_remaining_sec":3.0,"alert_total_sec":3.0,"alert_port_id":"B","paused":false}
	var original := row.duplicate(true)
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	check(label.text == "【接敌】 3.00 秒", "中文接敌/真实两位小数")
	check(warning.text == row.config.alert_text and overlay.visible, "实际消费自定义alert_text")
	check(ring.alert_port_id == "B" and overlay.alert_port_id == "B", "稳定端口透传")
	check(ring.get_snapshot().beep_requested and pulses.size() == 1, "red_eva首个蜂鸣")
	for repeat in 5:
		ring.consume_snapshot(row)
	check(pulses.size() == 1, "重复快照不重播")
	check(row == original, "不反写Owner配置/状态")
	await process_frame
	await process_frame
	check(ring.remaining_sec == 3.0 and label.text == "【接敌】 3.00 秒", "未收到快照不自行计时")
	for sample in [{"remaining":2.511,"text":"2.52","beep":false},{"remaining":2.5,"text":"2.50","beep":true},{"remaining":2.499,"text":"2.50","beep":false},{"remaining":2.0,"text":"2.00","beep":true},{"remaining":0.29,"text":"0.29","beep":true}]:
		row.alert_remaining_sec = sample.remaining
		ring.consume_snapshot(row)
		check(label.text == "【接敌】 %s 秒" % sample.text, "真实百分秒量化:"+str(sample.remaining))
		check(ring.get_snapshot().beep_requested == sample.beep, "0.5秒蜂鸣边界/掉帧不补播:"+str(sample.remaining))
		check(ring.get_snapshot().label_offset_px == 0.0, "不靠抖动或随机数制造快速末位")
	row.config.alert_pulse = false
	row.alert_remaining_sec = 0.2
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	var alpha: float = overlay.get_snapshot().edge_alpha
	row.alert_remaining_sec = 0.1
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	check(overlay.get_snapshot().edge_alpha == alpha and not ring.get_snapshot().impact_requested, "pulse=false关闭视觉脉冲/震屏")
	check(overlay.get_snapshot().pulse_hz <= 2.0, "红色视觉脉冲不超过2Hz")
	row.alert_phase = "intermission"
	row.alert_remaining_sec = 3.0
	row.alert_total_sec = 3.0
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	check(label.text == "【下一批接敌】 3.00 秒", "间歇使用同Owner时钟并显示下一批")
	check(ring.get_snapshot().beep_requested, "间歇重新开始蜂鸣档位")
	row.alert_remaining_sec = 2.2
	ring.consume_snapshot(row)
	row.alert_remaining_sec = 3.0
	ring.consume_snapshot(row)
	check(ring.get_snapshot().beep_requested, "相同phase下一批倒计时重置")
	row.paused = true
	row.alert_remaining_sec = 2.5
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	check(not ring.get_snapshot().beep_requested and not ring.get_snapshot().impact_requested, "暂停不发反馈")
	check(overlay.get_snapshot().edge_alpha == 0.48, "暂停恒亮")
	row.paused = false
	row.config.alert_pulse = true
	ring.set_reduce_motion(true)
	overlay.set_reduce_motion(true)
	row.alert_remaining_sec = 2.0
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	check(label.text == "【下一批接敌】 2 秒", "reduce_motion整秒")
	check(not ring.get_snapshot().impact_requested and overlay.get_snapshot().edge_alpha == 0.48, "reduce_motion无震屏/闪动")
	check(ring.remaining_sec == 2.0, "reduce_motion不改真实时间")
	row.alert_phase = ""
	row.alert_remaining_sec = 0.0
	row.alert_total_sec = 0.0
	ring.consume_snapshot(row)
	overlay.consume_snapshot(row)
	check(ring.visible and label.text == "【清除入侵者】" and not overlay.visible, "战斗期降级小提示无红边")
	check(not ring.get_snapshot().beep_requested, "战斗期无蜂鸣")
	for style in ["subtle", "none"]:
		row.config.alert_style = style
		row.alert_phase = "preparation"
		row.alert_remaining_sec = 2.0
		row.alert_total_sec = 2.0
		ring.consume_snapshot(row)
		overlay.consume_snapshot(row)
		check(not overlay.visible and not ring.get_snapshot().beep_requested and not ring.get_snapshot().impact_requested, style+"无红屏/震屏/蜂鸣")
		check(ring.visible == (style == "subtle"), style+"显隐")
	check(warning.text == row.config.alert_text, "文字不被固定WARNING覆盖")
	row.config.alert_style = "red_eva"
	row.erase("alert_phase")
	row.erase("alert_remaining_sec")
	row.erase("alert_total_sec")
	row.merge({"preparation_active":true,"preparation_remaining_sec":1.231,"preparation_total_sec":3.0})
	ring.set_reduce_motion(false)
	ring.consume_snapshot(row)
	check(label.text == "【接敌】 1.24 秒", "兼容preparation原字段")
	for style in ["red_eva", "subtle", "none"]:
		row.config.alert_style = style
		row.terminal = true
		ring.consume_snapshot(row)
		overlay.consume_snapshot(row)
		check(not ring.visible and not overlay.visible, "终态清理:"+style)
	ring.consume_snapshot({})
	overlay.consume_snapshot({})
	check(not ring.visible and not overlay.visible, "空快照清理")
	for control: Control in [ring,label,overlay,warning]:
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "所有控件鼠标穿透")
	check(not ring.has_method("_process") and not overlay.has_method("_process"), "无表现计时Owner")
	check(RING.format_preparation_time(0.001) == "0.01", "非零不提前归零")
	check(RING.format_preparation_time(65.21) == "65.21", "显示实际秒数而非分钟格式")
	check(float(RING.project_alert({"config":{"alert_style":"red_eva"}}).interval) == 1.0, "蜂鸣缺省1秒")
	ring.free()
	overlay.free()
	for failure in failures:
		push_error(failure)
	print("ENCOUNTER_ALERT_CONFIG_HUD_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
