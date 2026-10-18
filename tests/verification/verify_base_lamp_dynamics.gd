extends Node
## 验收：99F 基地灯具动态 `BaseLampDynamics3D`。
##
## 判据全部可失败，不允许「看着差不多」：
##   N1  登记覆盖     9 个 surface / 7 个通道，0 个未命中
##   N2  不新增光源   场景 Light3D 数 = 11（改动前基线，设计文档 §5 同一口径）
##   N3  霓虹间隔     相邻起始 ≥8s、≤15s（≥90%），事件数 ≥15（业主指定 8~15s）
##   N4  事件错开     同时进行中的事件 ≤2；任意两次起始间隔 ≥ MIN_EVENT_GAP
##   N5  三灯流水     01→02→03 峰值相位差 = 0.32s ± 0.05s；同时点亮 ≤2 盏
##   N6  电脑频闪     事件内主频 ∈ [7, 16] Hz
##   N7  呼吸只向上   床头灯 factor 全程 ≥1.0（活着的灯，不是坏了的灯）
##   N8  不改颜色     albedo / emission / emission 贴图与运行前逐值相同
##   N9  亮度包络     电脑屏 factor ∈ [0.15, 1.85]
##   N10 关灯联动     开关关掉后，9 个受控材质能量必须全为 0（呼吸不得残留）
##   N11 启动不打架   启动序列期间，受控能量只能落在 {0, 0.16b, b} 三档（动态不得插手）
##   N12 序列后接管   序列结束后动态恢复，且不把能量锁死在 0
##
## 直接加载 `zone_base.tscn`（根节点就是 Art），走真实运行时链路。
##
## 运行：godot --headless --path . --scene res://tests/verification/verify_base_lamp_dynamics.tscn

const ZONE := "res://assets/art/environments/tower_zones/base/runtime/zone_base.tscn"
const NODE_NAME := "基地灯具动态"

const STEP := 1.0 / 120.0
const DURATION := 300.0
const EXPECTED_SLOTS := 9
const EXPECTED_CHANNELS := 7
const EXPECTED_LIGHTS := 11
const MIN_GAP := 2.9
const STATUS_STAGGER := 0.32
const STARTUP_LEVELS := [0.0, 0.16, 1.0]
const SEED := 20261018

var _failures: Array[String] = []
var _art: Node3D
var _dyn: Node3D

var _neon_samples: Array[float] = []
var _lamp_samples: Array[float] = []
var _door_samples: Array[float] = []
var _pc_samples: Array[float] = []
var _status_samples: Array = []
var _material_baseline := {}


func _ready() -> void:
	_build_stage()
	for _i in range(4):
		await get_tree().process_frame
	await _run()
	_finish()


func _build_stage() -> void:
	var packed: PackedScene = load(ZONE)
	_art = packed.instantiate() as Node3D
	add_child(_art)


func _run() -> void:
	_dyn = _art.get_node_or_null(NODE_NAME) as Node3D
	if _dyn == null:
		_check(false, "N0 场景里没有挂 %s 节点" % NODE_NAME)
		return
	_check_n1()
	_check_n2()
	_snapshot_materials()
	_dyn.set_process(false)
	_dyn.set("capture_event_log", true)
	# 必须复位：从 _ready 到 set_process(false) 之间的几帧 _process 已经推进过时钟，
	# 那是真实 delta，而下面的采样索引是按「clock = index × STEP」推的 ——
	# 不复位就整体错位（实测 N6 截到的是事件中段之外，波形根本对不上日志）。
	_dyn.call("reset_for_test", SEED)

	var steps := int(DURATION / STEP)
	for index in range(steps):
		_dyn.call("advance_for_test", STEP)
		_neon_samples.append(float(_dyn.call("get_factor", "neon")))
		_lamp_samples.append(float(_dyn.call("get_factor", "lamp")))
		_door_samples.append(float(_dyn.call("get_factor", "door")))
		_pc_samples.append(float(_dyn.call("get_factor", "loft_pc")))
		_status_samples.append(_dyn.call("get_factors", "status"))
	var log_entries: Array = _dyn.call("get_event_log")
	_check_n3(log_entries)
	_check_n4(log_entries)
	_check_n5()
	_check_n6(log_entries)
	_check_n7()
	_check_n9()
	_check_n8()
	await _check_switch_interplay()


func _check_n1() -> void:
	var slots := int(_dyn.call("get_slot_count"))
	var missing: Array = _dyn.call("get_missing_targets")
	var channels: Array = _dyn.call("get_channel_keys")
	_check(
		slots == EXPECTED_SLOTS and missing.is_empty() and channels.size() == EXPECTED_CHANNELS,
		"N1 登记覆盖 slots=%d/%d channels=%d/%d missing=%s" % [
			slots, EXPECTED_SLOTS, channels.size(), EXPECTED_CHANNELS, str(missing),
		]
	)


func _check_n2() -> void:
	var lights := _art.find_children("*", "Light3D", true, false).size()
	var from_dynamics := _dyn.find_children("*", "Light3D", true, false).size()
	_check(
		lights == EXPECTED_LIGHTS and from_dynamics == 0,
		"N2 光源数 lights=%d（基线 %d）动态新增=%d" % [
			lights, EXPECTED_LIGHTS, from_dynamics,
		]
	)


func _check_n3(log_entries: Array) -> void:
	var starts: Array[float] = []
	for entry in log_entries:
		var item := entry as Dictionary
		if str(item.get("channel", "")) == "neon" and str(item.get("phase", "")) == "start":
			starts.append(float(item.get("at", 0.0)))
	starts.sort()
	var gaps: Array[float] = []
	for index in range(1, starts.size()):
		gaps.append(starts[index] - starts[index - 1])
	gaps.sort()
	var early := 0
	var too_late := 0
	var beyond_band := 0
	for gap in gaps:
		if gap < 8.0 - 0.05:
			early += 1
		if gap > 15.0 + 0.05:
			beyond_band += 1
		if gap > 15.0 + MIN_GAP:
			too_late += 1
	var median := 0.0
	if not gaps.is_empty():
		median = gaps[gaps.size() / 2]
	var late_ratio := float(beyond_band) / maxf(float(gaps.size()), 1.0)
	# 判据：绝不允许「更频繁」（<8s），中位数必须落在 8~15s，
	# 且至多 20% 被「错开闸门」推到 15s 以上（闸门最多顺延一个 MIN_GAP）。
	_check(
		starts.size() >= 15 and early == 0 and too_late == 0
		and median >= 8.0 and median <= 15.0 and late_ratio <= 0.20,
		"N3 霓虹间隔 事件=%d 中位=%.2fs 区间=[%.2f, %.2f] 少于8s=%d 超15s=%.0f%% 超18s=%d" % [
			starts.size(), median, gaps[0] if not gaps.is_empty() else 0.0,
			gaps[gaps.size() - 1] if not gaps.is_empty() else 0.0,
			early, late_ratio * 100.0, too_late,
		]
	)


func _check_n4(log_entries: Array) -> void:
	var open_at := {}
	var windows: Array = []
	for entry in log_entries:
		var item := entry as Dictionary
		var channel := str(item.get("channel", ""))
		var at := float(item.get("at", 0.0))
		if str(item.get("phase", "")) == "start":
			open_at[channel] = at
		elif open_at.has(channel):
			windows.append(Vector2(float(open_at[channel]), at))
			open_at.erase(channel)
	windows.sort_custom(func(a, b): return (a as Vector2).x < (b as Vector2).x)
	var burst_gap := 999.0
	for index in range(1, windows.size()):
		burst_gap = minf(
			burst_gap, (windows[index] as Vector2).x - (windows[index - 1] as Vector2).x
		)
	var peak := 0
	for window in windows:
		var current := window as Vector2
		var active := 0
		for other in windows:
			var candidate := other as Vector2
			if candidate.x <= current.x and candidate.y > current.x:
				active += 1
		peak = maxi(peak, active)
	_check(
		peak <= 2 and burst_gap >= MIN_GAP - 1e-3,
		"N4 事件错开 峰值并发=%d 最小起始间隔=%.2fs 事件数=%d" % [
			peak, burst_gap, windows.size(),
		]
	)


func _check_n5() -> void:
	var peak_time: Array[float] = [-1.0, -1.0, -1.0]
	var peak_value: Array[float] = [-1.0, -1.0, -1.0]
	var limit := mini(int(12.0 / STEP), _status_samples.size())
	for index in range(limit):
		var row: Array = _status_samples[index]
		for slot in range(3):
			var value := float(row[slot])
			if value > peak_value[slot]:
				peak_value[slot] = value
				peak_time[slot] = float(index) * STEP
	var gap01 := peak_time[1] - peak_time[0]
	var gap12 := peak_time[2] - peak_time[1]
	var max_lit := 0
	for row in _status_samples:
		var lit := 0
		for value in (row as Array):
			if float(value) > 1.2:
				lit += 1
		max_lit = maxi(max_lit, lit)
	_check(
		absf(gap01 - STATUS_STAGGER) <= 0.05
		and absf(gap12 - STATUS_STAGGER) <= 0.05
		and max_lit <= 2
		and peak_value[0] > 1.7,
		"N5 三灯流水 峰值间隔=%.3fs/%.3fs（期望 %.2f）同时亮≤%d 峰值=%.2f" % [
			gap01, gap12, STATUS_STAGGER, max_lit, peak_value[0],
		]
	)


func _check_n6(log_entries: Array) -> void:
	var start_at := -1.0
	var end_at := -1.0
	for entry in log_entries:
		var item := entry as Dictionary
		if str(item.get("channel", "")) != "loft_pc":
			continue
		if str(item.get("phase", "")) == "start" and start_at < 0.0:
			start_at = float(item.get("at", 0.0))
		elif str(item.get("phase", "")) == "end" and start_at >= 0.0 and end_at < 0.0:
			end_at = float(item.get("at", 0.0))
	if start_at < 0.0 or end_at <= start_at:
		_check(false, "N6 电脑频闪 未捕获到事件")
		return
	var first := maxi(int(start_at / STEP), 0)
	var last := mini(int(end_at / STEP), _pc_samples.size() - 1)
	# 用「施密特触发」数周期：上穿 1.06、下穿 0.94 才算一次完整翻转。
	# 直接数局部极值会被上下 clamp（0.35 / 1.15）削平出的平台骗到；
	# 直接数零点又会被 1.6Hz 的 CRT 慢波污染。阈值带是唯一稳的判法。
	# 事件内基线 0.78、抖动 ±0.34 ⇒ 施密特阈值取 0.90 / 0.66。
	var state := 0
	var ups: Array[float] = []
	for index in range(first, last + 1):
		var value := _pc_samples[index]
		if state <= 0 and value > 0.90:
			if state == -1 or ups.is_empty():
				ups.append(float(index) * STEP)
			state = 1
		elif state >= 0 and value < 0.66:
			state = -1
	if ups.size() < 2:
		var row := ""
		for index in range(first, last + 1):
			row += "%.2f," % _pc_samples[index]
		print("  DEBUG pc_event %.3f->%.3f first=%d last=%d realsize=%d" % [
			start_at, end_at, first, last, _pc_samples.size(),
		])
		print("  DEBUG wave ", row)
		_check(false, "N6 电脑频闪 事件内完整周期不足（上穿次数=%d）" % ups.size())
		return
	var duration := ups[ups.size() - 1] - ups[0]
	var frequency := float(ups.size() - 1) / maxf(duration, 0.001)
	_check(
		frequency >= 7.0 and frequency <= 16.0,
		"N6 电脑频闪 主频=%.1fHz（上穿 %d 次 / %.2fs）" % [
			frequency, ups.size(), duration,
		]
	)


func _check_n7() -> void:
	var lamp_min := 9.0
	var lamp_max := 0.0
	var door_min := 9.0
	var door_max := 0.0
	for index in range(_lamp_samples.size()):
		lamp_min = minf(lamp_min, _lamp_samples[index])
		lamp_max = maxf(lamp_max, _lamp_samples[index])
		door_min = minf(door_min, _door_samples[index])
		door_max = maxf(door_max, _door_samples[index])
	# 台灯：只向下沉（灯罩已过曝，向上无变化）；门警示灯：双向慢呼吸。
	_check(
		lamp_min >= 0.855 and lamp_max <= 1.001
		and door_min >= 0.82 and door_max <= 1.18,
		"N7 呼吸 床头灯[%.3f, %.3f]（只向下沉） 门警示灯[%.3f, %.3f]（双向）" % [
			lamp_min, lamp_max, door_min, door_max,
		]
	)


## N9：屏幕的常态必须是 0（= 改动前的外观，不发光），事件内落在 [0.30, 1.15]。
## 这条是防止「为了看得见而把屏幕常态点亮」—— 那是在改美术，不是加动态。
func _check_n9() -> void:
	var low := 9.0
	var high := 0.0
	var zero_ratio := 0.0
	var zeros := 0
	for index in range(_pc_samples.size()):
		var value := _pc_samples[index]
		low = minf(low, value)
		high = maxf(high, value)
		if value <= 1e-6:
			zeros += 1
	zero_ratio = float(zeros) / float(maxi(_pc_samples.size(), 1))
	_check(
		low <= 1e-6 and high <= 1.85 + 1e-6 and high >= 0.6 and zero_ratio >= 0.75,
		"N9 屏幕包络 [%.3f, %.3f] 常态静默占比=%.0f percent（应 >= 75 percent）" % [
			low, high, zero_ratio * 100.0,
		]
	)


func _check_n8() -> void:
	var changed := 0
	var checked := 0
	for node in _art.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_surface_override_material(surface) as BaseMaterial3D
			if material == null:
				continue
			var key := material.get_instance_id()
			if not _material_baseline.has(key):
				continue
			checked += 1
			var baseline: Dictionary = _material_baseline[key]
			if material.albedo_color != baseline.get("albedo"):
				changed += 1
			if material.emission_texture != baseline.get("emission_texture"):
				changed += 1
			if material.emission != baseline.get("emission"):
				changed += 1
	_check(changed == 0, "N8 不改颜色 检查材质=%d 颜色漂移=%d" % [checked, changed])


## N10~N12：动态必须让位给「墙面开关」与「4.2s 启动序列」，然后再接管。
func _check_switch_interplay() -> void:
	var base_energies: Array = _dyn.call("get_managed_base_energies")
	# N10 关灯：受管材质 energy 归 0；屏幕面（self_owned）emission 关掉。
	_art.call("set_presentation_lighting_enabled", false)
	for _i in range(12):
		_dyn.call("_process", 1.0 / 60.0)
	var off_energies: Array = _dyn.call("get_managed_energies")
	var residual := 0
	for value in off_energies:
		if absf(float(value)) > 1e-5:
			residual += 1
	var screen_lit := bool(_dyn.call("are_self_owned_lit"))
	_check(
		residual == 0 and not screen_lit,
		"N10 关灯联动 受管材质=%d 仍有能量=%d 屏幕仍发亮=%s" % [
			off_energies.size(), residual, str(screen_lit),
		]
	)

	# N11 启动序列：动态不得插手
	_art.call("play_turn_on_sequence", 0.9)
	var samples: Array = []
	var frames := 0
	while bool(_art.call("get_presentation_snapshot").get("presentation_starting", false)):
		await get_tree().process_frame
		_dyn.call("_process", 1.0 / 60.0)
		# 序列可能在「这一帧」里跑完；那一帧动态已经开始接管，样本不能算进启动档。
		if not bool(_art.call("get_presentation_snapshot").get("presentation_starting", false)):
			break
		samples.append(_dyn.call("get_managed_energies"))
		frames += 1
		if frames > 300:
			break
	var off_level := 0
	for sample in samples:
		var row: Array = sample
		for index in range(row.size()):
			var value := float(row[index])
			var base := float(base_energies[index])
			var matched := false
			for level in STARTUP_LEVELS:
				if absf(value - base * float(level)) <= maxf(0.002, base * 0.001):
					matched = true
					break
			if not matched:
				off_level += 1
	_check(
		frames > 0 and off_level == 0,
		"N11 启动不打架 采样帧=%d 越出启动三档的次数=%d" % [frames, off_level]
	)

	# N12 序列结束后动态恢复
	for _i in range(20):
		await get_tree().process_frame
		_dyn.call("_process", 1.0 / 60.0)
	var resumed: Array = _dyn.call("get_managed_energies")
	var alive := 0
	var moving := 0
	for index in range(resumed.size()):
		var value := float(resumed[index])
		if value > 1e-4:
			alive += 1
		if absf(value - float(base_energies[index])) > 1e-3:
			moving += 1
	_check(
		alive == resumed.size() and moving >= 3
		and bool(_dyn.call("are_self_owned_lit")),
		"N12 序列后接管 恢复亮起=%d/%d 正在动态=%d 屏幕恢复=%s" % [
			alive, resumed.size(), moving, str(_dyn.call("are_self_owned_lit")),
		]
	)


func _snapshot_materials() -> void:
	for node in _art.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_surface_override_material(surface) as BaseMaterial3D
			if material == null:
				continue
			_material_baseline[material.get_instance_id()] = {
				"albedo": material.albedo_color,
				"emission": material.emission,
				"emission_texture": material.emission_texture,
			}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS ", message)
	else:
		printerr("  FAIL ", message)
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ACCEPT base_lamp_dynamics")
		get_tree().quit(0)
	else:
		printerr("REJECT base_lamp_dynamics failures=%d" % _failures.size())
		get_tree().quit(1)
